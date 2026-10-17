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

    func testLiveWatchRequiresPositiveReplyBeforeStarting() {
        let liveButTimedOut = AppleWatchActivityStartPolicy.resolve(
            watchReachable: true, cachedActive: false,
            reply: nil, replyIsCurrent: false
        )
        XCTAssertEqual(liveButTimedOut, .unconfirmed)

        let idle = WatchWorkoutActivityState(
            isActive: false, title: nil, updatedAt: Date()
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: false,
                reply: idle, replyIsCurrent: true
            ),
            .clear
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: false,
                reply: idle, replyIsCurrent: false
            ),
            .unconfirmed
        )
    }

    func testActiveWatchCannotBeOverriddenByOldOrMissingReply() {
        let active = WatchWorkoutActivityState(
            isActive: true, title: "Run", updatedAt: Date()
        )
        let idle = WatchWorkoutActivityState(
            isActive: false, title: nil, updatedAt: Date()
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: true,
                reply: active, replyIsCurrent: true
            ),
            .active
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: true,
                reply: idle, replyIsCurrent: false
            ),
            .unconfirmed
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: true,
                reply: nil, replyIsCurrent: false
            ),
            .unconfirmed
        )
    }

    func testSleepingWatchKeepsPhoneFallbackUnlessActiveWasReported() {
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: false, cachedActive: false,
                reply: nil, replyIsCurrent: false
            ),
            .clear
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: false, cachedActive: true,
                reply: nil, replyIsCurrent: false
            ),
            .unconfirmed
        )
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
