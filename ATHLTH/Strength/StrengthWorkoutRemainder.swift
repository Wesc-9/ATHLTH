import Foundation

/// A read-only description of unfinished strength work. No new plan or
/// recorded workout is created until the athlete explicitly confirms it.
struct StrengthWorkoutRemainder {
    let sourceWorkoutID: UUID
    let exercises: [Exercise]

    struct Exercise {
        let sourceExerciseID: UUID
        let snapshot: ExerciseSnapshot
        let sets: [Set]
    }

    struct Set {
        let sourceSetID: UUID
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
        exercises = workout.exercises.compactMap { exercise in
            let remaining = exercise.sets.compactMap { set -> Set? in
                guard !set.isCompleted else { return nil }

                let proposal = Set(
                    sourceSetID: set.id,
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
                sets: remaining
            )
        }
    }

    var setCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var isEmpty: Bool { exercises.isEmpty }
}
