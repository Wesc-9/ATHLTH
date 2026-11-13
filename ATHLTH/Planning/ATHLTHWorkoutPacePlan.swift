import Foundation

/// Personal pace choices are overlays on a workout's existing ordered recipe.
/// Never replace warm-up/recovery durations, distances or source HR guidance.
struct ATHLTHWorkoutPacePlan: Equatable {
    enum Scope: String, CaseIterable, Identifiable {
        case allWork
        case selectedSteps
        case individual
        var id: String { rawValue }
    }

    var scope: Scope
    var sharedPaceSecondsPerKilometer: Int
    var selectedIndices: [Int] = []
    var individualPaces: [Int: Int] = [:]

    static func eligibleIndices(in blocks: [WorkoutTemplateBlock]) -> [Int] {
        blocks.indices.filter { blocks[$0].kind == .run }
    }

    static func suggestedWorkIndices(in blocks: [WorkoutTemplateBlock]) -> [Int] {
        blocks.indices.filter {
            let block = blocks[$0]
            return block.kind == .run &&
                block.resolvedPhase == .main && !block.isActiveRecovery
        }
    }

    func pace(for block: WorkoutTemplateBlock, at index: Int) -> Int? {
        guard block.kind == .run else { return nil }
        let target: Int?
        switch scope {
        case .allWork:
            target = block.resolvedPhase == .main && !block.isActiveRecovery
                ? sharedPaceSecondsPerKilometer : nil
        case .selectedSteps:
            target = selectedIndices.contains(index)
                ? sharedPaceSecondsPerKilometer : nil
        case .individual:
            target = selectedIndices.contains(index)
                ? individualPaces[index] ?? sharedPaceSecondsPerKilometer : nil
        }
        guard let target, (120...959).contains(target) else { return nil }
        return target
    }
}
