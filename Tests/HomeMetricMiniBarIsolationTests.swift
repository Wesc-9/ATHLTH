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


final class HomeTrainingLoadTrendTests: XCTestCase {
    func testLatestTrainingDaySkipsRestDaysWithoutChangingChartValues() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let points: [HomeMetricPoint] = [
            .init(date: today.addingTimeInterval(-2 * 86_400), value: 43),
            .init(date: today.addingTimeInterval(-86_400), value: 48),
            .init(date: today, value: 0)
        ]
        let latest = HomeTrainingLoadTrend.latestTrainingDay(in: points)
        XCTAssertEqual(latest?.value, 48)
        XCTAssertEqual(latest?.date, points[1].date)
        XCTAssertEqual(points.map(\.value), [43, 48, 0])
    }

    func testLatestTrainingDayUsesDateAndRejectsMissingOrInvalidValues() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let points: [HomeMetricPoint] = [
            .init(date: today, value: .infinity),
            .init(date: today.addingTimeInterval(-86_400), value: 35),
            .init(date: today.addingTimeInterval(-2 * 86_400), value: 60),
            .init(date: today, value: nil),
            .init(date: today, value: -5)
        ]
        XCTAssertEqual(HomeTrainingLoadTrend.latestTrainingDay(in: points)?.value, 35)
        XCTAssertNil(HomeTrainingLoadTrend.latestTrainingDay(in: []))
        XCTAssertNil(HomeTrainingLoadTrend.latestTrainingDay(in: [.init(date: today, value: 0)]))
    }

    func testTodayIsLatestWhenTrainingIsRecordedToday() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(HomeTrainingLoadTrend.latestTrainingDay(in: [
            .init(date: today, value: 15),
            .init(date: today.addingTimeInterval(-86_400), value: 48)
        ])?.value, 15)
    }
}
