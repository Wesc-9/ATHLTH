import Foundation

/// Only deliberate workout-summary fields may leave the private training log.
/// Never send HealthKit pulse, zones, energy, medical notes or other raw
/// measurements to the social activity feed, regardless of old user defaults.
enum WorkoutFeedSafety {
    private static let allowedKeys: Set<String> = [
        "workout_id", "kind", "source", "effort", "caption",
        "duration_seconds", "distance_meters", "exercise_count",
        "volume_kg", "muscle_groups", "with_names", "with_count",
        "partner_count_selected", "route_preview", "hide_route_start_end"
    ]

    static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        var safe = metadata.filter { allowedKeys.contains($0.key) }
        // Compatibility with existing activity cards: the false flag is
        // explicit even when a previous post contained heart-rate data.
        safe["share_health_data"] = "false"
        return safe
    }
}
