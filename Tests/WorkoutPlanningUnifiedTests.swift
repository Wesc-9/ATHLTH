import Foundation
import XCTest
@testable import ATHLTH

final class WorkoutPlanningUnifiedTests: XCTestCase {
    private func makeWorkout() -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: "Run on Sunday",
            kind: .running,
            scheduledStart: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: nil,
            targetDistanceKilometers: 8.5,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: "Easy run"
        )
    }

    func testManualStandaloneAlwaysOffersSourceSelectionWithAndWithoutDraft() {
        for hasDraft in [false, true] {
            XCTAssertTrue(SessionEditorEntryRouting.requiresSourceChoice(
                isStandalone: true,
                hasExistingWorkout: false,
                hasInitialSource: false,
                isPreparedWorkout: false,
                hasDirectPartner: false,
                hasSavedDraft: hasDraft
            ))
        }
    }

    func testExistingAndPartnerWorkoutsPreserveDirectEditingRoutes() {
        XCTAssertFalse(SessionEditorEntryRouting.requiresSourceChoice(
            isStandalone: false,
            hasExistingWorkout: true,
            hasInitialSource: false,
            isPreparedWorkout: false,
            hasDirectPartner: false,
            hasSavedDraft: true
        ))
        XCTAssertFalse(SessionEditorEntryRouting.requiresSourceChoice(
            isStandalone: true,
            hasExistingWorkout: false,
            hasInitialSource: true,
            isPreparedWorkout: false,
            hasDirectPartner: false,
            hasSavedDraft: true
        ))
        XCTAssertFalse(SessionEditorEntryRouting.requiresSourceChoice(
            isStandalone: true,
            hasExistingWorkout: false,
            hasInitialSource: false,
            isPreparedWorkout: false,
            hasDirectPartner: true,
            hasSavedDraft: true
        ))
    }

    func testPrivateWorkoutProposalDoesNotMutateOriginal() throws {
        let original = makeWorkout()
        var modified = original
        modified.notes = "Intervals instead"
        modified.meetingPoint = PlannedWorkoutMeetingPoint(
            name: "Park", address: "Tromsø", latitude: 69.65, longitude: 18.95
        )
        modified.trainTogetherMode = .physical

        let proposal = WorkoutChangeProposal(
            id: UUID(),
            proposedBy: UUID(),
            ownerID: UUID(),
            original: original,
            proposed: modified,
            submittedAt: Date()
        )

        XCTAssertTrue(proposal.hasChanges)
        XCTAssertNil(proposal.original.meetingPoint)
        let changes = WorkoutChangeComparison.rows(proposal)
        XCTAssertTrue(changes.contains(where: { $0.key == "notes" }))
        XCTAssertTrue(changes.contains(where: { $0.key == "meetingPoint" }))
        XCTAssertTrue(changes.contains(where: { $0.key == "trainTogetherMode" }))

        let stored = try JSONDecoder().decode(
            WorkoutChangeProposal.self,
            from: JSONEncoder().encode(proposal)
        )
        XCTAssertEqual(stored, proposal)
    }

    func testApprovedRevisionTravelsWithDecision() throws {
        var workout = makeWorkout()
        workout.durationMinutes = 65
        let response = WorkoutChangeDecision(
            proposalID: UUID(),
            workoutID: workout.id,
            approved: true,
            approvedWorkout: workout
        )
        let decoded = try JSONDecoder().decode(
            WorkoutChangeDecision.self,
            from: JSONEncoder().encode(response)
        )
        XCTAssertTrue(decoded.approved)
        XCTAssertEqual(decoded.approvedWorkout?.id, workout.id)
        XCTAssertEqual(decoded.approvedWorkout?.durationMinutes, 65)
    }

    func testRejectedProposalHasNoRevision() throws {
        let response = WorkoutChangeDecision(
            proposalID: UUID(),
            workoutID: UUID(),
            approved: false,
            approvedWorkout: nil
        )
        let decoded = try JSONDecoder().decode(
            WorkoutChangeDecision.self,
            from: JSONEncoder().encode(response)
        )
        XCTAssertFalse(decoded.approved)
        XCTAssertNil(decoded.approvedWorkout)
    }
}
