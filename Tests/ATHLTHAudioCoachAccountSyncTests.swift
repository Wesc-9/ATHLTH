import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHAudioCoachAccountSyncTests: XCTestCase {
    func testLocalChangeUploadsWhenCloudMatchesLastAcknowledgement() {
        XCTAssertEqual(
            ATHLTHAudioCoachAccountSyncDecision.choose(
                local: "new-local", remote: "ack", lastAcknowledged: "ack",
                localEditedAt: Date(), remoteEditedAt: .distantPast
            ), .upload
        )
    }

    func testRemoteChangeDownloadsWhenLocalMatchesAcknowledgement() {
        XCTAssertEqual(
            ATHLTHAudioCoachAccountSyncDecision.choose(
                local: "ack", remote: "new-remote", lastAcknowledged: "ack",
                localEditedAt: .distantPast, remoteEditedAt: Date()
            ), .download
        )
    }

    func testConcurrentEditsResolveDeterministicallyWithLatestTimestamp() {
        let past = Date(timeIntervalSince1970: 1000)
        let future = Date(timeIntervalSince1970: 2000)
        XCTAssertEqual(
            ATHLTHAudioCoachAccountSyncDecision.choose(
                local: "local", remote: "remote", lastAcknowledged: "baseline",
                localEditedAt: future, remoteEditedAt: past
            ), .upload
        )
        XCTAssertEqual(
            ATHLTHAudioCoachAccountSyncDecision.choose(
                local: "local", remote: "remote", lastAcknowledged: "baseline",
                localEditedAt: past, remoteEditedAt: future
            ), .download
        )
    }

    func testSameSnapshotDoesNotLoopBetweenPhoneAndPad() {
        XCTAssertEqual(
            ATHLTHAudioCoachAccountSyncDecision.choose(
                local: "same", remote: "same", lastAcknowledged: "outdated",
                localEditedAt: Date(), remoteEditedAt: .distantPast
            ), .unchanged
        )
    }

    func testGroupPhaseAndActivationSurviveJSONRoundTrip() throws {
        var group = ATHLTHAudioCoachGroup(name: "Main work")
        group.enabled = false
        group.phases = [.main, .recovery]
        let restored = try JSONDecoder().decode(
            ATHLTHAudioCoachGroup.self, from: JSONEncoder().encode(group)
        )
        XCTAssertFalse(restored.isEnabled)
        XCTAssertEqual(restored.phases, [.main, .recovery])
    }
}
