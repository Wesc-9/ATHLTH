import Foundation
import Supabase

struct TrophyInscription: Codable, Hashable {
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

private struct TrophyInscriptionRequest:
    Encodable
{
    let trophyID: String
    let username: String
    let achievementTitle: String
    let achievementDetail: String
    let unlockedAt: String?
    let language: String
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
    ) async -> TrophyInscription {
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
            return fallback
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
                "v2",
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
        cached.achievementTitle ==
            achievementTitle {
            return cached.inscription
        }

        let formatter =
            ISO8601DateFormatter()
        let request =
            TrophyInscriptionRequest(
                trophyID: trophyID,
                username: cleanUsername,
                achievementTitle:
                    achievementTitle,
                achievementDetail:
                    achievementDetail,
                unlockedAt:
                    unlockedAt.map {
                        formatter.string(
                            from: $0
                        )
                    },
                language: language
            )

        do {
            let generated:
                TrophyInscription =
                try await client
                    .functions
                    .invoke(
                        "generate-trophy-inscription",
                        options:
                            FunctionInvokeOptions(
                                body: request
                            )
                    )

            let normalized =
                TrophyInscription(
                    athlete:
                        clipped(
                            generated
                                .athlete,
                            maximum: 24
                        )
                        .uppercased(),
                    achievement:
                        clipped(
                            generated
                                .achievement,
                            maximum: 28
                        )
                        .uppercased(),
                    inscription:
                        clipped(
                            generated
                                .inscription,
                            maximum: 48
                        )
                        .uppercased()
                )

            if let data =
                try? JSONEncoder()
                    .encode(
                        TrophyInscriptionCacheEntry(
                            username:
                                normalized
                                    .athlete,
                            achievementTitle:
                                achievementTitle,
                            inscription:
                                normalized
                        )
                    ) {
                defaults.set(
                    data,
                    forKey: cacheKey
                )
            }

            return normalized
        } catch {
            // The trophy must always render even if AI is offline.
            // A later visit can retry because fallbacks are not cached.
            return fallback
        }
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
