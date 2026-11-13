import Foundation

/// A planned pulse range is a prediction from the athlete's HRmax, not a
/// measured pulse or a promise that the zone is reached at the start of a drag.
enum ATHLTHPlannedHeartRatePreview {
    static func expectedBPM(
        for block: WorkoutTemplateBlock,
        maximumBPM: Double?
    ) -> ClosedRange<Int>? {
        guard let maximumBPM, maximumBPM.isFinite,
              (100...240).contains(maximumBPM) else { return nil }
        if let lower = block.targetHeartRatePercentMin,
           let upper = block.targetHeartRatePercentMax,
           (30...100).contains(lower), (30...100).contains(upper),
           lower <= upper {
            let minimumBPM = Int((maximumBPM * lower / 100).rounded())
            let maximumBPMValue = Int((maximumBPM * upper / 100).rounded())
            return minimumBPM...maximumBPMValue
        }
        if let zone = block.targetHeartRateZone {
            return ATHLTHHeartRateZones.range(for: zone, maximumBPM: maximumBPM)
        }
        return nil
    }

    static func rangeText(
        for block: WorkoutTemplateBlock,
        maximumBPM: Double?
    ) -> String? {
        guard let range = expectedBPM(for: block, maximumBPM: maximumBPM) else {
            return nil
        }
        return ATHLTHLocalization.choose(
            english: "Estimated target: ~\(range.lowerBound)–\(range.upperBound) bpm",
            norwegian: "Estimert pulsmål: ca. \(range.lowerBound)–\(range.upperBound) slag/min"
        )
    }
}
