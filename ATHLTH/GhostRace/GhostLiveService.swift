import Foundation
import Supabase

struct GhostLiveSessionRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let sourceReferenceID: UUID?
    let status: String
    let shareLocation: Bool
    let startedAt: Date
    let endedAt: Date?
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case sourceReferenceID = "source_reference_id"
        case status
        case shareLocation = "share_location"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}

struct GhostLivePositionRecord: Codable, Hashable, Sendable {
    let sessionID: UUID
    let userID: UUID
    let latitude: Double
    let longitude: Double
    let elapsedSeconds: TimeInterval
    let distanceMeters: Double
    let heartRateBPM: Double?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userID = "user_id"
        case latitude
        case longitude
        case elapsedSeconds = "elapsed_seconds"
        case distanceMeters = "distance_meters"
        case heartRateBPM = "heart_rate_bpm"
        case updatedAt = "updated_at"
    }
}

struct GhostLiveRunner: Identifiable, Hashable, Sendable {
    var id: UUID { session.id }

    let session: GhostLiveSessionRecord
    let position: GhostLivePositionRecord
}

private struct GhostLiveSessionInsert: Encodable, Sendable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let sourceReferenceID: UUID?
    let status: String
    let shareLocation: Bool
    let startedAt: Date
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case sourceReferenceID = "source_reference_id"
        case status
        case shareLocation = "share_location"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}

private struct GhostLiveSessionUpdate: Encodable, Sendable {
    let status: String
    let endedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
    }
}

private struct GhostLivePositionWrite: Encodable, Sendable {
    let sessionID: UUID
    let userID: UUID
    let latitude: Double
    let longitude: Double
    let elapsedSeconds: TimeInterval
    let distanceMeters: Double
    let heartRateBPM: Double?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userID = "user_id"
        case latitude
        case longitude
        case elapsedSeconds = "elapsed_seconds"
        case distanceMeters = "distance_meters"
        case heartRateBPM = "heart_rate_bpm"
        case updatedAt = "updated_at"
    }
}

enum GhostLiveServiceError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in before sharing a live Ghost Race."
        }
    }
}

final class SupabaseGhostLiveService: Sendable {
    private let client: SupabaseClient

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func beginSession(
        title: String,
        sourceReferenceID: UUID?
    ) async throws -> GhostLiveSessionRecord {
        guard let ownerID = currentUserID else {
            throw GhostLiveServiceError.notAuthenticated
        }

        let now = Date()
        let record = GhostLiveSessionRecord(
            id: UUID(),
            ownerID: ownerID,
            title: String(title.prefix(160)),
            sourceReferenceID: sourceReferenceID,
            status: "running",
            shareLocation: true,
            startedAt: now,
            endedAt: nil,
            updatedAt: now,
            expiresAt: now.addingTimeInterval(6 * 60 * 60)
        )

        try await client
            .from("ghost_live_sessions")
            .insert(
                GhostLiveSessionInsert(
                    id: record.id,
                    ownerID: ownerID,
                    title: record.title,
                    sourceReferenceID: sourceReferenceID,
                    status: record.status,
                    shareLocation: true,
                    startedAt: now,
                    updatedAt: now,
                    expiresAt: record.expiresAt
                )
            )
            .execute()

        return record
    }

    func publish(
        sessionID: UUID,
        latitude: Double,
        longitude: Double,
        elapsedSeconds: TimeInterval,
        distanceMeters: Double,
        heartRateBPM: Double?
    ) async throws {
        guard let userID = currentUserID else {
            throw GhostLiveServiceError.notAuthenticated
        }

        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            return
        }

        try await client
            .from("ghost_live_positions")
            .upsert(
                GhostLivePositionWrite(
                    sessionID: sessionID,
                    userID: userID,
                    latitude: latitude,
                    longitude: longitude,
                    elapsedSeconds: max(elapsedSeconds, 0),
                    distanceMeters: max(distanceMeters, 0),
                    heartRateBPM:
                        heartRateBPM.flatMap {
                            $0.isFinite && $0 > 0
                                ? $0
                                : nil
                        },
                    updatedAt: Date()
                )
            )
            .execute()
    }

    func finishSession(
        id: UUID,
        status: String
    ) async throws {
        guard currentUserID != nil else {
            throw GhostLiveServiceError.notAuthenticated
        }

        let resolvedStatus: String
        switch status {
        case "completed", "cancelled", "failed":
            resolvedStatus = status
        default:
            resolvedStatus = "cancelled"
        }

        let now = Date()

        try await client
            .from("ghost_live_sessions")
            .update(
                GhostLiveSessionUpdate(
                    status: resolvedStatus,
                    endedAt: now,
                    updatedAt: now
                )
            )
            .eq("id", value: id)
            .execute()

        try? await client
            .from("ghost_live_positions")
            .delete()
            .eq("session_id", value: id)
            .execute()
    }

    func loadVisibleRunners() async throws -> [GhostLiveRunner] {
        async let sessionsTask: [GhostLiveSessionRecord] =
            client
                .from("ghost_live_sessions")
                .select()
                .eq("status", value: "running")
                .order("updated_at", ascending: false)
                .limit(100)
                .execute()
                .value

        async let positionsTask: [GhostLivePositionRecord] =
            client
                .from("ghost_live_positions")
                .select()
                .order("updated_at", ascending: false)
                .limit(200)
                .execute()
                .value

        let (sessions, positions) =
            try await (
                sessionsTask,
                positionsTask
            )

        let now = Date()
        let freshPositionCutoff =
            now.addingTimeInterval(-90)

        let positionBySession =
            Dictionary(
                uniqueKeysWithValues:
                    positions
                        .filter {
                            $0.updatedAt >=
                                freshPositionCutoff
                        }
                        .map {
                            ($0.sessionID, $0)
                        }
            )

        return sessions
            .filter {
                $0.shareLocation &&
                $0.status == "running" &&
                $0.expiresAt > now
            }
            .compactMap { session in
                guard let position =
                        positionBySession[
                            session.id
                        ]
                else {
                    return nil
                }

                return GhostLiveRunner(
                    session: session,
                    position: position
                )
            }
    }
}
