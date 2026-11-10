import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHStudioFavoriteWorkoutReplacementTests: XCTestCase {
    private func session(
        id: UUID = UUID(),
        title: String,
        kind: WorkoutKind
    ) -> PlannedSession {
        PlannedSession(
            id: id, title: title, kind: kind,
            scheduledStart: nil, durationMinutes: 40,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
    }

    func testReplacingAWorkoutKeepsOriginalCalendarIdentity() {
        let original = session(title: "Old workout", kind: .running)
        var favorite = session(title: "Strength favorite", kind: .strength)
        favorite.workoutCategory = "strength"
        favorite.durationMinutes = 55
        favorite.autoPauseEnabled = false

        let result = favorite.studioReplacement(keepingIDFrom: original)

        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.title, "Strength favorite")
        XCTAssertEqual(result.kind, .strength)
        XCTAssertEqual(result.durationMinutes, 55)
        XCTAssertEqual(result.workoutCategory, "strength")
        XCTAssertEqual(result.autoPauseEnabled, false)
        XCTAssertNotEqual(result.id, favorite.id)
    }

    func testReplacementKeepsScheduledClockTime() {
        var original = session(title: "Scheduled", kind: .running)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        original.scheduledStart = start
        var favorite = session(title: "Interval", kind: .running)
        favorite.scheduledStart = Date(timeIntervalSince1970: 1_700_000_000)

        let result = favorite.studioReplacement(keepingIDFrom: original)
        XCTAssertEqual(result.scheduledStart, start)
    }
}
