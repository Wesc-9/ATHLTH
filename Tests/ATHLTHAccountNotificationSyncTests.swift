import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAccountNotificationSyncTests: XCTestCase {
    private func item(
        key: String,
        readAt: Date? = nil,
        id: UUID = UUID(),
        kind: ATHLTHNotificationKind = .social
    ) -> ATHLTHNotificationItem {
        ATHLTHNotificationItem(
            id: id, eventKey: key, kind: kind,
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

    func testCompletedCheckInCannotReturnFromCloud() {
        let today = item(key: "insights.daily-check-in.today", kind: .dailyCheckIn)
        let invite = item(key: "invite")
        let stale = ATHLTHAccountNotificationSnapshot(items: [today, invite], tombstones: [])
        var local = stale
        XCTAssertTrue(local.expireDailyCheckIns(keeping: nil, now: .now))
        XCTAssertEqual(local.items.map(\.eventKey), ["invite"])
        XCTAssertEqual(local.tombstones.map { $0.item.eventKey }, [today.eventKey])
        XCTAssertFalse(local.expireDailyCheckIns(keeping: nil, now: .now))
        XCTAssertEqual(ATHLTHAccountNotificationSnapshot.merged(local, stale).items.map(\.eventKey), ["invite"])
    }

    func testExpiredCheckInsDoNotRemoveTodaysUnansweredReminderOrOtherAlerts() {
        let today = item(key: "today", kind: .dailyCheckIn)
        let yesterday = item(key: "yesterday", kind: .dailyCheckIn)
        let invite = item(key: "invite")
        var snapshot = ATHLTHAccountNotificationSnapshot(
            items: [today, yesterday, invite], tombstones: [])
        XCTAssertTrue(snapshot.expireDailyCheckIns(keeping: today.eventKey, now: .now))
        XCTAssertEqual(Set(snapshot.items.map(\.eventKey)), Set(["today", "invite"]))
        XCTAssertEqual(snapshot.tombstones.map { $0.item.eventKey }, ["yesterday"])
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
