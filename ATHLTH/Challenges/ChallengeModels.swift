import Foundation

enum ATHLTHChallengeSport: String, CaseIterable, Identifiable, Codable, Hashable {
    case running
    case walking
    case strength
    case heartRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Running",
                norwegian: "Løping"
            )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walking",
                norwegian: "Gåing"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .heartRate:
            return ATHLTHLocalization.choose(
                english: "Heart Rate",
                norwegian: "Puls"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
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
            return ATHLTHLocalization.string( "Fastest")
        case .farthestInTime:
            return ATHLTHLocalization.string( "Farthest in Time")
        case .mostDistance:
            return ATHLTHLocalization.string( "Most Distance")
        case .heaviestWeight: return ATHLTHLocalization.string( "Heaviest Weight")
        case .mostReps: return ATHLTHLocalization.string( "Most Reps")
        case .exerciseVolume: return ATHLTHLocalization.string( "Exercise Volume")
        case .workoutVolume: return ATHLTHLocalization.string( "Workout Volume")
        case .heartRateZoneTime: return ATHLTHLocalization.string( "Time in Zone")
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

/// An optional specialty for running challenges. Old records decode as
/// standard runs; this does not change the existing scoring enum.
enum ATHLTHChallengeRunningFocus: String, CaseIterable, Identifiable, Codable, Hashable {
    case standard
    case hills
    case intervals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return ATHLTHLocalization.choose(english: "Running", norwegian: "Vanlig løping")
        case .hills:
            return ATHLTHLocalization.choose(english: "Hill repeats", norwegian: "Bakkeløp")
        case .intervals:
            return ATHLTHLocalization.choose(english: "Intervals", norwegian: "Intervall")
        }
    }
}

enum ATHLTHChallengeRunningComparison: String, CaseIterable, Identifiable, Codable, Hashable {
    case fastestWork
    case mostWorkDistance
    case completedRepeats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastestWork:
            return ATHLTHLocalization.choose(
                english: "Fastest work time", norwegian: "Raskeste drag"
            )
        case .mostWorkDistance:
            return ATHLTHLocalization.choose(
                english: "Longest work distance", norwegian: "Lengst distanse i drag"
            )
        case .completedRepeats:
            return ATHLTHLocalization.choose(
                english: "Most completed repeats", norwegian: "Flest fullførte drag"
            )
        }
    }
}

/// Only measured WORK steps in the actual completed structured session
/// count. Warmup, recovery, downhill jog and cooldown are never included.
enum ATHLTHChallengeRunningWorkPolicy {
    struct Work: Equatable {
        let seconds: Double
        let meters: Double
        let count: Int
    }

    static func measuredWork(
        from result: WatchWorkoutResult,
        expectedTemplateID: UUID,
        minimumRepetitions: Int
    ) -> Work? {
        guard result.structuredWorkoutFullyCompleted == true,
              result.structuredWorkoutSourceID == expectedTemplateID,
              let steps = result.recordedRunningSteps,
              !steps.isEmpty else { return nil }
        let work = steps.filter {
            $0.phase?.lowercased() == "work"
        }
        guard work.count >= max(1, minimumRepetitions),
              work.allSatisfy({
                  $0.activeSeconds.isFinite && $0.activeSeconds >= 1 &&
                  $0.distanceMeters.isFinite && $0.distanceMeters >= 0 &&
                  !$0.isUserReported
              })
        else { return nil }
        let time = work.reduce(0.0) { $0 + $1.activeSeconds }
        let distance = work.reduce(0.0) { $0 + $1.distanceMeters }
        guard time.isFinite, time > 0,
              distance.isFinite, distance > 0 else { return nil }
        return Work(seconds: time, meters: distance, count: work.count)
    }
}

/// A challenge may share a structured workout prescription with invitees,
/// but never serializes account-owned route, coaching or Spotify settings.
enum ATHLTHChallengeRunningTemplateTransfer {
    static func portable(_ source: RunningWorkoutTemplate) -> RunningWorkoutTemplate {
        var copy = source
        copy.routeID = nil
        copy.coachBrief = nil
        copy.intervalGhostPaceSecondsPerKilometer = nil
        copy.intervalGhostFollowRecovery = nil
        copy.intervalGhostRecoverySlowdownPercent = nil
        copy.blocks = copy.blocks.map { block in
            var clean = block
            clean.spotifyPlaylist = nil
            return clean
        }
        return copy
    }
}

enum ChallengeCreationPolicy {
    static func automaticTitle(
        sport: ATHLTHChallengeSport,
        scoring: ATHLTHChallengeScoring
    ) -> String {
        "\(sport.title) · \(scoring.title)"
    }

    static func resolvedTitle(
        _ title: String,
        sport: ATHLTHChallengeSport,
        scoring: ATHLTHChallengeScoring
    ) -> String {
        let clean = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return clean.isEmpty
            ? automaticTitle(
                sport: sport,
                scoring: scoring
            )
            : String(clean.prefix(60))
    }

    static func resolvedTitle(
        _ title: String,
        sport: ATHLTHChallengeSport,
        scoring: ATHLTHChallengeScoring,
        creatorName: String,
        invitedNames: [String],
        scoringTitle: String? = nil
    ) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.isEmpty else { return String(clean.prefix(100)) }

        func shortName(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return String((trimmed.isEmpty ? "ATHLTH" : trimmed).prefix(20))
        }

        let people: String
        switch invitedNames.count {
        case 0:
            people = shortName(creatorName)
        case 1:
            people = shortName(creatorName) + " · " + shortName(invitedNames[0])
        case 2:
            people = shortName(creatorName) + " · " +
                invitedNames.map(shortName).joined(separator: " · ")
        default:
            people = shortName(creatorName) + " + " +
                String(invitedNames.count)
        }
        let titlePart = (scoringTitle ?? automaticTitle(
            sport: sport, scoring: scoring
        )).replacingOccurrences(of: " · ", with: " • ")
        return String((titlePart + " • " +
            people.replacingOccurrences(of: " · ", with: " • ")).prefix(120))
    }

    static func requiresDirectInvite(
        visibility: ProfileVisibility
    ) -> Bool {
        visibility != .publicProfile
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
        case .verifiedRequired: return ATHLTHLocalization.string( "Verified required")
        case .verifiedPreferredManualAllowed: return ATHLTHLocalization.string( "Verified preferred")
        case .manualAllowed: return ATHLTHLocalization.string( "Manual allowed")
        case .manualOnly: return ATHLTHLocalization.string( "Manual only")
        }
    }

    var subtitle: String {
        switch self {
        case .verifiedRequired:
            return ATHLTHLocalization.string( "Only qualifying ATHLTH or Apple Health attempts count.")
        case .verifiedPreferredManualAllowed:
            return ATHLTHLocalization.string( "Verified attempts are preferred, but manual submissions are accepted and labelled.")
        case .manualAllowed:
            return ATHLTHLocalization.string( "Both verified and manual attempts count equally, with clear labels.")
        case .manualOnly:
            return ATHLTHLocalization.string( "All results are entered manually.")
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
        case .appleHealth: return ATHLTHLocalization.string( "Apple Health")
        case .athlth: return ATHLTHLocalization.string( "ATHLTH Verified")
        case .manual: return ATHLTHLocalization.string( "Manual")
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
        case .elapsed: return ATHLTHLocalization.string( "Elapsed Time")
        case .moving: return ATHLTHLocalization.string( "Moving Time")
        }
    }
}

enum ChallengeRouteDirection: String, CaseIterable, Identifiable, Codable, Hashable {
    case sameDirection
    case eitherDirection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sameDirection: return ATHLTHLocalization.string( "Same Direction")
        case .eitherDirection: return ATHLTHLocalization.string( "Either Direction")
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
        case .best: return ATHLTHLocalization.string( "Best Attempt")
        case .first: return ATHLTHLocalization.string( "First Attempt")
        case .latest: return ATHLTHLocalization.string( "Latest Attempt")
        }
    }

    var shortTitle: String {
        switch self {
        case .best: return ATHLTHLocalization.string( "Best counts")
        case .first: return ATHLTHLocalization.string( "First counts")
        case .latest: return ATHLTHLocalization.string( "Latest counts")
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
            return ATHLTHLocalization.string( "Best Workout")
        case .totalChallenge:
            return ATHLTHLocalization.string( "Total Challenge")
        }
    }

    var subtitle: String {
        switch self {
        case .bestWorkout:
            return ATHLTHLocalization.string( "Your single workout with the most time in the selected zone counts.")
        case .totalChallenge:
            return ATHLTHLocalization.string( "Time in the selected zone adds up across all qualifying workouts.")
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
    case withdrawn
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

/// A private Train Together intent, not a discoverable marketplace post.
enum ChallengeTrainTogetherMode: String, Codable, Hashable {
    case physical
    case sameWorkout
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
    // created before Ghost support default to allowing these pacing tools.
    var allowTargetGhost: Bool? = nil
    var allowLiveGhost: Bool? = nil

    var exerciseName: String?
    var fixedWeightKilograms: Double?

    // Heart-rate challenge rules use each participant's own private max HR.
    // The actual max-HR value is intentionally never stored on the challenge.
    var heartRateZone: Int? = nil
    var heartRateAggregation: ChallengeHeartRateAggregation? = nil

    // Optional presentation metadata. Stored inside the rules JSON so
    // existing challenge rows remain backwards-compatible.
    var summary: String? = nil
    var coverArtworkName: String? = nil
    var coverImageURL: String? = nil

    // Optional marker for a direct Friends-vs-Friends duel. Stored in the
    // existing rules JSON, so older challenges remain fully compatible and no
    // database schema change is required.
    var headToHeadMetricRaw: String? = nil

    // Specialty running challenges require the same saved/installed
    // structured template for everyone. These fields are optional for old
    // challenges and work with the existing rules JSON.
    var runningFocus: ATHLTHChallengeRunningFocus? = nil
    var runningComparison: ATHLTHChallengeRunningComparison? = nil
    var runningTemplateID: UUID? = nil
    var runningMinimumRepetitions: Int? = nil
    /// Portable, explicitly shared workout prescription. Never includes
    /// local route IDs, Spotify data, or private coach notes.
    var runningTemplateSnapshot: RunningWorkoutTemplate? = nil

    var startsAt: Date
    var endsAt: Date?
    var allowMultipleAttempts: Bool
    var lockRulesAtStart: Bool

    var meetup: ChallengeMeetup?
    // nil means no Train Together request. Historical meetups are physical.
    var trainTogetherModeRaw: String? = nil

    var trainTogetherMode: ChallengeTrainTogetherMode? {
        if let trainTogetherModeRaw {
            return ChallengeTrainTogetherMode(rawValue: trainTogetherModeRaw)
        }
        return meetup != nil ? .physical : nil
    }

    var targetGhostAllowed: Bool {
        allowTargetGhost ?? true
    }

    var liveGhostAllowed: Bool {
        allowLiveGhost ?? true
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

    /// An invitation or a lone creator is never a valid contest.
    /// Treat legacy "completed" rows with no accepted opponent as cancelled
    /// once their deadline has passed.
    var hasAcceptedOpponent: Bool {
        participants.contains {
            $0.userID != creatorID &&
            $0.state == .accepted &&
            $0.respondedAt != nil
        }
    }

    func expiredWithoutOpponent(at date: Date = Date()) -> Bool {
        guard status != .draft,
              let end = rules.endsAt,
              date >= end else { return false }
        return !hasAcceptedOpponent
    }

    // The first opponent must explicitly accept before any workout can score.
    // Start time is based on the actual accepted response, never invite time.
    var scoringStartDate: Date? {
        let acceptedAt = participants
            .filter { $0.state == .accepted && $0.userID != creatorID }
            .compactMap(\.respondedAt)
            .min()
        guard status != .draft,
              status != .cancelled,
              let acceptedAt else { return nil }
        return max(rules.startsAt, acceptedAt)
    }

    func scoringStartDate(for participantID: UUID) -> Date? {
        guard let start = scoringStartDate,
              let person = participants.first(where: { $0.id == participantID })
        else { return nil }
        switch person.state {
        case .creator:
            return start
        case .accepted:
            guard let acceptedAt = person.respondedAt else { return nil }
            return max(start, acceptedAt)
        case .invited, .declined, .withdrawn:
            return nil
        }
    }

    func canCountWorkout(startedAt: Date, participantID: UUID) -> Bool {
        guard let start = scoringStartDate(for: participantID),
              startedAt >= start else { return false }
        return rules.endsAt.map { startedAt <= $0 } ?? true
    }

    // Invalid route/verification results still remain visible after acceptance
    // with their explanation, but must never contribute to the leaderboard.
    func showsAttempt(_ attempt: ChallengeAttempt) -> Bool {
        guard attempt.challengeID == id else { return false }
        let performedAt = attempt.verification == .manual
            ? attempt.submittedAt
            : attempt.startedAt
        guard let performedAt else { return false }
        return canCountWorkout(startedAt: performedAt, participantID: attempt.participantID)
    }

    func countsAttempt(_ attempt: ChallengeAttempt) -> Bool {
        attempt.isEligible && showsAttempt(attempt)
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
