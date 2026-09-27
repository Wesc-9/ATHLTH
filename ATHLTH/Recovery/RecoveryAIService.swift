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

private struct RecoveryAIRequest: Encodable {
    let mode: String
    let context: RecoveryAIContext
    let question: String?
}

private struct RecoveryAIInsightCacheEntry: Codable {
    let signature: String
    let createdAt: Date
    let insight: RecoveryAIInsight
}

private struct RecoveryAIAnswer: Decodable {
    let answer: String
}

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
        let signature = try contextSignature(context)
        let userScope =
            client.auth.currentUser?.id.uuidString
            ?? "signed-out"
        let cacheKey =
            "athlth.recoveryAIInsight.\(userScope)"

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
            return cached.insight
        }

        let insight: RecoveryAIInsight =
            try await client.functions.invoke(
                "recovery-sense",
                options: FunctionInvokeOptions(
                    body: RecoveryAIRequest(
                        mode: "insight",
                        context: context,
                        question: nil
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

    private func contextSignature(
        _ context: RecoveryAIContext
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(context)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func ask(
        _ question: String,
        context: RecoveryAIContext
    ) async throws -> String {
        let response: RecoveryAIAnswer =
            try await client.functions.invoke(
                "recovery-sense",
                options: FunctionInvokeOptions(
                    body: RecoveryAIRequest(
                        mode: "ask",
                        context: context,
                        question: question
                    )
                )
            )

        return response.answer
    }
}
