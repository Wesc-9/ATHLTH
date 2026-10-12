import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPlanProgramTrendAdvisorTests: XCTestCase {
    private func session(
        kind: WorkoutKind,
        minutes: Int? = 45,
        distance: Double? = nil
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: kind.title,
            kind: kind,
            scheduledStart: nil,
            durationMinutes: minutes,
            targetDistanceKilometers: distance,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }

    private func week(
        _ index: Int,
        _ sessions: [PlannedSession],
        phase: TrainingWeekStrengthPhase? = nil
    ) -> TrainingPlanWeek {
        var week = TrainingPlanWeek(
            id: UUID(),
            weekNumber: index,
            title: "Week \(index)",
            days: (1...7).map { day in
                TrainingPlanDay(
                    id: UUID(),
                    dayIndex: day,
                    title: "Day \(day)",
                    sessions: day == 1 ? sessions : []
                )
            }
        )
        week.strengthPhase = phase
        return week
    }

    private func plan(_ weeks: [TrainingPlanWeek]) -> TrainingPlan {
        TrainingPlan(
            id: UUID(),
            ownerID: UUID(),
            title: "Program analysis",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: weeks,
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            startDate: Date()
        )
    }

    func testWeekCountsAndChangesAreDerivedFromSharedWeekAdvisor() {
        let first = week(1, [
            session(kind: .running, minutes: 40, distance: 5),
            session(kind: .strength, minutes: 60)
        ])
        let second = week(2, [
            session(kind: .running, minutes: 50, distance: 6),
            session(kind: .running, minutes: 30, distance: 4),
            session(kind: .strength, minutes: 50),
            session(kind: .mobility, minutes: 20)
        ])
        let third = week(3, [
            session(kind: .strength, minutes: 30)
        ], phase: .deload)

        let report = ATHLTHPlanProgramTrendAdvisor.inspect(
            plan([third, first, second])
        )
        XCTAssertEqual(report.weeks.map(\.number), [1, 2, 3])
        XCTAssertEqual(report.weeks.map(\.sessionCount), [2, 4, 1])
        XCTAssertEqual(report.totalSessions, 7)
        XCTAssertEqual(report.totalRuns, 3)
        XCTAssertEqual(report.totalStrength, 3)
        XCTAssertEqual(report.totalOther, 1)
        XCTAssertEqual(report.knownTotalMinutes, 280)
        XCTAssertEqual(report.totalRunKilometers, 15)
        XCTAssertEqual(report.weeks[0].comparison, .noBaseline)
        XCTAssertEqual(report.weeks[1].comparison, .higher(2))
        XCTAssertEqual(report.weeks[2].comparison, .lower(3))
        XCTAssertTrue(report.weeks[2].deload)
        XCTAssertEqual(report.largestIncrease, 2)
    }

    func testUnknownDurationNeverProducesAnInventedWeekTime() {
        let report = ATHLTHPlanProgramTrendAdvisor.inspect(plan([
            week(1, [
                session(kind: .strength, minutes: 60),
                session(kind: .running, minutes: nil, distance: 6)
            ]),
            week(2, [session(kind: .strength, minutes: 45)])
        ]))
        XCTAssertNil(report.weeks[0].plannedMinutes)
        XCTAssertEqual(report.weeks[1].plannedMinutes, 45)
        XCTAssertEqual(report.weeksWithUnknownTime, 1)
        XCTAssertEqual(report.knownTotalMinutes, 45)
    }

    func testMissingRunningDistanceNeverBecomesZeroOrGuessed() {
        let report = ATHLTHPlanProgramTrendAdvisor.inspect(plan([
            week(1, [session(kind: .running, distance: 10)]),
            week(2, [session(kind: .running, distance: nil)])
        ]))
        XCTAssertEqual(report.weeks[0].plannedRunKilometers, 10)
        XCTAssertNil(report.weeks[1].plannedRunKilometers)
        XCTAssertNil(report.totalRunKilometers)
    }

    func testMissingWeekDoesNotClaimDirectWeekToWeekChange() {
        let report = ATHLTHPlanProgramTrendAdvisor.inspect(plan([
            week(1, [session(kind: .strength)]),
            week(3, [session(kind: .running)])
        ]))
        XCTAssertEqual(report.weeks[1].comparison, .noBaseline)
        XCTAssertNil(report.largestIncrease)
    }

    func testEmptyAndSingleWeekRemainSafe() {
        let empty = ATHLTHPlanProgramTrendAdvisor.inspect(plan([]))
        XCTAssertTrue(empty.weeks.isEmpty)
        XCTAssertEqual(empty.totalSessions, 0)
        XCTAssertTrue(empty.isSingleWeek)
        XCTAssertEqual(empty.maximumWeekSessions, 1)

        let single = ATHLTHPlanProgramTrendAdvisor.inspect(
            plan([week(1, [])])
        )
        XCTAssertEqual(single.weeks.count, 1)
        XCTAssertEqual(single.weeks[0].sessionCount, 0)
        XCTAssertEqual(single.weeks[0].plannedMinutes, 0)
        XCTAssertEqual(single.weeks[0].comparison, .noBaseline)
    }

    func testOtherWorkoutsNeverGetClassifiedAsRunningOrStrength() {
        let report = ATHLTHPlanProgramTrendAdvisor.inspect(
            plan([week(1, [
                session(kind: .walking),
                session(kind: .custom),
                session(kind: .recovery)
            ])])
        )
        XCTAssertEqual(report.totalOther, 3)
        XCTAssertEqual(report.totalRuns, 0)
        XCTAssertEqual(report.totalStrength, 0)
    }
}
