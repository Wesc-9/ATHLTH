import EventKit
import Foundation
import UserNotifications

enum CommunityGroupEventSystemActions {
    static func addToCalendar(
        event: CommunityGroupEventRecord,
        group: CommunityGroupRecord
    ) async throws {
        let store = EKEventStore()

        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store
                .requestFullAccessToEvents()
        } else {
            granted = try await withCheckedThrowingContinuation {
                continuation in

                store.requestAccess(
                    to: .event
                ) { allowed, error in
                    if let error {
                        continuation.resume(
                            throwing: error
                        )
                    } else {
                        continuation.resume(
                            returning: allowed
                        )
                    }
                }
            }
        }

        guard granted else {
            throw CommunityGroupSystemActionError
                .calendarAccessDenied
        }

        let calendarEvent = EKEvent(
            eventStore: store
        )
        calendarEvent.title = event.title
        calendarEvent.startDate = event.startsAt
        calendarEvent.endDate =
            event.endsAt ??
            event.startsAt.addingTimeInterval(
                3_600
            )
        calendarEvent.location =
            event.meetingName.isEmpty
                ? nil
                : event.meetingName
        calendarEvent.notes = [
            group.name,
            event.summary,
            event.activityConfiguration?
                .compactSummary
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        calendarEvent.calendar =
            store.defaultCalendarForNewEvents

        if event.repeatRule == "weekly" {
            let end: EKRecurrenceEnd?
            if let repeatUntil = event.repeatUntil {
                end = EKRecurrenceEnd(
                    end: repeatUntil
                )
            } else {
                end = nil
            }

            calendarEvent.addRecurrenceRule(
                EKRecurrenceRule(
                    recurrenceWith: .weekly,
                    interval: 1,
                    end: end
                )
            )
        }

        try store.save(
            calendarEvent,
            span: .thisEvent
        )
    }

    static func scheduleReminder(
        event: CommunityGroupEventRecord,
        minutesBefore: Int
    ) async throws {
        let center =
            UNUserNotificationCenter.current()

        let granted = try await center
            .requestAuthorization(
                options: [.alert, .sound, .badge]
            )

        guard granted else {
            throw CommunityGroupSystemActionError
                .notificationAccessDenied
        }

        let fireDate = event.startsAt
            .addingTimeInterval(
                -Double(minutesBefore * 60)
            )

        guard fireDate > Date() else {
            throw CommunityGroupSystemActionError
                .reminderAlreadyPassed
        }

        var components = Calendar.current
            .dateComponents(
                [
                    .year,
                    .month,
                    .day,
                    .hour,
                    .minute
                ],
                from: fireDate
            )
        components.second = 0

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body =
            "Group event starts " +
            event.startsAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
        content.sound = .default
        content.userInfo = [
            "kind": "group_event_reminder",
            "event_id": event.id.uuidString,
            "group_id":
                event.groupID.uuidString
        ]

        let request = UNNotificationRequest(
            identifier:
                "athlth-group-event-" +
                event.id.uuidString +
                "-\(minutesBefore)",
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        )

        try await center.add(request)
    }

    static func cancelReminders(
        eventID: UUID
    ) async {
        let center =
            UNUserNotificationCenter.current()
        let pending =
            await center.pendingNotificationRequests()
        let prefix =
            "athlth-group-event-" +
            eventID.uuidString +
            "-"

        let ids = pending
            .map(\.identifier)
            .filter {
                $0.hasPrefix(prefix)
            }

        center.removePendingNotificationRequests(
            withIdentifiers: ids
        )
    }
}

enum CommunityGroupSystemActionError:
    LocalizedError
{
    case calendarAccessDenied
    case notificationAccessDenied
    case reminderAlreadyPassed

    var errorDescription: String? {
        switch self {
        case .calendarAccessDenied:
            return "Calendar access is required to add this event."
        case .notificationAccessDenied:
            return "Notifications are disabled for ATHLTH."
        case .reminderAlreadyPassed:
            return "That reminder time has already passed."
        }
    }
}
