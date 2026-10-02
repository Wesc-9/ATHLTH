import Foundation
import Supabase

struct TrophyCloudState {
    let unlocks: [TrophyUnlockRecord]
    let inscriptions:
        [String: TrophyInscription]
    let showcaseIDs: [String]
    let cabinetUpdatedAt: Date?
}

private struct TrophyCloudRequest:
    Encodable
{
    let operation: String
    let username: String?
    let unlocks: [TrophyCloudUnlockWrite]?
    let trophyID: String?
    let evidence: PrestigeRunEvidenceWrite?
    let showcaseIDs: [String]?

    enum CodingKeys:
        String,
        CodingKey
    {
        case operation
        case username
        case unlocks
        case trophyID = "trophy_id"
        case evidence
        case showcaseIDs =
            "showcase_ids"
    }
}

private struct TrophyCloudResponse:
    Decodable
{
    let unlocks: [TrophyCloudUnlockRow]?
    let showcaseIDs: [String]?
    let cabinetUpdatedAt: Date?
    let unlock: TrophyCloudUnlockRow?

    enum CodingKeys:
        String,
        CodingKey
    {
        case unlocks
        case showcaseIDs =
            "showcase_ids"
        case cabinetUpdatedAt =
            "cabinet_updated_at"
        case unlock
    }
}

private struct TrophyCloudUnlockWrite:
    Encodable
{
    let stageKey: String
    let awardID: String
    let awardClass: String
    let stageTitle: String
    let title: String
    let rarity: String
    let category: String
    let verificationSource: String
    let systemImage: String
    let unlockedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case stageKey = "stage_key"
        case awardID = "award_id"
        case awardClass =
            "award_class"
        case stageTitle =
            "stage_title"
        case title
        case rarity
        case category
        case verificationSource =
            "verification_source"
        case systemImage =
            "system_image"
        case unlockedAt =
            "unlocked_at"
    }
}

private struct PrestigeRunEvidenceWrite:
    Encodable
{
    let workoutID: UUID
    let activityType: String
    let distanceMeters: Double
    let durationSeconds: Double
    let startedAt: Date
    let endedAt: Date
    let sourceBundleIdentifier: String
    let sourceName: String
    let isIndoor: Bool?
    let wasUserEntered: Bool

    init(
        evidence:
            PrestigeRunEvidence
    ) {
        workoutID =
            evidence.workoutID
        activityType = "running"
        distanceMeters =
            evidence.distanceMeters
        durationSeconds =
            evidence.durationSeconds
        startedAt =
            evidence.startedAt
        endedAt =
            evidence.endedAt
        sourceBundleIdentifier =
            evidence
                .sourceBundleIdentifier
        sourceName =
            evidence.sourceName
        isIndoor =
            evidence.isIndoor
        wasUserEntered =
            evidence.wasUserEntered
    }

    enum CodingKeys:
        String,
        CodingKey
    {
        case workoutID =
            "workout_id"
        case activityType =
            "activity_type"
        case distanceMeters =
            "distance_meters"
        case durationSeconds =
            "duration_seconds"
        case startedAt =
            "started_at"
        case endedAt =
            "ended_at"
        case sourceBundleIdentifier =
            "source_bundle_identifier"
        case sourceName =
            "source_name"
        case isIndoor =
            "is_indoor"
        case wasUserEntered =
            "was_user_entered"
    }
}

private struct TrophyCloudUnlockRow:
    Decodable
{
    let stageKey: String
    let awardID: String
    let stageTitle: String
    let title: String
    let rarity: String
    let category: String
    let verificationSource: String
    let unlockedAt: Date
    let usernameAtUnlock: String?
    let engravingAchievement: String?
    let engravingText: String?
    let engravingVersion: Int?

    enum CodingKeys:
        String,
        CodingKey
    {
        case stageKey = "stage_key"
        case awardID = "award_id"
        case stageTitle =
            "stage_title"
        case title
        case rarity
        case category
        case verificationSource =
            "verification_source"
        case unlockedAt =
            "unlocked_at"
        case usernameAtUnlock =
            "username_at_unlock"
        case engravingAchievement =
            "engraving_achievement"
        case engravingText =
            "engraving_text"
        case engravingVersion =
            "engraving_version"
    }

    var inscription:
        TrophyInscription?
    {
        guard
            let athlete =
                usernameAtUnlock?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
            !athlete.isEmpty,
            let achievement =
                engravingAchievement?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
            !achievement.isEmpty,
            let text =
                engravingText?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
            !text.isEmpty
        else {
            return nil
        }

        return TrophyInscription(
            athlete: athlete,
            achievement:
                achievement,
            inscription: text
        )
    }

    var localRecord:
        TrophyUnlockRecord?
    {
        guard
            let rarity =
                Self.rarity(
                    rarity
                ),
            let category =
                TrophyCategory(
                    rawValue:
                        category
                ),
            let source =
                TrophyVerificationSource(
                    rawValue:
                        verificationSource
                )
        else {
            return nil
        }

        return TrophyUnlockRecord(
            stageKey: stageKey,
            trophyID: awardID,
            stageTitle:
                stageTitle,
            title: title,
            rarity: rarity,
            category: category,
            verificationSource:
                source,
            unlockedAt:
                unlockedAt
        )
    }

    private static func rarity(
        _ value: String
    ) -> TrophyRarity? {
        switch value
            .lowercased() {
        case "core":
            return .core
        case "rare":
            return .rare
        case "epic":
            return .epic
        case "signature":
            return .signature
        default:
            return nil
        }
    }
}

@MainActor
final class TrophyCloudService
{
    private let client:
        SupabaseClient

    init(
        client:
            SupabaseClient =
                SupabaseEnvironment
                    .client
    ) {
        self.client = client
    }

    func loadState()
        async throws ->
        TrophyCloudState
    {
        let response:
            TrophyCloudResponse =
            try await invoke(
                TrophyCloudRequest(
                    operation: "load",
                    username: nil,
                    unlocks: nil,
                    trophyID: nil,
                    evidence: nil,
                    showcaseIDs: nil
                )
            )

        let rows =
            response.unlocks ?? []
        var inscriptions:
            [String: TrophyInscription] =
            [:]

        for row in rows {
            if let inscription =
                    row.inscription {
                inscriptions[
                    row.awardID
                ] = inscription
            }
        }

        return TrophyCloudState(
            unlocks:
                rows.compactMap(
                    \.localRecord
                ),
            inscriptions:
                inscriptions,
            showcaseIDs:
                response
                    .showcaseIDs ??
                [],
            cabinetUpdatedAt:
                response
                    .cabinetUpdatedAt
        )
    }

    func syncAchievements(
        _ records:
            [TrophyUnlockRecord],
        trophies:
            [TrophyProgressItem],
        username: String?
    ) async throws {
        let images =
            Dictionary(
                uniqueKeysWithValues:
                    trophies.map {
                        (
                            $0.id,
                            $0.systemImage
                        )
                    }
            )

        let payload =
            records
                .filter {
                    !$0.isPrestigeTrophy
                }
                .map {
                    TrophyCloudUnlockWrite(
                        stageKey:
                            $0.stageKey,
                        awardID:
                            $0.trophyID,
                        awardClass:
                            "achievement",
                        stageTitle:
                            $0.stageTitle,
                        title:
                            $0.title,
                        rarity:
                            Self.rarityKey(
                                $0.rarity
                            ),
                        category:
                            $0.category
                                .rawValue,
                        verificationSource:
                            $0
                                .verificationSource
                                .rawValue,
                        systemImage:
                            images[
                                $0.trophyID
                            ] ??
                            "medal.fill",
                        unlockedAt:
                            $0.unlockedAt
                    )
                }

        guard !payload.isEmpty
        else {
            return
        }

        let _: TrophyCloudResponse =
            try await invoke(
                TrophyCloudRequest(
                    operation:
                        "sync_achievements",
                    username:
                        username,
                    unlocks:
                        payload,
                    trophyID: nil,
                    evidence: nil,
                    showcaseIDs: nil
                )
            )
    }

    func claimPrestigeTrophy(
        trophyID: String,
        evidence:
            PrestigeRunEvidence,
        username: String?
    ) async throws ->
        TrophyUnlockRecord?
    {
        let response:
            TrophyCloudResponse =
            try await invoke(
                TrophyCloudRequest(
                    operation:
                        "claim_prestige",
                    username:
                        username,
                    unlocks: nil,
                    trophyID:
                        trophyID,
                    evidence:
                        PrestigeRunEvidenceWrite(
                            evidence:
                                evidence
                        ),
                    showcaseIDs: nil
                )
            )

        return response
            .unlock?
            .localRecord
    }

    func saveCabinet(
        _ showcaseIDs:
            [String]
    ) async throws ->
        Date?
    {
        let response:
            TrophyCloudResponse =
            try await invoke(
                TrophyCloudRequest(
                    operation:
                        "save_cabinet",
                    username: nil,
                    unlocks: nil,
                    trophyID: nil,
                    evidence: nil,
                    showcaseIDs:
                        Array(
                            showcaseIDs
                                .prefix(4)
                        )
                )
            )

        return response
            .cabinetUpdatedAt
    }

    private func invoke(
        _ request:
            TrophyCloudRequest
    ) async throws ->
        TrophyCloudResponse
    {
        try await client
            .functions
            .invoke(
                "sync-trophy-state",
                options:
                    FunctionInvokeOptions(
                        body: request
                    )
            )
    }

    private static func rarityKey(
        _ rarity:
            TrophyRarity
    ) -> String {
        switch rarity {
        case .core:
            return "core"
        case .rare:
            return "rare"
        case .epic:
            return "epic"
        case .signature:
            return "signature"
        }
    }
}
