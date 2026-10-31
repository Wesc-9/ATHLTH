import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHLiveActivityStopPolicyTests: XCTestCase {
    func testStopAndFinishImmediatelyCloseLiveActivity() {
        XCTAssertTrue(ATHLTHLiveActivityStopPolicy.shouldDismiss(.ending))
        XCTAssertTrue(ATHLTHLiveActivityStopPolicy.shouldDismiss(.completed))
        XCTAssertTrue(ATHLTHLiveActivityStopPolicy.shouldDismiss(.failed))
    }

    func testPauseDoesNotEndLiveActivity() {
        XCTAssertFalse(ATHLTHLiveActivityStopPolicy.shouldDismiss(.preparing))
        XCTAssertFalse(ATHLTHLiveActivityStopPolicy.shouldDismiss(.running))
        XCTAssertFalse(ATHLTHLiveActivityStopPolicy.shouldDismiss(.paused))
    }

    func testLateRunningSnapshotCannotRestartStoppedTimer() {
        let stopped = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            fallbackTitle: "Run"
        )
        XCTAssertFalse(ATHLTHLiveActivityStopPolicy.mayStart(
            identity: stopped, lastStopped: stopped
        ))

        let nextWorkout = ATHLTHLiveActivitySessionIdentity(
            systemImage: "figure.run",
            startedAt: Date(timeIntervalSince1970: 1_800_001_000),
            fallbackTitle: "Run"
        )
        XCTAssertTrue(ATHLTHLiveActivityStopPolicy.mayStart(
            identity: nextWorkout, lastStopped: stopped
        ))
    }
}
