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
    func testOldUnansweredWorkoutNotificationBecomesCancelled() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .active,
                participantState: .invited,
                scheduledStart: start,
                now: now
            ), .cancelled
        )
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .active,
                participantState: .accepted,
                scheduledStart: start,
                now: now
            ), .accepted
        )
    }

    func testFutureOrStartedWorkoutNotificationRemainsCorrect() {
        let now = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .active,
                participantState: .invited,
                scheduledStart: Date(timeIntervalSince1970: 3_000),
                now: now
            ), .actionable
        )
        XCTAssertEqual(
            ATHLTHNotificationWorkoutInvitationPolicy.status(
                sessionStatus: .active,
                participantState: .invited,
                scheduledStart: Date(timeIntervalSince1970: 1_000),
                isPlanned: false,
                now: now
            ), .actionable
        )
    }

}
