import Foundation

/// A small, local-only checkpoint for the plan creation wizard.
/// Intentionally excludes injuries, health history, free-text notes, goal details
/// and other potentially sensitive inputs. It never creates an active plan.
struct ATHLTHPlanCreationDraft: Codable, Equatable {
    static let schemaVersion = 1
    static let lifetime: TimeInterval = 45 * 24 * 60 * 60

    let schemaVersion: Int
    var title: String
    var weekCount: Int
    var startDate: Date
    var advanced: Bool
    var source: String
    var stage: String
    var savedAt: Date

    init(
        title: String,
        weekCount: Int,
        startDate: Date,
        advanced: Bool,
        source: String,
        stage: String,
        savedAt: Date = Date()
    ) {
        self.schemaVersion = Self.schemaVersion
        self.title = String(title.prefix(40))
        self.weekCount = min(max(weekCount, 1), 52)
        self.startDate = startDate
        self.advanced = advanced
        self.source = source
        self.stage = stage
        self.savedAt = savedAt
    }

    func isRestorable(at date: Date = Date()) -> Bool {
        schemaVersion == Self.schemaVersion &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...52).contains(weekCount) &&
        savedAt <= date &&
        date.timeIntervalSince(savedAt) <= Self.lifetime
    }
}

/// Isolate each signed-in user to a different key; do not persist any
/// personal health/limitation text in this convenience checkpoint.
struct ATHLTHPlanCreationDraftStore {
    var defaults: UserDefaults = .standard

    private func key(userID: UUID) -> String {
        "athlth.planWizardDraft.v1.\(userID.uuidString)"
    }

    func save(_ draft: ATHLTHPlanCreationDraft, userID: UUID) {
        guard draft.isRestorable() else {
            clear(userID: userID)
            return
        }
        guard let encoded = try? JSONEncoder().encode(draft) else {
            return
        }
        defaults.set(encoded, forKey: key(userID: userID))
    }

    func load(userID: UUID, at date: Date = Date()) -> ATHLTHPlanCreationDraft? {
        guard let data = defaults.data(forKey: key(userID: userID)),
              let draft = try? JSONDecoder().decode(ATHLTHPlanCreationDraft.self, from: data),
              draft.isRestorable(at: date) else {
            return nil
        }
        return draft
    }

    func clear(userID: UUID) {
        defaults.removeObject(forKey: key(userID: userID))
    }
}
