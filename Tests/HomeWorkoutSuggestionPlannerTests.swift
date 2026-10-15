import XCTest
@testable import ATHLTH

final class HomeWorkoutSuggestionPlannerTests: XCTestCase {
    private func template() -> PlannedSession {
        var workout = PlannedSession(
            id: UUID(),
            title: "Intervaller",
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 35,
            targetDistanceKilometers: 5,
            targetPaceSecondsPerKilometer: 310,
            routeID: nil,
            exercises: [],
            notes: "Økt fra Workouts"
        )
        workout.workoutBlocks = [
            WorkoutTemplateBlock(
                sequence: 1,
                kind: .run,
                title: "Løp",
                exerciseSlug: nil,
                distanceMeters: 1_000,
                repetitions: nil,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: nil,
                phase: .main
            )
        ]
        workout.workoutTemplateID = UUID()
        workout.workoutCategory = "running"
        return workout
    }

    func testPlanningFromTemplateCreatesIndependentWorkoutWithBlocks() {
        let original = template()
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let first = HomeWorkoutSuggestionPlanner.independentSession(
            from: original, start: start
        )
        let second = HomeWorkoutSuggestionPlanner.independentSession(
            from: original, start: start
        )

        XCTAssertNotEqual(original.id, first.id)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(original.scheduledStart)
        XCTAssertEqual(first.scheduledStart, start)
        XCTAssertEqual(first.title, original.title)
        XCTAssertEqual(first.workoutBlocks, original.workoutBlocks)
        XCTAssertEqual(first.workoutTemplateID, original.workoutTemplateID)
        XCTAssertEqual(first.workoutCategory, original.workoutCategory)
        XCTAssertEqual(first.targetDistanceKilometers, 5)
    }

    func testDateValidationRejectsPastOrAnotherDay() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2030, month: 10, day: 15, hour: 0
        )))
        let now = try XCTUnwrap(cal.date(
            byAdding: .hour, value: 9, to: day
        ))
        let ten = try XCTUnwrap(cal.date(
            byAdding: .hour, value: 10, to: day
        ))
        let yesterday = try XCTUnwrap(cal.date(
            byAdding: .day, value: -1, to: day
        ))
        XCTAssertTrue(HomeWorkoutSuggestionPlanner.canSchedule(
            on: day, at: ten, now: now, calendar: cal
        ))
        XCTAssertFalse(HomeWorkoutSuggestionPlanner.canSchedule(
            on: day, at: now, now: now, calendar: cal
        ))
        XCTAssertFalse(HomeWorkoutSuggestionPlanner.canSchedule(
            on: day, at: yesterday, now: now, calendar: cal
        ))
    }
}
