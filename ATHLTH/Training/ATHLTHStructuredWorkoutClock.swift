import Foundation

/// Shared clock arithmetic for a single structured iPhone workout.
/// This policy does not allocate or write a second workout or HealthKit session.
enum ATHLTHStructuredWorkoutClock {
    static func at(_ now: Date, pause: Date?) -> Date? {
        guard now.timeIntervalSince1970.isFinite else { return nil }
        guard let pause else { return now }
        return pause.timeIntervalSince1970.isFinite && pause <= now ? pause : nil
    }

    static func elapsed(
        start: Date, now: Date, pause: Date?, pausedSeconds: TimeInterval
    ) -> TimeInterval? {
        guard start.timeIntervalSince1970.isFinite,
              pausedSeconds.isFinite, pausedSeconds >= 0,
              let effective = at(now, pause: pause) else { return nil }
        let wall = effective.timeIntervalSince(start)
        guard wall >= 0, pausedSeconds <= wall else { return nil }
        return wall - pausedSeconds
    }

    static func resumeOffset(from pause: Date, at now: Date) -> TimeInterval? {
        guard at(now, pause: pause) != nil else { return nil }
        return now.timeIntervalSince(pause)
    }
}
