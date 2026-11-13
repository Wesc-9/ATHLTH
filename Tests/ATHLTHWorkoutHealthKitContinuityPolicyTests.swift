import XCTest
@testable import ATHLTH

/// Internal training phases do not change the HealthKit workout clock.
/// Only a deliberate whole-workout pause, or optional outdoor auto-pause,
/// may pause the session.
final class ATHLTHWorkoutHealthKitContinuityPolicyTests: XCTestCase {
    func testInternalRecoveryNeverPausesHealthKitForAnyWorkoutKind() {
        for kind in WatchWorkoutKind.allCases {
            XCTAssertFalse(
                ATHLTHWorkoutHealthKitContinuityPolicy
                    .pausesWorkoutForInternalRecoveryOrRest(kind: kind),
                "Internal rest must not pause HealthKit for \(kind.rawValue)"
            )
        }
    }

    func testAutomaticPauseIsOnlyAvailableForRunningAndWalking() {
        for kind in WatchWorkoutKind.allCases {
            XCTAssertEqual(
                ATHLTHWorkoutHealthKitContinuityPolicy
                    .supportsAutomaticPause(kind),
                kind == .running || kind == .walking,
                "Unexpected auto-pause eligibility for \(kind.rawValue)"
            )
        }
    }

    func testStructuredRunningAndWalkingNeverAutoPauseDuringIntervals() {
        for kind in WatchWorkoutKind.allCases {
            XCTAssertFalse(
                ATHLTHWorkoutHealthKitContinuityPolicy.mayAutoPause(
                    kind: kind, hasStructuredIntervals: true
                ),
                "A recovery phase must not truncate HealthKit duration"
            )
        }
        XCTAssertTrue(
            ATHLTHWorkoutHealthKitContinuityPolicy.mayAutoPause(
                kind: .running, hasStructuredIntervals: false
            )
        )
        XCTAssertTrue(
            ATHLTHWorkoutHealthKitContinuityPolicy.mayAutoPause(
                kind: .walking, hasStructuredIntervals: false
            )
        )
    }

    func testUnexpectedStrengthPauseIsRecoveredWhenNotRequestedByAthlete() {
        XCTAssertTrue(
            ATHLTHWorkoutHealthKitContinuityPolicy.shouldResumeUnexpectedPause(
                kind: .strength, userPausedWholeWorkout: false,
                finishing: false
            )
        )

        XCTAssertFalse(
            ATHLTHWorkoutHealthKitContinuityPolicy.shouldResumeUnexpectedPause(
                kind: .strength, userPausedWholeWorkout: true,
                finishing: false
            )
        )

        XCTAssertFalse(
            ATHLTHWorkoutHealthKitContinuityPolicy.shouldResumeUnexpectedPause(
                kind: .strength, userPausedWholeWorkout: false,
                finishing: true
            )
        )
    }

    func testOtherNonAutoPauseSportsRecoverUnexpectedPause() {
        for kind in WatchWorkoutKind.allCases {
            let shouldRecover =
                !ATHLTHWorkoutHealthKitContinuityPolicy.supportsAutomaticPause(kind)
            XCTAssertEqual(
                ATHLTHWorkoutHealthKitContinuityPolicy.shouldResumeUnexpectedPause(
                    kind: kind, userPausedWholeWorkout: false, finishing: false
                ),
                shouldRecover,
                "Unexpected pause recovery in \(kind.rawValue)"
            )
            XCTAssertFalse(
                ATHLTHWorkoutHealthKitContinuityPolicy.shouldResumeUnexpectedPause(
                    kind: kind, userPausedWholeWorkout: true, finishing: false
                ),
                "An intentional pause must never auto-resume"
            )
        }
    }
}
