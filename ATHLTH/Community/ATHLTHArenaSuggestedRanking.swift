import Foundation

/// Separate active duels from immutable race history. A completed or
/// cancelled room never re-enters the live list, while an already-started
/// race stays live even if its initial invitation has expired.
enum ATHLTHArenaLiveDuelBrowsing {
    static func isHistorical(
        roomStatus: LiveGhostRaceRoomStatus?,
        expiresAt: Date,
        now: Date = Date()
    ) -> Bool {
        switch roomStatus {
        case .finished, .cancelled:
            return true
        case .racing, .countdown:
            return false
        case .lobby, nil:
            return expiresAt <= now
        }
    }
}

/// Whether a linked Arena Live Ghost room may be reopened. A started
/// race remains recoverable after invite expiry; an unstarted or finished
/// race may never start a new workout from a stale invitation.
enum ATHLTHArenaLinkedRaceAccess {
    static func canOpen(
        roomStatus: LiveGhostRaceRoomStatus?,
        expiresAt: Date,
        now: Date = Date()
    ) -> Bool {
        switch roomStatus {
        case .finished, .cancelled:
            return false
        case .racing, .countdown:
            return true
        case .lobby, nil:
            return expiresAt > now
        }
    }
}

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

/// Compact live-race telemetry for the Arena recap. These are reported
/// estimates, not GPS verification or a basis for awarding points.
struct ATHLTHArenaLiveDuelHighlights: Equatable {
    let peakLeadMeters: Double
    let leadChanges: Int
}

enum ATHLTHArenaLiveDuelReview {
    /// Preselect ranks only when a completed live duel has a single winner.
    /// This NEVER awards points: every result still needs review and votes.
    static func proposedSlots(
        candidate: ATHLTHArenaLiveDuelCandidate,
        senderID: UUID,
        recipientID: UUID,
        senderSlotID: UUID,
        recipientSlotID: UUID,
        scoring: ATHLTHArenaScoring
    ) -> [UUID]? {
        guard senderID != recipientID,
              senderSlotID != recipientSlotID,
              let winner = candidate.winnerID,
              winner == senderID || winner == recipientID else {
            return nil
        }
        let first = winner == senderID ? senderSlotID : recipientSlotID
        let second = winner == senderID ? recipientSlotID : senderSlotID
        return scoring == .winner ? [first] : [first, second]
    }

    static func highlights(
        senderPeakLeadMeters: Double,
        recipientPeakLeadMeters: Double,
        leadChangeCount: Int
    ) -> ATHLTHArenaLiveDuelHighlights? {
        guard senderPeakLeadMeters.isFinite,
              recipientPeakLeadMeters.isFinite,
              (0...100_000).contains(senderPeakLeadMeters),
              (0...100_000).contains(recipientPeakLeadMeters),
              (0...10_000).contains(leadChangeCount) else {
            return nil
        }
        return ATHLTHArenaLiveDuelHighlights(
            peakLeadMeters: max(senderPeakLeadMeters, recipientPeakLeadMeters),
            leadChanges: leadChangeCount
        )
    }

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

/// Read-only summary of this Arena series' completed, consistent Live Ghost
/// races. It deliberately excludes incomplete or disputed submissions and
/// never allocates points or overwrites the official Arena standings.
struct ATHLTHArenaRivalrySummary: Equatable {
    let wins: Int
    let losses: Int
    let ties: Int
    let excluded: Int

    var finishedCount: Int { wins + losses + ties }

    static func calculate(
        challenges: [GhostFriendRaceChallengeRecord],
        rooms: [LiveGhostRaceRoomRecord],
        participants: [LiveGhostRaceParticipantRecord],
        eligibleRoundIDs: Set<UUID>,
        currentUserID: UUID
    ) -> ATHLTHArenaRivalrySummary {
        let roomByID = Dictionary(
            rooms.map { ($0.challengeID, $0) },
            uniquingKeysWith: { latest, _ in latest }
        )
        let timesByChallenge = Dictionary(grouping: participants, by: \.challengeID)
        var wins = 0
        var losses = 0
        var ties = 0
        var excluded = 0
        var seen = Set<UUID>()
        for challenge in challenges {
            guard let roundID = challenge.arenaRoundID,
                  eligibleRoundIDs.contains(roundID),
                  challenge.status == .accepted,
                  challenge.senderID == currentUserID ||
                    challenge.recipientID == currentUserID,
                  seen.insert(challenge.id).inserted
            else { continue }

            guard let room = roomByID[challenge.id],
                  room.status == .finished else { continue }
            let participantsForRace = timesByChallenge[challenge.id] ?? []
            let senderTime = participantsForRace.first {
                $0.userID == challenge.senderID
            }?.elapsedSeconds
            let recipientTime = participantsForRace.first {
                $0.userID == challenge.recipientID
            }?.elapsedSeconds

            guard let result = ATHLTHArenaLiveDuelReview.candidate(
                senderID: challenge.senderID,
                recipientID: challenge.recipientID,
                senderSeconds: senderTime,
                recipientSeconds: recipientTime,
                reportedWinnerID: room.winnerID,
                isFinished: true
            ) else {
                excluded += 1
                continue
            }

            if let winnerID = result.winnerID {
                if winnerID == currentUserID { wins += 1 }
                else { losses += 1 }
            } else {
                ties += 1
            }
        }
        return ATHLTHArenaRivalrySummary(
            wins: wins, losses: losses, ties: ties, excluded: excluded
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
            guard $0.roundID == roundID,
                  $0.metricType == expectedMetric,
                  $0.metricValue.isFinite,
                  $0.metricValue > 0 else {
                return false
            }
            // A shared elapsed time is not a route attempt without a
            // satisfactory reported match to this exact round's course.
            // Device reports remain provisional until participant approval.
            if template == .fastestRoute {
                return $0.activityType == "running" &&
                    ($0.reportedRouteMatchPercent.map {
                        $0.isFinite && (90...100).contains($0)
                    } ?? false)
            }
            return true
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
