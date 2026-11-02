import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWorkoutDraftRecoveryPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPlanDraftSurvivesRecreatedRunningBlockIdentifiers() {
        XCTAssertTrue(ATHLTHWorkoutDraftRecoveryPolicy.accepts(
            storedSignature: "30/30|first-generated-blocks",
            currentSignature: "30/30|new-generated-blocks",
            context: "plan-abc-day-def-workout-new",
            storedSourceTitle: "30/30 – 20 drag",
            currentSourceTitle: "30/30 – 20 drag",
            storedSourceID: nil,
            currentSourceID: nil,
            savedAt: now.addingTimeInterval(-60),
            now: now
        ))
    }

    func testRecentCatalogCopyRecoversWhenSourceRecipeRegenerated() {
        let source = UUID()
        XCTAssertTrue(ATHLTHWorkoutDraftRecoveryPolicy.accepts(
            storedSignature: "original-timeline-id",
            currentSignature: "regenerated-timeline-id",
            context: "catalog-copy-running-30-30",
            storedSourceTitle: "30/30 – 20 drag",
            currentSourceTitle: "30/30 – 20 drag",
            storedSourceID: source,
            currentSourceID: source,
            savedAt: now.addingTimeInterval(-3_600),
            now: now
        ))
    }

    func testOldSharedScratchDraftWillNotReplaceAnotherWorkout() {
        XCTAssertFalse(ATHLTHWorkoutDraftRecoveryPolicy.accepts(
            storedSignature: "workout-one",
            currentSignature: "workout-two",
            context: "shared-template",
            storedSourceTitle: "Strength Session",
            currentSourceTitle: "30/30 – 20 drag",
            storedSourceID: nil,
            currentSourceID: nil,
            savedAt: now.addingTimeInterval(-30),
            now: now
        ))
    }

    func testUnrelatedSourceIdentityCannotRecover() {
        XCTAssertFalse(ATHLTHWorkoutDraftRecoveryPolicy.accepts(
            storedSignature: "first",
            currentSignature: "second",
            context: "catalog-copy-running-workout",
            storedSourceTitle: "First workout",
            currentSourceTitle: "Second workout",
            storedSourceID: UUID(),
            currentSourceID: UUID(),
            savedAt: now.addingTimeInterval(-60),
            now: now
        ))
    }

    func testDiscardStaleContextMismatchRatherThanReplaceNewWorkout() {
        XCTAssertFalse(ATHLTHWorkoutDraftRecoveryPolicy.accepts(
            storedSignature: "old",
            currentSignature: "new",
            context: "plan-abc-day-def-workout-new",
            storedSourceTitle: "Old workout",
            currentSourceTitle: "New workout",
            storedSourceID: nil,
            currentSourceID: nil,
            savedAt: now.addingTimeInterval(-35 * 24 * 3_600),
            now: now
        ))
    }

    func testMatchingSignatureKeepsOlderStoredDraft() {
        XCTAssertTrue(ATHLTHWorkoutDraftRecoveryPolicy.accepts(
            storedSignature: "stable-saved-workout",
            currentSignature: "stable-saved-workout",
            context: "shared-template",
            storedSourceTitle: nil,
            currentSourceTitle: "Any workout",
            storedSourceID: nil,
            currentSourceID: nil,
            savedAt: now.addingTimeInterval(-50 * 24 * 3_600),
            now: now
        ))
    }

    func testPlanRevisionRefreshDoesNotDiscardUnsavedSteps() {
        XCTAssertTrue(ATHLTHWorkoutDraftRecoveryPolicy.canRestorePlanDraft(
            storedVersion: 17,
            currentVersion: 18,
            hasActualWorkout: true
        ))
        XCTAssertFalse(ATHLTHWorkoutDraftRecoveryPolicy.canRestorePlanDraft(
            storedVersion: 17,
            currentVersion: 18,
            hasActualWorkout: false
        ))
    }

    @MainActor
    func testLegacyIntervalRecipeRoundTripsAsDraftWithoutLosingPauses() throws {
        let source = try XCTUnwrap(
            RunningWorkoutLibraryStore.builtInTemplates.first {
                $0.title == "30/30 – 20 drag"
            }
        )
        let original = source.plannedSession()
        let draft = PlannedSession(
            id: UUID(),
            title: original.title,
            kind: original.kind,
            scheduledStart: nil,
            durationMinutes: original.durationMinutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: original.notes
        )
        var selected = draft
        selected.runningWorkout = original.runningWorkout
        selected.runningWorkouts = original.runningWorkouts

        let encoded = try JSONEncoder().encode(selected)
        let recovered = try JSONDecoder().decode(PlannedSession.self, from: encoded)
        let steps = ATHLTHUnifiedWorkout.editorBlocks(from: recovered)
        XCTAssertEqual(steps.count, 41)
        XCTAssertEqual(steps.first?.resolvedPhase, .warmup)
        XCTAssertEqual(steps.last?.resolvedPhase, .cooldown)
        XCTAssertEqual(
            steps.filter { $0.title == "Pause" || $0.title == "Recovery" }.count,
            19
        )
    }

    func testPreMigrationNamedWorkoutDraftRecoversAfterNewBlockIDs() {
        XCTAssertTrue(ATHLTHWorkoutDraftRecoveryPolicy.accepts(
            storedSignature: "30/30 – 20 drag|old-generated-ids|duration",
            currentSignature: "30/30 – 20 drag|fresh-generated-ids|duration",
            context: "shared-template",
            storedSourceTitle: nil,
            currentSourceTitle: "30/30 – 20 drag",
            storedSourceID: nil,
            currentSourceID: nil,
            savedAt: now.addingTimeInterval(-600),
            now: now
        ))
    }

}
