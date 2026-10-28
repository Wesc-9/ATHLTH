import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHGymCoachStrengthLibraryTests: XCTestCase {
    @MainActor
    func testAllElevenTemplatesLoadWithExecutableExercises() {
        XCTAssertEqual(ATHLTHGymCoachStrengthLibrary.programs.count, 11)
        XCTAssertEqual(ATHLTHGymCoachStrengthLibrary.catalogEntries.count, 11)
        XCTAssertEqual(ATHLTHGymCoachStrengthLibrary.workoutCatalogEntries.count, 40)
        XCTAssertTrue(ATHLTHGymCoachStrengthLibrary.programs.allSatisfy {
            !$0.program.workouts.isEmpty && $0.program.workouts.allSatisfy {
                !$0.exercises.isEmpty
            }
        })
    }

    @MainActor
    func testAllImportedStrengthBlocksRetainPrescribedSetsRepsAndRecovery() {
        for program in ATHLTHGymCoachStrengthLibrary.programs {
            for workout in program.program.workouts {
                let blocks = ATHLTHGymCoachStrengthLibrary.blocks(for: workout)
                let exercises = blocks.filter { $0.kind == .exercise }
                XCTAssertEqual(exercises.count, workout.exercises.count, program.slug)
                XCTAssertEqual(blocks.first?.resolvedPhase, .warmup)
                for (block, source) in zip(exercises, workout.exercises) {
                    XCTAssertEqual(block.setCount, source.targetSets)
                    XCTAssertEqual(block.repetitions, source.targetRepsMin)
                    XCTAssertEqual(block.restBetweenSetsSeconds,
                                   Double(source.restSec))
                    XCTAssertEqual(block.targetEffortRPE, 10 - source.targetRIR)
                    XCTAssertNil(block.targetWeightKilograms)
                }
            }
        }
    }

    @MainActor
    func testABThreeDayPlansAlternateAcrossWeeks() throws {
        for slug in ["starting-strength-3day", "stronglifts-5x5-3day"] {
            let plan = try XCTUnwrap(ATHLTHGymCoachStrengthLibrary.programs.first {
                $0.slug == slug
            })
            let weekOne = ATHLTHGymCoachStrengthLibrary.sourceWorkouts(
                for: plan, week: 1
            )
            let weekTwo = ATHLTHGymCoachStrengthLibrary.sourceWorkouts(
                for: plan, week: 2
            )
            XCTAssertEqual(weekOne.count, 3)
            XCTAssertEqual(weekTwo.count, 3)
            XCTAssertEqual(weekOne[0].name, weekOne[2].name)
            XCTAssertNotEqual(weekOne[0].name, weekTwo[0].name)
        }
    }

    @MainActor
    func testPlanSessionsUseSingleATHLTHTimelineNotParallelExercises() throws {
        let program = try XCTUnwrap(ATHLTHGymCoachStrengthLibrary.programs.first)
        let source = try XCTUnwrap(program.program.workouts.first)
        let session = ATHLTHGymCoachStrengthLibrary.plannedSession(
            source, program: program, week: 2
        )
        XCTAssertEqual(session.kind, .strength)
        XCTAssertTrue(session.exercises.isEmpty)
        XCTAssertFalse(session.resolvedWorkoutBlocks.isEmpty)
        XCTAssertTrue(session.resolvedWorkoutBlocks.contains {
            $0.kind == .exercise
        })
        XCTAssertTrue(session.resolvedWorkoutBlocks.allSatisfy {
            $0.targetWeightKilograms == nil
        })
    }

    @MainActor
    func testEveryCatalogProgramCanResolveItsWeek() throws {
        for entry in ATHLTHGymCoachStrengthLibrary.catalogEntries {
            let program = try XCTUnwrap(
                ATHLTHGymCoachStrengthLibrary.program(for: entry.slug)
            )
            let sessions = ATHLTHGymCoachStrengthLibrary.sourceWorkouts(
                for: program, week: entry.durationWeeks
            )
            XCTAssertEqual(sessions.count, entry.sessionsPerWeek)
            for workout in sessions {
                let planned = ATHLTHGymCoachStrengthLibrary.plannedSession(
                    workout, program: program, week: entry.durationWeeks
                )
                XCTAssertFalse(planned.resolvedWorkoutBlocks.isEmpty)
            }
        }
    }
}
