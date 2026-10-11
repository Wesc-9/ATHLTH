import Foundation

/// Sensor input validation for LIVE coach alerts; display and HealthKit
/// recording keep their existing independent behavior.
enum ATHLTHCoachSensorFreshness {
    static let maximumHeartRateAge: TimeInterval = 12
    static let maximumPaceAge: TimeInterval = 8
    static let maximumSnapshotAge: TimeInterval = 5

    static func isFresh(
        sampledAt: Date?,
        maximumAge: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard let sampledAt,
              maximumAge >= 0
        else { return false }
        let age = now.timeIntervalSince(sampledAt)
        return age >= -2 && age <= maximumAge
    }

    static func validHeartRate(
        _ value: Double,
        sampledAt: Date?,
        now: Date = Date()
    ) -> Bool {
        value.isFinite &&
        (30...240).contains(value) &&
        isFresh(
            sampledAt: sampledAt,
            maximumAge: maximumHeartRateAge,
            now: now
        )
    }

    static func validPace(
        _ secondsPerKilometer: TimeInterval?,
        sampledAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let pace = secondsPerKilometer else {
            return false
        }
        return pace.isFinite &&
            (120...1_800).contains(pace) &&
            isFresh(
                sampledAt: sampledAt,
                maximumAge: maximumPaceAge,
                now: now
            )
    }
}
