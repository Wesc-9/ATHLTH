import Foundation

/// One time-based rule shared by the Explore map, Community lists and Club
/// event surfaces. The database cron is authoritative for writing cancellation;
/// this guard also prevents an out-of-date device cache from advertising an
/// event during the few minutes before the next server job runs.
enum CommunityEventExpiryPolicy {
    static let unstartedGracePeriod: TimeInterval = 12 * 60 * 60

    static func shouldAutoCancel(
        status: String,
        startsAt: Date,
        repeatRule: String? = nil,
        repeatUntil: Date? = nil,
        now: Date = Date()
    ) -> Bool {
        guard status == "upcoming",
              startsAt <= now.addingTimeInterval(-unstartedGracePeriod)
        else { return false }

        // A weekly Club series can still contain future occurrences. Never
        // cancel those because one past occurrence was missed.
        if repeatRule == "weekly" {
            guard let repeatUntil else { return false }
            return repeatUntil <= now.addingTimeInterval(-unstartedGracePeriod)
        }

        return true
    }

    static func shouldShowAsUpcoming(
        status: String,
        startsAt: Date,
        repeatRule: String? = nil,
        repeatUntil: Date? = nil,
        now: Date = Date()
    ) -> Bool {
        if status == "live" { return true }
        guard status == "upcoming" else { return false }
        return !shouldAutoCancel(
            status: status,
            startsAt: startsAt,
            repeatRule: repeatRule,
            repeatUntil: repeatUntil,
            now: now
        )
    }
}
