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
        // Competition updates and invitations open the SAME group chat that
        // the athlete already has under Inbox, even on a cold app launch.
        .sheet(
            item: Binding<ATHLTHTournamentPushRoute?>(
                get: {
                    guard session.signedIn,
                          let route = pushManager.pendingTournamentNotification,
                          route.isForAccount(session.profile.userID)
                    else { return nil }
                    return route
                },
                set: { route, _ in
                    if route == nil {
                        pushManager.clearPendingTournamentNotification()
                    }
                }
            )
        ) { route in
            NavigationStack {
                ATHLTHTournamentNotificationDestination(
                    tournamentID: route.tournamentID
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Lukk") {
                            pushManager.clearPendingTournamentNotification()
                        }
                    }
                }
            }
        }
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
        .sheet(
            item: Binding<ATHLTHPlusGrantNotificationRoute?>(
                get: {
                    guard session.signedIn,
                          let route = pushManager.pendingPlusGrantNotification,
                          route.accountID == session.profile.userID
                    else { return nil }
                    return route
                },
                set: { route, _ in
                    if route == nil {
                        pushManager.clearPendingPlusGrantNotification()
                    }
                }
            )
        ) { _ in
            NavigationStack {
                ATHLTHNotificationCenterView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(
                                english: "Close", norwegian: "Lukk"
                            )) {
                                pushManager.clearPendingPlusGrantNotification()
                            }
                        }
                    }
            }
        }
        .sheet(item: Binding<ATHLTHSharedWorkoutRoomRoute?>(
            get: {
                guard session.signedIn, let route = pushManager.pendingSharedWorkoutRoom,
                      route.recipientID == session.profile.userID else { return nil }
                return route
            },
            set: { route in if route == nil { pushManager.clearPendingSharedWorkoutRoom() } }
        )) { route in
            NavigationStack {
                TrainTogetherLiveDraftRoomView(sourceWorkoutID: route.sourceID, initiallyShowsChat: true)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")) {
                                pushManager.clearPendingSharedWorkoutRoom()
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
