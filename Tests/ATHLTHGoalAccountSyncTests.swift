import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHGoalAccountSyncTests: XCTestCase {
    private func item(
        id: UUID = UUID(), title: String = "Run 10 km",
        image: String? = nil, lastSavedAt: Date? = nil
    ) -> ATHLTHCloudGoal {
        ATHLTHCloudGoal(
            goal: ATHLTHGoal(
                id: id, title: title, category: .endurance,
                lastSavedAt: lastSavedAt, dataSource: .manual
            ),
            coverBase64: image
        )
    }

    func testGoalUpdateDoesNotIntroduceLocalBodyMeasurements() {
        let goal = item()
        let reading = ATHLTHBodyMeasurement(metric: .weight, value: 68, date: Date(timeIntervalSince1970: 1_800_000_000))
        let fresh = ATHLTHCloudGoalDocument(goals: [], measurements: [])
        XCTAssertTrue(fresh.replacingGoals([goal]).measurements.isEmpty)
        let legacy = ATHLTHCloudGoalDocument(goals: [], measurements: [reading])
        XCTAssertEqual(legacy.replacingGoals([goal]).measurements, [reading])
        XCTAssertEqual(legacy.replacingGoals([goal]).goals, [goal])
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

    func testMostRecentlySavedGoalWinsWithoutPrompt() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = older.addingTimeInterval(60)
        let existing = item(id: id, title: "Original")
        let local = item(id: id, title: "iPhone edit", lastSavedAt: newer)
        let remote = item(id: id, title: "iPad edit", lastSavedAt: older)
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [existing], local: [local], remote: [remote]
        )
        XCTAssertEqual(outcome.merged, [local])
        XCTAssertTrue(outcome.conflictingIDs.isEmpty)
    }

    func testCloudNewerGoalWinsWithoutPrompt() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = older.addingTimeInterval(60)
        let existing = item(id: id, title: "Original")
        let local = item(id: id, title: "iPhone edit", lastSavedAt: older)
        let remote = item(id: id, title: "iPad edit", lastSavedAt: newer)
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [existing], local: [local], remote: [remote]
        )
        XCTAssertEqual(outcome.merged, [remote])
        XCTAssertTrue(outcome.conflictingIDs.isEmpty)
    }

    func testConcurrentDeleteIsNeverResurrected() {
        let id = UUID()
        let existing = item(id: id, title: "Original")
        let remoteEdit = item(id: id, title: "Changed", lastSavedAt: .now)
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [existing], local: [], remote: [remoteEdit]
        )
        XCTAssertTrue(outcome.merged.isEmpty)
        XCTAssertTrue(outcome.conflictingIDs.isEmpty)
    }

    func testChangedCoverUsesMostRecentSave() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = older.addingTimeInterval(60)
        let existing = item(id: id, image: "one")
        let local = item(id: id, image: "two", lastSavedAt: older)
        let remote = item(id: id, image: "three", lastSavedAt: newer)
        let outcome = ATHLTHGoalMergePolicy.reconcile(
            base: [existing], local: [local], remote: [remote]
        )
        XCTAssertEqual(outcome.merged, [remote])
        XCTAssertTrue(outcome.conflictingIDs.isEmpty)
    }

    func testConcurrentMeasurementEditsResolveBySaveDate() {
        let id = UUID()
        let base = ATHLTHBodyMeasurement(
            id: id, metric: .weight, value: 70,
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        var local = base
        local.value = 69
        local.lastSavedAt = Date(timeIntervalSince1970: 1_800_000_100)
        var remote = base
        remote.value = 68
        remote.lastSavedAt = Date(timeIntervalSince1970: 1_800_000_200)
        let outcome = ATHLTHGoalMergePolicy.reconcileMeasurements(
            base: [base], local: [local], remote: [remote]
        )
        XCTAssertEqual(outcome.merged, [remote])
        XCTAssertTrue(outcome.conflictingIDs.isEmpty)
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
