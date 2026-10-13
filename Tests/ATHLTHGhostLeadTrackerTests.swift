import XCTest
@testable import ATHLTH

final class ATHLTHGhostLeadTrackerTests: XCTestCase {
    func testSingleGPSSpikeCannotRecordOvertake() {
        var tracker = ATHLTHGhostLeadTracker()
        XCTAssertFalse(tracker.observe(signedGapMeters: -40, elapsedSeconds: 10))
        XCTAssertFalse(tracker.observe(signedGapMeters: 22, elapsedSeconds: 11))
        XCTAssertFalse(tracker.observe(signedGapMeters: -36, elapsedSeconds: 12))
        XCTAssertEqual(tracker.confirmedSign, -1)
    }

    func testTwoSeparatedSamplesConfirmARealOvertake() {
        var tracker = ATHLTHGhostLeadTracker()
        _ = tracker.observe(signedGapMeters: -20, elapsedSeconds: 10)
        XCTAssertFalse(tracker.observe(signedGapMeters: 19, elapsedSeconds: 20))
        XCTAssertTrue(tracker.observe(signedGapMeters: 25, elapsedSeconds: 23))
        XCTAssertEqual(tracker.confirmedSign, 1)
        XCTAssertFalse(tracker.observe(signedGapMeters: 30, elapsedSeconds: 25))
    }

    func testDuplicateAndTooRapidSnapshotsNeverConfirmPassing() {
        var tracker = ATHLTHGhostLeadTracker()
        _ = tracker.observe(signedGapMeters: -50, elapsedSeconds: 10)
        XCTAssertFalse(tracker.observe(signedGapMeters: 50, elapsedSeconds: 15))
        XCTAssertFalse(tracker.observe(signedGapMeters: 55, elapsedSeconds: 15))
        XCTAssertFalse(tracker.observe(signedGapMeters: 60, elapsedSeconds: 16))
        XCTAssertTrue(tracker.observe(signedGapMeters: 65, elapsedSeconds: 17))
    }

    func testNearTieCancelsPendingLeaderChange() {
        var tracker = ATHLTHGhostLeadTracker()
        _ = tracker.observe(signedGapMeters: -25, elapsedSeconds: 10)
        _ = tracker.observe(signedGapMeters: 20, elapsedSeconds: 12)
        _ = tracker.observe(signedGapMeters: 2, elapsedSeconds: 14)
        XCTAssertFalse(tracker.observe(signedGapMeters: 20, elapsedSeconds: 16))
        XCTAssertTrue(tracker.observe(signedGapMeters: 20, elapsedSeconds: 18))
    }

    func testInvalidOrOutOfOrderSamplesDoNotConfirmOvertake() {
        var tracker = ATHLTHGhostLeadTracker()
        _ = tracker.observe(signedGapMeters: -25, elapsedSeconds: 10)
        _ = tracker.observe(signedGapMeters: 30, elapsedSeconds: 20)
        XCTAssertFalse(tracker.observe(signedGapMeters: .nan, elapsedSeconds: 21))
        XCTAssertFalse(tracker.observe(signedGapMeters: 30, elapsedSeconds: 19))
        XCTAssertFalse(tracker.observe(signedGapMeters: 30, elapsedSeconds: 22))
        XCTAssertTrue(tracker.observe(signedGapMeters: 30, elapsedSeconds: 25))
    }
}
