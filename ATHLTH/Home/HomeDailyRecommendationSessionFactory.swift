import Foundation

/// Build one real timed recipe for the existing iPhone/Watch workout engines.
/// No calendar or training-plan writes; recommendations are suggestions only.
enum HomeDailyRecommendationSessionFactory {
    static func make(
        advice: HomeDailyRecommendationPolicy.Advice
    ) -> PlannedSession? {
        guard let kind = advice.suggestedWorkout.kind,
              let minutes = advice.suggestedWorkout.durationMinutes,
              minutes > 0
        else { return nil }

        let walking = kind == .walking
        var workout = PlannedSession(
            id: UUID(),
            title: advice.suggestedTitle,
            kind: kind,
            scheduledStart: nil,
            durationMinutes: minutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: advice.suggestedDetail
        )
        workout.workoutBlocks = [
            WorkoutTemplateBlock(
                sequence: 1,
                kind: .run,
                title: advice.suggestedTitle,
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: Double(minutes * 60),
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: advice.suggestedDetail,
                phase: .main,
                targetHeartRateZone: nil,
                cardioActivity: walking ? .walking : .running
            )
        ]
        workout.workoutCategory = walking ? "walking" : "running"
        return workout
    }
}
