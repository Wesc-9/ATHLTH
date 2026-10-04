import Charts
import Combine
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ATHLTHTrainNavigationRequest: Identifiable {
    case plan
    case workout(planID: UUID, workoutID: UUID)
    case quick(WorkoutKind)
    case customQuick
    case ghost

    var id: String {
        switch self {
        case .plan:
            return "plan"
        case let .workout(planID, workoutID):
            return "workout:\(planID.uuidString):\(workoutID.uuidString)"
        case let .quick(kind):
            return "quick:\(kind.title)"
        case .customQuick:
            return "quick:custom"
        case .ghost:
            return "ghost"
        }
    }
}

struct ProductRootTabView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore

    @State private var selectedTab: Int
    @State private var trainNavigationRequest:
        ATHLTHTrainNavigationRequest?

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

    var body: some View {
        TabView(selection: $selectedTab) {
            ATHLTHHomeView(
                onSelectTab: { tab in
                    selectedTab = tab
                },
                onOpenTrain: { request in
                    trainNavigationRequest = request
                    selectedTab = 2
                }
            )
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            ATHLTHRecoveryView { tab in
                selectedTab = tab
            }
                .tabItem {
                    Label(
                        "Insights",
                        systemImage: "sparkles"
                    )
                }
                .tag(1)

            ATHLTHTrainView(
                navigationRequest:
                    $trainNavigationRequest
            )
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }
                .tag(2)

            ATHLTHExploreView()
                .tabItem { Label("Explore", systemImage: "map.fill") }
                .tag(3)

            ATHLTHCommunityV4View()
                .tabItem { Label("Community", systemImage: "person.3.fill") }
                .tag(4)
        }
        .tint(ATHLTHTheme.accentDeep)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .athlthRemoteNotificationTapped
            )
        ) { notification in
            let kind = (
                notification.userInfo?["athlth_kind"] as? String
            )?.lowercased() ?? ""

            if kind.contains("message") ||
                kind.contains("friend") ||
                kind.contains("challenge") ||
                kind.contains("reaction") ||
                kind.contains("workout") {
                selectedTab = 4
            } else {
                selectedTab = 0
            }
        }
        .background {
            ATHLTHMirroredWorkoutPresenter()
                .frame(width: 0, height: 0)
        }
        .overlay(alignment: .top) {
            if workoutMirroring
                    .hasActiveMirroredWorkout,
               workoutMirroring
                    .isUserMinimized {
                Button {
                    workoutMirroring
                        .presentWorkout()
                } label: {
                    HStack(spacing: 10) {
                        Image(
                            systemName:
                                "figure.run"
                        )
                        .font(
                            .system(
                                size: 20,
                                weight:
                                    .semibold
                            )
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Return to Apple Watch workout",
                                norwegian:
                                    "Tilbake til Apple Watch-økt"
                            )
                        )
                        .font(
                            .headline
                                .weight(
                                    .semibold
                                )
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .padding(
                        .horizontal,
                        22
                    )
                    .frame(height: 58)
                    .background(
                        .regularMaterial,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.black
                                    .opacity(
                                        0.05
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
                .padding(.top, 8)
                .transition(
                    .move(edge: .top)
                        .combined(
                            with:
                                .opacity
                        )
                )
                .zIndex(50)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: {
                    social.coordinatedLobbySessionID != nil
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
    }
}

private struct ATHLTHMirroredWorkoutPresenter: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var showingLiveWorkout = false

    private var presentationTrigger: String {
        "\(workoutMirroring.presentationGeneration)-\(workoutMirroring.isPresentationRequested)-\(scenePhase == .active)"
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
                    if !workoutMirroring.hasActiveMirroredWorkout {
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
                for delay in [
                    Duration.milliseconds(350),
                    Duration.milliseconds(650),
                    Duration.milliseconds(1_100),
                    Duration.milliseconds(1_800)
                ] {
                    try? await Task.sleep(for: delay)

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

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var spotifyPlayback: SpotifyPlaybackStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace: GhostRaceStore

    @State private var homeStreakDays: [Date]?
    @State private var showingGlobalSearch = false
    @State private var selectedHomeStrengthSession: PlannedSession?
    @State private var pendingHomeQuickStartKind: WorkoutKind?
    @State private var showingHomeStrengthWorkout = false
    @State private var homeDirectStartInProgress = false
    @State private var homeWatchTransferMessage: String?
    @State private var homeWatchTransferError: String?
    @State private var showingGettingStartedPopup = false
    @State private var homeRecoveryTrendSnapshot =
        RecoveryTrendSnapshot.empty
    @StateObject private var homeWeather =
        HomeWeatherStore()
    @AppStorage("hasEditedATHLTHProfile")
    private var hasEditedATHLTHProfile = false

    var body: some View {
        NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: ATHLTHTheme.premiumGold.opacity(0.44),
                pullDownFadeBridge: true
            ) {
                ZStack(alignment: .topTrailing) {
                    ATHLTHHomeDashboardHero(
                        imageName: "HomeHero",
                        workout:
                            homeTodayPlanWorkout?
                                .workout,
                        isStarting:
                            homeDirectStartInProgress,
                        weather:
                            homeWeather.snapshot,
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

                    HStack(spacing: 7) {
                        HomeHeroUtilityButtons(
                            challengeInviteUnreadCount:
                                social.inboxEvents.filter {
                                    $0.kind == "challenge_invite" &&
                                    $0.readAt == nil
                                }.count,
                            pendingWorkoutImportCount:
                                health.pendingWorkoutImportCount,
                            onSearch: {
                                showingGlobalSearch = true
                            }
                        )

                        NavigationLink {
                            ATHLTHProfileView()
                        } label: {
                            homeProfileShortcut
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Profile")
                    }
                    .padding(.top, 64)
                    .padding(.trailing, 16)
                }
            } content: {
                LazyVStack(spacing: 12) {
                    HomeHealthMetricStrip(
                        snapshot:
                            homeRecoveryTrendSnapshot,
                        sleepText:
                            homeSleepMetricText,
                        respiratoryRateText:
                            homeRespiratoryRateMetricText,
                        hrvText:
                            homeHRVMetricText,
                        loadText:
                            homeLoadMetricText,
                        readinessText:
                            homeReadinessMetricText
                    )

                    HomeWeeklyProgressStrip(
                        plan: session.activePlan,
                        workouts: health.workouts
                    )

                    homeGoalAndCalendarRow

                    HomePersonalRecentActivitySection()

                    HomeWeeklySummaryCard(
                        runningDistanceKilometers:
                            homeWeeklyRunningDistanceKilometers,
                        durationMinutes:
                            homeWeeklyDurationMinutes,
                        strengthSessions:
                            homeWeeklyStrengthSessions,
                        sessionCount:
                            homeWeeklySessionCount
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
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
            .sheet(isPresented: $showingGlobalSearch) {
                ATHLTHGlobalSearchView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(30)
            }
            .sheet(item: $selectedHomeStrengthSession) { workout in
                WorkoutStartOptionsView(
                    session: workout,
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady,
                    defaultCapture: .automatic,
                    defaultTracking: settings.defaultStrengthTracking
                ) { configuredWorkout, captureDevice, trackingMode, selectedFriends, audioCoach, advancedConfiguration in
                    Task { @MainActor in
                        do {
                            let didStart =
                                try await WorkoutLaunchCoordinator.startStrength(
                                workout: configuredWorkout,
                                captureDevice: captureDevice,
                                trackingMode: trackingMode,
                                selectedFriends: selectedFriends,
                                audioCoach: audioCoach,
                                advancedConfiguration:
                                    advancedConfiguration,
                                session: session,
                                settings: settings,
                                social: social,
                                strengthWorkout: strengthWorkout,
                                watchConnection: watchConnection,
                                spotify: spotifyPlayback
                            )
                            if didStart {
                                showingHomeStrengthWorkout = true
                            }
                        } catch {
                            homeWatchTransferError =
                                error.localizedDescription
                        }
                    }
                }
            }
            .sheet(item: $pendingHomeQuickStartKind) { kind in
                if kind == .running {
                    RunQuickStartSheet(
                        trainingDeviceProvider:
                            watchConnection.isReady ? .appleWatch : .none,
                        watchConnected:
                            watchConnection.isReady
                    ) { configuration in
                        Task { @MainActor in
                            guard await social.beginWorkoutWithFriends(
                                title:
                                    configuration.title,
                                kind: .running,
                                friends:
                                    configuration.friends,
                                creatorName:
                                    session.profile.displayName,
                                creatorUsername:
                                    session.profile.username,
                                invitePayload:
                                    configuration
                                        .trainTogetherInvitePayload(
                                            savedRoutes:
                                                session.savedRoutes
                                        ),
                                creatorCaptureDevice:
                                    configuration.captureDevice
                            ) else {
                                return
                            }

                            do {
                                try await WorkoutLaunchCoordinator
                                    .startRunQuick(
                                        configuration:
                                            configuration,
                                        session:
                                            session,
                                        settings:
                                            settings,
                                        gear:
                                            gear,
                                        phoneWorkout:
                                            phoneWorkout,
                                        watchConnection:
                                            watchConnection,
                                        spotify:
                                            spotifyPlayback,
                                        ghostRace:
                                            ghostRace,
                                        workoutMirroring:
                                            workoutMirroring
                                    )
                                _ = await social
                                    .confirmCurrentJoinedWorkoutStarted()
                            } catch {
                                await social
                                    .markCurrentJoinedWorkoutLaunchFailed()
                                homeWatchTransferError =
                                    error.localizedDescription
                            }
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
                    ) {
                        configuredWorkout,
                        captureDevice,
                        trackingMode,
                        selectedFriends,
                        audioCoach,
                        advancedConfiguration in

                        Task { @MainActor in
                            do {
                                let didStart =
                                    try await WorkoutLaunchCoordinator
                                        .startStrength(
                                            workout:
                                                configuredWorkout,
                                            captureDevice:
                                                captureDevice,
                                            trackingMode:
                                                trackingMode,
                                            selectedFriends:
                                                selectedFriends,
                                            audioCoach:
                                                audioCoach,
                                            advancedConfiguration:
                                                advancedConfiguration,
                                            session:
                                                session,
                                            settings:
                                                settings,
                                            social:
                                                social,
                                            strengthWorkout:
                                                strengthWorkout,
                                            watchConnection:
                                                watchConnection,
                                            spotify:
                                                spotifyPlayback
                                        )

                                if didStart {
                                    pendingHomeQuickStartKind =
                                        nil
                                    showingHomeStrengthWorkout =
                                        true
                                }
                            } catch {
                                homeWatchTransferError =
                                    error.localizedDescription
                            }
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
            .refreshable {
                async let communityRefresh: Void = community.refresh()
                async let activityRefresh: Void =
                    social.refreshHomeFeed(force: true)

                if !health.shouldDeferAutomaticHealthWork {
                    _ = await health.refreshWorkoutImportInbox()
                    await health.refreshAll()
                    homeRecoveryTrendSnapshot =
                        await health.recoveryTrendSnapshot(
                            days: 14
                        )
                    homeWeather.refreshIfNeeded(
                        force: true
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

                _ = await (communityRefresh, activityRefresh)
            }
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
            .task {
                homeWeather.refreshIfNeeded()

                // Let the Home hierarchy paint before starting refresh work.
                // The compatibility preview is intentionally data-static so
                // smoke tests measure rendering rather than backend latency.
                await Task.yield()
                guard !session.previewModeEnabled else {
                    return
                }

                async let communityRefresh: Void = community.refresh()
                async let activityRefresh: Void = social.refreshHomeFeed()

                guard !health.shouldDeferAutomaticHealthWork else {
                    await loadHomeStreak()
                    _ = await (communityRefresh, activityRefresh)
                    return
                }

                _ = await health.refreshWorkoutImportInbox()

                await health.refreshIfStale(
                    maxAge: 90
                )

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
                    goalsRefresh,
                    communityRefresh,
                    activityRefresh
                )
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
            .onChange(of: session.activePlan?.id) {
                syncHomeTodayWorkoutToWatch()
            }
        }
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

    @ViewBuilder
    private var homeProfileShortcut: some View {
        if let avatarURL = session.profile.avatarURL {
            ATHLTHStorageImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.48), lineWidth: 1)
            }
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.48), lineWidth: 1)
                }
        }
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

    private var homeRespiratoryRateMetricText: String {
        guard let value =
                homeRecoveryTrendSnapshot.days
                    .reversed()
                    .compactMap(\.respiratoryRate)
                    .first,
              value.isFinite,
              value > 0
        else {
            return "—"
        }

        return String(
            format: "%.1f/min",
            locale: Locale.current,
            value
        )
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

    private var homeWorkoutsThisWeek:
        [WorkoutSummary] {
        health.workouts.filter {
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

    @ViewBuilder
    private var homeGoalAndCalendarRow:
        some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            Group {
                if let goal =
                        homeActiveGoal {
                    homeCompactGoalCard(
                        goal
                    )
                } else {
                    homeCompactCreateGoalCard
                }
            }
            .frame(
                maxWidth: .infinity
            )

            homeTodayCalendarCard
                .frame(
                    maxWidth:
                        .infinity
                )
        }
    }

    private func homeCompactGoalCard(
        _ goal: ATHLTHGoal
    ) -> some View {
        NavigationLink {
            GoalDetailView(
                goalID: goal.id
            )
        } label: {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                HStack {
                    Text("Aktuelt mål")
                        .font(
                            .subheadline
                                .weight(
                                    .bold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

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

                HStack(spacing: 10) {
                    ZStack(
                        alignment:
                            .bottomTrailing
                    ) {
                        GoalCoverView(
                            goal: goal
                        )
                        // Some Goal artwork files include a small light
                        // edge in the source image. Overscan the Home
                        // thumbnail so the artwork always reaches the
                        // rounded crop on every side.
                        .frame(
                            width: 90,
                            height: 90
                        )
                        .scaleEffect(
                            1.34,
                            anchor: .center
                        )
                        .clipped()
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18,
                                style:
                                    .continuous
                            )
                        )

                        Text(
                            "\(Int((goal.progress * 100).rounded()))%"
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            .white
                        )
                        .padding(
                            .horizontal,
                            6
                        )
                        .padding(
                            .vertical,
                            4
                        )
                        .background(
                            .black.opacity(
                                0.58
                            ),
                            in: Capsule()
                        )
                        .padding(5)
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(goal.title)
                            .font(
                                .caption
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)

                        Text(
                            homeNextMilestone(
                                for: goal
                            )?
                            .title ??
                            "Fortsett mot målet"
                        )
                        .font(
                            .system(
                                size: 9.5
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)

                        ProgressView(
                            value:
                                goal.progress
                        )
                        .tint(
                            ATHLTHTheme
                                .vitality
                        )
                    }
                }
                .frame(
                    minHeight: 90
                )
            }
            .padding(11)
            .background(
                Color.white.opacity(
                    0.90
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 19,
                        style:
                            .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 19,
                    style:
                        .continuous
                )
                .stroke(
                    Color.black.opacity(
                        0.04
                    ),
                    lineWidth: 0.7
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var homeCompactCreateGoalCard:
        some View {
        NavigationLink {
            GoalCreationView()
        } label: {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                HStack {
                    Text("Aktuelt mål")
                        .font(
                            .subheadline
                                .weight(
                                    .bold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                    Spacer()

                    Image(
                        systemName: "plus"
                    )
                    .font(
                        .caption.bold()
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }

                HStack(spacing: 9) {
                    Image(
                        systemName:
                            "target"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        .green
                    )
                    .frame(
                        width: 34,
                        height: 34
                    )
                    .background(
                        Color.green
                            .opacity(0.10),
                        in: Circle()
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text("Sett et mål")
                            .font(
                                .caption
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                        Text(
                            "Følg fremgangen direkte fra Home."
                        )
                        .font(
                            .system(
                                size: 9.5
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                    }
                }
                .frame(
                    minHeight: 74
                )
            }
            .padding(11)
            .background(
                Color.white.opacity(
                    0.90
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 19,
                        style:
                            .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 19,
                    style:
                        .continuous
                )
                .stroke(
                    Color.black.opacity(
                        0.04
                    ),
                    lineWidth: 0.7
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var homeTodayCalendarCard:
        some View {
        let plan =
            session.activePlan
        let workouts =
            plan.map {
                homeTodaySessions(
                    in: $0
                )
            } ?? []

        return VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Button {
                onOpenTrain(.plan)
            } label: {
                HStack {
                    Text("Kalender i dag")
                        .font(
                            .subheadline
                                .weight(
                                    .bold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

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

            if let plan,
               !workouts.isEmpty {
                VStack(spacing: 7) {
                    ForEach(
                        Array(
                            workouts
                                .prefix(2)
                        )
                    ) { workout in
                        Button {
                            onOpenTrain(
                                .workout(
                                    planID:
                                        plan.id,
                                    workoutID:
                                        workout
                                            .id
                                )
                            )
                        } label: {
                            HStack(
                                spacing: 7
                            ) {
                                Text(
                                    workout
                                        .scheduledStart?
                                        .formatted(
                                            date:
                                                .omitted,
                                            time:
                                                .shortened
                                        ) ??
                                    "—"
                                )
                                .font(
                                    .system(
                                        size:
                                            9.5,
                                        weight:
                                            .medium
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                                .frame(
                                    width: 34,
                                    alignment:
                                        .leading
                                )

                                Image(
                                    systemName:
                                        workout
                                            .kind
                                            .systemImage
                                )
                                .font(
                                    .system(
                                        size: 11,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    homeWorkoutTint(
                                        workout
                                            .kind
                                    )
                                )
                                .frame(
                                    width: 27,
                                    height: 27
                                )
                                .background(
                                    homeWorkoutTint(
                                        workout
                                            .kind
                                    )
                                    .opacity(
                                        0.10
                                    ),
                                    in:
                                        RoundedRectangle(
                                            cornerRadius:
                                                9,
                                            style:
                                                .continuous
                                        )
                                )

                                VStack(
                                    alignment:
                                        .leading,
                                    spacing: 1
                                ) {
                                    Text(
                                        workout
                                            .title
                                    )
                                    .font(
                                        .system(
                                            size:
                                                10.5,
                                            weight:
                                                .semibold
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )
                                    .lineLimit(
                                        1
                                    )

                                    Text(
                                        homeSessionSummary(
                                            workout
                                        )
                                    )
                                    .font(
                                        .system(
                                            size:
                                                8.5
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                    .lineLimit(
                                        1
                                    )
                                }

                                Spacer(
                                    minLength:
                                        0
                                )
                            }
                        }
                        .buttonStyle(
                            .plain
                        )
                    }
                }
                .frame(
                    minHeight: 74,
                    alignment: .top
                )
            } else {
                HStack(spacing: 7) {
                    homeCalendarQuickStartButton(
                        title: "Run",
                        icon: "figure.run",
                        tint: ATHLTHTheme.vitality
                    ) {
                        pendingHomeQuickStartKind =
                            .running
                    }

                    homeCalendarQuickStartButton(
                        title: "Strength",
                        icon: "dumbbell.fill",
                        tint: ATHLTHTheme.accentDeep
                    ) {
                        pendingHomeQuickStartKind =
                            .strength
                    }
                }
                .frame(
                    minHeight: 74,
                    alignment: .center
                )
            }
        }
        .padding(11)
        .background(
            Color.white.opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style:
                        .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style:
                    .continuous
            )
            .stroke(
                Color.black.opacity(
                    0.04
                ),
                lineWidth: 0.7
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
        if session.isPlanSessionManuallyCompleted(
            planID: planID,
            sessionID: workout.id
        ) {
            return true
        }

        return strengthWorkout.workoutHistory.contains {
            $0.isFinished &&
            $0.plannedSessionID == workout.id
        }
    }

    @ViewBuilder
    private var homeTodayCard: some View {
        let completion = homeTodayCompletion

        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today")
                        .font(.title3.weight(.bold))

                    Text(
                        session.activePlan?.title ??
                        "Choose what you want to train."
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                if session.activePlan != nil {
                    Button("Train") {
                        onSelectTab(2)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .buttonStyle(.plain)
                }
            }

            if workoutMirroring.hasActiveMirroredWorkout,
               let snapshot = workoutMirroring.snapshot,
               snapshot.kind != .strength,
               snapshot.kind != .functional {
                HStack(spacing: 13) {
                    Image(systemName: snapshot.kind.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.vitality)
                        .frame(width: 46, height: 46)
                        .background(
                            ATHLTHTheme.vitalitySoft,
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("LIVE ON APPLE WATCH")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(snapshot.kind.title)
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)

                        Text(workoutMirroring.connectionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Circle()
                        .fill(ATHLTHTheme.vitality)
                        .frame(width: 9, height: 9)
                }
                .padding(.top, 14)

                HStack {
                    Button {
                        workoutMirroring.isPresentationRequested = true
                    } label: {
                        Label(
                            "Continue Workout",
                            systemImage: "applewatch"
                        )
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)

                    Spacer()
                }
                .padding(.top, 12)
            } else if let active = strengthWorkout.activeWorkout {
                HStack(spacing: 13) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 46, height: 46)
                        .background(
                            Color.purple.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            strengthWorkout.hasRecoveredActiveWorkout
                                ? ATHLTHLocalization.choose(
                                    english: "UNFINISHED WORKOUT",
                                    norwegian: "UFERDIG ØKT"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "WORKOUT IN PROGRESS",
                                    norwegian: "ØKT PÅGÅR"
                                )
                        )
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(active.title)
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)

                        if let recoveredAt =
                                strengthWorkout
                                    .recoveredActiveWorkoutReferenceDate {
                            Text(
                                ATHLTHLocalization.format(
                                    english: "Last saved %@",
                                    norwegian: "Sist lagret %@",
                                    recoveredAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(active.startedAt, style: .timer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.top, 14)

                HStack {
                    Button {
                        strengthWorkout
                            .acknowledgeRecoveredWorkout()
                        showingHomeStrengthWorkout = true
                    } label: {
                        Label(
                            "Continue Workout",
                            systemImage: "play.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)

                    Spacer()
                }
                .padding(.top, 12)
            } else if let selection = homeTodayPlanWorkout {
                let workout = selection.workout

                HStack(spacing: 13) {
                    Image(systemName: workout.kind.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(homeWorkoutTint(workout.kind))
                        .frame(width: 46, height: 46)
                        .background(
                            homeWorkoutTint(workout.kind).opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT WORKOUT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(workout.title)
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)

                        Text(homeSessionSummary(workout))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Menu {
                        Button {
                            session.setPlanSessionManuallyCompleted(
                                planID: selection.planID,
                                sessionID: workout.id,
                                completed: true
                            )
                        } label: {
                            Label(
                                "Mark as Completed",
                                systemImage: "checkmark.circle"
                            )
                        }

                        NavigationLink {
                            PlannedWorkoutDetailView(
                                planID: selection.planID,
                                workout: workout,
                                isHealthCompleted: false
                            )
                        } label: {
                            Label(
                                "View Details",
                                systemImage: "info.circle"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Workout actions")
                }
                .padding(.top, 14)

                if completion.total > 0 &&
                   completion.completed > 0 &&
                   completion.completed < completion.total {
                    Label(
                        ATHLTHLocalization.format(
                            "%d of %d completed today",
                            completion.completed,
                            completion.total
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.vitality)
                    .padding(.top, 10)
                }

                if homeCanStartDirectly(workout) {
                    Button {
                        startHomeWorkout(workout)
                    } label: {
                        if homeDirectStartInProgress {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)

                                Text("Starting…")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                        } else {
                            Label(
                                "Start Workout",
                                systemImage: "play.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .disabled(homeDirectStartInProgress)
                    .padding(.top, 10)
                } else if homeRequiresAppleWatch(
                    workout
                ) {
                    Label(
                        "Apple Watch Required",
                        systemImage: "lock.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        Color.black.opacity(0.045),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                    .padding(.top, 10)
                } else {
                    NavigationLink {
                        PlannedWorkoutDetailView(
                            planID: selection.planID,
                            workout: workout,
                            isHealthCompleted: false
                        )
                    } label: {
                        Label(
                            "Open Workout",
                            systemImage: "arrow.right"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .padding(.top, 10)
                }
            } else if completion.total > 0 &&
                        completion.completed == completion.total {
                HStack(spacing: 13) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.vitality)
                        .frame(width: 46, height: 46)
                        .background(
                            ATHLTHTheme.vitalitySoft,
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("TODAY COMPLETE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                        Text("All planned workouts completed")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(
                            completion.total == 1
                                ? ATHLTHLocalization.string(
                                    "1 workout completed today."
                                )
                                : ATHLTHLocalization.format(
                                    "%d workouts completed today.",
                                    completion.total
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.top, 14)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.vitality)
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTheme.vitalitySoft,
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            session.activePlan == nil
                                ? "No workout planned"
                                : "Recovery day"
                        )
                        .font(.subheadline.weight(.semibold))

                        Text(
                            session.activePlan == nil
                                ? "Quick start a session or build a plan."
                                : "Nothing is scheduled today. Train if you feel ready."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.top, 14)

                HStack(spacing: 10) {
                    homeQuickStartButton(
                        title: "Run",
                        icon: "figure.run",
                        tint: .green
                    ) {
                        pendingHomeQuickStartKind = .running
                    }

                    homeQuickStartButton(
                        title: "Strength",
                        icon: "dumbbell.fill",
                        tint: .purple
                    ) {
                        pendingHomeQuickStartKind =
                            .strength
                    }
                }
                .padding(.top, 12)
            }
        }
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
        guard let today = homeTodayPlanWorkout,
              let watchKind =
                PlannedWorkoutWatchBuilder.watchKind(
                    for: today.workout.kind
                )
        else {
            watchConnection.sendTodayWorkout(nil)
            return
        }

        let workout = today.workout
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

        watchConnection.sendTodayWorkout(
            WatchTodayWorkoutTransfer(
                planID: today.planID,
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

    private func homeStrengthWatchSnapshot(
        _ workout: PlannedSession
    ) -> WatchStrengthSessionSnapshot? {
        guard workout.kind == .strength,
              !workout.exercises.isEmpty
        else {
            return nil
        }

        let queue =
            workout.exercises
                .enumerated()
                .map {
                    index,
                    planned in

                    let setCount =
                        max(
                            planned.sets,
                            1
                        )
                    let plans =
                        (1...setCount)
                            .map {
                                setNumber in

                                WatchStrengthSetPlan(
                                    setNumber:
                                        setNumber,
                                    reps:
                                        planned
                                            .resolvedTargetReps,
                                    durationSeconds:
                                        planned
                                            .resolvedTargetDurationSeconds,
                                    weightKilograms:
                                        planned
                                            .resolvedLoadKind ==
                                            .weightKilograms
                                            ? planned
                                                .targetWeightKilograms
                                            : nil,
                                    resistanceLevel:
                                        planned
                                            .resolvedLoadKind ==
                                            .resistanceLevel
                                            ? planned
                                                .resolvedTargetResistanceLevel
                                            : nil,
                                    restSeconds:
                                        planned
                                            .restSeconds,
                                    isWarmUp: nil
                                )
                            }

                    return WatchStrengthExerciseSummary(
                        index: index,
                        name:
                            planned
                                .embeddedExercise
                                .name,
                        primaryMuscles:
                            planned
                                .embeddedExercise
                                .primaryMuscles,
                        setCount:
                            setCount,
                        instructions:
                            planned
                                .embeddedExercise
                                .instructions,
                        secondaryMuscles:
                            planned
                                .embeddedExercise
                                .secondaryMuscles,
                        equipment:
                            planned
                                .embeddedExercise
                                .equipment,
                        setPlans:
                            plans
                    )
                }

        guard let first =
                queue.first,
              let firstPlan =
                first.setPlans?.first
        else {
            return nil
        }

        return WatchStrengthSessionSnapshot(
            workoutID:
                workout.id,
            title:
                workout.title,
            exerciseIndex: 0,
            exerciseCount:
                queue.count,
            exerciseName:
                first.name,
            primaryMuscles:
                first.primaryMuscles,
            setIndex: 0,
            setCount:
                first.setCount,
            setNumber: 1,
            completedSets: 0,
            totalSets:
                queue.reduce(0) {
                    $0 + $1.setCount
                },
            draftReps:
                firstPlan.reps ?? 8,
            draftWeightKilograms:
                firstPlan
                    .weightKilograms ??
                20,
            draftRestSeconds:
                firstPlan.restSeconds ??
                90,
            draftDurationSeconds:
                firstPlan
                    .durationSeconds,
            draftResistanceLevel:
                firstPlan
                    .resistanceLevel,
            targetKindRaw:
                firstPlan
                    .durationSeconds != nil
                    ? "time"
                    : "reps",
            loadKindRaw:
                firstPlan
                    .resistanceLevel != nil
                    ? "resistanceLevel"
                    : "weightKilograms",
            isResting: false,
            restEndsAt: nil,
            currentExerciseComplete:
                false,
            hasNextExercise:
                queue.count > 1,
            allExercisesComplete:
                false,
            updatedAt: Date(),
            inputMode:
                .appleWatch,
            draftRPE:
                plannedDefaultRPE(
                    workout
                ),
            draftRIR:
                plannedDefaultRIR(
                    workout
                ),
            isWarmUp:
                firstPlan.isWarmUp,
            effortMetricRaw:
                "rpe",
            exerciseQueue:
                queue,
            startedAt: nil,
            plannedSessionID:
                workout.id,
            allowsLiveExerciseBuilding:
                false
        )
    }

    private func plannedDefaultRPE(
        _ workout: PlannedSession
    ) -> Double? {
        workout.exercises
            .first?
            .targetRPE ??
        8
    }

    private func plannedDefaultRIR(
        _ workout: PlannedSession
    ) -> Double? {
        workout.exercises
            .first?
            .targetRIR ??
        2
    }

    private func homeTodaySessions(
        in plan: TrainingPlan
    ) -> [PlannedSession] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let dayIndex = ((weekday + 5) % 7) + 1

        let week: TrainingPlanWeek?

        if let startDate = plan.startDate {
            let start = calendar.startOfDay(for: startDate)
            let today = calendar.startOfDay(for: Date())
            let days = max(
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: today
                ).day ?? 0,
                0
            )
            let weekIndex = min(
                days / 7,
                max(plan.weeks.count - 1, 0)
            )
            week = plan.weeks.indices.contains(weekIndex)
                ? plan.weeks[weekIndex]
                : plan.weeks.first
        } else {
            week = plan.weeks.first
        }

        return week?
            .days
            .first(where: { $0.dayIndex == dayIndex })?
            .sessions ?? []
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

        if !workout.exercises.isEmpty {
            parts.append("\(workout.exercises.count) exercises")
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

        Task {
            do {
                try await watchConnection.startWorkoutOnWatch(watchKind)
                gear.prepareNextWorkoutGear(gearIDs)
                watchConnection.sendAudioCoachConfiguration(
                    audioCoach
                )
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
        _ workout: PlannedSession
    ) {
        guard let watchKind = PlannedWorkoutWatchBuilder.watchKind(for: workout.kind),
              watchConnection.isReady
        else {
            homeWatchTransferError =
                "Apple Watch is not ready for this workout."
            return
        }

        let selectedRoute =
            PlannedWorkoutWatchBuilder.route(
                for: workout,
                routes: session.savedRoutes
            )

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

        if let ghostTarget =
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

        homeDirectStartInProgress = true
        homeWatchTransferError = nil

        Task { @MainActor in
            defer {
                homeDirectStartInProgress = false
            }

            do {
                try await watchConnection
                    .startWorkoutOnWatch(watchKind)

                if let plannedGearIDs = workout.gearIDs {
                    gear.prepareNextWorkoutGear(
                        Set(plannedGearIDs)
                    )
                } else {
                    // Legacy plans keep the normal default-gear fallback.
                    gear.clearPreparedWorkoutGear()
                }

                let coachConfiguration =
                    PlannedWorkoutWatchBuilder
                        .audioCoachConfiguration(
                            for: workout,
                            selectedRoute: selectedRoute,
                            defaultConfiguration:
                                settings.audioCoachConfiguration(
                                    enabled:
                                        settings.audioCoachEnabledByDefault
                                )
                        )

                watchConnection.sendAudioCoachConfiguration(
                    coachConfiguration
                )

                if workout.kind == .running {
                    watchConnection.sendRunningWorkout(
                        PlannedWorkoutWatchBuilder.runningTransfer(
                            from: workout,
                            routeAlerts:
                                settings.routeAlertConfiguration,
                            autoPauseEnabled:
                                workout.autoPauseEnabled ??
                                settings.autoPauseOutdoorWorkouts
                        )
                    )
                } else {
                    // Clear any structured run left from an earlier session.
                    watchConnection.sendRunningWorkout(
                        WatchRunningWorkoutTransfer(
                            title: workout.title,
                            steps: [],
                            routeAlerts:
                                settings
                                    .routeAlertConfiguration,
                            targetAlerts:
                                workout
                                    .targetAlertConfiguration,
                            autoPauseEnabled:
                                workout.autoPauseEnabled ??
                                settings.autoPauseOutdoorWorkouts
                        )
                    )
                }

                session.beginTrainingStatus(for: workout)
                WorkoutLaunchCoordinator.startLinkedSpotifyIfNeeded(
                        workout: workout,
                        session: session,
                        settings: settings,
                        spotify: spotifyPlayback
                    )

                // No success modal: the Home card/live mirror becomes the
                // confirmation that the planned workout has started.
                homeWatchTransferMessage = nil
            } catch {
                homeWatchTransferError =
                    error.localizedDescription
            }
        }
    }

    private func startHomePlannedStrengthWorkout(
        _ workout: PlannedSession
    ) {
        guard strengthWorkout.activeWorkout == nil else {
            return
        }

        let trackingMode: StrengthTrackingMode =
            settings.defaultStrengthTracking == .advanced
                ? .advanced
                : .simple

        let useAppleWatch = watchConnection.isReady

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

                do {
                    try await watchConnection
                        .startWorkoutOnWatch(.strength)

                    session.beginTrainingStatus(for: workout)
                    strengthWorkout.start(
                        session: workout,
                        watchSessionID: UUID(),
                        trackingMode: trackingMode,
                        captureDevice: .appleWatch
                    )
                    WorkoutLaunchCoordinator.startLinkedSpotifyIfNeeded(
                        workout: workout,
                        session: session,
                        settings: settings,
                        spotify: spotifyPlayback
                    )
                    showingHomeStrengthWorkout = true
                } catch {
                    homeWatchTransferError =
                        error.localizedDescription
                }
            }
        } else {
            session.beginTrainingStatus(for: workout)
            strengthWorkout.start(
                session: workout,
                watchSessionID: nil,
                trackingMode: trackingMode,
                captureDevice: .iPhone
            )
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

private struct PlannedWorkoutSelection: Identifiable {
    let planID: UUID
    let workout: PlannedSession
    let isHealthCompleted: Bool

    var id: UUID { workout.id }
}

private struct ATHLTHTrainSectionSwitcher: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(
                Array(titles.enumerated()),
                id: \.offset
            ) { index, title in
                Button {
                    guard selection != index
                    else {
                        return
                    }

                    withAnimation(
                        .easeOut(duration: 0.16)
                    ) {
                        selection = index
                    }
                } label: {
                    Text(title)
                        .font(
                            .system(
                                size: 12.5,
                                weight:
                                    selection == index
                                        ? .bold
                                        : .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            selection == index
                                ? ATHLTHTheme.primaryText
                                : Color.white.opacity(0.92)
                        )
                        .padding(.horizontal, 15)
                        .frame(height: 34)
                        .background {
                            ZStack {
                                Capsule()
                                    .fill(.ultraThinMaterial)

                                Capsule()
                                    .fill(
                                        selection == index
                                            ? Color.white.opacity(0.94)
                                            : Color.black.opacity(0.24)
                                    )
                            }
                        }
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color.white.opacity(
                                        selection == index
                                            ? 0.54
                                            : 0.28
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(
                            color:
                                Color.black.opacity(
                                    selection == index
                                        ? 0.11
                                        : 0.07
                                ),
                            radius: 8,
                            y: 3
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selection == index
                        ? .isSelected
                        : []
                )
            }
        }
    }
}

private struct ATHLTHTrainPlanWorkspaceView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TrainingPlanManagerView()
                AdvancedPlannerView(
                    showsEmptyState: false
                )
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
        .navigationTitle("Training Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HomeHeroUtilityButtons: View {
    @EnvironmentObject private var notifications:
        ATHLTHNotificationStore
    @EnvironmentObject private var messaging:
        MessagingStore

    let challengeInviteUnreadCount: Int
    let pendingWorkoutImportCount: Int
    let onSearch: () -> Void

    private var inboxUnreadCount: Int {
        messaging.unreadCount +
            messaging.messageRequestCount +
            challengeInviteUnreadCount
    }

    private var notificationCount: Int {
        notifications.notificationCenterUnreadCount +
            pendingWorkoutImportCount
    }

    var body: some View {
        HStack(spacing: 7) {
            heroButton(
                icon: "magnifyingglass",
                action: onSearch
            )
            .accessibilityLabel("Search ATHLTH")

            NavigationLink {
                MessageInboxDestinationView()
            } label: {
                badgeButton(
                    icon:
                        inboxUnreadCount > 0
                            ? "tray.full.fill"
                            : "tray",
                    count: inboxUnreadCount
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                inboxUnreadCount > 0
                    ? "Inbox, \(inboxUnreadCount) unread"
                    : "Inbox"
            )

            NavigationLink {
                ATHLTHNotificationCenterView()
            } label: {
                badgeButton(
                    icon:
                        notificationCount > 0
                            ? "bell.fill"
                            : "bell",
                    count: notificationCount
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                notificationCount > 0
                    ? "Notifications, \(notificationCount) pending"
                    : "Notifications"
            )
        }
    }

    private func heroButton(
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Color.black.opacity(0.20),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.30),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func badgeButton(
        icon: String,
        count: Int
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Color.black.opacity(0.20),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.30),
                            lineWidth: 0.8
                        )
                }

            if count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(
                        minWidth: 14,
                        minHeight: 14
                    )
                    .padding(
                        .horizontal,
                        count > 9 ? 2 : 0
                    )
                    .background(
                        .red,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                .white,
                                lineWidth: 1
                            )
                    }
                    .offset(x: 4, y: -4)
            }
        }
    }
}

struct ATHLTHTrainView: View {
    @Binding private var navigationRequest:
        ATHLTHTrainNavigationRequest?

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

    @State private var selectedSection = 0
    @State private var watchTransferMessage: String?
    @State private var watchTransferError: String?
    @State private var selectedStrengthSession: PlannedSession?
    @State private var selectedPlanWorkout: PlannedWorkoutSelection?
    @State private var pendingRunningTemplate: RunningWorkoutTemplate?
    @State private var showingRunQuickStart = false
    @State private var showingWalkQuickStart = false
    @State private var showingStrengthQuickStart = false
    @State private var showingCustomQuickStart = false
    @State private var showingStrengthWorkout = false
    @State private var selectedStructuredWorkout:
        PlannedSession?
    @State private var showingGhostHub = false
    @State private var showingLibrary = false

    init(
        navigationRequest:
            Binding<ATHLTHTrainNavigationRequest?> =
            .constant(nil)
    ) {
        _navigationRequest = navigationRequest
    }

    var body: some View {
        NavigationStack {
            ATHLTHExclusiveHomeHeroLayout(
                accent: Color.green.opacity(0.42),
                showsTopSheen: false,
                pullDownFadeBridge: true
            ) {
                ZStack(alignment: .topTrailing) {
                    ATHLTHExclusiveHomeHero(
                        imageName: "TrainHero",
                        title: "Train",
                        subtitle: "Build a stronger, healthier you."
                    )

                    ATHLTHTrainSectionSwitcher(
                        titles: [
                            ATHLTHLocalization.choose(
                                english: "Today",
                                norwegian: "I dag"
                            ),
                            ATHLTHLocalization.choose(
                                english: "Plan",
                                norwegian: "Plan"
                            )
                        ],
                        selection: $selectedSection
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .padding(.top, 64)
                    .padding(.leading, 16)
                    .padding(.trailing, 68)

                    Button {
                        showingLibrary = true
                    } label: {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Color.black.opacity(0.20),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.30),
                                        lineWidth: 0.8
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Training Library")
                    .padding(.top, 64)
                    .padding(.trailing, 16)
                }
            } content: {
                VStack(spacing: 15) {
                    switch selectedSection {
                    case 1:
                        planContent
                    default:
                        todayContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 30)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .navigationDestination(
                isPresented: $showingLibrary
            ) {
                ScrollView {
                    libraryContent
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .background(
                    ATHLTHPremiumCanvas(
                        accent: Color.green.opacity(0.12)
                    )
                )
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(
                isPresented: $showingGhostHub
            ) {
                GhostRaceHubView()
            }
            .sheet(item: $selectedPlanWorkout) { selection in
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
                ) { configuredWorkout, captureDevice, trackingMode, selectedFriends, audioCoach, advancedConfiguration in
                    Task { @MainActor in
                        do {
                            let didStart =
                                try await WorkoutLaunchCoordinator.startStrength(
                                workout: configuredWorkout,
                                captureDevice: captureDevice,
                                trackingMode: trackingMode,
                                selectedFriends: selectedFriends,
                                audioCoach: audioCoach,
                                advancedConfiguration:
                                    advancedConfiguration,
                                session: session,
                                settings: settings,
                                social: social,
                                strengthWorkout: strengthWorkout,
                                watchConnection: watchConnection,
                                spotify: spotifyPlayback
                            )
                            if didStart {
                                showingStrengthWorkout = true
                            }
                        } catch {
                            watchTransferError =
                                error.localizedDescription
                        }
                    }
                }
            }
            .sheet(isPresented: $showingRunQuickStart) {
                RunQuickStartSheet(
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady
                ) { configuration in
                    Task { @MainActor in
                        guard await social.beginWorkoutWithFriends(
                            title: configuration.title,
                            kind: .running,
                            friends: configuration.friends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username,
                            invitePayload:
                                configuration
                                    .trainTogetherInvitePayload(
                                        savedRoutes:
                                            session.savedRoutes
                                    ),
                            creatorCaptureDevice:
                                configuration.captureDevice
                        ) else {
                            return
                        }
                        do {
                            try await WorkoutLaunchCoordinator
                                .startRunQuick(
                                    configuration:
                                        configuration,
                                    session: session,
                                    settings: settings,
                                    gear: gear,
                                    phoneWorkout:
                                        phoneWorkout,
                                    watchConnection:
                                        watchConnection,
                                    spotify:
                                        spotifyPlayback,
                                    ghostRace:
                                        ghostRace,
                                    workoutMirroring:
                                        workoutMirroring
                                )
                            _ = await social
                                .confirmCurrentJoinedWorkoutStarted()
                        } catch {
                            await social
                                .markCurrentJoinedWorkoutLaunchFailed()
                            watchTransferError =
                                error.localizedDescription
                        }
                    }
                }
            }
            .sheet(isPresented: $showingWalkQuickStart) {
                WalkQuickStartSheet(
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady
                ) { configuration in
                    Task { @MainActor in
                        guard await social.beginWorkoutWithFriends(
                            title: "Walk",
                            kind: .walking,
                            friends: configuration.friends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username,
                            invitePayload:
                                configuration
                                    .trainTogetherInvitePayload,
                            creatorCaptureDevice:
                                configuration.captureDevice
                        ) else {
                            return
                        }
                        do {
                            try await WorkoutLaunchCoordinator
                                .startWalkQuick(
                                    configuration:
                                        configuration,
                                    settings: settings,
                                    gear: gear,
                                    phoneWorkout:
                                        phoneWorkout,
                                    watchConnection:
                                        watchConnection,
                                    spotify:
                                        spotifyPlayback,
                                    workoutMirroring:
                                        workoutMirroring
                                )
                            _ = await social
                                .confirmCurrentJoinedWorkoutStarted()
                        } catch {
                            await social
                                .markCurrentJoinedWorkoutLaunchFailed()
                            watchTransferError =
                                error.localizedDescription
                        }
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
                ) {
                    configuredWorkout,
                    captureDevice,
                    trackingMode,
                    selectedFriends,
                    audioCoach,
                    advancedConfiguration in

                    Task { @MainActor in
                        do {
                            let didStart =
                                try await WorkoutLaunchCoordinator
                                    .startStrength(
                                        workout:
                                            configuredWorkout,
                                        captureDevice:
                                            captureDevice,
                                        trackingMode:
                                            trackingMode,
                                        selectedFriends:
                                            selectedFriends,
                                        audioCoach:
                                            audioCoach,
                                        advancedConfiguration:
                                            advancedConfiguration,
                                        session:
                                            session,
                                        settings:
                                            settings,
                                        social:
                                            social,
                                        strengthWorkout:
                                            strengthWorkout,
                                        watchConnection:
                                            watchConnection,
                                        spotify:
                                            spotifyPlayback
                                    )

                            if didStart {
                                showingStrengthQuickStart =
                                    false
                                showingStrengthWorkout =
                                    true
                            }
                        } catch {
                            watchTransferError =
                                error.localizedDescription
                        }
                    }
                }
            }
            .sheet(item: $pendingRunningTemplate) { workout in
                RunQuickStartSheet(
                    trainingDeviceProvider:
                        watchConnection.isReady
                            ? .appleWatch
                            : .none,
                    watchConnected:
                        watchConnection.isReady,
                    initialWorkout: workout
                ) { configuration in
                    Task { @MainActor in
                        guard await social
                            .beginWorkoutWithFriends(
                                title:
                                    configuration
                                        .title,
                                kind: .running,
                                friends:
                                    configuration
                                        .friends,
                                creatorName:
                                    session
                                        .profile
                                        .displayName,
                                creatorUsername:
                                    session
                                        .profile
                                        .username,
                                invitePayload:
                                    configuration
                                        .trainTogetherInvitePayload(
                                            savedRoutes:
                                                session.savedRoutes
                                        ),
                                creatorCaptureDevice:
                                    configuration.captureDevice
                            )
                        else {
                            return
                        }
                        do {
                            try await WorkoutLaunchCoordinator
                                .startRunQuick(
                                    configuration:
                                        configuration,
                                    session: session,
                                    settings: settings,
                                    gear: gear,
                                    phoneWorkout:
                                        phoneWorkout,
                                    watchConnection:
                                        watchConnection,
                                    spotify:
                                        spotifyPlayback,
                                    ghostRace:
                                        ghostRace,
                                    workoutMirroring:
                                        workoutMirroring
                                )
                            _ = await social
                                .confirmCurrentJoinedWorkoutStarted()
                        } catch {
                            await social
                                .markCurrentJoinedWorkoutLaunchFailed()
                            watchTransferError =
                                error.localizedDescription
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCustomQuickStart) {
                CustomQuickStartSheet(
                    trainingDeviceProvider:
                        watchConnection.isReady ? .appleWatch : .none,
                    watchConnected: watchConnection.isReady
                ) { configuration in
                    startCustomWorkoutOnWatch(configuration)
                }
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
                    workout: workout
                )
                .environmentObject(session)
            }
            .task {
                session.refreshActivePlanForToday()
                await exerciseLibrary.refresh()
                handleNavigationRequest()
            }
            .onChange(
                of: navigationRequest?.id
            ) { _, _ in
                handleNavigationRequest()
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
    private var todayContent: some View {
        HStack(
            alignment: .top,
            spacing: 14
        ) {
            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "TODAY",
                        norwegian: "I DAG"
                    )
                )
                .font(.caption2.weight(.bold))
                .tracking(2.4)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english: "Ready for today?",
                        norwegian: "Klar for i dag?"
                    )
                )
                .font(
                    .system(
                        size: 29,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    session.activePlan == nil
                        ? ATHLTHLocalization.choose(
                            english:
                                "Train freely, or build a plan around what you want to achieve.",
                            norwegian:
                                "Tren fritt, eller bygg en plan rundt det du vil oppnå."
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "Today's sessions, quick starts and training tools in one place.",
                            norwegian:
                                "Dagens økter, hurtigstart og treningsverktøy samlet på ett sted."
                        )
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Text(
                    Date.now.formatted(
                        .dateTime.day()
                    )
                )
                .font(
                    .system(
                        size: 22,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    Date.now.formatted(
                        .dateTime.weekday(
                            .abbreviated
                        )
                    )
                    .uppercased()
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .tracking(0.8)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
            .frame(
                width: 54,
                height: 58
            )
            .background(
                Color.white.opacity(0.72),
                in: RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.82),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color:
                    Color.black.opacity(0.035),
                radius: 9,
                y: 4
            )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )

        unfinishedWorkoutRecoveryCards

        if let plan = session.activePlan {
            todaysPlanCard(plan)
        } else {
            noActivePlanCard
        }

        VStack(
            alignment: .leading,
            spacing: 13
        ) {
            HStack(
                alignment: .firstTextBaseline
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "QUICK START",
                            norwegian: "HURTIGSTART"
                        )
                    )
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Move now",
                            norwegian: "Kom i gang"
                        )
                    )
                    .font(.title3.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                }

                Spacer()

                Text(quickStartDeviceTitle)
                    .font(
                        .system(
                            size: 10.5,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .multilineTextAlignment(
                        .trailing
                    )
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                quickStartTile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Run",
                            norwegian: "Løp"
                        ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english: "Free run",
                            norwegian: "Fri løping"
                        ),
                    icon: "figure.run",
                    enabled:
                        quickStartAvailable(
                            .running
                        )
                ) {
                    handleQuickStart(.running)
                }

                quickStartTile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Walk",
                            norwegian: "Gå"
                        ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english: "Free walk",
                            norwegian: "Fri gange"
                        ),
                    icon: "figure.walk",
                    enabled:
                        quickStartAvailable(
                            .walking
                        )
                ) {
                    handleQuickStart(.walking)
                }

                quickStartTile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Strength",
                            norwegian: "Styrke"
                        ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english: "Gym / Home",
                            norwegian: "Gym / hjemme"
                        ),
                    icon: "dumbbell.fill",
                    enabled:
                        quickStartAvailable(
                            .strength
                        )
                ) {
                    handleQuickStart(.strength)
                }

                quickStartTile(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Custom",
                            norwegian: "Egen"
                        ),
                    subtitle:
                        quickStartCustomSubtitle,
                    icon: "plus",
                    enabled:
                        customQuickStartAvailable
                ) {
                    showingCustomQuickStart = true
                }
            }
        }
        .padding(15)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.84),
                    ATHLTHTheme.accentSoft.opacity(0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.88),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.025),
            radius: 12,
            y: 5
        )

        Button {
            showingGhostHub = true
        } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GHOST TRAINING")
                        .font(.caption.weight(.bold))
                        .tracking(3.0)
                        .foregroundStyle(
                            Color.white.opacity(0.72)
                        )

                    Text("Compete with yourself.")
                        .font(
                            .system(
                                size: 27,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(
                        "Replay a previous run, chase a target time, race a route or challenge a friend."
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        Color.white.opacity(0.74)
                    )
                    .multilineTextAlignment(.leading)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Spacer(minLength: 6)

                ZStack {
                    Circle()
                        .fill(
                            Color.white.opacity(0.13)
                        )
                        .frame(width: 82, height: 82)

                    Circle()
                        .fill(
                            Color.white.opacity(0.96)
                        )
                        .frame(width: 50, height: 50)

                    Image(systemName: "figure.run")
                        .font(
                            .system(
                                size: 25,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            Color(
                                red: 0.25,
                                green: 0.28,
                                blue: 0.34
                            )
                        )
                }
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(
                maxWidth: .infinity,
                minHeight: 168,
                alignment: .leading
            )
            .background(
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.06,
                            green: 0.07,
                            blue: 0.10
                        ),
                        Color(
                            red: 0.15,
                            green: 0.18,
                            blue: 0.24
                        )
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 30,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 30,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.06),
                    lineWidth: 0.8
                )
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 30,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Ghost Training. Compete with yourself."
        )
        .accessibilityHint(
            "Open Ghost Training to replay a previous run, chase a target time, race a route or challenge a friend."
        )

        if !session.savedWorkoutTemplates.isEmpty {
            ATHLTHCard {
                ATHLTHSectionHeader(
                    title: "Saved Workouts",
                    actionTitle: "From you & friends"
                )

                VStack(spacing: 13) {
                    ForEach(session.savedWorkoutTemplates.prefix(4)) { workout in
                        HStack(spacing: 12) {
                            Image(systemName: workout.kind.systemImage)
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 36, height: 36)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 11)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(todaySessionSummary(workout))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if workout.isStructuredWorkout {
                                Button("Start") {
                                    selectedStructuredWorkout =
                                        workout
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(ATHLTHTheme.accentDeep)
                            } else if workout.kind == .strength {
                                Button("Start") {
                                    selectedStrengthSession = workout
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Text("Saved")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }


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

    @ViewBuilder
    private var planContent: some View {
        if session.activePlan != nil {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("YOUR PLAN")
                            .font(.caption2.weight(.bold))
                            .tracking(1.8)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                        Text("Plan first. Tools second.")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                    }

                    Spacer()

                    Button {
                        showingLibrary = true
                    } label: {
                        Label(
                            "Library",
                            systemImage: "square.grid.2x2.fill"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                }

                AdvancedPlannerView(
                    showsEmptyState: false
                )

                HStack(spacing: 10) {
                    Rectangle()
                        .fill(
                            ATHLTHTheme.accent.opacity(0.12)
                        )
                        .frame(height: 1)

                    Text("PLAN TOOLS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Rectangle()
                        .fill(
                            ATHLTHTheme.accent.opacity(0.12)
                        )
                        .frame(height: 1)
                }
                .padding(.vertical, 2)

                TrainingPlanManagerView()
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                // Standalone workouts must remain available even when the
                // athlete does not currently have an active training plan.
                AdvancedPlannerView(
                    showsEmptyState: false
                )

                TrainingPlanManagerView()

                Button {
                    showingLibrary = true
                } label: {
                    HStack(spacing: 13) {
                        Image(
                            systemName:
                                "square.grid.2x2.fill"
                        )
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text("Browse the Library")
                                .font(.headline)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )

                            Text(
                                "Find a plan, workout, exercise or route."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(
                            systemName: "chevron.right"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                    }
                    .padding(15)
                    .background(
                        Color.white.opacity(0.72),
                        in: RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var libraryContent: some View {
        TrainingLibraryHomeView { workout in
            pendingRunningTemplate = workout
        }
    }

    private func quickStartTile(
        title: String,
        subtitle: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 34,
                        height: 34
                    )
                    .background(
                        ATHLTHTheme.accentSoft
                            .opacity(0.88),
                        in: Circle()
                    )

                Text(title)
                    .font(
                        .system(
                            size: 11.5,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(subtitle)
                    .font(
                        .system(
                            size: 9.2,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 92
            )
            .padding(.horizontal, 3)
            .background(
                Color.white.opacity(
                    enabled
                        ? 0.68
                        : 0.40
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
                        ? ATHLTHTheme.accent.opacity(
                            0.08
                        )
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
        watchConnection.isReady &&
        phoneWorkout.active == nil &&
        strengthWorkout.activeWorkout == nil
    }

    private var quickStartCustomSubtitle: String {
        customQuickStartAvailable
            ? ATHLTHLocalization.choose(
                english: "Build yours",
                norwegian: "Lag egen"
            )
            : ATHLTHLocalization.choose(
                english: "Watch",
                norwegian: "Watch"
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
        case .mobility, .recovery, .custom:
            break
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
        guard watchConnection.isReady
        else {
            return
        }

        Task {
            do {
                try await watchConnection.startWorkoutOnWatch(
                    configuration.activity.watchKind
                )
                watchConnection.sendAudioCoachConfiguration(
                    configuration.audioCoach
                )
                watchTransferMessage =
                    "\(configuration.title) started on Apple Watch · \(configuration.detail)."
            } catch {
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

        do {
            if let route = configuration.route {
                try watchConnection.sendRoute(route)
                watchConnection.sendWorkoutRouteSelection(route.id)
            } else if let workout = configuration.workout,
                      let routeID = workout.routeID,
                      let route = session.savedRoutes.first(
                        where: { $0.id == routeID }
                      ) {
                try watchConnection.sendRoute(route)
                watchConnection.sendWorkoutRouteSelection(route.id)
            } else {
                watchConnection.sendWorkoutRouteSelection(nil)
            }
        } catch {
            Task { @MainActor in
                await social.markCurrentJoinedWorkoutLaunchFailed()
            }
            watchTransferError = error.localizedDescription
            return
        }

        Task {
            do {
                try await watchConnection
                    .startWorkoutOnWatch(.running)

                gear.prepareNextWorkoutGear(
                    configuration.gearIDs
                )

                watchConnection.sendAudioCoachConfiguration(
                    configuration.audioCoach
                )

                if let workout = configuration.workout {
                    var watchTransfer =
                        watchRunningWorkoutTransfer(
                            from: workout
                        )
                    watchTransfer.routeAlerts =
                        settings
                            .routeAlertConfiguration
                    watchTransfer.autoPauseEnabled =
                        configuration.autoPauseEnabled
                    watchConnection.sendRunningWorkout(
                        watchTransfer
                    )
                } else {
                    watchConnection.sendRunningWorkout(
                        WatchRunningWorkoutTransfer(
                            title: "",
                            steps: [],
                            routeAlerts:
                                settings
                                    .routeAlertConfiguration,
                            autoPauseEnabled:
                                configuration.autoPauseEnabled
                        )
                    )
                }

                _ = await social
                    .confirmCurrentJoinedWorkoutStarted()
                watchTransferMessage =
                    "\(configuration.title) started on Apple Watch."
            } catch {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                watchTransferError = error.localizedDescription
            }
        }
    }

    private func startWalkQuickWorkout(
        _ configuration: WalkQuickStartConfiguration
    ) {
        if configuration.captureDevice == .iPhone {
            gear.prepareNextWorkoutGear(configuration.gearIDs)
            phoneWorkout.start(
                walking: true,
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
                "Apple Watch is not ready to start this walk."
            return
        }

        watchConnection.sendWorkoutRouteSelection(nil)
        watchConnection.sendRunningWorkout(
            WatchRunningWorkoutTransfer(
                title: "",
                steps: [],
                routeAlerts:
                    settings.routeAlertConfiguration,
                autoPauseEnabled:
                    configuration.autoPauseEnabled
            )
        )

        Task {
            do {
                try await watchConnection
                    .startWorkoutOnWatch(.walking)
                gear.prepareNextWorkoutGear(
                    configuration.gearIDs
                )
                watchConnection.sendAudioCoachConfiguration(
                    configuration.audioCoach
                )
                _ = await social
                    .confirmCurrentJoinedWorkoutStarted()
                watchTransferMessage =
                    "Walk started on Apple Watch."
            } catch {
                await social.markCurrentJoinedWorkoutLaunchFailed()
                watchTransferError = error.localizedDescription
            }
        }
    }

    private func startQuickWorkoutOnWatch(_ kind: WorkoutKind) {
        guard watchConnection.isReady,
              let watchKind = watchWorkoutKind(for: kind)
        else {
            return
        }

        Task {
            do {
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

        do {
            if let routeID = workout.routeID,
               let route = session.savedRoutes.first(
                    where: { $0.id == routeID }
               ) {
                try watchConnection.sendRoute(route)
                watchConnection.sendWorkoutRouteSelection(route.id)
            } else {
                watchConnection.sendWorkoutRouteSelection(nil)
            }
        } catch {
            Task { @MainActor in
                await social.markCurrentJoinedWorkoutLaunchFailed()
            }
            watchTransferError = error.localizedDescription
            return
        }

        Task {
            do {
                try await watchConnection.startWorkoutOnWatch(.running)
                gear.prepareNextWorkoutGear(gearIDs)
                watchConnection.sendAudioCoachConfiguration(
                    audioCoach
                )
                var watchTransfer =
                    watchRunningWorkoutTransfer(
                        from: workout
                    )
                watchTransfer.routeAlerts =
                    settings.routeAlertConfiguration
                watchConnection.sendRunningWorkout(
                    watchTransfer
                )
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

    @ViewBuilder
    private func todaysPlanCard(_ plan: TrainingPlan) -> some View {
        let sessions = todaySessions(in: plan)
        let healthCompletedIDs = healthCompletedTodaySessionIDs(sessions)
        let manuallyCompletedIDs = manuallyCompletedTodaySessionIDs(
            planID: plan.id,
            sessions: sessions
        )

        ATHLTHCard {
            HStack(spacing: 10) {
                Text("Today's Plan")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    selectedSection = 1
                } label: {
                    HStack(spacing: 5) {
                        Text("View Plan")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            if sessions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars")
                        .font(.title3)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 13)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recovery day")
                            .font(.subheadline.weight(.semibold))

                        Text(
                            ATHLTHLocalization.format(
                                "Nothing is scheduled in %@ today.",
                                plan.title
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, workout in
                        todayPlanRow(
                            workout,
                            planID: plan.id,
                            isHealthCompleted:
                                healthCompletedIDs.contains(workout.id),
                            isManuallyCompleted:
                                manuallyCompletedIDs.contains(workout.id),
                            isFirst: index == 0,
                            isLast: index == sessions.count - 1
                        )
                    }
                }
                .padding(.top, 8)
            }
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
        let isCompleted = isHealthCompleted || isManuallyCompleted

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

    private func healthCompletedTodaySessionIDs(
        _ sessions: [PlannedSession]
    ) -> Set<UUID> {
        let calendar = Calendar.current
        var unusedWorkouts = health.workouts
            .filter { calendar.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }

        var result = Set<UUID>()

        for session in sessions {
            guard let matchIndex = unusedWorkouts.firstIndex(where: {
                healthWorkout($0, matches: session)
            }) else {
                continue
            }

            result.insert(session.id)
            unusedWorkouts.remove(at: matchIndex)
        }

        return result
    }

    private func healthWorkout(
        _ workout: WorkoutSummary,
        matches session: PlannedSession
    ) -> Bool {
        switch session.kind {
        case .running:
            return workout.activity == .running
        case .walking:
            return workout.activity == .walking || workout.activity == .hiking
        case .strength:
            return workout.activity == .strength
        case .mobility:
            return workout.activity == .yoga || workout.activity == .coreTraining
        case .recovery:
            return false
        case .custom:
            return workout.activity == .hiit ||
                workout.activity == .rowing ||
                workout.activity == .cycling ||
                workout.activity == .stairClimbing ||
                workout.activity == .other
        }
    }

    private func todaySessions(
        in plan: TrainingPlan
    ) -> [PlannedSession] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let dayIndex = ((weekday + 5) % 7) + 1

        let week: TrainingPlanWeek?
        if let startDate = plan.startDate {
            let start = calendar.startOfDay(for: startDate)
            let today = calendar.startOfDay(for: Date())
            let days = max(
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: today
                ).day ?? 0,
                0
            )
            let weekIndex = min(
                days / 7,
                max(plan.weeks.count - 1, 0)
            )
            week = plan.weeks.indices.contains(weekIndex)
                ? plan.weeks[weekIndex]
                : plan.weeks.first
        } else {
            week = plan.weeks.first
        }

        return week?
            .days
            .first(where: { $0.dayIndex == dayIndex })?
            .sessions ?? []
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

    @ViewBuilder
    private func builderTile(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(ATHLTHTheme.accent)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 100,
            alignment: .leading
        )
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }




    private func handleNavigationRequest() {
        guard let request = navigationRequest else {
            return
        }

        switch request {
        case .plan:
            selectedSection = 1

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
                                [workout]
                            )
                            .contains(workout.id)
                    )
            } else {
                selectedSection = 1
            }

        case let .quick(kind):
            selectedSection = 0
            handleQuickStart(kind)

        case .customQuick:
            selectedSection = 0
            if customQuickStartAvailable {
                showingCustomQuickStart = true
            } else {
                watchTransferError =
                    "Connect Apple Watch to use Custom Quick Train."
            }

        case .ghost:
            selectedSection = 0
            showingGhostHub = true
        }

        navigationRequest = nil
    }

}

struct ATHLTHRecoveryView: View {
    var onSelectTab: (Int) -> Void = { _ in }

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    @StateObject private var sorenessStore = RecoverySorenessStore()
    @State private var recoverySnapshot = RecoveryTrendSnapshot.empty
    @State private var recoveryAIInsight: RecoveryAIInsight?
    @State private var isLoadingRecoveryAI = false
    @State private var recoveryAIError: String?
    @State private var showingSorenessLog = false
    @State private var showingRecoveryInfo = false
    @State private var showingRecoveryCoach = false
    @State private var selectedRecoveryTool: RecoveryTool?
    @State private var recoveryDerivedSnapshot =
        RecoveryDerivedSnapshot.empty
    @State private var recoveryDerivedGeneration = 0

    private struct RecoveryChangeItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let tint: Color
        let magnitude: Double
    }

    private func insightText(
        _ english: String,
        _ norwegian: String
    ) -> String {
        ATHLTHLocalization.choose(
            english: english,
            norwegian: norwegian
        )
    }

    private func insightMuscleName(
        _ name: String
    ) -> String {
        guard ATHLTHLocalization.isNorwegian else {
            return name
        }

        switch name {
        case "Chest": return "Bryst"
        case "Back": return "Rygg"
        case "Shoulders": return "Skuldre"
        case "Arms": return "Armer"
        case "Core": return "Kjerne"
        case "Glutes": return "Sete"
        case "Quads": return "Forside lår"
        case "Hamstrings": return "Bakside lår"
        case "Calves": return "Legger"
        default: return name
        }
    }

    private func insightWorkoutKindTitle(
        _ kind: WorkoutKind
    ) -> String {
        switch kind {
        case .running:
            return insightText("Running", "Løping")
        case .walking:
            return insightText("Walking", "Gange")
        case .strength:
            return insightText("Strength", "Styrke")
        case .mobility:
            return insightText("Mobility", "Mobilitet")
        case .recovery:
            return insightText("Recovery", "Restitusjon")
        case .custom:
            return insightText("Workout", "Treningsøkt")
        }
    }

    var body: some View {
        NavigationStack {
            ATHLTHExclusiveHomeHeroLayout(
                accent: Color.blue.opacity(0.36),
                showsTopSheen: false,
                pullDownFadeBridge: true
            ) {
                ATHLTHExclusiveHomeHero(
                    imageName: "RecoveryHero",
                    title: "Insights",
                    subtitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Understand your body. Make better decisions. Stay in the game.",
                            norwegian:
                                "Forstå kroppen din. Ta bedre valg. Hold deg i gang."
                        )
                )
            } content: {
                LazyVStack(spacing: 16) {
                    if shouldShowWearableRecoveryContent {
                        if session.hasPaidAccess &&
                            session.aiHealthDataSharingEnabled {
                            RecoveryAIInsightCard(
                                insight:
                                    recoveryAIInsight ??
                                    fallbackRecoveryAIInsight,
                                context: recoveryAIContext,
                                isLoading: isLoadingRecoveryAI,
                                onScoreDetails: {
                                    showingRecoveryInfo = true
                                },
                                onAdjustTraining: {
                                    onSelectTab(2)
                                },
                                onAskATHLTH: {
                                    showingRecoveryCoach = true
                                }
                            )
                        } else {
                            recoveryScoreCard
                            todaysSignalsCard

                            RecoveryReadinessBreakdownCard(
                                recovery: health.recovery,
                                sleep: health.sleep,
                                heart: health.heart
                            )

                            if session.hasPaidAccess {
                                ATHLTHCard {
                                    Label(
                                        insightText("ATHLTH Coach health insights are off", "ATHLTH Coach-helseinnsikt er av"),
                                        systemImage: "lock.shield.fill"
                                    )
                                    .font(.headline)
                                    .foregroundStyle(ATHLTHTheme.accentDeep)

                                    Text(
                                        insightText("Enable health-data use in Settings → Privacy & Data only if you want Coach to use sleep, HRV, heart-rate and workout context. Recovery scoring continues locally either way.", "Aktiver bruk av helsedata i Innstillinger → Personvern og data bare hvis du vil at Coach skal bruke søvn, HRV, puls og treningskontekst. Restitusjon beregnes lokalt uansett.")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                                    .padding(.top, 5)
                                }
                            }
                        }

                        MuscleRecoveryCard(
                            statuses: muscleRecoveryStatuses,
                            unmappedExerciseNames:
                                unmappedMuscleExercises,
                            trendDays:
                                recoverySnapshot.days
                        ) {
                            showingSorenessLog = true
                        }

                        plannedWorkoutInsightCard
                        whatChangedCard
                        loadBalanceCard

                        RecoveryTrendsCard(
                            snapshot: recoverySnapshot,
                            sleep: health.sleep
                        )

                        recoveryPatternsCard

                        if session.hasPaidAccess &&
                            session.aiHealthDataSharingEnabled {
                            RecoverySuggestedTodayCard(
                                suggestion:
                                    (recoveryAIInsight ??
                                        fallbackRecoveryAIInsight)
                                        .suggestion
                            ) {
                                onSelectTab(2)
                            }
                        } else {
                            todaysGuidanceCard
                        }

                        RecoveryDailyCheckInCard(
                            store: sorenessStore
                        ) {
                            showingSorenessLog = true
                        }

                        RecoveryToolsCard { tool in
                            selectedRecoveryTool = tool
                        }

                        if health.sleep.totalAsleep > 0 {
                            RecoveryLastNightCard(
                                sleep: health.sleep
                            )
                        }
                    } else {
                        recoveryUnavailableCard

                        MuscleRecoveryCard(
                            statuses: muscleRecoveryStatuses,
                            unmappedExerciseNames:
                                unmappedMuscleExercises,
                            trendDays:
                                recoverySnapshot.days
                        ) {
                            showingSorenessLog = true
                        }

                        plannedWorkoutInsightCard

                        RecoveryDailyCheckInCard(
                            store: sorenessStore
                        ) {
                            showingSorenessLog = true
                        }

                        RecoveryToolsCard { tool in
                            selectedRecoveryTool = tool
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .athlthLightweightCardChrome()
            }
            .refreshable {
                let performanceID =
                    ATHLTHPerformance.begin(
                        "InsightRefresh"
                    )
                defer {
                    ATHLTHPerformance.end(
                        "InsightRefresh",
                        id: performanceID
                    )
                }

                await health.refreshAll()
                recoverySnapshot =
                    await health.recoveryTrendSnapshot()
                await refreshRecoveryDerivedSnapshot()
                await loadRecoveryAIIfNeeded(
                    force: true
                )
            }
            .task {
                let performanceID =
                    ATHLTHPerformance.begin(
                        "InsightInitialLoad"
                    )
                defer {
                    ATHLTHPerformance.end(
                        "InsightInitialLoad",
                        id: performanceID
                    )
                }

                recoverySnapshot =
                    await health.recoveryTrendSnapshot()
                await refreshRecoveryDerivedSnapshot()
                await loadRecoveryAIIfNeeded()
            }
            .onReceive(
                strengthWorkout
                    .$workoutHistory
                    .dropFirst()
            ) { _ in
                Task { @MainActor in
                    await refreshRecoveryDerivedSnapshot()
                }
            }
            .onReceive(
                sorenessStore
                    .$entries
                    .dropFirst()
            ) { _ in
                Task { @MainActor in
                    await refreshRecoveryDerivedSnapshot()
                }
            }
            .onAppear {
                ATHLTHPerformance.event(
                    "InsightAppear"
                )
            }
            .sheet(isPresented: $showingSorenessLog) {
                RecoverySorenessLogView(
                    store: sorenessStore
                )
            }
            .sheet(isPresented: $showingRecoveryInfo) {
                RecoveryMethodInfoView()
            }
            .sheet(item: $selectedRecoveryTool) { tool in
                RecoveryGuidedToolView(tool: tool)
            }
            .sheet(isPresented: $showingRecoveryCoach) {
                if session.aiHealthDataSharingEnabled {
                    RecoveryCoachView(
                        context: recoveryAIContext,
                        insight:
                            recoveryAIInsight ??
                            fallbackRecoveryAIInsight
                    )
                } else {
                    ContentUnavailableView(
                        insightText("Coach health access is off", "Tilgang til helsedata for Coach er av"),
                        systemImage: "lock.shield.fill",
                        description: Text(
                            insightText("Enable it in Settings → Privacy & Data before sharing recovery health context with ATHLTH Coach.", "Aktiver dette i Innstillinger → Personvern og data før restitusjonsdata deles med ATHLTH Coach.")
                        )
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var recoveryScoreCard: some View {
        ATHLTHCard {
            HStack(spacing: 9) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                ATHLTHTheme.premiumGold,
                                ATHLTHTheme.accent
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 19)

                Text(insightText("Readiness", "Dagsform"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Spacer()

                Text(insightText("Today", "I dag"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep.opacity(0.78)
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )

                Button {
                    showingRecoveryInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    insightText("How ATHLTH calculates recovery", "Hvordan ATHLTH beregner restitusjon")
                )
            }

            if let score = health.recovery.score {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(
                            alignment: .firstTextBaseline,
                            spacing: 3
                        ) {
                            Text("\(score)")
                                .font(
                                    .system(
                                        size: 52,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.90)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                                .contentTransition(.numericText())

                            Text("/100")
                                .font(
                                    .subheadline.weight(.semibold)
                                )
                                .foregroundStyle(.secondary)
                        }

                        Label(
                            localizedRecoveryStateTitle,
                            systemImage:
                                health.recovery.state.systemImage
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                    }
                    .frame(
                        minWidth: 132,
                        alignment: .leading
                    )

                    Divider()
                        .frame(height: 92)

                    recoveryScoreCopy
                }
                .padding(.top, 8)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 50, height: 50)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(insightText("Building your baseline", "Bygger grunnlaget ditt"))
                            .font(.headline)

                        Text(localizedRecoveryDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
            }
        }
    }

    private var recoveryScoreCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recoveryHeadline)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(localizedRecoveryDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var todaysSignalsCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: insightText("Recent signals", "Nylige signaler"))

            HStack(alignment: .top, spacing: 0) {
                recoverySignalMetric(
                    title: insightText("Sleep", "Søvn"),
                    value: health.sleep.totalAsleep > 0
                        ? health.sleep.totalAsleep.shortDuration
                        : "—",
                    comparison: sleepComparisonText,
                    icon: "moon.fill",
                    tint: .purple
                )

                recoverySignalDivider

                recoverySignalMetric(
                    title: "HRV",
                    value: health.heart.hrvMilliseconds.map {
                        "\(Int($0.rounded())) ms"
                    } ?? "—",
                    comparison: hrvComparisonText,
                    icon: "waveform.path.ecg",
                    tint: .blue
                )

                recoverySignalDivider

                recoverySignalMetric(
                    title: insightText("Resting HR", "Hvilepuls"),
                    value: health.heart.restingHeartRate.map {
                        "\(Int($0.rounded())) bpm"
                    } ?? "—",
                    comparison: restingHRComparisonText,
                    icon: "heart.fill",
                    tint: .red
                )

                recoverySignalDivider

                recoverySignalMetric(
                    title: insightText("Load", "Belastning"),
                    value:
                        "\(Int(recoverySnapshot.trainingLoad.acuteMinutes.rounded())) min",
                    comparison:
                        insightText("7d · strength + walk + run", "7 d · styrke + gange + løp"),
                    icon: "chart.bar.fill",
                    tint: .green
                )
            }
            .padding(.top, 14)
        }
    }


    private var plannedWorkoutInsightCard: some View {
        let sessions = recoveryTodaySessions
        let overlaps = recoveryPlanOverlapStatuses(
            sessions: sessions
        )

        return ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(insightText("Today vs planned workout", "Dagens form mot planlagt økt"))
                        .font(.title3.weight(.bold))

                    Text(
                        insightText("Recovery context applied to what you already planned.", "Restitusjonen vurdert opp mot det du allerede har planlagt.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(recoveryPlanStatusTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(recoveryPlanStatusTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        recoveryPlanStatusTint.opacity(0.10),
                        in: Capsule()
                    )
            }

            if let first = sessions.first {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: first.kind.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            recoveryWorkoutTint(first.kind)
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            recoveryWorkoutTint(first.kind).opacity(0.09),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(first.title)
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text(recoverySessionSummary(first))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if sessions.count > 1 {
                            Text(
                                sessions.count == 2
                                    ? ATHLTHLocalization.format(
                                        english:
                                            "+%d more session planned today",
                                        norwegian:
                                            "+%d økt til planlagt i dag",
                                        sessions.count - 1
                                    )
                                    : ATHLTHLocalization.format(
                                        english:
                                            "+%d more sessions planned today",
                                        norwegian:
                                            "+%d økter til planlagt i dag",
                                        sessions.count - 1
                                    )
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)

                Text(recoveryPlanDetail(overlaps: overlaps))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .padding(.top, 10)

                if !overlaps.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(overlaps.prefix(3)) { status in
                            Text(insightMuscleName(status.muscleGroup))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(
                                    status.loadScore >= 0.67
                                        ? Color.red
                                        : Color.orange
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    (
                                        status.loadScore >= 0.67
                                            ? Color.red
                                            : Color.orange
                                    ).opacity(0.09),
                                    in: Capsule()
                                )
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 9)
                }
            } else {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(insightText("No workout planned today", "Ingen økt planlagt i dag"))
                            .font(.headline)

                        Text(
                            insightText("ATHLTH can still use your recovery and muscle load when you choose a quick-start workout.", "ATHLTH kan fortsatt bruke restitusjon og muskelbelastning når du velger en hurtigstartøkt.")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }

            Button {
                onSelectTab(2)
            } label: {
                HStack {
                    Label(
                        sessions.isEmpty
                            ? insightText("Open Train", "Åpne Train")
                            : insightText("Review today's training", "Se gjennom dagens trening"),
                        systemImage: "dumbbell.fill"
                    )

                    Spacer()

                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)
            .padding(.top, 12)
        }
    }

    private var whatChangedCard: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(insightText("What changed?", "Hva har endret seg?"))
                        .font(.title3.weight(.bold))

                    Text(insightText("Recent 7 days compared with the previous 7.", "Siste 7 dager sammenlignet med de 7 foregående."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .foregroundStyle(ATHLTHTheme.premiumGold)
            }

            let items = Array(
                recoveryChangeItems.prefix(3)
            )

            if items.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "equal.circle.fill")
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text(
                        insightText("No clear shift yet, or there are not enough comparable days. ATHLTH will surface only changes large enough to be useful.", "Ingen tydelig endring ennå, eller for få sammenlignbare dager. ATHLTH viser bare endringer som er store nok til å være nyttige.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(item.tint)
                                .frame(width: 34, height: 34)
                                .background(
                                    item.tint.opacity(0.10),
                                    in: RoundedRectangle(
                                        cornerRadius: 11,
                                        style: .continuous
                                    )
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 9)

                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 5)
            }
        }
    }

    private var loadBalanceCard: some View {
        let load = recoverySnapshot.trainingLoad
        let total = max(
            load.strengthMinutes +
                load.runningMinutes +
                load.walkingMinutes +
                load.otherMinutes,
            0
        )

        return ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(insightText("Load & balance", "Belastning og balanse"))
                        .font(.title3.weight(.bold))

                    Text(
                        insightText("Last 7 days · strength, run, walk and other tracked workouts.", "Siste 7 dager · styrke, løp, gange og andre registrerte økter.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Spacer()

                Text(load.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Capsule()
                    )
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(load.acuteMinutes.rounded()))")
                    .font(
                        .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                                insightText(
                                    "min / 7d",
                                    "min / 7 d"
                                )
                            )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let baseline =
                    load.chronicWeeklyAverageMinutes {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(baseline.rounded())) min")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                        Text(insightText("28d weekly avg", "28 d ukesnitt"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 12)

            if total > 0 {
                VStack(spacing: 10) {
                    recoveryLoadRow(
                        title: insightText("Strength", "Styrke"),
                        icon: "dumbbell.fill",
                        minutes: load.strengthMinutes,
                        total: total,
                        tint: .purple
                    )
                    recoveryLoadRow(
                        title: insightText("Run", "Løp"),
                        icon: "figure.run",
                        minutes: load.runningMinutes,
                        total: total,
                        tint: .green
                    )
                    recoveryLoadRow(
                        title: insightText("Walk", "Gange"),
                        icon: "figure.walk",
                        minutes: load.walkingMinutes,
                        total: total,
                        tint: .blue
                    )

                    if load.otherMinutes >= 1 {
                        recoveryLoadRow(
                            title: insightText("Other", "Annet"),
                            icon: "figure.mixed.cardio",
                            minutes: load.otherMinutes,
                            total: total,
                            tint: .gray
                        )
                    }
                }
                .padding(.top, 14)
            } else {
                Text(
                    insightText("No tracked workout load was found in the last 7 days.", "Ingen registrert treningsbelastning ble funnet de siste 7 dagene.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }

            Text(
                insightText("This load view is currently duration-based. It combines tracked activity without pretending that a minute of walking and a minute of hard intervals create identical stress.", "Denne belastningsvisningen er foreløpig basert på varighet. Den kombinerer registrert aktivitet uten å anta at ett minutt gange og ett minutt harde intervaller gir samme belastning.")
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        }
    }

    private var recoveryPatternsCard: some View {
        let patterns = Array(
            recoveryObservedPatterns.prefix(3)
        )

        return ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(insightText("Patterns ATHLTH noticed", "Mønstre ATHLTH har oppdaget"))
                        .font(.title3.weight(.bold))

                    Text(insightText("Observed in your recent data when enough days exist.", "Vises fra dine nyere data når det finnes nok dager."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "sparkles")
                    .foregroundStyle(ATHLTHTheme.premiumGold)
            }

            if patterns.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text(
                        insightText("ATHLTH is still building enough comparable history to show useful personal patterns.", "ATHLTH bygger fortsatt nok sammenlignbar historikk til å vise nyttige personlige mønstre.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(
                        Array(patterns.enumerated()),
                        id: \.offset
                    ) { index, pattern in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                                .frame(width: 30, height: 30)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                )

                            Text(pattern)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 12)
            }

            Label(
                insightText("Observed associations only — not proof that one signal caused another.", "Observerte sammenhenger — ikke bevis på at ett signal forårsaket et annet."),
                systemImage: "info.circle"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
    }

    private func recoveryLoadRow(
        title: String,
        icon: String,
        minutes: Double,
        total: Double,
        tint: Color
    ) -> some View {
        let fraction =
            total > 0
                ? min(max(minutes / total, 0), 1)
                : 0

        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)

                Text(title)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text("\(Int(minutes.rounded())) min")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.055))

                    Capsule()
                        .fill(tint.opacity(0.72))
                        .frame(
                            width: proxy.size.width * fraction
                        )
                }
            }
            .frame(height: 7)
        }
    }

    private var recoveryTodaySessions: [PlannedSession] {
        guard let plan = session.activePlan else {
            return []
        }

        let calendar = Calendar.current
        let weekday =
            calendar.component(.weekday, from: Date())
        let dayIndex = ((weekday + 5) % 7) + 1

        let week: TrainingPlanWeek?

        if let startDate = plan.startDate {
            let start = calendar.startOfDay(for: startDate)
            let today = calendar.startOfDay(for: Date())
            let days = max(
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: today
                ).day ?? 0,
                0
            )
            let weekIndex = min(
                days / 7,
                max(plan.weeks.count - 1, 0)
            )
            week = plan.weeks.indices.contains(weekIndex)
                ? plan.weeks[weekIndex]
                : plan.weeks.first
        } else {
            week = plan.weeks.first
        }

        return week?
            .days
            .first(
                where: {
                    $0.dayIndex == dayIndex
                }
            )?
            .sessions ?? []
    }

    private func recoverySessionSummary(
        _ workout: PlannedSession
    ) -> String {
        var parts = [
            insightWorkoutKindTitle(workout.kind)
        ]

        if let duration = workout.durationMinutes {
            parts.append("\(duration) min")
        }

        if let distance =
            workout.targetDistanceKilometers {
            parts.append(
                String(
                    format: "%.1f km",
                    distance
                )
            )
        }

        if !workout.exercises.isEmpty {
            parts.append(
                ATHLTHLocalization.choose(
                    english:
                        "\(workout.exercises.count) exercises",
                    norwegian:
                        "\(workout.exercises.count) øvelser"
                )
            )
        }

        if let running = workout.runningWorkout {
            parts.append(running.type.title)
        }

        return parts.joined(separator: " · ")
    }

    private func recoveryWorkoutTint(
        _ kind: WorkoutKind
    ) -> Color {
        switch kind {
        case .running: return .green
        case .walking: return .blue
        case .strength: return .purple
        case .mobility: return .teal
        case .recovery: return .indigo
        case .custom: return ATHLTHTheme.accentDeep
        }
    }

    private var recoveryPlanStatusTitle: String {
        guard !recoveryTodaySessions.isEmpty else {
            return insightText("No plan", "Ingen plan")
        }

        guard shouldShowWearableRecoveryContent ||
                !muscleRecoveryStatuses.isEmpty else {
            return insightText("Check manually", "Sjekk manuelt")
        }

        if recoveryPlanSeverity >= 2 {
            return insightText("Adjust", "Juster")
        }

        if recoveryPlanSeverity == 1 {
            return insightText("Watch", "Følg med")
        }

        return insightText("On track", "På rett spor")
    }

    private var recoveryPlanStatusTint: Color {
        switch recoveryPlanSeverity {
        case 2...: return .red
        case 1: return .orange
        default: return .green
        }
    }

    private var recoveryPlanSeverity: Int {
        guard !recoveryTodaySessions.isEmpty else {
            return 0
        }

        if health.recovery.state == .recover {
            return 2
        }

        if recoveryPlanOverlapStatuses(
            sessions: recoveryTodaySessions
        ).contains(
            where: {
                $0.soreness == .high ||
                    $0.loadScore >= 0.67 ||
                    $0.progress < 0.45
            }
        ) {
            return 2
        }

        if health.recovery.state == .takeItEasy ||
            recoverySnapshot.trainingLoad.ratio.map({
                $0 >= 1.50
            }) ?? false {
            return 1
        }

        if !recoveryPlanOverlapStatuses(
            sessions: recoveryTodaySessions
        ).isEmpty {
            return 1
        }

        return 0
    }

    private func recoveryPlanDetail(
        overlaps: [MuscleRecoveryStatus]
    ) -> String {
        guard let first = recoveryTodaySessions.first else {
            return ""
        }

        if health.recovery.state == .recover {
            return
                insightText(
                            "Your current recovery signals are below your normal range. Consider reducing the volume or intensity of \(first.title), or moving it if that fits your plan.",
                            "Restitusjonssignalene dine er under normalen. Vurder å redusere volumet eller intensiteten på \(first.title), eller flytte økten hvis det passer planen."
                        )
        }

        if !overlaps.isEmpty {
            let names = overlaps
                .prefix(3)
                .map {
                    insightMuscleName(
                        $0.muscleGroup
                    )
                }
                .joined(separator: ", ")

            return ATHLTHLocalization.choose(
                english:
                    "\(names) overlap with today's planned work and are still carrying recent load. Review intensity before you start rather than changing the plan automatically.",
                norwegian:
                    "\(names) overlapper med dagens planlagte arbeid og har fortsatt nyere belastning. Vurder intensiteten før du starter i stedet for å endre planen automatisk."
            )
        }

        if let ratio =
            recoverySnapshot.trainingLoad.ratio,
           ratio >= 1.50 {
            return
                insightText(
                            "Your 7-day training load is high relative to your recent weekly average. The workout can stay planned, but lower volume or intensity may be worth considering.",
                            "Treningsbelastningen de siste 7 dagene er høy sammenlignet med ditt nyere ukesnitt. Økten kan fortsatt stå i planen, men lavere volum eller intensitet kan være verdt å vurdere."
                        )
        }

        if shouldShowWearableRecoveryContent {
            return
                insightText(
                            "Recovery signals and recent muscle load do not show a clear reason to change today's planned workout.",
                            "Restitusjonssignalene og den siste muskelbelastningen gir ingen tydelig grunn til å endre dagens planlagte økt."
                        )
        }

        return
            insightText(
                            "There is not enough wearable recovery data to assess this workout yet. Use soreness, energy and how the warm-up feels as the final check.",
                            "Det finnes ikke nok restitusjonsdata fra klokke til å vurdere økten ennå. Bruk ømhet, energi og hvordan oppvarmingen føles som siste sjekk."
                        )
    }

    private func recoveryPlanOverlapStatuses(
        sessions: [PlannedSession]
    ) -> [MuscleRecoveryStatus] {
        let groups = recoveryPlanMuscleGroups(
            sessions: sessions
        )

        guard !groups.isEmpty else {
            return []
        }

        return muscleRecoveryStatuses
            .filter {
                groups.contains($0.muscleGroup) &&
                    (
                        $0.loadScore >= 0.34 ||
                        $0.progress < 0.85 ||
                        $0.soreness.rawValue >=
                            RecoverySorenessLevel.moderate.rawValue
                    )
            }
            .sorted {
                if $0.loadScore != $1.loadScore {
                    return $0.loadScore > $1.loadScore
                }

                return $0.progress < $1.progress
            }
    }

    private func recoveryPlanMuscleGroups(
        sessions: [PlannedSession]
    ) -> Set<String> {
        var groups = Set<String>()

        for workout in sessions {
            switch workout.kind {
            case .running:
                groups.formUnion(
                    [
                        "Quads",
                        "Calves",
                        "Hamstrings",
                        "Glutes",
                        "Core"
                    ]
                )

            case .walking:
                groups.formUnion(
                    [
                        "Quads",
                        "Calves",
                        "Glutes"
                    ]
                )

            case .strength:
                for exercise in workout.exercises {
                    for raw in
                        exercise.embeddedExercise.primaryMuscles {
                        if let group =
                            recoveryNormalizedMuscleGroup(raw) {
                            groups.insert(group)
                        }
                    }
                }

            case .mobility, .recovery, .custom:
                break
            }
        }

        return groups
    }

    private func recoveryNormalizedMuscleGroup(
        _ raw: String
    ) -> String? {
        let value = raw
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        if value.contains("chest") ||
            value.contains("pect") {
            return "Chest"
        }
        if value.contains("lat") ||
            value.contains("back") ||
            value.contains("trap") {
            return "Back"
        }
        if value.contains("shoulder") ||
            value.contains("delt") {
            return "Shoulders"
        }
        if value.contains("bicep") ||
            value.contains("tricep") ||
            value.contains("forearm") {
            return "Arms"
        }
        if value.contains("core") ||
            value.contains("ab") ||
            value.contains("oblique") {
            return "Core"
        }
        if value.contains("glute") ||
            value.contains("hip") {
            return "Glutes"
        }
        if value.contains("quad") {
            return "Quads"
        }
        if value.contains("hamstring") {
            return "Hamstrings"
        }
        if value.contains("calf") ||
            value.contains("calves") {
            return "Calves"
        }

        return nil
    }

    private var recoveryChangeItems:
        [RecoveryChangeItem] {
        let ordered =
            recoverySnapshot.days
                .sorted { $0.date < $1.date }

        guard ordered.count >= 8 else {
            return []
        }

        let split = ordered.count / 2
        let previous = Array(ordered.prefix(split))
        let recent = Array(ordered.suffix(ordered.count - split))

        var items: [RecoveryChangeItem] = []

        if let recentSleep =
                recoveryAverage(
                    recent.compactMap(\.sleepDuration)
                ),
           let previousSleep =
                recoveryAverage(
                    previous.compactMap(\.sleepDuration)
                ),
           previousSleep > 0 {
            let deltaMinutes =
                (recentSleep - previousSleep) / 60
            let magnitude =
                abs(recentSleep - previousSleep) /
                previousSleep

            if abs(deltaMinutes) >= 15 {
                items.append(
                    RecoveryChangeItem(
                        id: "sleep",
                        title:
                            insightText(
                                "Sleep duration",
                                "Søvnvarighet"
                            ),
                        detail:
                            ATHLTHLocalization.choose(
                                english:
                                    "\(recoverySignedMinutes(deltaMinutes)) average sleep vs previous 7 days.",
                                norwegian:
                                    "\(recoverySignedMinutes(deltaMinutes)) gjennomsnittlig søvn sammenlignet med de 7 foregående dagene."
                            ),
                        icon: "moon.fill",
                        tint:
                            deltaMinutes >= 0
                                ? .green
                                : .orange,
                        magnitude: magnitude
                    )
                )
            }
        }

        if let recentHRV =
                recoveryAverage(
                    recent.compactMap(\.hrvMilliseconds)
                ),
           let previousHRV =
                recoveryAverage(
                    previous.compactMap(\.hrvMilliseconds)
                ),
           previousHRV > 0 {
            let delta = recentHRV - previousHRV
            let magnitude = abs(delta) / previousHRV

            if abs(delta) >= 3 {
                items.append(
                    RecoveryChangeItem(
                        id: "hrv",
                        title:
                            insightText(
                                "Heart rate variability",
                                "Hjertefrekvensvariabilitet"
                            ),
                        detail:
                            ATHLTHLocalization.choose(
                                english:
                                    "\(recoverySignedNumber(delta)) ms average HRV vs previous 7 days.",
                                norwegian:
                                    "\(recoverySignedNumber(delta)) ms gjennomsnittlig HRV sammenlignet med de 7 foregående dagene."
                            ),
                        icon: "waveform.path.ecg",
                        tint:
                            delta >= 0
                                ? .green
                                : .orange,
                        magnitude: magnitude
                    )
                )
            }
        }

        if let recentRHR =
                recoveryAverage(
                    recent.compactMap(\.restingHeartRate)
                ),
           let previousRHR =
                recoveryAverage(
                    previous.compactMap(\.restingHeartRate)
                ),
           previousRHR > 0 {
            let delta = recentRHR - previousRHR
            let magnitude = abs(delta) / previousRHR

            if abs(delta) >= 2 {
                items.append(
                    RecoveryChangeItem(
                        id: "rhr",
                        title:
                            insightText(
                                "Resting heart rate",
                                "Hvilepuls"
                            ),
                        detail:
                            ATHLTHLocalization.choose(
                                english:
                                    "\(recoverySignedNumber(delta)) bpm average resting HR vs previous 7 days.",
                                norwegian:
                                    "\(recoverySignedNumber(delta)) bpm gjennomsnittlig hvilepuls sammenlignet med de 7 foregående dagene."
                            ),
                        icon: "heart.fill",
                        tint:
                            delta <= 0
                                ? .green
                                : .orange,
                        magnitude: magnitude
                    )
                )
            }
        }

        let recentTraining =
            recent.reduce(0) {
                $0 + $1.trainingMinutes
            }
        let previousTraining =
            previous.reduce(0) {
                $0 + $1.trainingMinutes
            }

        if recentTraining > 0 ||
            previousTraining > 0 {
            let delta =
                recentTraining - previousTraining
            let denominator =
                max(previousTraining, 30)
            let magnitude =
                abs(delta) / denominator

            if abs(delta) >= 20 {
                items.append(
                    RecoveryChangeItem(
                        id: "load",
                        title:
                            insightText(
                                "Training load",
                                "Treningsbelastning"
                            ),
                        detail:
                            ATHLTHLocalization.choose(
                                english:
                                    "\(recoverySignedNumber(delta)) min tracked training vs previous 7 days.",
                                norwegian:
                                    "\(recoverySignedNumber(delta)) min registrert trening sammenlignet med de 7 foregående dagene."
                            ),
                        icon: "chart.line.uptrend.xyaxis",
                        tint: .blue,
                        magnitude: magnitude
                    )
                )
            }
        }

        return items.sorted {
            $0.magnitude > $1.magnitude
        }
    }

    private var recoveryObservedPatterns: [String] {
        let days =
            recoverySnapshot.days
                .sorted { $0.date < $1.date }
        var patterns: [String] = []

        let sleepHRVPairs:
            [(sleep: Double, hrv: Double)] =
            days.compactMap { day in
                guard let sleep = day.sleepDuration,
                      let hrv = day.hrvMilliseconds
                else {
                    return nil
                }

                return (sleep, hrv)
            }

        if sleepHRVPairs.count >= 6,
           let averageSleep =
                recoveryAverage(
                    sleepHRVPairs.map { $0.sleep }
                ) {
            let higher =
                sleepHRVPairs.filter {
                    $0.sleep >= averageSleep
                }
            let lower =
                sleepHRVPairs.filter {
                    $0.sleep < averageSleep
                }

            if higher.count >= 2,
               lower.count >= 2,
               let highHRV =
                    recoveryAverage(
                        higher.map { $0.hrv }
                    ),
               let lowHRV =
                    recoveryAverage(
                        lower.map { $0.hrv }
                    ) {
                let difference =
                    highHRV - lowHRV

                if abs(difference) >= 3 {
                    patterns.append(
                        ATHLTHLocalization.choose(
                            english:
                                "On higher-sleep days in this 14-day window, HRV averaged \(Int(abs(difference).rounded())) ms \(difference >= 0 ? "higher" : "lower") than on lower-sleep days.",
                            norwegian:
                                "På dager med mer søvn i dette 14-dagersvinduet var HRV i snitt \(Int(abs(difference).rounded())) ms \(difference >= 0 ? "høyere" : "lavere") enn på dager med mindre søvn."
                        )
                    )
                }
            }
        }

        var loadNextRHR:
            [(load: Double, rhr: Double)] = []

        if days.count >= 2 {
            for index in 0..<(days.count - 1) {
                if let nextRHR =
                    days[index + 1].restingHeartRate {
                    loadNextRHR.append(
                        (
                            days[index].trainingMinutes,
                            nextRHR
                        )
                    )
                }
            }
        }

        if loadNextRHR.count >= 6,
           let averageLoad =
                recoveryAverage(
                    loadNextRHR.map { $0.load }
                ) {
            let higher =
                loadNextRHR.filter {
                    $0.load > averageLoad
                }
            let lower =
                loadNextRHR.filter {
                    $0.load <= averageLoad
                }

            if higher.count >= 2,
               lower.count >= 2,
               let highRHR =
                    recoveryAverage(
                        higher.map { $0.rhr }
                    ),
               let lowRHR =
                    recoveryAverage(
                        lower.map { $0.rhr }
                    ) {
                let difference =
                    highRHR - lowRHR

                if abs(difference) >= 2 {
                    patterns.append(
                        ATHLTHLocalization.choose(
                            english:
                                "Days after higher training volume showed resting HR averaging \(Int(abs(difference).rounded())) bpm \(difference >= 0 ? "higher" : "lower") than after lighter days.",
                            norwegian:
                                "Dager etter høyere treningsvolum viste en hvilepuls som i snitt var \(Int(abs(difference).rounded())) bpm \(difference >= 0 ? "høyere" : "lavere") enn etter lettere dager."
                        )
                    )
                }
            }
        }

        let load =
            recoverySnapshot.trainingLoad
        let total =
            load.strengthMinutes +
            load.runningMinutes +
            load.walkingMinutes +
            load.otherMinutes

        if total >= 60 {
            let sources: [(String, Double)] = [
                (
                    insightText("strength", "styrke"),
                    load.strengthMinutes
                ),
                (
                    insightText("running", "løping"),
                    load.runningMinutes
                ),
                (
                    insightText("walking", "gange"),
                    load.walkingMinutes
                ),
                (
                    insightText(
                        "other training",
                        "annen trening"
                    ),
                    load.otherMinutes
                )
            ]

            if let dominant =
                sources.max(
                    by: {
                        $0.1 < $1.1
                    }
                ),
               dominant.1 / total >= 0.55 {
                patterns.append(
                    ATHLTHLocalization.choose(
                        english:
                            "\(Int(((dominant.1 / total) * 100).rounded()))% of your tracked 7-day training time came from \(dominant.0).",
                        norwegian:
                            "\(Int(((dominant.1 / total) * 100).rounded()))% av den registrerte treningstiden de siste 7 dagene kom fra \(dominant.0)."
                    )
                )
            }
        }

        let loadedAreas =
            muscleRecoveryStatuses
                .filter {
                    $0.loadScore >= 0.34 &&
                        $0.progress < 0.90
                }
                .prefix(2)
                .map {
                    insightMuscleName(
                        $0.muscleGroup
                    )
                }

        if !loadedAreas.isEmpty {
            let separator =
                ATHLTHLocalization.isNorwegian
                    ? " og "
                    : " and "

            patterns.append(
                ATHLTHLocalization.choose(
                    english:
                        "\(loadedAreas.joined(separator: separator)) currently carry the most notable combination of recent load and incomplete recovery.",
                    norwegian:
                        "\(loadedAreas.joined(separator: separator)) har nå den tydeligste kombinasjonen av nyere belastning og ufullstendig restitusjon."
                )
            )
        }

        return Array(patterns.prefix(3))
    }

    private func recoveryAverage(
        _ values: [Double]
    ) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) /
            Double(values.count)
    }

    private func recoverySignedNumber(
        _ value: Double
    ) -> String {
        let rounded =
            Int(abs(value).rounded())
        return value >= 0
            ? "+\(rounded)"
            : "−\(rounded)"
    }

    private func recoverySignedMinutes(
        _ value: Double
    ) -> String {
        let rounded =
            Int(abs(value).rounded())
        return value >= 0
            ? "+\(rounded) min"
            : "−\(rounded) min"
    }

    private var todaysGuidanceCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: insightText("Today's guidance", "Dagens anbefaling"))

            HStack(alignment: .top, spacing: 13) {
                Image(systemName: health.recovery.state.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(guidanceTitle)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(guidanceDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 10)

            HStack(spacing: 9) {
                Button {
                    onSelectTab(2)
                } label: {
                    Label(
                        guidanceTrainActionTitle,
                        systemImage: "dumbbell.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)

                Button {
                    selectedRecoveryTool =
                        recommendedRecoveryTool
                } label: {
                    Label(
                        insightText("Recovery session", "Restitusjonsøkt"),
                        systemImage: "leaf.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.accent)
            }
            .padding(.top, 12)
        }
    }


    private var recoveryUnavailableCard: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(insightText("Recovery data isn’t available yet", "Restitusjonsdata er ikke tilgjengelig ennå"))
                        .font(.headline)

                    Text(recoveryUnavailableDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var recoverySignalDivider: some View {
        Rectangle()
            .fill(ATHLTHTheme.divider)
            .frame(width: 1, height: 94)
            .padding(.horizontal, 6)
    }

    private func recoverySignalMetric(
        title: String,
        value: String,
        comparison: String?,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 20)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(comparison ?? insightText("No baseline yet", "Ingen grunnlinje ennå"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sleepComparisonText: String? {
        guard health.sleep.totalAsleep > 0,
              let baseline = health.recovery.averageSleepDuration,
              baseline > 0 else {
            return nil
        }

        return durationComparison(
            current: health.sleep.totalAsleep,
            baseline: baseline
        )
    }

    private var hrvComparisonText: String? {
        guard let current = health.heart.hrvMilliseconds,
              let baseline = health.recovery.baselineHRVMilliseconds else {
            return nil
        }

        return numberComparison(
            current: current,
            baseline: baseline,
            unit: "ms"
        )
    }

    private var restingHRComparisonText: String? {
        guard let current = health.heart.restingHeartRate,
              let baseline = health.recovery.baselineRestingHeartRate else {
            return nil
        }

        return numberComparison(
            current: current,
            baseline: baseline,
            unit: "bpm"
        )
    }

    private func durationComparison(
        current: TimeInterval,
        baseline: TimeInterval
    ) -> String {
        let difference = current - baseline

        guard abs(difference) >= 60 else {
            return insightText("At baseline", "På grunnlinjen")
        }

        let totalMinutes = Int((abs(difference) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let sign = difference > 0 ? "+" : "−"

        if hours > 0, minutes > 0 {
            return ATHLTHLocalization.choose(
                english:
                    "\(sign)\(hours)h \(minutes)m vs baseline",
                norwegian:
                    "\(sign)\(hours)t \(minutes)m mot grunnlinje"
            )
        }

        if hours > 0 {
            return ATHLTHLocalization.choose(
                english:
                    "\(sign)\(hours)h vs baseline",
                norwegian:
                    "\(sign)\(hours)t mot grunnlinje"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "\(sign)\(minutes)m vs baseline",
            norwegian:
                "\(sign)\(minutes)m mot grunnlinje"
        )
    }

    private func numberComparison(
        current: Double,
        baseline: Double,
        unit: String
    ) -> String {
        let difference = Int((current - baseline).rounded())

        guard difference != 0 else {
            return insightText("At baseline", "På grunnlinjen")
        }

        let sign = difference > 0 ? "+" : "−"
        return ATHLTHLocalization.choose(
            english:
                "\(sign)\(abs(difference)) \(unit) vs baseline",
            norwegian:
                "\(sign)\(abs(difference)) \(unit) mot grunnlinje"
        )
    }

    private var shouldShowWearableRecoveryContent: Bool {
        health.recovery.score != nil ||
            health.sleep.totalAsleep > 0 ||
            health.heart.hrvMilliseconds != nil ||
            health.heart.restingHeartRate != nil ||
            health.recovery.baselineDays > 0
    }

    private var recoveryUnavailableDetail: String {
        if !health.hasRequestedAuthorization {
            if watchConnection.isReady {
                return insightText(
                    "Apple Watch is connected, but recovery metrics stay hidden until Apple Health data is available. You can still use training plans, log strength sessions and use the rest of ATHLTH.",
                    "Apple Watch er tilkoblet, men restitusjonsdata skjules til Apple Health-data er tilgjengelig. Du kan fortsatt bruke treningsplaner, registrere styrkeøkter og bruke resten av ATHLTH."
                )
            }

            return insightText(
                "Apple Health is not connected, so ATHLTH hides unavailable recovery metrics. You can connect Apple Health or Apple Watch later in Settings.",
                "Apple Health er ikke tilkoblet, så ATHLTH skjuler utilgjengelige restitusjonsmålinger. Du kan koble til Apple Health eller Apple Watch senere i Innstillinger."
            )
        }

        return watchConnection.isReady
            ? insightText(
                "ATHLTH will show recovery as soon as compatible Apple Health data from your Watch or another source is available. Empty metrics stay hidden in the meantime.",
                "ATHLTH viser restitusjon så snart kompatible Apple Health-data fra klokken eller en annen kilde er tilgjengelig. Tomme målinger skjules i mellomtiden."
            )
            : insightText(
                "Apple Health is configured. ATHLTH will show recovery when compatible readable sleep, HRV or resting heart-rate data becomes available.",
                "Apple Health er konfigurert. ATHLTH viser restitusjon når kompatible, lesbare data for søvn, HRV eller hvilepuls blir tilgjengelig."
            )
    }

    private var localizedRecoveryStateTitle: String {
        switch health.recovery.state {
        case .ready:
            return insightText("Ready", "Klar")
        case .balanced:
            return insightText("Balanced", "Balansert")
        case .takeItEasy:
            return insightText("Take it easy", "Ta det roligere")
        case .recover:
            return insightText("Recover", "Restituer")
        case .buildingBaseline:
            return insightText("Building baseline", "Bygger grunnlinje")
        }
    }

    private var localizedRecoveryDetail: String {
        if health.recovery.state == .buildingBaseline {
            if health.recovery.baselineDays > 0 {
                return ATHLTHLocalization.choose(
                    english:
                        "ATHLTH has \(health.recovery.baselineDays) usable baseline day\(health.recovery.baselineDays == 1 ? "" : "s"). At least 5 days with sleep, HRV and resting heart rate are needed.",
                    norwegian:
                        "ATHLTH har \(health.recovery.baselineDays) brukbar\(health.recovery.baselineDays == 1 ? "" : "e") dag\(health.recovery.baselineDays == 1 ? "" : "er") i grunnlinjen. Minst 5 dager med søvn, HRV og hvilepuls er nødvendig."
                )
            }

            return insightText(
                "ATHLTH is learning your recent sleep, HRV and resting heart-rate baseline.",
                "ATHLTH lærer grunnlinjen din for søvn, HRV og hvilepuls."
            )
        }

        return insightText(
            "Based on last night's sleep and your most recent HRV/resting heart rate compared with your recent baseline.",
            "Basert på nattens søvn og din nyeste HRV/hvilepuls sammenlignet med din nyere grunnlinje."
        )
    }

    private var recoveryHeadline: String {
        switch health.recovery.state {
        case .ready:
            return insightText("Well recovered", "Godt restituert")
        case .balanced:
            return insightText("Balanced recovery", "Balansert restitusjon")
        case .takeItEasy:
            return insightText("A lighter day may fit", "En lettere dag kan passe")
        case .recover:
            return insightText("Prioritize recovery", "Prioriter restitusjon")
        case .buildingBaseline:
            return insightText("Building your baseline", "Bygger grunnlaget ditt")
        }
    }

    private var guidanceTitle: String {
        if sorenessStore.todayOverallSoreness.map({
            $0 >= 4
        }) ?? false {
            return insightText("Your body is asking for less today", "Kroppen din ber om mindre i dag")
        }

        if sorenessStore.highestTodayLevel == .high {
            return insightText("Protect sore muscle groups today", "Skån ømme muskelgrupper i dag")
        }

        if sorenessStore.todayEnergy.map({
            $0 <= 2
        }) ?? false {
            return insightText("Energy is low today", "Energien er lav i dag")
        }

        if sorenessStore.todayStress.map({
            $0 >= 4
        }) ?? false {
            return insightText("Stress is elevated today", "Stressnivået er høyere i dag")
        }

        if sorenessStore.todayMotivation.map({
            $0 <= 2
        }) ?? false {
            return insightText("Motivation is low today", "Motivasjonen er lav i dag")
        }

        if sorenessStore.highestTodayLevel == .moderate {
            return insightText("Adjust around sore areas", "Tilpass rundt ømme områder")
        }

        if let ratio = recoverySnapshot.trainingLoad.ratio,
           ratio >= 1.50 {
            return insightText("Training load is high", "Treningsbelastningen er høy")
        }

        switch health.recovery.state {
        case .ready:
            return insightText("Good day for a hard session", "God dag for en hard økt")
        case .balanced:
            return insightText("Train as planned", "Tren som planlagt")
        case .takeItEasy:
            return insightText("Consider active recovery", "Vurder aktiv restitusjon")
        case .recover:
            return insightText("Prioritize recovery today", "Prioriter restitusjon i dag")
        case .buildingBaseline:
            return watchConnection.isReady
                ? insightText("Keep wearing your Apple Watch", "Fortsett å bruke Apple Watch")
                : insightText("More health data is needed", "Mer helsedata er nødvendig")
        }
    }

    private var guidanceDetail: String {
        if sorenessStore.todayOverallSoreness.map({
            $0 >= 4
        }) ?? false {
            return insightText(
                "Your Daily Check-in shows high overall soreness. Consider reducing load, changing muscle groups or choosing a gentle recovery session.",
                "Dagens innsjekk viser høy generell ømhet. Vurder lavere belastning, andre muskelgrupper eller en rolig restitusjonsøkt."
            )
        }

        if sorenessStore.highestTodayLevel == .high {
            return insightText(
                "Your body check-in shows high soreness. Keep those muscle groups out of heavy work and choose another area, mobility or easy recovery.",
                "Innsjekken viser høy muskelømhet. Unngå tung belastning på disse muskelgruppene og velg et annet område, mobilitet eller lett restitusjon."
            )
        }

        if sorenessStore.todayEnergy.map({
            $0 <= 2
        }) ?? false {
            return insightText(
                "Your Daily Check-in shows low energy. Keep the session flexible and reduce volume or intensity if effort feels unusually high.",
                "Dagens innsjekk viser lav energi. Hold økten fleksibel og reduser volum eller intensitet hvis belastningen føles uvanlig høy."
            )
        }

        if sorenessStore.todayStress.map({
            $0 >= 4
        }) ?? false {
            return insightText(
                "Your Daily Check-in shows elevated stress. A shorter session, easier intensity or a recovery tool may fit better today.",
                "Dagens innsjekk viser høyere stress. En kortere økt, lavere intensitet eller et restitusjonsverktøy kan passe bedre i dag."
            )
        }

        if sorenessStore.todayMotivation.map({
            $0 <= 2
        }) ?? false {
            return insightText(
                "Motivation is low in today's check-in. Keep the plan flexible: start easy, reassess after the warm-up, and reduce the session if it still feels off.",
                "Motivasjonen er lav i dagens innsjekk. Hold planen fleksibel: start rolig, vurder på nytt etter oppvarmingen og reduser økten hvis det fortsatt føles feil."
            )
        }

        if sorenessStore.highestTodayLevel == .moderate {
            return insightText(
                "Moderate soreness is logged today. You can still train, but reduce load on the affected muscle groups or choose a different focus.",
                "Moderat ømhet er registrert i dag. Du kan fortsatt trene, men reduser belastningen på berørte muskelgrupper eller velg et annet fokus."
            )
        }

        if let ratio = recoverySnapshot.trainingLoad.ratio,
           ratio >= 1.50 {
            return insightText(
                "Your last 7 days are substantially above your recent 28-day weekly average. Consider lower volume, easier intensity or a recovery session today.",
                "De siste 7 dagene ligger tydelig over ditt nyere 28-dagers ukesnitt. Vurder lavere volum, roligere intensitet eller en restitusjonsøkt i dag."
            )
        }

        switch health.recovery.state {
        case .ready:
            return insightText(
                "Sleep, HRV and resting heart rate support a normal-to-hard training day. Use your planned session and how you feel as the final check.",
                "Søvn, HRV og hvilepuls støtter en normal til hard treningsdag. Bruk den planlagte økten og hvordan du føler deg som siste sjekk."
            )
        case .balanced:
            return insightText(
                "Your signals are close to baseline. Follow the plan and adjust if effort feels unusually high.",
                "Signalene dine ligger nær grunnlinjen. Følg planen og juster hvis belastningen føles uvanlig høy."
            )
        case .takeItEasy:
            return insightText(
                "One or more recovery signals are below your recent pattern. Easy cardio, mobility or reduced training volume may fit better today.",
                "Ett eller flere restitusjonssignaler ligger under det nyere mønsteret ditt. Lett kondisjon, mobilitet eller redusert treningsvolum kan passe bedre i dag."
            )
        case .recover:
            return insightText(
                "Your combined recovery signals are well below baseline. Rest, mobility, breathing or very easy activity may be more appropriate.",
                "De samlede restitusjonssignalene ligger godt under grunnlinjen. Hvile, mobilitet, pust eller svært lett aktivitet kan passe bedre."
            )
        case .buildingBaseline:
            return watchConnection.isReady
                ? insightText(
                    "ATHLTH needs at least five usable days with sleep, HRV and resting heart-rate data before showing a recovery score.",
                    "ATHLTH trenger minst fem brukbare dager med søvn, HRV og hvilepuls før en restitusjonsscore kan vises."
                )
                : insightText(
                    "Recovery scoring needs sleep, HRV and resting heart-rate data. Without compatible data, ATHLTH leaves the score unavailable instead of estimating it.",
                    "Restitusjonsscoren trenger data for søvn, HRV og hvilepuls. Uten kompatible data lar ATHLTH scoren stå utilgjengelig i stedet for å gjette."
                )
        }
    }

    private var guidanceTrainActionTitle: String {
        let highOverallSoreness =
            sorenessStore.todayOverallSoreness.map {
                $0 >= 4
            } ?? false
        let lowEnergy =
            sorenessStore.todayEnergy.map {
                $0 <= 2
            } ?? false
        let highStress =
            sorenessStore.todayStress.map {
                $0 >= 4
            } ?? false
        let lowMotivation =
            sorenessStore.todayMotivation.map {
                $0 <= 2
            } ?? false

        if highOverallSoreness ||
            lowEnergy ||
            highStress ||
            lowMotivation ||
            sorenessStore.highestTodayLevel == .high ||
            health.recovery.state == .takeItEasy ||
            health.recovery.state == .recover {
            return insightText("Adjust workout", "Juster økten")
        }

        return insightText("Open Train", "Åpne Train")
    }

    private var recommendedRecoveryTool: RecoveryTool {
        let highStress =
            sorenessStore.todayStress.map {
                $0 >= 4
            } ?? false
        let highOverallSoreness =
            sorenessStore.todayOverallSoreness.map {
                $0 >= 4
            } ?? false

        if highStress {
            return .breathing
        }

        if highOverallSoreness ||
            sorenessStore.highestTodayLevel == .high ||
            sorenessStore.highestTodayLevel == .moderate {
            return .mobility
        }

        return .stretch
    }

    private var muscleRecoveryStatuses: [MuscleRecoveryStatus] {
        recoveryDerivedSnapshot.statuses
    }

    private var unmappedMuscleExercises: [String] {
        recoveryDerivedSnapshot
            .unmappedExerciseNames
    }

    private var recoveryAIContext: RecoveryAIContext {
        RecoveryAIContext(
            recoveryScore: health.recovery.score,
            recoveryState: localizedRecoveryStateTitle,
            recoveryDetail: health.recovery.detail,
            sleepSeconds: health.sleep.totalAsleep > 0
                ? health.sleep.totalAsleep
                : nil,
            baselineSleepSeconds: health.recovery.averageSleepDuration,
            hrvMilliseconds: health.heart.hrvMilliseconds,
            baselineHRVMilliseconds:
                health.recovery.baselineHRVMilliseconds,
            restingHeartRate: health.heart.restingHeartRate,
            baselineRestingHeartRate:
                health.recovery.baselineRestingHeartRate,
            yesterdayTrainingMinutes: yesterdayTrainingMinutes,
            acuteTrainingMinutes:
                recoverySnapshot.trainingLoad.acuteMinutes,
            chronicWeeklyAverageMinutes:
                recoverySnapshot.trainingLoad.chronicWeeklyAverageMinutes,
            muscles: muscleRecoveryStatuses.prefix(8).map {
                RecoveryAIMuscleInput(
                    name: $0.muscleGroup,
                    recoveryPercent: Int(
                        ($0.progress * 100).rounded()
                    ),
                    status: $0.statusTitle,
                    completedSets: $0.completedSets
                )
            },
            checkIn: RecoveryAICheckIn(
                energy: sorenessStore.todayEnergy,
                stress: sorenessStore.todayStress,
                overallSoreness:
                    sorenessStore.todayOverallSoreness,
                motivation: sorenessStore.todayMotivation
            )
        )
    }

    private var yesterdayTrainingMinutes: Double {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: Date()
        ) else {
            return 0
        }

        return recoverySnapshot.days.first {
            calendar.isDate(
                $0.date,
                inSameDayAs: yesterday
            )
        }?.trainingMinutes ?? 0
    }

    private var fallbackRecoveryAIInsight: RecoveryAIInsight {
        RecoveryAIInsight(
            headline: recoveryHeadline,
            summary: localizedRecoveryDetail,
            factors: [
                RecoveryAIFactor(
                    title: insightText("Sleep", "Søvn"),
                    detail: sleepComparisonText ?? insightText("No personal baseline yet.", "Ingen personlig grunnlinje ennå."),
                    impact: recoveryFactorImpact(
                        current: health.sleep.totalAsleep > 0
                            ? health.sleep.totalAsleep
                            : nil,
                        baseline: health.recovery.averageSleepDuration,
                        higherIsBetter: true
                    )
                ),
                RecoveryAIFactor(
                    title: "HRV",
                    detail: hrvComparisonText ?? insightText("No personal baseline yet.", "Ingen personlig grunnlinje ennå."),
                    impact: recoveryFactorImpact(
                        current: health.heart.hrvMilliseconds,
                        baseline:
                            health.recovery.baselineHRVMilliseconds,
                        higherIsBetter: true
                    )
                ),
                RecoveryAIFactor(
                    title: insightText("Resting HR", "Hvilepuls"),
                    detail:
                        restingHRComparisonText ??
                        insightText("No personal baseline yet.", "Ingen personlig grunnlinje ennå."),
                    impact: recoveryFactorImpact(
                        current: health.heart.restingHeartRate,
                        baseline:
                            health.recovery.baselineRestingHeartRate,
                        higherIsBetter: false
                    )
                )
            ],
            suggestion: RecoveryAISuggestion(
                title: guidanceTitle,
                subtitle: fallbackSuggestionSubtitle,
                reason: guidanceDetail
            ),
            quickQuestions: [
                insightText("Why is my recovery different today?", "Hvorfor er restitusjonen min annerledes i dag?"),
                insightText("Should I change today's workout?", "Bør jeg endre dagens økt?"),
                insightText("Which muscle groups need more recovery?", "Hvilke muskelgrupper trenger mer restitusjon?")
            ]
        )
    }

    private var fallbackSuggestionSubtitle: String {
        switch health.recovery.state {
        case .ready:
            return insightText("Normal to hard · follow your plan", "Normal til hard · følg planen")
        case .balanced:
            return insightText("Train as planned · stay flexible", "Tren som planlagt · vær fleksibel")
        case .takeItEasy:
            return insightText("Easy effort · reduce load if needed", "Rolig innsats · reduser belastningen ved behov")
        case .recover:
            return insightText("Rest, mobility or very easy activity", "Hvile, mobilitet eller svært lett aktivitet")
        case .buildingBaseline:
            return insightText("Keep collecting recovery data", "Fortsett å samle restitusjonsdata")
        }
    }

    private func recoveryFactorImpact(
        current: Double?,
        baseline: Double?,
        higherIsBetter: Bool
    ) -> String {
        guard let current,
              let baseline,
              baseline > 0 else {
            return "neutral"
        }

        let difference = (current - baseline) / baseline
        guard abs(difference) >= 0.04 else {
            return "neutral"
        }

        let favorable = higherIsBetter
            ? difference > 0
            : difference < 0
        return favorable ? "positive" : "negative"
    }

    @MainActor
    private func refreshRecoveryDerivedSnapshot()
        async {
        recoveryDerivedGeneration &+= 1
        let generation =
            recoveryDerivedGeneration
        let history =
            strengthWorkout.workoutHistory
        let sorenessRatings =
            sorenessStore.todayRatings
        let activityLoad =
            recoverySnapshot.trainingLoad

        let snapshot =
            await RecoveryDerivedSnapshotBuilder
                .build(
                    history: history,
                    sorenessRatings:
                        sorenessRatings,
                    activityLoad:
                        activityLoad
                )

        guard generation ==
                recoveryDerivedGeneration
        else {
            return
        }

        recoveryDerivedSnapshot = snapshot
    }

    @MainActor
    private func loadRecoveryAIIfNeeded(
        force: Bool = false
    ) async {
        guard session.hasPaidAccess,
              session.aiHealthDataSharingEnabled,
              shouldShowWearableRecoveryContent else {
            recoveryAIInsight = nil
            recoveryAIError = nil
            return
        }

        if !force, recoveryAIInsight != nil {
            return
        }

        isLoadingRecoveryAI = true
        recoveryAIError = nil
        let performanceID =
            ATHLTHPerformance.begin(
                "RecoveryAILoad"
            )
        defer {
            isLoadingRecoveryAI = false
            ATHLTHPerformance.end(
                "RecoveryAILoad",
                id: performanceID
            )
        }

        do {
            recoveryAIInsight = try await RecoveryAIService()
                .generate(
                    recoveryAIContext,
                    bypassCache: force
                )
        } catch {
            // The deterministic fallback remains visible so Recovery
            // never becomes an empty screen when AI is unavailable.
            recoveryAIError = error.localizedDescription
        }
    }

}


private enum ProgressPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"
    case year = "Year"

    var id: String { rawValue }
}

struct ATHLTHProgressView: View {
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
        let useImmersiveProgressHero =
            UIDevice.current.userInterfaceIdiom == .pad ||
            UIScreen.main.bounds.width >= 390

        return NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: green.opacity(0.60),
                softTransition: true,
                immersiveTransition: useImmersiveProgressHero,
                scrollFadeTransition: true
            ) {
                ATHLTHTabHero(
                    imageName: "ProgressHero",
                    title: "Progress",
                    subtitle: "See your training, consistency and health trends.",
                    height:
                        useImmersiveProgressHero
                            ? 226
                            : 190,
                    alignment: .leading,
                    focalOffsetX:
                        useImmersiveProgressHero
                            ? 4
                            : 18,
                    focalOffsetY:
                        useImmersiveProgressHero
                            ? 6
                            : 16,
                    titleFontSize:
                        useImmersiveProgressHero
                            ? 31
                            : 30,
                    copyWidthFraction:
                        useImmersiveProgressHero
                            ? 0.66
                            : 0.80,
                    immersiveCopy: useImmersiveProgressHero
                )
            } content: {
                LazyVStack(spacing: 14) {
                    if health.hasRequestedAuthorization &&
                        (health.hasTrainingHealthData || progressHasHealthData) {
                        periodPicker

                        weeklyOverview

                        if let snapshot = progressSnapshot {
                            ProgressTrendCard(
                                snapshot: snapshot,
                                metric: $trendMetric
                            )
                        }

                        ProgressConsistencyCard(
                            snapshot: consistencySnapshot
                        )

                        ProgressPerformanceCard(
                            runningWorkouts:
                                selectedPeriodRunningWorkouts,
                            strengthWorkouts:
                                selectedPeriodStrengthWorkouts,
                            healthRecords: personalRecords,
                            strengthRecords:
                                strengthWorkout.personalRecords,
                            repRecords:
                                strengthWorkout.repPersonalRecords
                        )

                        personalRecordsCard
                        achievementsCard
                    } else {
                        progressWithoutHealthCard

                        ProgressPerformanceCard(
                            runningWorkouts: [],
                            strengthWorkouts:
                                selectedPeriodStrengthWorkouts,
                            healthRecords: personalRecords,
                            strengthRecords:
                                strengthWorkout.personalRecords,
                            repRecords:
                                strengthWorkout.repPersonalRecords
                        )

                        personalRecordsCard
                        achievementsCard
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
                            ? "No Apple Health progress data yet"
                            : "Progress without Apple Health"
                    )
                    .font(.headline)

                    Text(
                        health.hasRequestedAuthorization
                            ? "Apple Health is configured, but ATHLTH has not found readable workout, steps or sleep progress for this period yet. Health-based charts stay hidden instead of showing empty cards."
                            : "Health-based charts stay hidden until Apple Health is connected. Strength records, goals, achievements and other ATHLTH-native progress remain available."
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
        let healthRecords = Array(personalRecords.prefix(2))
        let strengthRecords = Array(
            strengthWorkout.personalRecords
                .filter { $0.kind == .heaviestSet }
                .prefix(2)
        )
        let totalRecordCount =
            personalRecords.count +
            strengthWorkout.personalRecords.count +
            strengthWorkout.repPersonalRecords.count

        return NavigationLink {
            ProgressPersonalRecordsView(
                healthRecords: personalRecords,
                strengthRecords:
                    strengthWorkout.personalRecords,
                repRecords:
                    strengthWorkout.repPersonalRecords
            )
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personal Records")
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text("Your verified best performances.")
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

                        Text("No records yet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text(
                            "ATHLTH will surface verified records from Apple Health and strength workouts you log in ATHLTH."
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

    private func compactHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
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

    private func formattedSteps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Int(value.rounded()).formatted()
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

    private func bucketAxisLabel(_ date: Date) -> String {
        switch period {
        case .week:
            return date.formatted(.dateTime.weekday(.narrow))
        case .month, .threeMonths:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .year:
            return date.formatted(.dateTime.month(.abbreviated))
        }
    }

    @ViewBuilder
    private func chartPlaceholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.025))
            .frame(height: 120)
            .overlay {
                Image(systemName: icon)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
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
            progressError = "Connect Apple Health to show your progress."
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

    private func statTile(
        icon: String,
        tint: Color,
        value: String,
        label: String,
        change: Double?
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

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

            Spacer(minLength: 0)
        }
    }

    private func achievementBadge(
        icon: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(45))

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 58)

            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func goalRow(
        icon: String,
        title: String,
        detail: String,
        progress: Double,
        progressText: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(green)
                .frame(width: 34, height: 34)
                .background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(progressText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(green)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.055))
                        Capsule()
                            .fill(green)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 6)
            }
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

private struct ATHLTHSwipeBackEnabler: UIViewControllerRepresentable {
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
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var strengthWorkout:
        StrengthWorkoutStore
    @EnvironmentObject private var challenges:
        ChallengeStore

    @State private var performanceStats:
        ProfilePerformanceStats?
    @State private var personalRecords:
        [HealthPersonalRecord] = []
    @State private var loadingProfileData = false
    @AppStorage(ProfileFeaturedRecordKind.storageKey)
    private var featuredRecordSelectionRaw = ""
    @AppStorage(ProfileMomentFavorites.storageKey)
    private var favoriteMomentSelectionRaw = ""

    var body: some View {
        ATHLTHPinnedHeroLayout(
            accent:
                ATHLTHTheme.premiumGold.opacity(0.34),
            immersiveTransition: true,
            sheetOverlapOverride: 12
        ) {
            profileHero
        } content: {
            LazyVStack(spacing: 12) {
                trophyCabinetSection
                personalRecordsSection
                gearSection
                workoutMomentsSection
            }
            .padding(.horizontal, 14)
            // Keep the first section comfortably below the profile stats.
            // The profile uses a smaller sheet overlap so all four stat cells
            // remain fully visible above the rounded white content sheet.
            .padding(.top, 50)
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
            await refreshProfile(
                forceRefresh: true
            )
        }
        .task {
            await refreshProfile()
        }
    }

    private var profileHero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Image("ProfileHero")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .accessibilityHidden(true)

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
                        alignment: .bottom,
                        spacing: 14
                    ) {
                        profileAvatar

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            HStack(spacing: 7) {
                                Text(
                                    session.profile
                                        .displayName
                                )
                                .font(
                                    .system(
                                        size: 27,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.70)

                                if trophyStore
                                    .unlockedCount > 0 {
                                    Image(
                                        systemName:
                                            "checkmark.seal.fill"
                                    )
                                    .font(.system(size: 16))
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .premiumGold
                                    )
                                }
                            }

                            if !session.profile
                                .username.isEmpty {
                                Text(
                                    "@\(session.profile.username)"
                                )
                                .font(
                                    .subheadline
                                        .weight(.medium)
                                )
                                .foregroundStyle(
                                    .white.opacity(0.84)
                                )
                            }

                            if let focus =
                                trainingIdentityFocus {
                                Text(
                                    focus.title
                                )
                                .font(
                                    .caption.weight(
                                        .semibold
                                    )
                                )
                                .foregroundStyle(
                                    .white.opacity(0.92)
                                )
                            }

                            let bio =
                                session.profile.bio
                                    .trimmingCharacters(
                                        in:
                                            .whitespacesAndNewlines
                                    )

                            if !bio.isEmpty {
                                Text(bio)
                                    .font(.caption)
                                    .foregroundStyle(
                                        .white.opacity(0.88)
                                    )
                                    .lineLimit(2)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                                    .padding(.top, 2)
                            }
                        }

                        Spacer(minLength: 0)
                    }

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
        .overlay(
            alignment: .topTrailing
        ) {
            HStack(spacing: 10) {
                NavigationLink {
                    ATHLTHEditProfileView()
                } label: {
                    Image(systemName: "pencil")
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.white)
                        .frame(
                            width: 42,
                            height: 42
                        )
                        .background(
                            Color.black.opacity(0.30),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.30),
                                    lineWidth: 0.8
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english: "Edit Profile",
                        norwegian: "Rediger profil"
                    )
                )

                NavigationLink {
                    ATHLTHSettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.white)
                        .frame(
                            width: 42,
                            height: 42
                        )
                        .background(
                            Color.black.opacity(0.30),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.30),
                                    lineWidth: 0.8
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english: "Settings",
                        norwegian: "Innstillinger"
                    )
                )
            }
            .padding(.top, 72)
            .padding(.trailing, 18)
        }
        .frame(height: 236)
        .clipped()
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
                        lifetimeDistanceText,
                    title:
                        ATHLTHLocalization.choose(
                            english: "Total km",
                            norwegian: "Km totalt"
                        ),
                    icon:
                        "chart.bar.fill"
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

    private var trophyCabinetSection:
        some View {
        profileSection(
            title:
                ATHLTHLocalization.choose(
                    english: "Trophy cabinet",
                    norwegian: "Troféskap"
                ),
            icon: "trophy.fill",
            actionTitle:
                ATHLTHLocalization.choose(
                    english: "Edit",
                    norwegian: "Rediger"
                ),
            destination:
                AnyView(
                    TrophyCollectionView(
                        startInCabinet: true
                    )
                )
        ) {
            HStack(
                alignment: .top,
                spacing: 8
            ) {
                ForEach(
                    0..<TrophyStore.showcaseLimit,
                    id: \.self
                ) { index in
                    if profileTrophySlots.indices.contains(
                        index
                    ) {
                        let trophy =
                            profileTrophySlots[
                                index
                            ]

                        NavigationLink {
                            TrophyDetailView(
                                trophyID:
                                    trophy.id
                            )
                        } label: {
                            VStack(
                                spacing: 3
                            ) {
                                ATHLTHTrophyCoreView(
                                    trophy:
                                        trophy,
                                    size: 28
                                )

                                Text(
                                    trophy.title
                                )
                                .font(
                                    .system(
                                        size: 8.0,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(
                                    0.68
                                )
                            }
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            TrophyCollectionView(
                        startInCabinet: true
                    )
                        } label: {
                            VStack(
                                spacing: 8
                            ) {
                                ZStack {
                                    ATHLTHTrophyPlateShape()
                                        .fill(
                                            Color.black
                                                .opacity(
                                                    0.035
                                                )
                                        )

                                    Image(
                                        systemName:
                                            "plus"
                                    )
                                    .font(
                                        .system(
                                            size: 13,
                                            weight: .medium
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .premiumGold
                                            .opacity(
                                                0.70
                                            )
                                    )
                                }
                                .frame(
                                    width: 28,
                                    height: 32
                                )
                                .overlay {
                                    ATHLTHTrophyPlateShape()
                                        .stroke(
                                            Color.black
                                                .opacity(
                                                    0.08
                                                ),
                                            style:
                                                StrokeStyle(
                                                    lineWidth:
                                                        1,
                                                    dash:
                                                        [
                                                            4,
                                                            4
                                                        ]
                                                )
                                        )
                                }

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Choose",
                                        norwegian:
                                            "Velg"
                                    )
                                )
                                .font(
                                    .system(
                                        size: 8.5,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var personalRecordsSection:
        some View {
        profileSection(
            title:
                ATHLTHLocalization.choose(
                    english:
                        "Personal records",
                    norwegian:
                        "Personlige rekorder"
                ),
            icon: "chart.bar.fill",
            actionTitle:
                ATHLTHLocalization.choose(
                    english: "See all",
                    norwegian: "Se alle"
                ),
            destination:
                AnyView(
                    PerformanceStatsView(
                        stats: performanceStats,
                        healthRecords: personalRecords
                    )
                )
        ) {
            HStack(spacing: 8) {
                ForEach(
                    0..<ProfileFeaturedRecordKind
                        .showcaseLimit,
                    id: \.self
                ) { index in
                    if featuredRecordKinds.indices
                        .contains(index) {
                        recordCard(
                            kind:
                                featuredRecordKinds[
                                    index
                                ]
                        )
                    } else {
                        NavigationLink {
                            ProfileRecordShowcasePickerView(
                                stats:
                                    performanceStats,
                                healthRecords:
                                    personalRecords
                            )
                            .environmentObject(
                                strengthWorkout
                            )
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
                )
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
        profileSection(
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
            if profileMedia.isEmpty &&
                recentWorkoutHighlights.isEmpty {
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
                        ForEach(
                            profileMedia
                        ) { media in
                            mediaTile(media)
                        }

                        ForEach(
                            recentWorkoutHighlights
                        ) { highlight in
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
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
        .padding(14)
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

    private func trophyBadge(
        _ trophy: TrophyProgressItem
    ) -> some View {
        let tint =
            trophyTint(
                trophy.displayRarity
            )

        return VStack(spacing: 7) {
            ZStack {
                ProfileHexagonBadgeShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.95),
                                tint.opacity(0.58)
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        )
                    )

                ProfileHexagonBadgeShape()
                    .stroke(
                        Color.white
                            .opacity(0.56),
                        lineWidth: 1
                    )

                Image(
                    systemName:
                        trophy.systemImage
                )
                .font(
                    .system(
                        size: 19,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.white)
            }
            .frame(
                width: 66,
                height: 72
            )
            .shadow(
                color:
                    tint.opacity(0.20),
                radius: 8,
                y: 4
            )

            Text(trophy.title)
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
                .minimumScaleFactor(0.70)

            Text(trophy.stageLabel)
                .font(
                    .system(
                        size: 9,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private var featuredRecordKinds:
        [ProfileFeaturedRecordKind] {
        ProfileFeaturedRecordKind
            .decodedSelection(
                from:
                    featuredRecordSelectionRaw
            )
    }

    private func recordCard(
        kind:
            ProfileFeaturedRecordKind
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            Image(
                systemName: kind.icon
            )
            .font(
                .system(
                    size: 11,
                    weight: .semibold
                )
            )
            .foregroundStyle(kind.tint)
            .frame(
                width: 24,
                height: 24
            )
            .background(
                kind.tint.opacity(0.11),
                in: RoundedRectangle(
                    cornerRadius: 8,
                    style: .continuous
                )
            )

            Text(kind.title)
                .font(
                    .system(
                        size: 8.2,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(
                kind.displayValue(
                    healthRecords:
                        personalRecords,
                    stats:
                        performanceStats,
                    strengthRecords:
                        strengthWorkout.personalRecords,
                    strengthRepRecords:
                        strengthWorkout.repPersonalRecords
                )
            )
            .font(
                .system(
                    size: 13.5,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
            .lineLimit(1)
            .minimumScaleFactor(0.58)
        }
        .padding(8)
        .frame(
            maxWidth: .infinity,
            minHeight: 72,
            alignment: .topLeading
        )
        .background(
            Color.black.opacity(0.018),
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
                kind.tint.opacity(0.09),
                lineWidth: 0.8
            )
        }
    }

    private var emptyRecordShowcaseCard:
        some View {
        VStack(spacing: 5) {
            Image(systemName: "plus")
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )

            Text(
                ATHLTHLocalization.choose(
                    english: "Choose",
                    norwegian: "Velg"
                )
            )
            .font(
                .system(
                    size: 8.5,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 58
        )
        .background(
            Color.black.opacity(0.025),
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
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.16),
                style:
                    StrokeStyle(
                        lineWidth: 1,
                        dash: [4, 4]
                    )
            )
        }
    }

    private func gearTile(
        _ item: ProfileGearItem
    ) -> some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 11,
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
                                size: 20
                            )
                        }
                    }
                } else {
                    ProfileGearCategoryIcon(
                        category:
                            item.category,
                        size: 20
                    )
                }
            }
            .frame(
                width: 38,
                height: 38
            )

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text(item.name)
                    .font(
                        .system(
                            size: 9.5,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Text(
                    item.category.shortTitle
                )
                .font(
                    .system(
                        size: 8,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
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
    }

    private func mediaTile(
        _ media: WorkoutMediaRecord
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

            if let workout =
                workoutForMedia(media) {
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
        Array(
            social.workoutMedia
                .filter { media in
                    favoriteMomentTokens
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

    private var lifetimeDistanceText:
        String {
        guard let meters =
                performanceStats?
                    .totalRunningDistanceMeters,
              meters > 0
        else {
            return "0"
        }

        let kilometers =
            meters / 1_000

        if kilometers >= 1_000 {
            return String(
                format: "%.1fk",
                kilometers / 1_000
            )
        }

        return String(
            format: "%.0f",
            kilometers
        )
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

    private func workoutForMedia(
        _ media: WorkoutMediaRecord
    ) -> WorkoutSummary? {
        health.workouts.first {
            $0.id == media.workoutID
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
    private func refreshProfile(
        forceRefresh: Bool = false
    ) async {
        guard !loadingProfileData else {
            return
        }

        loadingProfileData = true
        defer {
            loadingProfileData = false
        }

        async let socialRefresh: Void =
            social.refresh()
        async let gearRefresh: Void =
            gear.refresh()
        async let mediaRefresh: Void =
            social.refreshWorkoutMedia()

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

            let (
                loadedStats,
                loadedRecords
            ) = await (
                statsTask,
                recordsTask
            )

            performanceStats =
                loadedStats
            personalRecords =
                loadedRecords ?? []
        } else {
            performanceStats = nil
            personalRecords = []
        }

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
