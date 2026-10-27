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
    // Only built-in category identifiers are stored. No private goal notes.
    var entryGoalArea: String? = nil
    var entryGoalChoice: String? = nil
    var entryPlanFocus: String? = nil
    var entryPlanGoal: String? = nil
    // Optional so v1 snapshots made before the advanced-fields update still decode.
    // Only structural preferences; health, injuries and private notes are excluded.
    var preferredDayIndexes: [Int]?
    var varyWeekdays: Bool? = nil
    var linkedGoalIDs: [UUID]? = nil
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
    // Restore the actual workspace position, not just the plan's fields.
    var selectedPlanWeekIndex: Int? = nil
    var editorDay: Int? = nil
    var editorKind: String? = nil
    var simpleMinutes: Int? = nil
    var simpleActivityKinds: [String]? = nil
    var savedAt: Date

    init(
        title: String,
        weekCount: Int,
        usedDefaultTitle: Bool = false,
        startDate: Date,
        advanced: Bool,
        source: String,
        stage: String,
        entryGoalArea: String? = nil,
        entryGoalChoice: String? = nil,
        entryPlanFocus: String? = nil,
        entryPlanGoal: String? = nil,
        preferredDayIndexes: [Int]? = nil,
        varyWeekdays: Bool = false,
        linkedGoalIDs: [UUID]? = nil,
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
        selectedPlanWeekIndex: Int? = nil,
        editorDay: Int? = nil,
        editorKind: String? = nil,
        simpleMinutes: Int? = nil,
        simpleActivityKinds: [String]? = nil,
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
        let parsedArea = entryGoalArea.flatMap(ATHLTHPlanGoalArea.init(rawValue:))
        self.entryGoalArea = parsedArea?.rawValue
        self.entryGoalChoice = entryGoalChoice.flatMap { choice in
            guard let area = parsedArea,
                  ATHLTHPlanGoalOption.options(for: area).contains(where: { $0.id == choice })
            else { return nil }
            return choice
        }
        self.entryPlanFocus = entryPlanFocus.flatMap {
            TrainingPlanFocus(rawValue: $0)?.rawValue
        }
        self.entryPlanGoal = entryPlanGoal.flatMap {
            TrainingPlanGoalType(rawValue: $0)?.rawValue
        }
        // Preserve sanitized advanced inputs even when the last visible
        // screen was Simple. The active mode is presentation, not ownership.
        self.planningApproach = ["quick", "guided"].contains(planningApproach ?? "")
            ? planningApproach : nil
        self.guidedDayCursor = guidedDayCursor.map { min(max($0, 0), min(max(weekCount, 1), 52) * 7) }
        self.firstGuidedWeekDecisionMade = firstGuidedWeekDecisionMade
        self.selectedPlanWeekIndex = selectedPlanWeekIndex.map {
            min(max($0, 0), min(max(weekCount, 1), 52) - 1)
        }
        self.editorDay = advanced && editorKind != nil ? editorDay.flatMap {
            (1...7).contains($0) ? $0 : nil
        } : nil
        self.editorKind = advanced && ["day", "studio", "library"].contains(editorKind ?? "")
            ? editorKind : nil
        self.simpleMinutes = simpleMinutes.map { min(max($0, 5), 180) }
        self.simpleActivityKinds = simpleActivityKinds?
            .filter { ["running", "walking", "strength"].contains($0) }
        if let preferredDayIndexes {
            let valid = Set(preferredDayIndexes.filter { (1...7).contains($0) })
            self.preferredDayIndexes = valid.isEmpty ? nil : valid.sorted()
        } else {
            self.preferredDayIndexes = nil
        }
        self.varyWeekdays = varyWeekdays
        self.linkedGoalIDs = linkedGoalIDs.map { Array(Set($0)).prefix(20).map { $0 } }
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
        if let structuredWorkoutsByDay {
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
        if let weekDayEdits {
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

/// Atomic, per-account checkpoint storage. Existing UserDefaults snapshots are
/// migrated on first read to avoid losing drafts created by older TestFlight builds.
/// The payload intentionally excludes injury notes, free-text notes and route IDs.
struct ATHLTHPlanDraftRecord: Identifiable {
    let draftID: UUID?
    let draft: ATHLTHPlanCreationDraft
    var id: String { draftID?.uuidString ?? "original" }
}

struct ATHLTHPlanCreationDraftStore {
    var defaults: UserDefaults = .standard
    // Injection point for isolated tests; production uses Application Support.
    var directoryURL: URL? = nil

    private func legacyKey(userID: UUID) -> String {
        "athlth.planWizardDraft.v1.\(userID.uuidString)"
    }

    private func editingKey(userID: UUID, draftID: UUID?) -> String {
        let prefix = "athlth.planWizardEditing.v1.\(userID.uuidString)"
        return draftID.map { prefix + "." + $0.uuidString } ?? prefix
    }

    // Only a non-sensitive boolean is saved outside the protected draft.
    func wasEditing(userID: UUID, draftID: UUID? = nil) -> Bool {
        defaults.bool(forKey: editingKey(userID: userID, draftID: draftID))
    }

    func setEditing(_ editing: Bool, userID: UUID, draftID: UUID? = nil) {
        defaults.set(editing, forKey: editingKey(userID: userID, draftID: draftID))
    }

    private var folder: URL? {
        directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.appendingPathComponent("ATHLTHPlanDrafts", isDirectory: true)
    }

    private func url(for userID: UUID, draftID: UUID? = nil) -> URL? {
        let base = "plan-\(userID.uuidString.lowercased())"
        let file = draftID.map { base + "-\($0.uuidString.lowercased())" } ?? base
        return folder?.appendingPathComponent(file + ".json")
    }

    func save(
        _ draft: ATHLTHPlanCreationDraft,
        userID: UUID,
        draftID: UUID? = nil
    ) {
        guard draft.isRestorable() else {
            clear(userID: userID, draftID: draftID)
            return
        }
        guard let data = try? JSONEncoder().encode(draft),
              data.count <= 8_000_000,
              let destination = url(for: userID, draftID: draftID),
              let folder else { return }
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true
            )
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS) || os(watchOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
            #endif
            try data.write(to: destination, options: options)
            // A new draft must never clear the old format's checkpoint.
            if draftID == nil {
                defaults.removeObject(forKey: legacyKey(userID: userID))
            }
        } catch {
            // Never destroy the existing valid checkpoint on a write error.
        }
    }

    func load(
        userID: UUID,
        draftID: UUID? = nil,
        at date: Date = Date()
    ) -> ATHLTHPlanCreationDraft? {
        if let url = url(for: userID, draftID: draftID),
           let bytes = try? Data(contentsOf: url),
           let draft = try? JSONDecoder().decode(ATHLTHPlanCreationDraft.self, from: bytes),
           draft.isRestorable(at: date) {
            return draft
        }

        // The legacy original must never masquerade as a new draft.
        guard draftID == nil,
              let old = defaults.data(forKey: legacyKey(userID: userID)),
              let draft = try? JSONDecoder().decode(ATHLTHPlanCreationDraft.self, from: old),
              draft.isRestorable(at: date) else { return nil }
        save(draft, userID: userID)
        return draft
    }

    /// Lists only this account's valid checkpoints, newest first.
    func records(userID: UUID) -> [ATHLTHPlanDraftRecord] {
        var result: [ATHLTHPlanDraftRecord] = []
        if let original = load(userID: userID) {
            result.append(.init(draftID: nil, draft: original))
        }
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: nil
              )
        else { return result }

        let prefix = "plan-\(userID.uuidString.lowercased())-"
        for file in files {
            let filename = file.lastPathComponent
            guard filename.hasPrefix(prefix), filename.hasSuffix(".json")
            else { continue }
            let suffix = String(filename.dropFirst(prefix.count).dropLast(5))
            guard let id = UUID(uuidString: suffix),
                  let draft = load(userID: userID, draftID: id)
            else { continue }
            result.append(.init(draftID: id, draft: draft))
        }
        return result.sorted { $0.draft.savedAt > $1.draft.savedAt }
    }

    /// Explicit user-triggered deletion. Reports failure instead of hiding a
    /// draft that could reappear after relaunch if file removal was denied.
    @discardableResult
    func deleteDraft(userID: UUID, draftID: UUID? = nil) -> Bool {
        if let url = url(for: userID, draftID: draftID),
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                return false
            }
        }
        if draftID == nil {
            defaults.removeObject(forKey: legacyKey(userID: userID))
        }
        setEditing(false, userID: userID, draftID: draftID)
        return true
    }

    func clear(userID: UUID, draftID: UUID? = nil) {
        _ = deleteDraft(userID: userID, draftID: draftID)
    }
}
