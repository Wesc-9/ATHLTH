import SwiftUI

/// Owns deep-link sheets independently from ATHLTH's root tab bar.
/// The parent retains the current tab, deep-link delivery and reminder lifecycle.
struct ATHLTHRootNotificationSheetHost<Content: View>: View {
    let content: Content
    @ObservedObject var pushManager: APNsPushManager
    @Binding var showingDailyCheckIn: Bool
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    var body: some View {
        content
        // Render the actual challenge detail above the root tabs. The
        // singleton retains the route if iOS delivers the tap before this
        // view is created (cold launch).
        .sheet(
            item: Binding(
                get: { pushManager.pendingChallengeNotification },
                set: { route in
                    if route == nil {
                        pushManager.clearPendingChallengeNotification()
                    }
                }
            )
        ) { route in
            NavigationStack {
                ATHLTHChallengeNotificationDestination(route: route)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(
                                english: "Close", norwegian: "Lukk"
                            )) {
                                pushManager.clearPendingChallengeNotification()
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingDailyCheckIn) {
            NavigationStack {
                RecoverySorenessLogView(store: RecoverySorenessStore())
            }
        }
        .sheet(
            item: Binding<ATHLTHBodyGoalNotificationRoute?>(
                get: {
                    guard let route = pushManager.pendingBodyGoalCheckIn,
                          route.accountID == session.profile.userID,
                          goalStore.goals.contains(where: { $0.id == route.goalID })
                    else { return nil }
                    return route
                },
                set: { route, _ in
                    if route == nil { pushManager.clearPendingBodyGoalCheckIn() }
                }
            )
        ) { route in
            NavigationStack {
                GoalDetailView(goalID: route.goalID,
                               openMeasurementCheckIn: true)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(
                                english: "Close", norwegian: "Lukk"
                            )) {
                                pushManager.clearPendingBodyGoalCheckIn()
                            }
                        }
                    }
            }
        }
    }
}
