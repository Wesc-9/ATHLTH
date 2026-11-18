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

    func testRollingTwelveCalendarMonthsExcludesHistoricalPeaks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 18, hour: 13
        ))!
        func peak(_ year: Int, _ month: Int, _ day: Int, _ bpm: Int)
            -> ATHLTHWorkoutHeartRatePeak {
            ATHLTHWorkoutHeartRatePeak(
                beatsPerMinute: bpm,
                workoutID: UUID(),
                workoutDate: calendar.date(from: DateComponents(
                    year: year, month: month, day: day, hour: 13
                ))!,
                workoutTitle: "Running"
            )
        }
        let oldHigh = peak(2023, 6, 5, 194)
        let oldBoundary = peak(2025, 11, 17, 200)
        let exactStart = peak(2025, 11, 18, 175)
        let within = peak(2026, 8, 27, 192)
        let future = peak(2026, 11, 19, 230)
        let recent = ATHLTHWorkoutHeartRatePeakPolicy.recent(
            among: [oldHigh, oldBoundary, exactStart, within, future],
            asOf: now, calendar: calendar
        )
        XCTAssertEqual(Set(recent.map(\.workoutID)), Set([
            exactStart.workoutID, within.workoutID
        ]))
        XCTAssertEqual(
            ATHLTHWorkoutHeartRatePeakPolicy.highest(among: recent)?.beatsPerMinute,
            192
        )
    }

    func testWindowUsesCalendarMonthsNotFixedNumberOfDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 1
        ))!
        let cutoff = ATHLTHWorkoutHeartRatePeakPolicy.windowStart(
            asOf: now, calendar: calendar
        )
        XCTAssertEqual(calendar.dateComponents(
            [.year, .month, .day], from: cutoff
        ).year, 2025)
        XCTAssertEqual(calendar.component(.month, from: cutoff), 3)
        XCTAssertEqual(calendar.component(.day, from: cutoff), 1)
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
