import Foundation

/// Single range calculation for Training Plan and live workouts.
/// A zone is a target, never a claim that a pulse has been measured.
enum ATHLTHHeartRateZones {
    /// Shared free-run/plan/Ghost HRmax source. A configured maximum takes
    /// precedence; age estimate is a fallback, never a measured heart rate.
    static func resolvedMaximumBPM(
        configured: Int?,
        dateOfBirth: Date?,
        now: Date = Date()
    ) -> Double? {
        if let configured, (100...240).contains(configured) {
            return Double(configured)
        }
        guard let dateOfBirth else { return nil }
        let age = Calendar.current.dateComponents(
            [.year], from: dateOfBirth, to: now
        ).year ?? 0
        guard (18...100).contains(age) else { return nil }
        return max(100, 208 - 0.7 * Double(age))
    }

    static func range(for zone: Int, maximumBPM: Double?) -> ClosedRange<Int>? {
        guard (1...5).contains(zone),
              let maximumBPM, maximumBPM.isFinite,
              (100...240).contains(maximumBPM)
        else { return nil }
        let lower = 0.50 + 0.10 * Double(zone - 1)
        let upper = min(lower + 0.10, 1)
        let lowerBPM = Int((maximumBPM * lower).rounded())
        let upperBPM = Int((maximumBPM * upper).rounded())
        return lowerBPM...upperBPM
    }

    /// Observed zone uses an actually measured heart rate and a valid
    /// athlete maximum. A planned target is never reused as a measurement.
    static func measuredZone(
        heartRateBPM: Double?,
        maximumBPM: Double?
    ) -> Int? {
        guard let heartRateBPM, heartRateBPM.isFinite,
              heartRateBPM > 0,
              let maximumBPM, maximumBPM.isFinite,
              (100...240).contains(maximumBPM)
        else { return nil }
        let fraction = heartRateBPM / maximumBPM
        guard fraction >= 0.50 else { return nil }
        return min(5, max(1, Int((fraction - 0.50) / 0.10) + 1))
    }
}
