import Foundation

/// Present plan adjustments only for workouts the existing execution state
/// still allows the athlete to edit. This is a read-only filter.
@MainActor
enum ATHLTHPlanReviewEligibility {
    static func editableIDs(
        in plan: TrainingPlan,
        store: AppSessionStore,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<UUID> {
        guard let startDate = plan.startDate else { return [] }
        let firstDate = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: referenceDate)
        var ids = Set<UUID>()
        for (weekIndex, week) in plan.weeks.enumerated() {
            for day in week.days where (1...7).contains(day.dayIndex) {
                guard let fallback = calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + day.dayIndex - 1,
                    to: firstDate
                ) else { continue }
                for workout in day.sessions {
                    let date = calendar.startOfDay(
                        for: workout.scheduledStart ?? fallback
                    )
                    guard date >= today,
                          !store.isPlanSessionSkipped(
                            planID: plan.id, sessionID: workout.id
                          ),
                          !store.isPlanSessionCompleted(
                            planID: plan.id, sessionID: workout.id,
                            healthWorkouts: healthWorkouts,
                            strengthHistory: strengthHistory
                          )
                    else { continue }
                    ids.insert(workout.id)
                }
            }
        }
        return ids
    }

    static func isRelevant(
        _ suggestion: ATHLTHPlanReviewAdvisor.Suggestion,
        in plan: TrainingPlan,
        editableIDs: Set<UUID>
    ) -> Bool {
        guard let week = plan.weeks.first(where: {
            $0.id == suggestion.weekID
        }) else { return false }

        let workouts: [PlannedSession]
        if let dayID = suggestion.dayID {
            guard let day = week.days.first(where: {
                $0.id == dayID
            }) else { return false }
            workouts = day.sessions
        } else {
            workouts = week.days.flatMap(\.sessions)
        }

        return workouts.contains { workout in
            guard editableIDs.contains(workout.id) else { return false }
            switch suggestion.kind {
            case .missingDuration:
                return (workout.durationMinutes ?? 0) <= 0
            case .consecutiveRuns:
                return workout.kind == .running
            case .consecutiveStrength:
                return workout.kind == .strength
            case .mixedDay:
                return workout.kind == .strength
            case .longDay, .crowdedWeek, .increasingFrequency:
                return true
            }
        }
    }
}
