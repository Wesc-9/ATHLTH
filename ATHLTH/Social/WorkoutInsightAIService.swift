import Foundation
import Supabase

private struct WorkoutAIInsightRequest: Encodable {
    let context: WorkoutAIInsightContext
}

private struct WorkoutAIInsightCacheEntry: Codable {
    let signature: String
    let insight: WorkoutAIInsight
}

final class WorkoutInsightAIService {
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

    func generate(
        workoutID: UUID,
        context: WorkoutAIInsightContext
    ) async throws -> WorkoutAIInsight {
        let signature =
            Self.signature(for: context)
        let key =
            "athlth.workoutInsight.\(workoutID.uuidString)"

        if let data = defaults.data(
            forKey: key
        ),
        let cached =
            try? JSONDecoder().decode(
                WorkoutAIInsightCacheEntry.self,
                from: data
            ),
        cached.signature == signature {
            return cached.insight
        }

        let response: WorkoutAIInsight =
            try await client.functions.invoke(
                "workout-insight",
                options: FunctionInvokeOptions(
                    body:
                        WorkoutAIInsightRequest(
                            context: context
                        )
                )
            )

        let entry =
            WorkoutAIInsightCacheEntry(
                signature: signature,
                insight: response
            )

        if let data =
            try? JSONEncoder().encode(entry) {
            defaults.set(
                data,
                forKey: key
            )
        }

        return response
    }

    private static func signature(
        for context: WorkoutAIInsightContext
    ) -> String {
        var parts: [String] = [
            context.activity,
            rounded(context.durationSeconds),
            rounded(context.distanceMeters),
            rounded(
                context.averageHeartRateBPM
            ),
            rounded(
                context.maxHeartRateBPM
            ),
            rounded(
                context.elevationGainMeters
            ),
            "\(context.routePointCount)"
        ]

        for segment in context.segments {
            parts.append(segment.label)
            parts.append(
                rounded(
                    segment.distanceMeters
                )
            )
            parts.append(
                rounded(
                    segment.elevationGainMeters
                )
            )
            parts.append(
                rounded(
                    segment.averageHeartRateBPM
                )
            )
            parts.append(
                rounded(
                    segment.paceSecondsPerKilometer
                )
            )
        }

        return parts.joined(
            separator: "|"
        )
    }

    private static func rounded(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "-"
        }

        return String(
            format: "%.2f",
            value
        )
    }
}
