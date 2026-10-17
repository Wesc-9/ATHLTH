import Foundation

/// Target of a challenge reminder tapped in iOS Notification Center.
/// Keep both reminder types distinct: personal challenges use ChallengeStore,
/// while official weekly challenges use OfficialWeeklyChallengeStore.
enum ATHLTHChallengeNotificationRoute: Equatable, Identifiable {
    case personal(UUID)
    case officialWeekly(UUID)

    var id: String {
        switch self {
        case .personal(let id):
            return "personal:\(id.uuidString)"
        case .officialWeekly(let id):
            return "official-weekly:\(id.uuidString)"
        }
    }

    static func resolve(
        userInfo: [AnyHashable: Any]
    ) -> ATHLTHChallengeNotificationRoute? {
        // The official scheduler publishes its own ID key. Do not interpret
        // it as a personal challenge, even if other metadata is also present.
        if let rawID = userInfo["athlthOfficialWeeklyChallengeID"] as? String,
           let id = UUID(uuidString: rawID) {
            return .officialWeekly(id)
        }

        // Personal challenge reminders, including "24 hours left", have no
        // athlth_kind field. The ID is their authoritative destination.
        if let rawID = userInfo["athlthChallengeID"] as? String,
           let id = UUID(uuidString: rawID) {
            return .personal(id)
        }

        return nil
    }
}
