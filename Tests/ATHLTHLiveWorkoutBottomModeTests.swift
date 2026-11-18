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
}
