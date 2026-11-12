import Foundation

/// Presentation-only rules shared by Home Screen, Lock Screen and iPad
/// widgets. The recording engine remains the sole source of workout data.
enum ATHLTHWidgetPresentationPolicy {
    static func intervalLabel(
        ordinal: Int?, total: Int?, isRecovery: Bool
    ) -> String? {
        guard let ordinal, let total, total > 1,
              ordinal >= 1, ordinal <= total else { return nil }
        if isRecovery {
            return "Neste \(min(ordinal + 1, total)) av \(total)"
        }
        return "\(ordinal) av \(total)"
    }

    static func remainingSeconds(_ seconds: TimeInterval?) -> TimeInterval? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    static func elapsedAnchor(
        updatedAt: Date, elapsedSeconds: TimeInterval
    ) -> Date {
        let bounded = elapsedSeconds.isFinite ? max(0, elapsedSeconds) : 0
        return updatedAt.addingTimeInterval(-bounded)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let bounded = seconds.isFinite ? max(0, min(seconds, 359_999)) : 0
        let value = Int(ceil(bounded))
        if value >= 3_600 {
            return String(format: "%d:%02d:%02d",
                          value / 3_600, (value / 60) % 60, value % 60)
        }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func heartRateLabel(_ bpm: Double) -> String? {
        guard bpm.isFinite, bpm >= 20, bpm <= 250 else { return nil }
        return "\(Int(bpm.rounded())) bpm"
    }

    static func distanceLabel(_ meters: Double) -> String? {
        guard meters.isFinite, meters > 0 else { return nil }
        return String(format: "%.2f km", meters / 1_000)
    }
}
