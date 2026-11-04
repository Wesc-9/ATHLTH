import Foundation

/// Local, privacy-first overview of the current calendar week.
/// Planned sessions and recorded workouts are deliberately separate:
/// a recorded workout never implies that a specific plan item was completed.
enum ATHLTHStudioHomeWeek {
    struct Day: Identifiable {
        let date: Date
        let planned: [ATHLTHStudioSchedule.Occurrence]
        let recorded: [WorkoutSummary]
        var id: Date { date }
    }

    struct Snapshot {
        let days: [Day]
        var plannedCount: Int { days.reduce(0) { $0 + $1.planned.count } }
        var recordedCount: Int { days.reduce(0) { $0 + $1.recorded.count } }
        var plannedMinutes: Int {
            days.flatMap(\.planned).reduce(0) {
                $0 + max(0, $1.workout.durationMinutes ?? 0)
            }
        }
    }

    /// Monday-based weeks advance by calendar days, not 604_800 seconds,
    /// which would drift over daylight saving changes in Norway.
    static func shiftedWeek(
        from date: Date,
        offset: Int,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: date) ?? date
    }

    static func weekRange(
        containing date: Date,
        calendar source: Calendar = .current
    ) -> (start: Date, end: Date) {
        var calendar = source
        calendar.firstWeekday = 2
        let startDay = calendar.startOfDay(for: date)
        let days = (calendar.component(.weekday, from: startDay) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -days, to: startDay)
            ?? startDay
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return (start, end)
    }

    static func make(
        plans: [TrainingPlan],
        standalone: [PlannedSession],
        recorded: [WorkoutSummary],
        pausedPlanIDs: Set<UUID> = [],
        deactivatedPlanIDs: Set<UUID> = [],
        now: Date = .now,
        calendar sourceCalendar: Calendar = .current
    ) -> Snapshot {
        var calendar = sourceCalendar
        calendar.firstWeekday = 2
        let referenceDay = calendar.startOfDay(for: now)
        let daysSinceMonday = (calendar.component(.weekday, from: referenceDay) + 5) % 7
        let monday = calendar.date(
            byAdding: .day, value: -daysSinceMonday, to: referenceDay
        ) ?? referenceDay

        let planned = ATHLTHStudioSchedule.window(
            plans: plans,
            standalone: standalone,
            pausedPlanIDs: pausedPlanIDs,
            deactivatedPlanIDs: deactivatedPlanIDs,
            startDate: monday,
            days: 7,
            calendar: calendar
        )
        let groupedPlanned = Dictionary(grouping: planned) {
            calendar.startOfDay(for: $0.date)
        }
        let until = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let includedRecorded = recorded.filter {
            $0.startDate >= monday && $0.startDate < until &&
            $0.duration.isFinite && $0.duration >= 0
        }
        let groupedRecorded = Dictionary(grouping: includedRecorded) {
            calendar.startOfDay(for: $0.startDate)
        }

        let days: [Day] = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monday)
            else { return nil }
            return Day(
                date: date,
                planned: groupedPlanned[date] ?? [],
                recorded: (groupedRecorded[date] ?? [])
                    .sorted { $0.startDate > $1.startDate }
            )
        }
        return Snapshot(days: days)
    }
}
