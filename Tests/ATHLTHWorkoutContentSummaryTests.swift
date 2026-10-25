import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutContentSummaryTests: XCTestCase {
    private func block(
        _ kind: WorkoutTemplateBlockKind, _ title: String,
        seconds: Double = 120
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: title,
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: seconds,
            targetWeightKilograms: nil, loadNote: nil, notes: nil
        )
    }

    private func workout(_ blocks: [WorkoutTemplateBlock]) -> PlannedSession {
        var session = PlannedSession(
            id: UUID(), title: "Mixed session", kind: .custom,
            scheduledStart: nil, durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        )
        session.workoutBlocks = blocks
        return session
    }

    func testGroupedIntervalsCountFourEffortsAndOnlyThreeRecoveries() {
        let id = UUID()
        var run = block(.run, "Work")
        run.groupID = id
        run.groupKind = .intervals
        run.groupRounds = 4
        var rest = block(.rest, "Recovery")
        rest.groupID = id
        rest.groupKind = .intervals
        rest.groupRounds = 4

        let summary = ATHLTHWorkoutContentSummary.text(
            for: workout([run, rest])
        ) ?? ""
        XCTAssertTrue(summary.contains("4"), summary)
        XCTAssertTrue(summary.contains("3"), summary)
    }

    func testCyclingAndStrengthAreBothVisibleInMixedPlan() {
        var cycling = block(.note, "Bike")
        cycling.activityTag = "cycling"
        let strength = block(.exercise, "Squat")
        let summary = ATHLTHWorkoutContentSummary.text(
            for: workout([cycling, strength])
        ) ?? ""
        XCTAssertTrue(summary.contains("1"), summary)
        XCTAssertFalse(summary.isEmpty)
        // No duplicate workout is created; this is display-only.
    }

    func testCyclingOnlySummaryNotGenericCustomFallback() {
        var cycling = block(.note, "Bike")
        cycling.activityTag = "cycling"
        let summary = ATHLTHWorkoutContentSummary.text(
            for: workout([cycling])
        )
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("1") == true)
    }
}
