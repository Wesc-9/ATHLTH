import Foundation

struct ATHLTHWorkoutTimelineSection: Identifiable {
    let id: String
    let phase: WorkoutPhaseKind
    var blocks: [WorkoutTemplateBlock]
}

/// Group adjacent phases only. A preview must never sort a recovery out of
/// the recipe or collect separated phases into a misleading execution order.
enum ATHLTHWorkoutTimelineOverview {
    static func sections(for blocks: [WorkoutTemplateBlock]) -> [ATHLTHWorkoutTimelineSection] {
        var sections: [ATHLTHWorkoutTimelineSection] = []
        for (index, block) in blocks.enumerated() {
            if sections.last?.phase == block.resolvedPhase {
                sections[sections.count - 1].blocks.append(block)
            } else {
                sections.append(.init(
                    id: "\(index)|\(block.id)", phase: block.resolvedPhase, blocks: [block]))
            }
        }
        return sections
    }
}
