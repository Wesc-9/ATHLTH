import Foundation

/// Evidence-based indicators for goals linked to an ATHLTH training plan.
/// A numerical result is only shown when recorded data support it.
enum ATHLTHTrainGoalEvidence {
    struct Result {
        let observed: Double?
        let baseline: Double?
        let target: Double?
        let unit: String?
        let completionFraction: Double?
        let evidenceLabel: String
        let description: String
        let sampleCount: Int

        var hasEvidence: Bool { observed != nil }
    }

    static func evaluate(
        goal: ATHLTHGoal,
        plan: TrainingPlan,
        strengthHistory: [StrengthWorkoutLog],
        completedSessionIDs: Set<UUID>
    ) -> Result {
        guard goal.linkedTrainingPlanID == plan.id else {
            return .init(
                observed: nil, baseline: nil, target: nil,
                unit: nil, completionFraction: nil,
                evidenceLabel: "Not linked",
                description: "This goal is not linked to the chosen training plan.",
                sampleCount: 0
            )
        }

        guard let target = goal.target else {
            return .init(
                observed: nil, baseline: nil, target: nil,
                unit: nil, completionFraction: nil,
                evidenceLabel: "Manual goal",
                description: "No numerical target. See the goal's milestones for progress.",
                sampleCount: 0
            )
        }

        switch target.metric {
        case .workoutCount:
            // Only workouts explicitly completed against this plan count.
            let value = Double(completedSessionIDs.count)
            return .init(
                observed: value,
                baseline: target.baselineValue ?? 0,
                target: target.targetValue,
                unit: "økter",
                completionFraction: ratio(
                    current: value,
                    baseline: target.baselineValue ?? 0,
                    target: target.targetValue
                ),
                evidenceLabel: "Plan session completions",
                description: "Counts completed planned workouts only; future sessions never count.",
                sampleCount: completedSessionIDs.count
            )

        case .strengthWeightKilograms:
            let rawName = target.exerciseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawName.isEmpty else {
                return unavailable(target: target, reason: "Choose an exercise for this strength goal.")
            }

            // ATHLTH strength data are joined through planned-session IDs.
            // Never infer that a similarly named unrelated workout belongs to this plan.
            let plannedIDs = Set(plan.weeks.flatMap(\.days).flatMap(\.sessions).map(\.id))
            let logged = strengthHistory.filter {
                $0.isFinished && $0.plannedSessionID.map(plannedIDs.contains) == true
            }
            let weights = logged.flatMap(\.exercises)
                .filter {
                    $0.exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        .localizedCaseInsensitiveCompare(rawName) == .orderedSame
                }
                .flatMap(\.sets)
                .filter { $0.isCompleted && $0.isWarmUp != true }
                .compactMap { set -> Double? in
                    guard let weight = set.completedWeightKilograms,
                          weight.isFinite, weight >= 0 else { return nil }
                    return weight
                }
            guard let best = weights.max() else {
                return unavailable(
                    target: target,
                    reason: "No linked, completed working set with a recorded weight for this exercise."
                )
            }
            return .init(
                observed: best,
                baseline: target.baselineValue,
                target: target.targetValue,
                unit: "kg",
                completionFraction: target.baselineValue.flatMap {
                    ratio(current: best, baseline: $0, target: target.targetValue)
                },
                evidenceLabel: "Recorded working-set load",
                description: "Highest recorded working-set weight for this exercise in linked ATHLTH strength sessions. Not estimated 1RM.",
                sampleCount: weights.count
            )

        default:
            return unavailable(
                target: target,
                reason: "This metric is managed by ATHLTH Goals. No unsupported plan-specific estimate is shown."
            )
        }
    }

    private static func unavailable(target: GoalTarget, reason: String) -> Result {
        Result(
            observed: nil,
            baseline: target.baselineValue,
            target: target.targetValue,
            unit: target.unit,
            completionFraction: nil,
            evidenceLabel: "Waiting for verified results",
            description: reason,
            sampleCount: 0
        )
    }

    private static func ratio(current: Double, baseline: Double, target: Double) -> Double? {
        guard current.isFinite, baseline.isFinite, target.isFinite,
              target > baseline else { return nil }
        return min(max((current - baseline) / (target - baseline), 0), 1)
    }
}
