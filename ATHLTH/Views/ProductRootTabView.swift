import Charts
import Combine
import MapKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// Explicit foreground-only delayed launch. A phone workout must never
/// begin by itself while the user is in another app or after a relaunch.
private struct ATHLTHHomeDeferredPhoneStartSheet: View {
    let workoutTitle: String
    let onStart: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var startAt: Date

    init(workoutTitle: String, delaySeconds: TimeInterval,
         onStart: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.workoutTitle = workoutTitle
        self.onStart = onStart
        self.onCancel = onCancel
        _startAt = State(initialValue: Date().addingTimeInterval(delaySeconds))
    }
    @State private var started = false
    @State private var wasBackgrounded = false

    private func startIfEligible() {
        guard !started, !wasBackgrounded, scenePhase == .active else { return }
        started = true
        dismiss()
        onStart()
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "timer")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(ATHLTHLocalization.choose(
                english: "Start workout shortly",
                norwegian: "Start økten om litt"
            ))
            .font(.title3.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(workoutTitle)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(2)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text("\(max(0, Int(ceil(startAt.timeIntervalSince(timeline.date))))) s")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            Button {
                startIfEligible()
            } label: {
                Text(ATHLTHLocalization.choose(
                    english: "Start now", norwegian: "Start nå"
                ))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)

            Button {
                onCancel()
                dismiss()
            } label: {
                Text(ATHLTHLocalization.choose(
                    english: "Cancel countdown",
                    norwegian: "Avbryt nedtellingen"
                ))
            }
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
        .presentationDetents([.height(370)])
        .presentationDragIndicator(.visible)
        .task {
            while !Task.isCancelled, Date() < startAt {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            startIfEligible()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                wasBackgrounded = true
                dismiss()
            }
        }
    }
}

struct ProductRootTabView: View {
    @ObservedObject private var pushManager = APNsPushManager.shared
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var goalAccountSync: ATHLTHGoalAccountSyncStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var notifications:
        ATHLTHNotificationStore
    @EnvironmentObject private var messaging:
        MessagingStore
    @EnvironmentObject private var health:
        HealthKitManager
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: Int
    @SceneStorage("athlth.root.openTab") private var persistedSelectedTab = 0
    @SceneStorage("athlth.root.openTabAccount") private var persistedTabAccount = ""
    @State private var hasRestoredSelectedTab = false
    // A force-quit must not turn an actively edited plan into a Home launch.
    // Do this once per signed-in account, never for a manually closed draft.
    @State private var routedInterruptedPlanAccount: UUID?
    @State private var trainNavigationRequest:
        ATHLTHTrainNavigationRequest?
    @State private var showingDailyCheckInFromNotification = false
    @State private var deferredTabReminderTask: Task<Void, Never>?
    @State private var showingCoachFromDock = false
    @State private var showingSideMenu = false
    @State private var sideMenuModalDestination: ATHLTHSideMenuDestination?
    @State private var sideMenuUtilityDestination: ATHLTHSideMenuDestination?
    @State private var pushedWorkoutInviteID: UUID?
    @State private var sideMenuFullScreenDestination: ATHLTHSideMenuDestination?
    @State private var friendShareToast: ATHLTHFriendQuickShareKind?
    @State private var friendShareToastDismissTask: Task<Void, Never>?

    /// The push delegate can fire before sign-in or before the tab hierarchy
    /// is mounted. Never consume the route until the intended account is ready.
    private func openPendingWorkoutInviteIfNeeded() {
        guard session.signedIn,
              let route = pushManager.pendingWorkoutInviteNotification,
              route.isForAccount(session.profile.userID)
        else { return }

        pushedWorkoutInviteID = route.workoutSessionID
        showingSideMenu = false
        sideMenuModalDestination = nil
        sideMenuFullScreenDestination = nil
        sideMenuUtilityDestination = .inbox
        pushManager.clearPendingWorkoutInviteNotification()
    }

    private func openPendingDailyCheckInIfNeeded() {
        guard pushManager.pendingDailyCheckInAccountID ==
                session.profile.userID else { return }
        pushManager.clearPendingDailyCheckIn()
        showingDailyCheckInFromNotification = true
    }

    private func updateBodyGoalCheckInReminders() {
        let userID = session.profile.userID
        let profile = ATHLTHTrainingProfile.load(userID: userID)
        let goals = goalStore.goals
        notifications.reconcileBodyGoalCheckIns(
            goals: goals, accountID: userID, profile: profile
        )
        Task {
            await ATHLTHBodyGoalReminderScheduler.sync(
                goals: goals, profile: profile, userID: userID
            )
        }
    }

    /// Keep push-routing decisions independent from the root SwiftUI view builder.
    private func handleRemoteNotification(_ notification: Notification) {
            let info = notification.userInfo ?? [:]
            if let rawGoal = info["athlth_body_goal_checkin_id"] as? String,
               let goalID = UUID(uuidString: rawGoal),
               let rawAccount = info["athlth_body_goal_account_id"] as? String,
               rawAccount == session.profile.userID.uuidString,
               goalStore.goals.contains(where: { $0.id == goalID }) {
                pushManager.captureTappedNotification(info)
                return
            }
            if ATHLTHDailyCheckInReminderScheduler.isCurrentAccountCheckInTap(
                info, accountID: session.profile.userID
            ) {
                openPendingDailyCheckInIfNeeded()
                return
            }

            // Workout invitations belong to the actionable Inbox, not to
            // Community or the generic notifications page.
            if ATHLTHWorkoutInviteNotificationRoute.resolve(userInfo: info) != nil {
                openPendingWorkoutInviteIfNeeded()
                return
            }

            // Personal and official weekly challenge reminders are local
            // notifications with an entity ID, but no athlth_kind. Never
            // fall back to Home or a generic Community tab for those taps.
            if ATHLTHChallengeNotificationRoute.resolve(userInfo: info) != nil {
                return
            }

            if let destination = ATHLTHRootNotificationTabPolicy.destinationTab(
                for: info["athlth_kind"] as? String
            ) {
                selectedTab = destination
            }
    }

    /// A completed direct share returns to Home without an extra Done screen.
    /// Only a confirmed backend send triggers this root-level navigation.
    private func handleFriendQuickShareSuccess(_ notification: Notification) {
        guard let kind = notification.object as? ATHLTHFriendQuickShareKind else {
            return
        }
        selectedTab = 0
        showingSideMenu = false
        sideMenuModalDestination = nil
        sideMenuUtilityDestination = nil
        sideMenuFullScreenDestination = nil

        friendShareToastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            friendShareToast = kind
        }
        friendShareToastDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.5))
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                friendShareToast = nil
            }
        }
    }

    private func updateDailyCheckInReminder() {
        let store = RecoverySorenessStore()
        notifications.reconcileDailyCheckIn(
            enabled: settings.dailyCheckInRemindersEnabled,
            accountID: session.profile.userID,
            completed: store.hasTodayCheckIn
        )
    }

    private var visibleAppBadgeCount: Int {
        ATHLTHSideMenuBadgePolicy.counts(
            messaging: messaging,
            social: social,
            notificationStore: notifications,
            health: health
        ).total
    }

    init() {
        let prefix =
            "--athlth-compatibility-tab="
        let requestedTab =
            ProcessInfo.processInfo.arguments
                .first(
                    where: {
                        $0.hasPrefix(prefix)
                    }
                )
                .flatMap {
                    Int(
                        $0.dropFirst(
                            prefix.count
                        )
                    )
                }

        _selectedTab = State(
            initialValue:
                min(
                    max(
                        requestedTab ?? 0,
                        0
                    ),
                    4
                )
        )
    }

    private func restoreInterruptedPlanTabIfNeeded() {
        guard session.signedIn else { return }
        let accountID = session.profile.userID
        guard routedInterruptedPlanAccount != accountID else { return }
        // Cold-start tab routing is single-shot for each authenticated account.
        // A transient session refresh on warm foreground must not redirect
        // someone away from a card already open in the navigation stack.
        routedInterruptedPlanAccount = accountID
        // Compatibility/preview UI must remain on its requested tab.
        guard !ProcessInfo.processInfo.arguments.contains(where: {
            $0.hasPrefix("--athlth-compatibility-tab=")
        }) else { return }
        guard TrainProgramCreationLaunch.interruptedDraft(
            userID: accountID, store: ATHLTHPlanCreationDraftStore()
        ) != nil else { return }
        selectedTab = 1
    }

    private var rootTabs: some View {
        TabView(selection: $selectedTab) {
            ATHLTHHomeView(
                onSelectTab: { tab in
                    selectedTab = tab
                },
                onOpenTrain: { request in
                    trainNavigationRequest = request
                    selectedTab = 1
                },
                onOpenSideMenu: {
                    openSideMenu()
                },
                sideMenuUnreadCount: visibleAppBadgeCount,
                isActive: selectedTab == 0
            )
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            ATHLTHTrainView(
                navigationRequest: $trainNavigationRequest,
                isActive: selectedTab == 1
            )
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }
                .tag(1)

            // Insights must use the reference-designed four-section screen.
            // The former Recovery view remains available from within Insights
            // for detailed readiness and the daily check-in.
            ATHLTHInsightsView(
                onSelectTab: { tab in selectedTab = tab },
                isActive: selectedTab == 2
            )
                .tabItem {
                    Label(
                        "Insights",
                        systemImage: "sparkles"
                    )
                }
                .tag(2)

            ATHLTHExploreView(isActive: selectedTab == 3)
                .tabItem { Label("Explore", systemImage: "map.fill") }
                .tag(3)

            ATHLTHCommunityV5View(isActive: selectedTab == 4)
                .tabItem { Label("Community", systemImage: "person.3.fill") }
                .tag(4)
        }
        .tint(ATHLTHTheme.accentDeep)
        // Preserve measured Watch intervals before their result queue is
        // acknowledged; recording eligibility is checked by the receiver.
        .modifier(ATHLTHRunningPerformanceReceiver())
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        // TabView is already a complex generic container. Erase its type
        // before attaching global notifications, overlays and state hooks.
        .athlthStablePresentationBoundary()
        .environmentObject(goalAccountSync)
    }

    private var tabsWithNotificationSheets: some View {
        ATHLTHRootNotificationSheetHost(
            content: rootTabs,
            pushManager: pushManager,
            showingDailyCheckIn: $showingDailyCheckInFromNotification
        )
    }

    private var tabsWithNotifications: some View {
        tabsWithNotificationSheets
        // Goal sync shares the scene's foreground cadence rather than
        // running a second, independent 20-second polling loop. Goal edits
        // still use their existing event-driven, debounced scheduleSync.
        .onReceive(
            NotificationCenter.default.publisher(
                for: .athlthRemoteNotificationTapped
            )
        ) { notification in
            handleRemoteNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .athlthFriendQuickShareDidSucceed
        )) { notification in
            handleFriendQuickShareSuccess(notification)
        }
        .onAppear {
            guard !hasRestoredSelectedTab else { return }
            hasRestoredSelectedTab = true
            let isCompatibilityPreview = ProcessInfo.processInfo.arguments.contains {
                $0.hasPrefix("--athlth-compatibility-tab=")
            }
            if !isCompatibilityPreview,
               session.signedIn,
               persistedTabAccount == session.profile.userID.uuidString,
               (0...4).contains(persistedSelectedTab) {
                selectedTab = persistedSelectedTab
            }
            restoreInterruptedPlanTabIfNeeded()
        }
        .task {
            updateDailyCheckInReminder()
            updateBodyGoalCheckInReminders()
            openPendingDailyCheckInIfNeeded()
            openPendingWorkoutInviteIfNeeded()
            goalAccountSync.switchAccount(session.signedIn ? session.profile.userID : nil)
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
            await syncApplicationIconBadge()
        }
        .onChange(of: pushManager.pendingDailyCheckInAccountID) { _, _ in
            openPendingDailyCheckInIfNeeded()
        }
        .onChange(of: pushManager.pendingWorkoutInviteNotification) { _, _ in
            openPendingWorkoutInviteIfNeeded()
        }
        .onChange(of: selectedTab) { previous, next in
            if session.signedIn {
                persistedSelectedTab = next
                persistedTabAccount = session.profile.userID.uuidString
            }
            // Instruments signposts let us correlate a perceived tab stall
            // with HealthKit, MapKit and Community refreshes on a real device.
            switch next {
            case 0: ATHLTHPerformance.event("TabHome")
            case 1: ATHLTHPerformance.event("TabTrain")
            case 2: ATHLTHPerformance.event("TabInsights")
            case 3: ATHLTHPerformance.event("TabExplore")
            case 4: ATHLTHPerformance.event("TabCommunity")
            default: break
            }
            // Never reschedule notifications synchronously on a tab tap.
            // Finish the tab's first animation frame before doing the
            // account-local read + notification reconciliation. Only leaving
            // Insights or returning Home needs this refresh.
            deferredTabReminderTask?.cancel()
            guard previous == 2 || next == 0 else { return }
            deferredTabReminderTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(180))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                updateDailyCheckInReminder()
            }
        }
        .onChange(of: settings.dailyCheckInRemindersEnabled) { _, _ in
            updateDailyCheckInReminder()
        }
        .onChange(of: goalStore.goals) { _, _ in
            updateBodyGoalCheckInReminders()
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.goalDocumentDidChange")
        )) { notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  session.signedIn, accountID == session.profile.userID else { return }
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.privateMeasurementsDidChange")
        )) { notification in
            guard let accountID = notification.userInfo?["accountID"] as? UUID,
                  session.signedIn, accountID == session.profile.userID else { return }
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
        }
        .onChange(of: session.signedIn) { _, signedIn in
            goalAccountSync.switchAccount(signedIn ? session.profile.userID : nil)
            if signedIn {
                goalAccountSync.scheduleSync(session: session, goals: goalStore)
                openPendingWorkoutInviteIfNeeded()
                restoreInterruptedPlanTabIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .athlthTrainingDataDidChange
        )) { _ in
            updateBodyGoalCheckInReminders()
        }
        .onChange(of: session.profile.userID) { _, _ in
            routedInterruptedPlanAccount = nil
            restoreInterruptedPlanTabIfNeeded()
            goalAccountSync.switchAccount(session.signedIn ? session.profile.userID : nil)
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
            showingDailyCheckInFromNotification = false
            updateDailyCheckInReminder()
            updateBodyGoalCheckInReminders()
            openPendingDailyCheckInIfNeeded()
            openPendingWorkoutInviteIfNeeded()
        }
        .onChange(
            of: visibleAppBadgeCount
        ) { _, _ in
            Task {
                await syncApplicationIconBadge()
            }
        }
        .onChange(
            of: scenePhase
        ) { _, phase in
            guard phase == .active
            else {
                return
            }

            updateDailyCheckInReminder()
            updateBodyGoalCheckInReminders()
            openPendingDailyCheckInIfNeeded()
            openPendingWorkoutInviteIfNeeded()
            goalAccountSync.scheduleSync(session: session, goals: goalStore)
            Task {
                await syncApplicationIconBadge()
            }
        }
    }

    private var tabsWithCoachDock: some View {
        tabsWithNotifications
            .overlay(alignment: .bottom) {
                // Lightweight Coach affordance on every main tab; keep the
                // system tab bar untouched and the rest of Home scrollable.
                ATHLTHCoachDockHint {
                    showingCoachFromDock = true
                }
                // Move the visible handle 12 pt closer to the bottom tab bar,
                // while keeping the full 44-pt accessible touch target.
                .padding(.bottom, 44)
                .zIndex(40)
            }
            .sheet(isPresented: $showingCoachFromDock) {
                NavigationStack {
                    RecoveryCoachInboxDestinationView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(ATHLTHLocalization.choose(
                                    english: "Close", norwegian: "Lukk"
                                )) {
                                    showingCoachFromDock = false
                                }
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
            .athlthStablePresentationBoundary()
    }

    var body: some View {
        tabsWithCoachDock
        .background {
            ATHLTHMirroredWorkoutPresenter()
                .frame(width: 0, height: 0)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let friendShareToast {
                    Label(friendShareToast.sentConfirmation,
                          systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(.regularMaterial, in: Capsule())
                        .overlay {
                            Capsule().stroke(
                                ATHLTHTheme.premiumGold.opacity(0.24),
                                lineWidth: 1
                            )
                        }
                        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if social
                        .isCoordinatedLobbyMinimized,
                   social
                        .coordinatedLobbySessionID != nil {
                    Button {
                        social
                            .presentCoordinatedLobby()
                    } label: {
                        HStack(spacing: 11) {
                            Image(
                                systemName:
                                    "person.2.fill"
                            )
                            .font(
                                .system(
                                    size: 19,
                                    weight:
                                        .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .vitality
                            )

                            VStack(
                                alignment:
                                    .leading,
                                spacing: 1
                            ) {
                                Text(
                                    minimizedLobbyStatusText
                                )
                                .font(
                                    .system(
                                        size: 10,
                                        weight:
                                            .bold
                                    )
                                )
                                .tracking(0.8)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Return to Train Together",
                                        norwegian:
                                            "Returner til Tren sammen"
                                    )
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                            }

                            Spacer(minLength: 4)

                            Image(
                                systemName:
                                    "chevron.up"
                            )
                            .font(
                                .caption
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                        .padding(
                            .horizontal,
                            18
                        )
                        .frame(
                            width: 340,
                            height: 62
                        )
                        .background(
                            .regularMaterial,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    ATHLTHTheme
                                        .vitality
                                        .opacity(
                                            0.15
                                        ),
                                    lineWidth:
                                        0.8
                                )
                        }
                        .shadow(
                            color:
                                Color.black
                                    .opacity(
                                        0.10
                                    ),
                            radius: 14,
                            y: 6
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(
                        .move(edge: .top)
                            .combined(
                                with:
                                    .opacity
                            )
                    )
                }

                if let workout = strengthWorkout.activeWorkout {
                    ATHLTHMinimizedWorkoutReturnPill(
                        title: ATHLTHLocalization.choose(
                            english: "Return to strength workout",
                            norwegian: "Tilbake til styrkeøkten"
                        ),
                        systemImage: "dumbbell.fill",
                        detail: workout.title
                    ) {
                        // Reuse the existing Train presenter instead of
                        // creating a new recording or competing full-screen
                        // presentation over Home/Community.
                        trainNavigationRequest = .quick(.strength)
                        selectedTab = 1
                    }
                    .transition(
                        .move(edge: .top).combined(with: .opacity)
                    )
                }

                if workoutMirroring
                        .hasActiveMirroredWorkout,
                   workoutMirroring
                        .isUserMinimized,
                   strengthWorkout.activeWorkout == nil {
                    ATHLTHMinimizedWorkoutReturnPill(
                        title: ATHLTHLocalization.choose(
                            english: "Return to Apple Watch workout",
                            norwegian: "Tilbake til Apple Watch-økt"
                        ),
                        systemImage:
                            workoutMirroring.snapshot?.kind.systemImage ??
                            "figure.run"
                    ) {
                        workoutMirroring.presentWorkout()
                    }
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                    )
                }
            }
            .padding(.top, 8)
            .zIndex(50)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: {
                    social.coordinatedLobbySessionID != nil &&
                    !social.isCoordinatedLobbyMinimized
                },
                set: { _ in }
            )
        ) {
            if let sessionID =
                    social.coordinatedLobbySessionID {
                TrainTogetherCreatorLobbyView(
                    sessionID: sessionID
                )
                .environmentObject(social)
            }
        }
        .overlay {
            ZStack(alignment: .leading) {
                if showingSideMenu {
                    Button {
                        showingSideMenu = false
                    } label: {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Close navigation menu",
                        norwegian: "Lukk sidemenyen"
                    ))
                    .transition(.opacity)
                    .zIndex(99)

                    ATHLTHSideMenuView(
                        selectedTab: selectedTab,
                        onSelect: selectFromSideMenu,
                        onDismiss: { showingSideMenu = false }
                    )
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .leading)
                    )
                    .zIndex(100)
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86),
                value: showingSideMenu
            )
        }
        .sheet(item: $sideMenuModalDestination) { _ in
            NavigationStack {
                ATHLTHSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(
                                english: "Close", norwegian: "Lukk"
                            )) {
                                sideMenuModalDestination = nil
                            }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $sideMenuUtilityDestination) { destination in
            // Reuse the exact same Inbox / Notifications screens; only the
            // host presentation changes, so Home never peeks above the card.
            ATHLTHSideMenuUtilitiesView(
                destination: destination,
                workoutInviteID: destination == .inbox ? pushedWorkoutInviteID : nil
            )
                .accessibilityIdentifier("athlth-home-utility-fullscreen")
        }
        // Unlike the former 90% sheet, profile and deeper destinations
        // occupy the entire iPhone screen, including the safe area.
        .fullScreenCover(item: $sideMenuFullScreenDestination) { destination in
            ATHLTHSideMenuDeepLinkView(destination: destination)
        }
        .environmentObject(goalAccountSync)
    }

    private func openSideMenu() {
        showingSideMenu = true
    }

    private func selectFromSideMenu(_ destination: ATHLTHSideMenuDestination) {
        showingSideMenu = false

        switch destination {
        case .home:
            selectedTab = 0

        case .search:
            // The search cell expands inside ATHLTHSideMenuView.
            // No separate modal is presented for search.
            showingSideMenu = true

        case .inbox, .notifications:
            pushedWorkoutInviteID = nil
            sideMenuUtilityDestination = destination

        case .trainingLibrary:
            trainNavigationRequest = .library
            selectedTab = 1

        case .myExercises:
            trainNavigationRequest = .personalLibrary(.exercises)
            selectedTab = 1

        case .myRoutes:
            trainNavigationRequest = .personalLibrary(.routes)
            selectedTab = 1

        case .myTrainingPlans:
            trainNavigationRequest = .personalLibrary(.trainingPlans)
            selectedTab = 1

        case .myWorkouts:
            trainNavigationRequest = .personalLibrary(.workouts)
            selectedTab = 1

        case .ghostRace:
            trainNavigationRequest = .ghost
            selectedTab = 1

        case .profile, .trainTogether, .challenges, .arena, .clubs:
            sideMenuFullScreenDestination = destination

        case .settings:
            sideMenuModalDestination = .settings
        }
    }

    @MainActor
    private func syncApplicationIconBadge()
        async {
        do {
            try await UNUserNotificationCenter
                .current()
                .setBadgeCount(
                    visibleAppBadgeCount
                )
        } catch {
            // In-app badges remain the source of truth. iOS can briefly reject
            // a badge write while notification permissions are changing.
        }
    }

    private var minimizedLobbyStatusText:
        String {
        guard let sessionID =
                social
                    .coordinatedLobbySessionID
        else {
            return ATHLTHLocalization.choose(
                english: "WAITING",
                norwegian: "VENTER"
            )
        }

        let participants =
            (
                social
                    .activeWorkoutParticipants
                    .isEmpty
                    ? social
                        .workoutParticipants
                    : social
                        .activeWorkoutParticipants
            )
            .filter {
                $0.sessionID ==
                    sessionID &&
                $0.userID !=
                    social.currentUserID &&
                $0.workoutStartedAt ==
                    nil &&
                $0.state !=
                    .declined
            }

        if let waiting =
                participants.first(
                    where: {
                        !$0.isReady
                    }
                ) {
            let firstName =
                waiting
                    .displayNameSnapshot
                    .split(
                        separator: " "
                    )
                    .first
                    .map(String.init) ??
                waiting
                    .displayNameSnapshot

            return ATHLTHLocalization.choose(
                english:
                    "WAITING FOR \(firstName.uppercased())",
                norwegian:
                    "VENTER PÅ \(firstName.uppercased())"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "EVERYONE IS READY",
            norwegian:
                "ALLE ER KLARE"
        )
    }
}

private struct ATHLTHMirroredWorkoutPresenter: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var showingLiveWorkout = false

    private var presentationTrigger: String {
        "\(workoutMirroring.presentationGeneration)-\(workoutMirroring.snapshot?.startedAt?.timeIntervalSince1970 ?? 0)-\(workoutMirroring.isPresentationRequested)-\(workoutMirroring.isUserMinimized)-\(scenePhase == .active)"
    }

    private var canPresentMirroredWorkout: Bool {
        guard scenePhase == .active,
              workoutMirroring.isPresentationRequested,
              !workoutMirroring.isUserMinimized
        else {
            return false
        }

        if let kind = workoutMirroring.snapshot?.kind,
           kind == .strength || kind == .functional {
            return false
        }

        return workoutMirroring.snapshot != nil
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .fullScreenCover(
                isPresented: $showingLiveWorkout,
                onDismiss: {
                    guard !workoutMirroring
                        .hasActiveMirroredWorkout
                    else {
                        return
                    }

                    // A completed Watch workout auto-dismisses the live cover.
                    // Preserve its final snapshot and Ghost result until the
                    // completion/review pipeline has consumed them. Failed
                    // mirrors can still be discarded immediately.
                    if workoutMirroring
                        .snapshot?
                        .state == .failed {
                        workoutMirroring.dismissSummary()

                        if ghostRace.reference != nil {
                            ghostRace.dismissResult()
                        }
                    }
                }
            ) {
                MirroredWorkoutLiveView()
                    .environmentObject(workoutMirroring)
            }
            .task(id: presentationTrigger) {
                guard canPresentMirroredWorkout else {
                    showingLiveWorkout = false
                    return
                }

                // Mirroring can attach while the quick-start sheet is still
                // dismissing. Own the cover with local state and retry the
                // actual presentation, so SwiftUI cannot leave an active
                // workout hidden behind a stale true binding.
                while canPresentMirroredWorkout && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(650))

                    guard !Task.isCancelled,
                          canPresentMirroredWorkout
                    else {
                        showingLiveWorkout = false
                        return
                    }

                    if workoutMirroring.liveViewIsVisible {
                        return
                    }

                    showingLiveWorkout = false
                    await Task.yield()
                    try? await Task.sleep(
                        for: .milliseconds(70)
                    )

                    guard !Task.isCancelled,
                          canPresentMirroredWorkout
                    else {
                        return
                    }

                    showingLiveWorkout = true
                }
            }
            .onChange(
                of: workoutMirroring.isPresentationRequested
            ) { _, requested in
                if !requested {
                    showingLiveWorkout = false
                }
            }
    }
}

struct ATHLTHHomeView: View {
    var onSelectTab: (Int) -> Void = { _ in }
    var onOpenTrain:
        (ATHLTHTrainNavigationRequest) -> Void =
        { _ in }
    var onOpenSideMenu: () -> Void = {}
    var sideMenuUnreadCount = 0
    // TabView can instantiate inactive tabs while rendering the first frame.
    // Defer Home's network/Health loads until it is the selected tab.
    var isActive: Bool = true

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @Environment(\.dynamicTypeSize) private var homeDynamicTypeSize
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var tournamentCalendar: ATHLTHTournamentCalendarStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var spotifyPlayback: SpotifyPlaybackStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace: GhostRaceStore

    @State private var homeStreakDays: [Date]?
    @State private var lastHomeInitialLoadAt: Date?
    @State private var homeInitialLoadAccountID: UUID?
    @State private var lastHomeSocialLoadAt: Date?
    @State private var homeSocialLoadAccountID: UUID?
    @State private var showingHomeTodayCalendarAll = false
    @State private var showingHomeSocialInbox = false
    @State private var selectedHomeStandaloneWorkout: PlannedSession?
    @State private var selectedHomeCompletedWorkout: SocialPublishableWorkout?
    @State private var homeDeferredPhoneWorkout: PlannedSession?
    @State private var homeDeferredPhoneDelaySeconds: TimeInterval = 30
    @State private var selectedHomeAllStandaloneWorkout: PlannedSession?
    @State private var homeWorkoutPendingRemoval: PlannedSession?
    @State private var showingHomeWorkoutRemovalConfirmation = false
    @State private var selectedHomeStrengthSession: PlannedSession?
    @State private var selectedHomeStructuredWorkout: PlannedSession?
    @State private var pendingHomeQuickStartKind: WorkoutKind?
    @State private var showingHomeStrengthWorkout = false
    @State private var homeDirectStartInProgress = false
    @State private var homeWatchTransferMessage: String?
    @State private var homeWatchTransferError: String?
    @State private var showingGettingStartedPopup = false
    @State private var homeRecoveryTrendSnapshot =
        RecoveryTrendSnapshot.empty
    @AppStorage("hasEditedATHLTHProfile")
    private var hasEditedATHLTHProfile = false

    // Home and Train must consult the same authoritative capture gate.
    // A live Watch session, structured/manual timer or pending HealthKit
    // launch occupies the slot even when the Home tab is not active.
    private var universalRecordingOccupied: Bool {
        ATHLTHUniversalWorkoutAdmission.isOccupied(
            phone: phoneWorkout,
            strength: strengthWorkout,
            remoteWatchActive: watchConnection.hasActiveWatchWorkout
        )
    }

    var body: some View {
        NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: ATHLTHTrainDesign.gold.opacity(0.16),
                pullDownFadeBridge: true,
                warmHomePalette: true
            ) {
                ZStack(alignment: .topTrailing) {
                    ATHLTHHomeDashboardHero(
                        imageName: "HomeHero",
                        workout:
                            homeTodayPlanWorkout?
                                .workout,
                        isStarting:
                            homeDirectStartInProgress,
                        onStart: {
                            guard let selection =
                                    homeTodayPlanWorkout
                            else {
                                return
                            }

                            if homeCanStartDirectly(
                                selection.workout
                            ) {
                                startHomeWorkout(
                                    selection.workout
                                )
                            } else {
                                onOpenTrain(
                                    .workout(
                                        planID:
                                            selection
                                                .planID,
                                        workoutID:
                                            selection
                                                .workout
                                                .id
                                    )
                                )
                            }
                        },
                        onOpenPlan: {
                            onOpenTrain(.plan)
                        }
                    )
                    .overlay(alignment: .topLeading) {
                        Button(action: onOpenSideMenu) {
                            VStack(spacing: 5) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(width: 21, height: 2)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .background(Color.black.opacity(0.27), in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Color.white.opacity(0.36),
                                        lineWidth: 0.8
                                    )
                                    .allowsHitTesting(false)
                            }
                            .overlay(alignment: .topTrailing) {
                                if sideMenuUnreadCount > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 9, height: 9)
                                        .overlay {
                                            Circle()
                                                .stroke(.white, lineWidth: 1.5)
                                        }
                                        .offset(x: 2, y: -1)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: sideMenuUnreadCount > 0
                                ? "Open menu, unread items available"
                                : "Open navigation menu",
                            norwegian: sideMenuUnreadCount > 0
                                ? "Åpne menyen, uleste elementer"
                                : "Åpne sidemenyen"
                        ))
                        .padding(.leading, 16)
                        .padding(.top, 60)
                    }


                }
            } content: {
                LazyVStack(spacing: 12) {
                    HomeHealthMetricStrip(
                        snapshot:
                            homeRecoveryTrendSnapshot,
                        sleepText:
                            homeSleepMetricText,
                        stepsText:
                            homeStepsMetricText,
                        hrvText:
                            homeHRVMetricText,
                        loadText:
                            homeLoadMetricText,
                        readinessText:
                            homeReadinessMetricText,
                        isActive: isActive
                    )

                    HomeWeeklyProgressStrip(
                        plan: session.activePlan,
                        workouts: homeRecordedWorkouts,
                        events: homeWeeklyCommunityEvents,
                        canStartWithWatch: watchConnection.isReady,
                        onStartStandaloneWorkout: { workout, device in
                            startHomeStandaloneWorkout(workout, device: device)
                        },
                        onSendWorkoutToWatch: { workout in
                            prepareHomeCalendarWorkoutForWatch(workout, mode: .onWatch)
                        },
                        onDelayWorkoutStart: { workout, seconds in
                            deferHomeCalendarWorkoutOnPhone(workout, after: seconds)
                        },
                        onDelayWatchStart: { workout in
                            prepareHomeCalendarWorkoutForWatch(
                                workout, mode: .afterThirtySeconds
                            )
                        }
                    )

                    homeSocialStatusStrip

                    homeFriendsAndCalendarRow

                    HomePersonalRecentActivitySection()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                // Let Home's scrolling sheet continue underneath the floating
                // tab bar instead of ending in a fixed gray bottom rectangle.
                // Extra inset keeps the final card reachable above the bar.
                .padding(.bottom, 112)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            // Home should underlap the native floating tab bar just like the
            // other root tabs. Only the scrolling sheet moves behind it; the
            // system tab bar itself remains unchanged.
            .ignoresSafeArea(.container, edges: .bottom)
            // Recognize a deliberate swipe from the screen's left edge,
            // without stealing vertical scrolling or changing how the menu
            // button opens the existing drawer. This is attached only to
            // Home's root content, not to pushed screens or other tabs.
            .simultaneousGesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .local)
                    .onEnded { value in
                        guard isActive,
                              !ATHLTHDeviceRole.isIPad,
                              ATHLTHHomeEdgeSwipePolicy.shouldOpen(
                                startLocation: value.startLocation,
                                translation: value.translation
                              )
                        else { return }
                        onOpenSideMenu()
                    }
            )
            // Erase the large Home content before attaching modal sheets.
            .athlthStablePresentationBoundary()
            .sheet(
                isPresented:
                    $showingGettingStartedPopup
            ) {
                HomeGettingStartedPopupView(
                    hasPlan:
                        session.activePlan != nil,
                    hasGoal:
                        !goalStore.activeGoals.isEmpty,
                    hasEditedProfile:
                        hasCompletedProfileSetup
                )
            }
            .sheet(item: $selectedHomeStrengthSession) { workout in
                WorkoutStartOptionsView(
                    session: workout,
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady,
                    defaultCapture: .automatic,
                    defaultTracking: settings.defaultStrengthTracking
                ) { configuredWorkout, captureDevice, trackingMode, selectedFriends, socialMode, audioCoach, advancedConfiguration in
                    // Return the launch failure to the sheet that owns the
                    // unsaved exercise/set configuration. Do not show a global
                    // Home alert or dismiss the setup on a locked Watch.
                    do {
                        let didStart = try await WorkoutLaunchCoordinator.startStrength(
                            workout: configuredWorkout,
                            captureDevice: captureDevice,
                            trackingMode: trackingMode,
                            selectedFriends: selectedFriends,
                            participationMode: socialMode,
                            audioCoach: audioCoach,
                            advancedConfiguration: advancedConfiguration,
                            session: session,
                            settings: settings,
                            social: social,
                            strengthWorkout: strengthWorkout,
                            watchConnection: watchConnection,
                            spotify: spotifyPlayback
                        )
                        if didStart {
                            showingHomeStrengthWorkout = true
                            return nil
                        }
                        // The iPad sends an envelope to the paired iPhone;
                        // a successful enqueue deliberately returns false.
                        if ATHLTHDeviceRole.isIPad { return nil }
                        return social.errorMessage ?? ATHLTHLocalization.choose(
                            english: "The workout could not start. Check Apple Watch and try again.",
                            norwegian: "Økten kunne ikke startes. Kontroller Apple Watch og prøv igjen."
                        )
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            .athlthStablePresentationBoundary()
            .sheet(item: $pendingHomeQuickStartKind) { kind in
                // Stable type regardless of running, walking or other kind.
                AnyView(
                    Group {
                if kind == .running {
                    RunQuickStartSheet(
                        trainingDeviceProvider:
                            watchConnection.isReady ? .appleWatch : .none,
                        watchConnected:
                            watchConnection.isReady
                    ) { configuration in
                    
                    guard await social.beginWorkoutWithFriends(
                        title: configuration.title,
                        kind: .running,
                        friends: configuration.friends,
                        creatorName: session.profile.displayName,
                        creatorUsername: session.profile.username,
                        invitePayload: configuration.trainTogetherInvitePayload(
                            savedRoutes: session.savedRoutes
                        ),
                        creatorCaptureDevice: configuration.captureDevice
                    ) else {
                        return social.errorMessage ?? ATHLTHLocalization.choose(
                            english: "Workout could not start. Unlock Apple Watch and try again.",
                            norwegian: "Økten kunne ikke startes. Lås opp Apple Watch og prøv igjen."
                        )
                    }
                    do {
                        try await WorkoutLaunchCoordinator.startRunQuick(
                            configuration: configuration,
                            session: session,
                            settings: settings,
                            gear: gear,
                            phoneWorkout: phoneWorkout,
                            watchConnection: watchConnection,
                            spotify: spotifyPlayback,
                            ghostRace: ghostRace,
                            workoutMirroring: workoutMirroring
                        )
                        _ = await social.confirmCurrentJoinedWorkoutStarted()
                        if configuration.captureDevice == .appleWatch {
                            homeWatchTransferMessage = configuration.watchStartMode == .onWatch
                                ? configuration.watchStartMode.confirmationText : nil
                        }
                        return nil
                    } catch {
                        await social.markCurrentJoinedWorkoutLaunchFailed()
                        return error.localizedDescription
                    }
                }
                } else if kind == .strength {
                    WorkoutStartOptionsView(
                        session:
                            homeFreestyleStrengthSession,
                        trainingDeviceProvider:
                            watchConnection.isReady
                                ? .appleWatch
                                : .none,
                        watchConnected:
                            watchConnection.isReady,
                        defaultCapture:
                            .automatic,
                        defaultTracking:
                            settings
                                .defaultStrengthTracking
                    ) { configuredWorkout, captureDevice, trackingMode, selectedFriends, socialMode, audioCoach, advancedConfiguration in
                    // Return the launch failure to the sheet that owns the
                    // unsaved exercise/set configuration. Do not show a global
                    // Home alert or dismiss the setup on a locked Watch.
                    do {
                        let didStart = try await WorkoutLaunchCoordinator.startStrength(
                            workout: configuredWorkout,
                            captureDevice: captureDevice,
                            trackingMode: trackingMode,
                            selectedFriends: selectedFriends,
                            participationMode: socialMode,
                            audioCoach: audioCoach,
                            advancedConfiguration: advancedConfiguration,
                            session: session,
                            settings: settings,
                            social: social,
                            strengthWorkout: strengthWorkout,
                            watchConnection: watchConnection,
                            spotify: spotifyPlayback
                        )
                        if didStart {
                            pendingHomeQuickStartKind = nil
                                                        showingHomeStrengthWorkout = true
                            return nil
                        }
                        // The iPad sends an envelope to the paired iPhone;
                        // a successful enqueue deliberately returns false.
                        if ATHLTHDeviceRole.isIPad { return nil }
                        return social.errorMessage ?? ATHLTHLocalization.choose(
                            english: "The workout could not start. Check Apple Watch and try again.",
                            norwegian: "Økten kunne ikke startes. Kontroller Apple Watch og prøv igjen."
                        )
                    } catch {
                        return error.localizedDescription
                    }
                }
                } else {
                    QuickWorkoutStartSheet(
                        kind: kind,
                        trainingDeviceProvider:
                            watchConnection.isReady ? .appleWatch : .none,
                        watchConnected:
                            watchConnection.isReady
                    ) { selectedFriends, gearIDs, audioCoach in
                        Task { @MainActor in
                            var inviteWorkout =
                                PlannedSession(
                                    id: UUID(),
                                    title: kind.title,
                                    kind: kind,
                                    scheduledStart: nil,
                                    durationMinutes: nil,
                                    targetDistanceKilometers: nil,
                                    targetPaceSecondsPerKilometer: nil,
                                    routeID: nil,
                                    exercises: [],
                                    notes: nil
                                )
                            inviteWorkout
                                .audioCoachConfiguration =
                                audioCoach

                            guard await social.beginWorkoutWithFriends(
                                title: kind.title,
                                kind: kind,
                                friends: selectedFriends,
                                creatorName: session.profile.displayName,
                                creatorUsername: session.profile.username,
                                invitePayload:
                                    SocialWorkoutInvitePayload(
                                        workout:
                                            inviteWorkout
                                    ),
                                creatorCaptureDevice:
                                    .appleWatch
                            ) else {
                                if let message = social.errorMessage {
                                    homeWatchTransferError = message
                                }
                                return
                            }

                            startHomeQuickWorkoutOnWatch(
                                kind,
                                gearIDs: gearIDs,
                                audioCoach: audioCoach
                            )
                        }
                    }
                }
                    }
                )
            }
            .athlthStablePresentationBoundary()
            .fullScreenCover(item: $selectedHomeStructuredWorkout) { workout in
                // Newer workout builders store their ordered sets in blocks,
                // not legacy session.exercises. Reuse the real timeline
                // recorder rather than starting an empty strength log.
                StructuredWorkoutSessionView(
                    workout: workout,
                    linkedPlanID: HomeWeeklyProgressCalendar.containingPlanID(
                        for: workout, in: session.activePlan
                    )
                )
            }
            .fullScreenCover(isPresented: $showingHomeStrengthWorkout) {
                ActiveStrengthWorkoutView()
                    .environmentObject(strengthWorkout)
                    .environmentObject(session)
            }
            .alert(
                "ATHLTH",
                isPresented: Binding(
                    get: {
                        homeWatchTransferMessage != nil ||
                        homeWatchTransferError != nil
                    },
                    set: { visible in
                        if !visible {
                            homeWatchTransferMessage = nil
                            homeWatchTransferError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    homeWatchTransferMessage = nil
                    homeWatchTransferError = nil
                }
            } message: {
                Text(
                    homeWatchTransferError ??
                    homeWatchTransferMessage ??
                    ""
                )
            }
            .athlthStablePresentationBoundary()
            .refreshable {
                async let communityRefresh: Void = community.refresh()
                async let groupRefresh: Void =
                    refreshHomeGroupCalendar()
                async let activityRefresh: Void =
                    social.refreshHomeFeed(force: true)
                async let friendsRefresh: Void =
                    social.refreshHomeFriends(force: true)
                async let socialStatusRefresh: Void =
                    social.refreshHomeSocialStatus(challengeStore: challenges, force: true)

                if !health.shouldDeferAutomaticHealthWork {
                    _ = await health.refreshWorkoutImportInbox()
                    await health.refreshAll()
                    homeRecoveryTrendSnapshot =
                        await health.recoveryTrendSnapshot(
                            days: 14
                        )

                    async let streakRefresh: Void = loadHomeStreak()
                    async let goalsRefresh: Void =
                        goalStore.refreshAutomaticMilestones(
                            health: health,
                            strength: strengthWorkout
                        )

                    _ = await (
                        streakRefresh,
                        goalsRefresh
                    )
                } else {
                    await loadHomeStreak()
                }

                _ = await (
                    communityRefresh,
                    groupRefresh,
                    activityRefresh,
                    friendsRefresh,
                    socialStatusRefresh
                )
            }
            // Invitations open the same edge-to-edge inbox as the side menu.
            .fullScreenCover(isPresented: $showingHomeSocialInbox) {
                ATHLTHSideMenuUtilitiesView(destination: .inbox)
            }
            // Independent sessions share the calendar but not a plan ID.
            .sheet(item: $homeDeferredPhoneWorkout) { workout in
                ATHLTHHomeDeferredPhoneStartSheet(
                    workoutTitle: workout.title,
                    delaySeconds: homeDeferredPhoneDelaySeconds,
                    onStart: {
                        PlannedWorkoutReminderScheduler.cancelDelayedStart(workout.id)
                        homeDeferredPhoneWorkout = nil
                        startHomeStandaloneWorkout(workout, device: .iPhone)
                    },
                    onCancel: {
                        PlannedWorkoutReminderScheduler.cancelDelayedStart(workout.id)
                        homeDeferredPhoneWorkout = nil
                    }
                )
            }
            .sheet(item: $selectedHomeStandaloneWorkout) { workout in
                homeCalendarWorkoutSheet(workout)
                .presentationDetents([.fraction(0.76), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .sheet(item: $selectedHomeCompletedWorkout) { workout in
                NavigationStack {
                    WorkoutHistoryDetailView(workout: workout)
                        .navigationTitle(ATHLTHLocalization.choose(
                            english: "Completed workout", norwegian: "Fullført økt"
                        ))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(ATHLTHLocalization.choose(
                                    english: "Done", norwegian: "Ferdig"
                                )) { selectedHomeCompletedWorkout = nil }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .sheet(isPresented: $showingHomeTodayCalendarAll) {
                homeTodayCalendarAllSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
            .confirmationDialog(
                        ATHLTHLocalization.choose(
                            english: "Remove this planned workout?",
                            norwegian: "Fjerne denne planlagte økten?"
                        ),
                        isPresented: $showingHomeWorkoutRemovalConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(
                            ATHLTHLocalization.choose(
                                english: "Remove workout", norwegian: "Fjern økt"
                            ),
                            role: .destructive
                        ) {
                            if let workout = homeWorkoutPendingRemoval {
                                removeHomeCalendarWorkout(workout)
                            }
                            homeWorkoutPendingRemoval = nil
                        }
                        Button(
                            ATHLTHLocalization.choose(
                                english: "Cancel", norwegian: "Avbryt"
                            ),
                            role: .cancel
                        ) {
                            homeWorkoutPendingRemoval = nil
                        }
                    } message: {
                        Text(homeWorkoutPendingRemoval?.title ?? "")
                    }
            .athlthStablePresentationBoundary()
            .onAppear {
                syncHomeTodayWorkoutToWatch()

                guard !session.previewModeEnabled else {
                    return
                }

                let gettingStartedComplete =
                    hasCompletedProfileSetup &&
                    session.activePlan != nil &&
                    !goalStore.activeGoals.isEmpty

                let popupKey =
                    "homeGettingStartedPopupShownV1." +
                    session.profile.userID.uuidString

                guard !UserDefaults.standard.bool(
                    forKey: popupKey
                ),
                !gettingStartedComplete
                else {
                    return
                }

                UserDefaults.standard.set(
                    true,
                    forKey: popupKey
                )

                Task { @MainActor in
                    try? await Task.sleep(
                        for: .milliseconds(450)
                    )
                    showingGettingStartedPopup = true
                }
            }
            // Trend cards receive their own update as soon as HealthKit
            // reports a new snapshot. They must not wait for friends,
            // import-inbox processing or other Home network work, and never
            // require the user to pull to refresh.
            .task(id: "\(isActive)|\(session.profile.userID.uuidString)|\(health.hasRequestedAuthorization)|\(health.lastSuccessfulRefreshAt?.timeIntervalSince1970 ?? 0)|\(health.sleep.sleepEnd?.timeIntervalSince1970 ?? 0)|\(health.heart.hrvMilliseconds ?? -1)|\(health.workouts.count)") {
                guard isActive,
                      !session.previewModeEnabled,
                      health.hasRequestedAuthorization,
                      !health.shouldDeferAutomaticHealthWork
                else { return }
                let trend = await health.recoveryTrendSnapshot(days: 14)
                guard !Task.isCancelled, isActive else { return }
                homeRecoveryTrendSnapshot = trend
            }
            // Social feeds and group calendars are secondary to the Health
            // cards. Give the native tab transition the first render frames.
            // Fast Home -> Train taps cancel this work before it begins.
            .task(id: "\(isActive)-\(session.profile.userID.uuidString)-social") {
                guard isActive, !session.previewModeEnabled else { return }
                let userID = session.profile.userID
                if homeSocialLoadAccountID == userID,
                   let lastHomeSocialLoadAt,
                   Date().timeIntervalSince(lastHomeSocialLoadAt) < 90 {
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(750))
                } catch {
                    return
                }
                guard !Task.isCancelled, isActive,
                      session.profile.userID == userID else { return }
                let signpost = ATHLTHPerformance.begin("HomeSecondaryData")
                defer { ATHLTHPerformance.end("HomeSecondaryData", id: signpost) }
                async let communityRefresh: Void = community.refresh()
                async let groupRefresh: Void = refreshHomeGroupCalendar()
                async let activityRefresh: Void = social.refreshHomeFeed()
                async let friendsRefresh: Void = social.refreshHomeFriends()
                async let socialStatusRefresh: Void =
                    social.refreshHomeSocialStatus(challengeStore: challenges)
                _ = await (
                    communityRefresh, groupRefresh, activityRefresh,
                    friendsRefresh, socialStatusRefresh
                )
                guard !Task.isCancelled, isActive,
                      session.profile.userID == userID else { return }
                homeSocialLoadAccountID = userID
                lastHomeSocialLoadAt = Date()
            }
            .task(id: "\(isActive)-\(session.profile.userID.uuidString)-arena") {
                guard isActive, !session.previewModeEnabled else { return }
                _ = await tournamentCalendar.refresh(for: session.profile.userID)
            }
            .task(id: "\(isActive)-\(session.profile.userID.uuidString)") {
                guard isActive else { return }
                // Let the Home hierarchy paint before starting refresh work.
                // The compatibility preview is intentionally data-static so
                // smoke tests measure rendering rather than backend latency.
                await Task.yield()
                guard !session.previewModeEnabled, !Task.isCancelled else {
                    return
                }

                // Switching rapidly between tabs should not relaunch every
                // Home network, HealthKit, and streak query. Refreshable and
                // store notifications still update explicit/new data.
                if homeInitialLoadAccountID == session.profile.userID,
                   let lastHomeInitialLoadAt,
                   Date().timeIntervalSince(lastHomeInitialLoadAt) < 90 {
                    // A quick tab hop is not a refresh request. All Home
                    // stores publish changes independently; re-querying mutual
                    // friends on every return needlessly blocks Home rendering.
                    return
                }

                let homeLoadSignpost = ATHLTHPerformance.begin("HomeInitialData")
                defer {
                    ATHLTHPerformance.end(
                        "HomeInitialData", id: homeLoadSignpost
                    )
                }
                // Independent secondary network work now owns its own
                // cancellable task above, never this Health-critical path.
                guard !health.shouldDeferAutomaticHealthWork else {
                    await loadHomeStreak()
                    return
                }

                // Give the four top Home cards their freshest HealthKit
                // values first. Import inbox is secondary and cannot block
                // the card refresh on a cold launch.
                await health.refreshIfStale(
                    maxAge: 90
                )
                guard !Task.isCancelled else { return }
                _ = await health.refreshWorkoutImportInbox()

                async let streakRefresh: Void = loadHomeStreak()
                async let goalsRefresh: Void =
                    goalStore.refreshAutomaticMilestones(
                        health: health,
                        strength: strengthWorkout
                    )

                _ = await (streakRefresh, goalsRefresh)
                guard !Task.isCancelled, isActive else { return }
                homeInitialLoadAccountID = session.profile.userID
                lastHomeInitialLoadAt = Date()
            }
            .onChange(of: strengthWorkout.workoutHistory.count) {
                syncHomeTodayWorkoutToWatch()
                Task {
                    await loadHomeStreak()
                }
            }
            .onChange(of: health.workouts.count) {
                syncHomeTodayWorkoutToWatch()
                Task {
                    await loadHomeStreak()
                }
            }
            .onChange(of: session.activePlan) {
                // Editing sessions in the same plan must also refresh Watch.
                syncHomeTodayWorkoutToWatch()
            }
        }
    }

    @MainActor
    private func refreshHomeGroupCalendar()
        async {
        await groups.refresh()
        await groups.refreshCalendarContent()
    }

    @MainActor
    private func loadHomeStreak() async {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(
            byAdding: .day,
            value: -90,
            to: today
        ) ?? now.addingTimeInterval(-7_776_000)

        // Native ATHLTH sessions count even when the user has chosen not to
        // grant Health write/read access. This keeps streak an ATHLTH training
        // concept rather than making it dependent on a wearable.
        var activeDays = Set(
            strengthWorkout.workoutHistory
                .filter {
                    $0.isFinished &&
                    $0.startedAt >= start &&
                    $0.startedAt <= now
                }
                .map {
                    calendar.startOfDay(for: $0.startedAt)
                }
        )

        if health.healthDataAvailable,
           health.hasRequestedAuthorization {
            do {
                let healthDays = try await health.activeWorkoutDays(
                    startDate: start,
                    endDate: now
                )

                activeDays.formUnion(
                    healthDays.map {
                        calendar.startOfDay(for: $0)
                    }
                )
            } catch {
                // Keep the ATHLTH-native days instead of turning a temporary
                // Health query failure into a lost streak.
            }
        }

        homeStreakDays = Array(activeDays).sorted()
    }



    private var homeStreakCount: Int {
        guard let homeStreakDays,
              !homeStreakDays.isEmpty
        else {
            return 0
        }

        let calendar = Calendar.current
        let active = Set(
            homeStreakDays.map {
                calendar.startOfDay(for: $0)
            }
        )
        let today = calendar.startOfDay(for: Date())

        let startDay: Date
        if active.contains(today) {
            startDay = today
        } else if let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: today
        ),
        active.contains(yesterday) {
            startDay = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = startDay

        while active.contains(cursor) {
            streak += 1

            guard let previous = calendar.date(
                byAdding: .day,
                value: -1,
                to: cursor
            ) else {
                break
            }

            cursor = previous
        }

        return streak
    }

    private var homeHealthSourceText: String {
        if !health.hasRequestedAuthorization {
            return watchConnection.isReady
                ? "Apple Watch connected · Apple Health not connected"
                : "No health source connected"
        }

        if !health.hasTrainingHealthData {
            return watchConnection.isReady
                ? "Apple Health configured · no training data yet"
                : "Apple Health configured · no training data yet"
        }

        return watchConnection.isReady
            ? "Apple Health + Apple Watch"
            : "Apple Health"
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String

        switch hour {
        case 5..<12:
            greeting = "Good morning"
        case 12..<18:
            greeting = "Good afternoon"
        default:
            greeting = "Good evening"
        }

        return "\(greeting), \(session.profile.displayName)"
    }

    private var shouldShowMoveSummary: Bool {
        health.training.activeEnergyKilocaloriesToday != nil ||
            health.training.exerciseMinutesToday != nil ||
            health.training.moveGoalKilocaloriesToday != nil
    }

    private var shouldShowSleepSummary: Bool {
        health.sleep.totalAsleep > 0
    }

    private var shouldShowRecoverySummary: Bool {
        health.recovery.score != nil ||
            health.heart.hrvMilliseconds != nil ||
            health.heart.restingHeartRate != nil ||
            health.recovery.baselineDays > 0
    }

    private var shouldShowAnyDaySummary: Bool {
        shouldShowMoveSummary ||
            shouldShowRecoverySummary ||
            shouldShowSleepSummary
    }

    private var homeNoHealthDetail: String {
        if !health.hasRequestedAuthorization {
            if watchConnection.isReady {
                return "Your Apple Watch is connected, but ATHLTH still needs Apple Health access before health metrics appear. Training plans, strength logging and social features remain available."
            }

            return "No Apple Watch or Apple Health source is connected. ATHLTH stays focused on training plans, strength logging, routes, challenges and social features you can use without wearable data."
        }

        return "Apple Health is configured. Health cards appear automatically when compatible readable data becomes available, so ATHLTH does not fill your dashboard with empty metrics."
    }

    private var moveValue: String {
        guard let calories = health.training.activeEnergyKilocaloriesToday,
              calories > 0
        else {
            return "—"
        }

        return "\(Int(calories.rounded())) kcal"
    }

    private var moveProgress: Double? {
        guard let calories = health.training.activeEnergyKilocaloriesToday,
              let goal = health.training.moveGoalKilocaloriesToday,
              goal > 0
        else {
            return nil
        }

        return min(max(calories / goal, 0), 1)
    }

    private var moveSubtitle: String {
        guard let calories = health.training.activeEnergyKilocaloriesToday
        else {
            return "No data yet"
        }

        if let goal = health.training.moveGoalKilocaloriesToday,
           goal > 0 {
            let percent = Int(
                ((calories / goal) * 100).rounded()
            )
            return "\(percent)% of goal"
        }

        if let minutes = health.training.exerciseMinutesToday,
           minutes > 0 {
            return "\(Int(minutes.rounded())) exercise min"
        }

        return "Today"
    }

    private var recoveryValue: String {
        guard let score = health.recovery.score else {
            return "—"
        }

        return "\(score)"
    }

    private var sleepValue: String {
        guard health.sleep.totalAsleep > 0 else {
            return "—"
        }

        return health.sleep.totalAsleep.shortDuration
    }

    private var sleepSubtitle: String {
        guard health.sleep.totalAsleep > 0 else {
            return "No sleep data"
        }

        if let baseline = health.recovery.averageSleepDuration,
           baseline > 0 {
            let difference = health.sleep.totalAsleep - baseline
            let minutes = Int(abs(difference / 60).rounded())

            if minutes < 10 {
                return "Near your baseline"
            }

            return difference >= 0
                ? "+\(minutes)m vs baseline"
                : "−\(minutes)m vs baseline"
        }

        if health.sleep.totalAsleep >= 7.5 * 3_600 {
            return "Good duration"
        }

        if health.sleep.totalAsleep >= 6.5 * 3_600 {
            return "A little short"
        }

        return "Short night"
    }

    private var homeSleepMetricText: String {
        guard health.sleep.totalAsleep > 0 else {
            return "—"
        }

        return health.sleep.totalAsleep.shortDuration
    }

    private var homeStepsMetricText: String {
        guard let value = health.training.stepsToday,
              value.isFinite,
              value >= 0,
              value < Double(Int.max)
        else {
            // Missing HealthKit permission/data is different from 0 steps.
            return "—"
        }

        return Int(value.rounded(.down)).formatted()
    }

    private var homeHRVMetricText: String {
        guard let value =
                health.heart.hrvMilliseconds,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return
            "\(Int(value.rounded())) ms"
    }

    private var homeLoadMetricText: String {
        let load =
            homeRecoveryTrendSnapshot
                .trainingLoad

        if let ratio = load.ratio,
           ratio.isFinite,
           ratio > 0 {
            switch ratio {
            case ..<0.75:
                return ATHLTHLocalization.choose(
                    english: "Low",
                    norwegian: "Lav"
                )
            case 0.75...1.25:
                return ATHLTHLocalization.choose(
                    english: "Normal",
                    norwegian: "Normal"
                )
            case 1.25...1.50:
                return ATHLTHLocalization.choose(
                    english: "Elevated",
                    norwegian: "Økt"
                )
            default:
                return ATHLTHLocalization.choose(
                    english: "High",
                    norwegian: "Høy"
                )
            }
        }

        guard load.acuteMinutes > 0
        else {
            return "—"
        }

        return
            "\(Int(load.acuteMinutes.rounded())) min"
    }

    private var homeReadinessMetricText:
        String? {
        switch health.recovery.state {
        case .ready:
            return "God form"
        case .balanced:
            return "Balansert"
        case .takeItEasy:
            return "Rolig"
        case .recover:
            return "Restitusjon"
        case .buildingBaseline:
            return nil
        }
    }

    private var homeWeekInterval:
        DateInterval {
        var calendar =
            Calendar.current
        calendar.firstWeekday = 2

        return calendar.dateInterval(
            of: .weekOfYear,
            for: Date()
        ) ??
            DateInterval(
                start:
                    calendar.startOfDay(
                        for: Date()
                    ),
                duration: 7 * 86_400
            )
    }

    /// Keep iPhone weekly progress consistent with iPad Studio. Completed
    /// strength sessions remain visible while their HealthKit export is pending.
    /// The shared projection de-duplicates linked and time-matched recordings.
    private var homeRecordedWorkouts: [WorkoutSummary] {
        ATHLTHStudioRecordedWorkouts.merged(
            health: health.workouts,
            localStrength: strengthWorkout.workoutHistory
        )
    }

    private var homeWorkoutsThisWeek:
        [WorkoutSummary] {
        homeRecordedWorkouts.filter {
            homeWeekInterval.contains(
                $0.startDate
            )
        }
    }

    private var homeWeeklyRunningDistanceKilometers:
        Double {
        homeWorkoutsThisWeek
            .filter {
                $0.activity ==
                    .running
            }
            .compactMap(
                \.distanceMeters
            )
            .reduce(0, +) /
            1_000
    }

    private var homeWeeklyDurationMinutes:
        Double {
        homeWorkoutsThisWeek.reduce(
            0
        ) {
            $0 +
                max(
                    $1.duration / 60,
                    0
                )
        }
    }

    private var homeWeeklyStrengthSessions:
        Int {
        homeWorkoutsThisWeek
            .filter {
                $0.activity ==
                    .strength
            }
            .count
    }

    private var homeWeeklySessionCount:
        Int {
        homeWorkoutsThisWeek.count
    }

    // Two real scheduled workouts fit in both compact Home cards.
    // Keep a little breathing room for localized titles.
    private let homeCalendarContentMinHeight: CGFloat = 70
    private let homeFriendsCalendarCardHeight: CGFloat = 154

    private var homeChallengeInvitationCount: Int {
        challenges.incomingInvitations(for: session.profile.userID).count
    }

    private var homeWorkoutInvitationCount: Int {
        social.workoutInvites.filter { $0.participant.state == .invited }.count
    }

    private var homeActiveChallenges: [ATHLTHChallenge] {
        challenges.trainingChallenges(for: session.profile.userID)
            .filter { $0.status == .active }
    }

    /// At most one slim status row, so Recent Activity remains the focal feed.
    private var homeSocialStatusStrip: some View {
        let invitations = homeChallengeInvitationCount + homeWorkoutInvitationCount
        let active = homeActiveChallenges

        return Group {
            if invitations > 0 || !active.isEmpty {
                HStack(spacing: 0) {
                    if invitations > 0 {
                        Button {
                            showingHomeSocialInbox = true
                        } label: {
                            homeSocialStatusCell(
                                icon: "envelope.badge",
                                title: ATHLTHLocalization.choose(
                                    english: invitations == 1 ? "1 invitation" : "\(invitations) invitations",
                                    norwegian: invitations == 1 ? "1 invitasjon" : "\(invitations) invitasjoner"
                                ),
                                detail: homeSocialInvitationKinds
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("athlth-home-social-invitations")
                    }

                    if invitations > 0 && !active.isEmpty {
                        Rectangle()
                            .fill(ATHLTHTrainDesign.rule.opacity(0.4))
                            .frame(width: 1, height: 33)
                    }

                    if let first = active.first {
                        NavigationLink {
                            if active.count == 1 {
                                ChallengeDetailView(challengeID: first.id)
                            } else {
                                ChallengeHubView()
                            }
                        } label: {
                            homeSocialStatusCell(
                                icon: "trophy",
                                title: ATHLTHLocalization.choose(
                                    english: active.count == 1 ? "Active challenge" : "\(active.count) active challenges",
                                    norwegian: active.count == 1 ? "Aktiv challenge" : "\(active.count) aktive challenges"
                                ),
                                detail: active.count == 1
                                    ? first.title
                                    : ATHLTHLocalization.choose(
                                        english: "View all challenges",
                                        norwegian: "Se alle utfordringene"
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("athlth-home-social-active-challenge")
                    }
                }
                .padding(.horizontal, 5)
                .frame(minHeight: 48)
                .background(
                    ATHLTHTrainDesign.paper,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.34), lineWidth: 0.8)
                }
                .accessibilityIdentifier("athlth-home-social-status")
            }
        }
    }

    private var homeSocialInvitationKinds: String {
        let challengeCount = homeChallengeInvitationCount
        let workoutCount = homeWorkoutInvitationCount
        if challengeCount > 0 && workoutCount > 0 {
            return ATHLTHLocalization.choose(
                english: "Challenge · Train Together",
                norwegian: "Challenge · Tren sammen"
            )
        }
        return challengeCount > 0
            ? "Challenge"
            : ATHLTHLocalization.choose(english: "Train Together", norwegian: "Tren sammen")
    }

    private func homeSocialStatusCell(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
    }

    // Keep Friends and Calendar compact to protect Recent Activity space.
    // Daily recommendations now belong only to Train > Today on open days.
    private var homeFriendsAndCalendarRow: some View {
        Group {
            if homeDynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    homeTodayCalendarCard
                    homeFriendsCard
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    homeFriendsCard
                        .frame(maxWidth: .infinity)
                    homeTodayCalendarCard
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var homeFriendsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The existing strip owns actual friend status and quick actions.
            HomeActiveFriendsStrip(isActive: isActive)
            if social.mutualFollows.isEmpty && !social.isHomeFriendsRefreshing {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Friends", norwegian: "Venner"
                        ),
                        systemImage: "person.2"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)

                    Text(ATHLTHLocalization.choose(
                        english: "Friends you connect with appear here.",
                        norwegian: "Venner du knytter kontakt med, vises her."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .frame(
            height: homeDynamicTypeSize.isAccessibilitySize
                ? nil : homeFriendsCalendarCardHeight,
            alignment: .topLeading
        )
        .background(
            ATHLTHTrainDesign.paper,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.34), lineWidth: 0.8)
        }
    }

    /// HealthKit, completed iPhone workouts and finished ATHLTH strength logs
    /// are all private to the signed-in athlete. This list is not a social feed.
    /// Planned sessions already shown with an actual start must not be repeated.
    private var homeCompletedWorkoutsToday: [SocialPublishableWorkout] {
        let planned = HomeTodayCalendarSchedule.workouts(
            plan: session.activePlan,
            standalone: session.standalonePlannedSessions
        )
        let plannedStarts = planned.compactMap {
            session.recordedTimes(for: $0.id)?.startedAt
        }
        let merged = HomePersonalWorkoutCatalog.mergeRecent(
            healthSummaries: health.workouts,
            strengthHistory: strengthWorkout.workoutHistory,
            phoneHistory: phoneWorkout.history
        )
        let today = Date()
        let filtered = merged.filter {
            HomeTodayRecordedWorkoutPolicy.shouldShow(
                startedAt: $0.startDate,
                endedAt: $0.endDate,
                plannedRecordedStarts: plannedStarts,
                today: today
            )
        }
        var seen = Set<UUID>()
        return filtered.filter { seen.insert($0.id).inserted }
            .sorted { $0.startDate > $1.startDate }
    }

    private func completedWorkoutCalendarTitle(
        _ workout: SocialPublishableWorkout
    ) -> String {
        let raw = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty && raw.lowercased() != workout.activity.rawValue.lowercased() {
            return raw
        }
        switch workout.activity {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Run completed", norwegian: "Løpeøkt fullført"
            )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walk completed", norwegian: "Gåøkt fullført"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength workout completed", norwegian: "Styrkeøkt fullført"
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Workout completed", norwegian: "Treningsøkt fullført"
            )
        }
    }

    private var homeTodayCalendarCard:
        some View {
        let plan =
            session.activePlan
        let todayWorkouts = HomeTodayCalendarSchedule.workouts(
            plan: plan,
            standalone: session.standalonePlannedSessions
        )
        let completedToday = homeCompletedWorkoutsToday
        let personalEvents =
            homeTodayCommunityEvents
        let clubEvents =
            homeTodayGroupEvents
        let tournamentItems = tournamentCalendar.events(on: Date())
        // Coaching text is now below Friends, never duplicated here.

        // Prioritize up to two actual workouts even when a tournament
        // also has an event today; other events use remaining slots.
        let visibleWorkoutCount = min(todayWorkouts.count, 2)
        let visibleCompletedCount = min(
            completedToday.count, max(0, 2 - visibleWorkoutCount)
        )
        let visibleTournamentCount = min(
            tournamentItems.count, max(0, 2 - visibleWorkoutCount - visibleCompletedCount)
        )
        let availableAfterPlan =
            max(2 - visibleWorkoutCount - visibleCompletedCount - visibleTournamentCount, 0)
        let visiblePersonalCount =
            min(
                personalEvents.count,
                availableAfterPlan
            )
        let availableForClub =
            max(
                availableAfterPlan -
                    visiblePersonalCount,
                0
            )

        return VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Button {
                showingHomeTodayCalendarAll = true
            } label: {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Today", norwegian: "Kalender i dag"
                    ))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                    Spacer()

                    Text("Se alle")
                        .font(
                            .system(
                                size: 9.5,
                                weight:
                                    .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }
            .buttonStyle(.plain)

            if !todayWorkouts.isEmpty ||
                !completedToday.isEmpty ||
                !personalEvents.isEmpty ||
                !clubEvents.isEmpty ||
                !tournamentItems.isEmpty {
                VStack(spacing: 7) {
                    ForEach(Array(todayWorkouts.prefix(visibleWorkoutCount))) { workout in
                        HStack(spacing: 5) {
                            Button {
                                selectedHomeStandaloneWorkout = workout
                            } label: {
                                homeCompactCalendarRow(
                                    time: session.recordedTimes(for: workout.id)?.startedAt ??
                                        workout.scheduledStart,
                                    endTime: session.recordedTimes(for: workout.id)?.endedAt,
                                    title: workout.title,
                                    icon: workout.kind.systemImage,
                                    isTrainTogether: workout.trainTogetherMode != nil,
                                    trainingPartner: homeTrainTogetherPartner(for: workout)
                                )
                            }
                            .buttonStyle(.plain)

                        }
                    }

                    ForEach(Array(completedToday.prefix(visibleCompletedCount))) { workout in
                        Button {
                            selectedHomeCompletedWorkout = workout
                        } label: {
                            homeCompactCalendarRow(
                                time: workout.startDate,
                                endTime: workout.endDate,
                                title: completedWorkoutCalendarTitle(workout),
                                icon: workout.activity == .strength
                                    ? "dumbbell.fill" : "checkmark.circle.fill"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("athlth-home-calendar-completed-\(workout.id)")
                    }

                    ForEach(Array(
                        tournamentItems.prefix(visibleTournamentCount)
                    )) { item in
                        if let tournament = tournamentCalendar.tournament(
                            for: item.tournamentID
                        ) {
                            NavigationLink {
                                ATHLTHTournamentLiveDetailView(tournament: tournament)
                            } label: {
                                homeCompactCalendarRow(
                                    time: item.relevantDate(on: Date()),
                                    title: item.isDeadline(on: Date())
                                        ? "Frist · \(item.exerciseTitle)"
                                        : item.isOngoing(on: Date())
                                        ? "Pågår · \(item.exerciseTitle)"
                                        : item.exerciseTitle,
                                    icon: "trophy"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(
                        Array(
                            personalEvents
                                .prefix(
                                    availableAfterPlan
                                )
                        )
                    ) { event in
                        NavigationLink {
                            CommunityEventDetailView(
                                eventID:
                                    event.id
                            )
                        } label: {
                            homeCompactCalendarRow(
                                time: event.event.startsAt,
                                title: event.event.title,
                                icon: event.event.activityType.systemImage
                            )

                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(
                        Array(
                            clubEvents
                                .prefix(
                                    availableForClub
                                )
                        )
                    ) { event in
                        if let group =
                                groups.group(
                                    for:
                                        event.groupID
                                ) {
                            NavigationLink {
                                CommunityGroupEventDetailView(
                                    group: group,
                                    event: event
                                )
                            } label: {
                                homeCompactCalendarRow(
                                    time: event.startsAt,
                                    title: event.title,
                                    icon: homeGroupEventSystemImage(event.activityType)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(
                    minHeight:
                        homeCalendarContentMinHeight,
                    alignment: .top
                )
            } else {
                // Show a quiet empty state only; starting a workout belongs
                // in Training, not in the compact Home calendar preview.
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Text(ATHLTHLocalization.choose(
                        english: "Nothing on the calendar today",
                        norwegian: "Ingen aktiviteter i kalenderen"
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .multilineTextAlignment(.center)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: homeCalendarContentMinHeight,
                    maxHeight: .infinity,
                    alignment: .center
                )
            }


        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
        .frame(
            height: homeDynamicTypeSize.isAccessibilitySize
                ? nil : homeFriendsCalendarCardHeight,
            alignment: .topLeading
        )
        .background(
            ATHLTHTrainDesign.paper,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.34),
                              lineWidth: 0.8)
        }
    }


    /// A guest's partner is the organizer; an organizer's partner is
    /// the invited athlete. Prefer the public @username if available.
    private func homeTrainTogetherPartner(for workout: PlannedSession) -> String? {
        guard workout.trainTogetherMode != nil,
              let partnerID = workout.sharedSourceOwnerID ?? workout.invitedPartnerID,
              partnerID != session.profile.userID,
              let profile = social.profile(for: partnerID)
        else { return nil }
        return profile.usernameLabel.isEmpty
            ? profile.resolvedName
            : profile.usernameLabel
    }

    private func homeCompactCalendarRow(
        time: Date?,
        endTime: Date? = nil,
        title: String,
        icon: String,
        isTrainTogether: Bool = false,
        trainingPartner: String? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 7) {
            // Keep the time column slim: recorded finish sits under start.
            VStack(alignment: .leading, spacing: 2) {
                Text(time?.formatted(date: .omitted, time: .shortened) ??
                     ATHLTHLocalization.choose(
                        english: "—:—", norwegian: "—:—"
                     ))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                if let endTime {
                    Text("–" + endTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
            }
            .monospacedDigit()
            .frame(width: 48, alignment: .leading)
            .accessibilityElement(children: .combine)

            Rectangle()
                .fill(ATHLTHTrainDesign.bronze.opacity(0.40))
                .frame(width: 2, height: 30)

            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 19)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .lineLimit(isTrainTogether ? 1 : 2)
                    .multilineTextAlignment(.leading)

                if isTrainTogether {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Train together", norwegian: "Tren sammen"
                        ) + (trainingPartner.map { " · \($0)" } ?? ""),
                        systemImage: "person.2.fill"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            ATHLTHTrainDesign.canvas.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 11)
        )
    }

    // The compact Home card displays two slots, but "See all" must expose
    // every saved workout, including sessions created from Weekly Progress.
    private var homeTodayCalendarAllSheet: some View {
        let activePlan = session.activePlan
        let workouts = HomeTodayCalendarSchedule.workouts(
            plan: activePlan,
            standalone: session.standalonePlannedSessions
        )
        let completedToday = homeCompletedWorkoutsToday
        let personalEvents = homeTodayCommunityEvents
        let clubEvents = homeTodayGroupEvents
        let tournamentItems = tournamentCalendar.events(on: Date())

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    if workouts.isEmpty && completedToday.isEmpty &&
                       tournamentItems.isEmpty && personalEvents.isEmpty &&
                       clubEvents.isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english: "Nothing scheduled today",
                                norwegian: "Ingenting planlagt i dag"
                            ),
                            systemImage: "calendar",
                            description: Text(ATHLTHLocalization.choose(
                                english: "Your planned workouts and events will appear here.",
                                norwegian: "Planlagte økter og arrangementer vises her."
                            ))
                        )
                    }

                    ForEach(workouts) { workout in
                        HStack(spacing: 8) {
                            Button {
                                selectedHomeAllStandaloneWorkout = workout
                            } label: {
                                homeCalendarPlanRow(workout)
                                    .padding(13)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        ATHLTHPlanDesign.surface,
                                        in: RoundedRectangle(cornerRadius: 16)
                                    )
                            }
                            .buttonStyle(.plain)

                        }
                    }

                    ForEach(completedToday) { workout in
                        NavigationLink {
                            WorkoutHistoryDetailView(workout: workout)
                                .navigationTitle(ATHLTHLocalization.choose(
                                    english: "Completed workout", norwegian: "Fullført økt"
                                ))
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            homeCalendarEventRow(
                                time: workout.startDate,
                                title: completedWorkoutCalendarTitle(workout),
                                systemImage: "checkmark.circle.fill",
                                detail: ATHLTHLocalization.choose(
                                    english: "Completed", norwegian: "Fullført"
                                ) + " · " + workout.endDate.formatted(
                                    date: .omitted, time: .shortened
                                )
                            )
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                ATHLTHPlanDesign.surface,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(tournamentItems) { item in
                        if let tournament = tournamentCalendar.tournament(
                            for: item.tournamentID
                        ) {
                            NavigationLink {
                                ATHLTHTournamentLiveDetailView(tournament: tournament)
                            } label: {
                                homeCalendarEventRow(
                                    time: item.relevantDate(on: Date()),
                                    title: item.isDeadline(on: Date())
                                        ? "Frist · \(item.exerciseTitle)"
                                        : item.isOngoing(on: Date())
                                        ? "Pågår · \(item.exerciseTitle)"
                                        : item.exerciseTitle,
                                    systemImage: "trophy",
                                    detail: "\(item.tournamentTitle) · Frist " +
                                        item.deadlineAt.formatted(
                                            date: .abbreviated, time: .shortened
                                        )
                                )
                                .padding(13)
                                .background(
                                    ATHLTHPlanDesign.surface,
                                    in: RoundedRectangle(cornerRadius: 16)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(personalEvents) { event in
                        NavigationLink {
                            CommunityEventDetailView(eventID: event.id)
                        } label: {
                            homeCalendarEventRow(
                                time: event.event.startsAt,
                                title: event.event.title,
                                systemImage: event.event.activityType.systemImage,
                                detail: event.event.meetingName.isEmpty
                                    ? event.event.activityType.title
                                    : event.event.meetingName
                            )
                            .padding(13)
                            .background(
                                ATHLTHPlanDesign.surface,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(clubEvents) { event in
                        if let group = groups.group(for: event.groupID) {
                            NavigationLink {
                                CommunityGroupEventDetailView(
                                    group: group, event: event
                                )
                            } label: {
                                homeCalendarEventRow(
                                    time: event.startsAt,
                                    title: event.title,
                                    systemImage: homeGroupEventSystemImage(
                                        event.activityType
                                    ),
                                    detail: event.meetingName.isEmpty
                                        ? homeGroupEventActivityTitle(
                                            event.activityType
                                        )
                                        : event.meetingName
                                )
                                .padding(13)
                                .background(
                                    ATHLTHPlanDesign.surface,
                                    in: RoundedRectangle(cornerRadius: 16)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Today's calendar",
                norwegian: "Kalender i dag"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) {
                        showingHomeTodayCalendarAll = false
                    }
                }
            }
        }
        .confirmationDialog(
                    ATHLTHLocalization.choose(
                        english: "Remove this planned workout?",
                        norwegian: "Fjerne denne planlagte økten?"
                    ),
                    isPresented: $showingHomeWorkoutRemovalConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Remove workout", norwegian: "Fjern økt"
                        ),
                        role: .destructive
                    ) {
                        if let workout = homeWorkoutPendingRemoval {
                            removeHomeCalendarWorkout(workout)
                        }
                        homeWorkoutPendingRemoval = nil
                    }
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel", norwegian: "Avbryt"
                        ),
                        role: .cancel
                    ) {
                        homeWorkoutPendingRemoval = nil
                    }
                } message: {
                    Text(homeWorkoutPendingRemoval?.title ?? "")
                }
        .sheet(item: $selectedHomeAllStandaloneWorkout) { workout in
                homeCalendarWorkoutSheet(workout)
                .presentationDetents([.fraction(0.76), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }

    private func homeCalendarWorkoutSheet(_ workout: PlannedSession) -> some View {
        let planID = HomeWeeklyProgressCalendar.containingPlanID(for: workout, in: session.activePlan)
        let completed = planID.map { homeIsPlanSessionCompleted(planID: $0, workout: workout) } ?? false
        let skipped = planID.map { session.isPlanSessionSkipped(planID: $0, sessionID: workout.id) } ?? false
        return HomeDailyRecommendedWorkoutSheet(
            workout: workout,
            isPlanWorkout: planID != nil,
            canStartWithWatch: watchConnection.isReady,
            onOpenPlannedWorkout: { startCalendarPreview(workout, planID: planID, device: .appleWatch) },
            onStartOnPhone: { startCalendarPreview(workout, planID: planID, device: .iPhone) },
            onStartOnWatch: { startCalendarPreview(workout, planID: planID, device: .appleWatch) },
            onSendToWatch: {
                selectedHomeStandaloneWorkout = nil
                selectedHomeAllStandaloneWorkout = nil
                prepareHomeCalendarWorkoutForWatch(workout, mode: .onWatch)
            },
            onDelayOnPhone: { seconds in
                selectedHomeStandaloneWorkout = nil
                selectedHomeAllStandaloneWorkout = nil
                deferHomeCalendarWorkoutOnPhone(workout, after: seconds)
            },
            onDelayOnWatch: {
                selectedHomeStandaloneWorkout = nil
                selectedHomeAllStandaloneWorkout = nil
                prepareHomeCalendarWorkoutForWatch(workout, mode: .afterThirtySeconds)
            },
            isCalendarWorkout: true,
            canStart: !completed && !skipped && !workout.isExplicitRestDay
                && session.recordedTimes(for: workout.id)?.endedAt == nil,
            onDelete: completed ? nil : { removeHomeCalendarWorkout(workout) }
        )
    }

    /// Validates the live calendar record before offering any delayed start.
    /// No HealthKit workout starts while backgrounded; the notification
    /// brings the athlete back if the foreground countdown is interrupted.
    private func deferHomeCalendarWorkoutOnPhone(
        _ selected: PlannedSession, after seconds: TimeInterval
    ) {
        guard seconds >= 1, seconds <= 7_200,
              let workout = session.standalonePlannedSessions.first(where: {
                  $0.id == selected.id
              }) ?? session.activePlan?.weeks.flatMap(\.days)
                .flatMap(\.sessions).first(where: { $0.id == selected.id }),
              !workout.isExplicitRestDay,
              session.recordedTimes(for: workout.id)?.endedAt == nil,
              !universalRecordingOccupied
        else { return }
        let planID = HomeWeeklyProgressCalendar.containingPlanID(
            for: workout, in: session.activePlan
        )
        if let planID, (
            session.isPlanSessionSkipped(planID: planID, sessionID: workout.id) ||
            session.isPlanSessionCompleted(
                planID: planID, sessionID: workout.id,
                healthWorkouts: health.workouts,
                strengthHistory: strengthWorkout.workoutHistory
            )
        ) { return }
        selectedHomeStandaloneWorkout = nil
        selectedHomeAllStandaloneWorkout = nil
        PlannedWorkoutReminderScheduler.cancelDelayedStart(workout.id)
        PlannedWorkoutReminderScheduler.scheduleDelayedStart(
            workout, after: seconds
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(390))
            homeDeferredPhoneDelaySeconds = seconds
            homeDeferredPhoneWorkout = workout
        }
    }

    /// A long press sends a prepared workout, never starts a Watch recording.
    /// Running/walking reuse the existing Watch transfer path; strength uses
    /// the same structured snapshot produced by PlannedWorkoutWatchBuilder.
    private func prepareHomeCalendarWorkoutForWatch(
        _ selected: PlannedSession, mode: WatchWorkoutStartMode
    ) {
        guard watchConnection.isReady,
              let workout = session.standalonePlannedSessions.first(where: {
                  $0.id == selected.id
              }) ?? session.activePlan?.weeks.flatMap(\.days)
                .flatMap(\.sessions).first(where: { $0.id == selected.id }),
              let watchKind = ATHLTHWorkoutCaptureAdmission.watchKind(
                  for: workout
              ),
              ATHLTHPlannedWorkoutCaptureRoute.resolve(
                  workout, device: .appleWatch
              ).canUsePreparedWatchTransfer,
              !workout.isExplicitRestDay,
              session.recordedTimes(for: workout.id)?.endedAt == nil,
              !universalRecordingOccupied
        else {
            homeWatchTransferError = ATHLTHLocalization.choose(
                english: "This workout cannot be sent to Apple Watch right now.",
                norwegian: "Denne økten kan ikke sendes til Apple Watch akkurat nå."
            )
            return
        }
        let planID = HomeWeeklyProgressCalendar.containingPlanID(
            for: workout, in: session.activePlan
        )
        if let planID, (
            session.isPlanSessionSkipped(planID: planID, sessionID: workout.id) ||
            session.isPlanSessionCompleted(
                planID: planID, sessionID: workout.id,
                healthWorkouts: health.workouts,
                strengthHistory: strengthWorkout.workoutHistory
            )
        ) { return }
        guard !ATHLTHHybridWorkoutLaunchPlan.isCandidate(workout) else {
            homeWatchTransferError = ATHLTHLocalization.choose(
                english: "Mixed workouts cannot yet be prepared on Watch.",
                norwegian: "Kombinerte økter kan foreløpig ikke sendes til Watch."
            )
            return
        }
        if workout.kind == .running || workout.kind == .walking {
            startHomeStandaloneWorkout(
                workout, device: .appleWatch, watchStartMode: mode
            )
            return
        }
        // Generic prepared Watch sport payloads cannot carry a
        // saved route yet. Never pretend that route was transferred.
        if watchKind != .strength && workout.routeID != nil {
            homeWatchTransferError = ATHLTHLocalization.choose(
                english: "This sport's saved route needs a compatible Watch transfer.",
                norwegian: "Den lagrede ruten krever en støttet Watch-overføring."
            )
            return
        }
        watchConnection.sendPreparedWorkout(
            WatchPreparedWorkoutTransfer(
                id: UUID(),
                title: workout.title,
                summary: workout.durationMinutes.map { "\($0) min" }
                    ?? workout.kind.title,
                kind: watchKind,
                routeID: nil,
                runningWorkout: nil,
                audioCoach: PlannedWorkoutWatchBuilder.audioCoachConfiguration(
                    for: workout,
                    selectedRoute: nil,
                    defaultConfiguration: settings.audioCoachConfiguration(
                        enabled: settings.audioCoachEnabledByDefault
                    )
                ),
                indoor: !watchKind.usesOutdoorLocation,
                startMode: mode,
                strengthWorkout: watchKind == .strength
                    ? PlannedWorkoutWatchBuilder.strengthSnapshot(workout)
                    : nil,
                // Preserve the original training-plan link, separate from
                // this ephemeral prepared card's UUID.
                plannedPlanID: planID,
                plannedSessionID: planID == nil ? nil : workout.id,
                updatedAt: Date()
            )
        )
        homeWatchTransferMessage = ATHLTHLocalization.choose(
            english: "Sent to Apple Watch. Start the prepared workout there.",
            norwegian: "Sendt til Apple Watch. Start den klargjorte økten på klokken."
        )
    }

    private func startCalendarPreview(_ workout: PlannedSession, planID: UUID?, device: WorkoutCaptureDevice) {
        selectedHomeStandaloneWorkout = nil
        selectedHomeAllStandaloneWorkout = nil
        showingHomeTodayCalendarAll = false
        Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            // Opening the calendar's Start action must use the actual recorder,
            // not the read-only plan detail, on either capture device.
            if let planID, session.trainingPlan(withID: planID) == nil {
                homeWatchTransferError = ATHLTHLocalization.choose(
                    english: "The planned workout is no longer available.",
                    norwegian: "Den planlagte økten er ikke lenger tilgjengelig."
                )
                return
            }
            startHomeStandaloneWorkout(workout, device: device)
        }
    }

    private func removeHomeCalendarWorkout(_ workout: PlannedSession) {
        if let planID = HomeWeeklyProgressCalendar.containingPlanID(
            for: workout, in: session.activePlan
        ), let plan = session.trainingPlan(withID: planID) {
            guard let day = plan.weeks.flatMap(\.days).first(where: {
                $0.sessions.contains(where: { $0.id == workout.id })
            }) else { return }
            let removed = session.removePlanStudioWorkout(
                planID: planID,
                workoutID: workout.id,
                dayID: day.id,
                expectedVersion: plan.version,
                healthWorkouts: health.workouts,
                strengthHistory: strengthWorkout.workoutHistory
            )
            if !removed {
                homeWatchTransferError = ATHLTHLocalization.choose(
                    english: "This workout has changed or is already completed.",
                    norwegian: "Økten er endret eller allerede fullført."
                )
            }
        } else {
            session.removeStandalonePlannedSession(workout.id)
        }
        syncHomeTodayWorkoutToWatch()
    }

    private func homeCalendarPlanRow(
        _ workout: PlannedSession
    ) -> some View {
        homeCalendarEventRow(
            time:
                session.recordedTimes(for: workout.id)?.startedAt ??
                workout.scheduledStart,
            endTime:
                session.recordedTimes(for: workout.id)?.endedAt,
            title:
                workout.title,
            systemImage:
                workout.kind
                    .systemImage,
            detail:
                workout.trainTogetherMode == nil
                    ? homeSessionSummary(workout)
                    : ATHLTHLocalization.choose(
                        english: "Train together", norwegian: "Tren sammen"
                    ) + (homeTrainTogetherPartner(for: workout).map {
                        " · \($0)"
                    } ?? ""),
            tint:
                workout.trainTogetherMode == nil
                    ? homeWorkoutTint(workout.kind)
                    : ATHLTHTrainDesign.bronze
        )
    }

    private func homeCalendarEventRow(
        time: Date?,
        endTime: Date? = nil,
        title: String,
        systemImage: String,
        detail: String,
        tint: Color =
            ATHLTHTheme.recoveryBlue
    ) -> some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                Text(time?.formatted(date: .omitted, time: .shortened) ?? "—")
                    .font(.system(size: 9.5, weight: .medium))
                if let endTime {
                    Text("–" + endTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9, weight: .regular))
                }
            }
            .monospacedDigit()
            .foregroundStyle(ATHLTHTheme.mutedText)
            .frame(width: endTime == nil ? 34 : 46, alignment: .leading)
            .accessibilityElement(children: .combine)

            Image(
                systemName:
                    systemImage
            )
            .font(
                .system(
                    size: 11,
                    weight:
                        .semibold
                )
            )
            .foregroundStyle(tint)
            .frame(
                width: 27,
                height: 27
            )
            .background(
                tint.opacity(0.10),
                in:
                    RoundedRectangle(
                        cornerRadius: 9,
                        style:
                            .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text(title)
                    .font(
                        .system(
                            size: 10.5,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                Text(detail)
                    .font(
                        .system(
                            size: 8.5
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
            }

            Spacer(
                minLength: 0
            )
        }
    }

    private func homeCalendarQuickStartButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(tint)

                Text(title)
                    .font(
                        .system(
                            size: 10.5,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(
                maxWidth: .infinity
            )
            .frame(height: 58)
            .background(
                tint.opacity(0.08),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .stroke(
                    tint.opacity(0.14),
                    lineWidth: 0.7
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Start quick \(title)"
        )
    }

    private var homeUserCommunityEvents:
        [CommunityEventItem] {
        community.events.filter {
            item in

            guard item.event.status ==
                    "upcoming"
            else {
                return false
            }

            return item.event.creatorID ==
                    session.profile.userID ||
                item.participantRows.contains {
                    $0.userID ==
                        session.profile.userID &&
                    (
                        $0.attendanceStatus ==
                            .going ||
                        $0.attendanceStatus ==
                            .maybe
                    )
                }
        }
    }

    private var homeTodayCommunityEvents:
        [CommunityEventItem] {
        let calendar =
            Calendar.current

        return homeUserCommunityEvents
            .filter {
                calendar.isDateInToday(
                    $0.event.startsAt
                )
            }
            .sorted {
                $0.event.startsAt <
                    $1.event.startsAt
            }
    }

    private var homeUserGroupEvents:
        [CommunityGroupEventRecord] {
        let acceptedEventIDs =
            Set(
                groups
                    .calendarEventRSVPs
                    .filter {
                        $0.status == "going" ||
                        $0.status == "maybe"
                    }
                    .map(\.eventID)
            )

        return groups.calendarEvents
            .filter { event in
                event.status != "cancelled" &&
                event.status != "draft" &&
                (
                    event.creatorID ==
                        session.profile.userID ||
                    acceptedEventIDs.contains(
                        event.id
                    )
                )
            }
            .sorted {
                $0.startsAt <
                    $1.startsAt
            }
    }

    private var homeTodayGroupEvents:
        [CommunityGroupEventRecord] {
        let calendar =
            Calendar.current

        return homeUserGroupEvents
            .filter {
                calendar.isDateInToday(
                    $0.startsAt
                )
            }
            .sorted {
                $0.startsAt <
                    $1.startsAt
            }
    }

    private var homeWeeklyCommunityEvents:
        [HomeScheduledCommunityEvent] {
        var scheduled =
            homeUserCommunityEvents
                .filter {
                    homeWeekInterval
                        .contains(
                            $0.event.startsAt
                        )
                }
                .map {
                    item in

                    let cleanMeeting =
                        item.event
                            .meetingName
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )

                    let detail =
                        [
                            item.event.startsAt
                                .formatted(
                                    date: .omitted,
                                    time: .shortened
                                ),
                            cleanMeeting.isEmpty
                                ? item.event
                                    .activityType
                                    .title
                                : cleanMeeting
                        ]
                        .filter {
                            !$0.isEmpty
                        }
                        .joined(
                            separator: " · "
                        )

                    return HomeScheduledCommunityEvent(
                        id:
                            "community-" +
                            item.id.uuidString,
                        title:
                            item.event.title,
                        startsAt:
                            item.event.startsAt,
                        activityType:
                            item.event.activityType
                                .rawValue,
                        systemImage:
                            item.event.activityType
                                .systemImage,
                        detail: detail
                    )
                }

        scheduled.append(
            contentsOf:
                homeUserGroupEvents
                    .filter {
                        homeWeekInterval
                            .contains(
                                $0.startsAt
                            )
                    }
                    .map {
                        event in

                        let cleanMeeting =
                            event.meetingName
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )
                        let activityTitle =
                            homeGroupEventActivityTitle(
                                event.activityType
                            )
                        let detail =
                            [
                                event.startsAt
                                    .formatted(
                                        date: .omitted,
                                        time: .shortened
                                    ),
                                cleanMeeting.isEmpty
                                    ? activityTitle
                                    : cleanMeeting
                            ]
                            .filter {
                                !$0.isEmpty
                            }
                            .joined(
                                separator: " · "
                            )

                        return HomeScheduledCommunityEvent(
                            id:
                                "club-" +
                                event.id.uuidString,
                            title:
                                event.title,
                            startsAt:
                                event.startsAt,
                            activityType:
                                event.activityType,
                            systemImage:
                                homeGroupEventSystemImage(
                                    event.activityType
                                ),
                            detail: detail
                        )
                    }
        )

        for exercise in tournamentCalendar.items {
            if homeWeekInterval.contains(exercise.opensAt) {
                scheduled.append(HomeScheduledCommunityEvent(
                    id: "arena-open-" + exercise.id.uuidString,
                    title: exercise.exerciseTitle,
                    startsAt: exercise.opensAt,
                    activityType: "arena",
                    systemImage: "trophy",
                    detail: exercise.tournamentTitle
                ))
            }
            if homeWeekInterval.contains(exercise.deadlineAt) {
                scheduled.append(HomeScheduledCommunityEvent(
                    id: "arena-due-" + exercise.id.uuidString,
                    title: "Frist · " + exercise.exerciseTitle,
                    startsAt: exercise.deadlineAt,
                    activityType: "arena",
                    systemImage: "clock.badge.exclamationmark",
                    detail: exercise.tournamentTitle
                ))
            }
        }

        return scheduled.sorted {
            $0.startsAt <
                $1.startsAt
        }
    }

    private func homeGroupEventActivityTitle(
        _ activityType: String
    ) -> String {
        switch activityType {
        case "running":
            return ATHLTHLocalization.choose(
                english: "Running",
                norwegian: "Løping"
            )
        case "walking":
            return ATHLTHLocalization.choose(
                english: "Walking",
                norwegian: "Gåtur"
            )
        case "cycling":
            return ATHLTHLocalization.choose(
                english: "Cycling",
                norwegian: "Sykling"
            )
        case "strength":
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Workout",
                norwegian: "Økt"
            )
        }
    }

    private func homeGroupEventSystemImage(
        _ activityType: String
    ) -> String {
        switch activityType {
        case "running":
            return "figure.run"
        case "walking":
            return "figure.walk"
        case "cycling":
            return "bicycle"
        case "strength":
            return "dumbbell.fill"
        default:
            return "figure.mixed.cardio"
        }
    }

    private var homeActiveGoal: ATHLTHGoal? {
        if let primary = goalStore.primaryGoal,
           primary.status == .active {
            return primary
        }

        return goalStore.activeGoals.first {
            $0.status == .active
        }
    }

    private func homeActiveGoalCard(
        _ goal: ATHLTHGoal
    ) -> some View {
        NavigationLink {
            GoalDetailView(goalID: goal.id)
        } label: {
            ATHLTHCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: goal.category.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.green)
                            .frame(width: 44, height: 44)
                            .background(
                                Color.green.opacity(0.10),
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("ACTIVE GOAL")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )

                            Text(goal.title)
                                .font(.headline)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                                .lineLimit(2)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(
                                "\(Int((goal.progress * 100).rounded()))%"
                            )
                            .font(.title3.weight(.bold))
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )

                            Text("complete")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }

                    ProgressView(value: goal.progress)
                        .tint(.green)

                    HStack(alignment: .top, spacing: 12) {
                        if let milestone = homeNextMilestone(
                            for: goal
                        ) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "flag.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text("Next milestone")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Text(milestone.title)
                                        .font(
                                            .caption.weight(.semibold)
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )
                                        .lineLimit(2)
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        } else {
                            HStack(spacing: 8) {
                                Image(
                                    systemName:
                                        "checkmark.circle.fill"
                                )
                                .foregroundStyle(.green)

                                Text(
                                    goal.progress >= 1
                                        ? "Goal complete"
                                        : "Keep progressing"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }

                        if let deadline = goal.deadline {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(homeGoalDeadlineLabel(deadline))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )
                                Text("remaining")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var homeCreateFirstGoalCard: some View {
        NavigationLink {
            GoalCreationView()
        } label: {
            ATHLTHCard {
                HStack(spacing: 14) {
                    Image(systemName: "target")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 48, height: 48)
                        .background(
                            Color.green.opacity(0.10),
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SET YOUR FIRST GOAL")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                        Text("Create your first goal")
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text(
                            "Set a target and let ATHLTH track your progress. Tap here to get started."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create your first goal")
    }

    private func homeNextMilestone(
        for goal: ATHLTHGoal
    ) -> GoalMilestone? {
        goal.milestones.first {
            !$0.isCompleted
        }
    }

    private func homeGoalDeadlineLabel(
        _ deadline: Date
    ) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents(
            [.day],
            from: today,
            to: target
        ).day ?? 0

        if days < 0 {
            return "Overdue"
        }

        if days == 0 {
            return "Today"
        }

        if days == 1 {
            return "1 day"
        }

        return "\(days) days"
    }

    private var hasCompletedProfileSetup: Bool {
        let hasBio = !session.profile.bio
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        return hasEditedATHLTHProfile ||
            hasBio ||
            session.profile.avatarURL != nil
    }

    private var readinessTint: Color {
        switch health.recovery.state {
        case .ready:
            return ATHLTHTheme.vitality
        case .balanced:
            return ATHLTHTheme.recoveryBlue
        case .takeItEasy:
            return .orange
        case .recover:
            return .red
        case .buildingBaseline:
            return ATHLTHTheme.mutedText
        }
    }

    private var homeTodayPlanWorkout: (
        planID: UUID,
        workout: PlannedSession
    )? {
        guard let plan = session.activePlan else {
            return nil
        }

        let workout = homeTodaySessions(in: plan)
            .first {
                !homeIsPlanSessionCompleted(
                    planID: plan.id,
                    workout: $0
                )
            }

        guard let workout else {
            return nil
        }

        return (plan.id, workout)
    }

    private var homeTodayCompletion: (
        completed: Int,
        total: Int
    ) {
        guard let plan = session.activePlan else {
            return (0, 0)
        }

        let workouts = homeTodaySessions(in: plan)
        let completed = workouts.filter {
            homeIsPlanSessionCompleted(
                planID: plan.id,
                workout: $0
            )
        }
        .count

        return (
            completed,
            workouts.count
        )
    }

    private func homeIsPlanSessionCompleted(
        planID: UUID,
        workout: PlannedSession
    ) -> Bool {
        session.isPlanSessionCompleted(
            planID: planID,
            sessionID: workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strengthWorkout.workoutHistory
        )
    }

    private var homeFreestyleStrengthSession: PlannedSession {
        PlannedSession(
            id: UUID(),
            title:
                ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                ),
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: "Freestyle gym session",
            runningWorkout: nil
        )
    }

    private func syncHomeTodayWorkoutToWatch() {
        guard let plan = session.activePlan else {
            watchConnection.sendTodayWorkouts([])
            return
        }

        let today = session.plannedSessions(on: Date(), in: plan)
            .filter { !$0.isExplicitRestDay
                && ATHLTHWorkoutCaptureAdmission.watchKind(for: $0) != nil
                && ATHLTHPlannedWorkoutCaptureRoute.resolve(
                    $0, device: .appleWatch
                ).canUsePreparedWatchTransfer }
        let workouts: [PlannedSession] = {
            if !today.isEmpty { return today }
            // On rest days show the next planned workout on Watch home,
            // without changing the athlete's actual weekly plan.
            for offset in 1...7 {
                guard let date = Calendar.current.date(
                    byAdding: .day, value: offset, to: Date()
                ) else { continue }
                let next = session.plannedSessions(on: date, in: plan)
                    .filter { !$0.isExplicitRestDay
                        && ATHLTHWorkoutCaptureAdmission.watchKind(for: $0) != nil
                        && ATHLTHPlannedWorkoutCaptureRoute.resolve(
                            $0, device: .appleWatch
                        ).canUsePreparedWatchTransfer }
                if !next.isEmpty { return next }
            }
            return []
        }()
        var transfers: [WatchTodayWorkoutTransfer] = []
        for workout in workouts {
            guard let watchKind = ATHLTHWorkoutCaptureAdmission.watchKind(
                for: workout
            ), ATHLTHPlannedWorkoutCaptureRoute.resolve(
                workout, device: .appleWatch
            ).canUsePreparedWatchTransfer else { continue }
        let selectedRoute =
            PlannedWorkoutWatchBuilder.route(
                for: workout,
                routes: session.savedRoutes
            )

        if let selectedRoute {
            try? watchConnection.sendRoute(
                selectedRoute
            )
        }

        let runningWorkout:
            WatchRunningWorkoutTransfer?

        if watchKind == .running ||
            watchKind == .walking {
            runningWorkout =
                PlannedWorkoutWatchBuilder
                    .runningTransfer(
                        from: workout,
                        routeAlerts: .standard,
                        autoPauseEnabled:
                            workout.autoPauseEnabled ??
                            settings.autoPauseOutdoorWorkouts
                    )
        } else {
            runningWorkout = nil
        }

        let audioCoach =
            PlannedWorkoutWatchBuilder
                .audioCoachConfiguration(
                    for: workout,
                    selectedRoute:
                        selectedRoute,
                    defaultConfiguration:
                        .disabled
                )

        transfers.append(
            WatchTodayWorkoutTransfer(
                planID: plan.id,
                workoutID: workout.id,
                title: workout.title,
                summary:
                    homeSessionSummary(
                        workout
                    ),
                kind: watchKind,
                scheduledStart:
                    workout.scheduledStart,
                durationMinutes:
                    workout.durationMinutes,
                distanceKilometers:
                    workout
                        .targetDistanceKilometers,
                routeID:
                    workout.routeID,
                runningWorkout:
                    runningWorkout,
                audioCoach:
                    audioCoach,
                strengthWorkout:
                    watchKind == .strength
                        ? homeStrengthWatchSnapshot(
                            workout
                        )
                        : nil,
                updatedAt: Date()
            )
        )
        }
        watchConnection.sendTodayWorkouts(transfers)
    }

    private func homeStrengthWatchSnapshot(
        _ workout: PlannedSession
    ) -> WatchStrengthSessionSnapshot? {
        PlannedWorkoutWatchBuilder.strengthSnapshot(workout)
    }

    private func homeTodaySessions(
        in plan: TrainingPlan
    ) -> [PlannedSession] {
        ATHLTHTrainingPlanSchedule.sessions(in: plan)
    }

    private func homeSessionSummary(
        _ workout: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let running = workout.runningWorkout {
            parts.append(running.type.title)
            if !running.blocks.isEmpty {
                parts.append("\(running.blocks.count) blocks")
            }
        } else if let duration = workout.durationMinutes {
            parts.append("\(duration) min")
        }

        if let distance = workout.targetDistanceKilometers {
            parts.append(
                String(format: "%.1f km", distance)
            )
        }

        if let structuredSummary = ATHLTHWorkoutContentSummary.text(for: workout) {
            parts.append(structuredSummary)
        } else if !workout.exercises.isEmpty {
            parts.append(ATHLTHLocalization.choose(
                english: "\(workout.exercises.count) exercises",
                norwegian: "\(workout.exercises.count) øvelser"
            ))
        }

        return parts.isEmpty
            ? workout.kind.title
            : parts.joined(separator: " · ")
    }

    private func homeWorkoutTint(_ kind: WorkoutKind) -> Color {
        switch kind {
        case .running: return .green
        case .walking: return .blue
        case .strength: return .purple
        case .mobility: return .teal
        case .recovery: return .indigo
        case .custom: return ATHLTHTheme.accentDeep
        }
    }

    private func homeRequiresAppleWatch(
        _ workout: PlannedSession
    ) -> Bool {
        guard !ATHLTHDeviceRole.isIPad else {
            return false
        }

        guard workout.kind == .running ||
                workout.kind == .walking
        else {
            return false
        }

        return !watchConnection.isReady
    }

    private func homeCanStartDirectly(
        _ workout: PlannedSession
    ) -> Bool {
        guard !homeDirectStartInProgress else {
            return true
        }

        switch workout.kind {
        case .strength:
            return strengthWorkout.activeWorkout == nil

        case .running, .walking:
            return watchConnection.isReady &&
                !watchConnection.workoutLaunchInProgress

        case .mobility, .recovery, .custom:
            return false
        }
    }

    @ViewBuilder
    private func homeQuickStartButton(
        title: String,
        icon: String,
        tint: Color,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(
                    systemName:
                        enabled
                            ? icon
                            : "lock.fill"
                )
                Text(
                    enabled
                        ? title
                        : "\(title) · Watch"
                )
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                tint.opacity(0.08),
                in: RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
                .stroke(tint.opacity(0.13), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.62)
    }

    // A standalone calendar workout has no plan ID. Launch the original
    // scheduled recipe with the existing Home iPhone/Watch recording engines.
    // Allow the detail sheet to close before showing a recorder cover.
    private func reconcileHomeEarlyWorkoutStart(
        _ workout: PlannedSession,
        startedAt: Date = Date(),
        startedOnWatch: Bool = false
    ) {
        // Persist actual start and reschedule tomorrow's occurrence only after
        // the workout engine acknowledges it. Never create a second session.
        guard session.recordPlannedWorkoutStarted(
            workoutID: workout.id,
            startedAt: startedAt,
            startedOnWatch: startedOnWatch
        ) else { return }
        syncHomeTodayWorkoutToWatch()
    }

    private func startHomeStandaloneWorkout(
        _ workout: PlannedSession,
        device: WorkoutCaptureDevice,
        watchStartMode: WatchWorkoutStartMode = .immediate
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            let planID = HomeWeeklyProgressCalendar.containingPlanID(
                for: workout, in: session.activePlan
            )
            let persisted = session.standalonePlannedSessions.first(
                where: { $0.id == workout.id }
            ) ?? session.activePlan?.weeks.flatMap(\.days)
                .flatMap(\.sessions).first(where: { $0.id == workout.id })
            guard let persisted, !persisted.isExplicitRestDay,
                  session.recordedTimes(for: persisted.id)?.endedAt == nil,
                  planID.map({ !session.isPlanSessionSkipped(
                      planID: $0, sessionID: persisted.id
                  ) && !session.isPlanSessionCompleted(
                      planID: $0, sessionID: persisted.id,
                      healthWorkouts: health.workouts,
                      strengthHistory: strengthWorkout.workoutHistory
                  ) }) ?? true
            else {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                homeWatchTransferError = ATHLTHLocalization.choose(
                    english: "This scheduled workout is no longer available.",
                    norwegian: "Denne planlagte økten er ikke lenger tilgjengelig."
                )
                return
            }

            // An existing structured session reopens its original
            // checkpoint, including a projected legacy timed sport.
            if ATHLTHStructuredCaptureAdmission.activeWorkoutID == persisted.id {
                selectedHomeStructuredWorkout =
                    ATHLTHUnifiedWorkout.timedNonCardioProjection(from: persisted)
                    ?? persisted
                return
            }
            guard !homeDirectStartInProgress,
                  !universalRecordingOccupied
            else {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                homeWatchTransferError = ATHLTHLocalization.choose(
                    english: "Finish your current workout before starting another.",
                    norwegian: "Avslutt økten som pågår før du starter en ny."
                )
                return
            }

            if device == .appleWatch &&
                !watchConnection.isReady {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                homeWatchTransferError = ATHLTHLocalization.choose(
                    english: "Apple Watch is unavailable. Start with iPhone instead.",
                    norwegian: "Apple Watch er ikke tilgjengelig. Start med iPhone i stedet."
                )
                return
            }

            switch ATHLTHPlannedWorkoutCaptureRoute.resolve(
                persisted, device: device
            ) {
            case .phoneHybridStrength, .watchHybridStrength:
                guard let parts = ATHLTHHybridWorkoutLaunchPlan.parts(
                    for: persisted, allowOutdoorGPS: device == .appleWatch
                ) else {
                    homeWatchTransferError = ATHLTHLocalization.choose(
                        english: "This mixed workout requires a compatible recorder.",
                        norwegian: "Denne kombinerte økten krever en støttet opptaker."
                    )
                    return
                }
                startHomePlannedStrengthWorkout(
                    persisted, device: device, hybridParts: parts
                )
            case .phoneEndurance:
                startHomeStandalonePhoneEndurance(
                    persisted, planID: planID
                )
            case .watchEndurance:
                startHomePlannedWorkoutOnWatch(
                    persisted, startMode: watchStartMode
                )
            case .phoneStrength, .watchStrength:
                startHomePlannedStrengthWorkout(persisted, device: device)
            case .phoneStructuredManual:
                selectedHomeStructuredWorkout =
                    ATHLTHUnifiedWorkout.timedNonCardioProjection(
                        from: persisted
                    ) ?? persisted
            case .watchSport:
                prepareHomeCalendarWorkoutForWatch(
                    persisted, mode: .onWatch
                )
            case .unavailable:
                await social.markCurrentJoinedWorkoutLaunchFailed()
                homeWatchTransferError = ATHLTHLocalization.choose(
                    english: "This workout needs a recorder that preserves every activity in the plan.",
                    norwegian: "Denne økten trenger en opptaker som tar vare på alle aktivitetene i planen."
                )
            }
        }
    }

    private func startHomeStandalonePhoneEndurance(
        _ workout: PlannedSession,
        planID: UUID? = nil
    ) {
        let treadmill = RunEnvironment.forPlannedSession(workout) == .treadmill
        let selectedRoute = treadmill ? nil : PlannedWorkoutWatchBuilder.route(
            for: workout, routes: session.savedRoutes
        )
        let autoPause = !treadmill && (workout.autoPauseEnabled ??
            settings.autoPauseOutdoorWorkouts)
        var routeAlerts = settings.routeAlertConfiguration
        if treadmill { routeAlerts.enabled = false }
        let audioCoach = PlannedWorkoutWatchBuilder.audioCoachConfiguration(
            for: workout,
            selectedRoute: selectedRoute,
            defaultConfiguration: settings.audioCoachConfiguration(
                enabled: settings.audioCoachEnabledByDefault
            )
        )

        if !treadmill, let ghostTarget = workout.ghostTargetDurationSeconds {
            guard let selectedRoute else {
                homeWatchTransferError = ATHLTHLocalization.choose(
                    english: "This Ghost workout needs a saved route.",
                    norwegian: "Denne Ghost-økten trenger en lagret rute."
                )
                return
            }
            do {
                try ghostRace.prepareTarget(
                    route: selectedRoute,
                    targetDurationSeconds: ghostTarget
                )
            } catch {
                homeWatchTransferError = error.localizedDescription
                return
            }
        } else {
            ghostRace.cancel()
        }

        if let plannedGearIDs = workout.gearIDs {
            gear.prepareNextWorkoutGear(Set(plannedGearIDs))
        } else {
            gear.clearPreparedWorkoutGear()
        }

        // The running transfer carries intervals, pace and target alerts to
        // iPhone just like the Watch path, even without a training plan.
        let runTransfer: WatchRunningWorkoutTransfer? =
            workout.kind == .running
                ? PlannedWorkoutWatchBuilder.runningTransfer(
                    from: workout,
                    routeAlerts: routeAlerts,
                    autoPauseEnabled: autoPause
                )
                : nil

        phoneWorkout.start(
            walking: workout.kind == .walking,
            route: selectedRoute,
            title: workout.title,
            environment: treadmill ? .treadmill : .outdoor,
            audioCoach: audioCoach,
            structuredWorkout: runTransfer,
            routeAlerts: routeAlerts,
            ghostUpdates: treadmill ? nil : workout.ghostUpdates,
            autoPauseEnabled: autoPause,
            plannedPlanID: planID,
            plannedSessionID: workout.id
        )
        // PhoneWorkout.start records the actual workout start before the
        // calendar is updated. Keep that timestamp, not the planned 18:00.
        if let active = phoneWorkout.active {
            reconcileHomeEarlyWorkoutStart(
                workout, startedAt: active.start
            )
        }
        // The coordinated lobby authorizes this individual recording.
        // Only acknowledge the start after the real iPhone engine begins.
        Task { _ = await social.confirmCurrentJoinedWorkoutStarted() }
        watchConnection.updateLocalWorkoutActivity(
            isActive: true,
            title: workout.title
        )
        session.beginTrainingStatus(for: workout)
        WorkoutLaunchCoordinator.startLinkedSpotifyIfNeeded(
            workout: workout,
            session: session,
            settings: settings,
            spotify: spotifyPlayback
        )
    }

    private func startHomeWorkout(
        _ workout: PlannedSession
    ) {
        guard !homeDirectStartInProgress else {
            return
        }

        switch workout.kind {
        case .strength:
            selectedHomeStrengthSession = workout

        case .running, .walking:
            startHomePlannedWorkoutOnWatch(workout)

        case .mobility, .recovery, .custom:
            break
        }
    }

    private func startHomeQuickWorkoutOnWatch(
        _ kind: WorkoutKind,
        gearIDs: Set<UUID>,
        audioCoach: WatchAudioCoachConfiguration
    ) {
        guard watchConnection.isReady,
              !universalRecordingOccupied,
              let watchKind = PlannedWorkoutWatchBuilder.watchKind(for: kind)
        else {
            Task {
                await social
                    .markCurrentJoinedWorkoutLaunchFailed()
            }
            homeWatchTransferError =
                "Apple Watch is not ready for this workout."
            return
        }

        Task { @MainActor in
            do {
                // Hold the ONE cross-sport recording slot through Watch
                // HealthKit's async start; two quick taps cannot race.
                let launchID = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
                defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(launchID) }
                let initiatingAccount = session.profile.userID
                watchConnection.sendAudioCoachConfiguration(audioCoach)
                try await watchConnection.startWorkoutOnWatch(watchKind)
                guard session.profile.userID == initiatingAccount else {
                    await social.markCurrentJoinedWorkoutLaunchFailed()
                    homeWatchTransferError = ATHLTHLocalization.choose(
                        english: "The account changed during Apple Watch launch.",
                        norwegian: "Kontoen ble endret mens Apple Watch startet."
                    )
                    return
                }
                gear.prepareNextWorkoutGear(gearIDs)
                _ = await social
                    .confirmCurrentJoinedWorkoutStarted()
                homeWatchTransferMessage =
                    "\(watchKind.title) started on Apple Watch."
            } catch {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                homeWatchTransferError = error.localizedDescription
            }
        }
    }

    private func startHomePlannedWorkoutOnWatch(
        _ workout: PlannedSession,
        startMode: WatchWorkoutStartMode = .immediate
    ) {
        guard ATHLTHPlannedWorkoutCaptureRoute.resolve(
                  workout, device: .appleWatch
              ) == .watchEndurance,
              let watchKind = ATHLTHWorkoutCaptureAdmission.watchKind(
                  for: workout
              ),
              watchConnection.isReady
        else {
            homeWatchTransferError =
                "Apple Watch is not ready for this workout."
            return
        }

        let planID = HomeWeeklyProgressCalendar.containingPlanID(
            for: workout, in: session.activePlan
        )
        let treadmill = RunEnvironment.forPlannedSession(workout) == .treadmill
        let selectedRoute: TrainingRoute? =
            treadmill ? nil : PlannedWorkoutWatchBuilder.route(
                for: workout,
                routes: session.savedRoutes
            )
        var routeAlerts = settings.routeAlertConfiguration
        if treadmill { routeAlerts.enabled = false }

        do {
            if let selectedRoute {
                try watchConnection.sendRoute(selectedRoute)
                watchConnection.sendWorkoutRouteSelection(
                    selectedRoute.id
                )
            } else {
                watchConnection.sendWorkoutRouteSelection(nil)
            }
        } catch {
            homeWatchTransferError = error.localizedDescription
            return
        }

        if !treadmill, let ghostTarget =
                workout
                    .ghostTargetDurationSeconds {
            guard let selectedRoute else {
                homeWatchTransferError =
                    ATHLTHLocalization.choose(
                        english:
                            "This planned Ghost workout needs a route.",
                        norwegian:
                            "Denne planlagte Ghost-økten trenger en rute."
                    )
                return
            }

            do {
                try ghostRace.prepareTarget(
                    route: selectedRoute,
                    targetDurationSeconds:
                        ghostTarget
                )

                if let transfer =
                        GhostRaceStartService
                            .preparedTransfer(
                                ghostRace:
                                    ghostRace,
                                audio:
                                    workout
                                        .ghostUpdates ??
                                    .disabled
                            ) {
                    watchConnection
                        .sendGhostRace(
                            transfer
                        )
                }
            } catch {
                homeWatchTransferError =
                    error.localizedDescription
                return
            }
        } else {
            ghostRace.cancel()
            watchConnection.clearGhostRace()
        }

        // Prepare the SAME Watch payload for immediate, manual and delayed
        // starts. First HealthKit frame must already know coach/steps/HRmax.
        var coachConfiguration = PlannedWorkoutWatchBuilder.audioCoachConfiguration(
            for: workout,
            selectedRoute: selectedRoute,
            defaultConfiguration: settings.audioCoachConfiguration(
                enabled: settings.audioCoachEnabledByDefault
            )
        )
        coachConfiguration.preferIPhoneAudioWhenReachable = false
        coachConfiguration.useAcknowledgedVoiceLease = false
        let autoPause = !treadmill &&
            (workout.autoPauseEnabled ?? settings.autoPauseOutdoorWorkouts)
        var runningTransfer: WatchRunningWorkoutTransfer =
            workout.kind == .running
                ? PlannedWorkoutWatchBuilder.runningTransfer(
                    from: workout,
                    routeAlerts: routeAlerts,
                    autoPauseEnabled: autoPause
                )
                : WatchRunningWorkoutTransfer(
                    title: workout.title,
                    steps: [],
                    routeAlerts: routeAlerts,
                    targetAlerts: workout.targetAlertConfiguration,
                    autoPauseEnabled: autoPause
                )
        runningTransfer.heartRateZoneMaximumBPM =
            ATHLTHHeartRateZones.resolvedMaximumBPM(
                configured: session.onboardingProfile?.maximumHeartRateBPM,
                dateOfBirth: session.onboardingProfile?.dateOfBirth
            )

        if startMode != .immediate {
            if let plannedGearIDs = workout.gearIDs {
                gear.prepareNextWorkoutGear(Set(plannedGearIDs))
            } else {
                gear.clearPreparedWorkoutGear()
            }

            watchConnection.sendPreparedWorkout(
                WatchPreparedWorkoutTransfer(
                    id: UUID(),
                    title: workout.title,
                    summary: workout.title,
                    kind: watchKind,
                    routeID: selectedRoute?.id,
                    runningWorkout: runningTransfer,
                    audioCoach: coachConfiguration,
                    ghostRace: treadmill ? nil :
                        GhostRaceStartService.preparedTransfer(
                            ghostRace: ghostRace,
                            audio: workout.ghostUpdates ?? .disabled
                        ),
                    indoor: treadmill,
                    startMode: startMode,
                    plannedPlanID: planID,
                    plannedSessionID: planID == nil ? nil : workout.id,
                    updatedAt: Date()
                )
            )

            // The Watch itself performs the countdown. Never trigger a
            // second immediate HealthKit start for delayed/manual payloads.
            homeWatchTransferMessage = startMode.confirmationText
            return
        }

        watchConnection.sendAudioCoachConfiguration(coachConfiguration)
        watchConnection.sendRunningWorkout(runningTransfer)
        homeDirectStartInProgress = true
        homeWatchTransferError = nil

        Task { @MainActor in
            defer {
                homeDirectStartInProgress = false
            }

            do {
                let launchID = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
                defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(launchID) }
                let initiatingAccount = session.profile.userID
                try await watchConnection
                    .startWorkoutOnWatch(watchKind, indoor: treadmill)
                // Watch may have accepted HealthKit just as a logout began;
                // do not attach that recording to the new account's plan.
                guard session.profile.userID == initiatingAccount else {
                    await social.markCurrentJoinedWorkoutLaunchFailed()
                    homeWatchTransferError = ATHLTHLocalization.choose(
                        english: "Apple Watch started under the previous account.",
                        norwegian: "Apple Watch startet på forrige konto."
                    )
                    return
                }
                if let plannedGearIDs = workout.gearIDs {
                    gear.prepareNextWorkoutGear(
                        Set(plannedGearIDs)
                    )
                } else {
                    // Legacy plans keep the normal default-gear fallback.
                    gear.clearPreparedWorkoutGear()
                }

                // Refresh idempotently after Watch remote launch; queued
                // WCSession messages may arrive during route activation.
                watchConnection.sendAudioCoachConfiguration(coachConfiguration)
                watchConnection.sendRunningWorkout(runningTransfer)

                session.beginTrainingStatus(for: workout)
                reconcileHomeEarlyWorkoutStart(
                    workout, startedOnWatch: true
                )
                WorkoutLaunchCoordinator.startLinkedSpotifyIfNeeded(
                        workout: workout,
                        session: session,
                        settings: settings,
                        spotify: spotifyPlayback,
                        captureDevice: .appleWatch
                    )

                // An authorized coordinated start only becomes "started"
                // once HealthKit has actually accepted the Watch workout.
                _ = await social.confirmCurrentJoinedWorkoutStarted()
                homeWatchTransferMessage = nil
            } catch {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                homeWatchTransferError =
                    error.localizedDescription
            }
        }
    }

    private func startHomePlannedStrengthWorkout(
        _ workout: PlannedSession,
        device: WorkoutCaptureDevice,
        hybridParts: [PlannedSession]? = nil
    ) {
        // This entry point also serves calendar and iPad handoffs. Do not
        // launch a new remote HealthKit session if its account-owned local
        // checkpoint is still loading, another recording is active, or the
        // athlete has already initiated this calendar start.
        guard !homeDirectStartInProgress,
              strengthWorkout.isLoaded(for: session.profile.userID),
              !universalRecordingOccupied
        else {
            homeWatchTransferError = ATHLTHLocalization.choose(
                english: "A workout is already starting, active, or your training data is still loading.",
                norwegian: "En økt er allerede i ferd med å starte, pågår, eller treningsdataene lastes fortsatt."
            )
            return
        }

        let trackingMode: StrengthTrackingMode =
            settings.defaultStrengthTracking == .advanced
                ? .advanced
                : .simple

        let useAppleWatch = device == .appleWatch

        homeDirectStartInProgress = true
        homeWatchTransferError = nil

        if let plannedGearIDs = workout.gearIDs {
            gear.prepareNextWorkoutGear(
                Set(plannedGearIDs)
            )
        } else {
            gear.clearPreparedWorkoutGear()
        }

        if useAppleWatch {
            Task { @MainActor in
                defer {
                    homeDirectStartInProgress = false
                }
                var watchStartAcknowledged = false
                do {
                    // Hold one global launch reservation across the Watch
                    // request and the authoritative strength-store start.
                    // No second Run, Walk or Strength launch can pass while
                    // the HealthKit acknowledgement is pending.
                    let launchID = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
                    defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(launchID) }
                    let initiatingAccount = session.profile.userID
                    let outdoorHybrid = hybridParts != nil &&
                        ATHLTHHybridWorkoutLaunchPlan.isOutdoorTimedHybrid(workout)
                    try await watchConnection.startWorkoutOnWatch(
                        .strength,
                        indoor: outdoorHybrid ? false : true,
                        outdoorHybrid: outdoorHybrid
                    )
                    watchStartAcknowledged = true

                    guard session.profile.userID == initiatingAccount,
                          strengthWorkout.isLoaded(for: initiatingAccount),
                          strengthWorkout.activeWorkout == nil,
                          phoneWorkout.active == nil
                    else {
                        throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
                    }

                    let remoteSessionID = UUID()
                    if let hybridParts {
                        _ = strengthWorkout.startPlannedHybrid(
                            session: workout,
                            validatedParts: hybridParts,
                            watchSessionID: remoteSessionID,
                            trackingMode: trackingMode,
                            captureDevice: .appleWatch,
                            admissionID: launchID
                        )
                    } else {
                        strengthWorkout.start(
                            session: workout,
                            watchSessionID: remoteSessionID,
                            trackingMode: trackingMode,
                            captureDevice: .appleWatch,
                            admissionID: launchID
                        )
                    }
                    guard strengthWorkout.matchesStartedPlannedWorkout(
                        sessionID: workout.id,
                        captureDevice: .appleWatch,
                        watchSessionID: remoteSessionID
                    ) else {
                        throw NSError(
                            domain: "ATHLTH.HybridLaunch",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    ATHLTHLocalization.choose(
                                        english: "Could not prepare the combined workout. The workout was not recorded.",
                                        norwegian: "Kunne ikke klargjøre kombinasjonsøkten. Økten ble ikke registrert."
                                    )
                            ]
                        )
                    }
                    session.beginTrainingStatus(for: workout)
                    reconcileHomeEarlyWorkoutStart(
                        workout,
                        startedAt: strengthWorkout.activeWorkout?.startedAt ?? Date(),
                        startedOnWatch: true
                    )
                    _ = await social.confirmCurrentJoinedWorkoutStarted()
                    guard session.profile.userID == initiatingAccount else { return }
                    WorkoutLaunchCoordinator.startLinkedSpotifyIfNeeded(
                        workout: workout,
                        session: session,
                        settings: settings,
                        spotify: spotifyPlayback,
                        captureDevice: .appleWatch
                    )
                    showingHomeStrengthWorkout = true
                } catch {
                    await social.markCurrentJoinedWorkoutLaunchFailed()
                    // A Watch acknowledgement without an iPhone checkpoint
                    // is *not* a failed Watch recording. Do not silently
                    // restart or claim no HealthKit capture exists.
                    if watchStartAcknowledged &&
                        !strengthWorkout.matchesStartedPlannedWorkout(
                            sessionID: workout.id,
                            captureDevice: .appleWatch,
                            watchSessionID: strengthWorkout.activeWorkout?.watchSessionID
                        ) {
                        homeWatchTransferError = ATHLTHLocalization.choose(
                            english: "Apple Watch may still be recording. Check the workout on Watch before trying again.",
                            norwegian: "Apple Watch kan fortsatt registrere økten. Kontroller økten på klokken før du prøver igjen."
                        )
                    } else {
                        homeWatchTransferError = error.localizedDescription
                    }
                }
            }
        } else {
            if let hybridParts {
                _ = strengthWorkout.startPlannedHybrid(
                    session: workout,
                    validatedParts: hybridParts,
                    watchSessionID: nil,
                    trackingMode: trackingMode,
                    captureDevice: .iPhone
                )
            } else {
                strengthWorkout.start(
                    session: workout,
                    watchSessionID: nil,
                    trackingMode: trackingMode,
                    captureDevice: .iPhone
                )
            }
            guard strengthWorkout.matchesStartedPlannedWorkout(
                sessionID: workout.id,
                captureDevice: .iPhone,
                watchSessionID: nil
            ) else {
                homeDirectStartInProgress = false
                homeWatchTransferError = ATHLTHLocalization.choose(
                    english: "Could not prepare the combined workout. No recording was started.",
                    norwegian: "Kunne ikke klargjøre kombinasjonsøkten. Ingen registrering ble startet."
                )
                return
            }
            session.beginTrainingStatus(for: workout)
            reconcileHomeEarlyWorkoutStart(
                workout,
                startedAt: strengthWorkout.activeWorkout?.startedAt ?? Date()
            )
            Task { _ = await social.confirmCurrentJoinedWorkoutStarted() }
            WorkoutLaunchCoordinator.startLinkedSpotifyIfNeeded(
                        workout: workout,
                        session: session,
                        settings: settings,
                        spotify: spotifyPlayback
                    )
            homeDirectStartInProgress = false
            showingHomeStrengthWorkout = true
        }
    }

    private var homeNextUp: HomeNextUpItem? {
        let now = Date()
        let horizon = now.addingTimeInterval(24 * 60 * 60)

        var candidates: [HomeNextUpItem] = []

        if let plan = session.activePlan {
            for week in plan.weeks {
                for day in week.days {
                    for workout in day.sessions {
                        guard let start = workout.scheduledStart,
                              start >= now,
                              start <= horizon
                        else {
                            continue
                        }

                        candidates.append(
                            .workout(
                                planID: plan.id,
                                workout: workout
                            )
                        )
                    }
                }
            }
        }

        for event in community.upcomingEvents {
            guard event.event.startsAt <= horizon,
                  event.event.creatorID == session.profile.userID ||
                    community.isJoined(event)
            else {
                continue
            }

            candidates.append(.event(event))
        }

        return candidates.min {
            $0.date < $1.date
        }
    }

    @ViewBuilder
    private func homeNextUpCard(
        _ item: HomeNextUpItem
    ) -> some View {
        switch item {
        case .workout(let planID, let workout):
            NavigationLink {
                PlannedWorkoutDetailView(
                    planID: planID,
                    workout: workout,
                    isHealthCompleted: false
                )
            } label: {
                homeNextUpContent(item)
            }
            .buttonStyle(.plain)

        case .event(let event):
            NavigationLink {
                CommunityEventDetailView(eventID: event.id)
            } label: {
                homeNextUpContent(item)
            }
            .buttonStyle(.plain)
        }
    }

    private func homeNextUpContent(
        _ item: HomeNextUpItem
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 44, height: 44)
                    .background(
                        item.tint.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT UP")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep.opacity(0.72)
                        )

                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)

                    Text(
                        item.date.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var homeInsight: (
        title: String,
        detail: String,
        icon: String
    )? {
        if let score = health.recovery.score {
            switch health.recovery.state {
            case .ready:
                return (
                    "You look ready for a normal training load.",
                    health.recovery.detail,
                    "bolt.heart.fill"
                )
            case .balanced:
                return (
                    "Recovery looks balanced today.",
                    health.recovery.detail,
                    "heart.fill"
                )
            case .takeItEasy:
                return (
                    "A lighter session may fit better today.",
                    health.recovery.detail,
                    "gauge.with.dots.needle.33percent"
                )
            case .recover:
                return (
                    "Recovery signals are below your baseline.",
                    "Consider reducing intensity and prioritizing sleep and recovery today.",
                    "bed.double.fill"
                )
            case .buildingBaseline:
                break
            }

            if score >= 0 {
                return nil
            }
        }

        if health.recovery.state == .buildingBaseline {
            return (
                "ATHLTH is building your recovery baseline.",
                health.recovery.detail,
                "waveform.path.ecg"
            )
        }

        return nil
    }
}

private enum HomeNextUpItem {
    case workout(planID: UUID, workout: PlannedSession)
    case event(CommunityEventItem)

    var date: Date {
        switch self {
        case .workout(_, let workout):
            return workout.scheduledStart ?? .distantFuture
        case .event(let event):
            return event.event.startsAt
        }
    }

    var title: String {
        switch self {
        case .workout(_, let workout):
            return workout.title
        case .event(let event):
            return event.event.title
        }
    }

    var icon: String {
        switch self {
        case .workout(_, let workout):
            return workout.kind.systemImage
        case .event(let event):
            return event.event.activityType.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .workout(_, let workout):
            switch workout.kind {
            case .running: return .green
            case .walking: return .blue
            case .strength: return .purple
            case .mobility: return .teal
            case .recovery: return .indigo
            case .custom: return ATHLTHTheme.accent
            }
        case .event:
            return .purple
        }
    }
}

private struct HomeDayStatus: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let progress: Double?
    var tint: Color = ATHLTHTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            if let progress {
                ProgressView(value: progress)
                    .tint(tint)
            } else {
                Capsule()
                    .fill(ATHLTHTheme.border)
                    .frame(height: 4)
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            minHeight: 150,
            alignment: .topLeading
        )
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.055),
                    ATHLTHTheme.cardWarm.opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }
}

private struct HomeCurrentStreakCard: View {
    let activeWorkoutDays: [Date]?

    private var currentWeekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(
            of: .weekOfYear,
            for: Date()
        )?.start ?? calendar.startOfDay(for: Date())

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private func isWorkoutDay(_ date: Date) -> Bool {
        guard let activeWorkoutDays else { return false }

        let calendar = Calendar.current
        return activeWorkoutDays.contains {
            calendar.isDate($0, inSameDayAs: date)
        }
    }

    private var workoutStreak: Int {
        guard let activeWorkoutDays,
              !activeWorkoutDays.isEmpty
        else {
            return 0
        }

        let calendar = Calendar.current
        let active = Set(
            activeWorkoutDays.map {
                calendar.startOfDay(for: $0)
            }
        )
        let today = calendar.startOfDay(for: Date())

        let startDay: Date
        if active.contains(today) {
            startDay = today
        } else if let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: today
        ),
        active.contains(yesterday) {
            startDay = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = startDay

        while active.contains(cursor) {
            streak += 1

            guard let previous = calendar.date(
                byAdding: .day,
                value: -1,
                to: cursor
            ) else {
                break
            }

            cursor = previous
        }

        return streak
    }

    private var title: String {
        guard activeWorkoutDays != nil else {
            return "Streak"
        }

        if workoutStreak == 0 {
            return "Start today"
        }

        return "\(workoutStreak) day\(workoutStreak == 1 ? "" : "s")"
    }

    private var subtitle: String {
        guard activeWorkoutDays != nil else {
            return "Syncing workout days…"
        }

        switch workoutStreak {
        case 0:
            return "One workout starts your streak."
        case 1:
            return "First day — keep it going."
        default:
            return "Keep the momentum going."
        }
    }

    private var streakIsActive: Bool {
        workoutStreak > 0
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        streakIsActive
                            ? Color.orange.opacity(0.13)
                            : ATHLTHTheme.accentSoft.opacity(0.70)
                    )

                if activeWorkoutDays == nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            streakIsActive
                                ? Color.orange
                                : ATHLTHTheme.mutedText.opacity(0.72)
                        )
                }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    if streakIsActive {
                        Text("STREAK")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Color.orange.opacity(0.10),
                                in: Capsule()
                            )
                    }
                }

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(currentWeekDays, id: \.self) { day in
                    streakDay(day)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: streakIsActive
                    ? [
                        Color.orange.opacity(0.075),
                        Color.white.opacity(0.90)
                    ]
                    : [
                        Color.white.opacity(0.84),
                        ATHLTHTheme.accentSoft.opacity(0.24)
                    ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                streakIsActive
                    ? Color.orange.opacity(0.14)
                    : ATHLTHTheme.border.opacity(0.72),
                lineWidth: 1
            )
        }
        .shadow(
            color: streakIsActive
                ? Color.orange.opacity(0.055)
                : Color.black.opacity(0.025),
            radius: 12,
            x: 0,
            y: 6
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            activeWorkoutDays == nil
                ? "Workout streak is syncing"
                : workoutStreak > 0
                    ? "Current workout streak, \(workoutStreak) days"
                    : "No current workout streak"
        )
    }

    @ViewBuilder
    private func streakDay(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let completed = isWorkoutDay(day)
        let isFuture = day > calendar.startOfDay(for: Date())

        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(
                        completed
                            ? Color.orange
                            : Color.black.opacity(isFuture ? 0.025 : 0.055)
                    )
                    .frame(width: 17, height: 17)

                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }

                if isToday && !completed {
                    Circle()
                        .stroke(Color.orange.opacity(0.72), lineWidth: 1.4)
                        .frame(width: 17, height: 17)
                }
            }

            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 7, weight: isToday ? .bold : .semibold))
                .foregroundStyle(
                    isToday
                        ? ATHLTHTheme.primaryText
                        : ATHLTHTheme.mutedText
                )
        }
        .frame(width: 20)
    }
}

/// A fresh launch and an explicit draft continuation are distinct sheet
/// identities. Reusing a Boolean sheet allowed an old wizard position
/// to be carried into a new-plan launch.
struct TrainProgramCreationLaunch: Identifiable {
    let id = UUID()
    let resumesDraft: Bool
    let draftID: UUID?

    static var fresh: Self {
        Self(resumesDraft: false, draftID: UUID())
    }
    static var continueDraft: Self {
        Self(resumesDraft: true, draftID: nil)
    }

    /// Restore an interruption, never an intentionally closed draft.
    /// All drafts (including legacy nil-ID checkpoints) are eligible for
    /// their full protected-file lifetime, not an arbitrary 24-hour window.
    static func interruptedDraft(
        userID: UUID, store: ATHLTHPlanCreationDraftStore
    ) -> Self? {
        guard let record = store.records(userID: userID).first(where: {
            store.wasEditing(userID: userID, draftID: $0.draftID)
        }) else { return nil }
        return Self(resumesDraft: true, draftID: record.draftID)
    }

    /// Returning to Create Plan reopens its last unfinished checkpoint.
    /// An explicitly new plan still gets an independent UUID via fresh.
    static func reopenOrCreate(
        userID: UUID,
        store: ATHLTHPlanCreationDraftStore
    ) -> Self {
        if let recent = store.recentDraftID(userID: userID),
           store.load(userID: userID, draftID: recent) != nil {
            return Self(resumesDraft: true, draftID: recent)
        }
        // Recover orphaned checkpoints as well: a missing recent-ID pointer
        // must never make an existing plan appear deleted on next launch.
        if let saved = store.records(userID: userID).first {
            if let id = saved.draftID {
                store.setRecentDraftID(id, userID: userID)
            }
            return Self(resumesDraft: true, draftID: saved.draftID)
        }
        let launch = Self.fresh
        store.setRecentDraftID(launch.draftID, userID: userID)
        return launch
    }
}

private struct PlannedWorkoutSelection: Identifiable {
    let planID: UUID
    let workout: PlannedSession
    let isHealthCompleted: Bool

    var id: UUID { workout.id }
}

private struct ATHLTHTrainUpcomingWorkout: Identifiable {
    let planID: UUID
    let date: Date
    let workout: PlannedSession

    var id: UUID { workout.id }
}

private struct ATHLTHTrainPlanWorkspaceView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AdvancedPlannerView(
                    showsEmptyState: false
                )

                TrainingPlanManagerView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(
            ATHLTHPremiumCanvas(
                accent: Color.green.opacity(0.16)
            )
        )
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Plan overview",
                norwegian: "Planoversikt"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ATHLTHTrainView: View {
    @Binding private var navigationRequest:
        ATHLTHTrainNavigationRequest?
    // True only while the global Train tab is selected.
    private let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.athlthStudioFullscreenEditing) private var studioFullscreenEditing

    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningWorkoutLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var spotifyPlayback: SpotifyPlaybackStore
    @EnvironmentObject private var pets: ATHLTHPetStore

    @State private var selectedSection: ATHLTHTrainSection = .today
    @SceneStorage("athlth.train.selectedSection") private var persistedTrainSection = "today"
    @SceneStorage("athlth.train.selectedSectionAccount") private var persistedTrainSectionAccount = ""
    @State private var restoredTrainSectionAccount: UUID?
    // A warm foreground resume must never re-present the editor.
    // A cold view mount is allowed to recover exactly one unfinished draft.
    @State private var coldPlanRestoreCheckedAccount: UUID?
    @State private var unexpectedPlanDismissalNeedsRecovery = false
    @State private var interruptedDraftResumePending = false
    @State private var displayedTrainDay = Calendar.current.startOfDay(for: .now)
    @State private var preparedTrainUserID: UUID?
    @State private var trainHistoryReconcileTask: Task<Void, Never>?
    @State private var todayScrollPosition = ScrollPosition(edge: .top)
    @State private var planScrollPosition = ScrollPosition(edge: .top)
    @State private var progressScrollPosition = ScrollPosition(edge: .top)
    @State private var highlightedTrainPlanID: UUID?
    private struct DelayedTrainPlanStart: Identifiable {
        let id = UUID()
        let planID: UUID
        let workoutID: UUID
        let startsAt: Date
    }
    @State private var watchTransferMessage: String?
    @State private var watchTransferError: String?
    @State private var delayedPlanStart: DelayedTrainPlanStart?
    @State private var isRecheckingWatchActivity = false
    @State private var watchActivityCheckMessage: String?
    @State private var selectedStrengthSession: PlannedSession?
    @State private var selectedPlanWorkout: PlannedWorkoutSelection?
    @State private var selectedSuggestedWorkout: WorkoutTemplateCatalogEntry?
    // Recommendation snapshots are updated on source changes, never during
    // scrolling. The detail sheet keeps the exact advice the athlete tapped.
    @State private var trainDailyRecommendationInfo: HomeDailyRecommendationInfo?
    @State private var selectedTrainDailyRecommendationInfo: HomeDailyRecommendationInfo?
    @State private var selectedTrainDailySuggestedWorkout: PlannedSession?
    @State private var selectedTrainStandaloneWorkout: PlannedSession?
    @State private var trainRecommendationRefreshTask: Task<Void, Never>?
    // Reuse the immutable published catalog and search cache already shared
    // with other workout-library entry points. Avoid rebuilding all bundled
    // recipes or fetching the same remote data on the first Train tab tap.
    @ObservedObject private var trainWorkoutCatalog =
        WorkoutTemplateCatalogStore.shared
    @State private var pendingRunningTemplate: RunningWorkoutTemplate?
    @State private var pendingPlannedEnduranceWorkout: PlannedWorkoutSelection?
    @State private var showingRunQuickStart = false
    @State private var showingWalkQuickStart = false
    @State private var showingStrengthQuickStart = false
    @State private var showingCustomQuickStart = false
    @State private var customQuickInitialActivity: CustomQuickWorkoutActivity = .hiit
    @State private var isFreeTrainingQuickStart = false
    @State private var pendingCustomIPhoneQuick: CustomIPhoneQuickLaunch?
    @State private var activeCustomIPhoneQuick: CustomIPhoneQuickLaunch?
    @State private var showingStrengthWorkout = false
    @State private var selectedStructuredWorkout:
        PlannedSession?
    @State private var showingGhostHub = false
    @State private var showingLibrary = false
    @State private var showingAllWorkoutCategories = false
    @State private var pendingWorkoutCategoryAction: ATHLTHTrainAllWorkoutCategoriesSheet.Action?
    @State private var selectedTrainCompetitionActivity: ATHLTHQuickStartActivity?
    @State private var showingTrainIntervalComposer = false
    @State private var showingTrainRunningWorkoutLibrary = false
    @State private var trainRunningWorkoutSelection: RunningWorkoutTemplate?
    @State private var savedTrainIntervalTemplate: RunningWorkoutTemplate?
    @State private var personalLibrarySection: ATHLTHPersonalLibrarySection?
    @State private var showingTrainPlanWorkspace = false
    @State private var showingTrainAllPlans = false
    @State private var trainProgramCreationLaunch: TrainProgramCreationLaunch?
    @State private var newlyCreatedPlanToOpen: UUID?
    @State private var showingTrainPlanProgress = false
    @State private var showingTrainExerciseLibrary = false
    @State private var selectedTrainPlanWeekIndex: Int?

    init(
        navigationRequest:
            Binding<ATHLTHTrainNavigationRequest?> =
            .constant(nil),
        isActive: Bool = true
    ) {
        _navigationRequest = navigationRequest
        self.isActive = isActive
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if selectedSection == .progress {
                    ATHLTHTrainProgressReferenceView(
                        onReturnToToday: { selectedSection = .today },
                        onOpenPlan: { selectedSection = .plan },
                        header: premiumTrainBrandHeader(for: .progress),
                        scrollPosition: $progressScrollPosition
                    )
                    .transition(.opacity)
                } else if selectedSection == .plan {
                    trainRootScroll(for: .plan)
                        .transition(.opacity)
                } else {
                    trainRootScroll(for: .today)
                        .transition(.opacity)
                }
            }
            // A short crossfade replaces the jerky animated height changes
            // between a full-bleed Today hero and compact Plan/Progress pages.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22),
                       value: selectedSection)
            .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // Keep root Train navigation metadata small regardless of which
            // Today/Plan/Progress section is selected.
            .athlthStablePresentationBoundary()
            .navigationDestination(
                isPresented: $showingLibrary
            ) {
                ScrollView {
                    libraryContent
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        // Leave room for the floating Train tab bar, including
                        // the last item of the user's personal library.
                        .padding(.bottom, 118)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .background(
                    ATHLTHPremiumCanvas(
                        accent: ATHLTHTheme.premiumGold.opacity(0.10)
                    )
                )
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Library", norwegian: "Bibliotek"
                ))
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(item: $personalLibrarySection) { section in
                ATHLTHPersonalLibraryDestinationView(
                    section: section,
                    onStartRunning: { workout in
                        pendingPlannedEnduranceWorkout = nil
                        pendingRunningTemplate = workout
                    },
                    onOpenPlan: openPlanFromTrainingLibrary
                )
                .background(
                    ATHLTHPremiumCanvas(
                        accent: ATHLTHTheme.premiumGold.opacity(0.10)
                    )
                )
            }
            .navigationDestination(
                isPresented: $showingGhostHub
            ) {
                GhostRaceHubView()
            }
            .navigationDestination(
                isPresented: $showingTrainPlanWorkspace
            ) {
                ATHLTHTrainPlanWorkspaceView()
            }
            .navigationDestination(
                isPresented: $showingTrainExerciseLibrary
            ) {
                ExerciseLibraryView()
                    .navigationTitle(
                        ATHLTHLocalization.choose(
                            english: "Exercises",
                            norwegian: "Øvelser"
                        )
                    )
                    .navigationBarTitleDisplayMode(.inline)
            }
            .athlthStablePresentationBoundary()
            .sheet(isPresented: $showingTrainAllPlans) {
                AllTrainingPlansView()
            }
            .sheet(isPresented: $showingAllWorkoutCategories, onDismiss: {
                guard let action = pendingWorkoutCategoryAction else { return }
                pendingWorkoutCategoryAction = nil
                handleWorkoutCategoryAction(action)
            }) {
                ATHLTHTrainAllWorkoutCategoriesSheet { action in
                    pendingWorkoutCategoryAction = action
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .sheet(item: $selectedTrainCompetitionActivity) { activity in
                switch activity {
                case .running:
                    ATHLTHCompetitionCreationView(
                        initialActivity: .running,
                        advanced: settings.resolvedAdvancedSetup(for: .running)
                    )
                case .walking:
                    ATHLTHCompetitionCreationView(
                        initialActivity: .walking,
                        advanced: settings.resolvedAdvancedSetup(for: .walking)
                    )
                case .strength:
                    ATHLTHCompetitionCreationView(
                        initialActivity: .strength,
                        advanced: settings.resolvedAdvancedSetup(for: .strength)
                    )
                }
            }
            .sheet(isPresented: $showingTrainRunningWorkoutLibrary, onDismiss: {
                if let selected = trainRunningWorkoutSelection {
                    trainRunningWorkoutSelection = nil
                    pendingPlannedEnduranceWorkout = nil
                    pendingRunningTemplate = selected
                }
            }) {
                NavigationStack {
                    RunningWorkoutLibraryView(
                        selectionTitle: ATHLTHLocalization.choose(
                            english: "Choose running workout",
                            norwegian: "Velg løpeøkt"
                        ),
                        onSelect: { workout in
                            trainRunningWorkoutSelection = workout
                            showingTrainRunningWorkoutLibrary = false
                        }
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingTrainIntervalComposer, onDismiss: {
                // The interval editor closes before the running quick-start
                // sheet is presented. Preserve the newly built interval steps.
                guard let template = savedTrainIntervalTemplate else { return }
                savedTrainIntervalTemplate = nil
                pendingRunningTemplate = template
            }) {
                ATHLTHTrainIntervalComposerView { template in
                    savedTrainIntervalTemplate = template
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .athlthStudioEditor(item: $trainProgramCreationLaunch, useFullScreen: studioFullscreenEditing, onDismiss: {
                // Only an actual dismissed presentation warrants a recovery.
                // A normal background/foreground transition never enters here.
                if let planID = newlyCreatedPlanToOpen {
                    unexpectedPlanDismissalNeedsRecovery = false
                    highlightedTrainPlanID = planID
                    selectedTrainPlanWeekIndex = 0
                    selectedSection = .plan
                    newlyCreatedPlanToOpen = nil
                } else if TrainProgramCreationLaunch.interruptedDraft(
                    userID: session.profile.userID,
                    store: ATHLTHPlanCreationDraftStore()
                ) != nil {
                    // The user neither saved-and-closed nor discarded. iOS
                    // removed the sheet: keep the checkpoint and recover only
                    // this presentation when the scene is active.
                    unexpectedPlanDismissalNeedsRecovery = true
                    if scenePhase == .active {
                        restoreUnexpectedPlanDismissalIfNeeded()
                    }
                } else {
                    unexpectedPlanDismissalNeedsRecovery = false
                }
            }) { launch in
                ATHLTHTrainProgramComposerView(
                    resumesDraftOnAppear: launch.resumesDraft,
                    draftID: launch.draftID
                ) { planID in
                    newlyCreatedPlanToOpen = planID
                }
                // Swipe-to-dismiss is not a valid way to lose an unsaved plan.
                // All intentional exits use Save Draft / Discard instead.
                .interactiveDismissDisabled()
                // Keep this identity alive during an ordinary app switch.
                .id(launch.id)
            }
            .sheet(isPresented: $showingTrainPlanProgress) {
                if let plan = session.activePlan {
                    TrainingPlanProgressDetailView(planID: plan.id)
                }
            }
            .sheet(item: $selectedSuggestedWorkout) { entry in
                NavigationStack {
                    WorkoutTemplateDetailView(entry: entry)
                }
            }
            .sheet(item: $selectedTrainDailyRecommendationInfo) { info in
                HomeDailyRecommendationInfoSheet(info: info)
                    .presentationDetents([.fraction(0.82), .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
            .sheet(item: $selectedTrainStandaloneWorkout) { workout in
                HomeDailyRecommendedWorkoutSheet(
                    workout: workout,
                    isPlanWorkout: false,
                    canStartWithWatch: watchConnection.isReady &&
                        ATHLTHPlannedWorkoutCaptureRoute.resolve(
                            workout, device: .appleWatch
                        ).canUsePreparedWatchTransfer,
                    onOpenPlannedWorkout: {
                        beginTrainStandaloneWorkout(workout, device: .iPhone)
                    },
                    onStartOnPhone: {
                        beginTrainStandaloneWorkout(workout, device: .iPhone)
                    },
                    onStartOnWatch: {
                        beginTrainStandaloneWorkout(workout, device: .appleWatch)
                    },
                    onSendToWatch: {
                        beginTrainStandaloneWorkout(workout, device: .appleWatch)
                    },
                    isCalendarWorkout: true,
                    canStart: !hasOngoingTrainWorkout && !workout.isExplicitRestDay &&
                        session.recordedTimes(for: workout.id)?.endedAt == nil
                )
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedTrainDailySuggestedWorkout) { workout in
                HomeDailyRecommendedWorkoutSheet(
                    workout: workout,
                    isPlanWorkout: false,
                    // This preview is reviewed before launch. A Watch
                    // recording must be configured via its own existing
                    // device-aware start flow rather than silently starting
                    // the iPhone structured player.
                    canStartWithWatch: false,
                    onOpenPlannedWorkout: {
                        openConfirmedTrainDailyWorkout(workout)
                    },
                    onStartOnPhone: {
                        openConfirmedTrainDailyWorkout(workout)
                    },
                    onStartOnWatch: {
                        openConfirmedTrainDailyWorkout(workout)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .athlthStudioEditor(item: $selectedPlanWorkout, useFullScreen: studioFullscreenEditing) { selection in
                PlannedWorkoutDetailView(
                    planID: selection.planID,
                    workout: selection.workout,
                    isHealthCompleted: selection.isHealthCompleted
                )
                .environmentObject(session)
            }
            .sheet(item: $selectedStrengthSession) { workout in
                WorkoutStartOptionsView(
                    session: workout,
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady,
                    defaultCapture: .automatic,
                    defaultTracking: settings.defaultStrengthTracking
                ) { configuredWorkout, captureDevice, trackingMode, selectedFriends, socialMode, audioCoach, advancedConfiguration in
                    // Return the launch failure to the sheet that owns the
                    // unsaved exercise/set configuration. Do not show a global
                    // Home alert or dismiss the setup on a locked Watch.
                    do {
                        let didStart = try await WorkoutLaunchCoordinator.startStrength(
                            workout: configuredWorkout,
                            captureDevice: captureDevice,
                            trackingMode: trackingMode,
                            selectedFriends: selectedFriends,
                            participationMode: socialMode,
                            audioCoach: audioCoach,
                            advancedConfiguration: advancedConfiguration,
                            session: session,
                            settings: settings,
                            social: social,
                            strengthWorkout: strengthWorkout,
                            watchConnection: watchConnection,
                            spotify: spotifyPlayback
                        )
                        if didStart {
                            showingStrengthWorkout = true
                            return nil
                        }
                        // The iPad sends an envelope to the paired iPhone;
                        // a successful enqueue deliberately returns false.
                        if ATHLTHDeviceRole.isIPad { return nil }
                        return social.errorMessage ?? ATHLTHLocalization.choose(
                            english: "The workout could not start. Check Apple Watch and try again.",
                            norwegian: "Økten kunne ikke startes. Kontroller Apple Watch og prøv igjen."
                        )
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            .athlthStablePresentationBoundary()
            .sheet(isPresented: $showingRunQuickStart, onDismiss: {
                pendingPlannedEnduranceWorkout = nil
            }) {
                RunQuickStartSheet(
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady,
                    initialRoute: pendingPlannedEnduranceWorkout?.workout
                        .routeID.flatMap { id in
                            session.savedRoutes.first { $0.id == id }
                        },
                    plannedSession: pendingPlannedEnduranceWorkout?.workout
                ) { configuration in
                    let planOrigin = matchedPlanOriginForRun(
                        pendingPlannedEnduranceWorkout, configuration: configuration
                    )
                    // Solo workouts are local-first and must never require a
                    // social backend connection to begin recording.
                    let needsSocialLobby = !configuration.friends.isEmpty
                    let lobbyReady: Bool
                    if needsSocialLobby {
                        lobbyReady = await social.beginWorkoutWithFriends(
                        title: configuration.title,
                        kind: .running,
                        friends: configuration.friends,
                        creatorName: session.profile.displayName,
                        creatorUsername: session.profile.username,
                        invitePayload: configuration.trainTogetherInvitePayload(
                            savedRoutes: session.savedRoutes
                        ),
                        creatorCaptureDevice: configuration.captureDevice
                        )
                    } else {
                        lobbyReady = true
                    }
                    guard lobbyReady else {
                        return social.errorMessage ?? ATHLTHLocalization.choose(
                            english: "Workout could not start. Unlock Apple Watch and try again.",
                            norwegian: "Økten kunne ikke startes. Lås opp Apple Watch og prøv igjen."
                        )
                    }
                    do {
                        try await WorkoutLaunchCoordinator.startRunQuick(
                            configuration: configuration,
                            session: session,
                            settings: settings,
                            gear: gear,
                            phoneWorkout: phoneWorkout,
                            watchConnection: watchConnection,
                            spotify: spotifyPlayback,
                            ghostRace: ghostRace,
                            workoutMirroring: workoutMirroring,
                            plannedPlanID: planOrigin?.planID,
                            plannedSessionID: planOrigin?.workout.id
                        )
                        if needsSocialLobby {
                            _ = await social.confirmCurrentJoinedWorkoutStarted()
                        }
                        if configuration.captureDevice == .appleWatch {
                            watchTransferMessage = configuration.watchStartMode == .onWatch
                                ? configuration.watchStartMode.confirmationText : nil
                        }
                        return nil
                    } catch {
                        if needsSocialLobby {
                            await social.markCurrentJoinedWorkoutLaunchFailed()
                        }
                        return error.localizedDescription
                    }
                }
            }
            .sheet(isPresented: $showingWalkQuickStart, onDismiss: {
                pendingPlannedEnduranceWorkout = nil
            }) {
                WalkQuickStartSheet(
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady,
                    plannedSession: pendingPlannedEnduranceWorkout?.workout
                ) { configuration in
                    let planOrigin = validPendingPlanOrigin(
                        pendingPlannedEnduranceWorkout, kind: .walking
                    )
                    let needsSocialLobby = !configuration.friends.isEmpty
                    let lobbyReady: Bool
                    if needsSocialLobby {
                        lobbyReady = await social.beginWorkoutWithFriends(
                            title: configuration.route?.title ??
                                ATHLTHLocalization.choose(english: "Walk", norwegian: "Gåtur"),
                            kind: .walking,
                            friends: configuration.friends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username,
                            invitePayload: configuration.trainTogetherInvitePayload,
                            creatorCaptureDevice: configuration.captureDevice
                        )
                    } else {
                        lobbyReady = true
                    }
                    guard lobbyReady else {
                        return social.errorMessage ?? ATHLTHLocalization.choose(
                            english: "Workout could not start. Unlock Apple Watch and try again.",
                            norwegian: "Økten kunne ikke startes. Lås opp Apple Watch og prøv igjen."
                        )
                    }
                    do {
                        try await WorkoutLaunchCoordinator.startWalkQuick(
                            configuration: configuration,
                            settings: settings,
                            gear: gear,
                            phoneWorkout: phoneWorkout,
                            watchConnection: watchConnection,
                            spotify: spotifyPlayback,
                            workoutMirroring: workoutMirroring,
                            plannedPlanID: planOrigin?.planID,
                            plannedSessionID: planOrigin?.workout.id
                        )
                        if needsSocialLobby {
                            _ = await social.confirmCurrentJoinedWorkoutStarted()
                        }
                        return nil
                    } catch {
                        if needsSocialLobby {
                            await social.markCurrentJoinedWorkoutLaunchFailed()
                        }
                        return error.localizedDescription
                    }
                }
            }
            .sheet(
                isPresented:
                    $showingStrengthQuickStart
            ) {
                WorkoutStartOptionsView(
                    session:
                        quickStrengthSession,
                    trainingDeviceProvider:
                        watchConnection.isReady
                            ? .appleWatch
                            : .none,
                    watchConnected:
                        watchConnection.isReady,
                    defaultCapture:
                        .automatic,
                    defaultTracking:
                        settings
                            .defaultStrengthTracking
                ) { configuredWorkout, captureDevice, trackingMode, selectedFriends, socialMode, audioCoach, advancedConfiguration in
                    // Return the launch failure to the sheet that owns the
                    // unsaved exercise/set configuration. Do not show a global
                    // Home alert or dismiss the setup on a locked Watch.
                    do {
                        let didStart = try await WorkoutLaunchCoordinator.startStrength(
                            workout: configuredWorkout,
                            captureDevice: captureDevice,
                            trackingMode: trackingMode,
                            selectedFriends: selectedFriends,
                            participationMode: socialMode,
                            audioCoach: audioCoach,
                            advancedConfiguration: advancedConfiguration,
                            session: session,
                            settings: settings,
                            social: social,
                            strengthWorkout: strengthWorkout,
                            watchConnection: watchConnection,
                            spotify: spotifyPlayback
                        )
                        if didStart {
                            showingStrengthQuickStart = false
                                                        showingStrengthWorkout = true
                            return nil
                        }
                        // The iPad sends an envelope to the paired iPhone;
                        // a successful enqueue deliberately returns false.
                        if ATHLTHDeviceRole.isIPad { return nil }
                        return social.errorMessage ?? ATHLTHLocalization.choose(
                            english: "The workout could not start. Check Apple Watch and try again.",
                            norwegian: "Økten kunne ikke startes. Kontroller Apple Watch og prøv igjen."
                        )
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
            .sheet(item: $pendingRunningTemplate, onDismiss: {
                pendingPlannedEnduranceWorkout = nil
            }) { workout in
                RunQuickStartSheet(
                    trainingDeviceProvider:
                        watchConnection.isReady
                            ? .appleWatch
                            : .none,
                    watchConnected:
                        watchConnection.isReady,
                    initialWorkout: workout,
                    plannedSession: pendingPlannedEnduranceWorkout?.workout
                ) { configuration in
                    let planOrigin = matchedPlanOriginForRun(
                        pendingPlannedEnduranceWorkout, configuration: configuration
                    )
                    // Solo workouts are local-first and must never require a
                    // social backend connection to begin recording.
                    let needsSocialLobby = !configuration.friends.isEmpty
                    if needsSocialLobby {
                        let lobbyReady = await social.beginWorkoutWithFriends(
                            title: configuration.title,
                            kind: .running,
                            friends: configuration.friends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username,
                            invitePayload: configuration.trainTogetherInvitePayload(
                                savedRoutes: session.savedRoutes
                            ),
                            creatorCaptureDevice: configuration.captureDevice
                        )
                        guard lobbyReady else {
                            return social.errorMessage ?? ATHLTHLocalization.choose(
                                english: "Workout could not start. Unlock Apple Watch and try again.",
                                norwegian: "Økten kunne ikke startes. Lås opp Apple Watch og prøv igjen."
                            )
                        }
                    }
                    do {
                        try await WorkoutLaunchCoordinator.startRunQuick(
                            configuration: configuration,
                            session: session,
                            settings: settings,
                            gear: gear,
                            phoneWorkout: phoneWorkout,
                            watchConnection: watchConnection,
                            spotify: spotifyPlayback,
                            ghostRace: ghostRace,
                            workoutMirroring: workoutMirroring,
                            plannedPlanID: planOrigin?.planID,
                            plannedSessionID: planOrigin?.workout.id
                        )
                        if needsSocialLobby {
                            _ = await social.confirmCurrentJoinedWorkoutStarted()
                        }
                        if configuration.captureDevice == .appleWatch {
                            watchTransferMessage = configuration.watchStartMode == .onWatch
                                ? configuration.watchStartMode.confirmationText : nil
                        }
                        return nil
                    } catch {
                        if needsSocialLobby {
                            await social.markCurrentJoinedWorkoutLaunchFailed()
                        }
                        return error.localizedDescription
                    }
                }
            }
            .athlthStablePresentationBoundary()
            .sheet(isPresented: $showingCustomQuickStart, onDismiss: {
                // Never compete with the setup sheet's dismissal animation.
                if let launch = pendingCustomIPhoneQuick {
                    pendingCustomIPhoneQuick = nil
                    activeCustomIPhoneQuick = launch
                }
            }) {
                CustomQuickStartSheet(
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady,
                    initialActivity: customQuickInitialActivity,
                    simpleFreeTraining: isFreeTrainingQuickStart
                ) { configuration, destination in
                    let invitedFriends = social.resolvedQuickTrainPartners(
                        configuration.selectedFriendIDs
                    )

                    if invitedFriends.isEmpty {
                        // Solo keeps the existing dismissal/launch behavior.
                        switch destination {
                        case .watch:
                            startCustomWorkoutOnWatch(configuration)
                        case .phoneTimer:
                            pendingCustomIPhoneQuick = CustomIPhoneQuickLaunch(
                                configuration: configuration, mode: .timed
                            )
                        case .retrospective:
                            pendingCustomIPhoneQuick = CustomIPhoneQuickLaunch(
                                configuration: configuration, mode: .retrospective
                            )
                        }
                    } else {
                        // The real invitation lobby must finish before starting
                        // the timer/Watch. The setup sheet will already have
                        // dismissed, so the phone cover is opened directly.
                        Task { @MainActor in
                            let usesWatch: Bool
                            switch destination {
                            case .watch: usesWatch = true
                            case .phoneTimer, .retrospective: usesWatch = false
                            }
                            if usesWatch &&
                               !watchConnection.isReady {
                                watchTransferError = ATHLTHLocalization.choose(
                                    english: "Connect Apple Watch before inviting friends.",
                                    norwegian: "Koble til Apple Watch før du inviterer venner."
                                )
                                return
                            }
                            guard await social.beginWorkoutWithFriends(
                                title: configuration.title,
                                kind: .custom,
                                friends: invitedFriends,
                                creatorName: session.profile.displayName,
                                creatorUsername: session.profile.username,
                                invitePayload: configuration.trainTogetherInvitePayload,
                                creatorCaptureDevice: usesWatch
                                    ? .appleWatch : .iPhone
                            ) else {
                                if let message = social.errorMessage {
                                    watchTransferError = message
                                }
                                return
                            }

                            switch destination {
                            case .watch:
                                startCustomWorkoutOnWatch(configuration)
                            case .phoneTimer:
                                activeCustomIPhoneQuick = CustomIPhoneQuickLaunch(
                                    configuration: configuration, mode: .timed
                                )
                            case .retrospective:
                                // Retrospective logging cannot invite anyone.
                                break
                            }
                        }
                    }
                }
            }
            .fullScreenCover(item: $activeCustomIPhoneQuick) { launch in
                CustomQuickIPhoneWorkoutView(
                    configuration: launch.configuration,
                    mode: launch.mode
                )
                .environmentObject(session)
                .environmentObject(social)
            }
            .fullScreenCover(isPresented: $showingStrengthWorkout) {
                ActiveStrengthWorkoutView()
                    .environmentObject(strengthWorkout)
                    .environmentObject(session)
            }
            .fullScreenCover(
                item: $selectedStructuredWorkout
            ) { workout in
                StructuredWorkoutSessionView(
                    workout: workout,
                    linkedPlanID: structuredSourcePlanID(for: workout.id)
                )
                .environmentObject(session)
            }
            .athlthStablePresentationBoundary()
            .onAppear {
                if restoredTrainSectionAccount != session.profile.userID {
                    restoreTrainSection(for: session.profile.userID)
                }
                restoreInterruptedPlanDestinationIfNeeded()
                restoreDelayedPlanStartIfNeeded()
            }
            .onChange(of: session.profile.userID) { _, userID in
                // Never reuse another athlete's selected Train subsection or timers.
                delayedPlanStart = nil
                restoreTrainSection(for: userID)
                restoreDelayedPlanStartIfNeeded()
            }
            .onChange(of: selectedSection) { _, section in
                persistedTrainSectionAccount = session.profile.userID.uuidString
                switch section {
                case .today:
                    persistedTrainSection = "today"
                    scheduleTrainDailyRecommendationRefresh()
                case .plan: persistedTrainSection = "plan"
                case .progress: persistedTrainSection = "progress"
                }
            }
            .task(id: "\(isActive)-\(session.profile.userID.uuidString)") {
                guard isActive else { return }
                // Retain the prepared catalog and plan state across quick
                // Today/Plan/tab transitions. On account switch a new owner
                // gets a full refresh rather than another owner's cache.
                // Resolve navigation first so the selected tab can render
                // before expensive plan reconciliation and catalog refresh.
                handleNavigationRequest()
                restoreInterruptedPlanDestinationIfNeeded()
                restoreDelayedPlanStartIfNeeded()
                let userID = session.profile.userID
                // Previously plan graph reconciliation started after 160 ms,
                // right in the native floating tab-pill animation (~300 ms).
                // Existing plan data already renders immediately: do the
                // expensive account reconciliation only after navigation has
                // settled. Cancelling an abandoned Train tap skips the work.
                do {
                    try await Task.sleep(for: .milliseconds(480))
                } catch {
                    return
                }
                guard !Task.isCancelled, isActive,
                      session.profile.userID == userID else { return }
                let reconciliationID = ATHLTHPerformance.begin(
                    "TrainPostTransitionReconcile"
                )
                defer {
                    ATHLTHPerformance.end(
                        "TrainPostTransitionReconcile", id: reconciliationID
                    )
                }
                if preparedTrainUserID != userID {
                    session.refreshActivePlanForToday()
                    session.reconcilePlanLinkedPhoneWorkouts(
                        phoneWorkout.history, healthWorkouts: health.workouts
                    )
                    // Local plan and workout state is ready even if the
                    // remote exercise catalog is slow or unavailable.
                    // Never tie Train's prepared state to network success.
                    preparedTrainUserID = userID
                    await exerciseLibrary.refresh()
                } else {
                    refreshTrainDayIfChanged()
                    // Catch changes received while Train was off-screen.
                    session.reconcilePlanLinkedPhoneWorkouts(
                        phoneWorkout.history, healthWorkouts: health.workouts
                    )
                }
                scheduleTrainDailyRecommendationRefresh()
            }
            // HealthKit and phone history can publish in bursts. Coalesce
            // them rather than reconciling plans repeatedly in one frame.
            .onReceive(phoneWorkout.$history) { _ in
                scheduleTrainHistoryReconciliation()
                scheduleTrainDailyRecommendationRefresh()
            }
            .onReceive(health.$workouts) { _ in
                scheduleTrainHistoryReconciliation()
                scheduleTrainDailyRecommendationRefresh()
            }
            .onReceive(strengthWorkout.$workoutHistory) { _ in
                scheduleTrainDailyRecommendationRefresh()
            }
            .onChange(
                of: navigationRequest?.id
            ) { _, _ in
                handleNavigationRequest()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, isActive {
                    // Returning from a short app switch preserves the ENTIRE
                    // existing sheet/navigation tree, including child editors.
                    // Only if iOS actually dismissed a sheet do we recover it.
                    restoreUnexpectedPlanDismissalIfNeeded()
                    restoreDelayedPlanStartIfNeeded()
                    // The first Train activation owns the heavy daily refresh
                    // in the post-transition task above.
                    if preparedTrainUserID == session.profile.userID {
                        refreshTrainDayIfChanged()
                    }
                    resolveDelayedPlanStartIfReady()
                    scheduleTrainDailyRecommendationRefresh()
                }
            }
            .task(id: delayedPlanStart?.id) {
                guard let launch = delayedPlanStart else { return }
                let interval = launch.startsAt.timeIntervalSinceNow
                if interval > 0 {
                    try? await Task.sleep(for: .seconds(interval))
                }
                guard !Task.isCancelled else { return }
                resolveDelayedPlanStartIfReady()
            }
            // iOS signals midnight, timezone and system-clock changes here.
            // A visible Train scene must not keep yesterday's workout hero.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.significantTimeChangeNotification
            )) { _ in
                refreshTrainDayIfChanged()
            }
            .onChange(of: isActive) { _, active in
                // A restored root tab becomes active after its child onAppear;
                // this second entry guarantees the plan editor is presented.
                if active {
                    restoreInterruptedPlanDestinationIfNeeded()
                    return
                }
                trainHistoryReconcileTask?.cancel()
                trainHistoryReconcileTask = nil
                // Preserve the viewport when leaving Train. Resetting three
                // ScrollPositions during a tab transition can force layout
                // work on the main thread and cause a visible hitch.
            }
            .alert("ATHLTH", isPresented: Binding(
                get: {
                    watchTransferMessage != nil ||
                    watchTransferError != nil
                },
                set: { newValue in
                    if !newValue {
                        watchTransferMessage = nil
                        watchTransferError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    watchTransferMessage = nil
                    watchTransferError = nil
                }
            } message: {
                Text(
                    watchTransferError ??
                    watchTransferMessage ??
                    ""
                )
            }
        }
    }


    @ViewBuilder
    private func trainRootScroll(for section: ATHLTHTrainSection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                premiumTrainBrandHeader(for: section)

                if section == .plan {
                    ATHLTHTrainPlanPremiumView(
                        highlightedPlanID: highlightedTrainPlanID,
                        onStartWorkout: { planID, workout in
                            openTodayPrimaryWorkout(
                                workout,
                                planID: planID,
                                isHealthCompleted: false
                            )
                        }
                    )
                } else {
                    premiumTodayScreen
                        .padding(.top, -40)
                        .zIndex(1)
                }
            }
            .padding(.horizontal, 17)
            // Today owns the full-bleed status-bar image; the compact
            // Plan and Progress mastheads start at the same screen y.
            .padding(.top, section == .today ? 18 : 24)
            .padding(.bottom, 36)
            .containerRelativeFrame(.horizontal) { @Sendable availableWidth, _ in
                min(availableWidth, ATHLTHTrainDesign.readingWidth)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: section == .today ? .top : [])
        // Preserve *independent* scroll positions on switching. No pinned
        // or floating duplicate tabs are drawn over scrolled content.
        .scrollPosition(section == .plan ? $planScrollPosition : $todayScrollPosition)
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
    }

    @MainActor
    private func scheduleTrainHistoryReconciliation() {
        guard isActive, preparedTrainUserID == session.profile.userID else { return }
        trainHistoryReconcileTask?.cancel()
        trainHistoryReconcileTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled, isActive,
                  preparedTrainUserID == session.profile.userID else { return }
            session.reconcilePlanLinkedPhoneWorkouts(
                phoneWorkout.history, healthWorkouts: health.workouts
            )
        }
    }

    private func refreshTrainDayIfChanged() {
        let today = Calendar.current.startOfDay(for: .now)
        guard ATHLTHTrainDayChangePolicy.needsRefresh(
            displayedDay: displayedTrainDay, now: today
        ) else { return }
        displayedTrainDay = today
        session.refreshActivePlanForToday()
    }

    /// Coalesce Health/phone/strength bursts outside the Train tab animation.
    /// The recommendation never runs from an on-scroll view computation.
    private func scheduleTrainDailyRecommendationRefresh() {
        trainRecommendationRefreshTask?.cancel()
        guard isActive, selectedSection == .today else { return }
        let account = session.profile.userID
        trainRecommendationRefreshTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(450)) }
            catch { return }
            guard !Task.isCancelled, isActive,
                  selectedSection == .today,
                  session.profile.userID == account else { return }

            let history = HomeTrainingPatternAdvisor.snapshot(
                workouts: health.workouts,
                strengthHistory: strengthWorkout.workoutHistory,
                phoneHistory: phoneWorkout.history,
                dogs: pets.pets.filter { $0.userID == account }
            )
            guard history.supportsPersonalization else {
                trainDailyRecommendationInfo = nil
                return
            }
            let readiness: HomeDailyRecommendationPolicy.Readiness
            if health.recovery.score == nil {
                readiness = .unavailable
            } else {
                switch health.recovery.state {
                case .ready: readiness = .ready
                case .balanced: readiness = .balanced
                case .takeItEasy: readiness = .takeItEasy
                case .recover: readiness = .recover
                case .buildingBaseline: readiness = .unavailable
                }
            }
            let ratio: Double?
            if health.hasRequestedAuthorization {
                ratio = await health.recoveryTrendSnapshot(days: 14)
                    .trainingLoad.ratio
            } else {
                ratio = nil
            }
            guard !Task.isCancelled, isActive,
                  selectedSection == .today,
                  session.profile.userID == account else { return }

            let recorded = ATHLTHStudioRecordedWorkouts.merged(
                health: health.workouts,
                localStrength: strengthWorkout.workoutHistory
            )
            let advice = HomeDailyRecommendationPolicy.recommendation(
                readiness: readiness,
                hasWorkoutToday: false,
                trainingLoadRatio: ratio,
                trainingHistory: HomeDailyRecommendationPolicy.TrainingHistory.from(
                    workouts: recorded
                ),
                personalizedHistory: history
            )
            trainDailyRecommendationInfo = HomeDailyRecommendationInfo(
                advice: advice, history: history,
                readiness: readiness, trainingLoadRatio: ratio
            )
        }
    }

    /// Recommendation sessions remain independent: they must never write to
    /// today's plan or replace an active workout. Structured blocks are kept.
    private func openTrainDailyRecommendedWorkout(
        _ advice: HomeDailyRecommendationPolicy.Advice
    ) {
        guard !hasOngoingTrainWorkout,
              HomeTodayCalendarSchedule.workouts(
                  plan: session.activePlan,
                  standalone: session.standalonePlannedSessions
              ).isEmpty,
              !TrainTodayOverviewPolicy.hasRecordedWorkout(
                  on: Date(),
                  healthStartDates: health.workouts.map(\.startDate),
                  strengthEndDates: strengthWorkout.workoutHistory.compactMap(\.endedAt),
                  phoneCompletedDates: phoneWorkout.history.compactMap(\.end)
              )
        else { return }

        guard let workout = HomeDailyRecommendationSessionFactory.make(
            advice: advice
        ) else {
            selectedTrainDailyRecommendationInfo = trainDailyRecommendationInfo
            return
        }

        selectedTrainDailySuggestedWorkout = workout
    }

    /// Only this explicit confirmation may open the recording/setup flow.
    /// Dismiss the review sheet first so SwiftUI never presents two sheets
    /// from the same navigation stack in a single transaction.
    private func openConfirmedTrainDailyWorkout(_ workout: PlannedSession) {
        selectedTrainDailySuggestedWorkout = nil
        Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            guard !hasOngoingTrainWorkout else { return }
            if workout.kind == .strength {
                selectedStrengthSession = workout
            } else if workout.isStructuredWorkout {
                // Keep the recommended interval phases and targets intact.
                selectedStructuredWorkout = workout
            } else if workout.kind == .walking {
                showingWalkQuickStart = true
            } else if workout.kind == .running {
                if let template = workout.resolvedRunningWorkouts.first {
                    pendingRunningTemplate = template
                } else {
                    showingRunQuickStart = true
                }
            } else {
                showingLibrary = true
            }
        }
    }

    /// Verify the original calendar record before selecting an existing recorder.
    private func beginTrainStandaloneWorkout(
        _ selected: PlannedSession, device: WorkoutCaptureDevice
    ) {
        guard let original = session.standalonePlannedSessions.first(where: {
            $0.id == selected.id
        }), !original.isExplicitRestDay,
            session.recordedTimes(for: original.id)?.endedAt == nil,
            !hasOngoingTrainWorkout else { return }

        selectedTrainStandaloneWorkout = nil
        if device == .appleWatch {
            prepareTodayWorkoutForAppleWatch(original, planID: nil)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            guard !hasOngoingTrainWorkout,
                  let current = session.standalonePlannedSessions.first(where: {
                      $0.id == original.id
                  }), !current.isExplicitRestDay,
                  session.recordedTimes(for: current.id)?.endedAt == nil
            else { return }

            if current.isStructuredWorkout {
                selectedStructuredWorkout = current
            } else if let timed = ATHLTHUnifiedWorkout.timedNonCardioProjection(from: current) {
                selectedStructuredWorkout = timed
            } else if current.kind == .strength {
                selectedStrengthSession = current
            } else if current.kind == .running || current.kind == .walking {
                startTrainStandalonePhoneEndurance(current)
            } else {
                watchTransferError = ATHLTHLocalization.choose(
                    english: "No compatible recorder for this scheduled workout.",
                    norwegian: "Ingen kompatibel opptaker for denne planlagte økten."
                )
            }
        }
    }

    /// Use the same authoritative iPhone endurance store as the Home calendar.
    /// The standalone workout ID is retained even without an active plan.
    private func startTrainStandalonePhoneEndurance(_ workout: PlannedSession) {
        guard !hasOngoingTrainWorkout else { return }
        let treadmill = RunEnvironment.forPlannedSession(workout) == .treadmill
        let route = treadmill ? nil : PlannedWorkoutWatchBuilder.route(
            for: workout, routes: session.savedRoutes
        )
        guard workout.routeID == nil || route != nil || treadmill else {
            watchTransferError = ATHLTHLocalization.choose(
                english: "The planned route is missing.",
                norwegian: "Den planlagte ruten mangler."
            )
            return
        }
        let autoPause = !treadmill && (workout.autoPauseEnabled ??
            settings.autoPauseOutdoorWorkouts)
        var alerts = settings.routeAlertConfiguration
        if treadmill { alerts.enabled = false }
        let coach = PlannedWorkoutWatchBuilder.audioCoachConfiguration(
            for: workout, selectedRoute: route,
            defaultConfiguration: settings.audioCoachConfiguration(
                enabled: settings.audioCoachEnabledByDefault
            )
        )
        if !treadmill, let target = workout.ghostTargetDurationSeconds {
            guard let route else {
                watchTransferError = ATHLTHLocalization.choose(
                    english: "Ghost requires a saved route.",
                    norwegian: "Ghost krever en lagret rute."
                )
                return
            }
            do {
                try ghostRace.prepareTarget(
                    route: route, targetDurationSeconds: target
                )
            } catch {
                watchTransferError = error.localizedDescription
                return
            }
        } else {
            ghostRace.cancel()
        }
        if let gearIDs = workout.gearIDs {
            gear.prepareNextWorkoutGear(Set(gearIDs))
        } else {
            gear.clearPreparedWorkoutGear()
        }
        let transfer = workout.kind == .running
            ? PlannedWorkoutWatchBuilder.runningTransfer(
                from: workout, routeAlerts: alerts, autoPauseEnabled: autoPause
            ) : nil
        phoneWorkout.start(
            walking: workout.kind == .walking,
            route: route, title: workout.title,
            environment: treadmill ? .treadmill : .outdoor,
            audioCoach: coach, structuredWorkout: transfer,
            routeAlerts: alerts,
            ghostUpdates: treadmill ? nil : workout.ghostUpdates,
            autoPauseEnabled: autoPause,
            plannedPlanID: nil, plannedSessionID: workout.id
        )
        if let active = phoneWorkout.active {
            _ = session.recordPlannedWorkoutStarted(
                workoutID: workout.id, startedAt: active.start
            )
            watchConnection.updateLocalWorkoutActivity(
                isActive: true, title: workout.title
            )
            session.beginTrainingStatus(for: workout)
            WorkoutLaunchCoordinator.startLinkedSpotifyIfNeeded(
                workout: workout, session: session, settings: settings,
                spotify: spotifyPlayback
            )
        }
    }

    // Every Train section has exactly one shared navigation row, embedded
    // in its scrollable content rather than pinned to the viewport.
    @ViewBuilder
    private func premiumTrainBrandHeader(
        for section: ATHLTHTrainSection
    ) -> some View {
        if section == .today {
            todayPhotoHeader
        } else {
            ATHLTHTrainHeaderRow(selection: $selectedSection)
                // Today cover starts at x = 20; Plan and Progress must
                // align both the selector and eyebrow to that same inset.
                .padding(.horizontal, section == .plan ? 3 : 4)
        }
    }

    private var todayPhotoHeader: some View {
        ATHLTHTrainTodayCoverView(
            day: displayedTrainDay, selection: $selectedSection
        )
        .padding(.horizontal, -17)
        .padding(.top, -18)
    }

    private var activeTrainWorkoutKind: WorkoutKind? {
        if let workout = phoneWorkout.active {
            return workout.walking ? .walking : .running
        }
        if strengthWorkout.activeWorkout != nil { return .strength }
        // Read the original timed/structured checkpoint through the same
        // universal activity interpretation as the workout engine.
        if let timed = ATHLTHManualTimedCapture.current(
            for: session.profile.userID
        ), let active = ATHLTHUniversalActiveCapture.manual(timed) {
            return active.activityCategory == "yoga" ||
                active.activityCategory == "mobility" ? .mobility : .custom
        }
        if let checkpoint = ATHLTHStructuredCaptureAdmission.activeCheckpoint(
            for: session.profile.userID
        ), let active = ATHLTHUniversalActiveCapture.structured(checkpoint) {
            switch active.activityCategory {
            case "running", "treadmill": return .running
            case "walking": return .walking
            case "strength": return .strength
            case "mobility": return .mobility
            case "recovery": return .recovery
            default: return .custom
            }
        }
        // An unconfirmed Watch-only session has no trustworthy activity kind.
        return nil
    }

    // One shared launch gate across every Train and Calendar surface.
    private var universalRecordingOccupied: Bool {
        ATHLTHUniversalWorkoutAdmission.isOccupied(
            phone: phoneWorkout, strength: strengthWorkout,
            remoteWatchActive: watchConnection.hasActiveWatchWorkout
        )
    }

    private var hasOngoingTrainWorkout: Bool {
        universalRecordingOccupied
    }

    @ViewBuilder
    private var activeTrainWorkoutCard: some View {
        if phoneWorkout.hasRecoveredActiveWorkout ||
            strengthWorkout.hasRecoveredActiveWorkout {
            // Checkpoint review is the main card, not a second banner.
            unfinishedWorkoutRecoveryCards
        } else if let workout = phoneWorkout.active {
            liveTrainCard(
                title: workout.title,
                source: "iPhone",
                symbol: workout.walking ? "figure.walk" : "figure.run",
                activityLabel: workout.walking ? "Gåing" : "Løping",
                detail: ATHLTHTrainLiveCardMetrics.phoneDetail(workout),
                elapsed: { workout.elapsed(at: $0) },
                elapsedCaption: "Aktiv tid"
            ) {
                phoneWorkout.presentWorkout()
            }
        } else if let workout = strengthWorkout.activeWorkout {
            liveTrainCard(
                title: workout.title,
                source: workout.captureDevice.title,
                symbol: "dumbbell",
                activityLabel: "Styrke",
                detail: ATHLTHTrainLiveCardMetrics.strengthDetail(
                    workout,
                    exerciseIndex: strengthWorkout.currentExerciseIndex,
                    setIndex: strengthWorkout.currentSetIndex,
                    restEndsAt: strengthWorkout.restEndsAt
                ),
                elapsed: { max(0, $0.timeIntervalSince(workout.startedAt)) },
                elapsedCaption: "Siden start",
                restEndsAt: strengthWorkout.restEndsAt
            ) {
                strengthWorkout.acknowledgeRecoveredWorkout()
                showingStrengthWorkout = true
            }
        } else if let structuredID =
            ATHLTHStructuredCaptureAdmission.activeWorkoutID,
            let structured = (
                session.standalonePlannedSessions +
                ([session.activePlan].compactMap { $0 } + session.scheduledPlans)
                    .flatMap(\.weeks).flatMap(\.days).flatMap(\.sessions)
            ).first(where: { $0.id == structuredID }) {
            Button {
                selectedStructuredWorkout = ATHLTHUnifiedWorkout
                    .timedNonCardioProjection(from: structured) ?? structured
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Continue structured workout",
                        norwegian: "Fortsett strukturert økt"
                    ) + " · " + structured.title,
                    systemImage: "play.circle.fill"
                )
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        } else if ATHLTHStructuredCaptureAdmission.hasActiveCapture {
            Text(ATHLTHLocalization.choose(
                english: "A structured workout is still active. Reopen its original plan to resume or discard it.",
                norwegian: "En strukturert økt pågår fortsatt. Åpne den opprinnelige planen for å fortsette eller forkaste."
            ))
            .font(.subheadline)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
        } else if let timed = ATHLTHManualTimedCapture.current(
            for: session.profile.userID
        ) {
            liveTrainCard(
                title: timed.recoveryConfiguration.title,
                source: "iPhone",
                symbol: timed.activity.systemImage,
                activityLabel: timed.activity.localizedTitle,
                detail: ATHLTHLocalization.choose(
                    english: "Phone-timed session · manual measurements",
                    norwegian: "Tidsmålt økt · øvrige målinger er manuelle"
                ),
                elapsed: {
                    ATHLTHUniversalActiveCapture.manual(timed, at: $0)?
                        .elapsedSeconds ?? timed.elapsed(at: $0)
                },
                elapsedCaption: "Målt tid",
                livePhase: { now in
                    guard let active = ATHLTHUniversalActiveCapture.manual(
                        timed, at: now
                    ) else { return nil }
                    if let index = active.stageIndex,
                       let total = active.stageCount {
                        let current = min(total, index + 1)
                        let phase = active.phase == .paused
                            ? ATHLTHLocalization.choose(
                                english: "Paused", norwegian: "Pauset")
                            : active.phase == .recovery
                            ? ATHLTHLocalization.choose(
                                english: "Rest", norwegian: "Pause")
                            : ATHLTHLocalization.choose(
                                english: "Work", norwegian: "Arbeid")
                        return ATHLTHLocalization.choose(
                            english: "Step \(current) of \(total) · \(phase)",
                            norwegian: "Del \(current) av \(total) · \(phase)"
                        )
                    }
                    if active.phase == .paused {
                        return ATHLTHLocalization.choose(
                            english: "Paused", norwegian: "Pauset")
                    }
                    return nil
                }
            ) {
                activeCustomIPhoneQuick = CustomIPhoneQuickLaunch(
                    configuration: timed.recoveryConfiguration,
                    mode: .timed
                )
            }
        } else if ATHLTHManualTimedCapture.hasActiveCapture {
            // An unreadable checkpoint protects the last saved bytes.
            // Never offer a new workout or erase it without user intent.
            Text(ATHLTHLocalization.choose(
                english: "A previous timed workout could not be restored. Its original checkpoint has been protected.",
                norwegian: "En tidligere tidsmålt økt kunne ikke gjenopprettes. Originalcheckpointen er beskyttet."
            ))
            .font(.subheadline)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
        } else if (watchConnection.hasActiveWatchWorkout ||
                   ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive),
                  phoneWorkout.active == nil,
                  strengthWorkout.activeWorkout == nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 22))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: watchConnection.reachable || ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive
                                ? "Workout active on Apple Watch"
                                : "Apple Watch workout status unconfirmed",
                            norwegian: watchConnection.reachable || ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive
                                ? "Aktiv økt på Apple Watch"
                                : "Øktstatus på Apple Watch er ikke bekreftet"
                        ))
                        .font(.subheadline.weight(.semibold))
                        Text(ATHLTHLocalization.choose(
                            english: "Check the Watch before starting another workout.",
                            norwegian: "Kontroller klokken før du starter en ny økt."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }

                if watchConnection.hasActiveWatchWorkout {
                    Button {
                        recheckActiveWatchWorkout()
                    } label: {
                        HStack(spacing: 8) {
                            if isRecheckingWatchActivity {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "Check workout status again",
                                norwegian: "Kontroller øktstatus på nytt"
                            ))
                            .font(.caption.weight(.semibold))
                        }
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRecheckingWatchActivity)
                }
                if let watchActivityCheckMessage {
                    Text(watchActivityCheckMessage)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
        }
    }

    private func recheckActiveWatchWorkout() {
        guard !isRecheckingWatchActivity else { return }
        isRecheckingWatchActivity = true
        watchActivityCheckMessage = nil
        watchConnection.connect()
        Task { @MainActor in
            let isClear = await watchConnection.confirmNoActiveWatchWorkout()
            if isClear {
                // The active-activity card disappears when the Watch reports
                // completion. Never clear the cached lock without evidence.
                watchActivityCheckMessage = nil
            } else {
                watchActivityCheckMessage = ATHLTHLocalization.choose(
                    english: "ATHLTH cannot confirm that this workout ended. Open ATHLTH on Apple Watch and check there, then try again.",
                    norwegian: "ATHLTH kan ikke bekrefte at økten er avsluttet. Åpne ATHLTH på Apple Watch og kontroller der før du prøver igjen."
                )
            }
            isRecheckingWatchActivity = false
        }
    }

    private func liveTrainCard(
        title: String,
        source: String,
        symbol: String,
        activityLabel: String,
        detail: String?,
        elapsed: @escaping (Date) -> TimeInterval,
        elapsedCaption: String,
        restEndsAt: Date? = nil,
        livePhase: ((Date) -> String?)? = nil,
        onContinue: @escaping () -> Void
    ) -> some View {
        Button(action: onContinue) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 48, height: 48)
                        .background(ATHLTHTrainDesign.paleGold, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "WORKOUT IN PROGRESS",
                            norwegian: "ØKT PÅGÅR"
                        ))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        Text(title)
                            .font(ATHLTHTrainDesign.sectionTitle)
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(activityLabel) · \(source)")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(ATHLTHTrainDesign.rule).frame(height: 1)
                VStack(alignment: .leading, spacing: 16) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = Int(max(0, elapsed(context.date)))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                                .font(.system(.largeTitle, design: .serif))
                                .monospacedDigit()
                            Text(elapsedCaption)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTrainDesign.secondary)
                            if let phase = livePhase?(context.date) {
                                Text(phase)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                    .monospacedDigit()
                            }
                            if let restEndsAt, restEndsAt > context.date {
                                Text(ATHLTHLocalization.choose(
                                    english: "Rest", norwegian: "Pause"
                                ) + " \(Int(ceil(restEndsAt.timeIntervalSince(context.date)))) s")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Label(ATHLTHLocalization.choose(
                        english: "Continue workout", norwegian: "Fortsett økten"
                    ), systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.vertical, 6)
                        .background(ATHLTHTrainDesign.ink, in: RoundedRectangle(cornerRadius: 16))
                }
                .foregroundStyle(ATHLTHTrainDesign.ink)
            }
            .padding(22)
            .athlthTrainPaper(emphasized: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Return to the current workout",
            norwegian: "Åpner økten som allerede pågår"
        ))
    }

    private func restoreTrainSection(for userID: UUID) {
        let section = ATHLTHTrainSectionContinuityPolicy.restoredSection(
            persistedTrainSection,
            persistedAccountID: persistedTrainSectionAccount,
            currentAccountID: userID
        )
        // Bind the owner before changing the selected SwiftUI state.
        persistedTrainSectionAccount = userID.uuidString
        persistedTrainSection = section
        restoredTrainSectionAccount = userID
        switch section {
        case "plan": selectedSection = .plan
        case "progress": selectedSection = .progress
        default: selectedSection = .today
        }
    }

    /// Runs once on a cold Train mount. It MUST NOT run again merely because
    /// the scene returns from background, since that would change navigation.
    private func restoreInterruptedPlanDestinationIfNeeded() {
        guard isActive, session.signedIn else { return }
        let userID = session.profile.userID
        let isFirstMount = coldPlanRestoreCheckedAccount != userID
        guard isFirstMount else { return }
        coldPlanRestoreCheckedAccount = userID
        guard ATHLTHPlanEditorContinuityPolicy.shouldRestore(
            coldMount: true,
            unexpectedlyDismissed: false,
            editorIsPresented: trainProgramCreationLaunch != nil
        ) else { return }
        presentInterruptedPlanIfNeeded(userID: userID)
    }

    /// Reserve warm recovery exclusively for a sheet that iOS actually
    /// dismissed. On a normal 10-second app switch this flag stays false.
    private func restoreUnexpectedPlanDismissalIfNeeded() {
        guard ATHLTHPlanEditorContinuityPolicy.shouldRestore(
            coldMount: false,
            unexpectedlyDismissed: unexpectedPlanDismissalNeedsRecovery,
            editorIsPresented: trainProgramCreationLaunch != nil
        ) else { return }
        presentInterruptedPlanIfNeeded(userID: session.profile.userID)
    }

    private func presentInterruptedPlanIfNeeded(userID: UUID) {
        guard isActive, session.signedIn, scenePhase == .active,
              session.profile.userID == userID,
              trainProgramCreationLaunch == nil,
              !interruptedDraftResumePending else { return }
        guard let launch = TrainProgramCreationLaunch.interruptedDraft(
            userID: userID, store: ATHLTHPlanCreationDraftStore()
        ) else {
            unexpectedPlanDismissalNeedsRecovery = false
            return
        }
        interruptedDraftResumePending = true
        // This selection changes only on cold launch or actual dismissal,
        // never on a normal foreground resume.
        selectedSection = .plan
        Task { @MainActor in
            defer { interruptedDraftResumePending = false }
            await Task.yield()
            guard isActive, session.signedIn, scenePhase == .active,
                  session.profile.userID == userID,
                  trainProgramCreationLaunch == nil else { return }
            unexpectedPlanDismissalNeedsRecovery = false
            trainProgramCreationLaunch = launch
        }
    }

    /// Reopen the same unfinished plan after closing the composer. Finished
    /// and explicitly deleted drafts are never resurrected; the next tap
    /// starts a genuinely independent plan.
    private func beginFreshTrainingPlan() {
        // Explicit user navigation owns this presentation, not scenePhase.
        unexpectedPlanDismissalNeedsRecovery = false
        trainProgramCreationLaunch = TrainProgramCreationLaunch.reopenOrCreate(
            userID: session.profile.userID,
            store: ATHLTHPlanCreationDraftStore()
        )
    }

    /// Only *completed* sessions from the last month may steer the
    /// no-plan recommendation; never infer an activity from an active recording.
    private var lastCompletedTrainKind: WorkoutKind? {
        // Scan histories once without allocating/sorting a combined array.
        // This is evaluated while SwiftUI builds the Train Today screen.
        let now = Date()
        let earliest = now.addingTimeInterval(-30 * 86_400)
        var latestDate = earliest
        var latestKind: WorkoutKind?

        for workout in phoneWorkout.history {
            guard let end = workout.end, end >= latestDate,
                  end <= now else { continue }
            latestDate = end
            latestKind = workout.walking ? .walking : .running
        }
        for workout in strengthWorkout.workoutHistory {
            guard let end = workout.endedAt, end >= latestDate,
                  end <= now else { continue }
            latestDate = end
            latestKind = .strength
        }
        for workout in health.workouts {
            let date = workout.startDate
            guard date >= latestDate, date <= now else { continue }
            let kind: WorkoutKind
            if workout.activity == .running {
                kind = .running
            } else if workout.activity == .strength {
                kind = .strength
            } else if workout.activity.rawValue.localizedCaseInsensitiveContains("walk") {
                kind = .walking
            } else {
                continue
            }
            latestDate = date
            latestKind = kind
        }
        return latestKind
    }

    @ViewBuilder
    private var premiumTodayScreen: some View {
        let active = session.activePlan
        let sessions = active.map { todaySessions(in: $0) } ?? []
        let planSessionIDs = Set(sessions.map(\.id))
        let standaloneToday = HomeTodayCalendarSchedule.workouts(
            plan: nil, standalone: session.standalonePlannedSessions, on: Date()
        ).filter {
            !$0.isExplicitRestDay && !planSessionIDs.contains($0.id)
        }
        let completedIDs: Set<UUID> = active.map {
            completedTodaySessionIDs(
                planID: $0.id,
                sessions: sessions
            )
        } ?? []
        let healthIDs: Set<UUID> = active.map {
            healthCompletedTodaySessionIDs(
                planID: $0.id,
                sessions: sessions,
                completedIDs: completedIDs
            )
        } ?? []
        let progress = active.map {
            session.trainingPlanProgress(
                $0,
                healthWorkouts: health.workouts,
                strengthHistory: strengthWorkout.workoutHistory
            ).completionFraction
        } ?? 0

        let today = Date()
        let hasRecordedWorkoutToday = TrainTodayOverviewPolicy.hasRecordedWorkout(
            on: today,
            healthStartDates: health.workouts.map(\.startDate),
            strengthEndDates: strengthWorkout.workoutHistory.compactMap(\.endedAt),
            phoneCompletedDates: phoneWorkout.history.compactMap(\.end)
        )

        let readiness = TrainTodayOverviewPolicy.reliableReadiness(
            health.recovery,
            sleepEnd: health.sleep.sleepEnd,
            hrvDate: health.heart.hrvDate,
            restingHeartRateDate: health.heart.restingHeartRateDate,
            now: today
        )

        VStack(alignment: .leading, spacing: 10) {
            if let delay = delayedPlanStart {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Scheduled workout start",
                            norwegian: "Utsatt oppstart"))
                            .font(.caption.weight(.semibold))
                        Text(delay.startsAt, style: .time)
                            .font(.caption2)
                    }
                    Spacer(minLength: 4)
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) {
                        cancelDelayedPlanStart()
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(12)
                .background(
                    ATHLTHTrainDesign.paleGold.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }

            ATHLTHTrainTodayPremiumView(
                workoutCatalog: trainWorkoutCatalog,
                isActive: isActive,
            plan: active,
            sessions: sessions,
            standaloneSessions: standaloneToday,
            completedIDs: completedIDs,
            healthCompletedIDs: healthIDs,
            completionFraction: progress,
            planPosition: active.map {
                trainTodayPlanOverviewText($0)
            } ?? "",
            hasActiveWorkout: hasOngoingTrainWorkout,
            activeWorkoutKind: activeTrainWorkoutKind,
            lastCompletedWorkoutKind: lastCompletedTrainKind,
            activeWorkoutCard: hasOngoingTrainWorkout
                ? AnyView(activeTrainWorkoutCard) : nil,
            hasRecordedWorkoutToday: hasRecordedWorkoutToday,
            dailyRecommendation:
                ATHLTHTrainTodayDailyAdvicePolicy.isVisible(
                    scheduledItemCount: HomeTodayCalendarSchedule.workouts(
                        plan: active,
                        standalone: session.standalonePlannedSessions,
                        on: today
                    ).count,
                    hasRecordedWorkoutToday: hasRecordedWorkoutToday,
                    hasActiveWorkout: hasOngoingTrainWorkout,
                    hasPersonalizedAdvice: trainDailyRecommendationInfo != nil
                ) ? trainDailyRecommendationInfo?.advice : nil,
            onShowDailyRecommendationDetails: {
                selectedTrainDailyRecommendationInfo = trainDailyRecommendationInfo
            },
            onChooseDailyRecommendedWorkout: { advice in
                openTrainDailyRecommendedWorkout(advice)
            },
            todaysReadiness: readiness,
            latestHealthWeightKilograms: health.personalDetails.weightKilograms,
            onChooseSuggestedWorkout: { selectedSuggestedWorkout = $0 },
            onOpenPlan: { selectedSection = .plan },
            onCreatePlan: { beginFreshTrainingPlan() },
            onOpenLibrary: { showingLibrary = true },
            onOpenWorkouts: {
                guard !hasOngoingTrainWorkout else { return }
                showingAllWorkoutCategories = true
            },
            onStartWorkout: { workout, healthCompleted in
                guard let active else { return }
                openTodayPrimaryWorkout(
                    workout,
                    planID: active.id,
                    isHealthCompleted: healthCompleted
                )
            },
            onWorkoutDetails: { workout, healthCompleted in
                guard let active else { return }
                selectedPlanWorkout = PlannedWorkoutSelection(
                    planID: active.id,
                    workout: workout,
                    isHealthCompleted: healthCompleted
                )
            },
            onOpenStandaloneWorkout: { workout in
                selectedTrainStandaloneWorkout = workout
            },
            onSendWorkoutToWatch: { workout in
                guard let active else { return }
                prepareTodayWorkoutForAppleWatch(workout, planID: active.id)
            },
            onDelayWorkout: { workout, seconds in
                guard let active else { return }
                scheduleTodayWorkoutStart(workout, planID: active.id, after: seconds)
            },
            onAcceptAlternative: { planned, suggestion in
                guard !hasOngoingTrainWorkout,
                      let plan = session.activePlan,
                      let current = plan.weeks.flatMap(\.days)
                        .flatMap(\.sessions)
                        .first(where: { $0.id == planned.id }),
                      !current.isExplicitRestDay,
                      current.dailyAlternativeOriginal == nil,
                      !session.isPlanSessionSkipped(
                        planID: plan.id, sessionID: current.id),
                      !session.isPlanSessionCompleted(
                        planID: plan.id, sessionID: current.id,
                        healthWorkouts: health.workouts,
                        strengthHistory: strengthWorkout.workoutHistory
                      )
                else { return }
                let checkIn = RecoverySorenessStore()
                let freshSignals = ATHLTHDailyWorkoutAlternativeAdvisor.Signals(
                    energy: checkIn.todayEnergy,
                    stress: checkIn.todayStress,
                    overallSoreness: checkIn.todayOverallSoreness,
                    muscleRatings: checkIn.todayRatings,
                    readiness: readiness
                )
                guard ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
                    for: current, signals: freshSignals
                ).contains(where: {
                    $0.choice == suggestion.choice &&
                    $0.distanceKilometers == suggestion.distanceKilometers
                }) else { return }
                let alternative = ATHLTHDailyWorkoutAlternativeAdvisor.replacing(
                    current, with: suggestion)
                session.updateSession(alternative, inPlan: plan.id)
            },
            onUndoAlternative: { planned in
                guard !hasOngoingTrainWorkout,
                      let plan = session.activePlan,
                      let current = plan.weeks.flatMap(\.days)
                        .flatMap(\.sessions)
                        .first(where: { $0.id == planned.id }),
                      let original = current.dailyAlternativeOriginal,
                      !session.isPlanSessionSkipped(
                        planID: plan.id, sessionID: current.id),
                      !session.isPlanSessionCompleted(
                        planID: plan.id, sessionID: current.id,
                        healthWorkouts: health.workouts,
                        strengthHistory: strengthWorkout.workoutHistory
                      )
                else { return }
                session.updateSession(original.restoring(current), inPlan: plan.id)
            },
            onQuickTrain: { kind in handleQuickStart(kind) },
            onQuickCycling: { startCyclingQuick() },
            onQuickCustom: { activity in startCustomQuick(as: activity) },
            onQuickFreeTraining: { startFreeTrainingQuick() },
            onGhostRace: { showingGhostHub = true }
        )
        // Reset date-specific check-in and proposed workout state exactly
        // once when the calendar day changes; never reset the live recorder.
        .id(displayedTrainDay)
        }
    }

    private func todayHeroMetric(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))

                Text(title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.7)
            }
            .foregroundStyle(
                Color.white.opacity(0.50)
            )

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayHeroDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 36)
            .padding(.horizontal, 9)
    }

    private func todayExercisePreviewRow(
        _ exercise: PlannedExercise,
        index: Int
    ) -> some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 24, height: 24)
                .background(
                    ATHLTHTheme.champagne,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.embeddedExercise.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(
                    [
                        exercise.compactTargetSummary,
                        exercise.compactLoadSummary,
                        exercise.restSeconds.map {
                            ATHLTHLocalization.choose(
                                english: "\($0)s rest",
                                norwegian: "\($0)s hvile"
                            )
                        }
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption2)
                .foregroundStyle(
                    Color.white.opacity(0.60)
                )
                .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 7)
    }

    private func todayRecoveryDayCard(
        _ plan: TrainingPlan
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.recoveryBlue)
                        .frame(width: 50, height: 50)
                        .background(
                            ATHLTHTheme.recoveryBlueSoft,
                            in: RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "RECOVERY DAY",
                                norwegian: "HVILEDAG"
                            )
                        )
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Nothing planned today",
                                norwegian: "Ingen økt planlagt i dag"
                            )
                        )
                        .font(
                            .system(
                                size: 24,
                                weight: .bold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(plan.title)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()
                }

                if let next =
                    trainUpcomingWorkouts(
                        in: plan,
                        limit: 1
                    )
                    .first {
                    Button {
                        selectedPlanWorkout =
                            PlannedWorkoutSelection(
                                planID: next.planID,
                                workout: next.workout,
                                isHealthCompleted: false
                            )
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName:
                                    next.workout.kind.systemImage
                            )
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                trainPlanKindTint(
                                    next.workout.kind
                                )
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                trainPlanKindTint(
                                    next.workout.kind
                                )
                                .opacity(0.10),
                                in: RoundedRectangle(
                                    cornerRadius: 11,
                                    style: .continuous
                                )
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Next workout",
                                        norwegian: "Neste økt"
                                    )
                                )
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(ATHLTHTheme.mutedText)

                                Text(next.workout.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                            }

                            Spacer()

                            Text(
                                trainUpcomingDateText(next.date)
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .padding(12)
                        .background(
                            Color.white.opacity(0.55),
                            in: RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func todayToolTile(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(2)
            }

            Spacer(minLength: 2)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.84),
                    ATHLTHTheme.cardWarm.opacity(0.40)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.88),
                lineWidth: 0.8
            )
        }
    }

    private func todayWorkoutFocusSummary(
        _ workout: PlannedSession
    ) -> String {
        if let structuredSummary = ATHLTHWorkoutContentSummary.text(for: workout) {
            return structuredSummary
        }
        if !workout.exercises.isEmpty {
            return ATHLTHLocalization.choose(
                english:
                    "\(workout.exercises.count) exercises",
                norwegian:
                    "\(workout.exercises.count) øvelser"
            )
        }

        if let distance =
            workout.targetDistanceKilometers {
            return String(
                format: "%.1f km",
                distance
            )
        }

        if let running =
            workout.resolvedRunningWorkouts.first {
            return running.type.title
        }

        switch workout.kind {
        case .recovery:
            return ATHLTHLocalization.choose(
                english: "Recovery",
                norwegian: "Restitusjon"
            )
        case .mobility:
            return ATHLTHLocalization.choose(
                english: "Mobility",
                norwegian: "Mobilitet"
            )
        default:
            return workout.kind.title
        }
    }

    private func todayPrimaryActionTitle(
        _ workout: PlannedSession
    ) -> String {
        switch workout.kind {
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Start workout",
                norwegian: "Start økt"
            )
        case .running:
            return workout.resolvedRunningWorkouts.first != nil
                ? ATHLTHLocalization.choose(
                    english: "Start workout",
                    norwegian: "Start økt"
                )
                : ATHLTHLocalization.choose(
                    english: "View workout",
                    norwegian: "Se økten"
                )
        default:
            return workout.isStructuredWorkout
                ? ATHLTHLocalization.choose(
                    english: "Start workout",
                    norwegian: "Start økt"
                )
                : ATHLTHLocalization.choose(
                    english: "View workout",
                    norwegian: "Se økten"
                )
        }
    }

    // A change from the planned run to a different quick-start mode
    // must not silently credit an unrelated workout to the plan.
    // The quick-start sheet may stay open while the plan changes elsewhere.
    // Never attach recorded evidence to a removed, skipped or finished session.
    private func validPendingPlanOrigin(
        _ origin: PlannedWorkoutSelection?,
        kind: WorkoutKind
    ) -> PlannedWorkoutSelection? {
        guard let origin,
              let current = session.trainingPlan(withID: origin.planID)?
                .weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == origin.workout.id }),
              current.kind == kind,
              !session.isPlanSessionSkipped(
                planID: origin.planID, sessionID: current.id
              ),
              !session.isPlanSessionCompleted(
                planID: origin.planID,
                sessionID: current.id,
                healthWorkouts: health.workouts,
                strengthHistory: strengthWorkout.workoutHistory
              ) else { return nil }
        return PlannedWorkoutSelection(
            planID: origin.planID,
            workout: current,
            isHealthCompleted: false
        )
    }

    private func matchedPlanOriginForRun(
        _ origin: PlannedWorkoutSelection?,
        configuration: RunQuickStartConfiguration
    ) -> PlannedWorkoutSelection? {
        guard let origin = validPendingPlanOrigin(origin, kind: .running) else {
            return nil
        }
        let planned = origin.workout
        if let expected = planned.resolvedRunningWorkouts.first {
            guard configuration.mode == .structured,
                  configuration.workout?.id == expected.id else {
                return nil
            }
        } else if let routeID = planned.routeID {
            guard configuration.mode == .route,
                  configuration.route?.id == routeID else {
                return nil
            }
        } else {
            guard configuration.mode == .free else {
                return nil
            }
        }
        return origin
    }

    /// Sending a planned session never calls HealthKit's Watch start API.
    /// The prepared card is durable and launches only on Watch START.
    /// A deferred start is local to the user and never creates a HealthKit
    /// session while the phone is locked or the application is backgrounded.
    private func scheduleTodayWorkoutStart(
        _ selected: PlannedSession, planID: UUID, after seconds: TimeInterval
    ) {
        guard seconds >= 1,
              let workout = session.trainingPlan(withID: planID)?
                .weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == selected.id }),
              !workout.isExplicitRestDay,
              !hasOngoingTrainWorkout,
              !session.isPlanSessionSkipped(planID: planID, sessionID: workout.id),
              !session.isPlanSessionCompleted(
                  planID: planID, sessionID: workout.id,
                  healthWorkouts: health.workouts,
                  strengthHistory: strengthWorkout.workoutHistory)
        else { return }

        cancelDelayedPlanStart()
        let startsAt = Date().addingTimeInterval(seconds)
        delayedPlanStart = DelayedTrainPlanStart(
            planID: planID,
            workoutID: workout.id,
            startsAt: startsAt
        )
        ATHLTHTrainDelayedStartStore.save(
            .init(planID: planID, workoutID: workout.id, startsAt: startsAt),
            for: session.profile.userID
        )
        PlannedWorkoutReminderScheduler.scheduleDelayedStart(
            workout, after: seconds
        )
    }

    private func cancelDelayedPlanStart() {
        if let launch = delayedPlanStart {
            PlannedWorkoutReminderScheduler.cancelDelayedStart(
                launch.workoutID
            )
        }
        delayedPlanStart = nil
        ATHLTHTrainDelayedStartStore.remove(for: session.profile.userID)
    }

    /// A delayed start survives a terminated scene, but never starts HealthKit
    /// or replays an uncertain recording when the application wakes up.
    private func restoreDelayedPlanStartIfNeeded() {
        guard delayedPlanStart == nil,
              let checkpoint = ATHLTHTrainDelayedStartStore.load(
                for: session.profile.userID
              ) else { return }
        delayedPlanStart = DelayedTrainPlanStart(
            planID: checkpoint.planID,
            workoutID: checkpoint.workoutID,
            startsAt: checkpoint.startsAt
        )
    }

    private func resolveDelayedPlanStartIfReady() {
        guard let launch = delayedPlanStart,
              Date() >= launch.startsAt,
              scenePhase == .active else { return }
        cancelDelayedPlanStart()
        guard !hasOngoingTrainWorkout,
              let workout = session.trainingPlan(withID: launch.planID)?
                .weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == launch.workoutID }),
              !session.isPlanSessionSkipped(
                planID: launch.planID, sessionID: launch.workoutID)
        else { return }
        openTodayPrimaryWorkout(
            workout, planID: launch.planID, isHealthCompleted: false
        )
    }

    private func prepareTodayWorkoutForAppleWatch(
        _ selected: PlannedSession, planID: UUID?
    ) {
        let stored = planID.flatMap { id in
            session.trainingPlan(withID: id)?
                .weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == selected.id })
        } ?? session.standalonePlannedSessions.first(where: { $0.id == selected.id })
        guard watchConnection.isReady,
              !hasOngoingTrainWorkout,
              let workout = stored,
              !workout.isExplicitRestDay,
              session.recordedTimes(for: workout.id)?.endedAt == nil,
              (planID.map { id in
                  !session.isPlanSessionSkipped(planID: id, sessionID: workout.id) &&
                  !session.isPlanSessionCompleted(
                      planID: id, sessionID: workout.id,
                      healthWorkouts: health.workouts,
                      strengthHistory: strengthWorkout.workoutHistory
                  )
              } ?? true),
              ATHLTHPlannedWorkoutCaptureRoute.resolve(
                  workout, device: .appleWatch
              ).canUsePreparedWatchTransfer,
              let watchKind = ATHLTHWorkoutCaptureAdmission.watchKind(
                for: workout)
        else {
            watchTransferError = ATHLTHLocalization.choose(
                english: "This workout cannot be sent to Apple Watch now.",
                norwegian: "Denne økten kan ikke sendes til Apple Watch nå."
            )
            return
        }

        let indoor = workout.kind == .running
            && RunEnvironment.forPlannedSession(workout) == .treadmill
        let route = indoor ? nil : PlannedWorkoutWatchBuilder.route(
            for: workout, routes: session.savedRoutes)
        if workout.routeID != nil && route == nil && !indoor {
            watchTransferError = ATHLTHLocalization.choose(
                english: "The planned route is missing.",
                norwegian: "Den planlagte ruten mangler."
            )
            return
        }
        if let route {
            do {
                try watchConnection.sendRoute(route)
            } catch {
                watchTransferError = error.localizedDescription
                return
            }
        }

        let running: WatchRunningWorkoutTransfer? =
            watchKind == .running || watchKind == .walking
            ? PlannedWorkoutWatchBuilder.runningTransfer(
                from: workout,
                routeAlerts: settings.routeAlertConfiguration,
                autoPauseEnabled: workout.autoPauseEnabled
                    ?? settings.autoPauseOutdoorWorkouts)
            : nil
        watchConnection.sendPreparedWorkout(
            WatchPreparedWorkoutTransfer(
                id: UUID(),
                title: workout.title,
                summary: workout.durationMinutes.map { "\($0) min" }
                    ?? workout.kind.title,
                kind: watchKind,
                routeID: route?.id,
                runningWorkout: running,
                audioCoach: PlannedWorkoutWatchBuilder.audioCoachConfiguration(
                    for: workout,
                    selectedRoute: route,
                    defaultConfiguration: settings.audioCoachConfiguration(
                        enabled: settings.audioCoachEnabledByDefault)),
                indoor: indoor,
                startMode: .onWatch,
                strengthWorkout: watchKind == .strength
                    ? PlannedWorkoutWatchBuilder.strengthSnapshot(workout)
                    : nil,
                plannedPlanID: planID,
                plannedSessionID: workout.id,
                updatedAt: Date()
            )
        )
        watchTransferMessage = ATHLTHLocalization.choose(
            english: "Sent to Apple Watch. Tap the ready card there to start.",
            norwegian: "Sendt til Apple Watch. Trykk på kortet der når du vil starte."
        )
    }

    private func structuredSourcePlanID(for workoutID: UUID) -> UUID? {
        ([session.activePlan].compactMap { $0 } + session.scheduledPlans)
            .first { plan in
                plan.weeks.flatMap(\.days).flatMap(\.sessions)
                    .contains { $0.id == workoutID }
            }?.id
    }

    private func openTodayPrimaryWorkout(
        _ workout: PlannedSession,
        planID: UUID,
        isHealthCompleted: Bool
    ) {
        // Guard against a deleted/moved plan session between selecting
        // a week card and confirming the launch.
        guard let workout = session.trainingPlan(withID: planID)?
            .weeks.flatMap(\.days).flatMap(\.sessions)
            .first(where: { $0.id == workout.id })
        else {
            watchTransferError = ATHLTHLocalization.choose(
                english: "This planned workout is no longer available. Refresh the plan.",
                norwegian: "Denne planlagte økten finnes ikke lenger. Oppdater planen."
            )
            return
        }

        if session.isPlanSessionCompleted(
            planID: planID,
            sessionID: workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strengthWorkout.workoutHistory
        ) {
            selectedPlanWorkout =
                PlannedWorkoutSelection(
                    planID: planID,
                    workout: workout,
                    isHealthCompleted:
                        isHealthCompleted
                )
            return
        }

        if session.isPlanSessionSkipped(
            planID: planID, sessionID: workout.id
        ) {
            selectedPlanWorkout = PlannedWorkoutSelection(
                planID: planID, workout: workout,
                isHealthCompleted: isHealthCompleted
            )
            return
        }

        // A minimized structured session reopens its single authoritative
        // checkpoint, never a second session with a new workout ID.
        if ATHLTHStructuredCaptureAdmission.activeWorkoutID == workout.id {
            selectedStructuredWorkout = workout
            return
        }
        // Never replace a live workout with a second one from the plan.
        if universalRecordingOccupied {
            watchTransferError = ATHLTHLocalization.choose(
                english: "A workout is already in progress. Finish it before starting a planned session.",
                norwegian: "En økt pågår allerede. Avslutt den før du starter en planlagt økt."
            )
            return
        }

        // Structured sessions must use their block-aware recorder,
        // including structured strength sessions. Routing strength first
        // silently discards the programmed blocks and their completion link.
        if workout.isStructuredWorkout {
            selectedStructuredWorkout = workout
            return
        }

        if let timedProjection = ATHLTHUnifiedWorkout
            .timedNonCardioProjection(from: workout) {
            selectedStructuredWorkout = timedProjection
            return
        }

        if workout.kind == .strength {
            selectedStrengthSession = workout
            return
        }

        if workout.kind == .running {
            pendingPlannedEnduranceWorkout = PlannedWorkoutSelection(
                planID: planID, workout: workout,
                isHealthCompleted: false
            )
            if let running = workout.resolvedRunningWorkouts.first {
                pendingRunningTemplate = running
            } else {
                showingRunQuickStart = true
            }
            return
        }

        if workout.kind == .walking {
            pendingPlannedEnduranceWorkout = PlannedWorkoutSelection(
                planID: planID, workout: workout,
                isHealthCompleted: false
            )
            showingWalkQuickStart = true
            return
        }

        selectedPlanWorkout =
            PlannedWorkoutSelection(
                planID: planID,
                workout: workout,
                isHealthCompleted:
                    isHealthCompleted
            )
    }

    /// A factual plan summary for the compact Today card.
    /// Week completion is based on actual completed sessions, never
    /// on invented showcase figures from the design reference.
    private func trainTodayPlanOverviewText(_ plan: TrainingPlan) -> String {
        guard !plan.weeks.isEmpty else {
            return ATHLTHLocalization.choose(
                english: "No scheduled weeks", norwegian: "Ingen planlagte uker"
            )
        }
        let weekIndex = min(trainCurrentWeekIndex(in: plan), plan.weeks.count - 1)
        let stats = trainWeekCompletionStats(in: plan, weekIndex: weekIndex)
        return ATHLTHLocalization.choose(
            english: "Week \(weekIndex + 1) of \(plan.weeks.count) · \(stats.completed) of \(stats.total) workouts this week",
            norwegian: "Uke \(weekIndex + 1) av \(plan.weeks.count) · \(stats.completed) av \(stats.total) økter denne uken"
        )
    }

    private func trainTodayPlanPositionText(
        _ plan: TrainingPlan
    ) -> String {
        let weekIndex = trainCurrentWeekIndex(in: plan)
        // Plan days are indexed from the plan start date, not from Monday.
        // The previous calendar-weekday calculation reported the wrong day
        // for plans starting on any other weekday.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let planStart = calendar.startOfDay(for: plan.startDate ?? today)
        let daysSinceStart = max(
            calendar.dateComponents([.day], from: planStart, to: today).day ?? 0,
            0
        )
        let dayIndex = (daysSinceStart % 7) + 1

        return ATHLTHLocalization.choose(
            english:
                "Week \(weekIndex + 1) · Day \(dayIndex)",
            norwegian:
                "Uke \(weekIndex + 1) · Dag \(dayIndex)"
        )
    }

    private func trainWeekCompletionStats(
        in plan: TrainingPlan,
        weekIndex: Int
    ) -> (completed: Int, total: Int) {
        guard plan.weeks.indices.contains(weekIndex) else {
            return (0, 0)
        }

        let sessions = plan.weeks[weekIndex]
            .days.flatMap(\.sessions)
        let completed = sessions.filter {
            session.isPlanSessionCompleted(
                planID: plan.id,
                sessionID: $0.id,
                healthWorkouts: health.workouts,
                strengthHistory: strengthWorkout.workoutHistory
            )
        }.count
        // The same source of truth drives week, day and whole-plan progress.
        return (completed, sessions.count)
    }

    private func trainUpcomingWorkouts(
        in plan: TrainingPlan,
        limit: Int
    ) -> [ATHLTHTrainUpcomingWorkout] {
        guard limit > 0 else {
            return []
        }

        let calendar = Calendar.current
        let today =
            calendar.startOfDay(for: Date())
        let planStart =
            calendar.startOfDay(
                for:
                    plan.startDate ??
                    today
            )

        var result:
            [ATHLTHTrainUpcomingWorkout] = []

        for (weekIndex, week)
        in plan.weeks.enumerated() {
            for day in week.days {
                guard
                    let baseDate =
                        calendar.date(
                            byAdding: .day,
                            value:
                                weekIndex * 7 +
                                max(day.dayIndex - 1, 0),
                            to: planStart
                        )
                else {
                    continue
                }

                guard baseDate > today else {
                    continue
                }

                for workout in day.sessions {
                    var date = baseDate

                    if let scheduled =
                        workout.scheduledStart {
                        let parts =
                            calendar.dateComponents(
                                [.hour, .minute],
                                from: scheduled
                            )

                        date =
                            calendar.date(
                                bySettingHour:
                                    parts.hour ?? 0,
                                minute:
                                    parts.minute ?? 0,
                                second: 0,
                                of: baseDate
                            ) ?? baseDate
                    }

                    result.append(
                        ATHLTHTrainUpcomingWorkout(
                            planID: plan.id,
                            date: date,
                            workout: workout
                        )
                    )
                }
            }
        }

        return Array(
            result
                .sorted {
                    if $0.date == $1.date {
                        return
                            $0.workout.title <
                            $1.workout.title
                    }

                    return $0.date < $1.date
                }
                .prefix(limit)
        )
    }

    private func trainUpcomingDateText(
        _ date: Date
    ) -> String {
        let calendar = Calendar.current

        if calendar.isDateInTomorrow(date) {
            return ATHLTHLocalization.choose(
                english: "Tomorrow",
                norwegian: "I morgen"
            )
        }

        return date.formatted(
            .dateTime.weekday(.abbreviated)
        )
    }

    @ViewBuilder
    private var unfinishedWorkoutRecoveryCards: some View {
        if phoneWorkout.hasRecoveredActiveWorkout,
           let active = phoneWorkout.active {
            unfinishedWorkoutRecoveryCard(
                title: active.title,
                activity:
                    active.walking
                        ? ATHLTHLocalization.choose(
                            english: "Walk",
                            norwegian: "Gange"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Run",
                            norwegian: "Løping"
                        ),
                source: "iPhone",
                lastUpdated:
                    phoneWorkout
                        .recoveredActiveWorkoutReferenceDate ??
                    active.lastCheckpoint,
                needsReview:
                    phoneWorkout
                        .recoveredActiveWorkoutNeedsReview,
                onContinue: {
                    phoneWorkout.presentWorkout()
                },
                onFinish: {
                    Task {
                        await phoneWorkout.finish()
                    }
                },
                onDiscard: {
                    phoneWorkout.discardActiveWorkout()
                }
            )
        }

        if strengthWorkout.hasRecoveredActiveWorkout,
           let active = strengthWorkout.activeWorkout {
            unfinishedWorkoutRecoveryCard(
                title: active.title,
                activity:
                    ATHLTHLocalization.choose(
                        english: "Strength",
                        norwegian: "Styrke"
                    ),
                source: active.captureDevice.title,
                lastUpdated:
                    strengthWorkout
                        .recoveredActiveWorkoutReferenceDate ??
                    active.startedAt,
                needsReview:
                    strengthWorkout
                        .recoveredActiveWorkoutNeedsReview,
                onContinue: {
                    strengthWorkout
                        .acknowledgeRecoveredWorkout()
                    showingStrengthWorkout = true
                },
                onFinish: {
                    strengthWorkout.finish()
                },
                onDiscard: {
                    strengthWorkout.discardActiveWorkout()
                }
            )
        }
    }

    private func unfinishedWorkoutRecoveryCard(
        title: String,
        activity: String,
        source: String,
        lastUpdated: Date,
        needsReview: Bool,
        onContinue: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(
                    systemName:
                        needsReview
                            ? "exclamationmark.arrow.triangle.2.circlepath"
                            : "arrow.counterclockwise.circle.fill"
                )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    needsReview
                        ? Color.orange
                        : ATHLTHTheme.accentDeep
                )
                .frame(width: 38, height: 38)
                .background(
                    (
                        needsReview
                            ? Color.orange
                            : ATHLTHTheme.accent
                    )
                    .opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "UNFINISHED WORKOUT",
                            norwegian: "UFERDIG ØKT"
                        )
                    )
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.25)
                    .foregroundStyle(
                        needsReview
                            ? Color.orange
                            : ATHLTHTheme.mutedText
                    )

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    Text(
                        "\(activity) · \(source) · " +
                        lastUpdated.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()
            }

            Text(
                needsReview
                    ? ATHLTHLocalization.choose(
                        english:
                            "This workout has been inactive for more than 12 hours. Continue it, end and save it, or discard it before starting something new.",
                        norwegian:
                            "Denne økten har vært inaktiv i mer enn 12 timer. Fortsett den, avslutt og lagre den, eller forkast den før du starter noe nytt."
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "ATHLTH recovered this workout from the last saved checkpoint.",
                        norwegian:
                            "ATHLTH gjenopprettet denne økten fra siste lagrede punkt."
                    )
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .fixedSize(
                horizontal: false,
                vertical: true
            )

            HStack(spacing: 8) {
                Button(action: onContinue) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Continue",
                            norwegian: "Fortsett"
                        ),
                        systemImage: "play.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)

                Menu {
                    Button {
                        onFinish()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "End and save",
                                norwegian: "Avslutt og lagre"
                            ),
                            systemImage: "checkmark.circle"
                        )
                    }

                    Button(
                        role: .destructive
                    ) {
                        onDiscard()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Discard workout",
                                norwegian: "Forkast økt"
                            ),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 34)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            (
                needsReview
                    ? Color.orange
                    : ATHLTHTheme.accent
            )
            .opacity(0.055),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                (
                    needsReview
                        ? Color.orange
                        : ATHLTHTheme.accent
                )
                .opacity(0.16),
                lineWidth: 0.8
            )
        }
    }

    private func trainPlanHeroMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            Text(value)
                .font(
                    .system(
                        size: 16,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trainPlanHeroMetricDivider: some View {
        Rectangle()
            .fill(ATHLTHTheme.divider)
            .frame(width: 1, height: 33)
            .padding(.horizontal, 10)
    }

    private func trainPlanDayRow(
        _ day: TrainingPlanDay,
        plan: TrainingPlan,
        weekIndex: Int
    ) -> some View {
        let date =
            trainPlanDate(
                plan: plan,
                weekIndex: weekIndex,
                dayIndex: day.dayIndex
            )

        return HStack(
            alignment: .top,
            spacing: 11
        ) {
            VStack(spacing: 1) {
                if let date {
                    Text(
                        date.formatted(
                            .dateTime.day()
                        )
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    Text(
                        date.formatted(
                            .dateTime.weekday(
                                .abbreviated
                            )
                        )
                        .uppercased()
                    )
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                } else {
                    Text("\(day.dayIndex)")
                        .font(
                            .system(
                                size: 17,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        ATHLTHLocalization.choose(
                            english: "DAY",
                            norwegian: "DAG"
                        )
                    )
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }
            .frame(width: 36, height: 42)

            if day.sessions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            ATHLTHTheme.recoveryBlue
                        )
                        .frame(width: 34, height: 34)
                        .background(
                            ATHLTHTheme
                                .recoveryBlueSoft,
                            in: RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Rest day",
                                norwegian: "Hviledag"
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Recovery is part of the plan",
                                norwegian:
                                    "Restitusjon er en del av planen"
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, 11)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 52
                )
                .background(
                    ATHLTHTheme
                        .recoveryBlueSoft
                        .opacity(0.50),
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            } else {
                VStack(spacing: 7) {
                    ForEach(day.sessions) { workout in
                        trainPlanSessionRow(
                            workout,
                            plan: plan,
                            date: date
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(
            Color.white.opacity(0.62),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private func trainPlanSessionRow(
        _ workout: PlannedSession,
        plan: TrainingPlan,
        date: Date?
    ) -> some View {
        let completed =
            trainPlanSessionCompleted(
                workout,
                planID: plan.id
            )
        let skipped =
            session.isPlanSessionSkipped(
                planID: plan.id,
                sessionID: workout.id
            )
        let tint =
            trainPlanKindTint(workout.kind)

        return Button {
            selectedPlanWorkout =
                PlannedWorkoutSelection(
                    planID: plan.id,
                    workout: workout,
                    isHealthCompleted:
                        healthCompletedTodaySessionIDs(
                            planID: plan.id,
                            sessions: [workout]
                        ).contains(workout.id)
                )
        } label: {
            HStack(spacing: 10) {
                Image(
                    systemName:
                        completed
                            ? "checkmark.circle.fill"
                            : skipped
                                ? "minus.circle.fill"
                                : workout.kind.systemImage
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    completed
                        ? ATHLTHTheme.vitality
                        : skipped
                            ? ATHLTHTheme.mutedText
                            : tint
                )
                .frame(width: 34, height: 34)
                .background(
                    (
                        completed
                            ? ATHLTHTheme.vitality
                            : skipped
                                ? ATHLTHTheme.mutedText
                                : tint
                    )
                    .opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    Text(
                        todaySessionSummary(workout)
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    if completed {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Done",
                                norwegian: "Ferdig"
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )
                    } else if skipped {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Skipped",
                                norwegian: "Hoppet over"
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    } else if let scheduled =
                        workout.scheduledStart {
                        Text(
                            scheduled.formatted(
                                date: .omitted,
                                time: .shortened
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }

                    if let duration =
                        workout.durationMinutes {
                        Text("\(duration) min")
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                    }
                }
                .font(.caption2.weight(.semibold))

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 44
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func trainPlanStatTile(
        value: String,
        label: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 31, height: 31)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(
                        .system(
                            size: 15,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: 56
        )
        .background(
            Color.white.opacity(0.58),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private func trainPlanActionTile(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 38, height: 38)
                        .background(
                            LinearGradient(
                                colors: [
                                    ATHLTHTheme.champagneSoft,
                                    ATHLTHTheme.accentSoft
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep.opacity(0.65)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .multilineTextAlignment(
                            .leading
                        )
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(
                maxWidth: .infinity,
                minHeight: 124,
                alignment: .topLeading
            )
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.86),
                        ATHLTHTheme.cardWarm.opacity(0.34)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 21,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.90),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var trainMyPlansSubtitle: String {
        // Evaluate each plan's status once and avoid allocating two arrays
        // whenever the Train plan subtitle is refreshed.
        var upcoming = 0
        var completed = 0
        for plan in session.trainingPlans {
            switch session.trainingPlanStatus(plan) {
            case .upcoming:
                upcoming += 1
            case .completed:
                completed += 1
            default:
                break
            }
        }

        if upcoming > 0 {
            return ATHLTHLocalization.choose(
                english:
                    "\(upcoming) upcoming · \(completed) completed",
                norwegian:
                    "\(upcoming) kommende · \(completed) fullført"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "\(session.trainingPlans.count) saved plans",
            norwegian:
                "\(session.trainingPlans.count) lagrede planer"
        )
    }

    private func trainResolvedPlanWeekIndex(
        _ plan: TrainingPlan
    ) -> Int {
        guard !plan.weeks.isEmpty else {
            return 0
        }

        if let selectedTrainPlanWeekIndex {
            return min(
                max(
                    selectedTrainPlanWeekIndex,
                    0
                ),
                plan.weeks.count - 1
            )
        }

        return trainCurrentWeekIndex(
            in: plan
        )
    }

    private func trainPlanDate(
        plan: TrainingPlan,
        weekIndex: Int,
        dayIndex: Int
    ) -> Date? {
        guard let start = plan.startDate else {
            return nil
        }

        return Calendar.current.date(
            byAdding: .day,
            value:
                weekIndex * 7 +
                max(dayIndex - 1, 0),
            to:
                Calendar.current
                    .startOfDay(for: start)
        )
    }

    private func trainPlanWeekDateRangeText(
        plan: TrainingPlan,
        weekIndex: Int
    ) -> String {
        guard
            let first =
                trainPlanDate(
                    plan: plan,
                    weekIndex: weekIndex,
                    dayIndex: 1
                ),
            let last =
                trainPlanDate(
                    plan: plan,
                    weekIndex: weekIndex,
                    dayIndex: 7
                )
        else {
            return ""
        }

        return
            first.formatted(
                .dateTime.day().month(.abbreviated)
            ) +
            " – " +
            last.formatted(
                .dateTime.day().month(.abbreviated)
            )
    }

    private func trainPlanDateRangeText(
        _ plan: TrainingPlan
    ) -> String {
        guard let start = plan.startDate else {
            return ATHLTHLocalization.choose(
                english: "No start date",
                norwegian: "Ingen startdato"
            )
        }

        let end =
            session.trainingPlanEndDate(plan)

        if let end {
            return
                start.formatted(
                    .dateTime.day().month(.abbreviated)
                ) +
                " – " +
                end.formatted(
                    .dateTime.day().month(.abbreviated)
                )
        }

        return start.formatted(
            date: .abbreviated,
            time: .omitted
        )
    }

    private func trainPlanDurationText(
        _ minutes: Int
    ) -> String {
        guard minutes >= 60 else {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainder = minutes % 60

        return remainder == 0
            ? "\(hours)t"
            : "\(hours)t \(remainder)m"
    }

    private func trainPlanSessionCompleted(
        _ workout: PlannedSession,
        planID: UUID
    ) -> Bool {
        session.isPlanSessionCompleted(
            planID: planID,
            sessionID: workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strengthWorkout.workoutHistory
        )
    }

    private func trainWeekSnapshotCard(
        _ plan: TrainingPlan
    ) -> some View {
        let weekIndex = trainCurrentWeekIndex(in: plan)
        let week =
            plan.weeks.indices.contains(weekIndex)
                ? plan.weeks[weekIndex]
                : plan.weeks.first
        let workoutCount =
            week?.days.reduce(0) {
                $0 + $1.sessions.count
            } ?? 0

        return ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "THIS WEEK",
                                norwegian: "DENNE UKEN"
                            )
                        )
                        .font(.caption2.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(
                            ATHLTHLocalization.choose(
                                english: "\(workoutCount) planned sessions",
                                norwegian: "\(workoutCount) planlagte økter"
                            )
                        )
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    }

                    Spacer()

                    Button {
                        selectedSection = .plan
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Plan",
                                    norwegian: "Plan"
                                )
                            )
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .buttonStyle(.plain)
                }

                if let week {
                    trainPlanWeekStrip(week)
                }
            }
        }
    }

    private func trainPlanWeekStrip(
        _ week: TrainingPlanWeek
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(
                Array(week.days.prefix(7).enumerated()),
                id: \.element.id
            ) { _, day in
                let workout = day.sessions.first
                let tint =
                    workout.map {
                        trainPlanKindTint($0.kind)
                    } ?? ATHLTHTheme.mutedText

                VStack(spacing: 6) {
                    Text(
                        String(
                            day.title
                                .prefix(1)
                        )
                        .uppercased()
                    )
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    Image(
                        systemName:
                            workout?.kind.systemImage ??
                            "moon.fill"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(
                        tint.opacity(0.10),
                        in: Circle()
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
    }

    private func trainPlanKindTint(
        _ kind: WorkoutKind
    ) -> Color {
        switch kind {
        case .running:
            return Color.green
        case .walking:
            return Color.teal
        case .strength:
            return ATHLTHTheme.premiumGold
        case .mobility:
            return Color.indigo
        case .recovery:
            return Color.blue
        case .custom:
            return ATHLTHTheme.accentDeep
        }
    }

    private func trainCurrentWeekIndex(
        in plan: TrainingPlan
    ) -> Int {
        guard !plan.weeks.isEmpty else {
            return 0
        }

        guard let startDate = plan.startDate else {
            return 0
        }

        let calendar = Calendar.current
        let start =
            calendar.startOfDay(for: startDate)
        let today =
            calendar.startOfDay(for: Date())
        let dayOffset =
            calendar.dateComponents(
                [.day],
                from: start,
                to: today
            ).day ?? 0

        return min(
            max(dayOffset / 7, 0),
            plan.weeks.count - 1
        )
    }

    private func openPlanFromTrainingLibrary(_ planID: UUID) {
        highlightedTrainPlanID = planID
        selectedTrainPlanWeekIndex = nil
        selectedSection = .plan
        showingLibrary = false
        personalLibrarySection = nil
    }

    private var libraryContent: some View {
        TrainingLibraryHomeView(
            onStartRunning: { workout in
                pendingPlannedEnduranceWorkout = nil
                pendingRunningTemplate = workout
            },
            onOpenPlan: openPlanFromTrainingLibrary
        )
    }

    private func quickStartTile(
        title: String,
        subtitle: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 19,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .background(
                        LinearGradient(
                            colors: [
                                ATHLTHTheme.champagneSoft,
                                ATHLTHTheme.accentSoft
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 2)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep.opacity(0.70)
                    )
            }
            .padding(12)
            .frame(
                maxWidth: .infinity,
                minHeight: 78,
                alignment: .leading
            )
            .background(
                Color.white.opacity(
                    enabled
                        ? 0.76
                        : 0.42
                ),
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    enabled
                        ? Color.white.opacity(0.90)
                        : ATHLTHTheme.border,
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.50)
    }

    private func watchWorkoutKind(
        for kind: WorkoutKind
    ) -> WatchWorkoutKind? {
        switch kind {
        case .running:
            return .running
        case .walking:
            return .walking
        case .strength:
            return .strength
        case .mobility, .recovery, .custom:
            return nil
        }
    }

    private var quickStartKinds: [WorkoutKind] {
        [.running, .walking, .strength]
    }

    private var customQuickStartAvailable: Bool {
        !universalRecordingOccupied
    }

    private var quickStartCustomSubtitle: String {
        ATHLTHLocalization.choose(
            english: "iPhone or Apple Watch",
            norwegian: "iPhone eller Apple Watch"
        )
    }

    private func quickStartSubtitle(
        _ kind: WorkoutKind
    ) -> String {
        switch kind {
        case .running:
            if let active = phoneWorkout.active {
                return active.walking
                    ? ATHLTHLocalization.choose(
                        english: "Walk in progress",
                        norwegian: "Gåøkt pågår"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Continue workout",
                        norwegian: "Fortsett økt"
                    )
            }
            return watchConnection.isReady
                ? "iPhone / Watch · Free / Route / Workout"
                : "iPhone · Free Run"
        case .walking:
            if let active = phoneWorkout.active {
                return active.walking
                    ? ATHLTHLocalization.choose(
                        english: "Continue workout",
                        norwegian: "Fortsett økt"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Run in progress",
                        norwegian: "Løpeøkt pågår"
                    )
            }
            return watchConnection.isReady
                ? "iPhone / Watch · Free Walk"
                : "iPhone · Free Walk"
        case .strength:
            if strengthWorkout.activeWorkout != nil {
                return ATHLTHLocalization.choose(
                    english: "Continue workout",
                    norwegian: "Fortsett økt"
                )
            }
            return ATHLTHLocalization.choose(
                english: "Choose device at start",
                norwegian: "Velg enhet ved start"
            )
        case .mobility, .recovery, .custom:
            return kind.title
        }
    }

    private func quickStartAvailable(_ kind: WorkoutKind) -> Bool {
        if ATHLTHManualTimedCapture.hasActiveCapture ||
           ATHLTHStructuredCaptureAdmission.hasActiveCapture { return false }
        if let active = phoneWorkout.active {
            switch kind {
            case .running:
                return !active.walking
            case .walking:
                return active.walking
            case .strength, .mobility, .recovery, .custom:
                return false
            }
        }

        switch kind {
        case .running, .walking:
            return true
        case .strength:
            // A recovered strength checkpoint is resumable and is surfaced
            // explicitly above, so it must never silently disable Strength.
            return true
        case .mobility, .recovery, .custom:
            return false
        }
    }

    private func handleQuickStart(_ kind: WorkoutKind) {
        pendingPlannedEnduranceWorkout = nil
        switch kind {
        case .running:
            if let active = phoneWorkout.active,
               !active.walking {
                phoneWorkout.presentWorkout()
            } else {
                showingRunQuickStart = true
            }
        case .walking:
            if let active = phoneWorkout.active,
               active.walking {
                phoneWorkout.presentWorkout()
            } else {
                showingWalkQuickStart = true
            }
        case .strength:
            if strengthWorkout.activeWorkout != nil {
                strengthWorkout
                    .acknowledgeRecoveredWorkout()
                showingStrengthWorkout = true
            } else {
                showingStrengthQuickStart = true
            }
        case .custom:
            if let timed = ATHLTHManualTimedCapture.current(
                for: session.profile.userID
            ) {
                activeCustomIPhoneQuick = CustomIPhoneQuickLaunch(
                    configuration: timed.recoveryConfiguration,
                    mode: .timed
                )
            } else if customQuickStartAvailable {
                customQuickInitialActivity = .hiit
                isFreeTrainingQuickStart = false
                showingCustomQuickStart = true
            } else {
                watchTransferError = ATHLTHLocalization.choose(
                    english: "Finish your active workout before starting another.",
                    norwegian: "Avslutt økten som pågår før du starter en ny."
                )
            }
        case .mobility, .recovery:
            break
        }
    }

    private func startCyclingQuick() {
        startCustomQuick(as: .cycling)
    }

    private func startCustomQuick(as activity: CustomQuickWorkoutActivity) {
        if let timed = ATHLTHManualTimedCapture.current(
            for: session.profile.userID
        ), timed.activity == activity {
            activeCustomIPhoneQuick = CustomIPhoneQuickLaunch(
                configuration: timed.recoveryConfiguration,
                mode: .timed
            )
            return
        }
        guard customQuickStartAvailable else {
            watchTransferError = ATHLTHLocalization.choose(
                english: "Finish the active workout before starting another.",
                norwegian: "Avslutt økten som pågår før du starter en ny."
            )
            return
        }
        customQuickInitialActivity = activity
        isFreeTrainingQuickStart = false
        showingCustomQuickStart = true
    }

    /// One-tap free training starts the existing open-ended iPhone timer.
    /// No setup sheet, no invented workouts and no automatic retrospective log.
    /// The user's finish/discard action still owns whether the workout saves.
    private func startFreeTrainingQuick() {
        if let timed = ATHLTHManualTimedCapture.current(
            for: session.profile.userID
        ), timed.activity == .other {
            activeCustomIPhoneQuick = CustomIPhoneQuickLaunch(
                configuration: timed.recoveryConfiguration,
                mode: .timed
            )
            return
        }
        guard customQuickStartAvailable,
              !ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive else {
            watchTransferError = ATHLTHLocalization.choose(
                english: "Finish the active workout before starting another.",
                norwegian: "Avslutt økten som pågår før du starter en ny."
            )
            return
        }
        social.quickTrainFriendIDs.removeAll()
        social.discardPreparedQuickTrainFriends()
        activeCustomIPhoneQuick = CustomIPhoneQuickLaunch(
            configuration: CustomQuickWorkoutConfiguration(
                activity: .other,
                method: .open,
                durationMinutes: 45,
                workSeconds: 40,
                restSeconds: 20,
                rounds: 8,
                titleOverride: ATHLTHLocalization.choose(
                    english: "Free training",
                    norwegian: "Fri trening"
                )
            ),
            mode: .timed
        )
    }

    private func handleWorkoutCategoryAction(
        _ action: ATHLTHTrainAllWorkoutCategoriesSheet.Action
    ) {
        guard !hasOngoingTrainWorkout else { return }
        switch action {
        case .freeRun:
            handleQuickStart(.running)
        case .runIntervals:
            savedTrainIntervalTemplate = nil
            showingTrainIntervalComposer = true
        case .freeWalk:
            handleQuickStart(.walking)
        case .freeStrength:
            handleQuickStart(.strength)
        case .strengthLibrary:
            personalLibrarySection = .workouts
        case .runningWorkouts:
            showingTrainRunningWorkoutLibrary = true
        case .strengthExercises:
            handleQuickStart(.strength)
        case .competition(let activity):
            selectedTrainCompetitionActivity = activity
        case .cycling:
            startCyclingQuick()
        case .freeTraining:
            startFreeTrainingQuick()
        case .custom(let activity):
            startCustomQuick(as: activity)
        }
    }

    private var quickStrengthSession:
        PlannedSession {
        PlannedSession(
            id: UUID(),
            title:
                ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                ),
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes:
                "Freestyle gym session",
            runningWorkout: nil
        )
    }

    private var quickStartDeviceTitle: String {
        watchConnection.isReady
            ? "iPhone / Watch"
            : ATHLTHLocalization.choose(
                english: "iPhone · Watch offline",
                norwegian: "iPhone · Watch frakoblet"
            )
    }

    @ViewBuilder
    private func routeDeviceActions(
        _ route: TrainingRoute
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                sendRouteToWatch(route)
            } label: {
                Label("Send to Apple Watch", systemImage: "applewatch")
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
            .disabled(!watchConnection.isReady)

            if !watchConnection.isReady {
                Text("Connect Apple Watch to send this route.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func startCustomWorkoutOnWatch(
        _ configuration: CustomQuickWorkoutConfiguration
    ) {
        guard watchConnection.isReady else {
            watchTransferError = ATHLTHLocalization.choose(
                english: "Apple Watch is not available. Choose iPhone timing or log the workout manually.",
                norwegian: "Apple Watch er ikke tilgjengelig. Velg tidtaking på iPhone eller registrer økten manuelt."
            )
            return
        }
        guard customQuickStartAvailable else {
            watchTransferError = ATHLTHLocalization.choose(
                english: "A workout is already active.",
                norwegian: "Du har allerede en aktiv økt."
            )
            return
        }

        Task {
            do {
                // Protect the entire asynchronous Watch preflight with the
                // same cross-activity launch reservation as Run and Strength.
                // A Watch cycling/yoga recording must not race an iPhone timer.
                let launchID = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
                defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(launchID) }
                try await watchConnection.requireNoActiveWatchWorkout()
                watchConnection.sendAudioCoachConfiguration(
                    configuration.audioCoach
                )
                try await watchConnection.startWorkoutOnWatch(
                    configuration.activity.watchKind
                )
                if !configuration.selectedFriendIDs.isEmpty {
                    _ = await social.confirmCurrentJoinedWorkoutStarted()
                }
                watchTransferMessage =
                    "\(configuration.title) started on Apple Watch · \(configuration.detail)."
            } catch {
                if !configuration.selectedFriendIDs.isEmpty {
                    await social.markCurrentJoinedWorkoutLaunchFailed()
                }
                watchTransferError = error.localizedDescription
            }
        }
    }

    private func startRunQuickWorkout(
        _ configuration: RunQuickStartConfiguration
    ) {
        if configuration.captureDevice == .iPhone {
            guard configuration.mode == .free else { return }
            gear.prepareNextWorkoutGear(configuration.gearIDs)
            phoneWorkout.start(
                walking: false,
                autoPauseEnabled:
                    configuration.autoPauseEnabled
            )
            Task {
                _ = await social
                    .confirmCurrentJoinedWorkoutStarted()
            }
            return
        }

        guard watchConnection.isReady else {
            watchTransferError =
                "Apple Watch is not ready to start this run."
            return
        }

        Task { @MainActor in
            do {
                let launchID = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
                defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(launchID) }
                let initiatingAccount = session.profile.userID

                // Advanced Quick Run is already a complete saved Plan
                // timeline. Never silently replace it with the free or
                // library-only WatchRunningWorkoutTransfer.
                let advanced = configuration.advancedWorkout
                if let advanced {
                    try ATHLTHWorkoutCaptureAdmission
                        .requireSupportedEnduranceCapture(
                            for: advanced,
                            expectedKind: .running,
                            device: .appleWatch
                        )
                }
                let original = configuration.workout
                let isIndoor = configuration.environment != .outdoor

                // Advanced Quick Run may explicitly choose a route even if
                // the draft has none. A library template instead owns its
                // saved route unconditionally. Both retain their original
                // identity and fail closed if that route cannot be found.
                let canonicalRouteID: UUID?
                if let advanced {
                    canonicalRouteID = advanced.routeID ??
                        configuration.route?.id
                } else {
                    canonicalRouteID = original?.routeID
                }
                let sourceExists = advanced != nil || original != nil
                let route: TrainingRoute?
                if let canonicalRouteID {
                    route = configuration.route?.id == canonicalRouteID
                        ? configuration.route
                        : session.savedRoutes.first {
                            $0.id == canonicalRouteID
                        }
                } else {
                    route = sourceExists ? nil : configuration.route
                }
                guard ATHLTHWatchRunRoutePolicy.matchesSource(
                    hasSourceWorkout: sourceExists,
                    sourceRouteID: canonicalRouteID,
                    selectedRouteID: route?.id
                ), (!isIndoor || route == nil) else {
                    watchTransferError = ATHLTHLocalization.choose(
                        english: "The saved running route is missing or has changed.",
                        norwegian: "Den lagrede løperuten mangler eller er endret."
                    )
                    await social.markCurrentJoinedWorkoutLaunchFailed()
                    return
                }
                if let route {
                    try watchConnection.sendRoute(route)
                    watchConnection.sendWorkoutRouteSelection(route.id)
                } else {
                    watchConnection.sendWorkoutRouteSelection(nil)
                }

                let runningTransfer: WatchRunningWorkoutTransfer
                if let advanced {
                    // All original Advanced stages, target pace and zones
                    // survive manual/delayed Watch launch as well.
                    runningTransfer = PlannedWorkoutWatchBuilder.runningTransfer(
                        from: advanced,
                        routeAlerts: settings.routeAlertConfiguration,
                        autoPauseEnabled: configuration.autoPauseEnabled
                    )
                } else if let source = original {
                    var transfer = watchRunningWorkoutTransfer(from: source)
                    transfer.routeAlerts = settings.routeAlertConfiguration
                    transfer.autoPauseEnabled = configuration.autoPauseEnabled
                    runningTransfer = transfer
                } else {
                    runningTransfer = WatchRunningWorkoutTransfer(
                        title: "",
                        steps: [],
                        routeAlerts: settings.routeAlertConfiguration,
                        autoPauseEnabled: configuration.autoPauseEnabled
                    )
                }

                if configuration.watchStartMode != .immediate {
                    // A delayed prepared card must never be misreported as
                    // a recording already started by HealthKit. Ghost
                    // races require an independently verified target and
                    // cannot silently fall back to a plain run.
                    guard configuration.ghostTargetDurationSeconds == nil else {
                        watchTransferError = ATHLTHLocalization.choose(
                            english: "Prepare the Ghost Race route before scheduling its Watch start.",
                            norwegian: "Klargjør Ghost Race-ruten før du planlegger Watch-start."
                        )
                        await social.markCurrentJoinedWorkoutLaunchFailed()
                        return
                    }
                    watchConnection.sendPreparedWorkout(
                        WatchPreparedWorkoutTransfer(
                            id: UUID(),
                            title: configuration.title,
                            summary: configuration.title,
                            kind: .running,
                            routeID: route?.id,
                            runningWorkout: runningTransfer,
                            audioCoach: configuration.audioCoach,
                            indoor: isIndoor,
                            startMode: configuration.watchStartMode,
                            updatedAt: Date()
                        )
                    )
                    watchTransferMessage =
                        configuration.watchStartMode.confirmationText
                    return
                }

                // Immediate: queue the entire original recipe before the
                // ONE Watch HealthKit session begins.
                watchConnection.sendAudioCoachConfiguration(
                    configuration.audioCoach
                )
                watchConnection.sendRunningWorkout(runningTransfer)
                try await watchConnection.startWorkoutOnWatch(
                    .running, indoor: isIndoor
                )
                guard session.profile.userID == initiatingAccount else {
                    await social.markCurrentJoinedWorkoutLaunchFailed()
                    watchTransferError = ATHLTHLocalization.choose(
                        english: "Apple Watch started under the previous account.",
                        norwegian: "Apple Watch startet på den forrige kontoen."
                    )
                    return
                }
                gear.prepareNextWorkoutGear(configuration.gearIDs)
                _ = await social.confirmCurrentJoinedWorkoutStarted()
                watchTransferMessage =
                    "\(configuration.title) started on Apple Watch."
            } catch {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                watchTransferError = error.localizedDescription
            }
        }
    }

    private func startQuickWorkoutOnWatch(_ kind: WorkoutKind) {
        guard watchConnection.isReady,
              !universalRecordingOccupied,
              let watchKind = watchWorkoutKind(for: kind)
        else {
            return
        }

        Task { @MainActor in
            do {
                let launchID = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
                defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(launchID) }
                try await watchConnection.startWorkoutOnWatch(watchKind)
                watchTransferMessage = "\(watchKind.title) started on Apple Watch."
            } catch {
                watchTransferError = error.localizedDescription
            }
        }
    }

    private func startRunningTemplate(
        _ workout: RunningWorkoutTemplate,
        gearIDs: Set<UUID>,
        audioCoach: WatchAudioCoachConfiguration
    ) {
        guard watchConnection.isReady
        else {
            watchTransferError =
                "Connect Apple Watch to start a live running workout from the library."
            return
        }

        Task { @MainActor in
            do {
                let launchID = try ATHLTHWorkoutRecordingArbiter.reserveLaunch()
                defer { ATHLTHWorkoutRecordingArbiter.releaseLaunch(launchID) }
                let initiatingAccount = session.profile.userID
                let route = workout.routeID.flatMap { routeID in
                    session.savedRoutes.first { $0.id == routeID }
                }
                guard ATHLTHWatchRunRoutePolicy.matchesSource(
                    hasSourceWorkout: true,
                    sourceRouteID: workout.routeID,
                    selectedRouteID: route?.id
                ) else {
                    watchTransferError = ATHLTHLocalization.choose(
                        english: "The library workout's saved route is missing.",
                        norwegian: "Den lagrede ruten til bibliotekøkten mangler."
                    )
                    await social.markCurrentJoinedWorkoutLaunchFailed()
                    return
                }
                if let route {
                    try watchConnection.sendRoute(route)
                    watchConnection.sendWorkoutRouteSelection(route.id)
                } else {
                    watchConnection.sendWorkoutRouteSelection(nil)
                }

                watchConnection.sendAudioCoachConfiguration(audioCoach)
                var transfer = watchRunningWorkoutTransfer(from: workout)
                transfer.routeAlerts = settings.routeAlertConfiguration
                watchConnection.sendRunningWorkout(transfer)
                // Do not lose the template's stages on the first Watch frame.
                try await watchConnection.startWorkoutOnWatch(.running)
                guard session.profile.userID == initiatingAccount else {
                    await social.markCurrentJoinedWorkoutLaunchFailed()
                    watchTransferError = ATHLTHLocalization.choose(
                        english: "Apple Watch started under the previous account.",
                        norwegian: "Apple Watch startet på den forrige kontoen."
                    )
                    return
                }
                gear.prepareNextWorkoutGear(gearIDs)
                watchTransferMessage =
                    "\(workout.title) started on Apple Watch."
            } catch {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                watchTransferError = error.localizedDescription
            }
        }
    }

    private func sendRouteToWatch(_ route: TrainingRoute) {
        guard watchConnection.isReady else {
            return
        }

        do {
            try watchConnection.sendRoute(route)
            watchTransferMessage = "Sent \(route.title) to Apple Watch."
        } catch {
            watchTransferError = error.localizedDescription
        }
    }


    private var noActivePlanCard: some View {
        ATHLTHCard {
            HStack(spacing: 10) {
                Text("Today's Plan")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    showingLibrary = true
                } label: {
                    HStack(spacing: 5) {
                        Text("Choose Plan")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 13) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("No active training plan")
                        .font(.subheadline.weight(.semibold))

                    Text("Start or create a program to see today's sessions, times and completed workouts here.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.top, 12)

            Button {
                showingLibrary = true
            } label: {
                Text("Explore Programs")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .background(
                ATHLTHTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: 15)
            )
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func todayPlanRow(
        _ workout: PlannedSession,
        planID: UUID,
        isHealthCompleted: Bool,
        isManuallyCompleted: Bool,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        let isCompleted = session.isPlanSessionCompleted(
            planID: planID,
            sessionID: workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strengthWorkout.workoutHistory
        )

        Button {
            selectedPlanWorkout = PlannedWorkoutSelection(
                planID: planID,
                workout: workout,
                isHealthCompleted: isHealthCompleted
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if !isFirst {
                        Rectangle()
                            .fill(ATHLTHTheme.accent.opacity(0.16))
                            .frame(width: 2, height: 22)
                            .offset(y: -21)
                    }

                    if !isLast {
                        Rectangle()
                            .fill(ATHLTHTheme.accent.opacity(0.16))
                            .frame(width: 2, height: 22)
                            .offset(y: 21)
                    }

                    Circle()
                        .fill(
                            isCompleted
                                ? ATHLTHTheme.accent
                                : Color.white.opacity(0.94)
                        )
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .stroke(
                                    isCompleted
                                        ? ATHLTHTheme.accent
                                        : ATHLTHTheme.accent.opacity(0.42),
                                    lineWidth: 1.5
                                )
                        }

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 32, height: 58)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)

                    Text(todaySessionSummary(workout))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(
                        todayPlanStatus(
                            workout,
                            isCompleted: isCompleted
                        )
                    )
                    .font(.caption.weight(isCompleted ? .semibold : .regular))
                    .foregroundStyle(
                        isCompleted
                            ? ATHLTHTheme.accent
                            : ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)

                    if isHealthCompleted {
                        Label("Health", systemImage: "heart.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    } else if isManuallyCompleted {
                        Text("Manual")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 64)
            .background(
                Color.white.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .accessibilityLabel(
            "\(workout.title), \(isCompleted ? "completed" : "planned")"
        )
        .accessibilityHint("Open workout details")
    }

    private func todayPlanStatus(
        _ workout: PlannedSession,
        isCompleted: Bool
    ) -> String {
        if isCompleted {
            return "Completed"
        }

        if let scheduledStart = workout.scheduledStart {
            return scheduledStart.formatted(
                date: .omitted,
                time: .shortened
            )
        }

        return "Today"
    }

    private func manuallyCompletedTodaySessionIDs(
        planID: UUID,
        sessions: [PlannedSession]
    ) -> Set<UUID> {
        Set(
            sessions
                .filter {
                    session.isPlanSessionManuallyCompleted(
                        planID: planID,
                        sessionID: $0.id
                    )
                }
                .map(\.id)
        )
    }

    private func completedTodaySessionIDs(
        planID: UUID,
        sessions: [PlannedSession]
    ) -> Set<UUID> {
        Set(
            sessions.filter {
                session.isPlanSessionCompleted(
                    planID: planID,
                    sessionID: $0.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: strengthWorkout.workoutHistory
                )
            }.map(\.id)
        )
    }

    private func healthCompletedTodaySessionIDs(
        planID: UUID,
        sessions: [PlannedSession],
        completedIDs: Set<UUID>? = nil
    ) -> Set<UUID> {
        // Reuse the completion set when the caller already has it;
        // otherwise derive one for single-workout links.
        let verifiedCompletedIDs = completedIDs ??
            completedTodaySessionIDs(planID: planID, sessions: sessions)
        return Set(
            sessions.lazy.filter {
                verifiedCompletedIDs.contains($0.id) &&
                !session.isPlanSessionManuallyCompleted(
                    planID: planID,
                    sessionID: $0.id
                ) &&
                session.linkedHealthWorkoutID(
                    planID: planID,
                    sessionID: $0.id
                ) != nil &&
                session.isPlanSessionCompleted(
                    planID: planID,
                    sessionID: $0.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: []
                )
            }.map(\.id)
        )
    }

    private func todaySessions(
        in plan: TrainingPlan
    ) -> [PlannedSession] {
        ATHLTHTrainingPlanSchedule.sessions(in: plan)
    }

    private func todaySessionSummary(
        _ workout: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let running = workout.runningWorkout {
            parts.append(running.type.title)
            parts.append("\(running.blocks.count) blocks")
        } else if let duration = workout.durationMinutes {
            parts.append("\(duration) min")
        }

        if !workout.exercises.isEmpty {
            parts.append("\(workout.exercises.count) exercises")
        }

        if workout.routeID != nil {
            parts.append("Route")
        }

        return parts.isEmpty
            ? workout.kind.title
            : parts.joined(separator: " · ")
    }





    private func handleNavigationRequest() {
        guard let request = navigationRequest else {
            return
        }

        switch request {
        case .today:
            selectedSection = .today

        case .plan:
            selectedSection = .plan

        case let .workout(planID, workoutID):
            if let plan =
                    session.trainingPlan(
                        withID: planID
                    ),
               let workout =
                    plan.weeks
                        .flatMap(\.days)
                        .flatMap(\.sessions)
                        .first(
                            where: {
                                $0.id == workoutID
                            }
                        ) {
                selectedPlanWorkout =
                    PlannedWorkoutSelection(
                        planID: planID,
                        workout: workout,
                        isHealthCompleted:
                            healthCompletedTodaySessionIDs(
                                planID: planID,
                                sessions: [workout]
                            )
                            .contains(workout.id)
                    )
            } else {
                selectedSection = .plan
            }

        case let .startPlannedWorkout(planID, workoutID):
            if let workout = session.trainingPlan(withID: planID)?
                .weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == workoutID }) {
                openTodayPrimaryWorkout(
                    workout, planID: planID, isHealthCompleted: false
                )
            } else {
                selectedSection = .plan
            }

        case let .sendPlannedWorkoutToWatch(planID, workoutID):
            if let workout = session.trainingPlan(withID: planID)?
                .weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == workoutID }) {
                prepareTodayWorkoutForAppleWatch(workout, planID: planID)
            } else {
                selectedSection = .plan
            }

        case let .startPlannedWorkoutAfter(planID, workoutID, seconds):
            if let workout = session.trainingPlan(withID: planID)?
                .weeks.flatMap(\.days).flatMap(\.sessions)
                .first(where: { $0.id == workoutID }) {
                scheduleTodayWorkoutStart(
                    workout, planID: planID, after: seconds
                )
            } else {
                selectedSection = .plan
            }

        case let .quick(kind):
            selectedSection = .today
            handleQuickStart(kind)

        case let .customQuickActivity(activity):
            selectedSection = .today
            customQuickInitialActivity = activity
            isFreeTrainingQuickStart = false
            if customQuickStartAvailable {
                showingCustomQuickStart = true
            } else {
                watchTransferError = ATHLTHLocalization.choose(
                    english: "Finish your current workout first.",
                    norwegian: "Avslutt økten som pågår først."
                )
            }

        case .customQuick:
            selectedSection = .today
            isFreeTrainingQuickStart = false
            if customQuickStartAvailable {
                showingCustomQuickStart = true
            } else {
                watchTransferError = ATHLTHLocalization.choose(
                    english: "Finish your current workout first.",
                    norwegian: "Avslutt økten som pågår først."
                )
            }

        case .ghost:
            selectedSection = .today
            showingGhostHub = true

        case .library:
            selectedSection = .today
            personalLibrarySection = nil
            showingLibrary = true

        case let .personalLibrary(section):
            selectedSection = .today
            showingLibrary = false
            personalLibrarySection = section
        }

        navigationRequest = nil
    }

}

// ATHLTHRecoveryView (legacy Insights) was retired in 2.0.1.
// Dagsform details now open in ATHLTHReadinessExplanationSheet.

private enum ProgressPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"
    case year = "Year"

    var id: String { rawValue }
}

struct ATHLTHProgressView: View {
    private enum TrainingScope: String, CaseIterable, Identifiable {
        case all, running, strength
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All trening"
            case .running: return "Løping"
            case .strength: return "Styrke"
            }
        }
    }
    @State private var trainingScope: TrainingScope = .all

    private var trainingScopePicker: some View {
        Menu {
            ForEach(TrainingScope.allCases) { choice in
                Button {
                    trainingScope = choice
                } label: {
                    if trainingScope == choice {
                        Label(choice.label, systemImage: "checkmark")
                    } else {
                        Text(choice.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(trainingScope.label)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(ATHLTHTheme.champagneSoft, in: Capsule())
        }
        .accessibilityLabel("Treningstype: \(trainingScope.label)")
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRENING")
                .font(.caption.weight(.medium))
                .tracking(3)
                .foregroundStyle(ATHLTHTheme.mutedText)
            Text("Fremdrift")
                .font(.system(size: 40, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
            HStack(alignment: .center) {
                Text("Se utviklingen din. Bygg videre på det som fungerer.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                Spacer(minLength: 8)
                trainingScopePicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var trophyStore: TrophyStore

    @State private var period: ProgressPeriod = .week
    @State private var progressSnapshot: HealthProgressSnapshot?
    @State private var consistencySnapshot: HealthProgressSnapshot?
    @State private var personalRecords: [HealthPersonalRecord] = []
    @State private var workoutHistory: [WorkoutSummary] = []
    @State private var trendMetric: ProgressTrendMetric = .training
    @State private var progressLoading = false
    @State private var progressError: String?

    private let green = ATHLTHTheme.accent
    private let blue = Color(red: 0.20, green: 0.56, blue: 0.96)
    private let purple = Color(red: 0.42, green: 0.36, blue: 0.95)
    private let canvas = Color(red: 0.965, green: 0.972, blue: 0.968)

    var body: some View {
        return NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: ATHLTHTheme.premiumGold.opacity(0.18),
                softTransition: true,
                immersiveTransition: false,
                scrollFadeTransition: false
            ) {
                Color.clear.frame(height: 1)
            } content: {
                LazyVStack(spacing: 15) {
                    progressHeader
                    periodPicker
                    premiumOverview
                    premiumTrend
                    if trainingScope == .all {
                        if let snapshot = progressSnapshot {
                            ProgressConsistencyCard(snapshot: consistencySnapshot)
                            ProgressTrendCard(snapshot: snapshot, metric: $trendMetric)
                        } else {
                            progressWithoutHealthCard
                        }
                    }
                    ProgressPerformanceCard(
                        runningWorkouts: trainingScope == .strength ? [] : selectedPeriodRunningWorkouts,
                        strengthWorkouts: trainingScope == .running ? [] : selectedPeriodStrengthWorkouts,
                        healthRecords: trainingScope == .strength ? [] : personalRecords,
                        strengthRecords: trainingScope == .running ? [] : strengthWorkout.personalRecords,
                        repRecords: trainingScope == .running ? [] : strengthWorkout.repPersonalRecords
                    )
                    personalRecordsCard
                    recentActivity
                    if trainingScope == .all { achievementsCard }
                    if progressLoading {
                        ProgressView().controlSize(.small)
                    } else if let progressError, trainingScope == .all {
                        Text(progressError)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                async let selected: Void = loadProgressData()
                async let support: Void = loadSupportingProgressData()
                _ = await (selected, support)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: period) {
            await loadProgressData()
        }
        .task {
            await loadSupportingProgressData()
            await goalStore.refreshAutomaticMilestones(
                health: health,
                strength: strengthWorkout
            )
            await trophyStore.refresh(
                health: health,
                strength: strengthWorkout,
                goals: goalStore
            )
        }
    }

    private var premiumOverview: some View {
        let runs = selectedPeriodRunningWorkouts
        let lifts = selectedPeriodStrengthWorkouts
        let runDuration = runs.reduce(0.0) { $0 + $1.duration }
        let liftDuration = lifts.reduce(0.0) {
            $0 + max(0, ($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt))
        }
        let distance = runs.compactMap(\.distanceMeters).reduce(0, +) / 1_000
        let volume = lifts.reduce(0.0) { $0 + $1.totalVolumeKilograms }
        let workoutCount = trainingScope == .all
            ? (progressSnapshot?.workoutCount ?? (runs.count + lifts.count))
            : (trainingScope == .running ? runs.count : lifts.count)
        let activeDayCount = trainingScope == .all
            ? (progressSnapshot?.activeWorkoutDays.count ?? 0)
            : Set(runs.map { Calendar.current.startOfDay(for: $0.startDate) }).count
        let duration = trainingScope == .all
            ? (progressSnapshot?.trainingDuration ?? (runDuration + liftDuration))
            : (trainingScope == .running ? runDuration : liftDuration)
        let cards: [(String, String, String)] = [
            ("Økter", "\(workoutCount)", "calendar"),
            ("Treningstid", duration.shortDuration, "clock"),
            (trainingScope == .strength ? "Treningsvolum" : "Distanse",
             trainingScope == .strength ? String(format: "%.0f kg", volume) :
                String(format: "%.1f km", trainingScope == .all
                    ? (progressSnapshot?.workoutDistanceMeters ?? (distance * 1_000)) / 1_000
                    : distance), trainingScope == .strength ? "dumbbell" : "figure.run"),
            (trainingScope == .strength ? "Arbeidssett" : "Aktive dager",
             trainingScope == .strength
                 ? "\(lifts.reduce(0) { $0 + $1.totalWorkingSets })"
                 : "\(activeDayCount)",
             "chart.bar")
        ]
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Oversikt")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                Spacer()
                Text(period.rawValue)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(cards.indices, id: \.self) { index in
                    let card = cards[index]
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: card.2)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(card.1)
                            .font(.system(size: 27, weight: .medium, design: .serif))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(card.0)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 19))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19)
                            .stroke(ATHLTHTheme.premiumGold.opacity(0.18), lineWidth: 0.8)
                    }
                }
            }
        }
    }

    private var premiumTrend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(trainingScope == .running ? "Utvikling i distanse"
                : trainingScope == .strength ? "Utvikling i treningsvolum"
                : "Treningsutvikling")
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
            Text(trainingScope == .running ? "Kilometer per økt"
                : trainingScope == .strength ? "Kilogram per økt"
                : "Treningstimer over tid")
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

            if trainingScope == .running {
                if selectedPeriodRunningWorkouts.isEmpty {
                    emptyTrend
                } else {
                    Chart(selectedPeriodRunningWorkouts) { workout in
                        BarMark(
                            x: .value("Dato", workout.startDate),
                            y: .value("km", (workout.distanceMeters ?? 0) / 1_000)
                        )
                        .foregroundStyle(ATHLTHTheme.accentDeep.gradient)
                        .cornerRadius(3)
                    }
                    .frame(height: 178)
                }
            } else if trainingScope == .strength {
                if selectedPeriodStrengthWorkouts.isEmpty {
                    emptyTrend
                } else {
                    Chart(selectedPeriodStrengthWorkouts) { workout in
                        BarMark(
                            x: .value("Dato", workout.startedAt),
                            y: .value("kg", workout.totalVolumeKilograms)
                        )
                        .foregroundStyle(ATHLTHTheme.accentDeep.gradient)
                        .cornerRadius(3)
                    }
                    .frame(height: 178)
                }
            } else if let snapshot = progressSnapshot, !snapshot.buckets.isEmpty {
                Chart(snapshot.buckets) { bucket in
                    AreaMark(
                        x: .value("Dato", bucket.startDate),
                        y: .value("Timer", bucket.trainingDuration / 3_600)
                    )
                    .foregroundStyle(ATHLTHTheme.champagneSoft)
                    LineMark(
                        x: .value("Dato", bucket.startDate),
                        y: .value("Timer", bucket.trainingDuration / 3_600)
                    )
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .frame(height: 178)
            } else {
                emptyTrend
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyTrend: some View {
        Label("Ingen registrerte økter for denne perioden", systemImage: "chart.xyaxis.line")
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .frame(maxWidth: .infinity, minHeight: 170)
    }

    private var recentActivity: some View {
        let runEntries = selectedPeriodRunningWorkouts.map {
            (date: $0.startDate, title: "Løping", detail:
                String(format: "%.1f km", ($0.distanceMeters ?? 0) / 1_000),
             symbol: "figure.run")
        }
        let strengthEntries = selectedPeriodStrengthWorkouts.map {
            (date: $0.startedAt, title: "Styrketrening",
             detail: "\($0.totalWorkingSets) arbeidssett", symbol: "dumbbell")
        }
        let entries = (trainingScope == .strength ? [] : runEntries) +
            (trainingScope == .running ? [] : strengthEntries)
        let sorted = entries.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 13) {
            Text("Siste økter")
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
            if sorted.isEmpty {
                Label("Ingen registrerte økter i perioden", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            } else {
                ForEach(Array(sorted.prefix(5).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 35, height: 35)
                            .background(ATHLTHTheme.champagneSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Text(item.detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    if item.date != sorted.prefix(5).last?.date {
                        Divider().overlay(ATHLTHTheme.divider)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var progressWithoutHealthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(green)
                    .frame(width: 48, height: 48)
                    .background(
                        green.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        health.hasRequestedAuthorization
                            ? ATHLTHLocalization.choose(
                                english: "No readable Apple Health progress yet",
                                norwegian: "Ingen lesbare helsedata ennå"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Progress without Apple Health",
                                norwegian: "Fremgang uten Apple Health"
                            )
                    )
                    .font(.headline)

                    Text(
                        health.hasRequestedAuthorization
                            ? ATHLTHLocalization.choose(
                                english: "Apple Health permissions have been reviewed, but no readable workouts, steps or sleep data were found for this period. This can also happen if read access was not granted. You can review access in the Health app.",
                                norwegian: "Apple Health-tillatelsene er gjennomgått, men vi fant ingen lesbare økter, skritt eller søvndata for perioden. Dette kan også skje hvis lesetilgang ikke ble gitt. Du kan kontrollere tilgangen i Helse-appen."
                            )
                            : ATHLTHLocalization.choose(
                                english: "Health-based charts are hidden until you review Apple Health access. Strength records, goals and ATHLTH progress remain available.",
                                norwegian: "Helsebaserte grafer skjules til du har gjennomgått Apple Health-tilgangen. Styrkeøkter, mål og ATHLTH-fremgang er fortsatt tilgjengelig."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private var progressHasHealthData: Bool {
        guard let snapshot = progressSnapshot else { return false }

        return snapshot.workoutCount > 0 ||
            (snapshot.totalSteps ?? 0) > 0 ||
            (snapshot.averageSleepDuration ?? 0) > 0 ||
            snapshot.trainingDuration > 0
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProgressPeriod.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        period = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(period == option ? .semibold : .medium))
                        .foregroundStyle(period == option ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            period == option ? green : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    ATHLTHTheme.cardWarm.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    ATHLTHTheme.premiumGold.opacity(0.12),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.07),
            radius: 12,
            x: 0,
            y: 6
        )
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(overviewTitle)
                        .font(.title3.weight(.bold))

                    Text("Tap a metric to explore the selected period.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(periodDateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let snapshot = progressSnapshot {
                HStack(spacing: 0) {
                    NavigationLink {
                        WorkoutHistoryView(
                            startDate: snapshot.startDate,
                            endDate: snapshot.endDate
                        )
                    } label: {
                        overviewMetric(
                            icon: "dumbbell.fill",
                            tint: green,
                            value: String(snapshot.workoutCount),
                            title: "Workouts",
                            change: snapshot.workoutChangePercent,
                            footer: comparisonLabel
                        )
                    }
                    .buttonStyle(.plain)

                    overviewDivider

                    NavigationLink {
                        ProgressMetricDetailView(
                            kind: .training,
                            snapshot: snapshot,
                            periodLabel: periodDateLabel
                        )
                    } label: {
                        overviewMetric(
                            icon: "clock.fill",
                            tint: purple,
                            value: snapshot.trainingDuration.shortDuration,
                            title: "Training",
                            change:
                                snapshot.trainingDurationChangePercent,
                            footer: comparisonLabel
                        )
                    }
                    .buttonStyle(.plain)

                    overviewDivider

                    NavigationLink {
                        ProgressMetricDetailView(
                            kind: .distance,
                            snapshot: snapshot,
                            periodLabel: periodDateLabel
                        )
                    } label: {
                        overviewMetric(
                            icon:
                                "point.topleft.down.to.point.bottomright.curvepath",
                            tint: blue,
                            value: String(
                                format: "%.1f km",
                                snapshot.workoutDistanceMeters / 1_000
                            ),
                            title: "Distance",
                            change:
                                snapshot.workoutDistanceChangePercent,
                            footer: comparisonLabel
                        )
                    }
                    .buttonStyle(.plain)

                    overviewDivider

                    NavigationLink {
                        ProgressConsistencyDetailView(
                            snapshot: consistencySnapshot
                        )
                    } label: {
                        overviewMetric(
                            icon: "calendar.badge.checkmark",
                            tint: green,
                            value:
                                "\(snapshot.activeWorkoutDays.count)d",
                            title: "Consistency",
                            change: nil,
                            footer: periodSummaryLabel
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if progressLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else if let progressError {
                Label(
                    progressError,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private var personalRecordsCard: some View {
        let healthRecords = Array((trainingScope == .strength ? [] : personalRecords).prefix(2))
        let strengthRecords = Array(
            (trainingScope == .running ? [] : strengthWorkout.personalRecords)
                .filter { $0.kind == .heaviestSet }
                .prefix(2)
        )
        let totalRecordCount =
            (trainingScope == .strength ? 0 : personalRecords.count) +
            (trainingScope == .running ? 0 : strengthWorkout.personalRecords.count + strengthWorkout.repPersonalRecords.count)

        return NavigationLink {
            ProgressPersonalRecordsView(
                healthRecords: trainingScope == .strength ? [] : personalRecords,
                strengthRecords:
                    trainingScope == .running ? [] : strengthWorkout.personalRecords,
                repRecords:
                    trainingScope == .running ? [] : strengthWorkout.repPersonalRecords
            )
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personlige rekorder")
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text("Dine beste registrerte prestasjoner.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if totalRecordCount >
                        healthRecords.count +
                        strengthRecords.count {
                        Text(
                            "+\(totalRecordCount - healthRecords.count - strengthRecords.count)"
                        )
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(green)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                if healthRecords.isEmpty &&
                    strengthRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "trophy")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text("Ingen rekorder ennå")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text(
                            "Rekorder vises når du har registrert treningsøkter."
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(healthRecords) { record in
                        recordRow(
                            record.kind.title,
                            value: record.formattedValue,
                            date: record.date.formatted(
                                .dateTime
                                    .month(.abbreviated)
                                    .day()
                                    .year()
                            ),
                            icon: record.kind.systemImage
                        )
                    }

                    if !healthRecords.isEmpty &&
                        !strengthRecords.isEmpty {
                        Divider()
                            .overlay(
                                Color.black.opacity(0.05)
                            )
                    }

                    ForEach(strengthRecords) { record in
                        recordRow(
                            record.title,
                            value: record.value,
                            date: record.date.formatted(
                                .dateTime
                                    .month(.abbreviated)
                                    .day()
                                    .year()
                            ),
                            icon: record.kind.systemImage
                        )
                    }
                }
            }
            .padding(16)
            .progressReferenceCard()
        }
        .buttonStyle(.plain)
    }

    private var achievementsCard: some View {
        TrophyProgressCard()
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(width: 1, height: 100)
    }


    private func overviewMetric(
        icon: String,
        tint: Color,
        value: String,
        title: String,
        change: Double?,
        footer: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.68)
                .lineLimit(1)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let change {
                changeIndicator(change)
            } else {
                Text("—")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(footer)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func changeIndicator(_ change: Double?) -> some View {
        if let change {
            HStack(spacing: 2) {
                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                Text("\(abs(change), specifier: "%.0f")%")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(change >= 0 ? green : Color.orange)
        } else {
            Text("—")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }


    private var overviewTitle: String {
        switch period {
        case .week: return "Weekly Overview"
        case .month: return "Monthly Overview"
        case .threeMonths: return "3 Month Overview"
        case .year: return "Year Overview"
        }
    }

    private var comparisonLabel: String {
        switch period {
        case .week: return "vs. prior 7 days"
        case .month: return "vs. prior month"
        case .threeMonths: return "vs. prior 3 mo."
        case .year: return "vs. prior year"
        }
    }

    private var periodSummaryLabel: String {
        switch period {
        case .week: return "last 7 days"
        case .month: return "last month"
        case .threeMonths: return "last 3 months"
        case .year: return "last year"
        }
    }

    private var periodDateLabel: String {
        let range = progressRange
        let start = range.start.formatted(.dateTime.month(.abbreviated).day())
        let end = range.end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    private var stepsChartUpperBound: Double {
        let maximum = progressSnapshot?.buckets
            .compactMap(\.averageDailySteps)
            .max() ?? 0
        let rounded = ceil(maximum / 5_000) * 5_000
        return max(10_000, rounded)
    }



    private var progressGrouping: HealthProgressGrouping {
        switch period {
        case .week:
            return .day
        case .month, .threeMonths:
            return .week
        case .year:
            return .month
        }
    }

    private var progressRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()

        // Progress periods are rolling windows anchored to the current
        // moment. They must not reset at the start of a calendar
        // week/month/year; otherwise Monday would contain only Monday
        // and the first day of a month would contain only that day.
        let start: Date
        let previousStart: Date

        switch period {
        case .week:
            start =
                calendar.date(
                    byAdding: .day,
                    value: -7,
                    to: now
                ) ??
                now.addingTimeInterval(-604_800)
            previousStart =
                calendar.date(
                    byAdding: .day,
                    value: -7,
                    to: start
                ) ??
                start.addingTimeInterval(-604_800)

        case .month:
            start =
                calendar.date(
                    byAdding: .month,
                    value: -1,
                    to: now
                ) ??
                now.addingTimeInterval(-2_592_000)
            previousStart =
                calendar.date(
                    byAdding: .month,
                    value: -1,
                    to: start
                ) ??
                start.addingTimeInterval(-2_592_000)

        case .threeMonths:
            start =
                calendar.date(
                    byAdding: .month,
                    value: -3,
                    to: now
                ) ??
                now.addingTimeInterval(-7_776_000)
            previousStart =
                calendar.date(
                    byAdding: .month,
                    value: -3,
                    to: start
                ) ??
                start.addingTimeInterval(-7_776_000)

        case .year:
            start =
                calendar.date(
                    byAdding: .year,
                    value: -1,
                    to: now
                ) ??
                now.addingTimeInterval(-31_536_000)
            previousStart =
                calendar.date(
                    byAdding: .year,
                    value: -1,
                    to: start
                ) ??
                start.addingTimeInterval(-31_536_000)
        }

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: start
        )
    }

    private var selectedPeriodRunningWorkouts: [WorkoutSummary] {
        let range = progressRange

        return workoutHistory.filter {
            $0.activity == .running &&
            $0.startDate >= range.start &&
            $0.startDate <= range.end
        }
    }

    private var selectedPeriodStrengthWorkouts: [StrengthWorkoutLog] {
        let range = progressRange

        return strengthWorkout.workoutHistory.filter {
            $0.isFinished &&
            $0.startedAt >= range.start &&
            $0.startedAt <= range.end
        }
    }

    private var consistencyRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-7_776_000)
        let previousStart = calendar.date(byAdding: .day, value: -90, to: start)
            ?? start.addingTimeInterval(-7_776_000)

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: start
        )
    }

    private func loadSupportingProgressData() async {
        let performanceID =
            ATHLTHPerformance.begin("ProgressSupportingData")
        defer {
            ATHLTHPerformance.end(
                "ProgressSupportingData",
                id: performanceID
            )
        }

        guard health.healthDataAvailable,
              health.hasRequestedAuthorization
        else {
            consistencySnapshot = nil
            personalRecords = []
            workoutHistory = []
            return
        }

        let consistency = consistencyRange

        async let consistencyData = health.progressSnapshot(
            startDate: consistency.start,
            endDate: consistency.end,
            previousStartDate: consistency.previousStart,
            previousEndDate: consistency.previousEnd,
            grouping: .day
        )

        // Load the shared workout history once. personalRecords() then reuses
        // HealthKitManager's historical cache instead of issuing a second
        // unbounded workout query at the same time.
        workoutHistory =
            (try? await health.workoutHistory()) ?? []
        personalRecords =
            (try? await health.personalRecords()) ?? []
        consistencySnapshot = try? await consistencyData
    }

    private func loadProgressData() async {
        let performanceID =
            ATHLTHPerformance.begin("ProgressRangeLoad")
        defer {
            ATHLTHPerformance.end(
                "ProgressRangeLoad",
                id: performanceID
            )
        }

        guard health.healthDataAvailable else {
            progressSnapshot = nil
            progressError = "Apple Health is unavailable on this device."
            return
        }

        guard health.hasRequestedAuthorization else {
            progressSnapshot = nil
            progressError = ATHLTHLocalization.choose(
                english: "Review Apple Health access to show health-based progress.",
                norwegian: "Gjennomgå Apple Health-tilgang for å vise helsebasert fremgang."
            )
            return
        }

        progressLoading = true
        progressError = nil
        defer { progressLoading = false }

        let range = progressRange

        do {
            progressSnapshot = try await health.progressSnapshot(
                startDate: range.start,
                endDate: range.end,
                previousStartDate: range.previousStart,
                previousEndDate: range.previousEnd,
                grouping: progressGrouping
            )
        } catch {
            progressSnapshot = nil
            progressError = error.localizedDescription
        }
    }

    private func recordRow(
        _ title: String,
        value: String,
        date: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(date)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.caption.weight(.bold))
        }
    }



}

extension View {
    func progressReferenceCard() -> some View {
        self
            .background(
                Color.white.opacity(0.97),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, x: 0, y: 7)
    }
}

struct ATHLTHSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(
        context: Context
    ) -> UIViewController {
        SwipeBackController()
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {}

    private final class SwipeBackController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)

            navigationController?
                .interactivePopGestureRecognizer?
                .delegate = nil
            navigationController?
                .interactivePopGestureRecognizer?
                .isEnabled = true
        }
    }
}

struct ATHLTHProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var profileRecords: ATHLTHProfileRecordSyncStore
    @EnvironmentObject private var accountService:
        SupabaseAccountService
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var pets: ATHLTHPetStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var strengthWorkout:
        StrengthWorkoutStore
    @EnvironmentObject private var challenges:
        ChallengeStore

    @State private var performanceStats:
        ProfilePerformanceStats?
    @State private var personalRecords:
        [HealthPersonalRecord] = []
    @State private var profilePerformanceWorkoutHistory:
        [WorkoutSummary] = []
    @State private var mostTrainedItems: [ATHLTHProfileHighlights.TrainedItem] = []
    @State private var mostTrainedSyncTask: Task<Void, Never>?
    @State private var mostTrainedRefreshTask: Task<Void, Never>?
    @State private var featuredRecordRefreshTask: Task<Void, Never>?
    @State private var mostTrainedPendingItems: [ATHLTHProfileHighlights.TrainedItem]?
    @State private var mostTrainedPendingUserID: UUID?
    @State private var lastSyncedMostTrainedItems: [ATHLTHProfileHighlights.TrainedItem] = []
    @State private var lastMostTrainedSyncAt: Date?
    @State private var lastMostTrainedSyncUserID: UUID?
    @State private var cachedFeaturedRecordValues: [ProfileFeaturedRecordKind: String] = [:]
    @State private var loadingProfileData = false
    @State private var showingProfilePhotoPicker =
        false
    @State private var selectedProfilePhoto:
        PhotosPickerItem?
    @State private var pendingProfileCropImage:
        UIImage?
    @State private var showingProfileCrop =
        false
    @State private var updatingProfilePhoto =
        false
    @State private var pendingProfilePhotoUploadData:
        Data?
    @State private var showingProfilePhotoUploadPreview =
        false
    @State private var profilePhotoError:
        String?
    @State private var showingHeaderPicker =
        false
    @State private var selectedHeaderPhoto:
        PhotosPickerItem?
    @State private var pendingHeaderCropRequest:
        CommunityImageCropRequest?
    @State private var pendingProfileHeaderUploadData:
        Data?
    @State private var showingProfileHeaderUploadPreview =
        false
    @State private var updatingProfileHeader =
        false
    // The account-backed selection is already synchronized by
    // ATHLTHProfileRecordSyncStore. The old device-global AppStorage key
    // is only a one-time migration fallback inside that store.
    private var featuredRecordSelectionRaw: String {
        profileRecords.selectionRaw
    }
    @AppStorage(ProfileMomentFavorites.storageKey)
    private var favoriteMomentSelectionRaw = ""

    var body: some View {
        ATHLTHPinnedHeroLayout(
            accent: ATHLTHTrainDesign.gold.opacity(0.16),
            // Reuse the Home fade and warm canvas. Disable the bright
            // sheet outline while keeping the same modest 8 pt overlap.
            softTransition: true,
            pullDownFadeBridge: true,
            warmHomePalette: true,
            sheetOverlapOverride: 8,
            fadeBridgeIntensity: 0.58
        ) {
            profileHero
        } content: {
            LazyVStack(spacing: 12) {
                ATHLTHProfileCompetitionCard(userID: session.profile.userID)
                HStack(alignment: .top, spacing: 10) {
                    compactProfileTrophies
                    ATHLTHProfileMostTrainedCard(items: mostTrainedItems)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                ATHLTHPrivateGoalsProfileCard()
                personalRecordsSection
                gearSection
                ATHLTHPetProfileSection()
                workoutMomentsSection
            }
            .padding(.horizontal, 14)
            // Keep the first card comfortably below the short hero fade.
            .padding(.top, 24)
            .padding(.bottom, 120)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(
            .hidden,
            for: .navigationBar
        )
        .toolbarColorScheme(
            .dark,
            for: .navigationBar
        )
        .background {
            ATHLTHSwipeBackEnabler()
                .frame(
                    width: 0,
                    height: 0
                )
        }
        .refreshable {
            // Pull-to-refresh bypasses the short cloud preview cache so
            // updates completed on iPad appear on iPhone immediately.
            lastMostTrainedSyncAt = nil
            await refreshProfile(forceRefresh: true)
            scheduleMostTrainedRefresh()
            scheduleFeaturedRecordRefresh()
            await pets.refresh()
        }
        .task {
            // Keep the first frame free of disk decoding and full history
            // aggregation. The pet card loads its own data when necessary.
            scheduleMostTrainedRefresh()
            scheduleFeaturedRecordRefresh()
            await refreshProfile()
        }
        .onChange(of: session.profile.userID) { _, _ in
            cachedFeaturedRecordValues = [:]
            mostTrainedItems = []
            mostTrainedSyncTask?.cancel()
            mostTrainedPendingItems = nil
            mostTrainedPendingUserID = nil
            lastMostTrainedSyncAt = nil
            scheduleMostTrainedRefresh()
            scheduleFeaturedRecordRefresh()
        }
        .onChange(of: session.signedIn) { _, _ in
            lastMostTrainedSyncAt = nil
            scheduleMostTrainedRefresh()
        }
        .onChange(of: featuredRecordSelectionRaw) { _, _ in
            scheduleFeaturedRecordRefresh()
        }
        .onChange(of: health.workouts.count) { _, _ in
            scheduleFeaturedRecordRefresh()
        }
        .onChange(of: strengthWorkout.workoutHistory.count) { _, _ in
            scheduleMostTrainedRefresh()
            scheduleFeaturedRecordRefresh()
        }
        .onDisappear {
            mostTrainedRefreshTask?.cancel()
            mostTrainedSyncTask?.cancel()
            mostTrainedPendingItems = nil
            mostTrainedPendingUserID = nil
            featuredRecordRefreshTask?.cancel()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)
        ) { notification in
            guard let userID = notification.object as? UUID,
                  userID == session.profile.userID else { return }
            scheduleMostTrainedRefresh()
            scheduleFeaturedRecordRefresh()
        }
        .photosPicker(
            isPresented:
                $showingProfilePhotoPicker,
            selection:
                $selectedProfilePhoto,
            matching: .images
        )
        .onChange(
            of: selectedProfilePhoto
        ) { _, newItem in
            guard let newItem else {
                return
            }

            Task {
                await prepareProfilePhoto(
                    newItem
                )
            }
        }
        .fullScreenCover(
            isPresented:
                $showingProfileCrop
        ) {
            if let pendingProfileCropImage {
                ATHLTHAvatarCropView(
                    image:
                        pendingProfileCropImage,
                    onCancel: {
                        selectedProfilePhoto =
                            nil
                        self.pendingProfileCropImage =
                            nil
                        showingProfileCrop =
                            false
                    },
                    onUse: { jpegData in
                        selectedProfilePhoto =
                            nil
                        self.pendingProfileCropImage =
                            nil
                        showingProfileCrop =
                            false
                        pendingProfilePhotoUploadData =
                            jpegData
                        showingProfilePhotoUploadPreview =
                            true
                    }
                )
            }
        }
        .sheet(
            isPresented:
                $showingProfilePhotoUploadPreview
        ) {
            if let pendingProfilePhotoUploadData {
                ATHLTHProfileMediaUploadPreview(
                    jpegData:
                        pendingProfilePhotoUploadData,
                    shape: .avatar,
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Profile photo",
                            norwegian:
                                "Profilbilde"
                        ),
                    isUploading:
                        updatingProfilePhoto,
                    onCancel: {
                        showingProfilePhotoUploadPreview =
                            false
                        self.pendingProfilePhotoUploadData =
                            nil
                    },
                    onUpload: {
                        let data =
                            self.pendingProfilePhotoUploadData
                        showingProfilePhotoUploadPreview =
                            false
                        self.pendingProfilePhotoUploadData =
                            nil

                        if let data {
                            Task {
                                await saveProfilePhoto(
                                    data
                                )
                            }
                        }
                    }
                )
            }
        }
        .sheet(
            isPresented:
                $showingHeaderPicker
        ) {
            ATHLTHProfileHeaderPickerView(
                currentArtwork:
                    session.profile
                        .headerArtworkName ??
                    "ProfileHero",
                hasCustomImage:
                    session.profile
                        .headerImageURL != nil,
                selectedPhoto:
                    $selectedHeaderPhoto,
                dimStrength:
                    Binding(
                        get: {
                            session.profile
                                .headerDimStrength ??
                            0
                        },
                        set: { value in
                            session.profile
                                .headerDimStrength =
                                min(
                                    max(value, 0),
                                    0.45
                                )
                        }
                    ),
                isUpdating:
                    updatingProfileHeader,
                onSelectArtwork: { artwork in
                    Task {
                        await setProfileHeaderArtwork(
                            artwork
                        )
                    }
                },
                onDimStrengthCommit: { value in
                    Task {
                        await setProfileHeaderDimStrength(
                            value
                        )
                    }
                }
            )
        }
        .onChange(
            of: selectedHeaderPhoto
        ) { _, item in
            guard let item else {
                return
            }

            Task {
                await prepareProfileHeaderPhoto(
                    item
                )
            }
        }
        .fullScreenCover(
            item:
                $pendingHeaderCropRequest
        ) { request in
            CommunityImageCropEditor(
                request: request
            ) { jpegData in
                pendingHeaderCropRequest =
                    nil
                pendingProfileHeaderUploadData =
                    jpegData
                showingProfileHeaderUploadPreview =
                    true
            }
        }
        .sheet(
            isPresented:
                $showingProfileHeaderUploadPreview
        ) {
            if let pendingProfileHeaderUploadData {
                ATHLTHProfileMediaUploadPreview(
                    jpegData:
                        pendingProfileHeaderUploadData,
                    shape: .header,
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Profile header",
                            norwegian:
                                "Profilheader"
                        ),
                    isUploading:
                        updatingProfileHeader,
                    onCancel: {
                        showingProfileHeaderUploadPreview =
                            false
                        self.pendingProfileHeaderUploadData =
                            nil
                    },
                    onUpload: {
                        let data =
                            self.pendingProfileHeaderUploadData
                        showingProfileHeaderUploadPreview =
                            false
                        self.pendingProfileHeaderUploadData =
                            nil

                        if let data {
                            Task {
                                await saveProfileHeader(
                                    data
                                )
                            }
                        }
                    }
                )
            }
        }
        .alert(
            "ATHLTH",
            isPresented:
                Binding(
                    get: {
                        profilePhotoError !=
                            nil
                    },
                    set: {
                        if !$0 {
                            profilePhotoError =
                                nil
                        }
                    }
                )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {}
        } message: {
            Text(
                profilePhotoError ??
                ""
            )
        }
    }

    private var profileHero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                profileHeaderImage
                    .athlthBoundedFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .accessibilityHidden(true)

                Color.black
                    .opacity(
                        min(
                            max(
                                session.profile
                                    .headerDimStrength ??
                                0,
                                0
                            ),
                            0.45
                        )
                    )
                    .allowsHitTesting(false)

                LinearGradient(
                    stops: [
                        .init(
                            color:
                                Color.black.opacity(0.06),
                            location: 0
                        ),
                        .init(
                            color:
                                Color.black.opacity(0.12),
                            location: 0.42
                        ),
                        .init(
                            color:
                                Color.black.opacity(0.74),
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    Spacer()

                    HStack(
                        alignment: .top,
                        spacing: 14
                    ) {
                        ZStack(alignment: .bottomTrailing) {
                            NavigationLink {
                                ATHLTHEditProfileView(
                                    onEditHeader: {
                                        showingHeaderPicker = true
                                    }
                                )
                            } label: {
                                profileAvatar
                                    .overlay {
                                        if isOwnProfileTrainingNow {
                                            Circle()
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(red: 0.96, green: 0.72, blue: 0.35),
                                                            Color(red: 0.87, green: 0.46, blue: 0.16)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 3
                                                )
                                                .padding(-4)
                                                .allowsHitTesting(false)
                                        } else if isOwnProfileOnline {
                                            Circle()
                                                .strokeBorder(
                                                    Color(red: 0.24, green: 0.68, blue: 0.37),
                                                    lineWidth: 3
                                                )
                                                .padding(-4)
                                                .allowsHitTesting(false)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                ATHLTHLocalization.choose(
                                    english: "Edit profile",
                                    norwegian: "Rediger profil"
                                )
                            )

                            NavigationLink {
                                ATHLTHEditProfileView(
                                    onEditHeader: {
                                        showingHeaderPicker = true
                                    }
                                )
                            } label: {
                                Group {
                                    if updatingProfilePhoto {
                                        ProgressView()
                                            .controlSize(
                                                .mini
                                            )
                                            .tint(.white)
                                    } else {
                                        Image(
                                            systemName:
                                                "pencil"
                                        )
                                        .font(
                                            .system(
                                                size: 9.5,
                                                weight:
                                                    .semibold
                                            )
                                        )
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(
                                    width: 24,
                                    height: 24
                                )
                                .background(
                                    Color.black
                                        .opacity(
                                            0.38
                                        ),
                                    in: Circle()
                                )
                                .overlay {
                                    Circle()
                                        .stroke(
                                            Color.white
                                                .opacity(
                                                    0.48
                                                ),
                                            lineWidth:
                                                0.8
                                        )
                                }
                                .shadow(
                                    color:
                                        Color.black
                                            .opacity(
                                                0.16
                                            ),
                                    radius: 3,
                                    y: 1
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                ATHLTHLocalization.choose(
                                    english: "Edit profile, photo and header",
                                    norwegian: "Rediger profil, profilbilde og profilheader"
                                )
                            )
                            .offset(
                                x: 4,
                                y: 4
                            )
                        }

                        ATHLTHProfileHeroIdentityView(
                            name: session.profile.displayName,
                            username: session.profile.username.isEmpty
                                ? ""
                                : "@\(session.profile.username)",
                            trainingFocus: trainingIdentityFocus?.title,
                            bio: session.profile.bio
                        )

                        Spacer(minLength: 0)
                    }
                    // Visually lower avatar, name, username, focus and bio,
                    // keeping the follower/workout/stat cards fixed.
                    .offset(y: ATHLTHProfileHeroIdentityView.heroRowDownshift)

                    heroStatRow
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .shadow(
                    color:
                        Color.black.opacity(0.28),
                    radius: 12,
                    y: 5
                )
            }
        }
        .frame(height: 236)
        .clipped()
    }

    // The avatar mirrors friends' realtime indicators but observes the
    // owner's independent status-sharing choices. No opt-in, no badge.
    private var isOwnProfileOnline: Bool {
        social.privacy?.showOnlineStatus == true &&
            realtime.isOnline(session.profile.userID)
    }

    private var isOwnProfileTrainingNow: Bool {
        social.privacy?.shareTrainingPresence == true &&
            realtime.isTrainingNow(session.profile.userID)
    }

    private var heroStatRow: some View {
        HStack(spacing: 6) {
            NavigationLink {
                ProfileFollowListView(
                    mode: .followers
                )
            } label: {
                heroStat(
                    value:
                        social.followerCount
                            .formatted(),
                    title:
                        ATHLTHLocalization.choose(
                            english: "Followers",
                            norwegian: "Følgere"
                        ),
                    icon: "person.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english:
                        "Open your followers",
                    norwegian:
                        "Åpne følgerne dine"
                )
            )

            NavigationLink {
                ProfileFollowListView(
                    mode: .following
                )
            } label: {
                heroStat(
                    value:
                        social.followingCount
                            .formatted(),
                    title:
                        ATHLTHLocalization.choose(
                            english: "Following",
                            norwegian: "Følger"
                        ),
                    icon: "person.2.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english:
                        "Open profiles you follow",
                    norwegian:
                        "Åpne profiler du følger"
                )
            )

            NavigationLink {
                HomePersonalActivityHistoryView(
                    showOnlyMine: true
                )
            } label: {
                heroStat(
                    value:
                        profileWorkoutCount
                            .formatted(),
                    title:
                        ATHLTHLocalization.choose(
                            english: "Workouts",
                            norwegian: "Økter"
                        ),
                    icon: "figure.run"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english:
                        "Open your workout history",
                    norwegian:
                        "Åpne treningshistorikken din"
                )
            )

            NavigationLink {
                PerformanceStatsView(
                    stats:
                        performanceStats,
                    healthRecords:
                        personalRecords
                )
            } label: {
                heroStat(
                    value:
                        lifetimeTrainingTimeText,
                    title:
                        ATHLTHLocalization.choose(
                            english: "Total training time",
                            norwegian: "Total treningstid"
                        ),
                    icon:
                        "clock.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english:
                        "Open performance statistics",
                    norwegian:
                        "Åpne prestasjonsstatistikk"
                )
            )
        }
    }

    private func heroStat(
        value: String,
        title: String,
        icon: String
    ) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 11.5,
                            weight: .semibold
                        )
                    )
                    .frame(width: 14)

                Text(value)
                    .font(
                        .system(
                            size: 14,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )

            Text(title)
                .font(
                    .system(
                        size: 9,
                        weight: .medium
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.60)
                .multilineTextAlignment(.center)
                .frame(
                    maxWidth: .infinity,
                    alignment: .center
                )
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            Color.black.opacity(0.43),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.12),
                lineWidth: 0.6
            )
        }
    }

    /// The profile shows two equally important compact cards; the full trophy
    /// editor and collection remain available from the preview's See all link.
    private var compactProfileTrophies: some View {
        ATHLTHProfileCompactTrophyCard(
            trophies: profileTrophySlots,
            unlockedCount: trophyStore.trophies.filter(\.isUnlocked).count,
            syncWarning: trophyStore.lastCloudSyncIssue
        )
    }

    @MainActor
    private func scheduleMostTrainedRefresh() {
        mostTrainedRefreshTask?.cancel()
        mostTrainedRefreshTask = Task { @MainActor in
            // Coalesce bursts of training/import notifications.
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
            guard !Task.isCancelled else { return }
            refreshMostTrained()
        }
    }

    @MainActor
    private func refreshMostTrained() {
        let signpost = ATHLTHPerformance.begin("ProfileMostTrainedCompute")
        defer { ATHLTHPerformance.end("ProfileMostTrainedCompute", id: signpost) }
        let accountID = session.profile.userID
        let running = ATHLTHRunningPerformanceHistory.load(userID: accountID)
        let phone = AccountLocalStorage.read(
            [PhoneWorkout].self, name: "phoneHistory", userID: accountID
        ) ?? []
        let localItems = ATHLTHProfileHighlights.mostTrained(
            strength: strengthWorkout.workoutHistory,
            running: running,
            phone: phone
        )
        // A different device may have more complete history. Keep the
        // richer already merged snapshot when local inputs are unchanged.
        if mostTrainedItems != localItems &&
            (lastMostTrainedSyncUserID != accountID ||
             lastSyncedMostTrainedItems != localItems) {
            mostTrainedItems = localItems
        }

        guard session.signedIn else {
            mostTrainedSyncTask?.cancel()
            mostTrainedPendingItems = nil
            mostTrainedPendingUserID = nil
            return
        }
        if mostTrainedPendingUserID == accountID,
           mostTrainedPendingItems == localItems { return }
        guard ATHLTHProfileRefreshPolicy.shouldSyncMostTrained(
            userID: accountID,
            local: localItems,
            previousUserID: lastMostTrainedSyncUserID,
            previousLocal: lastSyncedMostTrainedItems,
            lastSyncedAt: lastMostTrainedSyncAt
        ) else { return }

        mostTrainedSyncTask?.cancel()
        mostTrainedPendingUserID = accountID
        mostTrainedPendingItems = localItems
        mostTrainedSyncTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(650)) }
            catch { return }
            let merged = await ATHLTHProfileMostTrainedSyncService.synchronize(
                userID: accountID, local: localItems
            )
            guard !Task.isCancelled, session.signedIn,
                  session.profile.userID == accountID else { return }
            lastMostTrainedSyncUserID = accountID
            lastSyncedMostTrainedItems = localItems
            lastMostTrainedSyncAt = Date()
            mostTrainedPendingUserID = nil
            mostTrainedPendingItems = nil
            if mostTrainedItems != merged { mostTrainedItems = merged }
        }
    }

    @MainActor
    private func scheduleFeaturedRecordRefresh() {
        featuredRecordRefreshTask?.cancel()
        featuredRecordRefreshTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            guard !Task.isCancelled else { return }
            refreshFeaturedRecordValues()
        }
    }

    @MainActor
    private func refreshFeaturedRecordValues() {
        let signpost = ATHLTHPerformance.begin("ProfileRecordTileCompute")
        defer { ATHLTHPerformance.end("ProfileRecordTileCompute", id: signpost) }
        // Read the currently selected PRs once rather than rebuilding a
        // full weekly/monthly history for every SwiftUI body evaluation.
        let workouts = profilePerformanceWorkoutHistory.isEmpty
            ? health.workouts : profilePerformanceWorkoutHistory
        var updated: [ProfileFeaturedRecordKind: String] = [:]
        for kind in featuredRecordKinds {
            updated[kind] = kind.displayValue(
                healthRecords: personalRecords,
                stats: performanceStats,
                strengthRecords: strengthWorkout.personalRecords,
                strengthRepRecords: strengthWorkout.repPersonalRecords,
                performanceWorkouts: workouts,
                strengthWorkouts: strengthWorkout.workoutHistory
            )
        }
        if cachedFeaturedRecordValues != updated {
            cachedFeaturedRecordValues = updated
        }
    }

    private var personalRecordsSection: some View {
        ATHLTHProfileRecordShelf(
            destination: AnyView(
                PerformanceStatsView(
                    stats: performanceStats,
                    healthRecords: personalRecords
                )
            )
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 7),
                    GridItem(.flexible(), spacing: 7)
                ],
                spacing: 7
            ) {
                ForEach(0..<ProfileFeaturedRecordKind.showcaseLimit, id: \.self) { index in
                    if featuredRecordKinds.indices.contains(index) {
                        recordCard(kind: featuredRecordKinds[index])
                    } else {
                        NavigationLink {
                            ProfileRecordShowcasePickerView(
                                stats: performanceStats,
                                healthRecords: personalRecords
                            )
                            .environmentObject(strengthWorkout)
                        } label: {
                            emptyRecordShowcaseCard
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var gearSection: some View {
        profileSection(
            title:
                ATHLTHLocalization.choose(
                    english: "My gear",
                    norwegian: "Mitt utstyr"
                ),
            icon: "shoeprints.fill",
            actionTitle:
                ATHLTHLocalization.choose(
                    english: "Edit",
                    norwegian: "Rediger"
                ),
            destination:
                AnyView(
                    ProfileGearManagerView()
                ),
            compact: true
        ) {
            if featuredGear.isEmpty {
                NavigationLink {
                    ProfileGearManagerView()
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                "plus.circle.fill"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Add shoes, watch, headphones or other gear.",
                                norwegian:
                                    "Legg til sko, klokke, hodetelefoner eller annet utstyr."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                        Spacer()
                    }
                    .padding(12)
                    .background(
                        Color.black.opacity(
                            0.025
                        ),
                        in: RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    ForEach(
                        featuredGear
                    ) { item in
                        gearTile(item)
                    }
                }
            }
        }
    }

    private var workoutMomentsSection:
        some View {
        let media = profileMedia
        let highlights = recentWorkoutHighlights
        let workoutIDs = Set(media.map(\.workoutID))
        let matchingWorkouts = Dictionary(
            health.workouts.filter { workoutIDs.contains($0.id) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return profileSection(
            title:
                ATHLTHLocalization.choose(
                    english:
                        "Photos & highlights",
                    norwegian:
                        "Bilder og høydepunkter"
                ),
            icon:
                "photo.on.rectangle.angled",
            actionTitle:
                ATHLTHLocalization.choose(
                    english: "Manage",
                    norwegian: "Administrer"
                ),
            destination:
                AnyView(
                    ProfileHighlightsManagerView()
                )
        ) {
            if media.isEmpty && highlights.isEmpty {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            "photo.badge.plus"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Favorite workout moments appear here",
                                norwegian:
                                    "Favoritter fra øktene dine vises her"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Open Manage to choose the photos and workout highlights you want to feature on your profile.",
                                norwegian:
                                    "Åpne Administrer for å velge bildene og høydepunktene du vil vise på profilen."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }

                    Spacer()
                }
                .padding(12)
                .background(
                    Color.black.opacity(0.025),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
            } else {
                ScrollView(
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: 8) {
                        ForEach(media) { item in
                            mediaTile(item, workout: matchingWorkouts[item.workoutID])
                        }

                        ForEach(highlights) { highlight in
                            highlightTile(
                                highlight
                            )
                        }
                    }
                }
            }
        }
    }

    private func profileSection<Content: View>(
        title: String,
        icon: String,
        actionTitle: String,
        destination: AnyView,
        compact: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: compact ? 8 : 12
        ) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                Text(title)
                    .font(
                        .title3.weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Spacer()

                NavigationLink {
                    destination
                } label: {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(
                            systemName:
                                "chevron.right"
                        )
                    }
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                }
                .buttonStyle(.plain)
            }

            content()
        }
        // Only the gear preview opts into smaller section insets.
        .padding(compact ? 10 : 14)
        .background(
            Color.white.opacity(0.91),
            in: RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.88),
                lineWidth: 0.9
            )
        }
        .shadow(
            color: Color.black.opacity(0.035),
            radius: 14,
            y: 6
        )
    }


    private var featuredRecordKinds:
        [ProfileFeaturedRecordKind] {
        ProfileFeaturedRecordKind
            .decodedSelection(
                from:
                    featuredRecordSelectionRaw
            )
    }

    /// The original data, highlighted choices and full record picker are
    /// preserved. Only the profile preview is condensed into quiet mini-tiles.
    private func recordCard(kind: ProfileFeaturedRecordKind) -> some View {
        HStack(spacing: 9) {
            Image(systemName: kind.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 31, height: 31)
                .background(
                    ATHLTHTheme.premiumGoldSoft.opacity(0.52),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(profileRecords.value(
                    for: kind,
                    local: cachedFeaturedRecordValues[kind] ?? "—"
                ))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .contentTransition(.numericText())

                Text(kind.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(Color.white.opacity(0.91),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ATHLTHTheme.premiumGold.opacity(0.13), lineWidth: 0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyRecordShowcaseCard: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 31, height: 31)
                .background(
                    ATHLTHTheme.premiumGoldSoft.opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            Text(ATHLTHLocalization.choose(
                english: "Choose record", norwegian: "Velg rekord"
            ))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ATHLTHTheme.mutedText)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(Color.white.opacity(0.64),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    ATHLTHTheme.premiumGold.opacity(0.24),
                    style: StrokeStyle(lineWidth: 0.8, dash: [3, 4])
                )
        }
    }

    private func gearTile(
        _ item: ProfileGearItem
    ) -> some View {
        HStack(spacing: 5) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .fill(
                    Color.black.opacity(
                        0.025
                    )
                )

                if let imageURL =
                    item.imageURL,
                   let url =
                    URL(string: imageURL) {
                    ATHLTHStorageImage(url: url) {
                        phase in
                        switch phase {
                        case .success(
                            let image
                        ):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(5)
                        default:
                            ProfileGearCategoryIcon(
                                category:
                                    item.category,
                                size: 18
                            )
                        }
                    }
                } else {
                    ProfileGearCategoryIcon(
                        category:
                            item.category,
                        size: 18
                    )
                }
            }
            .frame(
                width: 30,
                height: 32
            )

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text(item.name)
                    .font(
                        .system(
                            size: 10,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(0.90)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Text(
                    item.category.shortTitle
                )
                .font(
                    .system(
                        size: 8.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.92)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(
            maxWidth: .infinity,
            minHeight: 56,
            alignment: .leading
        )
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.category.shortTitle)")
    }

    private func mediaTile(
        _ media: WorkoutMediaRecord,
        workout: WorkoutSummary?
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            ATHLTHStorageImage(
                url: URL(
                    string: media.imageURL
                )
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    LinearGradient(
                        colors: [
                            ATHLTHTheme
                                .surfaceSage,
                            ATHLTHTheme
                                .canvasBottom
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                    .overlay {
                        Image(
                            systemName: "photo"
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }
                }
            }
            .frame(
                width: 132,
                height: 118
            )
            .clipped()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.54)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let workout {
                Text(
                    momentTitle(
                        for: workout
                    )
                )
                .font(
                    .caption2.weight(
                        .bold
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(9)
            }
        }
        .frame(
            width: 132,
            height: 118
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private func highlightTile(
        _ highlight: ProfileWorkoutHighlight
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            Image(
                systemName:
                    highlight.icon
            )
            .font(
                .system(
                    size: 18,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                highlight.tint
            )

            Spacer()

            Text(highlight.value)
                .font(
                    .system(
                        size: 18,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)

            Text(highlight.title)
                .font(
                    .caption2.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)

            Text(
                highlight.date.formatted(
                    date: .abbreviated,
                    time: .omitted
                )
            )
            .font(
                .system(
                    size: 8.5,
                    weight: .medium
                )
            )
            .foregroundStyle(
                ATHLTHTheme.mutedText
                    .opacity(0.82)
            )
        }
        .padding(12)
        .frame(
            width: 132,
            height: 118,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors: [
                    highlight.tint
                        .opacity(0.11),
                    Color.white.opacity(0.80)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                highlight.tint
                    .opacity(0.10),
                lineWidth: 0.8
            )
        }
    }

    private var profileTrophySlots:
        [TrophyProgressItem] {
        Array(
            trophyStore
                .showcaseTrophies
                .prefix(
                    TrophyStore
                        .showcaseLimit
                )
        )
    }

    private var featuredGear:
        [ProfileGearItem] {
        let featured =
            gear.items.filter(
                \.isFeatured
            )

        if !featured.isEmpty {
            return Array(
                featured.prefix(3)
            )
        }

        return Array(
            gear.items.prefix(3)
        )
    }

    private var favoriteMomentTokens:
        Set<String> {
        ProfileMomentFavorites.decode(
            favoriteMomentSelectionRaw
        )
    }

    private var profileMedia:
        [WorkoutMediaRecord] {
        let favorites = favoriteMomentTokens
        return Array(
            social.workoutMedia
                .filter { media in
                    favorites
                        .contains(
                            ProfileMomentFavorites
                                .mediaToken(
                                    media.id
                                )
                        )
                }
                .sorted {
                    $0.createdAt >
                        $1.createdAt
                }
                .prefix(8)
        )
    }

    private var recentWorkoutHighlights:
        [ProfileWorkoutHighlight] {
        let favorites =
            favoriteMomentTokens

        return health.workouts
            .filter { workout in
                favorites.contains(
                    ProfileMomentFavorites
                        .highlightToken(
                            workout.id
                        )
                )
            }
            .sorted {
                $0.startDate >
                    $1.startDate
            }
            .prefix(8)
            .map { workout in
                let value: String
                let title: String
                let icon: String
                let tint: Color

                if let meters =
                    workout.distanceMeters,
                   meters > 0 {
                    value = String(
                        format: "%.1f km",
                        meters / 1_000
                    )
                    title =
                        workout.activity.rawValue
                    icon =
                        workout.activity.icon
                    tint =
                        workout.activity ==
                            .running
                            ? ATHLTHTheme
                                .vitality
                            : .blue
                } else {
                    value =
                        profileDurationText(
                            workout.duration
                        )
                    title =
                        workout.activity.rawValue
                    icon =
                        workout.activity.icon
                    tint =
                        workout.activity ==
                            .strength
                            ? .indigo
                            : ATHLTHTheme
                                .accentDeep
                }

                return ProfileWorkoutHighlight(
                    id: workout.id,
                    title: title,
                    value: value,
                    date: workout.startDate,
                    icon: icon,
                    tint: tint
                )
            }
    }

    private var profileWorkoutCount: Int {
        performanceStats?
            .totalWorkoutCount ??
            health.workouts.count
    }

    /// Use the existing deduplicated Apple Health performance aggregate.
    /// This measures all supported workout types, not just running distance.
    private var lifetimeTrainingTimeText: String {
        guard let seconds = performanceStats?.totalTrainingDuration,
              seconds.isFinite, seconds >= 0 else { return "—" }

        let hours = seconds / 3_600
        if hours >= 1_000 {
            return String(format: "%.1fk t", hours / 1_000)
        }
        if hours >= 1 {
            return "\(Int(hours.rounded())) t"
        }
        if seconds > 0 {
            return "\(max(1, Int((seconds / 60).rounded()))) min"
        }
        return "0 t"
    }

    private var trainingIdentityFocus:
        TrainingFocus? {
        session.onboardingProfile?
            .trainingFocus
    }

    private func trophyTint(
        _ rarity: TrophyRarity
    ) -> Color {
        switch rarity {
        case .core:
            return ATHLTHTheme.accentDeep
        case .rare:
            return .blue
        case .epic:
            return .purple
        case .signature:
            return ATHLTHTheme
                .premiumGold
        }
    }

    private func momentTitle(
        for workout: WorkoutSummary
    ) -> String {
        if let meters =
            workout.distanceMeters,
           meters > 0 {
            return String(
                format:
                    "%.1f km · %@",
                meters / 1_000,
                workout.activity.rawValue
            )
        }

        return workout.activity.rawValue
    }

    private func profileDurationText(
        _ duration: TimeInterval
    ) -> String {
        let totalMinutes =
            max(
                Int(
                    (duration / 60)
                        .rounded()
                ),
                0
            )

        if totalMinutes >= 60 {
            return
                "\(totalMinutes / 60)t " +
                "\(totalMinutes % 60)m"
        }

        return "\(totalMinutes) min"
    }

    @ViewBuilder
    private var profileHeaderImage:
        some View {
        if let url =
                session.profile
                    .headerImageURL {
            ATHLTHStorageImage(
                url: url,
                maxPixelSize: 1800
            ) { phase in
                switch phase {
                case .success(
                    let image
                ):
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                default:
                    Image(
                        session.profile
                            .headerArtworkName ??
                        "ProfileHero"
                    )
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                }
            }
        } else {
            Image(
                session.profile
                    .headerArtworkName ??
                "ProfileHero"
            )
            .resizable()
            .interpolation(.high)
            .scaledToFill()
        }
    }

    @ViewBuilder
    private var profileAvatar:
        some View {
        if let avatarURL =
            session.profile.avatarURL {
            ATHLTHStorageImage(
                url: avatarURL
            ) { phase in
                switch phase {
                case .success(
                    let image
                ):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    avatarFallback
                }
            }
            .frame(
                width: 84,
                height: 84
            )
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        Color.white.opacity(
                            0.98
                        ),
                        lineWidth: 3
                    )
            }
            .shadow(
                color:
                    .black.opacity(0.22),
                radius: 12,
                y: 6
            )
        } else {
            avatarFallback
                .frame(
                    width: 84,
                    height: 84
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white
                                .opacity(0.98),
                            lineWidth: 3
                        )
                }
        }
    }

    private var avatarFallback:
        some View {
        Circle()
            .fill(
                ATHLTHTheme.accentSoft
            )
            .overlay {
                Image(
                    systemName: "person.fill"
                )
                .font(
                    .system(
                        size: 40,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
            }
    }

    @MainActor
    private func prepareProfilePhoto(
        _ item: PhotosPickerItem
    ) async {
        do {
            guard
                let data =
                    try await item
                        .loadTransferable(
                            type: Data.self
                        ),
                let image =
                    UIImage(data: data),
                let prepared =
                    ATHLTHAvatarCropper
                        .prepare(image)
            else {
                throw NSError(
                    domain:
                        "ATHLTH.ProfilePhoto",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            ATHLTHLocalization.choose(
                                english:
                                    "The selected photo could not be loaded.",
                                norwegian:
                                    "Det valgte bildet kunne ikke lastes."
                            )
                    ]
                )
            }

            pendingProfileCropImage =
                prepared
            showingProfileCrop = true
            profilePhotoError = nil
        } catch {
            selectedProfilePhoto = nil
            profilePhotoError =
                error.localizedDescription
        }
    }

    @MainActor
    private func saveProfilePhoto(
        _ jpegData: Data
    ) async {
        guard !updatingProfilePhoto
        else {
            return
        }

        updatingProfilePhoto = true
        profilePhotoError = nil

        defer {
            updatingProfilePhoto = false
        }

        do {
            let avatarURL =
                try await accountService
                    .uploadProfileAvatar(
                        jpegData: jpegData
                    )

            let bootstrap =
                try await accountService
                    .updateProfile(
                        displayName:
                            session.profile
                                .displayName,
                        username:
                            session.profile
                                .username,
                        bio:
                            session.profile
                                .bio,
                        avatarURL:
                            avatarURL
                    )

            session.applyBackendBootstrap(
                bootstrap
            )
            await social.refresh()
        } catch {
            profilePhotoError =
                error.localizedDescription
        }
    }

    @MainActor
    private func prepareProfileHeaderPhoto(
        _ item: PhotosPickerItem
    ) async {
        do {
            guard
                let data =
                    try await item
                        .loadTransferable(
                            type: Data.self
                        ),
                let image =
                    UIImage(data: data)
            else {
                throw ATHLTHPublicImageError
                    .invalidImage
            }

            selectedHeaderPhoto = nil
            showingHeaderPicker = false
            pendingHeaderCropRequest =
                CommunityImageCropRequest(
                    image: image,
                    target: .wideCover
                )
            profilePhotoError = nil
        } catch {
            selectedHeaderPhoto = nil
            profilePhotoError =
                error.localizedDescription
        }
    }

    @MainActor
    private func saveProfileHeader(
        _ jpegData: Data
    ) async {
        guard !updatingProfileHeader
        else {
            return
        }

        updatingProfileHeader = true
        profilePhotoError = nil

        defer {
            updatingProfileHeader = false
        }

        do {
            let imageURL =
                try await accountService
                    .uploadProfileHeader(
                        jpegData: jpegData
                    )

            let bootstrap =
                try await accountService
                    .updateProfileHeader(
                        artworkName: nil,
                        imageURL: imageURL
                    )

            session.applyBackendBootstrap(
                bootstrap
            )
            await social.refresh()
        } catch {
            profilePhotoError =
                error.localizedDescription
        }
    }

    @MainActor
    private func setProfileHeaderDimStrength(
        _ value: Double
    ) async {
        guard !updatingProfileHeader
        else {
            return
        }

        updatingProfileHeader = true
        profilePhotoError = nil

        defer {
            updatingProfileHeader = false
        }

        do {
            let bootstrap =
                try await accountService
                    .updateProfileHeaderDimStrength(
                        value
                    )

            session.applyBackendBootstrap(
                bootstrap
            )
            await social.refresh()
        } catch {
            profilePhotoError =
                error.localizedDescription
        }
    }

    @MainActor
    private func setProfileHeaderArtwork(
        _ artwork: String
    ) async {
        guard !updatingProfileHeader
        else {
            return
        }

        updatingProfileHeader = true
        profilePhotoError = nil

        defer {
            updatingProfileHeader = false
        }

        do {
            let bootstrap =
                try await accountService
                    .updateProfileHeader(
                        artworkName: artwork,
                        imageURL: nil
                    )

            session.applyBackendBootstrap(
                bootstrap
            )
            showingHeaderPicker = false
            await social.refresh()
        } catch {
            profilePhotoError =
                error.localizedDescription
        }
    }

    @MainActor
    private func refreshSocialForProfile(forceRefresh: Bool) async {
        if forceRefresh {
            await social.refresh()
        } else {
            await social.refreshIfStale(maxAge: 180)
        }
    }

    @MainActor
    private func refreshProfile(
        forceRefresh: Bool = false
    ) async {
        guard !loadingProfileData else {
            return
        }
        let signpost = ATHLTHPerformance.begin("OwnerProfileRefresh")
        defer { ATHLTHPerformance.end("OwnerProfileRefresh", id: signpost) }

        loadingProfileData = true
        defer {
            loadingProfileData = false
        }

        // Keep already available account data visible while the profile
        // refreshes. Do not reload the entire inbox/feed on every entry.
        async let socialRefresh: Void = refreshSocialForProfile(
            forceRefresh: forceRefresh
        )
        async let gearRefresh: Void = gear.refreshForProfile(
            forceRefresh: forceRefresh
        )
        async let mediaRefresh: Void = social.refreshWorkoutMediaIfNeeded(
            forceRefresh: forceRefresh
        )

        if health.hasRequestedAuthorization {
            async let statsTask =
                try? health
                    .profilePerformanceStats(
                        forceRefresh:
                            forceRefresh
                    )
            async let recordsTask =
                try? health
                    .personalRecords(
                        forceRefresh:
                            forceRefresh
                    )
            async let historyTask =
                try? health
                    .performanceWorkoutHistory(
                        forceRefresh:
                            forceRefresh
                    )

            let (
                loadedStats,
                loadedRecords,
                loadedHistory
            ) = await (
                statsTask,
                recordsTask,
                historyTask
            )

            performanceStats =
                loadedStats
            personalRecords =
                loadedRecords ?? []
            profilePerformanceWorkoutHistory =
                loadedHistory ?? []
        } else {
            performanceStats = nil
            personalRecords = []
            profilePerformanceWorkoutHistory = []
        }

        scheduleFeaturedRecordRefresh()

        await trophyStore.refresh(
            health: health,
            strength: strengthWorkout,
            goals: goalStore,
            challenges: challenges,
            currentUserID:
                session.profile.userID
        )

        _ = await (
            socialRefresh,
            gearRefresh,
            mediaRefresh
        )

        if social.privacy?
            .sharePerformanceStats == true {
            await social
                .syncOwnPerformance(
                    performanceStats
                )
        }

        if social.privacy?
            .shareTrophyCabinet == true {
            await social
                .syncOwnTrophies(
                    trophyStore
                        .showcaseTrophies
                )
        }

        if let privacy = social.privacy {
            await social.syncOwnGoals(
                goalStore.goals,
                enabled:
                    privacy.shareGoals
            )
        }
    }
}

private enum ATHLTHProfileMediaPreviewShape {
    case avatar
    case header
}

private struct ATHLTHProfileMediaUploadPreview:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    let jpegData: Data
    let shape:
        ATHLTHProfileMediaPreviewShape
    let title: String
    let isUploading: Bool
    let onCancel: () -> Void
    let onUpload: () -> Void

    private var image: UIImage? {
        UIImage(data: jpegData)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.18)
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    Spacer(
                        minLength: 20
                    )

                    if let image {
                        Group {
                            switch shape {
                            case .avatar:
                                Image(
                                    uiImage: image
                                )
                                .resizable()
                                .interpolation(
                                    .high
                                )
                                .scaledToFill()
                                .frame(
                                    width: 230,
                                    height: 230
                                )
                                .clipShape(
                                    Circle()
                                )
                                .overlay {
                                    Circle()
                                        .stroke(
                                            Color.white
                                                .opacity(
                                                    0.96
                                                ),
                                            lineWidth:
                                                4
                                        )
                                }

                            case .header:
                                Image(
                                    uiImage: image
                                )
                                .resizable()
                                .interpolation(
                                    .high
                                )
                                .scaledToFill()
                                .athlthBoundedFill()
                                .frame(
                                    maxWidth:
                                        .infinity
                                )
                                .aspectRatio(
                                    16.0 / 7.0,
                                    contentMode:
                                        .fit
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            24,
                                        style:
                                            .continuous
                                    )
                                )
                            }
                        }
                        .shadow(
                            color:
                                Color.black
                                    .opacity(
                                        0.12
                                    ),
                            radius: 16,
                            y: 7
                        )
                    }

                    VStack(spacing: 7) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Ready to upload?",
                                norwegian:
                                    "Klar til opplasting?"
                            )
                        )
                        .font(
                            .title3
                                .weight(.bold)
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "This is the crop other people will see. The image is safety checked before it can become public.",
                                norwegian:
                                    "Dette er utsnittet andre vil se. Bildet sikkerhetskontrolleres før det kan bli offentlig."
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .multilineTextAlignment(
                            .center
                        )
                        .padding(
                            .horizontal,
                            18
                        )
                    }

                    Button {
                        onUpload()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            if isUploading {
                                ProgressView()
                                    .controlSize(
                                        .small
                                    )
                                    .tint(
                                        .white
                                    )
                            } else {
                                Image(
                                    systemName:
                                        "arrow.up.circle.fill"
                                )
                            }

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Upload photo",
                                    norwegian:
                                        "Last opp bilde"
                                )
                            )
                        }
                        .font(
                            .headline
                        )
                        .foregroundStyle(
                            .white
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .frame(height: 52)
                        .background(
                            ATHLTHTheme
                                .accentDeep,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        isUploading
                    )

                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Choose another photo",
                                norwegian:
                                    "Velg et annet bilde"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english:
                                "Cancel",
                            norwegian:
                                "Avbryt"
                        )
                    ) {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ATHLTHProfileHeaderPickerView:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    let currentArtwork: String
    let hasCustomImage: Bool
    @Binding var selectedPhoto:
        PhotosPickerItem?
    @Binding var dimStrength: Double
    let isUpdating: Bool
    let onSelectArtwork:
        (String) -> Void
    let onDimStrengthCommit:
        (Double) -> Void

    private let artworkOptions = [
        "ProfileHero",
        "HomeHero",
        "TrainHero",
        "GoalRunning",
        "GoalMountain",
        "GoalStrength",
        "GoalAdventure",
        "GoalRecovery"
    ]

    private let columns = [
        GridItem(
            .flexible(),
            spacing: 10
        ),
        GridItem(
            .flexible(),
            spacing: 10
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    PhotosPicker(
                        selection:
                            $selectedPhoto,
                        matching: .images
                    ) {
                        HStack(spacing: 12) {
                            Image(
                                systemName:
                                    "photo.badge.plus"
                            )
                            .font(
                                .system(
                                    size: 18,
                                    weight:
                                        .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .frame(
                                width: 42,
                                height: 42
                            )
                            .background(
                                ATHLTHTheme
                                    .accentSoft,
                                in:
                                    RoundedRectangle(
                                        cornerRadius:
                                            13,
                                        style:
                                            .continuous
                                    )
                            )

                            VStack(
                                alignment:
                                    .leading,
                                spacing: 3
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Choose from Photos",
                                        norwegian:
                                            "Velg fra Bilder"
                                    )
                                )
                                .font(
                                    .headline
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Crop it to the profile header before it is safety checked and published.",
                                        norwegian:
                                            "Juster utsnittet før bildet sikkerhetskontrolleres og publiseres."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }

                            Spacer()

                            if hasCustomImage {
                                Image(
                                    systemName:
                                        "checkmark.circle.fill"
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .vitality
                                )
                            }
                        }
                        .padding(14)
                        .background(
                            Color.white.opacity(
                                0.90
                            ),
                            in:
                                RoundedRectangle(
                                    cornerRadius: 22,
                                    style:
                                        .continuous
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdating)

                    VStack(
                        alignment: .leading,
                        spacing: 9
                    ) {
                        HStack {
                            Label(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Dim header",
                                        norwegian:
                                            "Demp header"
                                    ),
                                systemImage:
                                    "circle.lefthalf.filled"
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                            Spacer()

                            Text(
                                "\(Int((dimStrength * 100).rounded()))%"
                            )
                            .font(
                                .caption
                                    .weight(
                                        .semibold
                                    )
                                    .monospacedDigit()
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }

                        Slider(
                            value:
                                Binding(
                                    get: {
                                        dimStrength
                                    },
                                    set: { value in
                                        dimStrength =
                                            min(
                                                max(
                                                    value,
                                                    0
                                                ),
                                                0.45
                                            )
                                    }
                                ),
                            in: 0...0.45,
                            step: 0.05,
                            onEditingChanged: {
                                editing in

                                if !editing {
                                    onDimStrengthCommit(
                                        dimStrength
                                    )
                                }
                            }
                        )
                        .tint(
                            ATHLTHTheme
                                .accentDeep
                        )
                        .disabled(isUpdating)
                        .accessibilityLabel(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "Dim profile header",
                                    norwegian:
                                        "Demp profilheader"
                                )
                        )
                    }
                    .padding(14)
                    .background(
                        Color.white.opacity(
                            0.90
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 20,
                                style:
                                    .continuous
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "ATHLTH images",
                                norwegian:
                                    "ATHLTH-bilder"
                            )
                        )
                        .font(
                            .headline
                        )

                        LazyVGrid(
                            columns: columns,
                            spacing: 10
                        ) {
                            ForEach(
                                artworkOptions,
                                id: \.self
                            ) { artwork in
                                Button {
                                    onSelectArtwork(
                                        artwork
                                    )
                                } label: {
                                    ZStack(
                                        alignment:
                                            .topTrailing
                                    ) {
                                        Image(
                                            artwork
                                        )
                                        .resizable()
                                        .scaledToFill()
                                        .athlthBoundedFill()
                                        .frame(
                                            height: 92
                                        )
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius:
                                                    16,
                                                style:
                                                    .continuous
                                            )
                                        )

                                        if !hasCustomImage &&
                                            currentArtwork ==
                                            artwork {
                                            Image(
                                                systemName:
                                                    "checkmark.circle.fill"
                                            )
                                            .font(
                                                .system(
                                                    size: 20,
                                                    weight:
                                                        .semibold
                                                )
                                            )
                                            .foregroundStyle(
                                                .white
                                            )
                                            .shadow(
                                                color:
                                                    .black
                                                    .opacity(
                                                        0.35
                                                    ),
                                                radius: 4
                                            )
                                            .padding(8)
                                        }
                                    }
                                }
                                .buttonStyle(
                                    .plain
                                )
                                .disabled(
                                    isUpdating
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.18)
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Profile header",
                    norwegian:
                        "Profilheader"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english:
                                "Close",
                            norwegian:
                                "Lukk"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProfileWorkoutHighlight:
    Identifiable {
    let id: UUID
    let title: String
    let value: String
    let date: Date
    let icon: String
    let tint: Color
}

private struct ProfileHexagonBadgeShape:
    Shape {
    func path(
        in rect: CGRect
    ) -> Path {
        let center =
            CGPoint(
                x: rect.midX,
                y: rect.midY
            )
        let radius =
            min(
                rect.width,
                rect.height
            ) / 2

        var path = Path()

        for index in 0..<6 {
            let angle =
                Double(index) *
                .pi / 3 -
                .pi / 2
            let point =
                CGPoint(
                    x:
                        center.x +
                        CGFloat(
                            cos(angle)
                        ) * radius,
                    y:
                        center.y +
                        CGFloat(
                            sin(angle)
                        ) * radius
                )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }
}

// SwiftUI's metadata can be deeply nested when a tab contains many distinct
// sheet and full-screen destinations. Break up the nested type tree before
// UIKit asks Swift to demangle it during presentation.
private extension View {
    func athlthStablePresentationBoundary() -> AnyView {
        AnyView(self)
    }
}
