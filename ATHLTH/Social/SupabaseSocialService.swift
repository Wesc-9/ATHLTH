import Foundation
import Supabase

final class SupabaseSocialService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func searchProfiles(_ query: String) async throws -> [SocialProfileCard] {
        let clean = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()

        guard !clean.isEmpty else { return [] }

        let rows: [SocialProfileCard] = try await client
            .from("social_profile_cards")
            .select()
            .ilike("username", pattern: "%\(clean)%")
            .limit(30)
            .execute()
            .value

        guard let currentUserID else { return rows }
        return rows.filter { $0.userID != currentUserID }
    }

    func loadVisibleProfileCards() async throws -> [SocialProfileCard] {
        try await client
            .from("social_profile_cards")
            .select()
            .execute()
            .value
    }

    func loadFriendships() async throws -> [SocialFriendshipRecord] {
        try await client
            .from("friendships")
            .select()
            .execute()
            .value
    }

    func loadFriendRequests() async throws -> [SocialFriendRequestRecord] {
        try await client
            .from("friend_requests")
            .select()
            .execute()
            .value
    }

    func sendFriendRequest(to recipientID: UUID, message: String? = nil) async throws {
        guard let senderID = currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        let payload = FriendRequestInsert(
            senderID: senderID,
            recipientID: recipientID,
            message: message?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        try await client
            .from("friend_requests")
            .insert(payload)
            .execute()
    }

    func respondToFriendRequest(
        requestID: UUID,
        status: SocialFriendRequestState
    ) async throws {
        guard status == .accepted || status == .declined || status == .cancelled else {
            throw SocialServiceError.invalidFriendRequestState
        }

        try await client
            .from("friend_requests")
            .update(["status": status.rawValue])
            .eq("id", value: requestID)
            .execute()
    }

    func removeFriendship(_ friendshipID: UUID) async throws {
        try await client
            .from("friendships")
            .delete()
            .eq("id", value: friendshipID)
            .execute()
    }

    func loadPrivacySettings() async throws -> SocialPrivacySettings {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        return try await client
            .from("profile_social_settings")
            .select()
            .eq("user_id", value: currentUserID)
            .single()
            .execute()
            .value
    }

    func updatePrivacySettings(_ settings: SocialPrivacySettings) async throws {
        guard let currentUserID, currentUserID == settings.userID else {
            throw SocialServiceError.notAuthenticated
        }

        let payload = SocialPrivacyUpdate(
            profileVisibility: settings.profileVisibility,
            discoverable: settings.discoverable,
            allowFriendRequests: settings.allowFriendRequests,
            shareTrainingPresence: settings.shareTrainingPresence,
            sharePerformanceStats: settings.sharePerformanceStats,
            shareTrophyCabinet: settings.shareTrophyCabinet,
            shareGoals: settings.shareGoals,
            shareRecentActivity: settings.shareRecentActivity,
            shareRunningPRs: settings.shareRunningPRs,
            shareStrengthPRs: settings.shareStrengthPRs,
            shareWorkoutTotals: settings.shareWorkoutTotals,
            allowChallengeInvites: settings.allowChallengeInvites
        )

        try await client
            .from("profile_social_settings")
            .update(payload)
            .eq("user_id", value: currentUserID)
            .execute()
    }

    func blockUser(_ userID: UUID) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        try await client
            .from("user_blocks")
            .insert(BlockInsert(blockerID: currentUserID, blockedID: userID))
            .execute()
    }

    func unblockUser(_ userID: UUID) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        try await client
            .from("user_blocks")
            .delete()
            .eq("blocker_id", value: currentUserID)
            .eq("blocked_id", value: userID)
            .execute()
    }

    func loadBlockedUsers() async throws -> [SocialBlockedUser] {
        let blocks: [BackendBlockRecord] = try await client
            .from("user_blocks")
            .select()
            .execute()
            .value

        let cards = try await loadVisibleProfileCards()
        let cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.userID, $0) })

        return blocks.compactMap { block in
            guard let card = cardByID[block.blockedID] else { return nil }
            return SocialBlockedUser(profile: card, blockedAt: block.createdAt)
        }
    }

    func reportUser(
        _ userID: UUID,
        reason: String,
        details: String?
    ) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        try await client
            .from("user_reports")
            .insert(
                ReportInsert(
                    reporterID: currentUserID,
                    reportedID: userID,
                    reason: reason,
                    details: details?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            .execute()
    }

    func syncPerformanceStats(_ stats: ProfilePerformanceStats) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        try await client
            .from("social_performance_stats")
            .upsert(SocialPerformanceStats(userID: currentUserID, stats: stats))
            .execute()
    }

    func syncTrophyShowcase(_ trophies: [TrophyProgressItem]) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        let items = trophies.map {
            SocialTrophyShowcaseItem(
                trophyID: $0.id,
                title: $0.title,
                stageLabel: $0.stageLabel,
                rarity: $0.displayRarity.title,
                category: $0.category.title,
                systemImage: $0.systemImage,
                unlockedAt: $0.unlockedAt
            )
        }

        try await client
            .from("social_trophy_showcases")
            .upsert(
                TrophyShowcaseWrite(
                    userID: currentUserID,
                    items: items,
                    updatedAt: Date()
                )
            )
            .execute()
    }

    func syncPresence(
        state: TrainingPresenceState,
        workoutTitle: String?,
        startedAt: Date?
    ) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        try await client
            .from("social_presence")
            .upsert(
                PresenceWrite(
                    userID: currentUserID,
                    state: state.rawValue,
                    workoutTitle: workoutTitle,
                    startedAt: startedAt,
                    updatedAt: Date()
                )
            )
            .execute()
    }

    func loadFriendProfile(_ userID: UUID) async throws -> SocialFriendProfile {
        let card: SocialProfileCard = try await client
            .from("social_profile_cards")
            .select()
            .eq("user_id", value: userID)
            .single()
            .execute()
            .value

        let presenceRows: [SocialPresenceRecord] = try await client
            .from("social_presence")
            .select()
            .eq("user_id", value: userID)
            .execute()
            .value

        let performanceRows: [SocialPerformanceStats] = try await client
            .from("social_performance_stats")
            .select()
            .eq("user_id", value: userID)
            .execute()
            .value

        let trophyRows: [SocialTrophyShowcaseRecord] = try await client
            .from("social_trophy_showcases")
            .select()
            .eq("user_id", value: userID)
            .execute()
            .value

        let activities: [SocialActivityRecord] = try await client
            .from("social_activities")
            .select()
            .eq("actor_id", value: userID)
            .order("created_at", ascending: false)
            .limit(20)
            .execute()
            .value

        let reactions: [SocialActivityReactionRecord] = try await client
            .from("social_activity_reactions")
            .select()
            .execute()
            .value

        let grouped = Dictionary(grouping: reactions, by: \.activityID)
        let feed = activities.map {
            SocialFeedItem(
                activity: $0,
                actor: card,
                reactions: grouped[$0.id] ?? []
            )
        }

        return SocialFriendProfile(
            card: card,
            presence: presenceRows.first,
            performance: performanceRows.first,
            trophies: trophyRows.first?.items ?? [],
            recentActivities: feed
        )
    }

    func loadFeed() async throws -> [SocialFeedItem] {
        let activities: [SocialActivityRecord] = try await client
            .from("social_activities")
            .select()
            .order("created_at", ascending: false)
            .limit(60)
            .execute()
            .value

        let cards = try await loadVisibleProfileCards()
        let reactions: [SocialActivityReactionRecord] = try await client
            .from("social_activity_reactions")
            .select()
            .execute()
            .value

        let cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.userID, $0) })
        let reactionsByActivity = Dictionary(grouping: reactions, by: \.activityID)

        return activities.compactMap { activity in
            guard let actor = cardByID[activity.actorID] else { return nil }

            return SocialFeedItem(
                activity: activity,
                actor: actor,
                reactions: reactionsByActivity[activity.id] ?? []
            )
        }
    }

    func setReaction(
        activityID: UUID,
        reaction: SocialActivityReaction?
    ) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        if let reaction {
            try await client
                .from("social_activity_reactions")
                .upsert(
                    ReactionWrite(
                        activityID: activityID,
                        userID: currentUserID,
                        reaction: reaction.rawValue
                    )
                )
                .execute()
        } else {
            try await client
                .from("social_activity_reactions")
                .delete()
                .eq("activity_id", value: activityID)
                .eq("user_id", value: currentUserID)
                .execute()
        }
    }

    func publishActivity(
        eventKey: String,
        kind: String,
        title: String,
        subtitle: String?,
        metadata: [String: String] = [:],
        visibility: ProfileVisibility = .friends
    ) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        let existing: [SocialActivityRecord] = try await client
            .from("social_activities")
            .select()
            .eq("actor_id", value: currentUserID)
            .eq("event_key", value: eventKey)
            .execute()
            .value

        guard existing.isEmpty else { return }

        try await client
            .from("social_activities")
            .insert(
                ActivityInsert(
                    actorID: currentUserID,
                    kind: kind,
                    title: title,
                    subtitle: subtitle,
                    metadata: metadata,
                    visibility: visibility.rawValue,
                    eventKey: eventKey
                )
            )
            .execute()
    }

    func loadInboxEvents() async throws -> [SocialInboxEvent] {
        try await client
            .from("social_inbox_events")
            .select()
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func markInboxEventRead(_ eventID: UUID) async throws {
        try await client
            .from("social_inbox_events")
            .update(["read_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: eventID)
            .execute()
    }

    func loadRemoteChallenges() async throws -> [ATHLTHChallenge] {
        let backendChallenges: [BackendSocialChallenge] = try await client
            .from("social_challenges")
            .select()
            .execute()
            .value

        guard !backendChallenges.isEmpty else { return [] }

        let backendParticipants: [BackendChallengeParticipant] = try await client
            .from("social_challenge_participants")
            .select()
            .execute()
            .value

        let backendAttempts: [BackendChallengeAttempt] = try await client
            .from("social_challenge_attempts")
            .select()
            .execute()
            .value

        let backendCheckIns: [BackendChallengeCheckIn] = try await client
            .from("social_challenge_checkins")
            .select()
            .execute()
            .value

        let cards = try await loadVisibleProfileCards()
        let cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.userID, $0) })

        return backendChallenges.compactMap { backend in
            guard let sport = ATHLTHChallengeSport(rawValue: backend.sport),
                  let status = ATHLTHChallengeStatus(rawValue: backend.status),
                  let visibility = ProfileVisibility(rawValue: backend.visibility)
            else {
                return nil
            }

            let participants = backendParticipants
                .filter { $0.challengeID == backend.id }
                .compactMap { row -> ChallengeParticipant? in
                    guard let state = ChallengeParticipantState(rawValue: row.state) else {
                        return nil
                    }

                    let card = cardByID[row.userID]
                    return ChallengeParticipant(
                        id: row.id,
                        userID: row.userID,
                        username: card?.username,
                        displayName: card?.resolvedName ?? "ATHLTH Athlete",
                        state: state,
                        invitedAt: row.invitedAt,
                        respondedAt: row.respondedAt
                    )
                }

            let attempts = backendAttempts
                .filter { $0.challengeID == backend.id }
                .compactMap { row -> ChallengeAttempt? in
                    guard let verification = ChallengeAttemptVerification(rawValue: row.verification) else {
                        return nil
                    }

                    return ChallengeAttempt(
                        id: row.id,
                        challengeID: row.challengeID,
                        participantID: row.participantID,
                        userID: row.userID,
                        participantName: row.participantName,
                        submittedAt: row.submittedAt,
                        startedAt: row.startedAt,
                        endedAt: row.endedAt,
                        verification: verification,
                        sourceWorkoutID: row.sourceWorkoutID,
                        durationSeconds: row.durationSeconds,
                        distanceMeters: row.distanceMeters,
                        weightKilograms: row.weightKilograms,
                        reps: row.reps,
                        volumeKilograms: row.volumeKilograms,
                        routeMatchPercent: row.routeMatchPercent,
                        score: row.score,
                        detail: row.detail,
                        manualNote: row.manualNote,
                        isEligible: row.isEligible,
                        ineligibilityReason: row.ineligibilityReason
                    )
                }

            let checkIns = backendCheckIns
                .filter { $0.challengeID == backend.id }
                .map {
                    ChallengeMeetupCheckIn(
                        id: $0.id,
                        participantID: $0.participantID,
                        checkedInAt: $0.checkedInAt,
                        distanceFromMeetupMeters: $0.distanceFromMeetupMeters,
                        verifiedNearMeetup: $0.verifiedNearMeetup
                    )
                }

            return ATHLTHChallenge(
                id: backend.id,
                creatorID: backend.creatorID,
                title: backend.title,
                sport: sport,
                status: status,
                createdAt: backend.createdAt,
                participants: participants,
                rules: backend.rules,
                attempts: attempts,
                checkIns: checkIns,
                visibility: visibility,
                rulesLockedAt: backend.rulesLockedAt
            )
        }
    }

    func syncChallenge(_ challenge: ATHLTHChallenge) async throws {
        guard let currentUserID else {
            throw SocialServiceError.notAuthenticated
        }

        if challenge.creatorID == currentUserID {
            let challengeWrite = ChallengeWrite(
                id: challenge.id,
                creatorID: challenge.creatorID,
                title: challenge.title,
                sport: challenge.sport.rawValue,
                status: challenge.status.rawValue,
                rules: challenge.rules,
                visibility: challenge.visibility.rawValue,
                startsAt: challenge.rules.startsAt,
                endsAt: challenge.rules.endsAt,
                rulesLockedAt: challenge.rulesLockedAt,
                createdAt: challenge.createdAt,
                updatedAt: Date()
            )

            try await client
                .from("social_challenges")
                .upsert(challengeWrite)
                .execute()

            let participantWrites = challenge.participants.compactMap { participant -> ChallengeParticipantWrite? in
                guard let userID = participant.userID else { return nil }

                return ChallengeParticipantWrite(
                    id: participant.id,
                    challengeID: challenge.id,
                    userID: userID,
                    state: participant.state.rawValue,
                    invitedBy: challenge.creatorID,
                    invitedAt: participant.invitedAt,
                    respondedAt: participant.respondedAt
                )
            }

            if !participantWrites.isEmpty {
                try await client
                    .from("social_challenge_participants")
                    .upsert(participantWrites)
                    .execute()
            }
        } else if let mine = challenge.participants.first(where: { $0.userID == currentUserID }) {
            try await client
                .from("social_challenge_participants")
                .update(["state": mine.state.rawValue])
                .eq("id", value: mine.id)
                .execute()
        }

        let remoteAttempts: [BackendChallengeAttempt] = try await client
            .from("social_challenge_attempts")
            .select()
            .eq("challenge_id", value: challenge.id)
            .execute()
            .value

        let remoteAttemptIDs = Set(remoteAttempts.map(\.id))
        let missingAttempts = challenge.attempts
            .filter { $0.userID == currentUserID && !remoteAttemptIDs.contains($0.id) }
            .map {
                ChallengeAttemptWrite(
                    id: $0.id,
                    challengeID: $0.challengeID,
                    participantID: $0.participantID,
                    userID: currentUserID,
                    participantName: $0.participantName,
                    verification: $0.verification.rawValue,
                    sourceWorkoutID: $0.sourceWorkoutID,
                    submittedAt: $0.submittedAt,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    durationSeconds: $0.durationSeconds,
                    distanceMeters: $0.distanceMeters,
                    weightKilograms: $0.weightKilograms,
                    reps: $0.reps,
                    volumeKilograms: $0.volumeKilograms,
                    routeMatchPercent: $0.routeMatchPercent,
                    score: $0.score,
                    detail: $0.detail,
                    manualNote: $0.manualNote,
                    isEligible: $0.isEligible,
                    ineligibilityReason: $0.ineligibilityReason
                )
            }

        if !missingAttempts.isEmpty {
            try await client
                .from("social_challenge_attempts")
                .insert(missingAttempts)
                .execute()
        }

        if let myParticipant = challenge.participants.first(where: { $0.userID == currentUserID }),
           let checkIn = challenge.checkIns.first(where: { $0.participantID == myParticipant.id }) {
            try await client
                .from("social_challenge_checkins")
                .upsert(
                    ChallengeCheckInWrite(
                        id: checkIn.id,
                        challengeID: challenge.id,
                        participantID: checkIn.participantID,
                        userID: currentUserID,
                        checkedInAt: checkIn.checkedInAt,
                        distanceFromMeetupMeters: checkIn.distanceFromMeetupMeters,
                        verifiedNearMeetup: checkIn.verifiedNearMeetup
                    )
                )
                .execute()
        }
    }
}

enum SocialServiceError: LocalizedError {
    case notAuthenticated
    case invalidFriendRequestState

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to use ATHLTH social features."
        case .invalidFriendRequestState:
            return "That friend request action is not available."
        }
    }
}

private struct FriendRequestInsert: Encodable {
    let senderID: UUID
    let recipientID: UUID
    let message: String?

    enum CodingKeys: String, CodingKey {
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case message
    }
}

private struct SocialPrivacyUpdate: Encodable {
    let profileVisibility: String
    let discoverable: Bool
    let allowFriendRequests: Bool
    let shareTrainingPresence: Bool
    let sharePerformanceStats: Bool
    let shareTrophyCabinet: Bool
    let shareGoals: Bool
    let shareRecentActivity: Bool
    let shareRunningPRs: Bool
    let shareStrengthPRs: Bool
    let shareWorkoutTotals: Bool
    let allowChallengeInvites: String

    enum CodingKeys: String, CodingKey {
        case profileVisibility = "profile_visibility"
        case discoverable
        case allowFriendRequests = "allow_friend_requests"
        case shareTrainingPresence = "share_training_presence"
        case sharePerformanceStats = "share_performance_stats"
        case shareTrophyCabinet = "share_trophy_cabinet"
        case shareGoals = "share_goals"
        case shareRecentActivity = "share_recent_activity"
        case shareRunningPRs = "share_running_prs"
        case shareStrengthPRs = "share_strength_prs"
        case shareWorkoutTotals = "share_workout_totals"
        case allowChallengeInvites = "allow_challenge_invites"
    }
}

private struct BlockInsert: Encodable {
    let blockerID: UUID
    let blockedID: UUID

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
    }
}

private struct ReportInsert: Encodable {
    let reporterID: UUID
    let reportedID: UUID
    let reason: String
    let details: String?

    enum CodingKeys: String, CodingKey {
        case reporterID = "reporter_id"
        case reportedID = "reported_id"
        case reason
        case details
    }
}

private struct TrophyShowcaseWrite: Encodable {
    let userID: UUID
    let items: [SocialTrophyShowcaseItem]
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case items
        case updatedAt = "updated_at"
    }
}

private struct PresenceWrite: Encodable {
    let userID: UUID
    let state: String
    let workoutTitle: String?
    let startedAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case state
        case workoutTitle = "workout_title"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

private struct ReactionWrite: Encodable {
    let activityID: UUID
    let userID: UUID
    let reaction: String

    enum CodingKeys: String, CodingKey {
        case activityID = "activity_id"
        case userID = "user_id"
        case reaction
    }
}

private struct ActivityInsert: Encodable {
    let actorID: UUID
    let kind: String
    let title: String
    let subtitle: String?
    let metadata: [String: String]
    let visibility: String
    let eventKey: String

    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id"
        case kind
        case title
        case subtitle
        case metadata
        case visibility
        case eventKey = "event_key"
    }
}

private struct ChallengeWrite: Encodable {
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
    let updatedAt: Date

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

private struct ChallengeParticipantWrite: Encodable {
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

private struct ChallengeAttemptWrite: Encodable {
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

private struct ChallengeCheckInWrite: Encodable {
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
