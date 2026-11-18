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

    /// Exactly twelve calendar months, measured from the moment the
    /// HealthKit query is issued. Ignore historical and future samples.
    static func windowStart(
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .month, value: -12, to: date)
            ?? date.addingTimeInterval(-366 * 24 * 60 * 60)
    }

    static func isWithinLast12Months(
        workoutDate: Date,
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        workoutDate >= windowStart(asOf: date, calendar: calendar) &&
            workoutDate <= date
    }

    static func recent(
        among candidates: [ATHLTHWorkoutHeartRatePeak],
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> [ATHLTHWorkoutHeartRatePeak] {
        candidates.filter {
            isWithinLast12Months(
                workoutDate: $0.workoutDate,
                asOf: date,
                calendar: calendar
            )
        }
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
