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
