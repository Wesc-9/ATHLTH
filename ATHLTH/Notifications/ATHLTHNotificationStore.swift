import Foundation
import Supabase
import UserNotifications

/// Copy for scheduled challenge alerts. Text is resolved when iOS queues the
/// request, so the app re-schedules pending challenges if language changes.
enum ATHLTHChallengeReminderText {
    enum Reminder {
        case starting
        case meetup
        case ending
    }

    static func title(
        for reminder: Reminder,
        norwegian: Bool = ATHLTHLocalization.isNorwegian
    ) -> String {
        switch reminder {
        case .starting:
            return norwegian
                ? "Utfordringen starter om én time"
                : "Challenge starts in one hour"
        case .meetup:
            return norwegian
                ? "Fellestreningen starter om én time"
                : "Meet & Train starts in one hour"
        case .ending:
            return norwegian
                ? "Utfordringen avsluttes i morgen!"
                : "Challenge ends tomorrow!"
        }
    }

    static func message(
        for reminder: Reminder,
        challengeTitle: String,
        meetupPlace: String? = nil,
        norwegian: Bool = ATHLTHLocalization.isNorwegian
    ) -> String {
        let trimmed = challengeTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        // Short placeholder-like titles such as "Ok" should never be the
        // entire notification body. Preserve meaningful user-chosen names.
        let name = trimmed.lowercased() == "ok" || trimmed.isEmpty
            ? nil
            : String(trimmed.prefix(60)) + (trimmed.count > 60 ? "…" : "")

        switch reminder {
        case .starting:
            if let name {
                return norwegian
                    ? "«\(name)» starter snart. Sjekk detaljene og gjør deg klar."
                    : "«\(name)» starts soon. Check the details and get ready."
            }
            return norwegian
                ? "Start om én time. Åpne utfordringen for å se detaljene."
                : "Starts in one hour. Open the challenge to see the details."
        case .meetup:
            let place = meetupPlace?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            if !place.isEmpty {
                return norwegian
                    ? "Oppmøte: \(place). Se detaljene før start."
                    : "Meeting point: \(place). Check the details before starting."
            }
            return norwegian
                ? "Sjekk møtested og detaljer før fellestreningen."
                : "Check the meeting point and details before training."
        case .ending:
            if let name {
                return norwegian
                    ? "«\(name)»: 24 timer igjen. Sjekk fremdriften før fristen."
                    : "«\(name)»: 24 hours left. Check your progress before the deadline."
            }
            return norwegian
                ? "Du har 24 timer igjen. Sjekk fremdriften din før utfordringen avsluttes."
                : "24 hours left. Check your progress before the challenge ends."
        }
    }
}

/// Pure policy for low-noise, once-daily in-app reminders.
enum ATHLTHDailyCheckInReminderPolicy {
    static func shouldShow(
        enabled: Bool, completed: Bool,
        issuedToday: Bool, now: Date,
        minuteOfDay: Int = ATHLTHDailyCheckInReminderScheduler.defaultMinuteOfDay,
        calendar: Calendar = .current
    ) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let currentMinuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return enabled && !completed && !issuedToday &&
            currentMinuteOfDay >=
                ATHLTHDailyCheckInReminderScheduler.normalizedMinuteOfDay(minuteOfDay)
    }
}

@MainActor
final class ATHLTHNotificationStore: ObservableObject {
    @Published private(set) var items: [ATHLTHNotificationItem] = []
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastAccountSyncError: String?
    @Published private(set) var lastAccountSyncAt: Date?

    private let activationDate: Date
    private var accountID: UUID?
    private var tombstones: [ATHLTHNotificationTombstone] = []
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false

    init() {
        activationDate = Self.loadOrCreateActivationDate()
        // A device-global JSON file must never appear for the wrong account.
        // Switch to the verified, account-scoped cache during app login.
        items = []
        Task {
            await refreshAuthorizationStatus()
        }
    }

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        syncTask?.cancel()
        syncTask = nil
        accountID = userID
        lastAccountSyncError = nil
        lastAccountSyncAt = nil

        guard let userID else {
            items = []
            tombstones = []
            return
        }
        if let cached = Self.loadAccountSnapshot(userID: userID) {
            items = Array(cached.items.filter {
                $0.kind != .workoutCompleted
            }.prefix(250))
            tombstones = cached.tombstones
        } else if Self.verifiedLegacyAccountID() == userID {
            // The legacy file was device-global and could contain events
            // from multiple historical accounts. Only migrate entries with
            // an explicit verified account identifier; server-backed inbox
            // events are reloaded by SocialStore for their true recipient.
            items = Self.loadItems().filter { item in
                item.kind != .workoutCompleted &&
                item.eventKey.localizedCaseInsensitiveContains(
                    userID.uuidString
                )
            }
            tombstones = []
            persist(scheduleRemote: false)
        } else {
            items = []
            tombstones = []
        }
        scheduleAccountSync()
    }

    func scheduleAccountSync() {
        guard accountID != nil else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(550)) }
            catch { return }
            await self?.refreshAccountNotifications()
        }
    }

    func refreshAccountNotifications() async {
        guard !isSyncing, let userID = accountID else { return }
        guard SupabaseEnvironment.client.auth.currentUser?.id == userID else {
            lastAccountSyncError = ATHLTHLocalization.choose(
                english: "Notification sync awaits verified sign-in.",
                norwegian: "Varselsynkronisering venter på bekreftet innlogging."
            )
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        let original = ATHLTHAccountNotificationSnapshot(
            items: items, tombstones: tombstones
        )
        do {
            let cloud = try await ATHLTHAccountNotificationSyncService.reconcile(
                accountID: userID, local: original
            )
            guard !Task.isCancelled, accountID == userID else { return }
            // Preserve read/dismiss actions performed locally during the
            // network request; the next sync will publish those changes.
            let merged = ATHLTHAccountNotificationSnapshot.merged(
                .init(items: items, tombstones: tombstones), cloud
            )
            items = Array(merged.items.prefix(250))
            tombstones = merged.tombstones
            persist(scheduleRemote: false)
            lastAccountSyncAt = Date()
            lastAccountSyncError = nil
        } catch is CancellationError {
            return
        } catch {
            guard accountID == userID else { return }
            lastAccountSyncError = ATHLTHLocalization.choose(
                english: "Notifications are saved locally. Account sync will retry.",
                norwegian: "Varsler er lagret lokalt. Kontosynkroniseringen prøver igjen."
            )
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
             "message_request_accepted",
             "workout_invite",
             "arena_invite",
             "arena_chat",
             "arena_replacement",
             "arena_round":
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

            if eventKind.hasPrefix("arena_") {
                return eventKind == "arena_chat"
                    ? preferenceEnabled("settings.messageNotifications")
                    : preferenceEnabled("settings.challengeNotifications")
            }

            if eventKind == "mention" {
                return preferenceEnabled("settings.mentionNotifications")
            }

            // Group events are only created by the backend when the
            // per-group All / Important / Muted preference allows them.
            if eventKind.hasPrefix("group_") {
                return true
            }

            if eventKind == "workout_invite" {
                return preferenceEnabled("settings.messageNotifications")
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
        // Transient notification drafts can still be used in preview/tests
        // before authentication. Only verified account caches persist/upload.
        guard !tombstones.contains(where: {
            $0.item.eventKey == draft.eventKey
        }) else { return }
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

    /// Goal measurement reminders live in Activity even when iOS permission
    /// is declined. The scheduled device alert is handled separately so
    /// reopening ATHLTH does not cause a duplicate push/banner.
    func reconcileBodyGoalCheckIns(
        goals: [ATHLTHGoal], accountID: UUID,
        profile: ATHLTHTrainingProfile, now: Date = Date()
    ) {
        let prefix = "body-goal-checkin."
        let dueByGoal: [UUID: Date] = Dictionary(
            uniqueKeysWithValues: goals.compactMap { goal in
                ATHLTHBodyGoalCheckInPolicy.dueUnmeasuredPeriod(
                    goal: goal, profile: profile, now: now
                ).map { (goal.id, $0) }
            }
        )
        let validEventKeys = Set(dueByGoal.map { id, due in
            ATHLTHBodyGoalCheckInPolicy.eventKey(
                accountID: accountID, goalID: id, due: due
            )
        })
        let before = items.count
        items.removeAll { item in
            guard item.eventKey.hasPrefix(prefix) else { return false }
            // Do not leak another account's private goal reminder.
            guard item.eventKey.hasPrefix(prefix + accountID.uuidString + ".")
            else { return true }
            // Keep past read entries, but never leave a stale unread badge
            // once the check-in was completed or the goal was disabled.
            return item.isUnread && !validEventKeys.contains(item.eventKey)
        }
        if before != items.count { persist() }

        for (goalID, due) in dueByGoal {
            add(ATHLTHNotificationDraft(
                eventKey: ATHLTHBodyGoalCheckInPolicy.eventKey(
                    accountID: accountID, goalID: goalID, due: due
                ),
                kind: .system,
                title: ATHLTHLocalization.choose(
                    english: "Time for a goal check-in",
                    norwegian: "Tid for en målinnsjekk"
                ),
                message: ATHLTHLocalization.choose(
                    english: "Record a new measurement to track your progress.",
                    norwegian: "Registrer en ny måling for å følge utviklingen."
                ),
                createdAt: now,
                goalID: goalID,
                socialEventKind: "body_goal_checkin"
            ), deliverSystemAlert: false)
        }
    }

    /// One transient in-app reminder per local day. This intentionally does
    /// not schedule an iOS push/alert or repeatedly resurrect a dismissed
    /// notification. Only the user can enable it in ATHLTH Settings.
    func reconcileDailyCheckIn(
        enabled: Bool,
        accountID: UUID,
        completed: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        let reminderMinuteOfDay = defaults.object(
            forKey: "settings.dailyCheckInReminderMinuteOfDay"
        ) as? Int ?? ATHLTHDailyCheckInReminderScheduler.defaultMinuteOfDay
        let prefix = "insights.daily-check-in."
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        let dateKey = String(format: "%04d-%02d-%02d",
            day.year ?? 0, day.month ?? 0, day.day ?? 0)
        let eventKey = prefix + accountID.uuidString + "." + dateKey
        // All old reminders are stale. Switching accounts or opting out also
        // clears their unread badge, but leaves other notification types alone.
        let previousCount = items.count
        items.removeAll {
            $0.kind == .dailyCheckIn &&
                (!enabled || completed || $0.eventKey != eventKey)
        }
        if items.count != previousCount { persist() }

        // In-app Activity and the system notification share the same
        // account/day key. Future alerts remain queued even when ATHLTH
        // is closed; today's alert is cancelled after a completed check-in.
        Task {
            await ATHLTHDailyCheckInReminderScheduler.reconcile(
                enabled: enabled,
                accountID: accountID,
                completedToday: completed,
                now: now,
                minuteOfDay: reminderMinuteOfDay,
                calendar: calendar
            )
        }

        let issuedKey = "insights.daily-check-in.last-issued." + accountID.uuidString
        guard ATHLTHDailyCheckInReminderPolicy.shouldShow(
            enabled: enabled, completed: completed,
            issuedToday: defaults.string(forKey: issuedKey) == dateKey ||
                items.contains(where: { $0.eventKey == eventKey }),
            now: now, minuteOfDay: reminderMinuteOfDay,
            calendar: calendar
        ) else { return }

        add(ATHLTHNotificationDraft(
            eventKey: eventKey,
            kind: .dailyCheckIn,
            title: ATHLTHLocalization.choose(
                english: "How are you feeling today?",
                norwegian: "Hvordan føler du deg i dag?"),
            message: ATHLTHLocalization.choose(
                english: "A short, optional check-in helps personalize today's training advice.",
                norwegian: "En kort, valgfri innsjekk gjør dagens treningsråd mer personlige."),
            createdAt: now
        ), deliverSystemAlert: false)
        defaults.set(dateKey, forKey: issuedKey)
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
                        norwegian: "Nytt prestasjonsmerke låst opp"
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
            // Cancelled/unaccepted invitations are never competitions.
            // Do not synthesize old result/completion alerts for them.
            guard challenge.scoringStartDate != nil,
                  challenge.status != .cancelled,
                  !challenge.expiredWithoutOpponent() else {
                removeUncontestedChallengeAlerts(challenge.id)
                continue
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
                        kind: .challenge,
                        title: ATHLTHLocalization.choose(
                            english: "New challenge result",
                            norwegian: "Nytt resultat i utfordringen"
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
                            norwegian: "Utfordring fullført"
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

        for index in items.indices where items[index].readAt == nil &&
            !isMessageInboxOwned(items[index]) {
            items[index].readAt = now
            changed = true
        }

        if changed {
            persist()
        }
    }

    func delete(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        // Do not actually delete the cloud record. A tombstone makes the
        // dismissal permanent on all devices, even after an offline reimport.
        tombstones.append(.init(item: item, deletedAt: Date()))
        items.removeAll { $0.eventKey == item.eventKey }
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
                            $0.hasPrefix("challenge-") ||
                            $0.hasPrefix(OfficialWeeklyChallengeReminderPolicy.identifierPrefix)
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

    private func removeUncontestedChallengeAlerts(_ challengeID: UUID) {
        let prefix = "challenge-\(challengeID.uuidString)-"
        let outdated = items.filter {
            $0.challengeID == challengeID &&
            $0.kind == .challenge
        }
        if !outdated.isEmpty {
            items.removeAll {
                $0.challengeID == challengeID &&
                $0.kind == .challenge
            }
            persist()
        }

        let reminderIDs = [
            prefix + "start-1h",
            prefix + "meetup-1h",
            prefix + "end-24h",
            prefix + "completed"
        ]
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: reminderIDs)
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
              challenge.scoringStartDate != nil,
              !challenge.expiredWithoutOpponent(),
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
            content.title = ATHLTHChallengeReminderText.title(for: .starting)
            content.body = ATHLTHChallengeReminderText.message(
                for: .starting,
                challengeTitle: challenge.title
            )
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
                content.title = ATHLTHChallengeReminderText.title(for: .meetup)
                content.body = ATHLTHChallengeReminderText.message(
                    for: .meetup,
                    challengeTitle: challenge.title,
                    meetupPlace: meetup.placeName
                )
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
                content.title = ATHLTHChallengeReminderText.title(for: .ending)
                content.body = ATHLTHChallengeReminderText.message(
                    for: .ending,
                    challengeTitle: challenge.title
                )
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

    private func persist(scheduleRemote: Bool = true) {
        guard let userID = accountID,
              let url = Self.accountItemsURL(userID: userID) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(
                ATHLTHAccountNotificationSnapshot(
                    items: items, tombstones: tombstones
                )
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        if scheduleRemote { scheduleAccountSync() }
    }

    private static func loadAccountSnapshot(
        userID: UUID
    ) -> ATHLTHAccountNotificationSnapshot? {
        guard let url = accountItemsURL(userID: userID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(
            ATHLTHAccountNotificationSnapshot.self, from: data
        )
    }

    private static func accountItemsURL(userID: UUID) -> URL? {
        itemsURL?.deletingLastPathComponent()
            .appendingPathComponent(
                "notifications-\(userID.uuidString.lowercased()).json",
                isDirectory: false
            )
    }

    private static func verifiedLegacyAccountID() -> UUID? {
        guard let data = UserDefaults.standard.data(
            forKey: "session.verifiedOfflineProfile.v1"
        ),
              let profile = try? JSONDecoder().decode(
                UserProfile.self, from: data
              )
        else { return nil }
        return profile.userID
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
