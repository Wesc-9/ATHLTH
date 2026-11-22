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
        XCTAssertEqual(restored.recoveryConfiguration.activity, .cycling)
        XCTAssertEqual(restored.recoveryConfiguration.workSeconds, bike().workSeconds)
        XCTAssertEqual(restored.recoveryConfiguration.rounds, bike().rounds)
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

    func testPausedTimerRetainsSelectedIntervalsAcrossRelaunch() throws {
        let (defaults, suite) = try suite()
        defer {
            ATHLTHManualTimedCapture.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID()
        ATHLTHManualTimedCapture.switchAccount(owner, defaults: defaults)
        var original = bike()
        original.method = .intervals
        original.workSeconds = 95
        original.restSeconds = 35
        original.rounds = 12
        original.titleOverride = "Bike session"
        let saved = try ATHLTHManualTimedCapture.beginOrResume(
            configuration: original, userID: owner, defaults: defaults
        )
        XCTAssertTrue(ATHLTHManualTimedCapture.update(
            id: saved.id, userID: owner,
            accumulatedSeconds: 205, resumedAt: nil,
            approvedTimeLimit: 18_000, defaults: defaults
        ))
        ATHLTHManualTimedCapture.switchAccount(nil, defaults: defaults)
        let recovered = try XCTUnwrap(ATHLTHManualTimedCapture.switchAccount(
            owner, defaults: defaults
        ))
        XCTAssertEqual(recovered.recoveryConfiguration.method, .intervals)
        XCTAssertEqual(recovered.recoveryConfiguration.workSeconds, 95)
        XCTAssertEqual(recovered.recoveryConfiguration.restSeconds, 35)
        XCTAssertEqual(recovered.recoveryConfiguration.rounds, 12)
        XCTAssertEqual(recovered.recoveryConfiguration.titleOverride, "Bike session")
        XCTAssertEqual(recovered.accumulatedSeconds, 205)
        XCTAssertNil(recovered.resumedAt)
        XCTAssertTrue(ATHLTHManualTimedCapture.discard(
            id: saved.id, userID: owner, defaults: defaults
        ))
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

    func testResumeCannotReplaceExistingTimedConfiguration() throws {
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
        var changed = bike()
        changed.rounds = 9
        XCTAssertThrowsError(try ATHLTHManualTimedCapture.beginOrResume(
            configuration: changed, userID: owner, defaults: defaults
        ))
        changed = bike()
        changed.workSeconds = 75
        XCTAssertThrowsError(try ATHLTHManualTimedCapture.beginOrResume(
            configuration: changed, userID: owner, defaults: defaults
        ))
        changed = bike()
        changed.titleOverride = "Different workout"
        XCTAssertThrowsError(try ATHLTHManualTimedCapture.beginOrResume(
            configuration: changed, userID: owner, defaults: defaults
        ))
        XCTAssertEqual(ATHLTHManualTimedCapture.current(for: owner)?.id, started.id)
        XCTAssertTrue(ATHLTHManualTimedCapture.discard(
            id: started.id, userID: owner, defaults: defaults
        ))
    }


    func testManualPauseResumeAndFinishedCleanupRetainOneOriginalIdentity() throws {
        let (defaults, suite) = try suite()
        defer {
            ATHLTHManualTimedCapture.switchAccount(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suite)
        }
        let owner = UUID()
        ATHLTHManualTimedCapture.switchAccount(owner, defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let session = try ATHLTHManualTimedCapture.beginOrResume(
            configuration: bike(), userID: owner, at: now, defaults: defaults
        )

        XCTAssertFalse(ATHLTHManualTimedCapture.closeAfterSavedRecord(
            id: UUID(), userID: owner, defaults: defaults
        ))
        XCTAssertEqual(ATHLTHManualTimedCapture.current(for: owner)?.id, session.id)

        XCTAssertTrue(ATHLTHManualTimedCapture.update(
            id: session.id, userID: owner, accumulatedSeconds: 75,
            resumedAt: nil, approvedTimeLimit: 18_000, defaults: defaults
        ))
        XCTAssertTrue(ATHLTHManualTimedCapture.update(
            id: session.id, userID: owner, accumulatedSeconds: 75,
            resumedAt: now.addingTimeInterval(150),
            approvedTimeLimit: 18_000, defaults: defaults
        ))
        XCTAssertEqual(ATHLTHManualTimedCapture.current(for: owner)?.id, session.id)

        // The completion record is saved by the owning caller. This method
        // must release only the original active timer, never make a new ID.
        XCTAssertTrue(ATHLTHManualTimedCapture.closeAfterSavedRecord(
            id: session.id, userID: owner, defaults: defaults
        ))
        XCTAssertNil(ATHLTHManualTimedCapture.current(for: owner))
        XCTAssertFalse(ATHLTHManualTimedCapture.hasActiveCapture)
        XCTAssertFalse(ATHLTHManualTimedCapture.closeAfterSavedRecord(
            id: session.id, userID: owner, defaults: defaults
        ))
    }
}
