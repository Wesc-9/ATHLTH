import Foundation
import UserNotifications

@MainActor
final class ATHLTHNotificationStore: ObservableObject {
    @Published private(set) var items: [ATHLTHNotificationItem] = []
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let activationDate: Date

    init() {
        activationDate = Self.loadOrCreateActivationDate()

        // Raw workout-completion rows are activity history, not useful
        // notifications. Purge legacy rows from older builds on first load.
        let loadedItems = Self.loadItems()
        items = loadedItems.filter {
            $0.kind != .workoutCompleted
        }

        if items.count != loadedItems.count {
            persist()
        }

        Task {
            await refreshAuthorizationStatus()
        }
    }

    var unreadCount: Int {
        items.filter(\.isUnread).count
    }

    /// Direct-message events belong to the Messages inbox. Keeping them out of
    /// the bell prevents one request/message from producing two unread badges.
    var notificationCenterItems: [ATHLTHNotificationItem] {
        items.filter {
            $0.kind != .workoutCompleted &&
            !isMessageInboxOwned($0)
        }
    }

    var notificationCenterUnreadCount: Int {
        notificationCenterItems.filter(\.isUnread).count
    }

    private func isMessageInboxOwned(
        _ item: ATHLTHNotificationItem
    ) -> Bool {
        guard item.kind == .social else { return false }

        switch item.socialEventKind?.lowercased() {
        case "message",
             "message_request",
             "message_request_accepted":
            return true
        default:
            return false
        }
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

        if item.kind == .challenge {
            return preferenceEnabled("settings.challengeNotifications")
        }

        if item.kind == .workoutCompleted {
            return false
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
        if let index = items.firstIndex(
            where: { $0.eventKey == draft.eventKey }
        ) {
            var changed = false

            if items[index].groupID == nil,
               let groupID = draft.groupID {
                items[index].groupID = groupID
                changed = true
            }

            if items[index].socialEntityType == nil,
               let value = draft.socialEntityType {
                items[index].socialEntityType = value
                changed = true
            }

            if items[index].socialEntityID == nil,
               let value = draft.socialEntityID {
                items[index].socialEntityID = value
                changed = true
            }

            if items[index].readAt == nil,
               let readAt = draft.readAt {
                items[index].readAt = readAt
                changed = true
            }

            if changed {
                persist()
            }
            return
        }

        let item = ATHLTHNotificationItem(
            eventKey: draft.eventKey,
            kind: draft.kind,
            title: draft.title,
            message: draft.message,
            createdAt: draft.createdAt,
            readAt: draft.readAt,
            goalID: draft.goalID,
            workoutID: draft.workoutID,
            challengeID: draft.challengeID,
            backendEventID: draft.backendEventID,
            socialEventKind: draft.socialEventKind,
            socialEntityType: draft.socialEntityType,
            socialEntityID: draft.socialEntityID,
            groupID: draft.groupID
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
                    methodText = ATHLTHLocalization.choose(
                        english: "Verified from Apple Health.",
                        norwegian: "Verifisert fra Apple Health."
                    )
                case .automaticATHLTH:
                    methodText = ATHLTHLocalization.choose(
                        english: "Verified from your ATHLTH training.",
                        norwegian: "Verifisert fra treningen din i ATHLTH."
                    )
                case .manual:
                    methodText = ATHLTHLocalization.choose(
                        english: "Marked complete manually.",
                        norwegian: "Markert som fullført manuelt."
                    )
                case nil:
                    methodText = ATHLTHLocalization.choose(
                        english: "Milestone completed.",
                        norwegian: "Delmål fullført."
                    )
                }

                add(
                    ATHLTHNotificationDraft(
                        eventKey: "goal-\(goal.id.uuidString)-milestone-\(milestone.id.uuidString)-complete",
                        kind: .milestoneReached,
                        title: ATHLTHLocalization.choose(
                            english: "Milestone reached",
                            norwegian: "Milepæl nådd"
                        ),
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
                        title: ATHLTHLocalization.choose(
                            english: "Goal completed",
                            norwegian: "Mål fullført"
                        ),
                        message: ATHLTHLocalization.format(
                            english: "You reached %@.",
                            norwegian: "Du nådde målet %@.",
                            goal.title
                        ),
                        createdAt: completedAt,
                        goalID: goal.id
                    )
                )
            }
        }
    }

    func syncTrophyEvents(from unlocks: [TrophyUnlockRecord]) {
        for unlock in unlocks where unlock.unlockedAt >= activationDate {
            let title =
                unlock.isPrestigeTrophy
                    ? ATHLTHLocalization.choose(
                        english: "New trophy unlocked",
                        norwegian: "Ny pokal låst opp"
                    )
                    : ATHLTHLocalization.choose(
                        english: "New achievement unlocked",
                        norwegian: "Ny achievement låst opp"
                    )

            let message =
                ATHLTHLocalization.format(
                    english:
                        "%@ · %@. Tap to reveal.",
                    norwegian:
                        "%@ · %@. Trykk for å åpne.",
                    unlock.title,
                    unlock.stageTitle
                )

            add(
                ATHLTHNotificationDraft(
                    eventKey: "trophy-\(unlock.stageKey)-unlocked",
                    kind: .achievement,
                    title: title,
                    message: message,
                    createdAt: unlock.unlockedAt
                ),
                deliverSystemAlert: false
            )
        }
    }

    func syncChallengeEvents(
        from challenges: [ATHLTHChallenge],
        currentUserID: UUID
    ) {
        for challenge in challenges {
            let currentParticipantID = challenge.participants.first {
                $0.userID == currentUserID
            }?.id

            for attempt in challenge.attempts
            where attempt.submittedAt >= activationDate &&
                    attempt.participantID != currentParticipantID {
                add(
                    ATHLTHNotificationDraft(
                        eventKey: "challenge-\(challenge.id.uuidString)-attempt-\(attempt.id.uuidString)",
                        kind: .challenge,
                        title: ATHLTHLocalization.choose(
                            english: "New challenge result",
                            norwegian: "Nytt challenge-resultat"
                        ),
                        message: ATHLTHLocalization.format(
                            english: "%@ posted %@ in %@.",
                            norwegian: "%@ registrerte %@ i %@.",
                            attempt.participantName,
                            attempt.detail,
                            challenge.title
                        ),
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
                        kind: .challenge,
                        title: ATHLTHLocalization.choose(
                            english: "Challenge completed",
                            norwegian: "Challenge fullført"
                        ),
                        message: ATHLTHLocalization.format(
                            english: "%@ has finished. View the final leaderboard.",
                            norwegian: "%@ er ferdig. Se den endelige resultatlisten.",
                            challenge.title
                        ),
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
        // Completion belongs in workout history / Activity Center. Keep this
        // hook so existing call sites stay stable, but do not create a bell
        // notification just because HealthKit/Watch finished a workout.
        _ = result
    }

    func recordStrengthWorkout(_ workout: StrengthWorkoutLog) {
        // Strength completion is handled by workout history and post-workout
        // review. Notifications are reserved for meaningful follow-up such as
        // PRs, milestones, challenges or issues that need attention.
        _ = workout
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
                        ATHLTHLocalization.format(
                            english:
                                "%@ has reached %.0f km of your %.0f km target. Check the shoe’s condition and comfort before deciding whether to retire it.",
                            norwegian:
                                "%@ har nådd %.0f km av målet på %.0f km. Sjekk slitasje og komfort før du bestemmer om skoene bør byttes ut.",
                            item.name,
                            usedKM,
                            target
                        )
                } else {
                    message =
                        ATHLTHLocalization.format(
                            english:
                                "%@ has reached %.0f km of your %.0f km target. Keep an eye on wear and comfort.",
                            norwegian:
                                "%@ har nådd %.0f km av målet på %.0f km. Følg med på slitasje og komfort.",
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
                            ATHLTHLocalization.format(
                                english: "%@ · %d%% of shoe target",
                                norwegian: "%@ · %d%% av skomålet",
                                item.name,
                                percentage
                            ),
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

        let allowed =
            authorizationStatus == .authorized ||
            authorizationStatus == .provisional ||
            authorizationStatus == .ephemeral

        if allowed {
            // Alert permission and APNs registration are separate. Keep them
            // coupled from the user's point of view so enabling device alerts
            // always repairs/registers the backend push destination as well.
            APNsPushManager.shared
                .ensureSystemRegistration(
                    force: true
                )
            await APNsPushManager.shared
                .syncCurrentToken()
        }

        return allowed
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
        let challengeRequestIDs: [String] =
            await withCheckedContinuation {
                (
                    continuation:
                        CheckedContinuation<[String], Never>
                ) in

                center.getPendingNotificationRequests {
                    requests in

                    let identifiers = requests
                        .map(\.identifier)
                        .filter {
                            $0.hasPrefix("challenge-")
                        }

                    continuation.resume(
                        returning: identifiers
                    )
                }
            }

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
            content.title = ATHLTHLocalization.choose(
                english: "Challenge starts in 1 hour",
                norwegian: "Challenge starter om 1 time"
            )
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
                content.title = ATHLTHLocalization.choose(
                    english: "Meet & Train in 1 hour",
                    norwegian: "Meet & Train om 1 time"
                )
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
                content.title = ATHLTHLocalization.choose(
                    english: "Challenge ends tomorrow",
                    norwegian: "Challenge avsluttes i morgen"
                )
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

        if let groupID = item.groupID {
            userInfo["athlthGroupID"] = groupID.uuidString
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
