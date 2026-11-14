import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHPublicTrailDiskCacheTests: XCTestCase {
    func testPublicTrailSnapshotPersistsAcrossInstances() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlth-cache-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = ATHLTHPublicTrailDiskCache(fileURL: url)
        let payload = Data("[{\"source\":\"openstreetmap\"}]".utf8)
        await original.store(
            payload: payload,
            attribution: "© OpenStreetMap contributors",
            latitude: 63.42,
            longitude: 10.40,
            radiusKilometers: 12
        )

        let reopened = ATHLTHPublicTrailDiskCache(fileURL: url)
        let match = await reopened.cached(
            latitude: 63.421,
            longitude: 10.401,
            radiusKilometers: 12
        )
        XCTAssertEqual(match?.payload, payload)
        XCTAssertEqual(match?.attribution, "© OpenStreetMap contributors")

        let unrelatedArea = await reopened.cached(
            latitude: 59.9,
            longitude: 10.7,
            radiusKilometers: 12
        )
        XCTAssertNil(unrelatedArea)
    }

    func testLargeOrInvalidCacheEntryIsNotWritten() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("athlth-cache-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let cache = ATHLTHPublicTrailDiskCache(fileURL: url)
        await cache.store(
            payload: Data(repeating: 0, count: 7_000_001),
            attribution: "",
            latitude: 63.42,
            longitude: 10.4,
            radiusKilometers: 10
        )
        let result = await cache.cached(
            latitude: 63.42,
            longitude: 10.4,
            radiusKilometers: 10
        )
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
