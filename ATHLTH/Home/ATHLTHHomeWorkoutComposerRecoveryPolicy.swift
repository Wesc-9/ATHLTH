import Foundation

/// Restore only the signed-in athlete's recoverable day-workout editor.
enum ATHLTHHomeWorkoutComposerRecoveryPolicy {
    /// Zero is an empty SceneStorage sentinel, not January 1, 2001.
    /// Never turn it into a visible planned workout date.
    static func validComposerDate(
        referenceInterval: TimeInterval,
        fallback: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard referenceInterval.isFinite, referenceInterval > 0 else {
            return calendar.startOfDay(for: fallback)
        }
        return Date(timeIntervalSinceReferenceDate: referenceInterval)
    }

    static func canRestore(account: String, currentAccountID: UUID, day: TimeInterval) -> Bool {
        account == currentAccountID.uuidString && day.isFinite && day > 0
    }

    /// SceneStorage can re-open a sheet while iOS keeps the scene alive, but it
    /// is not a reliable cold-launch checkpoint after the app is terminated.
    /// Persist the *presentation intent*, not the workout payload (owned by
    /// the account-scoped editor and timeline draft stores).
    struct Intent: Codable, Equatable {
        let accountID: UUID
        let day: TimeInterval
        let updatedAt: Date
    }

    private static let storageKey = "athlth.home.workoutComposer.intent.v2"

    static func save(
        accountID: UUID,
        day: TimeInterval,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard day.isFinite, day > 0 else { return }
        let intent = Intent(accountID: accountID, day: day, updatedAt: now)
        if let data = try? JSONEncoder().encode(intent) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func load(
        for accountID: UUID,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Intent? {
        guard let data = defaults.data(forKey: storageKey),
              let intent = try? JSONDecoder().decode(Intent.self, from: data),
              intent.accountID == accountID,
              canRestore(
                account: intent.accountID.uuidString,
                currentAccountID: accountID,
                day: intent.day
              ),
              intent.updatedAt <= now.addingTimeInterval(300),
              now.timeIntervalSince(intent.updatedAt) < 14 * 86_400
        else { return nil }
        return intent
    }

    /// An explicit save/cancel clears only this athlete's intent; a temporary
    /// account switch cannot erase the other account's unfinished editor.
    static func clear(
        for accountID: UUID,
        defaults: UserDefaults = .standard
    ) {
        guard let data = defaults.data(forKey: storageKey),
              let intent = try? JSONDecoder().decode(Intent.self, from: data),
              intent.accountID == accountID else { return }
        defaults.removeObject(forKey: storageKey)
    }
}
