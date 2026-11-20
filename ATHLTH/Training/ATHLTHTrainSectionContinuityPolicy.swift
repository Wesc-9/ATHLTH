import Foundation

/// SceneStorage is device/scene-scoped, not athlete-scoped. Never reuse the
/// previous athlete's Train navigation after an account switch. Legacy
/// entries without an owner are treated as Today, without removing drafts.
enum ATHLTHTrainSectionContinuityPolicy {
    static func restoredSection(
        _ persistedSection: String,
        persistedAccountID: String,
        currentAccountID: UUID
    ) -> String {
        guard persistedAccountID == currentAccountID.uuidString else {
            return "today"
        }
        switch persistedSection {
        case "plan", "progress": return persistedSection
        default: return "today"
        }
    }
}
