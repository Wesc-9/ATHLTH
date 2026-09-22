import Foundation

enum ATHLTHChallengeSport: String, CaseIterable, Identifiable, Codable, Hashable {
    case running
    case strength

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return "Running"
        case .strength: return "Strength"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .strength: return "dumbbell.fill"
        }
    }
}

enum ATHLTHChallengeScoring: String, CaseIterable, Identifiable, Codable, Hashable {
    case fastestDistance
    case farthestInTime
    case mostDistance
    case fastestRoute
    case heaviestWeight
    case mostReps
    case exerciseVolume
    case workoutVolume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastestDistance: return "Fastest Distance"
        case .farthestInTime: return "Farthest in Time"
        case .mostDistance: return "Most Distance"
        case .fastestRoute: return "Fastest Route"
        case .heaviestWeight: return "Heaviest Weight"
        case .mostReps: return "Most Reps"
        case .exerciseVolume: return "Exercise Volume"
        case .workoutVolume: return "Workout Volume"
        }
    }

    var prefersLowerScore: Bool {
        switch self {
        case .fastestDistance, .fastestRoute:
            return true
        default:
            return false
        }
    }
}

enum ChallengeVerificationPolicy: String, CaseIterable, Identifiable, Codable, Hashable {
    case verifiedRequired
    case verifiedPreferredManualAllowed
    case manualAllowed
    case manualOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verifiedRequired: return "Verified required"
        case .verifiedPreferredManualAllowed: return "Verified preferred"
        case .manualAllowed: return "Manual allowed"
        case .manualOnly: return "Manual only"
        }
    }

    var subtitle: String {
        switch self {
        case .verifiedRequired:
            return "Only qualifying ATHLTH or Apple Health attempts count."
        case .verifiedPreferredManualAllowed:
            return "Verified attempts are preferred, but manual submissions are accepted and labelled."
        case .manualAllowed:
            return "Both verified and manual attempts count equally, with clear labels."
        case .manualOnly:
            return "All results are entered manually."
        }
    }

    var allowsManual: Bool {
        self != .verifiedRequired
    }

    var allowsVerified: Bool {
        self != .manualOnly
    }
}

enum ChallengeAttemptVerification: String, Codable, Hashable {
    case appleHealth
    case athlth
    case manual

    var title: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .athlth: return "ATHLTH Verified"
        case .manual: return "Manual"
        }
    }

    var systemImage: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .athlth: return "checkmark.seal.fill"
        case .manual: return "hand.tap.fill"
        }
    }
}

enum ChallengeTimeBasis: String, CaseIterable, Identifiable, Codable, Hashable {
    case elapsed
    case moving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elapsed: return "Elapsed Time"
        case .moving: return "Moving Time"
        }
    }
}

enum ATHLTHChallengeStatus: String, Codable, Hashable {
    case draft
    case invited
    case upcoming
    case active
    case completed
    case cancelled
}

enum ChallengeParticipantState: String, Codable, Hashable {
    case creator
    case invited
    case accepted
    case declined
}

struct ChallengeParticipant: Identifiable, Codable, Hashable {
    let id: UUID
    var userID: UUID?
    var username: String?
    var displayName: String
    var state: ChallengeParticipantState
    var invitedAt: Date
    var respondedAt: Date?

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        username: String? = nil,
        displayName: String,
        state: ChallengeParticipantState = .invited,
        invitedAt: Date = Date(),
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.state = state
        self.invitedAt = invitedAt
        self.respondedAt = respondedAt
    }
}

struct ChallengeRouteSnapshot: Codable, Hashable {
    let routeID: UUID?
    let title: String
    let distanceKilometers: Double
    let coordinates: [RouteCoordinate]
}

struct ChallengeMeetup: Codable, Hashable {
    var placeName: String
    var latitude: Double
    var longitude: Double
    var scheduledAt: Date
    var checkInRadiusMeters: Double
}

struct ATHLTHChallengeRules: Codable, Hashable {
    var scoring: ATHLTHChallengeScoring
    var verificationPolicy: ChallengeVerificationPolicy

    var targetDistanceMeters: Double?
    var targetDurationSeconds: TimeInterval?
    var timeBasis: ChallengeTimeBasis

    var route: ChallengeRouteSnapshot?
    var gpsRequired: Bool
    var minimumRouteMatchPercent: Double?

    var exerciseName: String?
    var fixedWeightKilograms: Double?

    var startsAt: Date
    var endsAt: Date?
    var allowMultipleAttempts: Bool
    var lockRulesAtStart: Bool

    var meetup: ChallengeMeetup?
}

struct ChallengeAttempt: Identifiable, Codable, Hashable {
    let id: UUID
    let challengeID: UUID
    var participantID: UUID
    var userID: UUID?
    var participantName: String

    var submittedAt: Date
    var startedAt: Date?
    var endedAt: Date?

    var verification: ChallengeAttemptVerification
    var sourceWorkoutID: UUID?

    var durationSeconds: TimeInterval?
    var distanceMeters: Double?
    var weightKilograms: Double?
    var reps: Int?
    var volumeKilograms: Double?
    var routeMatchPercent: Double?

    var score: Double
    var detail: String
    var manualNote: String?
    var isEligible: Bool
    var ineligibilityReason: String?
}

struct ATHLTHChallenge: Identifiable, Codable, Hashable {
    let id: UUID
    var creatorID: UUID
    var title: String
    var sport: ATHLTHChallengeSport
    var status: ATHLTHChallengeStatus
    var createdAt: Date

    var participants: [ChallengeParticipant]
    var rules: ATHLTHChallengeRules
    var attempts: [ChallengeAttempt]

    var visibility: ProfileVisibility
    var rulesLockedAt: Date?

    init(
        id: UUID = UUID(),
        creatorID: UUID,
        title: String,
        sport: ATHLTHChallengeSport,
        status: ATHLTHChallengeStatus = .invited,
        createdAt: Date = Date(),
        participants: [ChallengeParticipant],
        rules: ATHLTHChallengeRules,
        attempts: [ChallengeAttempt] = [],
        visibility: ProfileVisibility = .friends,
        rulesLockedAt: Date? = nil
    ) {
        self.id = id
        self.creatorID = creatorID
        self.title = title
        self.sport = sport
        self.status = status
        self.createdAt = createdAt
        self.participants = participants
        self.rules = rules
        self.attempts = attempts
        self.visibility = visibility
        self.rulesLockedAt = rulesLockedAt
    }

    var rulesAreLocked: Bool {
        rulesLockedAt != nil ||
        (rules.lockRulesAtStart && Date() >= rules.startsAt)
    }
}

struct ChallengeLeaderboardEntry: Identifiable, Hashable {
    var id: UUID { participant.id }

    let participant: ChallengeParticipant
    let bestAttempt: ChallengeAttempt?
    let rank: Int?
}
