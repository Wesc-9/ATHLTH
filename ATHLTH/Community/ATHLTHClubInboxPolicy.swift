import Foundation

/// Only message previews from clubs the viewer has joined enter the inbox.
enum ATHLTHClubInboxPolicy {
    static func isUnread(
        message: CommunityGroupMessageRecord,
        lastReadAt: Date,
        viewerID: UUID
    ) -> Bool {
        message.senderID != viewerID && message.createdAt > lastReadAt
    }

    static func previewText(
        clubName: String,
        message: CommunityGroupMessageRecord
    ) -> String {
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = body.isEmpty
            ? ATHLTHLocalization.choose(english: "Photo", norwegian: "Bilde")
            : body
        return clubName + ": " + content
    }
}
