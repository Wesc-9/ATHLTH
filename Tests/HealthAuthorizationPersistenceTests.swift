import XCTest
@testable import ATHLTH

final class HealthAuthorizationPersistenceTests: XCTestCase {
    @MainActor
    func testConfiguredConnectionDoesNotDependOnTransientReadResults() {
        XCTAssertTrue(HealthKitManager.isConfiguredConnection(enabled: true, available: true, requested: true))
        XCTAssertFalse(HealthKitManager.isConfiguredConnection(enabled: false, available: true, requested: true))
        XCTAssertFalse(HealthKitManager.isConfiguredConnection(enabled: true, available: false, requested: true))
        XCTAssertFalse(HealthKitManager.isConfiguredConnection(enabled: true, available: true, requested: false))
    }

    @MainActor
    func testLegacyAuthorizationMarkerStillCountsAsConfigured() {
        XCTAssertTrue(
            HealthKitManager.hasPersistedAuthorizationMarker(
                legacyRequested: true,
                authorizationVersion: 0
            )
        )
    }

    @MainActor
    func testOlderAuthorizationVersionStillCountsAsConfigured() {
        XCTAssertTrue(
            HealthKitManager.hasPersistedAuthorizationMarker(
                legacyRequested: false,
                authorizationVersion: 1
            )
        )
    }

    @MainActor
    func testFreshInstallWithoutAuthorizationMarkerNeedsSetup() {
        XCTAssertFalse(
            HealthKitManager.hasPersistedAuthorizationMarker(
                legacyRequested: false,
                authorizationVersion: 0
            )
        )
    }
}
