import Foundation

/// Resolve a programmed interval's Z1–Z5 target before evaluating measured
/// HealthKit pulse. Per-step targets take precedence over a workout-wide zone,
/// but preserve any separately configured pace alert and debounce settings.
enum ATHLTHHeartRateZoneCoachTarget {
    static func configuration(
        configured: WatchWorkoutTargetAlertConfiguration?,
        stepZone: Int?,
        maximumBPM: Double?,
        stepPercentMin: Double? = nil,
        stepPercentMax: Double? = nil,
        suppressHeartRateForUnzonedStep: Bool = false
    ) -> WatchWorkoutTargetAlertConfiguration? {
        // A planned 1-minute recovery without Z5 is NOT another Z5 effort.
        // Keep any independent pace alert, but remove its inherited HR zone.
        if suppressHeartRateForUnzonedStep {
            var restConfiguration = configured
            restConfiguration?.heartRateEnabled = false
            restConfiguration?.heartRateZone = nil
            restConfiguration?.heartRateMinimumBPM = nil
            restConfiguration?.heartRateMaximumBPM = nil
            return restConfiguration
        }
        if let lower = stepPercentMin, let upper = stepPercentMax {
            // A multiple-zone target like Z1–Z2 carries exact percent
            // boundaries, not an invented single zone. Prefer the source
            // prescription over any global Audio Coach pulse target.
            guard lower.isFinite, upper.isFinite,
                  (30...100).contains(lower), (30...100).contains(upper),
                  lower <= upper,
                  let maximumBPM, maximumBPM.isFinite,
                  (100...240).contains(maximumBPM) else {
                var unavailable = configured
                unavailable?.heartRateEnabled = false
                unavailable?.heartRateZone = nil
                unavailable?.heartRateMinimumBPM = nil
                unavailable?.heartRateMaximumBPM = nil
                return unavailable
            }
            let minimum = Double(Int((maximumBPM * lower / 100).rounded()))
            let maximum = Double(Int((maximumBPM * upper / 100).rounded()))
            var result = configured ?? WatchWorkoutTargetAlertConfiguration(
                heartRateEnabled: true,
                heartRateZone: stepZone,
                heartRateMinimumBPM: minimum,
                heartRateMaximumBPM: maximum,
                paceAlertsEnabled: false,
                paceToleranceSecondsPerKilometer: 15,
                graceSeconds: 10,
                repeatSeconds: 120,
                delivery: .both,
                announceBackInTarget: true
            )
            result.heartRateEnabled = true
            result.heartRateZone = stepZone
            result.heartRateMinimumBPM = minimum
            result.heartRateMaximumBPM = maximum
            return result
        }
        guard let stepZone else { return configured }
        guard let interval = ATHLTHHeartRateZones.range(
            for: stepZone,
            maximumBPM: maximumBPM
        ) else {
            // A stale workout-wide zone must never be described as the
            // current interval's goal when HRmax is not available.
            var fallback = configured
            if fallback?.heartRateZone != stepZone {
                fallback?.heartRateEnabled = false
                fallback?.heartRateZone = nil
                fallback?.heartRateMinimumBPM = nil
                fallback?.heartRateMaximumBPM = nil
            }
            return fallback
        }

        var result = configured ?? WatchWorkoutTargetAlertConfiguration(
            heartRateEnabled: true,
            heartRateZone: stepZone,
            heartRateMinimumBPM: Double(interval.lowerBound),
            heartRateMaximumBPM: Double(interval.upperBound),
            paceAlertsEnabled: false,
            paceToleranceSecondsPerKilometer: 15,
            graceSeconds: 10,
            repeatSeconds: 120,
            delivery: .both,
            announceBackInTarget: true
        )
        result.heartRateEnabled = true
        result.heartRateZone = stepZone
        result.heartRateMinimumBPM = Double(interval.lowerBound)
        result.heartRateMaximumBPM = Double(interval.upperBound)
        return result
    }

    static func alertPhrase(
        zone: Int?,
        below: Bool
    ) -> (english: String, norwegian: String) {
        guard let zone, (1...5).contains(zone) else {
            return below
                ? ("Heart rate below target", "Pulsen er under målområdet")
                : ("Heart rate above target", "Pulsen er over målområdet")
        }
        return below
            ? ("Heart rate below zone Z\(zone). Increase the effort slightly.",
               "Pulsen er under pulssone S\(zone). Øk intensiteten litt.")
            : ("Heart rate above zone Z\(zone). Ease off slightly.",
               "Pulsen er over pulssone S\(zone). Senk intensiteten litt.")
    }

    /// Positive affirmation is different from a recovery notification.
    /// The Watch applies freshness, stable-duration and cooldown gates.
    static func onTargetPhrase(
        zone: Int
    ) -> (english: String, norwegian: String) {
        ("You're holding heart-rate zone Z\(zone). Good control.",
         "Du holder deg i pulssone S\(zone). God kontroll.")
    }

    static func backInTargetPhrase(
        zone: Int?
    ) -> (english: String, norwegian: String) {
        guard let zone, (1...5).contains(zone) else {
            return ("Back in target", "Tilbake i målområdet")
        }
        return ("Back in heart-rate zone Z\(zone)",
                "Tilbake i pulssone S\(zone)")
    }

    static func spokenDelivery(
        _ selected: WatchAlertDelivery,
        coachEnabled: Bool
    ) -> WatchAlertDelivery {
        // Preserve a voice-only choice. With Audio Coach enabled a haptic-only
        // workout target also gains speech, without altering saved preferences.
        guard coachEnabled, !selected.usesVoice else { return selected }
        return .both
    }
}
