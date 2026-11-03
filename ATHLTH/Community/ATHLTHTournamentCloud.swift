import Foundation
import Supabase

/// Server-owned competitions, separate from the legacy private draft store.
/// A fixture has no winner until the opponent independently approves it.
struct ATHLTHTournamentRemote: Decodable, Identifiable {
    let id: UUID
    let ownerID: UUID
    let clubID: UUID?
    let seasonID: UUID?
    let title: String
    let format: ATHLTHTournamentFormat
    let groupSize: Int
    let qualifiersPerGroup: Int
    let winPoints: Int
    let drawPoints: Int
    let status: String
    let exerciseMode: ATHLTHTournamentExerciseMode
    let exerciseCount: Int
    let proposalsCloseAt: Date?
    let votesCloseAt: Date?
    let approvePlayerChanges: Bool
    let exerciseSelectionFinalizedAt: Date?
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, format, status
        case exerciseMode = "exercise_mode"
        case exerciseCount = "exercise_count"
        case proposalsCloseAt = "proposals_close_at"
        case votesCloseAt = "votes_close_at"
        case approvePlayerChanges = "approve_player_changes"
        case exerciseSelectionFinalizedAt = "exercise_selection_finalized_at"
        case ownerID = "owner_id"
        case clubID = "club_id"
        case seasonID = "season_id"
        case groupSize = "group_size"
        case qualifiersPerGroup = "qualifiers_per_group"
        case winPoints = "win_points"
        case drawPoints = "draw_points"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct ATHLTHTournamentRemoteEntry: Decodable, Identifiable {
    let tournamentID: UUID
    let userID: UUID
    let seed: Int
    let response: String
    let respondedAt: Date?
    let groupIndex: Int?
    let isReady: Bool
    let readyAt: Date?
    let removedAt: Date?
    let replacedBy: UUID?
    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case seed, response
        case tournamentID = "tournament_id"
        case userID = "user_id"
        case respondedAt = "responded_at"
        case groupIndex = "group_index"
        case isReady = "is_ready"
        case readyAt = "ready_at"
        case removedAt = "removed_at"
        case replacedBy = "replaced_by"
    }
}

struct ATHLTHTournamentRemoteMatch: Decodable, Identifiable {
    let id: UUID
    let tournamentID: UUID
    let phase: ATHLTHTournamentPhase
    let roundNumber: Int
    let groupIndex: Int?
    let slotIndex: Int
    let homeID: UUID
    let awayID: UUID?
    let homeScore: Double?
    let awayScore: Double?
    let status: String
    let proposedBy: UUID?
    let confirmedBy: UUID?
    let confirmedAt: Date?
    let evidenceNote: String
    let scheduledAt: Date?
    let deadlineAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, phase, status
        case tournamentID = "tournament_id"
        case roundNumber = "round_number"
        case groupIndex = "group_index"
        case slotIndex = "slot_index"
        case homeID = "home_id"
        case awayID = "away_id"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case proposedBy = "proposed_by"
        case confirmedBy = "confirmed_by"
        case confirmedAt = "confirmed_at"
        case evidenceNote = "evidence_note"
        case scheduledAt = "scheduled_at"
        case deadlineAt = "deadline_at"
    }

    var isVerified: Bool { status == "confirmed" }
    var isWarmup: Bool { phase == .warmup }
    var isBye: Bool { awayID == nil }
    var winnerID: UUID? {
        guard isVerified else { return nil }
        guard let awayID else { return homeID }
        guard let homeScore, let awayScore, homeScore != awayScore else {
            return nil
        }
        return homeScore > awayScore ? homeID : awayID
    }
}

/// The database is the authoritative source for official rankings and
/// playoff qualification. The iPhone never reorders tied athletes locally.
struct ATHLTHTournamentStandingRemote: Decodable, Identifiable {
    let userID: UUID
    let username: String
    let groupIndex: Int?
    let played: Int
    let wins: Int
    let draws: Int
    let losses: Int
    let scored: Double
    let conceded: Double
    let points: Int
    let rank: Int
    var id: UUID { userID }
    var difference: Double { scored - conceded }

    enum CodingKeys: String, CodingKey {
        case username, played, wins, draws, losses, scored, conceded
        case points, rank
        case userID = "user_id"
        case groupIndex = "group_index"
    }
}

private struct ATHLTHTournamentStandingsParams: Encodable {
    let p_tournament: UUID
    let p_group: Int?
}

private struct ATHLTHTournamentCreateParams: Encodable {
    let p_title: String
    let p_format: String
    let p_club: UUID?
    let p_season: UUID?
    let p_group_size: Int
    let p_qualifiers: Int
    let p_invitees: [UUID]
    let p_warmup_titles: [String]

    enum CodingKeys: String, CodingKey {
        case p_title, p_format, p_club, p_season
        case p_group_size, p_qualifiers, p_invitees, p_warmup_titles
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(p_title, forKey: .p_title)
        try values.encode(p_format, forKey: .p_format)
        // These positional RPC args are required even when the user creates
        // a personal competition. Explicit JSON nulls prevent PostgREST from
        // mistaking an omitted optional parameter for a different overload.
        try values.encode(p_club, forKey: .p_club)
        try values.encode(p_season, forKey: .p_season)
        try values.encode(p_group_size, forKey: .p_group_size)
        try values.encode(p_qualifiers, forKey: .p_qualifiers)
        try values.encode(p_invitees, forKey: .p_invitees)
        try values.encode(p_warmup_titles, forKey: .p_warmup_titles)
    }
}

private struct ATHLTHTournamentConfiguredCreateParams: Encodable {
    let p_title: String
    let p_format: String
    let p_club: UUID?
    let p_season: UUID?
    let p_group_size: Int
    let p_qualifiers: Int
    let p_invitees: [UUID]
    let p_warmup_titles: [String]
    let p_exercise_mode: String
    let p_exercise_count: Int
    let p_proposals_close: String?
    let p_votes_close: String?
    let p_approve_player_changes: Bool

    enum CodingKeys: String, CodingKey {
        case p_title,p_format,p_club,p_season,p_group_size,p_qualifiers,
             p_invitees,p_warmup_titles,p_exercise_mode,p_exercise_count,
             p_proposals_close,p_votes_close,p_approve_player_changes
    }

    func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: CodingKeys.self)
        try keyed.encode(p_title,forKey: .p_title)
        try keyed.encode(p_format,forKey: .p_format)
        try keyed.encode(p_club,forKey: .p_club)
        try keyed.encode(p_season,forKey: .p_season)
        try keyed.encode(p_group_size,forKey: .p_group_size)
        try keyed.encode(p_qualifiers,forKey: .p_qualifiers)
        try keyed.encode(p_invitees,forKey: .p_invitees)
        try keyed.encode(p_warmup_titles,forKey: .p_warmup_titles)
        try keyed.encode(p_exercise_mode,forKey: .p_exercise_mode)
        try keyed.encode(p_exercise_count,forKey: .p_exercise_count)
        try keyed.encode(p_proposals_close,forKey: .p_proposals_close)
        try keyed.encode(p_votes_close,forKey: .p_votes_close)
        try keyed.encode(p_approve_player_changes,forKey: .p_approve_player_changes)
    }
}

private struct ATHLTHTournamentSeasonParams: Encodable {
    let p_season: UUID
}

private struct ATHLTHTournamentIDParams: Encodable {
    let p_tournament: UUID
}

private struct ATHLTHTournamentWithdrawParams: Encodable {
    let p_tournament: UUID
    let p_athlete: UUID
}

private struct ATHLTHTournamentRespondParams: Encodable {
    let p_tournament: UUID
    let p_accept: Bool
}

private struct ATHLTHTournamentProposalParams: Encodable {
    let p_match: UUID
    let p_home_score: Double
    let p_away_score: Double
    let p_evidence: String
}

private struct ATHLTHTournamentDeadlineParams: Encodable {
    let p_match: UUID
    let p_deadline: String
}

private struct ATHLTHTournamentConfirmParams: Encodable {
    let p_match: UUID
    let p_confirm: Bool
}

private struct ATHLTHTournamentProfile: Decodable {
    let userID: UUID
    let username: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case username
        case userID = "user_id"
        case displayName = "display_name"
    }

    var preferredName: String {
        let handle = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (handle?.isEmpty == false) ? handle! :
            (displayName?.isEmpty == false ? displayName! : "Utøver")
    }
}

private struct ATHLTHTournamentInvitationID: Decodable {
    let tournamentID: UUID
    enum CodingKeys: String, CodingKey {
        case tournamentID = "tournament_id"
    }
}

private struct ATHLTHTournamentReplacementOfferID: Decodable {
    let tournamentID: UUID
    enum CodingKeys: String, CodingKey {
        case tournamentID = "tournament_id"
    }
}

struct ATHLTHTournamentCloudService {
    private let client = SupabaseEnvironment.client

    func create(from draft: ATHLTHTournamentDraft) async throws -> UUID {
        guard draft.participants.count >= 2 else {
            throw ATHLTHTournamentEngineError.tooFewParticipants
        }
        try ATHLTHTournamentEngine.validate(
            draft.participants,
            groupSize: draft.groupSize,
            qualifiersPerGroup: draft.qualifiersPerGroup
        )
        let targets = draft.participants.filter { $0.id != draft.ownerID }
        let timestamp = ISO8601DateFormatter()
        return try await client.rpc(
            "athlth_tournament_create_configured",
            params: ATHLTHTournamentConfiguredCreateParams(
                p_title: draft.title,
                p_format: draft.format.rawValue,
                p_club: draft.clubID,
                p_season: draft.seasonID,
                p_group_size: draft.groupSize,
                p_qualifiers: draft.qualifiersPerGroup,
                p_invitees: targets.map(\.id),
                p_warmup_titles: draft.warmupRounds.map(\.title),
                p_exercise_mode: draft.exerciseMode.rawValue,
                p_exercise_count: draft.exerciseCount,
                p_proposals_close: draft.proposalsCloseAt.map {
                    timestamp.string(from: $0)
                },
                p_votes_close: draft.votesCloseAt.map {
                    timestamp.string(from: $0)
                },
                p_approve_player_changes: draft.approvePlayerChanges
            )
        ).execute().value
    }

    func visibleTournaments() async throws -> [ATHLTHTournamentRemote] {
        var list: [ATHLTHTournamentRemote] = []
        let pageSize = 200
        var offset = 0
        repeat {
            let page: [ATHLTHTournamentRemote] = try await client
                .from("athlth_tournaments")
                .select()
                .order("created_at", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute().value
            list += page
            if page.count < pageSize { break }
            offset += pageSize
        } while offset < 5_000
        return list
    }

    func standings(for tournamentID: UUID) async throws
        -> [ATHLTHTournamentStandingRemote] {
        // Includes league and group-stage scores but never warmup or cup
        // rounds. Row-level security restricts the returned tournament.
        return try await client.rpc(
            "athlth_tournament_standings",
            params: ATHLTHTournamentStandingsParams(
                p_tournament: tournamentID, p_group: nil
            )
        ).execute().value
    }

    func myTournamentIDs(userID: UUID) async throws -> Set<UUID> {
        // The club may have competitions visible to members. Arena's "Mine"
        // tab lists only events where this athlete is actually an entrant,
        // not every event visible through club membership.
        var ids = Set<UUID>()
        let pageSize = 250
        var offset = 0
        repeat {
            let page: [ATHLTHTournamentInvitationID] = try await client
                .from("athlth_tournament_entries")
                .select("tournament_id")
                .eq("user_id", value: userID)
                .neq("response", value: "declined")
                .range(from: offset, to: offset + pageSize - 1)
                .execute().value
            ids.formUnion(page.map(\.tournamentID))
            if page.count < pageSize { break }
            offset += pageSize
        } while offset < 5_000
        ids.formUnion(try await pendingReplacementTournamentIDs(userID: userID))
        return ids
    }

    private func pendingReplacementTournamentIDs(userID: UUID) async throws
        -> Set<UUID> {
        let records: [ATHLTHTournamentReplacementOfferID] = try await client
            .from("athlth_tournament_player_change")
            .select("tournament_id")
            .eq("new_player_id",value: userID)
            .eq("status",value: "pending")
            .limit(200)
            .execute().value
        return Set(records.map(\.tournamentID))
    }

    func pendingInvitationIDs(userID: UUID) async throws -> Set<UUID> {
        let pending: [ATHLTHTournamentInvitationID] = try await client
            .from("athlth_tournament_entries")
            .select("tournament_id")
            .eq("user_id", value: userID)
            .eq("response", value: "invited")
            .limit(500)
            .execute().value
        var ids = Set(pending.map(\.tournamentID))
        ids.formUnion(try await pendingReplacementTournamentIDs(userID: userID))
        return ids
    }

    func entries(for tournamentID: UUID) async throws
        -> [ATHLTHTournamentRemoteEntry] {
        return try await client.from("athlth_tournament_entries")
            .select()
            .eq("tournament_id", value: tournamentID)
            .order("seed")
            .limit(128)
            .execute().value
    }

    func matches(for tournamentID: UUID) async throws
        -> [ATHLTHTournamentRemoteMatch] {
        var list: [ATHLTHTournamentRemoteMatch] = []
        let pageSize = 500
        var offset = 0
        repeat {
            let page: [ATHLTHTournamentRemoteMatch] = try await client
                .from("athlth_tournament_matches")
                .select()
                .eq("tournament_id", value: tournamentID)
                .order("round_number")
                .order("slot_index")
                .range(from: offset, to: offset + pageSize - 1)
                .execute().value
            list += page
            if page.count < pageSize { break }
            offset += pageSize
        } while offset < 10_000
        return list
    }

    func athleteNames(for IDs: Set<UUID>) async throws -> [UUID: String] {
        guard !IDs.isEmpty else { return [:] }
        let records: [ATHLTHTournamentProfile] = try await client
            .from("social_profile_cards")
            .select("user_id,username,display_name")
            .in("user_id", values: Array(IDs))
            .limit(150)
            .execute().value
        return Dictionary(uniqueKeysWithValues:
            records.map { ($0.userID, $0.preferredName) }
        )
    }

    func clubSeasonScores(
        seasonID: UUID
    ) async throws -> [ATHLTHArenaSeasonStandingsRow] {
        return try await client.rpc(
            "athlth_tournament_season_scores",
            params: ATHLTHTournamentSeasonParams(p_season: seasonID)
        ).execute().value
    }

    func respond(tournamentID: UUID, accept: Bool) async throws {
        try await client.rpc(
            "athlth_tournament_respond",
            params: ATHLTHTournamentRespondParams(
                p_tournament: tournamentID, p_accept: accept
            )
        ).execute()
    }

    func withdrawInvitation(
        tournamentID: UUID, athleteID: UUID
    ) async throws {
        try await client.rpc(
            "athlth_tournament_withdraw_invite",
            params: ATHLTHTournamentWithdrawParams(
                p_tournament: tournamentID, p_athlete: athleteID
            )
        ).execute()
    }

    func cancelUnstarted(tournamentID: UUID) async throws {
        try await client.rpc(
            "athlth_tournament_cancel",
            params: ATHLTHTournamentIDParams(p_tournament: tournamentID)
        ).execute()
    }

    func start(tournamentID: UUID) async throws {
        try await client.rpc(
            "athlth_tournament_start",
            params: ATHLTHTournamentIDParams(p_tournament: tournamentID)
        ).execute()
    }

    func propose(
        matchID: UUID, homeScore: Double, awayScore: Double,
        evidence: String
    ) async throws {
        guard homeScore.isFinite, awayScore.isFinite,
              homeScore >= 0, awayScore >= 0 else {
            throw ATHLTHTournamentEngineError.invalidApprovers
        }
        try await client.rpc(
            "athlth_tournament_propose_result",
            params: ATHLTHTournamentProposalParams(
                p_match: matchID,
                p_home_score: homeScore,
                p_away_score: awayScore,
                p_evidence: String(evidence.prefix(400))
            )
        ).execute()
    }

    func extendDeadline(matchID: UUID, until date: Date) async throws {
        let stamp = ISO8601DateFormatter().string(from: date)
        try await client.rpc(
            "athlth_tournament_extend_deadline",
            params: ATHLTHTournamentDeadlineParams(
                p_match: matchID, p_deadline: stamp
            )
        ).execute()
    }

    func confirm(matchID: UUID, approved: Bool) async throws {
        try await client.rpc(
            "athlth_tournament_confirm_result",
            params: ATHLTHTournamentConfirmParams(
                p_match: matchID, p_confirm: approved
            )
        ).execute()
    }
}
