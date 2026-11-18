import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHClubInboxPolicyTests: XCTestCase {
    private let groupID = UUID()
    private let senderID = UUID()
    private let viewerID = UUID()
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func message(body: String) -> CommunityGroupMessageRecord {
        CommunityGroupMessageRecord(
            id: UUID(),
            groupID: groupID,
            senderID: senderID,
            senderName: "Malin",
            body: body,
            imageURL: nil,
            createdAt: now
        )
    }

    func testUnreadOnlyWhenAnotherMemberPostedAfterLastRead() {
        let sample = message(body: "Hei!")
        XCTAssertTrue(ATHLTHClubInboxPolicy.isUnread(
            message: sample, lastReadAt: now.addingTimeInterval(-30),
            viewerID: viewerID
        ))
        XCTAssertFalse(ATHLTHClubInboxPolicy.isUnread(
            message: sample, lastReadAt: now, viewerID: viewerID
        ))
        XCTAssertFalse(ATHLTHClubInboxPolicy.isUnread(
            message: sample, lastReadAt: now.addingTimeInterval(-30),
            viewerID: senderID
        ))
    }

    func testClubNamePrefixesMessageAndPhoto() {
        XCTAssertEqual(
            ATHLTHClubInboxPolicy.previewText(
                clubName: "Testklubben", message: message(body: "Vi møtes kl. 18")
            ),
            "Testklubben: Vi møtes kl. 18"
        )
        XCTAssertEqual(
            ATHLTHClubInboxPolicy.previewText(
                clubName: "Testklubben", message: message(body: "")
            ),
            "Testklubben: " + ATHLTHLocalization.choose(
                english: "Photo", norwegian: "Bilde"
            )
        )
    }
}
