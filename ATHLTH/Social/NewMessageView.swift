import SwiftUI

struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var cleanQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredFriends: [SocialProfileCard] {
        guard !cleanQuery.isEmpty else {
            return social.mutualFollows.sorted {
                $0.resolvedName.localizedCaseInsensitiveCompare(
                    $1.resolvedName
                ) == .orderedAscending
            }
        }

        let term = cleanQuery.lowercased()

        return social.mutualFollows.filter {
            $0.resolvedName.lowercased().contains(term) ||
            $0.usernameLabel.lowercased().contains(term)
        }
    }

    private var searchedPeople: [SocialProfileCard] {
        guard cleanQuery.count >= 2 else { return [] }

        let friendIDs = Set(social.mutualFollows.map(\.userID))

        return social.discoverResults.filter {
            !friendIDs.contains($0.userID) &&
            social.relationshipState(with: $0.userID) != .selfUser &&
            social.relationshipState(with: $0.userID) != .blocked
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.10)
                )

                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 16
                    ) {
                        newMessageHeader
                        premiumSearchField

                        if cleanQuery.isEmpty {
                            friendsSection
                        } else {
                            if !filteredFriends.isEmpty {
                                peopleSection(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english:
                                                "MUTUAL FOLLOWS",
                                            norwegian:
                                                "FØLGER HVERANDRE"
                                        ),
                                    people:
                                        filteredFriends
                                )
                            }

                            if cleanQuery.count >= 2 {
                                if searchedPeople.isEmpty &&
                                    filteredFriends.isEmpty {
                                    ContentUnavailableView.search(
                                        text:
                                            cleanQuery
                                    )
                                    .padding(
                                        .vertical,
                                        56
                                    )
                                } else if !searchedPeople.isEmpty {
                                    peopleSection(
                                        title:
                                            ATHLTHLocalization.choose(
                                                english:
                                                    "PEOPLE",
                                                norwegian:
                                                    "PERSONER"
                                            ),
                                        people:
                                            searchedPeople
                                    )
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(
                        .bottom,
                        28
                    )
                    .frame(maxWidth: 680)
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .scrollDismissesKeyboard(
                    .interactively
                )
                .scrollIndicators(
                    .hidden
                )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbarBackground(
                .hidden,
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
            .task {
                if social.mutualFollows.isEmpty {
                    await social.refresh()
                }
                // Allow choosing a mutual friend without opening a keyboard
                // over half of the sheet. Focus search only on empty state.
                searchFocused = social.mutualFollows.isEmpty
            }
            .task(id: cleanQuery) {
                let term = cleanQuery

                guard term.count >= 2 else {
                    if term.isEmpty {
                        social.clearSearch()
                    }
                    return
                }

                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                await social.search(term)
            }
        }
    }

    private var newMessageHeader: some View {
        ATHLTHMessagingCompactHeader(
            eyebrow: ATHLTHLocalization.choose(
                english: "Messages", norwegian: "Meldinger"
            ),
            title: ATHLTHLocalization.choose(
                english: "New message", norwegian: "Ny melding"
            ),
            symbol: "square.and.pencil"
        )
    }

    private var premiumSearchField: some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    "magnifyingglass"
            )
            .font(
                .system(
                    size: 16,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .premiumGold
            )

            TextField(
                ATHLTHLocalization.choose(
                    english:
                        "Search name or @username",
                    norwegian:
                        "Søk navn eller @brukernavn"
                ),
                text: $query
            )
            .focused(
                $searchFocused
            )
            .textInputAutocapitalization(
                .never
            )
            .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(
                        systemName:
                            "xmark.circle.fill"
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(
            .horizontal,
            14
        )
        .frame(height: 50)
        .background(
            Color.white
                .opacity(0.82),
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .border,
                lineWidth: 0.8
            )
        }
    }

    private var introCard: some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .frame(width: 46, height: 46)
                    .background(
                        ATHLTHTheme.premiumGoldSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start a conversation")
                        .font(.headline)
                    Text(
                        "Mutual followers can chat immediately. Everyone else receives one message request to approve or decline before the conversation continues."
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var friendsSection: some View {
        if social.mutualFollows.isEmpty {
            VStack(spacing: 14) {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english: "Find someone to message",
                        norwegian: "Finn noen å sende melding til"
                    ),
                    systemImage: "person.2.wave.2",
                    description: Text(
                        ATHLTHLocalization.choose(
                            english: "Search by name or @username. New contacts receive a request they can accept or decline.",
                            norwegian: "Søk etter navn eller @brukernavn. Nye kontakter får en forespørsel de kan godta eller avslå."
                        )
                    )
                )

                Text(ATHLTHLocalization.choose(
                    english: "Start typing in the search field above.",
                    norwegian: "Søk i feltet over."
                ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        } else {
            peopleSection(
                title: ATHLTHLocalization.choose(
                    english: "MUTUAL FOLLOWS", norwegian: "FØLGER HVERANDRE"
                ),
                people: Array(filteredFriends.prefix(20))
            )
        }
    }

    private func peopleSection(
        title: String,
        people: [SocialProfileCard]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.8)
                .foregroundStyle(ATHLTHTheme.mutedText)

            VStack(spacing: 0) {
                ForEach(people) { profile in
                    if isDeclinedRequester(profile) {
                        NewMessagePersonRow(profile: profile)
                            .opacity(0.72)
                    } else {
                        NavigationLink {
                            DirectMessageThreadView(friend: profile)
                        } label: {
                            NewMessagePersonRow(profile: profile)
                        }
                        .buttonStyle(.plain)
                    }

                    if profile.id != people.last?.id {
                        Divider()
                            .padding(.leading, 70)
                            .opacity(0.45)
                    }
                }
            }
            .background(
                ATHLTHTheme.card,
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.74), lineWidth: 1)
            }
        }
    }

    private func isDeclinedRequester(
        _ profile: SocialProfileCard
    ) -> Bool {
        guard let conversation =
                messaging.conversation(with: profile.userID),
              let currentUserID = messaging.currentUserID
        else {
            return false
        }

        return conversation.requestStatus == .declined &&
            conversation.requestedBy == currentUserID
    }
}

private struct NewMessagePersonRow: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore

    let profile: SocialProfileCard

    private var relationship: SocialRelationshipState {
        social.relationshipState(with: profile.userID)
    }

    private var conversation: DirectConversationRecord? {
        messaging.conversation(with: profile.userID)
    }

    private var hasConversation: Bool {
        conversation != nil
    }

    private var isDeclinedRequester: Bool {
        guard let conversation,
              let currentUserID = messaging.currentUserID
        else {
            return false
        }

        return conversation.requestStatus == .declined &&
            conversation.requestedBy == currentUserID
    }

    private var actionTitle: String {
        if isDeclinedRequester {
            return ATHLTHLocalization.choose(
                english: "Declined", norwegian: "Avslått"
            )
        }

        if hasConversation {
            return ATHLTHLocalization.choose(
                english: "Open", norwegian: "Åpne"
            )
        }

        return social.isMutualFollow(profile.userID)
            ? ATHLTHLocalization.choose(
                english: "Message", norwegian: "Melding"
            )
            : ATHLTHLocalization.choose(
                english: "Request", norwegian: "Forespør"
            )
    }

    private var actionIcon: String {
        if isDeclinedRequester {
            return "xmark.circle.fill"
        }

        return social.isMutualFollow(profile.userID) || hasConversation
            ? "message.fill"
            : "paperplane.fill"
    }

    var body: some View {
        HStack(spacing: 13) {
            SocialAvatar(profile: profile, size: 50)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.resolvedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !profile.usernameLabel.isEmpty {
                        Text(profile.usernameLabel)
                    }

                    if social.isMutualFollow(profile.userID) {
                        Text(ATHLTHLocalization.choose(
                            english: "• Mutual follow", norwegian: "• Følger hverandre"
                        ))
                    } else if isDeclinedRequester {
                        Text(ATHLTHLocalization.choose(
                            english: "• Request declined", norwegian: "• Forespørsel avslått"
                        ))
                    } else if !hasConversation {
                        Text(ATHLTHLocalization.choose(
                            english: "• Message request", norwegian: "• Meldingsforespørsel"
                        ))
                    }
                }
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
            }

            Spacer()

            Label(actionTitle, systemImage: actionIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.premiumGold)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    ATHLTHTheme.premiumGoldSoft.opacity(0.72),
                    in: Capsule()
                )
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}
