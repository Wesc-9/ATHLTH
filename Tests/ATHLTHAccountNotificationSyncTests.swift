import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAccountNotificationSyncTests: XCTestCase {
    private func item(
        key: String,
        readAt: Date? = nil,
        id: UUID = UUID()
    ) -> ATHLTHNotificationItem {
        ATHLTHNotificationItem(
            id: id, eventKey: key, kind: .social,
            title: "Invitation", message: "Training tomorrow",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            readAt: readAt
        )
    }

    func testNewDeviceRestoresCloudHistoryWhenEmptyLocally() {
        let cloud = ATHLTHAccountNotificationSnapshot(
            items: [item(key: "shared-invite")], tombstones: []
        )
        let result = ATHLTHAccountNotificationSnapshot.merged(.empty, cloud)
        XCTAssertEqual(result.items.map(\.eventKey), ["shared-invite"])
    }

    func testReadingOnEitherDeviceNeverRevertsToUnread() {
        let read = Date(timeIntervalSince1970: 1_700_001_000)
        let local = ATHLTHAccountNotificationSnapshot(
            items: [item(key: "invite", readAt: read)], tombstones: []
        )
        let oldCloud = ATHLTHAccountNotificationSnapshot(
            items: [item(key: "invite")], tombstones: []
        )
        let result = ATHLTHAccountNotificationSnapshot.merged(local, oldCloud)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.readAt, read)
        XCTAssertEqual(
            ATHLTHAccountNotificationSnapshot.merged(oldCloud, local)
                .items.first?.readAt,
            read
        )
    }

    func testDeletedNotificationDoesNotResurrectFromOldDevice() {
        let removed = item(key: "old-invite")
        let deleted = ATHLTHAccountNotificationSnapshot(
            items: [],
            tombstones: [.init(item: removed, deletedAt: .now)]
        )
        let stale = ATHLTHAccountNotificationSnapshot(
            items: [removed], tombstones: []
        )
        XCTAssertTrue(
            ATHLTHAccountNotificationSnapshot.merged(stale, deleted)
                .items.isEmpty
        )
        XCTAssertEqual(
            ATHLTHAccountNotificationSnapshot.merged(deleted, stale)
                .tombstones.count, 1
        )
    }

    func testTwoDevicesDoNotDuplicateSameEventKey() {
        let one = item(key: "workout-123")
        let two = item(key: "workout-123")
        let merged = ATHLTHAccountNotificationSnapshot.merged(
            .init(items: [one], tombstones: []),
            .init(items: [two], tombstones: [])
        )
        XCTAssertEqual(merged.items.count, 1)
    }

    func testLinkedSocialDestinationIsNotLostOnMerge() {
        var local = item(key: "social-inbox-123")
        let other = item(key: "social-inbox-123")
        let entityID = UUID()
        local.socialEntityID = entityID
        let merged = ATHLTHAccountNotificationSnapshot.merged(
            .init(items: [local], tombstones: []),
            .init(items: [other], tombstones: [])
        )
        XCTAssertEqual(merged.items.first?.socialEntityID, entityID)
    }
}
