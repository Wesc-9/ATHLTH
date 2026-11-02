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

}
