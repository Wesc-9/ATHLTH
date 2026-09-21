import Foundation
import Supabase

protocol UsernameAvailabilityProviding {
    func isAvailable(_ username: String) async -> Bool
    func suggestions(for nameSeed: String) async -> [String]
    func claim(_ username: String) async throws
}

enum UsernameValidationState: Equatable {
    case idle
    case checking
    case available
    case taken
    case invalid

    var title: String? {
        switch self {
        case .idle: return nil
        case .checking: return "Checking availability…"
        case .available: return "Username is available"
        case .taken: return "Username is already taken"
        case .invalid: return "Use 3–20 characters: a–z, 0–9 or _"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .checking: return "hourglass"
        case .available: return "checkmark.circle.fill"
        case .taken, .invalid: return "xmark.circle.fill"
        }
    }
}


struct SupabaseUsernameAvailabilityService: UsernameAvailabilityProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func isAvailable(_ username: String) async -> Bool {
        guard UsernameGenerator.isValid(username) else { return false }

        do {
            let available: Bool = try await client
                .rpc(
                    "is_username_available",
                    params: ["candidate": username.lowercased()]
                )
                .execute()
                .value
            return available
        } catch {
            return false
        }
    }

    func suggestions(for nameSeed: String) async -> [String] {
        let base = UsernameGenerator.normalizedBase(from: nameSeed)
        var result: [String] = []

        for candidate in UsernameGenerator.candidatePool(for: base) {
            guard result.count < 3 else { break }
            guard await isAvailable(candidate) else { continue }
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }

        return result
    }

    func claim(_ username: String) async throws {
        let normalized = username.lowercased()
        guard await isAvailable(normalized) else {
            throw UsernameClaimError.unavailable
        }

        guard let userID = client.auth.currentUser?.id else {
            throw SupabaseAccountError.notAuthenticated
        }

        try await client
            .from("profiles")
            .update(["username": normalized])
            .eq("id", value: userID)
            .execute()
    }
}

actor MockUsernameAvailabilityService: UsernameAvailabilityProviding {
    private var claimed: Set<String> = [
        "admin",
        "support",
        "athlth",
        "official",
        "training"
    ]

    func isAvailable(_ username: String) async -> Bool {
        guard UsernameGenerator.isValid(username) else { return false }
        return !claimed.contains(username.lowercased())
    }

    func suggestions(for nameSeed: String) async -> [String] {
        let base = UsernameGenerator.normalizedBase(from: nameSeed)
        var result: [String] = []

        for candidate in UsernameGenerator.candidatePool(for: base) {
            guard result.count < 3 else { break }
            guard await isAvailable(candidate) else { continue }
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }

        return result
    }

    func claim(_ username: String) async throws {
        let normalized = username.lowercased()
        guard await isAvailable(normalized) else {
            throw UsernameClaimError.unavailable
        }
        claimed.insert(normalized)
    }
}

enum UsernameClaimError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "That username is no longer available."
    }
}

enum UsernameGenerator {
    static func hasValidCharacters(_ username: String) -> Bool {
        username.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            let isLowercaseASCII = value >= 97 && value <= 122
            let isNumber = value >= 48 && value <= 57
            return isLowercaseASCII || isNumber || scalar == "_"
        }
    }

    static func normalizedTypedUsername(_ value: String) -> String {
        let lowered = value.lowercased()
        let filtered = lowered.unicodeScalars.filter { scalar in
            let code = scalar.value
            let isLowercaseASCII = code >= 97 && code <= 122
            let isNumber = code >= 48 && code <= 57
            return isLowercaseASCII || isNumber || scalar == "_"
        }

        return String(String.UnicodeScalarView(filtered).prefix(20))
    }

    static func isValid(_ username: String) -> Bool {
        guard (3...20).contains(username.count) else { return false }
        return hasValidCharacters(username)
    }

    static func normalizedBase(from value: String) -> String {
        let latin = value
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)
            ?? value

        let identityPart = latin
            .split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)
            ?? latin

        let words = identityPart
            .split(whereSeparator: {
                $0.isWhitespace || $0 == "." || $0 == "-" || $0 == "_" || $0 == "+"
            })
            .map(String.init)

        let preferredWords: [String]
        if words.count >= 2 {
            preferredWords = [words.first!, words.last!]
        } else {
            preferredWords = words
        }

        let combined = preferredWords.joined()

        let ascii = combined
            .lowercased()
            .unicodeScalars
            .filter { scalar in
                let value = scalar.value
                return (value >= 97 && value <= 122) || (value >= 48 && value <= 57)
            }
            .map(String.init)
            .joined()

        let fallback = ascii.isEmpty ? "athlete" : ascii
        return String(fallback.prefix(12))
    }

    static func candidatePool(for base: String) -> [String] {
        let safeBase = normalizedBase(from: base)
        let startingNumber = numericSeed(for: safeBase)

        var numbered: [String] = []
        for offset in 0..<90 {
            let number = 10 + ((startingNumber - 10 + offset) % 90)
            numbered.append(String((safeBase + String(number)).prefix(20)))
        }

        let trainBase = String(safeBase.prefix(11))
        let trainingBase = String(safeBase.prefix(11))

        return [
            numbered.first ?? "\(safeBase)27",
            "trainwith\(trainBase)",
            "\(trainingBase)_training"
        ] + Array(numbered.dropFirst())
    }

    private static func numericSeed(for value: String) -> Int {
        let sum = value.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return 10 + (sum % 90)
    }
}
