import Foundation

/// One progress rule for goal detail, the goal list and the private profile card.
/// Weight targets use a recorded value when available; other goal types retain
/// the existing milestone-based calculation.
enum ATHLTHGoalProgressPolicy {
    static func progress(
        for goal: ATHLTHGoal,
        profile: ATHLTHTrainingProfile,
        latestBodyWeightKilograms: Double? = nil
    ) -> Double {
        if goal.bodyMeasurementGoal != nil {
            return ATHLTHBodyGoalCheckInPolicy.progress(goal, profile: profile)
        }

        if let target = goal.target,
           target.metric == .bodyWeightKilograms,
           let baseline = target.baselineValue,
           let current = latestBodyWeightKilograms,
           baseline.isFinite, target.targetValue.isFinite, current.isFinite,
           target.targetValue != baseline {
            let ratio = (current - baseline) / (target.targetValue - baseline)
            return min(1, max(0, ratio))
        }

        return min(1, max(0, goal.progress))
    }
}
