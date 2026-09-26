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
        _ context: RecoveryAIContext
    ) async throws -> RecoveryAIInsight {
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
