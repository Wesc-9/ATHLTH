import Foundation

enum ATHLTHChallengeSport: String, CaseIterable, Identifiable, Codable, Hashable {
    case running
    case strength
    case heartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return String(localized: "Running")
        case .strength: return String(localized: "Strength")
        case .heartRate: return String(localized: "Heart Rate")
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .heartRate: return "heart.circle.fill"
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
    case heartRateZoneTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastestDistance, .fastestRoute:
            return String(localized: "Fastest")
        case .farthestInTime:
            return String(localized: "Farthest in Time")
        case .mostDistance:
            return String(localized: "Most Distance")
        case .heaviestWeight: return String(localized: "Heaviest Weight")
        case .mostReps: return String(localized: "Most Reps")
        case .exerciseVolume: return String(localized: "Exercise Volume")
        case .workoutVolume: return String(localized: "Workout Volume")
        case .heartRateZoneTime: return String(localized: "Time in Zone")
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
        case .verifiedRequired: return String(localized: "Verified required")
        case .verifiedPreferredManualAllowed: return String(localized: "Verified preferred")
        case .manualAllowed: return String(localized: "Manual allowed")
        case .manualOnly: return String(localized: "Manual only")
        }
    }

    var subtitle: String {
        switch self {
        case .verifiedRequired:
            return String(localized: "Only qualifying ATHLTH or Apple Health attempts count.")
        case .verifiedPreferredManualAllowed:
            return String(localized: "Verified attempts are preferred, but manual submissions are accepted and labelled.")
        case .manualAllowed:
            return String(localized: "Both verified and manual attempts count equally, with clear labels.")
        case .manualOnly:
            return String(localized: "All results are entered manually.")
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
        case .appleHealth: return String(localized: "Apple Health")
        case .athlth: return String(localized: "ATHLTH Verified")
        case .manual: return String(localized: "Manual")
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
        case .elapsed: return String(localized: "Elapsed Time")
        case .moving: return String(localized: "Moving Time")
        }
    }
}

enum ChallengeRouteDirection: String, CaseIterable, Identifiable, Codable, Hashable {
    case sameDirection
    case eitherDirection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameDirection: return String(localized: "Same Direction")
        case .eitherDirection: return String(localized: "Either Direction")
        }
    }
}

enum ChallengeAttemptPolicy: String, CaseIterable, Identifiable, Codable, Hashable {
    case best
    case first
    case latest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: return String(localized: "Best Attempt")
        case .first: return String(localized: "First Attempt")
        case .latest: return String(localized: "Latest Attempt")
        }
    }

    var shortTitle: String {
        switch self {
        case .best: return String(localized: "Best counts")
        case .first: return String(localized: "First counts")
        case .latest: return String(localized: "Latest counts")
        }
    }
}

enum ChallengeHeartRateAggregation: String, CaseIterable, Identifiable, Codable, Hashable {
    case bestWorkout
    case totalChallenge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestWorkout:
            return String(localized: "Best Workout")
        case .totalChallenge:
            return String(localized: "Total Challenge")
        }
    }

    var subtitle: String {
        switch self {
        case .bestWorkout:
            return String(localized: "Your single workout with the most time in the selected zone counts.")
        case .totalChallenge:
            return String(localized: "Time in the selected zone adds up across all qualifying workouts.")
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

    // Optional so challenges created before 1.4.2 keep their original
    // qualification behaviour when decoded from disk/Supabase.
    var distanceTolerancePercent: Double? = nil
    var startFinishToleranceMeters: Double? = nil
    var routeDirection: ChallengeRouteDirection? = nil
    var attemptPolicy: ChallengeAttemptPolicy? = nil
    var maximumAttempts: Int? = nil
    var allowTreadmill: Bool? = nil

    // Optional for backwards compatibility. Existing route challenges
    // created before Target Ghost support default to allowing the pacing aid.
    var allowTargetGhost: Bool? = nil

    var exerciseName: String?
    var fixedWeightKilograms: Double?

    // Heart-rate challenge rules use each participant's own private max HR.
    // The actual max-HR value is intentionally never stored on the challenge.
    var heartRateZone: Int? = nil
    var heartRateAggregation: ChallengeHeartRateAggregation? = nil

    var startsAt: Date
    var endsAt: Date?
    var allowMultipleAttempts: Bool
    var lockRulesAtStart: Bool

    var meetup: ChallengeMeetup?

    var targetGhostAllowed: Bool {
        allowTargetGhost ?? true
    }
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

struct ChallengeMeetupCheckIn: Identifiable, Codable, Hashable {
    let id: UUID
    let participantID: UUID
    let checkedInAt: Date
    let distanceFromMeetupMeters: Double?
    let verifiedNearMeetup: Bool

    init(
        id: UUID = UUID(),
        participantID: UUID,
        checkedInAt: Date = Date(),
        distanceFromMeetupMeters: Double? = nil,
        verifiedNearMeetup: Bool = false
    ) {
        self.id = id
        self.participantID = participantID
        self.checkedInAt = checkedInAt
        self.distanceFromMeetupMeters = distanceFromMeetupMeters
        self.verifiedNearMeetup = verifiedNearMeetup
    }
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
    var checkIns: [ChallengeMeetupCheckIn]

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
        checkIns: [ChallengeMeetupCheckIn] = [],
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
        self.checkIns = checkIns
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
    let score: Double?
    let attemptCount: Int
    let rank: Int?
}

struct ChallengeHeartRateEvidence: Hashable {
    let startedAt: Date
    let endedAt: Date
    let zone: Int
    let zoneTimeSeconds: TimeInterval
    let averageHeartRateBPM: Double?
    let peakHeartRateBPM: Double?
    let score: Double
    let detail: String
    let isEligible: Bool
    let ineligibilityReason: String?
}

struct ChallengeRunningEvidence: Hashable {
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let routeMatchPercent: Double?
    let score: Double
    let detail: String
    let isEligible: Bool
    let ineligibilityReason: String?
}
