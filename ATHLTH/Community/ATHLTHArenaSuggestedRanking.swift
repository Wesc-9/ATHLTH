import Foundation

/// Provisional, participant-shared workout leaderboard. These values are
/// not independently attested and never grant points by themselves.
struct ATHLTHArenaSuggestedStanding: Identifiable, Equatable {
    let slotID: UUID
    let result: Double
    let contributions: Int
    var id: UUID { slotID }
}

enum ATHLTHArenaSuggestedRanking {
    static func standings(
        template: ATHLTHArenaRoundTemplate,
        roundID: UUID,
        evidence: [ATHLTHArenaWorkoutEvidence]
    ) -> [ATHLTHArenaSuggestedStanding] {
        let expectedMetric: String
        switch template {
        case .fastest5K, .fastest1K:
            expectedMetric = "elapsed_seconds"
        case .mostDistance:
            expectedMetric = "distance_meters"
        case .mostWorkouts:
            expectedMetric = "completed_workout"
        case .mostRepetitions, .custom:
            return []
        }
        let valid = evidence.filter {
            $0.roundID == roundID &&
            $0.metricType == expectedMetric &&
            $0.metricValue.isFinite &&
            $0.metricValue > 0
        }
        let groups = Dictionary(grouping: valid, by: \.slotID)
        let values = groups.compactMap { slot, entries -> ATHLTHArenaSuggestedStanding? in
            guard !entries.isEmpty else { return nil }
            let result: Double
            if template == .fastest5K || template == .fastest1K {
                result = entries.map(\.metricValue).min() ?? 0
            } else if template == .mostDistance {
                result = entries.reduce(0.0) { $0 + $1.metricValue }
            } else {
                result = Double(entries.count)
            }
            return ATHLTHArenaSuggestedStanding(
                slotID: slot, result: result, contributions: entries.count
            )
        }
        return values.sorted { lhs, rhs in
            if lhs.result != rhs.result {
                return template == .fastest5K || template == .fastest1K
                    ? lhs.result < rhs.result
                    : lhs.result > rhs.result
            }
            return lhs.slotID.uuidString < rhs.slotID.uuidString
        }
    }

    static func hasTieAtTop(
        _ standings: [ATHLTHArenaSuggestedStanding]
    ) -> Bool {
        guard standings.count >= 2 else { return false }
        return abs(standings[0].result - standings[1].result) < 0.001
    }
}
