import XCTest
@testable import ATHLTH

final class ATHLTHPlannedWorkoutLifecycleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute
        ))!
    }

    func testBeforeNineteenCancelsAtNextMidnight() {
        let start = date(2026, 11, 16, 18, 45)
        XCTAssertEqual(
            ATHLTHPlannedWorkoutLifecycle.cancellationDeadline(
                for: start, calendar: calendar
            ),
            date(2026, 11, 17, 0)
        )
        XCTAssertFalse(ATHLTHPlannedWorkoutLifecycle.shouldCancel(
            scheduled: start,
            now: date(2026, 11, 16, 23, 59),
            hasStarted: false, isCompleted: false,
            isCancelled: false, calendar: calendar
        ))
        XCTAssertTrue(ATHLTHPlannedWorkoutLifecycle.shouldCancel(
            scheduled: start,
            now: date(2026, 11, 17, 0),
            hasStarted: false, isCompleted: false,
            isCancelled: false, calendar: calendar
        ))
    }

    func testAtNineteenGetsFiveHoursAndLateWorkoutCrossesMidnight() {
        XCTAssertEqual(
            ATHLTHPlannedWorkoutLifecycle.cancellationDeadline(
                for: date(2026, 11, 16, 19), calendar: calendar
            ),
            date(2026, 11, 17, 0)
        )
        XCTAssertEqual(
            ATHLTHPlannedWorkoutLifecycle.cancellationDeadline(
                for: date(2026, 11, 16, 23), calendar: calendar
            ),
            date(2026, 11, 17, 4)
        )
    }

    func testActuallyStartedOrCompletedWorkoutIsNeverAutoCancelled() {
        let start = date(2026, 11, 16, 23)
        let later = date(2026, 11, 18, 12)
        for started in [true, false] {
            for completed in [true, false] {
                if started || completed {
                    XCTAssertFalse(ATHLTHPlannedWorkoutLifecycle.shouldCancel(
                        scheduled: start, now: later,
                        hasStarted: started,
                        isCompleted: completed,
                        isCancelled: false,
                        calendar: calendar
                    ))
                }
            }
        }
        XCTAssertFalse(ATHLTHPlannedWorkoutLifecycle.shouldCancel(
            scheduled: nil, now: later, hasStarted: false,
            isCompleted: false, isCancelled: false, calendar: calendar
        ))
    }

    func testUpdatingClockOnlyChangesTimeOfSelectedDay() {
        let day = date(2026, 11, 18, 9)
        let time = date(2026, 11, 16, 21, 25)
        XCTAssertEqual(
            ATHLTHPlannedWorkoutLifecycle.updatingClock(
                scheduled: day, clock: time, calendar: calendar
            ),
            date(2026, 11, 18, 21, 25)
        )
    }

    func testFinishedCalendarTitleAndTimesStayExternalOnly() {
        let original = "1min/1min Intervaller"
        let start = date(2026, 11, 16, 18)
        let end = date(2026, 11, 16, 18, 55)
        let complete = ATHLTHCalendarWorkoutStatus(
            completed: true, actualStart: start, actualEnd: end
        )
        XCTAssertEqual(complete.calendarTitle(original), "✔️ " + original)
        XCTAssertTrue(complete.hasValidRecordedInterval)
        XCTAssertEqual(original, "1min/1min Intervaller")
        let planned = ATHLTHCalendarWorkoutStatus()
        XCTAssertEqual(planned.calendarTitle(original), original)
        XCTAssertFalse(planned.hasValidRecordedInterval)
        let cancelled = ATHLTHCalendarWorkoutStatus(cancelled: true)
        XCTAssertEqual(cancelled.calendarTitle(original), "Avlyst · " + original)
    }

    func testPreviouslyPersistedWorkoutWithoutCancelledAtStillDecodes() throws {
        let original = PlannedSession(
            id: UUID(), title: "5 x 3", kind: .running,
            scheduledStart: date(2026, 11, 16, 20),
            durationMinutes: 40, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        let data = try JSONEncoder().encode(original)
        let old = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(old["cancelledAt"])
        let decoded = try JSONDecoder().decode(
            PlannedSession.self, from: data
        )
        XCTAssertNil(decoded.cancelledAt)
    }

    func testDaylightSavingUsesCalendarMidnight() {
        let eveningBeforeDST = date(2026, 3, 28, 18)
        let cutoff = ATHLTHPlannedWorkoutLifecycle.cancellationDeadline(
            for: eveningBeforeDST, calendar: calendar
        )
        XCTAssertEqual(cutoff, date(2026, 3, 29, 0))
    }
}
