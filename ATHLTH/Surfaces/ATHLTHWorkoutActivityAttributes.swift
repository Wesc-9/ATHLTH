import ActivityKit
import Foundation

struct ATHLTHWorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var workoutDisplayTitle: String? = nil
        var elapsedTime: TimeInterval
        var distanceMeters: Double
        var heartRate: Double
        var currentPaceSecondsPerKilometer: TimeInterval? = nil
        var routeProgressPercent: Double? = nil
        var routeRemainingMeters: Double? = nil
        var routeDeviationMeters: Double? = nil
        var routeDeviationThresholdMeters: Double? = nil

        var runningStepTitle: String? = nil
        var runningStepIndex: Int? = nil
        var runningStepCount: Int? = nil
        var runningStepProgress: Double? = nil
        var runningNextStepTitle: String? = nil
        var runningStepRemainingSeconds: TimeInterval? = nil
        var runningStepRemainingMeters: Double? = nil

        var heartRateTargetZone: Int? = nil
        var heartRateTargetMinimumBPM: Double? = nil
        var heartRateTargetMaximumBPM: Double? = nil
        var heartRateTargetStatus: String? = nil

        var ghostRaceTitle: String? = nil
        var ghostDistanceDeltaMeters: Double? = nil
        var ghostTimeDeltaSeconds: TimeInterval? = nil

        var strengthExerciseName: String? = nil
        var strengthSetIndex: Int? = nil
        var strengthSetCount: Int? = nil
        var strengthReps: Int? = nil
        var strengthWeightKilograms: Double? = nil
        var strengthRestEndsAt: Date? = nil
        var strengthNextExerciseName: String? = nil
        var strengthTimedSetTargetSeconds: Int? = nil
        var strengthTimedSetSecondsAtSnapshot: TimeInterval? = nil
        var strengthTimedSetResumedAt: Date? = nil

        /// Distinguishes run, walk, strength and generic workouts on lock screen.
        var workoutKindRaw: String? = nil

        var surfaceConfiguration:
            ATHLTHLiveWorkoutSurfaceConfiguration = .standard
        var liveContext:
            ATHLTHLiveWorkoutContext = .empty

        var updatedAt: Date
    }

    var workoutTitle: String
    var systemImage: String
    var startedAt: Date?
}
