import Foundation
import XCTest
@testable import ATHLTH

final class TrainingWeekTemplateEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var startDate: Date {
        calendar.date(
            from: DateComponents(
                year: 2030, month: 1, day: 7, hour: 0, minute: 0
            )
        )!
    }

    private func exercise(
        _ name: String,
        group: UUID? = nil
    ) -> PlannedExercise {
        var exercise = PlannedExercise(
            id: UUID(),
            exerciseID: UUID(),
            embeddedExercise: ExerciseSnapshot(
                name: name,
                instructions: [],
                primaryMuscles: ["biceps"],
                secondaryMuscles: [],
                equipment: ["Dumbbells"],
                imageURL: nil
            ),
            sets: 2,
            reps: 10,
            targetWeightKilograms: 12,
            targetRPE: nil,
            restSeconds: 90,
            notes: "Control the lowering",
            targetRIR: 2,
            supersetGroupID: group,
            progression: .none
        )
        exercise.setTargets = [
            PlannedExerciseSetTarget(
                reps: 10,
                weightKilograms: 12,
                restSeconds: 90,
                targetRIR: 2
            ),
            PlannedExerciseSetTarget(
                reps: 8,
                weightKilograms: 14,
                restSeconds: 90,
                targetRIR: 1
            )
        ]
        return exercise
    }

    private func workout(_ name: String, kind: WorkoutKind = .strength) -> PlannedSession {
        let group = UUID()
        return PlannedSession(
            id: UUID(),
            title: name,
            kind: kind,
            scheduledStart: calendar.date(
                byAdding: .hour,
                value: 18,
                to: startDate
            ),
            durationMinutes: 55,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: kind == .strength
                ? [exercise("Curl", group: group), exercise("Hammer Curl", group: group)]
                : [],
            notes: "Keep steady",
            runningWorkout: nil
        )
    }

    private func makePlan() -> TrainingPlan {
        let source = workout("Overkropp")
        let run = workout("Intervaller", kind: .running)
        let existing = workout("Already scheduled")

        let weeks = (1...3).map { weekNumber in
            TrainingPlanWeek(
                id: UUID(),
                weekNumber: weekNumber,
                title: "Week \(weekNumber)",
                days: (1...7).map { dayIndex in
                    let sessions: [PlannedSession]
                    if weekNumber == 1 && dayIndex == 1 {
                        sessions = [source]
                    } else if weekNumber == 1 && dayIndex == 3 {
                        sessions = [run]
                    } else if weekNumber == 2 && dayIndex == 3 {
                        sessions = [existing]
                    } else {
                        sessions = []
                    }
                    return TrainingPlanDay(
                        id: UUID(),
                        dayIndex: dayIndex,
                        title: "Day \(dayIndex)",
                        sessions: sessions
                    )
                }
            )
        }

        return TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Custom strength and run",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: weeks,
            tags: [],
            createdAt: startDate,
            updatedAt: startDate,
            startDate: startDate,
            endDate: calendar.date(byAdding: .day, value: 20, to: startDate)
        )
    }

    func testPreviewCountsOnlyEmptyFutureDays() {
        let plan = makePlan()
        let preview = TrainingWeekTemplateEngine.preview(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            now: startDate,
            calendar: calendar
        )

        XCTAssertEqual(preview.targetWeeks, 2)
        XCTAssertEqual(preview.filledDays, 3)
        XCTAssertEqual(preview.copiedSessions, 3)
    }

    func testCopyDoesNotOverwriteExistingOrSourceSessions() {
        let plan = makePlan()
        let sourceID = plan.weeks[0].days[0].sessions[0].id
        let existingID = plan.weeks[1].days[2].sessions[0].id

        guard let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            now: startDate,
            calendar: calendar
        ) else {
            XCTFail("Expected a copy")
            return
        }

        XCTAssertEqual(result.plan.weeks[0], plan.weeks[0])
        XCTAssertEqual(result.plan.weeks[1].days[2].sessions[0].id, existingID)
        XCTAssertEqual(result.plan.weeks[1].days[0].sessions.count, 1)
        XCTAssertEqual(result.plan.weeks[2].days[0].sessions.count, 1)
        XCTAssertEqual(result.plan.weeks[2].days[2].sessions.count, 1)

        let copy = result.plan.weeks[1].days[0].sessions[0]
        let original = plan.weeks[0].days[0].sessions[0]
        XCTAssertNotEqual(copy.id, sourceID)
        XCTAssertEqual(copy.title, original.title)
        XCTAssertNotEqual(copy.exercises[0].id, original.exercises[0].id)
        XCTAssertEqual(copy.exercises[0].setTargets?[1].weightKilograms, 14)
        XCTAssertNotEqual(copy.exercises[0].setTargets?[0].id, original.exercises[0].setTargets?[0].id)
        XCTAssertEqual(copy.exercises[0].supersetGroupID, copy.exercises[1].supersetGroupID)
        XCTAssertNotEqual(copy.exercises[0].supersetGroupID, original.exercises[0].supersetGroupID)
        XCTAssertEqual(
            copy.scheduledStart,
            calendar.date(byAdding: .weekOfYear, value: 1, to: original.scheduledStart!)
        )
    }

    func testCopiedClockTimeUsesCorrectTargetCalendarDay() {
        let plan = makePlan()
        // The source running session deliberately has a Monday timestamp
        // despite being placed on Wednesday, simulating a stale date field.
        let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            now: startDate,
            calendar: calendar
        )
        let copiedRun = result?.plan.weeks[2].days[2].sessions.first
        let targetDay = calendar.date(
            byAdding: .day,
            value: 16,
            to: startDate
        )!
        let expected = calendar.date(
            byAdding: .hour,
            value: 18,
            to: targetDay
        )
        XCTAssertEqual(copiedRun?.scheduledStart, expected)
    }

    func testNextWeekScopeCopiesOnlyNextWeek() {
        let plan = makePlan()
        let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .nextWeek,
            now: startDate,
            calendar: calendar
        )
        XCTAssertEqual(result?.summary.copiedSessions, 1)
        XCTAssertTrue(result?.plan.weeks[2].days.allSatisfy { $0.sessions.isEmpty } == true)
    }

    func testPastDaysAndFinalWeekAreNotCopied() {
        let plan = makePlan()
        let afterWeekTwo = calendar.date(byAdding: .day, value: 14, to: startDate)!
        let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            now: afterWeekTwo,
            calendar: calendar
        )

        XCTAssertEqual(result?.summary.copiedSessions, 2)
        XCTAssertTrue(result?.plan.weeks[1].days[0].sessions.isEmpty == true)
        XCTAssertEqual(
            TrainingWeekTemplateEngine.preview(
                plan: plan,
                sourceWeekID: plan.weeks[2].id,
                scope: .allFutureWeeks,
                now: startDate,
                calendar: calendar
            ).copiedSessions,
            0
        )
    }

    func testWeightProgressionAdjustsOnlyPrescribedWeightsByWeek() {
        let plan = makePlan()
        let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            progression: .addWeightPerWeek(2.5),
            now: startDate,
            calendar: calendar
        )
        XCTAssertNotNil(result)
        let sourceExercise = plan.weeks[0].days[0].sessions[0].exercises[0]
        let secondWeekExercise = result?.plan.weeks[1].days[0].sessions[0].exercises[0]
        let thirdWeekExercise = result?.plan.weeks[2].days[0].sessions[0].exercises[0]
        XCTAssertEqual(sourceExercise.targetWeightKilograms, 12)
        XCTAssertEqual(secondWeekExercise?.targetWeightKilograms, 14.5)
        XCTAssertEqual(thirdWeekExercise?.targetWeightKilograms, 17)
        XCTAssertEqual(secondWeekExercise?.setTargets?[1].weightKilograms, 16.5)
        XCTAssertEqual(thirdWeekExercise?.setTargets?[1].weightKilograms, 19)
        XCTAssertEqual(secondWeekExercise?.setTargets?[1].reps, 8)
    }

    func testRepetitionProgressionKeepsOriginalAndPerSetPrescriptions() {
        let plan = makePlan()
        let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            progression: .addRepsPerWeek(1),
            now: startDate,
            calendar: calendar
        )
        let second = result?.plan.weeks[1].days[0].sessions[0].exercises[0]
        let third = result?.plan.weeks[2].days[0].sessions[0].exercises[0]
        XCTAssertEqual(plan.weeks[0].days[0].sessions[0].exercises[0].reps, 10)
        XCTAssertEqual(second?.reps, 11)
        XCTAssertEqual(third?.reps, 12)
        XCTAssertEqual(second?.setTargets?[0].reps, 11)
        XCTAssertEqual(third?.setTargets?[1].reps, 10)
        XCTAssertEqual(third?.setTargets?[1].weightKilograms, 14)
    }

    func testRepeatDoesNotDuplicateAlreadyCopiedWorkouts() {
        let plan = makePlan()
        let first = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            now: startDate,
            calendar: calendar
        )
        XCTAssertNotNil(first)
        let second = first.flatMap {
            TrainingWeekTemplateEngine.copy(
                plan: $0.plan,
                sourceWeekID: plan.weeks[0].id,
                scope: .allFutureWeeks,
                now: startDate,
                calendar: calendar
            )
        }
        XCTAssertNil(second)
    }
}
