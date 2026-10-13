import Foundation

/// Shared discovery categories for Community. The data sources remain separate,
/// but users get one predictable way to discover Clubs, Events and Challenges.
enum ATHLTHCommunityDiscoveryCategory: String, CaseIterable, Identifiable {
    case all
    case clubs
    case events
    case challenges

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .clubs: "person.3"
        case .events: "calendar"
        case .challenges: "trophy"
        }
    }

    var localizedTitle: String {
        switch self {
        case .all:
            ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
        case .clubs:
            ATHLTHLocalization.choose(english: "Clubs", norwegian: "Klubber")
        case .events:
            ATHLTHLocalization.choose(english: "Events", norwegian: "Arrangementer")
        case .challenges:
            ATHLTHLocalization.choose(english: "Challenges", norwegian: "Utfordringer")
        }
    }
}

enum ATHLTHCommunityDiscoveryPolicy {
    /// Case- and diacritic-insensitive on the locally available, permitted data.
    /// Public/private visibility filtering happens before this function.
    static func matches(_ query: String, in fields: [String]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { word in
            fields.contains { field in
                field.range(
                    of: String(word),
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "nb_NO")
                ) != nil
            }
        }
    }
}
