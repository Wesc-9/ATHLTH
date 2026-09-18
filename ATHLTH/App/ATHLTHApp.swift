import SwiftUI

@main
struct ATHLTHApp: App {
    @StateObject private var health = HealthKitManager()
    @StateObject private var trainingPlan = TrainingPlanStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(health)
                .environmentObject(trainingPlan)
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject private var health: HealthKitManager

    var body: some View {
        Group {
            if health.hasRequestedAuthorization {
                RootTabView()
            } else {
                HealthAccessView()
            }
        }
        .task {
            guard health.hasRequestedAuthorization else { return }
            await health.refreshAll()
        }
    }
}
