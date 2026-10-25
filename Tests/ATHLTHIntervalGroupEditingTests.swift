import XCTest
@testable import ATHLTH

final class ATHLTHIntervalGroupEditingTests: XCTestCase {
    private func recipe(rounds: Int = 4) -> (UUID, [WorkoutTemplateBlock]) {
        let group = UUID()
        var run = WorkoutTemplateBlock(
            sequence: 1, kind: .run, title: "Effort",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 45, targetWeightKilograms: nil, loadNote: nil,
            notes: "Stay relaxed", phase: .main,
            targetPaceSecondsPerKilometer: 245, targetHeartRateZone: 4,
            targetEffortRPE: 7, treadmillInclinePercent: 1.5,
            groupID: group, groupKind: .intervals, groupRounds: rounds,
            cardioActivity: .running, isIndoor: true)
        var rest = run
        rest.kind = .rest
        rest.title = "Recovery"
        rest.durationSeconds = 20
        rest.phase = .recovery
        rest.targetHeartRateZone = 2
        rest.editorDragID = UUID()
        run.editorDragID = UUID()
        return (group, [run, rest])
    }

    func testIndividualEditingKeepsExactExecutionAndNoFinalRecovery() throws {
        let (group, original) = recipe()
        let result = try XCTUnwrap(ATHLTHIntervalGroupEditing.individualSteps(in: original, groupID: group))
        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result.expandedForExecution(), original.expandedForExecution())
        XCTAssertTrue(result.allSatisfy { $0.groupID == nil && $0.groupRounds == nil })
        XCTAssertEqual(Set(result.map(\.editorDragID)).count, result.count)
        XCTAssertEqual(result.last?.kind, .run)
    }

    func testEditingThirdEffortAndPauseSurvivesSavingWithoutChangingOtherTargets() throws {
        let (group, original) = recipe()
        var result = try XCTUnwrap(ATHLTHIntervalGroupEditing.individualSteps(in: original, groupID: group))
        result[4].targetPaceSecondsPerKilometer = 232
        result[4].durationSeconds = 47
        result[5].durationSeconds = 35
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: "Individual targets", kind: .running, durationMinutes: 5,
            routeID: nil, blocks: result)
        XCTAssertTrue(blueprint.isValid)
        let restored = try JSONDecoder().decode(ATHLTHPlanStructuredWorkoutBlueprint.self,
                                               from: JSONEncoder().encode(blueprint))
        let steps = restored.blocks.expandedForExecution()
        XCTAssertEqual(steps[0].durationSeconds, 45)
        XCTAssertEqual(steps[2].targetPaceSecondsPerKilometer, 245)
        XCTAssertEqual(steps[4].targetPaceSecondsPerKilometer, 232)
        XCTAssertEqual(steps[4].durationSeconds, 47)
        XCTAssertEqual(steps[5].durationSeconds, 35)
        XCTAssertEqual(steps[1].durationSeconds, 20)
        XCTAssertEqual(steps[4].targetHeartRateZone, 4)
        XCTAssertEqual(steps[4].targetEffortRPE, 7)
        XCTAssertEqual(steps[4].treadmillInclinePercent, 1.5)
    }

    func testUnrelatedGroupsArePreservedAndUnknownGroupRejected() throws {
        let (group, original) = recipe()
        let (_, other) = recipe(rounds: 2)
        let result = try XCTUnwrap(ATHLTHIntervalGroupEditing.individualSteps(
            in: original + other, groupID: group))
        XCTAssertEqual(result.suffix(2).map(\.groupID), other.map(\.groupID))
        XCTAssertEqual(result.suffix(2).map(\.groupRounds), [2, 2])
        XCTAssertNil(ATHLTHIntervalGroupEditing.individualSteps(in: original, groupID: UUID()))
    }

    func testExpansionRejectsRecipesThatWouldExceedEditablePlanLimit() {
        let (group, original) = recipe(rounds: 20)
        let large = Array(repeating: original[0], count: 11)
        XCTAssertNil(ATHLTHIntervalGroupEditing.individualSteps(in: large, groupID: group))
        XCTAssertEqual(large.count, 11)
    }
}
