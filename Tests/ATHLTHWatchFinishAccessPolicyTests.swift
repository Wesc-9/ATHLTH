import XCTest
@testable import ATHLTH

final class ATHLTHWatchFinishAccessPolicyTests: XCTestCase {
    private func eligible(
        progress: Double? = 97,
        remaining: Double? = 70,
        finishDistance: Double? = 34,
        accuracy: Double? = 8,
        age: Double? = 2,
        elapsed: Double = 1_800,
        warmup: Bool = false,
        awaitingMain: Bool = false
    ) -> Bool {
        ATHLTHWatchFinishAccessPolicy.shouldShowRouteFinish(
            routeProgressPercent: progress,
            routeRemainingMeters: remaining,
            metersFromFinish: finishDistance,
            gpsHorizontalAccuracy: accuracy,
            gpsAgeSeconds: age,
            workoutElapsedSeconds: elapsed,
            inWarmup: warmup,
            awaitingMainStart: awaitingMain
        )
    }

    func testVisibleOnlyAtVerifiedFinish() {
        XCTAssertTrue(eligible())
        XCTAssertFalse(eligible(progress: 5, remaining: 50,
                                finishDistance: 20)) // Loop starts beside the finish.
        XCTAssertFalse(eligible(progress: 70))
        XCTAssertFalse(eligible(remaining: 240))
        XCTAssertFalse(eligible(finishDistance: 185))
    }

    func testGpsMustBeAccurateAndCurrent() {
        XCTAssertFalse(eligible(accuracy: 65))
        XCTAssertFalse(eligible(age: 21))
        XCTAssertFalse(eligible(accuracy: nil))
        XCTAssertFalse(eligible(finishDistance: nil))
        XCTAssertFalse(eligible(progress: nil))
    }

    func testWarmupOrShortStartNeverShowsFinishButton() {
        XCTAssertFalse(eligible(warmup: true))
        XCTAssertFalse(eligible(awaitingMain: true))
        XCTAssertFalse(eligible(elapsed: 30))
        XCTAssertFalse(eligible(progress: 100, remaining: 0,
                                finishDistance: 0, elapsed: 0))
    }

    func testNoInvalidSensorInputCountsAsFinish() {
        XCTAssertFalse(eligible(progress: .nan))
        XCTAssertFalse(eligible(remaining: -.infinity))
        XCTAssertFalse(eligible(finishDistance: .infinity))
    }
}
