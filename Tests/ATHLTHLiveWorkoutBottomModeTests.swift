import SwiftUI
import XCTest
@testable import ATHLTH

/// Phase 2: every phase has one explicit next command and the control
/// surface never equates countdown completion with a recorded strength set.
final class ATHLTHLiveWorkoutBottomModeTests: XCTestCase {
    func testRunningModesAlwaysOfferProgressionOrAddingIntervals() {
        let modes: [ATHLTHLiveWorkoutBottomMode] = [
            .runningMain, .runningInterval, .runningNext, .runningFree
        ]
        XCTAssertEqual(Set(modes.map(\.primarySymbol)),
                       Set(["play.fill", "arrow.right.circle.fill", "plus.circle.fill"]))
        XCTAssertTrue(modes.allSatisfy { !$0.primaryTitle.isEmpty })
        XCTAssertTrue(modes.allSatisfy { $0.secondaryTitle == nil })
        XCTAssertTrue(modes.allSatisfy { !$0.recordsCompletedSet })
    }

    func testStrengthRequiresExplicitCompletion() {
        XCTAssertEqual(ATHLTHLiveWorkoutBottomMode.strengthReady.primarySymbol,
                       "play.fill")
        XCTAssertTrue(ATHLTHLiveWorkoutBottomMode.strengthWorking.recordsCompletedSet)
        XCTAssertFalse(ATHLTHLiveWorkoutBottomMode.strengthReady.recordsCompletedSet)
        XCTAssertFalse(ATHLTHLiveWorkoutBottomMode.strengthRest.recordsCompletedSet)
        XCTAssertFalse(ATHLTHLiveWorkoutBottomMode.strengthExerciseRest.recordsCompletedSet)
        XCTAssertFalse(ATHLTHLiveWorkoutBottomMode.strengthNextExercise.recordsCompletedSet)
        XCTAssertFalse(ATHLTHLiveWorkoutBottomMode.strengthFinish.recordsCompletedSet)
    }

    func testRestHasIndependentPlusThirtySecondsCommand() {
        XCTAssertEqual(
            ATHLTHLiveWorkoutBottomMode.strengthRest.secondarySymbol, "plus")
        XCTAssertEqual(ATHLTHLiveWorkoutBottomMode.strengthRest.primarySymbol,
                       "play.fill")
        XCTAssertEqual(ATHLTHLiveWorkoutBottomMode.strengthExerciseRest.primarySymbol,
                       "arrow.right.circle.fill")
        XCTAssertEqual(ATHLTHLiveWorkoutBottomMode.strengthExerciseRest.secondarySymbol,
                       "plus")
        XCTAssertNotNil(ATHLTHLiveWorkoutBottomMode.strengthRest.secondaryTitle)
    }

    func testStrengthTransitionUsesNextExerciseInsteadOfCompletingMissingSets() {
        XCTAssertEqual(
            ATHLTHLiveWorkoutBottomMode.strengthNextExercise.primarySymbol,
            "arrow.right.circle.fill")
        XCTAssertEqual(ATHLTHLiveWorkoutBottomMode.strengthFinish.primarySymbol,
                       "stop.circle.fill")
        XCTAssertFalse(ATHLTHLiveWorkoutBottomMode.strengthNextExercise.recordsCompletedSet)
    }

    func testSharedDockSupportsRunningAndStrengthDetailCards() {
        let run = ATHLTHLiveWorkoutBottomDock(
            mode: .runningInterval,
            onPrimary: {}
        ) { EmptyView() }
        let strength = ATHLTHLiveWorkoutBottomDock(
            mode: .strengthWorking,
            onPrimary: {},
            onSecondary: {}
        ) { Text("Set data") }
        XCTAssertEqual(run.mode, .runningInterval)
        XCTAssertEqual(strength.mode, .strengthWorking)
        XCTAssertNotNil(strength.onSecondary)
    }

    func testStructuredSportsUseOneDockWithSportSpecificActions() {
        let modes: [ATHLTHWorkoutSportMode] = [
            .running, .walking, .strength, .cycling, .rowing, .stairClimber,
            .hiit, .circuit, .functional, .yoga, .mobility, .sports,
            .other, .recovery, .instructions
        ]
        for sport in modes {
            let mode = ATHLTHLiveWorkoutBottomMode.structuredActivity(
                sport, isFinalStep: false
            )
            XCTAssertEqual(mode.phaseTitle, sport.title.uppercased())
            XCTAssertEqual(mode.primaryTitle, sport.nextActionTitle)
            XCTAssertEqual(mode.primarySymbol, "checkmark.circle.fill")
            XCTAssertEqual(mode.secondarySymbol, "stop.circle")
            XCTAssertNotNil(mode.secondaryTitle)
            XCTAssertFalse(mode.recordsCompletedSet)
            let final = ATHLTHLiveWorkoutBottomMode.structuredActivity(
                sport, isFinalStep: true
            )
            XCTAssertNotEqual(final.primaryTitle, "")
            XCTAssertEqual(final.secondarySymbol, mode.secondarySymbol)
        }
    }

    func testSharedDockSupportsStructuredSportActions() {
        let dock = ATHLTHLiveWorkoutBottomDock(
            mode: .structuredActivity(.cycling, isFinalStep: false),
            subtitle: "Cycling interval",
            onPrimary: {},
            onSecondary: {}
        ) { Text("1 / 4") }
        XCTAssertNotNil(dock.onSecondary)
        XCTAssertEqual(dock.mode.primaryTitle,
                       ATHLTHWorkoutSportMode.cycling.nextActionTitle)
    }


    func testManualQuickTimerSharesDockButCannotRecordStrengthSet() {
        let sports: [ATHLTHWorkoutSportMode] = [
            .running, .walking, .strength, .cycling, .rowing, .stairClimber,
            .hiit, .circuit, .functional, .yoga, .mobility, .sports, .other
        ]
        for sport in sports {
            let paused = ATHLTHLiveWorkoutBottomMode.manualTimed(
                sport, isPaused: true
            )
            let active = ATHLTHLiveWorkoutBottomMode.manualTimed(
                sport, isPaused: false
            )
            XCTAssertEqual(paused.phaseTitle, sport.title.uppercased())
            XCTAssertEqual(paused.secondarySymbol, "play.fill")
            XCTAssertEqual(active.secondarySymbol, "pause.fill")
            XCTAssertEqual(paused.primarySymbol, "checkmark.circle.fill")
            XCTAssertNotNil(paused.secondaryTitle)
            XCTAssertFalse(paused.recordsCompletedSet)
            XCTAssertFalse(active.recordsCompletedSet)
        }
        let dock = ATHLTHLiveWorkoutBottomDock(
            mode: .manualTimed(.cycling, isPaused: true),
            primaryDisabled: true,
            secondaryDisabled: true,
            onPrimary: {},
            onSecondary: {}
        ) { Text("Manual timing") }
        XCTAssertTrue(dock.primaryDisabled)
        XCTAssertTrue(dock.secondaryDisabled)
    }

}
