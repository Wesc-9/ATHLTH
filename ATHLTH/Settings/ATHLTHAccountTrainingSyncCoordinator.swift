import Foundation

/// A common entry point for the existing independently revisioned sync domains.
/// The stores retain their own owner checks, conflict handling and throttling.
@MainActor
enum ATHLTHAccountTrainingSyncCoordinator {
    static func schedule(session: AppSessionStore, settings: AppSettingsStore,
                         goals: GoalStore, strength: StrengthWorkoutStore,
                         plans: ATHLTHStudioPlanSyncStore, goalSync: ATHLTHGoalAccountSyncStore,
                         audio: ATHLTHAudioCoachAccountSyncStore, history: ATHLTHStrengthAccountSyncStore) {
        guard session.signedIn, !session.previewModeEnabled else { return }
        goalSync.scheduleSync(session: session, goals: goals)
        plans.scheduleSync(session: session)
        audio.scheduleSync(session: session, settings: settings)
        history.scheduleSync(session: session, strength: strength)
    }

    static func synchronize(session: AppSessionStore, settings: AppSettingsStore,
                            goals: GoalStore, strength: StrengthWorkoutStore,
                            plans: ATHLTHStudioPlanSyncStore, goalSync: ATHLTHGoalAccountSyncStore,
                            audio: ATHLTHAudioCoachAccountSyncStore, history: ATHLTHStrengthAccountSyncStore) async {
        guard session.signedIn, !session.previewModeEnabled else { return }
        let owner = session.profile.userID
        func sameAccount() -> Bool {
            !Task.isCancelled && session.signedIn && !session.previewModeEnabled && session.profile.userID == owner
        }
        // Sequential on purpose: a manual refresh should not fan out four
        // large writes while a live workout is sharing the device.
        await plans.sync(session: session)
        guard sameAccount() else { return }
        await history.sync(session: session, strength: strength, force: true)
        guard sameAccount() else { return }
        await goalSync.sync(session: session, goals: goals)
        guard sameAccount() else { return }
        await audio.sync(session: session, settings: settings)
    }
}
