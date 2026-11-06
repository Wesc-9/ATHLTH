import Foundation

/// One-way interpretation repair for older core holds that were incorrectly
/// saved as weighted repetition exercises. This NEVER invents a duration.
/// A one-time account-local copy of the original history is kept by the store.
enum StrengthTimedHistoryRepair {
    static func clean(
        _ history: [StrengthWorkoutLog]
    ) -> (history: [StrengthWorkoutLog], changed: Bool) {
        var changed = false
        let corrected = history.map { original in
            var workout = original
            workout.exercises = original.exercises.compactMap { source in
                guard source.exercise.isTimeOnlyBodyweightStrength else {
                    return source
                }
                var exercise = source
                exercise.barWeightKilograms = nil
                var repairedSets: [StrengthSetLog] = []
                for originalSet in source.sets {
                    var set = originalSet
                    let validDuration = set.resolvedCompletedDurationSeconds ??
                        set.actualSetElapsedSeconds.flatMap {
                            $0.isFinite && $0 >= 1 ? Int($0.rounded()) : nil
                        }

                    // An old completed "10 reps x 15 kg" is not evidence
                    // of a 10-second hold. Discard the incorrect set result.
                    if set.isCompleted && validDuration == nil {
                        changed = true
                        continue
                    }

                    if set.targetKind != .time ||
                        set.plannedReps != nil ||
                        set.completedReps != nil ||
                        set.plannedWeightKilograms != nil ||
                        set.completedWeightKilograms != nil ||
                        set.recordsWeight != false ||
                        set.effortSegments != nil {
                        changed = true
                    }

                    set.targetKind = .time
                    set.plannedReps = nil
                    set.completedReps = nil
                    set.plannedWeightKilograms = nil
                    set.completedWeightKilograms = nil
                    set.recordsWeight = false
                    // Mixed legacy segments containing reps/weight must not
                    // survive as personal records or bogus training volume.
                    set.effortSegments = nil
                    set.completedDurationSeconds = validDuration
                    if set.plannedDurationSeconds == nil {
                        set.plannedDurationSeconds =
                            source.exercise.defaultStrengthTargetDurationSeconds
                    }
                    repairedSets.append(set)
                }
                exercise.sets = repairedSets
                if exercise.sets.isEmpty {
                    if !source.sets.isEmpty { changed = true }
                    return nil
                }
                return exercise
            }
            return workout
        }
        return (corrected, changed)
    }
}
