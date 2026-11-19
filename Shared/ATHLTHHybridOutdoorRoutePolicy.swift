import Foundation

/// Only a confirmed outdoor Watch-owned running phase may append route
/// points to a strength/hybrid parent HealthKit session. Never fabricate
/// measured distance for ordinary strength or indoor treadmill training.
enum ATHLTHHybridOutdoorRoutePolicy {
    static func mayCaptureStrengthRoute(
        isOutdoor: Bool,
        isEmbeddedRunningInterval: Bool
    ) -> Bool {
        isOutdoor && isEmbeddedRunningInterval
    }
}
