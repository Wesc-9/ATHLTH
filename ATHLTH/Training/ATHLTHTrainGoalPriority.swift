import Foundation

/// Suggests a *temporary* Train Today spotlight. It never changes the
/// user's primary goal, stored goal status or linked training plan.
enum ATHLTHTrainGoalPriority {
    static func recommend(
        goals: [ATHLTHGoal],
        primary: ATHLTHGoal?,
        activity: WorkoutKind?,
        activePlanID: UUID?
    ) -> ATHLTHGoal? {
        guard let activity else { return nil }

        let ranked = goals.compactMap { goal -> (goal: ATHLTHGoal, score: Int)? in
            guard goal.status == .active,
                  goal.id != primary?.id
            else { return nil }

            // A goal explicitly linked to a different plan is not evidence
            // for today's plan or for an unplanned quick session.
            if let linked = goal.linkedTrainingPlanID,
               linked != activePlanID {
                return nil
            }

            guard let score = relevance(goal, for: activity) else {
                return nil
            }
            let planBoost = goal.linkedTrainingPlanID == activePlanID &&
                activePlanID != nil ? 2 : 0
            return (goal: goal, score: score + planBoost)
        }

        return ranked.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.goal.createdAt != $1.goal.createdAt {
                return $0.goal.createdAt > $1.goal.createdAt
            }
            return $0.goal.id.uuidString < $1.goal.id.uuidString
        }.first?.goal
    }

    /// Context must follow explicit metadata, not assumptions from a
    /// goal title (e.g. a race/event is not automatically a running goal).
    private static func relevance(
        _ goal: ATHLTHGoal,
        for activity: WorkoutKind
    ) -> Int? {
        let scoped = goal.target?.activity
        let expectedActivity: GoalActivityFilter?
        switch activity {
        case .running: expectedActivity = .running
        case .walking: expectedActivity = .walking
        case .strength, .mobility, .recovery, .custom:
            expectedActivity = nil
        }

        if let scoped, scoped != .any, scoped != expectedActivity {
            return nil
        }

        switch activity {
        case .running, .walking:
            if goal.target?.metric == .singleWorkoutDistanceMeters,
               scoped == expectedActivity {
                return 6
            }
            if goal.category == .event, scoped == expectedActivity {
                return 5
            }
            if goal.category == .endurance {
                return 4
            }
            if goal.category == .consistency,
               goal.target?.metric == .workoutCount,
               scoped == expectedActivity {
                return 3
            }
            return nil

        case .strength:
            // Strength-specific goals are relevant. A running-filtered goal
            // is already rejected by the scoped-activity guard above.
            return goal.category == .strength ? 4 : nil

        case .recovery, .mobility:
            return goal.category == .recovery ? 4 : nil

        case .custom:
            // "Custom" does not identify an activity accurately enough to
            // recommend a different personal goal.
            return nil
        }
    }
}
