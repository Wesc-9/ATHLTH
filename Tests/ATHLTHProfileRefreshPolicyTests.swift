import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHProfileRefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    func testRepeatedUnchangedHistoryDoesNotSyncAgain() {
        let user = UUID()
        XCTAssertFalse(ATHLTHProfileRefreshPolicy.shouldSyncMostTrained(
            userID: user, local: [], previousUserID: user,
            previousLocal: [], lastSyncedAt: now.addingTimeInterval(-60),
            now: now
        ))
    }

    func testChangedHistoryOrAccountIsSynced() {
        let user = UUID()
        let item = ATHLTHProfileHighlights.TrainedItem(
            id: "route", title: "Route", kind: .route,
            count: 1, lastCompleted: now
        )
        XCTAssertTrue(ATHLTHProfileRefreshPolicy.shouldSyncMostTrained(
            userID: user, local: [item], previousUserID: user,
            previousLocal: [], lastSyncedAt: now, now: now
        ))
        XCTAssertTrue(ATHLTHProfileRefreshPolicy.shouldSyncMostTrained(
            userID: user, local: [], previousUserID: UUID(),
            previousLocal: [], lastSyncedAt: now, now: now
        ))
    }

    func testStaleOrFirstLoadRefreshes() {
        let user = UUID()
        XCTAssertTrue(ATHLTHProfileRefreshPolicy.shouldSyncMostTrained(
            userID: user, local: [], previousUserID: user,
            previousLocal: [], lastSyncedAt: now.addingTimeInterval(-181), now: now
        ))
        XCTAssertTrue(ATHLTHProfileRefreshPolicy.shouldSyncMostTrained(
            userID: user, local: [], previousUserID: nil,
            previousLocal: [], lastSyncedAt: nil, now: now
        ))
    }
}
