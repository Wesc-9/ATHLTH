import Foundation
import UserNotifications

/// Exactly one local ending reminder for the active official Weekly Challenge.
/// Other Club, Arena and personal challenge notifications are unchanged.
enum OfficialWeeklyChallengeReminderPolicy {
    static let identifierPrefix = "official-weekly-ending-"
    static let leadTime: TimeInterval = 24 * 60 * 60

    static func identifier(for challengeID: UUID) -> String {
        identifierPrefix + challengeID.uuidString.lowercased()
    }

    static func reminderDate(
        for challenge: OfficialWeeklyChallenge,
        joined: Bool,
        completed: Bool,
        now: Date = Date()
    ) -> Date? {
        guard joined,
              !completed,
              challenge.startsAt <= now,
              challenge.endsAt > now
        else { return nil }

        let deadline = challenge.endsAt.addingTimeInterval(-leadTime)
        // Never re-trigger a reminder after the 24-hour point has passed.
        guard deadline > now else { return nil }
        return deadline
    }
}

@MainActor
enum OfficialWeeklyChallengeReminderScheduler {
    static func reconcile(
        challenge: OfficialWeeklyChallenge?,
        joined: Bool,
        completed: Bool
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending: [UNNotificationRequest] = await withCheckedContinuation {
            (continuation: CheckedContinuation<[UNNotificationRequest], Never>) in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }

        let existing = pending.filter {
            $0.identifier.hasPrefix(
                OfficialWeeklyChallengeReminderPolicy.identifierPrefix
            )
        }

        let enabled = UserDefaults.standard.object(
            forKey: "settings.challengeNotifications"
        ).map { _ in UserDefaults.standard.bool(forKey: "settings.challengeNotifications") } ?? true

        let settings = await center.notificationSettings()
        let authorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        default:
            authorized = false
        }

        let now = Date()
        let reminder: (id: String, date: Date)?
        if enabled, authorized,
           let challenge,
           let date = OfficialWeeklyChallengeReminderPolicy.reminderDate(
               for: challenge,
               joined: joined,
               completed: completed,
               now: now
           ) {
            reminder = (
                OfficialWeeklyChallengeReminderPolicy.identifier(for: challenge.id),
                date
            )
        } else {
            reminder = nil
        }

        // Cancels a pending notification as soon as completion is synced,
        // the challenge ends, the user leaves or notifications are disabled.
        let obsoleteIDs = existing.map(\.identifier).filter {
            $0 != reminder?.id
        }
        if !obsoleteIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsoleteIDs)
        }

        guard let reminder,
              !existing.contains(where: { $0.identifier == reminder.id }),
              let challenge
        else { return }

        let content = UNMutableNotificationContent()
        content.title = ATHLTHLocalization.choose(
            english: "Weekly challenge ends tomorrow",
            norwegian: "Ukens challenge avsluttes i morgen"
        )
        content.body = ATHLTHLocalization.choose(
            english: "You haven't completed “\(challenge.title)” yet. 24 hours remain.",
            norwegian: "Du har ikke fullført «\(challenge.title)» ennå. 24 timer igjen."
        )
        content.sound = .default
        content.threadIdentifier = "athlth.official.weekly"
        content.userInfo = ["athlthOfficialWeeklyChallengeID": challenge.id.uuidString]

        let seconds = reminder.date.timeIntervalSince(now)
        guard seconds > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: seconds,
            repeats: false
        )
        try? await center.add(
            UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: trigger
            )
        )
    }
}
