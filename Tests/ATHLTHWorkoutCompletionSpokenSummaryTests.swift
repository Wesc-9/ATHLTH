import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutCompletionSpokenSummaryTests: XCTestCase {
    func testDistanceTimeAndPaceAreFromRecordedMetrics() {
        let summary = ATHLTHWorkoutCompletionSpokenSummary.make(
            elapsedSeconds: 1_500,
            distanceMeters: 5_000,
            averageHeartRateBPM: 145
        )
        XCTAssertTrue(summary.english.contains("25 minutes"))
        XCTAssertTrue(summary.english.contains("5.00 kilometres"))
        XCTAssertTrue(summary.english.contains("5 minutes and 0 seconds per kilometre"))
        XCTAssertTrue(summary.norwegian.contains("5,00 kilometer"))
        XCTAssertTrue(summary.norwegian.contains("145 slag"))
        XCTAssertFalse(summary.norwegian.lowercased().contains("rekord"))
    }

    func testNoFakePaceForShortOrInvalidDistance() {
        let invalid = ATHLTHWorkoutCompletionSpokenSummary.make(
            elapsedSeconds: 300,
            distanceMeters: .nan
        )
        XCTAssertFalse(invalid.english.contains("Average pace"))
        XCTAssertFalse(invalid.english.contains("Distance:"))

        let short = ATHLTHWorkoutCompletionSpokenSummary.make(
            elapsedSeconds: 20,
            distanceMeters: 75
        )
        XCTAssertFalse(short.english.contains("Average pace"))
    }

    func testPersonalRecordMustBeSuppliedByVerifiedHistory() {
        let verified = ATHLTHWorkoutCompletionSpokenSummary.make(
            elapsedSeconds: 1_800,
            distanceMeters: 6_000,
            verifiedRecordEnglish: "New verified personal best!",
            verifiedRecordNorwegian: "Ny bekreftet personlig rekord!"
        )
        XCTAssertTrue(verified.norwegian.contains("bekreftet personlig rekord"))
    }

    func testSharedRecordsNeedOlderMeasuredEvidence() {
        let current = ATHLTHVerifiedRunningEvidence(
            distanceMeters: 5_000, activeSeconds: 1_500
        )
        XCTAssertTrue(ATHLTHVerifiedRunningRecordComparison.achievements(
            current: current, previous: []
        ).isEmpty)
        let old = ATHLTHVerifiedRunningEvidence(
            distanceMeters: 4_500, activeSeconds: 1_800
        )
        let achieved = ATHLTHVerifiedRunningRecordComparison.achievements(
            current: current, previous: [old]
        )
        XCTAssertTrue(achieved.contains(.longestDistance))
        XCTAssertTrue(achieved.contains(.fastestAveragePace))
        let spoken = ATHLTHVerifiedRunningRecordComparison.phrase(
            achievements: achieved,
            sourceEnglish: "Apple Health",
            sourceNorwegian: "Apple Health"
        )
        XCTAssertTrue(spoken?.norwegian.contains("lengste") == true)
    }

    func testProfileMaximumHeartRateHasSafeAgeFallback() {
        let birth = Calendar.current.date(
            from: DateComponents(year: 1990, month: 1, day: 1)
        )
        let date = Calendar.current.date(
            from: DateComponents(year: 2026, month: 11, day: 5)
        )!
        XCTAssertEqual(
            ATHLTHHeartRateZones.resolvedMaximumBPM(
                configured: 195, dateOfBirth: birth, now: date
            ), 195
        )
        XCTAssertEqual(
            ATHLTHHeartRateZones.resolvedMaximumBPM(
                configured: nil, dateOfBirth: birth, now: date
            ) ?? 0, 182.8, accuracy: 0.01
        )
        XCTAssertNil(ATHLTHHeartRateZones.resolvedMaximumBPM(
            configured: nil, dateOfBirth: nil
        ))
    }

    func testPositiveZonePhraseIsDifferentFromRecovery() {
        let positive = ATHLTHHeartRateZoneCoachTarget.onTargetPhrase(zone: 3)
        let recovered = ATHLTHHeartRateZoneCoachTarget.backInTargetPhrase(zone: 3)
        XCTAssertTrue(positive.norwegian.contains("S3"))
        XCTAssertNotEqual(positive.norwegian, recovered.norwegian)
    }
}
