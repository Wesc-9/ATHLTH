import Foundation
import SwiftUI

@main
struct ATHLTHApp: App {
    @UIApplicationDelegateAdaptor(ATHLTHAppDelegate.self)
    private var appDelegate
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var trainingPlan = TrainingPlanStore()
    @StateObject private var exerciseLibrary = ExerciseLibraryStore()
    @StateObject private var runningWorkoutLibrary = RunningWorkoutLibraryStore()
    @StateObject private var appSession = AppSessionStore()
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var strengthWorkout = StrengthWorkoutStore()
    @StateObject private var goals = GoalStore()
    @StateObject private var profileGear = ProfileGearStore()
    @StateObject private var notifications = ATHLTHNotificationStore()
    @StateObject private var calendarSync = AppleCalendarSyncStore()
    @StateObject private var challengeStore = ChallengeStore()
    @StateObject private var social = SocialStore()
    @StateObject private var messaging = MessagingStore()
    @StateObject private var communityEvents = CommunityEventStore()
    @StateObject private var communityGroups = CommunityGroupStore()
    @StateObject private var routeDiscovery = RouteDiscoveryStore()
    @StateObject private var trophies = TrophyStore()
    @StateObject private var spotifyPlayback = SpotifyPlaybackStore()
    @StateObject private var watchConnection = AppleWatchConnectionStore()
    @StateObject private var workoutMirroring = WorkoutMirroringStore()
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
                .environmentObject(trainingPlan)
                .environmentObject(exerciseLibrary)
                .environmentObject(runningWorkoutLibrary)
                .environmentObject(appSession)
                .environmentObject(settings)
                .environmentObject(strengthWorkout)
                .environmentObject(goals)
                .environmentObject(profileGear)
                .environmentObject(notifications)
                .environmentObject(calendarSync)
                .environmentObject(challengeStore)
                .environmentObject(social)
                .environmentObject(messaging)
                .environmentObject(communityEvents)
                .environmentObject(communityGroups)
                .environmentObject(routeDiscovery)
                .environmentObject(trophies)
                .environmentObject(spotifyPlayback)
                .environmentObject(watchConnection)
                .environmentObject(workoutMirroring)
                .environmentObject(subscriptionStore)
                .environmentObject(subscriptionBackend)
                .environmentObject(accountService)
                .environment(
                    \.locale,
                    settings.timeFormatPreference.locale
                )
                .preferredColorScheme(.light)
                .tint(ATHLTHTheme.accent)
        }
    }
}

private struct ATHLTHLaunchGateView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ATHLTHBrandMark(size: .compact, showTagline: false)

                ProgressView()
                    .controlSize(.regular)
                    .tint(ATHLTHTheme.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening ATHLTH")
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var subscriptionBackend: SubscriptionBackendService
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var calendarSync: AppleCalendarSyncStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var communityGroups: CommunityGroupStore
    @EnvironmentObject private var trophies: TrophyStore

    @State private var authCallbackError: String?
    @State private var startupAuthenticationResolved = false
    @State private var pendingWorkoutReview: SocialPublishableWorkout?
    @State private var queuedWorkoutReviewIDs: Set<UUID> = []
    @State private var lastQueuedWorkoutReview: SocialPublishableWorkout?

    private var lifecycleContent: some View {
        Group {
            if appSession.previewModeEnabled {
                ProductRootTabView()
            } else if appSession.signedIn && !startupAuthenticationResolved {
                ATHLTHLaunchGateView()
            } else if !appSession.signedIn || !appSession.onboardingCompleted {
                OnboardingFlowView()
            } else {
                ProductRootTabView()
            }
        }
        .task {
            await resolveStartupAuthentication()

            if settings.trainingDeviceProvider == .appleWatch {
                watchConnection.connect()
            }

            await subscriptionStore.start()
            appSession.applyStoreKitEntitlement(subscriptionStore.activeEntitlement)
            await submitLatestStoreProofIfPossible()

            if appSession.signedIn {
                await APNsPushManager.shared.syncCurrentToken()
                await syncPushPreferences()
                await refreshSocialCore()
                await messaging.refresh()
                await gear.refresh()
                await communityGroups.refresh()
                await syncCalendarIfAllowed()
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
            await health.refreshAll()
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }

            // Only touch WatchConnectivity when Apple Watch is the selected
            // provider. Garmin/no-watch users should not depend on Watch state.
            if settings.trainingDeviceProvider == .appleWatch {
                watchConnection.connect()
            }

            Task {
                if appSession.signedIn {
                    await refreshSocialCore()
                    await messaging.refresh()
                    await syncCalendarIfAllowed()
                }

                guard health.hasRequestedAuthorization,
                      !health.shouldDeferAutomaticHealthWork
                else {
                    return
                }

                await health.refreshAll()
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
        .onChange(of: settings.trainingDeviceProvider) { _, provider in
            if provider == .appleWatch {
                watchConnection.connect()
            } else if settings.preferredWorkoutCapture == .appleWatch {
                settings.preferredWorkoutCapture = .iPhone
            }
        }
        .onChange(of: health.personalDetails) { _, details in
            guard let source = appSession.onboardingProfile?.personalDetailsSource,
                  source == .appleHealth || source == .mixed,
                  details.hasAnyValue
            else {
                return
            }

            appSession.mergePersonalDetailsFromAppleHealth(details)
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
            guard settings.trainingDeviceProvider == .appleWatch,
                  let result
            else {
                if settings.trainingDeviceProvider != .appleWatch {
                    watchConnection.clearCompletedWorkout()
                }
                return
            }

            let watchFinishedActiveStrength =
                result.kind == .strength &&
                strengthWorkout.activeWorkout?.captureDevice == .appleWatch

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

            if !watchFinishedActiveStrength {
                notifications.recordWatchWorkout(result)
            }

            Task {
                await health.refreshAll()
                syncAppleHealthProfileDetailsIfNeeded()
                await goals.refreshAutomaticMilestones(
                    health: health,
                    strength: strengthWorkout
                )
                notifications.syncGoalEvents(from: goals.goals)

                if watchFinishedActiveStrength {
                    // The StrengthWorkoutStore completion pipeline handles
                    // progression, challenges, gear, sharing and review.
                    watchConnection.clearCompletedWorkout()
                    return
                }

                await challengeStore.ingestWatchWorkout(
                    result,
                    health: health,
                    userID: appSession.profile.userID,
                    displayName: appSession.profile.displayName
                )
                await social.finishActiveWorkout(
                    sourceWorkoutID: result.healthKitWorkoutUUID ?? result.id,
                    endedAt: result.endedAt
                )

                let publishable =
                    SocialPublishableWorkout(watchResult: result)
                await gear.savePreparedGearUsage(
                    for: publishable
                )
                await communityGroups.recordCompletedWorkout(
                    publishable
                )
                notifications.syncGearUsageAlerts(
                    from: gear
                )
                await handleCompletedWorkoutReview(
                    publishable
                )
                await refreshTrophiesAndNotifications()
                await social.syncChallenges(challengeStore)
                await syncSocialOwnedData()
                watchConnection.clearCompletedWorkout()
            }
        }
        .onChange(of: strengthWorkout.completedWorkout) { _, workout in
            guard let workout else { return }

            appSession.applyStrengthProgression(from: workout)
            notifications.recordStrengthWorkout(workout)
            challengeStore.ingestStrengthWorkout(
                workout,
                userID: appSession.profile.userID,
                displayName: appSession.profile.displayName
            )

            Task {
                if workout.healthMetrics.healthKitWorkoutUUID == nil,
                   let endedAt = workout.endedAt {
                    _ = await health.saveManualStrengthWorkout(
                        startDate: workout.startedAt,
                        endDate: endedAt,
                        externalID: workout.id
                    )
                    await health.refreshAll()
                }

                if let endedAt = workout.endedAt {
                    await social.finishActiveWorkout(
                        sourceWorkoutID: workout.healthMetrics.healthKitWorkoutUUID ?? workout.id,
                        endedAt: endedAt
                    )
                }
                let publishable =
                    SocialPublishableWorkout(
                        strengthWorkout: workout
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
                await handleCompletedWorkoutReview(
                    publishable
                )
                await social.syncChallenges(challengeStore)
                await refreshTrophiesAndNotifications()
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
        .onChange(of: social.privacy) { _, privacy in
            guard appSession.signedIn, privacy != nil else { return }

            Task {
                await syncSocialOwnedData()
            }
        }
        .onChange(of: appSession.signedIn) { _, signedIn in
            guard signedIn else { return }

            appSession.applyStoreKitEntitlement(subscriptionStore.activeEntitlement)
            Task {
                await APNsPushManager.shared.syncCurrentToken()
                await syncPushPreferences()
                await submitLatestStoreProofIfPossible()
                await refreshSocialCore()
                await syncCalendarIfAllowed()
                if health.hasRequestedAuthorization {
                    await syncSocialOwnedData()
                }
            }
        }
    }

    var body: some View {
        lifecycleContent
        .onOpenURL { url in
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
        .sheet(item: $pendingWorkoutReview) { workout in
            PostWorkoutReviewView(
                workout: workout,
                wasAutoPublished: settings.autoPublishCompletedWorkouts
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
        guard appSession.subscriptionAccess.hasPaidAccess else {
            return
        }

        await calendarSync.syncIfEnabled(
            plan: plan ?? appSession.activePlan
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

    private func resolveStartupAuthentication() async {
        defer {
            startupAuthenticationResolved = true
        }

        // UserDefaults is removed with the app, while Supabase's iOS
        // Keychain-backed session can survive an uninstall. Never use that
        // orphaned session to bypass the account/onboarding screen.
        guard appSession.signedIn else {
            await accountService.discardUnexpectedPersistedSession()
            return
        }

        // Existing installs may restore silently, but the main product UI is
        // held behind ATHLTHLaunchGateView until the backend session and
        // profile have both been validated.
        do {
            guard let bootstrap = try await accountService.restoreCurrentUser()
            else {
                appSession.resetAuthenticationState()
                await accountService.discardUnexpectedPersistedSession()
                return
            }

            appSession.applyBackendBootstrap(bootstrap)
        } catch {
            // Never enter ProductRootTabView with a stale/partial profile.
            // Falling back to the login screen is safer and recoverable.
            appSession.resetAuthenticationState()
            await accountService.discardUnexpectedPersistedSession()
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

        if settings.autoPublishCompletedWorkouts {
            _ = await social.publishWorkout(
                workout,
                visibility: settings.defaultActivityVisibility
            )
        }

        pendingWorkoutReview = workout
    }

    private func refreshSocialCore() async {
        await social.refresh(
            challengeStore: challengeStore,
            notificationStore: notifications
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
            messages: settings.messageNotificationsEnabled
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
