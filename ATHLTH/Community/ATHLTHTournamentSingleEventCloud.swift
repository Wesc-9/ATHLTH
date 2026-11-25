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

struct ATHLTHTournamentScoredExercise: Decodable, Identifiable {
    let id: UUID
    let title: String
    let metric: String
    let targetValue: Double?

    enum CodingKeys: String, CodingKey {
        case id = "candidate_id"
        case title, metric
        case targetValue = "target_value"
    }

    var unit: String {
        switch metric {
        case "distance", "time": "sek"
        case "duration": "m"
        default: "repetisjoner"
        }
    }

    var instruction: String {
        switch metric {
        case "distance": "Lavest tid vinner · mål: " + (targetValue.map { $0.formatted() + " m" } ?? "avtalt distanse")
        case "duration": "Lengst distanse vinner · tid: " + (targetValue.map { $0.formatted() + " sek" } ?? "avtalt tid")
        case "time": "Lengst tid vinner"
        default: "Flest repetisjoner vinner"
        }
    }

    func accepts(_ value: Double) -> Bool {
        value.isFinite && (0...100_000_000).contains(value) &&
            (metric != "distance" || value > 0) &&
            (metric != "repetitions" || value.rounded(.towardZero) == value)
    }
}

struct ATHLTHTournamentExerciseScoreDetail: Decodable, Identifiable {
    let userID: UUID
    let exerciseScores: [String: Double]
    let evidenceNote: String?
    var id: UUID { userID }
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case exerciseScores = "exercise_scores"
        case evidenceNote = "evidence_note"
    }
}

private struct ATHLTHTournamentExerciseScoresParams: Encodable {
    let p_tournament: UUID
    let p_scores: [String: Double]
    let p_evidence: String
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

    func exercises(tournamentID: UUID) async throws -> [ATHLTHTournamentScoredExercise] {
        try await client.rpc("athlth_tournament_single_event_exercises",
            params: ATHLTHTournamentSingleEventIDParams(p_tournament: tournamentID))
            .execute().value
    }

    func exerciseDetails(tournamentID: UUID) async throws -> [ATHLTHTournamentExerciseScoreDetail] {
        try await client.rpc("athlth_tournament_single_event_exercise_details",
            params: ATHLTHTournamentSingleEventIDParams(p_tournament: tournamentID))
            .execute().value
    }

    func submitExercises(tournamentID: UUID, scores: [String: Double], evidence: String) async throws {
        try await client.rpc("athlth_tournament_single_event_submit_exercises",
            params: ATHLTHTournamentExerciseScoresParams(p_tournament: tournamentID,
                p_scores: scores, p_evidence: evidence)).execute()
    }

    func eligibleWorkouts(userID: UUID, after: Date)
    async throws -> [ATHLTHTournamentEligibleWorkout] {
        try await client.from("social_challenge_attempts")
            .select("id,source_workout_id,started_at,ended_at,distance_meters,duration_seconds,volume_kilograms")
            .eq("user_id", value: userID)
            .eq("verification", value: "athlth")
            .eq("is_eligible", value: true)
            .gte("started_at", value: ISO8601DateFormatter().string(from: after))
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

struct ATHLTHSharedEventExerciseRow: Decodable, Identifiable {
    let candidateID: UUID
    let title: String
    let metric: String
    let targetValue: Double?
    let activity: String
    let sortOrder: Int
    let opensAt: Date?
    let deadlineAt: Date?
    let userID: UUID
    let progress: String
    let score: Double?
    let evidenceNote: String?
    var id: String { candidateID.uuidString + userID.uuidString }
    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case title, metric, activity, progress, score
        case targetValue = "target_value"
        case sortOrder = "sort_order"
        case opensAt = "opens_at"
        case deadlineAt = "deadline_at"
        case userID = "user_id"
        case evidenceNote = "evidence_note"
    }
    var unit: String {
        switch metric {
        case "distance", "time": "sek"
        case "duration": "m"
        default: "repetisjoner"
        }
    }
    var instruction: String {
        switch metric {
        case "distance": "Lavest tid vinner · " + (targetValue.map { $0.formatted() + " m" } ?? "avtalt distanse")
        case "duration": "Lengst distanse vinner · " + (targetValue.map { $0.formatted() + " sek" } ?? "avtalt tid")
        case "time": "Lengst tid vinner"
        default: "Flest repetisjoner vinner"
        }
    }
    var stateLabel: String {
        switch progress {
        case "submitted": "Til godkjenning"
        case "approved": "Godkjent"
        case "rejected": "Må leveres på nytt"
        case "missed": "0 poeng · frist utløpt"
        default: "Ikke gjennomført"
        }
    }
    var canSubmit: Bool {
        (progress == "pending" || progress == "rejected") &&
        opensAt.map { $0 <= Date() } == true && deadlineAt.map { $0 > Date() } == true
    }
    func accepts(_ score: Double) -> Bool {
        score.isFinite && (0...100_000_000).contains(score) &&
            (metric != "distance" || score > 0) &&
            (metric != "repetitions" || score.rounded(.towardZero) == score)
    }
}

private struct ATHLTHSharedEventSubmitParams: Encodable {
    let p_tournament: UUID
    let p_candidate: UUID
    let p_score: Double?
    let p_evidence: String
    let p_source_workout: UUID?
    enum CodingKeys: String, CodingKey {
        case p_tournament,p_candidate,p_score,p_evidence,p_source_workout
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_tournament, forKey: .p_tournament)
        try c.encode(p_candidate, forKey: .p_candidate)
        try c.encode(p_score, forKey: .p_score)
        try c.encode(p_evidence, forKey: .p_evidence)
        try c.encode(p_source_workout, forKey: .p_source_workout)
    }
}
private struct ATHLTHSharedEventReviewParams: Encodable {
    let p_tournament: UUID
    let p_candidate: UUID
    let p_athlete: UUID
    let p_approve: Bool
}
extension ATHLTHTournamentSingleEventCloud {
    func sharedState(tournamentID: UUID) async throws -> [ATHLTHSharedEventExerciseRow] {
        try await client.rpc("athlth_shared_event_state",
            params: ATHLTHTournamentSingleEventIDParams(p_tournament: tournamentID)).execute().value
    }
    func submitShared(tournamentID: UUID, candidateID: UUID, score: Double?,
                      evidence: String, sourceWorkoutID: UUID?) async throws {
        try await client.rpc("athlth_shared_event_submit", params: ATHLTHSharedEventSubmitParams(
            p_tournament: tournamentID, p_candidate: candidateID, p_score: score,
            p_evidence: evidence, p_source_workout: sourceWorkoutID)).execute()
    }
    func reviewShared(tournamentID: UUID, candidateID: UUID, athleteID: UUID, approve: Bool) async throws {
        try await client.rpc("athlth_shared_event_review", params: ATHLTHSharedEventReviewParams(
            p_tournament: tournamentID, p_candidate: candidateID, p_athlete: athleteID,
            p_approve: approve)).execute()
    }
}
