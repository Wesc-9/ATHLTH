import CoreLocation
import Foundation

enum OutdoorAutoPauseAction {
    case pause
    case resume
}

/// Conservative motion detector used only while an outdoor run/walk is active.
/// It requires sustained low-speed samples before pausing and sustained movement
/// before resuming, which keeps GPS jitter from repeatedly toggling the workout.
struct OutdoorAutoPauseDetector {
    private(set) var enabled = false
    private(set) var isAutoPaused = false

    private var stationarySince: Date?
    private var movingSince: Date?
    private var previousLocation: CLLocation?

    mutating func reset(
        enabled: Bool,
        paused: Bool = false
    ) {
        self.enabled = enabled
        isAutoPaused = enabled && paused
        stationarySince = nil
        movingSince = nil
        previousLocation = nil
    }

    mutating func evaluate(
        _ location: CLLocation,
        walking: Bool
    ) -> OutdoorAutoPauseAction? {
        guard enabled,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 30
        else {
            previousLocation = location
            stationarySince = nil
            movingSince = nil
            return nil
        }

        let previous = previousLocation
        previousLocation = location

        let measuredSpeed =
            location.speed >= 0
                ? location.speed
                : nil

        let derivedSpeed: CLLocationSpeed? = {
            guard let previous else {
                return nil
            }

            let interval =
                location.timestamp
                    .timeIntervalSince(
                        previous.timestamp
                    )

            guard interval > 0.25,
                  interval <= 15
            else {
                return nil
            }

            let distance =
                location.distance(
                    from: previous
                )

            guard distance.isFinite,
                  distance >= 0
            else {
                return nil
            }

            return distance / interval
        }()

        let speed =
            measuredSpeed ??
            derivedSpeed ??
            0

        let pauseSpeed:
            CLLocationSpeed =
                walking ? 0.20 : 0.35
        let resumeSpeed:
            CLLocationSpeed =
                walking ? 0.55 : 0.90
        let pauseDelay:
            TimeInterval =
                walking ? 12 : 8
        let resumeDelay:
            TimeInterval = 2

        if isAutoPaused {
            stationarySince = nil

            if speed >= resumeSpeed {
                if movingSince == nil {
                    movingSince =
                        location.timestamp
                }

                if let movingSince,
                   location.timestamp
                    .timeIntervalSince(
                        movingSince
                    ) >= resumeDelay {
                    isAutoPaused = false
                    self.movingSince = nil
                    return .resume
                }
            } else {
                movingSince = nil
            }

            return nil
        }

        movingSince = nil

        if speed <= pauseSpeed {
            if stationarySince == nil {
                stationarySince =
                    location.timestamp
            }

            if let stationarySince,
               location.timestamp
                .timeIntervalSince(
                    stationarySince
                ) >= pauseDelay {
                isAutoPaused = true
                self.stationarySince = nil
                return .pause
            }
        } else {
            stationarySince = nil
        }

        return nil
    }
}
