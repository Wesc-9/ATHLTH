import Foundation

/// Concise and accurate summary of the *executable* structured workout in
/// Home and Train. Grouped intervals expand to their real efforts/recoveries.
enum ATHLTHWorkoutContentSummary {
    static func text(for workout: PlannedSession) -> String? {
        let blocks = workout.resolvedWorkoutBlocks
        guard !blocks.isEmpty else { return nil }
        let executed = blocks.expandedForExecution()
        guard !executed.isEmpty, executed.count <= 1_000 else { return nil }

        let exercises = Set(
            blocks.filter { $0.kind == .exercise }
                .map { $0.exerciseSlug ?? $0.title }
        )
        let runs = executed.filter {
            $0.kind == .run && $0.cardioActivity != .walking
        }.count
        let walks = executed.filter {
            $0.kind == .run && $0.cardioActivity == .walking
        }.count
        let pauses = executed.filter { $0.kind == .rest }.count
        let cycling = executed.filter {
            $0.kind == .note && $0.activityTag == "cycling"
        }.count
        let wellness = executed.filter {
            $0.kind == .note && $0.wellnessKind != nil
        }.count

        var parts: [String] = []
        if !exercises.isEmpty {
            parts.append(ATHLTHLocalization.choose(
                english: "\(exercises.count) exercises",
                norwegian: "\(exercises.count) øvelser"
            ))
        }
        if runs > 0 {
            parts.append(ATHLTHLocalization.choose(
                english: "\(runs) running sections",
                norwegian: "\(runs) løpedeler"
            ))
        }
        if walks > 0 {
            parts.append(ATHLTHLocalization.choose(
                english: "\(walks) walking sections",
                norwegian: "\(walks) gådeler"
            ))
        }
        if cycling > 0 {
            parts.append(ATHLTHLocalization.choose(
                english: "\(cycling) cycling sections",
                norwegian: "\(cycling) sykkeldeler"
            ))
        }
        if wellness > 0 {
            parts.append(ATHLTHLocalization.choose(
                english: "\(wellness) mobility/recovery sections",
                norwegian: "\(wellness) bevegelighets-/restitusjonsdeler"
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
