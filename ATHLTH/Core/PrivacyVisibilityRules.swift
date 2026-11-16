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

    static func write<T: Encodable>(_ value: T, name: String, userID: UUID, defaults: UserDefaults = .standard) {
        try? writeChecked(value, name: name, userID: userID, defaults: defaults)
    }

    /// Critical transitions must handle encoding failure instead of discarding it.
    static func writeChecked<T: Encodable>(_ value: T, name: String, userID: UUID, defaults: UserDefaults = .standard) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: key(name, userID: userID))
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
