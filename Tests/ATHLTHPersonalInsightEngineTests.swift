import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPersonalInsightEngineTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 30, hour: 18
        ))!
    }

    private func day(
        _ daysAgo: Int,
        sleepHours: Double? = nil,
        hrv: Double? = nil,
        resting: Double? = nil,
        breathing: Double? = nil
    ) -> RecoveryTrendDay {
        let date = calendar.date(byAdding: .day, value: -daysAgo,
                                 to: calendar.startOfDay(for: now))!
        return RecoveryTrendDay(
            date: date,
            sleepDuration: sleepHours.map { $0 * 3600 },
            hrvMilliseconds: hrv,
            restingHeartRate: resting,
            respiratoryRate: breathing,
            trainingMinutes: 0
        )
    }

    private func checkIn(
        daysAgo: Int, energy: Int? = nil, stress: Int? = nil
    ) -> RecoverySorenessEntry {
        RecoverySorenessEntry(
            date: calendar.date(byAdding: .day, value: -daysAgo,
                                to: calendar.startOfDay(for: now))!,
            ratings: [:],
            energy: energy,
            stress: stress,
            overallSoreness: nil,
            motivation: nil
        )
    }

    private func analyze(
        _ days: [RecoveryTrendDay],
        _ entries: [RecoverySorenessEntry] = [],
        steps: Double? = nil,
        training: Double? = nil,
        averageSteps: Double? = nil
    ) -> [ATHLTHPersonalInsight] {
        ATHLTHPersonalInsightEngine.findings(
            days: days, checkIns: entries,
            stepsChangePercent: steps,
            trainingChangePercent: training,
            averageDailySteps: averageSteps,
            now: now, calendar: calendar
        )
    }

    func testNoFakeInsightsWhenSourcesHaveInsufficientCoverage() {
        let days = [day(0, sleepHours: 7, hrv: 60, resting: 55)]
        XCTAssertTrue(analyze(days).isEmpty)
        XCTAssertTrue(analyze([]).isEmpty)
    }

    func testTwoIndependentBodySignalsRequired() {
        let days = (0..<20).map { distance in
            day(distance,
                hrv: distance < 3 ? 48 : 62,
                resting: distance < 3 ? 64 : 55,
                breathing: 14
            )
        }
        let result = analyze(days)
        let finding = result.first { $0.kind == .combinedSignals }
        XCTAssertEqual(finding?.evidence.count, 2)
        XCTAssertGreaterThanOrEqual(finding?.sampleCount ?? 0, 10)
    }

    func testOneChangingSignalIsNotDiagnosedAsPattern() {
        let days = (0..<20).map { distance in
            day(distance,
                hrv: distance < 3 ? 48 : 62,
                resting: 55,
                breathing: 14
            )
        }
        XCTAssertFalse(analyze(days).contains {
            $0.kind == .combinedSignals
        })
    }

    func testSleepEnergyOnlyUsesPairedDays() {
        let days: [RecoveryTrendDay] = (0..<9).map { i in
            day(i, sleepHours: i < 3 ? 5 : i < 6 ? 7 : 9)
        }
        let reports: [RecoverySorenessEntry] = (0..<9).map { i in
            checkIn(daysAgo: i, energy: i < 3 ? 2 : i < 6 ? 3 : 5)
        }
        let finding = analyze(days, reports).first {
            $0.kind == .sleepAndEnergy
        }
        XCTAssertEqual(finding?.sampleCount, 9)
        XCTAssertEqual(finding?.evidence.count, 2)
        // Removing measured sleep from three days must not become zero hours.
        let incomplete = Array(days.dropLast(3))
        XCTAssertFalse(analyze(incomplete, reports).contains {
            $0.kind == .sleepAndEnergy
        })
    }

    func testStressEnergyNeedsBothLowAndHighStressGroups() {
        let reports = (0..<10).map { i -> RecoverySorenessEntry in
            let stress = i < 4 ? 1 : i < 8 ? 5 : 3
            let energy = i < 4 ? 5 : i < 8 ? 2 : 3
            return checkIn(daysAgo: i, energy: energy, stress: stress)
        }
        let finding = analyze([], reports).first {
            $0.kind == .stressAndEnergy
        }
        XCTAssertEqual(finding?.sampleCount, 10)
        XCTAssertEqual(finding?.evidence.count, 2)
    }

    func testOppositeTrainingAndStepChangesAreNotCalledCausation() {
        let finding = analyze(
            [], steps: 22, training: -25, averageSteps: 7_500
        ).first { $0.kind == .everydayMovement }
        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.evidence.count, 2)
        XCTAssertFalse(finding?.explanationNO.contains("fordi") == true)
        XCTAssertFalse(analyze(
            [], steps: 25, training: 25, averageSteps: 7_500
        ).contains { $0.kind == .everydayMovement })
    }

    func testInvalidAndFutureMeasurementsNeverProduceFinding() {
        let observations = (0..<18).map { i in
            day(i, hrv: .nan, resting: 60, breathing: 15)
        }
        XCTAssertFalse(analyze(observations).contains {
            $0.kind == .combinedSignals
        })
        XCTAssertTrue(analyze(
            [], steps: .nan, training: -40, averageSteps: 8_000
        ).isEmpty)
    }
}
