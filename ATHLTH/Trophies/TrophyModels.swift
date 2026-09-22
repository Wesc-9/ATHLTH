import Foundation

enum TrophyCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case signature
    case endurance
    case strength
    case consistency
    case goals
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signature: return "Signature"
        case .endurance: return "Endurance"
        case .strength: return "Strength"
        case .consistency: return "Consistency"
        case .goals: return "Goals"
        case .recovery: return "Recovery"
        }
    }

    var systemImage: String {
        switch self {
        case .signature: return "sparkles"
        case .endurance: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .consistency: return "flame.fill"
        case .goals: return "target"
        case .recovery: return "moon.stars.fill"
        }
    }
}

enum TrophyRarity: Int, CaseIterable, Codable, Hashable, Comparable {
    case core = 0
    case rare = 1
    case epic = 2
    case signature = 3

    static func < (lhs: TrophyRarity, rhs: TrophyRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .core: return "Core"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .signature: return "Signature"
        }
    }
}

enum TrophyVerificationSource: String, Codable, Hashable {
    case appleHealth
    case athlth
    case goal
    case mixed

    var title: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .athlth: return "ATHLTH"
        case .goal: return "ATHLTH Goal"
        case .mixed: return "Verified"
        }
    }

    var systemImage: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .athlth: return "a.circle.fill"
        case .goal: return "target"
        case .mixed: return "checkmark.seal.fill"
        }
    }
}

struct TrophyStageDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let threshold: Double
    let displayTarget: String
    let rarity: TrophyRarity
}

struct TrophySeriesDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: TrophyCategory
    let verificationSource: TrophyVerificationSource
    let systemImage: String
    let stages: [TrophyStageDefinition]
}

struct TrophyHealthSnapshot: Hashable {
    let workoutCount: Int
    let workoutCountReachedAt: [Int: Date]

    let totalRunningDistanceMeters: Double
    let runningDistanceReachedAt: [Int: Date]

    let longestRunMeters: Double
    let firstFiveKDate: Date?
    let firstHalfMarathonDate: Date?
    let firstMarathonDate: Date?

    let longestWorkoutStreakDays: Int
    let workoutStreakReachedAt: [Int: Date]

    let qualifyingSleepNights: Int
    let qualifyingSleepNightsReachedAt: [Int: Date]
}

struct TrophyStrengthSnapshot: Hashable {
    let completedWorkoutCount: Int
    let workoutCountReachedAt: [Int: Date]
    let firstWeightedSetDate: Date?
}

struct TrophyProgressItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: TrophyCategory
    let verificationSource: TrophyVerificationSource
    let systemImage: String

    let currentValue: Double
    let nextTargetValue: Double?
    let currentStage: TrophyStageDefinition?
    let nextStage: TrophyStageDefinition?
    let highestRarity: TrophyRarity
    let unlockedAt: Date?

    let goalID: UUID?
    let journeyMilestonesCompleted: Int?
    let journeyMilestonesTotal: Int?

    var isUnlocked: Bool {
        unlockedAt != nil || currentStage != nil
    }

    var isComplete: Bool {
        nextStage == nil && isUnlocked
    }

    var displayRarity: TrophyRarity {
        currentStage?.rarity ?? nextStage?.rarity ?? highestRarity
    }

    var progress: Double {
        guard let nextTargetValue, nextTargetValue > 0 else {
            return isUnlocked ? 1 : 0
        }

        let previousThreshold = currentStage?.threshold ?? 0
        let span = max(nextTargetValue - previousThreshold, 0.0001)
        return min(max((currentValue - previousThreshold) / span, 0), 1)
    }

    var stageLabel: String {
        if let currentStage {
            return currentStage.title
        }

        return "Locked"
    }
}

struct TrophyUnlockRecord: Identifiable, Codable, Hashable {
    var id: String { stageKey }

    let stageKey: String
    let trophyID: String
    let stageTitle: String
    let title: String
    let rarity: TrophyRarity
    let category: TrophyCategory
    let verificationSource: TrophyVerificationSource
    let unlockedAt: Date
}

enum TrophyCatalog {
    static let workoutMomentum = TrophySeriesDefinition(
        id: "consistency.workout-momentum",
        title: "Built to Move",
        subtitle: "Keep showing up. Every recorded workout strengthens the Core.",
        category: .consistency,
        verificationSource: .appleHealth,
        systemImage: "figure.run.circle.fill",
        stages: [
            .init(id: "10", title: "Ignition", threshold: 10, displayTarget: "10 workouts", rarity: .core),
            .init(id: "50", title: "Momentum", threshold: 50, displayTarget: "50 workouts", rarity: .rare),
            .init(id: "100", title: "Committed", threshold: 100, displayTarget: "100 workouts", rarity: .epic),
            .init(id: "250", title: "Relentless", threshold: 250, displayTarget: "250 workouts", rarity: .signature)
        ]
    )

    static let runningDistance = TrophySeriesDefinition(
        id: "endurance.running-distance",
        title: "Distance Engine",
        subtitle: "A single evolving trophy for the running distance you accumulate.",
        category: .endurance,
        verificationSource: .appleHealth,
        systemImage: "figure.run",
        stages: [
            .init(id: "25", title: "First Miles", threshold: 25_000, displayTarget: "25 km", rarity: .core),
            .init(id: "100", title: "Road Built", threshold: 100_000, displayTarget: "100 km", rarity: .rare),
            .init(id: "500", title: "Distance Engine", threshold: 500_000, displayTarget: "500 km", rarity: .epic),
            .init(id: "1000", title: "Thousand Club", threshold: 1_000_000, displayTarget: "1,000 km", rarity: .signature)
        ]
    )

    static let streak = TrophySeriesDefinition(
        id: "consistency.training-streak",
        title: "Unbroken",
        subtitle: "Consecutive calendar days with at least one recorded workout.",
        category: .consistency,
        verificationSource: .appleHealth,
        systemImage: "flame.fill",
        stages: [
            .init(id: "3", title: "Spark", threshold: 3, displayTarget: "3 days", rarity: .core),
            .init(id: "7", title: "Rhythm", threshold: 7, displayTarget: "7 days", rarity: .rare),
            .init(id: "14", title: "Locked In", threshold: 14, displayTarget: "14 days", rarity: .epic),
            .init(id: "30", title: "Unbroken", threshold: 30, displayTarget: "30 days", rarity: .signature)
        ]
    )

    static let strengthSessions = TrophySeriesDefinition(
        id: "strength.sessions",
        title: "Built Under Load",
        subtitle: "Strength sessions logged with ATHLTH advanced or simple tracking.",
        category: .strength,
        verificationSource: .athlth,
        systemImage: "dumbbell.fill",
        stages: [
            .init(id: "10", title: "Foundation", threshold: 10, displayTarget: "10 sessions", rarity: .core),
            .init(id: "25", title: "Under Load", threshold: 25, displayTarget: "25 sessions", rarity: .rare),
            .init(id: "50", title: "Forged", threshold: 50, displayTarget: "50 sessions", rarity: .epic),
            .init(id: "100", title: "Iron Core", threshold: 100, displayTarget: "100 sessions", rarity: .signature)
        ]
    )

    static let recoveryNights = TrophySeriesDefinition(
        id: "recovery.restored-nights",
        title: "Restored",
        subtitle: "Nights with at least seven hours of sleep recorded in Apple Health.",
        category: .recovery,
        verificationSource: .appleHealth,
        systemImage: "moon.stars.fill",
        stages: [
            .init(id: "7", title: "Reset", threshold: 7, displayTarget: "7 nights", rarity: .core),
            .init(id: "30", title: "Restored", threshold: 30, displayTarget: "30 nights", rarity: .rare),
            .init(id: "100", title: "Deep Reserve", threshold: 100, displayTarget: "100 nights", rarity: .epic)
        ]
    )

    static let completedGoals = TrophySeriesDefinition(
        id: "goals.completed",
        title: "Purpose",
        subtitle: "Complete goals you deliberately chose to pursue.",
        category: .goals,
        verificationSource: .goal,
        systemImage: "target",
        stages: [
            .init(id: "1", title: "First Finish", threshold: 1, displayTarget: "1 goal", rarity: .core),
            .init(id: "3", title: "Intentional", threshold: 3, displayTarget: "3 goals", rarity: .rare),
            .init(id: "5", title: "Driven", threshold: 5, displayTarget: "5 goals", rarity: .epic),
            .init(id: "10", title: "Purpose", threshold: 10, displayTarget: "10 goals", rarity: .signature)
        ]
    )

    static let allSeries: [TrophySeriesDefinition] = [
        workoutMomentum,
        runningDistance,
        streak,
        strengthSessions,
        recoveryNights,
        completedGoals
    ]
}
