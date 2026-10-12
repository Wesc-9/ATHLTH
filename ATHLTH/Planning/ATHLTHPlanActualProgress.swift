import Foundation

/// Read-only completion overlay for the program trajectory.
/// Session identity is authoritative: the same session can be backed by a
/// finished strength workout, a linked HealthKit activity and a manual mark,
/// but still counts only once. Skipped workouts take precedence.
@MainActor
enum ATHLTHPlanActualProgress {
    /// Every planned session belongs to exactly one of these buckets.
    /// "Recorded" includes a linked Health workout or an ATHLTH strength log;
    /// manual confirmation is reported separately and takes precedence.
    struct KindProgress: Equatable {
        var planned = 0
        var recorded = 0
        var manuallyMarked = 0
        var skipped = 0

        var completed: Int { recorded + manuallyMarked }

        mutating func add(_ other: KindProgress) {
            planned += other.planned
            recorded += other.recorded
            manuallyMarked += other.manuallyMarked
            skipped += other.skipped
        }
    }

    struct Week: Identifiable, Equatable {
        let id: UUID
        let number: Int
        let planned: Int
        let completed: Int
        let recorded: Int
        let manuallyMarked: Int
        let skipped: Int
        let running: KindProgress
        let strength: KindProgress
        let other: KindProgress

        var completedRunning: Int { running.completed }
        var completedStrength: Int { strength.completed }
        var completedOther: Int { other.completed }

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
        var running: KindProgress {
            weeks.reduce(into: KindProgress()) { $0.add($1.running) }
        }
        var strength: KindProgress {
            weeks.reduce(into: KindProgress()) { $0.add($1.strength) }
        }
        var other: KindProgress {
            weeks.reduce(into: KindProgress()) { $0.add($1.other) }
        }

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
            // Fixed indices: 0 = running, 1 = strength, 2 = other.
            var kinds = [KindProgress(), KindProgress(), KindProgress()]

            for workout in week.days.flatMap(\.sessions) {
                // Duplicate identities are flagged separately by the structure
                // advisor. Do not count the same linked workout twice.
                guard seenIDs.insert(workout.id).inserted else { continue }
                let kindIndex: Int
                switch workout.kind {
                case .running: kindIndex = 0
                case .strength: kindIndex = 1
                case .walking, .mobility, .recovery, .custom:
                    kindIndex = 2
                }
                planned += 1
                kinds[kindIndex].planned += 1

                if store.isPlanSessionSkipped(
                    planID: plan.id, sessionID: workout.id
                ) {
                    skipped += 1
                    kinds[kindIndex].skipped += 1
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
                    kinds[kindIndex].manuallyMarked += 1
                } else {
                    recorded += 1
                    kinds[kindIndex].recorded += 1
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
                running: kinds[0],
                strength: kinds[1],
                other: kinds[2]
            )
        }

        return Report(weeks: completedWeeks)
    }
}
