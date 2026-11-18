import SwiftUI

/// Inbox notification for a new member-only Club chat message. Behaves
/// like a normal conversation row and opens the existing Club chat.
struct ATHLTHUnreadClubMessageRow: View {
    let group: CommunityGroupRecord
    let message: CommunityGroupMessageRecord

    var body: some View {
        NavigationLink {
            CommunityGroupDetailView(group: group, initialTab: .chat)
        } label: {
            HStack(spacing: 13) {
                CommunityGroupIdentityAvatar(group: group, size: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)
                    Text(ATHLTHClubInboxPolicy.previewText(
                        clubName: group.name, message: message
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(2)
                }
                Spacer(minLength: 5)
                VStack(alignment: .trailing, spacing: 10) {
                    Text(message.createdAt, style: .relative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Color.white.opacity(0.88),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlth-unread-club-message")
    }
}
