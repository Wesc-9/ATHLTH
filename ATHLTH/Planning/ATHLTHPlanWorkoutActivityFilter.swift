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
        let activity = ATHLTHUnifiedActivityProfile.category(for: workout)
        if activity == "hybrid" { return self == .hybrid }
        switch self {
        case .all: return true
        case .running: return activity == "running" || activity == "treadmill"
        case .walking: return activity == "walking"
        case .strength: return activity == "strength"
        case .cycling: return activity == "cycling"
        case .mobility: return activity == "mobility" || activity == "recovery"
        case .hybrid: return false
        }
    }
}
