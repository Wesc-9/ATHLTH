import Foundation
import Supabase

struct ATHLTHTournamentSingleEventResult: Decodable, Identifiable {
    let userID: UUID
    let progress: String
    let score: Double?
    let rank: Int?
    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case progress, score, rank
        case userID = "user_id"
    }

    var statusLabel: String {
        switch progress {
        case "finished": return "Ferdig"
        case "awaiting_review": return "Gjennomført · avventer godkjenning"
        case "rejected": return "Må levere nytt resultat"
        case "not_ready": return "Ikke klar"
        default: return "Venter på start"
        }
    }
}

struct ATHLTHTournamentEligibleWorkout: Decodable, Identifiable {
    let id: UUID
    let sourceWorkoutID: UUID?
    let startedAt: Date?
    let endedAt: Date?
    let distanceMeters: Double?
    let durationSeconds: Double?
    let volumeKilograms: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceWorkoutID = "source_workout_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
        case volumeKilograms = "volume_kilograms"
    }
}

private struct ATHLTHTournamentSingleEventIDParams: Encodable {
    let p_tournament: UUID
}
private struct ATHLTHTournamentSingleEventSubmitParams: Encodable {
    let p_tournament: UUID
    let p_score: Double
    let p_laps: Int?
    let p_evidence: String
    let p_source_workout: UUID?
    private enum CodingKeys: String, CodingKey {
        case p_tournament,p_score,p_laps,p_evidence,p_source_workout
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(p_tournament, forKey: .p_tournament)
        try values.encode(p_score, forKey: .p_score)
        try values.encode(p_laps, forKey: .p_laps)
        try values.encode(p_evidence, forKey: .p_evidence)
        try values.encode(p_source_workout, forKey: .p_source_workout)
    }
}
private struct ATHLTHTournamentSingleEventReviewParams: Encodable {
    let p_tournament: UUID
    let p_athlete: UUID
    let p_approve: Bool
}

struct ATHLTHTournamentSingleEventCloud {
    private let client = SupabaseEnvironment.client

    func statuses(tournamentID: UUID) async throws
    -> [ATHLTHTournamentSingleEventResult] {
        try await client.rpc("athlth_tournament_single_event_status",
          params: ATHLTHTournamentSingleEventIDParams(
              p_tournament: tournamentID
          )).execute().value
    }

    func eligibleWorkouts(userID: UUID, after: Date)
    async throws -> [ATHLTHTournamentEligibleWorkout] {
        try await client.from("social_challenge_attempts")
            .select("id,source_workout_id,started_at,ended_at,distance_meters,duration_seconds,volume_kilograms")
            .eq("user_id", value: userID)
            .eq("verification", value: "athlth")
            .eq("is_eligible", value: true)
            .gte("started_at", value: ISO8601DateFormatter().string(from: after))
            .not("source_workout_id", operator: .is, value: "null")
            .order("started_at", ascending: false)
            .limit(30).execute().value
    }

    func submit(tournamentID: UUID, score: Double, laps: Int?,
                evidence: String, workoutID: UUID?) async throws {
        try await client.rpc(
          "athlth_tournament_single_event_submit",
          params: ATHLTHTournamentSingleEventSubmitParams(
            p_tournament: tournamentID,
            p_score: score, p_laps: laps,
            p_evidence: evidence,
            p_source_workout: workoutID
          )
        ).execute()
    }

    func review(tournamentID: UUID, athlete: UUID,
                approve: Bool) async throws {
        try await client.rpc(
          "athlth_tournament_single_event_review",
          params: ATHLTHTournamentSingleEventReviewParams(
            p_tournament: tournamentID, p_athlete: athlete,
            p_approve: approve
          )
        ).execute()
    }
}
