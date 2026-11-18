import Foundation

/// Pace for a complete, measured rolling kilometre. No GPS-coordinate
/// displacement, manually entered belt speed or planned target may be used.
struct ATHLTHAudioCoachRollingKilometer {
    private struct Sample {
        var meters: Double
        var activeSeconds: Double
    }
    private var samples: [Sample] = []
    private(set) var paceSecondsPerKilometer: Double?

    mutating func reset() {
        samples.removeAll(keepingCapacity: false)
        paceSecondsPerKilometer = nil
    }

    mutating func record(distanceMeters: Double, activeSeconds: Double) {
        guard distanceMeters.isFinite, activeSeconds.isFinite,
              distanceMeters >= 0, activeSeconds >= 0 else { return }
        if let previous = samples.last {
            if distanceMeters < previous.meters - 0.5 ||
               activeSeconds < previous.activeSeconds {
                reset() // A new activity must never reuse the previous one's samples.
            } else if distanceMeters <= previous.meters &&
                      activeSeconds <= previous.activeSeconds {
                return
            }
        }
        samples.append(Sample(meters: distanceMeters, activeSeconds: activeSeconds))
        let boundary = distanceMeters - 1_000
        // Keep the sample just before the rolling cutoff for interpolation.
        while samples.count > 2 && samples[1].meters <= boundary {
            samples.removeFirst()
        }
        if samples.count > 480 { samples.removeFirst(samples.count - 480) }
        guard boundary >= 0, let first = samples.first,
              first.meters <= boundary, samples.count >= 2 else {
            paceSecondsPerKilometer = nil
            return
        }
        let next = samples[1]
        let span = next.meters - first.meters
        guard span > 0 else { paceSecondsPerKilometer = nil; return }
        let fraction = min(max((boundary - first.meters) / span, 0), 1)
        let crossingTime = first.activeSeconds +
            fraction * (next.activeSeconds - first.activeSeconds)
        let seconds = activeSeconds - crossingTime
        // Unknown or unlikely intervals are omitted rather than announced.
        paceSecondsPerKilometer = seconds.isFinite && (120...1_800).contains(seconds)
            ? seconds : nil
    }
}
