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
        let terms = normalized(trimmed).split(whereSeparator: \.isWhitespace)
        let normalizedFields = fields.map(normalized)
        return terms.allSatisfy { term in
            normalizedFields.contains { $0.contains(term) }
        }
    }

    /// Foundation's diacritic folding alone does not fold Norwegian ø to o
    /// or æ to ae. Map them explicitly so "loping" finds "Løping" too.
    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "nb_NO")
        )
        .replacingOccurrences(of: "ø", with: "o")
        .replacingOccurrences(of: "æ", with: "ae")
        .replacingOccurrences(of: "å", with: "a")
    }
}
