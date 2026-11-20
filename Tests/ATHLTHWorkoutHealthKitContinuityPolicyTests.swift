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

    func testWatchSecondStartCannotResetActiveWorkoutForAnySport() {
        for kind in WatchWorkoutKind.allCases {
            XCTAssertTrue(
                ATHLTHWatchWorkoutStartAdmissionPolicy.canPrepare(
                    active: false, preparing: false,
                    ending: false, finishing: false
                ), kind.rawValue
            )
            XCTAssertFalse(
                ATHLTHWatchWorkoutStartAdmissionPolicy.canPrepare(
                    active: true, preparing: false,
                    ending: false, finishing: false
                ), kind.rawValue
            )
            XCTAssertFalse(
                ATHLTHWatchWorkoutStartAdmissionPolicy.canPrepare(
                    active: false, preparing: true,
                    ending: false, finishing: false
                ), kind.rawValue
            )
            XCTAssertFalse(
                ATHLTHWatchWorkoutStartAdmissionPolicy.canPrepare(
                    active: false, preparing: false,
                    ending: true, finishing: false
                ), kind.rawValue
            )
            XCTAssertFalse(
                ATHLTHWatchWorkoutStartAdmissionPolicy.canPrepare(
                    active: false, preparing: false,
                    ending: false, finishing: true
                ), kind.rawValue
            )
        }
    }


    func testWatchRecoveryAndOriginalHKSessionPreventNewWorkoutForEverySport() {
        for kind in WatchWorkoutKind.allCases {
            XCTAssertFalse(ATHLTHWatchWorkoutStartAdmissionPolicy.canPrepare(
                active: false, preparing: false, ending: false,
                finishing: false, recovering: true
            ), kind.rawValue)
            XCTAssertFalse(ATHLTHWatchWorkoutStartAdmissionPolicy.canPrepare(
                active: false, preparing: false, ending: false,
                finishing: false, hasExistingSession: true
            ), kind.rawValue)
            XCTAssertFalse(ATHLTHWatchWorkoutStartAdmissionPolicy.canPrepare(
                active: false, preparing: false, ending: false,
                finishing: false, recovering: true, hasExistingSession: true
            ), kind.rawValue)
        }
    }

    func testWatchResetNeverDropsLiveRecordingOrRecovery() {
        func mayReset(active: Bool = false, preparing: Bool = false,
                      ending: Bool = false, finishing: Bool = false,
                      recovering: Bool = false, hkLive: Bool = false) -> Bool {
            ATHLTHWatchWorkoutResetPolicy.mayClear(
                active: active, preparing: preparing, ending: ending,
                finishing: finishing, recovering: recovering,
                healthKitSessionInProgress: hkLive
            )
        }
        XCTAssertTrue(mayReset())
        XCTAssertFalse(mayReset(active: true))
        XCTAssertFalse(mayReset(preparing: true))
        XCTAssertFalse(mayReset(ending: true))
        XCTAssertFalse(mayReset(finishing: true))
        XCTAssertFalse(mayReset(recovering: true))
        XCTAssertFalse(mayReset(hkLive: true))
    }

    func testWatchFailedHealthKitSaveRetainsOnlyRealCheckpoint() {
        let p = ATHLTHWatchWorkoutFailureRecoveryPolicy.self
        XCTAssertTrue(p.shouldRetainCheckpoint(
            hasBuilder: true, hasOriginalStart: true,
            healthKitStartedOrEnded: true
        ))
        XCTAssertFalse(p.shouldRetainCheckpoint(
            hasBuilder: false, hasOriginalStart: true,
            healthKitStartedOrEnded: true
        ))
        XCTAssertFalse(p.shouldRetainCheckpoint(
            hasBuilder: true, hasOriginalStart: false,
            healthKitStartedOrEnded: true
        ))
        XCTAssertFalse(p.shouldRetainCheckpoint(
            hasBuilder: true, hasOriginalStart: true,
            healthKitStartedOrEnded: false
        ))
    }

}
