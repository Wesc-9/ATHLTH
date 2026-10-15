import SwiftUI

/// A single entry point to the existing Club chat rooms.
/// Uses the authenticated user's memberships; does not invent a separate
/// messaging store or show Clubs where the user cannot open the chat.
struct ATHLTHClubChatInboxSection: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    let searchText: String

    private var visibleClubs: [CommunityGroupRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.joinedGroups
            .filter { group in
                guard !query.isEmpty else { return true }
                if group.name.localizedCaseInsensitiveContains(query) {
                    return true
                }
                return groups.messages(in: group.id).contains {
                    $0.body.localizedCaseInsensitiveContains(query)
                }
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
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(ATHLTHLocalization.choose(
                        english: "CLUB CHATS",
                        norwegian: "KLUBBCHATTER"
                    ))
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    Spacer()
                    Text("\(visibleClubs.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                ForEach(visibleClubs) { group in
                    NavigationLink {
                        CommunityGroupDetailView(group: group, initialTab: .chat)
                    } label: {
                        HStack(spacing: 12) {
                            CommunityGroupIdentityAvatar(group: group, size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                    .lineLimit(1)

                                if let message = latestMessage(in: group.id) {
                                    Text(message.senderName + ": " + message.body)
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
        }
    }

    private func latestMessage(in groupID: UUID) -> CommunityGroupMessageRecord? {
        groups.messages(in: groupID).max { $0.createdAt < $1.createdAt }
    }
}
