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
    func testZonedSixSourceZonesNormalizeToFiveATHLTHZones() {
        let easy = ATHLTHZonedPlanLibrary.zonePrescription("Z1-Z2")
        XCTAssertEqual(easy?.minimum, 50)
        XCTAssertEqual(easy?.maximum, 70)
        XCTAssertNil(easy?.athlthZone)

        let sprint = ATHLTHZonedPlanLibrary.zonePrescription("Z6")
        XCTAssertEqual(sprint?.minimum, 90)
        XCTAssertEqual(sprint?.maximum, 100)
        XCTAssertEqual(sprint?.athlthZone, 5)
        XCTAssertEqual(sprint?.label, "Z5")

        let plus = ATHLTHZonedPlanLibrary.zonePrescription("Z5+")
        XCTAssertEqual(plus?.minimum, 90)
        XCTAssertEqual(plus?.maximum, 100)
        XCTAssertEqual(plus?.athlthZone, 5)
        XCTAssertEqual(plus?.label, "Z5")

        let wide = ATHLTHZonedPlanLibrary.zonePrescription("Z1-Z6")
        XCTAssertEqual(wide?.maximum, 100)
        XCTAssertEqual(wide?.label, "Z1-Z5")
        XCTAssertNil(wide?.athlthZone)
        XCTAssertNil(ATHLTHZonedPlanLibrary.zonePrescription("easy"))
        XCTAssertNil(ATHLTHZonedPlanLibrary.zonePrescription("Z7"))
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

    @MainActor
    func testRestCanBecomeActiveJogAndBackWithoutLosingIntervalGroupOrTime() {
        let id = UUID()
        var rest = WorkoutTemplateBlock(
            sequence: 3, kind: .rest, title: "Rest",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 120,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        rest.groupID = id
        rest.groupKind = .intervals
        rest.groupRounds = 4

        let active = ATHLTHActiveRecovery.convert(rest, active: true)
        XCTAssertTrue(active.isActiveRecovery)
        XCTAssertEqual(active.kind, .run)
        XCTAssertEqual(active.cardioActivity, .running)
        XCTAssertEqual(active.targetHeartRateZone, 1)
        XCTAssertEqual(active.durationSeconds, 120)
        XCTAssertEqual(active.groupID, id)
        XCTAssertEqual(active.groupRounds, 4)
        XCTAssertEqual(ATHLTHLiveWorkoutEngineRouter.engine(for: active), .endurance)

        let restored = ATHLTHActiveRecovery.convert(active, active: false)
        XCTAssertEqual(restored.kind, .rest)
        XCTAssertEqual(restored.durationSeconds, 120)
        XCTAssertEqual(restored.groupID, id)
        XCTAssertNil(restored.targetHeartRateZone)
    }

    @MainActor
    func testExpandedIntervalDoesNotAppendActiveRecoveryAfterLastRound() {
        let id = UUID()
        var effort = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Interval",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 240,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        effort.groupID = id
        effort.groupKind = .intervals
        effort.groupRounds = 4
        var recovery = ATHLTHActiveRecovery.convert(
            WorkoutTemplateBlock(
                sequence: 2, kind: .rest, title: "Rest",
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: 120,
                targetWeightKilograms: nil, loadNote: nil,
                notes: nil, phase: .main
            ), active: true
        )
        recovery.groupID = id
        recovery.groupKind = .intervals
        recovery.groupRounds = 4
        let timeline = [effort, recovery].expandedForExecution()
        XCTAssertEqual(timeline.count, 7)
        XCTAssertEqual(timeline.filter { $0.isActiveRecovery }.count, 3)
        XCTAssertEqual(timeline.last?.kind, .run)
        XCTAssertFalse(timeline.last?.isActiveRecovery ?? true)
    }

    @MainActor
    func testFiveZoneRangeSurvivesPhaseReordering() throws {
        let src = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first { $0.id == "VMA-001" })
        let zone = try XCTUnwrap(ATHLTHZonedPlanLibrary.blocks(for: src)
            .first { $0.sourceIntensityZoneLabel == "Z1-Z2" })
        let copy = ATHLTHWorkoutPhasePlacement.renumbered(zone, sequence: 17)
        XCTAssertEqual(copy.sourceIntensityZoneLabel, "Z1-Z2")
        XCTAssertEqual(copy.targetHeartRatePercentMin, 50)
        XCTAssertEqual(copy.targetHeartRatePercentMax, 70)
    }

    @MainActor
    func testNorwegianWorkoutLabels() {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "settings.language") }
            else { UserDefaults.standard.removeObject(forKey: "settings.language") }
        }
        UserDefaults.standard.set("nb", forKey: "settings.language")
        XCTAssertEqual(ATHLTHZonedLocalization.planTitle("5k-debutant", english: "5K Beginner"),
                       "Din første 5 km")
        XCTAssertEqual(ATHLTHZonedLocalization.text("Progressive jog"), "Progressiv jogg")
    }

}
