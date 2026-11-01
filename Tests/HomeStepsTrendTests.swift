import XCTest
@testable import ATHLTH

final class HomeStepsTrendTests: XCTestCase {
    func testSevenDayHistoryKeepsMissingDaysEmptyAndRealZero() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 1
        )))
        let samples = [
            ATHLTHInsightHealthDay(
                date: calendar.date(byAdding: .day, value: -6, to: today)!,
                value: 5_500
            ),
            ATHLTHInsightHealthDay(
                date: calendar.date(byAdding: .day, value: -2, to: today)!,
                value: 0
            ),
            ATHLTHInsightHealthDay(date: today, value: 2_302)
        ]
        let points = HomeStepsTrend.points(
            from: samples, days: 7, endingAt: today, calendar: calendar
        )
        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points[0].value, 5_500)
        XCTAssertNil(points[1].value)
        XCTAssertNil(points[3].value)
        XCTAssertEqual(points[4].value, 0)
        XCTAssertEqual(points[6].value, 2_302)
    }

    func testInvalidReadingsAreNotShownAsMeasuredSteps() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 1
        )))
        let points = HomeStepsTrend.points(
            from: [
                .init(date: today, value: -.infinity),
                .init(date: calendar.date(byAdding: .day, value: -1, to: today)!, value: -50)
            ],
            days: 7, endingAt: today, calendar: calendar
        )
        XCTAssertEqual(points.count, 7)
        XCTAssertTrue(points.allSatisfy { $0.value == nil })
    }

    func testStepsHasSameHomeCardMetadataAsOtherMeasurements() {
        XCTAssertTrue(HomeHealthMetricKind.allCases.contains(.steps))
        XCTAssertEqual(HomeHealthMetricKind.steps.title, "Skritt")
        XCTAssertEqual(HomeHealthMetricKind.steps.icon, "figure.walk")
    }
}
