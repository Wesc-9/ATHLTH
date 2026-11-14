import Foundation

/// Routing rules for the shared workout builder when it is presented from
/// the older standalone session editor. Kept pure for regression tests.
enum ATHLTHScratchComposerPresentationPolicy {
    /// Solo workouts can be committed from the new builder with their full
    /// session snapshot. Partner proposals and active-plan placement still
    /// require the parent editor's original confirmation.
    static func savesDirectly(
        isStandalone: Bool,
        preparesForSharing: Bool,
        hasPartner: Bool,
        targetsActivePlan: Bool
    ) -> Bool {
        isStandalone && !preparesForSharing &&
            !hasPartner && !targetsActivePlan
    }

    /// The legacy parent form must not reappear under the new solo
    /// scratch builder, even when it is dismissing or presenting a child sheet.
    /// Partner and plan-editing flows still use their established host UI.
    static func hidesLegacyStandaloneHost(
        isStandalone: Bool,
        hasScratchSource: Bool,
        preparesForSharing: Bool,
        hasPartner: Bool
    ) -> Bool {
        isStandalone && hasScratchSource && !preparesForSharing && !hasPartner
    }

    /// A scratch draft has a persistent checkpoint even before the athlete
    /// inserts a block. Always offer Delete/Keep/Continue on explicit Back.
    static func requiresExitDecision(
        isScratchHost: Bool,
        hasEdits: Bool
    ) -> Bool {
        isScratchHost || hasEdits
    }

    /// App suspension is not the same as cancelling the workout editor.
    /// Restore the exact same builder instead of exposing the legacy form.
    static func shouldRestoreOnWake(
        isStandalone: Bool,
        hasScratchSource: Bool,
        builderWasPresented: Bool,
        isFinalized: Bool
    ) -> Bool {
        isStandalone && hasScratchSource &&
            builderWasPresented && !isFinalized
    }
}


/// The legacy standalone host and the new timeline editor each have a
/// checkpoint. Delete them as ONE account-scoped draft so Home cannot offer
/// "Continue draft" after the athlete explicitly chose Delete.
enum ATHLTHStandaloneWorkoutDraftStore {
    private struct ScratchReference: Decodable {
        let id: UUID
    }

    static func parentKey(for userID: UUID) -> String {
        "athlth.sessionEditor.draft.v1.\(userID.uuidString).standalone"
    }

    static func entryKey(for userID: UUID) -> String {
        parentKey(for: userID) + ".scratchComposer"
    }

    static func childKey(for userID: UUID, draftID: UUID) -> String {
        let context = "session-scratch.\(userID.uuidString).\(draftID.uuidString)"
        return "athlth.workoutBuilder.draft.v1.\(userID.uuidString).\(Data(context.utf8).base64EncodedString())"
    }

    static func savedDraftID(for userID: UUID, defaults: UserDefaults = .standard) -> UUID? {
        guard let data = defaults.data(forKey: entryKey(for: userID)) else { return nil }
        return try? JSONDecoder().decode(ScratchReference.self, from: data).id
    }

    static func hasDraft(for userID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.data(forKey: parentKey(for: userID)) != nil ||
            defaults.data(forKey: entryKey(for: userID)) != nil
    }

    static func discard(
        for userID: UUID,
        additionalDraftID: UUID? = nil,
        defaults: UserDefaults = .standard
    ) {
        // Remove the child snapshot before its pointer. Never touch another
        // athlete's workout, a planned session or an unrelated partner draft.
        let candidateIDs = Set([savedDraftID(for: userID, defaults: defaults),
                                additionalDraftID].compactMap { $0 })
        for id in candidateIDs {
            defaults.removeObject(forKey: childKey(for: userID, draftID: id))
        }
        defaults.removeObject(forKey: parentKey(for: userID))
        defaults.removeObject(forKey: entryKey(for: userID))
    }
}
