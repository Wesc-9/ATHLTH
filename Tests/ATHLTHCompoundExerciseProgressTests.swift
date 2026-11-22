import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHCompoundExerciseProgressTests: XCTestCase {
    private func exercise() throws -> ATHLTHCompoundExercise {
        let original = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.title == "4 × 4 intervaller"
            }
        )
        return try XCTUnwrap(
            ATHLTHCompoundExerciseCatalog.build(
                running: [original], workoutCatalog: [], saved: []
            ).first
        )
    }

    private func recorded() -> [ATHLTHRecordedRunningStep] {
        let protocolTimes: [(String, Double, Double)] = [
            ("work", 240, 1_000), ("recovery", 120, 150),
            ("work", 240, 1_030), ("recovery", 120, 170),
            ("work", 240, 1_010), ("recovery", 120, 160),
            ("work", 240, 1_040)
        ]
        return protocolTimes.enumerated().map { i, item in
            ATHLTHRecordedRunningStep(
                index: i, title: item.0, phase: item.0,
                activeSeconds: item.1, distanceMeters: item.2
            )
        }
    }

    private func result(
        _ steps: [ATHLTHRecordedRunningStep]
    ) throws -> ATHLTHCompoundExerciseProgress.Result? {
        ATHLTHCompoundExerciseProgress.result(
            for: try exercise(), steps: steps,
            id: UUID(), date: Date(), source: "iPhone"
        )
    }

    func testCompletedNestedFourByFourIsAttributedByActualProtocol() throws {
        let expected = try exercise()
        var steps = recorded()
        let before = ATHLTHRecordedRunningStep(
            index: -1, title: "Other work", phase: "main",
            activeSeconds: 500, distanceMeters: 1_200
        )
        steps.insert(before, at: 0)
        let result = try XCTUnwrap(result(steps))
        XCTAssertEqual(result.protocolID, expected.protocolID)
        XCTAssertEqual(result.efforts, 4)
        XCTAssertEqual(result.workSeconds, 960, accuracy: 0.1)
        XCTAssertEqual(result.workDistanceMeters, 4080, accuracy: 0.1)
        XCTAssertFalse(result.reported)
    }

    func testOnlyMeasuredSpeedCountsNotPersonalTarget() throws {
        var steps = recorded()
        for index in steps.indices where steps[index].phase == "work" {
            steps[index].targetPaceSecondsPerKilometer = 150
        }
        let result = try XCTUnwrap(result(steps))
        XCTAssertEqual(result.averageWorkSpeedKmh, 15.3, accuracy: 0.1)
        XCTAssertNotEqual(result.averageWorkSpeedKmh, 24, accuracy: 0.1)
    }

    func testIncompleteEffortCannotBeAnAchievedResult() throws {
        var steps = recorded()
        steps[4].activeSeconds = 40
        XCTAssertNil(try result(steps))
        steps = recorded()
        steps[2].distanceMeters = 0
        XCTAssertNil(try result(steps))
    }

    func testAmbiguousRepeatedProtocolsCannotCreateFabricatedRecord() throws {
        let first = recorded()
        var second = first
        for index in second.indices { second[index].index += first.count }
        XCTAssertNil(try result(first + second))
    }

    func testReportedTreadmillDataIsNotMixedWithWatchMeasuredHistory() throws {
        var steps = recorded()
        steps[0].isUserReported = true
        let reported = try XCTUnwrap(result(steps))
        let measured = try XCTUnwrap(result(recorded()))
        XCTAssertTrue(reported.reported)
        XCTAssertFalse(measured.reported)
        XCTAssertNil(ATHLTHCompoundExerciseProgress.bestMeasured([reported]))
        XCTAssertNotNil(ATHLTHCompoundExerciseProgress.bestMeasured([reported, measured]))
    }
}
