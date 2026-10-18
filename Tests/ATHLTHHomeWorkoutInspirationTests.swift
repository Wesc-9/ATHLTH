import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHHomeWorkoutInspirationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func workout(
        _ title: String, kind: WorkoutKind, minutes: Int
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(), title: title, kind: kind, scheduledStart: nil,
            durationMinutes: minutes, targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: nil,
            exercises: [], notes: nil
        )
    }

    func testNoHistoryPrefersManageableDurationAndAvoidsHardIntervals() {
        let fullBody = workout("Full Body Foundation", kind: .strength, minutes: 45)
        let hard = workout("4 x 4 intervaller", kind: .running, minutes: 43)
        let longRun = workout("Long Run 16K", kind: .running, minutes: 110)
        let result = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [hard, longRun, fullBody],
            recent: [], minutes: 45, now: now
        )
        XCTAssertEqual(result.first?.title, fullBody.title)
        XCTAssertEqual(result.count, 3)
    }

    func testRecentStrengthTrainingDeprioritizesAnotherStrengthWorkout() {
        let strength = workout("Full Body", kind: .strength, minutes: 45)
        let easyRun = workout("Easy aerobic run", kind: .running, minutes: 40)
        let recent = ATHLTHInspirationRecentActivity(
            kind: .strength, startedAt: now.addingTimeInterval(-8 * 3_600)
        )
        let result = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [strength, easyRun],
            recent: [recent], minutes: 45, now: now
        )
        XCTAssertEqual(result.first?.title, easyRun.title)
    }

    func testRecentRunDeprioritizesAnotherRun() {
        let run = workout("Easy aerobic run", kind: .running, minutes: 40)
        let strength = workout("Full Body", kind: .strength, minutes: 45)
        let recent = ATHLTHInspirationRecentActivity(
            kind: .running, startedAt: now.addingTimeInterval(-12 * 3_600)
        )
        let result = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [run, strength],
            recent: [recent], minutes: 45, now: now
        )
        XCTAssertEqual(result.first?.title, strength.title)
    }

    func testStaleActivityDoesNotPretendToIndicateCurrentReadiness() {
        let strength = workout("Full Body", kind: .strength, minutes: 45)
        let recent = ATHLTHInspirationRecentActivity(
            kind: .strength, startedAt: now.addingTimeInterval(-8 * 86_400)
        )
        let result = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [strength], recent: [recent], minutes: 45, now: now
        )
        XCTAssertEqual(result.first?.title, strength.title)
        let explanation = ATHLTHHomeWorkoutInspirationPolicy.explanation(
            for: strength, recent: [recent], now: now
        )
        XCTAssertFalse(explanation.isEmpty)
    }

    func testDuplicatesAreRemovedAndOrderStable() {
        let first = workout("Full Body", kind: .strength, minutes: 45)
        let second = workout("full body", kind: .strength, minutes: 46)
        let run = workout("Easy Run", kind: .running, minutes: 45)
        let result1 = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [first, second, run],
            recent: [], minutes: 45, now: now
        )
        let result2 = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [first, second, run],
            recent: [], minutes: 45, now: now
        )
        XCTAssertEqual(result1.count, 2)
        XCTAssertEqual(result1.map(\.id), result2.map(\.id))
        XCTAssertEqual(result1.first?.id, first.id)
    }

    func testExplicitRunningGoalFavorsAppropriateRunningWorkouts() {
        let run = workout("Easy aerobic run", kind: .running, minutes: 45)
        let strength = workout("Full Body", kind: .strength, minutes: 45)
        let ranked = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [strength, run], recent: [], minutes: 45,
            goal: .runBetter, now: now
        )
        XCTAssertEqual(ranked.first?.id, run.id)
        XCTAssertEqual(ranked.count, 2)
    }

    func testGoalDoesNotOverrideRecentStrengthLoadCaution() {
        let strength = workout("Full Body", kind: .strength, minutes: 45)
        let run = workout("Easy aerobic run", kind: .running, minutes: 45)
        let recent = ATHLTHInspirationRecentActivity(
            kind: .strength, startedAt: now.addingTimeInterval(-9 * 3_600)
        )
        let ranked = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [strength, run], recent: [recent], minutes: 45,
            goal: .buildMuscle, now: now
        )
        XCTAssertEqual(ranked.first?.id, run.id)
    }

    func testAvailableTimeChangesRankWithoutInventingNewWorkouts() {
        let short = workout("Quick strength", kind: .strength, minutes: 25)
        let long = workout("Full Body", kind: .strength, minutes: 60)
        let quick = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [long, short], recent: [], minutes: 25, now: now
        )
        let extended = ATHLTHHomeWorkoutInspirationPolicy.ranked(
            from: [long, short], recent: [], minutes: 60, now: now
        )
        XCTAssertEqual(quick.first?.id, short.id)
        XCTAssertEqual(extended.first?.id, long.id)
    }
}
