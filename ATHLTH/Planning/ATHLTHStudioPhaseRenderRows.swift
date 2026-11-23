import Foundation

/// Linear-time presentation plan for a single workout phase. Keeping group
/// deduplication outside SwiftUI's ForEach avoids repeatedly walking earlier
/// rows (and recomputing interval group summaries) on every scroll update.
/// This is UI-only: exercise identities, order, and the executable recipe
/// never change.
enum ATHLTHStudioPhaseRenderRows {
    enum Kind: Equatable {
        case strengthGroup(UUID)
        case intervalGroup(UUID)
        case strengthSets
        case step
    }

    struct Item: Identifiable {
        let block: WorkoutTemplateBlock
        let position: Int
        let kind: Kind

        var id: UUID { block.editorDragID }
    }

    static func make(from blocks: [WorkoutTemplateBlock]) -> [Item] {
        var result: [Item] = []
        result.reserveCapacity(blocks.count)

        var seenStrengthGroups = Set<UUID>()
        var seenIntervalGroups = Set<UUID>()
        var intervalValidity: [UUID: Bool] = [:]

        for (position, block) in blocks.enumerated() {
            if let groupID = block.groupID,
               block.groupKind?.isStrengthGroup == true {
                if seenStrengthGroups.insert(groupID).inserted {
                    result.append(Item(
                        block: block,
                        position: position,
                        kind: .strengthGroup(groupID)
                    ))
                }
                continue
            }

            if let groupID = block.groupID {
                let valid: Bool
                if let cached = intervalValidity[groupID] {
                    valid = cached
                } else {
                    valid = ATHLTHIntervalRecipeEditing.summary(
                        for: groupID, in: blocks
                    ) != nil
                    intervalValidity[groupID] = valid
                }
                if valid {
                    if seenIntervalGroups.insert(groupID).inserted {
                        result.append(Item(
                            block: block,
                            position: position,
                            kind: .intervalGroup(groupID)
                        ))
                    }
                    continue
                }
            }

            let kind: Kind = block.kind == .exercise &&
                block.groupID == nil &&
                (block.setCount ?? 1) > 1 ? .strengthSets : .step
            result.append(Item(
                block: block,
                position: position,
                kind: kind
            ))
        }
        return result
    }
}
