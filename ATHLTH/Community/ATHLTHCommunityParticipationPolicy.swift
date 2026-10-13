import Foundation

/// Shared RSVP vocabulary for public and Club events. Their server-side
/// enrollment and deadline rules remain independent and authoritative.
enum ATHLTHCommunityRSVPDecision: String, CaseIterable, Identifiable {
    case going
    case maybe
    case notGoing = "not_going"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .going:
            ATHLTHLocalization.choose(english: "Going", norwegian: "Skal")
        case .maybe:
            ATHLTHLocalization.choose(english: "Maybe", norwegian: "Kanskje")
        case .notGoing:
            ATHLTHLocalization.choose(english: "Can't go", norwegian: "Kan ikke")
        }
    }

    var symbol: String {
        switch self {
        case .going: "checkmark.circle"
        case .maybe: "questionmark.circle"
        case .notGoing: "xmark.circle"
        }
    }

    static func resolvedStatus(_ serverValue: String?) -> ATHLTHCommunityRSVPDecision? {
        guard let serverValue else { return nil }
        // A waitlisted athlete has actively chosen "going", but their
        // participation has not yet been confirmed.
        if serverValue == "waitlist" { return .going }
        return ATHLTHCommunityRSVPDecision(rawValue: serverValue)
    }
}
