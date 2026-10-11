import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaInvitationReceiptTests: XCTestCase {
    private func receipt(_ response: String, slotID: UUID = UUID()) -> ATHLTHArenaInvitationReceipt {
        let json = """
        {"slot_id":"\(slotID.uuidString)","response":"\(response)"}
        """
        return try! JSONDecoder().decode(
            ATHLTHArenaInvitationReceipt.self,
            from: Data(json.utf8)
        )
    }

    func testSuccessfulAcceptRequiresExactlyOneUpdatedRow() {
        XCTAssertTrue(ATHLTHArenaInvitationReceipt.confirms(
            [receipt("accepted")], expected: "accepted"
        ))
    }

    func testSuccessfulDeclineRequiresExactlyOneUpdatedRow() {
        XCTAssertTrue(ATHLTHArenaInvitationReceipt.confirms(
            [receipt("declined")], expected: "declined"
        ))
    }

    func testSecondDeviceStaleZeroRowResponseIsNotSuccess() {
        XCTAssertFalse(ATHLTHArenaInvitationReceipt.confirms(
            [], expected: "accepted"
        ))
    }

    func testDuplicateUpdatedRowsAreNotReportedAsSuccess() {
        XCTAssertFalse(ATHLTHArenaInvitationReceipt.confirms(
            [receipt("accepted"), receipt("accepted")], expected: "accepted"
        ))
    }

    func testMismatchedResponseIsNotReportedAsSuccess() {
        XCTAssertFalse(ATHLTHArenaInvitationReceipt.confirms(
            [receipt("declined")], expected: "accepted"
        ))
    }
}
