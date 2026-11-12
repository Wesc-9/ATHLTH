import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHGoalAccountSyncTests: XCTestCase {
    private func item(
        id: UUID = UUID(), title: String = "Run 10 km",
        image: String? = nil
    ) -> ATHLTHCloudGoal {
        ATHLTHCloudGoal(
            goal: ATHLTHGoal(
                id: id, title: title, category: .endurance,
                dataSource: .manual
            ),
            coverBase64: image
        )
    }

    func testFreshIPadImportsAnExistingIPhoneGoal() {
        let remote = item()
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [], local: [], remote: [remote]
        )
        XCTAssertEqual(outcome.merged, [remote])
        XCTAssertTrue(outcome.conflictingIDs.isEmpty)
    }

    func testIndependentOfflineGoalEditsMergeWithoutDataLoss() {
        let local = item(title: "Strength")
        let remote = item(title: "Marathon")
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [], local: [local], remote: [remote]
        )
        XCTAssertEqual(Set(outcome.merged.map(\.id)), Set([local.id, remote.id]))
        XCTAssertTrue(outcome.conflictingIDs.isEmpty)
    }

    func testGoalDeletionIsNotResurrectedOnOtherDevice() {
        let existing = item()
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [existing], local: [], remote: [existing]
        )
        XCTAssertTrue(outcome.merged.isEmpty)
        XCTAssertTrue(outcome.conflictingIDs.isEmpty)
    }

    func testConcurrentEditsToSameGoalDoNotOverwriteEachOther() {
        let id = UUID()
        let existing = item(id: id, title: "Original")
        let local = item(id: id, title: "iPhone edit")
        let remote = item(id: id, title: "iPad edit")
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [existing], local: [local], remote: [remote]
        )
        XCTAssertEqual(outcome.conflictingIDs, [id])
        XCTAssertTrue(outcome.merged.isEmpty)
    }

    func testChangedCoverCountsAsAConflictingEdit() {
        let id = UUID()
        let existing = item(id: id, image: "one")
        let local = item(id: id, image: "two")
        let remote = item(id: id, image: "three")
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [existing], local: [local], remote: [remote]
        )
        XCTAssertEqual(outcome.conflictingIDs, [id])
    }

    func testRemoteManualBodyMeasurementIsImportedToIPad() {
        let reading = ATHLTHBodyMeasurement(metric: .weight, value: 68,
                                            date: Date(timeIntervalSince1970: 1_800_000_000))
        let result = ATHLTHGoalMergePolicy.reconcileMeasurements(
            base: [], local: [], remote: [reading]
        )
        XCTAssertEqual(result.merged, [reading])
        XCTAssertTrue(result.conflictingIDs.isEmpty)
    }

    func testDeletedManualBodyMeasurementStaysDeleted() {
        let reading = ATHLTHBodyMeasurement(metric: .waist, value: 80, date: .now)
        let result = ATHLTHGoalMergePolicy.reconcileMeasurements(
            base: [reading], local: [], remote: [reading]
        )
        XCTAssertTrue(result.merged.isEmpty)
        XCTAssertTrue(result.conflictingIDs.isEmpty)
    }
}
