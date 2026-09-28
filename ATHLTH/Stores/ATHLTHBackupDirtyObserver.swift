import SwiftUI

/// Bridges persisted training-data changes into the event-driven backup store.
/// It is deliberately separate from AppRootView so backup bookkeeping cannot
/// invalidate the visible product hierarchy.
struct ATHLTHBackupDirtyObserver: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var backups: TrainingBackupStore

    @State private var trackedUserID: UUID?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: session.signedIn ? session.profile.userID : nil) {
                trackedUserID = nil

                guard session.signedIn else { return }
                let userID = session.profile.userID

                // Account stores publish their initial restoration writes
                // during launch. Establish the baseline after that settles so
                // restoring cached state is not mistaken for a user edit.
                try? await Task.sleep(
                    for: .seconds(2)
                )

                guard !Task.isCancelled,
                      session.signedIn,
                      session.profile.userID == userID
                else {
                    return
                }

                backups.beginChangeTracking(
                    userID: userID
                )
                trackedUserID = userID
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .athlthTrainingDataDidChange
                )
            ) { notification in
                guard session.signedIn,
                      let changedUserID =
                        notification.object as? UUID,
                      changedUserID ==
                        session.profile.userID,
                      trackedUserID ==
                        changedUserID
                else {
                    return
                }

                backups.markDirty(
                    userID: changedUserID
                )
            }
    }
}
