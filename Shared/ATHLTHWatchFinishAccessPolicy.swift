import Foundation

/// Conservative first-screen finish affordance for Apple Watch workout UIs.
/// This only controls whether an additional button is shown. It never
/// completes, pauses or modifies the HealthKit workout automatically.
enum ATHLTHWatchFinishAccessPolicy {
    static func shouldShowRouteFinish(
        routeProgressPercent: Double?,
        routeRemainingMeters: Double?,
        metersFromFinish: Double?,
        gpsHorizontalAccuracy: Double?,
        gpsAgeSeconds: TimeInterval?,
        workoutElapsedSeconds: TimeInterval,
        inWarmup: Bool,
        awaitingMainStart: Bool
    ) -> Bool {
        guard !inWarmup, !awaitingMainStart,
              workoutElapsedSeconds.isFinite,
              workoutElapsedSeconds >= 120,
              let routeProgressPercent,
              routeProgressPercent.isFinite,
              (92...100).contains(routeProgressPercent),
              let routeRemainingMeters,
              routeRemainingMeters.isFinite,
              (0...150).contains(routeRemainingMeters),
              let metersFromFinish,
              metersFromFinish.isFinite,
              (0...100).contains(metersFromFinish),
              let gpsHorizontalAccuracy,
              gpsHorizontalAccuracy.isFinite,
              (0...30).contains(gpsHorizontalAccuracy),
              let gpsAgeSeconds,
              gpsAgeSeconds.isFinite,
              (-3...15).contains(gpsAgeSeconds)
        else { return false }
        return true
    }
}
