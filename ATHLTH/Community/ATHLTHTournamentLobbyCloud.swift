import Foundation
import Supabase

struct ATHLTHTournamentExerciseCandidateRemote: Decodable, Identifiable {
    let id: UUID
    let tournamentID: UUID
    let exerciseID: UUID
    let suggestedBy: UUID
    let createdAt: Date
    let selectedPosition: Int?
    enum CodingKeys: String, CodingKey {
        case id
        case tournamentID = "tournament_id"
        case exerciseID = "exercise_id"
        case suggestedBy = "suggested_by"
        case createdAt = "created_at"
        case selectedPosition = "selected_position"
    }
}

struct ATHLTHTournamentExerciseVoteRemote: Decodable {
    let candidateID: UUID
    let voterID: UUID
    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case voterID = "voter_id"
    }
}

struct ATHLTHTournamentLobbyMessageRemote: Decodable, Identifiable {
    let id: UUID
    let authorID: UUID
    let content: String
    let kind: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id,content,kind
        case authorID = "author_id"
        case createdAt = "created_at"
    }
}

struct ATHLTHTournamentPlayerChangeRemote: Decodable, Identifiable {
    let id: UUID
    let tournamentID: UUID
    let oldPlayerID: UUID
    let newPlayerID: UUID
    let initiatedBy: UUID
    let status: String
    let newPlayerAccepted: Bool
    let requiresApproval: Bool
    let createdAt: Date
    let appliedAt: Date?
    enum CodingKeys: String, CodingKey {
        case id,status
        case tournamentID = "tournament_id"
        case oldPlayerID = "old_player_id"
        case newPlayerID = "new_player_id"
        case initiatedBy = "initiated_by"
        case newPlayerAccepted = "new_player_accepted"
        case requiresApproval = "requires_approval"
        case createdAt = "created_at"
        case appliedAt = "applied_at"
    }
}

struct ATHLTHTournamentPlayerChangeVoteRemote: Decodable {
    let requestID: UUID
    let voterID: UUID
    let approved: Bool
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case voterID = "voter_id"
        case approved
    }
}

struct ATHLTHTournamentLibraryExerciseRemote: Decodable, Identifiable {
    let id: UUID
    let name: String
}

struct ATHLTHTournamentMatchExerciseRemote: Decodable, Identifiable {
    let id: UUID
    let matchID: UUID
    let candidateID: UUID
    let position: Int
    let deadlineAt: Date
    let state: String
    let winnerID: UUID?
    enum CodingKeys: String, CodingKey {
        case id,position,state
        case matchID = "match_id"
        case candidateID = "candidate_id"
        case deadlineAt = "deadline_at"
        case winnerID = "winner_id"
    }
}

struct ATHLTHTournamentExerciseCompletionRemote: Decodable {
    let matchExerciseID: UUID
    let userID: UUID
    let submittedAt: Date
    let reviewStatus: String
    enum CodingKeys: String, CodingKey {
        case reviewStatus = "review_status"
        case matchExerciseID = "match_exercise_id"
        case userID = "user_id"
        case submittedAt = "submitted_at"
    }
}

private struct ATHLTHTournamentSuggestParams: Encodable {
    let p_tournament: UUID
    let p_exercise: UUID
}
private struct ATHLTHTournamentVoteParams: Encodable {
    let p_candidate: UUID
    let p_voted: Bool
}
private struct ATHLTHTournamentReadyParams: Encodable {
    let p_tournament: UUID
    let p_ready: Bool
}
private struct ATHLTHTournamentMessageParams: Encodable {
    let p_tournament: UUID
    let p_content: String
    let p_announcement: Bool
}
private struct ATHLTHTournamentForfeitParams: Encodable {
    let p_tournament: UUID
    let p_player: UUID
}
private struct ATHLTHTournamentChangeParams: Encodable {
    let p_tournament: UUID
    let p_old: UUID
    let p_new: UUID
}
private struct ATHLTHTournamentRespondChangeParams: Encodable {
    let p_request: UUID
    let p_accept: Bool
}
private struct ATHLTHTournamentVoteChangeParams: Encodable {
    let p_request: UUID
    let p_approve: Bool
}
private struct ATHLTHTournamentExerciseAttemptParams: Encodable {
    let p_match_exercise: UUID
    let p_evidence_note: String
    let p_source_workout: UUID?
    enum CodingKeys: String, CodingKey {
        case p_match_exercise,p_evidence_note,p_source_workout
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(p_match_exercise,forKey: .p_match_exercise)
        try values.encode(p_evidence_note,forKey: .p_evidence_note)
        try values.encode(p_source_workout,forKey: .p_source_workout)
    }
}

private struct ATHLTHTournamentReviewExerciseParams: Encodable {
    let p_match_exercise: UUID
    let p_athlete: UUID
    let p_approve: Bool
}

struct ATHLTHTournamentLobbyCloudService {
    private let client = SupabaseEnvironment.client

    func candidates(tournamentID: UUID) async throws
      -> [ATHLTHTournamentExerciseCandidateRemote] {
        try await client.from("athlth_tournament_exercise_candidates")
          .select("id,tournament_id,exercise_id,suggested_by,created_at,selected_position")
          .eq("tournament_id", value: tournamentID)
          .order("created_at")
          .limit(500).execute().value
    }

    func exerciseVotes(tournamentID: UUID) async throws
      -> [ATHLTHTournamentExerciseVoteRemote] {
        try await client.from("athlth_tournament_exercise_votes")
          .select("candidate_id,voter_id")
          .eq("tournament_id", value: tournamentID)
          .limit(2500).execute().value
    }

    func exerciseNames(ids: Set<UUID>) async throws
      -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let list: [ATHLTHTournamentLibraryExerciseRemote] = try await client
          .from("exercise_catalog").select("id,name")
          .in("id",values: Array(ids)).limit(500).execute().value
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id,$0.name) })
    }

    func searchExercises(_ query: String) async throws
      -> [ATHLTHTournamentLibraryExerciseRemote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        return try await client.from("exercise_catalog")
          .select("id,name")
          .eq("is_published",value: true)
          .ilike("name",pattern: "%\(q)%")
          .order("name")
          .limit(30).execute().value
    }

    func suggest(tournamentID: UUID, exerciseID: UUID) async throws {
        try await client.rpc(
            "athlth_tournament_suggest_exercise",
            params: ATHLTHTournamentSuggestParams(
                p_tournament: tournamentID,p_exercise: exerciseID)
        ).execute()
    }

    func vote(candidateID: UUID, selected: Bool) async throws {
        try await client.rpc("athlth_tournament_vote_exercise",
            params: ATHLTHTournamentVoteParams(
                p_candidate: candidateID,p_voted: selected)
        ).execute()
    }

    func finalize(tournamentID: UUID) async throws {
        try await client.rpc("athlth_tournament_finalize_exercises",
          params: ATHLTHTournamentIDParamsPublic(p_tournament: tournamentID)
        ).execute()
    }

    func ready(tournamentID: UUID, value: Bool) async throws {
        try await client.rpc("athlth_tournament_set_ready",
          params: ATHLTHTournamentReadyParams(
            p_tournament: tournamentID,p_ready: value)
        ).execute()
    }

    func messages(tournamentID: UUID) async throws
      -> [ATHLTHTournamentLobbyMessageRemote] {
        let rows: [ATHLTHTournamentLobbyMessageRemote] = try await client
          .from("athlth_tournament_lobby_messages")
          .select("id,author_id,content,kind,created_at")
          .eq("tournament_id",value: tournamentID)
          .order("created_at",ascending: false)
          .limit(80).execute().value
        return Array(rows.reversed())
    }

    func sendMessage(tournamentID: UUID,text: String,
                     announcement: Bool = false) async throws {
        try await client.rpc(
          "athlth_tournament_send_lobby_message",
          params: ATHLTHTournamentMessageParams(
            p_tournament: tournamentID,
            p_content: text,p_announcement: announcement)
        ).execute()
    }

    func playerChanges(tournamentID: UUID) async throws
      -> [ATHLTHTournamentPlayerChangeRemote] {
        try await client.from("athlth_tournament_player_change")
          .select("id,tournament_id,old_player_id,new_player_id,initiated_by,status,new_player_accepted,requires_approval,created_at,applied_at")
          .eq("tournament_id",value: tournamentID)
          .order("created_at",ascending: false).limit(60).execute().value
    }

    func changeVotes(requestIDs: [UUID]) async throws
      -> [ATHLTHTournamentPlayerChangeVoteRemote] {
        guard !requestIDs.isEmpty else { return [] }
        return try await client.from("athlth_tournament_player_change_votes")
          .select("request_id,voter_id,approved")
          .in("request_id",values: requestIDs)
          .limit(2000).execute().value
    }

    func forfeit(tournamentID: UUID,playerID: UUID) async throws {
        try await client.rpc("athlth_tournament_forfeit_player",
          params: ATHLTHTournamentForfeitParams(
            p_tournament: tournamentID,p_player: playerID)
        ).execute()
    }

    func requestReplacement(tournamentID: UUID,
                            oldID: UUID,newID: UUID) async throws {
        try await client.rpc("athlth_tournament_request_replacement",
          params: ATHLTHTournamentChangeParams(
            p_tournament: tournamentID,p_old: oldID,p_new: newID)
        ).execute()
    }

    func respondReplacement(requestID: UUID,accept: Bool) async throws {
        try await client.rpc("athlth_tournament_respond_replacement",
          params: ATHLTHTournamentRespondChangeParams(
            p_request: requestID,p_accept: accept)
        ).execute()
    }

    func voteReplacement(requestID: UUID,approve: Bool) async throws {
        try await client.rpc("athlth_tournament_vote_replacement",
          params: ATHLTHTournamentVoteChangeParams(
            p_request: requestID,p_approve: approve)
        ).execute()
    }

    func matchExercises(matchIDs: [UUID]) async throws
      -> [ATHLTHTournamentMatchExerciseRemote] {
        guard !matchIDs.isEmpty else { return [] }
        var all: [ATHLTHTournamentMatchExerciseRemote] = []
        for start in stride(from: 0,to: matchIDs.count,by: 150) {
            let end = min(start + 150,matchIDs.count)
            let batch: [ATHLTHTournamentMatchExerciseRemote] = try await client
              .from("athlth_tournament_match_exercises")
              .select("id,match_id,candidate_id,position,deadline_at,state,winner_id")
              .in("match_id",values: Array(matchIDs[start..<end]))
              .order("position")
              .limit(2500).execute().value
            all.append(contentsOf: batch)
        }
        return all
    }

    func completions(slotIDs: [UUID]) async throws
      -> [ATHLTHTournamentExerciseCompletionRemote] {
        guard !slotIDs.isEmpty else { return [] }
        var all: [ATHLTHTournamentExerciseCompletionRemote] = []
        for start in stride(from: 0,to: slotIDs.count,by: 150) {
            let end = min(start + 150,slotIDs.count)
            let batch: [ATHLTHTournamentExerciseCompletionRemote] = try await client
              .from("athlth_tournament_exercise_completions")
              .select("match_exercise_id,user_id,submitted_at,review_status")
              .in("match_exercise_id",values: Array(slotIDs[start..<end]))
              .limit(1000).execute().value
            all.append(contentsOf: batch)
        }
        return all
    }

    func reviewExercise(slotID: UUID,
                        athleteID: UUID,
                        approve: Bool) async throws {
        try await client.rpc("athlth_tournament_review_exercise",
            params: ATHLTHTournamentReviewExerciseParams(
                p_match_exercise: slotID,
                p_athlete: athleteID,
                p_approve: approve
            )
        ).execute()
    }

    func completeExercise(slotID: UUID,evidence: String) async throws {
        try await client.rpc("athlth_tournament_complete_exercise",
          params: ATHLTHTournamentExerciseAttemptParams(
            p_match_exercise: slotID,p_evidence_note: evidence,
            p_source_workout: nil)
        ).execute()
    }
}

/// Local to the lobby client. The older Cloud service keeps its own private
/// RPC request structs, and nothing in its public API needs to be exposed.
private struct ATHLTHTournamentIDParamsPublic: Encodable {
    let p_tournament: UUID
}
