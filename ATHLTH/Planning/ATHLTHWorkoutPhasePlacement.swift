import Foundation

/// Positions new independent blocks in the requested training phase without
/// splitting an existing interval or superset group. Saved order remains the
/// execution order; this policy only governs initial insertion.
enum ATHLTHWorkoutPhasePlacement {
    static func insertionIndex(
        for phase: WorkoutPhaseKind,
        in blocks: [WorkoutTemplateBlock]
    ) -> Int {
        let candidate: Int
        switch phase {
        case .warmup:
            candidate = blocks.firstIndex { $0.resolvedPhase != .warmup }
                ?? blocks.count
        case .main, .recovery:
            candidate = blocks.firstIndex { $0.resolvedPhase == .cooldown }
                ?? blocks.count
        case .cooldown:
            candidate = blocks.count
        }

        guard candidate > 0, candidate < blocks.count,
              let previousGroup = blocks[candidate - 1].groupID,
              previousGroup == blocks[candidate].groupID
        else { return candidate }

        // A phase boundary inside an interval group would corrupt
        // interval rounds. Insert before that entire group instead.
        var position = candidate
        while position > 0, blocks[position - 1].groupID == previousGroup {
            position -= 1
        }
        return position
    }
    /// Move a selected activity (or its entire interval/superset group) to
    /// another part of the workout. Phase and physical timeline order must
    /// change together so previews, execution and Watch get one recipe.
    static func relocatingSelection(
        at selectedIndex: Int,
        to phase: WorkoutPhaseKind,
        in blocks: [WorkoutTemplateBlock]
    ) -> [WorkoutTemplateBlock] {
        guard blocks.indices.contains(selectedIndex) else { return blocks }
        let selected = blocks[selectedIndex]
        let affectedIndices = blocks.indices.filter { index in
            if let groupID = selected.groupID {
                return blocks[index].groupID == groupID
            }
            return index == selectedIndex
        }

        // Preserve the existing order when the requested phase already
        // matches every member. This avoids unexpected jumps on reselect.
        if affectedIndices.allSatisfy({ blocks[$0].resolvedPhase == phase }) {
            return blocks
        }

        let members = affectedIndices.map { index -> WorkoutTemplateBlock in
            var copy = blocks[index]
            copy.phase = phase
            return copy
        }
        let affected = Set(affectedIndices)
        var remaining = blocks.enumerated().compactMap { index, item in
            affected.contains(index) ? nil : item
        }

        // Insert as one indivisible section at the phase boundary, never
        // within the repetitions or recovery steps of an adjacent group.
        let destination = insertionIndex(for: phase, in: remaining)
        remaining.insert(contentsOf: members, at: destination)
        for index in remaining.indices {
            remaining[index].sequence = index + 1
        }
        return remaining
    }

}
