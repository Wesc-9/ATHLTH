import Foundation

/// Crash-safe replay of a user-approved cloud backup restore.
///
/// UserDefaults persists each key separately. A termination between writes
/// would otherwise leave an inconsistent mixture of old and restored plans,
/// workouts, and libraries. This journal is written atomically before the
/// first mutation, then replayed until every account-scoped key is replaced.
///
/// It is local-only, protected while the device is locked, and excluded
/// from iCloud/iTunes backup. It never contains raw HealthKit imports or
/// recorded GPS routes because those are excluded by TrainingBackupPayload.
enum TrainingBackupRestoreJournal {
    private struct PendingRestore: Codable {
        let userID: UUID
        let records: [String: Data]
    }

    private static let filename = "pending-training-restore-v1.json"
    private static let folderName = "ATHLTHRestoreJournal"
    private static let maximumBytes = 20_000_000

    /// The optional directory/defaults parameters isolate XCTest from the
    /// production account. App startup uses the default on-device location.
    static func stage(
        records: [String: Data],
        userID: UUID,
        defaults: UserDefaults = .standard,
        directory: URL? = nil
    ) throws {
        // Never overwrite an interrupted previous restore.
        try finishPending(defaults: defaults, directory: directory)
        try TrainingBackupPayload(
            version: 1, ownerID: userID, records: records
        ).validate(for: userID)

        let pending = PendingRestore(userID: userID, records: records)
        let encoded = try JSONEncoder().encode(pending)
        guard encoded.count <= maximumBytes else {
            throw BackupError.tooLarge
        }
        let url = try journalURL(directory: directory)
        try encoded.write(
            to: url,
            options: [.atomic, .completeFileProtection]
        )
    }

    /// Safe to call at launch and more than once: all replacements are
    /// idempotent; the journal is removed only after every key is written.
    @discardableResult
    static func finishPending(
        defaults: UserDefaults = .standard,
        directory: URL? = nil
    ) throws -> Bool {
        let url = try journalURL(directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else {
            throw BackupError.tooLarge
        }
        let pending = try JSONDecoder().decode(PendingRestore.self, from: data)
        try TrainingBackupPayload(
            version: 1, ownerID: pending.userID, records: pending.records
        ).validate(for: pending.userID)

        for name in TrainingBackupPayload.names {
            let key = AccountLocalStorage.key(name, userID: pending.userID)
            if let restored = pending.records[name] {
                defaults.set(restored, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        try FileManager.default.removeItem(at: url)
        return true
    }

    private static func journalURL(directory: URL?) throws -> URL {
        let folder: URL
        if let directory {
            folder = directory
        } else {
            folder = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent(folderName, isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        var protected = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        return folder.appendingPathComponent(filename)
    }
}
