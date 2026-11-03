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
}
