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
    func testTimeOnlyPickerUsesTappedSundayNotItsHiddenDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))

        // Sunday 18 October, 05:04; the athlete chooses 18:00.
        let selectedSunday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 18, hour: 0, minute: 0
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 18, hour: 5, minute: 4
        )))
        // Simulate a time-only DatePicker whose backing date is yesterday.
        let pickerValue = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 17, hour: 18, minute: 0
        )))
        XCTAssertFalse(HomeWorkoutSuggestionPlanner.canSchedule(
            on: selectedSunday, at: pickerValue, now: now, calendar: calendar
        ))
        let resolved = try XCTUnwrap(HomeWorkoutSuggestionPlanner.scheduledStart(
            on: selectedSunday, clockTime: pickerValue, calendar: calendar
        ))
        XCTAssertEqual(calendar.component(.day, from: resolved), 18)
        XCTAssertEqual(calendar.component(.hour, from: resolved), 18)
        XCTAssertTrue(HomeWorkoutSuggestionPlanner.canSchedule(
            on: selectedSunday, at: resolved, now: now, calendar: calendar
        ))
    }

    func testTimeOnlyPickerRejectsPastTimeAfterNormalizingToToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 18, hour: 0
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 18, hour: 18, minute: 15
        )))
        let clock = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 19, hour: 18
        )))
        let resolved = try XCTUnwrap(HomeWorkoutSuggestionPlanner.scheduledStart(
            on: today, clockTime: clock, calendar: calendar
        ))
        XCTAssertFalse(HomeWorkoutSuggestionPlanner.canSchedule(
            on: today, at: resolved, now: now, calendar: calendar
        ))
    }

    func testTimeOnlyPickerKeepsCorrectDateAcrossDSTBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 29, hour: 0
        )))
        let sourceClock = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 28, hour: 18, minute: 30
        )))
        let result = try XCTUnwrap(HomeWorkoutSuggestionPlanner.scheduledStart(
            on: day, clockTime: sourceClock, calendar: calendar
        ))
        XCTAssertEqual(calendar.component(.day, from: result), 29)
        XCTAssertEqual(calendar.component(.hour, from: result), 18)
        XCTAssertEqual(calendar.component(.minute, from: result), 30)
    }


    func testDefaultStartIsSixBeforeSixAndCurrentMinuteAfterSix() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let day = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 19, hour: 0
        )))
        let at1726 = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 19, hour: 17, minute: 26, second: 32
        )))
        let at1832 = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 19, hour: 18, minute: 32, second: 42
        )))
        let six = try XCTUnwrap(HomeWorkoutSuggestionPlanner.defaultStart(
            on: day, now: at1726, calendar: cal
        ))
        XCTAssertEqual(cal.component(.hour, from: six), 18)
        XCTAssertEqual(cal.component(.minute, from: six), 0)
        XCTAssertTrue(HomeWorkoutSuggestionPlanner.canSchedule(
            on: day, at: six, now: at1726, calendar: cal
        ))
        let thisMinute = try XCTUnwrap(HomeWorkoutSuggestionPlanner.defaultStart(
            on: day, now: at1832, calendar: cal
        ))
        XCTAssertEqual(cal.component(.hour, from: thisMinute), 18)
        XCTAssertEqual(cal.component(.minute, from: thisMinute), 32)
        XCTAssertTrue(HomeWorkoutSuggestionPlanner.canSchedule(
            on: day, at: thisMinute, now: at1832, calendar: cal,
            automaticSelectionCreatedAt: at1832
        ))
        // A manual choice of a now-past minute remains invalid.
        XCTAssertFalse(HomeWorkoutSuggestionPlanner.canSchedule(
            on: day, at: thisMinute, now: at1832, calendar: cal
        ))
    }

    func testAutomaticStartHasFifteenMinuteGraceForLongSetup() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let opened = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 19, hour: 18, minute: 25, second: 31
        )))
        let chosen = try XCTUnwrap(HomeWorkoutSuggestionPlanner.defaultStart(
            on: opened, now: opened, calendar: cal
        ))
        let tenMinutesLater = opened.addingTimeInterval(10 * 60)
        let sixteenMinutesLater = opened.addingTimeInterval(16 * 60)
        XCTAssertTrue(HomeWorkoutSuggestionPlanner.canSchedule(
            on: opened, at: chosen, now: tenMinutesLater, calendar: cal,
            automaticSelectionCreatedAt: opened
        ))
        XCTAssertFalse(HomeWorkoutSuggestionPlanner.canSchedule(
            on: opened, at: chosen, now: sixteenMinutesLater, calendar: cal,
            automaticSelectionCreatedAt: opened
        ))
        XCTAssertFalse(HomeWorkoutSuggestionPlanner.canSchedule(
            on: opened, at: chosen, now: tenMinutesLater, calendar: cal
        ))
    }

    func testSixOClockDefaultRemainsValidShortlyAfterSix() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let opened = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 19, hour: 17, minute: 56
        )))
        let saved = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 19, hour: 18, minute: 7
        )))
        let defaultStart = try XCTUnwrap(HomeWorkoutSuggestionPlanner.defaultStart(
            on: opened, now: opened, calendar: cal
        ))
        XCTAssertTrue(HomeWorkoutSuggestionPlanner.canSchedule(
            on: opened, at: defaultStart, now: saved, calendar: cal,
            automaticSelectionCreatedAt: opened
        ))
    }

    func testFutureDayStillDefaultsToSixButPastDayCannotBeSaved() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let now = try XCTUnwrap(cal.date(from: DateComponents(
            year: 2026, month: 10, day: 20, hour: 20, minute: 40
        )))
        let tomorrow = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: now))
        let yesterday = try XCTUnwrap(cal.date(byAdding: .day, value: -1, to: now))
        let futureDefault = try XCTUnwrap(HomeWorkoutSuggestionPlanner.defaultStart(
            on: tomorrow, now: now, calendar: cal
        ))
        XCTAssertEqual(cal.component(.hour, from: futureDefault), 18)
        XCTAssertEqual(cal.component(.minute, from: futureDefault), 0)
        XCTAssertTrue(HomeWorkoutSuggestionPlanner.canSchedule(
            on: tomorrow, at: futureDefault, now: now, calendar: cal
        ))
        let pastDefault = try XCTUnwrap(HomeWorkoutSuggestionPlanner.defaultStart(
            on: yesterday, now: yesterday, calendar: cal
        ))
        XCTAssertFalse(HomeWorkoutSuggestionPlanner.canSchedule(
            on: yesterday, at: pastDefault, now: now, calendar: cal,
            automaticSelectionCreatedAt: yesterday
        ))
    }
}
