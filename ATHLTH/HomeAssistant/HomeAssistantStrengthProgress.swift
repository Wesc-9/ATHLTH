import CryptoKit
import Foundation

/// Only *finished* ATHLTH strength workouts and completed non-warmup efforts.
/// Neither planned sets nor unfinished sessions can become an achievement.
struct HomeAssistantStrengthProgressPoint: Hashable {
    let id: String
    let exercise: String
    let reps: Int
    let weightKilograms: Double
    let endedAt: Date
}

enum HomeAssistantStrengthProgressExtractor {
    /// Return the strongest logged effort at an identical repetition count
    /// for a given exercise and completed workout. Split sets stay distinct.
    static func confirmedBestSets(
        from workouts: [StrengthWorkoutLog],
        now: Date = Date()
    ) -> [HomeAssistantStrengthProgressPoint] {
        let since = now.addingTimeInterval(-90 * 86_400)
        var best: [String: HomeAssistantStrengthProgressPoint] = [:]

        for workout in workouts {
            guard let end = workout.endedAt,
                  end >= since, end <= now,
                  workout.startedAt <= end
            else { continue }

            for loggedExercise in workout.exercises {
                let exerciseName = String(
                    loggedExercise.exercise.name
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .prefix(64)
                )
                guard !exerciseName.isEmpty else { continue }
                for set in loggedExercise.sets where set.countsTowardTrainingLoad {
                    let efforts: [(Int?, Double?)]
                    if let segments = set.effortSegments, !segments.isEmpty {
                        efforts = segments.map { ($0.reps, $0.weightKilograms) }
                    } else {
                        efforts = [(set.completedReps, set.completedWeightKilograms)]
                    }
                    for (rawReps, rawWeight) in efforts {
                        guard let reps = rawReps, (1...50).contains(reps),
                              let weight = rawWeight, weight.isFinite,
                              weight > 0, weight <= 2_000
                        else { continue }

                        let key = workout.id.uuidString + "|" +
                            exerciseName.lowercased() + "|" + String(reps)
                        if let existing = best[key],
                           existing.weightKilograms >= weight {
                            continue
                        }
                        let id = SHA256.hash(data: Data(key.utf8))
                            .map { String(format: "%02x", $0) }
                            .joined()
                        best[key] = HomeAssistantStrengthProgressPoint(
                            id: String(id.prefix(32)),
                            exercise: exerciseName,
                            reps: reps,
                            weightKilograms: weight,
                            endedAt: end
                        )
                    }
                }
            }
        }

        return Array(
            best.values.sorted {
                if $0.endedAt != $1.endedAt {
                    return $0.endedAt > $1.endedAt
                }
                return $0.id < $1.id
            }.prefix(60)
        )
    }
}
