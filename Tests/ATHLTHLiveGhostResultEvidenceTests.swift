import XCTest
@testable import ATHLTH

final class ATHLTHLiveGhostResultEvidenceTests: XCTestCase {
    private let sharedStart = Date(timeIntervalSince1970: 1_800_000_000)

    func testSyncedBothFinishesArePlausible() {
        XCTAssertTrue(ATHLTHLiveGhostResultEvidence.bothFinishesPlausible(
            synchronizedStart: sharedStart,
            firstFinish: sharedStart.addingTimeInterval(601),
            firstElapsed: 600,
            secondFinish: sharedStart.addingTimeInterval(634),
            secondElapsed: 630
        ))
    }

    func testOfflineDelayedFinishRequiresReviewRatherThanInventingWinner() {
        XCTAssertEqual(ATHLTHLiveGhostResultEvidence.assess(
            synchronizedStart: sharedStart,
            recordedFinish: sharedStart.addingTimeInterval(780),
            elapsedSeconds: 600
        ), .needsReview)
    }

    func testWatchLaunchedTooLateRequiresReview() {
        XCTAssertEqual(ATHLTHLiveGhostResultEvidence.assess(
            synchronizedStart: sharedStart,
            recordedFinish: sharedStart.addingTimeInterval(640),
            elapsedSeconds: 600
        ), .needsReview)
    }

    func testMissingServerStartCannotCertifyRace() {
        XCTAssertEqual(ATHLTHLiveGhostResultEvidence.assess(
            synchronizedStart: nil,
            recordedFinish: sharedStart.addingTimeInterval(600),
            elapsedSeconds: 600
        ), .pending)
    }

    func testFinishBeforeSharedStartIsRejected() {
        XCTAssertEqual(ATHLTHLiveGhostResultEvidence.assess(
            synchronizedStart: sharedStart,
            recordedFinish: sharedStart.addingTimeInterval(-2),
            elapsedSeconds: 600
        ), .needsReview)
    }

    func testCorruptDurationsAreNeverPlausible() {
        for seconds: Double in [.nan, .infinity, -4, 2, 90_000] {
            XCTAssertEqual(ATHLTHLiveGhostResultEvidence.assess(
                synchronizedStart: sharedStart,
                recordedFinish: sharedStart.addingTimeInterval(600),
                elapsedSeconds: seconds
            ), .needsReview)
        }
    }

    func testPausedSessionMustNotBePresentedAsVerifiedRaceTime() {
        XCTAssertEqual(ATHLTHLiveGhostResultEvidence.assess(
            synchronizedStart: sharedStart,
            recordedFinish: sharedStart.addingTimeInterval(900),
            elapsedSeconds: 600
        ), .needsReview)
    }
}
