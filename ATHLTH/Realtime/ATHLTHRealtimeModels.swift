import CoreLocation
import Foundation

enum LiveWorkoutAudience: String, Codable, CaseIterable, Identifiable, Sendable {
    case mutuals
    case followers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mutuals:
            return "Mutual follows"
        case .followers:
            return "Followers"
        }
    }

    var detail: String {
        switch self {
        case .mutuals:
            return "Only people you follow who also follow you."
        case .followers:
            return "People who follow your ATHLTH profile."
        }
    }
}

struct OnlinePresenceRecord: Codable, Hashable, Sendable {
    let userID: UUID
    let lastSeenAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lastSeenAt = "last_seen_at"
        case updatedAt = "updated_at"
    }

    func isOnline(
        now: Date = Date(),
        timeout: TimeInterval = 120
    ) -> Bool {
        now.timeIntervalSince(lastSeenAt) <= timeout
    }
}

struct LiveWorkoutSessionRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let activity: String
    let title: String?
    let mode: String
    let ghostReferenceID: UUID?
    let visibility: String
    let channelTopic: String
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let lastBroadcastAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case activity
        case title
        case mode
        case ghostReferenceID = "ghost_reference_id"
        case visibility
        case channelTopic = "channel_topic"
        case status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case lastBroadcastAt = "last_broadcast_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isLive: Bool {
        status == "active" || status == "paused"
    }

    var audience: LiveWorkoutAudience {
        LiveWorkoutAudience(rawValue: visibility) ?? .mutuals
    }

    var isGhostRace: Bool {
        mode == "ghost"
    }
}

struct LiveWorkoutLocationMessage: Codable, Hashable, Sendable {
    let sessionID: UUID
    let ownerID: UUID
    let latitude: Double
    let longitude: Double
    let capturedAt: Date
    let elapsedTime: TimeInterval
    let distanceMeters: Double
    let routeProgressPercent: Double?
    let state: String
    let mode: String
    let ghostReferenceID: UUID?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case ownerID = "owner_id"
        case latitude
        case longitude
        case capturedAt = "captured_at"
        case elapsedTime = "elapsed_time"
        case distanceMeters = "distance_meters"
        case routeProgressPercent = "route_progress_percent"
        case state
        case mode
        case ghostReferenceID = "ghost_reference_id"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

struct LiveWorkoutSessionInsert: Encodable, Sendable {
    let id: UUID
    let ownerID: UUID
    let activity: String
    let title: String?
    let mode: String
    let ghostReferenceID: UUID?
    let visibility: String
    let channelTopic: String
    let status: String
    let startedAt: Date
    let lastBroadcastAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case activity
        case title
        case mode
        case ghostReferenceID = "ghost_reference_id"
        case visibility
        case channelTopic = "channel_topic"
        case status
        case startedAt = "started_at"
        case lastBroadcastAt = "last_broadcast_at"
    }
}

struct OnlinePresenceWrite: Encodable, Sendable {
    let userID: UUID
    let lastSeenAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case lastSeenAt = "last_seen_at"
        case updatedAt = "updated_at"
    }
}
