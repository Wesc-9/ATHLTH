import CoreLocation
import Foundation

/// Route direction is evidence from GPS, not a UI toggle or a guess.
/// Legacy records remain unknown until their source workout can be reanalysed.
enum ATHLTHRouteAttemptDirection: String, Codable, CaseIterable, Identifiable {
    case forward
    case reverse
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forward:
            return ATHLTHLocalization.choose(
                english: "Original direction", norwegian: "Normal retning"
            )
        case .reverse:
            return ATHLTHLocalization.choose(
                english: "Reverse direction", norwegian: "Motsatt retning"
            )
        case .unknown:
            return ATHLTHLocalization.choose(
                english: "Direction unverified", norwegian: "Retning ikke bekreftet"
            )
        }
    }
}

enum ATHLTHRouteAttemptDirectionPolicy {
    /// Validates the start/end match first. For a loop, compare early GPS
    /// progression against the track on both sides of the shared start.
    /// Parallel paths and out-and-back overlap produce .unknown, not a
    /// potentially unfair leaderboard placement.
    static func classify(
        reference: [CLLocation],
        actual: [CLLocation]
    ) -> ATHLTHRouteAttemptDirection {
        guard reference.count >= 2, actual.count >= 2,
              let first = reference.first, let last = reference.last,
              let observedStart = actual.first, let observedEnd = actual.last
        else { return .unknown }

        let original = observedStart.distance(from: first)
            + observedEnd.distance(from: last)
        let reversed = observedStart.distance(from: last)
            + observedEnd.distance(from: first)
        let endpointsClose = first.distance(from: last) <= 75
        if !endpointsClose {
            let winner = min(original, reversed)
            guard winner <= 750, abs(original - reversed) >= 130 else {
                return .unknown
            }
            return original < reversed ? .forward : .reverse
        }

        guard reference.count >= 3, actual.count >= 3,
              observedStart.distance(from: first) <= 250,
              observedEnd.distance(from: first) <= 350,
              let observed = sample(actual, metersFromStart: 160),
              let ahead = sample(reference, metersFromStart: 160),
              let behind = sample(Array(reference.reversed()), metersFromStart: 160)
        else { return .unknown }

        let forwardGap = observed.distance(from: ahead)
        let reverseGap = observed.distance(from: behind)
        guard min(forwardGap, reverseGap) <= 115,
              abs(forwardGap - reverseGap) >= 55 else { return .unknown }
        return forwardGap < reverseGap ? .forward : .reverse
    }

    private static func sample(
        _ route: [CLLocation],
        metersFromStart target: Double
    ) -> CLLocation? {
        guard route.count >= 2 else { return nil }
        var covered = 0.0
        for index in 1..<route.count {
            let distance = route[index - 1].distance(from: route[index])
            guard distance.isFinite, distance >= 0 else { continue }
            if covered + distance >= target, distance > 0 {
                let t = min(1, max(0, (target - covered) / distance))
                let a = route[index - 1].coordinate
                let b = route[index].coordinate
                return CLLocation(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
            }
            covered += distance
        }
        return route.last
    }

    static func eligible(
        _ attempts: [RouteAttemptRecord],
        direction: ATHLTHRouteAttemptDirection,
        userID: UUID? = nil
    ) -> [RouteAttemptRecord] {
        guard direction != .unknown else { return [] }
        return attempts.filter {
            $0.leaderboardEligible &&
            $0.direction == direction &&
            (userID == nil || $0.userID == userID)
        }
    }

    static func bestByAthlete(
        _ attempts: [RouteAttemptRecord],
        direction: ATHLTHRouteAttemptDirection
    ) -> [RouteAttemptRecord] {
        var best: [UUID: RouteAttemptRecord] = [:]
        for attempt in eligible(attempts, direction: direction) {
            if let current = best[attempt.userID],
               current.durationSeconds <= attempt.durationSeconds {
                continue
            }
            best[attempt.userID] = attempt
        }
        return best.values.sorted {
            if abs($0.durationSeconds - $1.durationSeconds) > 0.1 {
                return $0.durationSeconds < $1.durationSeconds
            }
            return $0.startedAt < $1.startedAt
        }
    }

    static func personalProgress(
        _ attempts: [RouteAttemptRecord],
        direction: ATHLTHRouteAttemptDirection,
        userID: UUID
    ) -> (best: RouteAttemptRecord?, latest: RouteAttemptRecord?, gainSeconds: Double?) {
        let owned = eligible(attempts, direction: direction, userID: userID)
            .sorted { $0.startedAt > $1.startedAt }
        let best = owned.min { $0.durationSeconds < $1.durationSeconds }
        let latest = owned.first
        guard let latest, let previous = owned.dropFirst().first else {
            return (best, latest, nil)
        }
        return (best, latest, previous.durationSeconds - latest.durationSeconds)
    }
}
