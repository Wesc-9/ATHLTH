import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAIProgramWorkoutStepsTests: XCTestCase {
    private func step(
        _ name: String, kind: String, phase: String,
        seconds: Double, pace: Double? = nil, incline: Double? = nil
    ) -> AIProgramDraftStep {
        AIProgramDraftStep(
            title: name, kind: kind, phase: phase,
            durationSeconds: seconds, distanceMeters: nil, repetitions: nil,
            targetPaceSecondsPerKilometer: pace,
            treadmillInclinePercent: incline,
            targetHeartRateZone: nil, targetEffortRPE: nil, notes: nil
        )
    }

    private func session(blocks: [AIProgramDraftStep]?) -> AIProgramDraftSession {
        AIProgramDraftSession(
            title: "4 x 4 intervaller", kind: "running", durationMinutes: 42,
            targetDistanceKilometers: nil, targetPaceSecondsPerKilometer: nil,
            notes: nil, exercises: [], blocks: blocks
        )
    }

    func testAIIntervalWorkoutProducesOneRealChronologicalExecutionRecipe() {
        var steps = [step("Warm-up", kind: "run", phase: "warmup", seconds: 600)]
        for index in 1...4 {
            steps.append(step("Intervall \(index)", kind: "run", phase: "main",
                              seconds: 240, pace: 270, incline: index == 1 ? 3 : nil))
            if index < 4 {
                steps.append(step("Recovery", kind: "rest", phase: "recovery",
                                  seconds: 120))
            }
        }
        steps.append(step("Cool-down", kind: "run", phase: "cooldown", seconds: 600))
        let planned = session(blocks: steps).makePlannedSession()
        XCTAssertEqual(planned.resolvedWorkoutBlocks.count, 9)
        XCTAssertTrue(planned.exercises.isEmpty)
        XCTAssertNil(planned.runningWorkout)
        XCTAssertEqual(planned.resolvedWorkoutBlocks.map(\.kind), [
            .run, .run, .rest, .run, .rest, .run, .rest, .run, .run
        ])
        XCTAssertEqual(planned.resolvedWorkoutBlocks[1].targetPaceSecondsPerKilometer, 270)
        XCTAssertEqual(planned.resolvedWorkoutBlocks[1].treadmillInclinePercent, 3)
        XCTAssertNil(planned.resolvedWorkoutBlocks[3].treadmillInclinePercent)
    }

    func testOldAIResponseWithoutBlocksStillCreatesCompatibleWorkout() throws {
        let legacy = """
        {"title":"Easy run","kind":"running","durationMinutes":40,
        "targetDistanceKilometers":6,"targetPaceSecondsPerKilometer":360,
        "notes":null,"exercises":[]}
        """
        let parsed = try JSONDecoder().decode(
            AIProgramDraftSession.self, from: Data(legacy.utf8)
        )
        XCTAssertNil(parsed.blocks)
        let planned = parsed.makePlannedSession()
        XCTAssertEqual(planned.targetDistanceKilometers, 6)
        XCTAssertEqual(planned.durationMinutes, 40)
    }

    func testInvalidAIStepDoesNotBecomeWorkoutExecutionTarget() {
        let invalid = step("Impossible", kind: "run", phase: "main",
                           seconds: -40, pace: 0, incline: 99)
        let prepared = invalid.plannedBlock(sequence: 1, kind: .running)
        XCTAssertNil(prepared?.durationSeconds)
        XCTAssertNil(prepared?.targetPaceSecondsPerKilometer)
        XCTAssertNil(prepared?.treadmillInclinePercent)
    }
}
