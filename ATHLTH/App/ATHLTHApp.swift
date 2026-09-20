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
                .environment(\.locale, settings.language.locale)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var appSession: AppSessionStore

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
            guard health.hasRequestedAuthorization else { return }
            await health.configureBackgroundSync()
            await health.refreshAll()
        }
    }
}
