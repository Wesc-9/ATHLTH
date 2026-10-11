import XCTest
@testable import ATHLTH

final class ATHLTHLivePresentationModelTests: XCTestCase {
    func testFreeRunPrioritizesPaceAndDistance() {
        let plan = ATHLTHLivePresentationResolver.resolve(
            .init(kind: .running, state: .running)
        )
        XCTAssertEqual(plan.phase, .active)
        XCTAssertEqual(plan.primary, .pace)
        XCTAssertEqual(plan.secondary, [.distance, .heartRate, .elapsed])
        XCTAssertFalse(plan.pages.contains(.intervals))
    }

    func testStructuredRunAddsIntervalsWithoutHidingMetrics() {
        let plan = ATHLTHLivePresentationResolver.resolve(
            .init(
                kind: .running,
                state: .running,
                hasStructuredRunningStep: true,
                hasHeartRateTarget: true,
                hasRoute: true,
                hasGhost: true,
                hasAudioCoach: true
            )
        )
        XCTAssertEqual(plan.primary, .pace)
        XCTAssertEqual(
            plan.pages,
            [.overview, .intervals, .pulse, .route, .ghost,
             .audioCoach, .music, .controls]
        )
    }

    func testStrengthRestOverridesSetTargets() {
        let plan = ATHLTHLivePresentationResolver.resolve(
            .init(
                kind: .strength,
                state: .running,
                isStrengthResting: true,
                isTimedStrengthSet: true
            )
        )
        XCTAssertEqual(plan.phase, .resting)
        XCTAssertEqual(plan.primary, .restRemaining)
        XCTAssertEqual(plan.pages.first, .set)
    }

    func testTimeTargetDoesNotPretendToBeRunningCountdown() {
        let planned = ATHLTHLivePresentationResolver.resolve(
            .init(kind: .strength, state: .running,
                  isTimedStrengthSet: true)
        )
        let running = ATHLTHLivePresentationResolver.resolve(
            .init(kind: .strength, state: .running,
                  isTimedStrengthSet: true,
                  hasActiveTimedSetCountdown: true)
        )
        XCTAssertEqual(planned.primary, .strengthTimeTarget)
        XCTAssertEqual(running.primary, .strengthTimeRemaining)
    }

    func testPausedWorkoutIsNotAutomaticallyResting() {
        let plan = ATHLTHLivePresentationResolver.resolve(
            .init(kind: .strength, state: .paused,
                  isStrengthResting: true)
        )
        XCTAssertEqual(plan.phase, .paused)
        XCTAssertEqual(plan.primary, .reps)
    }

    func testWalkingAndCyclingPreferDistance() {
        for kind: WatchWorkoutKind in [.walking, .cycling] {
            let plan = ATHLTHLivePresentationResolver.resolve(
                .init(kind: kind, state: .running)
            )
            XCTAssertEqual(plan.primary, .distance)
        }
    }

    func testGenericActivitiesShowElapsedInsteadOfMadeUpPace() {
        for kind: WatchWorkoutKind in [.hiit, .rowing, .yoga, .other] {
            let plan = ATHLTHLivePresentationResolver.resolve(
                .init(kind: kind, state: .running)
            )
            XCTAssertEqual(plan.primary, .elapsed)
        }
    }

    func testTreadmillPageOnlyAppearsForTreadmill() {
        let normal = ATHLTHLivePresentationResolver.resolve(
            .init(kind: .running, state: .running)
        )
        let treadmill = ATHLTHLivePresentationResolver.resolve(
            .init(kind: .running, state: .running,
                  hasTreadmillIncline: true)
        )
        XCTAssertFalse(normal.pages.contains(.treadmill))
        XCTAssertTrue(treadmill.pages.contains(.treadmill))
    }

    func testCompletedWorkoutDoesNotRemainLive() {
        let plan = ATHLTHLivePresentationResolver.resolve(
            .init(kind: .running, state: .completed)
        )
        XCTAssertEqual(plan.phase, .completed)
    }
}

extension ATHLTHLivePresentationModelTests {
    func testStrengthNavigationRetainsCorePages() {
        let plan = ATHLTHLivePresentationResolver.resolve(
            .init(kind: .strength, state: .running)
        )
        XCTAssertEqual(
            plan.pages,
            [.set, .rest, .exercises, .summary, .music, .controls]
        )
        XCTAssertEqual(plan.primary, .reps)
    }

    func testStrengthCountdownAndWarmUpNeverInventReps() {
        let plan = ATHLTHLivePresentationResolver.resolve(
            .init(
                kind: .strength,
                state: .running,
                isTimedStrengthSet: true
            )
        )
        XCTAssertEqual(plan.primary, .strengthTimeTarget)
        XCTAssertFalse(plan.secondary.contains(.reps))
    }

    func testStrengthPauseRemainsExplicit() {
        let plan = ATHLTHLivePresentationResolver.resolve(
            .init(
                kind: .strength,
                state: .running,
                isStrengthResting: true
            )
        )
        XCTAssertEqual(plan.phase, .resting)
        XCTAssertEqual(plan.primary, .restRemaining)
    }
}

extension ATHLTHLivePresentationModelTests {
    func testTimedStrengthCountdownAnchorsToAbsoluteDate() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let countdown = WatchTimedStrengthCountdown(
            targetSeconds: 300,
            secondsAtPause: 300,
            resumedAt: start
        )
        XCTAssertEqual(countdown.remaining(at: start), 300, accuracy: 0.001)
        XCTAssertEqual(
            countdown.remaining(at: start.addingTimeInterval(75)),
            225, accuracy: 0.001
        )
        XCTAssertEqual(
            countdown.remaining(at: start.addingTimeInterval(350)),
            0, accuracy: 0.001
        )
    }

    func testTimedStrengthCountdownPausedAndResumedWithoutDrift() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var timer = WatchTimedStrengthCountdown(
            targetSeconds: 120,
            secondsAtPause: 120,
            resumedAt: start
        )
        let pausedAt = start.addingTimeInterval(40)
        timer.secondsAtPause = timer.remaining(at: pausedAt)
        timer.resumedAt = nil

        XCTAssertEqual(
            timer.remaining(at: pausedAt.addingTimeInterval(300)),
            80, accuracy: 0.001
        )

        timer.resumedAt = pausedAt.addingTimeInterval(300)
        XCTAssertEqual(
            timer.remaining(at: pausedAt.addingTimeInterval(320)),
            60, accuracy: 0.001
        )
    }

    func testTimedStrengthCountdownRoundTripsOverWire() throws {
        let timer = WatchTimedStrengthCountdown(
            targetSeconds: 180,
            secondsAtPause: 92.5,
            resumedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let data = try JSONEncoder().encode(timer)
        XCTAssertEqual(
            try JSONDecoder().decode(WatchTimedStrengthCountdown.self, from: data),
            timer
        )
    }

    func testTimeControlCommandsUseDistinctTypes() {
        let events: [WatchStrengthCommandKind] = [
            .startTimedSet, .pauseTimedSet, .resetTimedSet
        ]
        XCTAssertEqual(Set(events).count, 3)
    }
}
