import Foundation

enum TrainTogetherJoinPolicy:
    String,
    Codable,
    Hashable,
    CaseIterable,
    Identifiable
{
    case request
    case open

    var id: String { rawValue }

    var title: String {
        switch self {
        case .request:
            return ATHLTHLocalization.choose(
                english: "Request to join",
                norwegian: "Be om å bli med"
            )
        case .open:
            return ATHLTHLocalization.choose(
                english: "Open join",
                norwegian: "Åpen påmelding"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .request:
            return ATHLTHLocalization.choose(
                english:
                    "You approve each person before they enter the workout.",
                norwegian:
                    "Du godkjenner hver person før de blir med i økten."
            )
        case .open:
            return ATHLTHLocalization.choose(
                english:
                    "Anyone can join instantly until the workout is full.",
                norwegian:
                    "Alle kan bli med direkte til økten er full."
            )
        }
    }
}

enum TrainTogetherPostStatus:
    String,
    Codable,
    Hashable
{
    case open
    case full
    case cancelled
    case completed
}

enum TrainTogetherRequestState:
    String,
    Codable,
    Hashable
{
    case pending
    case accepted
    case declined
    case withdrawn
}

struct TrainTogetherPost:
    Identifiable,
    Codable,
    Hashable
{
    let id: UUID
    let creatorID: UUID
    let creatorDisplayName: String
    let creatorUsername: String?
    let creatorAvatarURL: String?
    var title: String
    var workoutKind: String
    var scheduledStart: Date
    var durationMinutes: Int?
    var distanceKilometers: Double?
    var level: String
    var broadArea: String
    var note: String?
    var maxGuests: Int
    var acceptedGuests: Int
    var status: TrainTogetherPostStatus
    var participationMode:
        SocialWorkoutParticipationMode?
    var joinPolicy:
        TrainTogetherJoinPolicy?
    var workoutPayload:
        SocialWorkoutInvitePayload?
    var sourcePlannedSessionID: UUID?
    var socialWorkoutSessionID: UUID?
    let createdAt: Date
    var updatedAt: Date?

    enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case creatorID = "creator_id"
        case creatorDisplayName =
            "creator_display_name"
        case creatorUsername =
            "creator_username"
        case creatorAvatarURL =
            "creator_avatar_url"
        case title
        case workoutKind = "workout_kind"
        case scheduledStart =
            "scheduled_start"
        case durationMinutes =
            "duration_minutes"
        case distanceKilometers =
            "distance_kilometers"
        case level
        case broadArea = "broad_area"
        case note
        case maxGuests = "max_guests"
        case acceptedGuests =
            "accepted_guests"
        case status
        case participationMode =
            "participation_mode"
        case joinPolicy =
            "join_policy"
        case workoutPayload =
            "workout_payload"
        case sourcePlannedSessionID =
            "source_planned_session_id"
        case socialWorkoutSessionID =
            "social_workout_session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var resolvedParticipationMode:
        SocialWorkoutParticipationMode {
        participationMode ?? .physical
    }

    var resolvedJoinPolicy:
        TrainTogetherJoinPolicy {
        joinPolicy ?? .request
    }

    var spotsLeft: Int {
        max(
            maxGuests - acceptedGuests,
            0
        )
    }

    var creatorCard:
        SocialProfileCard {
        SocialProfileCard(
            userID: creatorID,
            username:
                creatorUsername,
            displayName:
                creatorDisplayName,
            bio: nil,
            avatarURL:
                creatorAvatarURL,
            profileVisibility:
                "public",
            createdAt: nil,
            updatedAt: nil
        )
    }
}

struct TrainTogetherRequest:
    Identifiable,
    Codable,
    Hashable
{
    let id: UUID
    let postID: UUID
    let requesterID: UUID
    let requesterDisplayName: String
    let requesterUsername: String?
    let requesterAvatarURL: String?
    let message: String?
    var state: TrainTogetherRequestState
    let createdAt: Date
    var respondedAt: Date?
    var updatedAt: Date?

    enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case postID = "post_id"
        case requesterID = "requester_id"
        case requesterDisplayName =
            "requester_display_name"
        case requesterUsername =
            "requester_username"
        case requesterAvatarURL =
            "requester_avatar_url"
        case message
        case state
        case createdAt = "created_at"
        case respondedAt =
            "responded_at"
        case updatedAt = "updated_at"
    }

    var requesterCard:
        SocialProfileCard {
        SocialProfileCard(
            userID: requesterID,
            username:
                requesterUsername,
            displayName:
                requesterDisplayName,
            bio: nil,
            avatarURL:
                requesterAvatarURL,
            profileVisibility:
                "public",
            createdAt: nil,
            updatedAt: nil
        )
    }
}

struct TrainTogetherMeetup:
    Codable,
    Hashable
{
    let postID: UUID
    let creatorID: UUID
    var meetingName: String?
    var meetingAddress: String?
    var meetingLatitude: Double?
    var meetingLongitude: Double?
    var meetingDetails: String?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys:
        String,
        CodingKey
    {
        case postID = "post_id"
        case creatorID = "creator_id"
        case meetingName =
            "meeting_name"
        case meetingAddress =
            "meeting_address"
        case meetingLatitude =
            "meeting_latitude"
        case meetingLongitude =
            "meeting_longitude"
        case meetingDetails =
            "meeting_details"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TrainTogetherPostWrite:
    Encodable
{
    let id: UUID
    let creatorID: UUID
    let creatorDisplayName: String
    let creatorUsername: String?
    let creatorAvatarURL: String?
    let title: String
    let workoutKind: String
    let scheduledStart: Date
    let durationMinutes: Int?
    let distanceKilometers: Double?
    let level: String
    let broadArea: String
    let note: String?
    let maxGuests: Int
    let acceptedGuests: Int
    let status: String
    let participationMode: String
    let joinPolicy: String
    let workoutPayload:
        SocialWorkoutInvitePayload?
    let sourcePlannedSessionID: UUID?

    enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case creatorID = "creator_id"
        case creatorDisplayName =
            "creator_display_name"
        case creatorUsername =
            "creator_username"
        case creatorAvatarURL =
            "creator_avatar_url"
        case title
        case workoutKind = "workout_kind"
        case scheduledStart =
            "scheduled_start"
        case durationMinutes =
            "duration_minutes"
        case distanceKilometers =
            "distance_kilometers"
        case level
        case broadArea = "broad_area"
        case note
        case maxGuests = "max_guests"
        case acceptedGuests =
            "accepted_guests"
        case status
        case participationMode =
            "participation_mode"
        case joinPolicy =
            "join_policy"
        case workoutPayload =
            "workout_payload"
        case sourcePlannedSessionID =
            "source_planned_session_id"
    }
}

struct TrainTogetherMeetupWrite:
    Encodable
{
    let postID: UUID
    let creatorID: UUID
    let meetingName: String?
    let meetingAddress: String?
    let meetingLatitude: Double?
    let meetingLongitude: Double?
    let meetingDetails: String?

    enum CodingKeys:
        String,
        CodingKey
    {
        case postID = "post_id"
        case creatorID = "creator_id"
        case meetingName =
            "meeting_name"
        case meetingAddress =
            "meeting_address"
        case meetingLatitude =
            "meeting_latitude"
        case meetingLongitude =
            "meeting_longitude"
        case meetingDetails =
            "meeting_details"
    }
}
