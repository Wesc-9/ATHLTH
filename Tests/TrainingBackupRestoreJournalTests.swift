import Foundation
import XCTest
@testable import ATHLTH

final class TrainingBackupRestoreJournalTests: XCTestCase {
    private func isolatedStorage() throws -> (UUID, UUID, UserDefaults, URL) {
        let owner = UUID()
        let otherAccount = UUID()
        let suite = "athlth.tests.backup-restore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        return (owner, otherAccount, defaults, folder)
    }

    private func clean(_ defaults: UserDefaults, folder: URL) {
        if let suite = defaults.volatileDomainNames.first(where: {
            $0.hasPrefix("athlth.tests.backup-restore.")
        }) {
            defaults.removePersistentDomain(forName: suite)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    func testInterruptedRestoreReplaysEveryKeyWithoutMixingAccounts() throws {
        let (owner, other, defaults, folder) = try isolatedStorage()
        defer { try? FileManager.default.removeItem(at: folder) }

        let oldCoach = Data(#"{"version":"before"}"#.utf8)
        let newCoach = Data(#"{"version":"restored"}"#.utf8)
        let otherCoach = Data(#"{"version":"other-account"}"#.utf8)
        let ownerCoachKey = AccountLocalStorage.key("coach", userID: owner)
        let ownerGoalsKey = AccountLocalStorage.key("goals", userID: owner)
        let otherCoachKey = AccountLocalStorage.key("coach", userID: other)
        defaults.set(oldCoach, forKey: ownerCoachKey)
        defaults.set(otherCoach, forKey: otherCoachKey)

        try TrainingBackupRestoreJournal.stage(
            records: ["coach": newCoach, "goals": Data("[]".utf8)],
            userID: owner,
            defaults: defaults,
            directory: folder
        )

        // The process terminates after the first write, before the second.
        defaults.set(newCoach, forKey: ownerCoachKey)
        XCTAssertNil(defaults.data(forKey: ownerGoalsKey))

        XCTAssertTrue(try TrainingBackupRestoreJournal.finishPending(
            defaults: defaults, directory: folder
        ))
        XCTAssertEqual(defaults.data(forKey: ownerCoachKey), newCoach)
        XCTAssertEqual(defaults.data(forKey: ownerGoalsKey), Data("[]".utf8))
        XCTAssertEqual(defaults.data(forKey: otherCoachKey), otherCoach)
        XCTAssertFalse(try TrainingBackupRestoreJournal.finishPending(
            defaults: defaults, directory: folder
        ))
        XCTAssertEqual(defaults.data(forKey: ownerCoachKey), newCoach)
    }

    func testInvalidPayloadNeverTouchesExistingLocalData() throws {
        let (owner, _, defaults, folder) = try isolatedStorage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = AccountLocalStorage.key("goals", userID: owner)
        let original = Data("[]".utf8)
        defaults.set(original, forKey: key)

        XCTAssertThrowsError(
            try TrainingBackupRestoreJournal.stage(
                records: ["goals": Data("not valid JSON".utf8)],
                userID: owner,
                defaults: defaults,
                directory: folder
            )
        )
        XCTAssertFalse(try TrainingBackupRestoreJournal.finishPending(
            defaults: defaults, directory: folder
        ))
        XCTAssertEqual(defaults.data(forKey: key), original)
    }

    func testRestoreRemovesAbsentAccountKeysAfterJournalCommit() throws {
        let (owner, other, defaults, folder) = try isolatedStorage()
        defer { try? FileManager.default.removeItem(at: folder) }
        let ownerHistory = AccountLocalStorage.key("phoneHistory", userID: owner)
        let otherHistory = AccountLocalStorage.key("phoneHistory", userID: other)
        defaults.set(Data("[]".utf8), forKey: ownerHistory)
        defaults.set(Data("[]".utf8), forKey: otherHistory)

        try TrainingBackupRestoreJournal.stage(
            records: ["goals": Data("[]".utf8)],
            userID: owner,
            defaults: defaults,
            directory: folder
        )
        XCTAssertTrue(try TrainingBackupRestoreJournal.finishPending(
            defaults: defaults, directory: folder
        ))
        XCTAssertNil(defaults.data(forKey: ownerHistory))
        XCTAssertNotNil(defaults.data(forKey: otherHistory))
    }
    func testBackupRestoreIsBlockedDuringAnyLiveWorkoutIncludingWatch() {
        let safe = TrainingBackupRestoreSafetyPolicy.allowsRestore(
            phoneActive: false,
            strengthActive: false,
            mirroredWatchActive: false,
            watchReportedActive: false
        )
        XCTAssertTrue(safe)

        // A Watch-only workout must block restore even if neither iPhone
        // recorder has a local active workout.
        XCTAssertFalse(TrainingBackupRestoreSafetyPolicy.allowsRestore(
            phoneActive: false,
            strengthActive: false,
            mirroredWatchActive: false,
            watchReportedActive: true
        ))
        XCTAssertFalse(TrainingBackupRestoreSafetyPolicy.allowsRestore(
            phoneActive: false,
            strengthActive: false,
            mirroredWatchActive: true,
            watchReportedActive: false
        ))
        XCTAssertFalse(TrainingBackupRestoreSafetyPolicy.allowsRestore(
            phoneActive: true,
            strengthActive: false,
            mirroredWatchActive: false,
            watchReportedActive: false
        ))
        XCTAssertFalse(TrainingBackupRestoreSafetyPolicy.allowsRestore(
            phoneActive: false,
            strengthActive: true,
            mirroredWatchActive: false,
            watchReportedActive: false
        ))
    }

}
