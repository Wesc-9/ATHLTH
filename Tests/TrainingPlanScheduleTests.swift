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
        XCTAssertEqual(
            updated.weeks[0].days[2].sessions.first?.scheduledStart,
            target
        )
    }
}
