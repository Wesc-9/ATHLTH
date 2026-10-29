import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCalendarParticipationPolicyTests: XCTestCase {
    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute
        ))!
    }

    private func workout(start: Date?) -> PlannedSession {
        PlannedSession(
            title: "Rolig tur", kind: .running,
            scheduledStart: start, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    func testAcceptedAndUnansweredCommunityParticipation() {
        let tomorrow = date(2027, 5, 12)
        let now = date(2027, 5, 11)

        XCTAssertEqual(ATHLTHCalendarParticipationPolicy.community(
            eventStatus: "upcoming", endsAt: tomorrow,
            attendance: .going, isCreator: false, now: now
        ), .confirmed)
        XCTAssertEqual(ATHLTHCalendarParticipationPolicy.community(
            eventStatus: "upcoming", endsAt: tomorrow,
            attendance: .maybe, isCreator: false, now: now
        ), .tentative)
        XCTAssertNil(ATHLTHCalendarParticipationPolicy.community(
            eventStatus: "upcoming", endsAt: tomorrow,
            attendance: nil, isCreator: false, now: now
        ))
        XCTAssertNil(ATHLTHCalendarParticipationPolicy.community(
            eventStatus: "cancelled", endsAt: tomorrow,
            attendance: .going, isCreator: false, now: now
        ))
    }

    func testClubConfirmedUnansweredAndDeclined() {
        let upcoming = date(2027, 5, 12)
        let now = date(2027, 5, 11)
        for pending in [nil, "maybe", "waitlist"] as [String?] {
            XCTAssertEqual(ATHLTHCalendarParticipationPolicy.club(
                eventStatus: "upcoming", endsAt: upcoming,
                rsvp: pending, now: now
            ), .tentative)
        }
        XCTAssertEqual(ATHLTHCalendarParticipationPolicy.club(
            eventStatus: "upcoming", endsAt: upcoming,
            rsvp: "going", now: now
        ), .confirmed)
        XCTAssertNil(ATHLTHCalendarParticipationPolicy.club(
            eventStatus: "upcoming", endsAt: upcoming,
            rsvp: "not_going", now: now
        ))
        XCTAssertNil(ATHLTHCalendarParticipationPolicy.club(
            eventStatus: "upcoming", endsAt: upcoming,
            rsvp: "declined", now: now
        ))
    }

    func testChallengeInvitationAcceptDeclineWithdrawalAndCreator() {
        func status(_ state: ChallengeParticipantState?) ->
            ATHLTHCalendarParticipationPolicy.Attendance? {
            ATHLTHCalendarParticipationPolicy.challenge(
                status: .upcoming, participantState: state,
                isCreator: false
            )
        }
        XCTAssertEqual(status(.accepted), .confirmed)
        XCTAssertEqual(status(.invited), .tentative)
        XCTAssertNil(status(.declined))
        XCTAssertNil(status(.withdrawn))
        XCTAssertNil(status(nil))
        XCTAssertEqual(ATHLTHCalendarParticipationPolicy.challenge(
            status: .invited, participantState: nil, isCreator: true
        ), .confirmed)
        XCTAssertNil(ATHLTHCalendarParticipationPolicy.challenge(
            status: .cancelled, participantState: .accepted,
            isCreator: true
        ))
    }

    func testExplicitWorkoutStartOverridesOldPlanDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let planStart = date(2026, 10, 29)
        let moved = date(2026, 11, 2, 7, 45)
        XCTAssertEqual(ATHLTHCalendarParticipationPolicy.scheduledDate(
            session: workout(start: moved),
            planStart: planStart,
            weekNumber: 1, dayIndex: 2,
            calendar: calendar
        ), moved)

        XCTAssertEqual(ATHLTHCalendarParticipationPolicy.scheduledDate(
            session: workout(start: nil),
            planStart: planStart,
            weekNumber: 2, dayIndex: 1,
            calendar: calendar
        ), date(2026, 11, 5))
    }

    func testLongChallengeWindowDoesNotBlockEntireCalendarWeek() {
        let start = date(2027, 5, 12, 10, 30)
        let afterWeek = date(2027, 5, 19, 10, 30)
        XCTAssertEqual(ATHLTHCalendarParticipationPolicy.challengeEnd(
            start: start, explicitEnd: afterWeek
        ), start.addingTimeInterval(3600))
        XCTAssertEqual(ATHLTHCalendarParticipationPolicy.challengeEnd(
            start: start, explicitEnd: start.addingTimeInterval(5400)
        ), start.addingTimeInterval(5400))
    }
}
