import Foundation

/// Calculates an optional one-minute post-workout heart-rate drop from
/// actual heart-rate observations. This is a fallback, not Apple's
/// heartRateRecoveryOneMinute measurement, which has its own definition.
enum ATHLTHHeartRateRecoveryCalculator {
    struct Reading: Sendable, Equatable {
        let date: Date
        let bpm: Double
        let sourceIdentifier: String

        init(date: Date, bpm: Double, sourceIdentifier: String) {
            self.date = date
            self.bpm = bpm
            self.sourceIdentifier = sourceIdentifier
        }
    }

    /// Use an observed value close to the workout end and another around
    /// +60 seconds. Never extrapolate missing observations or assume an
    /// immediate drop. The same HealthKit source must provide both values.
    static func dropAfterOneMinute(
        workoutEnd: Date,
        readings: [Reading]
    ) -> Double? {
        let valid = readings.filter {
            $0.bpm.isFinite &&
            (35...245).contains($0.bpm) &&
            !$0.sourceIdentifier.isEmpty
        }
        let finishing = valid.filter {
            let offset = $0.date.timeIntervalSince(workoutEnd)
            return (-30...5).contains(offset)
        }
        .sorted {
            abs($0.date.timeIntervalSince(workoutEnd)) <
            abs($1.date.timeIntervalSince(workoutEnd))
        }

        for ending in finishing {
            let recovery = valid.filter {
                $0.sourceIdentifier == ending.sourceIdentifier &&
                (40...90).contains($0.date.timeIntervalSince(workoutEnd))
            }
            .min {
                abs($0.date.timeIntervalSince(workoutEnd) - 60) <
                abs($1.date.timeIntervalSince(workoutEnd) - 60)
            }

            guard let recovery else { continue }
            let drop = ending.bpm - recovery.bpm
            if drop.isFinite && (1...120).contains(drop) {
                return drop.rounded()
            }
        }
        return nil
    }
}
