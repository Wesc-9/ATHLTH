import Foundation

/// Generic tab routing; notification deep links and account-specific actions
/// are handled before this fallback, in the root presentation layer.
enum ATHLTHRootNotificationTabPolicy {
    static func destinationTab(for rawKind: String?) -> Int? {
        guard let kind = rawKind?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !kind.isEmpty else { return nil }
        let communityKinds = [
            "message", "friend", "challenge", "reaction",
            "workout", "event"
        ]
        return communityKinds.contains(where: kind.contains) ? 4 : 0
    }
}
