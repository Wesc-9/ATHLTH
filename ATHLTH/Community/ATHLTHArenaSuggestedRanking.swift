import Foundation

/// Provisional, participant-shared workout leaderboard. These values are
/// not independently attested and never grant points by themselves.
struct ATHLTHArenaSuggestedStanding: Identifiable, Equatable {
    let slotID: UUID
    let result: Double
    let contributions: Int
    var id: UUID { slotID }
}

/// Informational Live Ghost result, not an Arena score or proof of route
/// compliance. Both submitted times must be sane and match the server's
/// announced winner (including its 0.5-second tie threshold).
struct ATHLTHArenaLiveDuelCandidate: Equatable {
    let winnerID: UUID?
    let senderSeconds: TimeInterval
    let recipientSeconds: TimeInterval
    let marginSeconds: TimeInterval
}

enum ATHLTHArenaLiveDuelReview {
    static func candidate(
        senderID: UUID,
        recipientID: UUID,
        senderSeconds: TimeInterval?,
        recipientSeconds: TimeInterval?,
        reportedWinnerID: UUID?,
        isFinished: Bool
    ) -> ATHLTHArenaLiveDuelCandidate? {
        guard isFinished,
              senderID != recipientID,
              let senderSeconds, let recipientSeconds,
              senderSeconds.isFinite, recipientSeconds.isFinite,
              (60...86_400).contains(senderSeconds),
              (60...86_400).contains(recipientSeconds) else {
            return nil
        }

        let difference = senderSeconds - recipientSeconds
        let winner: UUID?
        if abs(difference) < 0.5 {
            winner = nil
        } else {
            winner = difference < 0 ? senderID : recipientID
        }

        guard winner == reportedWinnerID else { return nil }
        return ATHLTHArenaLiveDuelCandidate(
            winnerID: winner,
            senderSeconds: senderSeconds,
            recipientSeconds: recipientSeconds,
            marginSeconds: abs(difference)
        )
    }
}

enum ATHLTHArenaSuggestedRanking {
    /// A suggested pace target only, never a verified result or a replay of
    /// someone else's private GPS trace. Based on an explicitly shared round
    /// result, and excluded when the report is absent or implausible.
    static func fastestSharedRivalTime(
        roundID: UUID,
        currentUserID: UUID,
        evidence: [ATHLTHArenaWorkoutEvidence]
    ) -> TimeInterval? {
        evidence
            .filter {
                $0.roundID == roundID &&
                $0.userID != currentUserID &&
                $0.activityType == "running" &&
                $0.metricType == "elapsed_seconds" &&
                $0.metricValue.isFinite &&
                (60...86_400).contains($0.metricValue) &&
                ($0.reportedRouteMatchPercent.map { (90...100).contains($0) } ?? false)
            }
            .map(\.metricValue)
            .min()
    }

    static func standings(
        template: ATHLTHArenaRoundTemplate,
        roundID: UUID,
        evidence: [ATHLTHArenaWorkoutEvidence]
    ) -> [ATHLTHArenaSuggestedStanding] {
        let expectedMetric: String
        switch template {
        case .fastest5K, .fastest1K, .fastestDistance, .fastestRoute:
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
            if template == .fastest5K || template == .fastest1K || template == .fastestDistance || template == .fastestRoute {
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
                return template == .fastest5K || template == .fastest1K || template == .fastestDistance || template == .fastestRoute
                    ? lhs.result < rhs.result
                    : lhs.result > rhs.result
            }
            return lhs.slotID.uuidString < rhs.slotID.uuidString
        }
    }

    /// Safely preselect an outcome only when *every* competing slot has
    /// shared evidence and no ranked/award boundary is tied. No points
    /// are granted: the organizer must explicitly submit the proposal
    /// and all active participants still vote.
    static func eligibleSuggestion(
        template: ATHLTHArenaRoundTemplate,
        scoring: ATHLTHArenaScoring,
        roundID: UUID,
        requiredSlots: [UUID],
        evidence: [ATHLTHArenaWorkoutEvidence]
    ) -> [UUID]? {
        guard requiredSlots.count >= 2 else { return nil }
        let ranked = standings(
            template: template,
            roundID: roundID,
            evidence: evidence
        )
        let required = Set(requiredSlots)
        guard Set(ranked.map(\.slotID)) == required,
              ranked.count == requiredSlots.count
        else { return nil }

        let awarded = scoring == .winner ? 1 : min(3, ranked.count)
        guard awarded > 0 else { return nil }

        // A tied award position is ambiguous, even if the tie spans the
        // first excluded athlete. Never silently break ties using a UUID.
        for index in 1..<ranked.count {
            if abs(ranked[index].result - ranked[index - 1].result) < 0.001,
               index <= awarded {
                return nil
            }
        }
        return Array(ranked.prefix(awarded).map(\.slotID))
    }

    static func hasTieAtTop(
        _ standings: [ATHLTHArenaSuggestedStanding]
    ) -> Bool {
        guard standings.count >= 2 else { return false }
        return abs(standings[0].result - standings[1].result) < 0.001
    }
}
