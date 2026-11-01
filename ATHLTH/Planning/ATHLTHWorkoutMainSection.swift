import Foundation

/// An automatically indexed, reusable snapshot of a saved workout's Main
/// phase. It is independent of the scheduled session and is never recorded as
/// an exercise, so moving/reusing it cannot change the original workout.
struct ATHLTHWorkoutMainSection: Codable, Identifiable {
    let id: UUID
    let sourceWorkoutID: UUID
    var title: String
    var kind: WorkoutKind
    var blocks: [WorkoutTemplateBlock]
    var savedAt: Date

    /// The running picker must remain running-only, while the shared library
    /// can also index strength, cycling, mobility and hybrid main sections.
    var isRunningOnly: Bool {
        blocks.contains { $0.kind == .run && $0.cardioActivity != .walking } &&
        blocks.allSatisfy {
            ($0.kind == .run && $0.cardioActivity != .walking) ||
            $0.kind == .rest
        }
    }

    func blocksForReuse(in phase: WorkoutPhaseKind = .main) -> [WorkoutTemplateBlock] {
        var remappedGroups: [UUID: UUID] = [:]
        return blocks.enumerated().map { index, original in
            var block = original
            block.phase = phase
            block.editorDragID = UUID()
            if let previousGroup = original.groupID {
                if remappedGroups[previousGroup] == nil {
                    remappedGroups[previousGroup] = UUID()
                }
                block.groupID = remappedGroups[previousGroup]
            }
            return ATHLTHWorkoutPhasePlacement.renumbered(block, sequence: index + 1)
        }
    }
}

/// This is a shared save-time policy, not a "Save main set" action inside
/// any specific workout editor. Only committed sessions are captured.
@MainActor
enum ATHLTHWorkoutMainSectionLibrary {
    private static let storageName = "workoutMainSections.v1"

    static func load(userID: UUID) -> [ATHLTHWorkoutMainSection] {
        (AccountLocalStorage.read(
            [ATHLTHWorkoutMainSection].self,
            name: storageName,
            userID: userID
        ) ?? []).sorted { $0.savedAt > $1.savedAt }
    }

    @discardableResult
    static func capture(_ workout: PlannedSession, userID: UUID) -> Bool {
        // Use the unified recipe even for historic strength/running sessions
        // that still store their steps in older source-specific fields.
        let source = workout.resolvedWorkoutBlocks
        let main = source.filter { $0.resolvedPhase == .main }
        guard !main.isEmpty else { return false }

        let copied = main.enumerated().map { index, original in
            var block = original
            block.phase = .main
            return ATHLTHWorkoutPhasePlacement.renumbered(block, sequence: index + 1)
        }
        let trimmed = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? workout.kind.title : trimmed
        var saved = load(userID: userID)

        if let index = saved.firstIndex(where: { $0.sourceWorkoutID == workout.id }) {
            // No extra disk write for repeated saves of an unchanged workout.
            if saved[index].title == title &&
               saved[index].kind == workout.kind &&
               saved[index].blocks == copied {
                return true
            }
            saved[index].title = title
            saved[index].kind = workout.kind
            saved[index].blocks = copied
            saved[index].savedAt = Date()
        } else {
            saved.append(ATHLTHWorkoutMainSection(
                id: UUID(),
                sourceWorkoutID: workout.id,
                title: title,
                kind: workout.kind,
                blocks: copied,
                savedAt: Date()
            ))
        }
        AccountLocalStorage.write(saved, name: storageName, userID: userID)
        return true
    }

    static func delete(_ id: UUID, userID: UUID) {
        let remaining = load(userID: userID).filter { $0.id != id }
        AccountLocalStorage.write(remaining, name: storageName, userID: userID)
    }
}
