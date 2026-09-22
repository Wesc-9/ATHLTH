import Foundation
import UserNotifications

@MainActor
final class ATHLTHNotificationStore: ObservableObject {
    @Published private(set) var items: [ATHLTHNotificationItem] = []
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let activationDate: Date

    init() {
        items = Self.loadItems()
        activationDate = Self.loadOrCreateActivationDate()
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

    func syncGoalEvents(from goals: [ATHLTHGoal]) {
        for goal in goals {
            for milestone in goal.milestones {
                guard let completedAt = milestone.completedAt,
                      completedAt >= activationDate
                else {
                    continue
                }

                let methodText: String
                switch milestone.completionMethod {
                case .automaticAppleHealth:
                    methodText = "Verified from Apple Health."
                case .automaticATHLTH:
                    methodText = "Verified from your ATHLTH training."
                case .manual:
                    methodText = "Marked complete manually."
                case nil:
                    methodText = "Milestone completed."
                }

                add(
                    ATHLTHNotificationDraft(
                        eventKey: "goal-\(goal.id.uuidString)-milestone-\(milestone.id.uuidString)-complete",
                        kind: .milestoneReached,
                        title: "Milestone reached",
                        message: "\(milestone.title) · \(goal.title). \(methodText)",
                        createdAt: completedAt,
                        goalID: goal.id
                    )
                )
            }

            if let completedAt = goal.completedAt,
               completedAt >= activationDate {
                add(
                    ATHLTHNotificationDraft(
                        eventKey: "goal-\(goal.id.uuidString)-complete",
                        kind: .goalCompleted,
                        title: "Goal completed",
                        message: "You reached \(goal.title).",
                        createdAt: completedAt,
                        goalID: goal.id
                    )
                )
            }
        }
    }

    func recordWatchWorkout(_ result: WatchWorkoutResult) {
        let distanceText: String
        if result.distanceMeters >= 1 {
            distanceText = String(format: " · %.2f km", result.distanceMeters / 1_000)
        } else {
            distanceText = ""
        }

        add(
            ATHLTHNotificationDraft(
                eventKey: "watch-workout-\(result.id.uuidString)-complete",
                kind: .workoutCompleted,
                title: "\(result.kind.title) completed",
                message: "\(Self.durationText(result.duration))\(distanceText) · \(Int(result.activeCalories.rounded())) active kcal",
                createdAt: result.endedAt,
                workoutID: result.id
            )
        )
    }

    func recordStrengthWorkout(_ workout: StrengthWorkoutLog) {
        guard workout.captureDevice == .iPhone,
              let endedAt = workout.endedAt
        else {
            return
        }

        let volumeText = workout.totalVolumeKilograms > 0
            ? " · \(Self.kilogramsText(workout.totalVolumeKilograms)) kg volume"
            : ""

        add(
            ATHLTHNotificationDraft(
                eventKey: "strength-workout-\(workout.id.uuidString)-complete",
                kind: .workoutCompleted,
                title: "Strength workout completed",
                message: "\(workout.title) · \(workout.totalCompletedSets) sets\(volumeText)",
                createdAt: endedAt,
                workoutID: workout.id
            )
        )
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

    private static func loadOrCreateActivationDate() -> Date {
        let defaults = UserDefaults.standard
        let key = "athlth.notifications.activationDate"

        if let existing = defaults.object(forKey: key) as? Date {
            return existing
        }

        let now = Date()
        defaults.set(now, forKey: key)
        return now
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int((duration / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes) min"
    }

    private static func kilogramsText(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 {
            return String(Int(value.rounded()))
        }

        return String(format: "%.1f", value)
    }

    private static var itemsURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("notifications-v1.json", isDirectory: false)
    }
}
