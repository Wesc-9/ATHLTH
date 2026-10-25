import Foundation

/// Makes a compact interval group individually editable using the same steps
/// as live execution. No persisted schema or workout engine is changed.
enum ATHLTHIntervalGroupEditing {
    static func canIndividualize(in blocks: [WorkoutTemplateBlock], groupID: UUID) -> Bool {
        editableRange(in: blocks, groupID: groupID) != nil
    }

    static func individualSteps(
        in blocks: [WorkoutTemplateBlock], groupID: UUID
    ) -> [WorkoutTemplateBlock]? {
        guard let range = editableRange(in: blocks, groupID: groupID) else { return nil }
        let expanded = Array(blocks[range]).expandedForExecution()
        var result = blocks
        result.replaceSubrange(range, with: expanded)
        return result.enumerated().map { index, block in
            ATHLTHWorkoutPhasePlacement.renumbered(block, sequence: index + 1)
        }
    }

    private static func editableRange(
        in blocks: [WorkoutTemplateBlock], groupID: UUID
    ) -> ClosedRange<Int>? {
        let indices = blocks.indices.filter { blocks[$0].groupID == groupID }
        guard let first = indices.first, let last = indices.last,
              indices.count == last - first + 1,
              blocks[first].groupKind == .intervals else { return nil }
        let members = Array(blocks[first...last])
        let rounds = min(max(blocks[first].groupRounds ?? 1, 1), 20)
        // Reject an over-limit draft rather than silently truncate its recipe.
        let expected = members.count * rounds -
            (rounds > 1 && members.last?.kind == .rest ? 1 : 0)
        guard expected <= 1_000, blocks.count - members.count + expected <= 200 else {
            return nil
        }
        return first...last
    }
}
