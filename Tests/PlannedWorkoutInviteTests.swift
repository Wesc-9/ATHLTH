import Foundation
import XCTest
@testable import ATHLTH

final class PlannedWorkoutInviteTests: XCTestCase {
    private func makeWorkout() -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: "Sunday run",
            kind: .running,
            scheduledStart: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
    }

    func testTrainTogetherModeIsPreservedAcrossInvitations() throws {
        var session = makeWorkout()
        session.trainTogetherMode = .sameWorkout
        let decoded = try JSONDecoder().decode(
            PlannedSession.self,
            from: JSONEncoder().encode(session)
        )
        XCTAssertEqual(decoded.trainTogetherMode, .sameWorkout)
        XCTAssertNil(decoded.meetingPoint)
        var physical = makeWorkout()
        physical.trainTogetherMode = .physical
        let decodedPhysical = try JSONDecoder().decode(
            PlannedSession.self,
            from: JSONEncoder().encode(physical)
        )
        XCTAssertEqual(decodedPhysical.trainTogetherMode, .physical)
    }

    func testMeetingPointAndReminderSurviveRoundTrip() throws {
        var workout = makeWorkout()
        workout.meetingPoint = PlannedWorkoutMeetingPoint(
            name: "Start", address: "Tromsø",
            latitude: 69.65, longitude: 18.95
        )
        workout.reminderMinutesBefore = 30

        let decoded = try JSONDecoder().decode(
            PlannedSession.self,
            from: JSONEncoder().encode(workout)
        )
        XCTAssertEqual(decoded.meetingPoint, workout.meetingPoint)
        XCTAssertEqual(decoded.reminderMinutesBefore, 30)
        XCTAssertNil(decoded.durationMinutes)
    }

    func testOldWorkoutWithoutLogisticsFieldsStillDecodes() throws {
        let workout = makeWorkout()
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(workout))
            as? [String: Any]
        )
        payload.removeValue(forKey: "meetingPoint")
        payload.removeValue(forKey: "reminderMinutesBefore")
        let data = try JSONSerialization.data(withJSONObject: payload)
        let restored = try JSONDecoder().decode(PlannedSession.self, from: data)
        XCTAssertNil(restored.meetingPoint)
        XCTAssertNil(restored.reminderMinutesBefore)
    }

    func testInviteeExercisePermissionAndPartnerSurviveRoundTrip() throws {
        let partnerID = UUID()
        var workout = makeWorkout()
        workout.invitedPartnerID = partnerID
        workout.allowInviteeExercises = true
        let restored = try JSONDecoder().decode(
            PlannedSession.self,
            from: JSONEncoder().encode(workout)
        )
        XCTAssertEqual(restored.invitedPartnerID, partnerID)
        XCTAssertEqual(restored.allowInviteeExercises, true)
        XCTAssertTrue(
            WorkoutInviteExercisePolicy.canPropose(
                original: workout, proposed: restored
            )
        )
    }

    func testSharedDraftIsInviteableBeforeAnyExercisesAreAdded() throws {
        var draft = makeWorkout()
        let partnerID = UUID()
        draft.scheduledStart = nil // start time is agreed after joint planning
        draft.workoutBlocks = []
        draft.invitedPartnerID = partnerID
        draft.allowInviteeExercises = true
        draft.trainTogetherMode = .physical

        let remote = try JSONDecoder().decode(
            PlannedSession.self, from: JSONEncoder().encode(draft)
        )
        XCTAssertEqual(remote.id, draft.id, "Both athletes use one source ID")
        XCTAssertEqual(remote.invitedPartnerID, partnerID)
        XCTAssertTrue(remote.allowInviteeExercises == true)
        XCTAssertTrue(remote.resolvedWorkoutBlocks.isEmpty)
        XCTAssertTrue(PlannedWorkoutInvitationPresentationState.resolve(
            start: remote.scheduledStart,
            decision: nil,
            organizerCancelled: false
        ).canRespond, "An unscheduled draft must not be marked cancelled")
    }

    func testInviteeCanSuggestAnExerciseInUniversalTimelineOnlyWithPermission() {
        var original = makeWorkout()
        original.workoutBlocks = []
        original.exercises = []

        var proposed = original
        proposed.workoutBlocks = [WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "90/90 Hold",
            exerciseSlug: nil, distanceMeters: nil, repetitions: 10,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )]

        XCTAssertTrue(WorkoutInviteExercisePolicy.hasAddedExercises(
            original: original, proposed: proposed
        ))
        XCTAssertFalse(WorkoutInviteExercisePolicy.canPropose(
            original: original, proposed: proposed
        ), "A recipient cannot bypass invite permissions via workoutBlocks")

        original.allowInviteeExercises = true
        proposed.allowInviteeExercises = true
        XCTAssertTrue(WorkoutInviteExercisePolicy.canPropose(
            original: original, proposed: proposed
        ))
        let proposal = WorkoutChangeProposal(
            id: UUID(), proposedBy: UUID(), ownerID: UUID(),
            original: original, proposed: proposed,
            submittedAt: Date()
        )
        XCTAssertTrue(proposal.hasChanges)
        XCTAssertTrue(WorkoutChangeComparison.rows(proposal).contains {
            $0.key == "workoutBlocks"
        })
        XCTAssertEqual(proposal.workoutID, original.id)
    }

    func testAllowedGuestAdditionNeverChangesOwnerIdentity() throws {
        var original = makeWorkout()
        let partnerID = UUID()
        original.invitedPartnerID = partnerID
        original.allowInviteeExercises = true
        var proposed = original
        proposed.workoutBlocks = [WorkoutTemplateBlock(
            sequence: 1, kind: .exercise, title: "Squat",
            exerciseSlug: nil, distanceMeters: nil, repetitions: 8,
            durationSeconds: nil, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )]
        let restored = try JSONDecoder().decode(
            PlannedSession.self, from: JSONEncoder().encode(proposed)
        )
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.invitedPartnerID, partnerID)
        XCTAssertEqual(restored.allowInviteeExercises, true)
    }

    func testOldWorkoutDefaultsToNoExerciseAdditionPermission() throws {
        let source = makeWorkout()
        let restored = try JSONDecoder().decode(
            PlannedSession.self,
            from: JSONEncoder().encode(source)
        )
        XCTAssertNil(restored.invitedPartnerID)
        XCTAssertNil(restored.allowInviteeExercises)
    }

    func testInvitationResponseIsPreserved() throws {
        let id = UUID()
        let answer = PlannedWorkoutInviteResponse(
            sourceWorkoutID: id, decision: .accepted
        )
        let restored = try JSONDecoder().decode(
            PlannedWorkoutInviteResponse.self,
            from: JSONEncoder().encode(answer)
        )
        XCTAssertEqual(restored.sourceWorkoutID, id)
        XCTAssertEqual(restored.decision, .accepted)
    }
    func testInPersonLobbyCanSwitchToIndependentStart() throws {
        var payload = SocialWorkoutInvitePayload(workout: makeWorkout())
        XCTAssertEqual(payload.resolvedParticipationMode, .physical)
        XCTAssertFalse(payload.resolvedStartIndependently)
        payload.startIndependently = true

        let restored = try JSONDecoder().decode(
            SocialWorkoutInvitePayload.self,
            from: JSONEncoder().encode(payload)
        )
        XCTAssertEqual(restored.resolvedParticipationMode, .physical)
        XCTAssertTrue(restored.resolvedStartIndependently)
    }

    func testLegacySocialInviteDefaultsToSynchronizedStart() throws {
        let payload = SocialWorkoutInvitePayload(workout: makeWorkout())
        let restored = try JSONDecoder().decode(
            SocialWorkoutInvitePayload.self,
            from: JSONEncoder().encode(payload)
        )
        XCTAssertFalse(restored.resolvedStartIndependently)
    }

    func testSocialWorkoutPhaseSeparatesPlanningFromRecording() throws {
        var record = SocialWorkoutSessionRecord(
            id: UUID(),
            creatorID: UUID(),
            title: "Evening run",
            workoutKind: WorkoutKind.running.rawValue,
            status: .active,
            startedAt: Date(),
            endedAt: nil,
            sourceWorkoutID: nil,
            createdAt: Date()
        )

        // Legacy "active" means the invitation is still open.
        XCTAssertEqual(record.resolvedWorkoutPhase, .planned)

        record.workoutPhase = .planned
        let planned = try JSONDecoder().decode(
            SocialWorkoutSessionRecord.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertEqual(planned.resolvedWorkoutPhase, .planned)

        record.workoutPhase = .active
        let recording = try JSONDecoder().decode(
            SocialWorkoutSessionRecord.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertEqual(recording.resolvedWorkoutPhase, .active)

        record.status = .completed
        record.workoutPhase = .completed
        XCTAssertEqual(record.resolvedWorkoutPhase, .completed)
    }

    func testSocialWorkoutPhaseDecodesFromDatabaseField() throws {
        let sessionID = UUID()
        let creatorID = UUID()
        let source = """
        {
          "id": "\(sessionID.uuidString)",
          "creator_id": "\(creatorID.uuidString)",
          "title": "Shared run",
          "workout_kind": "running",
          "status": "active",
          "started_at": 0,
          "created_at": 0,
          "workout_phase": "planned"
        }
        """
        let session = try JSONDecoder().decode(
            SocialWorkoutSessionRecord.self,
            from: Data(source.utf8)
        )
        XCTAssertEqual(session.id, sessionID)
        XCTAssertEqual(session.resolvedWorkoutPhase, .planned)
    }

    func testSocialParticipantReadinessAndActualStartDecode() throws {
        let userID = UUID()
        let sessionID = UUID()
        let source = """
        {
          "id": "\(UUID().uuidString)",
          "session_id": "\(sessionID.uuidString)",
          "user_id": "\(userID.uuidString)",
          "invited_by": "\(UUID().uuidString)",
          "state": "accepted",
          "display_name_snapshot": "Partner",
          "invited_at": 0,
          "ready_at": 0,
          "capture_device": "iphone",
          "workout_started_at": null
        }
        """
        let ready = try JSONDecoder().decode(
            SocialWorkoutParticipantRecord.self,
            from: Data(source.utf8)
        )
        XCTAssertTrue(ready.isReady)
        XCTAssertFalse(ready.isTraining)
        XCTAssertNil(ready.workoutStartedAt)

        var started = ready
        started.workoutStartedAt = Date()
        XCTAssertTrue(started.isTraining)
    }

    func testPastUnansweredInvitationDisplaysCancelled() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(
            PlannedWorkoutInvitationPresentationState.resolve(
                start: start, decision: nil, organizerCancelled: false, now: now
            ), .cancelled
        )
        XCTAssertFalse(
            PlannedWorkoutInvitationPresentationState.resolve(
                start: start, decision: nil, organizerCancelled: false, now: now
            ).canRespond
        )
    }

    func testFutureInviteCanBeAcceptedAndPastAcceptanceIsPreserved() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(
            PlannedWorkoutInvitationPresentationState.resolve(
                start: Date(timeIntervalSince1970: 3_000),
                decision: nil, organizerCancelled: false, now: now
            ), .pending
        )
        XCTAssertEqual(
            PlannedWorkoutInvitationPresentationState.resolve(
                start: start, decision: .accepted, organizerCancelled: false, now: now
            ), .accepted
        )
        XCTAssertEqual(
            PlannedWorkoutInvitationPresentationState.resolve(
                start: start, decision: .declined, organizerCancelled: false, now: now
            ), .declined
        )
        XCTAssertEqual(
            PlannedWorkoutInvitationPresentationState.resolve(
                start: start, decision: .accepted, organizerCancelled: true, now: now
            ), .cancelled
        )
    }

    func testUnscheduledInvitationIsStillPendingWithoutExplicitCancellation() {
        XCTAssertEqual(
            PlannedWorkoutInvitationPresentationState.resolve(
                start: nil, decision: nil, organizerCancelled: false
            ), .pending
        )
    }

    func testWithdrawalPolicyRejectsForgedAndUnrelatedEvents() throws {
        let owner = UUID(), partner = UUID(), other = UUID(), source = UUID()
        func message(sender: UUID, recipient: UUID, version: Int,
                     event: WorkoutInviteLifecycleUpdate? = nil) throws -> DirectMessageRecord {
            let payload = try event.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
            return DirectMessageRecord(
                id: UUID(), conversationID: UUID(), senderID: sender, recipientID: recipient,
                body: nil, attachmentKindRaw: "workout", attachmentTitle: "Workout",
                attachmentSubtitle: nil, attachmentPayload: payload, shareVersion: version,
                sourceObjectID: source, sourceOwnerID: owner, createdAt: Date(),
                readAt: nil, deletedAt: nil)
        }
        let event = WorkoutInviteLifecycleUpdate(sourceWorkoutID: source,
            organizerID: owner, kind: .cancelled, updatedWorkout: nil, occurredAt: Date())
        let valid = try message(sender: owner, recipient: partner, version: 6, event: event)
        let forged = try message(sender: partner, recipient: partner, version: 6, event: event)
        let unrelated = try message(sender: owner, recipient: other, version: 6, event: event)
        XCTAssertNil(PlannedWorkoutWithdrawalPolicy.cancellation(
            in: [forged, unrelated], sourceID: source, organizerID: owner, recipientID: partner))
        XCTAssertEqual(PlannedWorkoutWithdrawalPolicy.cancellation(
            in: [valid, forged, unrelated], sourceID: source, organizerID: owner, recipientID: partner), event)
        let invite = try message(sender: owner, recipient: partner, version: 2)
        XCTAssertEqual(PlannedWorkoutWithdrawalPolicy.invitations(
            in: [invite, invite, forged], sourceID: source, organizerID: owner).count, 1)
    }

    func testWithdrawalOnlyOfferedToOrganizer() {
        var workout = makeWorkout()
        workout.invitedPartnerID = UUID()
        workout.trainTogetherMode = .sameWorkout
        XCTAssertTrue(PlannedWorkoutWithdrawalPolicy.isOrganizerWorkout(workout))
        workout.sharedSourceOwnerID = UUID()
        XCTAssertFalse(PlannedWorkoutWithdrawalPolicy.isOrganizerWorkout(workout))
        workout.sharedSourceOwnerID = nil
        workout.cancelledAt = Date()
        XCTAssertFalse(PlannedWorkoutWithdrawalPolicy.isOrganizerWorkout(workout))
    }

}
