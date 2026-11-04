import XCTest
@testable import ATHLTH

final class ATHLTHStudioPlanSyncDecisionTests: XCTestCase {
    typealias Decision = ATHLTHStudioPlanSyncDecision
    let acknowledgement = Decision.Acknowledgement(revision: 4, fingerprint: "initial")

    func testNewPlanIsUploadedWithoutRemoteRevision() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "new", remoteFingerprint: nil,
                remoteRevision: nil, acknowledged: nil
            ), .upload(expectedRevision: 0)
        )
    }

    func testNewRemotePlanIsDownloaded() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: nil, remoteFingerprint: "new",
                remoteRevision: 1, acknowledged: nil
            ), .download
        )
    }

    func testBothUnsynchronizedVersionsRequireExplicitConflictResolution() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "local", remoteFingerprint: "remote",
                remoteRevision: 1, acknowledged: nil
            ), .conflict
        )
    }

    func testLocalOnlyChangesUploadWithExpectedRevision() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "locally edited", remoteFingerprint: "initial",
                remoteRevision: 4, acknowledged: acknowledgement
            ), .upload(expectedRevision: 4)
        )
    }

    func testRemoteOnlyChangesDownload() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "initial", remoteFingerprint: "elsewhere edited",
                remoteRevision: 5, acknowledged: acknowledgement
            ), .download
        )
    }

    func testConcurrentChangesNeverAutoOverwrite() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "local", remoteFingerprint: "remote",
                remoteRevision: 5, acknowledged: acknowledgement
            ), .conflict
        )
    }

    func testRemoteDeletionCannotBeSilentlyRecreated() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: "initial", remoteFingerprint: nil,
                remoteRevision: nil, acknowledged: acknowledgement
            ), .conflict
        )
    }

    func testLocalDeletionCannotBeSilentlyRecreated() {
        XCTAssertEqual(
            Decision.choose(
                localFingerprint: nil, remoteFingerprint: "initial",
                remoteRevision: 4, acknowledged: acknowledgement
            ), .conflict
        )
    }
}
