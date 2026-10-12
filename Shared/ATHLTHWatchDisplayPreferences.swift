import Foundation

/// Read-only Watch presentation policy, derived from an already transferred
/// Live Workout configuration. No separate preference store or session state.
enum ATHLTHWatchDisplayPreferences {
    static func prefersDistance(
        kind: WatchWorkoutKind,
        configuration: ATHLTHLiveWorkoutSurfaceConfiguration
    ) -> Bool {
        switch configuration.preferredRunMetricRaw {
        case "distance": return true
        case "pace": return false
        default: return kind == .walking
        }
    }

    static func startingRunPage(
        configuration: ATHLTHLiveWorkoutSurfaceConfiguration,
        audioCoachAvailable: Bool
    ) -> Int {
        switch configuration.preferredRunPageRaw {
        case "pulse": return 7
        case "coach" where audioCoachAvailable: return 8
        default: return 0
        }
    }

    static func prefersStrongContrast(
        _ configuration: ATHLTHLiveWorkoutSurfaceConfiguration
    ) -> Bool {
        configuration.strongWatchContrast == true
    }

    static func hidesAlwaysOnDetails(
        _ configuration: ATHLTHLiveWorkoutSurfaceConfiguration
    ) -> Bool {
        configuration.privateAlwaysOn == true
    }
}
