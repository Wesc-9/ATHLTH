import Foundation

/// Calendar-day transitions need a refresh even when Train never disappears.
/// Uses the active calendar/timezone, not a fixed 24-hour interval (DST-safe).
enum ATHLTHTrainDayChangePolicy {
    static func needsRefresh(
        displayedDay: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: displayedDay) != calendar.startOfDay(for: now)
    }
}
