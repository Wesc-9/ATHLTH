import Foundation
import XCTest
@testable import ATHLTH

final class OfficialWeeklyChallengeCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func challenge(
        endInterval: TimeInterval,
        startInterval: TimeInterval = -2 * 86_400
    ) -> OfficialWeeklyChallenge {
        OfficialWeeklyChallenge(
            id: UUID(),
            title: "Momentum Streak",
            subtitle: "Stay active",
            kind: .streak,
            targetValue: 4,
            startsAt: now.addingTimeInterval(startInterval),
            endsAt: now.addingTimeInterval(endInterval),
            heroAsset: "weekly",
            source: "rotation",
            createdBy: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    func testCountdownShowsDaysAndHoursInsteadOfZeroDays() {
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now.addingTimeInterval(2 * 86_400 + 5 * 3600),
                now: now,
                norwegian: true
            ),
            "2 dager og 5 timer igjen"
        )
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now.addingTimeInterval(16 * 3600),
                now: now,
                norwegian: true
            ),
            "16 timer igjen"
        )
    }

    func testCountdownUsesMinutesInsideLastHour() {
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now.addingTimeInterval(59 * 60),
                now: now,
                norwegian: true
            ),
            "59 minutter igjen"
        )
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now.addingTimeInterval(59 * 60 + 59),
                now: now,
                norwegian: true
            ),
            "59 minutter igjen"
        )
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now.addingTimeInterval(23 * 3600 + 59 * 60 + 59),
                now: now,
                norwegian: true
            ),
            "23 timer igjen"
        )
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now.addingTimeInterval(20),
                now: now,
                norwegian: true
            ),
            "1 minutt igjen"
        )
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now,
                now: now,
                norwegian: true
            ),
            "Avsluttet"
        )
    }

    func testEnglishCountdownGrammar() {
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now.addingTimeInterval(86_400 + 3600),
                now: now,
                norwegian: false
            ),
            "1 day, 1 hour left"
        )
        XCTAssertEqual(
            OfficialWeeklyChallengeCountdown.remaining(
                until: now.addingTimeInterval(60),
                now: now,
                norwegian: false
            ),
            "1 minute left"
        )
    }

    func testReminderOnlyBeforeDeadlineForAnIncompleteActiveChallenge() {
        let weekly = challenge(endInterval: 2 * 86_400)
        let policy = OfficialWeeklyChallengeReminderPolicy.self
        XCTAssertEqual(
            policy.reminderDate(for: weekly, joined: true, completed: false, now: now),
            now.addingTimeInterval(86_400)
        )
        XCTAssertNil(policy.reminderDate(
            for: weekly, joined: true, completed: true, now: now
        ))
        XCTAssertNil(policy.reminderDate(
            for: weekly, joined: false, completed: false, now: now
        ))
        XCTAssertNil(policy.reminderDate(
            for: challenge(endInterval: 3600), joined: true, completed: false, now: now
        ))
        XCTAssertNil(policy.reminderDate(
            for: challenge(endInterval: 2 * 86_400, startInterval: 3600),
            joined: true, completed: false, now: now
        ))
        XCTAssertEqual(
            policy.identifier(for: weekly.id),
            policy.identifier(for: weekly.id)
        )
    }
}
