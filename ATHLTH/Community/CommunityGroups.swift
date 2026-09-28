import Foundation
import PhotosUI
import Supabase
import SwiftUI
import UIKit

struct CommunityGroupRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let creatorID: UUID
    let name: String
    let summary: String
    let locationName: String
    let visibility: String
    let imageURL: String?
    let joinMode: String
    let membersCanCreateContent: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case name
        case summary
        case locationName = "location_name"
        case visibility
        case imageURL = "image_url"
        case joinMode = "join_mode"
        case membersCanCreateContent = "members_can_create_content"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupMemberRecord: Codable, Hashable {
    let groupID: UUID
    let userID: UUID
    let role: String
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
    }
}

struct CommunityGroupAnnouncementRecord:
    Codable,
    Identifiable,
    Hashable
{
    let id: UUID
    let groupID: UUID
    let authorID: UUID
    let body: String
    let pinnedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case authorID = "author_id"
        case body
        case pinnedAt = "pinned_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupAnnouncementReactionRecord:
    Codable,
    Hashable
{
    let announcementID: UUID
    let groupID: UUID
    let userID: UUID
    let reaction: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case groupID = "group_id"
        case userID = "user_id"
        case reaction
        case createdAt = "created_at"
    }
}

struct CommunityGroupEngagementLeaderboardEntry:
    Codable,
    Identifiable,
    Hashable
{
    var id: UUID { userID }

    let userID: UUID
    let workoutCount: Int
    let messageCount: Int
    let likesGiven: Int
    let eventsJoined: Int
    let challengesJoined: Int
    let score: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case workoutCount = "workout_count"
        case messageCount = "message_count"
        case likesGiven = "likes_given"
        case eventsJoined = "events_joined"
        case challengesJoined = "challenges_joined"
        case score
    }
}

struct CommunityGroupActivityRecord:
    Codable,
    Identifiable,
    Hashable
{
    let id: UUID
    let groupID: UUID
    let actorID: UUID?
    let kind: String
    let entityID: UUID?
    let headline: String
    let detail: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case actorID = "actor_id"
        case kind
        case entityID = "entity_id"
        case headline
        case detail
        case createdAt = "created_at"
    }
}

struct CommunityGroupMessageRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let senderID: UUID
    let senderName: String
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case senderID = "sender_id"
        case senderName = "sender_name"
        case body
        case createdAt = "created_at"
    }
}

struct CommunityGroupEventRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let endsAt: Date?
    let meetingName: String
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let status: String
    let organizerKind: CommunityGroupOrganizerKind
    let organizerUserID: UUID?
    let capacity: Int?
    let rsvpDeadline: Date?
    let meetingLatitude: Double?
    let meetingLongitude: Double?
    let repeatRule: String?
    let repeatUntil: Date?
    let seriesID: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case creatorID = "creator_id"
        case title
        case summary
        case activityType = "activity_type"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case meetingName = "meeting_name"
        case imageURL = "image_url"
        case activityConfiguration = "activity_config"
        case status
        case organizerKind = "organizer_kind"
        case organizerUserID = "organizer_user_id"
        case capacity
        case rsvpDeadline = "rsvp_deadline"
        case meetingLatitude = "meeting_lat"
        case meetingLongitude = "meeting_long"
        case repeatRule = "repeat_rule"
        case repeatUntil = "repeat_until"
        case seriesID = "series_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum CommunityGroupChallengeMetric: String, Codable, CaseIterable, Identifiable {
    case distanceKM = "distance_km"
    case workouts
    case activeMinutes = "active_minutes"
    case fastestTime = "fastest_time_seconds"
    case strengthVolume = "strength_volume_kg"
    case heaviestWeight = "heaviest_weight_kg"
    case strengthReps = "strength_reps"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distanceKM: return "Distance"
        case .workouts: return "Workouts"
        case .activeMinutes: return "Active Minutes"
        case .fastestTime: return "Fastest Time"
        case .strengthVolume: return "Total Volume"
        case .heaviestWeight: return "Heaviest Weight"
        case .strengthReps: return "Total Reps"
        }
    }

    var unit: String {
        switch self {
        case .distanceKM: return "km"
        case .workouts: return "workouts"
        case .activeMinutes: return "min"
        case .fastestTime: return "time"
        case .strengthVolume: return "kg"
        case .heaviestWeight: return "kg"
        case .strengthReps: return "reps"
        }
    }

    var icon: String {
        switch self {
        case .distanceKM: return "figure.run"
        case .workouts: return "checkmark.circle.fill"
        case .activeMinutes: return "clock.fill"
        case .fastestTime: return "timer"
        case .strengthVolume: return "sum"
        case .heaviestWeight: return "dumbbell.fill"
        case .strengthReps: return "repeat"
        }
    }
}

struct CommunityGroupChallengeRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let groupID: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let metric: CommunityGroupChallengeMetric
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let status: String
    let organizerKind: CommunityGroupOrganizerKind
    let organizerUserID: UUID?
    let scoringMode: CommunityGroupScoringMode
    let attemptLimit: Int?
    let routeVerificationEnabled: Bool
    let routeToleranceMeters: Int
    let joinRequired: Bool
    let seriesID: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case creatorID = "creator_id"
        case title
        case summary
        case metric
        case targetValue = "target_value"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case imageURL = "image_url"
        case activityConfiguration = "activity_config"
        case status
        case organizerKind = "organizer_kind"
        case organizerUserID = "organizer_user_id"
        case scoringMode = "scoring_mode"
        case attemptLimit = "attempt_limit"
        case routeVerificationEnabled =
            "route_verification_enabled"
        case routeToleranceMeters =
            "route_tolerance_meters"
        case joinRequired = "join_required"
        case seriesID = "series_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupChallengeWorkoutRecord: Codable, Hashable {
    let challengeID: UUID
    let userID: UUID
    let workoutID: UUID
    let contribution: Double
    let routeMatchPercent: Double?
    let verificationStatus: String
    let isManual: Bool
    let manualNote: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case workoutID = "workout_id"
        case contribution
        case routeMatchPercent = "route_match_percent"
        case verificationStatus = "verification_status"
        case isManual = "is_manual"
        case manualNote = "manual_note"
        case createdAt = "created_at"
    }
}

struct CommunityGroupJoinRequestRecord: Codable, Hashable {
    let groupID: UUID
    let userID: UUID
    let status: String
    let createdAt: Date
    let respondedAt: Date?
    let respondedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
        case respondedBy = "responded_by"
    }
}

struct CommunityGroupInviteRecord: Codable, Hashable {
    let groupID: UUID
    let userID: UUID
    let invitedBy: UUID
    let status: String
    let createdAt: Date
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case invitedBy = "invited_by"
        case status
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }
}

struct CommunityGroupNotificationPreferenceRecord: Codable, Hashable {
    let groupID: UUID
    let userID: UUID
    let mode: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case mode
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupEventRSVPRecord: Codable, Hashable {
    let groupID: UUID
    let eventID: UUID
    let userID: UUID
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case eventID = "event_id"
        case userID = "user_id"
        case status
        case updatedAt = "updated_at"
    }
}

private struct CommunityGroupInsert: Encodable {
    let id: UUID
    let creatorID: UUID
    let name: String
    let summary: String
    let locationName: String
    let visibility: String
    let joinMode: String
    let membersCanCreateContent: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case name
        case summary
        case locationName = "location_name"
        case visibility
        case joinMode = "join_mode"
        case membersCanCreateContent = "members_can_create_content"
    }
}

private struct CommunityGroupUpdate: Encodable {
    let name: String
    let summary: String
    let locationName: String
    let visibility: String
    let joinMode: String
    let membersCanCreateContent: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case summary
        case locationName = "location_name"
        case visibility
        case joinMode = "join_mode"
        case membersCanCreateContent = "members_can_create_content"
        case updatedAt = "updated_at"
    }
}

private struct CommunityGroupImageUpdate: Encodable {
    let imageURL: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case updatedAt = "updated_at"
    }
}

private struct CommunityGroupAnnouncementInsert: Encodable {
    let groupID: UUID
    let authorID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case authorID = "author_id"
        case body
    }
}

private struct CommunityGroupAnnouncementReactionInsert: Encodable {
    let announcementID: UUID
    let groupID: UUID
    let userID: UUID
    let reaction: String

    enum CodingKeys: String, CodingKey {
        case announcementID = "announcement_id"
        case groupID = "group_id"
        case userID = "user_id"
        case reaction
    }
}

private struct CommunityGroupLeaderboardParams: Encodable {
    let groupID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
    }
}

private struct CommunityGroupWorkoutActivityParams: Encodable {
    let workoutID: UUID
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case workoutID = "p_workout_id"
        case completedAt = "p_completed_at"
    }
}

private struct CommunityGroupMemberInsert: Encodable {
    let groupID: UUID
    let userID: UUID
    let role: String

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
    }
}

private struct CommunityGroupMessageInsert: Encodable {
    let id: UUID
    let groupID: UUID
    let senderID: UUID
    let senderName: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case senderID = "sender_id"
        case senderName = "sender_name"
        case body
    }
}

private struct CommunityGroupEventInsert: Encodable {
    let id: UUID
    let groupID: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let endsAt: Date?
    let meetingName: String
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case creatorID = "creator_id"
        case title
        case summary
        case activityType = "activity_type"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case meetingName = "meeting_name"
        case imageURL = "image_url"
    }
}

private struct CommunityGroupChallengeInsert: Encodable {
    let id: UUID
    let groupID: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let metric: CommunityGroupChallengeMetric
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case creatorID = "creator_id"
        case title
        case summary
        case metric
        case targetValue = "target_value"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case imageURL = "image_url"
    }
}

private struct CommunityGroupEventCreateParams: Encodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let meetingName: String
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case groupID = "p_group_id"
        case title = "p_title"
        case summary = "p_summary"
        case activityType = "p_activity_type"
        case startsAt = "p_starts_at"
        case meetingName = "p_meeting_name"
        case imageURL = "p_image_url"
        case activityConfiguration =
            "p_activity_config"
    }
}

private struct CommunityGroupChallengeCreateParams: Encodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let summary: String
    let metric: String
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case groupID = "p_group_id"
        case title = "p_title"
        case summary = "p_summary"
        case metric = "p_metric"
        case targetValue = "p_target_value"
        case startsAt = "p_starts_at"
        case endsAt = "p_ends_at"
        case imageURL = "p_image_url"
        case activityConfiguration =
            "p_activity_config"
    }
}

private struct CommunityGroupEventCreateV2Params: Encodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let summary: String
    let activityType: String
    let startsAt: Date
    let meetingName: String
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let options: CommunityGroupEventAdvancedOptions

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case groupID = "p_group_id"
        case title = "p_title"
        case summary = "p_summary"
        case activityType = "p_activity_type"
        case startsAt = "p_starts_at"
        case meetingName = "p_meeting_name"
        case imageURL = "p_image_url"
        case activityConfiguration =
            "p_activity_config"
        case options = "p_options"
    }
}

private struct CommunityGroupChallengeCreateV2Params: Encodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let summary: String
    let metric: String
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let imageURL: String?
    let activityConfiguration:
        CommunityGroupActivityConfiguration?
    let options: CommunityGroupChallengeAdvancedOptions

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case groupID = "p_group_id"
        case title = "p_title"
        case summary = "p_summary"
        case metric = "p_metric"
        case targetValue = "p_target_value"
        case startsAt = "p_starts_at"
        case endsAt = "p_ends_at"
        case imageURL = "p_image_url"
        case activityConfiguration =
            "p_activity_config"
        case options = "p_options"
    }
}

private struct CommunityGroupChallengeWorkoutInsert: Encodable {
    let challengeID: UUID
    let userID: UUID
    let workoutID: UUID
    let contribution: Double
    let routeMatchPercent: Double?
    let verificationStatus: String

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case workoutID = "workout_id"
        case contribution
        case routeMatchPercent = "route_match_percent"
        case verificationStatus = "verification_status"
    }
}

private struct CommunityGroupAnnouncementPinParams: Encodable {
    let groupID: UUID
    let announcementID: UUID?

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case announcementID = "p_announcement_id"
    }
}

private struct CommunityGroupJoinParams: Encodable {
    let groupID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
    }
}

private struct CommunityGroupJoinResponseParams: Encodable {
    let groupID: UUID
    let userID: UUID
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case userID = "p_user_id"
        case accept = "p_accept"
    }
}

private struct CommunityGroupInviteParams: Encodable {
    let groupID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case userID = "p_user_id"
    }
}

private struct CommunityGroupInviteResponseParams: Encodable {
    let groupID: UUID
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case accept = "p_accept"
    }
}

@MainActor
final class CommunityGroupStore: ObservableObject {
    @Published private(set) var groups: [CommunityGroupRecord] = []
    @Published private(set) var ownMemberships: [CommunityGroupMemberRecord] = []
    @Published private(set) var membersByGroup: [UUID: [CommunityGroupMemberRecord]] = [:]
    @Published private(set) var announcementsByGroup: [UUID: [CommunityGroupAnnouncementRecord]] = [:]
    @Published private(set) var announcementReactionsByGroup: [UUID: [CommunityGroupAnnouncementReactionRecord]] = [:]
    @Published private(set) var activityByGroup: [UUID: [CommunityGroupActivityRecord]] = [:]
    @Published private(set) var communityActivity: [CommunityGroupActivityRecord] = []
    @Published private(set) var profileCardsByID: [UUID: SocialProfileCard] = [:]
    @Published private(set) var messagesByGroup: [UUID: [CommunityGroupMessageRecord]] = [:]
    @Published private(set) var eventsByGroup: [UUID: [CommunityGroupEventRecord]] = [:]
    @Published private(set) var challengesByGroup: [UUID: [CommunityGroupChallengeRecord]] = [:]
    @Published private(set) var challengeWorkouts: [CommunityGroupChallengeWorkoutRecord] = []
    @Published private(set) var joinRequestsByGroup: [UUID: [CommunityGroupJoinRequestRecord]] = [:]
    @Published private(set) var ownJoinRequests: [CommunityGroupJoinRequestRecord] = []
    @Published private(set) var ownInvites: [CommunityGroupInviteRecord] = []
    @Published private(set) var notificationPreferencesByGroup: [UUID: CommunityGroupNotificationPreferenceRecord] = [:]
    @Published private(set) var eventRSVPsByGroup: [UUID: [CommunityGroupEventRSVPRecord]] = [:]
    @Published private(set) var leaderboardByGroup: [UUID: [CommunityGroupEngagementLeaderboardEntry]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private var lastRefreshAt: Date?
    private var groupFetchLimit = 40
    @Published private(set) var canLoadMoreGroups = true
    @Published private(set) var isLoadingMoreGroups = false

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    private var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    var joinedGroupIDs: Set<UUID> {
        Set(ownMemberships.map(\.groupID))
    }

    var joinedGroups: [CommunityGroupRecord] {
        groups.filter { joinedGroupIDs.contains($0.id) }
    }

    func isMember(of group: CommunityGroupRecord) -> Bool {
        joinedGroupIDs.contains(group.id)
    }

    func isOwner(of group: CommunityGroupRecord) -> Bool {
        group.creatorID == currentUserID
    }

    func canManage(_ group: CommunityGroupRecord) -> Bool {
        if isOwner(of: group) {
            return true
        }

        return ownMemberships.contains {
            $0.groupID == group.id &&
            ($0.role == "owner" || $0.role == "admin")
        }
    }

    func canPublishUpdates(_ group: CommunityGroupRecord) -> Bool {
        if canManage(group) {
            return true
        }

        return ownMemberships.contains {
            $0.groupID == group.id &&
            $0.role == "contributor"
        }
    }

    func role(in group: CommunityGroupRecord) -> String? {
        if isOwner(of: group) {
            return "owner"
        }

        return ownMemberships.first {
            $0.groupID == group.id
        }?.role
    }

    func canCreateGroupContent(
        _ group: CommunityGroupRecord
    ) -> Bool {
        switch role(in: group) {
        case "owner", "admin", "contributor":
            return true
        case "member":
            return group.membersCanCreateContent
        default:
            return false
        }
    }

    func profileCard(for userID: UUID) -> SocialProfileCard? {
        profileCardsByID[userID]
    }

    func group(for groupID: UUID) -> CommunityGroupRecord? {
        groups.first { $0.id == groupID }
    }

    func members(in groupID: UUID) -> [CommunityGroupMemberRecord] {
        var resolved = membersByGroup[groupID] ?? []

        // The creator is always the Club owner in the backend. Surface that
        // immediately even if the detailed membership query is still loading,
        // so a freshly created Club never shows an empty Members screen.
        if let group = group(for: groupID),
           !resolved.contains(
               where: { $0.userID == group.creatorID }
           ) {
            resolved.insert(
                CommunityGroupMemberRecord(
                    groupID: groupID,
                    userID: group.creatorID,
                    role: "owner",
                    joinedAt: group.createdAt
                ),
                at: 0
            )
        }

        return resolved
    }

    func announcements(
        in groupID: UUID
    ) -> [CommunityGroupAnnouncementRecord] {
        announcementsByGroup[groupID] ?? []
    }

    func announcementLikeCount(
        _ announcementID: UUID,
        in groupID: UUID
    ) -> Int {
        announcementReactionsByGroup[groupID]?
            .filter {
                $0.announcementID == announcementID &&
                $0.reaction == "like"
            }
            .count ?? 0
    }

    func hasLikedAnnouncement(
        _ announcementID: UUID,
        in groupID: UUID
    ) -> Bool {
        guard let currentUserID else { return false }

        return announcementReactionsByGroup[groupID]?
            .contains {
                $0.announcementID == announcementID &&
                $0.userID == currentUserID &&
                $0.reaction == "like"
            } ?? false
    }

    func leaderboard(
        in groupID: UUID
    ) -> [CommunityGroupEngagementLeaderboardEntry] {
        leaderboardByGroup[groupID] ?? []
    }

    func activity(
        in groupID: UUID
    ) -> [CommunityGroupActivityRecord] {
        activityByGroup[groupID] ?? []
    }

    func messages(in groupID: UUID) -> [CommunityGroupMessageRecord] {
        messagesByGroup[groupID] ?? []
    }

    func events(in groupID: UUID) -> [CommunityGroupEventRecord] {
        eventsByGroup[groupID] ?? []
    }

    func challenges(in groupID: UUID) -> [CommunityGroupChallengeRecord] {
        challengesByGroup[groupID] ?? []
    }

    func joinRequests(
        in groupID: UUID
    ) -> [CommunityGroupJoinRequestRecord] {
        joinRequestsByGroup[groupID] ?? []
    }

    func pendingJoinRequest(
        for groupID: UUID
    ) -> CommunityGroupJoinRequestRecord? {
        ownJoinRequests.first {
            $0.groupID == groupID &&
            $0.status == "pending"
        }
    }

    func pendingInvite(
        for groupID: UUID
    ) -> CommunityGroupInviteRecord? {
        ownInvites.first {
            $0.groupID == groupID &&
            $0.status == "pending"
        }
    }

    func notificationMode(in groupID: UUID) -> String {
        notificationPreferencesByGroup[groupID]?.mode
            ?? "all"
    }

    func pinnedAnnouncement(
        in groupID: UUID
    ) -> CommunityGroupAnnouncementRecord? {
        announcements(in: groupID).first {
            $0.pinnedAt != nil
        }
    }

    func eventRSVP(
        eventID: UUID
    ) -> CommunityGroupEventRSVPRecord? {
        for values in eventRSVPsByGroup.values {
            if let value = values.first(where: {
                $0.eventID == eventID &&
                $0.userID == currentUserID
            }) {
                return value
            }
        }
        return nil
    }

    func eventRSVPCount(
        eventID: UUID,
        status: String
    ) -> Int {
        eventRSVPsByGroup.values
            .flatMap { $0 }
            .filter {
                $0.eventID == eventID &&
                $0.status == status
            }
            .count
    }

    func mentionCandidates(
        in groupID: UUID
    ) -> [SocialProfileCard] {
        members(in: groupID).compactMap {
            profileCardsByID[$0.userID]
        }
    }

    func challengeProgress(
        _ challenge: CommunityGroupChallengeRecord
    ) -> Double {
        let values = challengeWorkouts.filter {
            $0.challengeID == challenge.id &&
            $0.verificationStatus != "unverified"
        }

        switch challenge.scoringMode {
        case .cumulative:
            return values.reduce(0) {
                $0 + $1.contribution
            }

        case .bestAttempt:
            let scores = values.map(\.contribution)
            guard !scores.isEmpty else {
                return 0
            }

            if challenge.prefersLowerLeaderboardScore {
                return scores.min() ?? 0
            }

            return scores.max() ?? 0

        case .completeTarget:
            return min(
                values.reduce(0) {
                    $0 + $1.contribution
                },
                challenge.targetValue
            )
        }
    }

    func refresh(force: Bool = false) async {
        guard let userID = currentUserID else {
            groups = []
            ownMemberships = []
            ownJoinRequests = []
            ownInvites = []
            notificationPreferencesByGroup = [:]
            announcementReactionsByGroup = [:]
            leaderboardByGroup = [:]
            return
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 180,
           !groups.isEmpty {
            return
        }

        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            async let groupsQuery: [CommunityGroupRecord] = client
                .from("community_groups")
                .select()
                .order("created_at", ascending: false)
                .limit(groupFetchLimit)
                .execute()
                .value

            async let membershipsQuery: [CommunityGroupMemberRecord] = client
                .from("community_group_members")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            async let activityQuery: [CommunityGroupActivityRecord] = client
                .from("community_group_activity")
                .select()
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            async let invitesQuery: [CommunityGroupInviteRecord] = client
                .from("community_group_invites")
                .select()
                .eq("user_id", value: userID)
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value

            async let joinRequestsQuery: [CommunityGroupJoinRequestRecord] = client
                .from("community_group_join_requests")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            async let notificationPreferencesQuery:
                [CommunityGroupNotificationPreferenceRecord] = client
                    .from("community_group_notification_preferences")
                    .select()
                    .eq("user_id", value: userID)
                    .execute()
                    .value

            let discoveryGroups = try await groupsQuery
            let loadedMemberships =
                try await membershipsQuery
            let loadedActivity =
                try await activityQuery
                .filter { $0.kind != "announcement" }
            let loadedInvites = try await invitesQuery
            let loadedJoinRequests =
                try await joinRequestsQuery
            let notificationPreferences =
                try await notificationPreferencesQuery

            // The paged discovery list must never hide a club the user
            // belongs to or has been invited to just because that club is
            // older than the first page.
            var requiredGroupIDs =
                Set(loadedMemberships.map(\.groupID))
            requiredGroupIDs.formUnion(
                loadedInvites.map(\.groupID)
            )
            requiredGroupIDs.formUnion(
                loadedJoinRequests.map(\.groupID)
            )

            let discoveryGroupIDs =
                Set(discoveryGroups.map(\.id))
            let missingGroupIDs =
                requiredGroupIDs.subtracting(
                    discoveryGroupIDs
                )

            let requiredGroups: [CommunityGroupRecord]
            if missingGroupIDs.isEmpty {
                requiredGroups = []
            } else {
                requiredGroups = try await client
                    .from("community_groups")
                    .select()
                    .in(
                        "id",
                        values:
                            missingGroupIDs.map(
                                \.uuidString
                            )
                    )
                    .execute()
                    .value
            }

            let loadedGroups =
                discoveryGroups + requiredGroups
                .filter {
                    !discoveryGroupIDs.contains(
                        $0.id
                    )
                }

            var neededProfileIDs: Set<UUID> = [
                userID
            ]
            neededProfileIDs.formUnion(
                loadedGroups.map(\.creatorID)
            )
            neededProfileIDs.formUnion(
                loadedActivity.compactMap(\.actorID)
            )
            neededProfileIDs.formUnion(
                loadedInvites.map(\.invitedBy)
            )

            let profiles: [SocialProfileCard]
            if neededProfileIDs.isEmpty {
                profiles = []
            } else {
                profiles = try await client
                    .from("social_profile_cards")
                    .select()
                    .in(
                        "user_id",
                        values:
                            neededProfileIDs.map(
                                \.uuidString
                            )
                    )
                    .execute()
                    .value
            }

            groups = loadedGroups
            canLoadMoreGroups =
                discoveryGroups.count >= groupFetchLimit
            lastRefreshAt = Date()
            ownMemberships = loadedMemberships
            communityActivity = loadedActivity
            ownInvites = loadedInvites
            ownJoinRequests = loadedJoinRequests

            notificationPreferencesByGroup = Dictionary(
                uniqueKeysWithValues:
                    notificationPreferences.map {
                        ($0.groupID, $0)
                    }
            )

            profileCardsByID = Dictionary(
                uniqueKeysWithValues: profiles.map {
                    ($0.userID, $0)
                }
            )
            errorMessage = nil
        } catch is CancellationError {
            // A refresh can be cancelled when the Community view
            // disappears or a new refresh supersedes the current one.
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func mergeGroupActivityIntoCommunityFeed(
        _ groupID: UUID
    ) {
        let refreshedGroupActivity =
            activityByGroup[groupID] ?? []

        let unaffected =
            communityActivity.filter {
                $0.groupID != groupID
            }

        communityActivity =
            Array(
                (unaffected + refreshedGroupActivity)
                    .sorted {
                        $0.createdAt > $1.createdAt
                    }
                    .prefix(50)
            )
    }

    func loadMoreGroups() async {
        guard canLoadMoreGroups,
              !isLoading,
              !isLoadingMoreGroups
        else {
            return
        }

        isLoadingMoreGroups = true
        groupFetchLimit += 40
        await refresh(force: true)
        isLoadingMoreGroups = false
    }

    var calendarEvents: [CommunityGroupEventRecord] {
        let joinedIDs = joinedGroupIDs
        return eventsByGroup
            .filter { joinedIDs.contains($0.key) }
            .values
            .flatMap { $0 }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var calendarEventRSVPs: [CommunityGroupEventRSVPRecord] {
        let joinedIDs = joinedGroupIDs
        return eventRSVPsByGroup
            .filter { joinedIDs.contains($0.key) }
            .values
            .flatMap { $0 }
    }

    func refreshCalendarContent() async {
        guard let userID = currentUserID else {
            return
        }

        let groupIDs = Array(joinedGroupIDs)

        guard !groupIDs.isEmpty else {
            return
        }

        do {
            let values =
                groupIDs.map(\.uuidString)

            async let eventsQuery:
                [CommunityGroupEventRecord] =
                    client
                        .from(
                            "community_group_events"
                        )
                        .select()
                        .in(
                            "group_id",
                            values: values
                        )
                        .order(
                            "starts_at",
                            ascending: true
                        )
                        .limit(1_000)
                        .execute()
                        .value

            async let rsvpQuery:
                [CommunityGroupEventRSVPRecord] =
                    client
                        .from(
                            "community_group_event_rsvps"
                        )
                        .select()
                        .in(
                            "group_id",
                            values: values
                        )
                        .eq(
                            "user_id",
                            value: userID
                        )
                        .limit(1_000)
                        .execute()
                        .value

            let loadedEvents =
                try await eventsQuery
            let loadedRSVPs =
                try await rsvpQuery

            guard !Task.isCancelled else {
                return
            }

            let eventsByID =
                Dictionary(
                    grouping: loadedEvents,
                    by: \.groupID
                )
            let rsvpsByID =
                Dictionary(
                    grouping: loadedRSVPs,
                    by: \.groupID
                )

            for groupID in groupIDs {
                eventsByGroup[groupID] =
                    eventsByID[groupID] ?? []
                eventRSVPsByGroup[groupID] =
                    rsvpsByID[groupID] ?? []
            }

            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            errorMessage =
                error.localizedDescription
        }
    }

    func loadGroupContent(_ groupID: UUID) async {
        let creatorOwnsGroup =
            groups.first {
                $0.id == groupID &&
                $0.creatorID == currentUserID
            } != nil

        guard joinedGroupIDs.contains(groupID) ||
              creatorOwnsGroup
        else {
            return
        }

        do {
            async let membersQuery: [CommunityGroupMemberRecord] = client
                .from("community_group_members")
                .select()
                .eq("group_id", value: groupID)
                .execute()
                .value

            async let messagesQuery: [CommunityGroupMessageRecord] = client
                .from("community_group_messages")
                .select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: true)
                .limit(150)
                .execute()
                .value

            async let eventsQuery: [CommunityGroupEventRecord] = client
                .from("community_group_events")
                .select()
                .eq("group_id", value: groupID)
                .order("starts_at", ascending: true)
                .limit(100)
                .execute()
                .value

            async let challengesQuery: [CommunityGroupChallengeRecord] = client
                .from("community_group_challenges")
                .select()
                .eq("group_id", value: groupID)
                .order("starts_at", ascending: false)
                .limit(100)
                .execute()
                .value

            async let announcementsQuery: [CommunityGroupAnnouncementRecord] = client
                .from("community_group_announcements")
                .select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: false)
                .limit(30)
                .execute()
                .value

            async let activityQuery: [CommunityGroupActivityRecord] = client
                .from("community_group_activity")
                .select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            async let joinRequestsQuery:
                [CommunityGroupJoinRequestRecord] = client
                    .from("community_group_join_requests")
                    .select()
                    .eq("group_id", value: groupID)
                    .eq("status", value: "pending")
                    .order("created_at", ascending: true)
                    .execute()
                    .value

            async let eventRSVPsQuery:
                [CommunityGroupEventRSVPRecord] = client
                    .from("community_group_event_rsvps")
                    .select()
                    .eq("group_id", value: groupID)
                    .execute()
                    .value

            let loadedMembers = try await membersQuery
            let loadedMessages = try await messagesQuery
            let loadedEvents = try await eventsQuery
            let loadedChallenges = try await challengesQuery
            let loadedAnnouncements = try await announcementsQuery
            let loadedActivity = try await activityQuery
            let loadedJoinRequests = try await joinRequestsQuery
            let loadedEventRSVPs = try await eventRSVPsQuery

            var neededProfileIDs: Set<UUID> = []
            neededProfileIDs.formUnion(
                loadedMembers.map(\.userID)
            )
            neededProfileIDs.formUnion(
                loadedMessages.map(\.senderID)
            )
            neededProfileIDs.formUnion(
                loadedEvents.map(\.creatorID)
            )
            neededProfileIDs.formUnion(
                loadedAnnouncements.map(\.authorID)
            )
            neededProfileIDs.formUnion(
                loadedActivity.compactMap(\.actorID)
            )
            neededProfileIDs.formUnion(
                loadedJoinRequests.map(\.userID)
            )
            neededProfileIDs.formUnion(
                loadedJoinRequests.compactMap(
                    \.respondedBy
                )
            )
            if let currentUserID {
                neededProfileIDs.insert(
                    currentUserID
                )
            }

            let loadedProfiles: [SocialProfileCard]
            if neededProfileIDs.isEmpty {
                loadedProfiles = []
            } else {
                loadedProfiles = try await client
                    .from("social_profile_cards")
                    .select()
                    .in(
                        "user_id",
                        values:
                            neededProfileIDs.map(
                                \.uuidString
                            )
                    )
                    .execute()
                    .value
            }

            membersByGroup[groupID] = loadedMembers
            messagesByGroup[groupID] = loadedMessages
            eventsByGroup[groupID] = loadedEvents
            challengesByGroup[groupID] = loadedChallenges
            announcementsByGroup[groupID] = loadedAnnouncements
            activityByGroup[groupID] = loadedActivity
                .filter { $0.kind != "announcement" }
            joinRequestsByGroup[groupID] = loadedJoinRequests
            eventRSVPsByGroup[groupID] = loadedEventRSVPs

            for profile in loadedProfiles {
                profileCardsByID[profile.userID] = profile
            }

            let allContributions: [CommunityGroupChallengeWorkoutRecord] =
                try await client
                    .from("community_group_challenge_workouts")
                    .select()
                    .order("created_at", ascending: false)
                    .limit(1_000)
                    .execute()
                    .value

            let challengeIDs = Set(loadedChallenges.map(\.id))
            challengeWorkouts.removeAll {
                challengeIDs.contains($0.challengeID)
            }
            challengeWorkouts.append(
                contentsOf: allContributions.filter {
                    challengeIDs.contains($0.challengeID)
                }
            )

            await refreshAnnouncementReactions(
                groupID,
                reportErrors: false
            )
            await refreshLeaderboard(
                groupID,
                reportErrors: false
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createGroup(
        name: String,
        summary: String,
        visibility: String,
        joinMode: String = "open",
        membersCanCreateContent: Bool = true,
        imageJPEGData: Data? = nil
    ) async -> Bool {
        guard let userID = currentUserID else { return false }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanName.count >= 2 else {
            errorMessage = "Add a group name."
            return false
        }

        do {
            let resolvedVisibility =
                visibility == "private"
                    ? "private"
                    : "public"
            let resolvedJoinMode =
                resolvedVisibility == "private" &&
                joinMode == "open"
                    ? "invite_only"
                    : (
                        ["open", "approval", "invite_only"]
                            .contains(joinMode)
                            ? joinMode
                            : "open"
                    )

            let groupID = UUID()

            let payload = CommunityGroupInsert(
                id: groupID,
                creatorID: userID,
                name: String(cleanName.prefix(80)),
                summary: String(summary.prefix(800)),
                locationName: "",
                visibility: resolvedVisibility,
                joinMode: resolvedJoinMode,
                membersCanCreateContent:
                    membersCanCreateContent
            )

            try await client
                .from("community_groups")
                .insert(payload)
                .execute()

            let ownerMembership =
                CommunityGroupMemberRecord(
                    groupID: groupID,
                    userID: userID,
                    role: "owner",
                    joinedAt: Date()
                )

            ownMemberships.removeAll {
                $0.groupID == groupID &&
                $0.userID == userID
            }
            ownMemberships.append(ownerMembership)
            membersByGroup[groupID] = [ownerMembership]

            if let imageJPEGData {
                guard imageJPEGData.count <= 5_242_880 else {
                    errorMessage =
                        "Club image must be smaller than 5 MB."
                    await refresh(force: true)
                    return true
                }

                let path =
                    "\(groupID.uuidString.lowercased())/cover.jpg"

                do {
                    try await client.storage
                        .from("community-group-images")
                        .upload(
                            path: path,
                            file: imageJPEGData,
                            options: FileOptions(
                                cacheControl: "3600",
                                contentType: "image/jpeg",
                                upsert: true
                            )
                        )

                    let publicURL = try client.storage
                        .from("community-group-images")
                        .getPublicURL(path: path)

                    var components = URLComponents(
                        url: publicURL,
                        resolvingAgainstBaseURL: false
                    )
                    components?.queryItems = [
                        URLQueryItem(
                            name: "v",
                            value: String(
                                Int(
                                    Date()
                                        .timeIntervalSince1970
                                )
                            )
                        )
                    ]

                    let finalURL =
                        components?.url ?? publicURL

                    try await client
                        .from("community_groups")
                        .update(
                            CommunityGroupImageUpdate(
                                imageURL:
                                    finalURL.absoluteString,
                                updatedAt: Date()
                            )
                        )
                        .eq("id", value: groupID)
                        .execute()
                } catch {
                    // The club itself has already been created. Keep it
                    // usable even if Storage is temporarily unavailable;
                    // the owner can add/change the cover in Club Settings.
                    errorMessage =
                        "Club created, but the image could not be uploaded. You can add it from Club Settings."
                }
            }

            await refresh(force: true)

            // A refresh may finish before the detail membership cache is
            // populated. Keep the owner visible and then hydrate the full
            // Club content immediately.
            if !ownMemberships.contains(
                where: {
                    $0.groupID == groupID &&
                    $0.userID == userID
                }
            ) {
                ownMemberships.append(ownerMembership)
            }

            if membersByGroup[groupID]?.contains(
                where: { $0.userID == userID }
            ) != true {
                membersByGroup[groupID, default: []]
                    .insert(ownerMembership, at: 0)
            }

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateGroup(
        _ group: CommunityGroupRecord,
        name: String,
        locationName: String,
        summary: String,
        visibility: String,
        joinMode: String? = nil,
        membersCanCreateContent: Bool? = nil
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        let cleanName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = locationName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanName.count >= 2 else {
            errorMessage = "Add a group name."
            return false
        }

        do {
            let resolvedVisibility =
                visibility == "private"
                    ? "private"
                    : "public"
            let requestedJoinMode =
                joinMode ?? group.joinMode
            let resolvedJoinMode =
                resolvedVisibility == "private" &&
                requestedJoinMode == "open"
                    ? "invite_only"
                    : requestedJoinMode

            let payload = CommunityGroupUpdate(
                name: String(cleanName.prefix(80)),
                summary: String(summary.prefix(800)),
                locationName: String(cleanLocation.prefix(120)),
                visibility: resolvedVisibility,
                joinMode: resolvedJoinMode,
                membersCanCreateContent:
                    membersCanCreateContent ??
                    group.membersCanCreateContent,
                updatedAt: Date()
            )

            try await client
                .from("community_groups")
                .update(payload)
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func uploadGroupImage(
        _ group: CommunityGroupRecord,
        jpegData: Data
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        guard jpegData.count <= 5_242_880 else {
            errorMessage = "Club image must be smaller than 5 MB."
            return false
        }

        let path = "\(group.id.uuidString.lowercased())/cover.jpg"

        do {
            try await client.storage
                .from("community-group-images")
                .upload(
                    path: path,
                    file: jpegData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        upsert: false
                    )
                )

            let publicURL = try client.storage
                .from("community-group-images")
                .getPublicURL(path: path)

            var components = URLComponents(
                url: publicURL,
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(
                    name: "v",
                    value: String(
                        Int(Date().timeIntervalSince1970)
                    )
                )
            ]

            let finalURL = components?.url ?? publicURL

            try await client
                .from("community_groups")
                .update(
                    CommunityGroupImageUpdate(
                        imageURL: finalURL.absoluteString,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeGroupImage(
        _ group: CommunityGroupRecord
    ) async -> Bool {
        guard canManage(group) else {
            return false
        }

        let path = "\(group.id.uuidString.lowercased())/cover.jpg"

        do {
            try? await client.storage
                .from("community-group-images")
                .remove(paths: [path])

            try await client
                .from("community_groups")
                .update(
                    CommunityGroupImageUpdate(
                        imageURL: nil,
                        updatedAt: Date()
                    )
                )
                .eq("id", value: group.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteGroup(
        _ group: CommunityGroupRecord
    ) async -> Bool {
        guard isOwner(of: group) else {
            errorMessage = "Only the group owner can delete this group."
            return false
        }

        let imagePath =
            "\(group.id.uuidString.lowercased())/cover.jpg"

        do {
            // Storage objects do not cascade with the database row, so remove
            // the group photo while the group still exists and permissions can
            // be evaluated.
            try? await client.storage
                .from("community-group-images")
                .remove(paths: [imagePath])

            try await client
                .from("community_groups")
                .delete()
                .eq("id", value: group.id)
                .execute()

            membersByGroup[group.id] = nil
            announcementsByGroup[group.id] = nil
            announcementReactionsByGroup[group.id] = nil
            leaderboardByGroup[group.id] = nil
            activityByGroup[group.id] = nil
            messagesByGroup[group.id] = nil
            eventsByGroup[group.id] = nil
            challengesByGroup[group.id] = nil

            await refresh(force: true)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func postAnnouncement(
        groupID: UUID,
        body: String
    ) async -> Bool {
        guard let userID = currentUserID,
              let group = group(for: groupID),
              canPublishUpdates(group)
        else {
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
                .from("community_group_announcements")
                .insert(
                    CommunityGroupAnnouncementInsert(
                        groupID: groupID,
                        authorID: userID,
                        body: String(clean.prefix(1200))
                    )
                )
                .execute()

            // The announcement only changes detail-scoped group content.
            // Avoid a full Community reload (groups, memberships, activity,
            // invites and profiles) for a local timeline mutation.
            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleAnnouncementLike(
        groupID: UUID,
        announcementID: UUID
    ) async -> Bool {
        guard let userID = currentUserID,
              joinedGroupIDs.contains(groupID) ||
                groups.first(where: {
                    $0.id == groupID &&
                    $0.creatorID == userID
                }) != nil
        else {
            return false
        }

        do {
            if hasLikedAnnouncement(
                announcementID,
                in: groupID
            ) {
                try await client
                    .from(
                        "community_group_announcement_reactions"
                    )
                    .delete()
                    .eq(
                        "announcement_id",
                        value: announcementID
                    )
                    .eq("user_id", value: userID)
                    .eq("reaction", value: "like")
                    .execute()
            } else {
                try await client
                    .from(
                        "community_group_announcement_reactions"
                    )
                    .insert(
                        CommunityGroupAnnouncementReactionInsert(
                            announcementID: announcementID,
                            groupID: groupID,
                            userID: userID,
                            reaction: "like"
                        )
                    )
                    .execute()
            }

            await refreshAnnouncementReactions(groupID)
            await refreshLeaderboard(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshAnnouncementReactions(
        _ groupID: UUID,
        reportErrors: Bool = true
    ) async {
        do {
            let rows:
                [CommunityGroupAnnouncementReactionRecord] =
                    try await client
                        .from(
                            "community_group_announcement_reactions"
                        )
                        .select()
                        .eq("group_id", value: groupID)
                        .order(
                            "created_at",
                            ascending: false
                        )
                        .limit(1_000)
                        .execute()
                        .value

            announcementReactionsByGroup[groupID] = rows
        } catch {
            if reportErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshLeaderboard(
        _ groupID: UUID,
        reportErrors: Bool = true
    ) async {
        do {
            let rows: [CommunityGroupEngagementLeaderboardEntry] =
                try await client
                    .rpc(
                        "get_community_group_leaderboard",
                        params:
                            CommunityGroupLeaderboardParams(
                                groupID: groupID
                            )
                    )
                    .execute()
                    .value

            leaderboardByGroup[groupID] = rows
        } catch {
            if reportErrors {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteAnnouncement(
        groupID: UUID,
        announcementID: UUID
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group)
        else {
            return false
        }

        do {
            try await client
                .from("community_group_announcements")
                .delete()
                .eq("id", value: announcementID)
                .eq("group_id", value: groupID)
                .execute()

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func pinAnnouncement(
        groupID: UUID,
        announcementID: UUID?
    ) async -> Bool {
        guard let group = group(for: groupID),
              canPublishUpdates(group)
        else {
            return false
        }

        do {
            try await client
                .rpc(
                    "set_community_group_announcement_pin",
                    params:
                        CommunityGroupAnnouncementPinParams(
                            groupID: groupID,
                            announcementID: announcementID
                        )
                )
                .execute()

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func requestJoin(
        _ group: CommunityGroupRecord
    ) async -> String {
        guard currentUserID != nil else {
            return "unavailable"
        }

        do {
            let result: String = try await client
                .rpc(
                    "request_community_group_join",
                    params: CommunityGroupJoinParams(
                        groupID: group.id
                    )
                )
                .execute()
                .value

            await refresh(force: true)

            if result == "joined" {
                await loadGroupContent(group.id)
            }

            return result
        } catch {
            errorMessage = error.localizedDescription
            return "error"
        }
    }

    func respondToJoinRequest(
        groupID: UUID,
        userID: UUID,
        accept: Bool
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group)
        else {
            return false
        }

        do {
            try await client
                .rpc(
                    "respond_community_group_join_request",
                    params: CommunityGroupJoinResponseParams(
                        groupID: groupID,
                        userID: userID,
                        accept: accept
                    )
                )
                .execute()

            await refresh(force: true)
            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func inviteMember(
        groupID: UUID,
        userID: UUID
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group)
        else {
            return false
        }

        do {
            try await client
                .rpc(
                    "invite_community_group_member",
                    params: CommunityGroupInviteParams(
                        groupID: groupID,
                        userID: userID
                    )
                )
                .execute()

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func respondToInvite(
        groupID: UUID,
        accept: Bool
    ) async -> Bool {
        do {
            try await client
                .rpc(
                    "respond_community_group_invite",
                    params: CommunityGroupInviteResponseParams(
                        groupID: groupID,
                        accept: accept
                    )
                )
                .execute()

            await refresh(force: true)

            if accept {
                await loadGroupContent(groupID)
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setGroupNotificationMode(
        groupID: UUID,
        mode: String
    ) async -> Bool {
        guard let userID = currentUserID,
              joinedGroupIDs.contains(groupID),
              ["all", "muted"].contains(mode)
        else {
            return false
        }

        let record =
            CommunityGroupNotificationPreferenceRecord(
                groupID: groupID,
                userID: userID,
                mode: mode,
                updatedAt: Date()
            )

        do {
            try await client
                .from("community_group_notification_preferences")
                .upsert(
                    record,
                    onConflict: "group_id,user_id"
                )
                .execute()

            notificationPreferencesByGroup[groupID] =
                record
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setEventRSVP(
        groupID: UUID,
        eventID: UUID,
        status: String
    ) async -> Bool {
        guard let userID = currentUserID,
              joinedGroupIDs.contains(groupID),
              ["going", "maybe", "not_going"]
                .contains(status)
        else {
            return false
        }

        let record = CommunityGroupEventRSVPRecord(
            groupID: groupID,
            eventID: eventID,
            userID: userID,
            status: status,
            updatedAt: Date()
        )

        do {
            try await client
                .from("community_group_event_rsvps")
                .upsert(
                    record,
                    onConflict: "event_id,user_id"
                )
                .execute()

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeMember(
        groupID: UUID,
        userID: UUID
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group),
              userID != group.creatorID
        else {
            return false
        }

        do {
            try await client
                .from("community_group_members")
                .delete()
                .eq("group_id", value: groupID)
                .eq("user_id", value: userID)
                .neq("role", value: "owner")
                .execute()

            await refresh(force: true)
            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setMemberRole(
        groupID: UUID,
        userID: UUID,
        role: String
    ) async -> Bool {
        guard let group = group(for: groupID),
              canManage(group),
              userID != group.creatorID,
              ["admin", "contributor", "member"].contains(role)
        else {
            return false
        }

        do {
            try await client
                .from("community_group_members")
                .update(["role": role])
                .eq("group_id", value: groupID)
                .eq("user_id", value: userID)
                .execute()

            await loadGroupContent(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func join(_ group: CommunityGroupRecord) async {
        _ = await requestJoin(group)
    }

    func leave(_ group: CommunityGroupRecord) async {
        guard let userID = currentUserID,
              !isOwner(of: group)
        else { return }

        do {
            try await client
                .from("community_group_members")
                .delete()
                .eq("group_id", value: group.id)
                .eq("user_id", value: userID)
                .execute()

            await refresh(force: true)
            membersByGroup[group.id] = nil
            announcementsByGroup[group.id] = nil
            announcementReactionsByGroup[group.id] = nil
            leaderboardByGroup[group.id] = nil
            activityByGroup[group.id] = nil
            messagesByGroup[group.id] = nil
            eventsByGroup[group.id] = nil
            challengesByGroup[group.id] = nil
            joinRequestsByGroup[group.id] = nil
            eventRSVPsByGroup[group.id] = nil
            notificationPreferencesByGroup[group.id] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage(
        groupID: UUID,
        senderName: String,
        body: String
    ) async -> Bool {
        guard let userID = currentUserID else { return false }

        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }

        do {
            try await client
                .from("community_group_messages")
                .insert(
                    CommunityGroupMessageInsert(
                        id: UUID(),
                        groupID: groupID,
                        senderID: userID,
                        senderName: String(
                            senderName
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .prefix(100)
                        ),
                        body: String(clean.prefix(2000))
                    )
                )
                .execute()

            await refreshMessages(groupID)
            await refreshLeaderboard(groupID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshMessages(_ groupID: UUID) async {
        guard joinedGroupIDs.contains(groupID) else { return }

        do {
            let rows: [CommunityGroupMessageRecord] = try await client
                .from("community_group_messages")
                .select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: true)
                .limit(150)
                .execute()
                .value

            messagesByGroup[groupID] = rows
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func communityContentImagePath(
        groupID: UUID,
        kind: String,
        contentID: UUID
    ) -> String {
        "\(groupID.uuidString.lowercased())/" +
        "\(kind)/" +
        "\(contentID.uuidString.lowercased())/cover.jpg"
    }

    private func uploadCommunityContentImage(
        groupID: UUID,
        kind: String,
        contentID: UUID,
        jpegData: Data
    ) async throws -> String {
        guard jpegData.count <= 5_242_880 else {
            throw NSError(
                domain: "ATHLTH.Community",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Image must be smaller than 5 MB."
                ]
            )
        }

        let path = communityContentImagePath(
            groupID: groupID,
            kind: kind,
            contentID: contentID
        )

        try await client.storage
            .from("community-content-images")
            .upload(
                path: path,
                file: jpegData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        let publicURL = try client.storage
            .from("community-content-images")
            .getPublicURL(path: path)

        return publicURL.absoluteString
    }

    private func removeCommunityContentImage(
        groupID: UUID,
        kind: String,
        contentID: UUID
    ) async {
        let path = communityContentImagePath(
            groupID: groupID,
            kind: kind,
            contentID: contentID
        )

        try? await client.storage
            .from("community-content-images")
            .remove(paths: [path])
    }

    private func saveContentHosts(
        groupID: UUID,
        contentType: String,
        contentID: UUID,
        cohostIDs: [UUID]
    ) async throws {
        let unique = Array(Set(cohostIDs))
        guard !unique.isEmpty else {
            return
        }

        let payload = unique.map {
            CommunityGroupContentHostInsert(
                groupID: groupID,
                contentType: contentType,
                contentID: contentID,
                userID: $0
            )
        }

        try await client
            .from("community_group_content_hosts")
            .insert(payload)
            .execute()
    }

    func createEvent(
        groupID: UUID,
        title: String,
        summary: String,
        activityType: String,
        startsAt: Date,
        meetingName: String,
        imageData: Data? = nil,
        activityConfiguration:
            CommunityGroupActivityConfiguration? = nil,
        advancedOptions:
            CommunityGroupEventAdvancedOptions =
                CommunityGroupEventAdvancedOptions(),
        cohostIDs: [UUID] = []
    ) async -> Bool {
        guard currentUserID != nil,
              let group = group(for: groupID),
              canCreateGroupContent(group)
        else {
            errorMessage =
                "You do not have permission to create group events."
            return false
        }

        let cleanTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let cleanMeet = meetingName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanTitle.isEmpty else {
            errorMessage = "Add an event title."
            return false
        }

        let eventID = UUID()
        var uploadedImage = false

        do {
            let imageURL: String?
            if let imageData {
                imageURL = try await uploadCommunityContentImage(
                    groupID: groupID,
                    kind: "events",
                    contentID: eventID,
                    jpegData: imageData
                )
                uploadedImage = true
            } else {
                imageURL = nil
            }

            try await client
                .rpc(
                    "create_community_group_event_v2",
                    params:
                        CommunityGroupEventCreateV2Params(
                            id: eventID,
                            groupID: groupID,
                            title: String(
                                cleanTitle.prefix(160)
                            ),
                            summary: String(
                                summary.prefix(1200)
                            ),
                            activityType: activityType,
                            startsAt: startsAt,
                            meetingName: String(
                                cleanMeet.prefix(180)
                            ),
                            imageURL: imageURL,
                            activityConfiguration:
                                activityConfiguration,
                            options: advancedOptions
                        )
                )
                .execute()

            try await saveContentHosts(
                groupID: groupID,
                contentType: "event",
                contentID: eventID,
                cohostIDs: cohostIDs
            )

            errorMessage = nil
            await loadGroupContent(groupID)
            mergeGroupActivityIntoCommunityFeed(
                groupID
            )
            return true
        } catch {
            if uploadedImage {
                await removeCommunityContentImage(
                    groupID: groupID,
                    kind: "events",
                    contentID: eventID
                )
            }

            errorMessage = error.localizedDescription
            return false
        }
    }

    func createChallenge(
        groupID: UUID,
        title: String,
        summary: String,
        metric: CommunityGroupChallengeMetric,
        targetValue: Double,
        startsAt: Date,
        endsAt: Date,
        imageData: Data? = nil,
        activityConfiguration:
            CommunityGroupActivityConfiguration? = nil,
        advancedOptions:
            CommunityGroupChallengeAdvancedOptions =
                CommunityGroupChallengeAdvancedOptions(),
        cohostIDs: [UUID] = []
    ) async -> Bool {
        guard currentUserID != nil,
              let group = group(for: groupID),
              canCreateGroupContent(group),
              targetValue > 0,
              endsAt > startsAt
        else {
            errorMessage =
                "Check the challenge details and your group permissions."
            return false
        }

        let cleanTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanTitle.isEmpty else {
            errorMessage = "Give the challenge a title."
            return false
        }

        let challengeID = UUID()
        var uploadedImage = false

        do {
            let imageURL: String?
            if let imageData {
                imageURL = try await uploadCommunityContentImage(
                    groupID: groupID,
                    kind: "challenges",
                    contentID: challengeID,
                    jpegData: imageData
                )
                uploadedImage = true
            } else {
                imageURL = nil
            }

            try await client
                .rpc(
                    "create_community_group_challenge_v2",
                    params:
                        CommunityGroupChallengeCreateV2Params(
                            id: challengeID,
                            groupID: groupID,
                            title: String(
                                cleanTitle.prefix(160)
                            ),
                            summary: String(
                                summary.prefix(800)
                            ),
                            metric: metric.rawValue,
                            targetValue: targetValue,
                            startsAt: startsAt,
                            endsAt: endsAt,
                            imageURL: imageURL,
                            activityConfiguration:
                                activityConfiguration,
                            options: advancedOptions
                        )
                )
                .execute()

            try await saveContentHosts(
                groupID: groupID,
                contentType: "challenge",
                contentID: challengeID,
                cohostIDs: cohostIDs
            )

            errorMessage = nil
            await loadGroupContent(groupID)
            mergeGroupActivityIntoCommunityFeed(
                groupID
            )
            return true
        } catch {
            if uploadedImage {
                await removeCommunityContentImage(
                    groupID: groupID,
                    kind: "challenges",
                    contentID: challengeID
                )
            }

            errorMessage = error.localizedDescription
            return false
        }
    }

    private func challengeMatchesWorkout(
        _ challenge: CommunityGroupChallengeRecord,
        workout: SocialPublishableWorkout
    ) -> Bool {
        guard let configuration =
            challenge.activityConfiguration
        else {
            return true
        }

        switch configuration.activityType {
        case "running":
            return workout.activity == .running
        case "walking":
            return workout.activity == .walking
        case "cycling":
            return workout.activity == .cycling
        case "strength":
            return workout.activity == .strength
        default:
            return true
        }
    }

    func recordCompletedWorkout(
        _ workout: SocialPublishableWorkout
    ) async {
        guard let userID = currentUserID,
              !joinedGroupIDs.isEmpty
        else {
            return
        }

        do {
            do {
                try await client
                    .rpc(
                        "record_community_group_workout",
                        params:
                            CommunityGroupWorkoutActivityParams(
                                workoutID: workout.id,
                                completedAt: workout.endDate
                            )
                    )
                    .execute()
            } catch {
                // Club leaderboard tracking is additive and must never
                // block existing challenge workout processing.
            }

            let activeChallenges: [CommunityGroupChallengeRecord] =
                try await client
                    .from("community_group_challenges")
                    .select()
                    .lte(
                        "starts_at",
                        value: workout.endDate
                    )
                    .gte(
                        "ends_at",
                        value: workout.startDate
                    )
                    .neq("status", value: "cancelled")
                    .execute()
                    .value

            guard !activeChallenges.isEmpty else {
                return
            }

            let participations:
                [CommunityGroupChallengeParticipantRecord] =
                    try await client
                        .from(
                            "community_group_challenge_participants"
                        )
                        .select()
                        .eq("user_id", value: userID)
                        .execute()
                        .value

            let joinedChallengeIDs = Set(
                participations
                    .filter { $0.status == "joined" }
                    .map(\.challengeID)
            )

            let existingAttempts:
                [CommunityGroupChallengeWorkoutRecord] =
                    try await client
                        .from(
                            "community_group_challenge_workouts"
                        )
                        .select()
                        .eq("user_id", value: userID)
                        .execute()
                        .value

            var writes:
                [CommunityGroupChallengeWorkoutInsert] = []

            for challenge in activeChallenges {
                guard challengeMatchesWorkout(
                    challenge,
                    workout: workout
                ) else {
                    continue
                }

                if challenge.joinRequired &&
                    !joinedChallengeIDs.contains(
                        challenge.id
                    ) {
                    continue
                }

                if let limit = challenge.attemptLimit {
                    let attemptCount =
                        existingAttempts.filter {
                            $0.challengeID ==
                                challenge.id
                        }.count

                    if attemptCount >= limit {
                        continue
                    }
                }

                var contribution: Double

                switch challenge.metric {
                case .distanceKM:
                    contribution =
                        (workout.distanceMeters ?? 0) /
                        1_000

                case .workouts:
                    contribution = 1

                case .activeMinutes:
                    contribution = max(
                        workout.duration / 60,
                        0
                    )

                case .fastestTime:
                    let targetMeters =
                        challenge
                            .activityConfiguration?
                            .distanceKilometers
                            .map { $0 * 1_000 }

                    if let targetMeters,
                       let verifiedDuration =
                        await HealthKitManager.shared
                            .groupChallengeFastestSegmentDuration(
                                workoutID: workout.id,
                                targetDistanceMeters:
                                    targetMeters
                            ) {
                        contribution = verifiedDuration
                    } else if let targetMeters,
                              (workout.distanceMeters ?? 0) >=
                                targetMeters {
                        contribution = workout.duration
                    } else if targetMeters == nil {
                        contribution = workout.duration
                    } else {
                        continue
                    }
               

                case .strengthVolume:
                    contribution =
                        workout
                            .strengthTotalVolumeKilograms
                            ?? 0

                case .heaviestWeight:
                    contribution =
                        workout
                            .strengthHeaviestWeightKilograms
                            ?? 0

                case .strengthReps:
                    contribution =
                        Double(
                            workout.strengthTotalReps
                            ?? 0
                        )
                }

                guard contribution > 0 else {
                    continue
                }

                var routeMatch: Double?
                var verificationStatus =
                    "not_required"

                if challenge
                    .routeVerificationEnabled {
                    guard let route =
                        challenge
                            .activityConfiguration?
                            .route
                    else {
                        verificationStatus =
                            "unverified"
                        writes.append(
                            CommunityGroupChallengeWorkoutInsert(
                                challengeID:
                                    challenge.id,
                                userID: userID,
                                workoutID: workout.id,
                                contribution:
                                    contribution,
                                routeMatchPercent: nil,
                                verificationStatus:
                                    verificationStatus
                            )
                        )
                        continue
                    }

                    routeMatch =
                        await HealthKitManager.shared
                            .groupChallengeRouteMatchPercent(
                                workoutID: workout.id,
                                referenceCoordinates:
                                    route.coordinates,
                                toleranceMeters:
                                    Double(
                                        challenge
                                            .routeToleranceMeters
                                    )
                            )

                    verificationStatus =
                        (routeMatch ?? 0) >= 90
                            ? "verified"
                            : "unverified"
                }

                writes.append(
                    CommunityGroupChallengeWorkoutInsert(
                        challengeID: challenge.id,
                        userID: userID,
                        workoutID: workout.id,
                        contribution: contribution,
                        routeMatchPercent:
                            routeMatch,
                        verificationStatus:
                            verificationStatus
                    )
                )
            }

            guard !writes.isEmpty else {
                return
            }

            try await client
                .from(
                    "community_group_challenge_workouts"
                )
                .upsert(
                    writes,
                    onConflict:
                        "challenge_id,user_id,workout_id"
                )
                .execute()

            for challenge in activeChallenges
            where writes.contains(
                where: {
                    $0.challengeID == challenge.id
                }
            ) {
                await loadGroupContent(
                    challenge.groupID
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum CommunityGroupsTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case chat = "Chat"
    case events = "Events"
    case challenges = "Challenges"

    var id: String { rawValue }
}

struct CommunityGroupsView: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    @State private var query = ""
    @State private var showingCreate = false

    private var matchingGroups: [CommunityGroupRecord] {
        let publicGroups = groups.groups.filter {
            $0.visibility == "public" &&
            !groups.joinedGroupIDs.contains($0.id) &&
            groups.pendingInvite(for: $0.id) == nil
        }

        let clean = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !clean.isEmpty else {
            return publicGroups
        }

        return publicGroups.filter {
            $0.name.lowercased().contains(clean) ||
            $0.locationName.lowercased().contains(clean) ||
            $0.summary.lowercased().contains(clean)
        }
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent: Color.indigo.opacity(0.34)
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    publicGroupSearchBar
                    introCard

                    if !groups.ownInvites.isEmpty {
                        sectionTitle("INVITATIONS")
                        ForEach(
                            groups.ownInvites,
                            id: \.groupID
                        ) { invite in
                            if let group = groups.group(
                                for: invite.groupID
                            ) {
                                invitationCard(
                                    invite,
                                    group: group
                                )
                            }
                        }
                    }

                    if !groups.joinedGroups.isEmpty {
                        sectionTitle("YOUR GROUPS")
                        ForEach(groups.joinedGroups) { group in
                            groupLink(group, joined: true)
                        }
                    }

                    sectionTitle("DISCOVER PUBLIC GROUPS")
                    if matchingGroups.isEmpty {
                        ContentUnavailableView(
                            "No groups found",
                            systemImage: "person.3",
                            description: Text(
                                "Create a group for your city, area or training community."
                            )
                        )
                        .padding(.vertical, 36)
                    } else {
                        ForEach(matchingGroups) { group in
                            groupLink(group, joined: false)
                        }

                        if groups.canLoadMoreGroups {
                            Button {
                                Task {
                                    await groups.loadMoreGroups()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if groups.isLoadingMoreGroups {
                                        ProgressView()
                                            .controlSize(.small)
                                    }

                                    Text(
                                        groups.isLoadingMoreGroups
                                            ? "Loading more clubs…"
                                            : "Load more clubs"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.bordered)
                            .disabled(groups.isLoadingMoreGroups)
                            .padding(.top, 6)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Clubs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create group")
            }
        }
        .sheet(isPresented: $showingCreate) {
            CommunityGroupCreateView()
        }
        .task {
            await groups.refresh()
        }
        .refreshable {
            await groups.refresh()
        }
    }

    private var publicGroupSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)

            TextField(
                "Search public groups",
                text: $query
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(
                            ATHLTHTheme.mutedText.opacity(0.72)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear group search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(
            Color.white.opacity(0.82),
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border.opacity(0.72),
                lineWidth: 1
            )
        }
    }

    private var introCard: some View {
        ATHLTHCard {
            HStack(spacing: 14) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 48, height: 48)
                    .background(
                        Color.indigo.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 15)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Train with your community")
                        .font(.headline)
                    Text(
                        "Find public groups, train together and take on shared challenges."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private func invitationCard(
        _ invite: CommunityGroupInviteRecord,
        group: CommunityGroupRecord
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 12) {
                groupImage(
                    group,
                    size: 46,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.subheadline.weight(.semibold))
                    Text("You were invited to join")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button("Decline") {
                    Task {
                        _ = await groups.respondToInvite(
                            groupID: invite.groupID,
                            accept: false
                        )
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Join") {
                    Task {
                        _ = await groups.respondToInvite(
                            groupID: invite.groupID,
                            accept: true
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 10)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(1.7)
            .foregroundStyle(ATHLTHTheme.mutedText)
    }

    @ViewBuilder
    private func groupImage(
        _ group: CommunityGroupRecord,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        if let value = group.imageURL,
           let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    groupImageFallback
                }
            }
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
        } else {
            groupImageFallback
                .frame(width: size, height: size)
        }
    }

    private var groupImageFallback: some View {
        Image(systemName: "person.3.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.indigo)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.indigo.opacity(0.09),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
    }

    private func groupLink(
        _ group: CommunityGroupRecord,
        joined: Bool
    ) -> some View {
        NavigationLink {
            CommunityGroupDetailView(group: group)
        } label: {
            HStack(spacing: 13) {
                groupImage(
                    group,
                    size: 46,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !group.locationName
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty {
                        Label(
                            group.locationName,
                            systemImage: "location.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Label(
                        group.visibility == "private"
                            ? "Private"
                            : "Public",
                        systemImage:
                            group.visibility == "private"
                                ? "lock.fill"
                                : "globe"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        group.visibility == "private"
                            ? ATHLTHTheme.mutedText
                            : ATHLTHTheme.accentDeep
                    )
                }

                Spacer()

                if joined {
                    Text("Joined")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .background(
                ATHLTHTheme.card,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CommunityGroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var session: AppSessionStore

    let group: CommunityGroupRecord

    @State private var selectedTab: CommunityGroupsTab = .overview
    @State private var messageDraft = ""
    @State private var showingCreateEvent = false
    @State private var showingCreateChallenge = false
    @State private var showingGroupSettings = false
    @State private var showingNotificationSettings = false
    @State private var updateDraft = ""
    @State private var postingUpdate = false

    private var currentGroup: CommunityGroupRecord {
        groups.groups.first {
            $0.id == group.id
        } ?? group
    }

    private var isMember: Bool {
        groups.joinedGroupIDs.contains(group.id)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ATHLTHPremiumCanvas(
                    accent: Color.indigo.opacity(0.30)
                )

                if isMember && selectedTab == .chat {
                    VStack(spacing: 0) {
                        groupHeader(
                            topInset:
                                geometry.safeAreaInsets.top
                        )

                        groupAreaPicker
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(
                                ATHLTHTheme.canvasTop
                                    .opacity(0.96)
                            )

                        Divider()
                            .opacity(0.55)

                        chat
                            .frame(maxHeight: .infinity)
                    }
                    .ignoresSafeArea(edges: .top)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            groupHeader(
                                topInset:
                                    geometry.safeAreaInsets.top
                            )

                            VStack(spacing: 16) {
                                if isMember {
                                    groupAreaPicker

                                    switch selectedTab {
                                    case .overview:
                                        overview
                                    case .chat:
                                        EmptyView()
                                    case .events:
                                        events
                                    case .challenges:
                                        challenges
                                    }
                                } else {
                                    membershipAccessCard
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 30)
                            .frame(maxWidth: 760)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingCreateEvent) {
            CommunityGroupEventCreateView(
                group: currentGroup
            )
        }
        .sheet(isPresented: $showingCreateChallenge) {
            CommunityGroupChallengeCreateView(
                group: currentGroup
            )
        }
        .sheet(isPresented: $showingGroupSettings) {
            CommunityGroupSettingsView(
                group: currentGroup
            )
        }
        .sheet(isPresented: $showingNotificationSettings) {
            CommunityGroupNotificationSettingsView(
                group: currentGroup
            )
        }
        .task {
            if groups.groups.isEmpty {
                await groups.refresh()
            }

            if isMember ||
                currentGroup.creatorID ==
                    session.profile.userID {
                await groups.loadGroupContent(
                    group.id
                )
            }
        }
        .onChange(
            of: groups.groups.map(\.id)
        ) { _, groupIDs in
            if !groupIDs.contains(group.id) {
                dismiss()
            }
        }
    }

    private var groupAreaPicker: some View {
        Picker(
            "Group area",
            selection: $selectedTab
        ) {
            ForEach(CommunityGroupsTab.allCases) {
                Text($0.rawValue)
                    .tag($0)
            }
        }
        .pickerStyle(.segmented)
    }

    private var membershipAccessCard: some View {
        ATHLTHCard {
            if groups.pendingInvite(
                for: currentGroup.id
            ) != nil {
                Text("You have a group invitation")
                    .font(.headline)
                Text(
                    "Accept the invitation to unlock chat, events and challenges."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 3)

                HStack(spacing: 10) {
                    Button("Decline") {
                        Task {
                            _ = await groups.respondToInvite(
                                groupID: currentGroup.id,
                                accept: false
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Join Group") {
                        Task {
                            _ = await groups.respondToInvite(
                                groupID: currentGroup.id,
                                accept: true
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 12)
            } else if groups.pendingJoinRequest(
                for: currentGroup.id
            ) != nil {
                Label(
                    "Membership request pending",
                    systemImage: "clock.fill"
                )
                .font(.headline)

                Text(
                    "An Owner or Admin can approve your request."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            } else if currentGroup.joinMode == "invite_only" {
                Label(
                    "Invitation required",
                    systemImage: "envelope.badge"
                )
                .font(.headline)

                Text(
                    "This group only accepts members who have been invited by an Owner or Admin."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            } else {
                Text(
                    currentGroup.joinMode == "approval"
                        ? "Request membership to unlock group chat, events and challenges."
                        : "Join to unlock group chat, events and challenges."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button {
                    Task {
                        _ = await groups.requestJoin(
                            currentGroup
                        )
                    }
                } label: {
                    Label(
                        currentGroup.joinMode == "approval"
                            ? "Request to Join"
                            : "Join Group",
                        systemImage:
                            currentGroup.joinMode == "approval"
                                ? "person.badge.clock"
                                : "person.badge.plus"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                .padding(.top, 8)
            }
        }
    }

    private func groupHeader(
        topInset: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            groupHeroBackground

            LinearGradient(
                colors: [
                    Color.white.opacity(
                        currentGroup.imageURL == nil
                            ? 0.18
                            : 0.92
                    ),
                    ATHLTHTheme.cardWarm.opacity(
                        currentGroup.imageURL == nil
                            ? 0.16
                            : 0.72
                    ),
                    ATHLTHTheme.cardWarm.opacity(
                        currentGroup.imageURL == nil
                            ? 0.08
                            : 0.22
                    )
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    ATHLTHTheme.canvasBottom.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 14) {
                if groups.canManage(currentGroup) {
                    Button {
                        showingGroupSettings = true
                    } label: {
                        detailGroupImage
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil")
                                    .font(
                                        .system(
                                            size: 10,
                                            weight: .bold
                                        )
                                    )
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        ATHLTHTheme.accentDeep,
                                        in: Circle()
                                    )
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                Color.white,
                                                lineWidth: 2
                                            )
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change Club photo")
                } else {
                    detailGroupImage
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("CLUB")
                        .font(.caption2.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep.opacity(0.62)
                        )

                    Text(currentGroup.name)
                        .font(
                            .system(
                                size: 27,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    if !currentGroup.summary
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty {
                        Text(currentGroup.summary)
                            .font(.subheadline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText.opacity(0.72)
                            )
                            .lineLimit(2)
                    }

                    HStack(spacing: 10) {
                        if !currentGroup.locationName
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty {
                            Label(
                                currentGroup.locationName,
                                systemImage: "location.fill"
                            )
                        }

                        Label(
                            currentGroup.visibility == "private"
                                ? "Private"
                                : "Public",
                            systemImage:
                                currentGroup.visibility == "private"
                                    ? "lock.fill"
                                    : "globe"
                        )

                        if isMember ||
                            currentGroup.creatorID ==
                                session.profile.userID {
                            Text(memberCountText)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer(minLength: 8)

                if isMember ||
                    currentGroup.creatorID ==
                        session.profile.userID {
                    HStack(spacing: 8) {
                        NavigationLink {
                            CommunityGroupMembersView(
                                group: currentGroup
                            )
                        } label: {
                            Image(
                                systemName: "person.2.fill"
                            )
                            .font(
                                .system(
                                    size: 14,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                Color.white.opacity(0.70),
                                in: Circle()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Members, \(memberCountText)"
                        )

                        if groups.canManage(currentGroup) {
                            Menu {
                                Button {
                                    showingGroupSettings = true
                                } label: {
                                    Label(
                                        "Club Settings",
                                        systemImage: "gearshape"
                                    )
                                }

                                Button {
                                    showingNotificationSettings =
                                        true
                                } label: {
                                    Label(
                                        "Notifications",
                                        systemImage: "bell"
                                    )
                                }

                                if !groups.isOwner(
                                    of: currentGroup
                                ) {
                                    Button(
                                        "Leave Club",
                                        role: .destructive
                                    ) {
                                        Task {
                                            await groups.leave(
                                                currentGroup
                                            )
                                        }
                                    }
                                }
                            } label: {
                                groupMenuButton
                            }
                        } else {
                            Menu {
                                Button {
                                    showingNotificationSettings =
                                        true
                                } label: {
                                    Label(
                                        "Notifications",
                                        systemImage: "bell"
                                    )
                                }

                                Button(
                                    "Leave Club",
                                    role: .destructive
                                ) {
                                    Task {
                                        await groups.leave(
                                            currentGroup
                                        )
                                    }
                                }
                            } label: {
                                groupMenuButton
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(
                                .system(
                                    size: 14,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                            .frame(width: 38, height: 38)
                            .background(
                                Color.white.opacity(0.76),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.88),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(
                    .top,
                    max(topInset + 8, 18)
                )

                Spacer()
            }
        }
        .frame(
            height: 224 + max(topInset, 0)
        )
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.58))
                .frame(height: 1)
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.07),
            radius: 18,
            x: 0,
            y: 8
        )
    }

    @ViewBuilder
    private var groupHeroBackground: some View {
        if let value = currentGroup.imageURL,
           let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                        .clipped()
                default:
                    groupHeroFallback
                }
            }
        } else {
            groupHeroFallback
        }
    }

    private var groupHeroFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.24),
                    ATHLTHTheme.cardWarm.opacity(0.92),
                    ATHLTHTheme.canvasTop
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.30))
                .frame(width: 190, height: 190)
                .offset(x: 230, y: -74)
        }
    }

    private var groupMenuButton: some View {
        Image(systemName: "ellipsis")
            .font(
                .system(
                    size: 16,
                    weight: .bold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
            .frame(width: 36, height: 36)
            .background(
                Color.white.opacity(0.56),
                in: Circle()
            )
    }

    @ViewBuilder
    private var detailGroupImage: some View {
        Group {
            if let value = currentGroup.imageURL,
               let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        detailGroupImageFallback
                    }
                }
            } else {
                detailGroupImageFallback
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.92), lineWidth: 2)
        }
    }

    private var detailGroupImageFallback: some View {
        Image(systemName: "person.3.fill")
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(.indigo)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.indigo.opacity(0.10)
            )
    }

    private var memberCountText: String {
        let count = groups.members(in: group.id).count
        return count == 1
            ? "1 member"
            : "\(count) members"
    }

    private var overview: some View {
        VStack(spacing: 16) {
            if groups.canPublishUpdates(currentGroup) {
                groupUpdateComposer
            }

            let pinned = groups.pinnedAnnouncement(
                in: group.id
            )

            if let pinned {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        "Pinned Post",
                        systemImage: "pin.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(.horizontal, 4)

                    groupUpdateCard(
                        pinned,
                        isPinned: true
                    )
                }
            }

            let updates = groups.announcements(
                in: group.id
            ).filter {
                $0.id != pinned?.id
            }

            if !updates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Club Posts")
                        .font(.headline)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(.horizontal, 4)

                    ForEach(updates) { update in
                        groupUpdateCard(update)
                    }
                }
            }

            comingUpCard
            recentGroupActivityCard

            clubLeaderboardCard
        }
    }

    private var clubLeaderboardCard: some View {
        let entries = groups.leaderboard(
            in: group.id
        )

        return ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Club Leaderboard")
                        .font(.title3.weight(.bold))
                    Text(
                        "Last 7 days · training, participation and Club activity."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if entries.isEmpty {
                Text(
                    "Leaderboard activity will appear as members train and take part in the Club."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(
                            entries
                                .prefix(5)
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, entry in
                        HStack(spacing: 11) {
                            Text("\(index + 1)")
                                .font(
                                    .caption
                                        .weight(.bold)
                                )
                                .frame(
                                    width: 30,
                                    height: 30
                                )
                                .background(
                                    index < 3
                                        ? ATHLTHTheme.accent
                                            .opacity(0.14)
                                        : Color.secondary
                                            .opacity(0.08),
                                    in: Circle()
                                )

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                HStack(spacing: 6) {
                                    Text(
                                        leaderboardDisplayName(
                                            for: entry.userID
                                        )
                                    )
                                    .font(
                                        .subheadline
                                            .weight(.semibold)
                                    )

                                    if entry.userID ==
                                        session.profile.userID {
                                        Text("You")
                                            .font(
                                                .caption2
                                                    .weight(.bold)
                                            )
                                            .foregroundStyle(
                                                ATHLTHTheme
                                                    .accentDeep
                                            )
                                    }
                                }

                                Text(
                                    leaderboardActivitySummary(
                                        entry
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }

                            Spacer(minLength: 8)

                            Text(
                                "\(entry.score) pts"
                            )
                            .font(
                                .subheadline
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                        }
                        .padding(.vertical, 9)

                        if entry.id !=
                            entries.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 41)
                        }
                    }
                }
                .padding(.top, 8)
            }

            Text(
                "Scoring: workouts, events and challenges +5. Chat and likes +1, capped at 5 per day each."
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 10)
        }
    }

    private func leaderboardDisplayName(
        for userID: UUID
    ) -> String {
        guard let profile = groups.profileCard(
            for: userID
        ) else {
            return "Club member"
        }

        return profile.usernameLabel.isEmpty
            ? profile.resolvedName
            : profile.usernameLabel
    }

    private func leaderboardActivitySummary(
        _ entry: CommunityGroupEngagementLeaderboardEntry
    ) -> String {
        var parts: [String] = []

        if entry.workoutCount > 0 {
            parts.append(
                "\(entry.workoutCount) workout" +
                (entry.workoutCount == 1 ? "" : "s")
            )
        }

        if entry.messageCount > 0 {
            parts.append(
                "\(entry.messageCount) chat"
            )
        }

        if entry.likesGiven > 0 {
            parts.append(
                "\(entry.likesGiven) like" +
                (entry.likesGiven == 1 ? "" : "s")
            )
        }

        if entry.eventsJoined > 0 {
            parts.append(
                "\(entry.eventsJoined) event" +
                (entry.eventsJoined == 1 ? "" : "s")
            )
        }

        if entry.challengesJoined > 0 {
            parts.append(
                "\(entry.challengesJoined) challenge" +
                (entry.challengesJoined == 1
                    ? ""
                    : "s")
            )
        }

        return parts.isEmpty
            ? "No activity yet"
            : parts.joined(separator: " · ")
    }

    private var groupUpdateComposer: some View {
        ATHLTHCard {
            HStack(spacing: 9) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.indigo.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Club Post")
                        .font(.subheadline.weight(.semibold))
                    Text("Visible to every group member")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "Share a Club post…",
                    text: $updateDraft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )

                Button {
                    let body = updateDraft
                    updateDraft = ""

                    Task {
                        postingUpdate = true
                        let posted = await groups.postAnnouncement(
                            groupID: group.id,
                            body: body
                        )
                        postingUpdate = false

                        if !posted {
                            updateDraft = body
                        }
                    }
                } label: {
                    Group {
                        if postingUpdate {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentDeep,
                        in: Circle()
                    )
                }
                .disabled(
                    updateDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    updateDraft.count > 1200 ||
                    postingUpdate
                )
            }
            .padding(.top, 12)
        }
    }

    private var nextGroupEvent: CommunityGroupEventRecord? {
        let now = Date()

        return groups.events(in: group.id)
            .filter {
                $0.status != "draft" &&
                $0.status != "cancelled" &&
                $0.nextOccurrenceStart(
                    relativeTo: now
                ) != nil
            }
            .sorted {
                ($0.nextOccurrenceStart(
                    relativeTo: now
                ) ?? .distantFuture) <
                ($1.nextOccurrenceStart(
                    relativeTo: now
                ) ?? .distantFuture)
            }
            .first
    }

    private var nextGroupChallenge: CommunityGroupChallengeRecord? {
        let now = Date()

        return groups.challenges(in: group.id)
            .filter {
                $0.endsAt >= now &&
                $0.status != "draft" &&
                $0.status != "cancelled"
            }
            .sorted { lhs, rhs in
                let lhsActive =
                    lhs.startsAt <= now && lhs.endsAt >= now
                let rhsActive =
                    rhs.startsAt <= now && rhs.endsAt >= now

                if lhsActive != rhsActive {
                    return lhsActive
                }

                return lhs.startsAt < rhs.startsAt
            }
            .first
    }

    private var comingUpCard: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coming Up")
                        .font(.title3.weight(.bold))
                    Text("The next things happening in this group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if nextGroupEvent == nil &&
                nextGroupChallenge == nil {
                Text("No upcoming events or challenges yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    if let event = nextGroupEvent {
                        NavigationLink {
                            CommunityGroupEventDetailView(
                                group: currentGroup,
                                event: event
                            )
                        } label: {
                            comingUpRow(
                                icon: "calendar",
                                title: event.title,
                                detail:
                                    comingUpEventDetail(event),
                                tint: .purple
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if nextGroupEvent != nil &&
                        nextGroupChallenge != nil {
                        Divider()
                            .padding(.leading, 46)
                    }

                    if let challenge = nextGroupChallenge {
                        NavigationLink {
                            CommunityGroupChallengeDetailView(
                                group: currentGroup,
                                challenge: challenge
                            )
                        } label: {
                            comingUpRow(
                                icon: "bolt.fill",
                                title: challenge.title,
                                detail:
                                    comingUpChallengeDetail(
                                        challenge
                                    ),
                                tint: .green
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func comingUpEventDetail(
        _ event: CommunityGroupEventRecord
    ) -> String {
        let nextStart =
            event.nextOccurrenceStart()
            ?? event.startsAt

        var parts = [
            nextStart.formatted(
                date: .abbreviated,
                time: .shortened
            ),
            event.meetingName
        ]

        let going = groups.eventRSVPCount(
            eventID: event.id,
            status: "going"
        )

        if going > 0 {
            parts.append("\(going) going")
        }

        return parts
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func comingUpChallengeDetail(
        _ challenge: CommunityGroupChallengeRecord
    ) -> String {
        let timing =
            challenge.startsAt <= Date()
                ? "Active now · ends " +
                    challenge.endsAt.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                : "Starts " +
                    challenge.startsAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )

        guard challenge.targetValue > 0 else {
            return timing
        }

        let progress = groups.challengeProgress(
            challenge
        )
        let fraction = min(
            max(
                progress / challenge.targetValue,
                0
            ),
            1
        )

        return timing +
            " · " +
            String(
                format: "%.0f%% complete",
                fraction * 100
            )
    }

    private var recentGroupActivityCard: some View {
        let items = Array(
            groups.activity(in: group.id)
                .filter { $0.kind != "announcement" }
                .prefix(4)
        )

        return ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Activity")
                        .font(.title3.weight(.bold))
                    Text(
                        "What has changed in the group lately."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if items.isEmpty {
                Text(
                    "New members, events and challenges will appear here."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        recentActivityRow(item)

                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func recentActivityRow(
        _ item: CommunityGroupActivityRecord
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName:
                    recentActivityIcon(item.kind)
            )
            .font(
                .system(
                    size: 14,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                recentActivityTint(item.kind)
            )
            .frame(width: 34, height: 34)
            .background(
                recentActivityTint(item.kind)
                    .opacity(0.10),
                in: RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.headline)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                if let detail = item.detail,
                   !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    if let actorID = item.actorID,
                       let actor = groups.profileCard(
                           for: actorID
                       ) {
                        Text(
                            actor.usernameLabel.isEmpty
                                ? actor.resolvedName
                                : actor.usernameLabel
                        )
                    }

                    Text(
                        item.createdAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 9)
    }

    private func recentActivityIcon(
        _ kind: String
    ) -> String {
        switch kind {
        case "member_joined":
            return "person.badge.plus"
        case "announcement":
            return "megaphone.fill"
        case "event_created":
            return "calendar.badge.plus"
        case "challenge_created":
            return "bolt.fill"
        default:
            return "bell.fill"
        }
    }

    private func recentActivityTint(
        _ kind: String
    ) -> Color {
        switch kind {
        case "member_joined":
            return .indigo
        case "announcement":
            return .orange
        case "event_created":
            return .purple
        case "challenge_created":
            return .green
        default:
            return ATHLTHTheme.accent
        }
    }

    private func comingUpRow(
        icon: String,
        title: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
    }

    private func groupUpdateCard(
        _ update: CommunityGroupAnnouncementRecord,
        isPinned: Bool = false
    ) -> some View {
        let likeCount = groups.announcementLikeCount(
            update.id,
            in: group.id
        )
        let liked = groups.hasLikedAnnouncement(
            update.id,
            in: group.id
        )

        return ATHLTHCard {
            HStack {
                Label(
                    isPinned
                        ? "Pinned Post"
                        : "Club Post",
                    systemImage:
                        isPinned
                            ? "pin.fill"
                            : "megaphone.fill"
                )
                .font(.headline)
                .foregroundStyle(
                    isPinned
                        ? ATHLTHTheme.accentDeep
                        : .indigo
                )

                Spacer()

                if groups.canPublishUpdates(currentGroup) {
                    Menu {
                        Button {
                            Task {
                                _ = await groups.pinAnnouncement(
                                    groupID: group.id,
                                    announcementID:
                                        isPinned
                                            ? nil
                                            : update.id
                                )
                            }
                        } label: {
                            Label(
                                isPinned
                                    ? "Unpin Post"
                                    : "Pin Post",
                                systemImage:
                                    isPinned
                                        ? "pin.slash"
                                        : "pin"
                            )
                        }

                        if groups.canManage(currentGroup) {
                            Button(
                                "Delete Post",
                                role: .destructive
                            ) {
                                Task {
                                    _ = await groups.deleteAnnouncement(
                                        groupID: group.id,
                                        announcementID: update.id
                                    )
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 30, height: 30)
                    }
                }

                Text(
                    update.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Text(update.body)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.primaryText)
                .padding(.top, 6)

            if let author = groups.profileCard(
                for: update.authorID
            ) {
                Text(
                    author.username
                        .flatMap { value in
                            let clean = value.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            return clean.isEmpty
                                ? nil
                                : "Posted by @\(clean)"
                        }
                        ?? "Posted by \(author.resolvedName)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            Button {
                Task {
                    _ = await groups
                        .toggleAnnouncementLike(
                            groupID: group.id,
                            announcementID: update.id
                        )
                }
            } label: {
                Label(
                    likeCount == 0
                        ? "Like"
                        : "\(likeCount)",
                    systemImage:
                        liked
                            ? "hand.thumbsup.fill"
                            : "hand.thumbsup"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    liked
                        ? ATHLTHTheme.accentDeep
                        : .secondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    liked
                        ? ATHLTHTheme.accent
                            .opacity(0.12)
                        : Color.secondary
                            .opacity(0.07),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                liked
                    ? "Remove thumbs up"
                    : "Give thumbs up"
            )
            .padding(.top, 9)
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            let messages = groups.messages(
                in: group.id
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            ContentUnavailableView(
                                "No messages yet",
                                systemImage:
                                    "bubble.left.and.bubble.right",
                                description: Text(
                                    "Start the Club conversation."
                                )
                            )
                            .padding(.top, 70)
                        } else {
                            ForEach(messages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .background(
                    Color.white.opacity(0.48)
                )
                .frame(maxHeight: .infinity)
                .onChange(
                    of: messages.count
                ) { _, _ in
                    guard let last = messages.last else {
                        return
                    }

                    withAnimation(
                        .easeOut(duration: 0.18)
                    ) {
                        proxy.scrollTo(
                            last.id,
                            anchor: .bottom
                        )
                    }
                }
                .task {
                    guard let last = messages.last else {
                        return
                    }

                    proxy.scrollTo(
                        last.id,
                        anchor: .bottom
                    )
                }
            }

            if !groupMentionSuggestions.isEmpty {
                ATHLTHMentionSuggestionList(
                    suggestions:
                        groupMentionSuggestions
                ) { suggestion in
                    messageDraft =
                        ATHLTHMentionSupport.inserting(
                            suggestion,
                            into: messageDraft
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(.ultraThinMaterial)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "Message Club",
                    text: $messageDraft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit {
                    Task {
                        await sendGroupMessage()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color.white.opacity(0.86),
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .stroke(
                        ATHLTHTheme.border.opacity(0.82),
                        lineWidth: 1
                    )
                }

                Button {
                    Task {
                        await sendGroupMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(
                            .system(
                                size: 16,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            ATHLTHTheme.accentDeep,
                            in: Circle()
                        )
                }
                .disabled(
                    messageDraft
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
                    .opacity(0.55)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: selectedTab) {
            guard selectedTab == .chat else {
                return
            }

            while !Task.isCancelled {
                await groups.refreshMessages(
                    group.id
                )
                try? await Task.sleep(
                    for: .seconds(5)
                )
            }
        }
    }

    private func sendGroupMessage() async {
        let body = messageDraft
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !body.isEmpty else {
            return
        }

        messageDraft = ""

        let sent = await groups.sendMessage(
            groupID: group.id,
            senderName:
                session.profile.username.isEmpty
                    ? session.profile.displayName
                    : "@\(session.profile.username)",
            body: body
        )

        if !sent {
            messageDraft = body
        }
    }

    private var groupMentionSuggestions:
        [ATHLTHMentionSuggestion] {
        let candidates = groups.mentionCandidates(
            in: group.id
        ).filter {
            $0.userID != session.profile.userID
        }

        let role = groups.role(in: currentGroup)

        return ATHLTHMentionSupport.suggestions(
            in: messageDraft,
            candidates: candidates,
            includeEveryone:
                role == "owner" ||
                role == "admin" ||
                role == "contributor"
        )
    }

    private var visibleGroupEvents:
        [CommunityGroupEventRecord] {
        groups.events(in: group.id).filter {
            event in

            event.status != "draft" ||
            groups.canManage(currentGroup) ||
            event.creatorID ==
                session.profile.userID
        }
    }

    private var events: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Group Events")
                        .font(.title3.weight(.bold))
                    Text(
                        groups.canCreateGroupContent(
                            currentGroup
                        )
                            ? "Plan meetups and training sessions with the group."
                            : "Only members allowed by the group settings can create events."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if groups.canCreateGroupContent(
                    currentGroup
                ) {
                    Button {
                        showingCreateEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if visibleGroupEvents.isEmpty {
                ContentUnavailableView(
                    "No group events",
                    systemImage: "calendar.badge.plus",
                    description: Text(
                        groups.canCreateGroupContent(
                            currentGroup
                        )
                            ? "Create the first event for this group."
                            : "No events have been scheduled yet."
                    )
                )
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        visibleGroupEvents
                    ) { event in
                        NavigationLink {
                            CommunityGroupEventDetailView(
                                group: currentGroup,
                                event: event
                            )
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 10
                            ) {
                                if let imageURL =
                                    event.imageURL,
                                   !imageURL.isEmpty {
                                    communityContentCover(
                                        imageURL,
                                        height: 140
                                    )
                                }

                                HStack(spacing: 12) {
                                    Image(
                                        systemName:
                                            eventIcon(
                                                event
                                                    .activityType
                                            )
                                    )
                                    .foregroundStyle(.purple)
                                    .frame(
                                        width: 38,
                                        height: 38
                                    )
                                    .background(
                                        Color.purple
                                            .opacity(0.08),
                                        in:
                                            RoundedRectangle(
                                                cornerRadius:
                                                    12
                                            )
                                    )

                                    VStack(
                                        alignment: .leading,
                                        spacing: 2
                                    ) {
                                        HStack(spacing: 7) {
                                            Text(event.title)
                                                .font(
                                                    .subheadline
                                                        .weight(
                                                            .semibold
                                                        )
                                                )

                                            Text(
                                                event
                                                    .resolvedStatus
                                                    .title
                                            )
                                            .font(
                                                .system(
                                                    size: 9,
                                                    weight:
                                                        .bold
                                                )
                                            )
                                            .foregroundStyle(
                                                groupContentStatusColor(
                                                    event
                                                        .resolvedStatus
                                                )
                                            )
                                            .padding(
                                                .horizontal,
                                                6
                                            )
                                            .padding(
                                                .vertical,
                                                3
                                            )
                                            .background(
                                                groupContentStatusColor(
                                                    event
                                                        .resolvedStatus
                                                )
                                                .opacity(
                                                    0.10
                                                ),
                                                in: Capsule()
                                            )
                                        }

                                        Text(
                                            eventDetailText(
                                                event
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )

                                        if let configuration =
                                            event
                                                .activityConfiguration {
                                            Text(
                                                configuration
                                                    .compactSummary
                                            )
                                            .font(
                                                .caption
                                                    .weight(
                                                        .semibold
                                                    )
                                            )
                                            .foregroundStyle(
                                                ATHLTHTheme
                                                    .accentDeep
                                            )
                                            .lineLimit(2)
                                        }

                                        if !event.summary.isEmpty {
                                            Text(
                                                event.summary
                                            )
                                            .font(.caption)
                                            .foregroundStyle(
                                                .secondary
                                            )
                                            .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(.caption2.bold())
                                    .foregroundStyle(
                                        .tertiary
                                    )
                                }

                                let going =
                                    groups
                                        .eventRSVPCount(
                                            eventID:
                                                event.id,
                                            status:
                                                "going"
                                        )
                                let waitlist =
                                    groups
                                        .eventRSVPCount(
                                            eventID:
                                                event.id,
                                            status:
                                                "waitlist"
                                        )

                                if going > 0 ||
                                    waitlist > 0 ||
                                    event.capacity != nil {
                                    HStack(spacing: 8) {
                                        Label(
                                            event.capacity.map {
                                                "\(going)/\($0) going"
                                            } ??
                                            "\(going) going",
                                            systemImage:
                                                "person.2.fill"
                                        )

                                        if waitlist > 0 {
                                            Text(
                                                "· \(waitlist) waitlisted"
                                            )
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if event.id !=
                            visibleGroupEvents.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var visibleGroupChallenges:
        [CommunityGroupChallengeRecord] {
        groups.challenges(in: group.id).filter {
            challenge in

            challenge.status != "draft" ||
            groups.canManage(currentGroup) ||
            challenge.creatorID ==
                session.profile.userID
        }
    }

    private var challenges: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Group Challenges")
                        .font(.title3.weight(.bold))
                    Text(
                        groups.canCreateGroupContent(
                            currentGroup
                        )
                            ? "Create shared goals for the group."
                            : "Creation is restricted by the group settings."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if groups.canCreateGroupContent(
                    currentGroup
                ) {
                    Button {
                        showingCreateChallenge = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if visibleGroupChallenges.isEmpty {
                ContentUnavailableView(
                    "No group challenges",
                    systemImage: "bolt.badge.plus",
                    description: Text(
                        groups.canCreateGroupContent(
                            currentGroup
                        )
                            ? "Create a collective goal for the group."
                            : "No challenges have been created yet."
                    )
                )
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(
                        visibleGroupChallenges
                    ) { challenge in
                        NavigationLink {
                            CommunityGroupChallengeDetailView(
                                group: currentGroup,
                                challenge: challenge
                            )
                        } label: {
                            groupChallengeCard(
                                challenge
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func overviewMetric(
        icon: String,
        value: String,
        title: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 13)
        )
    }

    private func messageRow(
        _ message: CommunityGroupMessageRecord
    ) -> some View {
        let mine =
            message.senderID ==
            session.profile.userID
        let profile = groups.profileCard(
            for: message.senderID
        )

        return HStack(
            alignment: .bottom,
            spacing: 8
        ) {
            if !mine {
                groupMessageAvatar(
                    userID: message.senderID,
                    profile: profile
                )
            } else {
                Spacer(minLength: 44)
            }

            VStack(
                alignment:
                    mine ? .trailing : .leading,
                spacing: 4
            ) {
                Text(
                    mine
                        ? "You"
                        : (
                            profile?.usernameLabel
                                .isEmpty == false
                                ? profile!.usernameLabel
                                : message.senderName
                        )
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(
                        mine
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        mine
                            ? ATHLTHTheme.accentDeep
                            : Color.white,
                        in: RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )

                Text(
                    message.createdAt.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                )
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }

            if mine {
                groupMessageAvatar(
                    userID: message.senderID,
                    profile: profile
                )
            } else {
                Spacer(minLength: 44)
            }
        }
    }

    @ViewBuilder
    private func groupMessageAvatar(
        userID: UUID,
        profile: SocialProfileCard?
    ) -> some View {
        NavigationLink {
            FriendProfileView(userID: userID)
        } label: {
            if let profile {
                CommunityGroupProfileAvatar(
                    profile: profile,
                    size: 32
                )
            } else {
                Image(
                    systemName:
                        "person.crop.circle.fill"
                )
                .font(.system(size: 31))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Open sender profile"
        )
    }

    private func groupChallengeCard(
        _ challenge: CommunityGroupChallengeRecord
    ) -> some View {
        let progress = groups.challengeProgress(challenge)
        let fraction = min(max(progress / challenge.targetValue, 0), 1)

        return VStack(alignment: .leading, spacing: 9) {
            if let imageURL = challenge.imageURL,
               !imageURL.isEmpty {
                communityContentCover(
                    imageURL,
                    height: 140
                )
            }

            HStack {
                Label(
                    challenge.title,
                    systemImage: challenge.metric.icon
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

                Spacer()

                Text(
                    String(
                        format: "%.0f%%",
                        fraction * 100
                    )
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            if let configuration =
                challenge.activityConfiguration {
                Text(configuration.compactSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
            }

            ProgressView(value: fraction)
                .tint(ATHLTHTheme.accent)

            HStack {
                Text(
                    progressText(
                        progress,
                        metric: challenge.metric
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text(
                    "Goal " +
                    targetText(
                        challenge.targetValue,
                        metric: challenge.metric
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            ATHLTHTheme.cardWarm.opacity(0.70),
            in: RoundedRectangle(cornerRadius: 15)
        )
    }

    @ViewBuilder
    private func communityContentCover(
        _ value: String,
        height: CGFloat
    ) -> some View {
        if let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    LinearGradient(
                        colors: [
                            Color.indigo.opacity(0.12),
                            ATHLTHTheme.cardWarm,
                            ATHLTHTheme.canvasTop
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        }
    }

    private func eventDetailText(
        _ event: CommunityGroupEventRecord
    ) -> String {
        var parts = [
            event.startsAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
        ]

        let meeting = event.meetingName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !meeting.isEmpty {
            parts.append(meeting)
        }

        return parts.joined(separator: " · ")
    }

    private func groupContentStatusColor(
        _ status: CommunityGroupContentStatus
    ) -> Color {
        switch status {
        case .draft:
            return .secondary
        case .upcoming:
            return .blue
        case .live:
            return .green
        case .completed:
            return .indigo
        case .cancelled:
            return .red
        }
    }

    private func eventIcon(_ activity: String) -> String {
        switch activity {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "strength": return "dumbbell.fill"
        case "cycling": return "figure.outdoor.cycle"
        case "hike": return "figure.hiking"
        default: return "person.3.fill"
        }
    }

    private func progressText(
        _ value: Double,
        metric: CommunityGroupChallengeMetric
    ) -> String {
        switch metric {
        case .distanceKM:
            return String(format: "%.1f km", value)
        case .workouts:
            return "\(Int(value.rounded())) workouts"
        case .activeMinutes:
            return "\(Int(value.rounded())) min"
        case .fastestTime:
            let seconds = max(Int(value.rounded()), 0)
            return String(
                format: "%d:%02d",
                seconds / 60,
                seconds % 60
            )
        case .strengthVolume:
            return String(format: "%.0f kg", value)
        case .heaviestWeight:
            return String(format: "%.1f kg", value)
        case .strengthReps:
            return "\(Int(value.rounded())) reps"
        }
    }

    private func targetText(
        _ value: Double,
        metric: CommunityGroupChallengeMetric
    ) -> String {
        switch metric {
        case .distanceKM:
            return String(format: "%.0f km", value)
        case .workouts:
            return "\(Int(value.rounded())) workouts"
        case .activeMinutes:
            return "\(Int(value.rounded())) min"
        case .fastestTime:
            return "Fastest time"
        case .strengthVolume:
            return String(format: "%.0f kg", value)
        case .heaviestWeight:
            return String(format: "%.1f kg", value)
        case .strengthReps:
            return "\(Int(value.rounded())) reps"
        }
    }
}

struct CommunityGroupCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    @State private var name = ""
    @State private var summary = ""
    @State private var visibility = "public"
    @State private var joinMode = "open"
    @State private var membersCanCreateContent = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        createCoverPreview

                        PhotosPicker(
                            selection: $selectedPhoto,
                            matching: .images
                        ) {
                            Label(
                                selectedImageData == nil
                                    ? "Choose Club Photo"
                                    : "Change Club Photo",
                                systemImage: "photo.on.rectangle.angled"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)

                        if selectedImageData != nil {
                            Button(role: .destructive) {
                                selectedImageData = nil
                                selectedPhoto = nil
                            } label: {
                                Label(
                                    "Remove Photo",
                                    systemImage: "trash"
                                )
                            }
                            .font(.caption.weight(.semibold))
                        }

                        Text(
                            "This photo becomes the Club hero image and is also used as the Club thumbnail."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                } header: {
                    Text("Club photo")
                }

                Section("Club") {
                    TextField("Group name", text: $name)
                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section("Visibility") {
                    Picker(
                        "Group visibility",
                        selection: $visibility
                    ) {
                        Label("Public", systemImage: "globe")
                            .tag("public")
                        Label("Private", systemImage: "lock.fill")
                            .tag("private")
                    }
                    .pickerStyle(.segmented)

                    Text(
                        visibility == "public"
                            ? "Public groups appear in Discover."
                            : "Private groups stay hidden from Discover and are reached through invitations or an existing membership."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Membership") {
                    Picker(
                        "Who can join",
                        selection: $joinMode
                    ) {
                        if visibility == "public" {
                            Text("Open")
                                .tag("open")
                        }

                        Text("Approval required")
                            .tag("approval")
                        Text("Invite only")
                            .tag("invite_only")
                    }

                    Text(joinModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Member permissions") {
                    Toggle(
                        "Members can create events & challenges",
                        isOn: $membersCanCreateContent
                    )

                    Text(
                        membersCanCreateContent
                            ? "Members can create events and challenges. Owner, Admin and Contributor can always create them."
                            : "Only Owner, Admin and Contributor can create events and challenges."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Label(
                        "Owner has full control. Admin has full management access except deleting the group. Contributor can publish and pin updates, create events and challenges, and use @everyone, but cannot manage members.",
                        systemImage: "person.3.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        saving
                            ? "Creating…"
                            : "Create"
                    ) {
                        Task {
                            saving = true
                            let ok = await groups.createGroup(
                                name: name,
                                summary: summary,
                                visibility: visibility,
                                joinMode: joinMode,
                                membersCanCreateContent:
                                    membersCanCreateContent,
                                imageJPEGData:
                                    selectedImageData
                            )
                            saving = false

                            if ok {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).count < 2 ||
                        saving
                    )
                }
            }
            .onChange(of: visibility) { _, value in
                if value == "private" &&
                    joinMode == "open" {
                    joinMode = "invite_only"
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else {
                    return
                }

                Task {
                    do {
                        guard
                            let data = try await item
                                .loadTransferable(type: Data.self),
                            let jpeg =
                                prepareCreateClubImageData(data)
                        else {
                            groups.errorMessage =
                                "ATHLTH could not prepare that image. Try another photo."
                            return
                        }

                        await MainActor.run {
                            selectedImageData = jpeg
                        }
                    } catch {
                        groups.errorMessage =
                            error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var createCoverPreview: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let selectedImageData,
                   let image = UIImage(
                       data: selectedImageData
                   ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [
                            Color.indigo.opacity(0.22),
                            ATHLTHTheme.cardWarm,
                            ATHLTHTheme.canvasTop
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(
                        selectedImageData == nil
                            ? 0.16
                            : 0.88
                    ),
                    ATHLTHTheme.cardWarm.opacity(
                        selectedImageData == nil
                            ? 0.10
                            : 0.60
                    ),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    ATHLTHTheme.canvasBottom.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("CLUB")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep.opacity(0.62)
                    )

                Text(
                    name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                        ? "Your Club"
                        : name
                )
                .font(.title3.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
            }
            .padding(16)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }

    private func prepareCreateClubImageData(
        _ data: Data
    ) -> Data? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        let maxDimension: CGFloat = 1_600
        let longest = max(
            image.size.width,
            image.size.height
        )
        let scale = min(
            1,
            maxDimension / max(longest, 1)
        )
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )

        let format =
            UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let resized = UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        ).image { _ in
            image.draw(
                in: CGRect(
                    origin: .zero,
                    size: targetSize
                )
            )
        }

        if let jpeg = resized.jpegData(
            compressionQuality: 0.80
        ),
        jpeg.count <= 5_242_880 {
            return jpeg
        }

        return resized.jpegData(
            compressionQuality: 0.62
        )
    }

    private var joinModeDescription: String {
        switch joinMode {
        case "open":
            return "Anyone can join immediately."
        case "approval":
            return "People request access. Owner or Admin approves them."
        default:
            return "Only people invited by Owner or Admin can join."
        }
    }
}

struct CommunityGroupSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var name: String
    @State private var summary: String
    @State private var visibility: String
    @State private var joinMode: String
    @State private var membersCanCreateContent: Bool
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var saving = false
    @State private var deleting = false
    @State private var showingDeleteConfirmation = false

    init(group: CommunityGroupRecord) {
        self.group = group
        _name = State(initialValue: group.name)
        _summary = State(initialValue: group.summary)
        _visibility = State(initialValue: group.visibility)
        _joinMode = State(initialValue: group.joinMode)
        _membersCanCreateContent = State(
            initialValue: group.membersCanCreateContent
        )
    }

    private var currentGroup: CommunityGroupRecord {
        groups.group(for: group.id) ?? group
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        groupImagePreview

                        HStack(spacing: 10) {
                            PhotosPicker(
                                selection: $selectedPhoto,
                                matching: .images
                            ) {
                                Label(
                                    selectedImageData == nil
                                        ? "Choose Photo"
                                        : "Change Photo",
                                    systemImage: "photo"
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(ATHLTHTheme.accent)

                            if selectedImageData != nil {
                                Button(role: .destructive) {
                                    selectedImageData = nil
                                    selectedPhoto = nil
                                } label: {
                                    Label(
                                        "Remove",
                                        systemImage: "trash"
                                    )
                                }
                                .buttonStyle(.bordered)
                            } else if currentGroup.imageURL != nil {
                                Button(role: .destructive) {
                                    Task {
                                        saving = true
                                        _ = await groups.removeGroupImage(
                                            currentGroup
                                        )
                                        saving = false
                                    }
                                } label: {
                                    Label(
                                        "Remove",
                                        systemImage: "trash"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .disabled(saving)
                            }
                        }

                        Text(
                            "The Club photo is used as the hero image with an ATHLTH readability gradient, and as the Club thumbnail elsewhere in Community."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("Club photo")
                }

                Section("Group") {
                    TextField("Group name", text: $name)
                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section("Visibility") {
                    Picker(
                        "Group visibility",
                        selection: $visibility
                    ) {
                        Label("Public", systemImage: "globe")
                            .tag("public")
                        Label("Private", systemImage: "lock.fill")
                            .tag("private")
                    }
                    .pickerStyle(.segmented)

                    Text(
                        visibility == "public"
                            ? "Public groups appear in Discover."
                            : "Private groups stay hidden from Discover."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Membership") {
                    Picker(
                        "Who can join",
                        selection: $joinMode
                    ) {
                        if visibility == "public" {
                            Text("Open")
                                .tag("open")
                        }

                        Text("Approval required")
                            .tag("approval")
                        Text("Invite only")
                            .tag("invite_only")
                    }

                    Text(joinModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Member permissions") {
                    Toggle(
                        "Members can create events & challenges",
                        isOn: $membersCanCreateContent
                    )

                    Text(
                        membersCanCreateContent
                            ? "Members can create events and challenges. Owner, Admin and Contributor can always create them."
                            : "Only Owner and Admin can create events and challenges."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if groups.isOwner(of: currentGroup) {
                    Section {
                        Button(
                            "Delete Group",
                            role: .destructive
                        ) {
                            showingDeleteConfirmation = true
                        }
                        .disabled(saving || deleting)
                    } footer: {
                        Text(
                            "Only the Owner can delete the group. Deleting it permanently removes messages, updates, events, challenges and memberships."
                        )
                    }
                }
            }
            .navigationTitle("Club Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).count < 2 ||
                        saving ||
                        deleting
                    )
                }
            }
            .onChange(of: visibility) { _, value in
                if value == "private" &&
                    joinMode == "open" {
                    joinMode = "invite_only"
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else {
                    return
                }

                Task {
                    do {
                        guard
                            let data = try await item
                                .loadTransferable(type: Data.self),
                            let jpeg = prepareGroupImageData(data)
                        else {
                            groups.errorMessage =
                                "ATHLTH could not prepare that image. Try another photo."
                            return
                        }

                        await MainActor.run {
                            selectedImageData = jpeg
                        }
                    } catch {
                        groups.errorMessage =
                            error.localizedDescription
                    }
                }
            }
            .confirmationDialog(
                "Delete \(currentGroup.name)?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    "Delete Group",
                    role: .destructive
                ) {
                    Task {
                        deleting = true
                        let deleted = await groups.deleteGroup(
                            currentGroup
                        )
                        deleting = false

                        if deleted {
                            dismiss()
                        }
                    }
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This cannot be undone. All group content will be permanently removed."
                )
            }
        }
    }

    private var joinModeDescription: String {
        switch joinMode {
        case "open":
            return "Anyone can join immediately."
        case "approval":
            return "New members request access. Owner or Admin can approve them."
        default:
            return "Only people invited by Owner or Admin can join."
        }
    }

    private func saveChanges() async {
        saving = true

        var saved = await groups.updateGroup(
            currentGroup,
            name: name,
            locationName: currentGroup.locationName,
            summary: summary,
            visibility: visibility,
            joinMode: joinMode,
            membersCanCreateContent:
                membersCanCreateContent
        )

        if saved,
           let selectedImageData {
            saved = await groups.uploadGroupImage(
                currentGroup,
                jpegData: selectedImageData
            )
        }

        saving = false

        if saved {
            dismiss()
        }
    }

    @ViewBuilder
    private var groupImagePreview: some View {
        Group {
            if let selectedImageData,
               let image = UIImage(data: selectedImageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let value = currentGroup.imageURL,
                      let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        groupImagePlaceholder
                    }
                }
            } else {
                groupImagePlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.66),
                        ATHLTHTheme.cardWarm.opacity(0.34),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.border,
                    lineWidth: 1
                )
            }
        }
    }

    private var groupImagePlaceholder: some View {
        RoundedRectangle(
            cornerRadius: 22,
            style: .continuous
        )
        .fill(Color.indigo.opacity(0.10))
        .overlay {
            Image(systemName: "person.3.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.indigo)
        }
    }

    private func prepareGroupImageData(
        _ data: Data
    ) -> Data? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        let maxDimension: CGFloat = 1_600
        let longest = max(
            image.size.width,
            image.size.height
        )
        let scale = min(
            1,
            maxDimension / max(longest, 1)
        )
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let resized = UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        ).image { _ in
            image.draw(
                in: CGRect(
                    origin: .zero,
                    size: targetSize
                )
            )
        }

        if let jpeg = resized.jpegData(
            compressionQuality: 0.80
        ),
        jpeg.count <= 5_242_880 {
            return jpeg
        }

        return resized.jpegData(
            compressionQuality: 0.62
        )
    }
}

private struct CommunityGroupProfileAvatar: View {
    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        Group {
            if let value = profile.avatarURL,
               let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    Color.black.opacity(0.06),
                    lineWidth: 1
                )
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(ATHLTHTheme.accent)
            }
    }
}

struct CommunityGroupActivityPreviewCard: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Community Activity")
                        .font(.title3.weight(.bold))
                    Text("Updates from groups you belong to.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    CommunityGroupActivityCenterView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                }
            }

            if groups.communityActivity.isEmpty {
                Text(
                    "Group joins, updates, events and challenges will appear here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(
                        Array(groups.communityActivity.prefix(3))
                    ) { item in
                        CommunityGroupActivityRow(
                            item: item
                        )
                    }
                }
                .padding(.top, 12)
            }
        }
    }
}

struct CommunityGroupActivityCenterView: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    var body: some View {
        List {
            if groups.communityActivity.isEmpty {
                ContentUnavailableView(
                    "No group activity yet",
                    systemImage: "bell.badge",
                    description: Text(
                        "Club activity will appear here."
                    )
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(groups.communityActivity) { item in
                    CommunityGroupActivityRow(
                        item: item
                    )
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Community Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await groups.refresh()
        }
    }
}

private struct CommunityGroupActivityRow: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    let item: CommunityGroupActivityRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let group = groups.group(
                    for: item.groupID
                ) {
                    Text(group.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let detail = item.detail,
                   !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 5) {
                    if let actorID = item.actorID,
                       let actor = groups.profileCard(
                           for: actorID
                       ) {
                        Text(actor.resolvedName)
                    }

                    Text(
                        item.createdAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    private var icon: String {
        switch item.kind {
        case "member_joined":
            return "person.badge.plus"
        case "announcement":
            return "megaphone.fill"
        case "event_created":
            return "calendar.badge.plus"
        case "challenge_created":
            return "bolt.fill"
        default:
            return "bell.fill"
        }
    }

    private var tint: Color {
        switch item.kind {
        case "member_joined":
            return .indigo
        case "announcement":
            return .orange
        case "event_created":
            return .purple
        case "challenge_created":
            return .green
        default:
            return ATHLTHTheme.accent
        }
    }
}

struct CommunityGroupNotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var enabled = true
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group notifications") {
                    Toggle(
                        "Notifications",
                        isOn: $enabled
                    )

                    Text(
                        enabled
                            ? "Receive Club post, chat, event and challenge notifications."
                            : "Group activity notifications are off."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Label(
                        "Direct @mentions use your global Mentions setting in Settings → Notifications. Turning this group off does not disable a direct mention.",
                        systemImage: "at"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                enabled =
                    groups.notificationMode(
                        in: group.id
                    ) != "muted"
            }
            .onChange(of: enabled) {
                oldValue,
                newValue in

                guard oldValue != newValue else {
                    return
                }

                Task {
                    saving = true
                    let saved =
                        await groups.setGroupNotificationMode(
                            groupID: group.id,
                            mode:
                                newValue
                                    ? "all"
                                    : "muted"
                        )
                    saving = false

                    if !saved {
                        enabled = oldValue
                    }
                }
            }
            .disabled(saving)
        }
    }
}

struct CommunityGroupInviteMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var social: SocialStore

    let group: CommunityGroupRecord

    @State private var query = ""
    @State private var sendingIDs: Set<UUID> = []
    @State private var invitedIDs: Set<UUID> = []

    private var existingMemberIDs: Set<UUID> {
        Set(
            groups.members(in: group.id).map(\.userID)
        )
    }

    private var candidates: [SocialProfileCard] {
        let clean = query
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let source =
            clean.isEmpty
                ? social.visibleProfiles
                : social.discoverResults

        return source
            .filter {
                !existingMemberIDs.contains($0.userID) &&
                $0.userID != social.currentUserID
            }
            .sorted {
                $0.resolvedName
                    .localizedCaseInsensitiveCompare(
                        $1.resolvedName
                    ) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty
                            ? "Find people to invite"
                            : "No matching users",
                        systemImage: "person.badge.plus",
                        description: Text(
                            query.isEmpty
                                ? "Search by username or name."
                                : "Try another search."
                        )
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(candidates) { profile in
                        HStack(spacing: 12) {
                            CommunityGroupProfileAvatar(
                                profile: profile,
                                size: 42
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(profile.resolvedName)
                                    .font(
                                        .subheadline
                                            .weight(.semibold)
                                    )

                                if !profile.usernameLabel.isEmpty {
                                    Text(profile.usernameLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if invitedIDs.contains(
                                profile.userID
                            ) {
                                Label(
                                    "Invited",
                                    systemImage: "checkmark"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                            } else {
                                Button("Invite") {
                                    Task {
                                        sendingIDs.insert(
                                            profile.userID
                                        )

                                        let sent =
                                            await groups.inviteMember(
                                                groupID: group.id,
                                                userID:
                                                    profile.userID
                                            )

                                        sendingIDs.remove(
                                            profile.userID
                                        )

                                        if sent {
                                            invitedIDs.insert(
                                                profile.userID
                                            )
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    sendingIDs.contains(
                                        profile.userID
                                    )
                                )
                            }
                        }
                    }
                }
            }
            .searchable(
                text: $query,
                prompt: "Search username or name"
            )
            .navigationTitle("Invite Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task(id: query) {
                let clean = query
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                guard clean.count >= 2 else {
                    social.clearSearch()
                    return
                }

                try? await Task.sleep(
                    for: .milliseconds(250)
                )
                guard !Task.isCancelled else {
                    return
                }

                await social.search(clean)
            }
            .onDisappear {
                social.clearSearch()
            }
        }
    }
}

struct CommunityGroupMembersView: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var showingInvite = false

    private var sortedMembers:
        [CommunityGroupMemberRecord] {
        groups.members(in: group.id).sorted {
            roleRank($0.role) < roleRank($1.role)
        }
    }

    private var currentGroup: CommunityGroupRecord {
        groups.group(for: group.id) ?? group
    }

    var body: some View {
        List {
            if groups.canManage(currentGroup) &&
                !groups.joinRequests(
                    in: group.id
                ).isEmpty {
                Section("Membership Requests") {
                    ForEach(
                        groups.joinRequests(
                            in: group.id
                        ),
                        id: \.userID
                    ) { request in
                        joinRequestRow(request)
                    }
                }
            }

            Section("Members") {
                ForEach(
                    sortedMembers,
                    id: \.userID
                ) { member in
                    memberRow(member)
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if groups.canManage(currentGroup) {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button {
                        showingInvite = true
                    } label: {
                        Image(
                            systemName:
                                "person.badge.plus"
                        )
                    }
                    .accessibilityLabel(
                        "Invite group member"
                    )
                }
            }
        }
        .sheet(isPresented: $showingInvite) {
            CommunityGroupInviteMemberView(
                group: currentGroup
            )
        }
        .task {
            await groups.loadGroupContent(
                group.id
            )
        }
    }

    private func joinRequestRow(
        _ request: CommunityGroupJoinRequestRecord
    ) -> some View {
        HStack(spacing: 12) {
            if let profile = groups.profileCard(
                for: request.userID
            ) {
                CommunityGroupProfileAvatar(
                    profile: profile,
                    size: 42
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(profile.resolvedName)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                    if !profile.usernameLabel.isEmpty {
                        Text(profile.usernameLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(
                    systemName:
                        "person.crop.circle.fill"
                )
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

                Text("ATHLTH member")
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
            }

            Spacer()

            Button {
                Task {
                    _ = await groups
                        .respondToJoinRequest(
                            groupID: group.id,
                            userID: request.userID,
                            accept: false
                        )
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Button {
                Task {
                    _ = await groups
                        .respondToJoinRequest(
                            groupID: group.id,
                            userID: request.userID,
                            accept: true
                        )
                }
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)
        }
    }

    @ViewBuilder
    private func memberRow(
        _ member: CommunityGroupMemberRecord
    ) -> some View {
        HStack(spacing: 12) {
            if let profile = groups.profileCard(
                for: member.userID
            ) {
                CommunityGroupProfileAvatar(
                    profile: profile,
                    size: 42
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(profile.resolvedName)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                    if let username =
                        profile.username {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(
                    systemName:
                        "person.crop.circle.fill"
                )
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

                Text("Group member")
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
            }

            Spacer()

            Text(roleTitle(member.role))
                .font(.caption2.weight(.bold))
                .foregroundStyle(
                    roleTint(member.role)
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color(
                        .secondarySystemGroupedBackground
                    ),
                    in: Capsule()
                )

            if groups.canManage(currentGroup) &&
                member.role != "owner" {
                Menu {
                    roleButton(
                        member,
                        role: "admin",
                        title: "Admin",
                        icon: "shield.fill"
                    )

                    roleButton(
                        member,
                        role: "contributor",
                        title: "Contributor",
                        icon: "megaphone.fill"
                    )

                    roleButton(
                        member,
                        role: "member",
                        title: "Member",
                        icon: "person.fill"
                    )

                    Divider()

                    Button(
                        "Remove from Group",
                        role: .destructive
                    ) {
                        Task {
                            _ = await groups.removeMember(
                                groupID: group.id,
                                userID: member.userID
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(
                            width: 30,
                            height: 30
                        )
                }
            }
        }
    }

    private func roleButton(
        _ member: CommunityGroupMemberRecord,
        role: String,
        title: String,
        icon: String
    ) -> some View {
        Button {
            Task {
                _ = await groups.setMemberRole(
                    groupID: group.id,
                    userID: member.userID,
                    role: role
                )
            }
        } label: {
            Label(
                title,
                systemImage:
                    member.role == role
                        ? "checkmark"
                        : icon
            )
        }
        .disabled(member.role == role)
    }

    private func roleRank(
        _ role: String
    ) -> Int {
        switch role {
        case "owner": return 0
        case "admin": return 1
        case "contributor": return 2
        default: return 3
        }
    }

    private func roleTitle(
        _ role: String
    ) -> String {
        switch role {
        case "owner": return "Owner"
        case "admin": return "Admin"
        case "contributor": return "Contributor"
        default: return "Member"
        }
    }

    private func roleTint(
        _ role: String
    ) -> Color {
        switch role {
        case "owner":
            return ATHLTHTheme.premiumGold
        case "admin":
            return .indigo
        case "contributor":
            return .orange
        default:
            return .secondary
        }
    }
}

private struct CommunityContentCoverPicker: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var imageData: Data?

    let placeholderIcon: String

    @State private var imageError: String?

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let imageData,
                   let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [
                            Color.indigo.opacity(0.18),
                            ATHLTHTheme.cardWarm,
                            ATHLTHTheme.canvasTop
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: placeholderIcon)
                            .font(
                                .system(
                                    size: 34,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                                    .opacity(0.70)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.border,
                    lineWidth: 1
                )
            }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images
                ) {
                    Label(
                        imageData == nil
                            ? "Choose Photo"
                            : "Change Photo",
                        systemImage: "photo"
                    )
                }
                .buttonStyle(.bordered)

                if imageData != nil {
                    Button(
                        "Remove",
                        role: .destructive
                    ) {
                        selectedPhoto = nil
                        imageData = nil
                        imageError = nil
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }

            if let imageError {
                Text(imageError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
            } else {
                Text(
                    "Optional. ATHLTH resizes the image before upload."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else {
                return
            }

            Task {
                do {
                    guard
                        let data = try await item
                            .loadTransferable(
                                type: Data.self
                            ),
                        let jpeg =
                            prepareCommunityCoverImageData(
                                data
                            )
                    else {
                        imageError =
                            "ATHLTH could not prepare that image."
                        return
                    }

                    imageData = jpeg
                    imageError = nil
                } catch {
                    imageError =
                        error.localizedDescription
                }
            }
        }
    }
}

private func prepareCommunityCoverImageData(
    _ data: Data
) -> Data? {
    guard let image = UIImage(data: data) else {
        return nil
    }

    let maxDimension: CGFloat = 1_800
    let longest = max(
        image.size.width,
        image.size.height
    )
    let scale = min(
        1,
        maxDimension / max(longest, 1)
    )
    let targetSize = CGSize(
        width: max(
            1,
            image.size.width * scale
        ),
        height: max(
            1,
            image.size.height * scale
        )
    )

    let format =
        UIGraphicsImageRendererFormat.default()
    format.scale = 1

    let resized = UIGraphicsImageRenderer(
        size: targetSize,
        format: format
    ).image { _ in
        image.draw(
            in: CGRect(
                origin: .zero,
                size: targetSize
            )
        )
    }

    if let jpeg = resized.jpegData(
        compressionQuality: 0.82
    ),
    jpeg.count <= 5_242_880 {
        return jpeg
    }

    return resized.jpegData(
        compressionQuality: 0.62
    )
}

struct CommunityGroupEventCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups:
        CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var title = ""
    @State private var summary = ""
    @State private var startsAt =
        Date().addingTimeInterval(3600)
    @State private var meetingName = ""
    @State private var activityDraft =
        CommunityGroupActivityDraft()
    @State private var advancedOptions =
        CommunityGroupEventAdvancedOptions()
    @State private var cohostIDs: Set<UUID> = []
    @State private var selectedPhoto:
        PhotosPickerItem?
    @State private var imageData: Data?
    @State private var saving = false
    @State private var creationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Cover image") {
                    CommunityContentCoverPicker(
                        selectedPhoto: $selectedPhoto,
                        imageData: $imageData,
                        placeholderIcon:
                            "calendar.badge.plus"
                    )
                }

                Section("Event") {
                    TextField(
                        "Title",
                        text: $title
                    )

                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    DatePicker(
                        "Starts",
                        selection: $startsAt,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                }

                CommunityGroupActivityEditor(
                    draft: $activityDraft
                )

                Section("Meet") {
                    TextField(
                        "Meeting point (optional)",
                        text: $meetingName
                    )
                }

                CommunityGroupEventAdvancedEditor(
                    group: group,
                    eventStartsAt: startsAt,
                    options: $advancedOptions,
                    cohostIDs: $cohostIDs,
                    routeStart:
                        activityDraft
                            .configuration
                            .route?
                            .coordinates
                            .first
                )

                Section {
                    Label(
                        "Only members of \(group.name) can see this event.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Group Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        saving
                            ? "Creating…"
                            : "Create"
                    ) {
                        createEvent()
                    }
                    .disabled(!canCreate)
                }
            }
            .alert(
                "Could Not Create Event",
                isPresented: Binding(
                    get: {
                        creationError != nil
                    },
                    set: {
                        if !$0 {
                            creationError = nil
                        }
                    }
                )
            ) {
                Button(
                    "OK",
                    role: .cancel
                ) {}
            } message: {
                Text(creationError ?? "")
            }
        }
    }

    private var canCreate: Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        activityDraft.validationMessage == nil &&
        !saving
    }

    private func createEvent() {
        if let validation =
            activityDraft.validationMessage {
            creationError = validation
            return
        }

        let configuration =
            activityDraft.configuration

        Task {
            saving = true

            let ok = await groups.createEvent(
                groupID: group.id,
                title: title,
                summary: summary,
                activityType:
                    configuration.activityType,
                startsAt: startsAt,
                meetingName: meetingName,
                imageData: imageData,
                activityConfiguration:
                    configuration,
                advancedOptions:
                    advancedOptions,
                cohostIDs:
                    Array(cohostIDs)
            )

            saving = false

            if ok {
                dismiss()
            } else {
                creationError =
                    groups.errorMessage
                    ?? "ATHLTH could not create the event."
            }
        }
    }
}

struct CommunityGroupChallengeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups:
        CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var title = ""
    @State private var summary = ""
    @State private var goalPreset:
        CommunityGroupChallengeGoalPreset =
            .mostDistance
    @State private var metric:
        CommunityGroupChallengeMetric = .distanceKM
    @State private var target = "100"
    @State private var startsAt = Date()
    @State private var endsAt =
        Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: Date()
        ) ?? Date().addingTimeInterval(604800)
    @State private var activityDraft =
        CommunityGroupActivityDraft()
    @State private var challengeOptions =
        CommunityGroupChallengeAdvancedOptions()
    @State private var challengeCohostIDs:
        Set<UUID> = []
    @State private var selectedPhoto:
        PhotosPickerItem?
    @State private var imageData: Data?
    @State private var saving = false
    @State private var creationError: String?

    private var targetValue: Double? {
        Double(
            target
                .replacingOccurrences(
                    of: ",",
                    with: "."
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cover image") {
                    CommunityContentCoverPicker(
                        selectedPhoto: $selectedPhoto,
                        imageData: $imageData,
                        placeholderIcon: "bolt.fill"
                    )
                }

                Section("Challenge") {
                    TextField(
                        "Title",
                        text: $title
                    )

                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                CommunityGroupActivityEditor(
                    draft: $activityDraft
                )
                .onChange(
                    of: activityDraft.activityType
                ) { _, type in
                    if type == "strength" {
                        goalPreset = .strengthVolume
                        target = "5000"
                    } else if [
                        CommunityGroupChallengeGoalPreset
                            .strengthVolume,
                        .heaviestWeight,
                        .strengthReps
                    ].contains(goalPreset) {
                        goalPreset = .mostDistance
                        target = "100"
                    }

                    applyGoalPreset(goalPreset)
                }

                Section("Goal") {
                    Picker(
                        "Challenge goal",
                        selection: $goalPreset
                    ) {
                        ForEach(
                            suggestedGoalPresets
                        ) { preset in
                            Text(preset.title)
                                .tag(preset)
                        }
                    }
                    .onChange(
                        of: goalPreset
                    ) { _, preset in
                        applyGoalPreset(preset)
                    }

                    if goalNeedsTarget {
                        HStack {
                            TextField(
                                "Target",
                                text: $target
                            )
                            .keyboardType(
                                .decimalPad
                            )

                            Text(metric.unit)
                                .foregroundStyle(
                                    .secondary
                                )
                        }
                    } else {
                        LabeledContent(
                            "Scoring",
                            value:
                                challengeOptions
                                    .scoringMode
                                    .title
                        )
                    }

                    Text(goalExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Window") {
                    DatePicker(
                        "Starts",
                        selection: $startsAt,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )

                    DatePicker(
                        "Ends",
                        selection: $endsAt,
                        in: startsAt...,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                }

                CommunityGroupChallengeAdvancedEditor(
                    group: group,
                    options: $challengeOptions,
                    cohostIDs:
                        $challengeCohostIDs,
                    routeSelected:
                        activityDraft.mode ==
                            .route &&
                        (
                            activityDraft
                                .selectedRoute != nil ||
                            activityDraft
                                .selectedRouteSnapshot != nil
                        )
                )

                Section {
                    Label(
                        "Only completed workouts matching the selected activity contribute to this challenge. The same workout is counted once.",
                        systemImage: "bolt.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Group Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        saving
                            ? "Creating…"
                            : "Create"
                    ) {
                        createChallenge()
                    }
                    .disabled(!canCreate)
                }
            }
            .alert(
                "Could Not Create Challenge",
                isPresented: Binding(
                    get: {
                        creationError != nil
                    },
                    set: {
                        if !$0 {
                            creationError = nil
                        }
                    }
                )
            ) {
                Button(
                    "OK",
                    role: .cancel
                ) {}
            } message: {
                Text(creationError ?? "")
            }
        }
    }

    private var canCreate: Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        resolvedTargetValue > 0 &&
        endsAt > startsAt &&
        activityDraft.validationMessage == nil &&
        !saving
    }

    private func createChallenge() {
        if goalNeedsTarget &&
            (targetValue ?? 0) <= 0 {
            creationError =
                "Choose a valid challenge target."
            return
        }

        if let validation =
            activityDraft.validationMessage {
            creationError = validation
            return
        }

        let configuration =
            activityDraft.configuration

        Task {
            saving = true

            let ok = await groups.createChallenge(
                groupID: group.id,
                title: title,
                summary: summary,
                metric: metric,
                targetValue:
                    resolvedTargetValue,
                startsAt: startsAt,
                endsAt: endsAt,
                imageData: imageData,
                activityConfiguration:
                    configuration,
                advancedOptions:
                    challengeOptions,
                cohostIDs:
                    Array(challengeCohostIDs)
            )

            saving = false

            if ok {
                dismiss()
            } else {
                creationError =
                    groups.errorMessage
                    ?? "ATHLTH could not create the challenge."
            }
        }
    }

    private var suggestedGoalPresets:
        [CommunityGroupChallengeGoalPreset] {
        switch activityDraft.activityType {
        case "strength":
            return [
                .strengthVolume,
                .heaviestWeight,
                .strengthReps,
                .mostCompletions,
                .mostActiveMinutes,
                .completeTarget
            ]
        default:
            return [
                .fastestTime,
                .mostDistance,
                .mostCompletions,
                .mostActiveMinutes,
                .completeTarget
            ]
        }
    }

    private var goalNeedsTarget: Bool {
        switch goalPreset {
        case .mostDistance,
             .mostActiveMinutes,
             .strengthVolume,
             .heaviestWeight,
             .strengthReps:
            return true
        case .fastestTime,
             .mostCompletions,
             .completeTarget:
            return false
        }
    }

    private var resolvedTargetValue: Double {
        goalNeedsTarget
            ? (targetValue ?? 0)
            : 1
    }

    private var goalExplanation: String {
        switch goalPreset {
        case .fastestTime:
            return "The fastest qualifying attempt wins. For a fixed distance ATHLTH can verify the fastest GPS segment."
        case .mostDistance:
            return "All qualifying distance is added during the challenge window."
        case .mostCompletions:
            return "Each qualifying workout counts as one completion."
        case .mostActiveMinutes:
            return "Active workout minutes are added across qualifying attempts."
        case .strengthVolume:
            return "Completed reps × weight are added across qualifying strength workouts."
        case .heaviestWeight:
            return "The heaviest completed weight in a qualifying strength workout counts."
        case .strengthReps:
            return "Completed reps are added across qualifying strength workouts."
        case .completeTarget:
            return "Participants complete the configured activity target. Progress stops at completion."
        }
    }

    private func applyGoalPreset(
        _ preset:
            CommunityGroupChallengeGoalPreset
    ) {
        metric = preset.metric
        challengeOptions.scoringMode =
            preset.scoringMode

        if !goalNeedsTarget {
            target = "1"
        } else if targetValue == nil ||
                    (targetValue ?? 0) <= 0 {
            target = "100"
        }
    }

}
