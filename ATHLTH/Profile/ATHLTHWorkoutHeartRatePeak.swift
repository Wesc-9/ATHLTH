import Foundation

/// A pulse actually recorded in a HealthKit workout, not a measured
/// physiological HRmax. Users decide whether to use it for training zones.
struct ATHLTHWorkoutHeartRatePeak: Equatable, Identifiable {
    let beatsPerMinute: Int
    let workoutID: UUID
    let workoutDate: Date
    let workoutTitle: String

    var id: UUID { workoutID }
}

enum ATHLTHWorkoutHeartRatePeakPolicy {
    /// Reject obviously invalid values, but do not claim that a plausible
    /// sensor spike is a laboratory-verified physiological maximum.
    static func validPeak(_ beatsPerMinute: Double) -> Int? {
        guard beatsPerMinute.isFinite,
              (100...240).contains(beatsPerMinute)
        else { return nil }
        return Int(beatsPerMinute.rounded())
    }

    static func highest(
        among candidates: [ATHLTHWorkoutHeartRatePeak]
    ) -> ATHLTHWorkoutHeartRatePeak? {
        candidates.max {
            if $0.beatsPerMinute != $1.beatsPerMinute {
                return $0.beatsPerMinute < $1.beatsPerMinute
            }
            return $0.workoutDate < $1.workoutDate
        }
    }
}
