import Foundation

enum GoalCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case event
    case endurance
    case strength
    case body
    case consistency
    case recovery
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .event:
            return ATHLTHLocalization.format(
                english: "Event",
                norwegian: "Arrangement"
            )
        case .endurance:
            return ATHLTHLocalization.format(
                english: "Running & Endurance",
                norwegian: "Løping og utholdenhet"
            )
        case .strength:
            return ATHLTHLocalization.format(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .body:
            return ATHLTHLocalization.format(
                english: "Body",
                norwegian: "Kropp"
            )
        case .consistency:
            return ATHLTHLocalization.format(
                english: "Consistency",
                norwegian: "Kontinuitet"
            )
        case .recovery:
            return ATHLTHLocalization.format(
                english: "Recovery & Health",
                norwegian: "Restitusjon og helse"
            )
        case .custom:
            return ATHLTHLocalization.format(
                english: "Custom Goal",
                norwegian: "Egendefinert mål"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .event:
            return ATHLTHLocalization.format(
                english: "Prepare for a race or event.",
                norwegian: "Forbered deg til et løp eller arrangement."
            )
        case .endurance:
            return ATHLTHLocalization.format(
                english: "Distance, pace and endurance targets.",
                norwegian: "Mål for distanse, tempo og utholdenhet."
            )
        case .strength:
            return ATHLTHLocalization.format(
                english: "Exercise-specific strength targets.",
                norwegian: "Øvelsesspesifikke mål for styrke."
            )
        case .body:
            return ATHLTHLocalization.format(
                english: "Body-weight goals.",
                norwegian: "Mål for kroppsvekt."
            )
        case .consistency:
            return ATHLTHLocalization.format(
                english: "Workout frequency and consistency.",
                norwegian: "Mål for treningsfrekvens og kontinuitet."
            )
        case .recovery:
            return ATHLTHLocalization.format(
                english: "Sleep-duration goals.",
                norwegian: "Mål for søvnlengde."
            )
        case .custom:
            return ATHLTHLocalization.format(
                english: "Define a goal that does not fit a template.",
                norwegian: "Lag et mål som ikke passer i en mal."
            )
        }
    }

    var systemImage: String {
        switch self {
        case .event: return "flag.checkered"
        case .endurance: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .body: return "scalemass.fill"
        case .consistency: return "calendar.badge.checkmark"
        case .recovery: return "moon.stars.fill"
        case .custom: return "sparkles"
        }
    }
}

enum GoalStatus: String, CaseIterable, Codable, Hashable {
    case active
    case paused
    case completed
    case abandoned
}

enum GoalPrivacy: String, CaseIterable, Identifiable, Codable, Hashable {
    case privateOnly
    case friends
    case publicVisible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateOnly: return ATHLTHLocalization.string( "Private")
        case .friends: return ATHLTHLocalization.string( "Followers")
        case .publicVisible: return ATHLTHLocalization.string( "Public")
        }
    }
}

enum GoalDataSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case appleHealth
    case athlth
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleHealth: return ATHLTHLocalization.string( "Apple Health")
        case .athlth: return ATHLTHLocalization.string( "ATHLTH")
        case .manual: return ATHLTHLocalization.string( "Manual")
        }
    }

    var systemImage: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .athlth: return "a.circle.fill"
        case .manual: return "hand.tap.fill"
        }
    }
}

enum GoalMetric: String, Codable, Hashable {
    case bodyWeightKilograms
    case bodyWeightChangeKilograms
    case singleWorkoutDistanceMeters
    case strengthWeightKilograms
    case workoutCount
    case dailySteps
    case sleepDurationSeconds
    case manualProgress
}

enum GoalComparison: String, Codable, Hashable {
    case atLeast
    case atMost
    case decreaseFromBaseline
    case increaseFromBaseline
}

enum GoalActivityFilter: String, Codable, Hashable {
    case any
    case running
    case walking
    case cycling
    case hiking

    var title: String {
        switch self {
        case .any: return ATHLTHLocalization.string( "Any workout")
        case .running: return ATHLTHLocalization.string( "Running")
        case .walking: return ATHLTHLocalization.string( "Walking")
        case .cycling: return ATHLTHLocalization.string( "Cycling")
        case .hiking: return ATHLTHLocalization.string( "Hiking")
        }
    }
}

enum GoalCompletionMethod: String, Codable, Hashable {
    case automaticAppleHealth
    case automaticATHLTH
    case manual
}

enum GoalMilestoneManualOverride: String, Codable, Hashable {
    case none
    case forceCompleted
    case forceIncomplete
}

enum GoalCoverStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case forest
    case summit
    case track
    case strength
    case calm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest: return ATHLTHLocalization.string( "Forest")
        case .summit: return ATHLTHLocalization.string( "Summit")
        case .track: return ATHLTHLocalization.string( "Track")
        case .strength: return ATHLTHLocalization.string( "Strength")
        case .calm: return ATHLTHLocalization.string( "Calm")
        }
    }
}

struct GoalAutomationRule: Codable, Hashable {
    var isEnabled: Bool
    var dataSource: GoalDataSource
    var metric: GoalMetric
    var comparison: GoalComparison
    var targetValue: Double
    var baselineValue: Double?
    var activity: GoalActivityFilter?
    var exerciseName: String?
    var countEvidenceOnlyAfterGoalCreation: Bool

    init(
        isEnabled: Bool = true,
        dataSource: GoalDataSource,
        metric: GoalMetric,
        comparison: GoalComparison,
        targetValue: Double,
        baselineValue: Double? = nil,
        activity: GoalActivityFilter? = nil,
        exerciseName: String? = nil,
        countEvidenceOnlyAfterGoalCreation: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.dataSource = dataSource
        self.metric = metric
        self.comparison = comparison
        self.targetValue = targetValue
        self.baselineValue = baselineValue
        self.activity = activity
        self.exerciseName = exerciseName
        self.countEvidenceOnlyAfterGoalCreation = countEvidenceOnlyAfterGoalCreation
    }
}

struct GoalMilestone: Identifiable, Codable, Hashable {
    let id: UUID
    var createdAt: Date
    var title: String
    var targetDescription: String
    var automationRule: GoalAutomationRule?
    var completesGoal: Bool
    var completedAt: Date?
    var completionMethod: GoalCompletionMethod?
    var manualOverride: GoalMilestoneManualOverride
    var lastEvaluatedAt: Date?
    var lastEvidenceDescription: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        targetDescription: String,
        automationRule: GoalAutomationRule? = nil,
        completesGoal: Bool = false,
        completedAt: Date? = nil,
        completionMethod: GoalCompletionMethod? = nil,
        manualOverride: GoalMilestoneManualOverride = .none,
        lastEvaluatedAt: Date? = nil,
        lastEvidenceDescription: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.targetDescription = targetDescription
        self.automationRule = automationRule
        self.completesGoal = completesGoal
        self.completedAt = completedAt
        self.completionMethod = completionMethod
        self.manualOverride = manualOverride
        self.lastEvaluatedAt = lastEvaluatedAt
        self.lastEvidenceDescription = lastEvidenceDescription
    }

    var isCompleted: Bool { completedAt != nil }
}

struct GoalTarget: Codable, Hashable {
    var metric: GoalMetric
    var targetValue: Double
    var unit: String
    var baselineValue: Double?
    var activity: GoalActivityFilter?
    var exerciseName: String?
}

struct ATHLTHGoal: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var category: GoalCategory
    var createdAt: Date
    var startDate: Date
    var deadline: Date?
    var imageFilename: String?
    var coverStyle: GoalCoverStyle
    var whyItMatters: String?
    var notes: String?
    var privacy: GoalPrivacy
    var status: GoalStatus
    var isPrimary: Bool
    var dataSource: GoalDataSource
    var target: GoalTarget?
    var milestones: [GoalMilestone]
    var linkedTrainingPlanID: UUID?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        category: GoalCategory,
        createdAt: Date = Date(),
        startDate: Date = Date(),
        deadline: Date? = nil,
        imageFilename: String? = nil,
        coverStyle: GoalCoverStyle = .forest,
        whyItMatters: String? = nil,
        notes: String? = nil,
        privacy: GoalPrivacy = .privateOnly,
        status: GoalStatus = .active,
        isPrimary: Bool = false,
        dataSource: GoalDataSource,
        target: GoalTarget? = nil,
        milestones: [GoalMilestone] = [],
        linkedTrainingPlanID: UUID? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.createdAt = createdAt
        self.startDate = startDate
        self.deadline = deadline
        self.imageFilename = imageFilename
        self.coverStyle = coverStyle
        self.whyItMatters = whyItMatters
        self.notes = notes
        self.privacy = privacy
        self.status = status
        self.isPrimary = isPrimary
        self.dataSource = dataSource
        self.target = target
        self.milestones = milestones
        self.linkedTrainingPlanID = linkedTrainingPlanID
        self.completedAt = completedAt
    }

    var progress: Double {
        guard !milestones.isEmpty else {
            return status == .completed ? 1 : 0
        }
        let complete = milestones.filter(\.isCompleted).count
        return Double(complete) / Double(milestones.count)
    }

    var completedMilestones: Int {
        milestones.filter(\.isCompleted).count
    }
}

struct GoalAutomationEvidence: Hashable {
    let currentValue: Double
    let evidenceDate: Date
    let description: String
}
