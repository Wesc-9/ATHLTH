import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

enum EmailSignUpOutcome {
    case confirmationRequired
    case authenticated(BackendUserBootstrap)
}

@MainActor
final class SupabaseAccountService: ObservableObject {
    static let emailConfirmationURL = URL(string: "athlth://auth/confirm")!
    static let passwordResetURL = URL(string: "athlth://auth/reset")!

    @Published private(set) var passwordRecoveryPending = false

    private let client: SupabaseClient
    private var appleRawNonce: String?

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    var hasPersistedSession: Bool {
        client.auth.currentSession != nil
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        let rawNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        appleRawNonce = rawNonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(rawNonce)
    }

    func signInWithApple(
        credential: ASAuthorizationAppleIDCredential
    ) async throws -> BackendUserBootstrap {
        guard let rawNonce = appleRawNonce else {
            throw SupabaseAccountError.missingAppleNonce
        }

        defer { appleRawNonce = nil }

        guard let idToken = credential.identityToken
            .flatMap({ String(data: $0, encoding: .utf8) })
        else {
            throw SupabaseAccountError.missingAppleIDToken
        }

        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )
        } catch {
            throw SupabaseAccountError.appleSignInFailed(
                Self.appleSignInMessage(for: error)
            )
        }

        if let fullName = credential.fullName {
            let givenName = fullName.givenName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let middleName = fullName.middleName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let familyName = fullName.familyName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let displayName = [givenName, middleName, familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            if !displayName.isEmpty {
                try? await client.auth.update(
                    user: UserAttributes(
                        data: [
                            "full_name": .string(displayName),
                            "given_name": .string(givenName),
                            "family_name": .string(familyName)
                        ]
                    )
                )

                if let userID = currentUserID {
                    try? await client
                        .from("profiles")
                        .update(["display_name": displayName])
                        .eq("id", value: userID)
                        .execute()
                }
            }
        }

        return try await loadCurrentUser()
    }

    func signUp(
        email: String,
        password: String,
        firstName: String,
        lastName: String
    ) async throws -> EmailSignUpOutcome {
        let cleanFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [cleanFirstName, cleanLastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "full_name": .string(fullName),
                "given_name": .string(cleanFirstName),
                "family_name": .string(cleanLastName)
            ],
            redirectTo: Self.emailConfirmationURL
        )

        if response.session != nil {
            return .authenticated(try await loadCurrentUser())
        }

        return .confirmationRequired
    }

    func signIn(email: String, password: String) async throws -> BackendUserBootstrap {
        try await client.auth.signIn(
            email: email,
            password: password
        )
        return try await loadCurrentUser()
    }

    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(
            email,
            redirectTo: Self.passwordResetURL
        )
    }

    func updateRecoveredPassword(_ newPassword: String) async throws -> BackendUserBootstrap {
        try await client.auth.update(
            user: UserAttributes(password: newPassword)
        )
        passwordRecoveryPending = false
        return try await loadCurrentUser()
    }

    func handleAuthCallback(_ url: URL) async throws -> BackendUserBootstrap? {
        guard url.scheme?.lowercased() == "athlth",
              url.host?.lowercased() == "auth"
        else {
            return nil
        }

        _ = try await client.auth.session(from: url)

        if url.path == "/reset" {
            passwordRecoveryPending = true
            return nil
        }

        if url.path == "/confirm" {
            return try await loadCurrentUser()
        }

        return nil
    }

    func cancelPasswordRecovery() {
        passwordRecoveryPending = false
    }

    func signOut() async throws {
        try await client.auth.signOut()
        passwordRecoveryPending = false
    }

    func deleteAccount() async throws {
        guard currentUserID != nil else {
            throw SupabaseAccountError.notAuthenticated
        }

        let response: DeleteAccountResponse = try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(
                body: ["confirm": true]
            )
        )

        guard response.deleted else {
            throw SupabaseAccountError.accountDeletionFailed
        }

        try? await client.auth.signOut()
        passwordRecoveryPending = false
    }

    func restoreCurrentUser() async throws -> BackendUserBootstrap? {
        guard hasPersistedSession else { return nil }

        // Force Supabase to validate/refresh the stored session before
        // trusting locally persisted ATHLTH sign-in state.
        _ = try await client.auth.session

        guard currentUserID != nil else { return nil }
        return try await loadCurrentUser()
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

    func markOnboardingComplete() async throws {
        guard let userID = currentUserID else {
            throw SupabaseAccountError.notAuthenticated
        }

        try await client
            .from("profiles")
            .update([
                "onboarding_completed": "true",
                "onboarding_completed_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: userID)
            .execute()
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

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func appleSignInMessage(for error: Error) -> String {
        let technicalMessage = error.localizedDescription
        let lowered = technicalMessage.lowercased()

        if lowered.contains("audience") ||
            lowered.contains("client id") ||
            lowered.contains("client_id") {
            return "Apple sign-in is not configured for this ATHLTH app identifier."
        }

        if lowered.contains("nonce") {
            return "Apple sign-in verification failed. Please try again."
        }

        if lowered.contains("provider") {
            return "Apple sign-in is not fully configured on ATHLTH’s authentication service."
        }

        return "Apple sign-in failed: \(technicalMessage)"
    }

}

private struct DeleteAccountResponse: Decodable {
    let deleted: Bool
}

enum SupabaseAccountError: LocalizedError {
    case notAuthenticated
    case missingAppleNonce
    case missingAppleIDToken
    case invalidAppleCredential
    case accountDeletionFailed
    case appleSignInFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No authenticated ATHLTH user is available."
        case .missingAppleNonce:
            return "Apple sign-in could not be securely validated. Please try again."
        case .missingAppleIDToken:
            return "Apple did not return a valid sign-in token."
        case .invalidAppleCredential:
            return "Apple returned an invalid sign-in credential."
        case .accountDeletionFailed:
            return "ATHLTH could not confirm that your account was deleted. Please try again."
        case .appleSignInFailed(let message):
            return message
        }
    }
}
