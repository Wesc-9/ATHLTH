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
        expiresAt: Date? = nil
    ) -> Bool {
        WorkoutDeviceRelayClaimPolicy.accepts(
            source: source,
            target: target,
            kind: kind,
            payloadTarget: payloadTarget,
            payloadKind: payloadKind,
            payloadVersion: payloadVersion,
            expiresAt: expiresAt ?? now.addingTimeInterval(60),
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

    func testExpiredOrUnknownVersionCannotLaunch() {
        XCTAssertFalse(accepts(expiresAt: now))
        XCTAssertFalse(accepts(expiresAt: now.addingTimeInterval(-1)))
        XCTAssertFalse(accepts(payloadVersion: 0))
        XCTAssertFalse(accepts(payloadVersion: 2))
    }
}
