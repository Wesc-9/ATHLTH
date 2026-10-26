import Foundation

/// Pure date rules shared by the Train relocation sheet and its tests.
/// Dates follow the plan's actual start day, not the start of a calendar week.
enum ATHLTHTrainWorkoutMovePolicy {
    static func allowedDates(
        startDate: Date?,
        weekCount: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ClosedRange<Date>? {
        guard let startDate, weekCount > 0 else { return nil }
        let first = calendar.startOfDay(for: startDate)
        guard let last = calendar.date(
            byAdding: .day, value: weekCount * 7 - 1, to: first
        ) else { return nil }
        let earliest = max(first, calendar.startOfDay(for: now))
        guard earliest <= last else { return nil }
        return earliest...last
    }

    static func originalDate(
        for workoutID: UUID,
        in plan: TrainingPlan,
        calendar: Calendar = .current
    ) -> Date? {
        guard let start = plan.startDate else { return nil }
        for (weekIndex, week) in plan.weeks.enumerated() {
            for day in week.days
            where day.sessions.contains(where: { $0.id == workoutID }) {
                return calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + min(max(day.dayIndex - 1, 0), 6),
                    to: calendar.startOfDay(for: start)
                )
            }
        }
        return nil
    }

    static func canMove(
        to targetDate: Date,
        from originalDate: Date?,
        within bounds: ClosedRange<Date>?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let originalDate, let bounds else { return false }
        let day = calendar.startOfDay(for: targetDate)
        return bounds.contains(day) &&
            !calendar.isDate(day, inSameDayAs: originalDate)
    }
}
