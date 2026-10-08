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
        // Only when all work sets had the same prescribed weight and
        // every target was verified with actual effort data.
        let suggestedNextWeightKilograms: Double?
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

                // Avoid an invented exact prescription for pyramids,
                // missing weight data or sets of different prescribed loads.
                // For a uniform load, a modest ~5% step capped at 2.5 kg
                // can be offered for the athlete to consider manually.
                let prescribedWeights = prescribedWorkSets.compactMap {
                    $0.weightKilograms ?? planned.targetWeightKilograms
                }
                let uniformWeight: Double?
                if verdict == .considerIncrease,
                   let first = prescribedWeights.first,
                   prescribedWeights.count == prescribedWorkSets.count,
                   prescribedWeights.allSatisfy({ abs($0 - first) < 0.01 }) {
                    uniformWeight = first
                } else {
                    uniformWeight = nil
                }
                let suggestedWeight = uniformWeight.map { weight in
                    let increase = min(
                        2.5,
                        max(0.5, (weight * 0.05 * 2).rounded() / 2)
                    )
                    return (weight + increase) * 2
                }.map { $0.rounded() / 2 }

                seenExercises.insert(key)
                recommendations.append(
                    Advice(
                        id: key,
                        exerciseName: planned.embeddedExercise.displayName,
                        workoutDate: workout.endedAt ?? workout.startedAt,
                        verdict: verdict,
                        completedWorkSets: completedWorkSets.count,
                        plannedWorkSets: prescribedWorkSets.count,
                        suggestedNextWeightKilograms: suggestedWeight
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
