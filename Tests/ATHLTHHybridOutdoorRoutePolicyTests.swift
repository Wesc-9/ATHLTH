import XCTest
@testable import ATHLTH

final class ATHLTHHybridOutdoorRoutePolicyTests: XCTestCase {
    func testGPSCaptureRequiresOutdoorActiveRunningPhase() {
        XCTAssertFalse(ATHLTHHybridOutdoorRoutePolicy.mayCaptureStrengthRoute(
            isOutdoor: false, isEmbeddedRunningInterval: true
        ))
        XCTAssertFalse(ATHLTHHybridOutdoorRoutePolicy.mayCaptureStrengthRoute(
            isOutdoor: true, isEmbeddedRunningInterval: false
        ))
        XCTAssertTrue(ATHLTHHybridOutdoorRoutePolicy.mayCaptureStrengthRoute(
            isOutdoor: true, isEmbeddedRunningInterval: true
        ))
        XCTAssertFalse(ATHLTHHybridOutdoorRoutePolicy.mayCaptureStrengthRoute(
            isOutdoor: false, isEmbeddedRunningInterval: false
        ))
    }

    func testPausedFinishedOrRestingIntervalsNeverRecordGPS() {
        XCTAssertFalse(ATHLTHHybridOutdoorRoutePolicy.mayCaptureStrengthRoute(
            isOutdoor: true, isEmbeddedRunningInterval: true,
            isResting: true
        ))
        XCTAssertFalse(ATHLTHHybridOutdoorRoutePolicy.mayCaptureStrengthRoute(
            isOutdoor: true, isEmbeddedRunningInterval: true,
            isExerciseComplete: true
        ))
        XCTAssertFalse(ATHLTHHybridOutdoorRoutePolicy.mayCaptureStrengthRoute(
            isOutdoor: true, isEmbeddedRunningInterval: true,
            isWorkoutRunning: false
        ))
        XCTAssertTrue(ATHLTHHybridOutdoorRoutePolicy.mayCaptureStrengthRoute(
            isOutdoor: true, isEmbeddedRunningInterval: true,
            isResting: false, isExerciseComplete: false,
            isWorkoutRunning: true
        ))
    }
}
