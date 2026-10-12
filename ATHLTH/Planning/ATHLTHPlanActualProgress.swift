import Foundation

/// Read-only completion overlay for the program trajectory.
/// Session identity is authoritative: the same session can be backed by a
/// finished strength workout, a linked HealthKit activity and a manual mark,
/// but still counts only once. Skipped workouts take precedence.
@MainActor
enum ATHLTHPlanActualProgress {
    struct Week: Identifiable, Equatable {
        let id: UUID
        let number: Int
        let planned: Int
        let completed: Int
        let recorded: Int
        let manuallyMarked: Int
        let skipped: Int
        let completedRunning: Int
        let completedStrength: Int
        let completedOther: Int

        var remaining: Int {
            max(planned - completed - skipped, 0)
        }
    }

    struct Report {
        let weeks: [Week]

        var totalPlanned: Int { weeks.reduce(0) { $0 + $1.planned } }
        var totalCompleted: Int { weeks.reduce(0) { $0 + $1.completed } }
        var totalRecorded: Int { weeks.reduce(0) { $0 + $1.recorded } }
        var totalManuallyMarked: Int {
            weeks.reduce(0) { $0 + $1.manuallyMarked }
        }
        var totalSkipped: Int { weeks.reduce(0) { $0 + $1.skipped } }

        func week(id: UUID) -> Week? {
            weeks.first { $0.id == id }
        }
    }

    static func inspect(
        plan: TrainingPlan,
        store: AppSessionStore,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog]
    ) -> Report {
        var seenIDs = Set<UUID>()
        let sortedWeeks = plan.weeks.sorted { $0.weekNumber < $1.weekNumber }
        let completedWeeks: [Week] = sortedWeeks.map { week in
            var planned = 0
            var completed = 0
            var recorded = 0
            var manuallyMarked = 0
            var skipped = 0
            var completedRunning = 0
            var completedStrength = 0
            var completedOther = 0

            for workout in week.days.flatMap(\.sessions) {
                // Duplicate identities are flagged separately by the structure
                // advisor. Do not count the same linked workout twice.
                guard seenIDs.insert(workout.id).inserted else { continue }
                planned += 1

                if store.isPlanSessionSkipped(
                    planID: plan.id, sessionID: workout.id
                ) {
                    skipped += 1
                    continue
                }

                guard store.isPlanSessionCompleted(
                    planID: plan.id,
                    sessionID: workout.id,
                    healthWorkouts: healthWorkouts,
                    strengthHistory: strengthHistory
                ) else {
                    continue
                }
                completed += 1
                if store.isPlanSessionManuallyCompleted(
                    planID: plan.id, sessionID: workout.id
                ) {
                    manuallyMarked += 1
                } else {
                    recorded += 1
                }

                switch workout.kind {
                case .running: completedRunning += 1
                case .strength: completedStrength += 1
                case .walking, .mobility, .recovery, .custom:
                    completedOther += 1
                }
            }

            return Week(
                id: week.id,
                number: week.weekNumber,
                planned: planned,
                completed: completed,
                recorded: recorded,
                manuallyMarked: manuallyMarked,
                skipped: skipped,
                completedRunning: completedRunning,
                completedStrength: completedStrength,
                completedOther: completedOther
            )
        }

        return Report(weeks: completedWeeks)
    }
}
