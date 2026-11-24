import XCTest
@testable import ATHLTH

final class GarminPersonalResponseTests: XCTestCase {
    func testActivityDecodesUTCAndPreservesID() throws {
        let data = Data(#"{"activityId":123456789,"activityType":{"typeKey":"running"},"startTimeGMT":"2026-11-24 09:15:00","duration":1200,"elapsedDuration":1300,"distance":3000,"calories":300,"averageHR":150}"#.utf8)
        let row = try JSONDecoder().decode(GarminPersonalActivityResponse.self, from: data)
        let result = try row.normalized().workout
        XCTAssertEqual(result.id, "garmin:123456789")
        XCTAssertEqual(result.startedAt, ISO8601DateFormatter().date(from: "2026-11-24T09:15:00Z"))
        XCTAssertEqual(result.duration, 1200)
        XCTAssertEqual(result.averageHeartRate, 150)
        XCTAssertNil(result.activeEnergyKilocalories)
        XCTAssertNil(result.maximumHeartRate)
    }

    func testMissingHRVIsNotZero() throws {
        let data = Data(#"{"hrvSummary":{}}"#.utf8)
        let row = try JSONDecoder().decode(GarminPersonalHRV.self, from: data)
        XCTAssertNil(row.hrvSummary?.lastNightAvg)
    }
}
