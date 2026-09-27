import Foundation

enum PrivacyVisibilityRules {
    static func scope(enabled: Bool, current: String, profile: String) -> String {
        guard enabled, profile != "private" else { return "private" }
        if profile == "friends" { return "friends" }
        guard profile == "public" else { return "private" }
        return current == "friends" ? "friends" : "public"
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
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key(name, userID: userID))
    }
}
