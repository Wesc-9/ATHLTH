import Foundation

/// Shared pace rules for Watch, iPhone and mirrored workout surfaces.
/// Pace is always seconds per kilometer; distance is always meters.
enum ATHLTHRunningPace {
    /// Average pace requires real measured distance. It must never be inferred
    /// from GPS displacement during a treadmill workout.
    static func average(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double
    ) -> TimeInterval? {
        guard elapsedSeconds.isFinite, elapsedSeconds > 0,
              distanceMeters.isFinite, distanceMeters >= 20
        else { return nil }

        let pace = elapsedSeconds * 1_000 / distanceMeters
        return pace.isFinite && pace > 0 ? pace : nil
    }

    /// GPS speed is valid for outdoor workouts only. Indoor pace must use
    /// Watch distance, or a deliberately entered treadmill measurement.
    static func outdoorGPS(
        speedMetersPerSecond: Double,
        isOutdoor: Bool
    ) -> TimeInterval? {
        guard isOutdoor,
              speedMetersPerSecond.isFinite,
              speedMetersPerSecond >= 0.35
        else { return nil }

        let pace = 1_000 / speedMetersPerSecond
        guard pace.isFinite, (120...1_800).contains(pace)
        else { return nil }
        return pace
    }
}
