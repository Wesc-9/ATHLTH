import Foundation
import XCTest
@testable import ATHLTH

final class StrengthWarmUpExerciseTests: XCTestCase {
    private func exercise() -> PlannedExercise {
        PlannedExercise(
            id: UUID(),
            exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Warm-up row",
                instructions: [],
                primaryMuscles: ["Back"],
                secondaryMuscles: [],
                equipment: ["Cable"],
                imageURL: nil
            ),
            sets: 3,
            reps: 12,
            targetWeightKilograms: nil,
            targetRPE: nil,
            restSeconds: 60,
            notes: nil,
            targetRIR: nil,
            supersetGroupID: nil,
            progression: .none
        )
    }

    func testExerciseWarmUpClassifiesEveryPlannedSetAndCanBeReverted() throws {
        var planned = exercise()
        XCTAssertFalse(planned.isWarmUpExercise)

        planned.setEntireExerciseWarmUp(true)
        XCTAssertTrue(planned.isWarmUpExercise)
        XCTAssertEqual(planned.resolvedSetTargets.count, 3)
        XCTAssertTrue(planned.resolvedSetTargets.allSatisfy {
            $0.isWarmUp == true && $0.setType == .warmUp
        })

        let restored = try JSONDecoder().decode(
            PlannedExercise.self,
            from: JSONEncoder().encode(planned)
        )
        XCTAssertTrue(restored.isWarmUpExercise)
        XCTAssertEqual(restored.resolvedSetTargets.map(\.reps), [12, 12, 12])

        planned.setEntireExerciseWarmUp(false)
        XCTAssertFalse(planned.isWarmUpExercise)
        XCTAssertTrue(planned.resolvedSetTargets.allSatisfy {
            $0.isWarmUp == false && $0.setType == .work
        })
    }

    func testPartialWarmUpRemainsAWorkingExercise() {
        var planned = exercise()
        planned.setTargets = [
            PlannedExerciseSetTarget(reps: 8, isWarmUp: true, setType: .warmUp),
            PlannedExerciseSetTarget(reps: 10, isWarmUp: false, setType: .work),
            PlannedExerciseSetTarget(reps: 10, isWarmUp: false, setType: .work)
        ]
        XCTAssertFalse(planned.isWarmUpExercise)
        planned.setEntireExerciseWarmUp(true)
        XCTAssertTrue(planned.isWarmUpExercise)
        XCTAssertEqual(planned.resolvedSetTargets.map(\.reps), [8, 10, 10])
    }

    func testCompletedWarmUpSetDoesNotCountTowardTrainingLoad() {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        var first = StrengthSetLog(
            id: UUID(),
            setNumber: 1,
            plannedReps: 10,
            plannedWeightKilograms: 10,
            completedReps: 10,
            completedWeightKilograms: 10,
            rpe: nil,
            completedAt: date,
            restSeconds: 45
        )
        first.isWarmUp = true
        first.plannedSetType = .warmUp
        XCTAssertFalse(first.countsTowardTrainingLoad)

        var second = first
        second.isWarmUp = false
        second.plannedSetType = .work
        XCTAssertTrue(second.countsTowardTrainingLoad)
    }
}
