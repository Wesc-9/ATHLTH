import Foundation

/// Concise and consistent summary of a structured workout in Home and Train.
enum ATHLTHWorkoutContentSummary {
    static func text(for workout: PlannedSession) -> String? {
        let blocks = workout.resolvedWorkoutBlocks
        guard !blocks.isEmpty else { return nil }

        let exercises = Set(
            blocks.filter { $0.kind == .exercise }
                .map { $0.exerciseSlug ?? $0.title }
        )
        let runningSteps = blocks.filter { $0.kind == .run }.count
        let pauses = blocks.filter { $0.kind == .rest }.count

        var parts: [String] = []
        if !exercises.isEmpty {
            parts.append(ATHLTHLocalization.choose(
                english: "\(exercises.count) exercises",
                norwegian: "\(exercises.count) øvelser"
            ))
        }
        if runningSteps > 0 {
            parts.append(ATHLTHLocalization.choose(
                english: "\(runningSteps) running sections",
                norwegian: "\(runningSteps) løpedeler"
            ))
        }
        if pauses > 0 {
            parts.append(ATHLTHLocalization.choose(
                english: "\(pauses) pauses",
                norwegian: "\(pauses) pauser"
            ))
        }
        return parts.isEmpty ? workout.kind.title : parts.joined(separator: " · ")
    }
}
