import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanStructureAdvisorTests: XCTestCase {
    private func workout(
        id: UUID = UUID(),
        title: String = "Full body",
        duration: Int? = 45
    ) -> PlannedSession {
        PlannedSession(
            id: id, title: title, kind: .strength,
            scheduledStart: nil, durationMinutes: duration,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    private func plan(_ sessionsByWeek: [[PlannedSession]]) -> TrainingPlan {
        let weeks = sessionsByWeek.enumerated().map { index, sessions in
            TrainingPlanWeek(
                id: UUID(), weekNumber: index + 1, title: "Week \(index + 1)",
                days: (1...7).map { day in
                    TrainingPlanDay(
                        id: UUID(), dayIndex: day, title: "Day \(day)",
                        sessions: day == 1 ? sessions : []
                    )
                }
            )
        }
        return TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Quality review",
            summary: "", visibility: .privateOnly, version: 1,
            weeks: weeks, tags: [], createdAt: Date(),
            updatedAt: Date(), startDate: Date()
        )
    }

    func testEmptyProgramGetsActionableNotice() {
        let report = ATHLTHPlanStructureAdvisor.inspect(plan([[]]))
        XCTAssertTrue(report.contains(where: { $0.id == "empty-plan" }))
    }

    func testUniqueWorkoutIDsAreNotReportedAsDuplicates() {
        let report = ATHLTHPlanStructureAdvisor.inspect(
            plan([[workout()], [workout()]])
        )
        XCTAssertFalse(report.contains(where: { $0.id == "duplicate-session-identities" }))
        XCTAssertFalse(report.contains(where: { $0.id == "empty-plan" }))
    }

    func testDuplicatedWorkoutIDCannotGoUnnoticed() {
        let repeated = UUID()
        let report = ATHLTHPlanStructureAdvisor.inspect(
            plan([[workout(id: repeated)], [workout(id: repeated)]])
        )
        XCTAssertEqual(report.first?.id, "duplicate-session-identities")
        XCTAssertEqual(report.first?.severity, .attention)
    }

    func testInvalidWorkoutNameAndDurationHaveIndependentNotices() {
        let session = workout(title: " ", duration: -5)
        let report = ATHLTHPlanStructureAdvisor.inspect(plan([[session]]))
        XCTAssertTrue(report.contains(where: { $0.id == "title-\(session.id)" }))
        XCTAssertTrue(report.contains(where: { $0.id == "duration-\(session.id)" }))
    }

    func testMultipleWorkoutsAreInformationNotAutomaticRescheduling() {
        let report = ATHLTHPlanStructureAdvisor.inspect(
            plan([[workout(), workout(), workout()]])
        )
        XCTAssertTrue(report.contains(where: { $0.id.hasPrefix("busy-") &&
            $0.severity == .information }))
    }
}
