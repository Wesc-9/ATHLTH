import XCTest
@testable import ATHLTH

final class ATHLTHArenaStatusPresentationTests: XCTestCase {
    func testActiveAndDraftDoNotShareTheSameStatus() {
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.series(status: "active"), .active
        )
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.series(status: "draft"), .waiting
        )
    }

    func testExpiredCompetitionNeedsReviewEvenIfStillMarkedActive() {
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.series(
                status: "active", deadlinePassed: true
            ), .needsReview
        )
    }

    func testDisputedCompletedCompetitionDoesNotClaimFinalResult() {
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.series(
                status: "completed", unresolved: true
            ), .needsReview
        )
    }

    func testOnlyApprovedResultsUseCompletedStatus() {
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.result(status: "approved"), .completed
        )
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.result(status: "pending"), .waiting
        )
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.result(status: "rejected"), .needsReview
        )
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.result(status: "expired"), .needsReview
        )
    }

    func testLiveInvitationNeedsExplicitResponse() {
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.liveRace(
                status: "pending", requiresResponse: true
            ), .needsReview
        )
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.liveRace(status: "accepted"), .ready
        )
    }

    func testUnknownStateDoesNotPretendToBeApproved() {
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.series(status: "unexpected"),
            .unavailable
        )
        XCTAssertEqual(
            ATHLTHArenaStatusPresentation.result(status: "unexpected"),
            .unavailable
        )
    }
}
