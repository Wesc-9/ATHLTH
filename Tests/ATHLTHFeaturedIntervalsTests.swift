import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHFeaturedIntervalsTests: XCTestCase {
    func testFeaturedListUsesUniqueBuiltInWorkouts() {
        let templates = RunningWorkoutLibraryStore.builtInTemplates
        let ids = RunningWorkoutLibraryStore.featuredIntervalNumbers.compactMap {
            UUID(uuidString: String(format: "A1000000-0000-0000-0000-%012d", $0))
        }
        XCTAssertEqual(ids.count, 6)
        XCTAssertEqual(Set(ids).count, 6)

        let found = ids.compactMap { id in templates.first { $0.id == id } }
        XCTAssertEqual(found.count, 6)
        XCTAssertTrue(found.allSatisfy(\.isBuiltIn))
        XCTAssertEqual(found.map(\.title), [
            "4 × 4 intervaller",
            "30/30 – 20 drag",
            "45/15 – 15 drag",
            "5 × 1 km terskel",
            "6 × 400 m",
            "5 × 3 minutter"
        ])
    }

    func testNewIntervalPresetsHaveCorrectWorkRecoveryAndCooldown() throws {
        let cases: [(String, Int, Int, TimeInterval)] = [
            ("30/30 – 20 drag", 20, 19, 2_490),
            ("45/15 – 15 drag", 15, 14, 2_205),
            ("5 × 3 minutter", 5, 4, 2_580)
        ]
        for (name, reps, recoveries, seconds) in cases {
            let workout = try XCTUnwrap(
                RunningWorkoutLibraryStore.builtInTemplates.first {
                    $0.title == name
                }, "Missing preset: \(name)"
            )
            XCTAssertEqual(workout.blocks.first?.kind, .warmup)
            XCTAssertEqual(workout.blocks.last?.kind, .cooldown)
            XCTAssertEqual(workout.estimatedDurationSeconds ?? -1,
                           seconds, accuracy: 0.01)

            let transfer = PlannedWorkoutWatchBuilder.runningTransfer(
                from: workout, routeAlerts: .standard
            )
            XCTAssertEqual(transfer.steps.count, reps + recoveries + 2)
            XCTAssertEqual(transfer.steps.filter { $0.phase == "work" }.count,
                           reps)
            XCTAssertEqual(
                transfer.steps.filter { $0.phase == "recovery" }.count,
                recoveries
            )
            XCTAssertEqual(transfer.steps.last?.phase, "cooldown")
        }
    }
}
