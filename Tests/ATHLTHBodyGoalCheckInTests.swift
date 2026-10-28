import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHBodyGoalCheckInTests: XCTestCase {
    private let calendar = Calendar.current
    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    }

    private func goal(
        checkInEvery: Int = 7, notifications: Bool = true,
        status: GoalStatus = .active
    ) -> ATHLTHGoal {
        ATHLTHGoal(
            title: "Reduser midjemålet",
            category: .body,
            startDate: start,
            deadline: calendar.date(byAdding: .day, value: 70, to: start),
            privacy: .privateOnly,
            status: status,
            dataSource: .manual,
            bodyMeasurementGoal: .init(
                metric: .waist, baseline: 90, target: 80,
                checkInIntervalDays: checkInEvery,
                notificationsEnabled: notifications
            )
        )
    }

    private func at(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(byAdding: .hour, value: hour,
                      to: calendar.date(byAdding: .day, value: day, to: start)!)!
    }

    func testMeasureProgressUsesSavedReadingsRatherThanMilestoneCount() {
        let goal = goal()
        var profile = ATHLTHTrainingProfile()
        XCTAssertEqual(ATHLTHBodyGoalCheckInPolicy.progress(goal, profile: profile), 0)
        XCTAssertTrue(profile.record(metric: .waist, value: 90, at: start))
        XCTAssertTrue(profile.record(metric: .waist, value: 86, at: at(4)))
        XCTAssertEqual(ATHLTHBodyGoalCheckInPolicy.progress(goal, profile: profile),
                       0.4, accuracy: 0.0001)
        XCTAssertTrue(profile.record(metric: .waist, value: 80, at: at(8)))
        XCTAssertEqual(ATHLTHBodyGoalCheckInPolicy.progress(goal, profile: profile), 1)
    }

    func testFirstDueInActivityAndSecondAfterMissedCheckIn() {
        var profile = ATHLTHTrainingProfile()
        _ = profile.record(metric: .waist, value: 90, at: start)
        XCTAssertNil(ATHLTHBodyGoalCheckInPolicy.dueUnmeasuredPeriod(
            goal: goal(), profile: profile, now: at(6)))
        XCTAssertEqual(
            ATHLTHBodyGoalCheckInPolicy.dueUnmeasuredPeriod(
                goal: goal(), profile: profile, now: at(7)
            ),
            calendar.date(byAdding: .day, value: 7, to: start)
        )
        XCTAssertEqual(
            ATHLTHBodyGoalCheckInPolicy.dueUnmeasuredPeriod(
                goal: goal(), profile: profile, now: at(14)
            ),
            calendar.date(byAdding: .day, value: 14, to: start)
        )
    }

    func testEarlyCheckInClearsBothActivityAndPendingDeviceReminderForPeriod() {
        let goal = goal()
        var profile = ATHLTHTrainingProfile()
        _ = profile.record(metric: .waist, value: 90, at: start)
        _ = profile.record(metric: .waist, value: 87, at: at(6))
        XCTAssertTrue(ATHLTHBodyGoalCheckInPolicy.completedPeriod(
            goal: goal, due: at(7), profile: profile, now: at(7)
        ))
        XCTAssertNil(ATHLTHBodyGoalCheckInPolicy.dueUnmeasuredPeriod(
            goal: goal, profile: profile, now: at(7)
        ))
    }

    func testActivityReminderIndependentOfPhoneAlertsPermission() {
        var profile = ATHLTHTrainingProfile()
        _ = profile.record(metric: .waist, value: 90, at: start)
        let noPhoneAlerts = goal(notifications: false)
        XCTAssertNotNil(ATHLTHBodyGoalCheckInPolicy.dueUnmeasuredPeriod(
            goal: noPhoneAlerts, profile: profile, now: at(7)
        ))
        XCTAssertTrue(ATHLTHBodyGoalCheckInPolicy.dueDates(
            for: noPhoneAlerts, after: at(3)
        ).isEmpty)
    }

    func testPausedGoalsNeverScheduleNewAlertsOrInboxCheckIns() {
        var profile = ATHLTHTrainingProfile()
        _ = profile.record(metric: .waist, value: 90, at: start)
        XCTAssertTrue(ATHLTHBodyGoalCheckInPolicy.dueDates(
            for: goal(status: .paused), after: at(3)
        ).isEmpty)
        XCTAssertNil(ATHLTHBodyGoalCheckInPolicy.dueUnmeasuredPeriod(
            goal: goal(status: .paused), profile: profile, now: at(7)
        ))
    }

    func testDaysUseLocalCalendarAndStableEventKeyForDeDuplication() {
        let a = UUID(), b = UUID()
        let first = ATHLTHBodyGoalCheckInPolicy.eventKey(
            accountID: a, goalID: b, due: at(7)
        )
        XCTAssertEqual(first, ATHLTHBodyGoalCheckInPolicy.eventKey(
            accountID: a, goalID: b, due: at(7, hour: 20)
        ))
        XCTAssertNotEqual(first, ATHLTHBodyGoalCheckInPolicy.eventKey(
            accountID: UUID(), goalID: b, due: at(7)
        ))
        let upcoming = ATHLTHBodyGoalCheckInPolicy.dueDates(
            for: goal(checkInEvery: 14), after: at(3)
        )
        XCTAssertEqual(upcoming.count, 3)
        XCTAssertEqual(calendar.component(.day, from: upcoming[0]), 15)
    }

    func testPreviouslySavedGoalsDecodeWithNoBodyMeasurementConfig() throws {
        let original = ATHLTHGoal(
            title: "Running goal", category: .endurance, dataSource: .manual
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
                as? [String: Any]
        )
        json.removeValue(forKey: "bodyMeasurementGoal")
        let restored = try JSONDecoder().decode(
            ATHLTHGoal.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertNil(restored.bodyMeasurementGoal)
        XCTAssertEqual(restored.id, original.id)
    }
}
