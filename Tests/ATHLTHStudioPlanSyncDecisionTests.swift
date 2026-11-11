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

    private func makeMinimalPlan() -> TrainingPlan {
        TrainingPlan(
            id: UUID(), ownerID: UUID(), title: "Example plan",
            summary: "", visibility: .privateOnly, version: 1,
            weeks: [], tags: [], createdAt: Date(), updatedAt: Date()
        )
    }
}
