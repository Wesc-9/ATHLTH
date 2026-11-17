import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAssessmentMethodTests: XCTestCase {
    private func step(
        phase: WorkoutPhaseKind, kind: WorkoutTemplateBlockKind = .run
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: "Test",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 180, targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: phase
        )
    }

    func testMainOnlyMeasurementDoesNotLeakIntoWarmupOrCooldown() throws {
        var main = step(phase: .main)
        main.assessmentMethod = .threeMinuteAllOut
        XCTAssertEqual(
            ATHLTHAssessmentMethod.normalized(main.assessmentMethod, for: main),
            .threeMinuteAllOut
        )
        for phase in [WorkoutPhaseKind.warmup, .cooldown, .recovery] {
            var step = main
            step.phase = phase
            XCTAssertNil(
                ATHLTHAssessmentMethod.normalized(step.assessmentMethod, for: step)
            )
        }
        let expanded = [main].expandedForExecution()
        XCTAssertEqual(expanded.count, 1)
        XCTAssertEqual(expanded.first?.assessmentMethod, .threeMinuteAllOut)
    }

    func testStrengthMethodNotAvailableOnRunningAndViceVersa() {
        let running = step(phase: .main)
        let strength = step(phase: .main, kind: .exercise)
        XCTAssertTrue(ATHLTHAssessmentMethod.available(for: running)
            .contains(.cooperTwelveMinute))
        XCTAssertFalse(ATHLTHAssessmentMethod.available(for: running)
            .contains(.estimatedOneRepMax))
        XCTAssertEqual(
            ATHLTHAssessmentMethod.available(for: strength),
            [.estimatedOneRepMax]
        )
        XCTAssertNil(ATHLTHAssessmentMethod.normalized(
            .estimatedOneRepMax, for: running
        ))
        XCTAssertNil(ATHLTHAssessmentMethod.normalized(
            .threeMinuteAllOut, for: strength
        ))
        var walking = running
        walking.cardioActivity = .walking
        XCTAssertTrue(ATHLTHAssessmentMethod.available(for: walking).isEmpty)
        var resting = running
        resting.kind = .rest
        XCTAssertTrue(ATHLTHAssessmentMethod.available(for: resting).isEmpty)
    }

    func testMeasurementSelectionSurvivesSavedRecipeAndPhaseRenumbering() throws {
        var main = step(phase: .main)
        main.assessmentMethod = .cooperTwelveMinute
        let encoded = try JSONEncoder().encode(main)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self)
            .contains("assessment_method"))
        let decoded = try JSONDecoder().decode(WorkoutTemplateBlock.self, from: encoded)
        XCTAssertEqual(decoded.assessmentMethod, .cooperTwelveMinute)
        let renumbered = ATHLTHWorkoutPhasePlacement.renumbered(
            decoded, sequence: 7
        )
        XCTAssertEqual(renumbered.assessmentMethod, .cooperTwelveMinute)
        XCTAssertEqual(renumbered.sequence, 7)

        let warmup = ATHLTHWorkoutPhasePlacement.relocatingSelection(
            at: 0, to: .warmup, in: [main]
        )
        XCTAssertEqual(warmup.count, 1)
        XCTAssertNil(warmup[0].assessmentMethod)
    }

    @MainActor
    func testPresetsAttachOnlyToOneMainTestStepAndNeverWarmup() throws {
        let cases: [(String, ATHLTHAssessmentMethod)] = [
            ("ASS-009", .threeMinuteAllOut),
            ("ASS-005", .estimatedVO2Max),
            ("ASS-001", .sixMinuteRun),
            ("ASS-003", .distanceTimeTrial),
            ("ASS-006", .conconiStep),
            ("ASS-010", .lactateStep)
        ]
        for (id, expected) in cases {
            let source = try XCTUnwrap(
                ATHLTHZonedPlanLibrary.workouts.first { $0.id == id }
            )
            let blocks = ATHLTHZonedPlanLibrary.blocks(for: source)
            let marked = blocks.filter { $0.assessmentMethod != nil }
            XCTAssertEqual(marked.count, 1, id)
            XCTAssertEqual(marked.first?.assessmentMethod, expected, id)
            XCTAssertEqual(marked.first?.resolvedPhase, .main, id)
            XCTAssertTrue(blocks.filter { $0.resolvedPhase != .main }
                .allSatisfy { $0.assessmentMethod == nil }, id)
        }
        XCTAssertNil(ATHLTHAssessmentMethod.bundledTest(for: "ASS-007"))
        XCTAssertNil(ATHLTHAssessmentMethod.bundledTest(for: "ASS-008"))
    }

    func testSnapshotKeepsProfileButNeverARecordedResult() throws {
        let snapshot = ExerciseSnapshot(
            name: "Knebøy",
            instructions: ["Sett med god kontroll"],
            assessmentMethod: .estimatedOneRepMax,
            primaryMuscles: ["Quads"], equipment: ["Barbell"], imageURL: nil
        )
        let decoded = try JSONDecoder().decode(
            ExerciseSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.assessmentMethod, .estimatedOneRepMax)
        XCTAssertEqual(decoded.instructions, snapshot.instructions)
    }

    func testCooperUsesOnlyMeasuredTwelveMinuteTestDistance() throws {
        let result = try XCTUnwrap(ATHLTHAssessmentCalculation.cooperVO2Max(
            measuredMeters: 2_400, testDurationSeconds: 720
        ))
        XCTAssertEqual(result, (2_400 - 504.9) / 44.73, accuracy: 0.001)
        XCTAssertNil(ATHLTHAssessmentCalculation.cooperVO2Max(
            measuredMeters: 2_400, testDurationSeconds: 360
        ))
        XCTAssertNil(ATHLTHAssessmentCalculation.cooperVO2Max(
            measuredMeters: .nan, testDurationSeconds: 720
        ))
    }

    func testStrengthEstimateRequiresValidWeightAndFewRepetitions() throws {
        XCTAssertEqual(
            ATHLTHAssessmentCalculation.estimatedOneRepMax(
                weightKilograms: 100, completedRepetitions: 1
            ), 100
        )
        let estimated = try XCTUnwrap(
            ATHLTHAssessmentCalculation.estimatedOneRepMax(
                weightKilograms: 80, completedRepetitions: 5
            )
        )
        XCTAssertEqual(estimated, 80 * (1 + 5.0 / 30), accuracy: 0.001)
        XCTAssertNil(ATHLTHAssessmentCalculation.estimatedOneRepMax(
            weightKilograms: 80, completedRepetitions: 20
        ))
        XCTAssertNil(ATHLTHAssessmentCalculation.estimatedOneRepMax(
            weightKilograms: -10, completedRepetitions: 5
        ))
    }

    func testTimedRunPaceRequiresActualDistanceAndElapsedTime() {
        XCTAssertEqual(ATHLTHAssessmentCalculation.measuredAveragePace(
            distanceMeters: 1_000, elapsedSeconds: 240
        ), 240)
        XCTAssertNil(ATHLTHAssessmentCalculation.measuredAveragePace(
            distanceMeters: 0, elapsedSeconds: 360
        ))
    }


    func testCooperRejectsWarmupPauseCooldownAndFiveMinuteDuration() {
        var warmup = step(phase: .warmup)
        warmup.durationSeconds = 600
        var test = step(phase: .main)
        test.durationSeconds = 720
        var pause = step(phase: .recovery, kind: .rest)
        pause.durationSeconds = 60
        var cooldown = step(phase: .cooldown)
        cooldown.durationSeconds = 300
        let all = [warmup, test, pause, cooldown]
        var scope = ATHLTHAssessmentScope(
            vo2Protocol: .cooperTwelveMinutes
        )

        XCTAssertTrue(scope.canCalculateCooper(from: all, anchorIndex: 1))
        XCTAssertEqual(scope.validate(
            method: .estimatedVO2Max, in: all, anchorIndex: 1
        ), .valid)
        XCTAssertNotNil(ATHLTHAssessmentCalculation.validatedCooperVO2Max(
            measuredMeters: 2_400, measuredDurationSeconds: 720,
            scope: scope, blocks: all, anchorIndex: 1
        ))
        XCTAssertNil(ATHLTHAssessmentCalculation.validatedCooperVO2Max(
            measuredMeters: 2_400, measuredDurationSeconds: 300,
            scope: scope, blocks: all, anchorIndex: 1
        ))

        scope.area = .entireWorkout
        var validation = scope.validate(
            method: .estimatedVO2Max, in: all, anchorIndex: 1
        )
        XCTAssertTrue(validation.isBlocking)
        XCTAssertTrue(validation.message?.contains("oppvarming") == true)
        XCTAssertFalse(scope.canCalculateCooper(from: all, anchorIndex: 1))
        XCTAssertNil(ATHLTHAssessmentCalculation.validatedCooperVO2Max(
            measuredMeters: 2_400, measuredDurationSeconds: 720,
            scope: scope, blocks: all, anchorIndex: 1
        ))

        scope.area = .mainSection
        XCTAssertTrue(scope.canCalculateCooper(from: all, anchorIndex: 1))

        scope.includePauses = true
        validation = scope.validate(
            method: .estimatedVO2Max, in: all, anchorIndex: 1
        )
        XCTAssertTrue(validation.isBlocking)
        XCTAssertTrue(validation.message?.contains("pauser") == true)

        scope.includePauses = false
        test.durationSeconds = 300
        let fiveMinute = [warmup, test, pause, cooldown]
        validation = scope.validate(
            method: .estimatedVO2Max, in: fiveMinute, anchorIndex: 1
        )
        XCTAssertTrue(validation.isBlocking)
        XCTAssertTrue(validation.message?.contains("12") == true)
        XCTAssertFalse(scope.canCalculateCooper(
            from: fiveMinute, anchorIndex: 1
        ))
    }

    func testUserCanSelectSpecificMainStepsButInvalidTestRemainsBlocked() {
        var warmup = step(phase: .warmup)
        warmup.measurementStepID = UUID()
        var main = step(phase: .main)
        main.durationSeconds = 720
        main.measurementStepID = UUID()
        var secondMain = step(phase: .main)
        secondMain.durationSeconds = 300
        secondMain.measurementStepID = UUID()
        var cooldown = step(phase: .cooldown)
        cooldown.measurementStepID = UUID()
        let all = [warmup, main, secondMain, cooldown]
        var scope = ATHLTHAssessmentScope(
            area: .chosenSteps,
            selectedStepIDs: [main.measurementStepID!],
            vo2Protocol: .cooperTwelveMinutes
        )
        XCTAssertEqual(scope.includedIndices(in: all, anchorIndex: 1), [1])
        XCTAssertTrue(scope.canCalculateCooper(from: all, anchorIndex: 1))

        scope.selectedStepIDs.append(secondMain.measurementStepID!)
        XCTAssertEqual(scope.includedIndices(in: all, anchorIndex: 1), [1, 2])
        XCTAssertTrue(scope.validate(
            method: .estimatedVO2Max, in: all, anchorIndex: 1
        ).isBlocking)

        scope.selectedStepIDs = [main.measurementStepID!, warmup.measurementStepID!]
        XCTAssertTrue(scope.validate(
            method: .estimatedVO2Max, in: all, anchorIndex: 1
        ).message?.contains("oppvarming") == true)

        scope.selectedStepIDs = [main.measurementStepID!]
        scope.vo2Protocol = nil
        XCTAssertFalse(scope.canCalculateCooper(from: all, anchorIndex: 1))
        XCTAssertFalse(scope.validate(
            method: .estimatedVO2Max, in: all, anchorIndex: 1
        ).isValid)

        scope.selectedStepIDs = []
        XCTAssertTrue(scope.validate(
            method: .distanceTimeTrial, in: all, anchorIndex: 1
        ).isBlocking)
    }

    func test3MTAndSixMinuteRunAlsoRejectWrongProtocols() {
        var main = step(phase: .main)
        var scope = ATHLTHAssessmentScope()

        main.durationSeconds = 300
        XCTAssertTrue(scope.validate(
            method: .threeMinuteAllOut, in: [main], anchorIndex: 0
        ).isBlocking)
        XCTAssertTrue(scope.validate(
            method: .sixMinuteRun, in: [main], anchorIndex: 0
        ).isBlocking)

        main.durationSeconds = 180
        let status = scope.validate(
            method: .threeMinuteAllOut, in: [main], anchorIndex: 0
        )
        XCTAssertFalse(status.isBlocking)
        XCTAssertNotNil(status.message) // Still needs actual last-30s data.
        XCTAssertTrue(scope.validate(
            method: .sixMinuteRun, in: [main], anchorIndex: 0
        ).isBlocking)

        main.durationSeconds = 360
        XCTAssertTrue(scope.validate(
            method: .sixMinuteRun, in: [main], anchorIndex: 0
        ).isValid)
        scope.includePauses = true
        XCTAssertTrue(scope.validate(
            method: .sixMinuteRun, in: [main], anchorIndex: 0
        ).isBlocking)
    }

    func testMeasurementScopePersistsWithStableStepIdentities() throws {
        var warmup = step(phase: .warmup)
        warmup.measurementStepID = UUID()
        var effort = step(phase: .main)
        effort.measurementStepID = UUID()
        effort.assessmentMethod = .estimatedVO2Max
        effort.assessmentScope = ATHLTHAssessmentScope(
            area: .chosenSteps,
            selectedStepIDs: [effort.measurementStepID!, warmup.measurementStepID!],
            vo2Protocol: .cooperTwelveMinutes
        )

        let encoded = try JSONEncoder().encode(effort)
        let decoded = try JSONDecoder().decode(
            WorkoutTemplateBlock.self, from: encoded
        )
        XCTAssertEqual(decoded.assessmentMethod, .estimatedVO2Max)
        XCTAssertEqual(decoded.assessmentScope, effort.assessmentScope)
        XCTAssertEqual(decoded.measurementStepID, effort.measurementStepID)

        let renumbered = ATHLTHWorkoutPhasePlacement.renumbered(
            decoded, sequence: 9
        )
        XCTAssertEqual(renumbered.assessmentScope, effort.assessmentScope)
        XCTAssertEqual(renumbered.measurementStepID, effort.measurementStepID)
    }

}
