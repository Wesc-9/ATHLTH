import Foundation

/// Explicit per-question selection of the data classes Coach may receive.
/// This is a further restriction, never an authorization grant.
struct ATHLTHCoachProgressScope: Equatable {
    enum Category: String, CaseIterable, Identifiable {
        case strength, running, recovery, goals, plan
        var id: String { rawValue }
        var title: String {
            switch self {
            case .strength: return ATHLTHLocalization.choose(english: "Strength sessions", norwegian: "Styrkeøkter")
            case .running: return ATHLTHLocalization.choose(english: "Running sessions", norwegian: "Løpeøkter")
            case .recovery: return ATHLTHLocalization.choose(english: "Recovery and sleep", norwegian: "Restitusjon og søvn")
            case .goals: return ATHLTHLocalization.choose(english: "Goals", norwegian: "Mål")
            case .plan: return ATHLTHLocalization.choose(english: "Active training plan", norwegian: "Aktiv treningsplan")
            }
        }
    }

    var selected: Set<Category>
    var windowDays: Int = 56
    func contains(_ category: Category) -> Bool { selected.contains(category) }
}
