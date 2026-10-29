import Foundation

/// Shared, metadata-driven discovery rules for the *existing* workout
/// library. All sources (scheduled, personal, published and running) are
/// evaluated by the same criteria before returning a PlannedSession to
/// the original editor. No activity-specific recipe catalog is maintained.
struct ATHLTHWorkoutDiscoveryFilter {
    enum Duration: String, CaseIterable, Identifiable {
        case any, short, medium, long
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: return ATHLTHLocalization.choose(
                english: "Any duration", norwegian: "Alle lengder"
            )
            case .short: return ATHLTHLocalization.choose(
                english: "Under 30 min", norwegian: "Under 30 min"
            )
            case .medium: return "30–60 min"
            case .long: return ATHLTHLocalization.choose(
                english: "Over 60 min", norwegian: "Over 60 min"
            )
            }
        }
        func matches(minutes: Double?) -> Bool {
            if self == .any { return true }
            guard let minutes, minutes.isFinite, minutes > 0 else { return false }
            switch self {
            case .any: return true
            case .short: return minutes < 30
            case .medium: return (30...60).contains(minutes)
            case .long: return minutes > 60
            }
        }
    }

    var muscleGroups: Set<String> = []
    var runningType: RunningWorkoutType?
    var duration: Duration = .any

    func matches(_ entry: WorkoutTemplateCatalogEntry) -> Bool {
        guard duration.matches(minutes: entry.estimatedDurationMinutes.map(Double.init))
        else { return false }
        if !muscleGroups.isEmpty &&
            !Self.matchesMuscles(
                tags: entry.tags, blocks: entry.blocks, chosen: muscleGroups
            ) {
            return false
        }
        if let runningType {
            return Self.matchesRunningType(
                runningType, tags: entry.tags, blocks: entry.blocks
            )
        }
        return true
    }

    func matches(
        _ workout: PlannedSession,
        catalogEntry: WorkoutTemplateCatalogEntry? = nil
    ) -> Bool {
        guard duration.matches(
            minutes: workout.durationMinutes.map(Double.init) ??
                catalogEntry?.estimatedDurationMinutes.map(Double.init)
        ) else { return false }
        let recipeBlocks = workout.resolvedWorkoutBlocks
        // A personal copy may carry only the source workout ID and recipe,
        // without the publisher's muscle tags. Resolve its original metadata
        // from the *same* catalog rather than guessing from a workout title.
        if !muscleGroups.isEmpty &&
            !Self.matchesMuscles(
                tags: catalogEntry?.tags ?? [],
                blocks: recipeBlocks,
                chosen: muscleGroups
            ) {
            return false
        }
        if let runningType {
            if workout.resolvedRunningWorkouts.contains(where: {
                $0.type == runningType
            }) { return true }
            return Self.matchesRunningType(
                runningType, tags: catalogEntry?.tags ?? [],
                blocks: recipeBlocks
            )
        }
        return true
    }

    func matches(_ workout: RunningWorkoutTemplate) -> Bool {
        guard runningType == nil || workout.type == runningType else { return false }
        return duration.matches(
            minutes: workout.estimatedDurationSeconds.map { $0 / 60 }
        )
    }

    /// Only actual exercise metadata, not the name of a workout, decides
    /// its muscles. "Arms" and "legs" expand to their anatomical groups.
    static func matchesMuscles(
        tags: [String],
        blocks: [WorkoutTemplateBlock],
        chosen: Set<String>
    ) -> Bool {
        guard !chosen.isEmpty else { return true }
        let tokens = Set((tags + blocks.flatMap {
            ($0.exerciseSnapshot?.primaryMuscles ?? []) +
            ($0.exerciseSnapshot?.secondaryMuscles ?? [])
        }).map(normalize))
        return chosen.contains { selected in
            aliases(for: selected).contains(where: tokens.contains)
        }
    }

    private static func aliases(for muscle: String) -> Set<String> {
        switch muscle {
        case "chest": return ["chest", "bryst", "pectoral", "pectorals", "pecs"]
        case "back": return ["back", "rygg", "lats", "latissimus", "upper back", "lower back"]
        case "shoulders": return ["shoulders", "skuldre", "delts", "deltoids"]
        case "arms": return ["arms", "armer", "biceps", "triceps", "forearms", "underarmer"]
        case "biceps": return ["biceps"]
        case "triceps": return ["triceps"]
        case "core": return ["core", "kjerne", "abs", "mage", "abdominals"]
        case "glutes": return ["glutes", "setemuskler", "sete"]
        case "legs": return ["legs", "bein", "lower body", "underkropp",
                              "quads", "quadriceps", "hamstrings", "calves", "legger"]
        case "quads": return ["quads", "quadriceps", "forside lår"]
        case "hamstrings": return ["hamstrings", "bakside lår"]
        case "calves": return ["calves", "legger"]
        case "fullbody": return ["fullbody", "full body", "fullkropp"]
        default: return [normalize(muscle)]
        }
    }

    private static func matchesRunningType(
        _ selected: RunningWorkoutType,
        tags: [String],
        blocks: [WorkoutTemplateBlock]
    ) -> Bool {
        let wanted = normalize(selected.rawValue)
        let labels = Set(tags.map(normalize))
        if labels.contains(wanted) ||
            labels.contains(normalize(selected.title)) { return true }
        // Older catalog recipes may encode intervals in their structured
        // block group, even when they do not carry a running-type tag.
        if wanted.contains("interval") {
            return blocks.contains { $0.groupKind == .intervals }
        }
        return false
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
