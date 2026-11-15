import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHConversationPreferenceSyncTests: XCTestCase {
    private let conversation = UUID()
    private let older = Date(timeIntervalSince1970: 10)
    private let newer = Date(timeIntervalSince1970: 20)

    func testNewDeviceRestoresPinnedAndArchivedConversation() {
        let remote = ATHLTHConversationPreference(
            conversationID: conversation,
            pinnedAt: newer, unpinnedAt: nil,
            archivedAt: newer, unarchivedAt: nil
        )
        let result = ATHLTHConversationPreferenceSyncService.merged(
            local: [:], remote: [conversation: remote]
        )
        XCTAssertTrue(result[conversation]?.isPinned == true)
        XCTAssertTrue(result[conversation]?.isArchived == true)
    }

    func testOfflineOldPinCannotUndoNewerUnpin() {
        let old = ATHLTHConversationPreference(
            conversationID: conversation,
            pinnedAt: older, unpinnedAt: nil,
            archivedAt: nil, unarchivedAt: nil
        )
        let newerChange = ATHLTHConversationPreference(
            conversationID: conversation,
            pinnedAt: nil, unpinnedAt: newer,
            archivedAt: nil, unarchivedAt: nil
        )
        let result = ATHLTHConversationPreference.merged(old, newerChange)
        XCTAssertFalse(result.isPinned)
    }

    func testMostRecentArchiveChoiceWinsFromEitherDevice() {
        let archive = ATHLTHConversationPreference(
            conversationID: conversation,
            pinnedAt: nil, unpinnedAt: nil,
            archivedAt: older, unarchivedAt: nil
        )
        let unarchive = ATHLTHConversationPreference(
            conversationID: conversation,
            pinnedAt: nil, unpinnedAt: nil,
            archivedAt: nil, unarchivedAt: newer
        )
        XCTAssertFalse(ATHLTHConversationPreference.merged(archive, unarchive).isArchived)
        XCTAssertFalse(ATHLTHConversationPreference.merged(unarchive, archive).isArchived)
    }
}
