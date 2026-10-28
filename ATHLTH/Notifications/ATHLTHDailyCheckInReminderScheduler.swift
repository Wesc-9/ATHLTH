import Foundation
import UserNotifications

/// Local iPhone notifications for the optional daily check-in. A rolling
/// seven-day window works while the app is closed and requires no cloud
/// notification or disclosure of private health data.
@MainActor
enum ATHLTHDailyCheckInReminderScheduler {
    static let identifierPrefix = "insights.daily-check-in."
    static let reminderHour = 9
    static let horizonDays = 7

    static func eventKey(
        accountID: UUID, date: Date, calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return identifierPrefix + accountID.uuidString + "." +
            String(format: "%04d-%02d-%02d",
                   components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Calculate the exact identifiers to keep; the current day's reminder
    /// is removed immediately if the athlete completed that day's check-in.
    /// Future days never inherit today's completed status.
    static func datesToSchedule(
        enabled: Bool, completedToday: Bool,
        accountID: UUID, now: Date,
        calendar: Calendar = .current
    ) -> [(key: String, date: Date)] {
        guard enabled else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [(key: String, date: Date)] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: reminderHour, minute: 0,
                                           second: 0, of: day)
            else { continue }
            if offset == 0 && completedToday { continue }
            // Do not create overdue system alerts when the app is opened
            // after the scheduled time. The in-app reminder still appears.
            guard fire > now else { continue }
            result.append((key: eventKey(accountID: accountID, date: day,
                                         calendar: calendar), date: fire))
        }
        return result
    }

    static func reconcile(
        enabled: Bool, accountID: UUID, completedToday: Bool,
        now: Date = Date(), calendar: Calendar = .current
    ) async {
        let center = UNUserNotificationCenter.current()
        let wanted = datesToSchedule(enabled: enabled,
                                     completedToday: completedToday,
                                     accountID: accountID,
                                     now: now, calendar: calendar)
        let wantedIDs = Set(wanted.map(\.key))
        let pending = await center.pendingNotificationRequests()
        let owned = pending.map(\.identifier).filter {
            $0.hasPrefix(identifierPrefix)
        }
        let obsolete = owned.filter { !wantedIDs.contains($0) }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }

        // Remove stale delivered reminders on opt-out, account changes and
        // after completing today's check-in. Do not dismiss unrelated alerts.
        let delivered = await center.deliveredNotifications()
        let currentKey = eventKey(accountID: accountID, date: now,
                                  calendar: calendar)
        let expiredDelivered = delivered.map { $0.request.identifier }.filter {
            $0.hasPrefix(identifierPrefix) &&
                (!enabled || !$0.hasPrefix(identifierPrefix + accountID.uuidString + ".") ||
                 $0 != currentKey || completedToday)
        }
        if !expiredDelivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: expiredDelivered)
        }

        guard enabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized ||
              status == .provisional ||
              status == .ephemeral else { return }

        let alreadyScheduled = Set(owned).subtracting(obsolete)
        for reminder in wanted where !alreadyScheduled.contains(reminder.key) {
            let content = UNMutableNotificationContent()
            content.title = ATHLTHLocalization.choose(
                english: "How are you feeling today?",
                norwegian: "Hvordan føler du deg i dag?"
            )
            content.body = ATHLTHLocalization.choose(
                english: "Your optional daily check-in is ready. Share how you feel in ATHLTH.",
                norwegian: "Dagens valgfrie innsjekk er klar. Fortell ATHLTH hvordan du har det."
            )
            content.sound = .default
            content.userInfo = [
                "athlth_kind": "daily_check_in",
                "athlthCheckInAccountID": accountID.uuidString,
                "athlthEventKey": reminder.key
            ]
            let dateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.date
            )
            let request = UNNotificationRequest(
                identifier: reminder.key, content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: dateComponents, repeats: false
                )
            )
            try? await center.add(request)
        }
    }

    static func isCurrentAccountCheckInTap(
        _ info: [AnyHashable: Any], accountID: UUID
    ) -> Bool {
        (info["athlth_kind"] as? String) == "daily_check_in" &&
            (info["athlthCheckInAccountID"] as? String) == accountID.uuidString
    }
}
