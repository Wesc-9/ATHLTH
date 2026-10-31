import Foundation

/// Reorder one workout step or its entire interval/superset group.
/// The stored timeline, not just its visual position, is updated.
enum ATHLTHStudioBlockReorder {
    static func moving(
        _ id: UUID,
        to phase: WorkoutPhaseKind,
        over targetID: UUID?,
        in source: [WorkoutTemplateBlock]
    ) -> [WorkoutTemplateBlock] {
        guard let original = source.firstIndex(where: { $0.editorDragID == id }) else {
            return source
        }

        let groupID = source[original].groupID
        let movingIndices = source.indices.filter { index in
            if let groupID { return source[index].groupID == groupID }
            return index == original
        }
        let movingIDs = Set(movingIndices.map { source[$0].editorDragID })
        if let targetID, movingIDs.contains(targetID) { return source }

        let members = movingIndices.map { index -> WorkoutTemplateBlock in
            var item = source[index]
            item.phase = phase
            return item
        }
        var remaining = source.filter { !movingIDs.contains($0.editorDragID) }

        let destination: Int
        if let targetID,
           let oldTargetIndex = source.firstIndex(where: { $0.editorDragID == targetID }),
           let targetIndex = remaining.firstIndex(where: { $0.editorDragID == targetID }) {
            let target = remaining[targetIndex]
            // Do not split an existing group while dropping on any member.
            let groupIndices = remaining.indices.filter { index in
                guard let group = target.groupID else { return index == targetIndex }
                return remaining[index].groupID == group
            }
            let movingDown = movingIndices[0] < oldTargetIndex
            destination = movingDown
                ? (groupIndices.last ?? targetIndex) + 1
                : (groupIndices.first ?? targetIndex)
        } else {
            destination = ATHLTHWorkoutPhasePlacement.insertionIndex(
                for: phase, in: remaining
            )
        }
        remaining.insert(contentsOf: members, at: destination)
        return remaining.enumerated().map { index, block in
            ATHLTHWorkoutPhasePlacement.renumbered(block, sequence: index + 1)
        }
    }
}
