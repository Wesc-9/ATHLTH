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

    private func preferenceEnabled(_ key: String, defaultValue: Bool = true) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private func shouldDeliverSystemAlert(for item: ATHLTHNotificationItem) -> Bool {
        if item.challengeID != nil {
            return preferenceEnabled("settings.challengeNotifications")
        }

        if item.kind == .workoutCompleted {
            return preferenceEnabled("settings.workoutReminders")
        }

        if item.kind == .social {
            let eventKind = item.socialEventKind?.lowercased() ?? ""

            if eventKind == "mention" {
                return preferenceEnabled("settings.mentionNotifications")
            }

            // Group events are only created by the backend when the
            // per-group All / Important / Muted preference allows them.
            if eventKind.hasPrefix("group_") {
                return true
            }

            if eventKind.contains("message") || eventKind.contains("dm") {
                return preferenceEnabled("settings.messageNotifications")
            }

            if eventKind.contains("challenge") {
                return preferenceEnabled("settings.challengeNotifications")
            }

            return preferenceEnabled("settings.friendActivityNotifications")
        }

        return true
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
            workoutID: draft.workoutID,
            challengeID: draft.challengeID,
            backendEventID: draft.backendEventID,
            socialEventKind: draft.socialEventKind,
            socialEntityType: draft.socialEntityType,
            socialEntityID: draft.socialEntityID
        )

        items.insert(item, at: 0)
        trimIfNeeded()
        persist()

        if deliverSystemAlert, shouldDeliverSystemAlert(for: item) {
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

    func syncTrophyEvents(from unlocks: [TrophyUnlockRecord]) {
        for unlock in unlocks where unlock.unlockedAt >= activationDate {
            add(
                ATHLTHNotificationDraft(
                    eventKey: "trophy-\(unlock.stageKey)-unlocked",
                    kind: .achievement,
                    title: "Trophy unlocked",
                    message: "\(unlock.title) · \(unlock.stageTitle). Verified by \(unlock.verificationSource.title).",
                    createdAt: unlock.unlockedAt
                )
            )
        }
    }

    func syncChallengeEvents(
        from challenges: [ATHLTHChallenge],
        currentUserID: UUID
    ) {
        for challenge in challenges {
            if challenge.creatorID == currentUserID,
               challenge.createdAt >= activationDate {
                add(
                    ATHLTHNotificationDraft(
                        eventKey: "challenge-\(challenge.id.uuidString)-created",
                        kind: .social,
                        title: "Challenge created",
                        message: "\(challenge.title) is ready. Rules lock when it starts.",
                        createdAt: challenge.createdAt,
                        challengeID: challenge.id
                    ),
                    deliverSystemAlert: false
                )
            }

            let currentParticipantID = challenge.participants.first {
                $0.userID == currentUserID
            }?.id

            for attempt in challenge.attempts
            where attempt.submittedAt >= activationDate &&
                    attempt.participantID != currentParticipantID {
                add(
                    ATHLTHNotificationDraft(
                        eventKey: "challenge-\(challenge.id.uuidString)-attempt-\(attempt.id.uuidString)",
                        kind: .social,
                        title: "New challenge result",
                        message: "\(attempt.participantName) posted \(attempt.detail) in \(challenge.title).",
                        createdAt: attempt.submittedAt,
                        workoutID: attempt.sourceWorkoutID,
                        challengeID: challenge.id
                    )
                )
            }

            if challenge.status == .completed,
               let end = challenge.rules.endsAt,
               end >= activationDate {
                add(
                    ATHLTHNotificationDraft(
                        eventKey: "challenge-\(challenge.id.uuidString)-completed",
                        kind: .social,
                        title: "Challenge completed",
                        message: "\(challenge.title) has finished. View the final leaderboard.",
                        createdAt: end,
                        challengeID: challenge.id
                    )
                )
            }

            Task {
                await scheduleChallengeReminders(
                    challenge,
                    currentUserID: currentUserID
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

    func syncGearUsageAlerts(
        from gear: ProfileGearStore
    ) {
        for item in gear.items(in: .shoes)
        where gear.isActive(item) {
            guard
                let target =
                    gear.details(for: item)?
                        .replacementTargetKM,
                target > 0
            else {
                continue
            }

            let usedKM =
                gear.usageStats(for: item)
                    .totalDistanceMeters / 1_000
            let progress = usedKM / target

            for threshold in [0.80, 0.90, 1.00]
            where progress >= threshold {
                let percentage =
                    Int((threshold * 100).rounded())
                let message: String

                if threshold >= 1 {
                    message =
                        String(
                            format:
                                "%@ has reached %.0f km of your %.0f km target. Check the shoe’s condition and comfort before deciding whether to retire it.",
                            item.name,
                            usedKM,
                            target
                        )
                } else {
                    message =
                        String(
                            format:
                                "%@ has reached %.0f km of your %.0f km target. Keep an eye on wear and comfort.",
                            item.name,
                            usedKM,
                            target
                        )
                }

                add(
                    ATHLTHNotificationDraft(
                        eventKey:
                            "gear-\(item.id.uuidString)-replacement-\(percentage)",
                        kind: .system,
                        title:
                            "\(item.name) · \(percentage)% of shoe target",
                        message: message
                    ),
                    deliverSystemAlert: false
                )
            }
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
        _ = await requestSystemNotificationPermissionIfNeeded()
    }

    @discardableResult
    func requestSystemNotificationPermissionIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()

        if authorizationStatus == .notDetermined {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
            } catch {
                // The in-app notification center still works without system permission.
            }

            await refreshAuthorizationStatus()
        }

        return authorizationStatus == .authorized ||
            authorizationStatus == .provisional ||
            authorizationStatus == .ephemeral
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func reconcileSystemPreferences() async {
        await refreshAuthorizationStatus()

        guard !preferenceEnabled("settings.challengeNotifications") else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let requests: [UNNotificationRequest] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }

        let challengeRequestIDs = requests
            .map(\.identifier)
            .filter { $0.hasPrefix("challenge-") }

        if !challengeRequestIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: challengeRequestIDs)
        }
    }

    private func scheduleChallengeReminders(
        _ challenge: ATHLTHChallenge,
        currentUserID: UUID
    ) async {
        await refreshAuthorizationStatus()

        guard preferenceEnabled("settings.challengeNotifications"),
              authorizationStatus == .authorized ||
                authorizationStatus == .provisional ||
                authorizationStatus == .ephemeral,
              challenge.status != .completed,
              challenge.status != .cancelled,
              challenge.participants.contains(where: {
                  $0.userID == currentUserID &&
                  ($0.state == .creator || $0.state == .accepted)
              })
        else {
            return
        }

        let now = Date()

        let startReminder = challenge.rules.startsAt.addingTimeInterval(-3_600)
        if startReminder > now {
            let content = UNMutableNotificationContent()
            content.title = "Challenge starts in 1 hour"
            content.body = challenge.title
            content.sound = .default
            content.userInfo = [
                "athlthChallengeID": challenge.id.uuidString
            ]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: startReminder.timeIntervalSince(now),
                repeats: false
            )

            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: "challenge-\(challenge.id.uuidString)-start-1h",
                    content: content,
                    trigger: trigger
                )
            )
        }

        if let meetup = challenge.rules.meetup {
            let meetupReminder = meetup.scheduledAt.addingTimeInterval(-3_600)

            if meetupReminder > now {
                let content = UNMutableNotificationContent()
                content.title = "Meet & Train in 1 hour"
                content.body = "\(challenge.title) · \(meetup.placeName)"
                content.sound = .default
                content.userInfo = [
                    "athlthChallengeID": challenge.id.uuidString
                ]

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: meetupReminder.timeIntervalSince(now),
                    repeats: false
                )

                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(
                        identifier: "challenge-\(challenge.id.uuidString)-meetup-1h",
                        content: content,
                        trigger: trigger
                    )
                )
            }
        }

        if let endsAt = challenge.rules.endsAt {
            let endReminder = endsAt.addingTimeInterval(-86_400)

            if endReminder > now {
                let content = UNMutableNotificationContent()
                content.title = "Challenge ends tomorrow"
                content.body = challenge.title
                content.sound = .default
                content.userInfo = [
                    "athlthChallengeID": challenge.id.uuidString
                ]

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: endReminder.timeIntervalSince(now),
                    repeats: false
                )

                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(
                        identifier: "challenge-\(challenge.id.uuidString)-end-24h",
                        content: content,
                        trigger: trigger
                    )
                )
            }
        }
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
        var userInfo: [String: String] = [
            "athlthEventKey": item.eventKey,
            "athlthNotificationID": item.id.uuidString
        ]

        if let challengeID = item.challengeID {
            userInfo["athlthChallengeID"] = challengeID.uuidString
        }

        if let goalID = item.goalID {
            userInfo["athlthGoalID"] = goalID.uuidString
        }

        if let backendEventID = item.backendEventID {
            userInfo["athlthBackendEventID"] = backendEventID.uuidString
        }

        if let socialEventKind = item.socialEventKind {
            userInfo["athlthSocialEventKind"] = socialEventKind
        }

        content.userInfo = userInfo

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
