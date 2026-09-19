import SwiftUI

@main
struct ATHLTHApp: App {
    @StateObject private var health = HealthKitManager()
    @StateObject private var trainingPlan = TrainingPlanStore()
    @StateObject private var appSession = AppSessionStore()
    @StateObject private var settings = AppSettingsStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(health)
                .environmentObject(trainingPlan)
                .environmentObject(appSession)
                .environmentObject(settings)
                .environment(\.locale, Locale(identifier: settings.language.rawValue))
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var appSession: AppSessionStore

    var body: some View {
        Group {
            if health.hasRequestedAuthorization || appSession.previewModeEnabled {
                ProductRootTabView()
            } else {
                HealthAccessView()
            }
        }
        .task {
            guard health.hasRequestedAuthorization else { return }
            await health.configureBackgroundSync()
            await health.refreshAll()
        }
    }
}
