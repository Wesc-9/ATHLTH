import Foundation
import XCTest
@testable import ATHLTH

/// All bundled workout recipes feed the same plan/quick/live engine.
/// These are invariants, not snapshots of visual presentation.
@MainActor
final class ATHLTHWorkoutCatalogAuditTests: XCTestCase {
    func testAllBundledCatalogSourcesAndTheirIDsStayPresent() {
        let curated = ATHLTHCuratedStrengthWorkouts.entries
        let premium = ATHLTHPremiumStrengthSessions.entries
        let zoned = ATHLTHZonedPlanLibrary.workoutCatalogEntries
        let gymCoach = ATHLTHGymCoachStrengthLibrary.workoutCatalogEntries
        let combined = WorkoutTemplateCatalogEntry.bundledCatalog

        XCTAssertEqual(RunningWorkoutLibraryStore.builtInTemplates.count, 54)
        XCTAssertEqual(curated.count, 23)
        XCTAssertEqual(premium.count, 36)
        XCTAssertEqual(zoned.count, 240, "Swimming is intentionally excluded")
        XCTAssertEqual(gymCoach.count, 40)
        XCTAssertEqual(combined.count, 342,
                       "3 HYROX + 23 curated + 36 premium + 240 Zoned + 40 GymCoach")
        XCTAssertEqual(Set(combined.map(\.id)).count, combined.count)
        XCTAssertEqual(Set(combined.map(\.slug)).count, combined.count)
        XCTAssertEqual(Set(RunningWorkoutLibraryStore.builtInTemplates.map(\.id)).count, 54)
        XCTAssertEqual(ATHLTHZonedPlanLibrary.workouts.count, 250)
    }

    func testEveryActiveCatalogRecipeHasValidTargetsAndExecutionTimeline() {
        for recipe in WorkoutTemplateCatalogEntry.bundledCatalog {
            XCTAssertFalse(recipe.blocks.isEmpty, recipe.slug)
            let timeline = recipe.blocks.expandedForExecution()
            XCTAssertFalse(timeline.isEmpty, recipe.slug)
            XCTAssertLessThanOrEqual(timeline.count, 1_000, recipe.slug)
            for (index, block) in timeline.enumerated() {
                if let seconds = block.durationSeconds {
                    XCTAssertTrue(seconds.isFinite && seconds > 0,
                                  "\(recipe.slug), item \(index): invalid time \(seconds)")
                }
                if let meters = block.distanceMeters {
                    XCTAssertTrue(meters.isFinite && meters > 0,
                                  "\(recipe.slug), item \(index): invalid distance \(meters)")
                }
                if let zone = block.targetHeartRateZone {
                    XCTAssertTrue((1...5).contains(zone),
                                  "\(recipe.slug), item \(index): invalid ATHLTH zone \(zone)")
                }
            }
        }
    }

    func testAll240ZonedWorkoutPrescriptionsKeepSourceMetadataInPersonalCopies() {
        // A complete audit, not a test of only the sample one-minute workout.
        let published = ATHLTHZonedPlanLibrary.workoutCatalogEntries
        XCTAssertEqual(published.count, 240)
        for recipe in published {
            let original = recipe.plannedSession().resolvedWorkoutBlocks
            let copied = ATHLTHWorkoutLibraryPersonalization.blankTargets(original)
            XCTAssertEqual(copied.count, original.count, recipe.slug)
            for (index, source) in original.enumerated() {
                let target = copied[index]
                XCTAssertEqual(target.kind, source.kind, "\(recipe.slug) #\(index)")
                XCTAssertEqual(target.title, source.title, "\(recipe.slug) #\(index)")
                XCTAssertEqual(target.resolvedPhase, source.resolvedPhase)
                XCTAssertEqual(target.durationSeconds, source.durationSeconds)
                XCTAssertEqual(target.distanceMeters, source.distanceMeters)
                XCTAssertEqual(target.repetitions, source.repetitions)
                XCTAssertEqual(target.setCount, source.setCount)
                XCTAssertEqual(target.restBetweenSetsSeconds, source.restBetweenSetsSeconds)
                XCTAssertEqual(target.groupRounds, source.groupRounds)
                XCTAssertEqual(target.targetHeartRateZone, source.targetHeartRateZone)
                XCTAssertEqual(target.sourceIntensityZoneLabel,
                               source.sourceIntensityZoneLabel)
                XCTAssertEqual(target.targetHeartRatePercentMin,
                               source.targetHeartRatePercentMin)
                XCTAssertEqual(target.targetHeartRatePercentMax,
                               source.targetHeartRatePercentMax)
                XCTAssertEqual(target.notes, source.notes)
                if source.sourceIntensityZoneLabel != nil {
                    XCTAssertNotNil(target.targetHeartRatePercentMin,
                                    "\(recipe.slug): source zone without numeric lower bound")
                    XCTAssertNotNil(target.targetHeartRatePercentMax,
                                    "\(recipe.slug): source zone without numeric upper bound")
                }
            }
        }
    }

    func testAllActiveZonedWorkoutsImportWithoutLosingWorkoutParts() {
        let workouts = ATHLTHZonedPlanLibrary.workouts
            .filter { $0.discipline != "swimming" }
        XCTAssertEqual(workouts.count, 240)
        for source in workouts {
            let blocks = ATHLTHZonedPlanLibrary.blocks(for: source)
            XCTAssertFalse(blocks.isEmpty, source.id)
            XCTAssertFalse(blocks.contains { $0.title.isEmpty }, source.id)
            XCTAssertTrue(blocks.count <= 900, source.id)
            XCTAssertEqual(blocks.map(\.sequence), Array(1...blocks.count), source.id)
            XCTAssertTrue(blocks.allSatisfy {
                ($0.durationSeconds == nil || $0.durationSeconds! > 0) &&
                ($0.distanceMeters == nil || $0.distanceMeters! > 0)
            }, source.id)
        }
    }

    func testTimedWarmupIsIncludedInCuratedAndPremiumStrengthDuration() throws {
        let examples = [
            try XCTUnwrap(ATHLTHCuratedStrengthWorkouts.entries.first),
            try XCTUnwrap(ATHLTHPremiumStrengthSessions.entries.first),
            try XCTUnwrap(ATHLTHGymCoachStrengthLibrary.workoutCatalogEntries.first)
        ]
        for recipe in examples {
            let warmup = try XCTUnwrap(recipe.blocks.first {
                $0.kind == .note && $0.resolvedPhase == .warmup
            })
            let seconds = try XCTUnwrap(warmup.durationSeconds)
            let withWarmup = try XCTUnwrap(
                ATHLTHWorkoutDurationEstimator.previewSeconds(for: recipe.blocks)
            )
            let withoutWarmup = try XCTUnwrap(
                ATHLTHWorkoutDurationEstimator.previewSeconds(
                    for: recipe.blocks.filter { $0.sequence != warmup.sequence }
                )
            )
            XCTAssertEqual(
                withWarmup - withoutWarmup, seconds,
                accuracy: 0.01, recipe.slug
            )
        }
    }

    func testInstructionOnlyTimedNoteDoesNotCountAsExercise() {
        let note = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: "Instructions only",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 360, targetWeightKilograms: nil,
            loadNote: nil, notes: nil
        )
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.previewSeconds(for: [note]))
    }

    func testNoFakeRunningIntervalForInstructionsAndPlyometricCircuit() throws {
        let doubleThreshold = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "THR-016" }
        )
        let threshold = ATHLTHZonedPlanLibrary.blocks(for: doubleThreshold)
        let between = try XCTUnwrap(threshold.first {
            $0.kind == .note && $0.title.lowercased().contains("6")
        })
        XCTAssertNil(between.durationSeconds)
        XCTAssertNil(between.distanceMeters)
        XCTAssertTrue(between.notes?.contains("Apple") == true)

        let cutdown = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "RP-011" }
        )
        let cutdownBlocks = ATHLTHZonedPlanLibrary.blocks(for: cutdown)
        XCTAssertEqual(cutdownBlocks.count, 5)
        XCTAssertEqual(
            cutdownBlocks.filter { $0.resolvedPhase == .main }.count, 3
        )
        XCTAssertEqual(
            cutdownBlocks.filter { $0.resolvedPhase == .main }
                .compactMap(\.distanceMeters),
            [5_000, 3_000, 1_500]
        )

        let lactate = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "THR-018" }
        )
        XCTAssertTrue(ATHLTHZonedPlanLibrary.blocks(for: lactate).contains {
            $0.kind == .note && $0.durationSeconds == nil
        })
        let plyometric = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "MIX-014" }
        )
        XCTAssertEqual(ATHLTHZonedPlanLibrary.blocks(for: plyometric).filter {
            $0.kind == .note && $0.resolvedPhase == .main
        }.count, 3)
    }

    func testThirtyThirtyTempoComboRestoresWorkTimeFromExplicitSourceText() throws {
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first {
            $0.id == "MIX-001"
        })
        // The third source step says 30/30 but omitted durationSec.
        // Keep its 30-second effort and nine 30-second inter-effort rests.
        let sourceRepeat = try XCTUnwrap(source.mainSetStructure?.last)
        XCTAssertEqual(sourceRepeat.count, 10)
        XCTAssertNil(sourceRepeat.steps?.first?.durationSec)

        let timeline = ATHLTHZonedPlanLibrary.blocks(for: source)
        let efforts = timeline.filter {
            $0.title.lowercased().contains("30/30") && $0.kind == .run
        }
        XCTAssertEqual(efforts.count, 10)
        XCTAssertTrue(efforts.allSatisfy { $0.durationSeconds == 30 })
        let between = timeline.filter {
            $0.isActiveRecovery && $0.durationSeconds == 30
        }
        XCTAssertEqual(between.count, 9)
        let estimatedSeconds = try XCTUnwrap(
            ATHLTHWorkoutDurationEstimator.previewSeconds(for: timeline)
        )
        XCTAssertEqual(estimatedSeconds, 3_570, accuracy: 0.01)
        XCTAssertEqual(timeline.first?.resolvedPhase, .warmup)
        XCTAssertEqual(timeline.last?.resolvedPhase, .cooldown)
    }

    func testPreRaceFiveMinuteRestIsNotCountedAsRunning() throws {
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first {
            $0.id == "RP-016"
        })
        let timeline = ATHLTHZonedPlanLibrary.blocks(for: source)
        let rest = try XCTUnwrap(timeline.first {
            $0.kind == .rest &&
            $0.resolvedPhase == .recovery &&
            $0.durationSeconds == 300
        })
        XCTAssertEqual(rest.kind, .rest)
        XCTAssertEqual(rest.resolvedPhase, .recovery)
        XCTAssertEqual(rest.durationSeconds, 300)
        XCTAssertNil(rest.distanceMeters)
        // The walk-back has no source distance or duration, so the total
        // session estimate cannot be asserted as a fixed number.
        XCTAssertTrue(timeline.contains {
            $0.kind == .run && $0.resolvedPhase == .recovery &&
            $0.durationSeconds == nil && $0.distanceMeters == nil
        })
        XCTAssertNil(ATHLTHWorkoutDurationEstimator.previewSeconds(for: timeline))
    }

    func testOpenEndedAssessmentAndHillRecoveryStayManual() throws {
        for id in ["ASS-004", "ASS-010", "MIX-002", "VMA-026"] {
            let source = try XCTUnwrap(
                ATHLTHZonedPlanLibrary.workouts.first { $0.id == id }
            )
            let timeline = ATHLTHZonedPlanLibrary.blocks(for: source)
            XCTAssertTrue(timeline.contains {
                $0.kind == .run &&
                $0.durationSeconds == nil &&
                $0.distanceMeters == nil
            }, id)
            XCTAssertNil(
                ATHLTHWorkoutDurationEstimator.previewSeconds(for: timeline),
                id
            )
        }

        for id in ["HIL-005", "HIL-006", "VMA-019"] {
            let source = try XCTUnwrap(
                ATHLTHZonedPlanLibrary.workouts.first { $0.id == id }
            )
            let timeline = ATHLTHZonedPlanLibrary.blocks(for: source)
            XCTAssertTrue(timeline.contains {
                $0.resolvedPhase == .recovery &&
                $0.durationSeconds == nil &&
                $0.distanceMeters == nil
            }, id)
            XCTAssertNil(
                ATHLTHWorkoutDurationEstimator.previewSeconds(for: timeline),
                id
            )
        }
    }

    func testUntimedRecoveryIsKeptManualNeverInventsSeconds() throws {
        let partner = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "VMA-019" }
        )
        let rests = ATHLTHZonedPlanLibrary.blocks(for: partner).filter {
            $0.resolvedPhase == .recovery && $0.kind == .rest
        }
        XCTAssertEqual(rests.count, 9)
        XCTAssertTrue(rests.allSatisfy {
            $0.durationSeconds == nil &&
            $0.distanceMeters == nil &&
            !$0.title.isEmpty
        })
    }
}
