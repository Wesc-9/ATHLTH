import Foundation
@preconcurrency import CoreLocation

/// Shared low-level Watch workout state models. Kept separate from the
/// live HealthKit manager to limit cross-feature compiler work.
struct WatchLocationSample: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let course: Double
    let speed: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        horizontalAccuracy =
            location.horizontalAccuracy
        verticalAccuracy =
            location.verticalAccuracy
        course = location.course
        speed = location.speed
        timestamp = location.timestamp
    }

    func makeLocation() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            altitude: altitude,
            horizontalAccuracy:
                horizontalAccuracy,
            verticalAccuracy:
                verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }
}

// WatchConnectivity may complete via a reply, an error, or a timeout.
 // Resolve exactly once so a late callback cannot trap a checked continuation.
final class WatchStartGuardContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool?, Never>?

    init(_ continuation: CheckedContinuation<Bool?, Never>) {
        self.continuation = continuation
    }

    func complete(_ answer: Bool?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: answer)
    }

    // These closures are created outside MainActor isolation. WCSession
    // invokes them on a utility queue; closures created in an actor-isolated
    // method can trap with _dispatch_assert_queue_fail in Swift 6.
    nonisolated func makeReplyHandler() -> ([String: Any]) -> Void {
        { [self] reply in
            complete(
                reply[WatchTransferMetadataKey.workoutAllowed] as? Bool
            )
        }
    }

    nonisolated func makeErrorHandler() -> (Error) -> Void {
        { [self] _ in
            complete(nil)
        }
    }
}

struct WatchPersistedWorkoutState: Codable {
    var kind: WatchWorkoutKind
    var startedAt: Date?
    var plannedRoute: WatchRouteTransfer?
    var audioCoach: WatchAudioCoachConfiguration
    var structuredRunningWorkout: WatchRunningWorkoutTransfer?
    var structuredStepIndex: Int
    var structuredStepStartElapsedTime: TimeInterval
    var structuredStepStartDistanceMeters: Double
    var awaitingMainStart: Bool? = nil
    var ghostRace: WatchGhostRaceTransfer?
    var lapSummaries: [WatchWorkoutLapSummary]
    var lapCount: Int
    var lastLapElapsedTime: TimeInterval
    var lastLapDistanceMeters: Double
    var automaticPauseCount: Int
    var automaticPauseEnabled: Bool? = nil
    var indoorVenue: ATHLTHIndoorRunVenue? = nil
    var returningToRouteStart: Bool? = nil
    var routeLegDistanceOffsetMeters: Double? = nil
    var strengthSession:
        WatchStrengthSessionSnapshot? = nil
    var strengthCommands:
        [WatchStrengthCommand]? = nil
}

