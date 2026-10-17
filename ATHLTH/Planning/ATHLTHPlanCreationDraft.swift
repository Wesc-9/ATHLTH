import Foundation

/// A compact, local-only checkpoint for the plan creation wizard.
/// Intentionally excludes injuries, health history, free-text notes, goal details
/// and other potentially sensitive inputs. It never creates an active plan.
struct ATHLTHPlanCreationDraft: Codable, Equatable {
    static let schemaVersion = 1
    static let lifetime: TimeInterval = 45 * 24 * 60 * 60

    let schemaVersion: Int
    var title: String
    var usedDefaultTitle: Bool? = nil
    var weekCount: Int
    var startDate: Date
    var advanced: Bool
    var source: String
    var stage: String
    // Optional so v1 snapshots made before the advanced-fields update still decode.
    // Only structural preferences; health, injuries and private notes are excluded.
    var preferredDayIndexes: [Int]?
    var equipmentContext: String?
    var weeklyTimeBudgetMinutes: Int?
    // Only structural week choices and built-in subtype labels are stored.
    // Custom session names and personal health notes are intentionally omitted.
    var workoutKindsByDay: [Int: String]? = nil
    var workoutPresetsByDay: [Int: String]? = nil
    var workoutMinutesByDay: [Int: Int]? = nil
    // Advanced only. Compact local checkpoint retains equipment/sets/intervals
    // but strips free-text notes and route IDs for privacy.
    var structuredWorkoutsByDay:
        [Int: ATHLTHPlanStructuredWorkoutBlueprint]? = nil
    var weekDayEdits: [Int: ATHLTHPlanWeekDayEdit]? = nil
    var planningApproach: String? = nil
    var guidedDayCursor: Int? = nil
    var firstGuidedWeekDecisionMade: Bool? = nil
    var savedAt: Date

    init(
        title: String,
        weekCount: Int,
        usedDefaultTitle: Bool = false,
        startDate: Date,
        advanced: Bool,
        source: String,
        stage: String,
        preferredDayIndexes: [Int]? = nil,
        equipmentContext: String? = nil,
        weeklyTimeBudgetMinutes: Int? = nil,
        workoutKindsByDay: [Int: String]? = nil,
        workoutPresetsByDay: [Int: String]? = nil,
        workoutMinutesByDay: [Int: Int]? = nil,
        structuredWorkoutsByDay:
            [Int: ATHLTHPlanStructuredWorkoutBlueprint]? = nil,
        weekDayEdits: [Int: ATHLTHPlanWeekDayEdit]? = nil,
        planningApproach: String? = nil,
        guidedDayCursor: Int? = nil,
        firstGuidedWeekDecisionMade: Bool? = nil,
        savedAt: Date = Date()
    ) {
        self.schemaVersion = Self.schemaVersion
        self.title = String(title.prefix(40))
        self.usedDefaultTitle = usedDefaultTitle
        self.weekCount = min(max(weekCount, 1), 52)
        self.startDate = startDate
        self.advanced = advanced
        self.source = source
        self.stage = stage
        self.planningApproach = advanced && ["quick", "guided"].contains(planningApproach ?? "")
            ? planningApproach : nil
        self.guidedDayCursor = advanced ? guidedDayCursor.map { min(max($0, 0), self.weekCount * 7) } : nil
        self.firstGuidedWeekDecisionMade = advanced ? firstGuidedWeekDecisionMade : nil
        if let preferredDayIndexes {
            let valid = Set(preferredDayIndexes.filter { (1...7).contains($0) })
            self.preferredDayIndexes = valid.isEmpty ? nil : valid.sorted()
        } else {
            self.preferredDayIndexes = nil
        }
        self.equipmentContext = equipmentContext
        self.weeklyTimeBudgetMinutes = weeklyTimeBudgetMinutes.map {
            min(max($0, 60), 1200)
        }
        self.workoutKindsByDay = workoutKindsByDay?.filter {
            (1...7).contains($0.key) && $0.value.count <= 30
        }
        self.workoutPresetsByDay = workoutPresetsByDay?.filter {
            (1...7).contains($0.key) && $0.value.count <= 40
        }
        self.workoutMinutesByDay = workoutMinutesByDay?.filter {
            (1...7).contains($0.key) && (15...180).contains($0.value)
        }
        if advanced, let structuredWorkoutsByDay {
            var sanitized: [Int: ATHLTHPlanStructuredWorkoutBlueprint] = [:]
            for (day, original) in structuredWorkoutsByDay
                where (1...7).contains(day) && original.isValid {
                var safe = original
                safe.routeID = nil
                safe.blocks = original.blocks.compactMap { block in
                    // Personal health notes and arbitrary note-only blocks are
                    // not part of a convenience checkpoint.
                    guard block.kind != .note else { return nil }
                    var copy = block
                    copy.notes = nil
                    copy.loadNote = nil
                    return copy
                }
                guard safe.isValid else { continue }
                sanitized[day] = safe
            }
            self.structuredWorkoutsByDay =
                sanitized.isEmpty ? nil : sanitized
        } else {
            self.structuredWorkoutsByDay = nil
        }
        if advanced, let weekDayEdits {
            var sanitized: [Int: ATHLTHPlanWeekDayEdit] = [:]
            for (day, original) in weekDayEdits
                where (1...(self.weekCount * 7)).contains(day) {
                var safe = original
                if let blueprint = safe.detailedWorkout {
                    var clean = blueprint
                    clean.routeID = nil
                    clean.blocks = blueprint.blocks.filter { $0.kind != .note }.map {
                        var block = $0
                        block.notes = nil
                        block.loadNote = nil
                        return block
                    }
                    safe.detailedWorkout = clean.isValid ? clean : nil
                }
                if let extras = safe.additionalDetailedWorkouts {
                    safe.additionalDetailedWorkouts = extras.compactMap { extra in
                        var clean = extra
                        clean.routeID = nil
                        clean.blocks = extra.blocks.filter { $0.kind != .note }.map {
                            var block = $0
                            block.notes = nil
                            block.loadNote = nil
                            return block
                        }
                        return clean.isValid ? clean : nil
                    }
                }
                sanitized[day] = safe
            }
            self.weekDayEdits = sanitized.isEmpty ? nil : sanitized
        } else {
            self.weekDayEdits = nil
        }
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
        guard let encoded = try? JSONEncoder().encode(draft),
              encoded.count <= 750_000 else {
            // Never save an oversized plan snapshot to UserDefaults.
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
