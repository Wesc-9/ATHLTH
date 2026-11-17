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
    func testAll240PublishedWorkoutsResolveOriginalCoachingAndEnvironmentDetails() {
        let entries = ATHLTHZonedPlanLibrary.workoutCatalogEntries
        XCTAssertEqual(entries.count, 240)
        for entry in entries {
            let original = ATHLTHZonedPlanLibrary.workout(
                forCatalogSlug: entry.slug
            )
            XCTAssertNotNil(original, entry.slug)
            XCTAssertFalse(original?.coachingTipsEn?.isEmpty ?? true,
                           "\(entry.slug): source coaching tips missing")
            XCTAssertFalse(original?.commonMistakesEn?.isEmpty ?? true,
                           "\(entry.slug): source mistakes missing")
            XCTAssertNotNil(original?.environment,
                            "\(entry.slug): environment metadata missing")
        }
        XCTAssertNil(ATHLTHZonedPlanLibrary.workout(
            forCatalogSlug: "unrelated-workout"
        ))
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
        // The source's five-minute drills + 3 strides is now executable
        // as four distinct warm-up steps; walking and jogging cooldown
        // are two steps, rather than two combined instructions.
        XCTAssertEqual(original.count, 8)
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
    func testAssessmentEditorHasOneShortTitleAndCompleteNorwegianInstructions() throws {
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
        let steps = ATHLTHZonedPlanLibrary.blocks(for: source)
        let effort = try XCTUnwrap(steps.first {
            $0.resolvedPhase == .main
        })
        XCTAssertEqual(effort.title, "3 min maksimaltest")
        XCTAssertEqual(ATHLTHWorkoutNameSuggestion.displayStepTitle(effort),
                       "3 min maksimaltest")
        XCTAssertEqual(effort.durationSeconds, 180)
        XCTAssertEqual(effort.targetHeartRateZone, 5)
        XCTAssertFalse(ATHLTHPlannedRunStepEditor.allowsActivitySelection(for: effort))
        XCTAssertTrue(effort.notes?.contains("totaldistanse") == true)
        XCTAssertTrue(effort.notes?.contains("mellom 2:30 og 3:00") == true)

        let warmup = try XCTUnwrap(steps.first {
            $0.resolvedPhase == .warmup
        })
        XCTAssertTrue(ATHLTHPlannedRunStepEditor.allowsActivitySelection(for: warmup))

        let cooldown = steps.filter { $0.resolvedPhase == .cooldown }
        XCTAssertEqual(cooldown.count, 2)
        XCTAssertEqual(cooldown.map(\.title), ["Gange", "Rolig jogg"])
        XCTAssertEqual(cooldown.compactMap(\.durationSeconds).reduce(0, +), 600)
        XCTAssertEqual(cooldown.first?.cardioActivity, .walking)
        XCTAssertEqual(cooldown.last?.cardioActivity, .running)
        XCTAssertTrue(cooldown.allSatisfy { $0.targetHeartRateZone == 1 })
        XCTAssertTrue(cooldown.allSatisfy {
            $0.notes?.contains("estimert") == true
        })
    }

    @MainActor
    func testLegacyImportedStepRepairsMixedLanguageWithoutChangingTargets() throws {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }
        UserDefaults.standard.set("nb", forKey: "settings.language")
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first {
            $0.id == "ASS-009"
        })
        let steps = ATHLTHZonedPlanLibrary.blocks(for: source)
        var effort = try XCTUnwrap(steps.first { $0.resolvedPhase == .main })
        effort.title = "3 Minutter of sustained maximal effort på Bane. Record total distance og Fart of the last 30 Sekunder"
        effort.notes = "Min egen kommentar"
        let repaired = ATHLTHZonedLocalization.normalizeLegacyImportedStep(effort)
        XCTAssertEqual(repaired.title, "3 min maksimaltest")
        XCTAssertTrue(repaired.notes?.contains("totaldistanse") == true)
        XCTAssertTrue(repaired.notes?.contains("Min egen kommentar") == true)
        XCTAssertEqual(repaired.durationSeconds, effort.durationSeconds)
        XCTAssertEqual(repaired.targetHeartRateZone, effort.targetHeartRateZone)
        XCTAssertEqual(repaired.sourceIntensityZoneLabel, effort.sourceIntensityZoneLabel)
        XCTAssertEqual(
            ATHLTHZonedLocalization.normalizeLegacyImportedStep(repaired),
            repaired
        )
        XCTAssertFalse(ATHLTHPlannedRunStepEditor.allowsActivitySelection(for: repaired))

        var cooldown = try XCTUnwrap(steps.last)
        // Simulate the unexpanded 10-minute row stored by older builds.
        cooldown.durationSeconds = 600
        cooldown.title = "Gange deretter Svært Langsom Jogg"
        cooldown.notes = "Egen nedtrappingskommentar"
        let normalized = ATHLTHZonedLocalization.normalizeLegacyImportedStep(cooldown)
        XCTAssertEqual(normalized.title, "Gå, deretter rolig jogg")
        XCTAssertEqual(normalized.durationSeconds, 600)
        XCTAssertEqual(normalized.targetHeartRateZone, cooldown.targetHeartRateZone)
        XCTAssertTrue(normalized.notes?.contains("Egen nedtrappingskommentar") == true)
        XCTAssertTrue(normalized.notes?.contains("Start med gange") == true)
        XCTAssertEqual(
            ATHLTHZonedLocalization.normalizeLegacyImportedStep(normalized),
            normalized
        )
    }

    @MainActor
    func testOtherAssessmentTitlesAreNorwegianAndUnambiguous() throws {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }
        UserDefaults.standard.set("nb", forKey: "settings.language")

        let examples: [(String, String, Int)] = [
            ("ASS-001", "6 min testløp", 360),
            ("ASS-005", "12 min Cooper-test", 720)
        ]
        for (identifier, expectedTitle, expectedSeconds) in examples {
            let source = try XCTUnwrap(
                ATHLTHZonedPlanLibrary.workouts.first { $0.id == identifier }
            )
            let effort = try XCTUnwrap(
                ATHLTHZonedPlanLibrary.blocks(for: source).first {
                    $0.resolvedPhase == .main
                }
            )
            XCTAssertEqual(effort.title, expectedTitle, identifier)
            XCTAssertEqual(effort.durationSeconds, Double(expectedSeconds))
            XCTAssertFalse(
                ATHLTHPlannedRunStepEditor.allowsActivitySelection(for: effort)
            )
            XCTAssertNotNil(effort.notes)
        }
    }


    @MainActor
    func testAssessmentCatalogSourceInstructionsNoLongerBecomeEnglishHeadings() throws {
        let previous = UserDefaults.standard.string(forKey: "settings.language")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "settings.language")
            } else {
                UserDefaults.standard.removeObject(forKey: "settings.language")
            }
        }
        UserDefaults.standard.set("nb", forKey: "settings.language")

        let cases: [(id: String, title: String, note: String)] = [
            ("ASS-003", "5 km testløp", "Løp 5 km"),
            ("ASS-004", "20 m skytteltest", "lydsignalene"),
            ("ASS-006", "Conconi-test", "0,5 km/t"),
            ("ASS-008", "5 km MAF-test", "180 minus alder"),
            ("ASS-010", "Laktat-trinntest", "eventuelt laktat")
        ]
        for sample in cases {
            let source = try XCTUnwrap(
                ATHLTHZonedPlanLibrary.workouts.first { $0.id == sample.id }
            )
            let main = ATHLTHZonedPlanLibrary.blocks(for: source)
            let test = try XCTUnwrap(main.first {
                $0.title == sample.title
            }, "Missing clear Norwegian step: \(sample.id)")
            XCTAssertTrue(test.notes?.contains(sample.note) == true, sample.id)
            XCTAssertFalse(test.title.contains("Record"), sample.id)
            XCTAssertFalse(
                ATHLTHPlannedRunStepEditor.allowsActivitySelection(for: test),
                sample.id
            )
        }
    }

    @MainActor
    func testOrdinaryRunStillOffersWalkingAndUserTitleIsPreserved() throws {
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first {
            $0.id == "ASS-009"
        })
        var ordinary = try XCTUnwrap(
            ATHLTHZonedPlanLibrary.blocks(for: source).first {
                $0.resolvedPhase == .warmup
            }
        )
        ordinary.title = "Min egen rolige jogg"
        ordinary.notes = "Behold teksten som skrevet"
        XCTAssertEqual(
            ATHLTHZonedLocalization.normalizeLegacyImportedStep(ordinary),
            ordinary
        )
        XCTAssertTrue(
            ATHLTHPlannedRunStepEditor.allowsActivitySelection(for: ordinary)
        )
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


    @MainActor
    func testThreeMinuteAssessmentSplitsDrillsAndThreeStrides() throws {
        let source = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first {
            $0.id == "ASS-009"
        })
        let items = ATHLTHZonedPlanLibrary.blocks(for: source)
        let warmup = items.filter { $0.resolvedPhase == .warmup }
        XCTAssertEqual(warmup.count, 5)
        XCTAssertEqual(warmup[0].durationSeconds, 600)
        XCTAssertEqual(warmup[1].durationSeconds, 270)
        XCTAssertTrue(warmup[1].title.lowercased().contains(
            ATHLTHLocalization.isNorwegian ? "løpsdriller" : "drills"
        ))
        let efforts = warmup.filter { $0.title.contains("/3") }
        XCTAssertEqual(efforts.count, 3)
        XCTAssertEqual(efforts.compactMap(\.durationSeconds), [10, 10, 10])
        XCTAssertEqual(
            warmup.compactMap(\.durationSeconds).reduce(0, +), 900
        )
        XCTAssertTrue(efforts.allSatisfy { $0.kind == .run })
        XCTAssertTrue(efforts.allSatisfy { $0.notes?.isEmpty == false })
        XCTAssertEqual(
            items.compactMap(\.durationSeconds).reduce(0, +), 1_680
        )
        XCTAssertEqual(Set(items.map(\.editorDragID)).count, items.count)
        XCTAssertEqual(items.map(\.sequence), Array(1...items.count))
    }

    @MainActor
    func testAllRecognizedCombinedDrillsAreSplitAcrossImportedCatalog() throws {
        let cases: [(id: String, expectedEfforts: Int)] = [
            ("ASS-001", 3),
            ("ASS-003", 4),
            ("ASS-005", 3),
            ("ASS-006", 2),
            ("ASS-007", 4),
            ("ASS-009", 3),
            ("HIL-019", 4),
            ("RP-017", 3),
            ("RP-019", 3),
            ("THR-020", 3),
            ("TRL-001", 2),
            ("TRL-002", 3)
        ]
        for sample in cases {
            let workout = try XCTUnwrap(ATHLTHZonedPlanLibrary.workouts.first {
                $0.id == sample.id
            })
            let blocks = ATHLTHZonedPlanLibrary.blocks(for: workout)
            let inWarmup = blocks.filter { $0.resolvedPhase == .warmup }
            let expected = "/\(sample.expectedEfforts)"
            let efforts = inWarmup.filter { $0.title.contains(expected) }
            XCTAssertEqual(efforts.count, sample.expectedEfforts, sample.id)
            XCTAssertTrue(efforts.allSatisfy {
                $0.durationSeconds ?? 0 > 0
            }, sample.id)
            XCTAssertTrue(efforts.allSatisfy {
                $0.phase == .warmup
            }, sample.id)
        }
    }

    @MainActor
    func testCompoundSplitterNeverInventsDistanceOrChangesTotalTimeAndZones() throws {
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Drills and 3× progressive accelerations",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 300, targetWeightKilograms: nil,
            loadNote: nil, notes: "Original coaching", phase: .warmup
        )
        block.targetHeartRateZone = 3
        block.sourceIntensityZoneLabel = "Z3"
        block.targetHeartRatePercentMin = 70
        block.targetHeartRatePercentMax = 80

        for source in [
            "Drills and 3× progressive accelerations",
            "Drills and 3x accelerations",
            "Dynamic stretches and 3x progressive accelerations",
            "Drills and 4x strides",
            "Mobility and 2x gentle accelerations",
            "Drills and accelerations",
            "Drills and mobility"
        ] {
            let children = ATHLTHZonedCompoundStepSplitter.split(
                sourceEnglish: source, block: block
            )
            XCTAssertGreaterThan(children.count, 1, source)
            XCTAssertEqual(
                children.compactMap(\.durationSeconds).reduce(0, +),
                300, accuracy: 0.001, source
            )
            XCTAssertTrue(children.allSatisfy { $0.distanceMeters == nil }, source)
            XCTAssertTrue(children.allSatisfy {
                $0.targetHeartRateZone == 3 &&
                $0.sourceIntensityZoneLabel == "Z3" &&
                $0.targetHeartRatePercentMin == 70 &&
                $0.targetHeartRatePercentMax == 80
            }, source)
            XCTAssertEqual(
                Set(children.map(\.editorDragID)).count, children.count, source
            )
            XCTAssertTrue(children.allSatisfy {
                $0.durationSeconds ?? 0 >= 15
            }, source)
        }

        // An explicit per-stride time remains prescribed; the rest of the
        // original five minutes is an editable preparation block.
        let exact = ATHLTHZonedCompoundStepSplitter.split(
            sourceEnglish: "3x30s progressive accelerations", block: block
        )
        XCTAssertEqual(exact.count, 4)
        XCTAssertEqual(exact.map(\.durationSeconds), [210, 30, 30, 30])

        let noTime = ATHLTHZonedCompoundStepSplitter.split(
            sourceEnglish: "Drills and 3x progressive accelerations",
            block: WorkoutTemplateBlock(
                sequence: 1, kind: .run, title: "Open warmup",
                exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
                durationSeconds: nil, targetWeightKilograms: nil,
                loadNote: nil, notes: nil, phase: .warmup
            )
        )
        XCTAssertEqual(noTime.count, 1, "Never invent total time for open steps")
    }

    @MainActor
    func testAllRecognizedRunningSourceSegmentsConserveOriginalTime() {
        // Audit across every bundled source workout. Apply the same
        // splitter as the importer, including nested repeat segments.
        var converted = 0
        func walk(_ steps: [ATHLTHZonedPlanLibrary.Step]) {
            for step in steps {
                if step.kind == "segment", let duration = step.durationSec,
                   duration > 0 {
                    let input = WorkoutTemplateBlock(
                        sequence: 1, kind: .run,
                        title: step.descriptionEn ?? "Step",
                        exerciseSlug: nil, distanceMeters: step.distanceM,
                        repetitions: nil, durationSeconds: duration,
                        targetWeightKilograms: nil, loadNote: nil,
                        notes: nil, phase: .warmup
                    )
                    let result = ATHLTHZonedCompoundStepSplitter.split(
                        sourceEnglish: step.descriptionEn ?? "", block: input
                    )
                    if result.count > 1 { converted += 1 }
                    XCTAssertEqual(
                        result.compactMap(\.durationSeconds).reduce(0, +),
                        duration, accuracy: 0.001, step.descriptionEn ?? ""
                    )
                    XCTAssertTrue(result.allSatisfy {
                        ($0.durationSeconds ?? 0) > 0
                    }, step.descriptionEn ?? "")
                }
                walk(step.steps ?? [])
                walk(step.between ?? [])
            }
        }
        for workout in ATHLTHZonedPlanLibrary.workouts
            where workout.discipline != "cycling" &&
                workout.discipline != "swimming" {
            walk(workout.warmupStructure ?? [])
            walk(workout.mainSetStructure ?? [])
            walk(workout.cooldownStructure ?? [])
        }
        XCTAssertGreaterThan(converted, 40)
    }


}
