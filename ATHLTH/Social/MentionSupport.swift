import SwiftUI

struct ATHLTHMentionSuggestion: Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: String?
    let isEveryone: Bool

    init(
        username: String,
        displayName: String,
        avatarURL: String? = nil,
        isEveryone: Bool = false
    ) {
        self.id = username.lowercased()
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isEveryone = isEveryone
    }
}

enum ATHLTHMentionSupport {
    static func suggestions(
        in text: String,
        candidates: [SocialProfileCard],
        includeEveryone: Bool = false
    ) -> [ATHLTHMentionSuggestion] {
        guard let active = activeMention(in: text) else {
            return []
        }

        let query = active.query.lowercased()
        var values: [ATHLTHMentionSuggestion] = []

        if includeEveryone &&
            (
                query.isEmpty ||
                "everyone".hasPrefix(query) ||
                "all".hasPrefix(query) ||
                "alle".hasPrefix(query)
            ) {
            values.append(
                ATHLTHMentionSuggestion(
                    username: "everyone",
                    displayName: "Everyone",
                    avatarURL: nil,
                    isEveryone: true
                )
            )
        }

        let people = candidates
            .compactMap { profile -> ATHLTHMentionSuggestion? in
                guard let username = profile.username?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    !username.isEmpty
                else {
                    return nil
                }

                return ATHLTHMentionSuggestion(
                    username: username,
                    displayName: profile.resolvedName,
                    avatarURL: profile.avatarURL
                )
            }
            .filter { suggestion in
                query.isEmpty ||
                    suggestion.username
                        .lowercased()
                        .hasPrefix(query) ||
                    suggestion.displayName
                        .lowercased()
                        .contains(query)
            }
            .sorted {
                $0.username.localizedCaseInsensitiveCompare(
                    $1.username
                ) == .orderedAscending
            }

        for suggestion in people
        where !values.contains(where: {
            $0.id == suggestion.id
        }) {
            values.append(suggestion)
        }

        return Array(values.prefix(3))
    }

    static func inserting(
        _ suggestion: ATHLTHMentionSuggestion,
        into text: String
    ) -> String {
        guard let active = activeMention(in: text) else {
            return text
        }

        var result = text
        result.replaceSubrange(
            active.range,
            with: "@\(suggestion.username) "
        )
        return result
    }

    private static func activeMention(
        in text: String
    ) -> (
        range: Range<String.Index>,
        query: String
    )? {
        guard !text.isEmpty else {
            return nil
        }

        var start = text.endIndex

        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]

            if character.isWhitespace ||
                character.isNewline {
                break
            }

            start = previous
        }

        let token = text[start..<text.endIndex]
        guard token.first == "@" else {
            return nil
        }

        let query = String(token.dropFirst())

        guard query.allSatisfy({
            $0.isLetter ||
            $0.isNumber ||
            $0 == "." ||
            $0 == "_" ||
            $0 == "-"
        }) else {
            return nil
        }

        return (
            start..<text.endIndex,
            query
        )
    }
}

struct ATHLTHMentionSuggestionList: View {
    let suggestions: [ATHLTHMentionSuggestion]
    let onSelect: (ATHLTHMentionSuggestion) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            suggestionAvatar(suggestion)

                            VStack(
                                alignment: .leading,
                                spacing: 1
                            ) {
                                Text(suggestion.displayName)
                                    .font(
                                        .subheadline
                                            .weight(.semibold)
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )
                                    .lineLimit(1)

                                Text("@\(suggestion.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)

                    if suggestion.id != suggestions.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                ATHLTHTheme.card,
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.border,
                    lineWidth: 1
                )
            }
            .shadow(
                color: Color.black.opacity(0.07),
                radius: 12,
                x: 0,
                y: 5
            )
        }
    }

    @ViewBuilder
    private func suggestionAvatar(
        _ suggestion: ATHLTHMentionSuggestion
    ) -> some View {
        if suggestion.isEveryone {
            Image(systemName: "person.3.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 34, height: 34)
                .background(
                    Color.indigo.opacity(0.10),
                    in: Circle()
                )
        } else if let value = suggestion.avatarURL,
                  let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    personFallback
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
        } else {
            personFallback
        }
    }

    private var personFallback: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .frame(width: 34, height: 34)
            .background(
                ATHLTHTheme.accentSoft,
                in: Circle()
            )
    }
}
