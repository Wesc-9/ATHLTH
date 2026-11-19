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

    func testLateHealthKitLinkOnRepeatedLocalKeyPreventsDoubleCount() {
        let linked = UUID()
        let keys = ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [linked], localRecords: [
                .init(key: "run-a", healthID: nil),
                .init(key: "run-a", healthID: linked)
            ]
        )
        XCTAssertTrue(keys.isEmpty,
                      "The first unlinked snapshot must not override its later HealthKit link")
    }

    func testCoalescedLocalKeyClaimsLinkedIdentityOnlyOnce() {
        let linked = UUID()
        let keys = ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [], localRecords: [
                .init(key: "strength-a", healthID: nil),
                .init(key: "strength-a", healthID: linked),
                .init(key: "phone-b", healthID: linked),
                .init(key: "run-c", healthID: nil)
            ]
        )
        XCTAssertEqual(keys, ["strength-a", "run-c"])
    }

    func testConflictingHealthKitLinksFailClosedWhenAnyIsImported() {
        let first = UUID()
        let second = UUID()
        let keys = ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [second], localRecords: [
                .init(key: "run-a", healthID: first),
                .init(key: "run-a", healthID: second)
            ]
        )
        XCTAssertTrue(keys.isEmpty)
    }

    func testConflictingUnimportedHealthKitIDsCannotBecomeTrustedLocalCount() {
        let first = UUID()
        let second = UUID()
        let keys = ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [], localRecords: [
                .init(key: "phone-a", healthID: first),
                .init(key: "phone-a", healthID: second),
                .init(key: "strength-b", healthID: nil)
            ]
        )
        XCTAssertEqual(keys, ["strength-b"])
    }

    func testConflictingLocalSnapshotsDoNotClaimHealthIdentityFromOtherWorkouts() {
        let first = UUID()
        let second = UUID()
        let keys = ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: [], localRecords: [
                .init(key: "conflict", healthID: first),
                .init(key: "conflict", healthID: second),
                .init(key: "valid", healthID: first),
                .init(key: "duplicate", healthID: first),
                .init(key: "independent", healthID: second)
            ]
        )
        XCTAssertEqual(keys, ["valid", "independent"])
    }
}
