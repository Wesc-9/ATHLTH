import XCTest
@testable import ATHLTH

final class ATHLTHNotificationWorkoutInvitationPolicyTests: XCTestCase {
    func testCancelledWorkoutIsNeverActionableEvenIfEventSaysInvite() {
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .cancelled, participantState: .invited
            ),
            .cancelled
        )
    }

    func testCompletedWorkoutLeavesAttentionSection() {
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .completed, participantState: .invited
            ),
            .completed
        )
    }

    func testOnlyActivePendingInvitationIsActionable() {
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .active, participantState: .invited
            ),
            .actionable
        )
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .active, participantState: .accepted
            ),
            .accepted
        )
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .active, participantState: .declined
            ),
            .declined
        )
    }

    func testMissingSessionIsNotMislabelledDeletedOrCancelled() {
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: nil, participantState: .invited
            ),
            .unverified
        )
    }
}
