import SwiftUI

@main
struct ATHLTHApp: App {
    @StateObject private var health = HealthKitManager()
    @StateObject private var trainingPlan = TrainingPlanStore()
    @StateObject private var appSession = AppSessionStore()
    @StateObject private var settings = AppSettingsStore()
    @StateObject private var strengthWorkout = StrengthWorkoutStore()
    @StateObject private var spotifyPlayback = SpotifyPlaybackStore()
    @StateObject private var watchConnection = AppleWatchConnectionStore()
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
                .environmentObject(spotifyPlayback)
                .environmentObject(watchConnection)
                .environmentObject(subscriptionStore)
                .environmentObject(subscriptionBackend)
                .environmentObject(accountService)
                .environment(\.locale, settings.language.locale)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var accountService: SupabaseAccountService
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var subscriptionBackend: SubscriptionBackendService

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
            if let bootstrap = try? await accountService.restoreCurrentUser() {
                appSession.applyBackendBootstrap(bootstrap)
            }

            await subscriptionStore.start()
            appSession.applyStoreKitEntitlement(subscriptionStore.activeEntitlement)
            await submitLatestStoreProofIfPossible()

            guard health.hasRequestedAuthorization else { return }
            if appSession.hasPaidAccess {
                await health.configureBackgroundSync()
            }
            await health.refreshAll()
        }
        .onChange(of: subscriptionStore.activeEntitlement) { _, entitlement in
            appSession.applyStoreKitEntitlement(entitlement)

            guard appSession.hasPaidAccess, health.hasRequestedAuthorization else {
                return
            }

            Task {
                await health.configureBackgroundSync()
            }
        }
        .onChange(of: subscriptionStore.latestTransactionProof) { _, _ in
            Task {
                await submitLatestStoreProofIfPossible()
            }
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

        try? await subscriptionBackend.submit(proof)
    }
}
