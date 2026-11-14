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
