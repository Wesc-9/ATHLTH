import Foundation

/// Evidence-based, read-only training notes from explicitly linked workouts.
/// No planned prescriptions are edited or automatically increased.
enum TrainingPlanLoadAdvisor {
    enum Verdict: String {
        case considerIncrease
        case targetMet
        case reviewTargets
    }

    struct Advice: Identifiable {
        let id: String
        let exerciseName: String
        let workoutDate: Date
        let verdict: Verdict
        let completedWorkSets: Int
        let plannedWorkSets: Int
    }

    static func evaluate(
        plan: TrainingPlan,
        strengthHistory: [StrengthWorkoutLog],
        limit: Int = 5
    ) -> [Advice] {
        guard limit > 0 else { return [] }

        let sessions = plan.weeks
            .flatMap(\.days)
            .flatMap(\.sessions)
        let plannedBySessionID = sessions.reduce(
            into: [UUID: PlannedSession]()
        ) { result, workout in
            result[workout.id] = workout
        }

        let completed = strengthHistory
            .filter { workout in
                workout.isFinished &&
                    workout.trackingMode == .advanced &&
                    workout.plannedSessionID.flatMap {
                        plannedBySessionID[$0]
                    } != nil
            }
            .sorted {
                ($0.endedAt ?? $0.startedAt) >
                    ($1.endedAt ?? $1.startedAt)
            }

        var seenExercises = Set<String>()
        var recommendations: [Advice] = []

        for workout in completed {
            guard let sessionID = workout.plannedSessionID,
                  let session = plannedBySessionID[sessionID] else {
                continue
            }

            for log in workout.exercises {
                guard let plannedExerciseID = log.plannedExerciseID,
                      let planned = session.exercises.first(
                        where: { $0.id == plannedExerciseID }
                      ), planned.resolvedTargetKind == .reps
                else { continue }

                let name = planned.embeddedExercise.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let key = (planned.exerciseID?.uuidString ?? name.lowercased())
                guard !name.isEmpty, !seenExercises.contains(key) else {
                    continue
                }

                let prescribedWorkSets = planned.resolvedSetTargets.filter {
                    $0.isWarmUp != true && $0.setType != .warmUp
                }
                // Without specific rep targets, ATHLTH cannot objectively
                // compare logged results with the user's plan.
                let hasValidRepTargets = prescribedWorkSets.allSatisfy { target in
                    (target.reps ?? planned.reps ?? 0) > 0
                }
                guard !prescribedWorkSets.isEmpty, hasValidRepTargets else {
                    continue
                }

                let completedWorkSets = log.sets.filter(\.countsTowardTrainingLoad)
                let metTarget = completedWorkSets.count >= prescribedWorkSets.count &&
                    zip(prescribedWorkSets, completedWorkSets).allSatisfy { pair in
                        let target = pair.0
                        let actual = pair.1
                        let reps = target.reps ?? planned.reps ?? 0
                        if let weight = target.weightKilograms ??
                                planned.targetWeightKilograms,
                           weight > 0 {
                            return actual.completedReps(
                                atOrAboveWeightKilograms: weight
                            ) >= reps
                        }
                        return (actual.resolvedCompletedReps ?? 0) >= reps
                    }

                // An increase should be considered only if every planned
                // work set was achieved at its prescribed load AND actual
                // logged reps-in-reserve suggests capacity. Planned RIR is
                // never confused with completed RIR.
                let weightsSet = prescribedWorkSets.allSatisfy {
                    ($0.weightKilograms ?? planned.targetWeightKilograms ?? 0) > 0
                }
                let effortVerified = completedWorkSets
                    .prefix(prescribedWorkSets.count)
                    .allSatisfy { ($0.rir ?? -1) >= 2 }

                let verdict: Verdict
                if !metTarget {
                    verdict = .reviewTargets
                } else if weightsSet && effortVerified {
                    verdict = .considerIncrease
                } else {
                    verdict = .targetMet
                }

                seenExercises.insert(key)
                recommendations.append(
                    Advice(
                        id: key,
                        exerciseName: planned.embeddedExercise.displayName,
                        workoutDate: workout.endedAt ?? workout.startedAt,
                        verdict: verdict,
                        completedWorkSets: completedWorkSets.count,
                        plannedWorkSets: prescribedWorkSets.count
                    )
                )

                if recommendations.count >= limit {
                    return recommendations
                }
            }
        }

        return recommendations
    }
}
