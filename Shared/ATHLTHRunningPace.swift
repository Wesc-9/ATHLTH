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

    /// A treadmill speed entered by the athlete is an estimate, not Watch
    /// distance or outdoor GPS. Reuse the running unit conversion in Strength.
    static func manuallyEstimatedTreadmillDistance(
        speedKilometersPerHour: Double,
        durationSeconds: TimeInterval
    ) -> Double? {
        guard speedKilometersPerHour.isFinite,
              (0.1...30).contains(speedKilometersPerHour),
              durationSeconds.isFinite,
              durationSeconds > 0 else { return nil }
        return speedKilometersPerHour * durationSeconds / 3.6
    }

    static func paceForManualTreadmillSpeed(
        kilometersPerHour: Double
    ) -> TimeInterval? {
        guard kilometersPerHour.isFinite, kilometersPerHour > 0 else { return nil }
        return 3_600 / kilometersPerHour
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
