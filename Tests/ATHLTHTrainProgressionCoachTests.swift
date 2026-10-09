import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTrainProgressionCoachTests: XCTestCase {
    private let start = Calendar.current.date(
        from: DateComponents(year: 2030, month: 1, day: 7)
    )!

    private func planned(load: Double? = 14) -> PlannedExercise {
        PlannedExercise(
            id: UUID(), exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: "Dumbbell Curl",
                instructions: [], primaryMuscles: ["biceps"],
                secondaryMuscles: [], equipment: ["Dumbbells"],
                imageURL: nil
            ),
            sets: 2, reps: 10,
            targetWeightKilograms: load, targetRPE: nil,
            restSeconds: 90, notes: nil
        )
    }

    private func makePlan(weeks: Int = 4, load: Double? = 14) -> TrainingPlan {
        let list = (1...weeks).map { index in
            let workout = PlannedSession(
                id: UUID(), title: "Upper Body", kind: .strength,
                scheduledStart: nil, durationMinutes: 45,
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil, exercises: [planned(load: load)],
                notes: nil
            )
            return TrainingPlanWeek(
                id: UUID(), weekNumber: index, title: "Week \(index)",
                days: [
                    TrainingPlanDay(
                        id: UUID(), dayIndex: 1, title: "Monday",
                        sessions: [workout]
                    )
                ]
            )
        }
        return TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Strong arms",
            summary: "", visibility: .privateOnly, version: 1,
            weeks: list, tags: [], createdAt: start,
            updatedAt: start, startDate: start
        )
    }

    private func logged(
        _ sessionID: UUID,
        offset: Int,
        achieved: Bool = true,
        planWeight: Double = 14
    ) -> StrengthWorkoutLog {
        let workoutDate = Calendar.current.date(
            byAdding: .day, value: offset * 7, to: start
        )!
        let reps = achieved ? 10 : 8
        let sets = (1...2).map { index in
            StrengthSetLog(
                id: UUID(), setNumber: index,
                plannedReps: 10, plannedWeightKilograms: planWeight,
                completedReps: reps, completedWeightKilograms: planWeight,
                rpe: nil, completedAt: workoutDate,
                restSeconds: 90
            )
        }
        return StrengthWorkoutLog(
            id: UUID(), plannedSessionID: sessionID,
            watchSessionID: nil, captureDevice: .iPhone,
            trackingMode: .advanced, title: "Upper Body",
            startedAt: workoutDate,
            endedAt: workoutDate.addingTimeInterval(1800),
            exercises: [
                StrengthExerciseLog(
                    id: UUID(), plannedExerciseID: nil,
                    exercise: ExerciseSnapshot(
                        name: "Dumbbell Curl",
                        instructions: [], primaryMuscles: ["biceps"],
                        secondaryMuscles: [], equipment: ["Dumbbells"],
                        imageURL: nil
                    ),
                    sets: sets, completedAt: workoutDate
                )
            ],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: nil, activeCalories: nil,
                averageHeartRate: nil, maxHeartRate: nil
            )
        )
    }

    private func date(week: Int) -> Date {
        Calendar.current.date(
            byAdding: .day, value: (week - 1) * 7, to: start
        )!
    }

    func testSuggestOnlyAfterTwoSeparateSuccessfulSessions() throws {
        let plan = makePlan(weeks: 3)
        let first = plan.weeks[0].days[0].sessions[0]
        let second = plan.weeks[1].days[0].sessions[0]
        let third = plan.weeks[2].days[0].sessions[0]
        let history = [
            logged(first.id, offset: 0),
            logged(second.id, offset: 1)
        ]
        let suggested = ATHLTHTrainProgressionCoach.suggestions(
            plan: plan, strengthHistory: history,
            completedSessionIDs: [first.id, second.id],
            skippedSessionIDs: [],
            increaseKg: 1,
            now: date(week: 3)
        )
        XCTAssertEqual(suggested.count, 1)
        XCTAssertEqual(suggested.first?.workoutID, third.id)
        XCTAssertEqual(suggested.first?.beforeLoad, 14)
        XCTAssertEqual(suggested.first?.proposedLoad, 15)
        XCTAssertEqual(suggested.first?.workingSetsVerified, 4)
    }

    func testOneSessionInsufficientAndFutureCompletedIsProtected() {
        let plan = makePlan(weeks: 3)
        let first = plan.weeks[0].days[0].sessions[0]
        let second = plan.weeks[1].days[0].sessions[0]
        let third = plan.weeks[2].days[0].sessions[0]
        let one = ATHLTHTrainProgressionCoach.suggestions(
            plan: plan, strengthHistory: [logged(first.id, offset: 0)],
            completedSessionIDs: [first.id], skippedSessionIDs: [],
            now: date(week: 3)
        )
        XCTAssertTrue(one.isEmpty)
        let fullyLogged = ATHLTHTrainProgressionCoach.suggestions(
            plan: plan,
            strengthHistory: [logged(first.id, offset: 0), logged(second.id, offset: 1)],
            completedSessionIDs: [first.id, second.id, third.id],
            skippedSessionIDs: [], now: date(week: 3)
        )
        XCTAssertTrue(fullyLogged.isEmpty)
    }

    func testLatestFailedTargetsPreventSuggestionEvenAfterOlderSuccesses() {
        let plan = makePlan(weeks: 4)
        let all = plan.weeks.map { $0.days[0].sessions[0].id }
        let log = [
            logged(all[0], offset: 0),
            logged(all[1], offset: 1),
            logged(all[2], offset: 2, achieved: false)
        ]
        let result = ATHLTHTrainProgressionCoach.suggestions(
            plan: plan, strengthHistory: log,
            completedSessionIDs: Set(all.prefix(3)),
            skippedSessionIDs: [], now: date(week: 4)
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testUnlinkedLogsNeverQualify() {
        let plan = makePlan(weeks: 3)
        let first = plan.weeks[0].days[0].sessions[0].id
        let result = ATHLTHTrainProgressionCoach.suggestions(
            plan: plan, strengthHistory: [
                logged(first, offset: 0),
                logged(UUID(), offset: 1)
            ],
            completedSessionIDs: [first], skippedSessionIDs: [],
            now: date(week: 3)
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testNoInventionOfUnprescribedOrZeroWeight() {
        var exercise = planned(load: nil)
        XCTAssertNil(ATHLTHTrainProgressionCoach.adjustedExercise(
            exercise, increaseKg: 1
        ))
        exercise.targetWeightKilograms = 0
        XCTAssertNil(ATHLTHTrainProgressionCoach.adjustedExercise(
            exercise, increaseKg: 1
        ))
        let result = ATHLTHTrainProgressionCoach.suggestions(
            plan: makePlan(weeks: 3, load: nil),
            strengthHistory: [], completedSessionIDs: [],
            skippedSessionIDs: [], now: date(week: 3)
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testAdvancedWarmupPreservedAlongWithPerSetIdentity() throws {
        var exercise = planned(load: 14)
        let warmup = PlannedExerciseSetTarget(
            reps: 10, weightKilograms: 5,
            isWarmUp: true, setType: .warmUp
        )
        let first = PlannedExerciseSetTarget(reps: 10, weightKilograms: 14)
        let second = PlannedExerciseSetTarget(reps: 8, weightKilograms: 16)
        exercise.sets = 3
        exercise.setTargets = [warmup, first, second]
        let adjusted = try XCTUnwrap(
            ATHLTHTrainProgressionCoach.adjustedExercise(
                exercise, increaseKg: 1
            )
        )
        XCTAssertEqual(adjusted.setTargets?.map(\.id), [warmup.id, first.id, second.id])
        XCTAssertEqual(adjusted.setTargets?.map(\.weightKilograms), [5, 15, 17])
        XCTAssertEqual(adjusted.setTargets?[0].reps, 10)
        XCTAssertEqual(adjusted.targetWeightKilograms, 15)
        XCTAssertEqual(exercise.setTargets?[1].weightKilograms, 14)
    }
}
