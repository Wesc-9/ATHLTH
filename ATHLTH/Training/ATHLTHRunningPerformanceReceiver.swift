import SwiftUI

/// Persist the final Watch result even when the user never opens Progress.
/// A linked workout must belong to the signed-in account.
struct ATHLTHRunningPerformanceReceiver: ViewModifier {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watch: AppleWatchConnectionStore
    @EnvironmentObject private var health: HealthKitManager

    func body(content: Content) -> some View {
        content
            .onAppear(perform: receive)
            .onChange(of: watch.pendingWorkoutResults) { _, _ in receive() }
            .onChange(of: session.profile.userID) { _, _ in receive() }
            .onChange(of: health.workouts.map(\.id)) { _, _ in receive() }
    }

    private func receive() {
        guard session.signedIn, !session.previewModeEnabled else { return }
        let plans = session.scheduledPlans + [session.activePlan].compactMap { $0 }
        let sessions = plans.flatMap {
            $0.weeks.flatMap(\.days).flatMap(\.sessions)
        }
        let knownIDs = Set(
            sessions.map(\.id) +
            session.standalonePlannedSessions.map(\.id) +
            session.savedWorkoutTemplates.map(\.id)
        )
        for result in watch.pendingWorkoutResults {
            ATHLTHRunningPerformanceHistory.saveWatch(
                result,
                userID: session.profile.userID,
                knownWorkoutIDs: knownIDs,
                knownHealthWorkoutIDs: Set(health.workouts.map(\.id))
            )
        }
    }
}
