import Foundation

/// Per-exercise, recorded-only strength progress. Planned weights and
/// exercises that were never completed do not count as achieved results.
enum ATHLTHExerciseProgress {
    struct Session: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let workoutTitle: String
        let completedSets: Int
        let repetitions: Int
        let volumeKilograms: Double
        let highestWeightKilograms: Double?
    }

    struct Summary: Equatable {
        let sessions: [Session]
        var uses: Int { sessions.count }
        var totalSets: Int { sessions.reduce(0) { $0 + $1.completedSets } }
        var totalRepetitions: Int { sessions.reduce(0) { $0 + $1.repetitions } }
        var totalVolume: Double {
            sessions.reduce(0) { $0 + $1.volumeKilograms }
        }
        var bestWeight: Double? { sessions.compactMap(\.highestWeightKilograms).max() }
        var lastTrained: Date? { sessions.last?.date }
        var firstToLastWeightChange: Double? {
            guard let first = sessions.compactMap(\.highestWeightKilograms).first,
                  let last = sessions.compactMap(\.highestWeightKilograms).last,
                  sessions.compactMap(\.highestWeightKilograms).count >= 2
            else { return nil }
            return last - first
        }
    }

    static func summary(
        exerciseID: UUID,
        name: String,
        isCustom: Bool,
        workouts: [StrengthWorkoutLog]
    ) -> Summary {
        let canonical = ATHLTHExerciseReferenceResolver.key(name)
        var sessions: [Session] = []
        for workout in workouts where workout.isFinished {
            let matching = workout.exercises.filter { entry in
                if entry.plannedExerciseID == exerciseID { return true }
                // Built-in catalogue items can appear in plans under their
                // plan-specific IDs; exact canonical names are a fallback.
                // Custom exercises never use a potentially ambiguous name.
                return !isCustom &&
                    ATHLTHExerciseReferenceResolver.key(entry.exercise.name) == canonical
            }
            guard !matching.isEmpty else { continue }
            let sets = matching.flatMap(\.sets).filter(\.countsTowardTrainingLoad)
            guard !sets.isEmpty else { continue }
            let recordedReps = sets.compactMap(\.resolvedCompletedReps).reduce(0, +)
            let volume = sets.reduce(0.0) { sum, set in
                guard let weight = set.completedWeightKilograms,
                      let reps = set.resolvedCompletedReps,
                      weight.isFinite, weight > 0, reps > 0 else { return sum }
                return sum + weight * Double(reps)
            }
            let peak = sets.compactMap(\.completedWeightKilograms)
                .filter { $0.isFinite && $0 > 0 }.max()
            let date = matching.compactMap(\.completedAt).max() ??
                workout.endedAt ?? workout.startedAt
            sessions.append(Session(
                id: workout.id, date: date,
                workoutTitle: workout.title,
                completedSets: sets.count, repetitions: recordedReps,
                volumeKilograms: volume, highestWeightKilograms: peak
            ))
        }
        sessions.sort { $0.date < $1.date }
        return Summary(sessions: sessions)
    }
}
