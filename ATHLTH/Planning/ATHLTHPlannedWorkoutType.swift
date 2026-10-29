import Foundation

/// Categories shown before choosing an existing planned workout.
/// Cycling is a workout activityTag/category rather than a separate
/// WorkoutKind in the current shared session model.
enum ATHLTHPlannedWorkoutType: String, CaseIterable, Codable, Hashable, Identifiable {
    case strength
    case running
    case walking
    case cycling
    case mobility
    case custom

    var id: String { rawValue }

    static let defaultOrder: [Self] = [
        .strength, .running, .walking, .cycling, .mobility, .custom
    ]

    var title: String {
        switch self {
        case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case .walking: return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gå")
        case .cycling: return ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
        case .mobility: return ATHLTHLocalization.choose(english: "Mobility", norwegian: "Mobilitet")
        case .custom: return ATHLTHLocalization.choose(english: "Custom", norwegian: "Egendefinert")
        }
    }

    var description: String {
        switch self {
        case .strength: return ATHLTHLocalization.choose(
            english: "Build strength and muscle.", norwegian: "Bygg styrke og muskulatur.")
        case .running: return ATHLTHLocalization.choose(
            english: "For fitness and endurance.", norwegian: "For bedre kondisjon og utholdenhet.")
        case .walking: return ATHLTHLocalization.choose(
            english: "An accessible, active workout.", norwegian: "En lavterskeløkt for økt aktivitet.")
        case .cycling: return ATHLTHLocalization.choose(
            english: "Build endurance on two wheels.", norwegian: "Bygg utholdenhet på to hjul.")
        case .mobility: return ATHLTHLocalization.choose(
            english: "Move more freely, feel less stiff.", norwegian: "Bedre bevegelighet og mindre stivhet.")
        case .custom: return ATHLTHLocalization.choose(
            english: "Pick an individually created workout.", norwegian: "Hent din egen tilpassede økt.")
        }
    }

    var imageName: String {
        switch self {
        case .strength: return "StrengthFeedGym"
        case .running: return "GoalRunning"
        case .walking: return "GoalWalking"
        case .cycling: return "GoalEndurance"
        case .mobility: return "GoalRecovery"
        case .custom: return "GoalRelax"
        }
    }

    var symbol: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .mobility: return "figure.flexibility"
        case .custom: return "slider.horizontal.3"
        }
    }

    var catalogCategory: String { rawValue.capitalized }

    /// The shared PlannedSession model uses a category to distinguish cycling
    /// from generic custom sessions. No duplicate cycling workout engine.
    var scratchWorkoutKind: WorkoutKind {
        switch self {
        case .strength: return .strength
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .custom
        case .mobility: return .mobility
        case .custom: return .custom
        }
    }

    /// An optional first editable block in the existing timeline composer.
    /// A scratch workout contains no saved program or preselected loads.
    var scratchQuickAdd: String? {
        switch self {
        case .strength: return "exercise"
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .mobility: return "stretching"
        case .custom: return nil
        }
    }

    /// Use the saved activity and category, rather than guessing from title.
    func matches(_ workout: PlannedSession) -> Bool {
        let category = workout.workoutCategory?.lowercased() ?? ""
        // A cycling workout may be stored as .custom in the legacy shared
        // WorkoutKind model; inspect its saved recipe rather than its title.
        let includesCycling = workout.resolvedWorkoutBlocks.contains {
            $0.activityTag == "cycling"
        }
        switch self {
        case .strength: return workout.kind == .strength || category == "strength"
        case .running: return workout.kind == .running || category == "running"
        case .walking: return workout.kind == .walking || category == "walking"
        case .cycling: return category == "cycling" ||
            (category.isEmpty && workout.kind == .custom && includesCycling)
        case .mobility: return workout.kind == .mobility || category == "mobility"
        case .custom:
            return (workout.kind == .custom && category != "cycling" &&
                    !(category.isEmpty && includesCycling))
                || category == "hybrid" || category == "custom"
        }
    }

    func matches(_ entry: WorkoutTemplateCatalogEntry) -> Bool {
        let category = entry.category.lowercased()
        switch self {
        case .custom: return category == "custom" || category == "hybrid"
        default: return category == rawValue
        }
    }

    static func from(_ workout: PlannedSession) -> Self {
        for type in defaultOrder where type.matches(workout) { return type }
        return .custom
    }
}

struct ATHLTHPlannedWorkoutTypeUsage: Codable, Equatable {
    var count: Int = 0
    var lastUsedAt: Date?
}

/// Private, per-account preferences. A category is counted only after the
/// user actually chooses a workout, never merely by opening a tile.
enum ATHLTHPlannedWorkoutTypeUsageStore {
    private static func storageKey(userID: UUID) -> String {
        "athlth.plannedWorkoutTypeUsage.v1.\(userID.uuidString)"
    }

    static func load(
        userID: UUID,
        defaults: UserDefaults = .standard
    ) -> [String: ATHLTHPlannedWorkoutTypeUsage] {
        guard let data = defaults.data(forKey: storageKey(userID: userID)),
              let values = try? JSONDecoder().decode(
                [String: ATHLTHPlannedWorkoutTypeUsage].self,
                from: data
              ) else { return [:] }
        return values
    }

    static func record(
        _ type: ATHLTHPlannedWorkoutType,
        userID: UUID,
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        var values = load(userID: userID, defaults: defaults)
        var entry = values[type.rawValue] ?? ATHLTHPlannedWorkoutTypeUsage()
        entry.count = min(Int.max - 1, entry.count) + 1
        entry.lastUsedAt = date
        values[type.rawValue] = entry
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: storageKey(userID: userID))
    }

    static func ordered(
        userID: UUID,
        defaults: UserDefaults = .standard,
        healthWorkouts: [WorkoutSummary] = [],
        strengthHistory: [StrengthWorkoutLog] = []
    ) -> [ATHLTHPlannedWorkoutType] {
        let values = load(userID: userID, defaults: defaults)

        // A user's real workout history matters more than opening a tile.
        // Read the already cached workout histories; do not launch HealthKit
        // queries or count each second of live training as a new workout.
        var historical: [ATHLTHPlannedWorkoutType: ATHLTHPlannedWorkoutTypeUsage] = [:]
        for workout in healthWorkouts {
            let type: ATHLTHPlannedWorkoutType
            switch workout.activity {
            case .running: type = .running
            case .walking, .hiking: type = .walking
            case .cycling: type = .cycling
            case .strength, .coreTraining: type = .strength
            case .yoga: type = .mobility
            default: type = .custom
            }
            var entry = historical[type] ?? ATHLTHPlannedWorkoutTypeUsage()
            entry.count += 1
            entry.lastUsedAt = max(entry.lastUsedAt ?? .distantPast,
                                   workout.startDate)
            historical[type] = entry
        }

        // Strength performed only in ATHLTH (no Health permission) must
        // still influence the order. Avoid double-counting when HealthKit
        // has already supplied strength history for this account.
        if historical[.strength] == nil {
            let finished = strengthHistory.filter(\.isFinished)
            historical[.strength] = ATHLTHPlannedWorkoutTypeUsage(
                count: finished.count,
                lastUsedAt: finished.map(\.startedAt).max()
            )
        }

        return ATHLTHPlannedWorkoutType.defaultOrder.sorted { lhs, rhs in
            let left = values[lhs.rawValue] ?? ATHLTHPlannedWorkoutTypeUsage()
            let right = values[rhs.rawValue] ?? ATHLTHPlannedWorkoutTypeUsage()
            let leftHistory = historical[lhs] ?? ATHLTHPlannedWorkoutTypeUsage()
            let rightHistory = historical[rhs] ?? ATHLTHPlannedWorkoutTypeUsage()
            let leftCount = left.count + leftHistory.count
            let rightCount = right.count + rightHistory.count
            if leftCount != rightCount { return leftCount > rightCount }
            let leftRecent = max(left.lastUsedAt ?? .distantPast,
                                 leftHistory.lastUsedAt ?? .distantPast)
            let rightRecent = max(right.lastUsedAt ?? .distantPast,
                                  rightHistory.lastUsedAt ?? .distantPast)
            if leftRecent != rightRecent { return leftRecent > rightRecent }
            let order = ATHLTHPlannedWorkoutType.defaultOrder
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }
}
