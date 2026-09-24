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
            return social.friends.sorted {
                $0.resolvedName.localizedCaseInsensitiveCompare(
                    $1.resolvedName
                ) == .orderedAscending
            }
        }

        let term = cleanQuery.lowercased()

        return social.friends.filter {
            $0.resolvedName.lowercased().contains(term) ||
            $0.usernameLabel.lowercased().contains(term)
        }
    }

    private var searchedPeople: [SocialProfileCard] {
        guard cleanQuery.count >= 2 else { return [] }

        let friendIDs = Set(social.friends.map(\.userID))

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
                    accent: ATHLTHTheme.recoveryBlue.opacity(0.34)
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        introCard

                        if cleanQuery.isEmpty {
                            friendsSection
                        } else {
                            if !filteredFriends.isEmpty {
                                peopleSection(
                                    title: "FRIENDS",
                                    people: filteredFriends
                                )
                            }

                            if cleanQuery.count >= 2 {
                                if searchedPeople.isEmpty &&
                                    filteredFriends.isEmpty {
                                    ContentUnavailableView.search(
                                        text: cleanQuery
                                    )
                                    .padding(.vertical, 56)
                                } else if !searchedPeople.isEmpty {
                                    peopleSection(
                                        title: "PEOPLE",
                                        people: searchedPeople
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search name or @username"
            )
            .focused($searchFocused)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                if social.friends.isEmpty {
                    await social.refresh()
                }
                searchFocused = true
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

    private var introCard: some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 46, height: 46)
                    .background(
                        ATHLTHTheme.recoveryBlueSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start a conversation")
                        .font(.headline)
                    Text(
                        "Friends can chat immediately. Other athletes can receive one message request if their privacy settings allow it."
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
        if social.friends.isEmpty {
            VStack(spacing: 14) {
                ContentUnavailableView(
                    "Find someone to message",
                    systemImage: "person.2.wave.2",
                    description: Text(
                        "Search by name or @username. You can send one message request before becoming friends when the recipient allows it."
                    )
                )

                Text("Start typing in the search field above.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        } else {
            peopleSection(
                title: "FRIENDS",
                people: Array(social.friends.prefix(20))
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
                    NavigationLink {
                        DirectMessageThreadView(friend: profile)
                    } label: {
                        NewMessagePersonRow(profile: profile)
                    }
                    .buttonStyle(.plain)

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
}

private struct NewMessagePersonRow: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore

    let profile: SocialProfileCard

    private var relationship: SocialRelationshipState {
        social.relationshipState(with: profile.userID)
    }

    private var hasConversation: Bool {
        messaging.conversation(with: profile.userID) != nil
    }

    private var actionTitle: String {
        if hasConversation {
            return "Open"
        }

        switch relationship {
        case .friends:
            return "Message"
        default:
            return "Request"
        }
    }

    private var actionIcon: String {
        relationship == .friends || hasConversation
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

                    if relationship == .friends {
                        Text("• Friend")
                    } else if !hasConversation {
                        Text("• Message request")
                    }
                }
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
            }

            Spacer()

            Label(actionTitle, systemImage: actionIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    ATHLTHTheme.accentSoft.opacity(0.72),
                    in: Capsule()
                )
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}
