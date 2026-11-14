import UIKit
import XCTest
@testable import ATHLTH

final class ATHLTHPlanWorkoutArtworkTests: XCTestCase {
    private func entry(
        slug: String, category: String,
        title: String, pattern: [String] = ["easy_run"]
    ) -> TrainingPlanCatalogEntry {
        TrainingPlanCatalogEntry(
            id: UUID(), slug: slug, title: title, summary: "",
            category: category, goal: title, level: "intermediate",
            durationWeeks: 8, sessionsPerWeek: pattern.count,
            workoutPattern: pattern, tags: [], sortOrder: 1,
            catalogVersion: 1
        )
    }

    func testPlanArtworkFollowsTrainingNotJustBroadCategory() {
        let intervals = entry(
            slug: "athlth-track-interval-4x4", category: "running",
            title: "4x4 intervals"
        )
        let hills = entry(
            slug: "mountain-hill-running", category: "running",
            title: "Hill running"
        )
        let endurance = entry(
            slug: "long-distance-endurance", category: "running",
            title: "Long run", pattern: ["long_run"]
        )
        let strength = entry(
            slug: "strength-full-body", category: "strength",
            title: "Full body"
        )
        let hybrid = entry(
            slug: "hybrid-interval-gym", category: "hybrid",
            title: "HYROX intervals"
        )

        XCTAssertEqual(ATHLTHPlanWorkoutArtwork.scene(for: intervals),
                       .stadiumIntervals)
        XCTAssertEqual(ATHLTHPlanWorkoutArtwork.scene(for: hills),
                       .uphillRunning)
        XCTAssertEqual(ATHLTHPlanWorkoutArtwork.scene(for: endurance),
                       .trailEndurance)
        XCTAssertEqual(ATHLTHPlanWorkoutArtwork.scene(for: strength),
                       .strength)
        XCTAssertEqual(ATHLTHPlanWorkoutArtwork.scene(for: hybrid),
                       .hybrid)
    }

    func testAllCuratedPlanCoversAreBundledAndWorkOffline() {
        let entries = ATHLTHCuratedTrainingPlans.entries +
                      TrainingPlanCatalogEntry.fallbackCatalog
        XCTAssertGreaterThan(entries.count, 20)
        for entry in entries {
            let asset = ATHLTHPlanWorkoutArtwork.asset(for: entry)
            XCTAssertNotNil(UIImage(named: asset),
                            "No local plan cover for \(entry.slug): \(asset)")
        }
    }

    func testWeekSessionsUseRealWorkoutSignals() {
        let entry = entry(
            slug: "strength-full-body", category: "strength",
            title: "Strength", pattern: ["full_body_a"]
        )
        let workout = ATHLTHCatalogPlanSessionFactory.session(
            entry: entry, blueprint: .fullBodyA, week: 1
        )
        XCTAssertEqual(ATHLTHPlanWorkoutArtwork.scene(for: workout),
                       .strength)
        XCTAssertNotNil(
            UIImage(named: ATHLTHPlanWorkoutArtwork.asset(for: workout))
        )
    }
}
