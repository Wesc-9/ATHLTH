import Foundation
import SwiftUI

@main
struct ATHLTHApp: App {
    @UIApplicationDelegateAdaptor(ATHLTHAppDelegate.self)
    private var appDelegate
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var exerciseLibrary = ExerciseLibraryStore()
    @StateObject private var runningWorkoutLibrary = RunningWorkoutLibraryStore()
    @StateObject private var appSession = AppSessionStore()
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var strengthWorkout = StrengthWorkoutStore()
    @StateObject private var goals = GoalStore()
    @StateObject private var trainingBackups = TrainingBackupStore()
    @StateObject private var phoneWorkout = IPhoneWorkoutStore()
    @StateObject private var profileGear = ProfileGearStore()
    @StateObject private var notifications = ATHLTHNotificationStore()
    @StateObject private var workoutCompletion = WorkoutCompletionCoordinator()
    @StateObject private var calendarSync = AppleCalendarSyncStore()
    @StateObject private var challengeStore = ChallengeStore()
    @StateObject private var social = SocialStore()
    @StateObject private var realtimeSocial = ATHLTHRealtimeSocialStore()
    @StateObject private var messaging = MessagingStore()
    @StateObject private var communityEvents = CommunityEventStore()
    @StateObject private var officialWeeklyChallenges = OfficialWeeklyChallengeStore()
    @StateObject private var communityGroups = CommunityGroupStore()
    @StateObject private var routeDiscovery = RouteDiscoveryStore()
    @StateObject private var publicTrailDiscovery = PublicTrailDiscoveryStore()
    @StateObject private var workoutPlaceCheckIns = WorkoutPlaceCheckInStore()
    @StateObject private var libraryFavorites = LibraryFavoritesStore()
    @StateObject private var libraryRecents = LibraryRecentsStore()
    @StateObject private var trophies = TrophyStore()
    @StateObject private var spotifyPlayback = SpotifyPlaybackStore()
    @StateObject private var homeAssistant = HomeAssistantConnectionStore()
    @StateObject private var watchConnection = AppleWatchConnectionStore()
    @StateObject private var workoutMirroring = WorkoutMirroringStore()
    @StateObject private var ghostRace = GhostRaceStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var subscriptionBackend = SubscriptionBackendService()
    @StateObject private var accountService = SupabaseAccountService()
    @StateObject private var deviceRelay = WorkoutDeviceRelayStore.shared

    init() {
        let homeAssistantStore =
            HomeAssistantConnectionStore()
        let healthStore =
            HealthKitManager.shared

        _homeAssistant =
            StateObject(
                wrappedValue:
                    homeAssistantStore
            )
        _health =
            StateObject(
                wrappedValue:
                    healthStore
            )

        healthStore
            .backgroundRefreshDidComplete = {
                [weak homeAssistantStore,
                 weak healthStore] in

                guard ATHLTHDeviceRole.isIPhone,
                      let homeAssistantStore,
                      let healthStore
                else {
                    return
                }

                let backgroundTrainingLoad:
                    Double?
                if homeAssistantStore
                    .shareTrainingLoad {
                    backgroundTrainingLoad =
                        await healthStore
                            .recoveryTrendSnapshot(
                                days: 28
                            )
                            .trainingLoad
                            .ratio
                } else {
                    backgroundTrainingLoad =
                        nil
                }

                await homeAssistantStore
                    .syncBackgroundHealthSnapshot(
                        workouts:
                            healthStore.workouts,
                        sleep:
                            healthStore.sleep,
                        heart:
                            healthStore.heart,
                        training:
                            healthStore.training,
                        recoveryScore:
                            healthStore
                                .recovery
                                .score,
                        recoveryState:
                            homeAssistantRecoveryStateValue(
                                healthStore
                                    .recovery
                                    .state
                            ),
                        trainingLoad:
                            backgroundTrainingLoad
                    )
            }

        ATHLTHHomeAssistantBackgroundRefresh
            .refreshHandler = {
                [weak homeAssistantStore,
                 weak healthStore] in

                guard ATHLTHDeviceRole.isIPhone,
                      let homeAssistantStore,
                      let healthStore,
                      homeAssistantStore.isConnected
                else {
                    return false
                }

                await healthStore.refreshIfStale(
                    maxAge: 5 * 60
                )

                let backgroundTrainingLoad:
                    Double?
                if homeAssistantStore
                    .shareTrainingLoad {
                    backgroundTrainingLoad =
                        await healthStore
                            .recoveryTrendSnapshot(
                                days: 28
                            )
                            .trainingLoad
                            .ratio
                } else {
                    backgroundTrainingLoad =
                        nil
                }

                await homeAssistantStore
                    .syncBackgroundHealthSnapshot(
                        workouts: healthStore.workouts,
                        sleep: healthStore.sleep,
                        heart: healthStore.heart,
                        training: healthStore.training,
                        recoveryScore:
                            healthStore.recovery.score,
                        recoveryState:
                            homeAssistantRecoveryStateValue(
                                healthStore
                                    .recovery
                                    .state
                            ),
                        trainingLoad:
                            backgroundTrainingLoad
                    )

                return true
            }

                ATHLTHKeyboardCoordinator.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(health)
                .environmentObject(exerciseLibrary)
                .environmentObject(runningWorkoutLibrary)
                .environmentObject(appSession)
                .environmentObject(settings)
                .environmentObject(strengthWorkout)
                .environmentObject(goals)
                .environmentObject(trainingBackups)
                .environmentObject(phoneWorkout)
                .environmentObject(profileGear)
                .environmentObject(notifications)
                .environmentObject(workoutCompletion)
                .environmentObject(calendarSync)
                .environmentObject(challengeStore)
                .environmentObject(social)
                .environmentObject(realtimeSocial)
                .environmentObject(messaging)
                .environmentObject(communityEvents)
                .environmentObject(officialWeeklyChallenges)
                .environmentObject(communityGroups)
                .environmentObject(routeDiscovery)
                .environmentObject(publicTrailDiscovery)
                .environmentObject(workoutPlaceCheckIns)
                .environmentObject(libraryFavorites)
                .environmentObject(libraryRecents)
                .environmentObject(trophies)
                .environmentObject(spotifyPlayback)
                .environmentObject(homeAssistant)
                .environmentObject(watchConnection)
                .environmentObject(workoutMirroring)
                .environmentObject(ghostRace)
                .environmentObject(subscriptionStore)
                .environmentObject(subscriptionBackend)
                .environmentObject(accountService)
                .environmentObject(deviceRelay)
                .environment(
                    \.locale,
                    settings.interfaceLocale
                )
                .preferredColorScheme(.light)
                .tint(ATHLTHTheme.accent)
        }
    }
}

private struct ATHLTHLaunchGateView: View {
    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.55)
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                ATHLTHBrandMark(
                    size: .compact,
                    showTagline: false
                )

                ProgressView()
                    .controlSize(.regular)
                    .tint(
                        ATHLTHTheme.accent
                    )

                Text("Opening ATHLTH…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
            .padding(28)
        }
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            "Opening ATHLTH"
        )
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningWorkoutLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var subscriptionBackend: SubscriptionBackendService
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var trainingBackups: TrainingBackupStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var workoutCompletion: WorkoutCompletionCoordinator
    @EnvironmentObject private var calendarSync: AppleCalendarSyncStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var officialWeeklyChallenges: OfficialWeeklyChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtimeSocial: ATHLTHRealtimeSocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var communityEvents: CommunityEventStore
    @EnvironmentObject private var communityGroups: CommunityGroupStore
    @EnvironmentObject private var spotifyPlayback: SpotifyPlaybackStore
    @EnvironmentObject private var homeAssistant: HomeAssistantConnectionStore
    @EnvironmentObject private var trophies: TrophyStore
    @EnvironmentObject private var deviceRelay: WorkoutDeviceRelayStore

    @State private var authCallbackError: String?
    @State private var startupAuthenticationResolved = false
    @State private var pendingWorkoutReview: SocialPublishableWorkout?
    @State private var pendingWorkoutReviewVisibilityOverride: ProfileVisibility?
    @State private var pendingFirstWorkoutSharePrompt: SocialPublishableWorkout?
    @State private var queuedWorkoutReviewIDs: Set<UUID> = []
    @State private var lastQueuedWorkoutReview: SocialPublishableWorkout?
    @State private var lastFullLifecycleRefreshAt: Date?
    @State private var showingNotificationPermissionPrimer = false
    @State private var showingRelayedStrengthWorkout = false
    @State private var relayedWorkoutLaunchGuardUntil = Date.distantPast

    @AppStorage("athlth.notifications.permissionPrimerShown")
    private var notificationPermissionPrimerShown = false

    private let minimumLifecycleRefreshInterval:
        TimeInterval = 90

    private func handleWatchSpotifyCommand(
        _ command: WatchSpotifyCommand
    ) {
        Task { @MainActor in
            await spotifyPlayback
                .handleWatchRemoteCommand(
                    command.kind
                )
            syncSpotifyPlaybackToWatch()
        }
    }

    private func syncSpotifyPlaybackToWatch() {
        watchConnection.sendSpotifyPlaybackState(
            spotifyPlayback.watchPlaybackState
        )
    }

    private var signedInUserID: UUID? {
        appSession.signedIn
            ? appSession.profile.userID
            : nil
    }

    @MainActor
    private func processWorkoutDeviceRelayCommand(
        _ command: WorkoutDeviceRelayCommand
    ) async throws {
        guard ATHLTHDeviceRole.isIPhone else {
            return
        }

        guard Date() >= relayedWorkoutLaunchGuardUntil,
              phoneWorkout.active == nil,
              strengthWorkout.activeWorkout == nil,
              !workoutMirroring.hasActiveMirroredWorkout
        else {
            throw NSError(
                domain:
                    "ATHLTH.DeviceRelay",
                code: 409,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        ATHLTHLocalization.choose(
                            english:
                                "Another workout is already active or starting on this iPhone.",
                            norwegian:
                                "En annen økt er allerede aktiv eller i ferd med å starte på denne iPhonen."
                        )
                ]
            )
        }

        // Protect the small launch window before HealthKit mirroring or a local
        // workout store has had time to publish its active state.
        relayedWorkoutLaunchGuardUntil =
            Date().addingTimeInterval(20)

        let envelope = command.envelope
        let payload = envelope.workoutPayload
        let captureDevice =
            envelope.target.captureDevice

        switch envelope.kind {
        case .run:
            let runningWorkout =
                payload.workout
                    .resolvedRunningWorkouts
                    .first

            let mode: RunQuickStartMode
            if runningWorkout != nil {
                mode = .structured
            } else if payload.route != nil {
                mode = .route
            } else {
                mode = .free
            }

            let configuration =
                RunQuickStartConfiguration(
                    mode: mode,
                    route: payload.route,
                    workout: runningWorkout,
                    captureDevice: captureDevice,
                    environment:
                        envelope.runEnvironment ??
                        .outdoor,
                    treadmillInclinePercent:
                        envelope
                            .treadmillInclinePercent,
                    audioCoach:
                        envelope.watchAudioCoach ??
                        payload.workout
                            .audioCoachConfiguration ??
                        .disabled,
                    routeAlerts:
                        payload.routeAlerts ??
                        settings
                            .routeAlertConfiguration,
                    ghostTargetDurationSeconds:
                        envelope
                            .ghostTargetDurationSeconds,
                    ghostUpdates:
                        envelope.ghostUpdates,
                    autoPauseEnabled:
                        payload.workout
                            .autoPauseEnabled ??
                        settings
                            .autoPauseOutdoorWorkouts,
                    spotifyPlaylist:
                        envelope.spotifyPlaylist,
                    spotifyAutoplay:
                        envelope.spotifyAutoplay,
                    friends: [],
                    gearIDs:
                        Set(envelope.gearIDs)
                )

            try await WorkoutLaunchCoordinator
                .startRunQuick(
                    configuration:
                        configuration,
                    session: appSession,
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

        case .walk:
            let configuration =
                WalkQuickStartConfiguration(
                    captureDevice:
                        captureDevice,
                    audioCoach:
                        envelope.watchAudioCoach ??
                        payload.workout
                            .audioCoachConfiguration ??
                        .disabled,
                    autoPauseEnabled:
                        payload.workout
                            .autoPauseEnabled ??
                        settings
                            .autoPauseOutdoorWorkouts,
                    spotifyPlaylist:
                        envelope.spotifyPlaylist,
                    spotifyAutoplay:
                        envelope.spotifyAutoplay,
                    friends: [],
                    gearIDs:
                        Set(envelope.gearIDs)
                )

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

        case .strength:
            let trackingMode =
                payload.strengthTrackingMode ??
                .simple
            var advanced =
                payload
                    .strengthAdvancedConfiguration ??
                StrengthAdvancedConfiguration
                    .savedDefaults()

            if envelope.spotifyPlaylist != nil {
                advanced.spotifyPlaylist =
                    envelope.spotifyPlaylist
                advanced.spotifyAutoplay =
                    envelope.spotifyAutoplay
            }

            let didStart =
                try await WorkoutLaunchCoordinator
                    .startStrength(
                        workout:
                            payload
                                .recipientCopy(),
                        captureDevice:
                            captureDevice,
                        trackingMode:
                            trackingMode,
                        selectedFriends: [],
                        audioCoach:
                            envelope.watchAudioCoach ??
                            advanced
                                .audioCoach
                                .watchConfiguration,
                        advancedConfiguration:
                            advanced,
                        session:
                            appSession,
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
                showingRelayedStrengthWorkout =
                    true
            }
        }
    }

    private func startDeviceRelayIfNeeded() {
        guard
            appSession.signedIn,
            ATHLTHDeviceRole.isIPhone
        else {
            deviceRelay.stopListening()
            return
        }

        deviceRelay.startListening {
            command in
            try await self
                .processWorkoutDeviceRelayCommand(
                    command
                )
        }
    }

    private var lifecycleContent: some View {
        AnyView(
            AnyView(
                Group {
            if appSession.previewModeEnabled {
                AnyView(ProductRootTabView())
            } else if appSession.signedIn && !startupAuthenticationResolved {
                ATHLTHLaunchGateView()
            } else if !appSession.signedIn || !appSession.onboardingCompleted {
                OnboardingFlowView()
            } else {
                AnyView(ProductRootTabView())
            }
        }
        .task {
            // Compatibility preview is a CI-only rendering surface. Do not
            // compete with the first frame by starting auth, StoreKit or
            // backend work that the preview neither needs nor can use.
            if appSession.previewModeEnabled {
                startupAuthenticationResolved = true
                await Task.yield()
                return
            }

            await resolveStartupAuthentication()
            scheduleNotificationPermissionPrimerIfNeeded()

            // Give SwiftUI one render turn after authentication changes the
            // root surface. This keeps cold launch responsive on small phones
            // before secondary account/network work begins.
            await Task.yield()

            // Only the paired iPhone owns Apple Watch connectivity. iPad is a
            // controller/secondary screen and never activates WatchConnectivity.
            if ATHLTHDeviceRole.supportsDirectAppleWatch {
                watchConnection.connect()
                syncSpotifyPlaybackToWatch()
            }

            startDeviceRelayIfNeeded()

            // If Apple Watch already owns a workout, HealthKit may deliver the
            // mirroring callback just after app activation. Give that callback
            // first priority before any later Health refresh decisions.
            await allowWatchMirroringToAttachIfNeeded()

            await subscriptionStore.start()
            appSession.applyStoreKitEntitlement(subscriptionStore.activeEntitlement)
            await submitLatestStoreProofIfPossible()

            if appSession.signedIn {
                // Keep launch responsive: load only Home-critical account
                // context first and let independent network work overlap.
                async let pushToken: Void =
                    APNsPushManager.shared.syncCurrentToken()
                async let pushPreferences: Void =
                    syncPushPreferences()
                async let socialHome: Void =
                    refreshSocialHomeCore()
                async let messages: Void =
                    messaging.refresh()
                async let gearRefresh: Void =
                    gear.refresh()
                async let calendarRefresh: Void =
                    syncCalendarIfAllowed()

                _ = await (
                    pushToken,
                    pushPreferences,
                    socialHome,
                    messages,
                    gearRefresh,
                    calendarRefresh
                )

                if ATHLTHDeviceRole.isIPhone {
                    await realtimeSocial
                        .configureOnlinePresence(
                            appIsActive: true,
                            enabled:
                                social.privacy?
                                    .showOnlineStatus ??
                                true
                        )
                }
                await realtimeSocial
                    .refreshVisibleLiveSessions()
            }

            // Reconcile the app-local marker with HealthKit before deciding
            // whether Health is connected. This keeps existing permissions
            // intact across TestFlight/app updates and local defaults migrations
            // without presenting the Health permission sheet.
            _ = await health.restoreAuthorizationStateFromSystem()

            if health.needsHealthRefreshRecovery {
                // Give the UI a stable launch first. Clearing the recovery
                // latch here only affects future launches because this
                // process remains deferred until it exits.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                health.resumeAutomaticRefresh()
            }

            guard health.hasRequestedAuthorization,
                  !health.shouldDeferAutomaticHealthWork
            else {
                return
            }

            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )

            // Opening ATHLTH while the Watch owns an active workout should
            // prioritize the mirroring session. A full Health refresh can
            // wait until the workout finishes; the completion path refreshes
            // Health immediately afterwards.
            guard !workoutMirroring.hasActiveMirroredWorkout,
                  !ATHLTHWatchWorkoutRuntime
                    .isMirroredWorkoutActive
            else {
                return
            }

            await health.refreshIfStale(maxAge: 90)
            await officialWeeklyChallenges.syncCompletionState(
                workouts: health.workouts
            )
            syncAppleHealthProfileDetailsIfNeeded()
            await goals.refreshAutomaticMilestones(
                health: health,
                strength: strengthWorkout
            )
            notifications.syncGoalEvents(from: goals.goals)
            challengeStore.refreshStatuses()
            notifications.syncChallengeEvents(
                from: challengeStore.challenges,
                currentUserID: appSession.profile.userID
            )
            let startupUserID =
                appSession.profile.userID

            // Trophies and owned social snapshots are valuable but not needed
            // to make Home interactive. Let the first frame and gestures win,
            // then refresh these secondary surfaces shortly afterwards.
            Task { @MainActor in
                try? await Task.sleep(
                    for: .milliseconds(700)
                )

                guard appSession.signedIn,
                      appSession.profile.userID ==
                        startupUserID
                else {
                    return
                }

                await refreshTrophiesAndNotifications()
                await syncSocialOwnedData()
            }

            lastFullLifecycleRefreshAt = Date()
        }
        .overlay {
            if phoneWorkout.showingWorkout,
               phoneWorkout.active != nil {
                IPhoneWorkoutView()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .background(
                        Color(.systemGroupedBackground)
                            .ignoresSafeArea()
                    )
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
                    .zIndex(100)
            }
        }
        .animation(
            .easeInOut(duration: 0.20),
            value: phoneWorkout.showingWorkout
        )
        .fullScreenCover(
            isPresented:
                $showingRelayedStrengthWorkout
        ) {
            ActiveStrengthWorkoutView()
                .environmentObject(
                    strengthWorkout
                )
                .environmentObject(
                    appSession
                )
        }
        .onChange(of: watchConnection.lastSpotifyCommand) { _, command in
            guard let command else { return }
            handleWatchSpotifyCommand(command)
            watchConnection.clearSpotifyCommand()
        }
        .onChange(of: spotifyPlayback.isPlaying) { _, _ in
            syncSpotifyPlaybackToWatch()
        }
        .onChange(of: spotifyPlayback.activePlaylist?.id) { _, _ in
            syncSpotifyPlaybackToWatch()
        }
        .onChange(of: spotifyPlayback.connectionState) { _, _ in
            syncSpotifyPlaybackToWatch()
        }
        .overlay(alignment: .top) {
            if appSession.signedIn,
               phoneWorkout.active != nil,
               phoneWorkout.isUserMinimized {
                Button {
                    phoneWorkout.presentWorkout()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.run")
                            .font(
                                .system(
                                    size: 20,
                                    weight: .semibold
                                )
                            )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Return to iPhone workout",
                                norwegian:
                                    "Tilbake til iPhone-økt"
                            )
                        )
                        .font(
                            .headline
                                .weight(.semibold)
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 22)
                    .frame(height: 58)
                    .background(
                        .regularMaterial,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.black.opacity(
                                    0.05
                                ),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(0.10),
                        radius: 14,
                        y: 6
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.horizontal, 18)
                .transition(
                    .move(edge: .top)
                        .combined(with: .opacity)
                )
                .zIndex(60)
            }
        }
        .overlay(alignment: .top) {
            if ATHLTHDeviceRole.isIPad,
               let status =
                    deviceRelay.lastStatusText {
                Label(
                    status,
                    systemImage:
                        "iphone.and.arrow.forward"
                )
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    .regularMaterial,
                    in: Capsule()
                )
                .shadow(
                    radius: 10,
                    y: 4
                )
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(
                    .move(edge: .top)
                        .combined(
                            with: .opacity
                        )
                )
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value:
                deviceRelay.lastStatusText
        )
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    UIApplication
                        .didReceiveMemoryWarningNotification
            )
        ) { _ in
            ATHLTHArtworkImage
                .clearRemoteCache()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                spotifyPlayback
                    .applicationDidBecomeActive()
                startDeviceRelayIfNeeded()
            } else {
                spotifyPlayback
                    .applicationWillResignActive()
                deviceRelay.stopListening()
            }

            phoneWorkout.checkpoint()
            if phase != .active {
                strengthWorkout.checkpoint()
                appSession.checkpointTrainingContent()
            }

            if appSession.signedIn,
               ATHLTHDeviceRole.isIPhone {
                Task {
                    await realtimeSocial
                        .configureOnlinePresence(
                            appIsActive:
                                phase == .active,
                            enabled:
                                social.privacy?
                                    .showOnlineStatus ??
                                true
                        )
                }
            }

            if phase != .active,
               appSession.signedIn {
                let userID = appSession.profile.userID
                Task {
                    await trainingBackups.backUp(
                        userID: userID
                    )
                }
            }

            guard phase == .active else { return }

            // Apple Watch belongs to the paired iPhone. iPad does not query,
            // activate or present WatchConnectivity state.
            if ATHLTHDeviceRole.supportsDirectAppleWatch {
                watchConnection.connect()
            }

            if homeAssistant.isConnected,
               ATHLTHDeviceRole.isIPhone {
                ATHLTHHomeAssistantBackgroundRefresh
                    .schedule()
            }

            Task {
                if ATHLTHDeviceRole.isIPhone {
                    await deviceRelay
                        .refreshPending {
                            command in
                            try await self
                                .processWorkoutDeviceRelayCommand(
                                    command
                                )
                        }
                }
                await allowWatchMirroringToAttachIfNeeded()

                if !workoutMirroring.hasActiveMirroredWorkout,
                   !ATHLTHWatchWorkoutRuntime
                        .isMirroredWorkoutActive {
                    await resumeForegroundRefreshIfNeeded()
                }

                syncHomeAssistantWatchConfiguration()
                await syncHomeAssistantSnapshot()
            }
        }
        .onChange(of: appSession.signedIn) { _, signedIn in
            if signedIn {
                startDeviceRelayIfNeeded()
            } else {
                deviceRelay.stopListening()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for:
                    .athlthHomeAssistantCommandReceived
            )
        ) { notification in
            guard let command =
                    notification.object
                        as? HomeAssistantInboundCommand,
                  command.type == "sync_now"
            else {
                return
            }

            Task {
                await syncHomeAssistantSnapshot()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .athlthRemoteNotificationReceived
            )
        ) { _ in
            guard appSession.signedIn else { return }

            Task {
                // The backend already delivered this event through APNs.
                // Pull the authoritative inbox immediately so the Home bell
                // updates while ATHLTH is open, without scheduling a duplicate
                // local system notification for the same event.
                await refreshSocialHomeCore(
                    deliverSystemAlertsForImportedInbox: false,
                    force: true
                )
            }
        }
        .onChange(of: health.workouts.map(\.id)) { _, _ in
            guard appSession.signedIn else { return }

            Task {
                await officialWeeklyChallenges.syncCompletionState(
                    workouts: health.workouts
                )

                if let maxHR =
                    appSession.onboardingProfile?
                        .maximumHeartRateBPM {
                    await challengeStore
                        .syncHeartRateHealthWorkouts(
                            health: health,
                            userID:
                                appSession.profile.userID,
                            displayName:
                                appSession.profile.displayName,
                            maximumHeartRateBPM: maxHR
                        )
                }

                await syncHomeAssistantSnapshot()
            }
        }
        .onChange(of: health.recovery.score) { _, score in
            Task {
                if ATHLTHDeviceRole.isIPhone {
                    await homeAssistant.sendRecovery(
                        score: score
                    )
                }
                await syncHomeAssistantSnapshot()
            }
        }
        .onChange(of: health.recovery.state) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: health.sleep) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: health.heart) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: health.training) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: subscriptionStore.activeEntitlement) { _, entitlement in
            appSession.applyStoreKitEntitlement(entitlement)

            Task {
                await syncCalendarIfAllowed()
            }

            guard health.hasRequestedAuthorization else {
                return
            }

            Task {
                await health.configureBackgroundSync(
                    allowed: settings.backgroundHealthSyncEnabled
                )
            }
        }
        )
        .onChange(of: health.personalDetails) { _, details in
            guard let source = appSession.onboardingProfile?.personalDetailsSource,
                  source == .appleHealth || source == .mixed,
                  details.hasAnyValue
            else {
                return
            }

            appSession.mergePersonalDetailsFromAppleHealth(details)
        }
        .onChange(
            of: appSession.onboardingProfile?
                .maximumHeartRateBPM
        ) { _, maxHR in
            guard appSession.signedIn,
                  let maxHR
            else {
                return
            }

            Task {
                await challengeStore
                    .syncHeartRateHealthWorkouts(
                        health: health,
                        userID:
                            appSession.profile.userID,
                        displayName:
                            appSession.profile.displayName,
                        maximumHeartRateBPM: maxHR
                    )
            }
        }
        .onChange(of: settings.backgroundHealthSyncEnabled) { _, enabled in
            guard health.hasRequestedAuthorization else {
                return
            }

            Task {
                await health.configureBackgroundSync(
                    allowed: enabled
                )
            }
        }
        .onChange(of: subscriptionStore.latestTransactionProof) { _, _ in
            Task {
                await submitLatestStoreProofIfPossible()
            }
        }
        .task(
            id:
                "\(watchConnection.lastCompletedWorkout?.id.uuidString ?? "none")-\(startupAuthenticationResolved)-\(appSession.signedIn)"
        ) {
            guard startupAuthenticationResolved,
                  appSession.signedIn,
                  let result =
                    watchConnection
                        .lastCompletedWorkout
            else {
                return
            }

            handleWatchWorkoutCompletion(
                result
            )
        }
        .onChange(of: phoneWorkout.completionStartedWorkout?.id) { _, _ in
            guard let workout =
                    phoneWorkout.completionStartedWorkout
            else {
                return
            }
            capturePhoneWorkoutCompletionBaseline(
                workout
            )
        }
        .onChange(of: phoneWorkout.lastCompletedWorkout?.id) { _, _ in
            guard let workout =
                    phoneWorkout.lastCompletedWorkout
            else {
                return
            }
            handlePhoneWorkoutCompletion(workout)
        }
        .onChange(of: strengthWorkout.completedWorkout) { _, workout in
            guard let workout else { return }
            handleStrengthWorkoutCompletion(workout)
        }
        )
        .onChange(of: challengeStore.challenges) { _, updatedChallenges in
            notifications.syncChallengeEvents(
                from: updatedChallenges,
                currentUserID: appSession.profile.userID
            )

            Task {
                await social.syncChallenges(challengeStore)
                await refreshTrophiesAndNotifications()
                await syncSocialOwnedData()
            }
        }
        .onChange(of: communityEvents.events) { _, _ in
            guard appSession.signedIn else { return }

            Task {
                await syncCalendarIfAllowed()
            }
        }
        .onChange(of: communityGroups.eventsByGroup) { _, _ in
            guard appSession.signedIn else { return }

            Task {
                await syncCalendarIfAllowed()
            }
        }
        .onChange(of: communityGroups.eventRSVPsByGroup) { _, _ in
            guard appSession.signedIn else { return }

            Task {
                await syncCalendarIfAllowed()
            }
        }
        .onChange(of: goals.goals) { _, updatedGoals in
            notifications.syncGoalEvents(from: updatedGoals)

            Task {
                if social.privacy?.shareGoals == true {
                    await social.publishCompletedGoals(
                        updatedGoals,
                        visibility: settings.defaultActivityVisibility
                    )
                }
                await refreshTrophiesAndNotifications()
                await syncSocialOwnedData()
                await syncHomeAssistantSnapshot()
            }
        }
        .onChange(of: appSession.activePlan) { _, plan in
            guard appSession.signedIn else {
                return
            }

            Task {
                await syncCalendarIfAllowed(
                    plan: plan
                )
                await syncHomeAssistantSnapshot()
            }
        }
        .onChange(
            of: appSession.standalonePlannedSessions.map(\.id)
        ) { _, _ in
            Task {
                await syncHomeAssistantSnapshot()
            }
        }
        .onChange(of: appSession.profile.presence) { previous, presence in
            guard appSession.signedIn else {
                return
            }

            Task {
                guard ATHLTHDeviceRole.isIPhone else {
                    return
                }

                if presence.state == .training,
                   previous.state != .training {
                    await homeAssistant.sendWorkoutStarted(
                        name: presence.workoutTitle,
                        startedAt: presence.startedAt
                    )
                } else if previous.state == .training,
                          presence.state != .training {
                    await homeAssistant.sendWorkoutStopped()
                }

                if social.privacy?
                    .shareTrainingPresence == true {
                    await social.syncPresence(presence)
                }
            }
        }
        .onChange(of: settings.profileVisibility) { _, visibility in
            guard appSession.signedIn else { return }

            Task {
                await social.updateCorePrivacy(
                    profileVisibility: visibility,
                    shareTrainingPresence: settings.shareTrainingPresence
                )
            }
        }
        .onChange(of: settings.shareTrainingPresence) { _, sharePresence in
            guard appSession.signedIn else { return }

            Task {
                await social.updateCorePrivacy(
                    profileVisibility: settings.profileVisibility,
                    shareTrainingPresence: sharePresence
                )
            }
        }
        .onChange(of: settings.workoutRemindersEnabled) { _, _ in
            Task { await syncPushPreferences() }
        }
        .onChange(of: settings.friendActivityNotificationsEnabled) { _, _ in
            Task { await syncPushPreferences() }
        }
        .onChange(of: settings.challengeNotificationsEnabled) { _, _ in
            Task { await syncPushPreferences() }
        }
        .onChange(of: settings.messageNotificationsEnabled) { _, _ in
            Task { await syncPushPreferences() }
        }
        .onChange(of: settings.mentionNotificationsEnabled) { _, _ in
            Task { await syncPushPreferences() }
        }
        .onChange(of: social.privacy) { _, privacy in
            guard appSession.signedIn, privacy != nil else { return }

            Task {
                await syncSocialOwnedData()
            }
        }
        .environment(\.athlthImageAccountID, signedInUserID)
        .onChange(of: signedInUserID, initial: true) { _, userID in
            ATHLTHSurfaceCoordinator.clearAccountSurfaces()
            ATHLTHArtworkImage.clearRemoteCache()
            phoneWorkout.switchAccount(userID)
            trainingBackups.switchAccount(userID)
            goals.switchAccount(userID)
            strengthWorkout.switchAccount(userID)
            exerciseLibrary.switchAccount(userID)
            runningWorkoutLibrary.switchAccount(userID)
        }
        .task(id: signedInUserID) {
            guard let userID =
                    signedInUserID
            else {
                return
            }

            await runFailsafeBackupLoop(
                userID: userID
            )
        }
        .onChange(of: appSession.signedIn) { _, signedIn in
            guard signedIn else {
                Task {
                    if homeAssistant.isConnected {
                        await homeAssistant.disconnect()
                    }
                    syncHomeAssistantWatchConfiguration()
                }
                return
            }

            appSession.applyStoreKitEntitlement(subscriptionStore.activeEntitlement)
            scheduleNotificationPermissionPrimerIfNeeded()

            Task {
                await APNsPushManager.shared.syncCurrentToken()
                await syncPushPreferences()
                await submitLatestStoreProofIfPossible()
                await refreshSocialHomeCore(
                    force: true
                )
                await syncCalendarIfAllowed()
                if health.hasRequestedAuthorization {
                    await syncSocialOwnedData()
                }
                await syncHomeAssistantSnapshot()
            }
        }
        .onChange(of: homeAssistant.connectionState) { _, state in
            syncHomeAssistantWatchConfiguration()

            if ATHLTHDeviceRole.isIPhone {
                if state == .connected {
                    ATHLTHHomeAssistantBackgroundRefresh
                        .schedule()
                } else if !homeAssistant.isConnected {
                    ATHLTHHomeAssistantBackgroundRefresh
                        .cancel()
                }
            }

            guard state == .connected else {
                return
            }

            Task {
                await syncHomeAssistantSnapshot()
            }
        }
        .onChange(of: homeAssistant.shareWorkoutState) { _, _ in
            syncHomeAssistantWatchConfiguration()
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: watchConnection.state) { _, state in
            guard state == .ready else {
                return
            }
            syncHomeAssistantWatchConfiguration()
        }
        .onChange(of: homeAssistant.shareCompletedWorkouts) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareRecovery) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareTrainingLoad) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareSleep) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareHRV) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareRestingHeartRate) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareRespiratoryRate) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareWeeklyProgress) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareNextWorkout) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareTrainingCalendar) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: homeAssistant.shareGoals) { _, _ in
            Task { await syncHomeAssistantSnapshot() }
        }
        .onChange(of: appSession.onboardingCompleted) { _, completed in
            guard completed else { return }
            scheduleNotificationPermissionPrimerIfNeeded()
        }
        .background {
            ZStack {
                ATHLTHSurfaceRuntimeObserver()
                ATHLTHGhostRuntimeObserver()
                ATHLTHStrengthWatchSyncObserver()
                ATHLTHBackupDirtyObserver()
                AthleteToolsRuntimeObserver()
            }
        }
    }

    var body: some View {
        lifecycleContent
        .onOpenURL { url in
            if spotifyPlayback.handleOpenURL(url) {
                return
            }

            Task {
                do {
                    if let bootstrap = try await accountService.handleAuthCallback(url) {
                        appSession.applyBackendBootstrap(bootstrap, method: .email)
                    }
                } catch {
                    authCallbackError = error.localizedDescription
                }
            }
        }
        .onChange(of: spotifyPlayback.connectionState) { _, _ in
            settings.spotifyConnected = spotifyPlayback.isConnected
        }
        .confirmationDialog(
            "Share your first workout?",
            isPresented: Binding(
                get: { pendingFirstWorkoutSharePrompt != nil },
                set: { shown in
                    if !shown {
                        pendingFirstWorkoutSharePrompt = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Review & Share") {
                reviewFirstWorkoutForSharing()
            }

            Button("Turn On Auto Share") {
                enableAutoShareFromFirstWorkout()
            }

            Button("Keep Private") {
                keepFirstWorkoutPrivate()
            }
        } message: {
            Text(
                "Completed workouts are private by default. You can share this workout, automatically share future workouts, or keep them private. You can change this later in Settings."
            )
        }
        .sheet(isPresented: $showingNotificationPermissionPrimer) {
            ATHLTHNotificationPermissionPrimerView(
                onAllow: {
                    notificationPermissionPrimerShown = true
                    showingNotificationPermissionPrimer = false

                    Task {
                        _ = await notifications
                            .requestSystemNotificationPermissionIfNeeded()
                        await APNsPushManager.shared
                            .syncCurrentToken()
                        await syncPushPreferences()
                    }
                },
                onNotNow: {
                    notificationPermissionPrimerShown = true
                    showingNotificationPermissionPrimer = false
                }
            )
        }
        .sheet(item: $pendingWorkoutReview) { workout in
            PostWorkoutReviewView(
                workout: workout,
                wasAutoPublished: false,
                initialVisibilityOverride:
                    pendingWorkoutReviewVisibilityOverride
            )
        }
        .sheet(
            item: Binding(
                get: {
                    pendingWorkoutReview == nil
                        ? trophies.pendingReveal
                        : nil
                },
                set: { value in
                    if value == nil {
                        trophies.dismissCurrentReveal()
                    }
                }
            )
        ) { unlock in
            TrophyUnlockRevealView(unlock: unlock)
                .environmentObject(trophies)
        }
        .sheet(
            isPresented: Binding(
                get: { accountService.passwordRecoveryPending },
                set: { presented in
                    if !presented {
                        accountService.cancelPasswordRecovery()
                    }
                }
            )
        ) {
            PasswordUpdateView { bootstrap in
                appSession.applyBackendBootstrap(bootstrap, method: .email)
            }
            .environmentObject(accountService)
        }
        .alert(
            "Authentication Error",
            isPresented: Binding(
                get: { authCallbackError != nil },
                set: { presented in
                    if !presented {
                        authCallbackError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                authCallbackError = nil
            }
        } message: {
            Text(authCallbackError ?? "Authentication could not be completed.")
        }
    }


    private func syncCalendarIfAllowed(
        plan: TrainingPlan? = nil
    ) async {
        guard appSession.subscriptionAccess.hasPaidAccess,
              calendarSync.isEnabled
        else {
            return
        }

        async let eventRefresh: Void =
            communityEvents.refresh()
        async let groupCalendarRefresh: Void =
            communityGroups.refreshCalendarContent()

        _ = await (
            eventRefresh,
            groupCalendarRefresh
        )

        await calendarSync.syncIfEnabled(
            plan: plan ?? appSession.activePlan,
            communityEvents: communityEvents.events,
            groupEvents: communityGroups.calendarEvents,
            groupEventRSVPs:
                communityGroups.calendarEventRSVPs,
            challenges: challengeStore.challenges,
            currentUserID:
                appSession.profile.userID
        )
    }


    private func syncAppleHealthProfileDetailsIfNeeded() {
        guard let source = appSession.onboardingProfile?.personalDetailsSource,
              source == .appleHealth || source == .mixed,
              health.personalDetails.hasAnyValue
        else {
            return
        }

        appSession.mergePersonalDetailsFromAppleHealth(
            health.personalDetails
        )
    }

    @MainActor
    private func resolveStartupAuthentication() async {
        // UserDefaults is removed with the app, while Supabase's iOS
        // Keychain-backed session can survive an uninstall. Never use that
        // orphaned session to bypass the account/onboarding screen.
        guard appSession.signedIn else {
            await accountService
                .discardUnexpectedPersistedSession()
            startupAuthenticationResolved = true
            return
        }

        // A network/auth restoration must never leave a previously signed-in
        // user parked on the launch gate indefinitely.
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 10_000_000_000
            )

            guard !Task.isCancelled,
                  !startupAuthenticationResolved
            else {
                return
            }

            appSession.resetAuthenticationState()
            await accountService
                .discardUnexpectedPersistedSession()
            startupAuthenticationResolved = true
        }

        defer {
            timeoutTask.cancel()
            startupAuthenticationResolved = true
        }

        // Existing installs may restore silently, but the main product UI is
        // held behind ATHLTHLaunchGateView until the backend session and
        // profile have both been validated.
        do {
            guard let bootstrap =
                    try await accountService
                        .restoreCurrentUser()
            else {
                appSession.resetAuthenticationState()
                await accountService
                    .discardUnexpectedPersistedSession()
                return
            }

            // If the fallback already recovered the launch UI, ignore a late
            // backend response instead of unexpectedly switching screens.
            guard !startupAuthenticationResolved else {
                return
            }

            appSession.applyBackendBootstrap(
                bootstrap
            )
        } catch {
            // Never enter ProductRootTabView with a stale/partial profile.
            // Falling back to the login screen is safer and recoverable.
            guard !startupAuthenticationResolved else {
                return
            }

            appSession.resetAuthenticationState()
            await accountService
                .discardUnexpectedPersistedSession()
        }
    }

    private func runFailsafeBackupLoop(
        userID: UUID
    ) async {
        while !Task.isCancelled {
            try? await Task.sleep(
                for: .seconds(1_800)
            )

            guard !Task.isCancelled else {
                return
            }
            guard appSession.signedIn else {
                return
            }
            guard appSession.profile.userID ==
                    userID
            else {
                return
            }

            await trainingBackups
                .performFailsafeBackup(
                    userID: userID
                )
        }
    }

    @MainActor
    private func resumeForegroundRefreshIfNeeded()
        async {
        let now = Date()

        if let lastFullLifecycleRefreshAt,
           now.timeIntervalSince(
                lastFullLifecycleRefreshAt
           ) < minimumLifecycleRefreshInterval {
            return
        }

        lastFullLifecycleRefreshAt = now

        if appSession.signedIn {
            async let socialHome: Void =
                refreshSocialHomeCore()
            async let messages: Void =
                messaging.refresh()
            async let calendarRefresh: Void =
                syncCalendarIfAllowed()

            _ = await (
                socialHome,
                messages,
                calendarRefresh
            )
        }

        guard health.hasRequestedAuthorization,
              !health.shouldDeferAutomaticHealthWork,
              !workoutMirroring.hasActiveMirroredWorkout,
              !ATHLTHWatchWorkoutRuntime
                .isMirroredWorkoutActive
        else {
            return
        }

        await health.refreshIfStale(
            maxAge:
                minimumLifecycleRefreshInterval
        )
        await officialWeeklyChallenges
            .syncCompletionState(
                workouts: health.workouts
            )
        syncAppleHealthProfileDetailsIfNeeded()
        await goals.refreshAutomaticMilestones(
            health: health,
            strength: strengthWorkout
        )
        notifications.syncGoalEvents(
            from: goals.goals
        )
        challengeStore.refreshStatuses()
        notifications.syncChallengeEvents(
            from:
                challengeStore.challenges,
            currentUserID:
                appSession.profile.userID
        )
        await refreshTrophiesAndNotifications()
        await syncSocialOwnedData()
    }

    @MainActor
    private func allowWatchMirroringToAttachIfNeeded()
        async {
        switch watchConnection.state {
        case .unsupported,
             .notPaired,
             .appNotInstalled:
            return

        case .checking,
             .ready:
            // HealthKit can deliver workoutSessionMirroringStartHandler just
            // after the iPhone scene becomes active. Waiting here affects
            // background Health reads only; it does not block the first UI
            // frame or Watch controls.
            try? await Task.sleep(
                for: .milliseconds(550)
            )
        }
    }

    @MainActor
    private func refreshHealthAfterWatchCompletion()
        async {
        // The Watch result can beat HealthKit's mirrored-session "ended"
        // callback. Avoid launching the heavy Health query set until mirroring
        // has settled, especially the activity-summary query that caused the
        // historical app-open crash during Watch workouts.
        for _ in 0..<30 {
            if !workoutMirroring
                    .hasActiveMirroredWorkout &&
                !ATHLTHWatchWorkoutRuntime
                    .isMirroredWorkoutActive {
                await health.refreshAll()
                return
            }

            try? await Task.sleep(
                for: .milliseconds(100)
            )
        }

        // Do not force Health queries through an active/stale mirror flag.
        // The next scene activation/background delivery will retry safely.
    }

    @MainActor
    private func handleWatchWorkoutCompletion(
        _ result: WatchWorkoutResult
    ) {
        // A completed Watch result is authoritative evidence that the matching
        // mirrored workout has ended, even if HealthKit's mirror callback is
        // a fraction of a second late.
        workoutMirroring
            .reconcileCompletedWatchWorkout(
                result
            )

        // A standalone Watch can complete an entire strength session without
        // iPhone or internet. Recreate the local ATHLTH strength log from the
        // embedded prescription and replay the durable Watch action journal
        // before the ordinary completion path attaches HealthKit metrics.
        if result.kind == .strength,
           let snapshot =
                result.strengthSnapshot {
            let alreadyCompleted =
                strengthWorkout
                    .completedWorkout?
                    .id ==
                snapshot.workoutID

            if strengthWorkout.activeWorkout == nil,
               !alreadyCompleted {
                strengthWorkout
                    .startFromWatchSnapshot(
                        snapshot,
                        watchSessionID:
                            result.id
                    )
            }

            if strengthWorkout.activeWorkout?
                    .id ==
                snapshot.workoutID {
                strengthWorkout
                    .replayOfflineWatchCommands(
                        result
                            .strengthCommands ??
                        []
                    )
            }
        }

        let watchFinishedActiveStrength =
            result.kind == .strength &&
            strengthWorkout.activeWorkout?
                .captureDevice == .appleWatch

        let watchMatchesCompletedStrength =
            result.kind == .strength &&
            strengthWorkout.completedWorkout?
                .captureDevice == .appleWatch &&
            strengthWorkout.completedWorkout.map {
                abs(
                    result.endedAt.timeIntervalSince(
                        $0.endedAt ??
                        result.endedAt
                    )
                ) < 180
            } == true

        let watchBelongsToATHLTHStrength =
            watchFinishedActiveStrength ||
            watchMatchesCompletedStrength

        if watchBelongsToATHLTHStrength {
            let metrics =
                LinkedHealthWorkoutMetrics(
                    healthKitWorkoutUUID:
                        result
                            .healthKitWorkoutUUID,
                    duration: result.duration,
                    activeCalories:
                        result.activeCalories,
                    averageHeartRate:
                        result.averageHeartRate,
                    maxHeartRate:
                        result.maxHeartRate
                )

            if watchFinishedActiveStrength {
                // This transition publishes completedWorkout. The regular
                // strength completion handler below is therefore the single
                // owner of review, challenges, social, gear and trophies.
                strengthWorkout.finish(
                    healthKitWorkoutUUID:
                        metrics
                            .healthKitWorkoutUUID,
                    duration:
                        metrics.duration,
                    activeCalories:
                        metrics.activeCalories,
                    averageHeartRate:
                        metrics.averageHeartRate,
                    maxHeartRate:
                        metrics.maxHeartRate
                )
                appSession.endTrainingStatus()
            } else {
                strengthWorkout
                    .attachHealthMetrics(
                        metrics
                    )
            }

            // The strength completion handler owns every downstream side
            // effect, including the post-Watch Health refresh. The raw Watch
            // result is now fully consumed.
            watchConnection
                .clearCompletedWorkout()
            return
        }

        // Workouts started directly on Watch, or Watch workouts that are not
        // backed by an ATHLTH strength log, use the generic Watch pipeline.
        let publishable =
            SocialPublishableWorkout(
                watchResult: result
            )
        var completionSourceIDs:
            Set<UUID> = [result.id]

        if let healthKitWorkoutUUID =
                result.healthKitWorkoutUUID {
            completionSourceIDs.insert(
                healthKitWorkoutUUID
            )
        }

        workoutCompletion.begin(
            workout: publishable,
            sourceIDs: completionSourceIDs,
            goals: goals,
            challenges: challengeStore,
            officialWeekly:
                officialWeeklyChallenges,
            healthWorkouts: health.workouts,
            gear: gear,
            trophies: trophies
        )

        notifications
            .recordWatchWorkout(result)

        Task { @MainActor in
            await homeAssistant.sendCompletedWorkout(
                name: publishable.title,
                type: publishable.activity.rawValue,
                startedAt: publishable.startDate,
                endedAt: publishable.endDate,
                duration: publishable.duration,
                distanceMeters: publishable.distanceMeters,
                device: "Apple Watch"
            )

            await refreshHealthAfterWatchCompletion()

            await officialWeeklyChallenges
                .syncCompletionState(
                    workouts: health.workouts
                )
            syncAppleHealthProfileDetailsIfNeeded()

            await goals
                .refreshAutomaticMilestones(
                    health: health,
                    strength:
                        strengthWorkout
                )
            notifications.syncGoalEvents(
                from: goals.goals
            )

            await challengeStore
                .ingestWatchWorkout(
                    result,
                    health: health,
                    userID:
                        appSession.profile
                            .userID,
                    displayName:
                        appSession.profile
                            .displayName,
                    maximumHeartRateBPM:
                        appSession
                            .onboardingProfile?
                            .maximumHeartRateBPM
                )

            await realtimeSocial
                .finishCurrentLiveGhostRace(
                    elapsedSeconds:
                        result.duration
                )

            await social.finishActiveWorkout(
                sourceWorkoutID:
                    result
                        .healthKitWorkoutUUID ??
                    result.id,
                endedAt: result.endedAt
            )

            await gear.savePreparedGearUsage(
                for: publishable
            )
            await communityGroups
                .recordCompletedWorkout(
                    publishable
                )
            notifications
                .syncGearUsageAlerts(
                    from: gear
                )

            finalizeWorkoutCompletionImpact(
                workout: publishable,
                sourceIDs:
                    completionSourceIDs
            )

            await handleCompletedWorkoutReview(
                publishable
            )
            await refreshTrophiesAndNotifications()

            finalizeWorkoutCompletionImpact(
                workout: publishable,
                sourceIDs:
                    completionSourceIDs
            )

            await social.syncChallenges(
                challengeStore
            )
            await syncSocialOwnedData()
            watchConnection
                .clearCompletedWorkout()
        }
    }

    @MainActor
    private func capturePhoneWorkoutCompletionBaseline(
        _ workout: PhoneWorkout
    ) {
        guard appSession.signedIn else {
            return
        }

        let publishable =
            SocialPublishableWorkout(
                phoneWorkout: workout
            )

        workoutCompletion.begin(
            workout: publishable,
            baselineKey: workout.id,
            sourceIDs: [workout.id],
            goals: goals,
            challenges: challengeStore,
            officialWeekly:
                officialWeeklyChallenges,
            healthWorkouts: health.workouts,
            gear: gear,
            trophies: trophies
        )
    }

    @MainActor
    private func handlePhoneWorkoutCompletion(
        _ workout: PhoneWorkout
    ) {
        guard let endedAt = workout.end,
              appSession.signedIn
        else {
            return
        }

        let publishable =
            SocialPublishableWorkout(
                phoneWorkout: workout
            )
        var completionSourceIDs: Set<UUID> = [
            workout.id
        ]
        if let healthID = workout.healthID {
            completionSourceIDs.insert(
                healthID
            )
        }

        workoutCompletion.begin(
            workout: publishable,
            baselineKey: workout.id,
            sourceIDs: completionSourceIDs,
            goals: goals,
            challenges: challengeStore,
            officialWeekly:
                officialWeeklyChallenges,
            healthWorkouts: health.workouts,
            gear: gear,
            trophies: trophies
        )

        Task {
            await homeAssistant.sendCompletedWorkout(
                name: publishable.title,
                type: publishable.activity.rawValue,
                startedAt: publishable.startDate,
                endedAt: publishable.endDate,
                duration: publishable.duration,
                distanceMeters: publishable.distanceMeters
            )

            await officialWeeklyChallenges
                .syncCompletionState(
                    workouts: health.workouts
                )

            await goals.refreshAutomaticMilestones(
                health: health,
                strength: strengthWorkout
            )
            notifications.syncGoalEvents(
                from: goals.goals
            )

            let challengeResult =
                WatchWorkoutResult(
                    id: workout.id,
                    kind:
                        workout.walking
                            ? .walking
                            : .running,
                    healthKitWorkoutUUID:
                        workout.healthID,
                    startedAt: workout.start,
                    endedAt: endedAt,
                    duration:
                        publishable.duration,
                    activeCalories: 0,
                    distanceMeters:
                        workout.distanceMeters,
                    averageHeartRate: nil,
                    maxHeartRate: nil,
                    routePointCount:
                        workout.points.count
                )

            await challengeStore
                .ingestWatchWorkout(
                    challengeResult,
                    health: health,
                    userID:
                        appSession.profile.userID,
                    displayName:
                        appSession.profile.displayName,
                    maximumHeartRateBPM:
                        appSession
                            .onboardingProfile?
                            .maximumHeartRateBPM
                )

            await realtimeSocial
                .finishCurrentLiveGhostRace(
                    elapsedSeconds:
                        publishable.duration
                )

            await social.finishActiveWorkout(
                sourceWorkoutID:
                    workout.healthID ??
                    workout.id,
                endedAt: endedAt
            )

            await gear.savePreparedGearUsage(
                for: publishable
            )
            await communityGroups
                .recordCompletedWorkout(
                    publishable
                )
            notifications.syncGearUsageAlerts(
                from: gear
            )

            finalizeWorkoutCompletionImpact(
                workout: publishable,
                baselineKey: workout.id,
                sourceIDs: completionSourceIDs
            )

            await handleCompletedWorkoutReview(
                publishable
            )
            await social.syncChallenges(
                challengeStore
            )
            await refreshTrophiesAndNotifications()

            finalizeWorkoutCompletionImpact(
                workout: publishable,
                baselineKey: workout.id,
                sourceIDs: completionSourceIDs
            )

            await syncSocialOwnedData()
        }
    }

    @MainActor
    private func handleStrengthWorkoutCompletion(
        _ workout: StrengthWorkoutLog
    ) {
        let publishable =
            SocialPublishableWorkout(
                strengthWorkout: workout
            )
        var completionSourceIDs: Set<UUID> = [
            workout.id
        ]

        if let healthKitWorkoutUUID =
                workout.healthMetrics
                    .healthKitWorkoutUUID {
            completionSourceIDs.insert(
                healthKitWorkoutUUID
            )
        }

        workoutCompletion.begin(
            workout: publishable,
            sourceIDs: completionSourceIDs,
            goals: goals,
            challenges: challengeStore,
            officialWeekly:
                officialWeeklyChallenges,
            healthWorkouts: health.workouts,
            gear: gear,
            trophies: trophies
        )

        appSession.applyStrengthProgression(
            from: workout
        )
        notifications.recordStrengthWorkout(
            workout
        )
        challengeStore.ingestStrengthWorkout(
            workout,
            userID: appSession.profile.userID,
            displayName:
                appSession.profile.displayName
        )

        Task {
            await homeAssistant.sendCompletedWorkout(
                name: publishable.title,
                type: publishable.activity.rawValue,
                startedAt: publishable.startDate,
                endedAt: publishable.endDate,
                duration: publishable.duration,
                distanceMeters: publishable.distanceMeters,
                device:
                    workout.captureDevice == .appleWatch
                        ? "Apple Watch"
                        : "iPhone"
            )

            if workout.captureDevice == .appleWatch {
                await refreshHealthAfterWatchCompletion()
                await officialWeeklyChallenges
                    .syncCompletionState(
                        workouts:
                            health.workouts
                    )
                syncAppleHealthProfileDetailsIfNeeded()
            } else if workout.captureDevice == .iPhone,
               workout.healthMetrics
                    .healthKitWorkoutUUID == nil,
               let endedAt = workout.endedAt {
                _ = await health
                    .saveManualStrengthWorkout(
                        startDate:
                            workout.startedAt,
                        endDate: endedAt,
                        externalID: workout.id
                    )
                await health.refreshAll()
            }

            await goals.refreshAutomaticMilestones(
                health: health,
                strength: strengthWorkout
            )
            notifications.syncGoalEvents(
                from: goals.goals
            )

            if let endedAt = workout.endedAt {
                await social.finishActiveWorkout(
                    sourceWorkoutID:
                        workout.healthMetrics
                            .healthKitWorkoutUUID ??
                        workout.id,
                    endedAt: endedAt
                )
            }

            await gear.savePreparedGearUsage(
                for: publishable
            )
            await communityGroups
                .recordCompletedWorkout(
                    publishable
                )
            notifications.syncGearUsageAlerts(
                from: gear
            )

            finalizeWorkoutCompletionImpact(
                workout: publishable,
                sourceIDs: completionSourceIDs
            )

            await handleCompletedWorkoutReview(
                publishable
            )
            await social.syncChallenges(
                challengeStore
            )
            await refreshTrophiesAndNotifications()

            finalizeWorkoutCompletionImpact(
                workout: publishable,
                sourceIDs: completionSourceIDs
            )

            await syncSocialOwnedData()
        }
    }

    @MainActor
    private func finalizeWorkoutCompletionImpact(
        workout: SocialPublishableWorkout,
        baselineKey: UUID? = nil,
        sourceIDs: Set<UUID>
    ) {
        workoutCompletion.finalize(
            workout: workout,
            baselineKey: baselineKey,
            sourceIDs: sourceIDs,
            userID: appSession.profile.userID,
            goals: goals,
            challenges: challengeStore,
            officialWeekly:
                officialWeeklyChallenges,
            healthWorkouts: health.workouts,
            gear: gear,
            trophies: trophies
        )
    }

    private func handleCompletedWorkoutReview(
        _ workout: SocialPublishableWorkout
    ) async {
        guard !queuedWorkoutReviewIDs.contains(workout.id) else {
            return
        }

        if let lastQueuedWorkoutReview,
           lastQueuedWorkoutReview.activity == workout.activity,
           abs(
               lastQueuedWorkoutReview.endDate.timeIntervalSince(workout.endDate)
           ) < 90 {
            return
        }

        queuedWorkoutReviewIDs.insert(workout.id)
        lastQueuedWorkoutReview = workout

        if !settings.workoutSharingChoiceCompleted &&
            !settings.autoPublishCompletedWorkouts {
            pendingFirstWorkoutSharePrompt = workout
            return
        }

        pendingWorkoutReviewVisibilityOverride =
            settings.autoPublishCompletedWorkouts
                ? settings.defaultActivityVisibility
                : nil

        // Always show the post-workout review before anything is shared.
        // The auto-share preference only chooses the default visibility.
        pendingWorkoutReview = workout
    }

    @MainActor
    private func reviewFirstWorkoutForSharing() {
        guard let workout = pendingFirstWorkoutSharePrompt else {
            return
        }

        settings.workoutSharingChoiceCompleted = true
        pendingFirstWorkoutSharePrompt = nil
        pendingWorkoutReviewVisibilityOverride = .friends
        pendingWorkoutReview = workout
    }

    @MainActor
    private func keepFirstWorkoutPrivate() {
        guard let workout = pendingFirstWorkoutSharePrompt else {
            return
        }

        settings.workoutSharingChoiceCompleted = true
        settings.autoPublishCompletedWorkouts = false
        pendingFirstWorkoutSharePrompt = nil
        pendingWorkoutReviewVisibilityOverride = .privateOnly
        pendingWorkoutReview = workout
    }

    @MainActor
    private func enableAutoShareFromFirstWorkout() {
        guard let workout = pendingFirstWorkoutSharePrompt else {
            return
        }

        settings.workoutSharingChoiceCompleted = true
        settings.autoPublishCompletedWorkouts = true

        if settings.defaultActivityVisibility == .privateOnly {
            settings.defaultActivityVisibility = .friends
        }

        let visibility = settings.defaultActivityVisibility
        pendingFirstWorkoutSharePrompt = nil
        pendingWorkoutReviewVisibilityOverride = visibility

        // Keep review mandatory. Nothing is published until the user
        // confirms the completed workout from the review screen.
        pendingWorkoutReview = workout
    }

    private func refreshSocialHomeCore(
        deliverSystemAlertsForImportedInbox: Bool = true,
        force: Bool = false
    ) async {
        await social.refreshHomeContext(
            notificationStore: notifications,
            deliverSystemAlertsForImportedInbox:
                deliverSystemAlertsForImportedInbox,
            force: force
        )

        if let privacy = social.privacy {
            if let visibility = ProfileVisibility(
                rawValue: privacy.profileVisibility
            ) {
                settings.profileVisibility = visibility
            }
            settings.shareTrainingPresence =
                privacy.shareTrainingPresence
        }

        if social.privacy?.shareTrainingPresence == true {
            await social.syncPresence(
                appSession.profile.presence
            )
        }
    }

    private func refreshSocialCore(
        deliverSystemAlertsForImportedInbox: Bool = true
    ) async {
        await social.refresh(
            challengeStore: challengeStore,
            notificationStore: notifications,
            deliverSystemAlertsForImportedInbox:
                deliverSystemAlertsForImportedInbox
        )

        // Supabase social privacy is authoritative once the account is loaded.
        // Mirror the backend values into local settings instead of overwriting
        // server privacy from stale device defaults on every refresh.
        if let privacy = social.privacy {
            if let visibility = ProfileVisibility(rawValue: privacy.profileVisibility) {
                settings.profileVisibility = visibility
            }
            settings.shareTrainingPresence = privacy.shareTrainingPresence
        }

        if ATHLTHDeviceRole.isIPhone,
           social.privacy?.shareTrainingPresence == true {
            await social.syncPresence(appSession.profile.presence)
        }
    }

    private func syncSocialOwnedData() async {
        guard appSession.signedIn,
              let privacy = social.privacy
        else {
            return
        }

        if ATHLTHDeviceRole.isIPhone {
            if privacy.sharePerformanceStats,
               let stats =
                    try? await health
                        .profilePerformanceStats() {
                await social
                    .syncOwnPerformance(stats)
            }

            if privacy.shareRunningPRs,
               let runningRecords =
                    try? await health
                        .personalRecords() {
                await social
                    .publishRunningPersonalRecords(
                        runningRecords,
                        visibility:
                            settings
                                .defaultActivityVisibility
                    )
            }

            if privacy.shareStrengthPRs {
                await social
                    .publishStrengthRepPersonalRecords(
                        strengthWorkout
                            .repPersonalRecords,
                        visibility:
                            settings
                                .defaultActivityVisibility
                    )
            }

            if privacy.shareTrophyCabinet {
                await social.syncOwnTrophies(
                    trophies.showcaseTrophies
                )

                if privacy.shareRecentActivity {
                    await social
                        .publishTrophyUnlocks(
                            trophies.unlocks,
                            visibility:
                                settings
                                    .defaultActivityVisibility
                        )
                }
            }
        }

        await social.syncChallenges(challengeStore)
    }

    @MainActor
    private func scheduleNotificationPermissionPrimerIfNeeded() {
        guard !notificationPermissionPrimerShown,
              !showingNotificationPermissionPrimer,
              !appSession.previewModeEnabled,
              appSession.signedIn,
              appSession.onboardingCompleted
        else {
            return
        }

        Task { @MainActor in
            await notifications.refreshAuthorizationStatus()

            guard !notificationPermissionPrimerShown,
                  !showingNotificationPermissionPrimer,
                  appSession.signedIn,
                  appSession.onboardingCompleted,
                  notifications.authorizationStatus == .notDetermined
            else {
                return
            }

            try? await Task.sleep(
                for: .milliseconds(650)
            )

            guard !notificationPermissionPrimerShown,
                  appSession.signedIn,
                  appSession.onboardingCompleted,
                  notifications.authorizationStatus == .notDetermined
            else {
                return
            }

            showingNotificationPermissionPrimer = true
        }
    }

    private func refreshTrophiesAndNotifications() async {
        await trophies.refresh(
            health: health,
            strength: strengthWorkout,
            goals: goals,
            challenges: challengeStore,
            currentUserID: appSession.profile.userID,
            username:
                appSession.profile.username
        )
        notifications.syncTrophyEvents(from: trophies.unlocks)
    }

    @MainActor
    private func syncHomeAssistantWatchConfiguration() {
        watchConnection.sendHomeAssistantConfiguration(
            homeAssistant.watchConfiguration
        )
    }

    @MainActor
    private func syncHomeAssistantSnapshot() async {
        guard ATHLTHDeviceRole.isIPhone,
              appSession.signedIn,
              homeAssistant.isConnected
        else {
            return
        }

        let latestWorkout =
            health.workouts.max {
                $0.startDate < $1.startDate
            }

        let trainingLoad: Double?
        if homeAssistant.shareTrainingLoad {
            trainingLoad =
                await health
                    .recoveryTrendSnapshot(
                        days: 28
                    )
                    .trainingLoad
                    .ratio
        } else {
            trainingLoad = nil
        }

        let presence =
            appSession.profile.presence
        let nextWorkout =
            homeAssistantNextWorkoutOccurrence()
        let weeklyMetrics =
            homeAssistantWeeklyTrainingMetrics()
        let primaryGoal =
            goals.primaryGoal ??
            goals.activeGoals.first
        let goalDaysRemaining =
            homeAssistantGoalDaysRemaining(
                primaryGoal
            )

        await homeAssistant.syncSnapshot(
            workoutActive:
                presence.state == .training,
            activeWorkout:
                presence.state == .training
                    ? presence.workoutTitle
                    : nil,
            activeWorkoutStartedAt:
                presence.state == .training
                    ? presence.startedAt
                    : nil,
            lastWorkout:
                latestWorkout?
                    .activity
                    .rawValue,
            recoveryScore:
                health.recovery.score,
            trainingLoad:
                trainingLoad,
            sleepDurationMinutes:
                health.sleep.totalAsleep > 0
                    ? health.sleep.totalAsleep / 60
                    : nil,
            hrvMilliseconds:
                health.heart.hrvMilliseconds,
            restingHeartRate:
                health.heart.restingHeartRate,
            respiratoryRate:
                health.training.respiratoryRate,
            recoveryState:
                homeAssistantRecoveryStateValue(
                    health.recovery.state
                ),
            weeklyProgress:
                homeAssistantWeeklyProgress(),
            weeklyTrainingMinutes:
                weeklyMetrics.minutes,
            weeklyDistanceKilometers:
                weeklyMetrics.distanceKilometers,
            weeklyWorkoutCount:
                weeklyMetrics.workoutCount,
            trainingStreak:
                homeAssistantTrainingStreak(),
            nextWorkout:
                nextWorkout?.title,
            nextWorkoutTime:
                nextWorkout?.time,
            activeGoal:
                primaryGoal?.title,
            goalProgress:
                primaryGoal.map {
                    $0.progress * 100
                },
            goalDaysRemaining:
                goalDaysRemaining,
            calendarEvents:
                homeAssistantCalendarEvents()
        )
    }

    private func homeAssistantPlannedOccurrences()
        -> [
            (
                planID: UUID?,
                session: PlannedSession
            )
        ] {
        var plansByID: [UUID: TrainingPlan] = [:]

        if let activePlan =
                appSession.activePlan {
            plansByID[activePlan.id] =
                activePlan
        }

        for plan in appSession.scheduledPlans {
            plansByID[plan.id] = plan
        }

        var occurrences:
            [
                (
                    planID: UUID?,
                    session: PlannedSession
                )
            ] = []

        for plan in plansByID.values {
            for session in
                plan.weeks
                    .flatMap(\.days)
                    .flatMap(\.sessions) {
                occurrences.append(
                    (
                        planID: plan.id,
                        session: session
                    )
                )
            }
        }

        occurrences.append(
            contentsOf:
                appSession
                    .standalonePlannedSessions
                    .map {
                        (
                            planID: nil,
                            session: $0
                        )
                    }
        )

        return occurrences
    }

    private func homeAssistantNextWorkoutOccurrence()
        -> (title: String, time: Date)? {
        let now = Date()

        let candidates =
            homeAssistantPlannedOccurrences()
                .filter { occurrence in
                    guard let start =
                            occurrence.session
                                .scheduledStart,
                          start >= now
                    else {
                        return false
                    }

                    if let planID =
                            occurrence.planID {
                        if appSession
                            .isPlanSessionSkipped(
                                planID: planID,
                                sessionID:
                                    occurrence
                                        .session
                                        .id
                            ) {
                            return false
                        }

                        if appSession
                            .isPlanSessionManuallyCompleted(
                                planID: planID,
                                sessionID:
                                    occurrence
                                        .session
                                        .id
                            ) {
                            return false
                        }
                    }

                    return true
                }
                .sorted { lhs, rhs in
                    let lhsStart =
                        lhs.session
                            .scheduledStart ??
                        .distantFuture
                    let rhsStart =
                        rhs.session
                            .scheduledStart ??
                        .distantFuture
                    return lhsStart < rhsStart
                }

        guard let occurrence =
                candidates.first
        else {
            return nil
        }

        guard let start =
                occurrence.session
                    .scheduledStart
        else {
            return nil
        }

        return (
            occurrence.session.title,
            start
        )
    }

    private func homeAssistantWeeklyTrainingMetrics()
        -> (
            minutes: Double,
            distanceKilometers: Double,
            workoutCount: Int
        ) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        guard let week =
                calendar.dateInterval(
                    of: .weekOfYear,
                    for: Date()
                )
        else {
            return (0, 0, 0)
        }

        let workouts =
            health.workouts.filter {
                week.contains($0.startDate)
            }

        let totalSeconds =
            workouts.reduce(0.0) {
                $0 + max($1.duration, 0)
            }
        let totalMeters =
            workouts.reduce(0.0) {
                $0 + max($1.distanceMeters ?? 0, 0)
            }

        return (
            minutes: totalSeconds / 60,
            distanceKilometers: totalMeters / 1_000,
            workoutCount: workouts.count
        )
    }

    private func homeAssistantTrainingStreak() -> Int {
        let calendar = Calendar.current
        let workoutDays =
            Set(
                health.workouts.map {
                    calendar.startOfDay(
                        for: $0.startDate
                    )
                }
            )

        guard !workoutDays.isEmpty else {
            return 0
        }

        let today =
            calendar.startOfDay(
                for: Date()
            )
        let yesterday =
            calendar.date(
                byAdding: .day,
                value: -1,
                to: today
            ) ?? today

        var cursor: Date
        if workoutDays.contains(today) {
            cursor = today
        } else if workoutDays.contains(
                    yesterday
                  ) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while workoutDays.contains(cursor) {
            streak += 1
            guard let previous =
                    calendar.date(
                        byAdding: .day,
                        value: -1,
                        to: cursor
                    )
            else {
                break
            }
            cursor = previous
        }

        return streak
    }

    private func homeAssistantGoalDaysRemaining(
        _ goal: ATHLTHGoal?
    ) -> Int? {
        guard let deadline =
                goal?.deadline
        else {
            return nil
        }

        let calendar = Calendar.current
        let today =
            calendar.startOfDay(
                for: Date()
            )
        let end =
            calendar.startOfDay(
                for: deadline
            )

        return max(
            calendar.dateComponents(
                [.day],
                from: today,
                to: end
            ).day ?? 0,
            0
        )
    }

    private func homeAssistantCalendarEvents()
        -> [HomeAssistantCalendarEventPayload] {
        let now = Date()
        let lowerBound =
            Calendar.current.date(
                byAdding: .day,
                value: -7,
                to: now
            ) ?? now
        let upperBound =
            Calendar.current.date(
                byAdding: .day,
                value: 90,
                to: now
            ) ?? now

        return homeAssistantPlannedOccurrences()
            .compactMap { occurrence in
                guard let start =
                        occurrence
                            .session
                            .scheduledStart,
                      start >= lowerBound,
                      start <= upperBound
                else {
                    return nil
                }

                if let planID =
                        occurrence.planID {
                    if appSession
                        .isPlanSessionSkipped(
                            planID: planID,
                            sessionID:
                                occurrence
                                    .session
                                    .id
                        ) {
                        return nil
                    }
                }

                let duration =
                    max(
                        occurrence
                            .session
                            .durationMinutes ??
                            60,
                        1
                    )
                let end =
                    Calendar.current.date(
                        byAdding: .minute,
                        value: duration,
                        to: start
                    ) ??
                    start.addingTimeInterval(
                        Double(duration) * 60
                    )

                return HomeAssistantCalendarEventPayload(
                    id:
                        occurrence
                            .session
                            .id
                            .uuidString,
                    title:
                        occurrence
                            .session
                            .title,
                    start: start,
                    end: end,
                    type:
                        occurrence
                            .session
                            .kind
                            .rawValue
                )
            }
            .sorted {
                $0.start < $1.start
            }
            .prefix(64)
            .map { $0 }
    }

    private func homeAssistantWeeklyProgress()
        -> Double? {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        guard let week =
                calendar.dateInterval(
                    of: .weekOfYear,
                    for: Date()
                )
        else {
            return nil
        }

        var remainingActual =
            health.workouts
                .filter {
                    week.contains(
                        $0.startDate
                    )
                }

        var completed = 0
        var unfinished = 0

        let planned =
            homeAssistantPlannedOccurrences()
                .filter {
                    guard let start =
                            $0.session
                                .scheduledStart
                    else {
                        return false
                    }
                    return week.contains(start)
                }
                .sorted {
                    (
                        $0.session
                            .scheduledStart ??
                        .distantFuture
                    ) <
                    (
                        $1.session
                            .scheduledStart ??
                        .distantFuture
                    )
                }

        for occurrence in planned {
            if let planID = occurrence.planID {
                if appSession
                    .isPlanSessionSkipped(
                        planID: planID,
                        sessionID:
                            occurrence.session.id
                    ) {
                    continue
                }

                if appSession
                    .isPlanSessionManuallyCompleted(
                        planID: planID,
                        sessionID:
                            occurrence.session.id
                    ) {
                    completed += 1
                    continue
                }
            }

            if let index =
                    remainingActual
                        .firstIndex(
                            where: {
                                homeAssistantWorkout(
                                    $0,
                                    matches:
                                        occurrence
                                            .session,
                                    calendar:
                                        calendar
                                )
                            }
                        ) {
                completed += 1
                remainingActual.remove(
                    at: index
                )
            } else {
                unfinished += 1
            }
        }

        completed += remainingActual.count
        let total = completed + unfinished

        guard total > 0 else {
            return 0
        }

        return min(
            max(
                Double(completed) /
                    Double(total) *
                    100,
                0
            ),
            100
        )
    }

    private func homeAssistantWorkout(
        _ workout: WorkoutSummary,
        matches planned: PlannedSession,
        calendar: Calendar
    ) -> Bool {
        guard let start =
                planned.scheduledStart,
              calendar.isDate(
                workout.startDate,
                inSameDayAs: start
              )
        else {
            return false
        }

        switch planned.kind {
        case .running:
            return workout.activity ==
                .running
        case .walking:
            return workout.activity ==
                .walking ||
                workout.activity ==
                    .hiking
        case .strength:
            return workout.activity ==
                .strength
        case .mobility:
            return workout.activity ==
                .yoga ||
                workout.activity ==
                    .coreTraining
        case .recovery:
            return false
        case .custom:
            return workout.activity ==
                .hiit ||
                workout.activity ==
                    .rowing ||
                workout.activity ==
                    .cycling ||
                workout.activity ==
                    .stairClimbing ||
                workout.activity ==
                    .other
        }
    }

    private func syncPushPreferences() async {
        guard appSession.signedIn else { return }

        await APNsPushManager.shared.syncNotificationPreferences(
            workoutUpdates: settings.workoutRemindersEnabled,
            friendActivity: settings.friendActivityNotificationsEnabled,
            challenges: settings.challengeNotificationsEnabled,
            messages: settings.messageNotificationsEnabled,
            mentions: settings.mentionNotificationsEnabled
        )
    }

    private func submitLatestStoreProofIfPossible() async {
        guard appSession.signedIn,
              let proof = subscriptionStore.latestTransactionProof
        else {
            return
        }

        do {
            try await subscriptionBackend.submit(proof)

            if let bootstrap = try? await accountService.loadCurrentUser() {
                appSession.applyBackendBootstrap(bootstrap)
            }
        } catch {
            return
        }
    }
}
