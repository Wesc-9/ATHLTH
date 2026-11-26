import Foundation

/// Only deliberate workout-summary fields may leave the private training log.
/// Never send HealthKit pulse, zones, energy, medical notes or other raw
/// measurements to the social activity feed, regardless of old user defaults.
enum WorkoutFeedSafety {
    private static let allowedKeys: Set<String> = [
        "workout_id", "kind", "source", "effort", "caption",
        "duration_seconds", "distance_meters", "exercise_count",
        "volume_kg", "muscle_groups", "with_names", "with_count",
        "partner_count_selected", "route_preview", "hide_route_start_end",
        "activity_subtype", "custom_workout_title"
    ]

    static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        var safe = metadata.filter { allowedKeys.contains($0.key) }
        // Compatibility with existing activity cards: the false flag is
        // explicit even when a previous post contained heart-rate data.
        safe["share_health_data"] = "false"
        return safe
    }
}


/// Only deliberate, shared workout posts appear on the owner profile.
enum ATHLTHProfilePublishedFeedPolicy {
    static func includes(_ activity: SocialActivityRecord, owner: UUID?) -> Bool {
        guard let owner else { return false }
        return activity.actorID == owner && activity.kind == "workout" &&
            ["friends", "public"].contains(activity.visibility)
    }

    static func items(_ items: [SocialFeedItem], owner: UUID?) -> [SocialFeedItem] {
        var seen = Set<UUID>()
        return items.filter {
            includes($0.activity, owner: owner) && $0.actor.userID == owner
        }.sorted {
            if $0.activity.createdAt == $1.activity.createdAt { return $0.id.uuidString > $1.id.uuidString }
            return $0.activity.createdAt > $1.activity.createdAt
        }.filter { seen.insert($0.id).inserted }
    }
}
