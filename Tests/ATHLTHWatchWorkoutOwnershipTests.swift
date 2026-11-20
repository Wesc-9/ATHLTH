import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWatchWorkoutOwnershipTests: XCTestCase {
    private func completedResult() -> WatchWorkoutResult {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return WatchWorkoutResult(
            id: UUID(), kind: .running,
            healthKitWorkoutUUID: UUID(),
            startedAt: date, endedAt: date.addingTimeInterval(900),
            duration: 900, activeCalories: 100,
            distanceMeters: 2_200, averageHeartRate: 135,
            maxHeartRate: 158, routePointCount: 0
        )
    }

    func testMatchingSignedInOwnerAcceptsDelayedWatchResult() {
        let owner = UUID()
        XCTAssertTrue(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: owner, signedInUserID: owner
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: owner, signedInUserID: UUID()
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: owner, signedInUserID: nil
        ))
    }

    func testLegacyUnownedWatchResultIsNotSilentlyAssigned() throws {
        let owner = UUID()
        let legacy = completedResult()
        let bytes = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(WatchWorkoutResult.self, from: bytes)
        XCTAssertNil(decoded.accountOwnerID)
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: decoded.accountOwnerID,
            signedInUserID: owner
        ))
    }

    func testOwnerSurvivesWatchResultEncodingAndQueuedDelivery() throws {
        let owner = UUID()
        var result = completedResult()
        result.accountOwnerID = owner
        let bytes = try JSONEncoder().encode([result])
        let decoded = try JSONDecoder().decode([WatchWorkoutResult].self, from: bytes)
        XCTAssertEqual(decoded.first?.accountOwnerID, owner)
        XCTAssertTrue(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: decoded.first?.accountOwnerID,
            signedInUserID: owner
        ))
    }

    func testCompanionLogoutCanExplicitlyClearIdentity() throws {
        let identity = WatchAccountIdentityTransfer(
            ownerID: nil, updatedAt: Date()
        )
        let decoded = try JSONDecoder().decode(
            WatchAccountIdentityTransfer.self,
            from: JSONEncoder().encode(identity)
        )
        XCTAssertNil(decoded.ownerID)
    }
    func testCompletedWatchResultKeepsOriginalATHLTHIdentityOffline() throws {
        var result = completedResult()
        let originalID = UUID()
        result.universalWorkoutID = originalID
        let decoded = try JSONDecoder().decode(
            WatchWorkoutResult.self, from: JSONEncoder().encode(result)
        )
        XCTAssertEqual(decoded.universalWorkoutID, originalID)
        XCTAssertNotEqual(decoded.universalWorkoutID, decoded.id)
        XCTAssertNotEqual(decoded.universalWorkoutID, decoded.healthKitWorkoutUUID)
        XCTAssertNil(completedResult().universalWorkoutID)
    }


    func testSameHealthKitWorkoutCannotBeQueuedWithNewReceipt() {
        let recorded = completedResult()
        var deliveredAgain = completedResult()
        deliveredAgain.healthKitWorkoutUUID = recorded.healthKitWorkoutUUID
        XCTAssertNotEqual(recorded.id, deliveredAgain.id)
        XCTAssertTrue(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            recorded, handledReceiptIDs: [],
            handledOriginalIDs: [], pending: []
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            deliveredAgain, handledReceiptIDs: [],
            handledOriginalIDs: [], pending: [recorded]
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            deliveredAgain, handledReceiptIDs: [recorded.id],
            handledOriginalIDs: [recorded.healthKitWorkoutUUID!],
            pending: []
        ))
    }

    func testRecoveryCollapsesDuplicateOfflineWatchResultDelivery() {
        let first = completedResult()
        var replay = completedResult()
        replay.healthKitWorkoutUUID = first.healthKitWorkoutUUID
        let recovered = ATHLTHWatchWorkoutResultIdentity.restorePending(
            [replay, first],
            handledReceiptIDs: [], handledOriginalIDs: []
        )
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.healthKitWorkoutUUID,
                       first.healthKitWorkoutUUID)
        XCTAssertTrue(ATHLTHWatchWorkoutResultIdentity.restorePending(
            [replay], handledReceiptIDs: [],
            handledOriginalIDs: [first.healthKitWorkoutUUID!]
        ).isEmpty)
    }

    func testLegacySourceFallbackAndTwoDistinctWorkoutsStayDistinct() {
        var first = completedResult()
        var second = completedResult()
        first.healthKitWorkoutUUID = nil
        second.healthKitWorkoutUUID = nil
        let identity = UUID()
        first.universalWorkoutID = identity
        second.universalWorkoutID = identity
        XCTAssertEqual(ATHLTHWatchWorkoutResultIdentity.originalID(first),
                       identity)
        XCTAssertFalse(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            second, handledReceiptIDs: [], handledOriginalIDs: [],
            pending: [first]
        ))
        second.universalWorkoutID = UUID()
        XCTAssertTrue(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            second, handledReceiptIDs: [], handledOriginalIDs: [],
            pending: [first]
        ))
        second.universalWorkoutID = nil
        first.universalWorkoutID = nil
        XCTAssertTrue(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            second, handledReceiptIDs: [], handledOriginalIDs: [],
            pending: [first]
        ), "Legacy unknown originals can use their distinct receipt IDs")
    }

}
