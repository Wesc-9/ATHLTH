import Foundation
import Supabase

private struct WorkoutHeroImageRequest: Encodable {
    struct Context: Encodable {
        let activity: String
        let durationSeconds: Double
        let distanceMeters: Double?
        let elevationGainMeters: Double?
        let routePointCount: Int
        let startHour: Int
    }

    let workoutId: String
    let context: Context
    let recipe: WorkoutVisualRecipe
}

private struct WorkoutHeroImageResponse: Decodable {
    let status: String
    let imageURL: String?
}

final class WorkoutHeroImageService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func imageURL(
        workout: SocialPublishableWorkout,
        recipe: WorkoutVisualRecipe,
        elevationGainMeters: Double?,
        routePointCount: Int
    ) async throws -> URL? {
        let request = WorkoutHeroImageRequest(
            workoutId: workout.id.uuidString,
            context: WorkoutHeroImageRequest.Context(
                activity: workout.activity.rawValue,
                durationSeconds: workout.duration,
                distanceMeters: workout.distanceMeters,
                elevationGainMeters: elevationGainMeters,
                routePointCount: routePointCount,
                startHour: Calendar.current.component(
                    .hour,
                    from: workout.startDate
                )
            ),
            recipe: recipe
        )

        let response: WorkoutHeroImageResponse =
            try await client.functions.invoke(
                "generate-workout-hero-image",
                options: FunctionInvokeOptions(body: request)
            )

        guard response.status == "ready",
              let imageURL = response.imageURL
        else {
            return nil
        }

        return URL(string: imageURL)
    }
}
