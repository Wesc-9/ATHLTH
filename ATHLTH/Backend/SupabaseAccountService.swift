import Foundation
import Supabase

@MainActor
final class SupabaseAccountService: ObservableObject {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func signUp(email: String, password: String) async throws {
        _ = try await client.auth.signUp(
            email: email,
            password: password
        )
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(
            email: email,
            password: password
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func loadCurrentUser() async throws -> BackendUserBootstrap {
        guard let userID = currentUserID else {
            throw SupabaseAccountError.notAuthenticated
        }

        async let profile: BackendProfile = client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value

        async let role: BackendAccountRole = client
            .from("account_roles")
            .select()
            .eq("user_id", value: userID)
            .single()
            .execute()
            .value

        async let entitlement: BackendSubscriptionEntitlement = client
            .from("subscription_entitlements")
            .select()
            .eq("user_id", value: userID)
            .single()
            .execute()
            .value

        return try await BackendUserBootstrap(
            profile: profile,
            role: role,
            entitlement: entitlement
        )
    }

    func claimUsername(_ username: String) async throws {
        guard let userID = currentUserID else {
            throw SupabaseAccountError.notAuthenticated
        }

        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        try await client
            .from("profiles")
            .update(["username": cleaned])
            .eq("id", value: userID)
            .execute()
    }
}

enum SupabaseAccountError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No authenticated ATHLTH user is available."
        }
    }
}
