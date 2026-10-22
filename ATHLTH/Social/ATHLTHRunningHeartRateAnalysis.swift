import Foundation

/// A single measured HealthKit heart-rate observation. Never a target or a
/// fabricated interpolation. Persist no raw health observations.
struct ATHLTHRunningHeartRatePoint: Identifiable, Hashable {
    let date: Date
    let bpm: Double

    var id: Date { date }
}

/// Pure, bounded post-run physiology analysis, shared by regular runs and
/// structured intervals. Long sensor gaps do not count as time in a zone.
enum ATHLTHRunningHeartRateAnalysis {
    struct ZoneDuration: Identifiable, Equatable {
        let zone: Int
        let seconds: TimeInterval
        var id: Int { zone }
    }

    static func validPoints(_ points: [ATHLTHRunningHeartRatePoint],
                            from start: Date, through end: Date)
        -> [ATHLTHRunningHeartRatePoint] {
        points.filter {
            $0.date >= start && $0.date <= end &&
            $0.bpm.isFinite && (30...240).contains($0.bpm)
        }
        .sorted { $0.date < $1.date }
    }

    /// Use HealthKit samples for individual completed intervals only when
    /// the recorded active phase timeline aligns with wall-clock workout
    /// time. Paused sessions cannot safely assign a pulse to a phase from
    /// active time alone, so fall back to indexed Watch checkpoints.
    static func phasePoints(
        _ samples: [ATHLTHRunningHeartRatePoint],
        phaseIndex: Int,
        steps: [ATHLTHRecordedRunningStep],
        startedAt: Date,
        endedAt: Date
    ) -> [ATHLTHRunningHeartRatePoint] {
        let ordered = steps.sorted { $0.index < $1.index }
        guard let phase = ordered.first(where: { $0.index == phaseIndex }),
              !samples.isEmpty, endedAt > startedAt,
              ordered.allSatisfy({ $0.activeSeconds.isFinite &&
                                  $0.activeSeconds >= 0 }) else { return [] }
        let recordedTime = ordered.reduce(0.0) { $0 + $1.activeSeconds }
        let clockTime = endedAt.timeIntervalSince(startedAt)
        guard recordedTime > 0,
              abs(recordedTime - clockTime) <= max(20, clockTime * 0.025)
        else { return [] }
        let earlierSeconds = ordered.filter { $0.index < phaseIndex }
            .reduce(0.0) { $0 + $1.activeSeconds }
        let from = startedAt.addingTimeInterval(earlierSeconds)
        let through = from.addingTimeInterval(phase.activeSeconds)
        return validPoints(samples, from: from, through: through)
    }

    /// Bounded sample windows only. The denominator is covered sensor time,
    /// not the full workout duration, when the watch had missing data.
    static func zoneDurations(
        _ samples: [ATHLTHRunningHeartRatePoint],
        maximumBPM: Double?
    ) -> [ZoneDuration] {
        var counts = [Double](repeating: 0, count: 5)
        let ordered = samples.sorted { $0.date < $1.date }
        for i in ordered.indices.dropLast() {
            let seconds = ordered[i + 1].date.timeIntervalSince(ordered[i].date)
            guard seconds > 0, seconds <= 90,
                  let zone = ATHLTHHeartRateZones.measuredZone(
                    heartRateBPM: ordered[i].bpm, maximumBPM: maximumBPM
                  ) else { continue }
            counts[zone - 1] += seconds
        }
        return counts.enumerated().map { ZoneDuration(zone: $0.offset + 1, seconds: $0.element) }
    }

    static func average(
        _ samples: [ATHLTHRunningHeartRatePoint],
        from start: Date,
        through end: Date
    ) -> Double? {
        let values = samples.filter {
            $0.date >= start && $0.date <= end &&
            $0.bpm.isFinite && (30...240).contains($0.bpm)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0) { $0 + $1.bpm } / Double(values.count)
    }

    /// Keep chart rendering light on the Watch-connected iPhone.
    static func chartPoints(
        _ samples: [ATHLTHRunningHeartRatePoint], limit: Int = 280
    ) -> [ATHLTHRunningHeartRatePoint] {
        guard samples.count > limit, limit > 1 else { return samples }
        let stride = Double(samples.count - 1) / Double(limit - 1)
        return (0..<limit).map { samples[Int((Double($0) * stride).rounded())] }
    }
}
