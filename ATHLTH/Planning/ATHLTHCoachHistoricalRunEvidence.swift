import Foundation

/// Account-local, actually recorded first-kilometre evidence. Planned pace,
/// incomplete recordings and manually entered treadmill speed are never
/// silently presented as a previous workout's measured performance.
struct ATHLTHCoachHistoricalRunReference: Identifiable, Hashable {
    let id: UUID
    let title: String
    let completedAt: Date
    let firstKilometerSeconds: Double
}

enum ATHLTHCoachHistoricalRunEvidence {
    static func reference(
        from record: ATHLTHCompletedRunningPerformance
    ) -> ATHLTHCoachHistoricalRunReference? {
        guard !record.userReported,
              let minutes = record.minutes, !minutes.isEmpty else { return nil }
        let ordered = minutes.sorted {
            if $0.stepIndex != $1.stepIndex {
                return $0.stepIndex < $1.stepIndex
            }
            return $0.stepElapsedAtEndSeconds < $1.stepElapsedAtEndSeconds
        }
        var meters = 0.0
        var elapsed = 0.0
        for part in ordered {
            let seconds = part.activeSeconds
            let distance = part.recordedDistanceMeters
            guard seconds.isFinite, (1...120).contains(seconds),
                  distance.isFinite, distance >= 0,
                  part.stepElapsedAtEndSeconds.isFinite,
                  part.stepElapsedAtEndSeconds >= 0 else { return nil }
            if meters + distance >= 1_000 {
                guard distance > 0 else { return nil }
                let remaining = 1_000 - meters
                elapsed += seconds * (remaining / distance)
                guard (120...1_800).contains(elapsed) else { return nil }
                return ATHLTHCoachHistoricalRunReference(
                    id: record.id, title: record.title,
                    completedAt: record.completedAt,
                    firstKilometerSeconds: elapsed
                )
            }
            meters += distance
            elapsed += seconds
        }
        return nil
    }

    static func available(userID: UUID) -> [ATHLTHCoachHistoricalRunReference] {
        ATHLTHRunningPerformanceHistory.load(userID: userID)
            .compactMap(reference(from:))
            .sorted { $0.completedAt > $1.completedAt }
    }
}
