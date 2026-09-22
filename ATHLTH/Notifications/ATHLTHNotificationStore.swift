import Foundation
import UserNotifications

@MainActor
final class ATHLTHNotificationStore: ObservableObject {
    @Published private(set) var items: [ATHLTHNotificationItem] = []
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init() {
        items = Self.loadItems()
        Task {
            await refreshAuthorizationStatus()
        }
    }

    var unreadCount: Int {
        items.filter(\.isUnread).count
    }

    func add(_ draft: ATHLTHNotificationDraft, deliverSystemAlert: Bool = true) {
        guard !items.contains(where: { $0.eventKey == draft.eventKey }) else {
            return
        }

        let item = ATHLTHNotificationItem(
            eventKey: draft.eventKey,
            kind: draft.kind,
            title: draft.title,
            message: draft.message,
            createdAt: draft.createdAt,
            goalID: draft.goalID,
            workoutID: draft.workoutID
        )

        items.insert(item, at: 0)
        trimIfNeeded()
        persist()

        if deliverSystemAlert {
            Task {
                await deliverLocalNotification(for: item)
            }
        }
    }

    func add(contentsOf drafts: [ATHLTHNotificationDraft]) {
        for draft in drafts {
            add(draft)
        }
    }

    func markRead(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].readAt == nil
        else {
            return
        }

        items[index].readAt = Date()
        persist()
    }

    func markAllRead() {
        let now = Date()
        var changed = false

        for index in items.indices where items[index].readAt == nil {
            items[index].readAt = now
            changed = true
        }

        if changed {
            persist()
        }
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func requestSystemNotificationPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            // The in-app notification center still works without system permission.
        }

        await refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func deliverLocalNotification(for item: ATHLTHNotificationItem) async {
        await refreshAuthorizationStatus()

        guard authorizationStatus == .authorized ||
                authorizationStatus == .provisional ||
                authorizationStatus == .ephemeral
        else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.message
        content.sound = .default
        content.userInfo = [
            "athlthEventKey": item.eventKey,
            "athlthNotificationID": item.id.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: item.eventKey,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func trimIfNeeded() {
        if items.count > 250 {
            items = Array(items.prefix(250))
        }
    }

    private func persist() {
        guard let url = Self.itemsURL else { return }

        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private static func loadItems() -> [ATHLTHNotificationItem] {
        guard let url = itemsURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                [ATHLTHNotificationItem].self,
                from: data
              )
        else {
            return []
        }

        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private static var itemsURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("notifications-v1.json", isDirectory: false)
    }
}
