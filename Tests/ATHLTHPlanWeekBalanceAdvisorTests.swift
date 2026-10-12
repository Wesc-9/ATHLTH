import XCTest
@testable import ATHLTH

final class ATHLTHPlanWeekBalanceAdvisorTests: XCTestCase {
    private func session(
        kind: WorkoutKind,
        minutes: Int? = 45
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: kind.title,
            kind: kind,
            scheduledStart: nil,
            durationMinutes: minutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }

    private func week(
        number: Int = 1,
        scheduled: [Int: [PlannedSession]]
    ) -> TrainingPlanWeek {
        TrainingPlanWeek(
            id: UUID(),
            weekNumber: number,
            title: "Week \(number)",
            days: (1...7).map { number in
                TrainingPlanDay(
                    id: UUID(),
                    dayIndex: number,
                    title: "Day \(number)",
                    sessions: scheduled[number] ?? []
                )
            }
        )
    }

    func testMixedStrengthAndRunSameDayIsAnInformationalReview() {
        let report = ATHLTHPlanWeekBalanceAdvisor.inspect(week(scheduled: [
            1: [session(kind: .running), session(kind: .strength)],
            4: [session(kind: .running)]
        ]))
        XCTAssertEqual(report.runningCount, 2)
        XCTAssertEqual(report.strengthCount, 1)
        XCTAssertEqual(report.scheduledDays, 2)
        XCTAssertEqual(report.completePlannedMinutes, 135)
        XCTAssertTrue(report.findings.contains(where: {
            $0.kind == .mixedDay && $0.dayIndex == 1
        }))
    }

    func testThreeConsecutiveRunsSuggestReviewWithoutAssumingIntensity() {
        let report = ATHLTHPlanWeekBalanceAdvisor.inspect(week(scheduled: [
            1: [session(kind: .running)],
            2: [session(kind: .running)],
            3: [session(kind: .running)]
        ]))
        XCTAssertTrue(report.findings.contains(where: {
            $0.kind == .consecutiveRuns && $0.dayIndex == 3
        }))
        XCTAssertFalse(report.findings.contains(where: { $0.kind == .consecutiveStrength }))
    }

    func testThreeConsecutiveStrengthDaysSuggestExerciseReview() {
        let report = ATHLTHPlanWeekBalanceAdvisor.inspect(week(scheduled: [
            2: [session(kind: .strength)],
            3: [session(kind: .strength)],
            4: [session(kind: .strength)]
        ]))
        XCTAssertTrue(report.findings.contains(where: {
            $0.kind == .consecutiveStrength && $0.dayIndex == 4
        }))
    }

    func testFiveConsecutiveRunOrStrengthDaysAreNotMedicalRiskScore() {
        let report = ATHLTHPlanWeekBalanceAdvisor.inspect(week(scheduled: [
            1: [session(kind: .running)],
            2: [session(kind: .strength)],
            3: [session(kind: .running)],
            4: [session(kind: .strength)],
            5: [session(kind: .running)]
        ]))
        XCTAssertTrue(report.findings.contains(where: {
            $0.kind == .crowdedWeek && $0.dayIndex == 5
        }))
        XCTAssertEqual(report.scheduledDays, 5)
    }

    func testMissingDurationsAreNotSilentlyEstimated() {
        let report = ATHLTHPlanWeekBalanceAdvisor.inspect(week(scheduled: [
            1: [session(kind: .running, minutes: 30)],
            3: [session(kind: .strength, minutes: nil)]
        ]))
        XCTAssertNil(report.completePlannedMinutes)
        XCTAssertEqual(report.knownDurationMinutes, 30)
        XCTAssertEqual(report.sessionsWithoutDuration, 1)
    }

    func testLongDayRequiresCompleteDayDurations() {
        let reported = ATHLTHPlanWeekBalanceAdvisor.inspect(week(scheduled: [
            1: [session(kind: .running, minutes: 95),
                session(kind: .strength, minutes: 60)]
        ]))
        XCTAssertTrue(reported.findings.contains(where: { $0.kind == .longDay }))

        let unknown = ATHLTHPlanWeekBalanceAdvisor.inspect(week(scheduled: [
            1: [session(kind: .running, minutes: 95),
                session(kind: .strength, minutes: nil)]
        ]))
        XCTAssertFalse(unknown.findings.contains(where: { $0.kind == .longDay }))
    }

    func testMobilityAndWalkingNotMisclassifiedAsRunningOrStrength() {
        let report = ATHLTHPlanWeekBalanceAdvisor.inspect(week(scheduled: [
            1: [session(kind: .walking)],
            2: [session(kind: .mobility)],
            3: [session(kind: .recovery)]
        ]))
        XCTAssertEqual(report.otherCount, 3)
        XCTAssertEqual(report.runningCount, 0)
        XCTAssertEqual(report.strengthCount, 0)
        XCTAssertTrue(report.findings.isEmpty)
    }
}
