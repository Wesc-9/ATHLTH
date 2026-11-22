import Foundation
import Supabase

struct ATHLTHCompetitionLivePosition: Decodable, Identifiable {
    let userID: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let updatedAt: Date
    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case userID = "user_id"
        case accuracyMeters = "accuracy_meters"
        case updatedAt = "updated_at"
    }
}

private struct ATHLTHCompetitionPositionParams: Encodable {
    let p_tournament: UUID
    let p_latitude: Double
    let p_longitude: Double
    let p_accuracy: Double
}
private struct ATHLTHCompetitionPositionStopParams: Encodable {
    let p_tournament: UUID
}

/// Uses only GPS positions already recorded by ATHLTH's original workout
/// engine. No extra location manager, persisted trace or default sharing.
struct ATHLTHCompetitionLivePositionCloud {
    private let client = SupabaseEnvironment.client

    func share(tournamentID: UUID, point: PhoneRoutePoint) async throws {
        try await client.rpc(
            "athlth_competition_share_live_position",
            params: ATHLTHCompetitionPositionParams(
                p_tournament: tournamentID,
                p_latitude: point.latitude,
                p_longitude: point.longitude,
                p_accuracy: point.accuracy
            )
        ).execute()
    }

    func visible(tournamentID: UUID) async throws
        -> [ATHLTHCompetitionLivePosition] {
        try await client.from("athlth_competition_live_positions")
            .select("user_id,latitude,longitude,accuracy_meters,updated_at")
            .eq("tournament_id", value: tournamentID)
            .order("updated_at", ascending: false)
            .limit(128).execute().value
    }

    func stop(tournamentID: UUID) async throws {
        try await client.rpc(
            "athlth_competition_stop_live_position",
            params: ATHLTHCompetitionPositionStopParams(
                p_tournament: tournamentID
            )
        ).execute()
    }
}
