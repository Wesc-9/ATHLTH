import SwiftUI

@main
struct ATHLTHApp: App {
    @StateObject private var health = HealthKitManager()
    @StateObject private var trainingPlan = TrainingPlanStore()
    @StateObject private var appSession = AppSessionStore()
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var strengthWorkout = StrengthWorkoutStore()
    @StateObject private var goals = GoalStore()
    @StateObject private var notifications = ATHLTHNotificationStore()
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
                .environmentObject(appSession)
                .environmentObject(settings)
                .environmentObject(strengthWorkout)
                .environmentObject(goals)
                .environmentObject(notifications)
                .environmentObject(spotifyPlayback)
                .environmentObject(watchConnection)
                .environmentObject(workoutMirroring)
                .environmentObject(subscriptionStore)
                .environmentObject(subscriptionBackend)
                .environmentObject(accountService)
                .environment(\.locale, settings.language.locale)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var subscriptionBackend: SubscriptionBackendService
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore

    @State private var authCallbackError: String?

    var body: some View {
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

            guard health.hasRequestedAuthorization else { return }
            await health.configureBackgroundSync(
                allowed: appSession.canAccess(.backgroundHealthSync)
            )
            await health.refreshAll()
            await goals.refreshAutomaticMilestones(
                health: health,
                strength: strengthWorkout
            )
            notifications.syncGoalEvents(from: goals.goals)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }

            // Refresh pairing/install state whenever ATHLTH returns to the
            // foreground, for example after installing the Watch app.
            watchConnection.connect()

            guard health.hasRequestedAuthorization else { return }
            Task {
                await health.refreshAll()
                await goals.refreshAutomaticMilestones(
                    health: health,
                    strength: strengthWorkout
                )
                notifications.syncGoalEvents(from: goals.goals)
            }
        }
        .onChange(of: subscriptionStore.activeEntitlement) { _, entitlement in
            appSession.applyStoreKitEntitlement(entitlement)

            guard health.hasRequestedAuthorization else {
                return
            }

            Task {
                await health.configureBackgroundSync(
                    allowed: appSession.canAccess(.backgroundHealthSync)
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
                watchConnection.clearCompletedWorkout()
            }
        }
        .onChange(of: strengthWorkout.completedWorkout) { _, workout in
            guard let workout else { return }
            notifications.recordStrengthWorkout(workout)
        }
        .onChange(of: goals.goals) { _, updatedGoals in
            notifications.syncGoalEvents(from: updatedGoals)
        }
        .onChange(of: appSession.signedIn) { _, signedIn in
            guard signedIn else { return }

            appSession.applyStoreKitEntitlement(subscriptionStore.activeEntitlement)
            Task {
                await submitLatestStoreProofIfPossible()
            }
        }
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
