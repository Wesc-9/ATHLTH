import Foundation
import XCTest
@testable import ATHLTH

final class AppleWatchConnectionPolicyTests: XCTestCase {
    func testRecentWatchAcknowledgementIsFreshOnlyForTwoMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: nil,
            now: now
        ))
        XCTAssertTrue(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: now.addingTimeInterval(-119),
            now: now
        ))
        XCTAssertTrue(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: now.addingTimeInterval(-120),
            now: now
        ))
        XCTAssertFalse(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: now.addingTimeInterval(-121),
            now: now
        ))
        XCTAssertFalse(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: now.addingTimeInterval(10),
            now: now
        ))
    }

    func testUnreachableActiveWatchShowsARecoverableSafetyMessage() {
        let error = AppleWatchActivityStartPolicy.blockingError(
            hasActiveWatchWorkout: true,
            isWatchReachable: false
        )
        guard case .watchWorkoutStatusUnconfirmed = error else {
            return XCTFail("Must distinguish an offline active Watch from a confirmed active session")
        }
        XCTAssertNotNil(error.errorDescription)
    }

    func testReachableActiveWatchStillReportsAnActiveSession() {
        let error = AppleWatchActivityStartPolicy.blockingError(
            hasActiveWatchWorkout: true,
            isWatchReachable: true
        )
        guard case .workoutAlreadyActive = error else {
            return XCTFail("Active Watch sessions must continue blocking duplicate launch")
        }
    }

    func testNoCachedWatchActivityUsesOriginalBlockReason() {
        let error = AppleWatchActivityStartPolicy.blockingError(
            hasActiveWatchWorkout: false,
            isWatchReachable: false
        )
        guard case .workoutAlreadyActive = error else {
            return XCTFail("A different active iPhone session must retain its existing error")
        }
    }
}
