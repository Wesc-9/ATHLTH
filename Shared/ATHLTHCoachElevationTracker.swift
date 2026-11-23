import Foundation
import CoreLocation

/// Validated cumulative positive outdoor ascent for Audio Coach. This does
/// not alter HealthKit distance, routes or the workout's elevation summary.
/// A trigger stays inactive until two reliable, temporally ordered GPS fixes.
struct ATHLTHCoachElevationTracker {
    private var lastAccepted: CLLocation?
    private(set) var gainMeters: Double = 0
    private(set) var uphill: Bool?
    private(set) var hasReliableGain = false

    mutating func reset() {
        lastAccepted = nil
        gainMeters = 0
        uphill = nil
        hasReliableGain = false
    }

    mutating func observe(_ location: CLLocation, now: Date = Date()) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 25,
              location.verticalAccuracy >= 0,
              location.verticalAccuracy <= 8,
              abs(now.timeIntervalSince(location.timestamp)) <= 12,
              location.altitude.isFinite else {
            uphill = nil
            lastAccepted = nil
            return
        }
        guard let previous = lastAccepted else {
            lastAccepted = location
            return
        }
        let dt = location.timestamp.timeIntervalSince(previous.timestamp)
        let moved = location.distance(from: previous)
        guard dt > 0, dt <= 45,
              moved.isFinite, moved >= 12, moved <= min(300, dt * 12) else {
            if dt > 45 || moved > 300 { lastAccepted = location }
            uphill = nil
            return
        }
        let rise = location.altitude - previous.altitude
        guard rise.isFinite, abs(rise) <= max(18, moved * 0.5) else {
            lastAccepted = location
            uphill = nil
            return
        }
        hasReliableGain = true
        if rise >= 3 {
            gainMeters += rise
        }
        uphill = rise >= 4.5 && rise / moved >= 0.035
        lastAccepted = location
    }
}
