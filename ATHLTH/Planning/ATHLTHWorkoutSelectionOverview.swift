import Foundation

/// Read-only summary for the workout selection sheet. Counts and estimates are
/// derived from the same expanded recipe that the universal player executes.
/// A preview must never insert recovery blocks or mutate the source workout.
enum ATHLTHWorkoutSelectionOverview {
    struct Metrics {
        let exerciseCount: Int
        let setCount: Int
        let pauseCount: Int
        let totalSeconds: TimeInterval?
        let restSeconds: TimeInterval?
        let activeSeconds: TimeInterval?
        let primaryMuscles: [String]
        let equipment: [String]
        let executedStepCount: Int
        let hasBetweenExerciseRest: Bool
    }

    struct Row: Identifiable {
        let id: Int
        let steps: [WorkoutTemplateBlock]

        var first: WorkoutTemplateBlock { steps[0] }
        var isExercise: Bool { first.kind == .exercise }
        var isPause: Bool { first.isRestOrActiveRecovery }
        var sets: Int { steps.filter { $0.kind == .exercise }.count }
        var betweenSetPauses: Int {
            steps.filter { ATHLTHWorkoutSelectionOverview.isBetweenSetPause($0) }.count
        }
        var title: String {
            if first.kind == .rest {
                return ATHLTHLocalization.choose(
                    english: "Pause", norwegian: "Pause"
                )
            }
            return ATHLTHWorkoutSelectionOverview.baseExerciseTitle(first)
        }
        var subtitle: String {
            if first.kind == .rest {
                let type = ATHLTHWorkoutSelectionOverview.pauseType(first)
                let duration = first.durationSeconds.flatMap {
                    $0.isFinite && $0 > 0 ?
                        ATHLTHWorkoutDurationEstimator.conciseDuration($0) : nil
                }
                return [type, duration].compactMap { $0 }.joined(separator: " · ")
            }
            if first.isActiveRecovery {
                return [ATHLTHLocalization.choose(
                    english: "Active recovery", norwegian: "Aktiv pause"
                ), first.targetText].compactMap { $0 }.joined(separator: " · ")
            }
            if isExercise && sets > 1 {
                let repValues = Set(steps.compactMap { step in
                    step.kind == .exercise ? step.repetitions : nil
                })
                if repValues.count == 1, let reps = repValues.first {
                    return first.resolvedPhase.title + " · \(reps) reps"
                }
                return first.resolvedPhase.title + " · " +
                    ATHLTHLocalization.choose(
                        english: "Individual set targets",
                        norwegian: "Individuelle settmål"
                    )
            }
            return [first.resolvedPhase.title, first.targetText]
                .compactMap { $0 }.joined(separator: " · ")
        }

        var estimatedSeconds: TimeInterval? {
            // AMRAP and EMOM have ONE shared group clock. Showing that
            // entire clock beside every station would inflate row estimates.
            if first.executionGroupKind?.usesGroupClock == true { return nil }
            return ATHLTHWorkoutDurationEstimator.previewSeconds(
                for: steps,
                defaultActivity: first.cardioActivity == .walking
                    ? .walking : .running
            )
        }

        var betweenSetRestSeconds: TimeInterval? {
            let rests = steps.filter {
                ATHLTHWorkoutSelectionOverview.isBetweenSetPause($0)
            }
            guard rests.allSatisfy({
                $0.durationSeconds != nil &&
                $0.durationSeconds!.isFinite &&
                $0.durationSeconds! >= 0
            }) else { return nil }
            return rests.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        }
    }

    static func metrics(
        for blocks: [WorkoutTemplateBlock],
        defaultActivity: WorkoutCardioActivity = .running
    ) -> Metrics {
        let executed = blocks.expandedForExecution()
        guard executed.count <= 1_000 else {
            return Metrics(
                exerciseCount: 0, setCount: 0, pauseCount: 0,
                totalSeconds: nil, restSeconds: nil, activeSeconds: nil,
                primaryMuscles: [], equipment: [],
                executedStepCount: 0, hasBetweenExerciseRest: false
            )
        }

        let strength = executed.filter { $0.kind == .exercise }
        let identifiers = Set(strength.map { block in
            if let id = block.exerciseID ?? block.exerciseSnapshot?.libraryExerciseID {
                return "id:" + id.uuidString
            }
            if let slug = block.exerciseSlug, !slug.isEmpty {
                return "slug:" + slug
            }
            return "name:" + baseExerciseTitle(block)
                .folding(options: [.diacriticInsensitive, .caseInsensitive],
                         locale: Locale(identifier: "nb_NO")).lowercased()
        })
        let rests = executed.filter(\.isRestOrActiveRecovery)
        // Active recovery is a counted pause/segment but remains physical
        // exercise; only passive rest is subtracted from active minutes.
        let passiveRest = rests.filter { $0.kind == .rest }
        let knownRest = passiveRest.allSatisfy {
            guard let time = $0.durationSeconds else { return false }
            return time.isFinite && time >= 0
        }
        let restSeconds: TimeInterval? = knownRest
            ? passiveRest.reduce(0) { $0 + ($1.durationSeconds ?? 0) } : nil
        let totalSeconds = ATHLTHWorkoutDurationEstimator.previewSeconds(
            for: blocks, defaultActivity: defaultActivity
        )
        let activeSeconds: TimeInterval?
        if let totalSeconds, let restSeconds {
            activeSeconds = max(0, totalSeconds - restSeconds)
        } else {
            activeSeconds = nil
        }

        var muscles: [String] = []
        var equipment: [String] = []
        var seenMuscles = Set<String>()
        var seenEquipment = Set<String>()
        for block in strength {
            guard let snapshot = block.exerciseSnapshot else { continue }
            for muscle in snapshot.primaryMuscles {
                let key = muscle.lowercased()
                if seenMuscles.insert(key).inserted {
                    muscles.append(muscle)
                }
            }
            for item in snapshot.equipment {
                let key = item.lowercased()
                if seenEquipment.insert(key).inserted {
                    equipment.append(item)
                }
            }
        }

        return Metrics(
            exerciseCount: identifiers.count,
            setCount: strength.count,
            pauseCount: rests.count,
            totalSeconds: totalSeconds,
            restSeconds: restSeconds,
            activeSeconds: activeSeconds,
            primaryMuscles: muscles,
            equipment: equipment,
            executedStepCount: executed.count,
            hasBetweenExerciseRest: rests.contains {
                let type = $0.title.lowercased()
                return type.contains("between exercises") ||
                    type.contains("mellom øvelser")
            }
        )
    }

    /// Collapse only explicit successive sets of the SAME strength exercise.
    /// An intervening generic/transition rest, changed phase, circuit, EMOM,
    /// or unrelated exercise breaks the group. The actual recipe is untouched.
    static func rows(for blocks: [WorkoutTemplateBlock]) -> [Row] {
        let executed = blocks.expandedForExecution()
        guard executed.count <= 1_000 else { return [] }
        var result: [Row] = []
        var index = 0
        while index < executed.count {
            let first = executed[index]
            guard first.kind == .exercise,
                  first.executionGroupID == nil,
                  first.groupID == nil else {
                result.append(Row(id: index, steps: [first]))
                index += 1
                continue
            }

            var members: [WorkoutTemplateBlock] = [first]
            var cursor = index + 1
            while cursor < executed.count {
                if isBetweenSetPause(executed[cursor]),
                   cursor + 1 < executed.count,
                   sameExercise(first, executed[cursor + 1]) {
                    members.append(executed[cursor])
                    members.append(executed[cursor + 1])
                    cursor += 2
                    continue
                }
                if sameExercise(first, executed[cursor]),
                   isConsecutiveNumberedSet(
                       members.last(where: { $0.kind == .exercise }) ?? first,
                       executed[cursor]
                   ) {
                    members.append(executed[cursor])
                    cursor += 1
                    continue
                }
                break
            }

            result.append(Row(id: index, steps: members))
            index = cursor
        }
        return result
    }

    static func isBetweenSetPause(_ block: WorkoutTemplateBlock) -> Bool {
        guard block.kind == .rest,
              block.executionGroupID == nil,
              block.groupID == nil else { return false }
        let title = block.title.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title == "between sets" || title == "mellom sett"
    }

    static func baseExerciseTitle(_ block: WorkoutTemplateBlock) -> String {
        guard block.kind == .exercise else { return block.title }
        let pieces = block.title.components(separatedBy: " · ")
        guard pieces.count > 1,
              let suffix = pieces.last,
              numberedSet(suffix) != nil else { return block.title }
        return pieces.dropLast().joined(separator: " · ")
    }

    private static func numberedSet(_ suffix: String) -> (index: Int, total: Int)? {
        let values = suffix.split(separator: "/")
        guard values.count == 2,
              let index = Int(values[0]), let total = Int(values[1]),
              (1...20).contains(index), (1...20).contains(total),
              index <= total else { return nil }
        return (index, total)
    }

    private static func isConsecutiveNumberedSet(
        _ lhs: WorkoutTemplateBlock,
        _ rhs: WorkoutTemplateBlock
    ) -> Bool {
        let a = lhs.title.components(separatedBy: " · ").last
            .flatMap(numberedSet)
        let b = rhs.title.components(separatedBy: " · ").last
            .flatMap(numberedSet)
        guard let a, let b else { return false }
        return a.total == b.total && b.index == a.index + 1
    }

    private static func sameExercise(
        _ lhs: WorkoutTemplateBlock,
        _ rhs: WorkoutTemplateBlock
    ) -> Bool {
        guard rhs.kind == .exercise,
              rhs.executionGroupID == nil, rhs.groupID == nil,
              lhs.resolvedPhase == rhs.resolvedPhase,
              lhs.sourceSupersetGroupIndex == rhs.sourceSupersetGroupIndex
        else { return false }
        if let firstID = lhs.exerciseID ?? lhs.exerciseSnapshot?.libraryExerciseID,
           let secondID = rhs.exerciseID ?? rhs.exerciseSnapshot?.libraryExerciseID {
            return firstID == secondID
        }
        return lhs.exerciseSlug == rhs.exerciseSlug &&
            baseExerciseTitle(lhs) == baseExerciseTitle(rhs)
    }

    private static func pauseType(_ block: WorkoutTemplateBlock) -> String {
        let title = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if isBetweenSetPause(block) {
            return ATHLTHLocalization.choose(
                english: "Between sets", norwegian: "Mellom sett"
            )
        }
        if ["pause", "rest", "recovery"].contains(title.lowercased()) {
            return ATHLTHLocalization.choose(
                english: "Recovery", norwegian: "Hvile"
            )
        }
        return title
    }
}
