import Foundation
import Supabase

// Arena multiplayer uses separate tables from existing single Challenges,
// Club Challenges and the editorial Weekly Challenge. The database owns
// privacy checks, atomic invitations and approval permissions.
struct ATHLTHArenaRemoteSeries: Decodable, Identifiable {
    let id: UUID
    let ownerID: UUID?
    let title: String
    let scope: ATHLTHArenaScope
    let scoring: ATHLTHArenaScoring
    let durationDays: Int
    let status: String
    let startsAt: Date?
    let endsAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, scope, scoring, status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case completedAt = "completed_at"
        case ownerID = "owner_id"
        case durationDays = "duration_days"
    }
}

struct ATHLTHArenaRemoteMember: Decodable, Identifiable {
    let slotID: UUID
    let seriesID: UUID
    let userID: UUID?
    let response: String
    let points: Double
    let createdAt: Date

    var id: UUID { slotID }
    var isDeleted: Bool { userID == nil || response == "deleted" }

    enum CodingKeys: String, CodingKey {
        case response, points
        case createdAt = "created_at"
        case slotID = "slot_id"
        case seriesID = "series_id"
        case userID = "user_id"
    }
}

struct ATHLTHArenaRemoteProposal: Decodable, Identifiable {
    let id: UUID
    let seriesID: UUID
    let proposedBy: UUID?
    let template: ATHLTHArenaRoundTemplate
    let title: String
    let rules: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id, template, title, rules, position
        case seriesID = "series_id"
        case proposedBy = "proposed_by"
    }
}

struct ATHLTHArenaRemoteApproval: Decodable {
    let roundID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case userID = "user_id"
    }
}

struct ATHLTHArenaRemoteMessage: Decodable, Identifiable {
    let id: UUID
    let seriesID: UUID
    let senderID: UUID?
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case seriesID = "series_id"
        case senderID = "sender_id"
        case createdAt = "created_at"
    }
}

struct ATHLTHArenaReplacement: Decodable, Identifiable {
    let id: UUID
    let seriesID: UUID
    let slotID: UUID
    let nomineeID: UUID?
    let status: String
    enum CodingKeys: String, CodingKey {
        case id, status
        case seriesID = "series_id"
        case slotID = "slot_id"
        case nomineeID = "nominee_id"
    }
}

struct ATHLTHArenaReplacementVote: Decodable {
    let proposalID: UUID
    let voterID: UUID
    let accepted: Bool
    enum CodingKeys: String, CodingKey {
        case accepted
        case proposalID = "proposal_id"
        case voterID = "voter_id"
    }
}

struct ATHLTHArenaRoundResult: Decodable, Identifiable {
    let id: UUID
    let seriesID: UUID
    let roundID: UUID
    let proposedBy: UUID?
    let rankedSlots: [UUID]
    let evidenceNote: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case seriesID = "series_id"
        case roundID = "round_id"
        case proposedBy = "proposed_by"
        case rankedSlots = "ranked_slots"
        case evidenceNote = "evidence_note"
        case createdAt = "created_at"
    }
}

struct ATHLTHArenaRoundResultVote: Decodable {
    let resultID: UUID
    let userID: UUID
    let accepted: Bool
    enum CodingKeys: String, CodingKey {
        case accepted
        case resultID = "result_id"
        case userID = "user_id"
    }
}

struct ATHLTHArenaRoundPoints: Decodable {
    let roundID: UUID
    let slotID: UUID
    let points: Double
    enum CodingKeys: String, CodingKey {
        case points
        case roundID = "round_id"
        case slotID = "slot_id"
    }
}

private struct ATHLTHArenaStartParams: Encodable {
    let series: UUID
    enum CodingKeys: String, CodingKey { case series = "p_series" }
}

private struct ATHLTHArenaOutcomeParams: Encodable {
    let round: UUID
    let slots: [UUID]
    let evidence: String
    enum CodingKeys: String, CodingKey {
        case round = "p_round"
        case slots = "p_slots"
        case evidence = "p_evidence"
    }
}

private struct ATHLTHArenaOutcomeVoteParams: Encodable {
    let result: UUID
    let accept: Bool
    enum CodingKeys: String, CodingKey {
        case result = "p_result"
        case accept = "p_accept"
    }
}

struct ATHLTHArenaWorkoutEvidence: Decodable, Identifiable {
    let id: UUID
    let seriesID: UUID
    let roundID: UUID
    let slotID: UUID
    let userID: UUID
    let sourceWorkoutID: UUID
    let source: String
    let activityType: String
    let startedAt: Date
    let endedAt: Date
    let metricType: String
    let metricValue: Double
    let reportedDistanceMeters: Double?
    let verificationLevel: String

    enum CodingKeys: String, CodingKey {
        case id, source
        case reportedDistanceMeters = "reported_distance_meters"
        case verificationLevel = "verification_level"
        case seriesID = "series_id"
        case roundID = "round_id"
        case slotID = "slot_id"
        case userID = "user_id"
        case sourceWorkoutID = "source_workout_id"
        case activityType = "activity_type"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case metricType = "metric_type"
        case metricValue = "metric_value"
    }
}

private struct ATHLTHArenaEvidenceParams: Encodable {
    let roundID: UUID
    let sourceWorkoutID: UUID
    let source: String
    let activity: String
    let startedAt: Date
    let endedAt: Date
    let metricType: String
    let metricValue: Double
    let distanceMeters: Double?

    enum CodingKeys: String, CodingKey {
        case distanceMeters = "p_distance"
        case roundID = "p_round"
        case sourceWorkoutID = "p_source_workout"
        case source = "p_source"
        case activity = "p_activity"
        case startedAt = "p_started"
        case endedAt = "p_ended"
        case metricType = "p_metric_type"
        case metricValue = "p_metric"
    }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(roundID, forKey: .roundID)
        try fields.encode(sourceWorkoutID, forKey: .sourceWorkoutID)
        try fields.encode(source, forKey: .source)
        try fields.encode(activity, forKey: .activity)
        try fields.encode(startedAt, forKey: .startedAt)
        try fields.encode(endedAt, forKey: .endedAt)
        try fields.encode(metricType, forKey: .metricType)
        try fields.encode(metricValue, forKey: .metricValue)
        if let distanceMeters {
            try fields.encode(distanceMeters, forKey: .distanceMeters)
        } else {
            try fields.encodeNil(forKey: .distanceMeters)
        }
    }
}

private struct ATHLTHArenaUnshareParams: Encodable {
    let evidenceID: UUID
    enum CodingKeys: String, CodingKey {
        case evidenceID = "p_evidence"
    }
}

private struct ATHLTHArenaNewMessage: Encodable {
    let seriesID: UUID
    let senderID: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case body
        case seriesID = "series_id"
        case senderID = "sender_id"
    }
}
private struct ATHLTHArenaProposalReplacementParams: Encodable {
    let slot: UUID
    let nominee: UUID
    enum CodingKeys: String, CodingKey {
        case slot = "p_slot"
        case nominee = "p_nominee"
    }
}
private struct ATHLTHArenaVoteReplacementParams: Encodable {
    let proposal: UUID
    let accept: Bool
    enum CodingKeys: String, CodingKey {
        case proposal = "p_proposal"
        case accept = "p_accept"
    }
}

private struct ATHLTHArenaPublishRound: Encodable {
    let template: String
    let title: String
    let rules: String
}

private struct ATHLTHArenaPublishRequest: Encodable {
    let title: String
    let scope: String
    let scoring: String
    let durationDays: Int
    let invitees: [UUID]
    let rounds: [ATHLTHArenaPublishRound]

    enum CodingKeys: String, CodingKey {
        case title = "p_title"
        case scope = "p_scope"
        case scoring = "p_scoring"
        case durationDays = "p_duration_days"
        case invitees = "p_invitees"
        case rounds = "p_rounds"
    }
}

private struct ATHLTHArenaNewRound: Encodable {
    let seriesID: UUID
    let proposedBy: UUID
    let template: String
    let title: String
    let rules: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case template, title, rules, position
        case seriesID = "series_id"
        case proposedBy = "proposed_by"
    }
}

private struct ATHLTHArenaNewApproval: Encodable {
    let roundID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case userID = "user_id"
    }
}

enum ATHLTHArenaCloudError: LocalizedError {
    case signInRequired
    case unavailableScope
    case needInvitees
    case needRounds
    case tooManyRounds
    case evidenceNotFound

    var errorDescription: String? {
        switch self {
        case .signInRequired:
            return ATHLTHLocalization.choose(
                english: "Sign in to publish a competition.",
                norwegian: "Logg inn for å publisere en konkurranse."
            )
        case .unavailableScope:
            return ATHLTHLocalization.choose(
                english: "Club series need Club membership integration and cannot be published yet.",
                norwegian: "Club-serier kan ikke publiseres før Club-medlemskap er koblet til."
            )
        case .needInvitees:
            return ATHLTHLocalization.choose(
                english: "Select an opponent or friends before publishing.",
                norwegian: "Velg en motstander eller venner før publisering."
            )
        case .needRounds:
            return ATHLTHLocalization.choose(
                english: "Add at least one round before publishing.",
                norwegian: "Legg til minst én runde før publisering."
            )
        case .tooManyRounds:
            return ATHLTHLocalization.choose(
                english: "A series can contain up to 16 rounds.",
                norwegian: "En serie kan inneholde maksimalt 16 runder."
            )
        case .evidenceNotFound:
            return ATHLTHLocalization.choose(
                english: "The workout link is no longer available.",
                norwegian: "Øktkoblingen finnes ikke lenger."
            )
        }
    }
}

final class ATHLTHArenaCloudService: Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    private var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func loadSeries() async throws -> [ATHLTHArenaRemoteSeries] {
        guard currentUserID != nil else {
            return []
        }
        return try await client
            .from("arena_series")
            .select()
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func loadMembers(seriesID: UUID) async throws -> [ATHLTHArenaRemoteMember] {
        try await client
            .from("arena_series_members")
            .select()
            .eq("series_id", value: seriesID)
            .execute()
            .value
    }

    func loadProposals(seriesID: UUID) async throws -> [ATHLTHArenaRemoteProposal] {
        try await client
            .from("arena_round_proposals")
            .select()
            .eq("series_id", value: seriesID)
            .order("position")
            .execute()
            .value
    }

    func loadApprovals(roundIDs: [UUID]) async throws -> [ATHLTHArenaRemoteApproval] {
        guard !roundIDs.isEmpty else { return [] }
        return try await client
            .from("arena_round_approvals")
            .select()
            .in("round_id", values: roundIDs)
            .execute()
            .value
    }

    func loadGroupMessages(seriesID: UUID) async throws -> [ATHLTHArenaRemoteMessage] {
        try await client
            .from("arena_series_messages")
            .select()
            .eq("series_id", value: seriesID)
            .order("created_at", ascending: true)
            .limit(200)
            .execute()
            .value
    }

    func sendGroupMessage(seriesID: UUID, body: String) async throws {
        guard let senderID = currentUserID else {
            throw ATHLTHArenaCloudError.signInRequired
        }
        let message = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !message.isEmpty else { return }
        try await client.from("arena_series_messages")
            .insert(ATHLTHArenaNewMessage(seriesID: seriesID, senderID: senderID, body: message))
            .execute()
    }

    func loadReplacements(seriesID: UUID) async throws -> [ATHLTHArenaReplacement] {
        try await client.from("arena_replacement_proposals")
            .select()
            .eq("series_id", value: seriesID)
            .order("created_at", ascending: false)
            .execute().value
    }

    func loadReplacementVotes(proposalID: UUID) async throws -> [ATHLTHArenaReplacementVote] {
        try await client.from("arena_replacement_votes")
            .select()
            .eq("proposal_id", value: proposalID)
            .execute().value
    }

    func proposeReplacement(slotID: UUID, nomineeID: UUID) async throws {
        guard currentUserID != nil else { throw ATHLTHArenaCloudError.signInRequired }
        let _: UUID = try await client.rpc(
            "arena_propose_replacement",
            params: ATHLTHArenaProposalReplacementParams(slot: slotID, nominee: nomineeID)
        ).execute().value
    }

    func voteReplacement(proposalID: UUID, approve: Bool) async throws {
        guard currentUserID != nil else { throw ATHLTHArenaCloudError.signInRequired }
        let _: String = try await client.rpc(
            "arena_vote_replacement",
            params: ATHLTHArenaVoteReplacementParams(proposal: proposalID, accept: approve)
        ).execute().value
    }

    func loadRoundResults(seriesID: UUID) async throws -> [ATHLTHArenaRoundResult] {
        try await client.from("arena_round_results")
            .select()
            .eq("series_id", value: seriesID)
            .order("created_at", ascending: false)
            .execute().value
    }

    func loadResultVotes(resultIDs: [UUID]) async throws -> [ATHLTHArenaRoundResultVote] {
        guard !resultIDs.isEmpty else { return [] }
        return try await client.from("arena_round_result_votes")
            .select()
            .in("result_id", values: resultIDs)
            .execute().value
    }

    func loadAwardedPoints(seriesID: UUID) async throws -> [ATHLTHArenaRoundPoints] {
        let rounds = try await loadProposals(seriesID: seriesID)
        guard !rounds.isEmpty else { return [] }
        return try await client.from("arena_round_points")
            .select()
            .in("round_id", values: rounds.map(\.id))
            .execute().value
    }

    func startSeries(seriesID: UUID) async throws {
        guard currentUserID != nil else { throw ATHLTHArenaCloudError.signInRequired }
        let _: String = try await client.rpc(
            "arena_start_series",
            params: ATHLTHArenaStartParams(series: seriesID)
        ).execute().value
    }

    func proposeRoundOutcome(
        roundID: UUID,
        rankedSlots: [UUID],
        evidence: String
    ) async throws {
        guard currentUserID != nil else { throw ATHLTHArenaCloudError.signInRequired }
        let _: UUID = try await client.rpc(
            "arena_propose_result",
            params: ATHLTHArenaOutcomeParams(
                round: roundID, slots: rankedSlots, evidence: evidence
            )
        ).execute().value
    }

    func voteRoundOutcome(resultID: UUID, accept: Bool) async throws {
        guard currentUserID != nil else { throw ATHLTHArenaCloudError.signInRequired }
        let _: String = try await client.rpc(
            "arena_vote_result",
            params: ATHLTHArenaOutcomeVoteParams(result: resultID, accept: accept)
        ).execute().value
    }

    func loadWorkoutEvidence(seriesID: UUID) async throws -> [ATHLTHArenaWorkoutEvidence] {
        try await client.from("arena_workout_evidence")
            .select()
            .eq("series_id", value: seriesID)
            .order("started_at", ascending: false)
            .limit(300)
            .execute().value
    }

    /// Explicit user action only. Sends a workout UUID, time, source and
    /// minimum relevant metric, never heart rate, GPS track or health profile.
    func shareWorkoutEvidence(
        roundID: UUID,
        workout: SocialPublishableWorkout,
        metricType: String,
        metricValue: Double
    ) async throws {
        guard currentUserID != nil else {
            throw ATHLTHArenaCloudError.signInRequired
        }
        let source: String
        switch workout.source {
        case "ATHLTH":
            source = "athlth_strength"
        case "iPhone":
            source = "iphone"
        default:
            source = "apple_health"
        }
        let activity: String
        switch workout.activity {
        case .running: activity = "running"
        case .walking: activity = "walking"
        case .strength: activity = "strength"
        default: activity = "other"
        }
        let _: UUID = try await client.rpc(
            "arena_share_evidence_v2",
            params: ATHLTHArenaEvidenceParams(
                roundID: roundID,
                sourceWorkoutID: workout.id,
                source: source,
                activity: activity,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                metricType: metricType,
                metricValue: metricValue,
                distanceMeters: workout.distanceMeters
            )
        ).execute().value
    }

    func withdrawWorkoutEvidence(id: UUID) async throws {
        guard currentUserID != nil else {
            throw ATHLTHArenaCloudError.signInRequired
        }
        let success: Bool = try await client.rpc(
            "arena_unshare_evidence",
            params: ATHLTHArenaUnshareParams(evidenceID: id)
        ).execute().value
        guard success else {
            throw ATHLTHArenaCloudError.evidenceNotFound
        }
    }

    /// All writes happen in one server-side transaction. If any invitee
    /// disallows invitations or a round is invalid, nothing is published.
    func publish(_ draft: ATHLTHArenaCompetitionDraft) async throws -> UUID {
        guard let currentUserID, currentUserID == draft.ownerID else {
            throw ATHLTHArenaCloudError.signInRequired
        }
        guard draft.scope != .club else {
            throw ATHLTHArenaCloudError.unavailableScope
        }
        let invitees = Array(Set(draft.participantIDs))
            .filter { $0 != currentUserID }
            .sorted { $0.uuidString < $1.uuidString }
        guard !invitees.isEmpty,
              (draft.scope != .duel || invitees.count == 1) else {
            throw ATHLTHArenaCloudError.needInvitees
        }
        guard !draft.rounds.isEmpty else {
            throw ATHLTHArenaCloudError.needRounds
        }
        guard draft.rounds.count <= 16 else {
            throw ATHLTHArenaCloudError.tooManyRounds
        }

        let params = ATHLTHArenaPublishRequest(
            title: draft.title,
            scope: draft.scope.rawValue,
            scoring: draft.scoring.rawValue,
            durationDays: draft.durationDays,
            invitees: invitees,
            rounds: draft.rounds.map {
                ATHLTHArenaPublishRound(
                    template: $0.template.rawValue,
                    title: $0.title,
                    rules: $0.rules
                )
            }
        )
        let publishedID: UUID = try await client
            .rpc("arena_publish_series", params: params)
            .execute()
            .value
        return publishedID
    }

    func respond(seriesID: UUID, accept: Bool) async throws {
        guard let userID = currentUserID else {
            throw ATHLTHArenaCloudError.signInRequired
        }
        try await client
            .from("arena_series_members")
            .update(["response": accept ? "accepted" : "declined"])
            .eq("series_id", value: seriesID)
            .eq("user_id", value: userID)
            .execute()
    }

    func propose(
        seriesID: UUID,
        round: ATHLTHArenaRoundDraft,
        position: Int
    ) async throws {
        guard let userID = currentUserID else {
            throw ATHLTHArenaCloudError.signInRequired
        }
        try await client
            .from("arena_round_proposals")
            .insert(ATHLTHArenaNewRound(
                seriesID: seriesID,
                proposedBy: userID,
                template: round.template.rawValue,
                title: round.title,
                rules: round.rules,
                position: min(max(position, 0), 100)
            ))
            .execute()
    }

    func approve(roundID: UUID) async throws {
        guard let userID = currentUserID else {
            throw ATHLTHArenaCloudError.signInRequired
        }
        try await client
            .from("arena_round_approvals")
            .insert(ATHLTHArenaNewApproval(roundID: roundID, userID: userID))
            .execute()
    }
}
