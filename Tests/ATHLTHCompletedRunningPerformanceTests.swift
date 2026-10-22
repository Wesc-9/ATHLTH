import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCompletedRunningPerformanceTests: XCTestCase {
    private func sample(_ index: Int, phase: String = "main",
                        meters: Double = 800) -> ATHLTHRecordedRunningStep {
        ATHLTHRecordedRunningStep(
            index: index, title: "Intervall", phase: phase,
            activeSeconds: 240, distanceMeters: meters,
            isUserReported: false,
            targetPaceSecondsPerKilometer: 240
        )
    }

    func testIncompleteWorkoutsAndDuplicateSplitsNeverQualify() {
        XCTAssertFalse(ATHLTHCompletedRunningPerformance.validFullRecording(
            [sample(0)], expectedCount: 9
        ))
        XCTAssertFalse(ATHLTHCompletedRunningPerformance.validFullRecording(
            [sample(0), sample(0)], expectedCount: 2
        ))
    }

    func testRecordedSpeedIsIndependentOfTargetPace() throws {
        let steps = [
            sample(0, phase: "warmup"),
            sample(1),
            sample(2, phase: "recovery", meters: 200),
            sample(3),
            sample(4, phase: "cooldown")
        ]
        XCTAssertTrue(ATHLTHCompletedRunningPerformance.validFullRecording(
            steps, expectedCount: 5
        ))

        let now = Date()
        var result = WatchWorkoutResult(
            id: UUID(), kind: .running, healthKitWorkoutUUID: nil,
            startedAt: now.addingTimeInterval(-1200), endedAt: now,
            duration: 1200, activeCalories: 100, distanceMeters: 3500,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 20
        )
        result.structuredWorkoutFullyCompleted = false
        result.recordedRunningSteps = steps
        XCTAssertNil(ATHLTHCompletedRunningPerformance(watch: result))

        result.structuredWorkoutFullyCompleted = true
        let actual = try XCTUnwrap(
            ATHLTHCompletedRunningPerformance(watch: result)
        )
        XCTAssertEqual(actual.workSteps.count, 2)
        XCTAssertEqual(actual.averageWorkSpeed ?? 0, 12, accuracy: 0.01)
        // Target pace is 4:00/km = 15 km/t; actual was just 12 km/t.
        XCTAssertNotEqual(actual.averageWorkSpeed, 15)
    }

    func testPlannedFieldsSurviveRecordingAndLegacyHistoryDecodes() throws {
        var phase = sample(1)
        phase.targetDurationSeconds = 240
        phase.targetHeartRateZone = 4
        phase.targetTreadmillInclinePercent = 1.5
        let encoded = try JSONEncoder().encode(phase)
        let decoded = try JSONDecoder().decode(ATHLTHRecordedRunningStep.self,
                                               from: encoded)
        XCTAssertEqual(decoded.targetDurationSeconds, 240)
        XCTAssertEqual(decoded.targetHeartRateZone, 4)
        XCTAssertEqual(decoded.targetTreadmillInclinePercent, 1.5)

        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "targetDurationSeconds")
        legacy.removeValue(forKey: "targetHeartRateZone")
        legacy.removeValue(forKey: "targetTreadmillInclinePercent")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let migrated = try JSONDecoder().decode(ATHLTHRecordedRunningStep.self,
                                                from: legacyData)
        XCTAssertNil(migrated.targetDurationSeconds)
        XCTAssertNil(migrated.targetHeartRateZone)
        XCTAssertNil(migrated.targetTreadmillInclinePercent)
    }

    func testUniqueHistoricalHealthKitMatchNeverInfersAnAmbiguousWorkout() throws {
        let endedAt = Date(timeIntervalSince1970: 1_800_000_000)
        func completed(_ id: UUID, _ healthID: UUID?, _ ended: Date)
            throws -> ATHLTHCompletedRunningPerformance {
            let steps = [
                sample(0, phase: "warmup"),
                sample(1, phase: "work"),
                sample(2, phase: "recovery", meters: 150)
            ]
            var result = WatchWorkoutResult(
                id: id, kind: .running, healthKitWorkoutUUID: healthID,
                startedAt: ended.addingTimeInterval(-720), endedAt: ended,
                duration: 720, activeCalories: 90, distanceMeters: 1200,
                averageHeartRate: nil, maxHeartRate: nil, routePointCount: 0
            )
            result.structuredWorkoutFullyCompleted = true
            result.recordedRunningSteps = steps
            return try XCTUnwrap(ATHLTHCompletedRunningPerformance(watch: result))
        }

        let exactHealthID = UUID()
        let first = try completed(UUID(), exactHealthID, endedAt)
        let second = try completed(UUID(), nil, endedAt.addingTimeInterval(25))
        let unique = ATHLTHRunningPerformanceHistory.match(
            workoutID: exactHealthID, endDate: endedAt, duration: 720,
            candidates: [first, second]
        )
        XCTAssertEqual(unique?.id, first.id)

        let ambiguous = ATHLTHRunningPerformanceHistory.match(
            workoutID: UUID(), endDate: endedAt, duration: 720,
            candidates: [first, second]
        )
        XCTAssertNil(ambiguous)
        XCTAssertEqual(ATHLTHRunningPerformanceHistory.match(
            workoutID: UUID(), endDate: endedAt, duration: 720,
            candidates: [first]
        )?.id, first.id)
        XCTAssertNil(ATHLTHRunningPerformanceHistory.match(
            workoutID: UUID(), endDate: endedAt.addingTimeInterval(3_600),
            duration: 720, candidates: [first]
        ))
    }
}
