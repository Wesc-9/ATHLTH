import Foundation

/// A one-shot, short-lived navigation request. No account identity, workout
/// data, health data, free text or start-workout command is stored.
enum ATHLTHShortcutNavigation: String, CaseIterable {
    case coach, today, plan

    static let preferenceKey = "athlth.shortcut.navigation.v1"

    func token(now: Date = Date()) -> String {
        "\(rawValue)|\(now.timeIntervalSince1970)|\(UUID().uuidString)"
    }

    static func route(from token: String, now: Date = Date()) -> Self? {
        let parts = token.split(separator: "|")
        guard parts.count == 3, let route = Self(rawValue: String(parts[0])),
              let timestamp = Double(parts[1]), timestamp.isFinite,
              UUID(uuidString: String(parts[2])) != nil else { return nil }
        let age = now.timeIntervalSince1970 - timestamp
        guard (0...60).contains(age) else { return nil }
        return route
    }

    @MainActor
    func enqueue() {
        UserDefaults.standard.set(token(), forKey: Self.preferenceKey)
    }

    /// Multiple iPad windows may observe the same preference. Only the first
    /// active eligible shell consumes the current token.
    @MainActor
    static func consume(_ token: String) -> Self? {
        guard !token.isEmpty,
              UserDefaults.standard.string(forKey: preferenceKey) == token else { return nil }
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        return route(from: token)
    }
}
