import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHZonedPlanImportTests: XCTestCase {
    @MainActor
    func testAllTenPlansAndOriginalWorkoutSourcesDecodeOffline() {
        XCTAssertEqual(ATHLTHZonedPlanLibrary.plans.count, 10)
        XCTAssertEqual(ATHLTHZonedPlanLibrary.workouts.count, 250)
        XCTAssertEqual(ATHLTHZonedPlanLibrary.catalogEntries.count, 10)
        XCTAssertEqual(ATHLTHZonedPlanLibrary.workoutCatalogEntries.count, 240)
        XCTAssertEqual(Set(ATHLTHZonedPlanLibrary.catalogEntries.map(\.slug)).count, 10)
    }

    @MainActor
    func testEveryRequiredSessionResolvesToRealWorkoutIncludingRaceDay() {
        for plan in ATHLTHZonedPlanLibrary.plans {
            XCTAssertEqual(plan.weeks.count, plan.totalWeeks, plan.id)
            for week in plan.weeks {
                let required = ATHLTHZonedPlanLibrary.orderedRequiredSessions(in: week)
                XCTAssertGreaterThanOrEqual(required.count, 1, "\(plan.id), week \(week.weekNumber)")
                for source in required {
                    let created = ATHLTHZonedPlanLibrary.plannedSession(
                        source, week: week, sourcePlan: plan
                    )
                    XCTAssertNotNil(created, "\(plan.id)/\(week.weekNumber)/\(source.workoutId)")
                    XCTAssertFalse(created?.workoutBlocks?.isEmpty ?? true)
                    XCTAssertNil(created?.targetPaceSecondsPerKilometer,
                                 "Generic Zoned sample pace must not be treated as personal target")
                }
            }
        }
    }

    @MainActor
    func testZonedSixZoneRangesStayExactAndDoNotMasqueradeAsSingleFiveZoneTarget() {
        let easy = ATHLTHZonedPlanLibrary.zonePrescription("Z1-Z2")
        XCTAssertEqual(easy?.minimum, 50)
        XCTAssertEqual(easy?.maximum, 70)
        XCTAssertNil(easy?.athlthZone)

        let sprint = ATHLTHZonedPlanLibrary.zonePrescription("Z6")
        XCTAssertEqual(sprint?.minimum, 95)
        XCTAssertEqual(sprint?.maximum, 100)
        XCTAssertEqual(sprint?.athlthZone, 5)

        let plus = ATHLTHZonedPlanLibrary.zonePrescription("Z5+")
        XCTAssertEqual(plus?.minimum, 90)
        XCTAssertEqual(plus?.maximum, 100)
        XCTAssertEqual(plus?.athlthZone, 5)

        let wide = ATHLTHZonedPlanLibrary.zonePrescription("Z1-Z6")
        XCTAssertEqual(wide?.maximum, 100)
        XCTAssertNil(wide?.athlthZone)
        XCTAssertNil(ATHLTHZonedPlanLibrary.zonePrescription("easy"))
    }

    @MainActor
    func testIntervalStepsAndRecoveryRetainZoneMetadataThroughExecutionExpansion() throws {
        let example = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first { $0.id == "VMA-001" })
        let blocks = ATHLTHZonedPlanLibrary.blocks(for: example)
        XCTAssertGreaterThan(blocks.count, 25)
        XCTAssertTrue(blocks.contains { $0.resolvedPhase == .warmup })
        XCTAssertTrue(blocks.contains { $0.resolvedPhase == .cooldown })
        XCTAssertTrue(blocks.contains { $0.resolvedPhase == .recovery })
        let easy = try XCTUnwrap(blocks.first { $0.sourceIntensityZoneLabel == "Z1-Z2" })
        XCTAssertEqual(easy.targetHeartRatePercentMin, 50)
        XCTAssertEqual(easy.targetHeartRatePercentMax, 70)
        XCTAssertTrue(easy.targetText?.contains("Z1-Z2") == true)
        let preserved = blocks.expandedForExecution()
        XCTAssertEqual(preserved.first?.sourceIntensityZoneLabel, blocks.first?.sourceIntensityZoneLabel)
        XCTAssertTrue(preserved.contains {
            $0.sourceIntensityZoneLabel == "Z5" && $0.targetHeartRateZone == 5
        })
    }

    @MainActor
    func testRaceDaysAndCyclingRecipesAreNotDiscarded() throws {
        let plan = try XCTUnwrap(ATHLTHZonedPlanLibrary.plans.first { $0.id == "5k-debutant" })
        let week = try XCTUnwrap(plan.weeks.last)
        let source = try XCTUnwrap(week.sessions.first { $0.workoutId == "__race_day__" })
        let race = try XCTUnwrap(ATHLTHZonedPlanLibrary.plannedSession(
            source, week: week, sourcePlan: plan
        ))
        XCTAssertEqual(race.targetDistanceKilometers, 5)
        XCTAssertEqual(race.workoutBlocks?.first?.kind, .run)
        XCTAssertNil(race.workoutBlocks?.first?.targetHeartRateZone)

        let cycling = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first { $0.id == "CYC-001" })
        let cyclingBlocks = ATHLTHZonedPlanLibrary.blocks(for: cycling)
        XCTAssertFalse(cyclingBlocks.isEmpty)
        XCTAssertTrue(cyclingBlocks.contains { $0.activityTag == "cycling" })
        XCTAssertTrue(cyclingBlocks.contains { $0.sourceIntensityZoneLabel != nil })
    }
}
