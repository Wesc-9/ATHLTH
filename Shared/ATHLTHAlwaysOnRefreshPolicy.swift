import Foundation

/// Display and transport only; never changes HealthKit collection, deadlines,
/// haptics or Audio Coach timing.
enum ATHLTHAlwaysOnRefreshPolicy {
    static let loweredWristInterval: TimeInterval = 60
    static let criticalCountdownInterval: TimeInterval = 1

    static func countdownInterval(isRunning: Bool) -> TimeInterval {
        isRunning ? criticalCountdownInterval : loweredWristInterval
    }

    static func ghostInterval(isRunning: Bool, lowPower: Bool) -> TimeInterval {
        guard isRunning else { return loweredWristInterval }
        return lowPower ? 10 : 5
    }
}

enum ATHLTHWatchPerformancePolicy {
    static func mirrorInterval(lowPower: Bool, needsLivePrecision: Bool) -> TimeInterval {
        lowPower && !needsLivePrecision ? 2 : 0.85
    }

    /// Preserve GPS accuracy and the original filter for running, navigation,
    /// competition and auto-pause.
    static func locationDistanceFilter(
        lowPower: Bool, isFreeWalk: Bool, needsLivePrecision: Bool
    ) -> Double {
        lowPower && isFreeWalk && !needsLivePrecision ? 5 : 3
    }
}
