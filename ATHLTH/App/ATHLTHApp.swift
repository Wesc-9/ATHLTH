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
    @StateObject private var watchConnection = AppleWatchConnectionStore()
    @StateObject private var workoutMirroring = WorkoutMirroringStore()
    @StateObject private var ghostRace = GhostRaceStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var subscriptionBackend = SubscriptionBackendService()
    @StateObject private var accountService = SupabaseAccountService()

    init() {
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
                .environmentObject(watchConnection)
                .environmentObject(workoutMirroring)
                .environmentObject(ghostRace)
                .environmentObject(subscriptionStore)
                .environmentObject(subscriptionBackend)
                .environmentObject(accountService)
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
    @EnvironmentObject private var trophies: TrophyStore

    @State private var authCallbackError: String?
    @State private var startupAuthenticationResolved = false
    @State private var pendingWorkoutReview: SocialPublishableWorkout?
    @State private var pendingWorkoutReviewVisibilityOverride: ProfileVisibility?
    @State private var pendingFirstWorkoutSharePrompt: SocialPublishableWorkout?
    @State private var queuedWorkoutReviewIDs: Set<UUID> = []
    @State private var lastQueuedWorkoutReview: SocialPublishableWorkout?
    @State private var lastFullLifecycleRefreshAt: Date?
    @State private var showingNotificationPermissionPrimer = false

    @AppStorage("athlth.notifications.permissionPrimerShown")
    private var notificationPermissionPrimerShown = false

    private let minimumLifecycleRefreshInterval:
        TimeInterval = 90

    private var lifecycleContent: some View {
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

            // Watch availability is discovered independently of workout capture.
            // The user chooses iPhone vs Apple Watch for each workout.
            watchConnection.connect()

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

                await realtimeSocial
                    .configureOnlinePresence(
                        appIsActive: true,
                        enabled:
                            social.privacy?
                                .showOnlineStatus ??
                            true
                    )
                await realtimeSocial
                    .refreshVisibleLiveSessions()
            }

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
        .fullScreenCover(isPresented: $phoneWorkout.showingWorkout) { IPhoneWorkoutView() }
        .overlay(alignment: .top) {
            if appSession.signedIn, phoneWorkout.active != nil {
                Button { phoneWorkout.showingWorkout = true } label: {
                    Label("Return to iPhone workout", systemImage: "figure.run")
                        .padding(10).background(.regularMaterial, in: Capsule())
                }.padding(.top, 4)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                spotifyPlayback
                    .applicationDidBecomeActive()
            } else {
                spotifyPlayback
                    .applicationWillResignActive()
            }

            phoneWorkout.checkpoint()
            if phase != .active {
                strengthWorkout.checkpoint()
            }

            if appSession.signedIn {
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

            // Refresh Watch availability whenever the app becomes active.
            // This is connection state, not a global workout-device choice.
            watchConnection.connect()

            let now = Date()
            if let lastFullLifecycleRefreshAt,
               now.timeIntervalSince(lastFullLifecycleRefreshAt) <
                    minimumLifecycleRefreshInterval {
                return
            }
            lastFullLifecycleRefreshAt = now

            Task {
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
                      !health.shouldDeferAutomaticHealthWork
                else {
                    return
                }

                await health.refreshIfStale(
                    maxAge: minimumLifecycleRefreshInterval
                )
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
                await refreshTrophiesAndNotifications()
                await syncSocialOwnedData()
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
            }
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
        .onChange(of: watchConnection.lastCompletedWorkout) { _, result in
            guard let result else {
                return
            }

            let publishable =
                SocialPublishableWorkout(
                    watchResult: result
                )
            var completionSourceIDs: Set<UUID> = [
                result.id
            ]
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

            let watchFinishedActiveStrength =
                result.kind == .strength &&
                strengthWorkout.activeWorkout?.captureDevice == .appleWatch

            let watchMatchesCompletedStrength =
                result.kind == .strength &&
                strengthWorkout.completedWorkout?.captureDevice == .appleWatch &&
                strengthWorkout.completedWorkout.map {
                    abs(
                        result.endedAt.timeIntervalSince(
                            $0.endedAt ?? result.endedAt
                        )
                    ) < 180
                } == true

            let watchBelongsToATHLTHStrength =
                watchFinishedActiveStrength ||
                watchMatchesCompletedStrength

            if result.kind == .strength {
                let metrics = LinkedHealthWorkoutMetrics(
                    healthKitWorkoutUUID: result.healthKitWorkoutUUID,
                    duration: result.duration,
                    activeCalories: result.activeCalories,
                    averageHeartRate: result.averageHeartRate,
                    maxHeartRate: result.maxHeartRate
                )

                if watchFinishedActiveStrength {
                    // Finishing from Apple Watch closes the same ATHLTH
                    // strength log instead of creating a second workout.
                    strengthWorkout.finish(
                        healthKitWorkoutUUID: metrics.healthKitWorkoutUUID,
                        duration: metrics.duration,
                        activeCalories: metrics.activeCalories,
                        averageHeartRate: metrics.averageHeartRate,
                        maxHeartRate: metrics.maxHeartRate
                    )
                    appSession.endTrainingStatus()
                } else {
                    // If iPhone already finished the ATHLTH log, attach the
                    // final Watch metrics to that completed session.
                    strengthWorkout.attachHealthMetrics(
                        metrics
                    )
                }
            }

            if !watchBelongsToATHLTHStrength {
                notifications.recordWatchWorkout(result)
            }

            Task {
                await health.refreshAll()
                await officialWeeklyChallenges
                    .syncCompletionState(
                        workouts: health.workouts
                    )
                syncAppleHealthProfileDetailsIfNeeded()
                await goals.refreshAutomaticMilestones(
                    health: health,
                    strength: strengthWorkout
                )
                notifications.syncGoalEvents(from: goals.goals)

                await challengeStore.ingestWatchWorkout(
                    result,
                    health: health,
                    userID: appSession.profile.userID,
                    displayName: appSession.profile.displayName,
                    maximumHeartRateBPM:
                        appSession.onboardingProfile?
                            .maximumHeartRateBPM
                )

                if watchBelongsToATHLTHStrength {
                    // Strength-specific challenge processing stays in the
                    // StrengthWorkoutStore pipeline, but heart-rate
                    // challenges have already consumed the verified
                    // HealthKit heart-rate samples above.
                    watchConnection.clearCompletedWorkout()
                    return
                }
                await social.finishActiveWorkout(
                    sourceWorkoutID: result.healthKitWorkoutUUID ?? result.id,
                    endedAt: result.endedAt
                )

                await gear.savePreparedGearUsage(
                    for: publishable
                )
                await communityGroups.recordCompletedWorkout(
                    publishable
                )
                notifications.syncGearUsageAlerts(
                    from: gear
                )

                workoutCompletion.finalize(
                    workout: publishable,
                    sourceIDs: completionSourceIDs,
                    userID: appSession.profile.userID,
                    goals: goals,
                    challenges: challengeStore,
                    officialWeekly:
                        officialWeeklyChallenges,
                    healthWorkouts: health.workouts,
                    gear: gear,
                    trophies: trophies
                )

                await handleCompletedWorkoutReview(
                    publishable
                )
                await refreshTrophiesAndNotifications()

                workoutCompletion.finalize(
                    workout: publishable,
                    sourceIDs: completionSourceIDs,
                    userID: appSession.profile.userID,
                    goals: goals,
                    challenges: challengeStore,
                    officialWeekly:
                        officialWeeklyChallenges,
                    healthWorkouts: health.workouts,
                    gear: gear,
                    trophies: trophies
                )

                await social.syncChallenges(challengeStore)
                await syncSocialOwnedData()
                watchConnection.clearCompletedWorkout()
            }
        }
        .onChange(of: phoneWorkout.completionStartedWorkout?.id) { _, _ in
            guard let workout =
                    phoneWorkout.completionStartedWorkout,
                  appSession.signedIn
            else {
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
        .onChange(of: phoneWorkout.lastCompletedWorkout?.id) { _, _ in
            guard let workout =
                    phoneWorkout.lastCompletedWorkout,
                  let endedAt = workout.end,
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

                await social.finishActiveWorkout(
                    sourceWorkoutID:
                        workout.healthID ??
                        workout.id,
                    endedAt: endedAt
                )

                await gear.savePreparedGearUsage(
                    for: publishable
                )
                await communityGroups.recordCompletedWorkout(
                    publishable
                )
                notifications.syncGearUsageAlerts(
                    from: gear
                )

                workoutCompletion.finalize(
                    workout: publishable,
                    baselineKey: workout.id,
                    sourceIDs: completionSourceIDs,
                    userID: appSession.profile.userID,
                    goals: goals,
                    challenges: challengeStore,
                    officialWeekly:
                        officialWeeklyChallenges,
                    healthWorkouts: health.workouts,
                    gear: gear,
                    trophies: trophies
                )

                await handleCompletedWorkoutReview(
                    publishable
                )
                await social.syncChallenges(
                    challengeStore
                )
                await refreshTrophiesAndNotifications()

                workoutCompletion.finalize(
                    workout: publishable,
                    baselineKey: workout.id,
                    sourceIDs: completionSourceIDs,
                    userID: appSession.profile.userID,
                    goals: goals,
                    challenges: challengeStore,
                    officialWeekly:
                        officialWeeklyChallenges,
                    healthWorkouts: health.workouts,
                    gear: gear,
                    trophies: trophies
                )

                await syncSocialOwnedData()
            }
        }
        .onChange(of: strengthWorkout.completedWorkout) { _, workout in
            guard let workout else { return }

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

            appSession.applyStrengthProgression(from: workout)
            notifications.recordStrengthWorkout(workout)
            challengeStore.ingestStrengthWorkout(
                workout,
                userID: appSession.profile.userID,
                displayName: appSession.profile.displayName
            )

            Task {
                if workout.captureDevice == .iPhone,
                   workout.healthMetrics.healthKitWorkoutUUID == nil,
                   let endedAt = workout.endedAt {
                    _ = await health.saveManualStrengthWorkout(
                        startDate: workout.startedAt,
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
                        sourceWorkoutID: workout.healthMetrics.healthKitWorkoutUUID ?? workout.id,
                        endedAt: endedAt
                    )
                }
                await gear.savePreparedGearUsage(
                    for: publishable
                )
                await communityGroups.recordCompletedWorkout(
                    publishable
                )
                notifications.syncGearUsageAlerts(
                    from: gear
                )

                workoutCompletion.finalize(
                    workout: publishable,
                    sourceIDs: completionSourceIDs,
                    userID: appSession.profile.userID,
                    goals: goals,
                    challenges: challengeStore,
                    officialWeekly:
                        officialWeeklyChallenges,
                    healthWorkouts: health.workouts,
                    gear: gear,
                    trophies: trophies
                )

                await handleCompletedWorkoutReview(
                    publishable
                )
                await social.syncChallenges(challengeStore)
                await refreshTrophiesAndNotifications()

                workoutCompletion.finalize(
                    workout: publishable,
                    sourceIDs: completionSourceIDs,
                    userID: appSession.profile.userID,
                    goals: goals,
                    challenges: challengeStore,
                    officialWeekly:
                        officialWeeklyChallenges,
                    healthWorkouts: health.workouts,
                    gear: gear,
                    trophies: trophies
                )

                await syncSocialOwnedData()
            }
        }
        .onChange(of: challengeStore.challenges) { _, updatedChallenges in
            notifications.syncChallengeEvents(
                from: updatedChallenges,
                currentUserID: appSession.profile.userID
            )

            Task {
                await social.syncChallenges(challengeStore)
                await social.publishChallenges(
                    updatedChallenges,
                    visibility: settings.defaultActivityVisibility
                )
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
            }
        }
        .onChange(of: appSession.profile.presence) { _, presence in
            guard appSession.signedIn,
                  social.privacy?.shareTrainingPresence == true
            else {
                return
            }

            Task {
                await social.syncPresence(presence)
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
        .onChange(of: appSession.signedIn ? appSession.profile.userID : nil, initial: true) { _, userID in
            phoneWorkout.switchAccount(userID)
            trainingBackups.switchAccount(userID)
            goals.switchAccount(userID)
            strengthWorkout.switchAccount(userID)
            exerciseLibrary.switchAccount(userID)
            runningWorkoutLibrary.switchAccount(userID)
        }
        .task(id: appSession.signedIn ? appSession.profile.userID : nil) {
            guard appSession.signedIn else { return }
            let userID = appSession.profile.userID
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1_800))
                guard !Task.isCancelled,
                      appSession.signedIn,
                      appSession.profile.userID == userID
                else {
                    return
                }

                await trainingBackups.performFailsafeBackup(
                    userID: userID
                )
            }
        }
        .onChange(of: appSession.signedIn) { _, signedIn in
            guard signedIn else { return }

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
            }
        }
        .onChange(of: appSession.onboardingCompleted) { _, completed in
            guard completed else { return }
            scheduleNotificationPermissionPrimerIfNeeded()
        }
        .background {
            ZStack {
                ATHLTHSurfaceRuntimeObserver()
                ATHLTHStrengthWatchSyncObserver()
                ATHLTHBackupDirtyObserver()
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

        if social.privacy?.shareTrainingPresence == true {
            await social.syncPresence(appSession.profile.presence)
        }
    }

    private func syncSocialOwnedData() async {
        guard appSession.signedIn,
              let privacy = social.privacy
        else {
            return
        }

        if privacy.sharePerformanceStats,
           let stats = try? await health.profilePerformanceStats() {
            await social.syncOwnPerformance(stats)
        }

        if privacy.shareRunningPRs,
           let runningRecords = try? await health.personalRecords() {
            await social.publishRunningPersonalRecords(
                runningRecords,
                visibility: settings.defaultActivityVisibility
            )
        }

        if privacy.shareStrengthPRs {
            await social.publishStrengthRepPersonalRecords(
                strengthWorkout.repPersonalRecords,
                visibility: settings.defaultActivityVisibility
            )
        }

        if privacy.shareTrophyCabinet {
            await social.syncOwnTrophies(trophies.showcaseTrophies)

            if privacy.shareRecentActivity {
                await social.publishTrophyUnlocks(
                    trophies.unlocks,
                    visibility: settings.defaultActivityVisibility
                )
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
            currentUserID: appSession.profile.userID
        )
        notifications.syncTrophyEvents(from: trophies.unlocks)
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
