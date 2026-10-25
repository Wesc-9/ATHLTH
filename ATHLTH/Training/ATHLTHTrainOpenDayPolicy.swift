import Foundation

/// A non-prescriptive, deterministic choice for the primary Today card when
/// there is no planned workout. Never labels an activity as a repeat of a
/// specific saved session unless we have its identity and launch path.
enum ATHLTHTrainOpenDayPolicy {
    enum Choice: Equatable {
        case trainedToday
        case familiar(WorkoutKind)
        case goal(WorkoutKind)
        case favorite(String)
        case library
        case explore
    }

    static func choose(
        hasRecordedToday: Bool,
        lastCompletedKind: WorkoutKind?,
        activePrimaryGoal: ATHLTHGoal?,
        quickTaps: [String: Int],
        hasLibrarySuggestion: Bool
    ) -> Choice {
        if hasRecordedToday { return .trainedToday }

        // Only activity types supported by the existing quick launch flow.
        if let lastCompletedKind,
           [.running, .walking, .strength].contains(lastCompletedKind) {
            return .familiar(lastCompletedKind)
        }

        if let activePrimaryGoal,
           activePrimaryGoal.status == .active,
           let kind = explicitGoalKind(activePrimaryGoal) {
            return .goal(kind)
        }

        let defaultOrder = [
            "running", "walking", "strength", "cycling", "yoga", "custom"
        ]
        if let favorite = defaultOrder
            .enumerated()
            .filter({ quickTaps[$0.element, default: 0] > 0 })
            .sorted(by: { lhs, rhs in
                let left = quickTaps[lhs.element, default: 0]
                let right = quickTaps[rhs.element, default: 0]
                return left == right ? lhs.offset < rhs.offset : left > right
            })
            .first?.element {
            return .favorite(favorite)
        }
        return hasLibrarySuggestion ? .library : .explore
    }

    private static func explicitGoalKind(_ goal: ATHLTHGoal) -> WorkoutKind? {
        if goal.target?.activity == .running { return .running }
        if goal.target?.activity == .walking { return .walking }
        if goal.category == .strength,
           goal.target?.activity == nil || goal.target?.activity == .any {
            return .strength
        }
        // A generic endurance/event goal must not be guessed to be a run.
        return nil
    }
}
