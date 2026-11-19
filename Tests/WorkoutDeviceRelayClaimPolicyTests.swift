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
}
