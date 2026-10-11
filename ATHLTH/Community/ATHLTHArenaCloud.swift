import Foundation
import Supabase

// Arena multiplayer uses separate tables from existing single Challenges,
// Club Challenges and the editorial Weekly Challenge. The database owns
// privacy checks, atomic invitations and approval permissions.
struct ATHLTHArenaRemoteSeries: Decodable, Identifiable {
    let id: UUID
    let ownerID: UUID
    let title: String
    let scope: ATHLTHArenaScope
    let scoring: ATHLTHArenaScoring
    let durationDays: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, title, scope, scoring, status
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

    var id: UUID { slotID }
    var isDeleted: Bool { userID == nil || response == "deleted" }

    enum CodingKeys: String, CodingKey {
        case response, points
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
