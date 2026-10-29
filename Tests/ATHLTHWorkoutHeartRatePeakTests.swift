import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutHeartRatePeakTests: XCTestCase {
    func testPeakPolicyRejectsClearlyInvalidSensorMeasurements() {
        XCTAssertNil(ATHLTHWorkoutHeartRatePeakPolicy.validPeak(.nan))
        XCTAssertNil(ATHLTHWorkoutHeartRatePeakPolicy.validPeak(.infinity))
        XCTAssertNil(ATHLTHWorkoutHeartRatePeakPolicy.validPeak(0))
        XCTAssertNil(ATHLTHWorkoutHeartRatePeakPolicy.validPeak(99))
        XCTAssertNil(ATHLTHWorkoutHeartRatePeakPolicy.validPeak(241))
        XCTAssertEqual(ATHLTHWorkoutHeartRatePeakPolicy.validPeak(192.7), 193)
        XCTAssertEqual(ATHLTHWorkoutHeartRatePeakPolicy.validPeak(200), 200)
    }

    func testHighestRecordedWorkoutHeartRateUsesActualPeakAndSource() {
        let earlier = ATHLTHWorkoutHeartRatePeak(
            beatsPerMinute: 192, workoutID: UUID(),
            workoutDate: Date(timeIntervalSince1970: 1_700_000_000),
            workoutTitle: "Running"
        )
        let higher = ATHLTHWorkoutHeartRatePeak(
            beatsPerMinute: 202, workoutID: UUID(),
            workoutDate: Date(timeIntervalSince1970: 1_800_000_000),
            workoutTitle: "Cycling"
        )
        let best = ATHLTHWorkoutHeartRatePeakPolicy.highest(
            among: [earlier, higher]
        )
        XCTAssertEqual(best?.beatsPerMinute, 202)
        XCTAssertEqual(best?.workoutID, higher.workoutID)
        XCTAssertEqual(best?.workoutTitle, "Cycling")
    }

    func testSamePeakPrefersMostRecentWorkout() {
        let older = ATHLTHWorkoutHeartRatePeak(
            beatsPerMinute: 190, workoutID: UUID(),
            workoutDate: Date(timeIntervalSince1970: 1_700_000_000),
            workoutTitle: "Running"
        )
        let newer = ATHLTHWorkoutHeartRatePeak(
            beatsPerMinute: 190, workoutID: UUID(),
            workoutDate: Date(timeIntervalSince1970: 1_800_000_000),
            workoutTitle: "Walking"
        )
        XCTAssertEqual(
            ATHLTHWorkoutHeartRatePeakPolicy.highest(
                among: [older, newer]
            )?.workoutID,
            newer.workoutID
        )
    }

    func testWorkoutPeakOptInAndSourceSurviveProfileSerialization() throws {
        let workoutID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = HealthProfileBasics(
            dateOfBirth: nil,
            healthSex: .male,
            weightKilograms: nil,
            heightCentimeters: nil,
            maximumHeartRateBPM: 202,
            maximumHeartRateIsEstimated: false,
            maximumHeartRateUsesWorkoutPeak: true,
            maximumHeartRateWorkoutID: workoutID,
            maximumHeartRateWorkoutDate: date
        )

        let decoded = try JSONDecoder().decode(
            HealthProfileBasics.self,
            from: JSONEncoder().encode(saved)
        )
        XCTAssertEqual(decoded.maximumHeartRateBPM, 202)
        XCTAssertEqual(decoded.maximumHeartRateUsesWorkoutPeak, true)
        XCTAssertEqual(decoded.maximumHeartRateIsEstimated, false)
        XCTAssertEqual(decoded.maximumHeartRateWorkoutID, workoutID)
        XCTAssertEqual(decoded.maximumHeartRateWorkoutDate, date)
    }

    func testOlderProfilesDoNotAutomaticallyOptIntoWorkoutPeaks() throws {
        let oldRecord = Data(
            #"{"maximumHeartRateBPM":200,"maximumHeartRateIsEstimated":false}"#.utf8
        )
        let profile = try JSONDecoder().decode(
            HealthProfileBasics.self,
            from: oldRecord
        )
        XCTAssertEqual(profile.maximumHeartRateBPM, 200)
        XCTAssertNotEqual(profile.maximumHeartRateUsesWorkoutPeak, true)
    }
}
