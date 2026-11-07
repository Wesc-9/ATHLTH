import XCTest
@testable import ATHLTH

final class ATHLTHIntervalRecipeEditingTests: XCTestCase {
    @MainActor
    private func recipe() -> (UUID, [WorkoutTemplateBlock]) {
        let blocks = ATHLTHRunningExercisePreset.thirtyThirty.blocks(in: .main)
        return (blocks[0].groupID!, blocks)
    }

    @MainActor
    func testThirtyThirtyIsOneCollapsibleSequenceButExecutesFortyRealSteps() throws {
        let (id, blocks) = recipe()
        let summary = try XCTUnwrap(ATHLTHIntervalRecipeEditing.summary(
            for: id, in: blocks
        ))
        XCTAssertEqual(summary.rounds, 20)
        XCTAssertEqual(summary.recoveryCount, 20)
        XCTAssertTrue(summary.hasFinalRecovery)
        XCTAssertEqual(summary.exactSeconds, 1_200)
        XCTAssertEqual(blocks.expandedForExecution().count, 40)
        XCTAssertEqual(
            blocks.expandedForExecution().filter(\.isActiveRecovery).count, 20
        )
        XCTAssertEqual(Set(blocks.map(\.editorDragID)).count, 40)
    }

    @MainActor
    func testRoundCountPreservesExistingEditsAndAddsOnlyNewPairs() throws {
        let original = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        let id = try XCTUnwrap(original.first?.groupID)
        var edited = original
        edited[2].targetPaceSecondsPerKilometer = 285
        edited[2].targetHeartRateZone = 4
        edited[3].durationSeconds = 200

        let increased = try XCTUnwrap(ATHLTHIntervalRecipeEditing.changing(
            edited, groupID: id, rounds: 5, finalRecovery: true
        ))
        XCTAssertEqual(increased.count, 10)
        XCTAssertEqual(increased[2].targetPaceSecondsPerKilometer, 285)
        XCTAssertEqual(increased[2].targetHeartRateZone, 4)
        XCTAssertEqual(increased[3].durationSeconds, 200)
        XCTAssertEqual(increased[8].durationSeconds, 240)
        XCTAssertEqual(increased[9].durationSeconds, 180)
        XCTAssertEqual(Set(increased.map(\.editorDragID)).count, 10)

        let shortened = try XCTUnwrap(ATHLTHIntervalRecipeEditing.changing(
            increased, groupID: id, rounds: 3, finalRecovery: false
        ))
        XCTAssertEqual(shortened.count, 5)
        XCTAssertEqual(shortened[2].targetPaceSecondsPerKilometer, 285)
        XCTAssertEqual(shortened[3].durationSeconds, 200)
        XCTAssertEqual(shortened.last?.isRestOrActiveRecovery, false)
        XCTAssertEqual(shortened.expandedForExecution().count, 5)
        let restored = try XCTUnwrap(ATHLTHIntervalRecipeEditing.changing(
            shortened, groupID: id, rounds: 3, finalRecovery: true
        ))
        XCTAssertEqual(restored.count, 6)
        XCTAssertEqual(restored.last?.isRestOrActiveRecovery, true)
    }

    @MainActor
    func testApplyFirstTargetsDoesNotTouchActiveRecoveries() throws {
        let (id, original) = recipe()
        var changed = original
        changed[0].targetPaceSecondsPerKilometer = 240
        changed[0].targetHeartRateZone = 4
        changed[0].treadmillInclinePercent = 1.5
        changed[0].isIndoor = true
        changed[4].targetPaceSecondsPerKilometer = 270
        changed[1].targetPaceSecondsPerKilometer = 510
        let copied = try XCTUnwrap(
            ATHLTHIntervalRecipeEditing.copyingFirstEffortTargets(
                in: changed, groupID: id
            )
        )
        for i in copied.indices where i.isMultiple(of: 2) {
            XCTAssertEqual(copied[i].targetPaceSecondsPerKilometer, 240)
            XCTAssertEqual(copied[i].targetHeartRateZone, 4)
            XCTAssertEqual(copied[i].treadmillInclinePercent, 1.5)
            XCTAssertEqual(copied[i].isIndoor, true)
        }
        XCTAssertEqual(copied[1].targetPaceSecondsPerKilometer, 510)
        XCTAssertNil(copied[3].targetPaceSecondsPerKilometer)
        XCTAssertEqual(copied[3].treadmillInclinePercent, 1.5)
        XCTAssertEqual(copied[3].isIndoor, true)
    }

    @MainActor
    func testSavedExplicitGroupReopensAndCompactLegacyExpands() throws {
        let (id, original) = recipe()
        let restored = try JSONDecoder().decode(
            [WorkoutTemplateBlock].self, from: JSONEncoder().encode(original)
        )
        let selected = ATHLTHIntervalRecipeEditing.forEditing(restored)
        XCTAssertEqual(selected.count, 40)
        XCTAssertNotNil(ATHLTHIntervalRecipeEditing.summary(for: id, in: selected))
        XCTAssertEqual(selected.expandedForExecution().count, 40)

        let compactID = UUID()
        var compact = original[0]
        compact.groupID = compactID
        compact.groupRounds = 4
        compact.durationSeconds = 240
        compact.activityTag = nil
        var recovery = original[1]
        recovery.groupID = compactID
        recovery.groupRounds = 4
        recovery.kind = .rest
        recovery.activityTag = nil
        let legacy = ATHLTHIntervalRecipeEditing.forEditing([compact, recovery])
        XCTAssertEqual(legacy.count, 7)
        XCTAssertTrue(legacy.allSatisfy {
            $0.groupID == compactID &&
            $0.groupKind == .intervals && $0.groupRounds == 1
        })
        let oldSummary = try XCTUnwrap(ATHLTHIntervalRecipeEditing.summary(
            for: compactID, in: legacy
        ))
        XCTAssertEqual(oldSummary.rounds, 4)
        XCTAssertEqual(oldSummary.recoveryCount, 3)
        XCTAssertFalse(oldSummary.hasFinalRecovery)
        XCTAssertEqual(legacy.expandedForExecution().count, 7)
    }

    @MainActor
    func testTreadmillIntervalsWithActiveRecoveriesKeepIndoorClassification() {
        let (id, original) = recipe()
        var blocks = original
        blocks[0].isIndoor = true
        blocks[0].treadmillInclinePercent = 1.0
        let updated = ATHLTHIntervalRecipeEditing.copyingFirstEffortTargets(
            in: blocks, groupID: id
        )!
        XCTAssertEqual(
            ATHLTHPlannedWorkoutMetrics.runningLocation(for: updated),
            .treadmill
        )
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "30/30 treadmill", kind: .running, durationMinutes: 20,
            routeID: UUID(), blocks: updated
        )
        XCTAssertEqual(blueprint.category, "treadmill")
        XCTAssertNil(blueprint.applying(to: nil).routeID)
        XCTAssertEqual(updated.filter(\.isActiveRecovery).count, 20)
        XCTAssertTrue(updated.filter(\.isActiveRecovery).allSatisfy {
            $0.isIndoor == true && $0.treadmillInclinePercent == 1.0
        })
    }

    @MainActor
    func testUngroupDoesNotDeleteOrAlterAWorkoutStep() {
        let (id, original) = recipe()
        let plain = ATHLTHIntervalRecipeEditing.ungrouping(
            original, groupID: id
        )
        XCTAssertEqual(plain.count, original.count)
        XCTAssertEqual(
            plain.map(\.durationSeconds), original.map(\.durationSeconds)
        )
        XCTAssertTrue(plain.allSatisfy {
            $0.groupID == nil && $0.groupKind == nil && $0.groupRounds == nil
        })
        XCTAssertEqual(plain.expandedForExecution().count, 40)
    }

    @MainActor
    func testPlannerDisplaysActualSecondsEvenWhenSchedulingRoundsUp() {
        let steps = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.previewSeconds(for: steps),
            1_680
        )
        XCTAssertEqual(ATHLTHWorkoutDurationEstimator.minutes(for: steps), 30)
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.conciseDuration(1_680), "28 min"
        )
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.conciseDuration(30),
            ATHLTHLocalization.choose(english: "30 sec", norwegian: "30 sek")
        )
        XCTAssertEqual(
            ATHLTHWorkoutDurationEstimator.conciseDuration(90), "1:30"
        )
    }

    @MainActor
    func testAllNewRunningLibraryPresetsDoNotSetPerceivedExertion() {
        for preset in ATHLTHRunningExercisePreset.allCases {
            XCTAssertTrue(preset.blocks(in: .main).allSatisfy {
                $0.targetEffortRPE == nil
            })
        }
    }

    @MainActor
    func testIncreasingDefaultFourByFourRenumbersEveryGeneratedEffort() throws {
        let original = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        let id = try XCTUnwrap(original.first?.groupID)
        let expanded = try XCTUnwrap(ATHLTHIntervalRecipeEditing.changing(
            original, groupID: id, rounds: 10, finalRecovery: false
        ))
        let titles = expanded.filter { $0.kind == .run && !$0.isActiveRecovery }
            .map(\.title)
        XCTAssertEqual(titles.count, 10)
        for (index, title) in titles.enumerated() {
            XCTAssertTrue(title.hasSuffix("\(index + 1)/10"), title)
            XCTAssertFalse(title.contains("1/4 "), title)
        }
        XCTAssertEqual(expanded.count, 19)
        let summary = try XCTUnwrap(ATHLTHIntervalRecipeEditing.summary(
            for: id, in: expanded
        ))
        XCTAssertEqual(summary.rounds, 10)
        XCTAssertFalse(summary.displayName.contains("1/4"))
        XCTAssertEqual(expanded.expandedForExecution().count, 19)
    }

    @MainActor
    func testBadLegacyIntervalLabelsAreRepairedWithoutReplacingCustomTitles() throws {
        let original = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        let id = try XCTUnwrap(original.first?.groupID)
        var custom = original
        custom[0].title = "Løpeintervall · 1/4"
        custom[2].title = "Avslutt sterkt"
        custom[4].title = "Løpeintervall · 1/4 5"
        let updated = try XCTUnwrap(ATHLTHIntervalRecipeEditing.changing(
            custom, groupID: id, rounds: 6, finalRecovery: true
        ))
        XCTAssertTrue(updated[0].title.hasSuffix("1/6"))
        XCTAssertEqual(updated[2].title, "Avslutt sterkt")
        XCTAssertTrue(updated[4].title.hasSuffix("3/6"))
        XCTAssertTrue(updated[10].title.hasSuffix("6/6"))
    }

    @MainActor
    func testWholeIntervalUpdatesTargetsWhilePreservingEveryStepIdentity() throws {
        let original = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        let id = try XCTUnwrap(original.first?.groupID)
        var individualized = original
        individualized[2].durationSeconds = 290
        individualized[2].targetPaceSecondsPerKilometer = 410
        individualized[3].durationSeconds = 210

        // Count-only edits must not erase any manually tailored effort/pause.
        let countOnly = try XCTUnwrap(ATHLTHIntervalRecipeEditing.adjusting(
            individualized, groupID: id, rounds: 5, finalRecovery: false,
            sharedWork: nil, sharedRecovery: nil
        ))
        XCTAssertEqual(countOnly[2].durationSeconds, 290)
        XCTAssertEqual(countOnly[2].targetPaceSecondsPerKilometer, 410)
        XCTAssertEqual(countOnly[3].durationSeconds, 210)
        XCTAssertEqual(countOnly.count, 9)

        var sharedWork = individualized[0]
        sharedWork.durationSeconds = 180
        sharedWork.distanceMeters = nil
        sharedWork.targetPaceSecondsPerKilometer = 265
        sharedWork.targetHeartRateZone = 4
        sharedWork.treadmillInclinePercent = 2.5
        sharedWork.isIndoor = true
        sharedWork.targetEffortRPE = 8
        sharedWork.notes = "Controlled effort"

        var sharedRecovery = individualized[1]
        sharedRecovery = ATHLTHActiveRecovery.convert(sharedRecovery, active: true)
        sharedRecovery.durationSeconds = 75
        sharedRecovery.targetPaceSecondsPerKilometer = 490
        sharedRecovery.targetHeartRateZone = 2

        let applied = try XCTUnwrap(ATHLTHIntervalRecipeEditing.adjusting(
            individualized, groupID: id, rounds: 5, finalRecovery: true,
            sharedWork: sharedWork, sharedRecovery: sharedRecovery
        ))
        XCTAssertEqual(applied.count, 10)
        XCTAssertEqual(applied.expandedForExecution().count, 10)
        XCTAssertEqual(Set(applied.map(\.editorDragID)).count, applied.count)
        XCTAssertEqual(applied[2].editorDragID, individualized[2].editorDragID)
        for block in applied where block.kind == .run && !block.isActiveRecovery {
            XCTAssertEqual(block.durationSeconds, 180)
            XCTAssertEqual(block.targetPaceSecondsPerKilometer, 265)
            XCTAssertEqual(block.targetHeartRateZone, 4)
            XCTAssertEqual(block.treadmillInclinePercent, 2.5)
            XCTAssertEqual(block.targetEffortRPE, 8)
            XCTAssertEqual(block.notes, "Controlled effort")
        }
        for block in applied where block.isActiveRecovery {
            XCTAssertEqual(block.durationSeconds, 75)
            XCTAssertEqual(block.targetPaceSecondsPerKilometer, 490)
            XCTAssertEqual(block.targetHeartRateZone, 2)
        }
        XCTAssertEqual(applied.last?.isActiveRecovery, true)

        var oneEdit = applied
        oneEdit[4].durationSeconds = 245
        XCTAssertEqual(oneEdit[0].durationSeconds, 180)
        XCTAssertEqual(oneEdit[4].durationSeconds, 245)
    }

    @MainActor
    func testDeleteEntireIntervalRemovesAllEffortsAndPausesOnly() throws {
        let first = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        let firstID = try XCTUnwrap(first.first?.groupID)
        let second = ATHLTHRunningExercisePreset.fiveByThree.blocks(in: .main)
        let secondID = try XCTUnwrap(second.first?.groupID)

        let warmup = WorkoutTemplateBlock(
            sequence: 0, kind: .run, title: "Warm-up",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 600, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .warmup
        )
        let cooldown = WorkoutTemplateBlock(
            sequence: 0, kind: .run, title: "Cool-down",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 300, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .cooldown
        )
        let original = [warmup] + first + second + [cooldown]
        let remaining = try XCTUnwrap(
            ATHLTHIntervalRecipeEditing.removing(original, groupID: firstID)
        )

        XCTAssertEqual(remaining.count, 2 + second.count)
        XCTAssertFalse(remaining.contains { $0.groupID == firstID })
        XCTAssertEqual(remaining.filter { $0.groupID == secondID }.count, second.count)
        XCTAssertEqual(remaining.first?.title, "Warm-up")
        XCTAssertEqual(remaining.last?.title, "Cool-down")
        XCTAssertEqual(remaining.map(\.sequence), Array(1...remaining.count))
        XCTAssertEqual(
            remaining.expandedForExecution().count, 2 + second.count
        )
        XCTAssertEqual(
            remaining.filter { $0.groupID == secondID }.map(\.editorDragID),
            second.map(\.editorDragID)
        )
        XCTAssertNil(
            ATHLTHIntervalRecipeEditing.removing(original, groupID: UUID())
        )
    }

    @MainActor
    func testDeleteEntireIntervalPreservesOtherCustomizedInterval() throws {
        let first = ATHLTHRunningExercisePreset.fourByFour.blocks(in: .main)
        let firstID = try XCTUnwrap(first.first?.groupID)
        let second = ATHLTHRunningExercisePreset.fiveByThree.blocks(in: .main)
        var customized = second
        customized[2].durationSeconds = 210
        customized[2].targetPaceSecondsPerKilometer = 270
        let original = first + customized
        let remaining = try XCTUnwrap(
            ATHLTHIntervalRecipeEditing.removing(original, groupID: firstID)
        )
        XCTAssertEqual(remaining[2].durationSeconds, 210)
        XCTAssertEqual(remaining[2].targetPaceSecondsPerKilometer, 270)
        XCTAssertEqual(remaining.count, customized.count)
        XCTAssertEqual(Set(remaining.map(\.groupID)), Set(customized.map(\.groupID)))
    }
}
