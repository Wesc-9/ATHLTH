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

    @discardableResult
    static func bind(
        _ workout: inout PlannedSession,
        library: [ExerciseLibraryEntry]
    ) -> Report {
        var report = Report()

        if var blocks = workout.workoutBlocks {
            for i in blocks.indices where blocks[i].kind == .exercise {
                guard let match = ATHLTHExerciseReferenceResolver.resolve(
                    blocks[i], in: library
                ) else {
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
                // An AI/legacy textual suggestion has no authored technique.
                // Only exact, curated public catalog names can be resolved.
                let name = exercise.embeddedExercise.name
                let key = ATHLTHExerciseReferenceResolver.key(name)
                let reviewedIdentifier =
                    ATHLTHExerciseReferenceResolver.exerciseSourceIdentifier(for: name)
                let reviewed = library.filter {
                    guard let reviewedIdentifier else { return false }
                    let source: ExerciseLibrarySource =
                        reviewedIdentifier.hasPrefix("athlth-native-")
                        ? .athlthCatalog : .repDB
                    return $0.source == source &&
                        $0.sourceIdentifier == reviewedIdentifier
                }
                let exact = library.filter {
                    ($0.source == .athlthCatalog || $0.source == .repDB) &&
                    ATHLTHExerciseReferenceResolver.key($0.canonicalName) == key
                }
                match = reviewed.count == 1 ? reviewed[0] :
                    exact.count == 1 ? exact[0] : nil
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

    static func bind(
        _ plan: inout TrainingPlan,
        library: [ExerciseLibraryEntry]
    ) -> Report {
        var report = Report()
        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                for sessionIndex in plan.weeks[weekIndex].days[dayIndex].sessions.indices {
                    let current = bind(
                        &plan.weeks[weekIndex].days[dayIndex].sessions[sessionIndex],
                        library: library
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
