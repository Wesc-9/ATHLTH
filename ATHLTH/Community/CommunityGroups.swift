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
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case authorID = "author_id"
        case body
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

private struct CommunityGroupInsert: Encodable {
    let id: UUID
    let creatorID: UUID
    let name: String
    let summary: String
    let locationName: String
    let visibility: String

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case name
        case summary
        case locationName = "location_name"
        case visibility
    }
}

private struct CommunityGroupUpdate: Encodable {
    let name: String
    let summary: String
    let locationName: String
    let visibility: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case summary
        case locationName = "location_name"
        case visibility
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

    func challengeProgress(_ challenge: CommunityGroupChallengeRecord) -> Double {
        challengeWorkouts
            .filter { $0.challengeID == challenge.id }
            .reduce(0) { $0 + $1.contribution }
    }

    func refresh() async {
        guard let userID = currentUserID else {
            groups = []
            ownMemberships = []
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

            groups = try await groupsQuery
            ownMemberships = try await membershipsQuery
            communityActivity = try await activityQuery

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

            let loadedMembers = try await membersQuery
            let loadedMessages = try await messagesQuery
            let loadedEvents = try await eventsQuery
            let loadedChallenges = try await challengesQuery
            let loadedAnnouncements = try await announcementsQuery
            let loadedActivity = try await activityQuery
            let loadedProfiles = try await profilesQuery

            membersByGroup[groupID] = loadedMembers
            messagesByGroup[groupID] = loadedMessages
            eventsByGroup[groupID] = loadedEvents
            challengesByGroup[groupID] = loadedChallenges
            announcementsByGroup[groupID] = loadedAnnouncements
            activityByGroup[groupID] = loadedActivity

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
        visibility: String
    ) async -> Bool {
        guard let userID = currentUserID else { return false }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanName.count >= 2 else {
            errorMessage = "Add a group name."
            return false
        }

        do {
            let payload = CommunityGroupInsert(
                id: UUID(),
                creatorID: userID,
                name: String(cleanName.prefix(80)),
                summary: String(summary.prefix(800)),
                locationName: "",
                visibility:
                    visibility == "private"
                        ? "private"
                        : "public"
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
        visibility: String
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
            let payload = CommunityGroupUpdate(
                name: String(cleanName.prefix(80)),
                summary: String(summary.prefix(800)),
                locationName: String(cleanLocation.prefix(120)),
                visibility:
                    visibility == "private"
                        ? "private"
                        : "public",
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

    func postAnnouncement(
        groupID: UUID,
        body: String
    ) async -> Bool {
        guard let userID = currentUserID,
              let group = group(for: groupID),
              canManage(group)
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

    func setMemberRole(
        groupID: UUID,
        userID: UUID,
        role: String
    ) async -> Bool {
        guard let group = group(for: groupID),
              isOwner(of: group),
              role == "admin" || role == "member"
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
        guard let userID = currentUserID,
              !joinedGroupIDs.contains(group.id)
        else { return }

        do {
            try await client
                .from("community_group_members")
                .insert(
                    CommunityGroupMemberInsert(
                        groupID: group.id,
                        userID: userID,
                        role: "member"
                    )
                )
                .execute()

            await refresh()
            await loadGroupContent(group.id)
        } catch {
            errorMessage = error.localizedDescription
        }
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
        guard let userID = currentUserID else { return false }

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
              targetValue > 0,
              endsAt > startsAt
        else {
            errorMessage = "Check the challenge target and dates."
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
            !groups.joinedGroupIDs.contains($0.id)
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
    @EnvironmentObject private var groups: CommunityGroupStore
    @EnvironmentObject private var session: AppSessionStore

    let group: CommunityGroupRecord

    @State private var selectedTab: CommunityGroupsTab = .overview
    @State private var messageDraft = ""
    @State private var showingCreateEvent = false
    @State private var showingCreateChallenge = false
    @State private var showingGroupSettings = false
    @State private var showingPostUpdate = false

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
                        ATHLTHCard {
                            Text("Join to unlock group chat, events and challenges.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button {
                                Task { await groups.join(group) }
                            } label: {
                                Label("Join Group", systemImage: "person.badge.plus")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                            .padding(.top, 8)
                        }
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
        .sheet(isPresented: $showingPostUpdate) {
            CommunityGroupAnnouncementCreateView(
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
    }

    private var groupHeader: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                detailGroupImage

                VStack(alignment: .leading, spacing: 5) {
                    Text(currentGroup.name)
                        .font(.title3.weight(.bold))

                    if !currentGroup.locationName
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty {
                        Label(
                            currentGroup.locationName,
                            systemImage: "location.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Label(
                        currentGroup.visibility == "private"
                            ? "Private group"
                            : "Public group",
                        systemImage:
                            currentGroup.visibility == "private"
                                ? "lock.fill"
                                : "globe"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        currentGroup.visibility == "private"
                            ? ATHLTHTheme.mutedText
                            : ATHLTHTheme.accentDeep
                    )

                    if isMember {
                        Text(memberCountText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                }

                Spacer()

                if groups.canManage(currentGroup) {
                    Menu {
                        Button {
                            showingPostUpdate = true
                        } label: {
                            Label(
                                "Post Group Update",
                                systemImage: "megaphone.fill"
                            )
                        }

                        Button {
                            showingGroupSettings = true
                        } label: {
                            Label(
                                "Group Settings",
                                systemImage: "gearshape"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 34, height: 34)
                    }
                } else if isMember {
                    Menu {
                        Button("Leave Group", role: .destructive) {
                            Task {
                                await groups.leave(currentGroup)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 34, height: 34)
                    }
                }
            }

            if !currentGroup.summary.isEmpty {
                Text(currentGroup.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private var detailGroupImage: some View {
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
            .frame(width: 58, height: 58)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        } else {
            detailGroupImageFallback
        }
    }

    private var detailGroupImageFallback: some View {
        Image(systemName: "person.3.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.indigo)
            .frame(width: 58, height: 58)
            .background(
                Color.indigo.opacity(0.09),
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
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
            if let update = groups.announcements(
                in: group.id
            ).first {
                groupUpdateCard(update)
            } else if groups.canManage(currentGroup) {
                Button {
                    showingPostUpdate = true
                } label: {
                    ATHLTHCard {
                        HStack(spacing: 12) {
                            Image(systemName: "megaphone.fill")
                                .foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Post your first group update")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Updates appear here and in Community Activity.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

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

            if let next = groups.events(in: group.id)
                .filter({ $0.startsAt >= Date() })
                .sorted(by: { $0.startsAt < $1.startsAt })
                .first {
                ATHLTHCard {
                    Text("Next Event")
                        .font(.headline)
                    Text(next.title)
                        .font(.title3.weight(.bold))
                        .padding(.top, 4)
                    Text(
                        next.startsAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ) + " · " + next.meetingName
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let active = groups.challenges(in: group.id)
                .filter({ $0.startsAt <= Date() && $0.endsAt >= Date() })
                .first {
                groupChallengeCard(active)
            }
        }
    }

    private func groupUpdateCard(
        _ update: CommunityGroupAnnouncementRecord
    ) -> some View {
        ATHLTHCard {
            HStack {
                Label(
                    "Group Update",
                    systemImage: "megaphone.fill"
                )
                .font(.headline)
                .foregroundStyle(.indigo)

                Spacer()

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
                Text("Posted by \(author.resolvedName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            if groups.canManage(currentGroup) {
                Button("Post another update") {
                    showingPostUpdate = true
                }
                .font(.caption.weight(.semibold))
                .padding(.top, 6)
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
                        description: Text("Start the group conversation.")
                    )
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 12) {
                        ForEach(groups.messages(in: group.id)) { message in
                            messageRow(message)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Message group", text: $messageDraft, axis: .vertical)
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
                            senderName: session.profile.displayName,
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

    private var events: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Group Events")
                        .font(.title3.weight(.bold))
                    Text("Only members of this group can see these events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingCreateEvent = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }

            if groups.events(in: group.id).isEmpty {
                ContentUnavailableView(
                    "No group events",
                    systemImage: "calendar.badge.plus",
                    description: Text("Create the first event for this group.")
                )
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(groups.events(in: group.id)) { event in
                        HStack(spacing: 12) {
                            Image(systemName: eventIcon(event.activityType))
                                .foregroundStyle(.purple)
                                .frame(width: 38, height: 38)
                                .background(
                                    Color.purple.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(
                                    event.startsAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    ) + " · " + event.meetingName
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 10)

                        if event.id != groups.events(in: group.id).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var challenges: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Group Challenges")
                        .font(.title3.weight(.bold))
                    Text("Every completed member workout can contribute automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingCreateChallenge = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
            }

            if groups.challenges(in: group.id).isEmpty {
                ContentUnavailableView(
                    "No group challenges",
                    systemImage: "bolt.badge.plus",
                    description: Text("Create a collective goal for the group.")
                )
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(groups.challenges(in: group.id)) { challenge in
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
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Image") {
                    HStack {
                        Spacer()
                        groupImagePreview
                        Spacer()
                    }

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            selectedImageData == nil
                                ? "Choose Image"
                                : "Change Image",
                            systemImage: "photo"
                        )
                    }

                    if group.imageURL != nil {
                        Button(
                            "Remove Image",
                            role: .destructive
                        ) {
                            Task {
                                saving = true
                                _ = await groups.removeGroupImage(group)
                                saving = false
                            }
                        }
                    }
                }

                Section("Group") {
                    TextField("Group name", text: $name)
                    TextField("Description", text: $summary, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Visibility") {
                    Picker("Group visibility", selection: $visibility) {
                        Label("Public", systemImage: "globe")
                            .tag("public")
                        Label("Private", systemImage: "lock.fill")
                            .tag("private")
                    }
                    .pickerStyle(.segmented)

                    Text(
                        visibility == "public"
                            ? "Public groups appear in Discover and can be joined by signed-in ATHLTH users."
                            : "Private groups do not appear in Discover. Only the owner and existing members can see the group."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Label(
                        "Group chat, events and challenges are visible only to members.",
                        systemImage: "hand.raised.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Creating…" : "Create") {
                        Task {
                            saving = true
                            let ok = await groups.createGroup(
                                name: name,
                                summary: summary,
                                visibility: visibility
                            )
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 ||
                        saving
                    )
                }
            }
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var saving = false

    init(group: CommunityGroupRecord) {
        self.group = group
        _name = State(initialValue: group.name)
        _summary = State(initialValue: group.summary)
        _visibility = State(initialValue: group.visibility)
    }

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
                            ? "Public groups appear in Discover and can be joined by signed-in ATHLTH users."
                            : "Private groups are hidden from Discover. Existing members keep access."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                            saving = true
                            let ok = await groups.updateGroup(
                                group,
                                name: name,
                                locationName: group.locationName,
                                summary: summary,
                                visibility: visibility
                            )
                            saving = false

                            if ok {
                                if let selectedImageData {
                                    _ = await groups.uploadGroupImage(
                                        group,
                                        jpegData: selectedImageData
                                    )
                                }
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
            .onChange(of: selectedPhoto) { _, item in
                guard let item else {
                    return
                }

                Task {
                    do {
                        guard
                            let data = try await item
                                .loadTransferable(type: Data.self),
                            let image = UIImage(data: data),
                            let jpeg = image.jpegData(
                                compressionQuality: 0.82
                            )
                        else {
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
    private var groupImagePreview: some View {
        if let selectedImageData,
           let image = UIImage(data: selectedImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 24,
                        style: .continuous
                    )
                )
        } else if let value = group.imageURL,
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
            .frame(width: 120, height: 120)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
            )
        } else {
            groupImagePlaceholder
        }
    }

    private var groupImagePlaceholder: some View {
        Image(systemName: "person.3.fill")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.indigo)
            .frame(width: 120, height: 120)
            .background(
                Color.indigo.opacity(0.09),
                in: RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
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
                    "Group joins, admin updates, events and challenges will appear here."
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

struct CommunityGroupAnnouncementCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    @State private var bodyText = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Update") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 150)

                    Text("\(bodyText.count)/1200")
                        .font(.caption2)
                        .foregroundStyle(
                            bodyText.count > 1200
                                ? .red
                                : .secondary
                        )
                }

                Section {
                    Text(
                        "This is an announcement, not a chat message. Members will see it in the group Overview and Community Activity."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Post Group Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Posting…" : "Post") {
                        Task {
                            saving = true
                            let ok = await groups.postAnnouncement(
                                groupID: group.id,
                                body: bodyText
                            )
                            saving = false

                            if ok {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        bodyText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty ||
                        bodyText.count > 1200 ||
                        saving
                    )
                }
            }
        }
    }
}

struct CommunityGroupMembersView: View {
    @EnvironmentObject private var groups: CommunityGroupStore

    let group: CommunityGroupRecord

    private var sortedMembers: [CommunityGroupMemberRecord] {
        groups.members(in: group.id).sorted {
            roleRank($0.role) < roleRank($1.role)
        }
    }

    var body: some View {
        List {
            ForEach(sortedMembers, id: \.userID) { member in
                memberRow(member)
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await groups.loadGroupContent(group.id)
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.resolvedName)
                        .font(.subheadline.weight(.semibold))

                    if let username = profile.username {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Group member")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            Text(roleTitle(member.role))
                .font(.caption2.weight(.bold))
                .foregroundStyle(
                    member.role == "owner"
                        ? ATHLTHTheme.premiumGold
                        : member.role == "admin"
                            ? .indigo
                            : .secondary
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: Capsule()
                )

            if groups.isOwner(of: group) &&
                member.role != "owner" {
                Menu {
                    if member.role == "admin" {
                        Button("Make Member") {
                            Task {
                                _ = await groups.setMemberRole(
                                    groupID: group.id,
                                    userID: member.userID,
                                    role: "member"
                                )
                            }
                        }
                    } else {
                        Button("Make Admin") {
                            Task {
                                _ = await groups.setMemberRole(
                                    groupID: group.id,
                                    userID: member.userID,
                                    role: "admin"
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                }
            }
        }
    }

    private func roleRank(_ role: String) -> Int {
        switch role {
        case "owner": return 0
        case "admin": return 1
        default: return 2
        }
    }

    private func roleTitle(_ role: String) -> String {
        switch role {
        case "owner": return "Owner"
        case "admin": return "Admin"
        default: return "Member"
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
