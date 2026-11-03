import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTournamentCalendarIntegrationTests: XCTestCase {
    private func example(
        opensAt: Date, deadlineAt: Date
    ) -> ATHLTHTournamentCalendarItem {
        ATHLTHTournamentCalendarItem(
            id: UUID(),
            tournamentID: UUID(),
            tournamentTitle: "Høstliga",
            exerciseTitle: "Løp 5 km",
            opensAt: opensAt,
            deadlineAt: deadlineAt,
            exerciseNumber: 1,
            phase: "group"
        )
    }

    func testOngoingMultidayExerciseIsVisibleWithoutInventingTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let opening = Date(timeIntervalSince1970: 1_800_000_000)
        let due = opening.addingTimeInterval(72 * 3_600)
        let exercise = example(opensAt: opening, deadlineAt: due)
        let middle = opening.addingTimeInterval(36 * 3_600)

        XCTAssertNil(exercise.relevantDate(on: middle, calendar: calendar))
        XCTAssertTrue(exercise.isOngoing(on: middle, calendar: calendar))
        XCTAssertFalse(exercise.isDeadline(on: middle, calendar: calendar))
        XCTAssertFalse(exercise.isOngoing(
            on: due.addingTimeInterval(86_400), calendar: calendar
        ))
    }

    func testOpeningAndDeadlineUseDistinctStableNotificationIdentifiers() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let item = example(
            opensAt: start.addingTimeInterval(86_400),
            deadlineAt: start.addingTimeInterval(3 * 86_400)
        )
        let account = UUID()
        let results = ATHLTHTournamentExerciseReminderPolicy.reminders(
            for: [item], accountID: account, now: start
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(Set(results.map(\.id)).count, 2)
        XCTAssertTrue(results.allSatisfy { $0.fireAt > start })
        XCTAssertTrue(results.allSatisfy {
            $0.id.contains(account.uuidString)
        })
    }

    func testExpiredAndTooManyExerciseNotificationsAreDiscarded() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = example(
            opensAt: now.addingTimeInterval(-86_400),
            deadlineAt: now.addingTimeInterval(-60)
        )
        let future = (0..<30).map { i in
            example(
                opensAt: now.addingTimeInterval(Double(i+1)*3_600),
                deadlineAt: now.addingTimeInterval(Double(i+2)*3_600)
            )
        }
        let results = ATHLTHTournamentExerciseReminderPolicy.reminders(
            for: [expired]+future, accountID: UUID(), now: now
        )
        XCTAssertFalse(results.contains { $0.slotID == expired.id })
        XCTAssertLessThanOrEqual(results.count, 24)
    }
}
