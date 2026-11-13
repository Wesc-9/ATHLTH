import Foundation
import XCTest
@testable import ATHLTH

/// This test audits every bundled authored workout, not just the 1min/1min
/// screenshot. No guessed targets are accepted as substitutes for source data.
final class ATHLTHWorkoutStructuredDataAuditTests: XCTestCase {
    private func leafSteps(
        _ source: [ATHLTHZonedPlanLibrary.Step]?
    ) -> [ATHLTHZonedPlanLibrary.Step] {
        (source ?? []).flatMap { step in
            if step.kind == "repeat" {
                return leafSteps(step.steps) + leafSteps(step.between)
            }
            return [step]
        }
    }

    func testEveryPublishedZonedWorkoutPreservesAllExplicitSourceTargets() {
        let workouts = ATHLTHZonedPlanLibrary.workouts.filter {
            $0.discipline != "swimming"
        }
        XCTAssertEqual(workouts.count, 240)

        var auditedBlocks = 0
        var auditedFields = 0
        for workout in workouts {
            let blocks = ATHLTHZonedPlanLibrary.blocks(for: workout)
            XCTAssertFalse(blocks.isEmpty, "Missing workout \(workout.id)")
            auditedBlocks += blocks.count

            let source = leafSteps(workout.warmupStructure) +
                         leafSteps(workout.mainSetStructure) +
                         leafSteps(workout.cooldownStructure)
            for step in source where step.kind == "segment" {
                if let intensity = step.intensityType {
                    XCTAssertTrue(blocks.contains {
                        $0.targetIntensityType == intensity
                    }, "Missing source intensity \(workout.id) / \(intensity)")
                    auditedFields += 1
                }
                if let elevation = step.elevationGainM {
                    XCTAssertTrue(blocks.contains {
                        $0.targetElevationGainMeters == elevation
                    }, "Missing elevation \(workout.id) / \(elevation)")
                    auditedFields += 1
                }
                if let gradient = step.gradientPercent {
                    XCTAssertTrue(blocks.contains {
                        $0.targetGradientPercent == gradient
                    }, "Missing outdoor gradient \(workout.id) / \(gradient)")
                    auditedFields += 1
                }
                if let terrain = step.terrainType {
                    XCTAssertTrue(blocks.contains {
                        $0.targetTerrainType == terrain
                    }, "Missing terrain \(workout.id) / \(terrain)")
                    auditedFields += 1
                }
                if let vma = step.vmaPercent {
                    XCTAssertTrue(blocks.contains {
                        $0.targetVMAPercent == vma
                    }, "Missing VMA target \(workout.id)")
                    auditedFields += 1
                }
                if let zone = step.zone,
                   let prescribed = ATHLTHZonedPlanLibrary.zonePrescription(zone) {
                    XCTAssertTrue(blocks.contains {
                        $0.sourceIntensityZoneLabel == prescribed.label &&
                        $0.targetHeartRatePercentMin == prescribed.minimum &&
                        $0.targetHeartRatePercentMax == prescribed.maximum
                    }, "Missing structured heart-rate zone \(workout.id) / \(zone)")
                    auditedFields += 1
                }
            }
            let badNotes = blocks.compactMap(\.notes).filter { note in
                [
                    "VMA target:", "VMA-mål:",
                    "Pace intensity:", "Fartsintensitet:",
                    "Elevation gain:", "Høydemeter:",
                    "Gradient:", "Stigning:",
                    "Terrain:", "Terreng:"
                ].contains { note.contains(" · " + $0) || note.hasPrefix($0) }
            }
            XCTAssertTrue(badNotes.isEmpty,
                          "Source targets still hidden in notes \(workout.id)")
        }
        XCTAssertGreaterThan(auditedBlocks, 700)
        XCTAssertGreaterThan(auditedFields, 1_000)
    }

    func testAllPremiumStrengthSessionsPreserveRepetitionRangesAndRIR() {
        XCTAssertFalse(ATHLTHPremiumStrengthSessions.recipes.isEmpty)
        for recipe in ATHLTHPremiumStrengthSessions.recipes {
            let blocks = ATHLTHPremiumStrengthSessions.blocks(for: recipe)
            XCTAssertEqual(blocks.count, recipe.moves.count + 1)
            for (movement, block) in zip(recipe.moves, blocks.dropFirst()) {
                XCTAssertEqual(block.setCount, movement.sets)
                XCTAssertEqual(block.restBetweenSetsSeconds, Double(movement.restSeconds))
                XCTAssertEqual(block.targetRepsInReserve, movement.rir)
                XCTAssertEqual(block.targetRepetitionsMaximum,
                               movement.durationSeconds == nil ? movement.repsMax : nil)
                XCTAssertEqual(block.repetitions,
                               movement.durationSeconds == nil ? movement.repsMin : nil)
                XCTAssertEqual(block.durationSeconds,
                               movement.durationSeconds.map(Double.init))
            }
        }
    }

    func testAllGymCoachStrengthWorkoutsPreserveTempoRIRAndSupersetSource() {
        XCTAssertFalse(ATHLTHGymCoachStrengthLibrary.programs.isEmpty)
        for program in ATHLTHGymCoachStrengthLibrary.programs {
            for workout in program.program.workouts {
                let blocks = ATHLTHGymCoachStrengthLibrary.blocks(for: workout)
                let eligible = workout.exercises.prefix(20).filter { exercise in
                    (1...20).contains(exercise.targetSets) &&
                    (1...50).contains(exercise.targetRepsMin) &&
                    exercise.targetRepsMax >= exercise.targetRepsMin &&
                    exercise.targetRepsMax <= 50 &&
                    (0...5).contains(exercise.targetRIR) &&
                    (15...600).contains(exercise.restSec)
                }
                XCTAssertEqual(blocks.count, eligible.count + 1,
                               "\(program.slug) / \(workout.name)")
                for (exercise, block) in zip(eligible, blocks.dropFirst()) {
                    XCTAssertEqual(block.repetitions, exercise.targetRepsMin)
                    XCTAssertEqual(block.targetRepetitionsMaximum,
                                   exercise.targetRepsMax)
                    XCTAssertEqual(block.targetRepsInReserve, exercise.targetRIR)
                    XCTAssertEqual(block.targetMovementTempo, exercise.tempo)
                    XCTAssertEqual(block.sourceSupersetGroupIndex,
                                   exercise.supersetGroup)
                    XCTAssertEqual(block.restBetweenSetsSeconds,
                                   Double(exercise.restSec))
                }
            }
        }
    }

    func testEnglishAndNorwegianLegacyNotesUpgradeWithoutDiscardingCoaching() {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Hill workout",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 120, targetWeightKilograms: nil, loadNote: nil,
            notes: "Stay smooth · VMA target: 95 % · Pace intensity: hard" +
                   " · Elevation gain: 120 m · Gradient: 5 % · Terrain: trail",
            phase: .main
        )
        let fixed = ATHLTHWorkoutStructuredDataMigration.normalize(block)
        XCTAssertEqual(fixed.targetVMAPercent, 95)
        XCTAssertEqual(fixed.targetIntensityType, "hard")
        XCTAssertEqual(fixed.targetElevationGainMeters, 120)
        XCTAssertEqual(fixed.targetGradientPercent, 5)
        XCTAssertEqual(fixed.targetTerrainType, "trail")
        XCTAssertEqual(fixed.notes, "Stay smooth")
        XCTAssertEqual(ATHLTHWorkoutStructuredDataMigration.normalize(fixed), fixed)

        block.notes = "Rolig rytme · VMA-mål: 92,5 % · Fartsintensitet: progressiv" +
                      " · Høydemeter: 180 m · Stigning: 8 % · Terreng: grus"
        let norwegian = ATHLTHWorkoutStructuredDataMigration.normalize(block)
        XCTAssertEqual(norwegian.targetVMAPercent, 92.5)
        XCTAssertEqual(norwegian.targetTerrainType, "grus")
        XCTAssertEqual(norwegian.targetGradientPercent, 8)
        XCTAssertEqual(norwegian.notes, "Rolig rytme")
    }

    func testLegacyStrengthAndUnstructuredAthleteNotesRemainSafe() {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat",
            exerciseSlug: nil, distanceMeters: nil, repetitions: 8,
            durationSeconds: nil, targetWeightKilograms: nil, loadNote: nil,
            notes: "8–12 reps · 2 reps in reserve",
            phase: .main
        )
        let converted = ATHLTHWorkoutStructuredDataMigration.normalize(block)
        XCTAssertEqual(converted.repetitions, 8)
        XCTAssertEqual(converted.targetRepetitionsMaximum, 12)
        XCTAssertEqual(converted.targetRepsInReserve, 2)
        XCTAssertNil(converted.notes)

        block.notes = "Keep full range of motion · I felt great today"
        let unchanged = ATHLTHWorkoutStructuredDataMigration.normalize(block)
        XCTAssertEqual(unchanged.notes, block.notes)
        XCTAssertNil(unchanged.targetRepsInReserve)

        block.notes = "8–12 per sett · 2 repetisjoner i reserve (RIR). Velg vekt selv."
        let premium = ATHLTHWorkoutStructuredDataMigration.normalize(block)
        XCTAssertEqual(premium.targetRepetitionsMaximum, 12)
        XCTAssertEqual(premium.targetRepsInReserve, 2)
        XCTAssertEqual(premium.notes, "Velg vekt selv.")
    }

    func testHYROXLoadChoicesRemainAlternativesRatherThanPersonalWeights() {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Wall Balls",
            exerciseSlug: nil, distanceMeters: nil, repetitions: 60,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: "6 kg / 4 kg as specified by the HYROX PFT",
            notes: nil, phase: .main
        )
        let normalized = ATHLTHWorkoutStructuredDataMigration.normalize(block)
        XCTAssertEqual(normalized.sourceLoadAlternativesKilograms, [6, 4])
        XCTAssertNil(normalized.targetWeightKilograms)
        XCTAssertEqual(normalized.loadNote, block.loadNote)

        block.loadNote = "Use your division race load"
        let unassigned = ATHLTHWorkoutStructuredDataMigration.normalize(block)
        XCTAssertNil(unassigned.sourceLoadAlternativesKilograms)
        XCTAssertNil(unassigned.targetWeightKilograms)
    }

    func testExtendedTargetsSurviveCodingAndExecutionExpansion() throws {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Hill repetitions",
            exerciseSlug: nil, distanceMeters: 200, repetitions: nil,
            durationSeconds: 60, targetWeightKilograms: nil, loadNote: nil,
            notes: "Keep cadence high", phase: .main, setCount: 3
        )
        block.targetVMAPercent = 105
        block.targetIntensityType = "hill sprint"
        block.targetElevationGainMeters = 25
        block.targetGradientPercent = 6
        block.targetTerrainType = "hill"
        block.targetRepetitionsMaximum = 8
        block.targetRepsInReserve = 1
        block.targetMovementTempo = "3-1-1-0"
        block.sourceSupersetGroupIndex = 2
        block.sourceLoadAlternativesKilograms = [6, 4]

        let decoded = try JSONDecoder().decode(
            WorkoutTemplateBlock.self, from: JSONEncoder().encode(block)
        )
        XCTAssertEqual(decoded, block)
        let execution = [decoded].expandedForExecution()
        XCTAssertEqual(execution.count, 1)
        let result = try XCTUnwrap(execution.first)
        XCTAssertEqual(result.targetVMAPercent, 105)
        XCTAssertEqual(result.targetElevationGainMeters, 25)
        XCTAssertEqual(result.targetGradientPercent, 6)
        XCTAssertEqual(result.targetTerrainType, "hill")
        XCTAssertEqual(result.targetMovementTempo, "3-1-1-0")
        XCTAssertEqual(result.sourceSupersetGroupIndex, 2)
        XCTAssertEqual(result.sourceLoadAlternativesKilograms, [6, 4])
    }
}
