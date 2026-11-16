import Foundation

/// A missed workout is a calendar outcome, not a deleted training record.
/// Time calculations use Calendar so midnight, DST and next-day times remain
/// in the athlete's local time zone.
enum ATHLTHPlannedWorkoutLifecycle {
    static func cancellationDeadline(
        for scheduled: Date,
        calendar: Calendar = .current
    ) -> Date {
        let nextMidnight = calendar.date(
            byAdding: .day, value: 1,
            to: calendar.startOfDay(for: scheduled)
        ) ?? scheduled.addingTimeInterval(86_400)
        let hour = calendar.component(.hour, from: scheduled)
        guard hour >= 19 else { return nextMidnight }
        let fiveHoursLater = scheduled.addingTimeInterval(5 * 60 * 60)
        return max(nextMidnight, fiveHoursLater)
    }

    static func shouldCancel(
        scheduled: Date?,
        now: Date = Date(),
        hasStarted: Bool,
        isCompleted: Bool,
        isCancelled: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard let scheduled, !hasStarted, !isCompleted, !isCancelled
        else { return false }
        return now >= cancellationDeadline(for: scheduled, calendar: calendar)
    }

    /// Preserve a single day when the date picker only changes the clock.
    /// Handles DST gaps with Calendar's matching-date behavior.
    static func updatingClock(
        scheduled: Date,
        clock: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let components = calendar.dateComponents([.hour, .minute], from: clock)
        guard let hour = components.hour, let minute = components.minute
        else { return nil }
        guard let updated = calendar.date(
            bySettingHour: hour, minute: minute, second: 0,
            of: scheduled, matchingPolicy: .strict
        ), calendar.isDate(updated, inSameDayAs: scheduled)
        else { return nil }
        return updated
    }
}

/// Rendered only by Apple Calendar integration. Never write the marker back
/// to PlannedSession.title, saved workouts or the ATHLTH UI.
struct ATHLTHCalendarWorkoutStatus: Equatable {
    var completed = false
    var cancelled = false
    var actualStart: Date? = nil
    var actualEnd: Date? = nil

    var hasValidRecordedInterval: Bool {
        guard completed, let actualStart, let actualEnd
        else { return false }
        return actualEnd >= actualStart
    }

    func calendarTitle(_ original: String) -> String {
        if completed { return "✔️ " + original }
        if cancelled { return "Avlyst · " + original }
        return original
    }
}
