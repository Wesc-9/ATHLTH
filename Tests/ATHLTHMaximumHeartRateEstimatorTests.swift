import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHMaximumHeartRateEstimatorTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day
        ))!
    }

    func testMaleEstimateUsesTanakaAdultEquation() {
        let estimate = ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: date(1992, 6, 13),
            healthSex: .male,
            asOf: date(2026, 10, 29),
            calendar: calendar
        )
        XCTAssertEqual(estimate?.ageYears, 34)
        XCTAssertEqual(estimate?.beatsPerMinute, 184)
        XCTAssertEqual(estimate?.usesFemaleEquation, false)
    }

    func testFemaleEstimateUsesGulatiEquation() {
        let estimate = ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: date(1992, 6, 13),
            healthSex: .female,
            asOf: date(2026, 10, 29),
            calendar: calendar
        )
        XCTAssertEqual(estimate?.beatsPerMinute, 176)
        XCTAssertEqual(estimate?.usesFemaleEquation, true)
    }

    func testUnknownSexUsesGeneralAdultEquation() {
        let estimate = ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: date(1992, 6, 13),
            healthSex: .preferNotToSay,
            asOf: date(2026, 10, 29),
            calendar: calendar
        )
        XCTAssertEqual(estimate?.beatsPerMinute, 184)
        XCTAssertEqual(estimate?.usesFemaleEquation, false)
    }

    func testBirthdayHasToOccurBeforeAgeIncreases() {
        let before = ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: date(1992, 6, 13),
            healthSex: .male,
            asOf: date(2026, 6, 12),
            calendar: calendar
        )
        let after = ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: date(1992, 6, 13),
            healthSex: .male,
            asOf: date(2026, 6, 13),
            calendar: calendar
        )
        XCTAssertEqual(before?.ageYears, 33)
        XCTAssertEqual(after?.ageYears, 34)
    }

    func testNoBirthDateFutureDateAndMinorDoNotGetEstimate() {
        XCTAssertNil(ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: nil, healthSex: .male,
            asOf: date(2026, 10, 29), calendar: calendar
        ))
        XCTAssertNil(ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: date(2027, 1, 1), healthSex: .male,
            asOf: date(2026, 10, 29), calendar: calendar
        ))
        XCTAssertNil(ATHLTHMaximumHeartRateEstimator.estimate(
            dateOfBirth: date(2012, 1, 1), healthSex: .female,
            asOf: date(2026, 10, 29), calendar: calendar
        ))
    }

    func testLegacySavedProfileStillDecodesWithoutEstimateFlag() throws {
        let legacy = Data(#"{"weightKilograms":75,"maximumHeartRateBPM":200}"#.utf8)
        let decoded = try JSONDecoder().decode(
            HealthProfileBasics.self, from: legacy
        )
        XCTAssertEqual(decoded.maximumHeartRateBPM, 200)
        XCTAssertNil(decoded.maximumHeartRateIsEstimated)
    }

    func testEstimateSourceSurvivesProfileSerialization() throws {
        let basics = HealthProfileBasics(
            dateOfBirth: date(1992, 6, 13),
            healthSex: .female,
            weightKilograms: nil,
            heightCentimeters: nil,
            maximumHeartRateBPM: 176,
            maximumHeartRateIsEstimated: true
        )
        let encoded = try JSONEncoder().encode(basics)
        let decoded = try JSONDecoder().decode(
            HealthProfileBasics.self, from: encoded
        )
        XCTAssertEqual(decoded.maximumHeartRateBPM, 176)
        XCTAssertEqual(decoded.maximumHeartRateIsEstimated, true)
    }
}
