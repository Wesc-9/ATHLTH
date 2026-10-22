import Foundation

/// Single range calculation for Training Plan and live workouts.
/// A zone is a target, never a claim that a pulse has been measured.
enum ATHLTHHeartRateZones {
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
