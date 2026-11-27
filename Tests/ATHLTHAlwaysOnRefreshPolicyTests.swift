import XCTest
@testable import ATHLTH

final class ATHLTHAlwaysOnRefreshPolicyTests: XCTestCase {
    func testOnlyActiveCountdownRequestsOneSecond() {
        XCTAssertEqual(ATHLTHAlwaysOnRefreshPolicy.loweredWristInterval, 60)
        XCTAssertEqual(ATHLTHAlwaysOnRefreshPolicy.countdownInterval(isRunning: true), 1)
        XCTAssertEqual(ATHLTHAlwaysOnRefreshPolicy.countdownInterval(isRunning: false), 60)
    }

    func testGhostCadence() {
        XCTAssertEqual(ATHLTHAlwaysOnRefreshPolicy.ghostInterval(isRunning: true, lowPower: false), 5)
        XCTAssertEqual(ATHLTHAlwaysOnRefreshPolicy.ghostInterval(isRunning: true, lowPower: true), 10)
        XCTAssertEqual(ATHLTHAlwaysOnRefreshPolicy.ghostInterval(isRunning: false, lowPower: false), 60)
    }

    func testLowPowerProtectsPrecisionWorkouts() {
        XCTAssertEqual(ATHLTHWatchPerformancePolicy.mirrorInterval(lowPower: false, needsLivePrecision: false), 0.85)
        XCTAssertEqual(ATHLTHWatchPerformancePolicy.mirrorInterval(lowPower: true, needsLivePrecision: true), 0.85)
        XCTAssertEqual(ATHLTHWatchPerformancePolicy.mirrorInterval(lowPower: true, needsLivePrecision: false), 2)
        XCTAssertEqual(ATHLTHWatchPerformancePolicy.locationDistanceFilter(lowPower: true, isFreeWalk: true, needsLivePrecision: true), 3)
        XCTAssertEqual(ATHLTHWatchPerformancePolicy.locationDistanceFilter(lowPower: true, isFreeWalk: false, needsLivePrecision: false), 3)
        XCTAssertEqual(ATHLTHWatchPerformancePolicy.locationDistanceFilter(lowPower: true, isFreeWalk: true, needsLivePrecision: false), 5)
        XCTAssertEqual(ATHLTHWatchPerformancePolicy.locationDistanceFilter(lowPower: false, isFreeWalk: true, needsLivePrecision: false), 3)
    }
}
