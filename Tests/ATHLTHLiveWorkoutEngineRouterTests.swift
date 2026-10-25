import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHLiveWorkoutEngineRouterTests: XCTestCase {
    private func block(
        _ title: String,
        kind: WorkoutTemplateBlockKind,
        sequence: Int,
        phase: WorkoutPhaseKind = .main
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence,
            kind: kind,
            title: title,
            exerciseSlug: nil,
            distanceMeters: nil,
            repetitions: nil,
            durationSeconds: 120,
            targetWeightKilograms: nil,
            loadNote: nil,
            notes: nil,
            phase: phase
        )
    }

    func testHybridWorkoutSwitchesInterfaceWithoutChangingIdentity() throws {
        let workoutID = UUID()
        let blocks = [
            block("Warm-up", kind: .exercise, sequence: 1, phase: .warmup),
            block("4 x 4", kind: .run, sequence: 2),
            block("Recovery", kind: .rest, sequence: 3, phase: .recovery),
            block("Squats", kind: .exercise, sequence: 4),
            block("Cool-down", kind: .note, sequence: 5, phase: .cooldown)
        ]
        let expected: [ATHLTHLiveWorkoutEngine] = [
            .strength, .endurance, .recovery, .strength, .instructions
        ]
        let routes = try blocks.indices.map { index in
            try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
                workoutID: workoutID, blocks: blocks, index: index
            ))
        }
        XCTAssertEqual(routes.map(\.engine), expected)
        XCTAssertTrue(routes.allSatisfy { $0.workoutID == workoutID })
        for i in 1..<routes.count {
            let transition = try XCTUnwrap(
                ATHLTHLiveWorkoutEngineRouter.transition(
                    from: routes[i - 1], to: routes[i]
                )
            )
            XCTAssertTrue(transition.preservesWorkoutIdentity)
            XCTAssertTrue(transition.switchesEngine)
        }
    }

    func testConsecutiveIntervalsDoNotNeedAnotherMotor() throws {
        let workoutID = UUID()
        let blocks = [
            block("Effort 1", kind: .run, sequence: 1),
            block("Effort 2", kind: .run, sequence: 2)
        ]
        let first = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: workoutID, blocks: blocks, index: 0
        ))
        let next = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: workoutID, blocks: blocks, index: 1
        ))
        let transition = try XCTUnwrap(
            ATHLTHLiveWorkoutEngineRouter.transition(from: first, to: next)
        )
        XCTAssertFalse(transition.switchesEngine)
    }

    func testDifferentWorkoutCannotBeTreatedAsMotorTransition() throws {
        let blocks = [block("Squat", kind: .exercise, sequence: 1)]
        let first = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: UUID(), blocks: blocks, index: 0
        ))
        let other = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: UUID(), blocks: blocks, index: 0
        ))
        XCTAssertNil(ATHLTHLiveWorkoutEngineRouter.transition(
            from: first, to: other
        ))
        XCTAssertNil(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: first.workoutID, blocks: blocks, index: 1
        ))
    }

    func testLegacyNoteAndWellnessRouting() {
        var note = block("Notes", kind: .note, sequence: 1)
        XCTAssertEqual(
            ATHLTHLiveWorkoutEngineRouter.engine(for: note), .instructions
        )
        note.wellnessKind = .stretching
        XCTAssertEqual(
            ATHLTHLiveWorkoutEngineRouter.engine(for: note), .mobility
        )
    }
    func testCyclingStepUsesDedicatedDisplayButKeepsWorkoutIdentity() throws {
        let workoutID = UUID()
        var cycling = block("Cycling warm-up", kind: .note,
                            sequence: 1, phase: .warmup)
        cycling.activityTag = "cycling"
        cycling.targetHeartRateZone = 2
        cycling.targetEffortRPE = 4
        let strength = block("Squats", kind: .exercise, sequence: 2)
        let cooldown = block("Cool-down run", kind: .run,
                             sequence: 3, phase: .cooldown)
        let blocks = [cycling, strength, cooldown]
        let routes = try blocks.indices.map {
            try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
                workoutID: workoutID, blocks: blocks, index: $0
            ))
        }
        XCTAssertEqual(routes.map(\.engine),
                       [.cycling, .strength, .endurance])
        XCTAssertTrue(routes.allSatisfy { $0.workoutID == workoutID })
        let transition = try XCTUnwrap(
            ATHLTHLiveWorkoutEngineRouter.transition(
                from: routes[0], to: routes[1]
            )
        )
        XCTAssertTrue(transition.preservesWorkoutIdentity)
        XCTAssertTrue(transition.switchesEngine)
    }

}
