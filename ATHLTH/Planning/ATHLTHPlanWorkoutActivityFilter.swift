import Foundation

/// Activity chips for the existing plan-workout library. This never changes
/// library sources or classifies a recipe by guessing from its title.
enum ATHLTHPlanWorkoutActivityFilter: String, CaseIterable, Identifiable {
    case all, running, walking, strength, cycling, mobility, hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .walking: return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gå")
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .cycling: return ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
        case .mobility: return ATHLTHLocalization.choose(english: "Mobility", norwegian: "Mobilitet")
        case .hybrid: return "Hybrid"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell"
        case .cycling: return "bicycle"
        case .mobility: return "figure.flexibility"
        case .hybrid: return "figure.mixed.cardio"
        }
    }

    func matches(_ workout: PlannedSession) -> Bool {
        if self == .all { return true }

        let category = workout.workoutCategory?.lowercased() ?? ""
        let blocks = workout.resolvedWorkoutBlocks
        let running = blocks.contains {
            $0.kind == .run && $0.cardioActivity != .walking &&
                !$0.isActiveRecovery
        }
        let walking = blocks.contains {
            $0.kind == .run && $0.cardioActivity == .walking
        }
        let strength = blocks.contains { $0.kind == .exercise }
        let cycling = blocks.contains { $0.activityTag == "cycling" }
        let wellness = blocks.contains { $0.wellnessKind != nil }
        let kinds = [running, walking, strength, cycling, wellness].filter { $0 }.count
        let isHybrid = category == "hybrid" || kinds > 1

        if isHybrid { return self == .hybrid }
        switch self {
        case .all: return true
        case .running:
            return category == "running" || category == "treadmill" ||
                running || (category.isEmpty && workout.kind == .running)
        case .walking:
            return category == "walking" || walking ||
                (category.isEmpty && workout.kind == .walking)
        case .strength:
            return category == "strength" || strength ||
                (category.isEmpty && workout.kind == .strength)
        case .cycling:
            return category == "cycling" || cycling
        case .mobility:
            return category == "mobility" || category == "recovery" ||
                wellness || (category.isEmpty &&
                    (workout.kind == .mobility || workout.kind == .recovery))
        case .hybrid:
            return isHybrid
        }
    }
}
