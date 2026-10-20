import HealthKit
import XCTest
@testable import ATHLTH

final class SleepSessionGroupingTests: XCTestCase {
    private func sample(
        _ value: HKCategoryValueSleepAnalysis,
        start: String,
        end: String
    ) -> HKCategorySample {
        let formatter = ISO8601DateFormatter()
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        return HKCategorySample(
            type: type,
            value: value.rawValue,
            start: formatter.date(from: start)!,
            end: formatter.date(from: end)!
        )
    }

    func testRecordedLongAwakeningRemainsOneNight() {
        // Regression: Apple Health can show 6h44 despite an awake stretch
        // longer than two hours. ATHLTH previously retained only 5h20.
        let samples = [
            sample(.asleepCore, start: "2026-10-19T22:55:00Z", end: "2026-10-20T04:15:00Z"),
            sample(.awake, start: "2026-10-20T04:15:00Z", end: "2026-10-20T06:40:00Z"),
            sample(.asleepREM, start: "2026-10-20T06:40:00Z", end: "2026-10-20T08:04:00Z")
        ]

        let sessions = SleepSessionGrouping.sessions(from: samples)
        XCTAssertEqual(sessions.count, 1)
        let asleepSeconds = sessions[0].reduce(0.0) {
            $0 + $1.endDate.timeIntervalSince($1.startDate)
        }
        XCTAssertEqual(asleepSeconds, 6 * 3_600 + 44 * 60, accuracy: 0.1)
    }

    func testLongGapWithoutRecordedAwakeIntervalRemainsSeparate() {
        let samples = [
            sample(.asleepCore, start: "2026-10-19T22:55:00Z", end: "2026-10-20T04:15:00Z"),
            sample(.asleepREM, start: "2026-10-20T06:40:00Z", end: "2026-10-20T08:04:00Z")
        ]
        XCTAssertEqual(SleepSessionGrouping.sessions(from: samples).count, 2)
    }

    func testOverFourHourGapRemainsSeparateDespiteInBedRecord() {
        let samples = [
            sample(.asleepCore, start: "2026-10-19T23:00:00Z", end: "2026-10-20T02:00:00Z"),
            sample(.inBed, start: "2026-10-19T23:00:00Z", end: "2026-10-20T10:00:00Z"),
            sample(.asleepCore, start: "2026-10-20T07:00:00Z", end: "2026-10-20T10:00:00Z")
        ]
        XCTAssertEqual(SleepSessionGrouping.sessions(from: samples).count, 2)
    }

    func testNormalAwakeGapAndDaytimeNap() {
        let samples = [
            sample(.asleepCore, start: "2026-10-19T23:00:00Z", end: "2026-10-20T02:00:00Z"),
            sample(.awake, start: "2026-10-20T02:00:00Z", end: "2026-10-20T02:20:00Z"),
            sample(.asleepREM, start: "2026-10-20T02:20:00Z", end: "2026-10-20T07:00:00Z"),
            sample(.asleepCore, start: "2026-10-20T15:00:00Z", end: "2026-10-20T16:00:00Z")
        ]
        let sessions = SleepSessionGrouping.sessions(from: samples)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].count, 2)
        XCTAssertEqual(sessions[1].count, 1)
    }
}
