import SwiftUI

/// A single entry point to the existing Club chat rooms.
/// Uses the authenticated user's memberships; does not invent a separate
/// messaging store or show Clubs where the user cannot open the chat.
struct ATHLTHClubChatInboxSection: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    let searchText: String
    @Binding var isExpanded: Bool

    private var visibleClubs: [CommunityGroupRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.joinedGroups
            .filter { group in
                guard !query.isEmpty else { return true }
                if group.name.localizedCaseInsensitiveContains(query) {
                    return true
                }
                if groups.messages(in: group.id).contains(where: {
                    $0.body.localizedCaseInsensitiveContains(query)
                }) { return true }
                return groups.recentClubMessagesByGroup[group.id]?
                    .body.localizedCaseInsensitiveContains(query) ?? false
            }
            .sorted { lhs, rhs in
                let lhsLatest = latestMessage(in: lhs.id)?.createdAt
                let rhsLatest = latestMessage(in: rhs.id)?.createdAt
                if let lhsLatest, let rhsLatest, lhsLatest != rhsLatest {
                    return lhsLatest > rhsLatest
                }
                if lhsLatest != nil { return true }
                if rhsLatest != nil { return false }
                return lhs.name.localizedStandardCompare(rhs.name)
                    == .orderedAscending
            }
    }

    var body: some View {
        if !visibleClubs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(ATHLTHLocalization.choose(
                            english: "CLUB",
                            norwegian: "KLUBB"
                        ))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        Spacer()
                        let unreadClubCount = visibleClubs.filter {
                            groups.unreadClubGroupIDs.contains($0.id)
                        }.count
                        if unreadClubCount > 0 {
                            Text("\(unreadClubCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Color.orange, in: Capsule())
                        }
                        Text("\(visibleClubs.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        Image(systemName: isExpanded
                              ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Club chats", norwegian: "Klubbchatter"
                ))
                .accessibilityValue(isExpanded
                    ? ATHLTHLocalization.choose(english: "Expanded", norwegian: "Åpen")
                    : ATHLTHLocalization.choose(english: "Collapsed", norwegian: "Lukket"))
                .accessibilityIdentifier("athlth-club-inbox-disclosure")

                if isExpanded {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleClubs) { club in
                            NavigationLink {
                                CommunityGroupDetailView(
                                    group: club, initialTab: .chat
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    CommunityGroupIdentityAvatar(
                                        group: club, size: 52
                                    )
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(club.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ATHLTHTheme.primaryText)
                                            .lineLimit(1)

                                        if let message = latestMessage(in: club.id) {
                                            Text(ATHLTHClubInboxPolicy.previewText(
                                                clubName: club.name,
                                                message: message
                                            ))
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                            .lineLimit(2)
                                        } else {
                                            Text(ATHLTHLocalization.choose(
                                                english: "Open Club chat",
                                                norwegian: "Åpne klubbchatten"
                                            ))
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                                .padding(13)
                                .background(
                                    Color.white.opacity(0.87),
                                    in: RoundedRectangle(cornerRadius: 18)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func latestMessage(in groupID: UUID) -> CommunityGroupMessageRecord? {
        let stored = groups.messages(in: groupID)
            .max { $0.createdAt < $1.createdAt }
        let preview = groups.recentClubMessagesByGroup[groupID]
        guard let stored else { return preview }
        guard let preview else { return stored }
        return stored.createdAt >= preview.createdAt ? stored : preview
    }
}
