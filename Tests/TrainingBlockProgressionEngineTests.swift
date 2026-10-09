import Foundation
import XCTest
@testable import ATHLTH

final class TrainingBlockProgressionEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var start: Date {
        calendar.date(from: DateComponents(
            year: 2030, month: 1, day: 7
        ))!
    }
    private let blockID = UUID()

    private func exercise(
        weight: Double? = 12,
        reps: Int = 10,
        sets: Int = 3
    ) -> PlannedExercise {
        PlannedExercise(
            id: UUID(),
            exerciseID: UUID(),
            embeddedExercise: ExerciseSnapshot(
                name: "Curl",
                instructions: [],
                primaryMuscles: ["biceps"],
                secondaryMuscles: [],
                equipment: ["Dumbbells"],
                imageURL: nil
            ),
            sets: sets,
            reps: reps,
            targetWeightKilograms: weight,
            targetRPE: nil,
            restSeconds: 90,
            notes: nil
        )
    }
    private func session(
        week: Int,
        kind: WorkoutKind = .strength,
        exercise: PlannedExercise? = nil
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: "Workout \(week)", kind: kind,
            scheduledStart: nil, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: kind == .strength ? [exercise ?? self.exercise()] : [],
            notes: nil
        )
    }
    private func plan() -> TrainingPlan {
        let weeks = (1...4).map { week in
            TrainingPlanWeek(
                id: UUID(), weekNumber: week, title: "Week \(week)",
                days: (1...7).map { day in
                    TrainingPlanDay(
                        id: UUID(), dayIndex: day,
                        title: "Day \(day)",
                        sessions: day == 1 ? [session(week: week)] : []
                    )
                }
            )
        }
        var result = TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Biceps",
            summary: "", visibility: .privateOnly, version: 1,
            weeks: weeks, tags: [], createdAt: start, updatedAt: start,
            startDate: start
        )
        result.trainingBlocks = [
            TrainingPlanBlock(
                id: blockID, title: "Build", purpose: .progression,
                startWeek: 1, endWeek: 4, goal: "Get stronger"
            )
        ]
        return result
    }
    private func rule(_ mode: TrainingBlockProgressionKind) -> TrainingBlockProgressionRule {
        TrainingBlockProgressionRule(kind: mode)
    }
    private func workout(_ plan: TrainingPlan, week: Int) -> PlannedSession {
        plan.weeks[week - 1].days[0].sessions[0]
    }

    func testWeightProgressionTouchesOnlyFuturePrescribedWorkouts() throws {
        let initial = plan()
        let protectedID = workout(initial, week: 3).id
        let result = try XCTUnwrap(TrainingBlockProgressionEngine.prepare(
            plan: initial, blockID: blockID,
            rule: rule(.weight), protectedSessionIDs: [protectedID],
            now: start, calendar: calendar
        ))
        XCTAssertEqual(result.summary.changedWorkouts, 2)
        XCTAssertEqual(result.summary.protectedCompleted, 1)
        XCTAssertEqual(result.summary.unchangedUnprescribed, 1)
        XCTAssertEqual(workout(initial, week: 2).exercises[0].targetWeightKilograms, 12)
        XCTAssertEqual(workout(result.plan, week: 2).exercises[0].targetWeightKilograms, 14.5)
        XCTAssertEqual(workout(result.plan, week: 3), workout(initial, week: 3))
        XCTAssertEqual(workout(result.plan, week: 4).exercises[0].targetWeightKilograms, 19.5)
        XCTAssertEqual(workout(result.plan, week: 2).id, workout(initial, week: 2).id)
        XCTAssertEqual(workout(result.plan, week: 2).exercises[0].id,
                       workout(initial, week: 2).exercises[0].id)
    }

    func testSecondApplyIsIdempotent() throws {
        let first = try XCTUnwrap(TrainingBlockProgressionEngine.prepare(
            plan: plan(), blockID: blockID,
            rule: rule(.repetitions), protectedSessionIDs: [],
            now: start, calendar: calendar
        ))
        XCTAssertEqual(first.summary.changedWorkouts, 3)
        let second = try XCTUnwrap(TrainingBlockProgressionEngine.prepare(
            plan: first.plan, blockID: blockID,
            rule: rule(.repetitions), protectedSessionIDs: [],
            now: start, calendar: calendar
        ))
        XCTAssertEqual(second.summary.changedWorkouts, 0)
        XCTAssertEqual(second.summary.alreadyApplied, 3)
        XCTAssertEqual(workout(second.plan, week: 4).exercises[0].reps, 13)
    }

    func testPastSessionsNeverChange() throws {
        let initial = plan()
        let future = calendar.date(byAdding: .day, value: 15, to: start)!
        let result = try XCTUnwrap(TrainingBlockProgressionEngine.prepare(
            plan: initial, blockID: blockID,
            rule: rule(.weight), protectedSessionIDs: [],
            now: future, calendar: calendar
        ))
        XCTAssertEqual(result.summary.protectedPast, 3)
        XCTAssertEqual(result.summary.changedWorkouts, 1)
        for week in 1...3 {
            XCTAssertEqual(workout(result.plan, week: week),
                           workout(initial, week: week))
        }
    }

    func testRecoveryKeepsWarmupsAndIndividualSetIDs() throws {
        var initial = plan()
        var curl = workout(initial, week: 1).exercises[0]
        curl.sets = 5
        curl.setTargets = [
            PlannedExerciseSetTarget(reps: 12, weightKilograms: 5,
                                     isWarmUp: true, setType: .warmUp),
            PlannedExerciseSetTarget(reps: 10, weightKilograms: 12),
            PlannedExerciseSetTarget(reps: 10, weightKilograms: 12),
            PlannedExerciseSetTarget(reps: 8, weightKilograms: 14),
            PlannedExerciseSetTarget(reps: 8, weightKilograms: 14)
        ]
        initial.weeks[0].days[0].sessions[0].exercises[0] = curl
        let result = try XCTUnwrap(TrainingBlockProgressionEngine.prepare(
            plan: initial, blockID: blockID, rule: rule(.recovery),
            protectedSessionIDs: [], now: start, calendar: calendar
        ))
        let modified = workout(result.plan, week: 1).exercises[0]
        XCTAssertEqual(modified.sets, 3) // Warmup + 2 work sets.
        XCTAssertEqual(modified.setTargets?[0].id, curl.setTargets?[0].id)
        XCTAssertEqual(modified.setTargets?[0].weightKilograms, 5)
        XCTAssertEqual(modified.setTargets?[1].weightKilograms, 11)
        XCTAssertEqual(modified.targetWeightKilograms, 11)
    }

    func testUnknownOrZeroLoadsDoNotBecomeInventedWeight() throws {
        var initial = plan()
        var curl = workout(initial, week: 2).exercises[0]
        curl.targetWeightKilograms = nil
        curl.setTargets = [
            PlannedExerciseSetTarget(reps: 10, weightKilograms: 0),
            PlannedExerciseSetTarget(reps: 8, weightKilograms: nil)
        ]
        curl.sets = 2
        initial.weeks[1].days[0].sessions[0].exercises[0] = curl
        let result = try XCTUnwrap(TrainingBlockProgressionEngine.prepare(
            plan: initial, blockID: blockID, rule: rule(.weight),
            protectedSessionIDs: [], now: start, calendar: calendar
        ))
        let preserved = workout(result.plan, week: 2).exercises[0]
        XCTAssertNil(preserved.targetWeightKilograms)
        XCTAssertEqual(preserved.setTargets?[0].weightKilograms, 0)
        XCTAssertNil(preserved.setTargets?[1].weightKilograms)
        XCTAssertEqual(result.summary.changedWorkouts, 2)
    }

    func testRunningSessionsAreUntouched() throws {
        var initial = plan()
        initial.weeks[2].days[0].sessions = [session(week: 3, kind: .running)]
        let result = try XCTUnwrap(TrainingBlockProgressionEngine.prepare(
            plan: initial, blockID: blockID, rule: rule(.weight),
            protectedSessionIDs: [], now: start, calendar: calendar
        ))
        XCTAssertEqual(workout(result.plan, week: 3), workout(initial, week: 3))
    }
}
