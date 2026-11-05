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
}
