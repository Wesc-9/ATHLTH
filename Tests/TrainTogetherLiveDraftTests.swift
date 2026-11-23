import Foundation
import XCTest
@testable import ATHLTH

final class TrainTogetherLiveDraftTests: XCTestCase {
    private func workout(kind: WorkoutKind) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: "Felles økt",
            kind: kind,
            scheduledStart: nil,
            durationMinutes: 45,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }

    private func decodedDraft(
        workout: PlannedSession,
        ownerApproved: Int?,
        partnerApproved: Int?,
        editMode: String
    ) throws -> TrainTogetherLiveDraft {
        let snapshot = try XCTUnwrap(
            String(data: JSONEncoder().encode(workout), encoding: .utf8)
        )
        let payload: [String: Any] = [
            "source_workout_id": workout.id.uuidString,
            "owner_id": UUID().uuidString,
            "partner_id": UUID().uuidString,
            "edit_mode": editMode,
            "participation_mode": "remote",
            "workout_snapshot": snapshot,
            "revision": 4,
            "owner_approved_revision": ownerApproved as Any? ?? NSNull(),
            "partner_approved_revision": partnerApproved as Any? ?? NSNull()
        ]
        return try JSONDecoder().decode(
            TrainTogetherLiveDraft.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    func testBothMustApproveTheSameRevisionBeforeReady() throws {
        let session = workout(kind: .running)
        let pending = try decodedDraft(
            workout: session, ownerApproved: 4, partnerApproved: 3,
            editMode: "collaborative"
        )
        XCTAssertTrue(pending.ownerApproved)
        XCTAssertFalse(pending.partnerApproved)
        XCTAssertFalse(pending.bothApproved)
        let approved = try decodedDraft(
            workout: session, ownerApproved: 4, partnerApproved: 4,
            editMode: "collaborative"
        )
        XCTAssertTrue(approved.bothApproved)
    }

    func testReadOnlyInviteKeepsWorkoutVisible() throws {
        let session = workout(kind: .strength)
        let draft = try decodedDraft(
            workout: session, ownerApproved: nil, partnerApproved: nil,
            editMode: "view_only"
        )
        XCTAssertFalse(draft.isCollaborative)
        XCTAssertEqual(draft.workout?.id, session.id)
    }

    func testPlanningModelAcceptsEveryWorkoutKind() throws {
        for kind: WorkoutKind in [.running, .walking, .strength,
                                  .mobility, .recovery, .custom] {
            let session = workout(kind: kind)
            let draft = try decodedDraft(
                workout: session, ownerApproved: nil, partnerApproved: nil,
                editMode: "collaborative"
            )
            XCTAssertEqual(draft.workout?.kind, kind)
        }
    }

    @MainActor
    func testSharedEditorPreservesInvitationIdentityAndDate() {
        var original = workout(kind: .running)
        original.scheduledStart = Date(timeIntervalSince1970: 1_800_000_000)
        original.invitedPartnerID = UUID()
        original.allowInviteeExercises = false
        original.notes = "Meeting instructions"
        var edited = workout(kind: .strength)
        edited.title = "New recipe"
        edited.durationMinutes = 30
        let result = TrainTogetherLiveDraftStore.mergingEditorRecipe(edited, into: original)
        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.scheduledStart, original.scheduledStart)
        XCTAssertEqual(result.invitedPartnerID, original.invitedPartnerID)
        XCTAssertEqual(result.allowInviteeExercises, false)
        XCTAssertEqual(result.notes, original.notes)
        XCTAssertEqual(result.title, edited.title)
        XCTAssertEqual(result.durationMinutes, edited.durationMinutes)
    }

    func testRoomPushRequiresRecipientAndExactEntityType() {
        let source = UUID()
        let user = UUID()
        let payload: [AnyHashable: Any] = [
            "athlth_entity_type": "shared_workout_room",
            "athlth_kind": "train_together_chat",
            "athlth_entity_id": source.uuidString,
            "athlth_recipient_id": user.uuidString
        ]
        XCTAssertEqual(ATHLTHSharedWorkoutRoomRoute.resolve(userInfo: payload)?.sourceID, source)
        XCTAssertEqual(ATHLTHSharedWorkoutRoomRoute.resolve(userInfo: payload)?.recipientID, user)
        var missing = payload
        missing.removeValue(forKey: "athlth_recipient_id")
        XCTAssertNil(ATHLTHSharedWorkoutRoomRoute.resolve(userInfo: missing))
        var foreign = payload
        foreign["athlth_entity_type"] = "train_together_post"
        XCTAssertNil(ATHLTHSharedWorkoutRoomRoute.resolve(userInfo: foreign))
    }

    func testSharedProgressCountsCompletionNotExerciseOrder() {
        let progress = SocialWorkoutProgress.counted(planned: ["d", "a", "c", "b"], completed: Set(["b", "d", "unknown"]))
        XCTAssertEqual(progress?.completed, 2)
        XCTAssertEqual(progress?.total, 4)
        XCTAssertEqual(progress?.fraction, 0.5)
        XCTAssertNil(SocialWorkoutProgress.counted(planned: [String](), completed: Set<String>()))
        XCTAssertEqual(SocialWorkoutProgress.counted(planned: ["a", "a", "b"], completed: Set(["a"]))?.total, 2)
    }

    func testRemoteSessionCanChooseSynchronizedStart() throws {
        var payload = SocialWorkoutInvitePayload(
            workout: workout(kind: .running),
            participationMode: .remote
        )
        // Older remote invitations without an explicit field retain
        // independent starts. Newly approved ones choose false.
        XCTAssertTrue(payload.resolvedStartIndependently)
        payload.startIndependently = false
        let restored = try JSONDecoder().decode(
            SocialWorkoutInvitePayload.self,
            from: JSONEncoder().encode(payload)
        )
        XCTAssertFalse(restored.resolvedStartIndependently)
    }
}
