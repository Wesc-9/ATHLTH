import XCTest
@testable import ATHLTH

final class HomeCoachWorkoutSelectionTests: XCTestCase {
    private func workout(_ kind: WorkoutKind, title: String, minutes: Int = 35) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: title,
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

    func testHealthRecoveryOffersOnlyGentleChoicesForToday() {
        let run = workout(.running, title: "Intervals")
        let walk = workout(.walking, title: "Easy walk")
        let original = [run, walk]

        let selected = HomeCoachWorkoutSelection.ordered(
            original, planned: [],
            recentKinds: [.running],
            readiness: .recover, isToday: true
        )

        XCTAssertEqual(selected.map(\.id), [walk.id])
        XCTAssertEqual(original.map(\.id), [run.id, walk.id])
    }

    func testUnknownHealthReadinessDoesNotPretendToBeARecoveryWarning() {
        let run = workout(.running, title: "Easy running")
        let selected = HomeCoachWorkoutSelection.ordered(
            [run], planned: [],
            recentKinds: [],
            readiness: .unavailable, isToday: true
        )
        XCTAssertEqual(selected.first?.id, run.id)
    }

    func testCoachPreferredWorkoutAndPlanAffectRanking() {
        let run = workout(.running, title: "Running")
        let walk = workout(.walking, title: "Walking")
        let strength = workout(.strength, title: "Strength")
        let selected = HomeCoachWorkoutSelection.ordered(
            [strength, walk, run],
            planned: [run],
            recentKinds: [.strength],
            readiness: .balanced, isToday: true,
            recommendedKind: .running
        )
        XCTAssertEqual(selected.first?.id, run.id)
    }

    func testCurrentRecoveryDoesNotForecastAnotherDay() {
        let run = workout(.running, title: "Running")
        let selected = HomeCoachWorkoutSelection.ordered(
            [run], planned: [],
            recentKinds: [],
            readiness: .recover, isToday: false
        )
        XCTAssertEqual(selected.first?.id, run.id)
    }

    func testLimitAndStableTieBreak() {
        let a = workout(.walking, title: "Walk A")
        let b = workout(.walking, title: "Walk B")
        let selected = HomeCoachWorkoutSelection.ordered(
            [a, b], planned: [], recentKinds: [],
            readiness: .ready, isToday: true, limit: 1
        )
        XCTAssertEqual(selected.map(\.id), [a.id])
    }
}
