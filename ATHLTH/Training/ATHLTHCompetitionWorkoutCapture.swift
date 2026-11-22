import Foundation

/// GPS pass-through evidence attached to the ORIGINAL workout journal.
/// This never starts an additional HealthKit capture or claims server-side
/// attestation. Only accurate outdoor samples may count towards a lap.
struct ATHLTHCompetitionGPSFix: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let timestamp: Date
    let courseDegrees: Double?
}

struct ATHLTHCompetitionGPSLapState: Codable, Equatable {
    var laps: Int = 0
    var outsideSamples: Int = 0
    var insideSamples: Int = 0
    var leftStartZone = false
    var lastLapAt: Date?
    var lastFixAt: Date?
    var crossingHeadingDegrees: Double?
    var totalAcceptedLapMeters: Double = 0
    var lastFixLatitude: Double?
    var lastFixLongitude: Double?
}

/// Hysteresis and course consistency protect against stationary GPS
/// wandering, duplicate callbacks and crossing the lap point the wrong way.
enum ATHLTHCompetitionGPSLapCounter {
    static let innerRadiusMeters = 18.0
    static let outerRadiusMeters = 43.0
    static let maxAccuracyMeters = 15.0
    static let minimumLapSeconds: TimeInterval = 35
    static let minimumTravelMeters = 45.0

    static func update(
        _ state: ATHLTHCompetitionGPSLapState,
        fix: ATHLTHCompetitionGPSFix,
        startLatitude: Double,
        startLongitude: Double,
        startSignalAt: Date,
        limit: Int
    ) -> ATHLTHCompetitionGPSLapState {
        guard (1...500).contains(limit),
              state.laps < limit,
              fix.timestamp >= startSignalAt,
              fix.timestamp <= Date().addingTimeInterval(2),
              fix.accuracyMeters.isFinite,
              (0...maxAccuracyMeters).contains(fix.accuracyMeters),
              (-90...90).contains(fix.latitude),
              (-180...180).contains(fix.longitude),
              (-90...90).contains(startLatitude),
              (-180...180).contains(startLongitude),
              state.lastFixAt.map({ fix.timestamp > $0 }) ?? true
        else { return state }

        var next = state
        let distance = haversineMeters(fix.latitude, fix.longitude,
                                      startLatitude, startLongitude)
        if let a = state.lastFixLatitude, let b = state.lastFixLongitude,
           let last = state.lastFixAt {
            let travelled = haversineMeters(fix.latitude, fix.longitude, a, b)
            let elapsed = fix.timestamp.timeIntervalSince(last)
            if elapsed <= 25 && elapsed > 0 &&
               travelled / elapsed <= 9.5 {
                next.totalAcceptedLapMeters += travelled
            }
        }
        next.lastFixAt = fix.timestamp
        next.lastFixLatitude = fix.latitude
        next.lastFixLongitude = fix.longitude

        if distance >= outerRadiusMeters {
            next.insideSamples = 0
            next.outsideSamples = min(2, next.outsideSamples + 1)
            if next.outsideSamples >= 2 {
                next.leftStartZone = true
            }
            return next
        }
        if distance > innerRadiusMeters {
            next.insideSamples = 0
            return next
        }

        next.insideSamples = min(2, next.insideSamples + 1)
        guard next.insideSamples == 2, next.leftStartZone,
              next.totalAcceptedLapMeters >= minimumTravelMeters,
              fix.timestamp.timeIntervalSince(
                  next.lastLapAt ?? startSignalAt
              ) >= minimumLapSeconds
        else { return next }

        // Establish the accepted crossing direction from the first lap.
        // Ignore a later crossing in the reverse direction, when the GPS
        // reports a reliable heading. Absence of heading is not positive
        // proof of wrong-direction travel.
        if let expected = next.crossingHeadingDegrees,
           let actual = fix.courseDegrees, actual >= 0,
           angularDifference(expected, actual) > 75 {
            next.insideSamples = 0
            return next
        }

        next.laps += 1
        next.lastLapAt = fix.timestamp
        if next.crossingHeadingDegrees == nil,
           let heading = fix.courseDegrees, (0..<360).contains(heading) {
            next.crossingHeadingDegrees = heading
        }
        next.leftStartZone = false
        next.insideSamples = 0
        next.outsideSamples = 0
        next.totalAcceptedLapMeters = 0
        return next
    }

    private static func haversineMeters(
        _ lat1: Double, _ lon1: Double,
        _ lat2: Double, _ lon2: Double
    ) -> Double {
        let radians = Double.pi / 180
        let a = sin((lat2 - lat1) * radians / 2)
        let b = sin((lon2 - lon1) * radians / 2)
        let h = a * a +
            cos(lat1 * radians) * cos(lat2 * radians) * b * b
        return 12_742_000 * asin(min(1, sqrt(max(0, h))))
    }

    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let delta = abs(a.truncatingRemainder(dividingBy: 360) -
                        b.truncatingRemainder(dividingBy: 360))
        return min(delta, 360 - delta)
    }
}

/// An optional competition overlay on the one original running workout.
/// This identity follows the same source workout through live, summary and
/// server result submission; it never becomes a second workout recording.
struct ATHLTHCompetitionCaptureContext: Codable, Equatable {
    let tournamentID: UUID
    let startSignalAt: Date
    let raceRules: ATHLTHCompetitionRaceRules
    var lapState: ATHLTHCompetitionGPSLapState = .init()

    var lapSummary: String {
        "\(lapState.laps)/\(raceRules.lapCount) runder"
    }

    var isRaceArmed: Bool { Date() >= startSignalAt }
}
