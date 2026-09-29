import Foundation
import Supabase

private struct WorkoutHeroAIRequest: Encodable {
    struct Context: Encodable {
        let activity: String
        let durationSeconds: Double
        let distanceMeters: Double?
        let elevationGainMeters: Double?
        let routePointCount: Int
        let startHour: Int
    }

    let context: Context
}

private struct WorkoutHeroAIResponse: Decodable {
    let recipe: WorkoutVisualRecipe
    let generatedByGroq: Bool?
}

private struct WorkoutHeroAICacheEntry: Codable {
    let signature: String
    let recipe: WorkoutVisualRecipe
}

final class WorkoutHeroAIService {
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
        workout: SocialPublishableWorkout,
        elevationGainMeters: Double?,
        routePointCount: Int
    ) async throws -> WorkoutVisualRecipe {
        let startHour =
            Calendar.current.component(
                .hour,
                from: workout.startDate
            )

        let context =
            WorkoutHeroAIRequest.Context(
                activity: workout.activity.rawValue,
                durationSeconds: workout.duration,
                distanceMeters: workout.distanceMeters,
                elevationGainMeters:
                    elevationGainMeters,
                routePointCount: routePointCount,
                startHour: startHour
            )

        let signature =
            Self.signature(for: context)

        let userScope =
            client.auth.currentUser?.id.uuidString ??
            "signed-out"

        let key =
            "athlth.workoutHero.\(userScope).\(workout.id.uuidString)"

        if let data =
                defaults.data(forKey: key),
           let cached =
                try? JSONDecoder().decode(
                    WorkoutHeroAICacheEntry.self,
                    from: data
                ),
           cached.signature == signature {
            return cached.recipe
        }

        let response: WorkoutHeroAIResponse =
            try await client.functions.invoke(
                "workout-hero",
                options: FunctionInvokeOptions(
                    body: WorkoutHeroAIRequest(
                        context: context
                    )
                )
            )

        let entry =
            WorkoutHeroAICacheEntry(
                signature: signature,
                recipe: response.recipe
            )

        if let data =
            try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: key)
        }

        return response.recipe
    }

    private static func signature(
        for context: WorkoutHeroAIRequest.Context
    ) -> String {
        [
            context.activity,
            rounded(context.durationSeconds),
            rounded(context.distanceMeters),
            rounded(context.elevationGainMeters),
            "\(context.routePointCount)",
            "\(context.startHour)"
        ]
        .joined(separator: "|")
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
