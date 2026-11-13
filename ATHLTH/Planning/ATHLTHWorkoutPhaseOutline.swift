import Foundation

/// Linear-time display grouping. Recovery belongs visually to the preceding
/// effort, without modifying any stored execution phase or interval target.
enum ATHLTHWorkoutPhaseOutline {
    struct Section: Identifiable, Equatable {
        let id: Int
        let phase: WorkoutPhaseKind
        var indices: [Int]
    }

    static func sections(for blocks: [WorkoutTemplateBlock]) -> [Section] {
        var result: [Section] = []
        var activePhase: WorkoutPhaseKind = .main
        for (index, block) in blocks.enumerated() {
            let original = block.resolvedPhase
            let phase: WorkoutPhaseKind
            if original == .recovery {
                phase = activePhase
            } else {
                phase = original
                activePhase = original
            }
            if let last = result.indices.last, result[last].phase == phase {
                result[last].indices.append(index)
            } else {
                result.append(Section(id: index, phase: phase, indices: [index]))
            }
        }
        return result
    }
}
