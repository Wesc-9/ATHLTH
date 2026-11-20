import Foundation

enum PrivacyVisibilityRules {
    static func scope(enabled: Bool, current: String, profile: String) -> String {
        guard enabled, profile != "private" else { return "private" }
        if profile == "friends" { return "friends" }
        guard profile == "public" else { return "private" }
        return current == "public" ? "public" : "friends"
    }
}

enum AccountLocalStorage {
    static func key(_ name: String, userID: UUID) -> String {
        "account.\(userID.uuidString.lowercased()).\(name)"
    }

    static func read<T: Decodable>(_ type: T.Type, name: String, userID: UUID, defaults: UserDefaults = .standard) -> T? {
        guard let data = defaults.data(forKey: key(name, userID: userID)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // Legacy best-effort writes remain source-compatible. Critical
    // training updates must instead use writeChecked + a success receipt.
    static func write<T: Encodable>(_ value: T, name: String, userID: UUID, defaults: UserDefaults = .standard) {
        try? writeChecked(value, name: name, userID: userID, defaults: defaults)
    }

    enum StorageError: Error {
        case readBackMismatch
    }

    /// A checked write never claims success when serialization fails or
    /// the new bytes cannot be read back immediately. UserDefaults does not
    /// offer a disk-fsync guarantee; workout finish journals remain separate.
    static func writeChecked<T: Encodable>(
        _ value: T, name: String, userID: UUID,
        defaults: UserDefaults = .standard
    ) throws {
        let data = try JSONEncoder().encode(value)
        let storageKey = key(name, userID: userID)
        defaults.set(data, forKey: storageKey)
        // Readback is reserved for this critical account-training path;
        // do not duplicate multi-MB HealthKit and strength-history reads
        // for every other checked write in the app.
        if name == "training",
           defaults.data(forKey: storageKey) != data {
            throw StorageError.readBackMismatch
        }
    }
}

/// Only announce a training-data update once its account-scoped
/// serialized snapshot was actually accepted by local storage.
/// Failed writes do not clobber the last good value or tell cloud
/// coordinators that a new durable revision exists.
enum ATHLTHAccountTrainingCommit {
    static func save<Value: Encodable>(
        _ value: Value, userID: UUID,
        defaults: UserDefaults = .standard,
        onCommitted: () -> Void
    ) throws {
        try AccountLocalStorage.writeChecked(
            value, name: "training", userID: userID, defaults: defaults
        )
        onCommitted()
    }
}

// Consent is account-scoped and independent of cloud backup and HealthKit access.
enum CoachHistoryPermission {
    static func isEnabled(userID: UUID, defaults: UserDefaults = .standard) -> Bool {
        AccountLocalStorage.read(Bool.self, name: "coachHistoryConsent", userID: userID, defaults: defaults) == true
    }
}


// Feed publication is a separate, account-scoped choice. Sharing cannot be
// enabled by carrying settings over from another athlete on the same device.
enum FriendFeedSharingPreference {
    private static let storageName = "friendsFeedAutomaticSharing.v223"

    static func isEnabled(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        AccountLocalStorage.read(
            Bool.self, name: storageName, userID: userID, defaults: defaults
        ) == true
    }

    static func setEnabled(
        _ enabled: Bool,
        userID: UUID,
        defaults: UserDefaults = .standard
    ) {
        AccountLocalStorage.write(
            enabled, name: storageName, userID: userID, defaults: defaults
        )
    }
}
