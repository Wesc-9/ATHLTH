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
    func testOneMinuteIntervalsCarryRealZ5AndZ1ThroughLibraryAndExecution() throws {
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first {
            $0.id == "VMA-006"
        })
        let sourceBlocks = ATHLTHZonedPlanLibrary.blocks(for: source)
        let efforts = sourceBlocks.filter {
            $0.resolvedPhase == .main && $0.durationSeconds == 60
        }
        let recoveries = sourceBlocks.filter {
            $0.resolvedPhase == .recovery && $0.durationSeconds == 60
        }

        XCTAssertEqual(efforts.count, 12)
        XCTAssertEqual(recoveries.count, 11)
        XCTAssertTrue(efforts.allSatisfy {
            $0.kind == .run && $0.targetHeartRateZone == 5 &&
            $0.sourceIntensityZoneLabel == "Z5" &&
            $0.targetHeartRatePercentMin == 90 &&
            $0.targetHeartRatePercentMax == 100
        })
        XCTAssertTrue(recoveries.allSatisfy {
            $0.targetHeartRateZone == 1 &&
            $0.sourceIntensityZoneLabel == "Z1" &&
            $0.targetHeartRatePercentMin == 50 &&
            $0.targetHeartRatePercentMax == 60
        })

        let workout = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workoutCatalogEntries.first {
                $0.slug == "zoned-vma-006"
            }
        )
        let saved = ATHLTHWorkoutLibraryPersonalization.blankTargets(
            workout.plannedSession().resolvedWorkoutBlocks
        )
        XCTAssertEqual(saved.count, sourceBlocks.count)
        let executed = saved.expandedForExecution()
        XCTAssertEqual(executed.filter {
            $0.resolvedPhase == .main && $0.targetHeartRateZone == 5
        }.count, 12)
        XCTAssertEqual(executed.filter {
            $0.resolvedPhase == .recovery && $0.targetHeartRateZone == 1
        }.count, 11)
        XCTAssertEqual(
            ATHLTHWorkoutStepTargetSummary.zoneLabel(for: efforts[0]),
            "Z5"
        )
        XCTAssertEqual(
            ATHLTHWorkoutStepTargetSummary.percentRange(for: efforts[0]),
            90...100
        )
        XCTAssertEqual(
            ATHLTHWorkoutStepTargetSummary.highlightedZones(for: recoveries[0]),
            Set([1])
        )
        let overview = ATHLTHSimpleWorkoutOutline.stages(for: sourceBlocks)
        let main = try XCTUnwrap(overview.first { $0.phase == .main })
        XCTAssertTrue(main.items.contains {
            $0.detail.contains("Z5") && $0.detail.contains("Z1")
        })
    }

    @MainActor
    func testMultiZoneSourceRangesRemainStructuredAndVisible() throws {
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first {
            $0.id == "VMA-006"
        })
        let warmup = try XCTUnwrap(ATHLTHZonedPlanLibrary.blocks(for: source)
            .first { $0.sourceIntensityZoneLabel == "Z1-Z2" })
        XCTAssertNil(warmup.targetHeartRateZone)
        XCTAssertEqual(
            ATHLTHWorkoutStepTargetSummary.zoneLabel(for: warmup),
            "Z1–Z2"
        )
        XCTAssertEqual(
            ATHLTHWorkoutStepTargetSummary.percentRange(for: warmup),
            50...70
        )
        XCTAssertEqual(
            ATHLTHWorkoutStepTargetSummary.highlightedZones(for: warmup),
            Set([1, 2])
        )
    }

    @MainActor
    func testGenericLibraryCopyKeepsAuthoredHeartRateTargets() {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "VO2max effort",
            exerciseSlug: nil, distanceMeters: nil,
            repetitions: nil, durationSeconds: 60,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: .main
        )
        block.targetHeartRateZone = 5
        block.targetPaceSecondsPerKilometer = 260
        block.targetHeartRatePercentMin = 90
        block.targetHeartRatePercentMax = 100
        // Other curated sources may not use a separate source-zone label.
        XCTAssertNil(block.sourceIntensityZoneLabel)

        let personalized = ATHLTHWorkoutLibraryPersonalization.blankTargets([block])
        XCTAssertEqual(personalized[0].targetHeartRateZone, 5)
        XCTAssertEqual(personalized[0].targetHeartRatePercentMin, 90)
        XCTAssertEqual(personalized[0].targetHeartRatePercentMax, 100)
        XCTAssertNil(personalized[0].targetPaceSecondsPerKilometer)
        XCTAssertEqual(personalized[0].durationSeconds, 60)
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


    @MainActor
    func testZonedIntervalJogIsRecognizedAsActiveRecovery() throws {
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first { $0.id == "VMA-001" })
        let timeline = ATHLTHZonedPlanLibrary.blocks(for: source)
        let recoveries = timeline.filter(\.isActiveRecovery)
        XCTAssertFalse(recoveries.isEmpty)
        XCTAssertTrue(recoveries.allSatisfy { $0.kind == .run })
        XCTAssertTrue(recoveries.allSatisfy { $0.resolvedPhase == .recovery })
        XCTAssertTrue(recoveries.allSatisfy {
            $0.sourceIntensityZoneLabel == "Z1" && $0.targetHeartRateZone == 1
        })
        // Each 30-second jog between reps and the 3-minute jog between sets
        // are active recoveries. Both must survive the Zoned import.
        XCTAssertEqual(recoveries.filter { $0.durationSeconds == 30 }.count, 22)
        XCTAssertEqual(recoveries.filter { $0.durationSeconds == 180 }.count, 1)
        XCTAssertEqual(recoveries.count, 23)
    }

    @MainActor
    func testThreeMinuteAllOutHasReadableNameInstructionsAndPrescribedDuration() throws {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }
        UserDefaults.standard.set("nb", forKey: "settings.language")

        let source = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "ASS-009" }
        )
        let original = ATHLTHZonedPlanLibrary.blocks(for: source)
        XCTAssertEqual(original.count, 4)
        let effort = try XCTUnwrap(original.first { $0.resolvedPhase == .main })
        XCTAssertEqual(effort.kind, .run)
        XCTAssertEqual(effort.durationSeconds, 180)
        XCTAssertEqual(effort.title, "3 min maksimaltest")
        XCTAssertTrue(effort.notes?.contains("30 sekundene") == true)
        XCTAssertFalse(effort.title.contains("Record"))
        XCTAssertEqual(effort.targetHeartRateZone, 5)
        XCTAssertEqual(effort.sourceIntensityZoneLabel, "Z5")

        let personalCopy = ATHLTHWorkoutLibraryPersonalization.blankTargets(original)
        let personalized = try XCTUnwrap(
            personalCopy.first { $0.resolvedPhase == .main }
        )
        XCTAssertEqual(personalized.title, "3 min maksimaltest")
        XCTAssertEqual(personalized.durationSeconds, 180)
        XCTAssertEqual(personalized.targetHeartRateZone, 5)
        XCTAssertEqual(personalized.sourceIntensityZoneLabel, "Z5")
        XCTAssertTrue(personalized.notes?.contains("totaldistanse") == true)
        XCTAssertNil(personalized.targetPaceSecondsPerKilometer)

        let summary = ATHLTHZonedLocalization.workoutSummary(
            source.category, english: source.descriptionEn, workoutID: source.id
        )
        XCTAssertTrue(summary.contains("Tre minutters"))
    }

    @MainActor
    func testOlderMixedLanguageAllOutCopyIsCorrectedWithoutChangingPrescription() throws {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }
        UserDefaults.standard.set("nb", forKey: "settings.language")
        let source = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.workouts.first { $0.id == "ASS-009" }
        )
        var old = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.blocks(for: source).first {
                $0.resolvedPhase == .main
            }
        )
        old.title = "3 Minutter of sustained maximal effort på Bane. Record total distance og Fart of the last 30 Sekunder"
        old.notes = "Egen merknad"
        let fixed = ATHLTHZonedLocalization.normalizeLegacyAllOutStep(old)
        XCTAssertEqual(fixed.title, "3 min maksimaltest")
        XCTAssertEqual(fixed.durationSeconds, 180)
        XCTAssertEqual(fixed.targetHeartRateZone, old.targetHeartRateZone)
        XCTAssertTrue(fixed.notes?.contains("totaldistanse") == true)
        XCTAssertTrue(fixed.notes?.contains("Egen merknad") == true)
        XCTAssertEqual(ATHLTHZonedLocalization.normalizeLegacyAllOutStep(fixed), fixed)
        XCTAssertEqual(ATHLTHWorkoutStepCopy.title(
            for: old, workoutTitle: source.nameEn, compact: true
        ), "3 min maksimaltest")
    }

    @MainActor
    func testLengthySourceDescriptionUsesShortTitleAndPreservesInstructions() {
        let text = "Run steadily at a relaxed pace across the first long section. Record the exact elapsed time for your next test."
        let copy = ATHLTHZonedLocalization.stepCopy(
            sourceEnglish: text, durationSeconds: 600, isRunning: true
        )
        XCTAssertLessThan(copy.title.count, 60)
        XCTAssertNotNil(copy.instructions)
        XCTAssertTrue(copy.instructions?.contains("Record") == true)
    }

    @MainActor
    func testImportedWorkoutsNeverExposeSourceZoneSix() {
        for workout in ATHLTHZonedPlanLibrary.workouts where workout.discipline != "swimming" {
            for block in ATHLTHZonedPlanLibrary.blocks(for: workout) {
                XCTAssertFalse(block.sourceIntensityZoneLabel?.contains("6") ?? false, workout.id)
                if let zone = block.targetHeartRateZone {
                    XCTAssertTrue((1...5).contains(zone), workout.id)
                }
            }
        }
    }

}
