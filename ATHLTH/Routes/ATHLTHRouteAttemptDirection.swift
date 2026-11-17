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
              observedEnd.distance(from: first) <= 350
        else { return .unknown }

        // On a genuine A→B→A retrace the route and its reversal are
        // geographically equivalent. The previous algorithm compared one
        // point 160 m from the start and could NEVER confirm either
        // direction, even with a perfect GPS track. Treat the shared path
        // as the canonical forward direction only after confirming the
        // full workout, not just proximity to the start.
        let referenceLength = distance(reference)
        if isReciprocalOutAndBack(reference, length: referenceLength) {
            let actualLength = distance(actual)
            guard referenceLength > 300,
                  actualLength >= referenceLength * 0.70,
                  actualLength <= referenceLength * 1.45,
                  (RoutePerformanceMatcher.analyze(
                    reference: reference, actual: actual
                  )?.routeMatchPercent ?? 0) >= 85
            else { return .unknown }
            return .forward
        }

        // On other closed routes early segments can overlap even though
        // the later route branches differ. Compare several progress
        // positions rather than deciding solely from the first 160 m.
        let reversedReference = Array(reference.reversed())
        let probes = [160.0, max(300, referenceLength * 0.12),
                      max(450, referenceLength * 0.22)]
        var forwardVotes = 0
        var reverseVotes = 0
        for meters in probes where meters < referenceLength * 0.48 {
            guard let observed = sample(actual, metersFromStart: meters),
                  let ahead = sample(reference, metersFromStart: meters),
                  let behind = sample(reversedReference, metersFromStart: meters)
            else { continue }
            let forwardGap = observed.distance(from: ahead)
            let reverseGap = observed.distance(from: behind)
            guard min(forwardGap, reverseGap) <= 115,
                  abs(forwardGap - reverseGap) >= 55 else { continue }
            if forwardGap < reverseGap { forwardVotes += 1 }
            else { reverseVotes += 1 }
        }
        guard forwardVotes != reverseVotes,
              forwardVotes == 0 || reverseVotes == 0 else { return .unknown }
        return forwardVotes > 0 ? .forward : .reverse
    }

    private static func distance(_ points: [CLLocation]) -> Double {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + max(0, pair.0.distance(from: pair.1))
        }
    }

    /// Detect only genuinely retraced paths. A true circuit with
    /// separate clockwise/counter-clockwise sections must remain
    /// direction-sensitive even when it starts and ends at one point.
    private static func isReciprocalOutAndBack(
        _ reference: [CLLocation], length: Double
    ) -> Bool {
        guard reference.count >= 3, length >= 300,
              let first = reference.first, let last = reference.last,
              first.distance(from: last) <= 75 else { return false }
        let reverse = Array(reference.reversed())
        for fraction in [0.14, 0.27, 0.39, 0.61, 0.73, 0.86] {
            guard let ahead = sample(reference, metersFromStart: length * fraction),
                  let behind = sample(reverse, metersFromStart: length * fraction),
                  ahead.distance(from: behind) <= 40 else { return false }
        }
        return true
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

    /// All recorded workouts remain part of the athlete's history, even
    /// when an old record has no verifiable GPS direction.
    static func personalHistory(
        _ attempts: [RouteAttemptRecord],
        userID: UUID
    ) -> [RouteAttemptRecord] {
        attempts
            .filter { $0.userID == userID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// The selected direction shows its own runs plus legacy unknown-direction
    /// runs; leaderboard eligibility is deliberately checked elsewhere.
    static func visiblePersonalHistory(
        _ attempts: [RouteAttemptRecord],
        direction: ATHLTHRouteAttemptDirection,
        userID: UUID
    ) -> [RouteAttemptRecord] {
        personalHistory(attempts, userID: userID).filter {
            $0.direction == direction ||
                ($0.direction ?? .unknown) == .unknown
        }
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
