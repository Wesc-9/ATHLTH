import CoreLocation
import Foundation

/// Verified route-derived insights for the post-workout result and share card.
/// Never infer pace or achievements from a GPS jump or an unfinished kilometre.
enum ATHLTHRunningResultInsights {
    struct KilometerSplit: Identifiable, Equatable {
        let kilometer: Int
        let durationSeconds: Double
        var startedAt: Date? = nil
        var endedAt: Date? = nil
        var id: Int { kilometer }
        var paceSecondsPerKilometer: Double { durationSeconds }
    }

    struct ElevationPoint: Identifiable, Equatable {
        let distanceKilometers: Double
        let altitudeMeters: Double
        var id: Double { distanceKilometers }
    }

    /// A single workout-associated HealthKit walking/running distance sample.
    /// The HealthKit adapter lives in HealthKitManager; this calculation can
    /// be unit-tested without a health store or a device.
    struct HealthDistanceInterval: Equatable {
        let startDate: Date
        let endDate: Date
        let distanceMeters: Double
    }

    /// Prefer the Watch's workout-associated distance timeline for retrospective
    /// kilometre pace. Raw GPS geometry can disagree with the Watch's fused
    /// distance sensor, shifting the point at which each km is completed.
    /// Return [] if the Health samples are incomplete/condensed/contradictory;
    /// callers must then use the already-verified route-based fallback.
    static func healthDistanceKilometerSplits(
        from samples: [HealthDistanceInterval],
        workoutStart: Date,
        workoutEnd: Date,
        reportedDistanceMeters: Double?,
        pausedIntervals: [DateInterval] = []
    ) -> [KilometerSplit] {
        guard workoutEnd > workoutStart,
              samples.count >= 3, samples.count < 12_000 else { return [] }
        let ordered = samples.sorted { $0.startDate < $1.startDate }
        let pauses = pausedIntervals.sorted { $0.start < $1.start }
        guard pauses.allSatisfy({
            $0.start >= workoutStart && $0.end <= workoutEnd && $0.end > $0.start
        }) else { return [] }
        if pauses.count > 1 {
            for index in 1..<pauses.count {
                guard pauses[index].start >= pauses[index - 1].end else { return [] }
            }
        }

        var totalDistance = 0.0
        var previousEnd = workoutStart
        for interval in ordered {
            let seconds = interval.endDate.timeIntervalSince(interval.startDate)
            guard seconds.isFinite, seconds > 0, seconds <= 180,
                  interval.startDate >= workoutStart.addingTimeInterval(-2),
                  interval.endDate <= workoutEnd.addingTimeInterval(2),
                  interval.startDate >= previousEnd.addingTimeInterval(-0.25),
                  interval.distanceMeters.isFinite,
                  (0...600).contains(interval.distanceMeters),
                  interval.distanceMeters / seconds <= 9.8
            else { return [] }
            previousEnd = interval.endDate
            totalDistance += interval.distanceMeters
        }
        guard totalDistance >= 1_000 else { return [] }

        // Only use HealthKit's independent distance timeline if its total
        // agrees with the workout's recorded distance, not an unrelated walk.
        guard let reportedDistanceMeters,
              reportedDistanceMeters.isFinite, reportedDistanceMeters > 0,
              abs(totalDistance - reportedDistanceMeters) /
                reportedDistanceMeters <= 0.04
        else { return [] }

        func movingSeconds(_ start: Date, _ end: Date) -> Double {
            var seconds = end.timeIntervalSince(start)
            for pause in pauses where pause.start < end && pause.end > start {
                let overlapStart = max(start, pause.start)
                let overlapEnd = min(end, pause.end)
                seconds -= max(0, overlapEnd.timeIntervalSince(overlapStart))
            }
            return seconds
        }

        var completed: [KilometerSplit] = []
        var accumulated = 0.0
        var start = workoutStart
        var pointsInKilometer = 0

        for sample in ordered {
            let meters = sample.distanceMeters
            guard meters > 0 else { continue }
            pointsInKilometer += 1
            let before = accumulated
            let after = accumulated + meters

            if after >= 999.999 {
                // Avoid interpolating a split from one very coarse sample.
                guard pointsInKilometer >= 2 else { return [] }
                let fraction = min(1, max(0, (1_000 - before) / meters))
                let boundary = sample.startDate.addingTimeInterval(
                    sample.endDate.timeIntervalSince(sample.startDate) * fraction
                )
                let elapsed = movingSeconds(start, boundary)
                guard (50...2_400).contains(elapsed) else { return [] }
                completed.append(KilometerSplit(
                    kilometer: completed.count + 1,
                    durationSeconds: elapsed,
                    startedAt: start,
                    endedAt: boundary
                ))
                start = boundary
                accumulated = after - 1_000
                pointsInKilometer = accumulated > 0.001 ? 1 : 0

                // An associated sample should never span an entire km;
                // reject a pathological sample rather than inventing splits.
                guard accumulated < 999.999 else { return [] }
            } else {
                accumulated = after
            }
        }
        return completed
    }

    static func kilometerSplits(
        from route: [CLLocation],
        reportedDistanceMeters: Double?
    ) -> [KilometerSplit] {
        guard route.count >= 2, route.count <= 25_000 else { return [] }
        var accumulatedMeters = 0.0
        var splitSeconds = 0.0
        var completed: [KilometerSplit] = []
        var previous = route[0]
        var splitStart = previous.timestamp

        for point in route.dropFirst() {
            let seconds = point.timestamp.timeIntervalSince(previous.timestamp)
            let meters = point.distance(from: previous)
            // Strict integrity: an invalid leg means that a full continuous
            // kilometre cannot be reconstructed with confidence.
            guard CLLocationCoordinate2DIsValid(point.coordinate),
                  CLLocationCoordinate2DIsValid(previous.coordinate),
                  seconds > 0, seconds <= 120,
                  meters.isFinite, meters >= 0, meters <= 300,
                  meters / seconds <= 12.5,
                  point.horizontalAccuracy < 0 || point.horizontalAccuracy <= 65,
                  previous.horizontalAccuracy < 0 || previous.horizontalAccuracy <= 65
            else { return [] }

            var remainingMeters = meters
            var remainingSeconds = seconds
            while remainingMeters > 0 {
                let needed = 1_000 - accumulatedMeters
                let taken = min(needed, remainingMeters)
                let takenSeconds = remainingSeconds * (taken / remainingMeters)
                accumulatedMeters += taken
                splitSeconds += takenSeconds
                remainingMeters -= taken
                remainingSeconds -= takenSeconds
                if accumulatedMeters >= 999.999 {
                    guard splitSeconds >= 50, splitSeconds <= 2_400 else { return [] }
                    let splitEnd = point.timestamp.addingTimeInterval(-remainingSeconds)
                    completed.append(KilometerSplit(
                        kilometer: completed.count + 1,
                        durationSeconds: splitSeconds,
                        startedAt: splitStart,
                        endedAt: splitEnd
                    ))
                    splitStart = splitEnd
                    accumulatedMeters = 0
                    splitSeconds = 0
                }
            }
            // Preserve stationary time in the next completed kilometre.
            if meters == 0 { splitSeconds += seconds }
            previous = point
        }

        let measured = Double(completed.count) * 1_000 + accumulatedMeters
        if let reportedDistanceMeters,
           reportedDistanceMeters.isFinite, reportedDistanceMeters > 0 {
            // Suppress doubtful GPS splits rather than showing false PBs.
            let difference = abs(measured - reportedDistanceMeters) / reportedDistanceMeters
            guard difference <= 0.15 else { return [] }
        }
        return completed
    }

    /// Indoor Apple Watch/phone recordings have no GPS track. Reconstruct
    /// only fully measured kilometre splits from the actual recorded minute
    /// distance/time samples, never from prescribed belt speed or plan pace.
    static func kilometerSplits(
        from minutes: [ATHLTHRecordedRunningMinute],
        reportedDistanceMeters: Double?
    ) -> [KilometerSplit] {
        guard !minutes.isEmpty, minutes.count <= 2_500 else { return [] }
        var distance = 0.0
        var splitElapsed = 0.0
        var wholeDistance = 0.0
        var results: [KilometerSplit] = []
        for sample in minutes {
            let meters = sample.recordedDistanceMeters
            let seconds = sample.activeSeconds
            guard meters.isFinite, meters >= 0, meters <= 800,
                  seconds.isFinite, seconds > 0, seconds <= 120,
                  meters / seconds <= 9.8 else { return [] }
            wholeDistance += meters
            var available = meters
            var secondsLeft = seconds
            while available > 0 {
                let use = min(1_000 - distance, available)
                let usedSeconds = secondsLeft * (use / available)
                distance += use
                splitElapsed += usedSeconds
                available -= use
                secondsLeft -= usedSeconds
                if distance >= 999.999 {
                    guard (50...2_400).contains(splitElapsed) else { return [] }
                    results.append(KilometerSplit(
                        kilometer: results.count + 1,
                        durationSeconds: splitElapsed
                    ))
                    distance = 0
                    splitElapsed = 0
                }
            }
            if meters == 0 { splitElapsed += seconds }
        }
        if let official = reportedDistanceMeters, official.isFinite, official > 0 {
            guard abs(wholeDistance - official) / official <= 0.20 else {
                return []
            }
        }
        return results
    }

    static func bestKilometer(_ splits: [KilometerSplit]) -> KilometerSplit? {
        splits.min { $0.durationSeconds < $1.durationSeconds }
    }

    /// At least two complete kilometres and >=3% faster finish. No subjective
    /// "strong finish" claims on single-kilometre or incomplete GPS data.
    static func strongFinishPercent(_ splits: [KilometerSplit]) -> Int? {
        guard splits.count >= 2,
              let first = splits.first?.durationSeconds,
              let last = splits.last?.durationSeconds,
              first > 0, last > 0 else { return nil }
        let percent = (first - last) / first * 100
        return percent >= 3 ? Int(percent.rounded()) : nil
    }

    static func elevationProfile(from route: [CLLocation]) -> [ElevationPoint] {
        guard route.count >= 5 else { return [] }
        var points: [ElevationPoint] = []
        var distance = 0.0
        var previous: CLLocation?
        for point in route {
            guard point.altitude.isFinite,
                  point.verticalAccuracy >= 0, point.verticalAccuracy <= 40,
                  CLLocationCoordinate2DIsValid(point.coordinate)
            else { continue }
            if let previous {
                let meters = previous.distance(from: point)
                let seconds = point.timestamp.timeIntervalSince(previous.timestamp)
                guard meters.isFinite, meters >= 0, meters <= 300,
                      seconds > 0, seconds <= 120,
                      meters / seconds <= 12.5,
                      abs(point.altitude - previous.altitude) <= 30
                else {
                    // Discontinuity: do not connect misleading elevation data.
                    return []
                }
                distance += meters
            }
            points.append(ElevationPoint(
                distanceKilometers: distance / 1_000,
                altitudeMeters: point.altitude
            ))
            previous = point
        }
        guard points.count >= 5,
              distance >= 150,
              let lowest = points.map(\.altitudeMeters).min(),
              let highest = points.map(\.altitudeMeters).max(),
              highest - lowest >= 3 else { return [] }
        let strideSize = max(1, Int(ceil(Double(points.count) / 120)))
        return Swift.stride(from: 0, to: points.count, by: strideSize)
            .map { points[$0] } + (points.count > 1 && (points.count - 1) % strideSize != 0
                ? [points[points.count - 1]] : [])
    }
}
