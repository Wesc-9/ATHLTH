import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHProfileMostTrainedSyncTests: XCTestCase {
    typealias Item = ATHLTHProfileHighlights.TrainedItem

    private func item(
        _ id: String, kind: ATHLTHProfileHighlights.ActivityKind,
        count: Int, date: Date = .distantPast
    ) -> Item {
        Item(id: id, title: id, kind: kind, count: count, lastCompleted: date)
    }

    func testNewIPadWithNoLocalWorkoutsKeepsAccountHighlights() {
        let remote = [
            item("Squat", kind: .exercise, count: 24),
            item("Track intervals", kind: .interval, count: 6),
            item("Park route", kind: .route, count: 4)
        ]
        let merged = ATHLTHProfileMostTrainedSyncService.merged(
            local: [], remote: remote
        )
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.map(\.id), remote.map(\.id))
    }

    func testIncompleteDeviceHistoryNeverLowersExistingCloudCount() {
        let remote = item("Squat", kind: .exercise, count: 24)
        let local = item("Squat", kind: .exercise, count: 2, date: .now)
        let merged = ATHLTHProfileMostTrainedSyncService.merged(
            local: [local], remote: [remote]
        )
        XCTAssertEqual(merged.first?.count, 24)
    }

    func testCompletedSessionCountCanIncreaseWithoutDoubleCounting() {
        let remote = item("Squat", kind: .exercise, count: 4)
        let local = item("Squat", kind: .exercise, count: 5)
        let merged = ATHLTHProfileMostTrainedSyncService.merged(
            local: [local], remote: [remote]
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.count, 5)
    }
}
