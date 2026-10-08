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

    func testCopyMatchesPreviewForLegacyZeroNumberedWeek() {
        var plan = makePlan()
        // Legacy imported plans may have weekNumber == 0.
        plan.weeks[2].weekNumber = 0
        let secondWeek = calendar.date(
            byAdding: .day,
            value: 8,
            to: startDate
        )!

        // Week three is upcoming but week one is no longer available to
        // copy into week two. Preview and copy must agree on calendar dates.
        let preview = TrainingWeekTemplateEngine.preview(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            now: secondWeek,
            calendar: calendar
        )
        XCTAssertEqual(preview.targetWeeks, 1)
        XCTAssertEqual(preview.copiedSessions, 2)

        guard let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            now: secondWeek,
            calendar: calendar
        ) else {
            return XCTFail("Preview showed sessions to copy")
        }
        XCTAssertEqual(result.summary, preview)
        XCTAssertEqual(result.plan.weeks[2].days[0].sessions.count, 1)
        XCTAssertEqual(result.plan.weeks[2].days[2].sessions.count, 1)
        XCTAssertTrue(result.plan.weeks[1].days[0].sessions.isEmpty)

        let copiedDate = result.plan.weeks[2].days[0].sessions[0]
            .scheduledStart!
        let expected = calendar.date(
            byAdding: .day,
            value: 14,
            to: startDate
        )!
        XCTAssertTrue(calendar.isDate(copiedDate, inSameDayAs: expected))
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

    private func eightWeekPlan() -> TrainingPlan {
        var plan = makePlan()
        let source = plan.weeks[0]
        let protectedSession = plan.weeks[1].days[2].sessions
        plan.weeks = (1...8).map { number in
            TrainingPlanWeek(
                id: number == 1 ? source.id : UUID(),
                weekNumber: number,
                title: "Week \(number)",
                days: (1...7).map { day in
                    TrainingPlanDay(
                        id: UUID(),
                        dayIndex: day,
                        title: "Day \(day)",
                        sessions: number == 1
                            ? source.days[day - 1].sessions
                            : number == 2 && day == 3
                                ? protectedSession
                                : []
                    )
                }
            )
        }
        plan.endDate = calendar.date(byAdding: .day, value: 55, to: startDate)
        return plan
    }

    func testFourWeekBlockBuildAndDeloadRepeatAcrossTwoCycles() {
        let plan = eightWeekPlan()
        let originalProtected = plan.weeks[1].days[2].sessions[0]
        guard let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            progression: .fourWeekStrengthBlock,
            now: startDate,
            calendar: calendar
        ) else {
            XCTFail("Expected two blocks")
            return
        }

        let weeks = result.plan.weeks
        XCTAssertEqual(weeks[1].days[2].sessions[0], originalProtected)
        XCTAssertNil(weeks[1].strengthPhase, "Mixed existing strength workouts are not labeled a full block")
        XCTAssertEqual(weeks[2].strengthPhase, .build)
        XCTAssertEqual(weeks[3].strengthPhase, .deload)
        XCTAssertEqual(weeks[4].strengthPhase, .build)
        XCTAssertEqual(weeks[7].strengthPhase, .deload)

        XCTAssertEqual(weeks[1].days[0].sessions[0].exercises[0].targetWeightKilograms, 14.5)
        XCTAssertEqual(weeks[2].days[0].sessions[0].exercises[0].targetWeightKilograms, 17)
        XCTAssertEqual(weeks[3].days[0].sessions[0].exercises[0].targetWeightKilograms, 11)
        XCTAssertEqual(weeks[3].days[0].sessions[0].exercises[0].sets, 1)
        XCTAssertEqual(weeks[3].days[0].sessions[0].exercises[0].setTargets?.count, 1)
        XCTAssertEqual(weeks[4].days[0].sessions[0].exercises[0].targetWeightKilograms, 17)
        XCTAssertEqual(weeks[5].days[0].sessions[0].exercises[0].targetWeightKilograms, 19.5)
        XCTAssertEqual(weeks[7].days[0].sessions[0].exercises[0].targetWeightKilograms, 15.5)

        // Running is copied as normal: no periodization applied to its metrics.
        let originalRun = plan.weeks[0].days[2].sessions[0]
        let copiedRun = weeks[3].days[2].sessions[0]
        XCTAssertEqual(copiedRun.kind, .running)
        XCTAssertEqual(copiedRun.durationMinutes, originalRun.durationMinutes)
        XCTAssertEqual(copiedRun.targetDistanceKilometers, originalRun.targetDistanceKilometers)
        XCTAssertEqual(copiedRun.exercises, originalRun.exercises)
        XCTAssertEqual(plan.weeks[0].days[0].sessions[0].exercises[0].sets, 2)
    }

    func testBlockLeavesUnknownLoadEmptyAndPreservesTimedTargets() {
        var plan = eightWeekPlan()
        var source = plan.weeks[0].days[0].sessions[0]
        source.exercises[0].targetWeightKilograms = nil
        source.exercises[0].setTargets = source.exercises[0].setTargets?.map { old in
            var updated = old
            updated.weightKilograms = nil
            return updated
        }
        source.exercises[1].targetKind = .time
        source.exercises[1].reps = nil
        source.exercises[1].targetWeightKilograms = nil
        source.exercises[1].sets = 4
        source.exercises[1].setTargets = (0..<4).map { _ in
            PlannedExerciseSetTarget(durationSeconds: 45)
        }
        plan.weeks[0].days[0].sessions[0] = source

        let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            progression: .fourWeekStrengthBlock,
            now: startDate,
            calendar: calendar
        )
        let load = result?.plan.weeks[2].days[0].sessions[0].exercises[0]
        XCTAssertNil(load?.targetWeightKilograms)
        XCTAssertNil(load?.setTargets?.first?.weightKilograms)

        let deload = result?.plan.weeks[3].days[0].sessions[0]
        XCTAssertNil(deload?.exercises[0].targetWeightKilograms)
        XCTAssertEqual(deload?.exercises[1].sets, 2)
        XCTAssertEqual(deload?.exercises[1].setTargets?.first?.durationSeconds, 45)
    }

    func testFourWeekBlockPreservesExplicitZeroKilograms() {
        var plan = eightWeekPlan()
        plan.weeks[0].days[0].sessions[0].exercises[0].targetWeightKilograms = 0
        plan.weeks[0].days[0].sessions[0].exercises[0].setTargets =
            plan.weeks[0].days[0].sessions[0].exercises[0].setTargets?.map { original in
                var target = original
                target.weightKilograms = 0
                return target
            }

        let result = TrainingWeekTemplateEngine.copy(
            plan: plan,
            sourceWeekID: plan.weeks[0].id,
            scope: .allFutureWeeks,
            progression: .fourWeekStrengthBlock,
            now: startDate,
            calendar: calendar
        )

        let build = result?.plan.weeks[1].days[0].sessions[0].exercises[0]
        let deload = result?.plan.weeks[3].days[0].sessions[0].exercises[0]
        XCTAssertEqual(build?.targetWeightKilograms, 0)
        XCTAssertEqual(build?.setTargets?.first?.weightKilograms, 0)
        XCTAssertEqual(deload?.targetWeightKilograms, 0)
    }

    func testStrengthPhaseEncodesAndLegacyWeekDecodesWithoutIt() throws {
        let plan = makePlan()
        var tagged = plan.weeks[0]
        XCTAssertNil(tagged.strengthPhase)
        tagged.strengthPhase = .deload

        let data = try JSONEncoder().encode(tagged)
        let decoded = try JSONDecoder().decode(TrainingPlanWeek.self, from: data)
        XCTAssertEqual(decoded.strengthPhase, .deload)

        let oldData = try JSONEncoder().encode(plan.weeks[0])
        let legacy = try JSONDecoder().decode(TrainingPlanWeek.self, from: oldData)
        XCTAssertNil(legacy.strengthPhase)
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
