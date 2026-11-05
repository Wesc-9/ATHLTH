import XCTest
@testable import ATHLTH

final class ATHLTHHealthHistoryCacheEpochTests: XCTestCase {
    func testHistoricalResultAcceptedWhenNoNewWorkoutArrives() {
        let epoch = ATHLTHHealthHistoryCacheEpoch()
        let startedAt = epoch.value
        XCTAssertTrue(epoch.acceptsResult(startedAt: startedAt))
    }

    func testHistoricalResultIsNotCachedAfterWorkoutInvalidation() {
        var epoch = ATHLTHHealthHistoryCacheEpoch()
        let oldQuery = epoch.value
        epoch.invalidate() // A new workout arrives during an HKSampleQuery.
        XCTAssertFalse(epoch.acceptsResult(startedAt: oldQuery))
        XCTAssertTrue(epoch.acceptsResult(startedAt: epoch.value))
    }

    func testRepeatedCacheInvalidationsCannotResurrectOldSnapshot() {
        var epoch = ATHLTHHealthHistoryCacheEpoch()
        let oldQuery = epoch.value
        epoch.invalidate()
        epoch.invalidate() // Also covers memory-pressure eviction.
        XCTAssertFalse(epoch.acceptsResult(startedAt: oldQuery))
        XCTAssertFalse(epoch.acceptsResult(startedAt: epoch.value - 1))
        XCTAssertTrue(epoch.acceptsResult(startedAt: epoch.value))
    }
}
