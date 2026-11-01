import Foundation

/// Reusable main-section recipe, not a strength exercise or complete workout.
/// The original group relationships are stored and remapped on every insert.
struct ATHLTHRunningMainSet: Codable, Identifiable {
    let id: UUID
    let title: String
    let blocks: [WorkoutTemplateBlock]
    let savedAt: Date

    private static let storageName = "runningMainSets.v1"

    static func load(userID: UUID) -> [Self] {
        (AccountLocalStorage.read([Self].self, name: storageName, userID: userID) ?? [])
            .sorted { $0.savedAt > $1.savedAt }
    }

    @discardableResult
    static func save(title: String, from source: [WorkoutTemplateBlock],
                     userID: UUID) -> Bool {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let main = source.filter { $0.resolvedPhase == .main }
        guard !cleaned.isEmpty,
              main.contains(where: { $0.kind == .run && $0.cardioActivity != .walking }),
              main.allSatisfy({ $0.kind == .run || $0.kind == .rest }) else {
            return false
        }

        var copy = main
        for index in copy.indices {
            copy[index].phase = .main
        }
        var saved = load(userID: userID)
        saved.insert(Self(id: UUID(), title: cleaned, blocks: copy, savedAt: Date()), at: 0)
        AccountLocalStorage.write(saved, name: storageName, userID: userID)
        return true
    }

    func inserting(in phase: WorkoutPhaseKind = .main) -> [WorkoutTemplateBlock] {
        var groupIDs: [UUID: UUID] = [:]
        return blocks.enumerated().map { index, original in
            var block = original
            block.phase = phase
            block.editorDragID = UUID()
            if let originalID = original.groupID {
                if groupIDs[originalID] == nil { groupIDs[originalID] = UUID() }
                block.groupID = groupIDs[originalID]
            }
            return ATHLTHWorkoutPhasePlacement.renumbered(block, sequence: index + 1)
        }
    }
}
