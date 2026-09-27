import Foundation
import Supabase

struct TrainingBackupPayload: Codable, Equatable {
    let version: Int
    let ownerID: UUID
    let records: [String: Data]

    static let names = ["training", "goals", "strengthHistory", "runningLibrary", "exerciseLibrary", "coach", "phoneHistory"]

    static func capture(userID: UUID) -> Self {
        var records: [String: Data] = [:]
        for name in names {
            if let data = UserDefaults.standard.data(forKey: AccountLocalStorage.key(name, userID: userID)) { records[name] = data }
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
        if let data = records["training"] { _ = try decoder.decode(AccountTrainingContent.self, from: data) }
        if let data = records["goals"] { _ = try decoder.decode([ATHLTHGoal].self, from: data) }
        if let data = records["strengthHistory"] { _ = try decoder.decode([StrengthWorkoutLog].self, from: data) }
        if let data = records["runningLibrary"] { _ = try decoder.decode([RunningWorkoutTemplate].self, from: data) }
        if let data = records["exerciseLibrary"] { _ = try decoder.decode([Exercise].self, from: data) }
    }
}

enum BackupError: LocalizedError {
    case invalidBackup, tooLarge, accountChanged
    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "This backup is incompatible or belongs to another account. Nothing was restored."
        case .tooLarge: return "This backup is too large. Your local data is safe; contact support."
        case .accountChanged: return "Your account changed. Please try again."
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
    @Published private(set) var status = "Automatic backup is ready when you sign in."
    @Published private(set) var isBusy = false
    @Published private(set) var available: [TrainingBackupRow] = []
    private var lastPayload: TrainingBackupPayload?
    private var accountID: UUID?
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
        accountID = id
        lastPayload = nil
        available = []
        status = id == nil ? "Sign in to back up your training data." : "Automatic backup pending."
    }

    private func checkAccount(_ id: UUID) throws {
        guard accountID == id, client.auth.currentUser?.id == id else { throw BackupError.accountChanged }
    }

    func backUp(userID: UUID, force: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try checkAccount(userID)
            let payload = TrainingBackupPayload.capture(userID: userID)
            guard force || payload != lastPayload else { return }
            try await upload(payload, deviceID: deviceID)
            try checkAccount(userID)
            lastPayload = payload
            status = "Backed up \(Date().formatted(date: .abbreviated, time: .shortened))."
        } catch {
            if accountID == userID { status = "Backup pending: \(error.localizedDescription) Your data remains on this phone." }
        }
    }

    private func upload(_ payload: TrainingBackupPayload, deviceID: UUID) async throws {
        try checkAccount(payload.ownerID)
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
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try checkAccount(userID)
            guard row.user_id == userID else { throw BackupError.invalidBackup }
            try row.payload.validate(for: userID)
            // A separate recovery slot keeps the pre-restore state available.
            try await upload(.capture(userID: userID), deviceID: UUID())
            try checkAccount(userID)
            for name in TrainingBackupPayload.names {
                let key = AccountLocalStorage.key(name, userID: userID)
                if let data = row.payload.records[name] { UserDefaults.standard.set(data, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            lastPayload = nil
            status = "Training data restored. Your previous data is also backed up."
            return true
        } catch {
            if accountID == userID { status = error.localizedDescription }
            return false
        }
    }
}
