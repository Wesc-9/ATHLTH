import Foundation

/// The exercise library owns movement identity, technique, artwork, last
/// completed workout and progression. A workout only owns *prescriptions*:
/// sets, reps, rest, RIR, weight, group order and phase.
///
/// Binding runs when importing/accepting a plan. It never silently invents a
/// library exercise or drops an unresolved legacy/custom movement.
enum ATHLTHWorkoutExerciseBinding {
    struct Report: Equatable {
        var linked: Int = 0
        var unresolved: [String] = []
        var isReady: Bool { unresolved.isEmpty }
    }

    /// Repeated week prescriptions share the same movement identity even
    /// when weights, repetitions and rest differ. Key by authoritative source
    /// fields, never by the transient step sequence or a fuzzy exercise name.
    private struct LookupKey: Hashable {
        let id: UUID?
        let slug: String?
        let title: String
        let snapshot: ExerciseSnapshot?

        init(_ block: WorkoutTemplateBlock) {
            id = block.exerciseID
            slug = block.exerciseSlug
            title = block.title
            snapshot = block.exerciseSnapshot
        }
    }

    @discardableResult
    static func bind(
        _ workout: inout PlannedSession,
        library: [ExerciseLibraryEntry]
    ) -> Report {
        var cache: [LookupKey: ExerciseLibraryEntry] = [:]
        var misses = Set<LookupKey>()
        return bind(
            &workout, library: library, cache: &cache, misses: &misses
        )
    }

    private static func bind(
        _ workout: inout PlannedSession,
        library: [ExerciseLibraryEntry],
        cache: inout [LookupKey: ExerciseLibraryEntry],
        misses: inout Set<LookupKey>
    ) -> Report {
        var report = Report()

        if var blocks = workout.workoutBlocks {
            // Adapted running/cardio exercises retain their library ID or slug.
            // Unreferenced timing/route/interval blocks are never guessed by name.
            for i in blocks.indices where blocks[i].kind == .exercise ||
                blocks[i].exerciseID != nil || blocks[i].exerciseSlug != nil {
                if isLegacyTimedPhaseInstruction(blocks[i]),
                   ATHLTHExerciseReferenceResolver.resolve(blocks[i], in: library) == nil {
                    // A generic warm-up/cool-down instruction is not a single
                    // strength movement. Keep its actual name, time, phase and
                    // notes as a timed instruction, like current curated recipes.
                    blocks[i].kind = .note
                    blocks[i].exerciseSlug = nil
                    continue
                }
                let reference = LookupKey(blocks[i])
                let match: ExerciseLibraryEntry?
                if let cached = cache[reference] {
                    match = cached
                } else if misses.contains(reference) {
                    match = nil
                } else {
                    let resolved = ATHLTHExerciseReferenceResolver.resolve(
                        blocks[i], in: library
                    )
                    if let resolved {
                        cache[reference] = resolved
                    } else {
                        misses.insert(reference)
                    }
                    match = resolved
                }
                guard let match else {
                    report.unresolved.append(blocks[i].title)
                    continue
                }
                blocks[i].exerciseID = match.id
                if let identifier = match.sourceIdentifier {
                    blocks[i].exerciseSlug = identifier
                }
                // Old catalog snapshots sometimes contain only a translated
                // title. Replace just the instructional reference, never the
                // workout prescription. This is local/account-scoped data.
                if blocks[i].exerciseSnapshot == nil ||
                   blocks[i].exerciseSnapshot?.instructions.isEmpty == true {
                    blocks[i].exerciseSnapshot = match.exercise.snapshot
                }
                report.linked += 1
            }
            workout.workoutBlocks = blocks
        }

        for i in workout.exercises.indices {
            let exercise = workout.exercises[i]
            var match: ExerciseLibraryEntry?
            if let id = exercise.exerciseID {
                match = library.first(where: { $0.id == id }) ??
                    library.first(where: {
                        $0.source == .custom &&
                        $0.exercise.sharedSourceExerciseID == id
                    })
            } else if exercise.embeddedExercise.instructions.isEmpty {
                // Older plans store a separate PlannedExercise instead of a
                // canonical block. Resolve using the same exact/curated rules
                // as the workout timeline, including reviewed Norwegian names.
                match = ATHLTHExerciseReferenceResolver.resolvePublicName(
                    exercise.embeddedExercise.name, in: library
                )
            }
            guard let match else {
                report.unresolved.append(exercise.embeddedExercise.name)
                continue
            }
            workout.exercises[i].exerciseID = match.id
            if exercise.embeddedExercise.instructions.isEmpty {
                workout.exercises[i].embeddedExercise = match.exercise.snapshot
            }
            report.linked += 1
        }

        // Report each missing identity once. Do not alter its text, order or
        // targets; the editor can ask the athlete to select a library item.
        report.unresolved = Array(Set(report.unresolved)).sorted()
        return report
    }

    static func isLegacyTimedPhaseInstruction(_ block: WorkoutTemplateBlock) -> Bool {
        guard block.kind == .exercise, block.exerciseID == nil,
              block.exerciseSnapshot == nil,
              block.groupID == nil, block.executionGroupID == nil,
              (block.setCount ?? 1) == 1,
              block.repetitions == nil, block.targetWeightKilograms == nil,
              let seconds = block.durationSeconds, seconds.isFinite, seconds > 0
        else { return false }
        let name = ATHLTHExerciseReferenceResolver.key(block.title)
        if let slug = block.exerciseSlug,
           ATHLTHExerciseReferenceResolver.key(slug) != name { return false }
        switch block.resolvedPhase {
        case .warmup: return ["dynamic warm up", "dynamic warmup", "dynamisk oppvarming"].contains(name)
        case .cooldown: return ["cool down", "cooldown", "nedtrapping", "cool down stretching"].contains(name)
        default: return false
        }
    }

    static func bind(
        _ plan: inout TrainingPlan,
        library: [ExerciseLibraryEntry]
    ) -> Report {
        var report = Report()
        // One lookup per distinct movement across the entire plan, rather
        // than repeating full-library scans for every week's prescription.
        var cache: [LookupKey: ExerciseLibraryEntry] = [:]
        var misses = Set<LookupKey>()
        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                for sessionIndex in plan.weeks[weekIndex].days[dayIndex].sessions.indices {
                    let current = bind(
                        &plan.weeks[weekIndex].days[dayIndex].sessions[sessionIndex],
                        library: library, cache: &cache, misses: &misses
                    )
                    report.linked += current.linked
                    report.unresolved.append(contentsOf: current.unresolved)
                }
            }
        }
        report.unresolved = Array(Set(report.unresolved)).sorted()
        return report
    }
}
