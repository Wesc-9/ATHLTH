import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHLiveWorkoutAccessTests: XCTestCase {
    func testSharingIsOffByDefaultAndNeverGrantsUnknownSessions() {
        let state = ATHLTHCrossDeviceWorkoutStore()
        XCTAssertFalse(state.shareNextWorkout)
        XCTAssertFalse(state.isSharingActiveSession)
        XCTAssertFalse(state.isApprovedForSession(UUID()))
    }

    func testSignOutClearsAllConsentAndRequestState() {
        let state = ATHLTHCrossDeviceWorkoutStore()
        state.prepareOneWorkoutSharing(true)
        state.clearLocalState()
        XCTAssertFalse(state.shareNextWorkout)
        XCTAssertFalse(state.isSharingActiveSession)
        XCTAssertNil(state.incomingRequest)
        XCTAssertNil(state.remote)
        XCTAssertEqual(state.outgoingRequestState, .idle)
    }

    func testRequestIsNotAnApproval() throws {
        let req = ATHLTHLiveViewRequest(
            userID: UUID(), requestID: UUID(),
            requestedAt: Date(), expiresAt: Date().addingTimeInterval(120),
            status: "pending", respondedAt: nil,
            approvedSessionID: nil
        )
        XCTAssertTrue(req.isPending)
        XCTAssertNil(req.approvedSessionID)
        let decoded = try JSONDecoder().decode(
            ATHLTHLiveViewRequest.self,
            from: JSONEncoder().encode(req)
        )
        XCTAssertEqual(decoded.requestID, req.requestID)
        XCTAssertEqual(decoded.status, "pending")
        XCTAssertNil(decoded.approvedSessionID)
    }

    func testExpiredOrDeclinedRequestsNeverRemainPending() {
        let expired = ATHLTHLiveViewRequest(
            userID: UUID(), requestID: UUID(),
            requestedAt: Date().addingTimeInterval(-180),
            expiresAt: Date().addingTimeInterval(-60),
            status: "pending", respondedAt: nil,
            approvedSessionID: nil
        )
        var declined = expired
        declined.status = "denied"
        XCTAssertFalse(expired.isPending)
        XCTAssertFalse(declined.isPending)
    }

    func testRichSessionPayloadStillUsesOnlyOptionalSensorEvidence() throws {
        var snapshot = ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: UUID(), kind: "running", title: "4 × 4",
            startedAt: .now, elapsedSeconds: 420,
            distanceMeters: 1_800, currentStep: "Effort 2",
            nextStep: "Recovery", completedSets: nil, totalSets: nil
        )
        snapshot.runningSteps = [
            ATHLTHLiveWorkoutStage(
                index: 0, title: "Warm-up", phase: "warmup",
                durationSeconds: 600, distanceMeters: nil
            ),
            ATHLTHLiveWorkoutStage(
                index: 1, title: "Effort", phase: "main",
                durationSeconds: 240, distanceMeters: nil
            )
        ]
        snapshot.runningStepIndex = 1
        snapshot.ghostRaceTitle = "Race opponent"
        snapshot.ghostDistanceDeltaMeters = 42
        let roundTrip = try JSONDecoder().decode(
            ATHLTHCrossDeviceWorkoutSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(roundTrip.runningSteps?.count, 2)
        XCTAssertEqual(roundTrip.runningStepIndex, 1)
        XCTAssertEqual(roundTrip.ghostDistanceDeltaMeters, 42)
        XCTAssertNil(roundTrip.heartRateBPM)
        XCTAssertNil(roundTrip.spotifyPlaying)
    }
}
