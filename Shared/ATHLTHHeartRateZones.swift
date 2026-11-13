import Foundation

/// Single range calculation for Training Plan and live workouts.
/// A zone is a target, never a claim that a pulse has been measured.
enum ATHLTHHeartRateZones {
    /// Shared free-run/plan/Ghost HRmax source. A configured maximum takes
    /// precedence; age estimate is a fallback, never a measured heart rate.
    static func resolvedMaximumBPM(
        configured: Int?,
        dateOfBirth: Date?,
        now: Date = Date(),
        usesFemaleEstimate: Bool = false
    ) -> Double? {
        if let configured, (100...240).contains(configured) {
            return Double(configured)
        }
        guard let dateOfBirth else { return nil }
        let age = Calendar.current.dateComponents(
            [.year], from: dateOfBirth, to: now
        ).year ?? 0
        guard (18...100).contains(age) else { return nil }
        return usesFemaleEstimate
            ? max(100, 206 - 0.88 * Double(age))
            : max(100, 208 - 0.7 * Double(age))
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

    /// Multi-zone prescription, e.g. Z1–Z2 = 50–70% HRmax.
    /// Values are rounded only after calculating the full continuous band.
    static func range(
        from firstZone: Int,
        through lastZone: Int,
        maximumBPM: Double?
    ) -> ClosedRange<Int>? {
        guard (1...5).contains(firstZone),
              (1...5).contains(lastZone), firstZone <= lastZone,
              let maximumBPM, maximumBPM.isFinite,
              (100...240).contains(maximumBPM)
        else { return nil }
        let low = 0.50 + 0.10 * Double(firstZone - 1)
        let high = 0.50 + 0.10 * Double(lastZone)
        let lowerBPM = Int((low * maximumBPM).rounded())
        let upperBPM = Int((min(1, high) * maximumBPM).rounded())
        return lowerBPM...upperBPM
    }

    static func range(
        fromPercent lower: Double?,
        toPercent upper: Double?,
        maximumBPM: Double?
    ) -> ClosedRange<Int>? {
        guard let lower, let upper,
              lower.isFinite, upper.isFinite,
              (30...100).contains(lower),
              (30...100).contains(upper), lower <= upper,
              let maximumBPM, maximumBPM.isFinite,
              (100...240).contains(maximumBPM)
        else { return nil }
        let lowerBPM = Int((maximumBPM * lower / 100).rounded())
        let upperBPM = Int((maximumBPM * upper / 100).rounded())
        return lowerBPM...upperBPM
    }

    static func matchingZones(
        for target: ClosedRange<Int>?,
        maximumBPM: Double?
    ) -> Set<Int> {
        guard let target else { return [] }
        return Set((1...5).filter { zone in
            guard let range = range(for: zone, maximumBPM: maximumBPM) else {
                return false
            }
            // A shared boundary (e.g. exactly 60%) is not sufficient.
            return target.lowerBound < range.upperBound &&
                   target.upperBound > range.lowerBound
        })
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
