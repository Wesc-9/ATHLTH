import XCTest
@testable import ATHLTH

final class ATHLTHLiveActivityDisplayPolicyTests: XCTestCase {
    func testRunningAndWalkingUseDifferentHeadlineMetrics() {
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.resolve(
                kindRaw: "running", phase: "running",
                hasStrengthExercise: false, restEndsAt: nil,
                hasTimedSetCountdown: false, hasRunningStep: false
            ), .running
        )
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.resolve(
                kindRaw: "walking", phase: "running",
                hasStrengthExercise: false, restEndsAt: nil,
                hasTimedSetCountdown: false, hasRunningStep: false
            ), .walking
        )
    }

    func testRunningStepOverridesFreePaceInBothSports() {
        for kind in ["running", "walking"] {
            XCTAssertEqual(
                ATHLTHLiveActivityDisplayPolicy.resolve(
                    kindRaw: kind, phase: "running",
                    hasStrengthExercise: false, restEndsAt: nil,
                    hasTimedSetCountdown: false, hasRunningStep: true
                ), .runningInterval
            )
        }
    }

    func testStrengthRestOverridesTimedSetAndReps() {
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.resolve(
                kindRaw: "strength", phase: "running",
                hasStrengthExercise: true,
                restEndsAt: Date(timeIntervalSince1970: 100),
                hasTimedSetCountdown: true, hasRunningStep: false
            ), .strengthRest
        )
    }

    func testWorkoutPauseCannotPretendStrengthOrIntervalIsActive() {
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.resolve(
                kindRaw: "strength", phase: "paused",
                hasStrengthExercise: true, restEndsAt: nil,
                hasTimedSetCountdown: true, hasRunningStep: false
            ), .paused
        )
    }

    func testStrengthTimedSetIsNotReps() {
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.resolve(
                kindRaw: "strength", phase: "running",
                hasStrengthExercise: true, restEndsAt: nil,
                hasTimedSetCountdown: true, hasRunningStep: false
            ), .strengthTimedSet
        )
    }

    func testMissingMetricDoesNotBecomeNaNOrOutOfRange() {
        XCTAssertNil(ATHLTHLiveActivityDisplayPolicy.safeProgress(.nan))
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.safeProgress(-1), 0)
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.safeProgress(2), 1)
    }

    func testDisconnectedSnapshotIsNotClaimedAsLive() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(
            ATHLTHLiveActivityDisplayPolicy.isRecent(
                updatedAt: now.addingTimeInterval(-4), now: now
            )
        )
        XCTAssertFalse(
            ATHLTHLiveActivityDisplayPolicy.isRecent(
                updatedAt: now.addingTimeInterval(-35), now: now
            )
        )
    }

    func testSetCountdownStopsAtZeroAndPauseKeepsTime() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.remainingTimedSet(
                secondsAtSnapshot: 75, resumedAt: start,
                now: start.addingTimeInterval(30)
            ), 45
        )
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.remainingTimedSet(
                secondsAtSnapshot: 75, resumedAt: nil,
                now: start.addingTimeInterval(300)
            ), 75
        )
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.remainingTimedSet(
                secondsAtSnapshot: 75, resumedAt: start,
                now: start.addingTimeInterval(120)
            ), 0
        )
    }
    func testCyclingNeedsMeasuredDistanceForPrimaryMetric() {
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.resolve(
                kindRaw: "cycling", phase: "running",
                hasStrengthExercise: false, restEndsAt: nil,
                hasTimedSetCountdown: false, hasRunningStep: false,
                recordedDistanceMeters: 3250
            ), .cycling
        )
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.resolve(
                kindRaw: "cycling", phase: "running",
                hasStrengthExercise: false, restEndsAt: nil,
                hasTimedSetCountdown: false, hasRunningStep: false,
                recordedDistanceMeters: 0
            ), .elapsed
        )
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.resolve(
                kindRaw: "cycling", phase: "running",
                hasStrengthExercise: false, restEndsAt: nil,
                hasTimedSetCountdown: false, hasRunningStep: false,
                recordedDistanceMeters: .nan
            ), .elapsed
        )
    }


    func testCompactIslandRepetitionsDoNotShowLongUnitText() {
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactRepetitions(8), "8×")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactRepetitions(12), "12×")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactRepetitions(nil), "—")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactRepetitions(-1), "—")
    }

    func testCompactIslandDistanceKeepsKmUnitAlongsideMusic() {
        // The iOS 27 narrow Dynamic Island must not replace "km" with "k".
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactDistance(500), "500m")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactDistance(1_800), "1.8 km")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactDistance(2_400), "2.4 km")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactDistance(12_300), "12.3 km")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactDistance(.nan), "—")
    }

    func testCompactIslandLongSessionsUseShortDuration() {
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactDuration(300), "5:00")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactDuration(3_905), "1h05")
        XCTAssertEqual(ATHLTHLiveActivityDisplayPolicy.compactDuration(.infinity), "—")
    }

    func testDynamicIslandShowsBrandOnlyDuringTransitions() {
        for phase in ["idle", "preparing", "ending", "completed", "failed"] {
            XCTAssertTrue(ATHLTHLiveActivityDisplayPolicy.showsBrandMark(phase: phase))
        }
        for phase in ["running", "paused"] {
            XCTAssertFalse(ATHLTHLiveActivityDisplayPolicy.showsBrandMark(phase: phase))
        }
    }

    func testStrengthCompactIslandPrioritizesElapsedTime() {
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.compactMetric(focus: .strengthSet),
            .elapsed
        )
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.compactMetric(focus: .strengthRest),
            .strengthRest
        )
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.compactMetric(focus: .strengthTimedSet),
            .strengthTimedSet
        )
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.compactMetric(focus: .paused),
            .paused
        )
    }

    func testRunningCompactIslandPrioritizesAvailablePaceOrTime() {
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.compactMetric(
                focus: .running, pace: 310
            ), .pace
        )
        let invalidPaces: [TimeInterval?] = [nil, .nan, 0, 2_000]
        for pace in invalidPaces {
            XCTAssertEqual(
                ATHLTHLiveActivityDisplayPolicy.compactMetric(
                    focus: .running, pace: pace
                ), .elapsed
            )
        }
        XCTAssertEqual(
            ATHLTHLiveActivityDisplayPolicy.compactMetric(
                focus: .runningInterval
            ), .runningInterval
        )
    }

    func testWalkingAndCyclingOnlyUseValidRecordedDistance() {
        for sport in [
            ATHLTHLiveActivityDisplayFocus.walking,
            ATHLTHLiveActivityDisplayFocus.cycling
        ] {
            XCTAssertEqual(
                ATHLTHLiveActivityDisplayPolicy.compactMetric(
                    focus: sport, distanceMeters: 4100
                ), .distance
            )
            XCTAssertEqual(
                ATHLTHLiveActivityDisplayPolicy.compactMetric(
                    focus: sport, distanceMeters: 0
                ), .elapsed
            )
            XCTAssertEqual(
                ATHLTHLiveActivityDisplayPolicy.compactMetric(
                    focus: sport, distanceMeters: .nan
                ), .elapsed
            )
        }
    }

    func testIntervalTransitionKeyChangesImmediatelyForTheNextEffort() {
        func key(
            ordinal: Int = 1, recovery: Bool = false,
            title: String = "Work", awaiting: Bool = false
        ) -> String? {
            ATHLTHLiveActivityDisplayPolicy.runningTransitionKey(
                kindRaw: "running", stepIndex: ordinal,
                stepTitle: title, nextStepTitle: "Recovery",
                intervalOrdinal: ordinal, intervalTotal: 4,
                isRecovery: recovery, awaitingMainStart: awaiting
            )
        }
        XCTAssertNotNil(key())
        XCTAssertNotEqual(key(), key(ordinal: 2))
        XCTAssertNotEqual(key(), key(recovery: true))
        XCTAssertNotEqual(key(), key(title: "Recovery"))
        XCTAssertNotEqual(key(), key(awaiting: true))
    }

    func testFreeRunningUsesStableKeyAndOtherSportsDoNotBorrowIntervals() {
        let first = ATHLTHLiveActivityDisplayPolicy.runningTransitionKey(
            kindRaw: "running", stepIndex: nil,
            stepTitle: nil, nextStepTitle: nil,
            intervalOrdinal: nil, intervalTotal: nil,
            isRecovery: nil, awaitingMainStart: nil
        )
        XCTAssertEqual(first, ATHLTHLiveActivityDisplayPolicy.runningTransitionKey(
            kindRaw: "running", stepIndex: nil,
            stepTitle: nil, nextStepTitle: nil,
            intervalOrdinal: nil, intervalTotal: nil,
            isRecovery: nil, awaitingMainStart: nil
        ))
        XCTAssertNil(ATHLTHLiveActivityDisplayPolicy.runningTransitionKey(
            kindRaw: "strength", stepIndex: 1,
            stepTitle: "Set", nextStepTitle: "Rest",
            intervalOrdinal: 1, intervalTotal: 4,
            isRecovery: false, awaitingMainStart: false
        ))
    }

    func testStaleRunningPacketCannotCreateFreshActivityAfterReconnection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(ATHLTHLiveActivityDisplayPolicy.acceptsActivityCapture(
            updatedAt: now.addingTimeInterval(-20),
            isTerminal: false, now: now
        ))
        XCTAssertFalse(ATHLTHLiveActivityDisplayPolicy.acceptsActivityCapture(
            updatedAt: now.addingTimeInterval(-100),
            isTerminal: false, now: now
        ))
        XCTAssertFalse(ATHLTHLiveActivityDisplayPolicy.acceptsActivityCapture(
            updatedAt: now.addingTimeInterval(15),
            isTerminal: false, now: now
        ))
        XCTAssertTrue(ATHLTHLiveActivityDisplayPolicy.acceptsActivityCapture(
            updatedAt: now.addingTimeInterval(-1_200),
            isTerminal: true, now: now
        ))
        XCTAssertFalse(ATHLTHLiveActivityDisplayPolicy.acceptsActivityCapture(
            updatedAt: Date(timeIntervalSince1970: .infinity),
            isTerminal: true, now: now
        ))
    }

}
