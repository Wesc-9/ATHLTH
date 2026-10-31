import Foundation

/// Resolve a programmed interval's Z1–Z5 target before evaluating measured
/// HealthKit pulse. Per-step targets take precedence over a workout-wide zone,
/// but preserve any separately configured pace alert and debounce settings.
enum ATHLTHHeartRateZoneCoachTarget {
    static func configuration(
        configured: WatchWorkoutTargetAlertConfiguration?,
        stepZone: Int?,
        maximumBPM: Double?
    ) -> WatchWorkoutTargetAlertConfiguration? {
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
