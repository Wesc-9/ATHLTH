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
    let profileVisibility: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case bio
        case avatarURL = "avatar_url"
        case profileVisibility = "profile_visibility"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var resolvedName: String {
        let clean = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !clean.isEmpty { return clean }
        if let username, !username.isEmpty { return "@\(username)" }
        return ATHLTHLocalization.string( "ATHLTH Athlete")
    }

    var usernameLabel: String {
        guard let username, !username.isEmpty else { return "" }
        return "@\(username)"
    }

    var isPrivateProfile: Bool {
        profileVisibility == "private"
    }

    var isPublicProfile: Bool {
        profileVisibility == nil || profileVisibility == "public"
    }
}

struct SocialFollowOverview: Hashable {
    let followerCount: Int
    let followingCount: Int
    let followers: [SocialProfileCard]
    let following: [SocialProfileCard]

    static let empty = SocialFollowOverview(
        followerCount: 0,
        followingCount: 0,
        followers: [],
        following: []
    )
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
    var gearVisibility: String
    var runningPRsVisibility: String
    var strengthPRsVisibility: String
    var shareTrainingPresence: Bool
    var showOnlineStatus: Bool
    var shareLiveWorkoutLocation: Bool
    var shareLiveWorkoutHeartRate: Bool
    var liveLocationVisibility: String
    var sharePerformanceStats: Bool
    var shareTrophyCabinet: Bool
    var shareGoals: Bool
    var shareGear: Bool
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
        case gearVisibility = "gear_visibility"
        case runningPRsVisibility = "running_prs_visibility"
        case strengthPRsVisibility = "strength_prs_visibility"
        case shareTrainingPresence = "share_training_presence"
        case showOnlineStatus = "show_online_status"
        case shareLiveWorkoutLocation = "share_live_workout_location"
        case shareLiveWorkoutHeartRate = "share_live_workout_heart_rate"
        case liveLocationVisibility = "live_location_visibility"
        case sharePerformanceStats = "share_performance_stats"
        case shareTrophyCabinet = "share_trophy_cabinet"
        case shareGoals = "share_goals"
        case shareGear = "share_gear"
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
            profileVisibility: "public",
            discoverable: true,
            allowFriendRequests: true,
            allowDirectMessages: "requests",
            trainingFocusVisibility: "private",
            trainingPresenceVisibility: "private",
            performanceStatsVisibility: "private",
            trophyCabinetVisibility: "private",
            recentActivityVisibility: "private",
            goalsVisibility: "private",
            gearVisibility: "private",
            runningPRsVisibility: "private",
            strengthPRsVisibility: "private",
            shareTrainingPresence: false,
            showOnlineStatus: false,
            shareLiveWorkoutLocation: false,
            shareLiveWorkoutHeartRate: false,
            liveLocationVisibility: "followers",
            sharePerformanceStats: false,
            shareTrophyCabinet: false,
            shareGoals: false,
            shareGear: false,
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

struct SocialProfileGoalRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let userID: UUID
    let title: String
    let category: String
    let status: String
    let progress: Double
    let isPrimary: Bool
    let deadline: Date?
    let visibility: String
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case category
        case status
        case progress
        case isPrimary = "is_primary"
        case deadline
        case visibility
        case updatedAt = "updated_at"
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
    case heart

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .fire: return "🔥"
        case .strong: return "💪"
        case .clap: return "👏"
        case .heart: return "❤️"
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

struct SocialActivityCommentRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let activityID: UUID
    let userID: UUID
    let body: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityID = "activity_id"
        case userID = "user_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SocialUserMuteRecord: Codable, Hashable {
    let muterID: UUID
    let mutedID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case muterID = "muter_id"
        case mutedID = "muted_id"
        case createdAt = "created_at"
    }
}

struct SocialFeedItem: Identifiable, Hashable {
    var id: UUID { activity.id }

    let activity: SocialActivityRecord
    let actor: SocialProfileCard
    let reactions: [SocialActivityReactionRecord]
    let comments: [SocialActivityCommentRecord]
    let trainingPartners: [SocialWorkoutParticipantRecord]

    init(
        activity: SocialActivityRecord,
        actor: SocialProfileCard,
        reactions: [SocialActivityReactionRecord],
        comments: [SocialActivityCommentRecord] = [],
        trainingPartners: [SocialWorkoutParticipantRecord] = []
    ) {
        self.activity = activity
        self.actor = actor
        self.reactions = reactions
        self.comments = comments
        self.trainingPartners = trainingPartners
    }
}

struct SocialInboxEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let recipientID: UUID
    let actorID: UUID?
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
        case actorID = "actor_id"
        case kind
        case title
        case message
        case entityType = "entity_type"
        case entityID = "entity_id"
        case createdAt = "created_at"
        case readAt = "read_at"
        case pushNotifiedAt = "push_notified_at"
    }

    var localizedTitle: String {
        guard ATHLTHLocalization.isNorwegian else {
            return title
        }

        switch kind.lowercased() {
        case "friend_request",
             "follow_request":
            return "Ny følgeforespørsel"

        case "friend_accepted",
             "follow_accepted":
            return "Følgeforespørsel godkjent"

        case "challenge_invite":
            return "Ny challenge"

        case "challenge_result":
            return "Nytt challenge-resultat"

        case "challenge_accepted":
            return "Challenge godtatt"

        case "challenge_declined":
            return "Challenge avslått"

        case "challenge_withdrawn":
            return "Challenge trukket tilbake"

        case "reaction":
            return "Ny reaksjon"

        case "workout_invite":
            return "Tren sammen"

        case "workout_invite_accepted":
            return title == "Workout starting"
                ? "Økten starter"
                : "Treningspartner ble med"

        case "train_together_request":
            return "Ny Train Together-forespørsel"

        case "train_together_request_accepted":
            return "Du skal være med"

        case "train_together_request_declined":
            return "Train Together-forespørsel avslått"

        case "train_together_cancelled":
            return "Train Together-økt avlyst"

        case "message_request":
            let prefix = "Message request from "
            if title.hasPrefix(prefix) {
                return "Meldingsforespørsel fra " +
                    String(title.dropFirst(prefix.count))
            }
            return "Meldingsforespørsel"

        case "message_request_accepted":
            return "Meldingsforespørsel godtatt"

        case "mention":
            return "Du ble nevnt"

        case "group_update":
            let suffix = " update"
            if title.hasSuffix(suffix) {
                return "Oppdatering · " +
                    String(title.dropLast(suffix.count))
            }
            return title

        case "group_event":
            let newPrefix = "New event in "
            if title.hasPrefix(newPrefix) {
                return "Nytt event i " +
                    String(title.dropFirst(newPrefix.count))
            }

            switch title {
            case "Event cancelled":
                return "Event avlyst"
            case "Event updated":
                return "Event oppdatert"
            case "You have a spot":
                return "Du har fått plass"
            default:
                return title
            }

        case "group_challenge":
            let newPrefix = "New challenge in "
            if title.hasPrefix(newPrefix) {
                return "Ny challenge i " +
                    String(title.dropFirst(newPrefix.count))
            }

            switch title {
            case "Challenge cancelled":
                return "Challenge avlyst"
            case "Challenge updated":
                return "Challenge oppdatert"
            default:
                return title
            }

        case "group_invite":
            return "Gruppeinvitasjon"

        case "group_join_request":
            return "Ny forespørsel om medlemskap"

        case "group_join_approved":
            let prefix = "You joined "
            if title.hasPrefix(prefix) {
                return "Du ble med i " +
                    String(title.dropFirst(prefix.count))
            }
            return title

        default:
            return title
        }
    }

    var localizedMessage: String {
        guard ATHLTHLocalization.isNorwegian else {
            return message
        }

        switch kind.lowercased() {
        case "friend_request",
             "follow_request":
            return replacingSuffix(
                in: message,
                english:
                    " wants to follow you on ATHLTH.",
                norwegian:
                    " vil følge deg på ATHLTH."
            )

        case "friend_accepted",
             "follow_accepted":
            return replacingSuffix(
                in: message,
                english:
                    " accepted your follow request.",
                norwegian:
                    " godkjente følgeforespørselen din."
            )

        case "challenge_invite":
            return message.replacingOccurrences(
                of: " challenged you: ",
                with: " utfordret deg: "
            )

        case "challenge_result":
            return localizedChallengeResultMessage

        case "challenge_accepted":
            return message.replacingOccurrences(
                of: " accepted ",
                with: " godtok "
            )

        case "challenge_declined":
            return message.replacingOccurrences(
                of: " declined ",
                with: " avslo "
            )

        case "challenge_withdrawn":
            return message.replacingOccurrences(
                of: " withdrew ",
                with: " trakk tilbake "
            )

        case "reaction":
            return replacingSuffix(
                in: message,
                english:
                    " reacted to your ATHLTH activity.",
                norwegian:
                    " reagerte på ATHLTH-aktiviteten din."
            )

        case "workout_invite":
            return message.replacingOccurrences(
                of:
                    " invited you to train together: ",
                with:
                    " inviterte deg til å trene sammen: "
            )

        case "workout_invite_accepted":
            if title == "Workout starting" {
                return "Tren sammen-økten din starter nå."
            }

            return message.replacingOccurrences(
                of: " accepted your invite for ",
                with:
                    " godtok invitasjonen din til "
            )

        case "train_together_request":
            return message
                .replacingOccurrences(
                    of: " wants to join ",
                    with: " ønsker å bli med på "
                )

        case "train_together_request_accepted":
            return message
                .replacingOccurrences(
                    of: " accepted your request for ",
                    with: " godkjente forespørselen din til "
                )

        case "train_together_request_declined":
            return message
                .replacingOccurrences(
                    of: " declined your request for ",
                    with: " avslo forespørselen din til "
                )

        case "train_together_cancelled":
            return message
                .replacingOccurrences(
                    of: " cancelled ",
                    with: " avlyste "
                )

        case "message",
             "message_request":
            return message == "Shared something with you"
                ? "Delte noe med deg"
                : message

        case "message_request_accepted":
            return replacingSuffix(
                in: message,
                english:
                    " accepted your message request.",
                norwegian:
                    " godtok meldingsforespørselen din."
            )

        case "mention":
            return message
                .replacingOccurrences(
                    of:
                        " mentioned you in a message.",
                    with:
                        " nevnte deg i en melding."
                )
                .replacingOccurrences(
                    of: " mentioned you in ",
                    with: " nevnte deg i "
                )

        case "group_message",
             "group_update":
            // Group message/announcement bodies are user-authored.
            return message

        case "group_event":
            let important =
                replacingSuffix(
                    in: message,
                    english:
                        " has important changes.",
                    norwegian:
                        " har viktige endringer."
                )

            let prefix = "A spot opened up for "
            let suffix = ". You are now going."
            if message.hasPrefix(prefix),
               message.hasSuffix(suffix) {
                let start =
                    message.index(
                        message.startIndex,
                        offsetBy:
                            prefix.count
                    )
                let end =
                    message.index(
                        message.endIndex,
                        offsetBy:
                            -suffix.count
                    )
                let eventTitle =
                    String(
                        message[start..<end]
                    )
                return
                    "Det ble ledig plass på \(eventTitle). Du er nå påmeldt."
            }

            return important

        case "group_challenge":
            return replacingSuffix(
                in: message,
                english:
                    " has important changes.",
                norwegian:
                    " har viktige endringer."
            )

        case "group_invite":
            let prefix = "You were invited to "
            if message.hasPrefix(prefix) {
                return "Du ble invitert til " +
                    String(
                        message.dropFirst(
                            prefix.count
                        )
                    )
            }
            return message

        case "group_join_request":
            return replacingSuffix(
                in: message,
                english:
                    " has a new membership request.",
                norwegian:
                    " har en ny forespørsel om medlemskap."
            )

        case "group_join_approved":
            return message ==
                "Your membership request was approved."
                ? "Forespørselen om medlemskap ble godkjent."
                : message

        default:
            return message
        }
    }

    private var localizedChallengeResultMessage:
        String {
        guard
            let postedRange =
                message.range(
                    of: " posted "
                ),
            let inRange =
                message.range(
                    of: " in ",
                    options: .backwards,
                    range:
                        postedRange.upperBound..<message.endIndex
                )
        else {
            return message
        }

        let athlete =
            message[
                message.startIndex..<postedRange.lowerBound
            ]
        let result =
            message[
                postedRange.upperBound..<inRange.lowerBound
            ]
        let challenge =
            message[
                inRange.upperBound..<message.endIndex
            ]

        return
            "\(athlete) registrerte \(result) i \(challenge)"
    }

    private func replacingSuffix(
        in value: String,
        english: String,
        norwegian: String
    ) -> String {
        guard value.hasSuffix(english)
        else {
            return value
        }

        return
            String(
                value.dropLast(
                    english.count
                )
            ) +
            norwegian
    }
}

struct SocialFriendProfile: Hashable {
    let card: SocialProfileCard
    let trainingFocus: TrainingFocus?
    let presence: SocialPresenceRecord?
    let performance: SocialPerformanceStats?
    let trophies: [SocialTrophyShowcaseItem]
    let goals: [SocialProfileGoalRecord]
    let gear: [ProfileGearItem]
    let workoutMedia: [WorkoutMediaRecord]
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
    let readyAt: Date? = nil
    let captureDevice: String? = nil
    let workoutStartedAt: Date? = nil
    let workoutFinishedAt: Date? = nil
    let launchFailedAt: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case challengeID = "challenge_id"
        case userID = "user_id"
        case state
        case invitedBy = "invited_by"
        case invitedAt = "invited_at"
        case respondedAt = "responded_at"
        case readyAt = "ready_at"
        case captureDevice = "capture_device"
        case workoutStartedAt = "workout_started_at"
        case workoutFinishedAt = "workout_finished_at"
        case launchFailedAt = "launch_failed_at"
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

enum SocialWorkoutParticipationMode:
    String,
    Codable,
    Hashable,
    CaseIterable,
    Identifiable
{
    case physical
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .physical:
            return ATHLTHLocalization.choose(
                english: "Together in person",
                norwegian: "Sammen fysisk"
            )
        case .remote:
            return ATHLTHLocalization.choose(
                english: "Same workout · apart",
                norwegian: "Samme økt · hver for seg"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .physical:
            return ATHLTHLocalization.choose(
                english:
                    "Meet up and use a shared start when everyone is ready.",
                norwegian:
                    "Møt hverandre og bruk felles start når alle er klare."
            )
        case .remote:
            return ATHLTHLocalization.choose(
                english:
                    "Train from different places with chat and live partner progress.",
                norwegian:
                    "Tren fra ulike steder med chat og live fremdrift fra partnerne."
            )
        }
    }

    var systemImage: String {
        switch self {
        case .physical:
            return "person.2.fill"
        case .remote:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

struct SocialWorkoutInvitePayload: Codable, Hashable {
    var version: Int = 1
    var workout: PlannedSession
    var route: TrainingRoute? = nil
    var strengthTrackingMode: StrengthTrackingMode? = nil
    var strengthAdvancedConfiguration:
        StrengthAdvancedConfiguration? = nil
    var routeAlerts:
        WatchRouteAlertConfiguration? = nil

    // Optional for backwards compatibility with workout invites created
    // before social workout modes existed.
    var participationMode:
        SocialWorkoutParticipationMode? = nil
    var maxParticipants: Int? = nil

    var resolvedParticipationMode:
        SocialWorkoutParticipationMode {
        participationMode ?? .physical
    }

    var resolvedMaxParticipants: Int {
        min(
            max(
                maxParticipants ?? 2,
                2
            ),
            16
        )
    }

    var createdAt: Date = Date()

    /// The invited athlete chooses their own capture device, gear and music.
    /// The payload only preserves the workout itself and guidance that changes
    /// how the workout is performed.
    func recipientCopy() -> PlannedSession {
        var copy = workout
        copy.sharedSourceOwnerID = nil
        copy.sharedSourceSessionID = workout.id
        copy.gearIDs = []
        copy.spotifyPlaylist = nil
        copy.spotifyAutoplayOnStart = false
        copy.scheduledStart = nil
        return copy
    }
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
    var invitePayload: SocialWorkoutInvitePayload? = nil
    var coordinatedStartAt: Date? = nil

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
        case invitePayload = "invite_payload"
        case coordinatedStartAt = "coordinated_start_at"
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
    var readyAt: Date? = nil
    var captureDevice: String? = nil
    var workoutStartedAt: Date? = nil
    var workoutFinishedAt: Date? = nil
    var launchFailedAt: Date? = nil

    var isReady: Bool {
        readyAt != nil
    }

    var isTraining: Bool {
        workoutStartedAt != nil &&
        workoutFinishedAt == nil
    }

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
    let isIndoor: Bool?
    let strengthMuscleGroups: [String]?
    let strengthExerciseCount: Int?
    let strengthTotalVolumeKilograms: Double?
    let strengthHeaviestWeightKilograms: Double?
    let strengthTotalReps: Int?
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
        isIndoor = summary.isIndoor
        strengthMuscleGroups = nil
        strengthExerciseCount = nil
        strengthTotalVolumeKilograms = nil
        strengthHeaviestWeightKilograms = nil
        strengthTotalReps = nil
        source = "Apple Health"
    }

    init(strengthWorkout: StrengthWorkoutLog) {
        id = strengthWorkout.healthMetrics.healthKitWorkoutUUID ?? strengthWorkout.id
        title = strengthWorkout.title
        activity = .strength
        startDate = strengthWorkout.startedAt
        endDate = strengthWorkout.endedAt ?? strengthWorkout.startedAt
        duration = max(
            max(
                (strengthWorkout.endedAt ?? strengthWorkout.startedAt)
                    .timeIntervalSince(strengthWorkout.startedAt),
                0
            ),
            strengthWorkout.healthMetrics.duration ?? 0
        )
        distanceMeters = nil
        activeEnergyKilocalories = strengthWorkout.healthMetrics.activeCalories
        isIndoor = true

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

        let completedSets = performedExercises
            .flatMap(\.sets)
            .filter { set in
                set.isCompleted ||
                set.completedReps != nil ||
                set.completedWeightKilograms != nil
            }

        let totalVolume = completedSets.reduce(0.0) {
            partial,
            set in

            guard
                let reps = set.completedReps,
                let weight =
                    set.completedWeightKilograms
            else {
                return partial
            }

            return partial +
                Double(reps) * weight
        }

        let heaviest = completedSets
            .compactMap(
                \.completedWeightKilograms
            )
            .max()

        let totalReps = completedSets
            .compactMap(\.completedReps)
            .reduce(0, +)

        strengthTotalVolumeKilograms =
            totalVolume > 0
                ? totalVolume
                : nil
        strengthHeaviestWeightKilograms =
            heaviest
        strengthTotalReps =
            totalReps > 0
                ? totalReps
                : nil

        var muscleGroups: [String] = []
        let recordedMuscles =
            performedExercises.flatMap {
                $0.exercise.primaryMuscles +
                (
                    $0.exercise
                        .secondaryMuscles ??
                    []
                )
            }

        for rawGroup in recordedMuscles {
            let group =
                rawGroup.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            guard !group.isEmpty else {
                continue
            }

            if !muscleGroups.contains(
                where: {
                    $0.caseInsensitiveCompare(
                        group
                    ) ==
                    .orderedSame
                }
            ) {
                muscleGroups.append(group)
            }
        }

        if muscleGroups.isEmpty {
            for exercise in performedExercises {
                for region in
                    StrengthMuscleResolver
                        .fallbackRegions(
                            forExerciseName:
                                exercise
                                    .exercise
                                    .name
                        ) {
                    let value = region.title

                    if !muscleGroups
                        .contains(
                            where: {
                                $0.caseInsensitiveCompare(
                                    value
                                ) ==
                                    .orderedSame
                            }
                        ) {
                        muscleGroups.append(
                            value
                        )
                    }
                }
            }
        }

        strengthMuscleGroups =
            muscleGroups.isEmpty
                ? nil
                : muscleGroups
        source = "ATHLTH"
    }

    init(phoneWorkout: PhoneWorkout) {
        id = phoneWorkout.healthID ?? phoneWorkout.id
        title = phoneWorkout.title
        activity =
            phoneWorkout.walking
                ? .walking
                : .running
        startDate = phoneWorkout.start
        endDate =
            phoneWorkout.end ??
            phoneWorkout.lastCheckpoint

        let recordedDuration =
            max(
                phoneWorkout.accumulatedSeconds,
                0
            )
        let elapsedFallback =
            max(
                endDate.timeIntervalSince(
                    startDate
                ),
                0
            )

        duration =
            recordedDuration > 0
                ? recordedDuration
                : elapsedFallback
        distanceMeters =
            phoneWorkout.distanceMeters > 0
                ? phoneWorkout.distanceMeters
                : nil
        activeEnergyKilocalories = nil
        isIndoor = false
        strengthMuscleGroups = nil
        strengthExerciseCount = nil
        strengthTotalVolumeKilograms = nil
        strengthHeaviestWeightKilograms = nil
        strengthTotalReps = nil
        source = "iPhone"
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

        switch watchResult.kind {
        case .running,
             .walking,
             .cycling:
            isIndoor = false
        case .strength,
             .functional,
             .hiit,
             .rowing,
             .stairClimbing,
             .yoga:
            isIndoor = true
        case .other:
            isIndoor = nil
        }

        strengthMuscleGroups = nil
        strengthExerciseCount = nil
        strengthTotalVolumeKilograms = nil
        strengthHeaviestWeightKilograms = nil
        strengthTotalReps = nil
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

        switch wearableRecord.kind {
        case .running,
             .walking:
            isIndoor = false
        case .strength,
             .mobility:
            isIndoor = true
        case .recovery,
             .custom:
            isIndoor = nil
        }

        strengthMuscleGroups = nil
        strengthExerciseCount = nil
        strengthTotalVolumeKilograms = nil
        strengthHeaviestWeightKilograms = nil
        strengthTotalReps = nil
        source = wearableRecord.provider.title
    }

    var allowsTrainingPlaceCheckIn: Bool {
        activity.allowsTrainingPlaceCheckIn(
            isIndoor: isIndoor
        )
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


struct WorkoutMediaRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let userID: UUID
    let workoutID: UUID
    let imageURL: String
    let storagePath: String
    let caption: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case workoutID = "workout_id"
        case imageURL = "image_url"
        case storagePath = "storage_path"
        case caption
        case createdAt = "created_at"
    }
}

struct WorkoutMediaInsert: Encodable {
    let id: UUID
    let userID: UUID
    let workoutID: UUID
    let imageURL: String
    let storagePath: String
    let caption: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case workoutID = "workout_id"
        case imageURL = "image_url"
        case storagePath = "storage_path"
        case caption
        case createdAt = "created_at"
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

// Keep the controls displayed in Privacy & Visibility aligned with the
// audience fields enforced by the server. Never widen a friends-only section.
extension SocialPrivacySettings {
    mutating func normalizeSectionVisibility() {
        let audience = profileVisibility
        func scope(_ enabled: Bool, _ current: String) -> String {
            PrivacyVisibilityRules.scope(enabled: enabled, current: current, profile: audience)
        }
        trainingPresenceVisibility = scope(shareTrainingPresence, trainingPresenceVisibility)
        performanceStatsVisibility = scope(sharePerformanceStats || shareWorkoutTotals, performanceStatsVisibility)
        trophyCabinetVisibility = scope(shareTrophyCabinet, trophyCabinetVisibility)
        recentActivityVisibility = scope(shareRecentActivity, recentActivityVisibility)
        goalsVisibility = scope(shareGoals, goalsVisibility)
        gearVisibility = scope(shareGear, gearVisibility)
        runningPRsVisibility = scope(shareRunningPRs, runningPRsVisibility)
        strengthPRsVisibility = scope(shareStrengthPRs, strengthPRsVisibility)
        // Training focus has its own audience picker, not a sharing toggle.
        if profileVisibility == "private" { trainingFocusVisibility = "private" }
        else if profileVisibility == "friends" && trainingFocusVisibility == "public" {
            trainingFocusVisibility = "friends"
        }
    }
}
