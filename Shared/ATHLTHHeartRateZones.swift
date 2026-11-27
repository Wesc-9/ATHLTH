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


/// Exact per-workout HealthKit zone boundaries; never derive a historical
/// Apple zone from today's max heart rate or assume every group has five zones.
struct ATHLTHRecordedHeartRateZone: Codable, Hashable, Identifiable {
    let index: Int
    let minimumBPM: Double?
    let maximumBPM: Double?
    let durationSeconds: TimeInterval
    var id: Int { index }

    var isValid: Bool {
        index >= 0 && durationSeconds.isFinite && durationSeconds >= 0 &&
        (minimumBPM.map { $0.isFinite && $0 >= 0 } ?? true) &&
        (maximumBPM.map { $0.isFinite && $0 > (minimumBPM ?? 0) } ?? true)
    }
}

enum ATHLTHRecordedHeartRateZones {
    static func validated(_ zones: [ATHLTHRecordedHeartRateZone]) -> [ATHLTHRecordedHeartRateZone]? {
        let sorted = zones.sorted { $0.index < $1.index }
        guard (3...9).contains(sorted.count),
              sorted.enumerated().allSatisfy({ $0.offset == $0.element.index && $0.element.isValid }),
              sorted.first?.minimumBPM == nil || sorted.first?.minimumBPM == 0,
              sorted.last?.maximumBPM == nil
        else { return nil }
        for (lower, upper) in zip(sorted, sorted.dropFirst()) {
            guard let boundary = lower.maximumBPM, upper.minimumBPM == boundary else { return nil }
        }
        return sorted
    }

    static func zone(for bpm: Double, in zones: [ATHLTHRecordedHeartRateZone]) -> Int? {
        guard bpm.isFinite, bpm > 0, let zones = validated(zones) else { return nil }
        return zones.first(where: {
            bpm >= ($0.minimumBPM ?? 0) && bpm < ($0.maximumBPM ?? .infinity)
        }).map { $0.index + 1 }
    }
}


/// The recorder supplies the actual Apple boundaries. Existing authored
/// zone targets and coach rules retain their current semantics.
enum ATHLTHLiveZonePolicy {
    static func prefersApple(hasStructuredWorkout: Bool, hasTarget: Bool, coachEnabled: Bool) -> Bool {
        !hasStructuredWorkout && !hasTarget && !coachEnabled
    }

    static func measuredZone(bpm: Double?, maximumBPM: Double?, appleZones: [ATHLTHRecordedHeartRateZone]?) -> Int? {
        if let appleZones, let valid = ATHLTHRecordedHeartRateZones.validated(appleZones) {
            guard let bpm else { return nil }
            return ATHLTHRecordedHeartRateZones.zone(for: bpm, in: valid)
        }
        return ATHLTHHeartRateZones.measuredZone(heartRateBPM: bpm, maximumBPM: maximumBPM)
    }

    /// Preserve the existing five-zone scale, with an extra below-Z1
    /// bucket because HealthKit zones must cover the entire range.
    static func authoredBoundaries(maximumBPM: Double?) -> [Double]? {
        guard let maximumBPM, maximumBPM.isFinite,
              (100...240).contains(maximumBPM) else { return nil }
        return [0.5, 0.6, 0.7, 0.8, 0.9].map { maximumBPM * $0 }
    }

    static func recordedLabel(index: Int, authored: Bool) -> String {
        if authored { return index == 0 ? "‹ Z1" : "Z\(index)" }
        return "Z\(index + 1)"
    }

    static func zoneNumbers(_ appleZones: [ATHLTHRecordedHeartRateZone]?) -> [Int] {
        appleZones.flatMap(ATHLTHRecordedHeartRateZones.validated)?.map { $0.index + 1 } ?? Array(1...5)
    }
}
