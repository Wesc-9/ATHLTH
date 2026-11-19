import Foundation
import XCTest
@testable import ATHLTH

final class AppleWatchConnectionPolicyTests: XCTestCase {
    func testRecentWatchAcknowledgementIsFreshOnlyForTwoMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: nil,
            now: now
        ))
        XCTAssertTrue(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: now.addingTimeInterval(-119),
            now: now
        ))
        XCTAssertTrue(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: now.addingTimeInterval(-120),
            now: now
        ))
        XCTAssertFalse(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: now.addingTimeInterval(-121),
            now: now
        ))
        XCTAssertFalse(AppleWatchLinkVerificationPolicy.isFresh(
            lastVerifiedAt: now.addingTimeInterval(10),
            now: now
        ))
    }

    func testUnreachableActiveWatchShowsARecoverableSafetyMessage() {
        let error = AppleWatchActivityStartPolicy.blockingError(
            hasActiveWatchWorkout: true,
            isWatchReachable: false
        )
        guard case .watchWorkoutStatusUnconfirmed = error else {
            return XCTFail("Must distinguish an offline active Watch from a confirmed active session")
        }
        XCTAssertNotNil(error.errorDescription)
    }

    func testReachableActiveWatchStillReportsAnActiveSession() {
        let error = AppleWatchActivityStartPolicy.blockingError(
            hasActiveWatchWorkout: true,
            isWatchReachable: true
        )
        guard case .workoutAlreadyActive = error else {
            return XCTFail("Active Watch sessions must continue blocking duplicate launch")
        }
    }

    func testLiveWatchRequiresPositiveReplyBeforeStarting() {
        let liveButTimedOut = AppleWatchActivityStartPolicy.resolve(
            watchReachable: true, cachedActive: false,
            reply: nil, replyIsCurrent: false
        )
        XCTAssertEqual(liveButTimedOut, .unconfirmed)

        let idle = WatchWorkoutActivityState(
            isActive: false, title: nil, updatedAt: Date()
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: false,
                reply: idle, replyIsCurrent: true
            ),
            .clear
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: false,
                reply: idle, replyIsCurrent: false
            ),
            .unconfirmed
        )
    }

    func testActiveWatchCannotBeOverriddenByOldOrMissingReply() {
        let active = WatchWorkoutActivityState(
            isActive: true, title: "Run", updatedAt: Date()
        )
        let idle = WatchWorkoutActivityState(
            isActive: false, title: nil, updatedAt: Date()
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: true,
                reply: active, replyIsCurrent: true
            ),
            .active
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: true,
                reply: idle, replyIsCurrent: false
            ),
            .unconfirmed
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: true, cachedActive: true,
                reply: nil, replyIsCurrent: false
            ),
            .unconfirmed
        )
    }

    func testSleepingWatchKeepsPhoneFallbackUnlessActiveWasReported() {
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: false, cachedActive: false,
                reply: nil, replyIsCurrent: false
            ),
            .clear
        )
        XCTAssertEqual(
            AppleWatchActivityStartPolicy.resolve(
                watchReachable: false, cachedActive: true,
                reply: nil, replyIsCurrent: false
            ),
            .unconfirmed
        )
    }

    func testNoCachedWatchActivityUsesOriginalBlockReason() {
        let error = AppleWatchActivityStartPolicy.blockingError(
            hasActiveWatchWorkout: false,
            isWatchReachable: false
        )
        guard case .workoutAlreadyActive = error else {
            return XCTFail("A different active iPhone session must retain its existing error")
        }
    }
    func testCompletedWatchResultReleasesDeviceWideActiveGuard() {
        // The account may have changed, but the Watch is no longer recording.
        let endedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let active = WatchWorkoutActivityState(
            isActive: true, title: "Run",
            updatedAt: endedAt.addingTimeInterval(-900)
        )
        let resolved = WatchWorkoutActivityState.afterCompletion(
            current: active, endedAt: endedAt
        )
        XCTAssertFalse(resolved.isActive)
        XCTAssertEqual(resolved.updatedAt, endedAt)
    }

    func testDelayedOldCompletionDoesNotClearNewerActiveWatchWorkout() {
        let endedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = WatchWorkoutActivityState(
            isActive: true, title: "Strength",
            updatedAt: endedAt.addingTimeInterval(120)
        )
        let resolved = WatchWorkoutActivityState.afterCompletion(
            current: newer, endedAt: endedAt
        )
        XCTAssertEqual(resolved, newer)
    }

    func testRemoteWatchIdentityExpiresBeforeAnotherWorkoutCanInheritIt() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let identity = WatchRemoteLaunchIdentity(
            requestID: UUID(), kind: .strength, issuedAt: now
        )
        XCTAssertTrue(identity.isFresh(at: now.addingTimeInterval(44)))
        XCTAssertFalse(identity.isFresh(at: now.addingTimeInterval(46)))
        XCTAssertFalse(identity.isFresh(at: now.addingTimeInterval(-46)))
    }

    func testWatchActivityRequestIdentitySurvivesEncoding() throws {
        let id = UUID()
        let withIdentity = WatchWorkoutActivityState(
            isActive: true, title: "Run", updatedAt: Date(),
            relayRequestID: id
        )
        let decoded = try JSONDecoder().decode(
            WatchWorkoutActivityState.self,
            from: JSONEncoder().encode(withIdentity)
        )
        XCTAssertEqual(decoded.relayRequestID, id)
    }

    func testWatchActivityDecodesLegacyPayloadWithoutRemoteIdentity() throws {
        let legacy = """
        {"isActive":true,"title":"Run","updatedAt":0}
        """
        let activity = try JSONDecoder().decode(
            WatchWorkoutActivityState.self,
            from: Data(legacy.utf8)
        )
        XCTAssertNil(activity.relayRequestID)
    }

    func testCompletedWatchResultCarriesRelayIdentityThroughTransport() throws {
        let now = Date()
        let request = UUID()
        var result = WatchWorkoutResult(
            id: UUID(), kind: .walking, healthKitWorkoutUUID: UUID(),
            startedAt: now, endedAt: now.addingTimeInterval(90),
            duration: 90, activeCalories: 18, distanceMeters: 180,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 0
        )
        result.relayRequestID = request
        result.accountOwnerID = UUID()
        let restored = try JSONDecoder().decode(
            WatchWorkoutResult.self, from: JSONEncoder().encode(result)
        )
        XCTAssertEqual(restored.relayRequestID, request)
        let receipt = try XCTUnwrap(WatchRemoteLaunchCompletionReceipt(result: restored))
        XCTAssertEqual(receipt.relayRequestID, request)
        XCTAssertEqual(receipt.healthKitWorkoutUUID, result.healthKitWorkoutUUID)
    }

    func testLegacyWatchCompletionDoesNotInheritRemoteRequestID() throws {
        let now = Date()
        let original = WatchWorkoutResult(
            id: UUID(), kind: .running, healthKitWorkoutUUID: UUID(),
            startedAt: now, endedAt: now.addingTimeInterval(90),
            duration: 90, activeCalories: 18, distanceMeters: 250,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 0
        )
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)
        ) as? [String: Any])
        legacy.removeValue(forKey: "relayRequestID")
        let decoded = try JSONDecoder().decode(
            WatchWorkoutResult.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(decoded.relayRequestID)
        XCTAssertNil(WatchRemoteLaunchCompletionReceipt(result: decoded))
    }

    func testConflictingSavedWatchWorkoutsNeverSelectOneAsProof() throws {
        let start = Date()
        let requestID = UUID(), ownerID = UUID()
        var result = WatchWorkoutResult(
            id: UUID(), kind: .strength, healthKitWorkoutUUID: UUID(),
            startedAt: start, endedAt: start.addingTimeInterval(45),
            duration: 45, activeCalories: 9, distanceMeters: 0,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 0
        )
        result.relayRequestID = requestID
        result.accountOwnerID = ownerID
        let first = try XCTUnwrap(
            WatchRemoteLaunchCompletionReceipt(result: result)
        )
        XCTAssertEqual(
            WatchRemoteLaunchCompletionPolicy.uniqueReceipt(
                [first], requestID: requestID, ownerID: ownerID
            ), first
        )
        var conflictingResult = WatchWorkoutResult(
            id: UUID(), kind: .strength, healthKitWorkoutUUID: UUID(),
            startedAt: start, endedAt: start.addingTimeInterval(45),
            duration: 45, activeCalories: 9, distanceMeters: 0,
            averageHeartRate: nil, maxHeartRate: nil, routePointCount: 0
        )
        conflictingResult.relayRequestID = requestID
        conflictingResult.accountOwnerID = ownerID
        let second = try XCTUnwrap(
            WatchRemoteLaunchCompletionReceipt(result: conflictingResult)
        )
        XCTAssertNil(WatchRemoteLaunchCompletionPolicy.uniqueReceipt(
            [first, second], requestID: requestID, ownerID: ownerID
        ))
        XCTAssertNil(WatchRemoteLaunchCompletionPolicy.uniqueReceipt(
            [first], requestID: requestID, ownerID: UUID()
        ))
    }

}
