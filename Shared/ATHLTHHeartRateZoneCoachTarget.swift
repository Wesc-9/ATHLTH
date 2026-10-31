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
        guard let stepZone,
              let interval = ATHLTHHeartRateZones.range(
                for: stepZone,
                maximumBPM: maximumBPM
              ) else {
            return configured
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
            ? ("Heart rate below zone \(zone). Increase the effort slightly.",
               "Pulsen er under sone \(zone). Øk intensiteten litt.")
            : ("Heart rate above zone \(zone). Ease off slightly.",
               "Pulsen er over sone \(zone). Senk intensiteten litt.")
    }

    static func backInTargetPhrase(
        zone: Int?
    ) -> (english: String, norwegian: String) {
        guard let zone, (1...5).contains(zone) else {
            return ("Back in target", "Tilbake i målområdet")
        }
        return ("Back in heart-rate zone \(zone)",
                "Tilbake i pulssone \(zone)")
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
