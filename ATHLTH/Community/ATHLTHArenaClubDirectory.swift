import Foundation
import Supabase

/// Only club membership and public display names are fetched for inviting
/// Club athletes. This is intentionally separate from Weekly Challenges.
struct ATHLTHArenaClubChoice: Identifiable, Decodable {
    let id: UUID
    let name: String
}

struct ATHLTHArenaClubAthlete: Identifiable {
    let id: UUID
    let displayName: String
}

private struct ATHLTHArenaClubMembershipRow: Decodable {
    let groupID: UUID
    let userID: UUID
    let role: String
    enum CodingKeys: String, CodingKey {
        case role
        case groupID = "group_id"
        case userID = "user_id"
    }
}

private struct ATHLTHArenaClubPersonRow: Decodable {
    let userID: UUID
    let displayName: String?
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
    }
}

final class ATHLTHArenaClubDirectory: Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func manageableClubs() async throws -> [ATHLTHArenaClubChoice] {
        guard let actor = client.auth.currentUser?.id else { return [] }
        let memberships: [ATHLTHArenaClubMembershipRow] = try await client
            .from("community_group_members")
            .select("group_id,user_id,role")
            .eq("user_id", value: actor)
            .in("role", values: ["owner", "admin"])
            .execute().value
        let ids = memberships.map(\.groupID)
        guard !ids.isEmpty else { return [] }
        return try await client
            .from("community_groups")
            .select("id,name")
            .in("id", values: ids)
            .order("name")
            .execute().value
    }

    func athletes(in club: UUID) async throws -> [ATHLTHArenaClubAthlete] {
        let members: [ATHLTHArenaClubMembershipRow] = try await client
            .from("community_group_members")
            .select("group_id,user_id,role")
            .eq("group_id", value: club)
            .execute().value
        let ids = members.map(\.userID).filter { $0 != client.auth.currentUser?.id }
        guard !ids.isEmpty else { return [] }
        let profiles: [ATHLTHArenaClubPersonRow] = try await client
            .from("social_profile_cards")
            .select("user_id,display_name")
            .in("user_id", values: ids)
            .execute().value
        var names: [UUID: String] = [:]
        for profile in profiles {
            if let name = profile.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                names[profile.userID] = name
            }
        }
        return ids.map { id in
            let fallback = ATHLTHLocalization.choose(
                english: "Club member", norwegian: "Klubbmedlem"
            )
            return ATHLTHArenaClubAthlete(
                id: id, displayName: names[id] ?? fallback
            )
        }.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
