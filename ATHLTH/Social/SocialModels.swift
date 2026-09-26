import Foundation

enum SocialFriendRequestState: String, Codable, Hashable {
    case pending
    case accepted
    case declined
    case cancelled
}

struct SocialProfileCard: Identifiable, Codable, Hashable {
    var id: UUID { userID }

    let userID: UUID
    let username: String?
    let displayName: String?
    let bio: String?
    let avatarURL: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var resolvedName: String {
        let clean = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !clean.isEmpty { return clean }
        if let username, !username.isEmpty { return "@\(username)" }
        return "ATHLTH Athlete"
    }

    var usernameLabel: String {
        guard let username, !username.isEmpty else { return "" }
        return "@\(username)"
    }
}

struct SocialProfileDetailRecord: Codable, Hashable {
    let userID: UUID
    let bio: String?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case bio
        case updatedAt = "updated_at"
    }
}

struct SocialFriendshipRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let userA: UUID
    let userB: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userA = "user_a"
        case userB = "user_b"
        case createdAt = "created_at"
    }

    func otherUserID(for currentUserID: UUID) -> UUID? {
        if userA == currentUserID { return userB }
        if userB == currentUserID { return userA }
        return nil
    }
}

struct SocialFriendRequestRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    var status: SocialFriendRequestState
    let message: String?
    let createdAt: Date
    let respondedAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case status
        case message
        case createdAt = "created_at"
        case respondedAt = "responded_at"
        case updatedAt = "updated_at"
    }
}

struct SocialFriendRequestDisplay: Identifiable, Hashable {
    var id: UUID { request.id }

    let request: SocialFriendRequestRecord
    let profile: SocialProfileCard
    let isIncoming: Bool
}

struct SocialPrivacySettings: Codable, Equatable, Hashable {
    let userID: UUID
    var profileVisibility: String
    var discoverable: Bool
    var allowFriendRequests: Bool
    var allowDirectMessages: String
    var trainingFocusVisibility: String
    var trainingPresenceVisibility: String
    var performanceStatsVisibility: String
    var trophyCabinetVisibility: String
    var recentActivityVisibility: String
    var goalsVisibility: String
    var runningPRsVisibility: String
    var strengthPRsVisibility: String
    var shareTrainingPresence: Bool
    var sharePerformanceStats: Bool
    var shareTrophyCabinet: Bool
    var shareGoals: Bool
    var shareRecentActivity: Bool
    var shareRunningPRs: Bool
    var shareStrengthPRs: Bool
    var shareWorkoutTotals: Bool
    var allowChallengeInvites: String
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case profileVisibility = "profile_visibility"
        case discoverable
        case allowFriendRequests = "allow_friend_requests"
        case allowDirectMessages = "allow_direct_messages"
        case trainingFocusVisibility = "training_focus_visibility"
        case trainingPresenceVisibility = "training_presence_visibility"
        case performanceStatsVisibility = "performance_stats_visibility"
        case trophyCabinetVisibility = "trophy_cabinet_visibility"
        case recentActivityVisibility = "recent_activity_visibility"
        case goalsVisibility = "goals_visibility"
        case runningPRsVisibility = "running_prs_visibility"
        case strengthPRsVisibility = "strength_prs_visibility"
        case shareTrainingPresence = "share_training_presence"
        case sharePerformanceStats = "share_performance_stats"
        case shareTrophyCabinet = "share_trophy_cabinet"
        case shareGoals = "share_goals"
        case shareRecentActivity = "share_recent_activity"
        case shareRunningPRs = "share_running_prs"
        case shareStrengthPRs = "share_strength_prs"
        case shareWorkoutTotals = "share_workout_totals"
        case allowChallengeInvites = "allow_challenge_invites"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func fallback(userID: UUID) -> SocialPrivacySettings {
        SocialPrivacySettings(
            userID: userID,
            profileVisibility: "private",
            discoverable: false,
            allowFriendRequests: true,
            allowDirectMessages: "requests",
            trainingFocusVisibility: "private",
            trainingPresenceVisibility: "private",
            performanceStatsVisibility: "private",
            trophyCabinetVisibility: "private",
            recentActivityVisibility: "private",
            goalsVisibility: "private",
            runningPRsVisibility: "private",
            strengthPRsVisibility: "private",
            shareTrainingPresence: false,
            sharePerformanceStats: false,
            shareTrophyCabinet: false,
            shareGoals: false,
            shareRecentActivity: false,
            shareRunningPRs: false,
            shareStrengthPRs: false,
            shareWorkoutTotals: false,
            allowChallengeInvites: "friends",
            createdAt: nil,
            updatedAt: nil
        )
    }
}

struct SocialTrainingFocusRecord: Codable, Equatable, Hashable {
    let userID: UUID
    let focus: TrainingFocus
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case focus
        case updatedAt = "updated_at"
    }
}

struct SocialPerformanceStats: Codable, Equatable, Hashable {
    let userID: UUID
    var fastest1KSeconds: Double?
    var fastest1KDate: Date?
    var fastest5KSeconds: Double?
    var fastest5KDate: Date?
    var fastestMarathonSeconds: Double?
    var fastestMarathonDate: Date?
    var longestWorkoutSeconds: Double?
    var longestWorkoutDate: Date?
    var longestWorkoutActivity: String?
    var longestDistanceMeters: Double?
    var longestDistanceDate: Date?
    var longestDistanceActivity: String?
    var longestRunMeters: Double?
    var longestRunDate: Date?
    var totalWorkoutCount: Int
    var totalTrainingSeconds: Double
    var totalRunningDistanceMeters: Double
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case fastest1KSeconds = "fastest_1k_seconds"
        case fastest1KDate = "fastest_1k_date"
        case fastest5KSeconds = "fastest_5k_seconds"
        case fastest5KDate = "fastest_5k_date"
        case fastestMarathonSeconds = "fastest_marathon_seconds"
        case fastestMarathonDate = "fastest_marathon_date"
        case longestWorkoutSeconds = "longest_workout_seconds"
        case longestWorkoutDate = "longest_workout_date"
        case longestWorkoutActivity = "longest_workout_activity"
        case longestDistanceMeters = "longest_distance_meters"
        case longestDistanceDate = "longest_distance_date"
        case longestDistanceActivity = "longest_distance_activity"
        case longestRunMeters = "longest_run_meters"
        case longestRunDate = "longest_run_date"
        case totalWorkoutCount = "total_workout_count"
        case totalTrainingSeconds = "total_training_seconds"
        case totalRunningDistanceMeters = "total_running_distance_meters"
        case updatedAt = "updated_at"
    }

    init(userID: UUID, stats: ProfilePerformanceStats) {
        self.userID = userID
        fastest1KSeconds = stats.fastestOneKilometer?.duration
        fastest1KDate = stats.fastestOneKilometer?.date
        fastest5KSeconds = stats.fastestFiveKilometers?.duration
        fastest5KDate = stats.fastestFiveKilometers?.date
        fastestMarathonSeconds = stats.fastestMarathon?.duration
        fastestMarathonDate = stats.fastestMarathon?.date
        longestWorkoutSeconds = stats.longestWorkoutDuration
        longestWorkoutDate = stats.longestWorkoutDate
        longestWorkoutActivity = stats.longestWorkoutActivity?.rawValue
        longestDistanceMeters = stats.longestWorkoutDistanceMeters
        longestDistanceDate = stats.longestWorkoutDistanceDate
        longestDistanceActivity = stats.longestWorkoutDistanceActivity?.rawValue
        longestRunMeters = stats.longestRunMeters
        longestRunDate = stats.longestRunDate
        totalWorkoutCount = stats.totalWorkoutCount
        totalTrainingSeconds = stats.totalTrainingDuration
        totalRunningDistanceMeters = stats.totalRunningDistanceMeters
        updatedAt = Date()
    }
}

struct SocialTrophyShowcaseItem: Codable, Hashable, Identifiable {
    var id: String { trophyID }

    let trophyID: String
    let title: String
    let stageLabel: String
    let rarity: String
    let category: String
    let systemImage: String
    let unlockedAt: Date?

    enum CodingKeys: String, CodingKey {
        case trophyID = "trophy_id"
        case title
        case stageLabel = "stage_label"
        case rarity
        case category
        case systemImage = "system_image"
        case unlockedAt = "unlocked_at"
    }
}

struct SocialTrophyShowcaseRecord: Codable, Hashable {
    let userID: UUID
    let items: [SocialTrophyShowcaseItem]
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case items
        case updatedAt = "updated_at"
    }
}

struct SocialPresenceRecord: Codable, Hashable {
    let userID: UUID
    let state: String
    let workoutTitle: String?
    let startedAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case state
        case workoutTitle = "workout_title"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

enum SocialActivityReaction: String, CaseIterable, Identifiable, Codable, Hashable {
    case fire
    case strong
    case clap

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .fire: return "🔥"
        case .strong: return "💪"
        case .clap: return "👏"
        }
    }
}

struct SocialActivityRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let actorID: UUID
    let kind: String
    let title: String
    let subtitle: String?
    let metadata: [String: String]?
    let visibility: String
    let eventKey: String?
    let workoutSessionID: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case actorID = "actor_id"
        case kind
        case title
        case subtitle
        case metadata
        case visibility
        case eventKey = "event_key"
        case workoutSessionID = "workout_session_id"
        case createdAt = "created_at"
    }
}

struct SocialActivityReactionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let activityID: UUID
    let userID: UUID
    let reaction: SocialActivityReaction
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityID = "activity_id"
        case userID = "user_id"
        case reaction
        case createdAt = "created_at"
    }
}

struct SocialFeedItem: Identifiable, Hashable {
    var id: UUID { activity.id }

    let activity: SocialActivityRecord
    let actor: SocialProfileCard
    let reactions: [SocialActivityReactionRecord]
    let trainingPartners: [SocialWorkoutParticipantRecord] = []
}

struct SocialInboxEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let recipientID: UUID
    let kind: String
    let title: String
    let message: String
    let entityType: String?
    let entityID: UUID?
    let createdAt: Date
    let readAt: Date?
    let pushNotifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case recipientID = "recipient_id"
        case kind
        case title
        case message
        case entityType = "entity_type"
        case entityID = "entity_id"
        case createdAt = "created_at"
        case readAt = "read_at"
        case pushNotifiedAt = "push_notified_at"
    }
}

struct SocialFriendProfile: Hashable {
    let card: SocialProfileCard
    let trainingFocus: TrainingFocus?
    let presence: SocialPresenceRecord?
    let performance: SocialPerformanceStats?
    let trophies: [SocialTrophyShowcaseItem]
    let recentActivities: [SocialFeedItem]
}

struct SocialBlockedUser: Identifiable, Hashable {
    var id: UUID { profile.userID }
    let profile: SocialProfileCard
    let blockedAt: Date
}

struct BackendBlockRecord: Codable, Hashable {
    let blockerID: UUID
    let blockedID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
        case createdAt = "created_at"
    }
}

struct BackendSocialChallenge: Codable, Hashable {
    let id: UUID
    let creatorID: UUID
    let title: String
    let sport: String
    let status: String
    let rules: ATHLTHChallengeRules
    let visibility: String
    let startsAt: Date
    let endsAt: Date?
    let rulesLockedAt: Date?
    let createdAt: Date
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case title
        case sport
        case status
        case rules
        case visibility
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case rulesLockedAt = "rules_locked_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct BackendChallengeParticipant: Codable, Hashable {
    let id: UUID
    let challengeID: UUID
    let userID: UUID
    let state: String
    let invitedBy: UUID
    let invitedAt: Date
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case challengeID = "challenge_id"
        case userID = "user_id"
        case state
        case invitedBy = "invited_by"
        case invitedAt = "invited_at"
        case respondedAt = "responded_at"
    }
}

struct BackendChallengeAttempt: Codable, Hashable {
    let id: UUID
    let challengeID: UUID
    let participantID: UUID
    let userID: UUID
    let participantName: String
    let verification: String
    let sourceWorkoutID: UUID?
    let submittedAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let durationSeconds: Double?
    let distanceMeters: Double?
    let weightKilograms: Double?
    let reps: Int?
    let volumeKilograms: Double?
    let routeMatchPercent: Double?
    let score: Double
    let detail: String
    let manualNote: String?
    let isEligible: Bool
    let ineligibilityReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case challengeID = "challenge_id"
        case participantID = "participant_id"
        case userID = "user_id"
        case participantName = "participant_name"
        case verification
        case sourceWorkoutID = "source_workout_id"
        case submittedAt = "submitted_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case weightKilograms = "weight_kilograms"
        case reps
        case volumeKilograms = "volume_kilograms"
        case routeMatchPercent = "route_match_percent"
        case score
        case detail
        case manualNote = "manual_note"
        case isEligible = "is_eligible"
        case ineligibilityReason = "ineligibility_reason"
    }
}

struct BackendChallengeCheckIn: Codable, Hashable {
    let id: UUID
    let challengeID: UUID
    let participantID: UUID
    let userID: UUID
    let checkedInAt: Date
    let distanceFromMeetupMeters: Double?
    let verifiedNearMeetup: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case challengeID = "challenge_id"
        case participantID = "participant_id"
        case userID = "user_id"
        case checkedInAt = "checked_in_at"
        case distanceFromMeetupMeters = "distance_from_meetup_meters"
        case verifiedNearMeetup = "verified_near_meetup"
    }
}


enum SocialWorkoutSessionStatus: String, Codable, Hashable {
    case active
    case completed
    case cancelled
}

enum SocialWorkoutParticipantState: String, Codable, Hashable {
    case creator
    case invited
    case accepted
    case declined
}

struct SocialWorkoutSessionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let creatorID: UUID
    let title: String
    let workoutKind: String
    var status: SocialWorkoutSessionStatus
    let startedAt: Date
    var endedAt: Date?
    var sourceWorkoutID: UUID?
    let createdAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case title
        case workoutKind = "workout_kind"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case sourceWorkoutID = "source_workout_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SocialWorkoutParticipantRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let sessionID: UUID
    let userID: UUID
    let invitedBy: UUID
    var state: SocialWorkoutParticipantState
    let displayNameSnapshot: String
    let usernameSnapshot: String?
    let invitedAt: Date
    var respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case userID = "user_id"
        case invitedBy = "invited_by"
        case state
        case displayNameSnapshot = "display_name_snapshot"
        case usernameSnapshot = "username_snapshot"
        case invitedAt = "invited_at"
        case respondedAt = "responded_at"
    }
}

struct SocialWorkoutInviteDisplay: Identifiable, Hashable {
    var id: UUID { participant.id }

    let session: SocialWorkoutSessionRecord
    let participant: SocialWorkoutParticipantRecord
    let creator: SocialProfileCard?
}

struct SocialWorkoutStartSelection: Hashable {
    let title: String
    let workoutKind: String
    let friends: [SocialProfileCard]

    var isGroupWorkout: Bool {
        !friends.isEmpty
    }
}

struct SocialPublishableWorkout: Identifiable, Hashable {
    let id: UUID
    let title: String
    let activity: WorkoutActivity
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
    let strengthMuscleGroups: [String]?
    let strengthExerciseCount: Int?
    let source: String

    init(summary: WorkoutSummary) {
        id = summary.id
        title = summary.activity.rawValue
        activity = summary.activity
        startDate = summary.startDate
        endDate = summary.endDate
        duration = summary.duration
        distanceMeters = summary.distanceMeters
        activeEnergyKilocalories = summary.activeEnergyKilocalories
        strengthMuscleGroups = nil
        strengthExerciseCount = nil
        source = "Apple Health"
    }

    init(strengthWorkout: StrengthWorkoutLog) {
        id = strengthWorkout.healthMetrics.healthKitWorkoutUUID ?? strengthWorkout.id
        title = strengthWorkout.title
        activity = .strength
        startDate = strengthWorkout.startedAt
        endDate = strengthWorkout.endedAt ?? strengthWorkout.startedAt
        duration = max(
            (strengthWorkout.endedAt ?? strengthWorkout.startedAt)
                .timeIntervalSince(strengthWorkout.startedAt),
            0
        )
        distanceMeters = nil
        activeEnergyKilocalories = strengthWorkout.healthMetrics.activeCalories

        let performedExercises: [StrengthExerciseLog]
        if strengthWorkout.trackingMode == .advanced {
            let completedExercises = strengthWorkout.exercises.filter { exercise in
                exercise.isCompleted ||
                    exercise.sets.contains(where: { $0.isCompleted })
            }
            performedExercises = completedExercises
        } else {
            performedExercises = strengthWorkout.exercises
        }

        strengthExerciseCount = performedExercises.count

        var muscleGroups: [String] = []
        for rawGroup in performedExercises.flatMap({ $0.exercise.primaryMuscles }) {
            let group = rawGroup.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !group.isEmpty else { continue }

            if !muscleGroups.contains(where: {
                $0.caseInsensitiveCompare(group) == .orderedSame
            }) {
                muscleGroups.append(group)
            }
        }

        strengthMuscleGroups = muscleGroups.isEmpty ? nil : muscleGroups
        source = "ATHLTH"
    }

    init(watchResult: WatchWorkoutResult) {
        id = watchResult.healthKitWorkoutUUID ?? watchResult.id
        title = "\(watchResult.kind.title) completed"

        switch watchResult.kind {
        case .running:
            activity = .running
        case .walking:
            activity = .walking
        case .strength, .functional:
            activity = .strength
        case .hiit:
            activity = .hiit
        case .cycling:
            activity = .cycling
        case .rowing:
            activity = .rowing
        case .stairClimbing:
            activity = .stairClimbing
        case .yoga:
            activity = .yoga
        case .other:
            activity = .other
        }

        startDate = watchResult.startedAt
        endDate = watchResult.endedAt
        duration = watchResult.duration
        distanceMeters = watchResult.distanceMeters > 0
            ? watchResult.distanceMeters
            : nil
        activeEnergyKilocalories = watchResult.activeCalories > 0
            ? watchResult.activeCalories
            : nil
        strengthMuscleGroups = nil
        strengthExerciseCount = nil
        source = "Apple Watch"
    }

    init(wearableRecord: WearableWorkoutRecord) {
        id = UUID(uuidString: wearableRecord.id) ?? UUID()
        title = "\(wearableRecord.kind.title) completed"

        switch wearableRecord.kind {
        case .running:
            activity = .running
        case .walking:
            activity = .walking
        case .strength:
            activity = .strength
        case .mobility:
            activity = .yoga
        case .recovery, .custom:
            activity = .other
        }

        startDate = wearableRecord.startedAt
        endDate = wearableRecord.endedAt ??
            wearableRecord.startedAt.addingTimeInterval(
                wearableRecord.duration
            )
        duration = wearableRecord.duration
        distanceMeters = wearableRecord.distanceMeters
        activeEnergyKilocalories =
            wearableRecord.activeEnergyKilocalories
        strengthMuscleGroups = nil
        strengthExerciseCount = nil
        source = wearableRecord.provider.title
    }

    var summaryText: String {
        let minutes = max(Int((duration / 60).rounded()), 0)
        let time = minutes >= 60
            ? "\(minutes / 60)h \(minutes % 60)m"
            : "\(minutes) min"

        if let distanceMeters, distanceMeters > 0 {
            return String(format: "%.2f km · %@", distanceMeters / 1_000, time)
        }

        return time
    }
}


struct SocialFollowRecord: Codable, Hashable {
    let followerID: UUID
    let followingID: UUID
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followingID = "following_id"
        case createdAt = "created_at"
    }
}

struct SocialFollowInsert: Encodable {
    let followerID: UUID
    let followingID: UUID

    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followingID = "following_id"
    }
}
