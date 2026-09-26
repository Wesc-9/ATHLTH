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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum CommunityGroupChallengeMetric: String, Codable, CaseIterable, Identifiable {
    case distanceKM = "distance_km"
    case workouts
    case activeMinutes = "active_minutes"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distanceKM: return "Distance"
        case .workouts: return "Workouts"
        case .activeMinutes: return "Active Minutes"
        }
    }

    var unit: String {
        switch self {
        case .distanceKM: return "km"
        case .workouts: return "workouts"
        case .activeMinutes: return "min"
        }
    }

    var icon: String {
        switch self {
        case .distanceKM: return "figure.run"
        case .workouts: return "checkmark.circle.fill"
        case .activeMinutes: return "clock.fill"
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CommunityGroupChallengeWorkoutRecord: Codable, Hashable {
    let challengeID: UUID
    let userID: UUID
    let workoutID: UUID
    let contribution: Double
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case workoutID = "workout_id"
        case contribution
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
    }
}

private struct CommunityGroupChallengeWorkoutInsert: Encodable {
    let challengeID: UUID
    let userID: UUID
    let workoutID: UUID
    let contribution: Double

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case workoutID = "workout_id"
        case contribution
    }
}

private struct CommunityGroupAnnouncementPinUpdate: Encodable {
    let pinnedAt: Date?

    enum CodingKeys: String, CodingKey {
        case pinnedAt = "pinned_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        if let pinnedAt {
            try container.encode(
                pinnedAt,
                forKey: .pinnedAt
            )
        } else {
            try container.encodeNil(
                forKey: .pinnedAt
            )
        }
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
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

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
        case "owner", "admin":
            return true
        case "member":
            return group.membersCanCreateContent
        case "contributor":
            return false
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
        membersByGroup[groupID] ?? []
    }

    func announcements(
        in groupID: UUID
    ) -> [CommunityGroupAnnouncementRecord] {
        announcementsByGroup[groupID] ?? []
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
            ?? "important"
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

    func challengeProgress(_ challenge: CommunityGroupChallengeRecord) -> Double {
        challengeWorkouts
            .filter { $0.challengeID == challenge.id }
            .reduce(0) { $0 + $1.contribution }
    }

    func refresh() async {
        guard let userID = currentUserID else {
            groups = []
            ownMemberships = []
            ownJoinRequests = []
            ownInvites = []
            notificationPreferencesByGroup = [:]
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let groupsQuery: [CommunityGroupRecord] = client
                .from("community_groups")
                .select()
                .order("created_at", ascending: false)
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
                .limit(100)
                .execute()
                .value

            async let profilesQuery: [SocialProfileCard] = client
                .from("social_profile_cards")
                .select()
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

            groups = try await groupsQuery
            ownMemberships = try await membershipsQuery
            communityActivity = try await activityQuery
            ownInvites = try await invitesQuery
            ownJoinRequests = try await joinRequestsQuery

            let notificationPreferences =
                try await notificationPreferencesQuery
            notificationPreferencesByGroup = Dictionary(
                uniqueKeysWithValues:
                    notificationPreferences.map {
                        ($0.groupID, $0)
                    }
            )

            let profiles = try await profilesQuery
            profileCardsByID = Dictionary(
                uniqueKeysWithValues: profiles.map {
                    ($0.userID, $0)
                }
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadGroupContent(_ groupID: UUID) async {
        guard joinedGroupIDs.contains(groupID) else { return }

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
                .execute()
                .value

            async let challengesQuery: [CommunityGroupChallengeRecord] = client
                .from("community_group_challenges")
                .select()
                .eq("group_id", value: groupID)
                .order("starts_at", ascending: false)
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

            async let profilesQuery: [SocialProfileCard] = client
                .from("social_profile_cards")
                .select()
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
            let loadedProfiles = try await profilesQuery
            let loadedJoinRequests = try await joinRequestsQuery
            let loadedEventRSVPs = try await eventRSVPsQuery

            membersByGroup[groupID] = loadedMembers
            messagesByGroup[groupID] = loadedMessages
            eventsByGroup[groupID] = loadedEvents
            challengesByGroup[groupID] = loadedChallenges
            announcementsByGroup[groupID] = loadedAnnouncements
            activityByGroup[groupID] = loadedActivity
            joinRequestsByGroup[groupID] = loadedJoinRequests
            eventRSVPsByGroup[groupID] = loadedEventRSVPs

            for profile in loadedProfiles {
                profileCardsByID[profile.userID] = profile
            }

            let allContributions: [CommunityGroupChallengeWorkoutRecord] =
                try await client
                    .from("community_group_challenge_workouts")
                    .select()
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
        membersCanCreateContent: Bool = true
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
                    ? "approval"
                    : (
                        ["open", "approval", "invite_only"]
                            .contains(joinMode)
                            ? joinMode
                            : "open"
                    )

            let payload = CommunityGroupInsert(
                id: UUID(),
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

            await refresh()
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
                    ? "approval"
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

            await refresh()
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
            errorMessage = "Group image must be smaller than 5 MB."
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

            await refresh()
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

            await refresh()
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
            activityByGroup[group.id] = nil
            messagesByGroup[group.id] = nil
            eventsByGroup[group.id] = nil
            challengesByGroup[group.id] = nil

            await refresh()
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

            await loadGroupContent(groupID)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
              canManage(group)
        else {
            return false
        }

        do {
            try await client
                .from("community_group_announcements")
                .update(
                    CommunityGroupAnnouncementPinUpdate(
                        pinnedAt: nil
                    )
                )
                .eq("group_id", value: groupID)
                .execute()

            if let announcementID {
                try await client
                    .from("community_group_announcements")
                    .update(
                        CommunityGroupAnnouncementPinUpdate(
                            pinnedAt: Date()
                        )
                    )
                    .eq("id", value: announcementID)
                    .eq("group_id", value: groupID)
                    .execute()
            }

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

            await refresh()

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

            await refresh()
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

            await refresh()

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
              ["all", "important", "muted"].contains(mode)
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

            await refresh()
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

            await refresh()
            membersByGroup[group.id] = nil
            announcementsByGroup[group.id] = nil
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

    func createEvent(
        groupID: UUID,
        title: String,
        summary: String,
        activityType: String,
        startsAt: Date,
        meetingName: String
    ) async -> Bool {
        guard let userID = currentUserID,
              let group = group(for: groupID),
              canCreateGroupContent(group)
        else {
            errorMessage =
                "You do not have permission to create group events."
            return false
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMeet = meetingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanMeet.isEmpty else {
            errorMessage = "Add an event title and meeting point."
            return false
        }

        do {
            try await client
                .from("community_group_events")
                .insert(
                    CommunityGroupEventInsert(
                        id: UUID(),
                        groupID: groupID,
                        creatorID: userID,
                        title: String(cleanTitle.prefix(160)),
                        summary: String(summary.prefix(1200)),
                        activityType: activityType,
                        startsAt: startsAt,
                        endsAt: nil,
                        meetingName: String(cleanMeet.prefix(180))
                    )
                )
                .execute()

            await loadGroupContent(groupID)
            await refresh()
            return true
        } catch {
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
        endsAt: Date
    ) async -> Bool {
        guard let userID = currentUserID,
              let group = group(for: groupID),
              canCreateGroupContent(group),
              targetValue > 0,
              endsAt > startsAt
        else {
            errorMessage =
                "Check the challenge details and your group permissions."
            return false
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorMessage = "Give the challenge a title."
            return false
        }

        do {
            try await client
                .from("community_group_challenges")
                .insert(
                    CommunityGroupChallengeInsert(
                        id: UUID(),
                        groupID: groupID,
                        creatorID: userID,
                        title: String(cleanTitle.prefix(160)),
                        summary: String(summary.prefix(800)),
                        metric: metric,
                        targetValue: targetValue,
                        startsAt: startsAt,
                        endsAt: endsAt
                    )
                )
                .execute()

            await loadGroupContent(groupID)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func recordCompletedWorkout(
        _ workout: SocialPublishableWorkout
    ) async {
        guard let userID = currentUserID,
              !joinedGroupIDs.isEmpty
        else { return }

        do {
            let activeChallenges: [CommunityGroupChallengeRecord] =
                try await client
                    .from("community_group_challenges")
                    .select()
                    .lte("starts_at", value: workout.endDate)
                    .gte("ends_at", value: workout.startDate)
                    .execute()
                    .value

            let writes = activeChallenges.compactMap { challenge
                -> CommunityGroupChallengeWorkoutInsert? in
                let contribution: Double

                switch challenge.metric {
                case .distanceKM:
                    contribution = (workout.distanceMeters ?? 0) / 1_000
                case .workouts:
                    contribution = 1
                case .activeMinutes:
                    contribution = max(workout.duration / 60, 0)
                }

                guard contribution > 0 else { return nil }

                return CommunityGroupChallengeWorkoutInsert(
                    challengeID: challenge.id,
                    userID: userID,
                    workoutID: workout.id,
                    contribution: contribution
                )
            }

            guard !writes.isEmpty else { return }

            try await client
                .from("community_group_challenge_workouts")
                .upsert(
                    writes,
                    onConflict: "challenge_id,user_id,workout_id"
                )
                .execute()
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
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Groups")
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
        ZStack {
            ATHLTHPremiumCanvas(
                accent: Color.indigo.opacity(0.30)
            )

            ScrollView {
                LazyVStack(spacing: 16) {
                    groupHeader

                    if isMember {
                        Picker("Group area", selection: $selectedTab) {
                            ForEach(CommunityGroupsTab.allCases) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch selectedTab {
                        case .overview:
                            overview
                        case .chat:
                            chat
                        case .events:
                            events
                        case .challenges:
                            challenges
                        }
                    } else {
                        membershipAccessCard
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(currentGroup.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreateEvent) {
            CommunityGroupEventCreateView(group: currentGroup)
        }
        .sheet(isPresented: $showingCreateChallenge) {
            CommunityGroupChallengeCreateView(group: currentGroup)
        }
        .sheet(isPresented: $showingGroupSettings) {
            CommunityGroupSettingsView(group: currentGroup)
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
            if isMember {
                await groups.loadGroupContent(group.id)
            }
        }
        .refreshable {
            await groups.refresh()
            if isMember {
                await groups.loadGroupContent(group.id)
            }
        }
        .onChange(of: groups.groups.map(\.id)) { _, groupIDs in
            if !groupIDs.contains(group.id) {
                dismiss()
            }
        }
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

    private var groupHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.22),
                    ATHLTHTheme.cardWarm.opacity(0.92),
                    ATHLTHTheme.canvasTop
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.28))
                .frame(width: 180, height: 180)
                .offset(x: 230, y: -82)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    if groups.canManage(currentGroup) {
                        Button {
                            showingGroupSettings = true
                        } label: {
                            detailGroupImage
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10, weight: .bold))
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
                        .accessibilityLabel("Change group photo")
                    } else {
                        detailGroupImage
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentGroup.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        if !currentGroup.summary
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty {
                            Text(currentGroup.summary)
                                .font(.subheadline)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                                .lineLimit(3)
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

                            if isMember {
                                Text(memberCountText)
                            }
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()

                    if groups.canManage(currentGroup) {
                        Menu {
                            Button {
                                showingGroupSettings = true
                            } label: {
                                Label(
                                    "Group Settings",
                                    systemImage: "gearshape"
                                )
                            }

                            Button {
                                showingNotificationSettings = true
                            } label: {
                                Label(
                                    "Notifications",
                                    systemImage: "bell"
                                )
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .frame(width: 36, height: 36)
                                .background(
                                    Color.white.opacity(0.56),
                                    in: Circle()
                                )
                        }
                    } else if isMember {
                        Menu {
                            Button {
                                showingNotificationSettings = true
                            } label: {
                                Label(
                                    "Notifications",
                                    systemImage: "bell"
                                )
                            }

                            Button(
                                "Leave Group",
                                role: .destructive
                            ) {
                                Task {
                                    await groups.leave(currentGroup)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .frame(width: 36, height: 36)
                                .background(
                                    Color.white.opacity(0.56),
                                    in: Circle()
                                )
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(minHeight: 166)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.78), lineWidth: 1)
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.08),
            radius: 18,
            x: 0,
            y: 8
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
                        "Pinned Update",
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
                    Text("Updates")
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

            membersOverviewCard

            ATHLTHCard {
                Text("Inside this group")
                    .font(.headline)

                HStack(spacing: 8) {
                    overviewMetric(
                        icon: "bubble.left.and.bubble.right.fill",
                        value: "\(groups.messages(in: group.id).count)",
                        title: "Messages"
                    )
                    overviewMetric(
                        icon: "calendar",
                        value: "\(groups.events(in: group.id).count)",
                        title: "Events"
                    )
                    overviewMetric(
                        icon: "bolt.fill",
                        value: "\(groups.challenges(in: group.id).count)",
                        title: "Challenges"
                    )
                }
                .padding(.top, 10)
            }
        }
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
                    Text("Group update")
                        .font(.subheadline.weight(.semibold))
                    Text("Visible to every group member")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "Share an update…",
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
        groups.events(in: group.id)
            .filter { $0.startsAt >= Date() }
            .sorted { $0.startsAt < $1.startsAt }
            .first
    }

    private var nextGroupChallenge: CommunityGroupChallengeRecord? {
        let now = Date()

        return groups.challenges(in: group.id)
            .filter { $0.endsAt >= now }
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
                        Button {
                            selectedTab = .events
                        } label: {
                            comingUpRow(
                                icon: "calendar",
                                title: event.title,
                                detail:
                                    event.startsAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    ) +
                                    " · " +
                                    event.meetingName,
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
                        Button {
                            selectedTab = .challenges
                        } label: {
                            comingUpRow(
                                icon: "bolt.fill",
                                title: challenge.title,
                                detail:
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
        ATHLTHCard {
            HStack {
                Label(
                    isPinned
                        ? "Pinned Update"
                        : "Group Update",
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

                if groups.canManage(currentGroup) {
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
                                    ? "Unpin Update"
                                    : "Pin Update",
                                systemImage:
                                    isPinned
                                        ? "pin.slash"
                                        : "pin"
                            )
                        }

                        Button(
                            "Delete Update",
                            role: .destructive
                        ) {
                            Task {
                                _ = await groups.deleteAnnouncement(
                                    groupID: group.id,
                                    announcementID: update.id
                                )
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
        }
    }

    private var membersOverviewCard: some View {
        NavigationLink {
            CommunityGroupMembersView(
                group: currentGroup
            )
        } label: {
            ATHLTHCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Members")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(memberCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: -8) {
                        ForEach(
                            Array(
                                groups.members(in: group.id)
                                    .prefix(4)
                            ),
                            id: \.userID
                        ) { member in
                            memberAvatar(member)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func memberAvatar(
        _ member: CommunityGroupMemberRecord
    ) -> some View {
        if let profile = groups.profileCard(
            for: member.userID
        ) {
            CommunityGroupProfileAvatar(
                profile: profile,
                size: 34
            )
            .overlay {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            }
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                }
        }
    }

    private var chat: some View {
        VStack(spacing: 12) {
            ATHLTHCard {
                if groups.messages(in: group.id).isEmpty {
                    ContentUnavailableView(
                        "No messages yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(
                            "Start the group conversation."
                        )
                    )
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 12) {
                        ForEach(
                            groups.messages(in: group.id)
                        ) { message in
                            messageRow(message)
                        }
                    }
                }
            }

            if !groupMentionSuggestions.isEmpty {
                ATHLTHMentionSuggestionList(
                    suggestions: groupMentionSuggestions
                ) { suggestion in
                    messageDraft =
                        ATHLTHMentionSupport.inserting(
                            suggestion,
                            into: messageDraft
                        )
                }
            }

            HStack(spacing: 10) {
                TextField(
                    "Message group",
                    text: $messageDraft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(
                    ATHLTHTheme.card,
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

                Button {
                    let body = messageDraft
                    messageDraft = ""
                    Task {
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
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            ATHLTHTheme.accentDeep,
                            in: Circle()
                        )
                }
                .disabled(
                    messageDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .task(id: selectedTab) {
            guard selectedTab == .chat else { return }
            while !Task.isCancelled {
                await groups.refreshMessages(group.id)
                try? await Task.sleep(for: .seconds(5))
            }
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
                role == "admin"
        )
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

            if groups.events(in: group.id).isEmpty {
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
                        groups.events(in: group.id)
                    ) { event in
                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        eventIcon(
                                            event.activityType
                                        )
                                )
                                .foregroundStyle(.purple)
                                .frame(width: 38, height: 38)
                                .background(
                                    Color.purple.opacity(0.08),
                                    in: RoundedRectangle(
                                        cornerRadius: 12
                                    )
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(event.title)
                                        .font(
                                            .subheadline
                                                .weight(.semibold)
                                        )
                                    Text(
                                        event.startsAt.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        ) +
                                        " · " +
                                        event.meetingName
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    if !event.summary.isEmpty {
                                        Text(event.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()
                            }

                            eventRSVPControls(event)
                        }
                        .padding(.vertical, 10)

                        if event.id != groups.events(
                            in: group.id
                        ).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func eventRSVPControls(
        _ event: CommunityGroupEventRecord
    ) -> some View {
        let current =
            groups.eventRSVP(
                eventID: event.id
            )?.status

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                rsvpButton(
                    event: event,
                    title: "Going",
                    status: "going",
                    selected: current == "going"
                )
                rsvpButton(
                    event: event,
                    title: "Maybe",
                    status: "maybe",
                    selected: current == "maybe"
                )
                rsvpButton(
                    event: event,
                    title: "Can't go",
                    status: "not_going",
                    selected: current == "not_going"
                )
            }

            let going = groups.eventRSVPCount(
                eventID: event.id,
                status: "going"
            )
            let maybe = groups.eventRSVPCount(
                eventID: event.id,
                status: "maybe"
            )

            if going > 0 || maybe > 0 {
                Text(
                    "\(going) going · \(maybe) maybe"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 50)
    }

    private func rsvpButton(
        event: CommunityGroupEventRecord,
        title: String,
        status: String,
        selected: Bool
    ) -> some View {
        Button {
            Task {
                _ = await groups.setEventRSVP(
                    groupID: group.id,
                    eventID: event.id,
                    status: status
                )
            }
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(
            selected
                ? ATHLTHTheme.accentDeep
                : Color.gray
        )
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

            if groups.challenges(in: group.id).isEmpty {
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
                        groups.challenges(in: group.id)
                    ) { challenge in
                        groupChallengeCard(challenge)
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
        let mine = message.senderID == session.profile.userID

        return HStack {
            if mine { Spacer(minLength: 40) }

            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(mine ? "You" : message.senderName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        mine
                            ? ATHLTHTheme.accentSoft
                            : Color.primary.opacity(0.045),
                        in: RoundedRectangle(
                            cornerRadius: 14,
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

            if !mine { Spacer(minLength: 40) }
        }
    }

    private func groupChallengeCard(
        _ challenge: CommunityGroupChallengeRecord
    ) -> some View {
        let progress = groups.challengeProgress(challenge)
        let fraction = min(max(progress / challenge.targetValue, 0), 1)

        return VStack(alignment: .leading, spacing: 9) {
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
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
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
                            ? "Members can create events and challenges. Contributor remains update-only. Owner and Admin can always create them."
                            : "Only Owner and Admin can create events and challenges. Contributor still keeps update-publishing access."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Label(
                        "Owner has full control. Admin has full management access except deleting the group. Contributor can publish official group updates.",
                        systemImage: "person.3.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Group")
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
                                    membersCanCreateContent
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
                    joinMode = "approval"
                }
            }
        }
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
                            "The group photo appears beside the group name. The large header stays a gradient so the group keeps a consistent ATHLTH look."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("Group photo")
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
                            ? "Members can create events and challenges. Contributor remains update-only. Owner and Admin can always create them."
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
            .navigationTitle("Group Settings")
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
                    joinMode = "approval"
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
        .frame(width: 112, height: 112)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }

    private var groupImagePlaceholder: some View {
        RoundedRectangle(
            cornerRadius: 28,
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
                        "Updates from your groups will appear here."
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

    @State private var mode = "important"
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group notifications") {
                    Picker(
                        "Notify me about",
                        selection: $mode
                    ) {
                        Text("All activity")
                            .tag("all")
                        Text("Important only")
                            .tag("important")
                        Text("Muted")
                            .tag("muted")
                    }

                    Text(modeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Label(
                        "Direct @mentions follow your global Mentions setting in Settings → Notifications, even when this group is muted.",
                        systemImage: "at"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                mode = groups.notificationMode(
                    in: group.id
                )
            }
            .onChange(of: mode) { oldValue, newValue in
                guard oldValue != newValue else {
                    return
                }

                Task {
                    saving = true
                    let saved =
                        await groups.setGroupNotificationMode(
                            groupID: group.id,
                            mode: newValue
                        )
                    saving = false

                    if !saved {
                        mode = oldValue
                    }
                }
            }
            .disabled(saving)
        }
    }

    private var modeDescription: String {
        switch mode {
        case "all":
            return "Receive alerts for new chat messages, official updates, events and challenges."
        case "muted":
            return "No ordinary group activity alerts. Direct @mentions can still alert you if Mentions are enabled globally."
        default:
            return "Receive official group updates, events and challenges, but not every chat message."
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

struct CommunityGroupEventCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var title = ""
    @State private var summary = ""
    @State private var activityType = "running"
    @State private var startsAt = Date().addingTimeInterval(3600)
    @State private var meetingName = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $summary, axis: .vertical)
                        .lineLimit(2...5)

                    Picker("Activity", selection: $activityType) {
                        Text("Run").tag("running")
                        Text("Walk").tag("walking")
                        Text("Strength").tag("strength")
                        Text("Cycling").tag("cycling")
                        Text("Hike").tag("hike")
                        Text("Group workout").tag("group_workout")
                        Text("Other").tag("other")
                    }

                    DatePicker(
                        "Starts",
                        selection: $startsAt,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Meet") {
                    TextField("Meeting point", text: $meetingName)
                }

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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Creating…" : "Create") {
                        Task {
                            saving = true
                            let ok = await groups.createEvent(
                                groupID: group.id,
                                title: title,
                                summary: summary,
                                activityType: activityType,
                                startsAt: startsAt,
                                meetingName: meetingName
                            )
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        meetingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        saving
                    )
                }
            }
        }
    }
}

struct CommunityGroupChallengeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var title = ""
    @State private var summary = ""
    @State private var metric: CommunityGroupChallengeMetric = .distanceKM
    @State private var target = "100"
    @State private var startsAt = Date()
    @State private var endsAt = Calendar.current.date(
        byAdding: .day,
        value: 7,
        to: Date()
    ) ?? Date().addingTimeInterval(604800)
    @State private var saving = false

    private var targetValue: Double? {
        Double(
            target
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Challenge") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $summary, axis: .vertical)
                        .lineLimit(2...5)

                    Picker("Metric", selection: $metric) {
                        ForEach(CommunityGroupChallengeMetric.allCases) {
                            Label($0.title, systemImage: $0.icon)
                                .tag($0)
                        }
                    }

                    HStack {
                        TextField("Target", text: $target)
                            .keyboardType(.decimalPad)
                        Text(metric.unit)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Window") {
                    DatePicker(
                        "Starts",
                        selection: $startsAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Ends",
                        selection: $endsAt,
                        in: startsAt...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section {
                    Label(
                        "Completed member workouts contribute automatically. The same workout is counted only once.",
                        systemImage: "bolt.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Group Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Creating…" : "Create") {
                        guard let targetValue else { return }
                        Task {
                            saving = true
                            let ok = await groups.createChallenge(
                                groupID: group.id,
                                title: title,
                                summary: summary,
                                metric: metric,
                                targetValue: targetValue,
                                startsAt: startsAt,
                                endsAt: endsAt
                            )
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (targetValue ?? 0) <= 0 ||
                        endsAt <= startsAt ||
                        saving
                    )
                }
            }
        }
    }
}
