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

    /// When a shared editor is presented it is the ONLY visible editing
    /// surface, regardless of whether its caller is Home, a friend, a planned
    /// session or a Train Together proposal. Once it closes, the legacy
    /// host returns only for flows that still need its original controls.
    static func hidesLegacyStandaloneHost(
        isStandalone: Bool,
        hasScratchSource: Bool,
        preparesForSharing: Bool,
        hasPartner: Bool,
        builderIsPresented: Bool = false
    ) -> Bool {
        if builderIsPresented { return true }
        return isStandalone && hasScratchSource &&
            !preparesForSharing && !hasPartner
    }

    /// Sheets that choose a workout may only hand off to the next editor
    /// after the first sheet's onDismiss callback has finished. Keep this
    /// transition independent from whether the workout was newly created.
    static func opensQueuedEditorAfterPickerDismiss(
        queued: Bool,
        pickerIsPresented: Bool
    ) -> Bool {
        queued && !pickerIsPresented
    }

    /// Plan Studio may restore one or both sheet flags after scene wake.
    /// Never let a resumed day editor and standalone editor compete. The
    /// explicit standalone intent wins; either may open again deliberately.
    static func exclusiveEditorRestoration(
        standalone: Bool,
        day: Bool
    ) -> (standalone: Bool, day: Bool) {
        if standalone { return (true, false) }
        return (false, day)
    }

    /// Starting a strength recorder and presenting its live UI are
    /// separate operations. SwiftUI must finish dismissing the options sheet
    /// before the live full-screen cover takes ownership of presentation.
    /// Failed launches never queue the transition.
    static func startsLiveAfterSetupDismiss(
        queued: Bool,
        setupIsPresented: Bool
    ) -> Bool {
        queued && !setupIsPresented
    }

    /// Quick Train's setup sheet remains mounted for the recorder and
    /// settings, but its obsolete editable surface is hidden while the
    /// shared running composer has focus.
    static func showsQuickSetupBehindComposer(
        composerIsPresented: Bool
    ) -> Bool {
        !composerIsPresented
    }

    /// A Train Together post built from scratch can advance directly to the
    /// invitation composer without reopening the duplicate legacy workout
    /// editor. This prepares the workout only; publication remains explicit.
    static func preparesSharedScratchDirectly(
        isStandalone: Bool,
        hasScratchSource: Bool,
        preparesForSharing: Bool
    ) -> Bool {
        isStandalone && hasScratchSource && preparesForSharing
    }

    /// A prepared partner workout requires scheduling and permission review,
    /// but must never return to the old "Plan extra workout" Form.
    static func showsPartnerInvitationReview(
        isStandalone: Bool,
        hasPartner: Bool,
        hasScratchSource: Bool,
        preparesForSharing: Bool,
        builderIsPresented: Bool
    ) -> Bool {
        isStandalone && hasPartner && hasScratchSource &&
            !preparesForSharing && !builderIsPresented
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
    // Navigation is deliberately separate from the workout recipe. The last
    // visible card is restored automatically only for an *active* Home
    // composer; an ordinary new visit still offers explicit draft selection.
    enum NavigationStage: String, Codable {
        case source
        case scratchTypePicker
        case scratchBuilder
        case savedWorkoutPicker
        case recoveryRestPlanner
        case legacyEditor
    }

    private struct NavigationSnapshot: Codable {
        let stage: NavigationStage
        let savedAt: Date
    }

    private static func navigationKey(for userID: UUID) -> String {
        "athlth.sessionEditor.navigation.v1.\(userID.uuidString)"
    }

    static func navigationStage(
        for userID: UUID,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> NavigationStage? {
        guard let data = defaults.data(forKey: navigationKey(for: userID)),
              let snapshot = try? JSONDecoder().decode(
                NavigationSnapshot.self, from: data
              ),
              snapshot.savedAt <= now.addingTimeInterval(300),
              now.timeIntervalSince(snapshot.savedAt) < 14 * 86_400
        else { return nil }
        return snapshot.stage
    }

    static func setNavigationStage(
        _ stage: NavigationStage,
        for userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        let snapshot = NavigationSnapshot(stage: stage, savedAt: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: navigationKey(for: userID))
        }
    }

    static func clearNavigationStage(
        for userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: navigationKey(for: userID))
    }

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
