import Foundation

/// Per-kilometre pulse shown in completed running/walking reviews.
/// Only real samples tied to the relevant kilometre are used; workout-wide
/// average pulse and target pulse/zone are never substituted as observations.
enum ATHLTHRunningKilometerPulseAnalysis {
    struct Result: Equatable {
        let averageBPM: Int
        let observedZone: Int?
    }

    static func results(
        for splits: [ATHLTHRunningResultInsights.KilometerSplit],
        measuredPulse: [ATHLTHRunningHeartRatePoint],
        recordedMinutes: [ATHLTHRecordedRunningMinute],
        athleteMaximumBPM: Double?
    ) -> [Int: Result] {
        let indoorAverages = minuteCheckpointAverages(recordedMinutes)
        var values: [Int: Result] = [:]

        for split in splits {
            let mean: Double?
            if let start = split.startedAt, let end = split.endedAt,
               end > start {
                // GPS split boundaries have actual timestamps: match
                // HealthKit observations to this kilometre only.
                mean = ATHLTHRunningHeartRateAnalysis.average(
                    measuredPulse, from: start, through: end
                )
            } else {
                // Indoor sessions have no GPS timestamps; use Watch's
                // recorded minute checkpoints instead, when present.
                mean = indoorAverages[split.kilometer]
            }

            guard let mean, mean.isFinite, (30...240).contains(mean)
            else { continue }

            values[split.kilometer] = Result(
                averageBPM: Int(mean.rounded()),
                observedZone: ATHLTHHeartRateZones.measuredZone(
                    heartRateBPM: mean,
                    maximumBPM: athleteMaximumBPM
                )
            )
        }

        return values
    }

    /// Distribute observed minute heart-rate checkpoints proportionally
    /// across a 1000 m boundary using the same recorded distance/time
    /// allocation as ATHLTHRunningResultInsights.kilometerSplits.
    /// Missing pulse observations do not count toward the average.
    /// Require at least 25% observed time (and 30 s) for a usable split.
    private static func minuteCheckpointAverages(
        _ minutes: [ATHLTHRecordedRunningMinute]
    ) -> [Int: Double] {
        guard !minutes.isEmpty, minutes.count <= 2_500 else { return [:] }

        var results: [Int: Double] = [:]
        var kilometre = 1
        var splitMeters = 0.0
        var splitSeconds = 0.0
        var observedSeconds = 0.0
        var weightedPulseSum = 0.0

        for minute in minutes {
            let meters = minute.recordedDistanceMeters
            let seconds = minute.activeSeconds
            guard meters.isFinite, meters >= 0, meters <= 800,
                  seconds.isFinite, seconds > 0, seconds <= 120,
                  meters / seconds <= 9.8 else { return [:] }

            let observedPulse: Double? = minute.watchHeartRateBPM.flatMap {
                $0.isFinite && (30...240).contains($0) ? $0 : nil
            }

            if meters == 0 {
                splitSeconds += seconds
                if let observedPulse {
                    observedSeconds += seconds
                    weightedPulseSum += observedPulse * seconds
                }
                continue
            }

            var availableMeters = meters
            var availableSeconds = seconds
            while availableMeters > 0 {
                let taken = min(1_000 - splitMeters, availableMeters)
                let secondsUsed = availableSeconds * (taken / availableMeters)
                splitMeters += taken
                splitSeconds += secondsUsed
                if let observedPulse {
                    observedSeconds += secondsUsed
                    weightedPulseSum += observedPulse * secondsUsed
                }
                availableMeters -= taken
                availableSeconds -= secondsUsed

                if splitMeters >= 999.999 {
                    if observedSeconds >= max(30, splitSeconds * 0.25) {
                        results[kilometre] = weightedPulseSum / observedSeconds
                    }
                    kilometre += 1
                    splitMeters = 0
                    splitSeconds = 0
                    observedSeconds = 0
                    weightedPulseSum = 0
                }
            }
        }

        return results
    }
}
