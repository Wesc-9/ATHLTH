import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHSpecificProgressEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func run(
        title: String,
        recordedAt: Date,
        workoutID: UUID? = nil,
        effortSeconds: [TimeInterval] = [240, 240, 240, 240],
        metersPerEffort: Double = 950
    ) throws -> ATHLTHCompletedRunningPerformance {
        var steps: [ATHLTHRecordedRunningStep] = []
        for (index, duration) in effortSeconds.enumerated() {
            steps.append(ATHLTHRecordedRunningStep(
                index: index,
                title: "Drag \(index + 1)",
                phase: "main",
                activeSeconds: duration,
                distanceMeters: metersPerEffort
            ))
        }
        var result = WatchWorkoutResult(
            id: UUID(),
            kind: .running,
            healthKitWorkoutUUID: nil,
            startedAt: recordedAt.addingTimeInterval(-1_500),
            endedAt: recordedAt,
            duration: 1_500,
            activeCalories: 250,
            distanceMeters: metersPerEffort * Double(steps.count),
            averageHeartRate: nil,
            maxHeartRate: nil,
            routePointCount: 0
        )
        result.structuredWorkoutFullyCompleted = true
        result.structuredWorkoutSourceID = workoutID
        result.structuredWorkoutTitle = title
        result.recordedRunningSteps = steps
        return try XCTUnwrap(ATHLTHCompletedRunningPerformance(watch: result))
    }

    func testPeriodBoundariesHaveWeekMonthYearAndAll() {
        let calendar = Calendar(identifier: .gregorian)
        let week = ATHLTHSpecificProgressEngine.Period.week.start(
            now: now, calendar: calendar
        )
        let month = ATHLTHSpecificProgressEngine.Period.month.start(
            now: now, calendar: calendar
        )
        let year = ATHLTHSpecificProgressEngine.Period.year.start(
            now: now, calendar: calendar
        )
        XCTAssertEqual(now.timeIntervalSince(week), 7 * 86_400, accuracy: 1)
        XCTAssertLessThan(year, month)
        XCTAssertLessThan(month, week)
        XCTAssertEqual(
            ATHLTHSpecificProgressEngine.Period.all.start(now: now),
            .distantPast
        )
    }

    func testFourByFourMatchesActualFourMinuteEffortsNotMerelyTitle() throws {
        let proper = try run(title: "Mine intervaller", recordedAt: now)
        let wrongCount = try run(
            title: "4x4", recordedAt: now, effortSeconds: [240, 240, 240]
        )
        let shortEffort = try run(
            title: "4x4", recordedAt: now, effortSeconds: [60, 60, 60, 60]
        )
        XCTAssertTrue(ATHLTHSpecificProgressEngine.isFourByFour(proper))
        XCTAssertFalse(ATHLTHSpecificProgressEngine.isFourByFour(wrongCount))
        XCTAssertFalse(ATHLTHSpecificProgressEngine.isFourByFour(shortEffort))
    }

    func testActualResultsGroupedBySourceWorkoutAndPeriod() throws {
        let source = UUID()
        let other = UUID()
        let recent = try run(title: "4x4", recordedAt: now.addingTimeInterval(-86_400),
                             workoutID: source)
        let old = try run(title: "4x4", recordedAt: now.addingTimeInterval(-50 * 86_400),
                          workoutID: source)
        let different = try run(title: "4x4", recordedAt: now.addingTimeInterval(-86_400),
                                workoutID: other)
        let history = [old, different, recent]
        let key = ATHLTHSpecificProgressEngine.identity(recent)
        let week = ATHLTHSpecificProgressEngine.intervalRecords(
            key: key, from: history, period: .week, now: now
        )
        let year = ATHLTHSpecificProgressEngine.intervalRecords(
            key: key, from: history, period: .year, now: now
        )
        XCTAssertEqual(week.map(\.id), [recent.id])
        XCTAssertEqual(year.map(\.id), [old.id, recent.id])
        XCTAssertEqual(
            ATHLTHSpecificProgressEngine.intervalRecords(
                key: "benchmark:4x4", from: history, period: .week, now: now
            ).count, 2
        )
    }

    func testStrengthComparisonUsesRecordedWeightsOnly() {
        let a = ATHLTHTrainTrendEngine.Point(
            exerciseID: "squat", date: now.addingTimeInterval(-600),
            peakWeightKilograms: 60, volumeKilograms: 900,
            completedWorkingSets: 3, completedRepetitions: 15
        )
        let plannedWithoutPerformance = ATHLTHTrainTrendEngine.Point(
            exerciseID: "squat", date: now,
            peakWeightKilograms: nil, volumeKilograms: 0,
            completedWorkingSets: 1, completedRepetitions: 10
        )
        let b = ATHLTHTrainTrendEngine.Point(
            exerciseID: "squat", date: now.addingTimeInterval(600),
            peakWeightKilograms: 75, volumeKilograms: 1_125,
            completedWorkingSets: 3, completedRepetitions: 15
        )
        XCTAssertEqual(
            ATHLTHSpecificProgressEngine.weightChange(
                [a, plannedWithoutPerformance, b]
            ) ?? 0, 15, accuracy: 0.01
        )
    }
}
