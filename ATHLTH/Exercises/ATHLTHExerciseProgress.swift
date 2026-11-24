import Foundation

/// Per-exercise, recorded-only strength progress. Planned weights and
/// exercises that were never completed do not count as achieved results.
enum ATHLTHExerciseProgress {
    struct Session: Identifiable, Codable, Equatable {
        let id: UUID
        let date: Date
        let workoutTitle: String
        let completedSets: Int
        let repetitions: Int
        let volumeKilograms: Double
        let highestWeightKilograms: Double?
    }

    /// Frozen local-only reference for a specific active workout/exercise.
    /// It is not embedded in shared workouts or their HealthKit exports.
    struct GhostReference: Codable, Equatable {
        let workoutID: UUID
        let exerciseID: UUID
        let exerciseSnapshot: ExerciseSnapshot
        let result: Session

        func applies(to workoutID: UUID, exercise: StrengthExerciseLog) -> Bool {
            self.workoutID == workoutID && exerciseID == exercise.id &&
                ATHLTHCoachStrengthComparableHistory.isSameExercise(exerciseSnapshot, exercise.exercise)
        }
    }

    struct GhostProgress: Equatable {
        let sets: Int
        let reps: Int
        let volume: Double
        let peakWeight: Double?

        init(sets entries: [StrengthSetLog]) {
            let completed = entries.filter(\.countsTowardTrainingLoad)
            sets = completed.count
            reps = completed.compactMap(\.resolvedCompletedReps).reduce(0, +)
            volume = completed.reduce(0) { sum, entry in
                guard let load = entry.completedWeightKilograms, load.isFinite,
                      load > 0, let reps = entry.resolvedCompletedReps, reps > 0 else { return sum }
                return sum + load * Double(reps)
            }
            peakWeight = completed.compactMap(\.completedWeightKilograms)
                .filter { $0.isFinite && $0 > 0 }.max()
        }

        func setProgress(against reference: Session) -> Double {
            guard reference.completedSets > 0 else { return 0 }
            return min(1, Double(sets) / Double(reference.completedSets))
        }
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
        /// Bodyweight-only movements should not show an artificial 0 kg metric.
        var hasMeaningfulLoad: Bool {
            (bestWeight ?? 0) > 0 || totalVolume > 0
        }
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
        workouts: [StrengthWorkoutLog],
        reference: ExerciseSnapshot? = nil
    ) -> Summary {
        let canonical = ATHLTHExerciseReferenceResolver.key(name)
        let referenceIdentity = reference?.libraryExerciseID ?? exerciseID
        var sessions: [Session] = []
        for workout in workouts where workout.isFinished {
            let matching = workout.exercises.filter { entry in
                let logged = entry.exercise
                if let loggedID = logged.libraryExerciseID {
                    // Canonical library identity is authoritative, including
                    // when an exercise is renamed after the workout.
                    guard loggedID == referenceIdentity else { return false }
                    // Known load semantics and equipment must also agree.
                    return reference.map {
                        ATHLTHCoachStrengthComparableHistory.isSameExercise(
                            logged, $0
                        )
                    } ?? true
                }

                // PlannedExerciseID is not the library ID. Preserve the
                // legacy custom fallback only when the ID was explicitly
                // stored as the library ID AND metadata is still comparable.
                if isCustom {
                    guard entry.plannedExerciseID == exerciseID else {
                        return false
                    }
                } else {
                    guard ATHLTHExerciseReferenceResolver.key(logged.name) ==
                            canonical else { return false }
                }

                // Legacy public snapshots without canonical ID may use the
                // exact name only if apparatus and weight semantics match.
                // Unknown historical load basis is NOT assumed equal to a
                // newly specified per-hand/total basis.
                guard let reference else { return !isCustom }
                let oldEquipment = Set(logged.equipment.map {
                    $0.folding(options: [.caseInsensitive, .diacriticInsensitive],
                               locale: .current).trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                })
                let newEquipment = Set(reference.equipment.map {
                    $0.folding(options: [.caseInsensitive, .diacriticInsensitive],
                               locale: .current).trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                })
                guard !oldEquipment.isEmpty, oldEquipment == newEquipment,
                      logged.coachLoadBasis == reference.coachLoadBasis else {
                    return false
                }
                if !isCustom {
                    return ATHLTHExerciseReferenceResolver.key(logged.name) ==
                        canonical
                }
                return true
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
