import Foundation
@preconcurrency import CoreLocation
@preconcurrency import MapKit
import Supabase
import SwiftUI
import PhotosUI
import UIKit

enum CommunityEventActivity: String, CaseIterable, Codable, Hashable, Identifiable {
    case running
    case walking
    case strength
    case cycling
    case hike
    case groupWorkout = "group_workout"
    case other

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
                norwegian: "Gåtur"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .cycling:
            return ATHLTHLocalization.choose(
                english: "Cycling",
                norwegian: "Sykling"
            )
        case .hike:
            return ATHLTHLocalization.choose(
                english: "Hike",
                norwegian: "Tur"
            )
        case .groupWorkout:
            return ATHLTHLocalization.choose(
                english: "Group workout",
                norwegian: "Gruppeøkt"
            )
        case .other:
            return ATHLTHLocalization.choose(
                english: "Other",
                norwegian: "Annet"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        case .cycling: return "bicycle"
        case .hike: return "mountain.2.fill"
        case .groupWorkout: return "person.3.fill"
        case .other: return "sparkles"
        }
    }
}

enum CommunityEventCoverPolicy {
    static let standardArtworkOptions: [String] = [
        "GoalRunning",
        "GoalSprint",
        "GoalWalking",
        "GoalStrength",
        "GoalEndurance",
        "GoalMountain",
        "GoalEvent",
        "GoalAdventure",
        "GoalConsistency",
        "GoalProgress",
        "GoalRecovery",
        "GoalRelax"
    ]

    /// Standard event artwork now has a concrete runtime image in every
    /// semantic image set. Keep this indirection so older persisted events
    /// and future aliases still have one rendering path.
    static func displayArtworkName(
        _ artwork: String
    ) -> String {
        artwork
    }

    /// Every standard goal has a dedicated cropped picker thumbnail,
    /// including the semantic covers that share a full-resolution image.
    static func thumbnailArtworkName(
        _ artwork: String
    ) -> String {
        "\(artwork)Thumbnail"
    }

    static func defaultArtwork(
        for activity: CommunityEventActivity
    ) -> String {
        switch activity {
        case .running:
            return "GoalRunning"
        case .walking:
            return "GoalWalking"
        case .strength:
            return "GoalStrength"
        case .cycling:
            return "GoalAdventure"
        case .hike:
            return "GoalMountain"
        case .groupWorkout:
            return "GoalConsistency"
        case .other:
            return "GoalEvent"
        }
    }
}

struct CommunityEventRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let activityType: CommunityEventActivity
    let visibility: String
    let status: String
    let startsAt: Date
    let endsAt: Date?
    let meetingName: String
    let meetingDetails: String?
    let latitude: Double?
    let longitude: Double?
    let maxParticipants: Int?
    let paceLabel: String?
    let routeID: UUID?
    let routeTitle: String?
    let routeCoordinates: [RouteCoordinate]?
    let routeDistanceKilometers: Double?
    let routeElevationGainMeters: Double?
    let routeStartName: String?
    let routeEndName: String?
    let coverArtworkName: String?
    let coverImageURL: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case title
        case summary
        case activityType = "activity_type"
        case visibility
        case status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case meetingName = "meeting_name"
        case meetingDetails = "meeting_details"
        case latitude
        case longitude
        case maxParticipants = "max_participants"
        case paceLabel = "pace_label"
        case routeID = "route_id"
        case routeTitle = "route_title"
        case routeCoordinates = "route_coordinates"
        case routeDistanceKilometers =
            "route_distance_kilometers"
        case routeElevationGainMeters =
            "route_elevation_gain_meters"
        case routeStartName =
            "route_start_name"
        case routeEndName =
            "route_end_name"
        case coverArtworkName = "cover_artwork_name"
        case coverImageURL = "cover_image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum CommunityEventAttendance: String, Codable, Hashable {
    case going
    case maybe
}

enum CommunityEventLifecycleStatus:
    String,
    Codable,
    Hashable
{
    case upcoming
    case live
    case completed
    case cancelled

    var title: String {
        switch self {
        case .upcoming:
            return ATHLTHLocalization.choose(
                english: "Planned",
                norwegian: "Planlagt"
            )
        case .live:
            return ATHLTHLocalization.choose(
                english: "Started",
                norwegian: "Startet"
            )
        case .completed:
            return ATHLTHLocalization.choose(
                english: "Completed",
                norwegian: "Fullført"
            )
        case .cancelled:
            return ATHLTHLocalization.choose(
                english: "Cancelled",
                norwegian: "Avlyst"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .upcoming:
            return "calendar"
        case .live:
            return "play.circle.fill"
        case .completed:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.circle.fill"
        }
    }
}

enum CommunityEventCheckInMethod:
    String,
    Codable,
    Hashable
{
    case proximity
    case manual
}

struct CommunityEventParticipantRecord: Codable, Hashable {
    let eventID: UUID
    let userID: UUID
    let joinedAt: Date
    let attendanceStatus: CommunityEventAttendance
    let checkedInAt: Date?
    let checkInMethod:
        CommunityEventCheckInMethod?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
        case attendanceStatus = "attendance_status"
        case checkedInAt = "checked_in_at"
        case checkInMethod = "check_in_method"
    }
}

struct CommunityEventItem: Identifiable, Hashable {
    var id: UUID { event.id }

    let event: CommunityEventRecord
    let creator: SocialProfileCard?
    let participantRows: [CommunityEventParticipantRecord]
    let participantProfiles: [SocialProfileCard]

    var participantCount: Int {
        1 + participantRows.filter {
            $0.attendanceStatus == .going
        }.count
    }

    var checkedInCount: Int {
        participantRows.filter {
            $0.checkedInAt != nil
        }.count
    }
}

struct CommunityEventDraft:
    Codable,
    Hashable
{
    var title = ""
    var summary = ""
    var activityType: CommunityEventActivity = .running
    var visibility: ProfileVisibility = .publicProfile
    var startsAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    var meetingName = ""
    var meetingDetails = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var maxParticipants: Int? = nil
    var paceLabel = ""
    var routeID: UUID? = nil
    var routeTitle: String? = nil
    var routeCoordinates: [RouteCoordinate]? = nil
    var routeDistanceKilometers: Double? = nil
    var routeElevationGainMeters: Double? = nil
    var routeStartName: String? = nil
    var routeEndName: String? = nil
    var coverArtworkName: String? = nil
    var coverImageURL: String? = nil

    func isValidForCreation(
        now: Date = Date()
    ) -> Bool {
        !title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        startsAt > now
    }
}

private struct CommunityEventCreationDraftSnapshot:
    Codable
{
    var draft: CommunityEventDraft
    var limitParticipants: Bool
    var maxParticipants: Int
    var selectedRouteID: UUID?
    var shareToCommunity: Bool
    var selectedCoverArtworkName: String
    var coverWasManuallySelected: Bool
}

private enum CommunityEventCreationDraftStore {
    private static let prefix =
        "community.event.create.draft.v1."

    static func load(
        userID: UUID
    ) -> CommunityEventCreationDraftSnapshot? {
        guard let data =
                UserDefaults.standard.data(
                    forKey:
                        key(userID)
                )
        else {
            return nil
        }

        return try? JSONDecoder().decode(
            CommunityEventCreationDraftSnapshot.self,
            from: data
        )
    }

    static func save(
        _ snapshot:
            CommunityEventCreationDraftSnapshot,
        userID: UUID
    ) {
        guard let data =
                try? JSONEncoder().encode(
                    snapshot
                )
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey:
                key(userID)
        )
    }

    static func clear(
        userID: UUID
    ) {
        UserDefaults.standard.removeObject(
            forKey:
                key(userID)
        )
    }

    private static func key(
        _ userID: UUID
    ) -> String {
        prefix +
        userID.uuidString.lowercased()
    }
}

private struct CommunityEventWrite: Encodable {
    let id: UUID
    let creatorID: UUID
    let title: String
    let summary: String
    let activityType: String
    let visibility: String
    let status: String
    let startsAt: Date
    let meetingName: String
    let meetingDetails: String?
    let latitude: Double?
    let longitude: Double?
    let maxParticipants: Int?
    let paceLabel: String?
    let routeID: UUID?
    let routeTitle: String?
    let routeCoordinates: [RouteCoordinate]?
    let routeDistanceKilometers: Double?
    let routeElevationGainMeters: Double?
    let routeStartName: String?
    let routeEndName: String?
    let coverArtworkName: String?
    let coverImageURL: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case title
        case summary
        case activityType = "activity_type"
        case visibility
        case status
        case startsAt = "starts_at"
        case meetingName = "meeting_name"
        case meetingDetails = "meeting_details"
        case latitude
        case longitude
        case maxParticipants = "max_participants"
        case paceLabel = "pace_label"
        case routeID = "route_id"
        case routeTitle = "route_title"
        case routeCoordinates = "route_coordinates"
        case routeDistanceKilometers =
            "route_distance_kilometers"
        case routeElevationGainMeters =
            "route_elevation_gain_meters"
        case routeStartName =
            "route_start_name"
        case routeEndName =
            "route_end_name"
        case coverArtworkName = "cover_artwork_name"
        case coverImageURL = "cover_image_url"
        case updatedAt = "updated_at"
    }
}


private struct CommunityEventUpdate: Encodable {
    let title: String
    let summary: String
    let activityType: String
    let visibility: String
    let startsAt: Date
    let meetingName: String
    let meetingDetails: String?
    let latitude: Double?
    let longitude: Double?
    let maxParticipants: Int?
    let paceLabel: String?
    let routeID: UUID?
    let routeTitle: String?
    let routeCoordinates: [RouteCoordinate]?
    let routeDistanceKilometers: Double?
    let routeElevationGainMeters: Double?
    let routeStartName: String?
    let routeEndName: String?
    let coverArtworkName: String?
    let coverImageURL: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case activityType = "activity_type"
        case visibility
        case startsAt = "starts_at"
        case meetingName = "meeting_name"
        case meetingDetails = "meeting_details"
        case latitude
        case longitude
        case maxParticipants = "max_participants"
        case paceLabel = "pace_label"
        case routeID = "route_id"
        case routeTitle = "route_title"
        case routeCoordinates = "route_coordinates"
        case routeDistanceKilometers =
            "route_distance_kilometers"
        case routeElevationGainMeters =
            "route_elevation_gain_meters"
        case routeStartName = "route_start_name"
        case routeEndName = "route_end_name"
        case coverArtworkName = "cover_artwork_name"
        case coverImageURL = "cover_image_url"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container =
            encoder.container(keyedBy: CodingKeys.self)

        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(
            activityType,
            forKey: .activityType
        )
        try container.encode(
            visibility,
            forKey: .visibility
        )
        try container.encode(startsAt, forKey: .startsAt)
        try container.encode(
            meetingName,
            forKey: .meetingName
        )
        try container.encode(
            meetingDetails,
            forKey: .meetingDetails
        )
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(
            maxParticipants,
            forKey: .maxParticipants
        )
        try container.encode(paceLabel, forKey: .paceLabel)
        try container.encode(routeID, forKey: .routeID)
        try container.encode(routeTitle, forKey: .routeTitle)
        try container.encode(
            routeCoordinates,
            forKey: .routeCoordinates
        )
        try container.encode(
            routeDistanceKilometers,
            forKey: .routeDistanceKilometers
        )
        try container.encode(
            routeElevationGainMeters,
            forKey: .routeElevationGainMeters
        )
        try container.encode(
            routeStartName,
            forKey: .routeStartName
        )
        try container.encode(
            routeEndName,
            forKey: .routeEndName
        )
        try container.encode(
            coverArtworkName,
            forKey: .coverArtworkName
        )
        try container.encode(
            coverImageURL,
            forKey: .coverImageURL
        )
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct CommunityParticipantWrite: Encodable {
    let eventID: UUID
    let userID: UUID
    let attendanceStatus: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case userID = "user_id"
        case attendanceStatus = "attendance_status"
    }
}

private struct CommunityEventLifecycleParams:
    Encodable
{
    let eventID: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case eventID = "p_event_id"
        case status = "p_status"
    }
}

private struct CommunityEventCheckInUpdate:
    Encodable
{
    let attendanceStatus: String
    let checkInMethod: String

    enum CodingKeys: String, CodingKey {
        case attendanceStatus =
            "attendance_status"
        case checkInMethod =
            "check_in_method"
    }
}

private struct CommunityResolvedCoordinate: Sendable {
    let latitude: Double
    let longitude: Double
}

@MainActor
final class SupabaseCommunityService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func loadEvents() async throws -> [CommunityEventItem] {
        let events: [CommunityEventRecord] = try await client
            .from("community_events")
            .select()
            .order("starts_at", ascending: true)
            .execute()
            .value

        let participants: [CommunityEventParticipantRecord] = try await client
            .from("community_event_participants")
            .select()
            .execute()
            .value

        let profiles: [SocialProfileCard] = try await client
            .from("social_profile_cards")
            .select()
            .execute()
            .value

        let profilesByID = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.userID, $0) }
        )

        return events.map { event in
            let eventParticipants = participants.filter {
                $0.eventID == event.id
            }
            return CommunityEventItem(
                event: event,
                creator: profilesByID[event.creatorID],
                participantRows: eventParticipants,
                participantProfiles: eventParticipants.compactMap {
                    profilesByID[$0.userID]
                }
            )
        }
    }

    func searchEvents(
        _ query: String,
        limit: Int = 20
    ) async throws -> [CommunityEventItem] {
        let clean = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard clean.count >= 2 else { return [] }

        let boundedLimit = min(max(limit, 8), 32)
        let pattern = "%\(clean)%"

        async let titleRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("title", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let meetingRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("meeting_name", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let summaryRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("summary", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let routeRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("route_title", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        async let detailRows: [CommunityEventRecord] = client
            .from("community_events")
            .select()
            .ilike("meeting_details", pattern: pattern)
            .limit(boundedLimit)
            .execute()
            .value

        let (
            titles,
            meetings,
            summaries,
            routes,
            details
        ) = try await (
            titleRows,
            meetingRows,
            summaryRows,
            routeRows,
            detailRows
        )

        var seen = Set<UUID>()
        let matchedEvents = (
            titles +
            meetings +
            summaries +
            routes +
            details
        )
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let lhsUpcoming =
                    lhs.status == "upcoming" &&
                    lhs.startsAt >= Date()
                let rhsUpcoming =
                    rhs.status == "upcoming" &&
                    rhs.startsAt >= Date()

                if lhsUpcoming != rhsUpcoming {
                    return lhsUpcoming
                }

                return lhs.startsAt < rhs.startsAt
            }
            .prefix(boundedLimit)
            .map { $0 }

        guard !matchedEvents.isEmpty else { return [] }

        let eventIDs = matchedEvents.map { $0.id.uuidString }

        let participants: [CommunityEventParticipantRecord] = try await client
            .from("community_event_participants")
            .select()
            .in("event_id", values: eventIDs)
            .execute()
            .value

        var profileIDs = Set(matchedEvents.map(\.creatorID))
        profileIDs.formUnion(participants.map(\.userID))

        let profiles: [SocialProfileCard]
        if profileIDs.isEmpty {
            profiles = []
        } else {
            profiles = try await client
                .from("social_profile_cards")
                .select()
                .in(
                    "user_id",
                    values: profileIDs.map(\.uuidString)
                )
                .execute()
                .value
        }

        let profilesByID = Dictionary(
            uniqueKeysWithValues: profiles.map {
                ($0.userID, $0)
            }
        )

        return matchedEvents.map { event in
            let eventParticipants = participants.filter {
                $0.eventID == event.id
            }

            return CommunityEventItem(
                event: event,
                creator: profilesByID[event.creatorID],
                participantRows: eventParticipants,
                participantProfiles: eventParticipants.compactMap {
                    profilesByID[$0.userID]
                }
            )
        }
    }

    func createEvent(
        _ draft: CommunityEventDraft,
        eventID: UUID = UUID()
    ) async throws -> UUID {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMeeting = draft.meetingName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else {
            throw CommunityEventError.invalidEvent
        }

        let resolvedCoordinate: CLLocationCoordinate2D?
        if let latitude = draft.latitude,
           let longitude = draft.longitude {
            resolvedCoordinate = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
        } else if !cleanMeeting.isEmpty {
            resolvedCoordinate =
                await resolveMeetingCoordinate(
                    cleanMeeting
                )
        } else {
            resolvedCoordinate = nil
        }

        try await client
            .from("community_events")
            .insert(
                CommunityEventWrite(
                    id: eventID,
                    creatorID: currentUserID,
                    title: cleanTitle,
                    summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                    activityType: draft.activityType.rawValue,
                    visibility: draft.visibility.rawValue,
                    status: "upcoming",
                    startsAt: draft.startsAt,
                    meetingName: cleanMeeting,
                    meetingDetails: draft.meetingDetails.nilIfBlank,
                    latitude: resolvedCoordinate?.latitude,
                    longitude: resolvedCoordinate?.longitude,
                    maxParticipants: draft.maxParticipants,
                    paceLabel: draft.paceLabel.nilIfBlank,
                    routeID: draft.routeID,
                    routeTitle: draft.routeTitle,
                    routeCoordinates:
                        draft.routeCoordinates,
                    routeDistanceKilometers:
                        draft.routeDistanceKilometers,
                    routeElevationGainMeters:
                        draft.routeElevationGainMeters,
                    routeStartName:
                        draft.routeStartName,
                    routeEndName:
                        draft.routeEndName,
                    coverArtworkName:
                        draft.coverArtworkName,
                    coverImageURL:
                        draft.coverImageURL,
                    updatedAt: Date()
                )
            )
            .execute()

        return eventID
    }


    func updateEvent(
        eventID: UUID,
        draft: CommunityEventDraft
    ) async throws {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        let cleanTitle =
            draft.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let cleanMeeting =
            draft.meetingName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !cleanTitle.isEmpty else {
            throw CommunityEventError.invalidEvent
        }

        let resolvedCoordinate:
            CLLocationCoordinate2D?
        if let latitude = draft.latitude,
           let longitude = draft.longitude {
            resolvedCoordinate =
                CLLocationCoordinate2D(
                    latitude: latitude,
                    longitude: longitude
                )
        } else if !cleanMeeting.isEmpty {
            resolvedCoordinate =
                await resolveMeetingCoordinate(
                    cleanMeeting
                )
        } else {
            resolvedCoordinate = nil
        }

        try await client
            .from("community_events")
            .update(
                CommunityEventUpdate(
                    title: cleanTitle,
                    summary:
                        draft.summary
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            ),
                    activityType:
                        draft.activityType.rawValue,
                    visibility:
                        draft.visibility.rawValue,
                    startsAt: draft.startsAt,
                    meetingName: cleanMeeting,
                    meetingDetails:
                        draft.meetingDetails
                            .nilIfBlank,
                    latitude:
                        resolvedCoordinate?
                            .latitude,
                    longitude:
                        resolvedCoordinate?
                            .longitude,
                    maxParticipants:
                        draft.maxParticipants,
                    paceLabel:
                        draft.paceLabel
                            .nilIfBlank,
                    routeID: draft.routeID,
                    routeTitle:
                        draft.routeTitle,
                    routeCoordinates:
                        draft.routeCoordinates,
                    routeDistanceKilometers:
                        draft
                            .routeDistanceKilometers,
                    routeElevationGainMeters:
                        draft
                            .routeElevationGainMeters,
                    routeStartName:
                        draft.routeStartName,
                    routeEndName:
                        draft.routeEndName,
                    coverArtworkName:
                        draft.coverArtworkName,
                    coverImageURL:
                        draft.coverImageURL,
                    updatedAt: Date()
                )
            )
            .eq("id", value: eventID)
            .eq(
                "creator_id",
                value: currentUserID
            )
            .execute()
    }

    func uploadEventCover(
        eventID: UUID,
        jpegData: Data
    ) async throws -> String {
        guard let userID = currentUserID else {
            throw CommunityEventError
                .notAuthenticated
        }

        guard !jpegData.isEmpty,
              jpegData.count <=
                10_485_760
        else {
            throw CommunityEventError
                .invalidEvent
        }

        let published =
            try await ATHLTHPublicImagePublisher
                .publish(
                    jpegData: jpegData,
                    purpose:
                        .eventCover,
                    entityID:
                        eventID,
                    client: client
                )

        return published.url.absoluteString
    }

    func removeEventCover(
        eventID: UUID
    ) async throws {
        guard let userID = currentUserID else {
            throw CommunityEventError
                .notAuthenticated
        }

        let storagePath =
            "\(userID.uuidString.lowercased())/" +
            "event-covers/" +
            "\(eventID.uuidString.lowercased()).jpg"

        try await client.storage
            .from("workout-media")
            .remove(
                paths: [storagePath]
            )
    }

    private func resolveMeetingCoordinate(
        _ query: String
    ) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [
            .address,
            .pointOfInterest
        ]

        let resolved:
            CommunityResolvedCoordinate? =
                await withCheckedContinuation {
                    (
                        continuation:
                            CheckedContinuation<
                                CommunityResolvedCoordinate?,
                                Never
                            >
                    ) in

                    MKLocalSearch(request: request)
                        .start { response, _ in
                            guard let coordinate =
                                    response?
                                        .mapItems
                                        .first?
                                        .placemark
                                        .coordinate
                            else {
                                continuation.resume(
                                    returning: nil
                                )
                                return
                            }

                            continuation.resume(
                                returning:
                                    CommunityResolvedCoordinate(
                                        latitude:
                                            coordinate.latitude,
                                        longitude:
                                            coordinate.longitude
                                    )
                            )
                        }
                }

        guard let resolved else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: resolved.latitude,
            longitude: resolved.longitude
        )
    }

    func setAttendance(
        eventID: UUID,
        status: CommunityEventAttendance
    ) async throws {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        try await client
            .from("community_event_participants")
            .upsert(
                CommunityParticipantWrite(
                    eventID: eventID,
                    userID: currentUserID,
                    attendanceStatus: status.rawValue
                )
            )
            .execute()
    }

    func join(eventID: UUID) async throws {
        try await setAttendance(
            eventID: eventID,
            status: .going
        )
    }

    func maybe(eventID: UUID) async throws {
        try await setAttendance(
            eventID: eventID,
            status: .maybe
        )
    }

    func checkIn(
        eventID: UUID,
        method: CommunityEventCheckInMethod
    ) async throws {
        guard let currentUserID else {
            throw CommunityEventError
                .notAuthenticated
        }

        try await client
            .from(
                "community_event_participants"
            )
            .update(
                CommunityEventCheckInUpdate(
                    attendanceStatus:
                        CommunityEventAttendance
                            .going.rawValue,
                    checkInMethod:
                        method.rawValue
                )
            )
            .eq(
                "event_id",
                value: eventID
            )
            .eq(
                "user_id",
                value: currentUserID
            )
            .execute()
    }

    func leave(eventID: UUID) async throws {
        guard let currentUserID else {
            throw CommunityEventError.notAuthenticated
        }

        try await client
            .from("community_event_participants")
            .delete()
            .eq("event_id", value: eventID)
            .eq("user_id", value: currentUserID)
            .execute()
    }

    func setLifecycle(
        eventID: UUID,
        status: CommunityEventLifecycleStatus
    ) async throws {
        try await client
            .rpc(
                "community_event_set_lifecycle",
                params:
                    CommunityEventLifecycleParams(
                        eventID: eventID,
                        status: status.rawValue
                    )
            )
            .execute()
    }

    func cancel(eventID: UUID) async throws {
        try await setLifecycle(
            eventID: eventID,
            status: .cancelled
        )
    }
}

enum CommunityEventError: LocalizedError {
    case notAuthenticated
    case invalidEvent
    case eventFull

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to use Community events."
        case .invalidEvent:
            return "Add an event name and choose a future start time."
        case .eventFull:
            return "This event is full."
        }
    }
}

@MainActor
final class CommunityEventStore: ObservableObject {
    @Published private(set) var events: [CommunityEventItem] = []
    @Published private(set) var searchResults: [CommunityEventItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: SupabaseCommunityService
    private var lastRefreshAt: Date?

    init(service: SupabaseCommunityService = SupabaseCommunityService()) {
        self.service = service
    }

    var currentUserID: UUID? {
        service.currentUserID
    }

    var upcomingEvents: [CommunityEventItem] {
        events
            .filter {
                $0.event.status == "upcoming" ||
                $0.event.status == "live"
            }
            .sorted { lhs, rhs in
                if lhs.event.status !=
                    rhs.event.status {
                    return lhs.event.status ==
                        "live"
                }

                return lhs.event.startsAt <
                    rhs.event.startsAt
            }
    }

    func refresh(force: Bool = false) async {
        guard currentUserID != nil else {
            events = []
            return
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 120 {
            return
        }

        guard !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedEvents = try await service.loadEvents()

            guard !Task.isCancelled else {
                return
            }

            if events != loadedEvents {
                events = loadedEvents
            }
            lastRefreshAt = Date()
            errorMessage = nil
        } catch is CancellationError {
            // SwiftUI can legitimately cancel .task work when the view
            // refreshes, disappears or another refresh supersedes it.
            // This is not a user-facing Community error.
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        let requestedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard requestedQuery.count >= 2,
              currentUserID != nil
        else {
            searchResults = []
            return
        }

        do {
            let results = try await service.searchEvents(requestedQuery)
            guard !Task.isCancelled else { return }

            searchResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }

    func clearSearch() {
        searchResults = []
    }

    func create(_ draft: CommunityEventDraft) async -> Bool {
        do {
            _ = try await service
                .createEvent(draft)
            await refresh(force: true)
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func createAndReturnID(
        _ draft: CommunityEventDraft,
        eventID: UUID = UUID()
    ) async -> UUID? {
        do {
            let createdEventID =
                try await service
                    .createEvent(
                        draft,
                        eventID:
                            eventID
                    )
            await refresh(force: true)
            return createdEventID
        } catch {
            errorMessage =
                error.localizedDescription
            return nil
        }
    }


    func update(
        _ item: CommunityEventItem,
        with draft: CommunityEventDraft
    ) async -> Bool {
        do {
            try await service.updateEvent(
                eventID: item.id,
                draft: draft
            )
            await refresh(force: true)
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func uploadEventCover(
        eventID: UUID,
        jpegData: Data
    ) async -> String? {
        do {
            return try await service
                .uploadEventCover(
                    eventID: eventID,
                    jpegData: jpegData
                )
        } catch {
            errorMessage =
                error.localizedDescription
            return nil
        }
    }

    func removeEventCover(
        eventID: UUID
    ) async {
        do {
            try await service
                .removeEventCover(
                    eventID: eventID
                )
        } catch {
            // Best-effort cleanup only.
        }
    }

    func join(_ item: CommunityEventItem) async {
        if let maximum = item.event.maxParticipants,
           item.participantCount >= maximum {
            errorMessage = CommunityEventError.eventFull.localizedDescription
            return
        }

        do {
            try await service.join(eventID: item.id)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func maybe(_ item: CommunityEventItem) async {
        do {
            try await service.maybe(eventID: item.id)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkIn(
        _ item: CommunityEventItem,
        method: CommunityEventCheckInMethod
    ) async -> Bool {
        do {
            try await service.checkIn(
                eventID: item.id,
                method: method
            )
            await refresh(force: true)
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func leave(_ item: CommunityEventItem) async {
        do {
            try await service.leave(eventID: item.id)
            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLifecycle(
        _ item: CommunityEventItem,
        status: CommunityEventLifecycleStatus
    ) async -> Bool {
        do {
            try await service.setLifecycle(
                eventID: item.id,
                status: status
            )
            await refresh(force: true)
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }

    func cancel(_ item: CommunityEventItem) async {
        _ = await setLifecycle(
            item,
            status: .cancelled
        )
    }

    func item(id: UUID) -> CommunityEventItem? {
        events.first { $0.id == id } ??
            searchResults.first { $0.id == id }
    }

    func attendance(
        for item: CommunityEventItem
    ) -> CommunityEventAttendance? {
        guard let currentUserID else { return nil }

        return item.participantRows.first {
            $0.userID == currentUserID
        }?.attendanceStatus
    }

    func isJoined(_ item: CommunityEventItem) -> Bool {
        attendance(for: item) == .going
    }

    func isMaybe(_ item: CommunityEventItem) -> Bool {
        attendance(for: item) == .maybe
    }

    func checkInRecord(
        for item: CommunityEventItem
    ) -> CommunityEventParticipantRecord? {
        guard let currentUserID else {
            return nil
        }

        return item.participantRows.first {
            $0.userID == currentUserID &&
            $0.checkedInAt != nil
        }
    }

    func isCheckedIn(
        _ item: CommunityEventItem
    ) -> Bool {
        checkInRecord(for: item) != nil
    }
}

private struct CommunityAvatar: View {
    let profile: SocialProfileCard
    let size: CGFloat

    var body: some View {
        Group {
            if let rawURL = profile.avatarURL,
               let url = URL(string: rawURL) {
                ATHLTHStorageImage(url: url) { phase in
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
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
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

struct CommunityEventsView: View {
    @EnvironmentObject private var community: CommunityEventStore
    @State private var showingCreateEvent = false

    private var upcoming: [CommunityEventItem] {
        community.upcomingEvents
    }

    private var history: [CommunityEventItem] {
        community.events
            .filter {
                $0.event.status ==
                    "completed" ||
                $0.event.status ==
                    "cancelled"
            }
            .sorted {
                $0.event.startsAt >
                    $1.event.startsAt
            }
    }

    var body: some View {
        List {
            if community.isLoading &&
                community.events.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading events…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if community.events.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No events yet",
                        systemImage: "calendar.badge.plus"
                    )
                } description: {
                    Text(
                        "Create a public or friends-only run, walk or group workout."
                    )
                } actions: {
                    Button("Create Event") {
                        showingCreateEvent = true
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { item in
                            NavigationLink {
                                CommunityEventDetailView(
                                    eventID: item.id
                                )
                            } label: {
                                CommunityEventListRow(
                                    item: item
                                )
                            }
                        }
                    }
                }

                if !history.isEmpty {
                    Section("History") {
                        ForEach(history) { item in
                            NavigationLink {
                                CommunityEventDetailView(
                                    eventID: item.id
                                )
                            } label: {
                                CommunityEventListRow(
                                    item: item
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateEvent = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Event")
            }
        }
        .refreshable {
            await community.refresh()
        }
        .task {
            if community.events.isEmpty {
                await community.refresh()
            }
        }
        .sheet(isPresented: $showingCreateEvent) {
            CommunityEventCreateView()
                .environmentObject(community)
        }
    }
}

private struct CommunityEventListRow: View {
    let item: CommunityEventItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(
                    item.event.startsAt
                        .formatted(
                            .dateTime.month(.abbreviated)
                        )
                        .uppercased()
                )
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ATHLTHTheme.accent)

                Text(
                    item.event.startsAt
                        .formatted(.dateTime.day())
                )
                .font(.title3.weight(.bold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
            }
            .frame(width: 44, height: 52)
            .background(
                ATHLTHTheme.accentSoft,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(
                        systemName:
                            item.event.activityType.systemImage
                    )
                    .foregroundStyle(ATHLTHTheme.accent)

                    Text(item.event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)
                }

                Text(
                    [
                        item.event.startsAt
                            .formatted(
                                date: .omitted,
                                time: .shortened
                            ),
                        item.event.meetingName
                            .nilIfBlank
                    ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Label(
                    ATHLTHLocalization.format(
                        english: "%d joined",
                        norwegian: "%d deltar",
                        item.participantCount
                    ),
                    systemImage: "person.2.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CommunityEventDetailView: View {
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var session: AppSessionStore

    let eventID: UUID

    private enum DetailTab: String, CaseIterable, Identifiable {
        case overview
        case route
        case chat
        case participants

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview:
                return ATHLTHLocalization.choose(
                    english: "Overview",
                    norwegian: "Oversikt"
                )
            case .route:
                return ATHLTHLocalization.choose(
                    english: "Route",
                    norwegian: "Rute"
                )
            case .chat:
                return ATHLTHLocalization.choose(
                    english: "Chat",
                    norwegian: "Chat"
                )
            case .participants:
                return ATHLTHLocalization.choose(
                    english: "People",
                    norwegian: "Deltakere"
                )
            }
        }

        var systemImage: String {
            switch self {
            case .overview:
                return "rectangle.grid.1x2"
            case .route:
                return "map.fill"
            case .chat:
                return "bubble.left.and.bubble.right.fill"
            case .participants:
                return "person.2.fill"
            }
        }
    }

    @State private var selectedTab: DetailTab = .overview
    @State private var showingEditEvent = false
    @State private var showingCancelConfirmation =
        false
    @StateObject private var checkInLocation =
        ChallengeLocationStore()
    @StateObject private var eventWeather =
        CommunityEventWeatherStore()
    @State private var checkInMessage: String?
    @State private var manualCheckInFallback =
        false
    @State private var attemptedAutomaticCheckIn =
        false

    var body: some View {
        ScrollView {
            if let item = community.item(id: eventID) {
                LazyVStack(
                    alignment: .leading,
                    spacing: 16,
                    pinnedViews: [.sectionHeaders]
                ) {
                    eventHero(item)

                    Section {
                        detailTabContent(item)
                            .padding(.top, 2)
                    } header: {
                        eventTabBar(item)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 30)
            } else {
                ContentUnavailableView(
                    "Event unavailable",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .padding(.top, 70)
            }
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .vitality
                        .opacity(0.20)
            )
            .ignoresSafeArea()
        )
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Event",
                norwegian: "Arrangement"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            .hidden,
            for: .navigationBar
        )
        .sheet(
            isPresented: $showingEditEvent
        ) {
            if let item =
                community.item(id: eventID) {
                CommunityEventEditView(
                    item: item
                )
                .environmentObject(community)
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Cancel Event?",
                norwegian: "Avlyse arrangement?"
            ),
            isPresented:
                $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            if let item =
                community.item(id: eventID) {
                Button(
                    ATHLTHLocalization.choose(
                        english: "Cancel Event",
                        norwegian: "Avlys arrangement"
                    ),
                    role: .destructive
                ) {
                    Task {
                        await community.cancel(
                            item
                        )
                    }
                }
            }

            Button(
                ATHLTHLocalization.choose(
                    english: "Keep Event",
                    norwegian: "Behold arrangement"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Participants will see that the event has been cancelled.",
                    norwegian:
                        "Deltakere vil se at arrangementet er avlyst."
                )
            )
        }
        .task(id: eventID) {
            await attemptAutomaticCheckIn()
        }
        .task(
            id:
                community
                    .item(id: eventID)?
                    .event
                    .updatedAt
        ) {
            await loadEventStartWeather()
        }
    }

    private func availableTabs(
        for item: CommunityEventItem
    ) -> [DetailTab] {
        var tabs: [DetailTab] = [
            .overview,
            .chat,
            .participants
        ]

        if eventRoute(item) != nil ||
            item.event.routeTitle?.nilIfBlank != nil {
            tabs.insert(
                .route,
                at: 1
            )
        }

        return tabs
    }

    private func eventTabBar(
        _ item: CommunityEventItem
    ) -> some View {
        let tabs = availableTabs(
            for: item
        )

        return HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(
                        .easeInOut(
                            duration: 0.18
                        )
                    ) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(
                            systemName:
                                tab.systemImage
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )

                        Text(tab.title)
                            .font(
                                .caption2
                                    .weight(
                                        .semibold
                                    )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(
                                0.78
                            )
                    }
                    .foregroundStyle(
                        selectedTab == tab
                            ? ATHLTHTheme
                                .vitality
                            : ATHLTHTheme
                                .mutedText
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 46
                    )
                    .background(
                        selectedTab == tab
                            ? ATHLTHTheme
                                .vitalitySoft
                            : Color.clear,
                        in:
                            RoundedRectangle(
                                cornerRadius: 14,
                                style:
                                    .continuous
                            )
                    )
                    .contentShape(
                        Rectangle()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    tab.title
                )
            }
        }
        .padding(5)
        .background(
            Color.white.opacity(0.97),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.055),
                lineWidth: 0.7
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.055),
            radius: 9,
            y: 4
        )
    }

    @ViewBuilder
    private func detailTabContent(
        _ item: CommunityEventItem
    ) -> some View {
        switch selectedTab {
        case .overview:
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                eventStartWeatherCard(item)
                routeSpotlight(item)
                eventDetails(
                    item,
                    includeRoute: false
                )

                if item.event.creatorID ==
                    session.profile.userID {
                    adminLifecycleCard(item)
                }

                if item.event.creatorID ==
                    session.profile.userID &&
                    item.event.status !=
                    "cancelled" &&
                    item.event.status !=
                    "completed" {
                    cancelEventButton(item)
                }
            }

        case .route:
            routeTabContent(item)

        case .chat:
            CommunityEventChatView(
                event: item.event,
                embedded: true
            )

        case .participants:
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                checkInCard(item)
                participants(item)
            }
        }
    }

    private func loadEventStartWeather()
        async {
        guard
            let item =
                community.item(
                    id: eventID
                ),
            let coordinate =
                eventWeatherCoordinate(
                    item
                )
        else {
            return
        }

        await eventWeather.load(
            latitude:
                coordinate.latitude,
            longitude:
                coordinate.longitude,
            startsAt:
                item.event.startsAt
        )
    }

    private func eventWeatherCoordinate(
        _ item: CommunityEventItem
    ) -> CLLocationCoordinate2D? {
        if let latitude =
                item.event.latitude,
           let longitude =
                item.event.longitude {
            return CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
        }

        if let first =
                eventRoute(item)?
                    .coordinates
                    .first {
            return first.coordinate
        }

        return nil
    }

    @ViewBuilder
    private func eventStartWeatherCard(
        _ item: CommunityEventItem
    ) -> some View {
        if eventWeatherCoordinate(item) != nil {
            ATHLTHCard {
                HStack(
                    alignment: .top,
                    spacing: 12
                ) {
                    Image(
                        systemName:
                            eventWeather
                                .snapshot?
                                .symbolName ??
                            "cloud.sun.fill"
                    )
                    .font(
                        .system(
                            size: 22,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                    .frame(
                        width: 44,
                        height: 44
                    )
                    .background(
                        ATHLTHTheme
                            .vitalitySoft,
                        in: Circle()
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Weather at start",
                                norwegian:
                                    "Vær ved start"
                            )
                        )
                        .font(
                            .headline
                        )

                        Text(
                            item.event.startsAt
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                        if let snapshot =
                                eventWeather
                                    .snapshot {
                            HStack(
                                spacing: 12
                            ) {
                                Text(
                                    String(
                                        format:
                                            "%.0f°",
                                        snapshot
                                            .temperatureCelsius
                                    )
                                )
                                .font(
                                    .title3
                                        .weight(
                                            .bold
                                        )
                                )

                                if let rain =
                                        snapshot
                                            .precipitationProbabilityPercent {
                                    Label(
                                        "\(rain)%",
                                        systemImage:
                                            "drop.fill"
                                    )
                                }

                                if let wind =
                                        snapshot
                                            .windSpeedKilometersPerHour {
                                    Label(
                                        String(
                                            format:
                                                "%.0f km/t",
                                            wind
                                        ),
                                        systemImage:
                                            "wind"
                                    )
                                }
                            }
                            .font(
                                .caption
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .padding(.top, 4)

                            if let feels =
                                    snapshot
                                        .apparentTemperatureCelsius {
                                Text(
                                    ATHLTHLocalization.format(
                                        english:
                                            "Feels like %.0f°. Forecast for the event start, not current weather.",
                                        norwegian:
                                            "Føles som %.0f°. Prognose for arrangementsstart, ikke været akkurat nå.",
                                        feels
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary
                                )
                                .padding(.top, 2)
                            } else {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Forecast for the event start, not current weather.",
                                        norwegian:
                                            "Prognose for arrangementsstart, ikke været akkurat nå."
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary
                                )
                                .padding(.top, 2)
                            }
                        } else if eventWeather
                                    .isLoading {
                            ProgressView()
                                .padding(.top, 5)
                        } else {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "The start forecast will appear when it is available.",
                                    norwegian:
                                        "Værmelding for starttidspunktet vises når prognosen er tilgjengelig."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                            .padding(.top, 4)
                        }
                    }

                    Spacer(
                        minLength: 0
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func routeSpotlight(
        _ item: CommunityEventItem
    ) -> some View {
        if let route = eventRoute(item) {
            ATHLTHCard {
                HStack(
                    alignment: .firstTextBaseline
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "The route",
                                norwegian: "Ruten"
                            )
                        )
                        .font(.headline)

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Route overview for this event",
                                norwegian:
                                    "Løypen for arrangementet"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    Button {
                        withAnimation(
                            .easeInOut(
                                duration: 0.18
                            )
                        ) {
                            selectedTab = .route
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "View route",
                                    norwegian:
                                        "Se rute"
                                )
                            )

                            Image(
                                systemName:
                                    "chevron.right"
                            )
                        }
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                }

                eventRouteOverview(
                    route,
                    mapHeight: 218
                )
                .padding(.top, 8)
            }
        } else if let routeTitle =
                    item.event
                        .routeTitle?
                        .nilIfBlank {
            ATHLTHCard {
                Text(
                    ATHLTHLocalization.choose(
                        english: "The route",
                        norwegian: "Ruten"
                    )
                )
                .font(.headline)

                eventDetailRow(
                    ATHLTHLocalization.choose(
                        english: "Route",
                        norwegian: "Rute"
                    ),
                    value: routeTitle,
                    icon:
                        "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
        }
    }

    @ViewBuilder
    private func routeTabContent(
        _ item: CommunityEventItem
    ) -> some View {
        if let route = eventRoute(item) {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                ATHLTHCard {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Event route",
                                    norwegian:
                                        "Arrangementsrute"
                                )
                            )
                            .font(.headline)

                            Text(route.title)
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                        }

                        Spacer()

                        if route
                            .distanceKilometers >
                            0 {
                            Text(
                                String(
                                    format:
                                        "%.1f km",
                                    route
                                        .distanceKilometers
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .vitality
                            )
                        }
                    }
                }

                eventRouteOverview(
                    route,
                    mapHeight: 360
                )

                routeMetricsCard(route)

                eventDetails(
                    item,
                    includeRoute: false
                )
            }
        } else if let routeTitle =
                    item.event
                        .routeTitle?
                        .nilIfBlank {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                ATHLTHCard {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Event route",
                            norwegian:
                                "Arrangementsrute"
                        )
                    )
                    .font(.headline)

                    eventDetailRow(
                        ATHLTHLocalization.choose(
                            english: "Route",
                            norwegian: "Rute"
                        ),
                        value: routeTitle,
                        icon:
                            "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }

                eventDetails(
                    item,
                    includeRoute: false
                )
            }
        } else {
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english: "No route added",
                    norwegian: "Ingen rute lagt til"
                ),
                systemImage: "map"
            )
            .padding(.vertical, 36)
        }
    }

    private func participantsPreview(
        _ item: CommunityEventItem
    ) -> some View {
        let profiles =
            ([item.creator]
                .compactMap { $0 }) +
            participantProfiles(
                item,
                status: .going
            )
        let visibleProfiles =
            Array(
                profiles.prefix(4)
            )

        return ATHLTHCard {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "People",
                            norwegian: "Deltakere"
                        )
                    )
                    .font(.headline)

                    Text(
                        ATHLTHLocalization.format(
                            english: "%d going",
                            norwegian: "%d deltar",
                            item.participantCount
                        )
                    )
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                }

                Spacer()

                Button {
                    withAnimation(
                        .easeInOut(
                            duration: 0.18
                        )
                    ) {
                        selectedTab =
                            .participants
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "See all",
                                norwegian: "Se alle"
                            )
                        )

                        Image(
                            systemName:
                                "arrow.up.right"
                        )
                    }
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
            }

            if visibleProfiles.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "No participants yet",
                        norwegian:
                            "Ingen deltakere ennå"
                    ),
                    systemImage:
                        "person.2"
                )
                .font(.subheadline)
                .foregroundStyle(
                    .secondary
                )
                .padding(.top, 8)
            } else {
                HStack(spacing: -9) {
                    ForEach(
                        visibleProfiles
                    ) { profile in
                        CommunityAvatar(
                            profile: profile,
                            size: 40
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 2
                                )
                        }
                    }

                    if item.participantCount >
                        visibleProfiles.count {
                        Text(
                            "+\(item.participantCount - visibleProfiles.count)"
                        )
                        .font(
                            .caption2
                                .weight(
                                    .bold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .frame(
                            width: 40,
                            height: 40
                        )
                        .background(
                            ATHLTHTheme
                                .vitalitySoft,
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

                    Spacer()
                }
                .padding(.top, 8)

                ForEach(
                    Array(
                        visibleProfiles
                            .prefix(3)
                    )
                ) { profile in
                    HStack(spacing: 10) {
                        CommunityAvatar(
                            profile: profile,
                            size: 34
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                profile
                                    .resolvedName
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            if profile.userID ==
                                item.event
                                    .creatorID {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Host",
                                        norwegian:
                                            "Arrangør"
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }

                        Spacer()

                        if checkedInRows(
                            item
                        )
                        .contains(
                            where: {
                                $0.userID ==
                                    profile.userID
                            }
                        ) {
                            Image(
                                systemName:
                                    "checkmark.circle.fill"
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .vitality
                            )
                            .accessibilityLabel(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Checked in",
                                    norwegian:
                                        "Sjekket inn"
                                )
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func eventHero(_ item: CommunityEventItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            eventCover(item)
                .athlthBoundedFill()
                .frame(height: 178)
                .frame(maxWidth: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )

            HStack(spacing: 10) {
                Label(
                    item.event.activityType
                        .title.uppercased(),
                    systemImage:
                        item.event.activityType
                            .systemImage
                )
                .font(
                    .caption2.weight(.bold)
                )
                .tracking(1.1)
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )

                Spacer()

                eventLifecycleBadge(
                    item.event.status
                )
            }

            Text(item.event.title)
                .font(.largeTitle.weight(.bold))

            if !item.event.summary.isEmpty {
                Text(item.event.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label(
                    item.event.startsAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )

                Spacer()

                heroAttendanceSummary(item)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            actionButton(item)
        }
        .padding(18)
        .background(
            ATHLTHTheme.surfaceSage,
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.045),
            radius: 12,
            y: 5
        )
    }

    @ViewBuilder
    private func eventCover(
        _ item: CommunityEventItem
    ) -> some View {
        if let rawURL =
                item.event.coverImageURL,
           let url =
                URL(string: rawURL) {
            ATHLTHStorageImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                default:
                    Image(
                        CommunityEventCoverPolicy
                            .displayArtworkName(
                                item.event
                                    .coverArtworkName ??
                                CommunityEventCoverPolicy
                                    .defaultArtwork(
                                        for:
                                            item.event
                                                .activityType
                                    )
                            )
                    )
                    .resizable()
                    .scaledToFill()
                    .clipped()
                }
            }
        } else {
            Image(
                CommunityEventCoverPolicy
                    .displayArtworkName(
                        item.event
                            .coverArtworkName ??
                        CommunityEventCoverPolicy
                            .defaultArtwork(
                                for:
                                    item.event
                                        .activityType
                            )
                    )
            )
            .resizable()
            .scaledToFill()
            .clipped()
        }
    }

    @ViewBuilder
    private func actionButton(
        _ item: CommunityEventItem
    ) -> some View {
        if item.event.creatorID ==
            session.profile.userID {
            Button {
                showingEditEvent = true
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Edit Event",
                        norwegian:
                            "Rediger arrangement"
                    ),
                    systemImage: "pencil"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.vitality)
            .padding(.top, 4)
        } else if community.isJoined(item) {
            VStack(spacing: 7) {
                Button {
                    Task {
                        if hasMeetingCoordinate(
                            item
                        ) {
                            await verifyAndCheckIn(
                                item,
                                automatic: false
                            )
                        } else {
                            await manualCheckIn(
                                item
                            )
                        }
                    }
                } label: {
                    Label(
                        community.isCheckedIn(
                            item
                        )
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Checked in",
                                norwegian:
                                    "Sjekket inn"
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Check in",
                                norwegian:
                                    "Innsjekk"
                            ),
                        systemImage:
                            community.isCheckedIn(
                                item
                            )
                                ? "checkmark.seal.fill"
                                : "mappin.and.ellipse"
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )
                    .frame(
                        maxWidth:
                            .infinity,
                        minHeight: 44
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    community.isCheckedIn(
                        item
                    )
                        ? ATHLTHTheme
                            .vitality
                        : (
                            canCheckInNow(
                                item
                            )
                                ? ATHLTHTheme
                                    .vitality
                                : Color.gray
                        )
                )
                .disabled(
                    community.isCheckedIn(
                        item
                    ) ||
                    !canCheckInNow(
                        item
                    )
                )

                if !community
                    .isCheckedIn(item) {
                    Text(
                        checkInAvailabilityText(
                            item
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
            .padding(.top, 4)
        } else {
            HStack(spacing: 10) {
                Button {
                    Task {
                        await community.join(
                            item
                        )
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Going",
                            norwegian: "Delta"
                        ),
                        systemImage:
                            "person.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
                .disabled(
                    item.event
                        .maxParticipants
                        .map {
                            item.participantCount >=
                                $0
                        } ?? false
                )

                Button {
                    Task {
                        if community.isMaybe(
                            item
                        ) {
                            await community.leave(
                                item
                            )
                        } else {
                            await community.maybe(
                                item
                            )
                        }
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Maybe",
                            norwegian: "Kanskje"
                        ),
                        systemImage:
                            community.isMaybe(item)
                                ? "questionmark.circle.fill"
                                : "questionmark.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(
                    community.isMaybe(item)
                        ? ATHLTHTheme.vitality
                        : .secondary
                )
            }
            .padding(.top, 4)
        }
    }

    private func eventDetails(
        _ item: CommunityEventItem,
        includeRoute: Bool = true
    ) -> some View {
        ATHLTHCard {
            Text("Details")
                .font(.headline)

            if let meeting =
                    item.event.meetingName
                        .nilIfBlank {
                eventMeetingPointRow(
                    meeting,
                    latitude:
                        item.event.latitude,
                    longitude:
                        item.event.longitude
                )
            } else {
                eventDetailRow(
                    ATHLTHLocalization.choose(
                        english: "Meeting point",
                        norwegian: "Møtested"
                    ),
                    value:
                        ATHLTHLocalization.choose(
                            english:
                                "No meeting point",
                            norwegian:
                                "Ingen oppmøteplass"
                        ),
                    icon:
                        "mappin.slash"
                )
            }

            if let details = item.event.meetingDetails, !details.isEmpty {
                eventDetailRow(
                    "Where to meet",
                    value: details,
                    icon: "text.bubble"
                )
            }

            if let pace = item.event.paceLabel, !pace.isEmpty {
                eventDetailRow(
                    "Pace / level",
                    value: pace,
                    icon: "speedometer"
                )
            }

            if includeRoute {
                if let route =
                        eventRoute(item) {
                    eventRouteOverview(
                        route
                    )
                    .padding(.top, 10)
                } else if let routeTitle =
                            item.event
                                .routeTitle?
                                .nilIfBlank {
                    eventDetailRow(
                        ATHLTHLocalization.choose(
                            english: "Route",
                            norwegian: "Rute"
                        ),
                        value: routeTitle,
                        icon:
                            "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
            }

            eventDetailRow(
                "Visibility",
                value: item.event.visibility.capitalized,
                icon: item.event.visibility == "public"
                    ? "globe"
                    : "person.2.fill"
            )

            if let max = item.event.maxParticipants {
                eventDetailRow(
                    "Capacity",
                    value: "\(item.participantCount) / \(max)",
                    icon: "person.3.fill"
                )
            }
        }
    }

    private func participants(
        _ item: CommunityEventItem
    ) -> some View {
        let going =
            participantProfiles(
                item,
                status: .going
            )
        let maybe =
            participantProfiles(
                item,
                status: .maybe
            )
        let checkedIn =
            checkedInRows(item)

        return ATHLTHCard {
            Text(
                ATHLTHLocalization.choose(
                    english: "People",
                    norwegian: "Deltakere"
                )
            )
            .font(.headline)

            Text(
                ATHLTHLocalization.format(
                    english: "Going · %d",
                    norwegian: "Deltar · %d",
                    item.participantCount
                )
            )
            .font(
                .caption.weight(.semibold)
            )
            .foregroundStyle(
                ATHLTHTheme.vitality
            )
            .padding(.top, 6)

            if let creator = item.creator {
                attendeeRow(
                    profile: creator,
                    subtitle:
                        ATHLTHLocalization.choose(
                            english: "Host",
                            norwegian: "Arrangør"
                        )
                )
            } else {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Event host",
                        norwegian: "Arrangør"
                    ),
                    systemImage:
                        "person.crop.circle"
                )
                .font(.subheadline)
                .padding(.top, 8)
            }

            ForEach(going) { profile in
                attendeeRow(
                    profile: profile,
                    subtitle: nil
                )
            }

            if !checkedIn.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                Text(
                    ATHLTHLocalization.format(
                        english:
                            "Checked in · %d",
                        norwegian:
                            "Sjekket inn · %d",
                        checkedIn.count
                    )
                )
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )

                ForEach(
                    checkedIn,
                    id: \.userID
                ) { row in
                    if let profile =
                        profile(
                            for: row.userID,
                            in: item
                        ) {
                        attendeeRow(
                            profile: profile,
                            subtitle:
                                checkInSubtitle(
                                    row
                                )
                        )
                    }
                }
            }

            if !maybe.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                Text(
                    ATHLTHLocalization.format(
                        english: "Maybe · %d",
                        norwegian: "Kanskje · %d",
                        maybe.count
                    )
                )
                .font(
                    .caption.weight(
                        .semibold
                    )
                )
                .foregroundStyle(
                    .secondary
                )

                ForEach(maybe) { profile in
                    attendeeRow(
                        profile: profile,
                        subtitle: nil
                    )
                }
            }
        }
    }


    private func checkInOpensAt(
        _ item: CommunityEventItem
    ) -> Date {
        item.event.startsAt
            .addingTimeInterval(
                -30 * 60
            )
    }

    private func canCheckInNow(
        _ item: CommunityEventItem,
        now: Date = Date()
    ) -> Bool {
        guard
            item.event.status !=
                "cancelled",
            item.event.status !=
                "completed"
        else {
            return false
        }

        return now >=
            checkInOpensAt(item)
    }

    private func checkInAvailabilityText(
        _ item: CommunityEventItem,
        now: Date = Date()
    ) -> String {
        if item.event.status ==
            "cancelled" ||
            item.event.status ==
            "completed" {
            return ATHLTHLocalization.choose(
                english:
                    "Check-in is closed.",
                norwegian:
                    "Innsjekk er stengt."
            )
        }

        let opensAt =
            checkInOpensAt(item)

        if now < opensAt {
            return ATHLTHLocalization.format(
                english:
                    "Opens 30 min before start · %@",
                norwegian:
                    "Åpner 30 min før start · %@",
                opensAt.formatted(
                    date:
                        Calendar.current
                            .isDateInToday(
                                opensAt
                            )
                            ? .omitted
                            : .abbreviated,
                    time:
                        .shortened
                )
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "Check-in is open.",
            norwegian:
                "Innsjekk er åpen."
        )
    }

    @ViewBuilder
    private func checkInCard(
        _ item: CommunityEventItem
    ) -> some View {
        let isHost =
            item.event.creatorID ==
            session.profile.userID
        let hasResponse =
            community.attendance(
                for: item
            ) != nil

        if isHost ||
            hasResponse ||
            item.checkedInCount > 0 {
            ATHLTHCard {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "Check-in",
                                    norwegian:
                                        "Innsjekk"
                                )
                        )
                        .font(.headline)

                        Text(
                            ATHLTHLocalization
                                .format(
                                    english:
                                        "%d checked in",
                                    norwegian:
                                        "%d sjekket inn",
                                    item.checkedInCount
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()

                    Image(
                        systemName:
                            item.checkedInCount > 0
                            ? "checkmark.seal.fill"
                            : "mappin.and.ellipse"
                    )
                    .foregroundStyle(
                        item.checkedInCount > 0
                            ? ATHLTHTheme
                                .vitality
                            : .secondary
                    )
                }

                if isHost {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Participant check-ins appear below as people arrive.",
                                norwegian:
                                    "Innsjekkede deltakere vises under etter hvert som de kommer."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .padding(.top, 6)
                } else if let record =
                            community
                                .checkInRecord(
                                    for: item
                                ) {
                    HStack(spacing: 10) {
                        Image(
                            systemName:
                                "checkmark.circle.fill"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            ATHLTHTheme
                                .vitality
                        )

                        VStack(
                            alignment:
                                .leading,
                            spacing: 2
                        ) {
                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "You're checked in",
                                        norwegian:
                                            "Du er sjekket inn"
                                    )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            Text(
                                checkInSubtitle(
                                    record
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        Spacer()
                    }
                    .padding(.top, 8)
                } else if community
                            .isJoined(item) &&
                            item.event.status !=
                                "cancelled" &&
                            item.event.status !=
                                "completed" {
                    if hasMeetingCoordinate(
                        item
                    ) {
                        Button {
                            Task {
                                await verifyAndCheckIn(
                                    item,
                                    automatic: false
                                )
                            }
                        } label: {
                            HStack {
                                if checkInLocation
                                    .isLocating {
                                    ProgressView()
                                } else {
                                    Image(
                                        systemName:
                                            "location.fill"
                                    )
                                }

                                Text(
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Check in near meetup",
                                            norwegian:
                                                "Sjekk inn ved møtested"
                                        )
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )
                            }
                            .frame(
                                maxWidth:
                                    .infinity,
                                minHeight: 42
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .tint(
                            ATHLTHTheme.vitality
                        )
                        .disabled(
                            checkInLocation
                                .isLocating ||
                            !canCheckInNow(
                                item
                            )
                        )
                        .padding(.top, 8)

                        Text(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "ATHLTH verifies that you are within about 100 m of the meetup point. Your location is not stored.",
                                    norwegian:
                                        "ATHLTH bekrefter at du er innen omtrent 100 m fra møtestedet. Posisjonen din lagres ikke."
                                )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                        .padding(.top, 4)

                        if manualCheckInFallback {
                            Button {
                                Task {
                                    await manualCheckIn(
                                        item
                                    )
                                }
                            } label: {
                                Label(
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Check in manually",
                                            norwegian:
                                                "Sjekk inn manuelt"
                                        ),
                                    systemImage:
                                        "hand.tap"
                                )
                                .font(
                                    .caption
                                        .weight(
                                            .semibold
                                        )
                                )
                            }
                            .buttonStyle(
                                .bordered
                            )
                            .padding(.top, 6)
                        }
                    } else {
                        Button {
                            Task {
                                await manualCheckIn(
                                    item
                                )
                            }
                        } label: {
                            Label(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Check in manually",
                                        norwegian:
                                            "Sjekk inn manuelt"
                                    ),
                                systemImage:
                                    "hand.tap"
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .frame(
                                maxWidth:
                                    .infinity,
                                minHeight: 42
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .tint(
                            ATHLTHTheme.vitality
                        )
                        .padding(.top, 8)

                        Text(
                            ATHLTHLocalization
                                .choose(
                                    english:
                                        "No meetup location was set, so check-in is manual.",
                                    norwegian:
                                        "Det er ikke angitt et møtested, derfor gjøres innsjekk manuelt."
                                )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                        .padding(.top, 4)
                    }
                } else if community
                            .isMaybe(item) {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Choose Going before you check in.",
                                norwegian:
                                    "Velg Deltar før du kan sjekke inn."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .padding(.top, 6)
                }

                if let checkInMessage {
                    Text(checkInMessage)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .padding(.top, 6)
                }
            }
        }
    }

    private func hasMeetingCoordinate(
        _ item: CommunityEventItem
    ) -> Bool {
        item.event.latitude != nil &&
        item.event.longitude != nil
    }

    private func meetingLocation(
        _ item: CommunityEventItem
    ) -> CLLocation? {
        guard let latitude =
                item.event.latitude,
              let longitude =
                item.event.longitude
        else {
            return nil
        }

        return CLLocation(
            latitude: latitude,
            longitude: longitude
        )
    }

    private func verifyAndCheckIn(
        _ item: CommunityEventItem,
        automatic: Bool
    ) async {
        guard canCheckInNow(item)
        else {
            if !automatic {
                checkInMessage =
                    checkInAvailabilityText(
                        item
                    )
            }
            return
        }

        guard let meeting =
                meetingLocation(item)
        else {
            if !automatic {
                await manualCheckIn(item)
            }
            return
        }

        let current =
            await checkInLocation
                .requestCurrentLocation()

        guard let current else {
            if !automatic {
                manualCheckInFallback = true
                checkInMessage =
                    ATHLTHLocalization
                        .choose(
                            english:
                                "ATHLTH couldn't verify your location. You can use manual check-in instead.",
                            norwegian:
                                "ATHLTH klarte ikke å bekrefte posisjonen din. Du kan bruke manuell innsjekk i stedet."
                        )
            }
            return
        }

        let distance =
            current.distance(from: meeting)
        let accuracyAllowance =
            min(
                max(
                    current.horizontalAccuracy,
                    0
                ),
                35
            )
        let allowedDistance =
            100 + accuracyAllowance

        guard distance <=
                allowedDistance
        else {
            if !automatic {
                manualCheckInFallback =
                    false
                checkInMessage =
                    ATHLTHLocalization
                        .format(
                            english:
                                "You're about %d m from the meetup point. Move within 100 m to check in.",
                            norwegian:
                                "Du er omtrent %d m fra møtestedet. Gå innenfor 100 m for å sjekke inn.",
                            Int(
                                distance
                                    .rounded()
                            )
                        )
            }
            return
        }

        let saved =
            await community.checkIn(
                item,
                method: .proximity
            )

        if saved {
            manualCheckInFallback =
                false
            checkInMessage =
                ATHLTHLocalization
                    .choose(
                        english:
                            "Checked in at the meetup point.",
                        norwegian:
                            "Du er sjekket inn ved møtestedet."
                    )
        }
    }

    private func manualCheckIn(
        _ item: CommunityEventItem
    ) async {
        guard canCheckInNow(item)
        else {
            checkInMessage =
                checkInAvailabilityText(
                    item
                )
            return
        }

        let saved =
            await community.checkIn(
                item,
                method: .manual
            )

        if saved {
            manualCheckInFallback =
                false
            checkInMessage =
                ATHLTHLocalization
                    .choose(
                        english:
                            "Manual check-in completed.",
                        norwegian:
                            "Manuell innsjekk er registrert."
                    )
        }
    }

    private func attemptAutomaticCheckIn()
        async {
        guard !attemptedAutomaticCheckIn
        else {
            return
        }

        attemptedAutomaticCheckIn =
            true

        guard let item =
                community.item(
                    id: eventID
                ),
              item.event.creatorID !=
                session.profile.userID,
              community.isJoined(item),
              !community.isCheckedIn(item),
              canCheckInNow(item),
              hasMeetingCoordinate(item),
              item.event.status !=
                "cancelled",
              item.event.status !=
                "completed"
        else {
            return
        }

        switch checkInLocation
            .authorizationStatus {
        case .authorizedAlways,
             .authorizedWhenInUse:
            await verifyAndCheckIn(
                item,
                automatic: true
            )

        case .notDetermined,
             .denied,
             .restricted:
            // Never prompt for location merely by opening an event.
            // Tapping Check in can request permission and offers a
            // manual fallback if verification is unavailable.
            break

        @unknown default:
            break
        }
    }

    private func checkedInRows(
        _ item: CommunityEventItem
    ) -> [CommunityEventParticipantRecord] {
        item.participantRows
            .filter {
                $0.checkedInAt != nil
            }
            .sorted {
                ($0.checkedInAt ??
                    .distantFuture) <
                ($1.checkedInAt ??
                    .distantFuture)
            }
    }

    private func profile(
        for userID: UUID,
        in item: CommunityEventItem
    ) -> SocialProfileCard? {
        if userID ==
            item.event.creatorID {
            return item.creator
        }

        return item.participantProfiles
            .first {
                $0.userID == userID
            }
    }

    private func checkInSubtitle(
        _ row:
            CommunityEventParticipantRecord
    ) -> String {
        let method:
            String

        switch row.checkInMethod {
        case .proximity:
            method =
                ATHLTHLocalization.choose(
                    english:
                        "Verified at meetup",
                    norwegian:
                        "Bekreftet ved møtested"
                )
        case .manual:
            method =
                ATHLTHLocalization.choose(
                    english:
                        "Manual check-in",
                    norwegian:
                        "Manuell innsjekk"
                )
        case nil:
            method =
                ATHLTHLocalization.choose(
                    english: "Checked in",
                    norwegian:
                        "Sjekket inn"
                )
        }

        guard let checkedInAt =
                row.checkedInAt
        else {
            return method
        }

        return method +
            " · " +
            checkedInAt.formatted(
                date: .omitted,
                time: .shortened
            )
    }

    private func participantProfiles(
        _ item: CommunityEventItem,
        status: CommunityEventAttendance
    ) -> [SocialProfileCard] {
        let matchingIDs =
            Set(
                item.participantRows
                    .filter {
                        $0.attendanceStatus ==
                            status &&
                        $0.userID !=
                            item.event.creatorID
                    }
                    .map(\.userID)
            )

        return item.participantProfiles
            .filter {
                matchingIDs.contains(
                    $0.userID
                )
            }
    }

    @ViewBuilder
    private func attendeeRow(
        profile: SocialProfileCard,
        subtitle: String?
    ) -> some View {
        Divider()

        HStack(spacing: 10) {
            CommunityAvatar(
                profile: profile,
                size: 36
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(profile.resolvedName)
                    .font(
                        .subheadline
                            .weight(.medium)
                    )

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )
                }
            }

            Spacer()
        }
    }

    private func heroAttendanceSummary(
        _ item: CommunityEventItem
    ) -> some View {
        let profiles =
            ([item.creator]
                .compactMap { $0 }) +
            participantProfiles(
                item,
                status: .going
            )

        return HStack(spacing: 7) {
            if profiles.isEmpty {
                Image(
                    systemName:
                        "person.2.fill"
                )
                .font(.caption)
            } else {
                HStack(spacing: -7) {
                    ForEach(
                        Array(
                            profiles.prefix(3)
                        )
                    ) { profile in
                        CommunityAvatar(
                            profile: profile,
                            size: 25
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    ATHLTHTheme
                                        .surfaceSage,
                                    lineWidth: 2
                                )
                        }
                    }
                }
            }

            Text(
                ATHLTHLocalization.format(
                    english: "%d joined",
                    norwegian: "%d deltar",
                    item.participantCount
                )
            )
        }
    }


    @ViewBuilder
    private func adminLifecycleCard(
        _ item: CommunityEventItem
    ) -> some View {
        let lifecycle =
            CommunityEventLifecycleStatus(
                rawValue: item.event.status
            ) ?? .upcoming

        ATHLTHCard {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Event control",
                                norwegian:
                                    "Styring av arrangement"
                            )
                    )
                    .font(.headline)

                    Text(
                        lifecycle.title
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                Image(
                    systemName:
                        lifecycle.systemImage
                )
                .font(.title3)
                .foregroundStyle(
                    lifecycleTint(
                        lifecycle
                    )
                )
            }

            switch lifecycle {
            case .upcoming:
                Button {
                    Task {
                        _ = await community
                            .setLifecycle(
                                item,
                                status: .live
                            )
                    }
                } label: {
                    Label(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Start event now",
                                norwegian:
                                    "Start arrangement nå"
                            ),
                        systemImage:
                            "play.fill"
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 44
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
                .padding(.top, 8)

            case .live:
                Button {
                    Task {
                        _ = await community
                            .setLifecycle(
                                item,
                                status:
                                    .completed
                            )
                    }
                } label: {
                    Label(
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "Mark as completed",
                                norwegian:
                                    "Marker som fullført"
                            ),
                        systemImage:
                            "checkmark.seal.fill"
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 44
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
                .padding(.top, 8)

            case .completed:
                Label(
                    ATHLTHLocalization
                        .choose(
                            english:
                                "This event is completed.",
                            norwegian:
                                "Arrangementet er fullført."
                        ),
                    systemImage:
                        "checkmark.seal.fill"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .padding(.top, 8)

            case .cancelled:
                Label(
                    ATHLTHLocalization
                        .choose(
                            english:
                                "This event is cancelled.",
                            norwegian:
                                "Arrangementet er avlyst."
                        ),
                    systemImage:
                        "xmark.circle.fill"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .foregroundStyle(.red)
                .padding(.top, 8)
            }
        }
    }

    private func eventLifecycleBadge(
        _ rawStatus: String
    ) -> some View {
        let lifecycle =
            CommunityEventLifecycleStatus(
                rawValue: rawStatus
            ) ?? .upcoming

        return Label(
            lifecycle.title,
            systemImage:
                lifecycle.systemImage
        )
        .font(.caption2.weight(.bold))
        .foregroundStyle(
            lifecycleTint(lifecycle)
        )
        .padding(
            .horizontal,
            9
        )
        .padding(
            .vertical,
            5
        )
        .background(
            lifecycleTint(
                lifecycle
            )
            .opacity(0.11),
            in: Capsule()
        )
    }

    private func lifecycleTint(
        _ lifecycle:
            CommunityEventLifecycleStatus
    ) -> Color {
        switch lifecycle {
        case .upcoming:
            return ATHLTHTheme.vitality
        case .live:
            return .green
        case .completed:
            return .indigo
        case .cancelled:
            return .red
        }
    }

    private func cancelEventButton(
        _ item: CommunityEventItem
    ) -> some View {
        Button(role: .destructive) {
            showingCancelConfirmation =
                true
        } label: {
            Label(
                ATHLTHLocalization.choose(
                    english: "Cancel Event",
                    norwegian:
                        "Avlys arrangement"
                ),
                systemImage: "xmark.circle"
            )
            .font(
                .subheadline.weight(.semibold)
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 46
            )
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .accessibilityHint(
            ATHLTHLocalization.choose(
                english:
                    "Moves this event to cancelled.",
                norwegian:
                    "Flytter arrangementet til avlyst."
            )
        )
    }

    private func eventRoute(
        _ item:
            CommunityEventItem
    ) -> TrainingRoute? {
        if let coordinates =
                item.event
                    .routeCoordinates,
           coordinates.count >= 2 {
            return TrainingRoute(
                id:
                    item.event.routeID ??
                    UUID(),
                ownerID:
                    item.event.creatorID,
                title:
                    item.event.routeTitle ??
                    ATHLTHLocalization.choose(
                        english: "Event route",
                        norwegian:
                            "Arrangementsrute"
                    ),
                visibility:
                    ProfileVisibility(
                        rawValue:
                            item.event
                                .visibility
                    ) ??
                    .publicProfile,
                coordinates:
                    coordinates,
                distanceKilometers:
                    item.event
                        .routeDistanceKilometers ??
                    0,
                elevationGainMeters:
                    item.event
                        .routeElevationGainMeters,
                importedFilename: nil,
                createdAt:
                    item.event.createdAt,
                startName:
                    item.event.routeStartName,
                endName:
                    item.event.routeEndName
            )
        }

        guard let routeID =
                item.event.routeID
        else {
            return nil
        }

        return session.savedRoutes
            .first {
                $0.id == routeID
            }
    }

    private func eventRouteOverview(
        _ route: TrainingRoute,
        mapHeight: CGFloat = 176
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Route",
                        norwegian: "Rute"
                    ),
                    systemImage:
                        "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Spacer()

                if route
                    .distanceKilometers >
                    0 {
                    Text(
                        String(
                            format:
                                "%.1f km",
                            route
                                .distanceKilometers
                        )
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )
                }
            }

            Button {
                openRouteInMaps(route)
            } label: {
                VStack(
                    alignment: .leading,
                    spacing: 9
                ) {
                    Map(
                        initialPosition:
                            .region(
                                routeRegion(
                                    route
                                )
                            )
                    ) {
                        MapPolyline(
                            coordinates:
                                route
                                    .coordinates
                                    .map(
                                        \.coordinate
                                    )
                        )
                        .stroke(
                            ATHLTHTheme
                                .vitality,
                            lineWidth: 5
                        )

                        if let first =
                                route
                                    .coordinates
                                    .first {
                            Marker(
                                route.startName ??
                                ATHLTHLocalization.choose(
                                    english:
                                        "Start",
                                    norwegian:
                                        "Start"
                                ),
                                coordinate:
                                    first
                                        .coordinate
                            )
                            .tint(
                                ATHLTHTheme
                                    .vitality
                            )
                        }

                        if let last =
                                route
                                    .coordinates
                                    .last {
                            Marker(
                                route.endName ??
                                ATHLTHLocalization.choose(
                                    english:
                                        "Finish",
                                    norwegian:
                                        "Mål"
                                ),
                                coordinate:
                                    last
                                        .coordinate
                            )
                            .tint(.red)
                        }
                    }
                    .allowsHitTesting(false)
                    .frame(height: mapHeight)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style:
                                .continuous
                        )
                    )

                    HStack(spacing: 8) {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(route.title)
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Open start and finish in Apple Maps",
                                    norwegian:
                                        "Åpne start og mål i Apple Maps"
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }

                        Spacer()

                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            ATHLTHTheme
                .surfaceSage,
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style:
                        .continuous
                )
        )
    }

    private func routeRegion(
        _ route:
            TrainingRoute
    ) -> MKCoordinateRegion {
        let coordinates =
            route.coordinates.map(
                \.coordinate
            )

        guard let first =
                coordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 63.43,
                        longitude: 10.39
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta:
                            0.04,
                        longitudeDelta:
                            0.04
                    )
            )
        }

        var minLat =
            first.latitude
        var maxLat =
            first.latitude
        var minLon =
            first.longitude
        var maxLon =
            first.longitude

        for coordinate in
            coordinates {
            minLat = min(
                minLat,
                coordinate.latitude
            )
            maxLat = max(
                maxLat,
                coordinate.latitude
            )
            minLon = min(
                minLon,
                coordinate.longitude
            )
            maxLon = max(
                maxLon,
                coordinate.longitude
            )
        }

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (
                            minLat +
                            maxLat
                        ) / 2,
                    longitude:
                        (
                            minLon +
                            maxLon
                        ) / 2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        max(
                            (
                                maxLat -
                                minLat
                            ) *
                            1.30,
                            0.008
                        ),
                    longitudeDelta:
                        max(
                            (
                                maxLon -
                                minLon
                            ) *
                            1.30,
                            0.008
                        )
                )
        )
    }

    private func eventMeetingPointRow(
        _ meeting: String,
        latitude: Double?,
        longitude: Double?
    ) -> some View {
        Button {
            if let latitude,
               let longitude {
                openMeetingPoint(
                    meeting,
                    latitude: latitude,
                    longitude: longitude
                )
            }
        } label: {
            HStack(
                alignment: .center,
                spacing: 12
            ) {
                HStack(
                    alignment: .top,
                    spacing: 10
                ) {
                    Image(
                        systemName:
                            "mappin.and.ellipse"
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                    .frame(width: 24)

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        HStack(spacing: 5) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Meeting point",
                                    norwegian:
                                        "Møtested"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )

                            if latitude != nil,
                               longitude != nil {
                                Image(
                                    systemName:
                                        "arrow.up.right"
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .vitality
                                )
                            }
                        }

                        Text(meeting)
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(3)

                        if latitude != nil,
                           longitude != nil {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Open in Apple Maps",
                                    norwegian:
                                        "Åpne i Apple Maps"
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .vitality
                            )
                        }
                    }
                }

                Spacer(
                    minLength: 8
                )

                if let latitude,
                   let longitude {
                    let coordinate =
                        CLLocationCoordinate2D(
                            latitude: latitude,
                            longitude: longitude
                        )

                    Map(
                        initialPosition:
                            .region(
                                meetingRegion(
                                    coordinate
                                )
                            )
                    ) {
                        Marker(
                            meeting,
                            coordinate:
                                coordinate
                        )
                        .tint(
                            ATHLTHTheme
                                .vitality
                        )
                    }
                    .mapStyle(
                        .standard(
                            pointsOfInterest:
                                .excludingAll
                        )
                    )
                    .allowsHitTesting(false)
                    .frame(
                        width: 118,
                        height: 82
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14,
                            style:
                                .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 14,
                            style:
                                .continuous
                        )
                        .stroke(
                            ATHLTHTheme
                                .vitality
                                .opacity(0.18),
                            lineWidth: 1
                        )
                    }
                }
            }
            .contentShape(
                Rectangle()
            )
        }
        .buttonStyle(.plain)
        .disabled(
            latitude == nil ||
            longitude == nil
        )
        .padding(.top, 10)
    }

    private func openMeetingPoint(
        _ meeting: String,
        latitude: Double,
        longitude: Double
    ) {
        let coordinate =
            CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )
        let placemark =
            MKPlacemark(
                coordinate:
                    coordinate
            )
        let mapItem =
            MKMapItem(
                placemark:
                    placemark
            )
        mapItem.name = meeting
        mapItem.openInMaps()
    }

    private func meetingRegion(
        _ coordinate:
            CLLocationCoordinate2D
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        0.012,
                    longitudeDelta:
                        0.012
                )
        )
    }

    private func eventDetailRow(
        _ title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.vitality)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
            }

            Spacer()
        }
        .padding(.top, 10)
    }
}

struct CommunityEventMapPlace:
    Identifiable,
    Hashable
{
    let id: String
    let displayName: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
}

struct CommunityEventMapPlacePickerView:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    let initialName: String
    let initialLatitude: Double?
    let initialLongitude: Double?
    let onSelect:
        (CommunityEventMapPlace) -> Void

    @State private var query = ""
    @State private var results:
        [CommunityEventMapPlace] = []
    @State private var isSearching =
        false
    @State private var isResolvingPoint =
        false
    @State private var searchError:
        String?
    @State private var selectedPlace:
        CommunityEventMapPlace?
    @State private var selectedCoordinate:
        CLLocationCoordinate2D?
    @State private var position:
        MapCameraPosition = .automatic
    @State private var didApplyInitialPosition =
        false

    init(
        initialName: String = "",
        initialLatitude: Double? = nil,
        initialLongitude: Double? = nil,
        onSelect:
            @escaping (CommunityEventMapPlace) -> Void
    ) {
        self.initialName = initialName
        self.initialLatitude = initialLatitude
        self.initialLongitude = initialLongitude
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                mapCard

                if let selectedPlace {
                    selectedPlaceCard(
                        selectedPlace
                    )
                } else {
                    HStack(
                        alignment: .top,
                        spacing: 10
                    ) {
                        Image(
                            systemName:
                                "hand.tap.fill"
                        )
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Search for an address or tap directly on the map to choose the exact meeting point.",
                                norwegian:
                                    "Søk etter en adresse, eller trykk direkte i kartet for å velge nøyaktig møtested."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                    .padding(.horizontal, 4)
                }

                if query
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .count >= 2 {
                    searchResultsSection
                } else {
                    searchHintCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 108)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .vitality
                        .opacity(0.16)
            )
        )
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Meeting point",
                norwegian:
                    "Møtested"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .searchable(
            text: $query,
            placement:
                .navigationBarDrawer(
                    displayMode:
                        .always
                ),
            prompt:
                ATHLTHLocalization.choose(
                    english:
                        "Address or place",
                    norwegian:
                        "Adresse eller sted"
                )
        )
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button(
                    ATHLTHLocalization.choose(
                        english: "Cancel",
                        norwegian: "Avbryt"
                    )
                ) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button {
                    guard let selectedPlace
                    else {
                        return
                    }

                    onSelect(selectedPlace)
                    dismiss()
                } label: {
                    HStack(spacing: 7) {
                        if isResolvingPoint {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Use meeting point",
                                norwegian:
                                    "Bruk møtested"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                    }
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 48)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
                .disabled(
                    selectedPlace == nil ||
                    isResolvingPoint
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .task(id: query) {
            await searchMaps()
        }
        .onAppear {
            applyInitialPositionIfNeeded()
        }
    }

    private var mapCard:
        some View {
        MapReader { proxy in
            Map(position: $position) {
                if let selectedCoordinate {
                    Marker(
                        ATHLTHLocalization.choose(
                            english:
                                "Meeting point",
                            norwegian:
                                "Møtested"
                        ),
                        coordinate:
                            selectedCoordinate
                    )
                    .tint(
                        ATHLTHTheme.vitality
                    )
                }

                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture {
                point in

                guard
                    let coordinate =
                        proxy.convert(
                            point,
                            from: .local
                        )
                else {
                    return
                }

                selectedCoordinate =
                    coordinate
                position =
                    .region(
                        MKCoordinateRegion(
                            center:
                                coordinate,
                            span:
                                MKCoordinateSpan(
                                    latitudeDelta:
                                        0.012,
                                    longitudeDelta:
                                        0.012
                                )
                        )
                    )

                Task {
                    await resolveMapPoint(
                        coordinate
                    )
                }
            }
        }
        .frame(height: 300)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.90),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.07),
            radius: 14,
            y: 7
        )
        .overlay(
            alignment: .topLeading
        ) {
            Label(
                ATHLTHLocalization.choose(
                    english:
                        "Tap map to place pin",
                    norwegian:
                        "Trykk i kartet for å sette punkt"
                ),
                systemImage:
                    "hand.tap"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .padding(10)
        }
    }

    private func selectedPlaceCard(
        _ place: CommunityEventMapPlace
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    "mappin.circle.fill"
            )
            .font(
                .system(
                    size: 19,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.vitality
            )
            .frame(
                width: 42,
                height: 42
            )
            .background(
                ATHLTHTheme.vitalitySoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Selected meeting point",
                        norwegian:
                            "Valgt møtested"
                    )
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Text(place.displayName)
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(2)

                if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(2)
                }
            }

            Spacer()

            if isResolvingPoint {
                ProgressView()
            } else {
                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
            }
        }
        .padding(14)
        .background(
            Color.white.opacity(0.72),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.88),
                lineWidth: 0.8
            )
        }
    }

    @ViewBuilder
    private var searchResultsSection:
        some View {
        VStack(
            alignment: .leading,
            spacing: 9
        ) {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "SEARCH RESULTS",
                    norwegian:
                        "SØKERESULTATER"
                )
            )
            .font(.caption2.weight(.bold))
            .tracking(1.4)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .padding(.horizontal, 3)

            if isSearching &&
                results.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(height: 90)
            } else if let searchError,
                      results.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english:
                            "Could not search Maps",
                        norwegian:
                            "Kunne ikke søke i Maps"
                    ),
                    systemImage:
                        "exclamationmark.triangle",
                    description:
                        Text(searchError)
                )
                .frame(minHeight: 120)
            } else if results.isEmpty {
                ContentUnavailableView(
                    ATHLTHLocalization.choose(
                        english:
                            "No places found",
                        norwegian:
                            "Fant ingen steder"
                    ),
                    systemImage:
                        "mappin.slash"
                )
                .frame(minHeight: 110)
            } else {
                VStack(spacing: 7) {
                    ForEach(results) {
                        place in

                        Button {
                            selectSearchResult(
                                place
                            )
                        } label: {
                            HStack(
                                spacing: 11
                            ) {
                                Image(
                                    systemName:
                                        "mappin.circle.fill"
                                )
                                .font(
                                    .system(
                                        size: 16,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .vitality
                                )
                                .frame(
                                    width: 38,
                                    height: 38
                                )
                                .background(
                                    ATHLTHTheme
                                        .vitalitySoft,
                                    in:
                                        RoundedRectangle(
                                            cornerRadius:
                                                11,
                                            style:
                                                .continuous
                                        )
                                )

                                VStack(
                                    alignment:
                                        .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        place
                                            .displayName
                                    )
                                    .font(
                                        .subheadline
                                            .weight(
                                                .semibold
                                            )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )
                                    .lineLimit(1)

                                    if !place
                                        .subtitle
                                        .isEmpty {
                                        Text(
                                            place
                                                .subtitle
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                        .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        selectedPlace?.id ==
                                        place.id
                                        ? "checkmark.circle.fill"
                                        : "chevron.right"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(
                                    selectedPlace?.id ==
                                    place.id
                                    ? ATHLTHTheme
                                        .vitality
                                    : .secondary
                                )
                            }
                            .padding(.horizontal, 11)
                            .frame(minHeight: 58)
                            .background(
                                Color.white
                                    .opacity(0.68),
                                in:
                                    RoundedRectangle(
                                        cornerRadius:
                                            16,
                                        style:
                                            .continuous
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchHintCard:
        some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            Image(
                systemName:
                    "magnifyingglass"
            )
            .font(
                .system(
                    size: 16,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                ATHLTHTheme.accentSoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Search Apple Maps",
                        norwegian:
                            "Søk i Apple Maps"
                    )
                )
                .font(
                    .subheadline
                        .weight(
                            .semibold
                        )
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Search for a street address, gym, park or other place. You can also ignore search and place the pin manually.",
                        norwegian:
                            "Søk etter gateadresse, treningssenter, park eller annet sted. Du kan også hoppe over søket og sette punktet manuelt i kartet."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(14)
        .background(
            Color.white.opacity(0.62),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
    }

    private func applyInitialPositionIfNeeded() {
        guard !didApplyInitialPosition
        else {
            return
        }

        didApplyInitialPosition = true

        guard
            let initialLatitude,
            let initialLongitude
        else {
            position =
                .userLocation(
                    followsHeading: false,
                    fallback: .automatic
                )
            return
        }

        let coordinate =
            CLLocationCoordinate2D(
                latitude:
                    initialLatitude,
                longitude:
                    initialLongitude
            )

        selectedCoordinate = coordinate
        position =
            .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span:
                        MKCoordinateSpan(
                            latitudeDelta:
                                0.012,
                            longitudeDelta:
                                0.012
                        )
                )
            )

        let cleanName =
            initialName
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        selectedPlace =
            CommunityEventMapPlace(
                id:
                    "\(initialLatitude)|\(initialLongitude)|\(cleanName)",
                displayName:
                    cleanName.isEmpty
                        ? ATHLTHLocalization.choose(
                            english:
                                "Selected point",
                            norwegian:
                                "Valgt punkt"
                        )
                        : cleanName,
                subtitle: "",
                latitude:
                    initialLatitude,
                longitude:
                    initialLongitude
            )
    }

    private func selectSearchResult(
        _ place: CommunityEventMapPlace
    ) {
        selectedPlace = place

        let coordinate =
            CLLocationCoordinate2D(
                latitude:
                    place.latitude,
                longitude:
                    place.longitude
            )
        selectedCoordinate =
            coordinate

        withAnimation(
            .easeOut(duration: 0.20)
        ) {
            position =
                .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span:
                            MKCoordinateSpan(
                                latitudeDelta:
                                    0.012,
                                longitudeDelta:
                                    0.012
                            )
                    )
                )
        }
    }

    @MainActor
    private func resolveMapPoint(
        _ coordinate:
            CLLocationCoordinate2D
    ) async {
        isResolvingPoint = true
        searchError = nil

        defer {
            isResolvingPoint = false
        }

        do {
            let placemarks =
                try await CLGeocoder()
                    .reverseGeocodeLocation(
                        CLLocation(
                            latitude:
                                coordinate
                                    .latitude,
                            longitude:
                                coordinate
                                    .longitude
                        )
                    )

            guard let placemark =
                    placemarks.first
            else {
                selectedPlace =
                    fallbackPlace(
                        coordinate
                    )
                return
            }

            let street =
                [
                    placemark
                        .subThoroughfare,
                    placemark
                        .thoroughfare
                ]
                .compactMap { $0 }
                .filter {
                    !$0.isEmpty
                }
                .joined(
                    separator: " "
                )
            let city =
                [
                    placemark.postalCode,
                    placemark.locality
                ]
                .compactMap { $0 }
                .filter {
                    !$0.isEmpty
                }
                .joined(
                    separator: " "
                )
            let subtitle =
                [
                    street,
                    city,
                    placemark
                        .administrativeArea
                ]
                .compactMap { $0 }
                .filter {
                    !$0.isEmpty
                }
                .joined(
                    separator: ", "
                )
            let name =
                placemark.name ??
                (!street.isEmpty
                    ? street
                    : ATHLTHLocalization.choose(
                        english:
                            "Selected point",
                        norwegian:
                            "Valgt punkt"
                    ))

            selectedPlace =
                CommunityEventMapPlace(
                    id:
                        "\(coordinate.latitude)|\(coordinate.longitude)|\(name)",
                    displayName:
                        name,
                    subtitle:
                        subtitle,
                    latitude:
                        coordinate.latitude,
                    longitude:
                        coordinate.longitude
                )
        } catch {
            selectedPlace =
                fallbackPlace(
                    coordinate
                )
        }
    }

    private func fallbackPlace(
        _ coordinate:
            CLLocationCoordinate2D
    ) -> CommunityEventMapPlace {
        CommunityEventMapPlace(
            id:
                "\(coordinate.latitude)|\(coordinate.longitude)|manual",
            displayName:
                ATHLTHLocalization.choose(
                    english:
                        "Pinned location",
                    norwegian:
                        "Valgt punkt"
                ),
            subtitle:
                String(
                    format:
                        "%.5f, %.5f",
                    coordinate.latitude,
                    coordinate.longitude
                ),
            latitude:
                coordinate.latitude,
            longitude:
                coordinate.longitude
        )
    }

    @MainActor
    private func searchMaps() async {
        let clean =
            query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard clean.count >= 2
        else {
            results = []
            isSearching = false
            searchError = nil
            return
        }

        do {
            try await Task.sleep(
                for:
                    .milliseconds(280)
            )
        } catch {
            return
        }

        guard !Task.isCancelled
        else {
            return
        }

        isSearching = true
        searchError = nil

        let request =
            MKLocalSearch.Request()
        request.naturalLanguageQuery =
            clean
        request.resultTypes = [
            .address,
            .pointOfInterest
        ]

        do {
            let response =
                try await MKLocalSearch(
                    request: request
                )
                .start()

            guard !Task.isCancelled
            else {
                return
            }

            results =
                response.mapItems
                    .prefix(20)
                    .map {
                        mapPlace($0)
                    }
            isSearching = false
        } catch {
            guard !Task.isCancelled
            else {
                return
            }

            results = []
            isSearching = false
            searchError =
                error.localizedDescription
        }
    }

    private func mapPlace(
        _ item: MKMapItem
    ) -> CommunityEventMapPlace {
        let placemark =
            item.placemark
        let street =
            [
                placemark
                    .subThoroughfare,
                placemark
                    .thoroughfare
            ]
            .compactMap { $0 }
            .filter {
                !$0.isEmpty
            }
            .joined(
                separator: " "
            )
        let city =
            [
                placemark.postalCode,
                placemark.locality
            ]
            .compactMap { $0 }
            .filter {
                !$0.isEmpty
            }
            .joined(
                separator: " "
            )
        let subtitle =
            [
                street,
                city,
                placemark
                    .administrativeArea
            ]
            .compactMap { $0 }
            .filter {
                !$0.isEmpty
            }
            .joined(
                separator: ", "
            )
        let fallback =
            subtitle.isEmpty
                ? (
                    placemark.title ??
                    ""
                )
                : subtitle
        let displayName =
            item.name ??
            placemark.name ??
            fallback

        return CommunityEventMapPlace(
            id:
                "\(placemark.coordinate.latitude)|\(placemark.coordinate.longitude)|\(displayName)",
            displayName:
                displayName,
            subtitle:
                subtitle,
            latitude:
                placemark
                    .coordinate
                    .latitude,
            longitude:
                placemark
                    .coordinate
                    .longitude
        )
    }
}

private struct CommunityEventEditView: View {
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject
    private var community:
        CommunityEventStore

    let item: CommunityEventItem

    @State private var draft:
        CommunityEventDraft
    @State private var limitParticipants:
        Bool
    @State private var maxParticipants: Int
    @State private var isSaving = false

    init(item: CommunityEventItem) {
        self.item = item

        var initial =
            CommunityEventDraft()
        initial.title = item.event.title
        initial.summary =
            item.event.summary
        initial.activityType =
            item.event.activityType
        initial.visibility =
            ProfileVisibility(
                rawValue:
                    item.event.visibility
            ) ?? .publicProfile
        initial.startsAt =
            item.event.startsAt
        initial.meetingName =
            item.event.meetingName
        initial.meetingDetails =
            item.event.meetingDetails ?? ""
        initial.latitude =
            item.event.latitude
        initial.longitude =
            item.event.longitude
        initial.maxParticipants =
            item.event.maxParticipants
        initial.paceLabel =
            item.event.paceLabel ?? ""
        initial.routeID =
            item.event.routeID
        initial.routeTitle =
            item.event.routeTitle
        initial.routeCoordinates =
            item.event.routeCoordinates
        initial.routeDistanceKilometers =
            item.event
                .routeDistanceKilometers
        initial.routeElevationGainMeters =
            item.event
                .routeElevationGainMeters
        initial.routeStartName =
            item.event.routeStartName
        initial.routeEndName =
            item.event.routeEndName
        initial.coverArtworkName =
            item.event.coverArtworkName
        initial.coverImageURL =
            item.event.coverImageURL

        _draft = State(
            initialValue: initial
        )
        _limitParticipants =
            State(
                initialValue:
                    item.event
                        .maxParticipants != nil
            )
        _maxParticipants =
            State(
                initialValue:
                    item.event
                        .maxParticipants ?? 20
            )
    }

    private var canSave: Bool {
        !draft.title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty &&
        !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    ATHLTHLocalization.choose(
                        english: "Event",
                        norwegian: "Arrangement"
                    )
                ) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Event name",
                            norwegian:
                                "Navn på arrangement"
                        ),
                        text: $draft.title
                    )

                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Description",
                            norwegian: "Beskrivelse"
                        ),
                        text: $draft.summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Activity",
                            norwegian: "Aktivitet"
                        ),
                        selection:
                            $draft.activityType
                    ) {
                        ForEach(
                            CommunityEventActivity
                                .allCases
                        ) { activity in
                            Label(
                                activity.title,
                                systemImage:
                                    activity
                                        .systemImage
                            )
                            .tag(activity)
                        }
                    }

                    DatePicker(
                        ATHLTHLocalization.choose(
                            english: "Starts",
                            norwegian: "Starter"
                        ),
                        selection:
                            $draft.startsAt,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )

                    Picker(
                        ATHLTHLocalization.choose(
                            english:
                                "Who can see it",
                            norwegian:
                                "Hvem kan se det"
                        ),
                        selection:
                            $draft.visibility
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Public",
                                norwegian:
                                    "Offentlig"
                            )
                        )
                        .tag(
                            ProfileVisibility
                                .publicProfile
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english: "Friends",
                                norwegian: "Følgere"
                            )
                        )
                        .tag(
                            ProfileVisibility
                                .friends
                        )
                    }
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Meet",
                        norwegian: "Oppmøte"
                    )
                ) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Meeting point",
                            norwegian: "Møtested"
                        ),
                        text:
                            $draft.meetingName
                    )

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Meeting details",
                            norwegian: "Detaljer"
                        ),
                        text:
                            $draft.meetingDetails,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    if draft.activityType ==
                        .running ||
                        draft.activityType ==
                        .walking {
                        TextField(
                            ATHLTHLocalization.choose(
                                english:
                                    "Pace / level",
                                norwegian:
                                    "Fart / nivå"
                            ),
                            text:
                                $draft.paceLabel
                        )
                    }
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Participants",
                        norwegian: "Deltakere"
                    )
                ) {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english:
                                "Limit participants",
                            norwegian:
                                "Begrens antall deltakere"
                        ),
                        isOn:
                            $limitParticipants
                    )

                    if limitParticipants {
                        Stepper(
                            value:
                                $maxParticipants,
                            in: 2...500
                        ) {
                            Text(
                                ATHLTHLocalization.format(
                                    english:
                                        "Maximum %d",
                                    norwegian:
                                        "Maks %d",
                                    maxParticipants
                                )
                            )
                        }
                    }
                }

                if item.event.routeID != nil ||
                    item.event
                        .routeCoordinates?
                        .isEmpty == false {
                    Section {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "The current route is kept when you save.",
                                norwegian:
                                    "Gjeldende rute beholdes når du lagrer."
                            ),
                            systemImage: "map"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Edit Event",
                    norwegian:
                        "Rediger arrangement"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        isSaving
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Saving…",
                                    norwegian:
                                        "Lagrer…"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english: "Save",
                                    norwegian: "Lagre"
                                )
                    ) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        var updated = draft
        updated.maxParticipants =
            limitParticipants
                ? maxParticipants
                : nil

        let oldMeeting =
            item.event.meetingName
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
        let newMeeting =
            updated.meetingName
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        if oldMeeting != newMeeting {
            updated.latitude = nil
            updated.longitude = nil
        }

        if updated.activityType !=
            .running &&
            updated.activityType !=
            .walking {
            updated.paceLabel = ""
            updated.routeID = nil
            updated.routeTitle = nil
            updated.routeCoordinates = nil
            updated.routeDistanceKilometers =
                nil
            updated.routeElevationGainMeters =
                nil
            updated.routeStartName = nil
            updated.routeEndName = nil
        }

        Task {
            isSaving = true
            let saved =
                await community.update(
                    item,
                    with: updated
                )
            isSaving = false

            if saved {
                dismiss()
            }
        }
    }
}

struct CommunityEventCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    @State private var draft = CommunityEventDraft()
    @State private var limitParticipants = false
    @State private var maxParticipants = 20
    @State private var selectedRouteID: UUID?
    @State private var shareToCommunity = true
    @State private var isCreating = false
    @State private var selectedCoverArtworkName =
        CommunityEventCoverPolicy
            .defaultArtwork(
                for: .running
            )
    @State private var selectedCoverPhoto:
        PhotosPickerItem?
    @State private var selectedCoverImageData:
        Data?
    @State private var coverWasManuallySelected =
        false
    @State private var createError: String?
    @State private var restoredSavedDraft =
        false
    @State private var showingMeetingSearch =
        false

    private var canCreate: Bool {
        draft.isValidForCreation() &&
        !isCreating
    }

    private var selectedRoute: TrainingRoute? {
        guard let selectedRouteID else {
            return nil
        }

        return session.savedRoutes.first {
            $0.id == selectedRouteID
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme.vitality
                            .opacity(0.20)
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        eventHero
                        eventCoverPicker

                        if let createError {
                            Text(createError)
                                .font(.caption)
                                .foregroundStyle(
                                    .red
                                )
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    alignment:
                                        .leading
                                )
                                .padding(
                                    .horizontal,
                                    4
                                )
                        }

                        eventSection(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Event",
                                    norwegian: "Arrangement"
                                ),
                            icon:
                                "calendar.badge.plus"
                        ) {
                            eventTextField(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Event name",
                                        norwegian: "Navn på arrangement"
                                    ),
                                placeholder:
                                    ATHLTHLocalization.choose(
                                        english: "Add a name",
                                        norwegian: "Gi arrangementet et navn"
                                    ),
                                text: $draft.title,
                                icon: "doc.text"
                            )

                            eventDivider

                            Menu {
                                ForEach(
                                    CommunityEventActivity.allCases
                                ) { activity in
                                    Button {
                                        draft.activityType =
                                            activity

                                        if activity !=
                                            .running &&
                                            activity !=
                                            .walking {
                                            draft.paceLabel =
                                                ""
                                            selectedRouteID =
                                                nil
                                        }
                                    } label: {
                                        Label(
                                            activity.title,
                                            systemImage:
                                                activity
                                                    .systemImage
                                        )
                                    }
                                }
                            } label: {
                                eventSelectionRow(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Activity",
                                            norwegian: "Aktivitet"
                                        ),
                                    value:
                                        draft.activityType
                                            .title,
                                    icon:
                                        draft.activityType
                                            .systemImage
                                )
                            }
                            .buttonStyle(.plain)

                            eventDivider

                            eventTextField(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Description",
                                        norwegian: "Beskrivelse"
                                    ),
                                placeholder:
                                    ATHLTHLocalization.choose(
                                        english: "Optional",
                                        norwegian: "Valgfritt"
                                    ),
                                text: $draft.summary,
                                icon: "text.alignleft",
                                axis: .vertical
                            )

                            eventDivider

                            HStack(spacing: 10) {
                                compactDateControl(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Date",
                                            norwegian: "Dato"
                                        ),
                                    icon: "calendar",
                                    components: [.date]
                                )

                                compactDateControl(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Time",
                                            norwegian: "Tid"
                                        ),
                                    icon: "clock",
                                    components: [
                                        .hourAndMinute
                                    ]
                                )
                            }

                            eventDivider

                            Menu {
                                Button {
                                    draft.visibility =
                                        .publicProfile
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Public",
                                            norwegian: "Offentlig"
                                        ),
                                        systemImage: "globe"
                                    )
                                }

                                Button {
                                    draft.visibility =
                                        .friends
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Friends",
                                            norwegian: "Følgere"
                                        ),
                                        systemImage:
                                            "person.2.fill"
                                    )
                                }
                            } label: {
                                eventSelectionRow(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Who can see it",
                                            norwegian: "Hvem kan se det"
                                        ),
                                    value:
                                        visibilityTitle,
                                    icon:
                                        draft.visibility ==
                                            .publicProfile
                                            ? "globe"
                                            : "person.2.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        eventSection(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Meet",
                                    norwegian: "Oppmøte"
                                ),
                            icon:
                                "mappin.and.ellipse"
                        ) {
                            Button {
                                showingMeetingSearch =
                                    true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName:
                                            "mappin.and.ellipse"
                                    )
                                    .font(
                                        .system(
                                            size: 17,
                                            weight:
                                                .semibold
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .vitality
                                    )
                                    .frame(
                                        width: 38,
                                        height: 38
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .vitalitySoft,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius: 12,
                                                style:
                                                    .continuous
                                            )
                                    )

                                    VStack(
                                        alignment: .leading,
                                        spacing: 3
                                    ) {
                                        Text(
                                            ATHLTHLocalization.choose(
                                                english:
                                                    "Meeting point",
                                                norwegian:
                                                    "Møtested"
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )

                                        Text(
                                            draft.meetingName
                                                .nilIfBlank ??
                                            ATHLTHLocalization.choose(
                                                english:
                                                    "Choose from Apple Maps",
                                                norwegian:
                                                    "Velg fra Apple Maps"
                                            )
                                        )
                                        .font(
                                            .subheadline
                                                .weight(
                                                    draft.meetingName
                                                        .nilIfBlank ==
                                                        nil
                                                        ? .regular
                                                        : .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            draft.meetingName
                                                .nilIfBlank ==
                                                nil
                                                ? .secondary
                                                : ATHLTHTheme
                                                    .primaryText
                                        )
                                        .lineLimit(2)
                                    }

                                    Spacer()

                                    if draft.latitude != nil,
                                       draft.longitude != nil {
                                        Image(
                                            systemName:
                                                "checkmark.circle.fill"
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .vitality
                                        )
                                    }

                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                            .buttonStyle(.plain)

                            if draft.latitude != nil ||
                                draft.longitude != nil ||
                                !draft.meetingName.isEmpty {
                                Button(
                                    role: .destructive
                                ) {
                                    clearMeetingPoint()
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Clear meeting point",
                                            norwegian:
                                                "Fjern møtested"
                                        ),
                                        systemImage:
                                            "xmark.circle"
                                    )
                                    .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }

                            eventDivider

                            eventTextField(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Meeting details",
                                        norwegian: "Detaljer"
                                    ),
                                placeholder:
                                    ATHLTHLocalization.choose(
                                        english: "Optional",
                                        norwegian: "Valgfritt"
                                    ),
                                text:
                                    $draft.meetingDetails,
                                icon:
                                    "text.bubble",
                                axis: .vertical
                            )

                            if draft.activityType ==
                                .running ||
                                draft.activityType ==
                                .walking {
                                eventDivider

                                eventTextField(
                                    title:
                                        ATHLTHLocalization.choose(
                                            english: "Pace / level",
                                            norwegian: "Fart / nivå"
                                        ),
                                    placeholder:
                                        ATHLTHLocalization.choose(
                                            english: "Optional",
                                            norwegian: "Valgfritt"
                                        ),
                                    text:
                                        $draft.paceLabel,
                                    icon:
                                        "speedometer"
                                )

                                eventDivider

                                HStack(spacing: 12) {
                                    Image(
                                        systemName:
                                            "point.topleft.down.to.point.bottomright.curvepath"
                                    )
                                    .font(
                                        .system(
                                            size: 17,
                                            weight:
                                                .semibold
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .vitality
                                    )
                                    .frame(
                                        width: 38,
                                        height: 38
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .vitalitySoft,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius: 12,
                                                style:
                                                    .continuous
                                            )
                                    )

                                    Text(
                                        ATHLTHLocalization.choose(
                                            english: "Route",
                                            norwegian: "Rute"
                                        )
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )

                                    Spacer(
                                        minLength: 8
                                    )

                                    Menu {
                                        Button {
                                            selectedRouteID =
                                                nil
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "No route",
                                                    norwegian: "Ingen rute"
                                                ),
                                                systemImage:
                                                    "xmark.circle"
                                            )
                                        }

                                        ForEach(
                                            session.savedRoutes
                                        ) { route in
                                            Button {
                                                selectedRouteID =
                                                    route.id
                                            } label: {
                                                Label(
                                                    route.title,
                                                    systemImage:
                                                        "map"
                                                )
                                            }
                                        }
                                    } label: {
                                        HStack(
                                            spacing: 7
                                        ) {
                                            Text(
                                                selectedRoute?
                                                    .title ??
                                                ATHLTHLocalization.choose(
                                                    english:
                                                        "No route",
                                                    norwegian:
                                                        "Ingen rute"
                                                )
                                            )
                                            .lineLimit(1)
                                            .minimumScaleFactor(
                                                0.78
                                            )

                                            Image(
                                                systemName:
                                                    "chevron.up.chevron.down"
                                            )
                                            .font(
                                                .caption2
                                                    .bold()
                                            )
                                        }
                                        .font(
                                            .subheadline
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .accentDeep
                                        )
                                        .padding(
                                            .horizontal,
                                            12
                                        )
                                        .frame(
                                            height: 40
                                        )
                                        .background(
                                            ATHLTHTheme
                                                .surfaceSage,
                                            in: Capsule()
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    NavigationLink {
                                        RunRouteBuilderView()
                                    } label: {
                                        Image(
                                            systemName:
                                                "plus"
                                        )
                                        .font(
                                            .system(
                                                size: 16,
                                                weight:
                                                    .bold
                                            )
                                        )
                                        .foregroundStyle(
                                            .white
                                        )
                                        .frame(
                                            width: 40,
                                            height: 40
                                        )
                                        .background(
                                            ATHLTHTheme
                                                .vitality,
                                            in: Circle()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Create new route",
                                            norwegian:
                                                "Lag ny rute"
                                        )
                                    )
                                }

                                if let selectedRoute {
                                    eventRoutePreview(
                                        selectedRoute
                                    )
                                    .padding(.top, 12)
                                }
                            }
                        }

                        eventSection(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Participants",
                                    norwegian: "Deltakere"
                                ),
                            icon: "person.2.fill"
                        ) {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "person.badge.plus"
                                )
                                .font(
                                    .system(
                                        size: 17,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.accent
                                )
                                .frame(
                                    width: 38,
                                    height: 38
                                )
                                .background(
                                    ATHLTHTheme
                                        .accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 12,
                                        style:
                                            .continuous
                                    )
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Limit participants",
                                        norwegian:
                                            "Begrens deltakere"
                                    )
                                )
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )

                                Spacer()

                                Toggle(
                                    "",
                                    isOn:
                                        $limitParticipants
                                )
                                .labelsHidden()
                                .tint(
                                    ATHLTHTheme.accent
                                )
                            }

                            if limitParticipants {
                                eventDivider

                                HStack(spacing: 14) {
                                    Text(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Maximum participants",
                                            norwegian:
                                                "Maks antall deltakere"
                                        )
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        .secondary
                                    )

                                    Spacer()

                                    Button {
                                        maxParticipants =
                                            max(
                                                2,
                                                maxParticipants -
                                                1
                                            )
                                    } label: {
                                        Image(
                                            systemName:
                                                "minus"
                                        )
                                        .frame(
                                            width: 34,
                                            height: 34
                                        )
                                        .background(
                                            Color.primary
                                                .opacity(
                                                    0.045
                                                ),
                                            in: Circle()
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Text(
                                        "\(maxParticipants)"
                                    )
                                    .font(
                                        .headline
                                            .monospacedDigit()
                                    )
                                    .frame(
                                        minWidth: 32
                                    )

                                    Button {
                                        maxParticipants =
                                            min(
                                                500,
                                                maxParticipants +
                                                1
                                            )
                                    } label: {
                                        Image(
                                            systemName:
                                                "plus"
                                        )
                                        .frame(
                                            width: 34,
                                            height: 34
                                        )
                                        .background(
                                            Color.primary
                                                .opacity(
                                                    0.045
                                                ),
                                            in: Circle()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        eventSection(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Community",
                                    norwegian: "Fellesskap"
                                ),
                            icon: "person.3.fill"
                        ) {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "megaphone.fill"
                                )
                                .font(
                                    .system(
                                        size: 17,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.accent
                                )
                                .frame(
                                    width: 38,
                                    height: 38
                                )
                                .background(
                                    ATHLTHTheme
                                        .accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 12,
                                        style:
                                            .continuous
                                    )
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Share to Community activity",
                                            norwegian:
                                                "Del til Community-aktivitet"
                                        )
                                    )
                                    .font(
                                        .subheadline
                                            .weight(
                                                .semibold
                                            )
                                    )

                                    Text(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "People who can see the event can also discover it in Community.",
                                            norwegian:
                                                "Arrangementet kan vises i Community for dem som har tilgang."
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                    .fixedSize(
                                        horizontal:
                                            false,
                                        vertical: true
                                    )
                                }

                                Spacer(
                                    minLength: 8
                                )

                                Toggle(
                                    "",
                                    isOn:
                                        $shareToCommunity
                                )
                                .labelsHidden()
                                .tint(
                                    ATHLTHTheme.accent
                                )
                            }

                            eventDivider

                            Label(
                                privacyMessage,
                                systemImage:
                                    draft.visibility ==
                                        .publicProfile
                                        ? "globe"
                                        : "lock.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(
                    .interactively
                )
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Create Event",
                    norwegian: "Opprett arrangement"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbarBackground(
                .hidden,
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        clearSavedDraft()
                        dismiss()
                    }
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button {
                        createEvent()
                    } label: {
                        Text(
                            isCreating
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Creating…",
                                    norwegian:
                                        "Oppretter…"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Create",
                                    norwegian:
                                        "Opprett"
                                )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                    }
                    .disabled(!canCreate)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.35)

                    Button {
                        createEvent()
                    } label: {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(
                                isCreating
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Creating…",
                                        norwegian:
                                            "Oppretter…"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english:
                                            "Create event",
                                        norwegian:
                                            "Opprett arrangement"
                                    )
                            )
                            .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            ATHLTHTheme
                                .vitality,
                            in: Capsule(
                                style:
                                    .continuous
                            )
                        )
                        .opacity(
                            canCreate
                                ? 1
                                : 0.34
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(
                    .ultraThinMaterial
                )
            }
            .sheet(
                isPresented:
                    $showingMeetingSearch
            ) {
                NavigationStack {
                    CommunityEventMapPlacePickerView {
                        place in
                        applyMeetingPlace(
                            place
                        )
                        showingMeetingSearch =
                            false
                    }
                }
            }
            .task {
                restoreSavedDraftIfNeeded()
            }
            .onChange(
                of: draft
            ) { _, _ in
                saveDraftIfRestored()
            }
            .onChange(
                of: limitParticipants
            ) { _, _ in
                saveDraftIfRestored()
            }
            .onChange(
                of: maxParticipants
            ) { _, _ in
                saveDraftIfRestored()
            }
            .onChange(
                of: selectedRouteID
            ) { _, _ in
                saveDraftIfRestored()
            }
            .onChange(
                of: shareToCommunity
            ) { _, _ in
                saveDraftIfRestored()
            }
            .onChange(
                of: selectedCoverArtworkName
            ) { _, _ in
                saveDraftIfRestored()
            }
            .onChange(
                of: coverWasManuallySelected
            ) { _, _ in
                saveDraftIfRestored()
            }
            .onChange(
                of: draft.activityType
            ) { _, activity in
                if !coverWasManuallySelected &&
                    selectedCoverImageData ==
                        nil {
                    selectedCoverArtworkName =
                        CommunityEventCoverPolicy
                            .defaultArtwork(
                                for: activity
                            )
                }
            }
            .onChange(
                of: selectedCoverPhoto
            ) { _, item in
                guard let item else {
                    return
                }

                Task {
                    guard let data =
                            try? await item
                                .loadTransferable(
                                    type: Data.self
                                ),
                          let image =
                            UIImage(data: data),
                          let jpeg =
                            image.jpegData(
                                compressionQuality:
                                    0.86
                            )
                    else {
                        await MainActor.run {
                            createError =
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "The selected image could not be read.",
                                        norwegian:
                                            "Det valgte bildet kunne ikke leses."
                                    )
                        }
                        return
                    }

                    await MainActor.run {
                        selectedCoverImageData =
                            jpeg
                        coverWasManuallySelected =
                            true
                        createError = nil
                    }
                }
            }
            .sensoryFeedback(
                .selection,
                trigger:
                    draft.activityType
            )
            .sensoryFeedback(
                .selection,
                trigger:
                    draft.visibility
            )
        }
    }

    private var eventHero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data =
                        selectedCoverImageData,
                   let image =
                        UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(
                        CommunityEventCoverPolicy
                            .displayArtworkName(
                                selectedCoverArtworkName
                            )
                    )
                    .resizable()
                    .scaledToFill()
                    .clipped()
                }
            }
            .athlthBoundedFill()
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    .clear,
                    Color.black.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Label(
                eventActivityLabel,
                systemImage:
                    draft.activityType
                        .systemImage
            )
            .font(
                .caption.weight(.semibold)
            )
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .padding(14)
        }
        .frame(height: 150)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.35),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.06),
            radius: 12,
            y: 5
        )
    }

    private var eventCoverPicker:
        some View {
        VStack(
            alignment: .leading,
            spacing: 9
        ) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Cover",
                        norwegian: "Bilde"
                    ),
                    systemImage: "photo"
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                PhotosPicker(
                    selection:
                        $selectedCoverPhoto,
                    matching: .images
                ) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Own photo",
                            norwegian: "Eget bilde"
                        ),
                        systemImage:
                            "photo.badge.plus"
                    )
                    .font(.caption.weight(.semibold))
                }
            }

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 9) {
                    ForEach(
                        CommunityEventCoverPolicy
                            .standardArtworkOptions,
                        id: \.self
                    ) { artwork in
                        Button {
                            selectedCoverArtworkName =
                                artwork
                            selectedCoverImageData =
                                nil
                            selectedCoverPhoto =
                                nil
                            coverWasManuallySelected =
                                true
                            createError = nil
                        } label: {
                            Image(
                                CommunityEventCoverPolicy
                                    .thumbnailArtworkName(
                                        artwork
                                    )
                            )
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: 82,
                                    height: 52
                                )
                                .clipped()
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            12,
                                        style:
                                            .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius:
                                            12,
                                        style:
                                            .continuous
                                    )
                                    .stroke(
                                        selectedCoverImageData ==
                                                nil &&
                                            selectedCoverArtworkName ==
                                                artwork
                                            ? ATHLTHTheme
                                                .accent
                                            : Color
                                                .black
                                                .opacity(
                                                    0.05
                                                ),
                                        lineWidth:
                                            selectedCoverImageData ==
                                                    nil &&
                                                selectedCoverArtworkName ==
                                                    artwork
                                                ? 2
                                                : 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(
            ATHLTHTheme.surfaceSage,
            in: RoundedRectangle(
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
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
    }

    private var eventArtworkName: String {
        selectedCoverArtworkName
    }

    private var eventActivityLabel: String {
        ATHLTHLocalization.format(
            english: "%@ event",
            norwegian: "%@event",
            draft.activityType.title
        )
    }

    private var visibilityTitle: String {
        draft.visibility ==
            .publicProfile
            ? ATHLTHLocalization.choose(
                english: "Public",
                norwegian: "Offentlig"
            )
            : ATHLTHLocalization.choose(
                english: "Friends",
                norwegian: "Følgere"
            )
    }

    private var privacyMessage: String {
        draft.visibility ==
            .publicProfile
            ? ATHLTHLocalization.choose(
                english:
                    "Public events can be discovered by signed-in ATHLTH users.",
                norwegian:
                    "Offentlige arrangementer kan oppdages av innloggede ATHLTH-brukere."
            )
            : ATHLTHLocalization.choose(
                english:
                    "Followers-only events are limited to your ATHLTH network.",
                norwegian:
                    "Arrangementet er begrenset til følgernettverket ditt."
            )
    }

    private var eventDivider: some View {
        Divider()
            .opacity(0.42)
            .padding(.leading, 50)
    }

    private func eventSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                HStack(spacing: 10) {
                    Image(
                        systemName: icon
                    )
                    .font(
                        .system(
                            size: 16,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .vitality
                    )
                    .frame(
                        width: 36,
                        height: 36
                    )
                    .background(
                        ATHLTHTheme
                            .vitalitySoft,
                        in:
                            RoundedRectangle(
                                cornerRadius: 11,
                                style:
                                    .continuous
                            )
                    )

                    Text(title)
                        .font(
                            .headline
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                    Spacer()
                }

                content()
            }
        }
    }

    private func eventTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        axis: Axis = .horizontal
    ) -> some View {
        HStack(
            alignment:
                axis == .vertical
                    ? .top
                    : .center,
            spacing: 12
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    placeholder,
                    text: text,
                    axis: axis
                )
                .font(.body)
                .lineLimit(
                    axis == .vertical
                        ? 2...4
                        : 1...1
                )
            }
        }
        .padding(.vertical, 2)
    }

    private func eventSelectionRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accent
                )
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            Text(title)
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Spacer()

            HStack(spacing: 7) {
                Text(value)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .lineLimit(1)

                Image(
                    systemName:
                        "chevron.up.chevron.down"
                )
                .font(.caption2.bold())
            }
            .foregroundStyle(
                Color(
                    red: 0.20,
                    green: 0.26,
                    blue: 0.36
                )
            )
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                Color(
                    red: 0.91,
                    green: 0.94,
                    blue: 0.98
                ),
                in: Capsule()
            )
        }
    }

    private func compactDateControl(
        title: String,
        icon: String,
        components:
            DatePickerComponents
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            DatePicker(
                "",
                selection: $draft.startsAt,
                in: Date()...,
                displayedComponents:
                    components
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private func eventRoutePreview(
        _ route: TrainingRoute
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if route.coordinates.count >= 2 {
                Map(
                    initialPosition:
                        .region(
                            routeRegion(
                                route
                            )
                        )
                ) {
                    MapPolyline(
                        coordinates:
                            route.coordinates
                                .map(
                                    \.coordinate
                                )
                    )
                    .stroke(
                        Color(
                            red: 0.20,
                            green: 0.29,
                            blue: 0.52
                        ),
                        lineWidth: 5
                    )

                    if let first =
                        route.coordinates.first {
                        Marker(
                            route.startName ??
                                ATHLTHLocalization.choose(
                                    english: "Start",
                                    norwegian: "Start"
                                ),
                            coordinate:
                                first.coordinate
                        )
                        .tint(
                            ATHLTHTheme.accent
                        )
                    }

                    if let last =
                        route.coordinates.last {
                        Marker(
                            route.endName ??
                                ATHLTHLocalization.choose(
                                    english: "Finish",
                                    norwegian: "Mål"
                                ),
                            coordinate:
                                last.coordinate
                        )
                        .tint(.red)
                    }
                }
                .allowsHitTesting(false)
                .frame(height: 138)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
            }

            HStack(spacing: 10) {
                Image(
                    systemName:
                        "point.topleft.down.to.point.bottomright.curvepath"
                )
                .foregroundStyle(
                    ATHLTHTheme.accent
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(route.title)
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                    HStack(spacing: 8) {
                        Text(
                            String(
                                format:
                                    "%.1f km",
                                route
                                    .distanceKilometers
                            )
                        )

                        if let elevation =
                            route
                                .elevationGainMeters {
                            Text(
                                "· \(Int(elevation.rounded())) m ↑"
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()
            }
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.028),
            in: RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
        )
    }

    private func routeRegion(
        _ route: TrainingRoute
    ) -> MKCoordinateRegion {
        let coordinates =
            route.coordinates.map(
                \.coordinate
            )

        guard let first =
                coordinates.first
        else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 63.43,
                        longitude: 10.39
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.04,
                        longitudeDelta: 0.04
                    )
            )
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates {
            minLat = min(
                minLat,
                coordinate.latitude
            )
            maxLat = max(
                maxLat,
                coordinate.latitude
            )
            minLon = min(
                minLon,
                coordinate.longitude
            )
            maxLon = max(
                maxLon,
                coordinate.longitude
            )
        }

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (minLat + maxLat) /
                        2,
                    longitude:
                        (minLon + maxLon) /
                        2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta:
                        max(
                            (maxLat - minLat) *
                            1.35,
                            0.008
                        ),
                    longitudeDelta:
                        max(
                            (maxLon - minLon) *
                            1.35,
                            0.008
                        )
                )
        )
    }

    private func applyMeetingPlace(
        _ place:
            CommunityEventMapPlace
    ) {
        draft.meetingName =
            place.displayName
        draft.latitude =
            place.latitude
        draft.longitude =
            place.longitude
    }

    private func clearMeetingPoint() {
        draft.meetingName = ""
        draft.latitude = nil
        draft.longitude = nil
    }

    private func createEvent() {
        guard canCreate else {
            return
        }

        Task {
            isCreating = true
            createError = nil

            draft.maxParticipants =
                limitParticipants
                    ? maxParticipants
                    : nil

            if let selectedRoute {
                draft.routeID =
                    selectedRoute.id
                draft.routeTitle =
                    selectedRoute.title
                draft.routeCoordinates =
                    selectedRoute.coordinates
                draft.routeDistanceKilometers =
                    selectedRoute
                        .distanceKilometers
                draft.routeElevationGainMeters =
                    selectedRoute
                        .elevationGainMeters
                draft.routeStartName =
                    selectedRoute.startName
                draft.routeEndName =
                    selectedRoute.endName
            } else {
                draft.routeID = nil
                draft.routeTitle = nil
                draft.routeCoordinates = nil
                draft.routeDistanceKilometers =
                    nil
                draft.routeElevationGainMeters =
                    nil
                draft.routeStartName = nil
                draft.routeEndName = nil
            }

            let requestedEventID = UUID()
            var uploadedCoverURL: String?

            if let selectedCoverImageData {
                guard let imageURL =
                        await community
                            .uploadEventCover(
                                eventID:
                                    requestedEventID,
                                jpegData:
                                    selectedCoverImageData
                            )
                else {
                    createError =
                        community.errorMessage ??
                        ATHLTHLocalization.choose(
                            english:
                                "The event image could not be uploaded.",
                            norwegian:
                                "Bildet til arrangementet kunne ikke lastes opp."
                        )
                    isCreating = false
                    return
                }

                uploadedCoverURL =
                    imageURL
            }

            draft.coverArtworkName =
                selectedCoverImageData == nil
                    ? selectedCoverArtworkName
                    : nil
            draft.coverImageURL =
                uploadedCoverURL

            let eventID =
                await community
                    .createAndReturnID(
                        draft,
                        eventID:
                            requestedEventID
                    )

            guard let eventID else {
                if uploadedCoverURL != nil {
                    await community
                        .removeEventCover(
                            eventID:
                                requestedEventID
                        )
                }

                createError =
                    community.errorMessage ??
                    ATHLTHLocalization.choose(
                        english:
                            "The event could not be created.",
                        norwegian:
                            "Arrangementet kunne ikke opprettes."
                    )
                isCreating = false
                return
            }

            if shareToCommunity {
                _ = await social
                    .shareCommunityEvent(
                        id: eventID,
                        title: draft.title,
                        activityType:
                            draft.activityType,
                        startsAt:
                            draft.startsAt,
                        meetingName:
                            draft.meetingName,
                        visibility:
                            draft.visibility,
                        coverArtworkName:
                            draft.coverArtworkName,
                        coverImageURL:
                            draft.coverImageURL
                    )
            }

            isCreating = false
            clearSavedDraft()
            dismiss()
        }
    }

    private func restoreSavedDraftIfNeeded() {
        guard !restoredSavedDraft
        else {
            return
        }

        defer {
            restoredSavedDraft = true
        }

        guard let saved =
                CommunityEventCreationDraftStore
                    .load(
                        userID:
                            session
                                .profile
                                .userID
                    )
        else {
            return
        }

        draft = saved.draft
        limitParticipants =
            saved.limitParticipants
        maxParticipants =
            saved.maxParticipants
        selectedRouteID =
            saved.selectedRouteID
        shareToCommunity =
            saved.shareToCommunity
        selectedCoverArtworkName =
            saved.selectedCoverArtworkName
        coverWasManuallySelected =
            saved.coverWasManuallySelected

        // A PhotosPicker selection cannot be reconstructed after the
        // process has released it. Keep the rest of the draft intact and
        // fall back to the saved standard cover until the user reselects a
        // custom photo.
        selectedCoverPhoto = nil
        selectedCoverImageData = nil
        createError = nil
    }

    private func saveDraftIfRestored() {
        guard restoredSavedDraft
        else {
            return
        }

        let snapshot =
            CommunityEventCreationDraftSnapshot(
                draft: draft,
                limitParticipants:
                    limitParticipants,
                maxParticipants:
                    maxParticipants,
                selectedRouteID:
                    selectedRouteID,
                shareToCommunity:
                    shareToCommunity,
                selectedCoverArtworkName:
                    selectedCoverArtworkName,
                coverWasManuallySelected:
                    coverWasManuallySelected
            )

        CommunityEventCreationDraftStore
            .save(
                snapshot,
                userID:
                    session
                        .profile
                        .userID
            )
    }

    private func clearSavedDraft() {
        CommunityEventCreationDraftStore
            .clear(
                userID:
                    session
                        .profile
                        .userID
            )
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
