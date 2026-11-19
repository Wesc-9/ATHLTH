import Foundation
import XCTest
@testable import ATHLTH

final class WorkoutDeviceRelayClaimPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func accepts(
        source: String = "ipad",
        target: String = "apple_watch",
        kind: String = "strength",
        payloadTarget: String = "apple_watch",
        payloadKind: String = "strength",
        payloadVersion: Int = 1,
        expiresAt: Date? = nil,
        claimedDeviceID: String? = "device-a",
        expectedDeviceID: String = "device-a",
        completedAt: Date? = nil,
        failedAt: Date? = nil
    ) -> Bool {
        WorkoutDeviceRelayClaimPolicy.accepts(
            source: source,
            target: target,
            kind: kind,
            payloadTarget: payloadTarget,
            payloadKind: payloadKind,
            payloadVersion: payloadVersion,
            expiresAt: expiresAt ?? now.addingTimeInterval(60),
            claimedDeviceID: claimedDeviceID,
            expectedDeviceID: expectedDeviceID,
            completedAt: completedAt,
            failedAt: failedAt,
            now: now
        )
    }

    func testValidIpadCommandIsAccepted() {
        XCTAssertTrue(accepts())
        XCTAssertTrue(accepts(target: "iphone", kind: "run",
                              payloadTarget: "iphone", payloadKind: "run"))
    }

    func testSpoofedSourceOrMismatchedPayloadCannotLaunch() {
        XCTAssertFalse(accepts(source: "iphone"))
        XCTAssertFalse(accepts(source: "unknown"))
        XCTAssertFalse(accepts(payloadTarget: "iphone"))
        XCTAssertFalse(accepts(payloadKind: "walk"))
    }

    func testWrongDeviceOrTerminalClaimCannotLaunch() {
        XCTAssertFalse(accepts(claimedDeviceID: nil))
        XCTAssertFalse(accepts(claimedDeviceID: "device-b"))
        XCTAssertFalse(accepts(expectedDeviceID: ""))
        XCTAssertFalse(accepts(completedAt: now))
        XCTAssertFalse(accepts(failedAt: now))
    }

    func testOnlyConfirmedLaunchMayRetryItsReceipt() {
        let command = UUID()
        let policy = WorkoutDeviceRelayClaimPolicy.self
        XCTAssertEqual(policy.launchDecision(
            commandID: command,
            unacknowledgedLaunchIDs: [command],
            uncertainLaunchIDs: []
        ), .retryConfirmedReceipt)
        XCTAssertEqual(policy.launchDecision(
            commandID: command,
            unacknowledgedLaunchIDs: [],
            uncertainLaunchIDs: []
        ), .validateNewLaunch)
    }

    func testUncertainStartCannotBeAcknowledgedEvenIfAlsoMarkedCompleted() {
        let command = UUID()
        let policy = WorkoutDeviceRelayClaimPolicy.self
        XCTAssertEqual(policy.launchDecision(
            commandID: command,
            unacknowledgedLaunchIDs: [],
            uncertainLaunchIDs: [command]
        ), .holdForDeviceReconciliation)
        XCTAssertEqual(policy.launchDecision(
            commandID: command,
            unacknowledgedLaunchIDs: [command],
            uncertainLaunchIDs: [command]
        ), .holdForDeviceReconciliation)
        XCTAssertEqual(policy.launchDecision(
            commandID: UUID(),
            unacknowledgedLaunchIDs: [],
            uncertainLaunchIDs: [command]
        ), .validateNewLaunch)
    }

    func testExpiredOrUnknownVersionCannotLaunch() {
        XCTAssertFalse(accepts(expiresAt: now))
        XCTAssertFalse(accepts(expiresAt: now.addingTimeInterval(-1)))
        XCTAssertFalse(accepts(payloadVersion: 0))
        XCTAssertFalse(accepts(payloadVersion: 2))
    }

    func testCrashBetweenConfirmedLaunchAndUncertainMarkerCleanup() {
        let confirmed = UUID()
        let unknown = UUID()
        let otherConfirmed = UUID()
        XCTAssertEqual(
            WorkoutDeviceRelayClaimPolicy.resolvedUncertainIDs(
                uncertainIDs: [confirmed, unknown],
                confirmedLaunchIDs: [confirmed, otherConfirmed]
            ), [unknown]
        )
        XCTAssertEqual(
            WorkoutDeviceRelayClaimPolicy.resolvedUncertainIDs(
                uncertainIDs: [unknown],
                confirmedLaunchIDs: []
            ), [unknown]
        )
    }

    func testCorrelatedRelayRequestIdentity() {
        let request = UUID()
        XCTAssertTrue(WorkoutDeviceRelayClaimPolicy.hasMatchingRequestID(
            serverID: request, payloadID: request
        ))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.hasMatchingRequestID(
            serverID: request, payloadID: UUID()
        ))
        // Previously queued v1 payloads did not contain the correlation ID.
        XCTAssertTrue(WorkoutDeviceRelayClaimPolicy.hasMatchingRequestID(
            serverID: request, payloadID: nil
        ))
    }

    func testRejectedGPSRelayCancelsOnlyTheSamePendingRequest() {
        let request = UUID(), unrelated = UUID()
        let policy = ATHLTHRelayedPhoneLaunchCancellationPolicy.self
        XCTAssertTrue(policy.mayCancel(
            requestID: request, pendingID: request,
            hasPendingStart: true, activeRecordingID: nil
        ))
        XCTAssertFalse(policy.mayCancel(
            requestID: request, pendingID: unrelated,
            hasPendingStart: true, activeRecordingID: nil
        ))
        XCTAssertFalse(policy.mayCancel(
            requestID: request, pendingID: nil,
            hasPendingStart: true, activeRecordingID: nil
        ))
        XCTAssertFalse(policy.mayCancel(
            requestID: request, pendingID: request,
            hasPendingStart: false, activeRecordingID: nil
        ))
        XCTAssertFalse(policy.mayCancel(
            requestID: request, pendingID: request,
            hasPendingStart: true, activeRecordingID: request
        ))
    }

    func testSavedIPhoneRecordingRequiresExactRequestOwnerAndSport() {
        let request = UUID()
        let now = Date()
        let policy = WorkoutDeviceRelayClaimPolicy.self
        func confirm(
            target: String = "iphone",
            kind: String = "run",
            token: UUID? = nil,
            recordingKind: String = "run",
            startedAt: Date? = nil,
            ownerMatches: Bool = true,
            failedAt: Date? = nil
        ) -> Bool {
            policy.confirmsIPhoneRecording(
                target: target, kind: kind,
                serverRequestID: request,
                serverCreatedAt: now.addingTimeInterval(-5),
                recordingRequestID: token ?? request,
                recordingKind: recordingKind,
                recordingStartedAt: startedAt ?? now,
                ownerMatches: ownerMatches, failedAt: failedAt
            )
        }
        XCTAssertTrue(confirm())
        XCTAssertTrue(confirm(kind: "walk", recordingKind: "walk"))
        XCTAssertTrue(confirm(kind: "strength", recordingKind: "strength"))
        XCTAssertFalse(confirm(target: "apple_watch"))
        XCTAssertFalse(confirm(kind: "strength", recordingKind: "run"))
        XCTAssertFalse(confirm(token: UUID()))
        XCTAssertFalse(confirm(ownerMatches: false))
        XCTAssertFalse(confirm(failedAt: now))
        XCTAssertFalse(confirm(startedAt: now.addingTimeInterval(-600)))
        XCTAssertFalse(confirm(startedAt: now.addingTimeInterval(600)))
    }

    func testPhoneWorkoutRetainsRemoteIdentityAcrossCheckpointSerialization() throws {
        let now = Date()
        let identity = UUID()
        var workout = PhoneWorkout(
            walking: true, start: now, end: nil,
            lastCheckpoint: now
        )
        workout.relayRequestID = identity
        let decoded = try JSONDecoder().decode(
            PhoneWorkout.self,
            from: JSONEncoder().encode(workout)
        )
        XCTAssertEqual(decoded.relayRequestID, identity)
        XCTAssertTrue(decoded.walking)
    }

    func testLegacyPhoneCheckpointCannotClaimNewRemoteStart() throws {
        let now = Date()
        let original = PhoneWorkout(
            walking: false, start: now, end: nil, lastCheckpoint: now
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)
        ) as? [String: Any])
        json.removeValue(forKey: "relayRequestID")
        let restored = try JSONDecoder().decode(
            PhoneWorkout.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertNil(restored.relayRequestID)
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.confirmsIPhoneRecording(
            target: "iphone", kind: "run", serverRequestID: UUID(),
            serverCreatedAt: now.addingTimeInterval(-5),
            recordingRequestID: restored.relayRequestID,
            recordingKind: "run", recordingStartedAt: restored.start,
            ownerMatches: true, failedAt: nil
        ))
    }

    func testStrengthCheckpointRetainsExactRemoteRequestIdentity() throws {
        let request = UUID()
        var workout = StrengthWorkoutLog(
            id: UUID(), plannedSessionID: nil, watchSessionID: nil,
            captureDevice: .iPhone, trackingMode: .simple,
            title: "Remote strength", startedAt: Date(), endedAt: nil,
            exercises: [],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil, duration: nil,
                activeCalories: nil, averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
        workout.relayRequestID = request
        let restored = try JSONDecoder().decode(
            StrengthWorkoutLog.self,
            from: JSONEncoder().encode(workout)
        )
        XCTAssertEqual(restored.relayRequestID, request)
        XCTAssertEqual(restored.captureDevice, .iPhone)
    }

    func testCompletedWatchResultResolvesOnlyMatchingAccountKindAndRequest() {
        let now = Date()
        let id = UUID(), owner = UUID()
        var result = WatchWorkoutResult(
            id: UUID(), kind: .running, healthKitWorkoutUUID: UUID(),
            startedAt: now, endedAt: now.addingTimeInterval(120),
            duration: 120, activeCalories: 20, distanceMeters: 450,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 0
        )
        result.relayRequestID = id
        result.accountOwnerID = owner
        let receipt = WatchRemoteLaunchCompletionReceipt(result: result)
        let policy = WorkoutDeviceRelayClaimPolicy.self
        func verified(
            target: String = "apple_watch", kind: String = "run",
            request: UUID? = nil, signedIn: UUID? = nil,
            failure: Date? = nil, createdAt: Date? = nil
        ) -> Bool {
            policy.confirmsCompletedWatchLaunch(
                target: target, kind: kind,
                serverRequestID: request ?? id,
                serverCreatedAt: createdAt ?? now.addingTimeInterval(-5),
                signedInOwnerID: signedIn ?? owner, receipt: receipt, failedAt: failure
            )
        }
        XCTAssertNotNil(receipt)
        XCTAssertTrue(verified())
        XCTAssertFalse(verified(target: "iphone"))
        XCTAssertFalse(verified(kind: "walk"))
        XCTAssertFalse(verified(kind: "strength"))
        XCTAssertFalse(verified(request: UUID()))
        XCTAssertFalse(verified(signedIn: UUID()))
        XCTAssertFalse(verified(failure: now))
        XCTAssertFalse(verified(createdAt: now.addingTimeInterval(300)))
    }

    func testCompletionProofRequiresSavedHealthKitUUIDAndOwner() {
        let now = Date()
        var result = WatchWorkoutResult(
            id: UUID(), kind: .strength, healthKitWorkoutUUID: nil,
            startedAt: now, endedAt: now.addingTimeInterval(20),
            duration: 20, activeCalories: 12, distanceMeters: 0,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 0
        )
        result.relayRequestID = UUID()
        result.accountOwnerID = UUID()
        XCTAssertNil(WatchRemoteLaunchCompletionReceipt(result: result))
        result.healthKitWorkoutUUID = UUID()
        result.accountOwnerID = nil
        XCTAssertNil(WatchRemoteLaunchCompletionReceipt(result: result))
        result.accountOwnerID = UUID()
        result.relayRequestID = nil
        XCTAssertNil(WatchRemoteLaunchCompletionReceipt(result: result))
        result.relayRequestID = UUID()
        XCTAssertNotNil(WatchRemoteLaunchCompletionReceipt(result: result))
    }

    func testUnknownWatchStartRequiresExactLiveRequestIdentity() {
        let request = UUID()
        let confirm = WorkoutDeviceRelayClaimPolicy.confirmsUncertainWatchLaunch
        XCTAssertTrue(confirm(
            target: "apple_watch", serverRequestID: request,
            watchRequestID: request, failedAt: nil
        ))
        XCTAssertFalse(confirm(
            target: "apple_watch", serverRequestID: request,
            watchRequestID: UUID(), failedAt: nil
        ))
        XCTAssertFalse(confirm(
            target: "apple_watch", serverRequestID: request,
            watchRequestID: nil, failedAt: nil
        ))
        XCTAssertFalse(confirm(
            target: "iphone", serverRequestID: request,
            watchRequestID: request, failedAt: nil
        ))
        XCTAssertFalse(confirm(
            target: "apple_watch", serverRequestID: request,
            watchRequestID: request, failedAt: Date()
        ))
    }

    func testTerminalFailureTransitionNeverOverridesConfirmedOrFailedStart() {
        let now = Date()
        let policy = WorkoutDeviceRelayClaimPolicy.self
        XCTAssertTrue(policy.mayTransitionToFailure(
            completedAt: nil, failedAt: nil
        ))
        XCTAssertFalse(policy.mayTransitionToFailure(
            completedAt: now, failedAt: nil
        ))
        XCTAssertFalse(policy.mayTransitionToFailure(
            completedAt: nil, failedAt: now
        ))
        XCTAssertFalse(policy.mayTransitionToFailure(
            completedAt: now, failedAt: now
        ))
    }

    func testRelayClaimRejectsMultipleServerRows() {
        XCTAssertTrue(WorkoutDeviceRelayClaimPolicy.hasValidClaimBatchSize(0))
        XCTAssertTrue(WorkoutDeviceRelayClaimPolicy.hasValidClaimBatchSize(1))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.hasValidClaimBatchSize(2))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.hasValidClaimBatchSize(12))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.hasValidClaimBatchSize(-1))
    }

    func testServerCompletionReconciliationRequiresConfirmedMatchingRow() {
        let id = UUID()
        let now = Date()
        let verify = WorkoutDeviceRelayClaimPolicy.confirmsPersistedCompletion
        XCTAssertTrue(verify([(id: id, completedAt: now, failedAt: nil)], commandID: id))
        XCTAssertFalse(verify([], commandID: id))
        XCTAssertFalse(verify([(id: UUID(), completedAt: now, failedAt: nil)], commandID: id))
        XCTAssertFalse(verify([(id: id, completedAt: nil, failedAt: nil)], commandID: id))
        XCTAssertFalse(verify([(id: id, completedAt: now, failedAt: now)], commandID: id))
        XCTAssertFalse(verify([(id: id, completedAt: now, failedAt: nil),
                               (id: id, completedAt: now, failedAt: nil)], commandID: id))
    }

    func testReceiptRequiresExactlyOneMatchingServerRow() {
        let commandID = UUID()
        XCTAssertTrue(WorkoutDeviceRelayClaimPolicy.confirmsReceipt(
            [commandID], commandID: commandID
        ))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.confirmsReceipt(
            [], commandID: commandID
        ))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.confirmsReceipt(
            [UUID()], commandID: commandID
        ))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.confirmsReceipt(
            [commandID, commandID], commandID: commandID
        ))
    }
    func testRelayCorrelationRequiresExactEmbeddedRequestID() {
        let request = UUID()
        XCTAssertTrue(WorkoutDeviceRelayClaimPolicy.hasMatchingRequestID(
            serverID: request, payloadID: request
        ))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.hasMatchingRequestID(
            serverID: request, payloadID: nil
        ))
        XCTAssertFalse(WorkoutDeviceRelayClaimPolicy.hasMatchingRequestID(
            serverID: request, payloadID: UUID()
        ))
    }

    func testClaimRejectsNonFiniteExpiry() {
        XCTAssertFalse(accepts(expiresAt: Date(timeIntervalSince1970: .infinity)))
        XCTAssertFalse(accepts(expiresAt: Date(timeIntervalSince1970: -.infinity)))
        XCTAssertFalse(accepts(expiresAt: now))
    }

}
