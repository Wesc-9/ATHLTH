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

    /// One pass through saved plans produces both Home timelines. Each window
    /// owns its own de-duplication set, preserving the previous behaviour
    /// when a saved session ID occurs in multiple dates.
    static func studioHomeWindows(
        plans: [TrainingPlan],
        standalone: [PlannedSession],
        pausedPlanIDs: Set<UUID> = [],
        deactivatedPlanIDs: Set<UUID> = [],
        selectedWeekDate: Date,
        upcomingFrom: Date = .now,
        calendar sourceCalendar: Calendar = .current
    ) -> (week: [Occurrence], upcoming: [Occurrence]) {
        var calendar = sourceCalendar
        calendar.firstWeekday = 2
        let monday = HomeWeeklyProgressCalendar.weekInterval(
            offset: 0, referenceDate: selectedWeekDate, calendar: calendar
        ).start
        let results = collect(
            plans: plans,
            standalone: standalone,
            pausedPlanIDs: pausedPlanIDs,
            deactivatedPlanIDs: deactivatedPlanIDs,
            requests: [
                WindowRequest(startDate: monday, days: 7, includeRestDays: true),
                WindowRequest(startDate: upcomingFrom, days: 14, includeRestDays: false)
            ],
            calendar: calendar
        )
        return (week: results[0], upcoming: results[1])
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
        collect(
            plans: plans,
            standalone: standalone,
            pausedPlanIDs: pausedPlanIDs,
            deactivatedPlanIDs: deactivatedPlanIDs,
            requests: [
                WindowRequest(startDate: startDate, days: days,
                              includeRestDays: includeRestDays)
            ],
            calendar: calendar
        )[0]
    }

    private struct WindowRequest {
        let startDate: Date
        let days: Int
        let includeRestDays: Bool
    }

    private static func collect(
        plans: [TrainingPlan],
        standalone: [PlannedSession],
        pausedPlanIDs: Set<UUID>,
        deactivatedPlanIDs: Set<UUID>,
        requests: [WindowRequest],
        calendar: Calendar
    ) -> [[Occurrence]] {
        let ranges = requests.map { request in
            let start = calendar.startOfDay(for: request.startDate)
            let end = calendar.date(
                byAdding: .day,
                value: max(1, min(request.days, 90)),
                to: start
            ) ?? start
            return (start: start, end: end, includeRestDays: request.includeRestDays)
        }
        var entries = requests.map { _ in [Occurrence]() }
        var identifiers = requests.map { _ in Set<String>() }

        func append(_ item: PlannedSession, date: Date,
                    planID: UUID?, planTitle: String?) {
            let key = "\(planID?.uuidString ?? "standalone"):\(item.id.uuidString)"
            for index in ranges.indices {
                let range = ranges[index]
                guard (range.includeRestDays || !item.isExplicitRestDay),
                      date >= range.start, date < range.end,
                      identifiers[index].insert(key).inserted else { continue }
                entries[index].append(Occurrence(
                    id: key, workout: item, date: date,
                    planTitle: planTitle, planID: planID
                ))
            }
        }

        for plan in plans {
            guard !pausedPlanIDs.contains(plan.id),
                  !deactivatedPlanIDs.contains(plan.id) else { continue }
            for (weekOffset, week) in plan.weeks.enumerated() {
                for day in week.days {
                    // Explicit workout dates override the planned day.
                    let inferredDate = plan.startDate.flatMap { initial in
                        calendar.date(
                            byAdding: .day,
                            value: weekOffset * 7 + max(0, day.dayIndex - 1),
                            to: calendar.startOfDay(for: initial)
                        )
                    }
                    for workout in day.sessions {
                        guard let date = workout.scheduledStart ?? inferredDate
                        else { continue }
                        append(workout, date: date, planID: plan.id,
                               planTitle: plan.title)
                    }
                }
            }
        }
        for workout in standalone {
            guard let date = workout.scheduledStart else { continue }
            append(workout, date: date, planID: nil, planTitle: nil)
        }
        return entries.map { list in
            list.sorted {
                if $0.date == $1.date { return $0.id < $1.id }
                return $0.date < $1.date
            }
        }
    }
}
