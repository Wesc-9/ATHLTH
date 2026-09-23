import Foundation
import SwiftUI

@main
struct ATHLTHApp: App {
    @StateObject private var health = HealthKitManager()
    @StateObject private var trainingPlan = TrainingPlanStore()
    @StateObject private var exerciseLibrary = ExerciseLibraryStore()
    @StateObject private var runningWorkoutLibrary = RunningWorkoutLibraryStore()
    @StateObject private var appSession = AppSessionStore()
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var strengthWorkout = StrengthWorkoutStore()
    @StateObject private var goals = GoalStore()
    @StateObject private var notifications = ATHLTHNotificationStore()
    @StateObject private var challengeStore = ChallengeStore()
    @StateObject private var social = SocialStore()
    @StateObject private var trophies = TrophyStore()
    @StateObject private var spotifyPlayback = SpotifyPlaybackStore()
    @StateObject private var watchConnection = AppleWatchConnectionStore()
    @StateObject private var workoutMirroring = WorkoutMirroringStore()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var subscriptionBackend = SubscriptionBackendService()
    @StateObject private var accountService = SupabaseAccountService()

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
                .environmentObject(notifications)
                .environmentObject(challengeStore)
                .environmentObject(social)
                .environmentObject(trophies)
                .environmentObject(spotifyPlayback)
                .environmentObject(watchConnection)
                .environmentObject(workoutMirroring)
                .environmentObject(subscriptionStore)
                .environmentObject(subscriptionBackend)
                .environmentObject(accountService)
                .environment(\.locale, Locale(identifier: "en"))
                .preferredColorScheme(.light)
                .tint(ATHLTHTheme.accent)
        }
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
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var trophies: TrophyStore

    @State private var authCallbackError: String?
    @State private var pendingWorkoutReview: SocialPublishableWorkout?
    @State private var queuedWorkoutReviewIDs: Set<UUID> = []
    @State private var lastQueuedWorkoutReview: SocialPublishableWorkout?

    private var lifecycleContent: some View {
        Group {
            if appSession.previewModeEnabled {
                ProductRootTabView()
            } else if !appSession.signedIn || !appSession.onboardingCompleted {
                OnboardingFlowView()
            } else {
                ProductRootTabView()
            }
        }
        .task {
            do {
                if let bootstrap = try await accountService.restoreCurrentUser() {
                    appSession.applyBackendBootstrap(bootstrap)
                } else if appSession.signedIn && !accountService.hasPersistedSession {
                    appSession.resetOnboardingForPreview()
                }
            } catch {
                if !accountService.hasPersistedSession {
                    appSession.resetOnboardingForPreview()
                }
            }

            watchConnection.connect()

            await subscriptionStore.start()
            appSession.applyStoreKitEntitlement(subscriptionStore.activeEntitlement)
            await submitLatestStoreProofIfPossible()

            if appSession.signedIn {
                await refreshSocialCore()
            }

            guard health.hasRequestedAuthorization else { return }
            await health.configureBackgroundSync(
                allowed:
                    appSession.canAccess(.backgroundHealthSync) &&
                    settings.backgroundHealthSyncEnabled
            )
            await health.refreshAll()
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

            // Refresh pairing/install state whenever ATHLTH returns to the
            // foreground, for example after installing the Watch app.
            watchConnection.connect()

            Task {
                if appSession.signedIn {
                    await refreshSocialCore()
                }

                guard health.hasRequestedAuthorization else { return }

                await health.refreshAll()
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

            guard health.hasRequestedAuthorization else {
                return
            }

            Task {
                await health.configureBackgroundSync(
                    allowed:
                        appSession.canAccess(.backgroundHealthSync) &&
                        settings.backgroundHealthSyncEnabled
                )
            }
        }
        .onChange(of: settings.backgroundHealthSyncEnabled) { _, enabled in
            guard health.hasRequestedAuthorization else {
                return
            }

            Task {
                await health.configureBackgroundSync(
                    allowed:
                        appSession.canAccess(.backgroundHealthSync) &&
                        enabled
                )
            }
        }
        .onChange(of: subscriptionStore.latestTransactionProof) { _, _ in
            Task {
                await submitLatestStoreProofIfPossible()
            }
        }
        .onChange(of: watchConnection.lastCompletedWorkout) { _, result in
            guard let result else { return }

            if result.kind == .strength {
                strengthWorkout.attachHealthMetrics(
                    LinkedHealthWorkoutMetrics(
                        healthKitWorkoutUUID: result.healthKitWorkoutUUID,
                        duration: result.duration,
                        activeCalories: result.activeCalories,
                        averageHeartRate: result.averageHeartRate,
                        maxHeartRate: result.maxHeartRate
                    )
                )
            }

            notifications.recordWatchWorkout(result)

            Task {
                await health.refreshAll()
                await goals.refreshAutomaticMilestones(
                    health: health,
                    strength: strengthWorkout
                )
                notifications.syncGoalEvents(from: goals.goals)
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
                await handleCompletedWorkoutReview(
                    SocialPublishableWorkout(watchResult: result)
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
                if let endedAt = workout.endedAt {
                    await social.finishActiveWorkout(
                        sourceWorkoutID: workout.healthMetrics.healthKitWorkoutUUID ?? workout.id,
                        endedAt: endedAt
                    )
                }
                await handleCompletedWorkoutReview(
                    SocialPublishableWorkout(strengthWorkout: workout)
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
                await social.publishCompletedGoals(
                    updatedGoals,
                    visibility: settings.defaultActivityVisibility
                )
                await refreshTrophiesAndNotifications()
                await syncSocialOwnedData()
            }
        }
        .onChange(of: appSession.profile.presence) { _, presence in
            guard appSession.signedIn else { return }

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
        .onChange(of: appSession.signedIn) { _, signedIn in
            guard signedIn else { return }

            appSession.applyStoreKitEntitlement(subscriptionStore.activeEntitlement)
            Task {
                await submitLatestStoreProofIfPossible()
                await refreshSocialCore()
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

        await social.syncPresence(appSession.profile.presence)
    }

    private func syncSocialOwnedData() async {
        guard appSession.signedIn else { return }

        if let stats = try? await health.profilePerformanceStats() {
            await social.syncOwnPerformance(stats)
        }

        await social.syncOwnTrophies(trophies.showcaseTrophies)
        await social.publishTrophyUnlocks(
            trophies.unlocks,
            visibility: settings.defaultActivityVisibility
        )
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
