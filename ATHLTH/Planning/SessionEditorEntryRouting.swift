import Foundation

/// New personal planning must always ask for a source first. An existing
/// saved draft offers an explicit Resume choice instead of silently bypassing
/// the picker. Editing, shared workout proposals and partner-specific flows
/// retain their existing entry behavior.
enum SessionEditorEntryRouting {
    static func requiresSourceChoice(
        isStandalone: Bool,
        hasExistingWorkout: Bool,
        hasInitialSource: Bool,
        isPreparedWorkout: Bool,
        hasDirectPartner: Bool,
        hasSavedDraft: Bool
    ) -> Bool {
        // A stored draft does not change the entry route.
        _ = hasSavedDraft
        return isStandalone && !hasExistingWorkout && !hasInitialSource
            && !isPreparedWorkout && !hasDirectPartner
    }
}
