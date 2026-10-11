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
    let seriesID: UUID
    let userID: UUID
    let response: String

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case response
        case seriesID = "series_id"
        case userID = "user_id"
    }
}

struct ATHLTHArenaRemoteProposal: Decodable, Identifiable {
    let id: UUID
    let seriesID: UUID
    let proposedBy: UUID
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
