import Foundation

/// Single, side-effect-free projection of saved plan dates and standalone
/// sessions for Studio. It never fabricates start times or completion data.
enum ATHLTHStudioSchedule {
    struct Occurrence: Identifiable {
        let id: String
        let workout: PlannedSession
        let date: Date
        let planTitle: String?
        let planID: UUID?
    }

    /// Untimed planned days remain actionable through their calendar day;
    /// explicit start times must never be presented as a future workout once
    /// their scheduled time has passed.
    static func isUpcoming(
        _ item: Occurrence,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        if let explicitStart = item.workout.scheduledStart {
            return explicitStart >= now
        }
        return calendar.startOfDay(for: item.date) >=
            calendar.startOfDay(for: now)
    }

    static func upcoming(
        plans: [TrainingPlan],
        standalone: [PlannedSession],
        pausedPlanIDs: Set<UUID> = [],
        deactivatedPlanIDs: Set<UUID> = [],
        now: Date = .now,
        days: Int = 14,
        calendar: Calendar = .current
    ) -> [Occurrence] {
        window(
            plans: plans,
            standalone: standalone,
            pausedPlanIDs: pausedPlanIDs,
            deactivatedPlanIDs: deactivatedPlanIDs,
            startDate: now,
            days: days,
            calendar: calendar
        )
    }

    /// A calendar-date window used by iPad's Monday–Sunday overview.
    /// No past plans or recordings are marked completed by date alone.
    static func window(
        plans: [TrainingPlan],
        standalone: [PlannedSession],
        pausedPlanIDs: Set<UUID> = [],
        deactivatedPlanIDs: Set<UUID> = [],
        startDate: Date,
        days: Int,
        calendar: Calendar = .current,
        includeRestDays: Bool = false
    ) -> [Occurrence] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: max(1, min(days, 90)), to: start) ?? start
        var entries: [Occurrence] = []
        var identifiers: Set<String> = []
        func append(_ item: PlannedSession, date: Date, planID: UUID?, planTitle: String?) {
            guard (includeRestDays || !item.isExplicitRestDay),
                  date >= start, date < end else { return }
            let key = "\(planID?.uuidString ?? "standalone"):\(item.id.uuidString)"
            guard identifiers.insert(key).inserted else { return }
            entries.append(Occurrence(id: key, workout: item, date: date, planTitle: planTitle, planID: planID))
        }
        for plan in plans {
            guard !pausedPlanIDs.contains(plan.id),
                  !deactivatedPlanIDs.contains(plan.id)
            else { continue }
            for (weekOffset, week) in plan.weeks.enumerated() {
                for day in week.days {
                    // A plan with no start date can still hold explicitly dated sessions.
                    let inferredDate = plan.startDate.flatMap { initial in
                        calendar.date(
                            byAdding: .day,
                            value: weekOffset * 7 + max(0, day.dayIndex - 1),
                            to: calendar.startOfDay(for: initial)
                        )
                    }
                    for workout in day.sessions {
                        guard let date = workout.scheduledStart ?? inferredDate else { continue }
                        append(workout, date: date, planID: plan.id, planTitle: plan.title)
                    }
                }
            }
        }
        for workout in standalone {
            guard let date = workout.scheduledStart else { continue }
            append(workout, date: date, planID: nil, planTitle: nil)
        }
        return entries.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date < $1.date
        }
    }
}
