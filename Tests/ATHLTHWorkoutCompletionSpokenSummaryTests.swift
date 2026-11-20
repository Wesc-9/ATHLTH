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

    func testCyclingCompletionUsesSpeedNotRunningPace() {
        let summary = ATHLTHWorkoutCompletionSpokenSummary.make(
            elapsedSeconds: 3600, distanceMeters: 30_000,
            averageHeartRateBPM: 135, activity: "cycling"
        )
        XCTAssertTrue(summary.english.contains("Average speed: 30.0"))
        XCTAssertTrue(summary.norwegian.contains("Snittfart"))
        XCTAssertFalse(summary.english.contains("Average pace"))
    }

    func testRowingCompletionUses500MeterSplit() {
        let summary = ATHLTHWorkoutCompletionSpokenSummary.make(
            elapsedSeconds: 1200, distanceMeters: 5_000, activity: "rowing"
        )
        XCTAssertTrue(summary.english.contains("per 500 metres"))
        XCTAssertTrue(summary.norwegian.contains("2 minutter og 0 sekunder per 500 meter"))
        XCTAssertFalse(summary.english.contains("Average pace"))
    }

    func testStrengthAndYogaNeverPretendToHaveRunningDistance() {
        for sport in ["strength", "yoga", "hiit", "functional", "other"] {
            let summary = ATHLTHWorkoutCompletionSpokenSummary.make(
                elapsedSeconds: 600, distanceMeters: 2000,
                averageHeartRateBPM: 120, activity: sport
            )
            XCTAssertFalse(summary.english.contains("Distance:"), sport)
            XCTAssertFalse(summary.english.contains("Average pace"), sport)
            XCTAssertTrue(summary.english.contains("Average heart rate"), sport)
        }
    }

    func testIncompleteCyclingAndRowingSensorDataIsNotInvented() {
        let shortCycle = ATHLTHWorkoutCompletionSpokenSummary.make(
            elapsedSeconds: 0, distanceMeters: 500, activity: "cycling"
        )
        XCTAssertFalse(shortCycle.english.contains("Average speed"))
        let invalidRow = ATHLTHWorkoutCompletionSpokenSummary.make(
            elapsedSeconds: 1200, distanceMeters: .infinity, activity: "rowing"
        )
        XCTAssertFalse(invalidRow.english.contains("Distance:"))
        XCTAssertFalse(invalidRow.english.contains("Average split"))
    }

}
