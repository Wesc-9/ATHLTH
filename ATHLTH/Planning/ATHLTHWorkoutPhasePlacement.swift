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
}
