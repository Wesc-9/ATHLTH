import Foundation

/// A read-only description of unfinished strength work. No new plan or
/// recorded workout is created until the athlete explicitly confirms it.
struct StrengthWorkoutRemainder {
    let sourceWorkoutID: UUID
    let sourceTitle: String
    let exercises: [Exercise]

    struct Exercise {
        let sourceExerciseID: UUID
        let snapshot: ExerciseSnapshot
        let supersetGroupID: UUID?
        let sets: [Set]
    }

    struct Set {
        let sourceSetID: UUID
        let targetKind: StrengthExerciseTargetKind
        let plannedReps: Int?
        let recordedPartialReps: Int?
        let plannedDurationSeconds: Int?
        let recordedPartialDurationSeconds: Int?
        let loadKind: StrengthExerciseLoadKind
        let plannedWeightKilograms: Double?
        let plannedResistanceLevel: Int?
        let restSeconds: Int?

        /// Always default to a new complete effort. A partial target can be
        /// requested, but must never be joined to the previous result.
        func proposedReps(onlyRemainder: Bool = false) -> Int? {
            guard let plannedReps else { return nil }
            guard onlyRemainder, let recordedPartialReps,
                  recordedPartialReps > 0 else { return plannedReps }
            return max(plannedReps - recordedPartialReps, 0)
        }

        func proposedDurationSeconds(onlyRemainder: Bool = false) -> Int? {
            guard let plannedDurationSeconds else { return nil }
            guard onlyRemainder, let recordedPartialDurationSeconds,
                  recordedPartialDurationSeconds > 0 else {
                return plannedDurationSeconds
            }
            return max(plannedDurationSeconds - recordedPartialDurationSeconds, 0)
        }

        /// A set with nothing remaining is not a useful follow-up target.
        /// It may still need a corrected completion status in its original log.
        var hasUnfinishedTarget: Bool {
            guard plannedReps != nil || plannedDurationSeconds != nil else {
                return true // Open-ended sets require the athlete to decide.
            }
            return (plannedReps.map { ($0 - (recordedPartialReps ?? 0)) > 0 } ?? false) ||
                (plannedDurationSeconds.map {
                    ($0 - (recordedPartialDurationSeconds ?? 0)) > 0
                } ?? false)
        }
    }

    init(workout: StrengthWorkoutLog) {
        sourceWorkoutID = workout.id
        sourceTitle = workout.title
        exercises = workout.exercises.compactMap { exercise in
            let remaining = exercise.sets.compactMap { set -> Set? in
                guard !set.isCompleted else { return nil }

                let proposal = Set(
                    sourceSetID: set.id,
                    targetKind: set.resolvedTargetKind,
                    plannedReps: set.plannedReps,
                    recordedPartialReps: set.resolvedCompletedReps,
                    plannedDurationSeconds: set.plannedDurationSeconds,
                    recordedPartialDurationSeconds:
                        set.resolvedCompletedDurationSeconds,
                    loadKind: set.resolvedLoadKind,
                    plannedWeightKilograms: set.plannedWeightKilograms,
                    plannedResistanceLevel: set.plannedResistanceLevel,
                    restSeconds: set.restSeconds
                )
                return proposal.hasUnfinishedTarget ? proposal : nil
            }
            guard !remaining.isEmpty else { return nil }
            return Exercise(
                sourceExerciseID: exercise.id,
                snapshot: exercise.exercise,
                supersetGroupID: exercise.groupID,
                sets: remaining
            )
        }
    }

    var setCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var isEmpty: Bool { exercises.isEmpty }

    /// Build a new standalone planned session without mutating either source
    /// or calendar. The caller must verify the workout has ended and obtain
    /// explicit user confirmation before saving.
    func makeFollowUp(
        scheduledStart: Date,
        selectedSetIDs: Swift.Set<UUID>? = nil,
        onlyRemainderForSetIDs: Swift.Set<UUID> = []
    ) -> PlannedSession? {
        var planned: [PlannedExercise] = []
        var linkedSetIDs: [UUID] = []

        for exercise in exercises {
            for set in exercise.sets {
                if let selectedSetIDs,
                   !selectedSetIDs.contains(set.sourceSetID) {
                    continue
                }
                let useRemainder = onlyRemainderForSetIDs
                    .contains(set.sourceSetID)
                let reps = set.targetKind == .reps
                    ? set.proposedReps(onlyRemainder: useRemainder)
                    : nil
                let seconds = set.targetKind == .time
                    ? set.proposedDurationSeconds(onlyRemainder: useRemainder)
                    : nil

                if set.targetKind == .reps &&
                    (reps ?? 0) <= 0 { return nil }
                // Timed strength targets currently require >= 15 seconds.
                // Reject an invalid short remainder rather than silently
                // converting 5 seconds into an unexpected 15-second target.
                if set.targetKind == .time &&
                    (seconds ?? 0) < 15 { return nil }

                let targetWeight = set.loadKind == .weightKilograms
                    ? set.plannedWeightKilograms : nil
                let resistance = set.loadKind == .resistanceLevel
                    ? set.plannedResistanceLevel : nil

                let item = PlannedExercise(
                    id: UUID(),
                    exerciseID: nil,
                    embeddedExercise: exercise.snapshot,
                    sets: 1,
                    reps: reps,
                    targetWeightKilograms: targetWeight,
                    targetRPE: nil,
                    restSeconds: set.restSeconds,
                    notes: nil,
                    targetRIR: nil,
                    supersetGroupID: exercise.supersetGroupID,
                    progression: .none,
                    targetKind: set.targetKind,
                    targetDurationSeconds: seconds,
                    loadKind: set.loadKind,
                    targetResistanceLevel: resistance
                )

                // Adjacent equal prescriptions can be displayed together;
                // unlike a single merged performance, these remain *new*
                // unrecorded sets with independent source links.
                if let lastIndex = planned.indices.last,
                   planned[lastIndex].embeddedExercise == item.embeddedExercise,
                   planned[lastIndex].reps == item.reps,
                   planned[lastIndex].targetWeightKilograms ==
                    item.targetWeightKilograms,
                   planned[lastIndex].restSeconds == item.restSeconds,
                   planned[lastIndex].targetKind == item.targetKind,
                   planned[lastIndex].targetDurationSeconds ==
                    item.targetDurationSeconds,
                   planned[lastIndex].loadKind == item.loadKind,
                   planned[lastIndex].targetResistanceLevel ==
                    item.targetResistanceLevel,
                   planned[lastIndex].supersetGroupID ==
                    item.supersetGroupID {
                    planned[lastIndex].sets += 1
                } else {
                    planned.append(item)
                }
                linkedSetIDs.append(set.sourceSetID)
            }
        }

        guard !planned.isEmpty else { return nil }

        return PlannedSession(
            id: UUID(),
            title: ATHLTHLocalization.choose(
                english: "Remaining: \(sourceTitle)",
                norwegian: "Resten av \(sourceTitle)"
            ),
            kind: .strength,
            scheduledStart: scheduledStart,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: planned,
            notes: nil,
            followUpSourceWorkoutID: sourceWorkoutID,
            followUpSourceSetIDs: linkedSetIDs
        )
    }
}
