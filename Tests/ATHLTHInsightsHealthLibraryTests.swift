import Foundation
import HealthKit
import XCTest
@testable import ATHLTH

final class ATHLTHInsightsHealthLibraryTests: XCTestCase {
    func testExpandedHealthAreasAndEveryMetricHasAGroup() {
        XCTAssertEqual(ATHLTHInsightHealthArea.allCases.count, 9)
        XCTAssertEqual(ATHLTHInsightHealthMetric.allCases.count, 48)
        XCTAssertEqual(
            Set(ATHLTHInsightHealthMetric.allCases.map(\.id)).count,
            ATHLTHInsightHealthMetric.allCases.count
        )
        for area in ATHLTHInsightHealthArea.allCases {
            XCTAssertFalse(area.title.isEmpty)
            XCTAssertFalse(area.detail.isEmpty)
            XCTAssertTrue(ATHLTHInsightHealthMetric.allCases.contains { $0.area == area })
        }
    }

    func testAllHistoryMetricsUseActualHealthKitIdentifiersOrSleepRecords() {
        for metric in ATHLTHInsightHealthMetric.allCases {
            if metric.area == .sleep {
                XCTAssertNil(metric.query)
            } else {
                XCTAssertNotNil(metric.query, "Missing HealthKit source for \(metric.title)")
            }
            XCTAssertFalse(metric.title.isEmpty)
        }
    }

    func testDailyStepsAreCumulativeWithoutAnAutomaticGoal() {
        XCTAssertTrue(ATHLTHInsightHealthMetric.steps.cumulative)
        XCTAssertFalse(ATHLTHInsightHealthMetric.restingHeartRate.cumulative)
        XCTAssertEqual(ATHLTHInsightHealthMetric.steps.formatted(nil), "—")
    }

    func testMissingAndInvalidReadingsAreNotFabricated() {
        for metric in ATHLTHInsightHealthMetric.allCases {
            XCTAssertEqual(metric.formatted(nil), "—")
            XCTAssertEqual(metric.formatted(.nan), "—")
            if metric == .wristTemperature {
                XCTAssertNotEqual(metric.formatted(-1), "—")
            } else {
                XCTAssertEqual(metric.formatted(-1), "—")
            }
        }
    }

    func testPercentageUnitConvertsHealthKitFractions() {
        XCTAssertEqual(ATHLTHInsightHealthMetric.oxygenSaturation.query?.multiplier, 100)
        XCTAssertEqual(ATHLTHInsightHealthMetric.bodyFatPercentage.query?.multiplier, 100)
        XCTAssertEqual(ATHLTHInsightHealthMetric.oxygenSaturation.formatted(97), "97 %")
    }

    func testSleepStagesAndPostWorkoutRecoveryStaySeparate() {
        let phases: [ATHLTHInsightHealthMetric] = [
            .sleepCore, .sleepDeep, .sleepREM, .sleepAwake
        ]
        XCTAssertTrue(phases.allSatisfy { $0.area == .sleep })
        XCTAssertEqual(ATHLTHInsightHealthMetric.heartRateRecovery.area, .recovery)
        XCTAssertEqual(ATHLTHInsightHealthMetric.vo2Max.area, .fitness)
        XCTAssertEqual(ATHLTHInsightHealthMetric.respiratoryRate.area, .vitalSigns)
    }

    func testNewMeasurementsUseRealHealthKitTypes() {
        let expected: [ATHLTHInsightHealthMetric: HKQuantityTypeIdentifier] = [
            .bloodPressureSystolic: .bloodPressureSystolic,
            .bloodPressureDiastolic: .bloodPressureDiastolic,
            .runningPower: .runningPower,
            .cyclingPower: .cyclingPower,
            .walkingSteadiness: .appleWalkingSteadiness,
            .daylightMinutes: .timeInDaylight,
            .dietaryWater: .dietaryWater,
            .dietaryProtein: .dietaryProtein
        ]
        for (metric, identifier) in expected {
            XCTAssertEqual(metric.query?.identifier, identifier)
        }
    }

    func testDailyTotalsAndMeasurementsAreNotMixed() {
        for metric in [
            ATHLTHInsightHealthMetric.activeEnergy,
            .walkingRunningDistance, .exerciseMinutes, .dietaryProtein,
            .dietaryWater, .flightsClimbed, .swimmingStrokeCount
        ] {
            XCTAssertTrue(metric.cumulative, "\(metric.id) should use a daily sum")
        }
        for metric in [
            ATHLTHInsightHealthMetric.heartRate,
            .bloodPressureSystolic, .walkingSteadiness, .runningPower
        ] {
            XCTAssertFalse(metric.cumulative, "\(metric.id) should not use a daily sum")
        }
    }

    func testSignedWristTemperatureDeviationsRemainVisible() {
        XCTAssertNotEqual(ATHLTHInsightHealthMetric.wristTemperature.formatted(-0.3), "—")
        XCTAssertEqual(ATHLTHInsightHealthMetric.activeEnergy.formatted(-1), "—")
    }


    func testIrrelevantMedicalAndSoundMetricsAreExcluded() {
        let ids = Set(ATHLTHInsightHealthMetric.allCases.map(\.id))
        for excluded in [
            "bloodGlucose", "insulinDelivery", "atrialFibrillationBurden",
            "headphoneAudioExposure", "inhalerUsage", "dietaryVitaminD"
        ] {
            XCTAssertFalse(ids.contains(excluded))
        }
    }

    func testFocusedHealthAreasRetainTrainingAndRecovery() {
        let areas = Set(ATHLTHInsightHealthArea.allCases)
        XCTAssertTrue(areas.contains(.activity))
        XCTAssertTrue(areas.contains(.mobility))
        XCTAssertTrue(areas.contains(.nutrition))
        XCTAssertFalse(areas.contains { $0.rawValue == "clinical" })
        XCTAssertFalse(areas.contains { $0.rawValue == "hearing" })
    }


    func testHeartRateRecoveryFallbackUsesTwoRealMeasurements() {
        let end = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let readings = [
            ATHLTHHeartRateRecoveryCalculator.Reading(
                date: end.addingTimeInterval(-5),
                bpm: 154,
                sourceIdentifier: "com.apple.health.watch"
            ),
            ATHLTHHeartRateRecoveryCalculator.Reading(
                date: end.addingTimeInterval(62),
                bpm: 112,
                sourceIdentifier: "com.apple.health.watch"
            )
        ]
        XCTAssertEqual(
            ATHLTHHeartRateRecoveryCalculator.dropAfterOneMinute(
                workoutEnd: end, readings: readings
            ),
            42
        )
    }

    func testHeartRateRecoveryNeverInventsMissingPostWorkoutPulse() {
        let end = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let readings = [
            ATHLTHHeartRateRecoveryCalculator.Reading(
                date: end.addingTimeInterval(-2),
                bpm: 153,
                sourceIdentifier: "watch"
            ),
            ATHLTHHeartRateRecoveryCalculator.Reading(
                date: end.addingTimeInterval(20),
                bpm: 142,
                sourceIdentifier: "watch"
            )
        ]
        XCTAssertNil(
            ATHLTHHeartRateRecoveryCalculator.dropAfterOneMinute(
                workoutEnd: end, readings: readings
            )
        )
    }

    func testHeartRateRecoveryDoesNotMixSourcesOrInventNegativeDrop() {
        let end = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let base = ATHLTHHeartRateRecoveryCalculator.Reading(
            date: end.addingTimeInterval(-3),
            bpm: 150,
            sourceIdentifier: "watch-one"
        )
        let other = ATHLTHHeartRateRecoveryCalculator.Reading(
            date: end.addingTimeInterval(62),
            bpm: 102,
            sourceIdentifier: "watch-two"
        )
        XCTAssertNil(
            ATHLTHHeartRateRecoveryCalculator.dropAfterOneMinute(
                workoutEnd: end, readings: [base, other]
            )
        )
        let higher = ATHLTHHeartRateRecoveryCalculator.Reading(
            date: end.addingTimeInterval(60),
            bpm: 160,
            sourceIdentifier: "watch-one"
        )
        XCTAssertNil(
            ATHLTHHeartRateRecoveryCalculator.dropAfterOneMinute(
                workoutEnd: end, readings: [base, higher]
            )
        )
    }

    func testRecoveryHistoryMarksCalculatedReadings() {
        let day = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let native = ATHLTHInsightHealthDay(date: day, value: 31)
        let calculated = ATHLTHInsightHealthDay(
            date: day, value: 34, isEstimated: true
        )
        XCTAssertFalse(native.isEstimated)
        XCTAssertTrue(calculated.isEstimated)
    }


    func testTrainingSignalsUseOnlyRealRecentMeasurements() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let recent = calendar.date(
            byAdding: .day, value: -3, to: calendar.startOfDay(for: now)
        )!
        let older = calendar.date(
            byAdding: .day, value: -40, to: calendar.startOfDay(for: now)
        )!
        let future = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
        )!
        let readings = [
            ATHLTHInsightHealthDay(date: older, value: 270),
            ATHLTHInsightHealthDay(date: recent, value: 255),
            ATHLTHInsightHealthDay(date: future, value: 280)
        ]
        let actual = ATHLTHInsightsTrainingSignalPolicy.latest(
            in: readings, now: now, calendar: calendar
        )
        XCTAssertEqual(actual?.date, recent)
        XCTAssertEqual(actual?.value, 255)
    }

    func testTrainingSignalMissingOrInvalidReadingsNeverBecomeScores() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let today = calendar.startOfDay(for: now)
        XCTAssertNil(ATHLTHInsightsTrainingSignalPolicy.latest(
            in: [], now: now, calendar: calendar
        ))
        XCTAssertNil(ATHLTHInsightsTrainingSignalPolicy.latest(
            in: [
                ATHLTHInsightHealthDay(date: today, value: 0),
                ATHLTHInsightHealthDay(date: today, value: .nan)
            ],
            now: now, calendar: calendar
        ))
    }

}
