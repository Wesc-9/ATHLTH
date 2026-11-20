import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHManualTimedCaptureTests: XCTestCase {
    private func suite() throws -> (UserDefaults, String) {
        let name = "ATHLTHManualTimer.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private func bike() -> CustomQuickWorkoutConfiguration {
        CustomQuickWorkoutConfiguration(
            activity: .cycling, method: .open,
            durationMinutes: 30, workSeconds: 40,
            restSeconds: 20, rounds: 6
        )
    }

    func testManualTimerOccupiesUniversalLaunchSlotAndRestoresAfterAccountSwitch() throws {
        let (defaults, suite) = try suite()
        defer {
            ATHLTHManualTimedCapture.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID()
        ATHLTHManualTimedCapture.switchAccount(owner, defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let started = try ATHLTHManualTimedCapture.beginOrResume(
            configuration: bike(), userID: owner, at: now, defaults: defaults
        )
        XCTAssertTrue(ATHLTHManualTimedCapture.hasActiveCapture)
        XCTAssertThrowsError(try ATHLTHWorkoutRecordingArbiter.reserveLaunch())
        XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartStrength())
        XCTAssertFalse(ATHLTHWorkoutRecordingArbiter.mayStartRunning())
        XCTAssertTrue(ATHLTHManualTimedCapture.update(
            id: started.id, userID: owner,
            accumulatedSeconds: 60, resumedAt: nil,
            approvedTimeLimit: 18_000, defaults: defaults
        ))
        ATHLTHManualTimedCapture.switchAccount(nil, defaults: defaults)
        XCTAssertFalse(ATHLTHManualTimedCapture.hasActiveCapture)
        let restored = try XCTUnwrap(ATHLTHManualTimedCapture.switchAccount(
            owner, defaults: defaults
        ))
        XCTAssertEqual(restored.id, started.id)
        XCTAssertEqual(restored.elapsed(at: now.addingTimeInterval(90)), 60)
        XCTAssertTrue(ATHLTHManualTimedCapture.discard(
            id: started.id, userID: owner, defaults: defaults
        ))
        XCTAssertFalse(ATHLTHManualTimedCapture.hasActiveCapture)
    }

    func testCorruptCheckpointIsProtectedAgainstOverwrite() throws {
        let (defaults, suite) = try suite()
        defer {
            ATHLTHManualTimedCapture.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID()
        let key = AccountLocalStorage.key("manualTimedActiveV1", userID: owner)
        let original = Data("unknown newer checkpoint".utf8)
        defaults.set(original, forKey: key)
        XCTAssertNil(ATHLTHManualTimedCapture.switchAccount(
            owner, defaults: defaults
        ))
        XCTAssertTrue(ATHLTHManualTimedCapture.hasActiveCapture)
        XCTAssertThrowsError(try ATHLTHManualTimedCapture.beginOrResume(
            configuration: bike(), userID: owner, defaults: defaults
        ))
        XCTAssertEqual(defaults.data(forKey: key), original)
    }

    func testAnotherActivityCannotTakeOverExistingTimer() throws {
        let (defaults, suite) = try suite()
        defer {
            ATHLTHManualTimedCapture.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID()
        ATHLTHManualTimedCapture.switchAccount(owner, defaults: defaults)
        let started = try ATHLTHManualTimedCapture.beginOrResume(
            configuration: bike(), userID: owner, defaults: defaults
        )
        var yoga = bike()
        yoga.activity = .yoga
        XCTAssertThrowsError(try ATHLTHManualTimedCapture.beginOrResume(
            configuration: yoga, userID: owner, defaults: defaults
        ))
        let same = try ATHLTHManualTimedCapture.beginOrResume(
            configuration: bike(), userID: owner, defaults: defaults
        )
        XCTAssertEqual(same.id, started.id)
        XCTAssertTrue(ATHLTHManualTimedCapture.discard(
            id: started.id, userID: owner, defaults: defaults
        ))
    }
}
