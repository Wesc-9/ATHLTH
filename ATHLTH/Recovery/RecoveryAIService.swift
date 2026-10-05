import CryptoKit
import Foundation
import Supabase

struct RecoveryAIMuscleInput: Codable, Hashable {
    let name: String
    let recoveryPercent: Int
    let status: String
    let completedSets: Int
}

struct RecoveryAICheckIn: Codable, Hashable {
    let energy: Int?
    let stress: Int?
    let overallSoreness: Int?
    let motivation: Int?
}

struct RecoveryAIContext: Codable, Hashable {
    let recoveryScore: Int?
    let recoveryState: String
    let recoveryDetail: String
    let sleepSeconds: Double?
    let baselineSleepSeconds: Double?
    let hrvMilliseconds: Double?
    let baselineHRVMilliseconds: Double?
    let restingHeartRate: Double?
    let baselineRestingHeartRate: Double?
    let yesterdayTrainingMinutes: Double
    let acuteTrainingMinutes: Double
    let chronicWeeklyAverageMinutes: Double?
    let muscles: [RecoveryAIMuscleInput]
    let checkIn: RecoveryAICheckIn
}

struct RecoveryAIFactor: Codable, Hashable, Identifiable {
    var id: String { title + detail }

    let title: String
    let detail: String
    let impact: String
}

struct RecoveryAISuggestion: Codable, Hashable {
    let title: String
    let subtitle: String
    let reason: String
}

struct RecoveryAIInsight: Codable, Hashable {
    let headline: String
    let summary: String
    let factors: [RecoveryAIFactor]
    let suggestion: RecoveryAISuggestion
    let quickQuestions: [String]
}

enum RecoveryCoachMessageRole:
    String,
    Codable,
    Hashable {
    case user
    case assistant
}

struct RecoveryCoachMessage:
    Identifiable,
    Codable,
    Hashable {
    let id: UUID
    let role: RecoveryCoachMessageRole
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: RecoveryCoachMessageRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct RecoveryCoachReply: Hashable {
    let answer: String
    let quickQuestions: [String]
}

struct RecoveryCoachConversationState:
    Codable,
    Hashable {
    var messages: [RecoveryCoachMessage]
    var quickQuestions: [String]
    var contextSignature: String?
}

private struct RecoveryAIChatTurn: Encodable {
    let role: String
    let content: String
}

private struct RecoveryAIRequest: Encodable {
    let mode: String
    let context: RecoveryAIContext
    let question: String?
    let language: String
    let history: [RecoveryAIChatTurn]?
}

private struct RecoveryAIInsightCacheEntry: Codable {
    let signature: String
    let createdAt: Date
    let insight: RecoveryAIInsight
}

private struct RecoveryAICacheMuscle: Codable {
    let name: String
    let completedSets: Int
}

private struct RecoveryAICacheSignature: Codable {
    let recoveryScore: Int?
    let recoveryState: String
    let sleepSeconds: Double?
    let baselineSleepSeconds: Double?
    let hrvMilliseconds: Double?
    let baselineHRVMilliseconds: Double?
    let restingHeartRate: Double?
    let baselineRestingHeartRate: Double?
    let yesterdayTrainingMinutes: Double
    let acuteTrainingMinutes: Double
    let chronicWeeklyAverageMinutes: Double?
    let muscles: [RecoveryAICacheMuscle]
    let checkIn: RecoveryAICheckIn
}

private struct RecoveryAIAnswer: Decodable {
    let answer: String
    let quickQuestions: [String]?
}

enum RecoveryCoachConversationPersistence {
    private static let maxStoredMessages = 200

    static func load(
        userID: UUID
    ) -> RecoveryCoachConversationState? {
        let url = conversationURL(
            userID: userID
        )

        guard let data =
                try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? JSONDecoder().decode(
            RecoveryCoachConversationState.self,
            from: data
        )
    }

    static func save(
        _ state: RecoveryCoachConversationState,
        userID: UUID
    ) {
        let trimmed =
            RecoveryCoachConversationState(
                messages:
                    Array(
                        state.messages
                            .suffix(
                                maxStoredMessages
                            )
                    ),
                quickQuestions:
                    Array(
                        state.quickQuestions
                            .prefix(3)
                    ),
                contextSignature:
                    state.contextSignature
            )

        guard let data =
                try? JSONEncoder()
                    .encode(trimmed)
        else {
            return
        }

        let url =
            conversationURL(
                userID: userID
            )

        do {
            try FileManager.default
                .createDirectory(
                    at:
                        url
                            .deletingLastPathComponent(),
                    withIntermediateDirectories:
                        true
                )
            try data.write(
                to: url,
                options: .atomic
            )
        } catch {
            return
        }
    }

    private static func conversationURL(
        userID: UUID
    ) -> URL {
        let language =
            ATHLTHLocalization.isNorwegian
                ? "nb"
                : "en"

        let directory =
            FileManager.default
                .urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )
                .first ??
            URL(
                fileURLWithPath:
                    NSTemporaryDirectory(),
                isDirectory: true
            )

        return directory
            .appendingPathComponent(
                "ATHLTH",
                isDirectory: true
            )
            .appendingPathComponent(
                "recovery-coach-(userID.uuidString)-(language).json",
                isDirectory: false
            )
    }
}

@MainActor
final class RecoveryAIService {
    private let client: SupabaseClient

    init(
        client: SupabaseClient = SupabaseEnvironment.client
    ) {
        self.client = client
    }

    func generate(
        _ context: RecoveryAIContext,
        bypassCache: Bool = false
    ) async throws -> RecoveryAIInsight {
        let signature =
            try Self.cacheSignature(
                for: context
            )
        let userScope =
            client.auth.currentUser?.id.uuidString
            ?? "signed-out"
        let language =
            ATHLTHLocalization.isNorwegian
                ? "nb"
                : "en"
        let cacheKey =
            "athlth.recoveryAIInsight.\(userScope).\(language)"

        if !bypassCache,
           let data = UserDefaults.standard.data(
               forKey: cacheKey
           ),
           let cached = try? JSONDecoder().decode(
               RecoveryAIInsightCacheEntry.self,
               from: data
           ),
           cached.signature == signature,
           Date().timeIntervalSince(cached.createdAt) <
                6 * 60 * 60 {
            ATHLTHPerformance.event(
                "RecoveryAICacheHit"
            )
            return cached.insight
        }

        ATHLTHPerformance.event(
            "RecoveryAICacheMiss"
        )

        let insight: RecoveryAIInsight =
            try await client.functions.invoke(
                "recovery-sense",
                options: FunctionInvokeOptions(
                    body: RecoveryAIRequest(
                        mode: "insight",
                        context: context,
                        question: nil,
                        language:
                            ATHLTHLocalization.isNorwegian
                                ? "nb"
                                : "en",
                        history: nil
                    )
                )
            )

        if let data = try? JSONEncoder().encode(
            RecoveryAIInsightCacheEntry(
                signature: signature,
                createdAt: Date(),
                insight: insight
            )
        ) {
            UserDefaults.standard.set(
                data,
                forKey: cacheKey
            )
        }

        return insight
    }

    static func cacheSignature(
        for context: RecoveryAIContext
    ) throws -> String {
        // Passive time progression must not invalidate the six-hour cache.
        // Muscle recovery percentage/status are time-derived, so the cache
        // key keeps only muscle identity + completed load. New Health data,
        // new workouts and new check-ins still change the signature.
        let stableContext =
            RecoveryAICacheSignature(
                recoveryScore:
                    context.recoveryScore,
                recoveryState:
                    context.recoveryState,
                sleepSeconds:
                    context.sleepSeconds,
                baselineSleepSeconds:
                    context.baselineSleepSeconds,
                hrvMilliseconds:
                    context.hrvMilliseconds,
                baselineHRVMilliseconds:
                    context.baselineHRVMilliseconds,
                restingHeartRate:
                    context.restingHeartRate,
                baselineRestingHeartRate:
                    context.baselineRestingHeartRate,
                yesterdayTrainingMinutes:
                    context.yesterdayTrainingMinutes,
                acuteTrainingMinutes:
                    context.acuteTrainingMinutes,
                chronicWeeklyAverageMinutes:
                    context.chronicWeeklyAverageMinutes,
                muscles:
                    context.muscles.map {
                        RecoveryAICacheMuscle(
                            name: $0.name,
                            completedSets:
                                $0.completedSets
                        )
                    },
                checkIn:
                    context.checkIn
            )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data =
            try encoder.encode(
                stableContext
            )
        return SHA256.hash(data: data)
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
    }

    func ask(
        _ question: String,
        context: RecoveryAIContext,
        history: [RecoveryCoachMessage]
    ) async throws -> RecoveryCoachReply {
        let requestHistory =
            history
                .suffix(16)
                .map {
                    RecoveryAIChatTurn(
                        role:
                            $0.role.rawValue,
                        content:
                            String(
                                $0.text
                                    .prefix(1800)
                            )
                    )
                }

        let response: RecoveryAIAnswer =
            try await client.functions.invoke(
                "recovery-sense",
                options: FunctionInvokeOptions(
                    body: RecoveryAIRequest(
                        mode: "ask",
                        context: context,
                        question: question,
                        language:
                            ATHLTHLocalization.isNorwegian
                                ? "nb"
                                : "en",
                        history:
                            requestHistory.isEmpty
                                ? nil
                                : requestHistory
                    )
                )
            )

        return RecoveryCoachReply(
            answer: response.answer,
            quickQuestions:
                Array(
                    (
                        response.quickQuestions ??
                        []
                    )
                    .filter {
                        !$0
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                    }
                    .prefix(3)
                )
        )
    }
}
