import Foundation

/// A draft is scoped to the signed-in athlete and its workout editor path.
/// Do not discard a real draft because ephemeral step IDs, source recipes or
/// the plan's optimistic-lock version change while the app is not running.
enum ATHLTHWorkoutDraftRecoveryPolicy {
    static func accepts(
        storedSignature: String,
        currentSignature: String,
        context: String,
        storedSourceTitle: String?,
        currentSourceTitle: String,
        storedSourceID: UUID?,
        currentSourceID: UUID?,
        savedAt: Date,
        now: Date = Date()
    ) -> Bool {
        if storedSignature == currentSignature { return true }

        // A changed source can be intentional. Only recover a mismatched
        // signature when this is a recent draft of the same editor context.
        guard savedAt <= now.addingTimeInterval(60 * 5),
              savedAt >= now.addingTimeInterval(-30 * 24 * 3_600)
        else { return false }
        guard storedSourceID == nil || storedSourceID == currentSourceID else {
            return false
        }

        let scoped = context.hasPrefix("plan-") ||
            context.hasPrefix("catalog-copy-") ||
            context.hasPrefix("coach-")
        if scoped { return true }

        // The shared scratch editor is reused across unrelated workouts:
        // never silently replace a different explicitly selected source.
        if let storedSourceTitle {
            return storedSourceTitle == currentSourceTitle
        }
        // v1 drafts did not store the source title separately. Its old
        // signature begins with the original title followed by '|'.
        // Allow an older personal draft to survive this app update.
        if !currentSourceTitle.isEmpty {
            return storedSignature.hasPrefix(currentSourceTitle + "|")
        }
        return currentSourceID == nil
    }

    /// The plan/day/workout key already identifies the source of truth.
    /// The plan's revision number is intentionally *not* part of the identity:
    /// a passive sync must not erase unsaved exercises or intervals.
    static func canRestorePlanDraft(
        storedVersion: Int,
        currentVersion: Int,
        hasActualWorkout: Bool
    ) -> Bool {
        // Preserve an unsaved same-editor draft across passive plan refreshes.
        // The actual save still enforces the latest plan version.
        hasActualWorkout && storedVersion >= 0 && currentVersion >= 0
    }
}
