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

    func testCaptureAwareRouteRejectsSilentOwnerHandoff() throws {
        let id = UUID()
        let blocks = [
            block("Run", kind: .run, sequence: 1),
            block("Strength", kind: .exercise, sequence: 2)
        ]
        let first = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: id, blocks: blocks, index: 0
        ))
        let next = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: id, blocks: blocks, index: 1
        ))
        func session(_ owner: ATHLTHWorkoutRecordingOwner) -> ATHLTHWorkoutSessionState {
            ATHLTHWorkoutSessionState(
                workoutID: id, plannedSessionID: nil,
                recordingOwner: owner, activity: .strength,
                phase: .work, engine: .strength,
                startedAt: Date(timeIntervalSince1970: 1_900_000_000),
                activeElapsedSeconds: 20, stageIndex: nil, stageCount: nil
            )
        }
        XCTAssertNotNil(ATHLTHLiveWorkoutEngineRouter.transition(
            from: first, to: next,
            previousSession: session(.appleWatch), nextSession: session(.appleWatch)
        ))
        XCTAssertNil(ATHLTHLiveWorkoutEngineRouter.transition(
            from: first, to: next,
            previousSession: session(.appleWatch), nextSession: session(.iPhone)
        ))
    }

    @MainActor
    func testRuntimeRoutingRequiresMatchingLiveRecording() throws {
        let phone = IPhoneWorkoutStore()
        let strength = StrengthWorkoutStore()
        strength.startFreestyle(watchSessionID: nil)
        let id = try XCTUnwrap(strength.activeWorkout?.id)
        let blocks = [
            block("Squat", kind: .exercise, sequence: 1),
            block("Run", kind: .run, sequence: 2)
        ]
        let first = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: id, blocks: blocks, index: 0
        ))
        let second = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: id, blocks: blocks, index: 1
        ))
        XCTAssertNotNil(try ATHLTHLiveWorkoutEngineRouter.transition(
            from: first, to: second, phone: phone, strength: strength
        ))
        let unrelated = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: UUID(), blocks: blocks, index: 1
        ))
        XCTAssertNil(try ATHLTHLiveWorkoutEngineRouter.transition(
            from: first, to: unrelated, phone: phone, strength: strength
        ))
        XCTAssertEqual(strength.activeWorkout?.id, id)
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


    func testOrderedRecipeTransitionPreservesEveryStageAndSingleIdentity() throws {
        let workoutID = UUID()
        let planned = [
            block("Warm-up", kind: .run, sequence: 1, phase: .warmup),
            block("Instruction", kind: .note, sequence: 2),
            block("Rest", kind: .rest, sequence: 3, phase: .recovery),
            block("Strength", kind: .exercise, sequence: 4)
        ]
        for index in 0..<(planned.count - 1) {
            let transition = try XCTUnwrap(
                ATHLTHLiveWorkoutEngineRouter.advance(
                    workoutID: workoutID, blocks: planned, from: index
                )
            )
            XCTAssertEqual(transition.previous.blockIndex, index)
            XCTAssertEqual(transition.next.blockIndex, index + 1)
            XCTAssertTrue(transition.preservesWorkoutIdentity)
            XCTAssertEqual(transition.next.workoutID, workoutID)
        }
        XCTAssertNil(ATHLTHLiveWorkoutEngineRouter.advance(
            workoutID: workoutID, blocks: planned, from: -1
        ))
        XCTAssertNil(ATHLTHLiveWorkoutEngineRouter.advance(
            workoutID: workoutID, blocks: planned,
            from: planned.count - 1
        ))
    }

    func testDuplicateStageIdentityCannotAdvanceOrInventAnExtraWorkout() {
        let id = UUID()
        let first = block("Work", kind: .exercise, sequence: 1)
        let duplicated = block("Work", kind: .exercise, sequence: 1)
        XCTAssertNil(ATHLTHLiveWorkoutEngineRouter.advance(
            workoutID: id, blocks: [first, duplicated], from: 0
        ))
        let recovered = [
            first, block("Rest", kind: .rest, sequence: 2)
        ]
        XCTAssertNotNil(ATHLTHLiveWorkoutEngineRouter.advance(
            workoutID: id, blocks: recovered, from: 0
        ))
    }


    func testAllSportTagsShareOneRouterWithSpecificPresentation() throws {
        let sportTags: [(String, ATHLTHWorkoutSportMode, ATHLTHLiveWorkoutEngine)] = [
            ("cycling", .cycling, .cycling),
            ("rowing", .rowing, .endurance),
            ("stairClimber", .stairClimber, .endurance),
            ("hiit", .hiit, .instructions),
            ("circuit", .circuit, .instructions),
            ("functional", .functional, .instructions),
            ("yoga", .yoga, .mobility),
            ("mobility", .mobility, .mobility),
            ("sports", .sports, .instructions),
            ("other", .other, .instructions)
        ]
        let workoutID = UUID()
        for (tag, expectedMode, expectedEngine) in sportTags {
            var block = self.block(tag, kind: .note, sequence: 1)
            block.activityTag = tag
            let mode = ATHLTHWorkoutSportMode.forBlock(block)
            XCTAssertEqual(mode, expectedMode, tag)
            XCTAssertEqual(ATHLTHLiveWorkoutEngineRouter.engine(for: block),
                           expectedEngine, tag)
            XCTAssertFalse(mode.title.isEmpty, tag)
            XCTAssertFalse(mode.systemImage.isEmpty, tag)
            XCTAssertTrue(mode.showsPlannedTargets, tag)
            let route = try XCTUnwrap(ATHLTHLiveWorkoutEngineRouter.route(
                workoutID: workoutID, blocks: [block], index: 0
            ))
            XCTAssertEqual(route.workoutID, workoutID, tag)
        }

        let text = block("Instruction", kind: .note, sequence: 1)
        XCTAssertEqual(ATHLTHWorkoutSportMode.forBlock(text), .instructions)
        XCTAssertFalse(ATHLTHWorkoutSportMode.forBlock(text).showsPlannedTargets)
        XCTAssertEqual(ATHLTHWorkoutSportMode(category: "stair_climbing"),
                       .stairClimber)
    }

}
