import Foundation

@MainActor
final class TrainingPlanStore: ObservableObject {
    @Published var selectedActivity: PlannedActivity
    @Published var selectedStrengthSplit: StrengthSplit

    private let defaults = UserDefaults.standard

    init() {
        selectedActivity = PlannedActivity(
            rawValue: defaults.string(forKey: "plannedActivity") ?? "running"
        ) ?? .running

        selectedStrengthSplit = StrengthSplit(
            rawValue: defaults.string(forKey: "strengthSplit") ?? "fullBody"
        ) ?? .fullBody
    }

    func save() {
        defaults.set(selectedActivity.rawValue, forKey: "plannedActivity")
        defaults.set(selectedStrengthSplit.rawValue, forKey: "strengthSplit")
        defaults.set(Date(), forKey: "plannedActivityUpdatedAt")
    }
}

enum PlannedActivity: String, CaseIterable, Identifiable {
    case running
    case walking
    case strength

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return "Run"
        case .walking: return "Walk"
        case .strength: return "Strength"
        }
    }

    var subtitle: String {
        switch self {
        case .running: return "Distance, pace and heart rate"
        case .walking: return "Movement, route and heart rate"
        case .strength: return "Choose what you want to train"
        }
    }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        }
    }
}

enum StrengthSplit: String, CaseIterable, Identifiable {
    case fullBody
    case push
    case pull
    case legs
    case upper
    case lower
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullBody: return "Full Body"
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .upper: return "Upper"
        case .lower: return "Lower"
        case .custom: return "Custom"
        }
    }
}
