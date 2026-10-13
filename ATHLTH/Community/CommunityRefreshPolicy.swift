import Foundation

/// The front page should tell the user which Community area is out of date
/// instead of showing a generic error that makes the entire tab look broken.
enum ATHLTHCommunityRefreshArea: String, CaseIterable, Identifiable {
    case events
    case clubs
    case weekly
    case friends
    case messages
    case live

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .events: ATHLTHLocalization.choose(english: "Events", norwegian: "Arrangementer")
        case .clubs: ATHLTHLocalization.choose(english: "Clubs", norwegian: "Klubber")
        case .weekly: ATHLTHLocalization.choose(english: "Weekly challenge", norwegian: "Ukesutfordring")
        case .friends: ATHLTHLocalization.choose(english: "Friends", norwegian: "Venner")
        case .messages: ATHLTHLocalization.choose(english: "Messages", norwegian: "Meldinger")
        case .live: ATHLTHLocalization.choose(english: "Live training", norwegian: "Direktetrening")
        }
    }
}

enum ATHLTHCommunityRefreshPolicy {
    static func failedAreas(
        events: Bool,
        clubs: Bool,
        weekly: Bool,
        friends: Bool,
        messages: Bool,
        live: Bool
    ) -> [ATHLTHCommunityRefreshArea] {
        ATHLTHCommunityRefreshArea.allCases.filter {
            switch $0 {
            case .events: events
            case .clubs: clubs
            case .weekly: weekly
            case .friends: friends
            case .messages: messages
            case .live: live
            }
        }
    }

    static func notice(
        for areas: [ATHLTHCommunityRefreshArea]
    ) -> String? {
        guard !areas.isEmpty else { return nil }
        let unique = ATHLTHCommunityRefreshArea.allCases.filter {
            areas.contains($0)
        }
        let names = unique.map(\.localizedTitle).joined(separator: ", ")
        return ATHLTHLocalization.choose(
            english: "Couldn't update: \(names). Other sections still show the latest available content.",
            norwegian: "Kunne ikke oppdatere: \(names). Andre seksjoner viser sist tilgjengelige innhold."
        )
    }
}
