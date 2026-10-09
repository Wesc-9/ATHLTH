import Foundation

/// Read-only time-series derived from completed ATHLTH strength sets.
/// A session counts only when its planned-session ID belongs to this plan.
/// Never infer missing loads, reps or body measurements from prescriptions.
enum ATHLTHTrainTrendEngine {
    struct Exercise: Identifiable, Hashable {
        let id: String
        let title: String
    }

    struct Point: Identifiable, Hashable {
        var id: String { "\(exerciseID)|\(Int(date.timeIntervalSince1970))" }
        let exerciseID: String
        let date: Date
        let peakWeightKilograms: Double?
        let volumeKilograms: Double
        let completedWorkingSets: Int
        let completedRepetitions: Int
    }

    struct Snapshot {
        let exercises: [Exercise]
        let points: [Point]
        let linkedWorkoutCount: Int
        let latestWorkoutDate: Date?
        let unlinkedWorkoutCount: Int

        func points(for exerciseID: String) -> [Point] {
            points.filter { $0.exerciseID == exerciseID }
        }
    }

    private struct Aggregate {
        var title: String
        var date: Date
        var peakWeight: Double?
        var volume = 0.0
        var sets = 0
        var reps = 0
    }

    static func make(
        plan: TrainingPlan,
        strengthHistory: [StrengthWorkoutLog],
        calendar: Calendar = .current
    ) -> Snapshot {
        let workouts = plan.weeks.flatMap(\.days).flatMap(\.sessions)
        let linkedSessionIDs = Set(workouts.map(\.id))
        let plannedExerciseNames = Dictionary(
            workouts.flatMap(\.exercises).map {
                ($0.id, $0.embeddedExercise.displayName)
            },
            uniquingKeysWith: { previous, _ in previous }
        )

        // Include exercises that have been scheduled but not yet logged.
        var names: [String: String] = [:]
        for planned in workouts.flatMap(\.exercises) {
            let title = planned.embeddedExercise.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(title)
            if !key.isEmpty { names[key] = title }
        }

        var aggregates: [String: Aggregate] = [:]
        var linkedIDs = Set<UUID>()
        var ignored = 0
        var lastDate: Date?

        for workout in strengthHistory where workout.isFinished {
            guard let plannedID = workout.plannedSessionID,
                  linkedSessionIDs.contains(plannedID) else {
                ignored += 1
                continue
            }
            // A recorded workout ID is unique; repeated copies in a history
            // import must not double the volume or session count.
            guard linkedIDs.insert(workout.id).inserted else { continue }
            let date = calendar.startOfDay(for: workout.endedAt ?? workout.startedAt)
            lastDate = max(lastDate ?? date, date)

            for entry in workout.exercises {
                let name = entry.plannedExerciseID.flatMap {
                    plannedExerciseNames[$0]
                } ?? entry.exercise.displayName
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = normalize(trimmed)
                guard !key.isEmpty else { continue }

                let completedSets = entry.sets.filter(\.countsTowardTrainingLoad)
                guard !completedSets.isEmpty else { continue }

                names[key] = names[key] ?? trimmed
                let groupKey = "\(key)|\(Int(date.timeIntervalSince1970))"
                var aggregate = aggregates[groupKey] ?? Aggregate(
                    title: names[key] ?? trimmed, date: date
                )

                for set in completedSets {
                    aggregate.sets += 1
                    let volume = set.volumeKilograms
                    if volume.isFinite { aggregate.volume += max(0, volume) }
                    aggregate.reps += max(0, set.resolvedCompletedReps ?? 0)

                    // A split/drop set can record several different weights.
                    // The heaviest *actual* segment is the observed peak.
                    let loads: [Double]
                    if let segments = set.effortSegments, !segments.isEmpty {
                        loads = segments.compactMap(\.weightKilograms)
                    } else {
                        loads = set.completedWeightKilograms.map { [$0] } ?? []
                    }
                    for weight in loads where weight.isFinite && weight >= 0 {
                        aggregate.peakWeight = max(
                            aggregate.peakWeight ?? weight, weight
                        )
                    }
                }
                aggregates[groupKey] = aggregate
            }
        }

        let points = aggregates.compactMap { key, aggregate -> Point? in
            guard let sep = key.lastIndex(of: "|") else { return nil }
            return Point(
                exerciseID: String(key[..<sep]),
                date: aggregate.date,
                peakWeightKilograms: aggregate.peakWeight,
                volumeKilograms: aggregate.volume,
                completedWorkingSets: aggregate.sets,
                completedRepetitions: aggregate.reps
            )
        }.sorted {
            $0.date == $1.date
                ? $0.exerciseID < $1.exerciseID
                : $0.date < $1.date
        }

        let exercises = names.map {
            Exercise(id: $0.key, title: $0.value)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return Snapshot(
            exercises: exercises,
            points: points,
            linkedWorkoutCount: linkedIDs.count,
            latestWorkoutDate: lastDate,
            unlinkedWorkoutCount: ignored
        )
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
