import Foundation
import Supabase

/// Personal competition templates are synchronized by account, never shared
/// and never contain other athletes' identifiers or an old season ID.
struct ATHLTHTournamentPersonalTemplate: Decodable, Identifiable {
    let id: UUID
    let ownerID: UUID
    let name: String
    let payload: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, name, payload
        case ownerID = "owner_id"
        case createdAt = "created_at"
    }
    func draft(for userID: UUID) throws -> ATHLTHTournamentDraft {
        guard ownerID == userID, let data = payload.data(using: .utf8) else {
            throw ATHLTHTournamentTemplateError.invalid
        }
        var draft = try JSONDecoder().decode(ATHLTHTournamentDraft.self, from: data)
        draft.id = UUID()
        draft.ownerID = userID
        draft.participants = draft.participants.filter { $0.id == userID }
        draft.clubID = nil
        draft.seasonID = nil
        draft.competitionSettings.startsAt = nil
        if draft.competitionSettings.startMode == .scheduled {
            draft.competitionSettings.startMode = .manual
        }
        draft.proposalsCloseAt = draft.exerciseMode == .vote
            ? Date().addingTimeInterval(2 * 86_400) : nil
        draft.votesCloseAt = draft.exerciseMode == .vote
            ? Date().addingTimeInterval(3 * 86_400) : nil
        return draft
    }
}

enum ATHLTHTournamentTemplateError: LocalizedError {
    case invalid
    var errorDescription: String? {
        "Malen kunne ikke åpnes. Lag en ny mal fra konkurranseoppsettet."
    }
}

private struct ATHLTHTournamentPersonalTemplateInsert: Encodable {
    let ownerID: UUID
    let name: String
    let payload: String
    enum CodingKeys: String, CodingKey {
        case name, payload
        case ownerID = "owner_id"
    }
}

struct ATHLTHTournamentTemplateCloudService {
    private let client = SupabaseEnvironment.client

    func load(for userID: UUID) async throws
        -> [ATHLTHTournamentPersonalTemplate] {
        try await client.from("athlth_tournament_templates")
            .select("id,owner_id,name,payload,created_at")
            .eq("owner_id", value: userID)
            .order("created_at", ascending: false)
            .limit(100).execute().value
    }

    func save(_ draft: ATHLTHTournamentDraft,
              name: String, userID: UUID) async throws {
        let title = String(name.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80))
        guard title.count >= 2 else { throw ATHLTHTournamentTemplateError.invalid }
        var copy = draft
        copy.id = UUID()
        copy.ownerID = userID
        copy.clubID = nil
        copy.seasonID = nil
        // Templates capture a recipe, not users, health notes, or private chats.
        copy.participants = copy.participants.filter { $0.id == userID }
        copy.competitionSettings.startsAt = nil
        if copy.competitionSettings.startMode == .scheduled {
            copy.competitionSettings.startMode = .manual
        }
        let payload = String(decoding: try JSONEncoder().encode(copy), as: UTF8.self)
        try await client.from("athlth_tournament_templates")
            .upsert(ATHLTHTournamentPersonalTemplateInsert(
                ownerID: userID, name: title, payload: payload
            ), onConflict: "owner_id,name").execute()
    }

    func delete(_ template: ATHLTHTournamentPersonalTemplate,
                userID: UUID) async throws {
        guard template.ownerID == userID else {
            throw ATHLTHTournamentTemplateError.invalid
        }
        try await client.from("athlth_tournament_templates")
            .delete()
            .eq("id",value: template.id)
            .eq("owner_id",value: userID).execute()
    }
}
