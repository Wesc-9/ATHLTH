import XCTest
@testable import ATHLTH

final class HomeMetricMiniBarIsolationTests: XCTestCase {
    func testBarSizingPreservesExistingHomeBehavior() {
        XCTAssertEqual(
            HomeMetricMiniBarMath.barHeight(
                value: nil, maximum: 100, availableHeight: 80, zeroIsEmpty: false
            ), 4
        )
        XCTAssertEqual(
            HomeMetricMiniBarMath.barHeight(
                value: 0, maximum: 1, availableHeight: 80, zeroIsEmpty: true
            ), 0
        )
        XCTAssertEqual(
            HomeMetricMiniBarMath.barHeight(
                value: 0, maximum: 1, availableHeight: 80, zeroIsEmpty: false
            ), 4
        )
        XCTAssertEqual(
            HomeMetricMiniBarMath.barHeight(
                value: 50, maximum: 100, availableHeight: 80, zeroIsEmpty: true
            ), 40
        )
        XCTAssertEqual(
            HomeMetricMiniBarMath.barHeight(
                value: 150, maximum: 100, availableHeight: 80, zeroIsEmpty: false
            ), 80
        )
    }

    func testScaleRoundingDoesNotChange() {
        XCTAssertEqual(HomeMetricMiniBarMath.roundedScaleMaximum(0), 1)
        XCTAssertEqual(HomeMetricMiniBarMath.roundedScaleMaximum(31), 40)
        XCTAssertEqual(HomeMetricMiniBarMath.roundedScaleMaximum(75), 100)
        XCTAssertEqual(HomeMetricMiniBarMath.roundedScaleMaximum(0.32), 0.4, accuracy: 0.00001)
    }
}
