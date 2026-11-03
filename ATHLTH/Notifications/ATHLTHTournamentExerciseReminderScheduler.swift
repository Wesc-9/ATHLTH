import Foundation
import UserNotifications

/// Upcoming Arena exercises use their own notification namespace, never
/// removing training reminders, community messages or other alerts.
/// Local notifications are optional and follow existing challenge settings.
enum ATHLTHTournamentExerciseReminderPolicy {
    static let prefix = "athlth.arena.exercise.reminder."
    static let maxExerciseCount = 12

    struct Reminder: Equatable {
        let id: String
        let slotID: UUID
        let tournamentID: UUID
        let title: String
        let tournamentTitle: String
        let kind: Kind
        let fireAt: Date

        enum Kind { case opens, deadline }
    }

    static func identifier(
        accountID: UUID, slotID: UUID, kind: Reminder.Kind, date: Date
    ) -> String {
        let tag = kind == .opens ? "start" : "deadline"
        let minute = Int(date.timeIntervalSince1970 / 60)
        return prefix + accountID.uuidString + "." +
            slotID.uuidString + "." + tag + "." + String(minute)
    }

    static func reminders(
        for items: [ATHLTHTournamentCalendarItem],
        accountID: UUID, now: Date = Date()
    ) -> [Reminder] {
        let upcoming = items.filter { $0.deadlineAt > now }
            .sorted {
                $0.deadlineAt == $1.deadlineAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.deadlineAt < $1.deadlineAt
            }
            .prefix(maxExerciseCount)
        var notifications: [Reminder] = []
        for item in upcoming {
            if item.opensAt > now {
                notifications.append(Reminder(
                    id: identifier(accountID: accountID, slotID: item.id,
                                   kind: .opens, date: item.opensAt),
                    slotID: item.id, tournamentID: item.tournamentID,
                    title: item.exerciseTitle,
                    tournamentTitle: item.tournamentTitle,
                    kind: .opens, fireAt: item.opensAt
                ))
            }
            // Avoid a deadline reminder for a still-unopened exercise.
            // For short windows use roughly the last quarter, while a long
            // window can notify no earlier than 24 hours before closure.
            let window = max(0, item.deadlineAt.timeIntervalSince(item.opensAt))
            let lead = min(86_400, max(900, window * 0.25))
            let deadlineReminder = item.deadlineAt.addingTimeInterval(-lead)
            if deadlineReminder > now && deadlineReminder > item.opensAt {
                notifications.append(Reminder(
                    id: identifier(accountID: accountID, slotID: item.id,
                                   kind: .deadline, date: deadlineReminder),
                    slotID: item.id, tournamentID: item.tournamentID,
                    title: item.exerciseTitle,
                    tournamentTitle: item.tournamentTitle,
                    kind: .deadline, fireAt: deadlineReminder
                ))
            }
        }
        return notifications
    }
}

@MainActor
enum ATHLTHTournamentExerciseReminderScheduler {
    static func reconcile(
        items: [ATHLTHTournamentCalendarItem],
        accountID: UUID,
        now: Date = Date()
    ) async {
        let center = UNUserNotificationCenter.current()
        let current = await center.pendingNotificationRequests()
        let owned = current.map(\.identifier).filter {
            $0.hasPrefix(ATHLTHTournamentExerciseReminderPolicy.prefix)
        }

        let enabled = UserDefaults.standard.object(
            forKey: "settings.challengeNotifications"
        ).map {
            _ in UserDefaults.standard.bool(
                forKey: "settings.challengeNotifications"
            )
        } ?? true
        let status = await center.notificationSettings().authorizationStatus
        let permitted = status == .authorized ||
            status == .provisional || status == .ephemeral
        let wanted = enabled && permitted
            ? ATHLTHTournamentExerciseReminderPolicy.reminders(
                for: items, accountID: accountID, now: now
            ) : []
        let keys = Set(wanted.map(\.id))
        let obsolete = owned.filter { !keys.contains($0) }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }
        guard enabled, permitted else { return }
        let existing = Set(owned).subtracting(obsolete)
        for event in wanted where !existing.contains(event.id) {
            let content = UNMutableNotificationContent()
            content.title = event.kind == .opens
                ? ATHLTHLocalization.choose(
                    english: "Arena exercise is open",
                    norwegian: "Ny Arena-øvelse er klar"
                )
                : ATHLTHLocalization.choose(
                    english: "Arena exercise deadline is approaching",
                    norwegian: "Fristen for Arena-øvelsen nærmer seg"
                )
            content.body = event.title + " · " + event.tournamentTitle
            content.sound = .default
            content.threadIdentifier = "athlth.arena.tournament"
            content.userInfo = [
                "athlth_kind": "tournament_exercise",
                "athlthTournamentID": event.tournamentID.uuidString,
                "athlthTournamentSlotID": event.slotID.uuidString,
                "athlthAccountID": accountID.uuidString
            ]
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: event.fireAt
                ),
                repeats: false
            )
            try? await center.add(UNNotificationRequest(
                identifier: event.id,
                content: content,
                trigger: trigger
            ))
        }
    }
}
