import XCTest
@testable import ATHLTH

final class ATHLTHRecordedWorkoutIndexTests: XCTestCase {
    func testLocalCompletionCountsBeforeHealthSyncAndDisappearsAfterSync() {
        let healthID = UUID()
        let records = [ATHLTHRecordedWorkoutIndex.LocalRecord(
            key: "phone-a", healthID: healthID)]
        XCTAssertEqual(ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [], localRecords: records), ["phone-a"])
        XCTAssertTrue(ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [healthID], localRecords: records).isEmpty)
    }

    func testLinkedPhoneAndStrengthCountOnceEvenBeforeHealthImport() {
        let sharedID = UUID()
        let keys = ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [], localRecords: [
                .init(key: "strength-a", healthID: sharedID),
                .init(key: "phone-b", healthID: sharedID)
            ])
        XCTAssertEqual(keys, ["strength-a"])
    }

    func testUnlinkedActivitiesArePreservedAndRepeatedDeliveryIsIgnored() {
        let keys = ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [], localRecords: [
                .init(key: "phone-a", healthID: nil),
                .init(key: "phone-a", healthID: nil),
                .init(key: "strength-b", healthID: nil)
            ])
        XCTAssertEqual(keys, ["phone-a", "strength-b"])
    }
}
