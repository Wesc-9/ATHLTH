import XCTest
@testable import ATHLTH

final class RunRouteMapPointModeTests: XCTestCase {
    func testAutomaticTapUsesStartThenFinishThenVia() {
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .automatic, hasStart: false, hasFinish: false),
            .start
        )
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .automatic, hasStart: true, hasFinish: false),
            .finish
        )
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .automatic, hasStart: true, hasFinish: true),
            .via
        )
    }

    func testSelectedPointModeOverridesAutomaticOrder() {
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .start, hasStart: true, hasFinish: true),
            .start
        )
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .finish, hasStart: false, hasFinish: false),
            .finish
        )
        XCTAssertEqual(
            RunRouteMapPointMode.resolve(mode: .via, hasStart: true, hasFinish: true),
            .via
        )
    }
}
