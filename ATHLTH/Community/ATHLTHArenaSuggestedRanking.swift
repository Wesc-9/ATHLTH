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

/// A linked Live Ghost duel must be started from an explicitly chosen
/// Arena route round. Never infer the first round or attach a generic duel.
enum ATHLTHArenaLiveRoundSelection {
    static func linkedRoundID(
        selectedRoundID: UUID?,
        selectedRouteID: UUID?,
        rounds: [ATHLTHArenaRemoteProposal]
    ) -> UUID? {
        guard let selectedRoundID,
              let selectedRouteID,
              let selected = rounds.first(where: {
                  $0.id == selectedRoundID
              }),
              selected.template == .fastestRoute,
              selected.routeSnapshot?.routeID == selectedRouteID else {
            return nil
        }
        return selected.id
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

/// Compare the user's last two *reported* Live Ghost times within the
/// very same approved Arena route round. Never compare times across different
/// courses, infer GPS verification, or award points.
struct ATHLTHArenaLiveTimeTrend: Identifiable, Equatable {
    let roundID: UUID
    let previousSeconds: TimeInterval
    let latestSeconds: TimeInterval
    let finishedAt: Date
    let attempts: Int

    var id: UUID { roundID }
    /// Positive: improved (faster). Negative: slower. No ranking impact.
    var improvementSeconds: TimeInterval { previousSeconds - latestSeconds }

    static func summaries(
        challenges: [GhostFriendRaceChallengeRecord],
        rooms: [LiveGhostRaceRoomRecord],
        participants: [LiveGhostRaceParticipantRecord],
        eligibleRoundIDs: Set<UUID>,
        currentUserID: UUID
    ) -> [ATHLTHArenaLiveTimeTrend] {
        let roomByID = Dictionary(
            rooms.map { ($0.challengeID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let participantsByChallenge = Dictionary(
            grouping: participants, by: \.challengeID
        )
        var seen = Set<UUID>()
        var byRound: [UUID: [(Date, UUID, TimeInterval)]] = [:]

        for challenge in challenges {
            guard let roundID = challenge.arenaRoundID,
                  eligibleRoundIDs.contains(roundID),
                  challenge.sourceKind == "planned_route",
                  challenge.status == .accepted,
                  currentUserID == challenge.senderID ||
                      currentUserID == challenge.recipientID,
                  seen.insert(challenge.id).inserted,
                  let room = roomByID[challenge.id],
                  room.status == .finished,
                  let finishedAt = room.finishedAt else {
                continue
            }

            let submissions = participantsByChallenge[challenge.id] ?? []
            let senderTime = submissions.first {
                $0.userID == challenge.senderID
            }?.elapsedSeconds
            let recipientTime = submissions.first {
                $0.userID == challenge.recipientID
            }?.elapsedSeconds
            guard let candidate = ATHLTHArenaLiveDuelReview.candidate(
                senderID: challenge.senderID,
                recipientID: challenge.recipientID,
                senderSeconds: senderTime,
                recipientSeconds: recipientTime,
                reportedWinnerID: room.winnerID,
                isFinished: true
            ) else { continue }

            let ownTime = currentUserID == challenge.senderID
                ? candidate.senderSeconds : candidate.recipientSeconds
            byRound[roundID, default: []].append(
                (finishedAt, challenge.id, ownTime)
            )
        }

        return byRound.compactMap { roundID, attempts in
            guard attempts.count >= 2 else { return nil }
            let chronological = attempts.sorted {
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                return $0.1.uuidString < $1.1.uuidString
            }
            let previous = chronological[chronological.count - 2]
            let latest = chronological[chronological.count - 1]
            return ATHLTHArenaLiveTimeTrend(
                roundID: roundID,
                previousSeconds: previous.2,
                latestSeconds: latest.2,
                finishedAt: latest.0,
                attempts: attempts.count
            )
        }
        .sorted {
            if $0.finishedAt != $1.finishedAt {
                return $0.finishedAt > $1.finishedAt
            }
            return $0.roundID.uuidString < $1.roundID.uuidString
        }
    }
}

/// Progress represents server-reviewed Arena rounds, not completed
/// workouts. Rejected and expired proposals never count as approved.
struct ATHLTHArenaRoundProgress: Equatable {
    let total: Int
    let approved: Int
    let pending: Int

    var unresolved: Int { max(0, total - approved - pending) }

    var approvedFraction: Double {
        total > 0 ? Double(approved) / Double(total) : 0
    }

    static func summarize(
        roundIDs: [UUID],
        results: [ATHLTHArenaRoundResult]
    ) -> ATHLTHArenaRoundProgress {
        let uniqueRounds = Set(roundIDs)
        let eligible = results.filter { uniqueRounds.contains($0.roundID) }
        let approved = Set(eligible.filter { $0.status == "approved" }.map(\.roundID))
        let pending = Set(eligible.filter {
            $0.status == "pending" && !approved.contains($0.roundID)
        }.map(\.roundID))
        return ATHLTHArenaRoundProgress(
            total: uniqueRounds.count,
            approved: approved.count,
            pending: pending.count
        )
    }
}

struct ATHLTHArenaTeamStanding: Identifiable, Equatable {
    let teamIndex: Int
    let points: Double
    let athleteCount: Int
    var id: Int { teamIndex }
}

/// Uses ONLY settled member points from Arena's server-side score engine.
/// Does not infer wins, add bonus points or re-score previous workouts.
/// A *draft-only* starting suggestion: balances the number of accepted
/// athletes, not their ability or predicted outcome. Users can adjust the
/// choices before the organizer confirms them through the server RPC.
/// Pure relay draft validation, used by the editor before server-side
/// checks. Never treats a leg order as evidence of a completed workout.
enum ATHLTHArenaRelayPlanning {
    static func isValid(
        firstTeam: [UUID],
        secondTeam: [UUID],
        legOrders: [UUID: Int],
        routeRoundID: UUID?,
        availableRouteRoundIDs: Set<UUID>
    ) -> Bool {
        guard let routeRoundID,
              availableRouteRoundIDs.contains(routeRoundID),
              (2...25).contains(firstTeam.count),
              firstTeam.count == secondTeam.count else {
            return false
        }
        let combined = firstTeam + secondTeam
        guard Set(combined).count == combined.count,
              Set(legOrders.keys) == Set(combined) else {
            return false
        }
        for team in [firstTeam, secondTeam] {
            let positions = team.compactMap { legOrders[$0] }
            guard positions.count == team.count,
                  Set(positions) == Set(1...team.count) else {
                return false
            }
        }
        return true
    }
}

enum ATHLTHArenaTeamBalancer {
    static func suggestedAssignments(
        members: [ATHLTHArenaRemoteMember]
    ) -> [UUID: Int]? {
        guard (4...50).contains(members.count),
              members.allSatisfy({
                  $0.response == "accepted" && $0.userID != nil
              }),
              Set(members.map(\.slotID)).count == members.count,
              Set(members.compactMap(\.userID)).count == members.count,
              Set(members.map(\.seriesID)).count == 1
        else { return nil }

        // Sorting makes the draft stable across app refreshes and devices;
        // no fabricated performance ratings or personal data are consulted.
        let ordered = members.sorted {
            $0.slotID.uuidString < $1.slotID.uuidString
        }
        var proposed: [UUID: Int] = [:]
        for (index, member) in ordered.enumerated() {
            proposed[member.slotID] = index.isMultiple(of: 2) ? 1 : 2
        }
        return proposed
    }
}

enum ATHLTHArenaTeamStandings {
    static func calculate(
        members: [ATHLTHArenaRemoteMember],
        assignments: [ATHLTHArenaTeamAssignment]
    ) -> [ATHLTHArenaTeamStanding] {
        guard !assignments.isEmpty else { return [] }
        let memberBySlot = Dictionary(
            uniqueKeysWithValues: members.map { ($0.slotID, $0) }
        )
        var seen = Set<UUID>()
        let valid = assignments.filter {
            (1...2).contains($0.teamIndex) &&
            memberBySlot[$0.slotID] != nil &&
            seen.insert($0.slotID).inserted
        }
        return (1...2).map { team in
            let slots = valid.filter { $0.teamIndex == team }
            let points = slots.reduce(0.0) { total, assignment in
                let settled = memberBySlot[assignment.slotID]?.points ?? 0
                return total + (settled.isFinite ? max(0, settled) : 0)
            }
            return ATHLTHArenaTeamStanding(
                teamIndex: team,
                points: points,
                athleteCount: slots.count
            )
        }
    }
}

/// Only used as an on-device suggestion for a runner's OWN relay leg.
/// It does not attest a workout on the server or award team points.
enum ATHLTHArenaRelayGPSMatch {
    static func qualifies(
        routeLengthMeters: Double,
        coveredMeters: Double,
        elapsedSeconds: Double,
        routeMatchPercent: Double,
        startGapMeters: Double,
        endGapMeters: Double
    ) -> Bool {
        guard routeLengthMeters.isFinite, coveredMeters.isFinite,
              elapsedSeconds.isFinite, routeMatchPercent.isFinite,
              startGapMeters.isFinite, endGapMeters.isFinite,
              (100...500_000).contains(routeLengthMeters),
              (10...86_400).contains(elapsedSeconds),
              coveredMeters > 0,
              abs(coveredMeters - routeLengthMeters) <= routeLengthMeters * 0.05,
              (90...100).contains(routeMatchPercent),
              (0...120).contains(startGapMeters),
              (0...120).contains(endGapMeters) else {
            return false
        }
        return true
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
