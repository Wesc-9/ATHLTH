import XCTest
@testable import ATHLTH

final class ATHLTHStudioPlanSyncDecisionTests: XCTestCase {
    typealias Decision = ATHLTHStudioPlanSyncDecision
    let acknowledgement = Decision.Acknowledgement(revision: 4, fingerprint: "initial")

    func testNewPlanIsUploadedWithoutRemoteRevision() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "new", remoteFingerprint: nil,
                remoteRevision: nil, acknowledged: nil
            ), .upload(expectedRevision: 0)
        )
    }

    func testNewRemotePlanIsDownloaded() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: nil, remoteFingerprint: "new",
                remoteRevision: 1, acknowledged: nil
            ), .download
        )
    }

    func testBothUnsynchronizedVersionsRequireExplicitConflictResolution() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "local", remoteFingerprint: "remote",
                remoteRevision: 1, acknowledged: nil
            ), .conflict
        )
    }

    func testLocalOnlyChangesUploadWithExpectedRevision() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "locally edited", remoteFingerprint: "initial",
                remoteRevision: 4, acknowledged: acknowledgement
            ), .upload(expectedRevision: 4)
        )
    }

    func testRemoteOnlyChangesDownload() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "initial", remoteFingerprint: "elsewhere edited",
                remoteRevision: 5, acknowledged: acknowledgement
            ), .download
        )
    }

    func testConcurrentChangesNeverAutoOverwrite() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "local", remoteFingerprint: "remote",
                remoteRevision: 5, acknowledged: acknowledgement
            ), .conflict
        )
    }

    func testRemoteDeletionCannotBeSilentlyRecreated() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "initial", remoteFingerprint: nil,
                remoteRevision: nil, acknowledged: acknowledgement
            ), .conflict
        )
    }

    func testLocalDeletionCannotBeSilentlyRecreated() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: nil, remoteFingerprint: "initial",
                remoteRevision: 4, acknowledged: acknowledgement
            ), .conflict
        )
    }

    @MainActor
    func testAccountCopyRemovesInjuryDetailsAndPrivateNotes() {
        var plan = makeMinimalPlan()
        plan.summary = "Private medical details"
        plan.builderProfile = TrainingPlanBuilderProfile(
            mode: .basic, primaryFocus: .running, goal: .improveFitness,
            goalDetail: "Private goal notes", sessionsPerWeek: 3,
            preferredDayIndexes: [1, 3, 5],
            injuriesOrLimitations: "Knee injury"
        )
        let copy = ATHLTHStudioPlanSyncStore.accountCopy(of: plan)
        XCTAssertNil(copy.builderProfile?.injuriesOrLimitations)
        XCTAssertNil(copy.builderProfile?.goalDetail)
        XCTAssertEqual(copy.summary, "")
        XCTAssertEqual(plan.builderProfile?.injuriesOrLimitations, "Knee injury")
        XCTAssertEqual(copy.id, plan.id)
        XCTAssertEqual(copy.ownerID, plan.ownerID)
    }

    @MainActor
    func testAccountCopyPreservesOriginalAndDoesNotImportOtherAccountNotes() {
        var plan = makeMinimalPlan()
        plan.summary = "Local note"
        let cloud = ATHLTHStudioPlanSyncStore.accountCopy(of: plan)
        let restored = ATHLTHStudioPlanSyncStore.restoringDeviceOnlyFields(
            from: plan, into: cloud
        )
        XCTAssertEqual(restored.summary, "Local note")
        XCTAssertEqual(cloud.summary, "")
        var other = cloud
        other.ownerID = UUID()
        let rejected = ATHLTHStudioPlanSyncStore.restoringDeviceOnlyFields(
            from: plan, into: other
        )
        XCTAssertEqual(rejected.summary, "")
    }

    @MainActor
    func testBasicAndAdvancedBothExcludeSessionNotesWithoutLosingWorkout() {
        for mode in [TrainingPlanBuilderMode.basic, .advanced] {
            var plan = makeMinimalPlan()
            plan.builderProfile = TrainingPlanBuilderProfile(
                mode: mode,
                primaryFocus: .running,
                goal: .improveFitness,
                sessionsPerWeek: 2,
                preferredDayIndexes: [1, 4],
                injuriesOrLimitations: "Private injury note"
            )
            var workout = PlannedSession(
                id: UUID(), title: "Easy run", kind: .running,
                scheduledStart: nil, durationMinutes: 30,
                targetDistanceKilometers: 5, targetPaceSecondsPerKilometer: nil,
                routeID: nil, exercises: [], notes: "Private session note"
            )
            workout.recoveryOriginalExercises = []
            workout.recoveryAdjustedExercises = []
            let day = TrainingPlanDay(
                id: UUID(), dayIndex: 1, title: "Monday", sessions: [workout]
            )
            plan.weeks = [TrainingPlanWeek(
                id: UUID(), weekNumber: 1, title: "Week one", days: [day]
            )]

            let cloud = ATHLTHStudioPlanSyncStore.accountCopy(of: plan)
            XCTAssertNil(cloud.builderProfile?.injuriesOrLimitations)
            XCTAssertNil(cloud.weeks[0].days[0].sessions[0].notes)
            XCTAssertNil(cloud.weeks[0].days[0].sessions[0].recoveryOriginalExercises)
            XCTAssertNil(cloud.weeks[0].days[0].sessions[0].recoveryAdjustedExercises)
            XCTAssertEqual(cloud.weeks[0].days[0].sessions[0].id, workout.id)
            XCTAssertEqual(cloud.weeks[0].days[0].sessions[0].durationMinutes, 30)
            XCTAssertEqual(plan.weeks[0].days[0].sessions[0].notes, "Private session note")

            let restored = ATHLTHStudioPlanSyncStore.restoringDeviceOnlyFields(
                from: plan, into: cloud
            )
            XCTAssertEqual(
                restored.weeks[0].days[0].sessions[0].notes, "Private session note"
            )
            XCTAssertNotNil(restored.weeks[0].days[0].sessions[0].recoveryOriginalExercises)
            XCTAssertNotNil(restored.weeks[0].days[0].sessions[0].recoveryAdjustedExercises)
            XCTAssertEqual(
                restored.builderProfile?.injuriesOrLimitations, "Private injury note"
            )
        }
    }

    @MainActor
    func testLocalPrivateNotesDoNotChangeAccountFingerprint() throws {
        var plan = makeMinimalPlan()
        plan.builderProfile = TrainingPlanBuilderProfile(
            mode: .advanced,
            primaryFocus: .running,
            goal: .improveFitness,
            sessionsPerWeek: 3,
            preferredDayIndexes: [1, 3, 5],
            injuriesOrLimitations: "Private injury"
        )
        let initial = try ATHLTHStudioPlanSyncStore.accountFingerprint(for: plan)
        plan.summary = "Private note edited"
        plan.builderProfile?.injuriesOrLimitations = "New private injury detail"
        plan.builderProfile?.goalDetail = "Another private detail"
        plan.updatedAt = Date().addingTimeInterval(120)
        plan.version += 1
        XCTAssertEqual(
            try ATHLTHStudioPlanSyncStore.accountFingerprint(for: plan),
            initial,
            "Changing only local notes must not create a remote conflict"
        )
    }

    @MainActor
    func testTrainingPrescriptionChangeUpdatesAccountFingerprint() throws {
        var plan = makeMinimalPlan()
        let before = try ATHLTHStudioPlanSyncStore.accountFingerprint(for: plan)
        plan.title = "New training plan title"
        XCTAssertNotEqual(
            try ATHLTHStudioPlanSyncStore.accountFingerprint(for: plan),
            before,
            "Shared content changes must still be synchronized"
        )
    }

    @MainActor
    func testEditsAfterUploadRequireAnotherSyncPass() throws {
        var plan = makeMinimalPlan()
        let uploaded = try ATHLTHStudioPlanSyncStore.accountFingerprint(for: plan)
        XCTAssertFalse(try ATHLTHStudioPlanSyncStore.needsResyncAfterUpload(
            uploadedFingerprint: uploaded, currentPlan: plan
        ))

        plan.title = "Changed while upload was in progress"
        XCTAssertTrue(try ATHLTHStudioPlanSyncStore.needsResyncAfterUpload(
            uploadedFingerprint: uploaded, currentPlan: plan
        ))
        XCTAssertTrue(try ATHLTHStudioPlanSyncStore.needsResyncAfterUpload(
            uploadedFingerprint: uploaded, currentPlan: nil
        ))
    }

    @MainActor
    func testPrivateNoteEditedDuringUploadDoesNotRequireResync() throws {
        var plan = makeMinimalPlan()
        let uploaded = try ATHLTHStudioPlanSyncStore.accountFingerprint(for: plan)
        plan.summary = "Local note changed during upload"
        plan.updatedAt = Date().addingTimeInterval(60)
        plan.version += 1
        XCTAssertFalse(try ATHLTHStudioPlanSyncStore.needsResyncAfterUpload(
            uploadedFingerprint: uploaded, currentPlan: plan
        ))
    }

    private func makeMinimalPlan() -> TrainingPlan {
        TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Example plan",
            summary: "", visibility: .privateOnly, version: 1,
            weeks: [], tags: [], createdAt: Date(), updatedAt: Date()
        )
    }
}
