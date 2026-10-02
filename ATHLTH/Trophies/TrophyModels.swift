import Foundation

enum TrophyCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case signature
    case walking
    case endurance
    case strength
    case consistency
    case goals
    case recovery
    case challenges

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signature: return ATHLTHLocalization.string( "Signature")
        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walking",
                norwegian: "Gåing"
            )
        case .endurance: return ATHLTHLocalization.string( "Endurance")
        case .strength: return ATHLTHLocalization.string( "Strength")
        case .consistency: return ATHLTHLocalization.string( "Consistency")
        case .goals: return ATHLTHLocalization.string( "Goals")
        case .recovery:
            return ATHLTHLocalization.choose(
                english: "Health & Recovery",
                norwegian: "Helse & restitusjon"
            )
        case .challenges: return ATHLTHLocalization.string( "Challenges")
        }
    }

    var systemImage: String {
        switch self {
        case .signature: return "sparkles"
        case .walking: return "figure.walk"
        case .endurance: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .consistency: return "flame.fill"
        case .goals: return "target"
        case .recovery: return "moon.stars.fill"
        case .challenges: return "person.2.fill"
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
        case .core: return ATHLTHLocalization.string( "Core")
        case .rare: return ATHLTHLocalization.string( "Rare")
        case .epic: return ATHLTHLocalization.string( "Epic")
        case .signature: return ATHLTHLocalization.string( "Signature")
        }
    }
}

enum ATHLTHAwardClass: String, Codable, Hashable {
    case achievement
    case trophy

    var title: String {
        switch self {
        case .achievement:
            return ATHLTHLocalization.choose(
                english: "Achievement",
                norwegian: "Achievement"
            )
        case .trophy:
            return ATHLTHLocalization.choose(
                english: "Trophy",
                norwegian: "Pokal"
            )
        }
    }
}

enum PrestigeTrophyCatalog {
    static let halfMarathonID =
        "signature.half-marathon"
    static let marathonID =
        "signature.marathon"

    static let ids: Set<String> = [
        halfMarathonID,
        marathonID
    ]

    static func isPrestigeTrophy(
        _ id: String
    ) -> Bool {
        ids.contains(id)
    }
}

enum TrophyVerificationSource: String, Codable, Hashable {
    case appleHealth
    case athlth
    case goal
    case challenge
    case mixed

    var title: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .athlth: return "ATHLTH"
        case .goal: return ATHLTHLocalization.string( "ATHLTH Goal")
        case .challenge: return ATHLTHLocalization.string( "ATHLTH Challenge")
        case .mixed: return ATHLTHLocalization.string( "Verified")
        }
    }

    var systemImage: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .athlth: return "a.circle.fill"
        case .goal: return "target"
        case .challenge: return "person.2.fill"
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

struct PrestigeRunEvidence:
    Hashable,
    Codable
{
    let workoutID: UUID
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let startedAt: Date
    let endedAt: Date
    let sourceBundleIdentifier: String
    let sourceName: String
    let isIndoor: Bool?
    let wasUserEntered: Bool
}

struct TrophyHealthSnapshot: Hashable, Codable {
    let workoutCount: Int
    let workoutCountReachedAt: [Int: Date]

    let totalRunningDistanceMeters: Double
    let runningDistanceReachedAt: [Int: Date]

    let longestRunMeters: Double
    let firstFiveKDate: Date?
    let firstTenKDate: Date?
    let firstHalfMarathonDate: Date?
    let firstMarathonDate: Date?
    let firstHalfMarathonEvidence: PrestigeRunEvidence?
    let firstMarathonEvidence: PrestigeRunEvidence?

    // Optional so an existing on-device trophy cache from an older ATHLTH
    // build remains decodable after the walking trophy expansion.
    let walkingWorkoutCount: Int?
    let walkingWorkoutCountReachedAt: [Int: Date]?
    let totalWalkingDistanceMeters: Double?
    let walkingDistanceReachedAt: [Int: Date]?
    let longestWalkMeters: Double?
    let firstFiveKWalkDate: Date?
    let firstTenKWalkDate: Date?

    let longestWorkoutStreakDays: Int
    let workoutStreakReachedAt: [Int: Date]

    let qualifyingSleepNights: Int
    let qualifyingSleepNightsReachedAt: [Int: Date]
}

struct TrophyStrengthSnapshot: Hashable {
    let completedWorkoutCount: Int
    let workoutCountReachedAt: [Int: Date]
    let firstWeightedSetDate: Date?
    let totalVolumeKilograms: Double
    let volumeReachedAt: [Int: Date]
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

        return ATHLTHLocalization.string( "Locked")
    }

    var concreteProgressText: String? {
        guard let nextTargetValue else {
            return nil
        }

        func integer(
            _ value: Double
        ) -> String {
            Int(value.rounded())
                .formatted(
                    .number
                        .grouping(.automatic)
                )
        }

        if id ==
            TrophyCatalog
                .runningDistance
                .id ||
            id ==
            TrophyCatalog
                .walkingDistance
                .id {
            let currentKilometers =
                currentValue / 1_000
            let targetKilometers =
                nextTargetValue / 1_000

            return ATHLTHLocalization.format(
                english: "%.0f / %.0f km",
                norwegian: "%.0f / %.0f km",
                currentKilometers,
                targetKilometers
            )
        }

        if id ==
            TrophyCatalog
                .strengthVolume
                .id {
            return ATHLTHLocalization.format(
                english: "%@ / %@ kg",
                norwegian: "%@ / %@ kg",
                integer(currentValue),
                integer(
                    nextTargetValue
                )
            )
        }

        let unit: String
        switch id {
        case TrophyCatalog
            .workoutMomentum
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "workouts",
                    norwegian: "økter"
                )
        case TrophyCatalog
            .walkingSessions
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "walks",
                    norwegian: "gåturer"
                )
        case TrophyCatalog
            .streak
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "days",
                    norwegian: "dager"
                )
        case TrophyCatalog
            .strengthSessions
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "sessions",
                    norwegian: "økter"
                )
        case TrophyCatalog
            .recoveryNights
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "nights",
                    norwegian: "netter"
                )
        case TrophyCatalog
            .completedGoals
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "goals",
                    norwegian: "mål"
                )
        case TrophyCatalog
            .challengeParticipation
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "challenges",
                    norwegian: "challenges"
                )
        case TrophyCatalog
            .challengeWins
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "wins",
                    norwegian: "seire"
                )
        case TrophyCatalog
            .friendsChallenged
            .id:
            unit =
                ATHLTHLocalization.choose(
                    english: "friends",
                    norwegian: "venner"
                )
        default:
            if let completed =
                journeyMilestonesCompleted,
               let total =
                journeyMilestonesTotal {
                return ATHLTHLocalization.format(
                    english: "%d / %d milestones",
                    norwegian: "%d / %d milepæler",
                    completed,
                    total
                )
            }
            return nil
        }

        return "\(integer(currentValue)) / \(integer(nextTargetValue)) \(unit)"
    }

    var awardClass: ATHLTHAwardClass {
        PrestigeTrophyCatalog
            .isPrestigeTrophy(id)
            ? .trophy
            : .achievement
    }

    var isPrestigeTrophy: Bool {
        awardClass == .trophy
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

    var awardClass: ATHLTHAwardClass {
        PrestigeTrophyCatalog
            .isPrestigeTrophy(trophyID)
            ? .trophy
            : .achievement
    }

    var isPrestigeTrophy: Bool {
        awardClass == .trophy
    }
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

    static let walkingDistance = TrophySeriesDefinition(
        id: "walking.total-distance",
        title: "Pathfinder",
        subtitle: "Every recorded walking workout adds distance to this evolving trophy.",
        category: .walking,
        verificationSource: .appleHealth,
        systemImage: "figure.walk",
        stages: [
            .init(id: "10", title: "First Paths", threshold: 10_000, displayTarget: "10 km", rarity: .core),
            .init(id: "50", title: "Trail Maker", threshold: 50_000, displayTarget: "50 km", rarity: .rare),
            .init(id: "250", title: "Pathfinder", threshold: 250_000, displayTarget: "250 km", rarity: .epic),
            .init(id: "1000", title: "Long Way Home", threshold: 1_000_000, displayTarget: "1,000 km", rarity: .signature)
        ]
    )

    static let walkingSessions = TrophySeriesDefinition(
        id: "walking.sessions",
        title: "Keep Walking",
        subtitle: "Build a walking habit one recorded session at a time.",
        category: .walking,
        verificationSource: .appleHealth,
        systemImage: "shoeprints.fill",
        stages: [
            .init(id: "10", title: "Out the Door", threshold: 10, displayTarget: "10 walks", rarity: .core),
            .init(id: "50", title: "Regular", threshold: 50, displayTarget: "50 walks", rarity: .rare),
            .init(id: "150", title: "Wayfarer", threshold: 150, displayTarget: "150 walks", rarity: .epic),
            .init(id: "500", title: "Keep Walking", threshold: 500, displayTarget: "500 walks", rarity: .signature)
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

    static let strengthVolume = TrophySeriesDefinition(
        id: "strength.total-volume",
        title: "Iron Ledger",
        subtitle: "Cumulative lifted volume from completed ATHLTH strength sets.",
        category: .strength,
        verificationSource: .athlth,
        systemImage: "scalemass.fill",
        stages: [
            .init(id: "10000", title: "Loaded", threshold: 10_000, displayTarget: "10,000 kg", rarity: .core),
            .init(id: "50000", title: "Heavy Work", threshold: 50_000, displayTarget: "50,000 kg", rarity: .rare),
            .init(id: "250000", title: "Forged", threshold: 250_000, displayTarget: "250,000 kg", rarity: .epic),
            .init(id: "1000000", title: "Million Kilo Club", threshold: 1_000_000, displayTarget: "1,000,000 kg", rarity: .signature)
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
            .init(id: "100", title: "Deep Reserve", threshold: 100, displayTarget: "100 nights", rarity: .epic),
            .init(id: "365", title: "Year of Recovery", threshold: 365, displayTarget: "365 nights", rarity: .signature)
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

    static let challengeParticipation = TrophySeriesDefinition(
        id: "challenges.participation",
        title: "Head to Head",
        subtitle: "Take part in ATHLTH Challenges with friends.",
        category: .challenges,
        verificationSource: .challenge,
        systemImage: "person.2.fill",
        stages: [
            .init(id: "1", title: "First Challenge", threshold: 1, displayTarget: "1 challenge", rarity: .core),
            .init(id: "5", title: "Rival", threshold: 5, displayTarget: "5 challenges", rarity: .rare),
            .init(id: "20", title: "Competitor", threshold: 20, displayTarget: "20 challenges", rarity: .epic),
            .init(id: "50", title: "Head to Head", threshold: 50, displayTarget: "50 challenges", rarity: .signature)
        ]
    )

    static let challengeWins = TrophySeriesDefinition(
        id: "challenges.wins",
        title: "On Top",
        subtitle: "Finish ATHLTH Challenges at the top of the leaderboard.",
        category: .challenges,
        verificationSource: .challenge,
        systemImage: "crown.fill",
        stages: [
            .init(id: "1", title: "First Win", threshold: 1, displayTarget: "1 win", rarity: .rare),
            .init(id: "5", title: "Winner", threshold: 5, displayTarget: "5 wins", rarity: .epic),
            .init(id: "10", title: "On Top", threshold: 10, displayTarget: "10 wins", rarity: .signature)
        ]
    )

    static let friendsChallenged = TrophySeriesDefinition(
        id: "challenges.friends-invited",
        title: "Call Them Out",
        subtitle: "Invite different friends into your ATHLTH Challenges.",
        category: .challenges,
        verificationSource: .challenge,
        systemImage: "person.badge.plus",
        stages: [
            .init(id: "1", title: "Call Out", threshold: 1, displayTarget: "1 friend", rarity: .core),
            .init(id: "5", title: "Crew", threshold: 5, displayTarget: "5 friends", rarity: .rare),
            .init(id: "10", title: "Call Them Out", threshold: 10, displayTarget: "10 friends", rarity: .epic)
        ]
    )

    static let allSeries: [TrophySeriesDefinition] = [
        workoutMomentum,
        walkingDistance,
        walkingSessions,
        runningDistance,
        streak,
        strengthSessions,
        strengthVolume,
        recoveryNights,
        completedGoals,
        challengeParticipation,
        challengeWins,
        friendsChallenged
    ]
}
