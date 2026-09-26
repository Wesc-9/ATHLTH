import Foundation
import Supabase

@MainActor
final class CommunityGroupAdvancedStore: ObservableObject {
    @Published private(set) var hosts:
        [CommunityGroupContentHostRecord] = []
    @Published private(set) var comments:
        [CommunityGroupContentCommentRecord] = []
    @Published private(set) var participants:
        [CommunityGroupChallengeParticipantRecord] = []
    @Published private(set) var eventRSVPs:
        [CommunityGroupEventRSVPRecord] = []
    @Published private(set) var attempts:
        [CommunityGroupChallengeWorkoutRecord] = []
    @Published private(set) var latestEvent:
        CommunityGroupEventRecord?
    @Published private(set) var latestChallenge:
        CommunityGroupChallengeRecord?
    @Published var errorMessage: String?

    private let client: SupabaseClient

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.client = client
    }

    private var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func loadEvent(
        groupID: UUID,
        eventID: UUID
    ) async {
        do {
            async let eventQuery:
                [CommunityGroupEventRecord] = client
                    .from("community_group_events")
                    .select()
                    .eq("id", value: eventID)
                    .limit(1)
                    .execute()
                    .value

            async let hostsQuery:
                [CommunityGroupContentHostRecord] =
                    client
                        .from(
                            "community_group_content_hosts"
                        )
                        .select()
                        .eq(
                            "content_type",
                            value: "event"
                        )
                        .eq(
                            "content_id",
                            value: eventID
                        )
                        .execute()
                        .value

            async let commentsQuery:
                [CommunityGroupContentCommentRecord] =
                    client
                        .from(
                            "community_group_content_comments"
                        )
                        .select()
                        .eq(
                            "content_type",
                            value: "event"
                        )
                        .eq(
                            "content_id",
                            value: eventID
                        )
                        .order(
                            "created_at",
                            ascending: true
                        )
                        .execute()
                        .value

            async let rsvpQuery:
                [CommunityGroupEventRSVPRecord] =
                    client
                        .from(
                            "community_group_event_rsvps"
                        )
                        .select()
                        .eq(
                            "event_id",
                            value: eventID
                        )
                        .execute()
                        .value

            let events = try await eventQuery
            latestEvent = events.first
            hosts = try await hostsQuery
            comments = try await commentsQuery
            eventRSVPs = try await rsvpQuery
            participants = []
            attempts = []
            errorMessage = nil

            _ = groupID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadChallenge(
        groupID: UUID,
        challengeID: UUID
    ) async {
        do {
            async let challengeQuery:
                [CommunityGroupChallengeRecord] =
                    client
                        .from(
                            "community_group_challenges"
                        )
                        .select()
                        .eq(
                            "id",
                            value: challengeID
                        )
                        .limit(1)
                        .execute()
                        .value

            async let hostsQuery:
                [CommunityGroupContentHostRecord] =
                    client
                        .from(
                            "community_group_content_hosts"
                        )
                        .select()
                        .eq(
                            "content_type",
                            value: "challenge"
                        )
                        .eq(
                            "content_id",
                            value: challengeID
                        )
                        .execute()
                        .value

            async let commentsQuery:
                [CommunityGroupContentCommentRecord] =
                    client
                        .from(
                            "community_group_content_comments"
                        )
                        .select()
                        .eq(
                            "content_type",
                            value: "challenge"
                        )
                        .eq(
                            "content_id",
                            value: challengeID
                        )
                        .order(
                            "created_at",
                            ascending: true
                        )
                        .execute()
                        .value

            async let participantsQuery:
                [CommunityGroupChallengeParticipantRecord] =
                    client
                        .from(
                            "community_group_challenge_participants"
                        )
                        .select()
                        .eq(
                            "challenge_id",
                            value: challengeID
                        )
                        .execute()
                        .value

            async let attemptsQuery:
                [CommunityGroupChallengeWorkoutRecord] =
                    client
                        .from(
                            "community_group_challenge_workouts"
                        )
                        .select()
                        .eq(
                            "challenge_id",
                            value: challengeID
                        )
                        .order(
                            "created_at",
                            ascending: true
                        )
                        .execute()
                        .value

            let values = try await challengeQuery
            latestChallenge = values.first
            hosts = try await hostsQuery
            comments = try await commentsQuery
            participants = try await participantsQuery
            attempts = try await attemptsQuery
            eventRSVPs = []
            errorMessage = nil

            _ = groupID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEventRSVP(
        eventID: UUID,
        status: String
    ) async -> String? {
        do {
            let resolved: String = try await client
                .rpc(
                    "set_community_group_event_rsvp",
                    params:
                        CommunityGroupEventRSVPParams(
                            eventID: eventID,
                            status: status
                        )
                )
                .execute()
                .value

            return resolved
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func setChallengeParticipation(
        challengeID: UUID,
        join: Bool
    ) async -> String? {
        do {
            let resolved: String = try await client
                .rpc(
                    "set_community_group_challenge_participation",
                    params:
                        CommunityGroupChallengeParticipationParams(
                            challengeID:
                                challengeID,
                            join: join
                        )
                )
                .execute()
                .value

            return resolved
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func postComment(
        groupID: UUID,
        contentType: String,
        contentID: UUID,
        body: String
    ) async -> Bool {
        guard let userID = currentUserID else {
            return false
        }

        let clean = body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !clean.isEmpty else {
            return false
        }

        do {
            try await client
                .from(
                    "community_group_content_comments"
                )
                .insert(
                    CommunityGroupContentCommentInsert(
                        groupID: groupID,
                        contentType: contentType,
                        contentID: contentID,
                        authorID: userID,
                        body: String(clean.prefix(1200))
                    )
                )
                .execute()

            await reloadComments(
                contentType: contentType,
                contentID: contentID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteComment(
        contentType: String,
        contentID: UUID,
        commentID: UUID
    ) async -> Bool {
        do {
            try await client
                .from(
                    "community_group_content_comments"
                )
                .delete()
                .eq("id", value: commentID)
                .execute()

            await reloadComments(
                contentType: contentType,
                contentID: contentID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setHosts(
        groupID: UUID,
        contentType: String,
        contentID: UUID,
        userIDs: [UUID]
    ) async -> Bool {
        do {
            try await client
                .from(
                    "community_group_content_hosts"
                )
                .delete()
                .eq(
                    "content_type",
                    value: contentType
                )
                .eq(
                    "content_id",
                    value: contentID
                )
                .execute()

            let payload = Array(Set(userIDs))
                .map {
                    CommunityGroupContentHostInsert(
                        groupID: groupID,
                        contentType: contentType,
                        contentID: contentID,
                        userID: $0
                    )
                }

            if !payload.isEmpty {
                try await client
                    .from(
                        "community_group_content_hosts"
                    )
                    .insert(payload)
                    .execute()
            }

            hosts = try await client
                .from(
                    "community_group_content_hosts"
                )
                .select()
                .eq(
                    "content_type",
                    value: contentType
                )
                .eq(
                    "content_id",
                    value: contentID
                )
                .execute()
                .value

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelEvent(
        event: CommunityGroupEventRecord
    ) async -> Bool {
        do {
            try await client
                .from("community_group_events")
                .update(
                    CommunityContentStatusUpdate(
                        status: "cancelled"
                    )
                )
                .eq("id", value: event.id)
                .execute()

            await loadEvent(
                groupID: event.groupID,
                eventID: event.id
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelChallenge(
        challenge: CommunityGroupChallengeRecord
    ) async -> Bool {
        do {
            try await client
                .from(
                    "community_group_challenges"
                )
                .update(
                    CommunityContentStatusUpdate(
                        status: "cancelled"
                    )
                )
                .eq(
                    "id",
                    value: challenge.id
                )
                .execute()

            await loadChallenge(
                groupID: challenge.groupID,
                challengeID: challenge.id
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateEvent(
        eventID: UUID,
        title: String,
        summary: String,
        activityType: String,
        startsAt: Date,
        meetingName: String,
        activityConfiguration:
            CommunityGroupActivityConfiguration?,
        options: CommunityGroupEventAdvancedOptions
    ) async -> Bool {
        do {
            try await client
                .rpc(
                    "update_community_group_event_v2",
                    params:
                        CommunityGroupEventUpdateParams(
                            eventID: eventID,
                            title: title,
                            summary: summary,
                            activityType:
                                activityType,
                            startsAt: startsAt,
                            meetingName:
                                meetingName,
                            activityConfiguration:
                                activityConfiguration,
                            options: options
                        )
                )
                .execute()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateChallenge(
        challengeID: UUID,
        title: String,
        summary: String,
        metric: CommunityGroupChallengeMetric,
        targetValue: Double,
        startsAt: Date,
        endsAt: Date,
        activityConfiguration:
            CommunityGroupActivityConfiguration?,
        options:
            CommunityGroupChallengeAdvancedOptions
    ) async -> Bool {
        do {
            try await client
                .rpc(
                    "update_community_group_challenge_v2",
                    params:
                        CommunityGroupChallengeUpdateParams(
                            challengeID:
                                challengeID,
                            title: title,
                            summary: summary,
                            metric: metric.rawValue,
                            targetValue:
                                targetValue,
                            startsAt: startsAt,
                            endsAt: endsAt,
                            activityConfiguration:
                                activityConfiguration,
                            options: options
                        )
                )
                .execute()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func reloadComments(
        contentType: String,
        contentID: UUID
    ) async {
        do {
            comments = try await client
                .from(
                    "community_group_content_comments"
                )
                .select()
                .eq(
                    "content_type",
                    value: contentType
                )
                .eq(
                    "content_id",
                    value: contentID
                )
                .order(
                    "created_at",
                    ascending: true
                )
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CommunityContentStatusUpdate:
    Encodable
{
    let status: String
}

private struct CommunityGroupEventUpdateParams:
    Encodable
{
    let eventID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let meetingName: String
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let options: CommunityGroupEventAdvancedOptions

    enum CodingKeys: String, CodingKey {
        case eventID = "p_event_id"
        case title = "p_title"
        case summary = "p_summary"
        case activityType = "p_activity_type"
        case startsAt = "p_starts_at"
        case meetingName = "p_meeting_name"
        case activityConfiguration =
            "p_activity_config"
        case options = "p_options"
    }
}

private struct CommunityGroupChallengeUpdateParams:
    Encodable
{
    let challengeID: UUID
    let title: String
    let summary: String
    let metric: String
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let options:
        CommunityGroupChallengeAdvancedOptions

    enum CodingKeys: String, CodingKey {
        case challengeID = "p_challenge_id"
        case title = "p_title"
        case summary = "p_summary"
        case metric = "p_metric"
        case targetValue = "p_target_value"
        case startsAt = "p_starts_at"
        case endsAt = "p_ends_at"
        case activityConfiguration =
            "p_activity_config"
        case options = "p_options"
    }
}
