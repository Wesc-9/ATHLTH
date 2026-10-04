import Foundation
import Supabase

struct TrainingBackupChangeTracker {
    private(set) var revision: UInt64 = 0
    var isDirty = false

    mutating func markDirty() {
        revision &+= 1
        isDirty = true
    }

    mutating func didUpload(revision capturedRevision: UInt64) {
        isDirty = revision != capturedRevision
    }
}

struct TrainingBackupPayload: Codable, Equatable {
    let version: Int
    let ownerID: UUID
    let records: [String: Data]

    static let names = ["training", "goals", "strengthHistory", "runningLibrary", "exerciseLibrary", "coach", "phoneHistory"]

    static func capture(userID: UUID) throws -> Self {
        var records: [String: Data] = [:]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for name in names {
            if let data = UserDefaults.standard.data(forKey: AccountLocalStorage.key(name, userID: userID)) {
                // Keep imported health readings and recorded GPS traces out of cloud backup.
                if name == "strengthHistory" {
                    var logs = try JSONDecoder().decode([StrengthWorkoutLog].self, from: data)
                    for index in logs.indices {
                        logs[index].healthMetrics = LinkedHealthWorkoutMetrics(healthKitWorkoutUUID: logs[index].healthMetrics.healthKitWorkoutUUID, duration: nil, activeCalories: nil, averageHeartRate: nil, maxHeartRate: nil)
                    }
                    records[name] = try encoder.encode(logs)
                } else if name == "phoneHistory" {
                    var logs = try JSONDecoder().decode([PhoneWorkout].self, from: data)
                    for index in logs.indices { logs[index].points = [] }
                    records[name] = try encoder.encode(logs)
                } else if name == "training" {
                    _ = try JSONDecoder().decode(AccountTrainingContent.self, from: data)
                    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BackupError.invalidBackup }
                    object.removeValue(forKey: "onboardingProfile")
                    records[name] = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
                } else {
                    records[name] = data
                }
            }
        }
        return Self(version: 1, ownerID: userID, records: records)
    }

    func validate(for userID: UUID) throws {
        guard version == 1, ownerID == userID,
              Set(records.keys).isSubset(of: Set(Self.names)) else { throw BackupError.invalidBackup }
        for data in records.values { _ = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) }
        // Decode each public model before replacing anything on this device.
        let decoder = JSONDecoder()
        if let data = records["phoneHistory"] { _ = try decoder.decode([PhoneWorkout].self, from: data) }
        if let data = records["training"] {
            _ = try decoder.decode(AccountTrainingContent.self, from: data)
        }
        if let data = records["goals"] { _ = try decoder.decode([ATHLTHGoal].self, from: data) }
        if let data = records["strengthHistory"] { _ = try decoder.decode([StrengthWorkoutLog].self, from: data) }
        if let data = records["runningLibrary"] { _ = try decoder.decode([RunningWorkoutTemplate].self, from: data) }
        if let data = records["exerciseLibrary"] { _ = try decoder.decode([Exercise].self, from: data) }
    }
}

enum BackupError: LocalizedError {
    case invalidBackup, tooLarge, accountChanged, consentRequired
    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "This backup is incompatible or belongs to another account. Nothing was restored."
        case .tooLarge: return "This backup is too large. Your local data is safe; contact support."
        case .accountChanged: return "Your account changed. Please try again."
        case .consentRequired: return "Enable cloud backup before uploading training data."
        }
    }
}

struct TrainingBackupRow: Codable, Identifiable {
    let user_id: UUID
    let device_id: UUID
    let payload: TrainingBackupPayload
    let updated_at: Date
    var id: UUID { device_id }
}

@MainActor
final class TrainingBackupStore: ObservableObject {
    @Published private(set) var status = "Cloud backup is off until you choose to enable it."
    @Published private(set) var enabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var available: [TrainingBackupRow] = []
    private var lastPayload: TrainingBackupPayload?
    private var accountID: UUID?
    private var changes = TrainingBackupChangeTracker()
    private var isDirty: Bool {
        get { changes.isDirty }
        set { changes.isDirty = newValue }
    }
    private var scheduledBackupTask: Task<Void, Never>?
    private var lastSuccessfulBackupAt: Date?
    private let automaticBackupDelay: Duration = .seconds(20)
    private let client = SupabaseEnvironment.client
    let deviceID: UUID

    init() {
        // UserDefaults can be restored by iCloud. A new installation must get its own slot.
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("athlth-backup-device")
        if let data = try? String(contentsOf: url, encoding: .utf8), let id = UUID(uuidString: data) {
            deviceID = id
        } else {
            let id = UUID(); deviceID = id
            try? id.uuidString.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func switchAccount(_ id: UUID?) {
        scheduledBackupTask?.cancel()
        scheduledBackupTask = nil
        accountID = id
        lastPayload = nil
        isDirty = false
        available = []
        enabled = id.flatMap {
            AccountLocalStorage.read(
                Bool.self,
                name: "cloudBackupConsent",
                userID: $0
            )
        } ?? false
        lastSuccessfulBackupAt = id.flatMap {
            AccountLocalStorage.read(
                Date.self,
                name: "cloudBackupLastSuccessfulAt",
                userID: $0
            )
        }
        status =
            id == nil
                ? "Sign in to manage cloud backups."
                : enabled
                    ? "Automatic backup is ready."
                    : "Automatic training backup is off."
    }

    private struct ConsentChange: Encodable {
        let p_enabled: Bool
        let p_delete: Bool
    }
    private struct RemoteConsent: Decodable { let enabled: Bool }

    private func rememberConsent(_ value: Bool, userID: UUID) {
        enabled = value
        AccountLocalStorage.write(
            value,
            name: "cloudBackupConsent",
            userID: userID
        )
        AccountLocalStorage.write(
            Date(),
            name: "cloudBackupConsentChangedAt",
            userID: userID
        )
        lastPayload = nil

        if value {
            markDirty(userID: userID)
        } else {
            scheduledBackupTask?.cancel()
            scheduledBackupTask = nil
            isDirty = false
        }
    }

    func setEnabled(_ value: Bool) async {
        guard let userID = accountID, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        // Stop this device immediately, even if server revocation needs a retry.
        if !value { rememberConsent(false, userID: userID) }
        do {
            try checkAccount(userID)
            try await client.rpc("set_training_backup_consent", params: ConsentChange(p_enabled: value, p_delete: false)).execute()
            try checkAccount(userID)
            rememberConsent(value, userID: userID)
            status = value ? "Cloud backup enabled. Waiting for the next backup." : "Backup stopped for this account. Existing copies remain until you delete them."
            if value {
                // The first copy must not depend on keeping the app open for five minutes.
                isBusy = false
                await backUp(userID: userID, force: true)
            }
        } catch {
            if accountID == userID {
                status = value ? "Could not enable backup: \(error.localizedDescription)" : "Stopped on this phone. Could not stop other devices; reconnect and turn backup off again: \(error.localizedDescription)"
            }
        }
    }

    func deleteCloudBackups(userID: UUID) async {
        guard !isBusy else { return }
        guard accountID == userID else { return }
        rememberConsent(false, userID: userID)
        isBusy = true
        defer { isBusy = false }
        do {
            try checkAccount(userID)
            try await client.rpc("set_training_backup_consent", params: ConsentChange(p_enabled: false, p_delete: true)).execute()
            try checkAccount(userID)
            available = []
            status = "Cloud backup records deleted. Local data is unchanged. Provider disaster-recovery copies follow its retention policy."
        } catch { if accountID == userID { status = "Backup is off, but deletion failed: \(error.localizedDescription). Try again." } }
    }

    func beginChangeTracking(userID: UUID) {
        guard accountID == userID else { return }
        isDirty = false
    }

    func markDirty(userID: UUID) {
        guard accountID == userID else { return }

        changes.markDirty()
        guard enabled else { return }
        scheduleAutomaticBackup(userID: userID)
    }

    private func scheduleAutomaticBackup(userID: UUID) {
        guard scheduledBackupTask == nil,
              enabled,
              accountID == userID
        else {
            return
        }

        scheduledBackupTask = Task { @MainActor in
            try? await Task.sleep(
                for: automaticBackupDelay
            )

            guard !Task.isCancelled else { return }
            scheduledBackupTask = nil

            await backUp(userID: userID)

            if isDirty,
               enabled,
               accountID == userID {
                scheduleAutomaticBackup(
                    userID: userID
                )
            }
        }
    }

    func performFailsafeBackup(
        userID: UUID,
        maximumAge: TimeInterval = 30 * 60
    ) async {
        guard enabled,
              accountID == userID
        else {
            return
        }

        if isDirty {
            await backUp(userID: userID)
            return
        }

        guard lastSuccessfulBackupAt == nil ||
              Date().timeIntervalSince(
                lastSuccessfulBackupAt ?? .distantPast
              ) >= maximumAge
        else {
            return
        }

        // The failsafe intentionally captures once even when no dirty event
        // was observed. It protects against a future persistence path that
        // forgets to emit a dirty signal without returning to frequent polling.
        await backUp(
            userID: userID,
            force: true
        )
    }

    private func checkAccount(_ id: UUID) throws {
        guard accountID == id, client.auth.currentUser?.id == id else { throw BackupError.accountChanged }
    }

    func backUp(userID: UUID, force: Bool = false) async {
        guard enabled, !isBusy else { return }
        guard force || isDirty else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            try checkAccount(userID)
            let capturedRevision = changes.revision
            let payload = try TrainingBackupPayload.capture(
                userID: userID
            )

            if !force,
               let lastPayload,
               payload == lastPayload {
                isDirty = false
                return
            }

            try await upload(
                payload,
                deviceID: deviceID
            )
            try checkAccount(userID)

            let completedAt = Date()
            lastPayload = payload
            // An edit may arrive while the previous snapshot is uploading.
            // Leave it pending so the scheduler uploads the newer snapshot.
            changes.didUpload(revision: capturedRevision)
            lastSuccessfulBackupAt = completedAt
            AccountLocalStorage.write(
                completedAt,
                name: "cloudBackupLastSuccessfulAt",
                userID: userID
            )
            status =
                "Backed up \(completedAt.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            if accountID == userID {
                status =
                    "Backup pending: \(error.localizedDescription) Your data remains on this phone."
            }
        }
    }

    private func upload(_ payload: TrainingBackupPayload, deviceID: UUID) async throws {
        try checkAccount(payload.ownerID)
        guard enabled else { throw BackupError.consentRequired }
        let consents: [RemoteConsent] = try await client.from("training_backup_consent").select("enabled").eq("user_id", value: payload.ownerID).execute().value
        try checkAccount(payload.ownerID)
        guard consents.first?.enabled == true else {
            rememberConsent(false, userID: payload.ownerID)
            throw BackupError.consentRequired
        }
        try payload.validate(for: payload.ownerID)
        guard try JSONEncoder().encode(payload).count <= 20_000_000 else { throw BackupError.tooLarge }
        let row = TrainingBackupRow(user_id: payload.ownerID, device_id: deviceID, payload: payload, updated_at: Date())
        try await client.from("account_training_backups").upsert(row, onConflict: "user_id,device_id").execute()
    }

    func loadBackups(userID: UUID) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try checkAccount(userID)
            let rows: [TrainingBackupRow] = try await client.from("account_training_backups").select().eq("user_id", value: userID).order("updated_at", ascending: false).limit(20).execute().value
            try checkAccount(userID)
            available = rows
            if rows.isEmpty { status = "No cloud backups yet. Use Back up now to create one." }
        } catch { if accountID == userID { status = error.localizedDescription } }
    }

    func restore(_ row: TrainingBackupRow, userID: UUID) async -> Bool {
        guard enabled, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try checkAccount(userID)
            guard row.user_id == userID else { throw BackupError.invalidBackup }
            try row.payload.validate(for: userID)
            // A separate recovery slot keeps the pre-restore state available.
            try await upload(.capture(userID: userID), deviceID: UUID())
            try checkAccount(userID)
            var restoredRecords = row.payload.records
            if let data = restoredRecords["training"] {
                var training = try JSONDecoder().decode(AccountTrainingContent.self, from: data)
                training.onboardingProfile = AccountLocalStorage.read(AccountTrainingContent.self, name: "training", userID: userID)?.onboardingProfile
                restoredRecords["training"] = try JSONEncoder().encode(training)
            }
            for name in TrainingBackupPayload.names {
                let key = AccountLocalStorage.key(name, userID: userID)
                if let data = restoredRecords[name] { UserDefaults.standard.set(data, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            lastPayload = nil
            markDirty(userID: userID)
            status = "Training data restored. Your previous data is also backed up."
            return true
        } catch {
            if accountID == userID { status = error.localizedDescription }
            return false
        }
    }
}
