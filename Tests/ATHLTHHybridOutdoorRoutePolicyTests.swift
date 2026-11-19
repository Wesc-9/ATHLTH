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
}
