import Foundation
import Supabase

struct TrophyInscription: Codable, Hashable {
    static let currentVersion = 1

    let athlete: String
    let achievement: String
    let inscription: String

    static func fallback(
        username: String,
        achievement: String
    ) -> TrophyInscription {
        TrophyInscription(
            athlete: username.uppercased(),
            achievement: achievement.uppercased(),
            inscription:
                ATHLTHLocalization.choose(
                    english: "VERIFIED PERFORMANCE",
                    norwegian: "VERIFISERT PRESTASJON"
                )
                .uppercased()
        )
    }
}

struct TrophyInscriptionResolution {
    let inscription: TrophyInscription
    let isPersisted: Bool
}

private struct TrophyInscriptionCacheEntry:
    Codable
{
    let username: String
    let achievementTitle: String
    let inscription: TrophyInscription
}

@MainActor
final class TrophyInscriptionAIService {
    static let shared =
        TrophyInscriptionAIService()

    private let client: SupabaseClient
    private let defaults: UserDefaults

    init(
        client: SupabaseClient =
            SupabaseEnvironment.client,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
    }

    func inscription(
        trophyID: String,
        username: String,
        achievementTitle: String,
        achievementDetail: String,
        unlockedAt: Date?
    ) async -> TrophyInscriptionResolution {
        let cleanUsername =
            sanitizedUsername(username)
        let fallback =
            TrophyInscription.fallback(
                username: cleanUsername,
                achievement:
                    achievementTitle
            )

        guard PrestigeTrophyCatalog
            .isPrestigeTrophy(trophyID)
        else {
            return TrophyInscriptionResolution(
                inscription: fallback,
                isPersisted: false
            )
        }

        let language =
            ATHLTHLocalization.isNorwegian
                ? "nb"
                : "en"
        let userScope =
            client.auth.currentUser?
                .id.uuidString ??
            "signed-out"
        let cacheKey =
            [
                "athlth",
                "trophyInscription",
                "v\(TrophyInscription.currentVersion)",
                userScope,
                trophyID,
                language
            ]
            .joined(separator: ".")

        if let data = defaults.data(
            forKey: cacheKey
        ),
        let cached =
            try? JSONDecoder().decode(
                TrophyInscriptionCacheEntry.self,
                from: data
            ),
        cached.achievementTitle == achievementTitle,
        cached.username == cleanUsername.uppercased() {
            return TrophyInscriptionResolution(
                inscription: cached.inscription,
                isPersisted: true
            )
        }

        // Only two generic, approved inscriptions reach the local model.
        // Username, achievement details and dates are never sent to AI.
        let options = [fallback.inscription, ATHLTHLocalization.choose(
            english: "EARNED THROUGH DEDICATION", norwegian: "FORTJENT GJENNOM INNSATS")]
        let wording = (try? await ATHLTHIntelligenceEngine.privateWording(
            feature: .trophyInscription, options: options)) ?? fallback.inscription
        let normalized = TrophyInscription(
            athlete: clipped(cleanUsername, maximum: 24).uppercased(),
            achievement: clipped(achievementTitle, maximum: 28).uppercased(),
            inscription: clipped(wording, maximum: 48).uppercased())
        guard !Task.isCancelled,
              (client.auth.currentUser?.id.uuidString ?? "signed-out") == userScope else {
            return TrophyInscriptionResolution(inscription: fallback, isPersisted: false)
        }
        if let data = try? JSONEncoder().encode(TrophyInscriptionCacheEntry(
            username: normalized.athlete, achievementTitle: achievementTitle, inscription: normalized)) {
            defaults.set(data, forKey: cacheKey)
            return TrophyInscriptionResolution(inscription: normalized, isPersisted: true)
        }
        return TrophyInscriptionResolution(inscription: normalized, isPersisted: false)
    }

    private func sanitizedUsername(
        _ value: String
    ) -> String {
        let clean =
            value
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        if clean.isEmpty {
            return "ATHLTH ATHLETE"
        }

        return clipped(
            clean,
            maximum: 24
        )
    }

    private func clipped(
        _ value: String,
        maximum: Int
    ) -> String {
        let clean =
            value
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        return String(
            clean.prefix(maximum)
        )
    }
}
