import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutSummaryEngineTests: XCTestCase {
    func testRunningMetricsAreShared() {
        let result = ATHLTHWorkoutSummaryEngine(duration: 1500, distanceMeters: 5000,
            activeCalories: 350, averageHeartRate: 145, maximumHeartRate: 175, activity: "running")
        XCTAssertEqual(result.durationText, "25:00")
        XCTAssertEqual(result.paceText, "5:00 /km")
        XCTAssertEqual(result.speedKilometersPerHour ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(result.averagePulseText, "145 bpm")
        XCTAssertEqual(result.maximumPulseText, "175 bpm")
        XCTAssertEqual(result.calorieText, "350 kcal")
    }

    func testStrengthDoesNotReportUnrelatedDistance() {
        let result = ATHLTHWorkoutSummaryEngine(duration: 600, distanceMeters: 200,
            activity: "strength", completedSets: 4)
        XCTAssertNil(result.distanceMeters)
        XCTAssertNil(result.paceSecondsPerKilometer)
        XCTAssertEqual(result.completedSets, 4)
    }

    func testSportsUsesMeasuredSpeedNotRunningPace() {
        let result = ATHLTHWorkoutSummaryEngine(duration: 3600, distanceMeters: 5000, activity: "sports")
        XCTAssertNil(result.paceSecondsPerKilometer)
        XCTAssertEqual(result.speedKilometersPerHour ?? 0, 5, accuracy: 0.001)
    }

    func testMissingAndInvalidMetricsStayMissing() {
        let result = ATHLTHWorkoutSummaryEngine(duration: .nan, distanceMeters: .infinity,
            activeCalories: -1, averageHeartRate: 0, maximumHeartRate: .nan, activity: "walking")
        XCTAssertEqual(result.durationText, "—")
        XCTAssertEqual(result.distanceText, "—")
        XCTAssertEqual(result.paceText, "—")
        XCTAssertEqual(result.calorieText, "—")
        XCTAssertEqual(result.averagePulseText, "—")
        XCTAssertEqual(result.maximumPulseText, "—")
        XCTAssertNil(ATHLTHWorkoutSummaryEngine.roundedInteger(Double.greatestFiniteMagnitude))
    }

    func testNativeRunningDynamicsStayOptionalAndSportSpecific() throws {
        let metrics = ATHLTHNativeRunningMetrics(
            powerWatts: 250, strideMeters: 1.1,
            verticalCentimeters: nil, groundContactMilliseconds: 240
        )
        let run = ATHLTHWorkoutSummaryEngine(duration: 1500, activity: "running", nativeRunningMetrics: metrics)
        XCTAssertEqual(run.nativeRunningMetrics, metrics)
        XCTAssertNil(ATHLTHWorkoutSummaryEngine(duration: 600, activity: "strength", nativeRunningMetrics: metrics).nativeRunningMetrics)
        let empty = ATHLTHNativeRunningMetrics(powerWatts: .nan, strideMeters: -1, verticalCentimeters: 0, groundContactMilliseconds: nil)
        XCTAssertFalse(empty.hasMeasurements)
        XCTAssertNil(ATHLTHWorkoutSummaryEngine(duration: 600, activity: "running", nativeRunningMetrics: empty).nativeRunningMetrics)
        let encoded = try JSONEncoder().encode(metrics)
        XCTAssertEqual(try JSONDecoder().decode(ATHLTHNativeRunningMetrics.self, from: encoded), metrics)
    }

    func testCyclingAndRowingUseSportSpecificMetrics() {
        let cycle = ATHLTHWorkoutSummaryEngine(duration: 3600, distanceMeters: 30000, activity: "cycling")
        XCTAssertNil(cycle.paceSecondsPerKilometer)
        XCTAssertEqual(cycle.speedKilometersPerHour ?? 0, 30, accuracy: 0.001)
        let row = ATHLTHWorkoutSummaryEngine(duration: 1200, distanceMeters: 5000, activity: "rowing")
        XCTAssertEqual(row.rowingSplitSeconds ?? 0, 120, accuracy: 0.001)
        XCTAssertNil(row.paceSecondsPerKilometer)
    }
}
