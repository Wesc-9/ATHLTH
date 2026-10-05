import Foundation

enum SignInMethod: String, Codable {
    case apple
    case email
}

enum HealthSex: String, CaseIterable, Identifiable, Codable {
    case female
    case male
    case other
    case preferNotToSay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

enum PersonalDetailsSource: String, Codable {
    case none
    case appleHealth
    case manual
    case mixed
}

struct HealthProfileBasics: Codable, Hashable {
    var dateOfBirth: Date?
    var healthSex: HealthSex?
    var weightKilograms: Double?
    var heightCentimeters: Double?
    var maximumHeartRateBPM: Int? = nil

    static let empty = HealthProfileBasics(
        dateOfBirth: nil,
        healthSex: nil,
        weightKilograms: nil,
        heightCentimeters: nil,
        maximumHeartRateBPM: nil
    )

    var hasAnyValue: Bool {
        dateOfBirth != nil ||
        healthSex != nil ||
        weightKilograms != nil ||
        heightCentimeters != nil ||
        maximumHeartRateBPM != nil
    }
}

enum TrainingFocus: String, CaseIterable, Identifiable, Codable, Hashable {
    case running
    case strength
    case hybrid
    case walking
    case generalFitness
    case recovery

    var id: String { rawValue }

    // Profile editing exposes running and strength as two independent choices.
    // The existing hybrid value remains the persisted/backend representation
    // when both are selected, so this improvement does not require a schema
    // migration and older clients keep understanding the value.
    static var profileSelectionCases: [TrainingFocus] {
        allCases.filter { $0 != .hybrid }
    }

    static func profileSelections(
        from persistedFocus: TrainingFocus?
    ) -> Set<TrainingFocus> {
        guard let persistedFocus else {
            return []
        }

        if persistedFocus == .hybrid {
            return [.running, .strength]
        }

        return [persistedFocus]
    }

    static func persistedProfileFocus(
        from selections: Set<TrainingFocus>
    ) -> TrainingFocus? {
        if selections.contains(.running) &&
            selections.contains(.strength) {
            return .hybrid
        }

        return profileSelectionCases.first {
            selections.contains($0)
        }
    }

    var title: String {
        switch self {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Running",
                norwegian: "Løping"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength training",
                norwegian: "Styrketrening"
            )
        case .hybrid:
            return ATHLTHLocalization.choose(
                english: "Running · Strength",
                norwegian: "Løping · Styrketrening"
            )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walking",
                norwegian: "Gåing"
            )
        case .generalFitness:
            return ATHLTHLocalization.choose(
                english: "General fitness",
                norwegian: "Allsidig trening"
            )
        case .recovery:
            return ATHLTHLocalization.choose(
                english: "Recovery",
                norwegian: "Restitusjon"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Running performance, endurance and structured run training.",
                norwegian: "Løpsprestasjon, utholdenhet og strukturert løpetrening."
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength, muscle and progressive resistance training.",
                norwegian: "Styrke, muskelutvikling og progressiv styrketrening."
            )
        case .hybrid:
            return ATHLTHLocalization.choose(
                english: "Running and strength training.",
                norwegian: "Løping og styrketrening."
            )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walking, daily movement and active lifestyle.",
                norwegian: "Gåing, hverdagsaktivitet og en aktiv livsstil."
            )
        case .generalFitness:
            return ATHLTHLocalization.choose(
                english: "A balanced mix of health, fitness and movement.",
                norwegian: "En balansert kombinasjon av helse, trening og bevegelse."
            )
        case .recovery:
            return ATHLTHLocalization.choose(
                english: "Recovery, sleep and readiness as the main focus.",
                norwegian: "Restitusjon, søvn og treningsberedskap som hovedfokus."
            )
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .hybrid: return "bolt.heart.fill"
        case .walking: return "figure.walk"
        case .generalFitness: return "figure.mixed.cardio"
        case .recovery: return "leaf.fill"
        }
    }
}

enum AchievementGoal: String, CaseIterable, Identifiable, Codable, Hashable {
    case loseWeight
    case buildMuscle
    case getStronger
    case improveEndurance
    case runBetter
    case moveMore
    case recoverySleep
    case mobility
    case event
    case maintainHealth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loseWeight: return "Lose weight"
        case .buildMuscle: return "Build muscle"
        case .getStronger: return "Get stronger"
        case .improveEndurance: return "Improve fitness & endurance"
        case .runBetter: return "Run faster or farther"
        case .moveMore: return "Move more"
        case .recoverySleep: return "Improve recovery & sleep"
        case .mobility: return "Improve mobility & flexibility"
        case .event: return "Prepare for an event"
        case .maintainHealth: return "Maintain health & fitness"
        }
    }

    var subtitle: String {
        switch self {
        case .loseWeight: return "Work toward a healthier body-weight goal."
        case .buildMuscle: return "Prioritize muscle growth and progressive training."
        case .getStronger: return "Increase strength and track performance over time."
        case .improveEndurance: return "Build cardiovascular fitness and stamina."
        case .runBetter: return "Improve pace, distance and running performance."
        case .moveMore: return "Increase everyday movement and activity."
        case .recoverySleep: return "Focus on sleep, recovery and readiness."
        case .mobility: return "Improve movement quality and flexibility."
        case .event: return "Prepare for a race, challenge or target date."
        case .maintainHealth: return "Stay active and maintain your current fitness."
        }
    }

    var systemImage: String {
        switch self {
        case .loseWeight: return "scalemass.fill"
        case .buildMuscle: return "figure.strengthtraining.traditional"
        case .getStronger: return "dumbbell.fill"
        case .improveEndurance: return "heart.circle.fill"
        case .runBetter: return "figure.run"
        case .moveMore: return "figure.walk"
        case .recoverySleep: return "moon.stars.fill"
        case .mobility: return "figure.flexibility"
        case .event: return "flag.checkered"
        case .maintainHealth: return "heart.fill"
        }
    }
}

enum GoalFocusArea: String, CaseIterable, Identifiable, Hashable {
    case strengthBody
    case performance
    case healthMovement
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strengthBody: return "Strength & Body"
        case .performance: return "Performance"
        case .healthMovement: return "Health & Movement"
        case .recovery: return "Recovery"
        }
    }

    var subtitle: String {
        switch self {
        case .strengthBody: return "Strength, muscle & body goals"
        case .performance: return "Fitness, running & events"
        case .healthMovement: return "Daily movement & mobility"
        case .recovery: return "Sleep, readiness & recovery"
        }
    }

    var systemImage: String {
        switch self {
        case .strengthBody: return "dumbbell.fill"
        case .performance: return "bolt.fill"
        case .healthMovement: return "figure.walk"
        case .recovery: return "moon.stars.fill"
        }
    }

    var goals: [AchievementGoal] {
        switch self {
        case .strengthBody:
            return [.loseWeight, .buildMuscle, .getStronger]
        case .performance:
            return [.improveEndurance, .runBetter, .event]
        case .healthMovement:
            return [.moveMore, .mobility, .maintainHealth]
        case .recovery:
            return [.recoverySleep]
        }
    }

    func contains(_ goal: AchievementGoal?) -> Bool {
        guard let goal else { return false }
        return goals.contains(goal)
    }
}

enum ATHLTHInterest: String, CaseIterable, Identifiable, Codable, Hashable {
    case strength
    case running
    case walking
    case recovery
    case nutrition
    case trainingPlans
    case healthTracking
    case social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: return "Strength"
        case .running: return "Running"
        case .walking: return "Walking"
        case .recovery: return "Recovery"
        case .nutrition: return "Nutrition"
        case .trainingPlans: return "Training plans"
        case .healthTracking: return "Health tracking"
        case .social: return "Friends & challenges"
        }
    }

    var systemImage: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .recovery: return "leaf.fill"
        case .nutrition: return "fork.knife"
        case .trainingPlans: return "list.bullet.clipboard.fill"
        case .healthTracking: return "chart.xyaxis.line"
        case .social: return "person.2.fill"
        }
    }
}

enum PersonalizedOfferConsent: String, Codable, Hashable {
    case notAsked
    case declined
    case granted

    var title: String {
        switch self {
        case .notAsked: return "Not requested"
        case .declined: return "Declined"
        case .granted: return "Allowed"
        }
    }
}

struct UserGoalRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var type: AchievementGoal
    var createdAt: Date
    var targetWeightKilograms: Double?
    var targetDate: Date?
    var eventName: String?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        type: AchievementGoal,
        createdAt: Date = Date(),
        targetWeightKilograms: Double? = nil,
        targetDate: Date? = nil,
        eventName: String? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.targetWeightKilograms = targetWeightKilograms
        self.targetDate = targetDate
        self.eventName = eventName
        self.completedAt = completedAt
    }
}

struct OnboardingProfileData: Codable, Hashable {
    var dateOfBirth: Date?
    var healthSex: HealthSex?
    var weightKilograms: Double?
    var heightCentimeters: Double?
    var maximumHeartRateBPM: Int? = nil
    var personalDetailsSource: PersonalDetailsSource
    var trainingFocus: TrainingFocus? = nil

    var currentGoal: UserGoalRecord?
    var interests: Set<ATHLTHInterest>
    var personalizedOfferConsent: PersonalizedOfferConsent

    var healthBasics: HealthProfileBasics {
        HealthProfileBasics(
            dateOfBirth: dateOfBirth,
            healthSex: healthSex,
            weightKilograms: weightKilograms,
            heightCentimeters: heightCentimeters,
            maximumHeartRateBPM: maximumHeartRateBPM
        )
    }
}

enum OnboardingStep: Int, CaseIterable {
    case account
    case username
    case goals
    case connections
    case ready

    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }
}
