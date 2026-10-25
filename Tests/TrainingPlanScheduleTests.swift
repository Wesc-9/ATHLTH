import XCTest
@testable import ATHLTH

/// Regression coverage for the shared Train / Home / Plan calendar.
@MainActor
final class TrainingPlanScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }

    private func workout(
        id: UUID = UUID(),
        scheduledStart: Date? = nil
    ) -> PlannedSession {
        PlannedSession(
            id: id,
            title: "Interval 4×4",
            kind: .running,
            scheduledStart: scheduledStart,
            durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil,
            runningWorkout: nil
        )
    }

    private func plan(
        starting start: Date,
        session: PlannedSession,
        weekCount: Int = 2
    ) -> TrainingPlan {
        var weeks: [TrainingPlanWeek] = (1...weekCount).map { number in
            TrainingPlanWeek(
                id: UUID(),
                weekNumber: number,
                title: "Week \(number)",
                days: (1...7).map { dayIndex in
                    TrainingPlanDay(
                        id: UUID(),
                        dayIndex: dayIndex,
                        title: "Day \(dayIndex)",
                        sessions: []
                    )
                }
            )
        }
        weeks[0].days[0].sessions = [session]

        return TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Test plan",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: weeks,
            tags: [],
            createdAt: start,
            updatedAt: start,
            startDate: start,
            endDate: calendar.date(
                byAdding: .day,
                value: weekCount * 7 - 1,
                to: start
            )
        )
    }

    func testFirstTrainingDayIsStartDateEvenWhenItIsWednesday() {
        let start = day(2026, 10, 21)
        let run = workout()
        let program = plan(starting: start, session: run)

        XCTAssertEqual(
            TrainingPlanSchedule.sessions(
                in: program,
                on: start,
                calendar: calendar
            ).map(\.id),
            [run.id]
        )

        let nextMonday = day(2026, 10, 26)
        XCTAssertTrue(
            TrainingPlanSchedule.sessions(
                in: program,
                on: nextMonday,
                calendar: calendar
            ).isEmpty
        )
    }

    func testPlanDoesNotRepeatLastWeekAfterEndDate() {
        let start = day(2026, 10, 21)
        let program = plan(
            starting: start,
            session: workout(),
            weekCount: 1
        )
        let afterEnd = day(2026, 10, 28)

        XCTAssertTrue(
            TrainingPlanSchedule.sessions(
                in: program,
                on: afterEnd,
                calendar: calendar
            ).isEmpty
        )
        XCTAssertTrue(
            TrainingPlanSchedule.sessions(
                in: program,
                on: day(2026, 10, 20),
                calendar: calendar
            ).isEmpty
        )
    }

    func testRescheduledWorkoutUsesExplicitScheduledDate() {
        let start = day(2026, 10, 21)
        let movedDay = day(2026, 10, 24)
        let run = workout(scheduledStart: movedDay)
        let program = plan(starting: start, session: run)

        XCTAssertTrue(
            TrainingPlanSchedule.sessions(
                in: program,
                on: start,
                calendar: calendar
            ).isEmpty
        )
        XCTAssertEqual(
            TrainingPlanSchedule.sessions(
                in: program,
                on: movedDay,
                calendar: calendar
            ).map(\.id),
            [run.id]
        )
    }

    func testPartialStrengthLogDoesNotCompletePlanProgress() throws {
        let suite = "TrainingPlanScheduleTests.progress.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let owner = UUID()
        defer {
            for name in TrainingBackupPayload.names +
                ["strengthActive", "phoneActive"] {
                UserDefaults.standard.removeObject(
                    forKey: AccountLocalStorage.key(name, userID: owner)
                )
            }
        }

        let profile = UserProfile(
            id: UUID(),
            userID: owner,
            username: "partial-progress-test",
            displayName: "Partial Progress Test",
            bio: "",
            avatarURL: nil,
            presence: TrainingPresence(
                state: .available,
                workoutTitle: nil,
                startedAt: nil,
                visibility: .friends
            )
        )
        let app = AppSessionStore(profile: profile, defaults: defaults)
        let exercise = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: owner,
            name: "Bench Press",
            instructions: [],
            primaryMuscles: ["Chest"],
            secondaryMuscles: [],
            equipment: [],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        let planned = PlannedSession(
            id: UUID(),
            title: "Strength day",
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [
                PlannedExercise(
                    id: UUID(),
                    exerciseID: exercise.id,
                    embeddedExercise: exercise.snapshot,
                    sets: 2,
                    reps: 8,
                    targetWeightKilograms: 40,
                    targetRPE: nil,
                    restSeconds: 90,
                    notes: nil
                )
            ],
            notes: nil
        )
        let program = plan(
            starting: day(2026, 10, 21),
            session: planned,
            weekCount: 1
        )
        let store = StrengthWorkoutStore()
        store.switchAccount(owner)
        store.start(
            session: planned,
            watchSessionID: nil,
            trackingMode: .simple,
            captureDevice: .iPhone
        )
        store.completeCurrentSet(
            reps: 8,
            weightKilograms: 40,
            rpe: 7
        )
        store.finish()

        let partial = try XCTUnwrap(store.workoutHistory.first)
        let reference = day(2026, 10, 23)
        let progress = app.trainingPlanProgress(
            program,
            healthWorkouts: [],
            strengthHistory: [partial],
            referenceDate: reference
        )
        XCTAssertEqual(progress.totalSessions, 1)
        XCTAssertEqual(progress.completedSessions, 0)
        XCTAssertEqual(progress.missed.count, 1)

        var complete = partial
        complete.exercises[0].sets[1].completedReps = 8
        complete.exercises[0].sets[1].completedAt = Date()
        let completedProgress = app.trainingPlanProgress(
            program,
            healthWorkouts: [],
            strengthHistory: [complete],
            referenceDate: reference
        )
        XCTAssertTrue(complete.isFullyCompleted)
        XCTAssertEqual(completedProgress.completedSessions, 1)
        XCTAssertTrue(completedProgress.missed.isEmpty)
    }

    func testDateOnlyWorkoutCannotClaimUnrelatedAppleHealthActivity() {
        let start = day(2026, 10, 21)
        let sessions = [workout(scheduledStart: start)]
        XCTAssertTrue(
            TrainingPlanSchedule.confidentHealthCompletionIDs(
                sessions: sessions,
                healthWorkouts: [],
                on: start,
                calendar: calendar
            ).isEmpty
        )
    }

    func testMovingWorkoutKeepsExplicitTimeAndDoesNotReplaceDestinationSessions() {
        let suite = "TrainMoveExplicitTimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let profile = UserProfile(
            id: UUID(),
            userID: UUID(),
            username: "move-timed-test",
            displayName: "Move Timed Test",
            bio: "",
            avatarURL: nil,
            presence: TrainingPresence(
                state: .available,
                workoutTitle: nil,
                startedAt: nil,
                visibility: .friends
            )
        )
        let store = AppSessionStore(profile: profile, defaults: defaults)
        let start = day(2030, 1, 2)
        var run = workout()
        run.scheduledStart = Calendar.current.date(
            bySettingHour: 18, minute: 30, second: 0, of: start
        )
        run.scheduledTimeIsExplicit = true

        var program = plan(starting: start, session: run)
        let existing = workout()
        program.weeks[0].days[2].sessions.append(existing)
        XCTAssertTrue(store.addTrainingPlan(program))

        let target = day(2030, 1, 4)
        XCTAssertTrue(store.movePlanSession(
            planID: program.id, sessionID: run.id, to: target
        ))
        let updated = store.trainingPlan(withID: program.id)!
        let targetSessions = TrainingPlanSchedule.sessions(
            in: updated, on: target
        )
        XCTAssertEqual(targetSessions.count, 2)
        XCTAssertTrue(targetSessions.contains(where: { $0.id == existing.id }))
        let moved = targetSessions.first(where: { $0.id == run.id })!
        XCTAssertEqual(moved.scheduledTimeIsExplicit, true)
        let clock = Calendar.current.dateComponents(
            [.hour, .minute], from: moved.scheduledStart!
        )
        XCTAssertEqual(clock.hour, 18)
        XCTAssertEqual(clock.minute, 30)
        XCTAssertFalse(TrainingPlanSchedule.sessions(
            in: updated, on: start
        ).contains(where: { $0.id == run.id }))
    }

    func testMovingDateOnlyWorkoutDoesNotAssignMidnightClockTime() {
        let suite = "TrainMoveDateOnlyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let profile = UserProfile(
            id: UUID(),
            userID: UUID(),
            username: "move-date-only-test",
            displayName: "Move Date Only Test",
            bio: "",
            avatarURL: nil,
            presence: TrainingPresence(
                state: .available,
                workoutTitle: nil,
                startedAt: nil,
                visibility: .friends
            )
        )
        let store = AppSessionStore(profile: profile, defaults: defaults)
        let start = day(2030, 1, 2)
        var run = workout()
        run.scheduledStart = start
        run.scheduledTimeIsExplicit = false
        let program = plan(starting: start, session: run)
        XCTAssertTrue(store.addTrainingPlan(program))
        let target = day(2030, 1, 5)

        XCTAssertTrue(store.movePlanSession(
            planID: program.id, sessionID: run.id, to: target
        ))
        let updated = store.trainingPlan(withID: program.id)!
        let moved = TrainingPlanSchedule.sessions(
            in: updated, on: target
        ).first!
        XCTAssertEqual(moved.scheduledTimeIsExplicit, false)
        XCTAssertTrue(Calendar.current.isDate(
            moved.scheduledStart!, inSameDayAs: target
        ))
    }

    func testMovingWorkoutUsesPlanRelativeDayNotWeekday() {
        let suite = "TrainingPlanScheduleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let profile = UserProfile(
            id: UUID(),
            userID: UUID(),
            username: "schedule-test",
            displayName: "Schedule Test",
            bio: "",
            avatarURL: nil,
            presence: TrainingPresence(
                state: .available,
                workoutTitle: nil,
                startedAt: nil,
                visibility: .friends
            )
        )
        let store = AppSessionStore(profile: profile, defaults: defaults)
        let start = day(2030, 1, 2)
        let run = workout()
        let program = plan(starting: start, session: run)
        XCTAssertTrue(store.addTrainingPlan(program))

        let target = day(2030, 1, 4)
        XCTAssertTrue(
            store.movePlanSession(
                planID: program.id,
                sessionID: run.id,
                to: target
            )
        )

        let updated = store.trainingPlan(withID: program.id)!
        XCTAssertTrue(
            updated.weeks[0].days[2].sessions.contains {
                $0.id == run.id
            }
        )
        XCTAssertNotNil(updated.weeks[0].days[2].sessions.first?.scheduledStart)
        XCTAssertTrue(
            Calendar.current.isDate(
                updated.weeks[0].days[2].sessions.first!.scheduledStart!,
                inSameDayAs: target
            )
        )
    }
}
