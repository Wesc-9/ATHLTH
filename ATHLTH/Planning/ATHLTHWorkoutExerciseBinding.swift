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

    /// Only migrate the reviewed rowing identity; leave all other exercise
    /// IDs, user-created movements and workout prescriptions untouched.
    private static func legacyRowing(_ block: WorkoutTemplateBlock) -> Bool {
        guard block.kind == .exercise || block.exerciseID != nil || block.exerciseSlug != nil else { return false }
        if block.exerciseID == nil && block.exerciseSlug == nil,
           let snapshot = block.exerciseSnapshot, !snapshot.instructions.isEmpty {
            return false
        }
        return ATHLTHExerciseReferenceResolver.isLegacyRowingReference(
            id: block.exerciseID, slug: block.exerciseSlug, name: block.title
        )
    }

    private static func legacyRowing(_ exercise: PlannedExercise) -> Bool {
        guard exercise.exerciseID != nil || exercise.embeddedExercise.instructions.isEmpty else { return false }
        return ATHLTHExerciseReferenceResolver.isLegacyRowingReference(
            id: exercise.exerciseID, slug: nil, name: exercise.embeddedExercise.name
        )
    }

    static func needsRowingMigration(_ workout: PlannedSession) -> Bool {
        (workout.workoutBlocks ?? []).contains(where: { legacyRowing($0) }) ||
            workout.exercises.contains(where: { legacyRowing($0) })
    }

    static func needsRowingMigration(_ plan: TrainingPlan) -> Bool {
        plan.weeks.contains { week in
            week.days.contains { day in day.sessions.contains(where: { needsRowingMigration($0) }) }
        }
    }

    private static func replaceRowing(_ block: inout WorkoutTemplateBlock, with rower: ExerciseLibraryEntry) {
        if ["row run", "rowing machine run", "romaskin loping"].contains(ATHLTHExerciseReferenceResolver.key(block.title)) {
            block.title = ATHLTHLocalization.choose(english: "Rowing Machine / Run", norwegian: "Romaskin / løping")
        } else {
            block.title = ATHLTHLocalization.choose(english: "Rowing Machine", norwegian: "Romaskin")
        }
        block.exerciseID = rower.id
        block.exerciseSlug = rower.sourceIdentifier
        block.exerciseSnapshot = rower.exercise.snapshot
    }

    static func migrateRowing(_ source: PlannedSession, to rower: ExerciseLibraryEntry) -> PlannedSession {
        guard needsRowingMigration(source) else { return source }
        var copy = source
        if var blocks = copy.workoutBlocks {
            for i in blocks.indices where legacyRowing(blocks[i]) {
                replaceRowing(&blocks[i], with: rower)
            }
            copy.workoutBlocks = blocks
        }
        for i in copy.exercises.indices where legacyRowing(copy.exercises[i]) {
            copy.exercises[i].exerciseID = rower.id
            copy.exercises[i].embeddedExercise = rower.exercise.snapshot
        }
        return copy
    }

    static func migrateRowing(_ source: TrainingPlan, to rower: ExerciseLibraryEntry) -> TrainingPlan {
        guard needsRowingMigration(source) else { return source }
        var copy = source
        for w in copy.weeks.indices {
            for d in copy.weeks[w].days.indices {
                copy.weeks[w].days[d].sessions = copy.weeks[w].days[d].sessions.map {
                    migrateRowing($0, to: rower)
                }
            }
        }
        return copy
    }

    private static func reviewedTarget(_ block: WorkoutTemplateBlock) -> String? {
        guard block.kind == .exercise || block.exerciseID != nil || block.exerciseSlug != nil else { return nil }
        let name: String?
        if let snapshot = block.exerciseSnapshot {
            name = snapshot.instructions.isEmpty && snapshot.imageURL == nil && snapshot.videoURL == nil
                ? snapshot.name : nil
        } else {
            name = block.title
        }
        return ATHLTHExerciseReferenceResolver.reviewedReplacementSlug(
            id: block.exerciseID, slug: block.exerciseSlug, legacyName: name
        )
    }

    private static func reviewedTarget(_ exercise: PlannedExercise) -> String? {
        let snapshot = exercise.embeddedExercise
        let name = snapshot.instructions.isEmpty && snapshot.imageURL == nil && snapshot.videoURL == nil
            ? snapshot.name : nil
        return ATHLTHExerciseReferenceResolver.reviewedReplacementSlug(
            id: exercise.exerciseID, slug: nil, legacyName: name
        )
    }

    /// Build once per batch. Migration preserves every prescription and all
    /// private/custom IDs; missing RepDB targets leave the old record intact.
    struct DuplicateIndex {
        private let repDB: [String: ExerciseLibraryEntry]

        init(library: [ExerciseLibraryEntry]) {
            let grouped = Dictionary(grouping: library.filter {
                $0.source == .repDB && $0.sourceIdentifier != nil
            }, by: { $0.sourceIdentifier ?? "" })
            repDB = grouped.compactMapValues { entries in
                entries.count == 1 ? entries[0] : nil
            }
        }

        private func replacement(_ target: String?) -> ExerciseLibraryEntry? {
            guard let target else { return nil }
            return repDB[target]
        }

        func migrate(_ source: PlannedSession) -> PlannedSession {
            var copy = source
            if var blocks = copy.workoutBlocks {
                for i in blocks.indices {
                    guard let match = replacement(ATHLTHWorkoutExerciseBinding.reviewedTarget(blocks[i])) else { continue }
                    if match.sourceIdentifier == "rowing-machine" {
                        ATHLTHWorkoutExerciseBinding.replaceRowing(&blocks[i], with: match)
                    } else {
                        blocks[i].exerciseID = match.id
                        blocks[i].exerciseSlug = match.sourceIdentifier
                        blocks[i].exerciseSnapshot = match.exercise.snapshot
                    }
                }
                copy.workoutBlocks = blocks
            }
            for i in copy.exercises.indices {
                guard let match = replacement(ATHLTHWorkoutExerciseBinding.reviewedTarget(copy.exercises[i])) else { continue }
                copy.exercises[i].exerciseID = match.id
                copy.exercises[i].embeddedExercise = match.exercise.snapshot
            }
            if let rower = repDB["rowing-machine"] {
                copy = ATHLTHWorkoutExerciseBinding.migrateRowing(copy, to: rower)
            }
            return copy
        }

        func migrate(_ source: TrainingPlan) -> TrainingPlan {
            var copy = source
            for w in copy.weeks.indices {
                for d in copy.weeks[w].days.indices {
                    copy.weeks[w].days[d].sessions = copy.weeks[w].days[d].sessions.map { migrate($0) }
                }
            }
            return copy
        }
    }

    static func needsDuplicateMigration(_ workout: PlannedSession) -> Bool {
        needsRowingMigration(workout) ||
            (workout.workoutBlocks ?? []).contains {
                reviewedTarget($0) != nil
            } || workout.exercises.contains {
                reviewedTarget($0) != nil
            }
    }

    static func needsDuplicateMigration(_ plan: TrainingPlan) -> Bool {
        plan.weeks.contains { week in
            week.days.contains { day in day.sessions.contains(where: { needsDuplicateMigration($0) }) }
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
            &workout, library: library, cache: &cache, misses: &misses,
            duplicateIndex: DuplicateIndex(library: library)
        )
    }

    private static func bind(
        _ workout: inout PlannedSession,
        library: [ExerciseLibraryEntry],
        cache: inout [LookupKey: ExerciseLibraryEntry],
        misses: inout Set<LookupKey>,
        duplicateIndex: DuplicateIndex
    ) -> Report {
        var report = Report()
        if needsDuplicateMigration(workout) {
            workout = duplicateIndex.migrate(workout)
        }

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
        let duplicateIndex = DuplicateIndex(library: library)
        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                for sessionIndex in plan.weeks[weekIndex].days[dayIndex].sessions.indices {
                    let current = bind(
                        &plan.weeks[weekIndex].days[dayIndex].sessions[sessionIndex],
                        library: library, cache: &cache, misses: &misses,
                        duplicateIndex: duplicateIndex
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
