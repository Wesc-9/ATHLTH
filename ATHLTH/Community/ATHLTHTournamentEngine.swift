import Foundation

/// Shared tournament rules: never infer a winner from an unverified workout.
/// Scores advance only after an independent opponent confirms the result.
/// Practice rounds can have results but cannot alter a table or an elimination.
enum ATHLTHTournamentPhase: String, Codable, CaseIterable {
    case warmup, league, group, cup, playoff

    var awardsPoints: Bool { self == .league || self == .group }
    var eliminates: Bool { self == .cup || self == .playoff }
    var acceptsDraw: Bool { !eliminates }
}

struct ATHLTHTournamentFixture: Identifiable, Codable, Equatable {
    let id: UUID
    let phase: ATHLTHTournamentPhase
    let round: Int
    let groupIndex: Int?
    let homeID: UUID
    let awayID: UUID?
    var result: ATHLTHTournamentApprovedResult?

    init(
        id: UUID = UUID(), phase: ATHLTHTournamentPhase, round: Int,
        groupIndex: Int? = nil, homeID: UUID, awayID: UUID?,
        result: ATHLTHTournamentApprovedResult? = nil
    ) {
        self.id = id
        self.phase = phase
        self.round = round
        self.groupIndex = groupIndex
        self.homeID = homeID
        self.awayID = awayID
        self.result = result
    }

    var isBye: Bool { awayID == nil }

    /// An automatic bye advances a real athlete, but gives no table points.
    var approvedWinnerID: UUID? {
        if isBye { return homeID }
        guard let result else { return nil }
        guard phase.eliminates else { return nil }
        if result.homeScore == result.awayScore { return nil }
        return result.homeScore > result.awayScore ? homeID : awayID
    }

    var isComplete: Bool { isBye || result != nil }
}

struct ATHLTHTournamentApprovedResult: Codable, Equatable {
    let homeScore: Double
    let awayScore: Double
    let proposedBy: UUID
    let approvedBy: UUID
    let approvedAt: Date
    let evidenceID: UUID?

    /// A participant cannot approve their own match report.
    init?(
        homeScore: Double, awayScore: Double,
        proposedBy: UUID, approvedBy: UUID,
        approvedAt: Date = Date(), evidenceID: UUID? = nil
    ) {
        guard proposedBy != approvedBy,
              homeScore.isFinite, awayScore.isFinite,
              homeScore >= 0, awayScore >= 0
        else { return nil }
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.proposedBy = proposedBy
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.evidenceID = evidenceID
    }
}

struct ATHLTHTournamentStanding: Identifiable, Equatable {
    let id: UUID
    let username: String
    var played = 0
    var wins = 0
    var draws = 0
    var losses = 0
    var scored: Double = 0
    var conceded: Double = 0
    var points = 0
    var difference: Double { scored - conceded }
}

enum ATHLTHTournamentEngineError: Error, Equatable {
    case tooFewParticipants
    case duplicateParticipant
    case invalidGroupSize
    case invalidQualifierCount
    case matchNotFound
    case resultAlreadyFinal
    case invalidApprovers
    case drawNotPermitted
    case roundNotComplete
    case notEnoughQualifiers
}

/// Deterministic scheduling and standings. Each match is derived from an
/// immutable participant ID, never a mutable username or display name.
enum ATHLTHTournamentEngine {
    static func validate(
        _ roster: [ATHLTHTournamentParticipant],
        groupSize: Int = 4, qualifiersPerGroup: Int = 2
    ) throws {
        guard roster.count >= 2 && roster.count <= 128 else {
            throw ATHLTHTournamentEngineError.tooFewParticipants
        }
        guard Set(roster.map(\.id)).count == roster.count else {
            throw ATHLTHTournamentEngineError.duplicateParticipant
        }
        guard (2...16).contains(groupSize) else {
            throw ATHLTHTournamentEngineError.invalidGroupSize
        }
        guard (1...groupSize).contains(qualifiersPerGroup) else {
            throw ATHLTHTournamentEngineError.invalidQualifierCount
        }
    }

    /// Circle-method round robin; odd player counts rotate against a bye,
    /// leaving exactly n(n-1)/2 actual fixtures and no phantom matches.
    static func roundRobin(
        _ ids: [UUID], phase: ATHLTHTournamentPhase,
        groupIndex: Int? = nil, firstRound: Int = 1
    ) -> [ATHLTHTournamentFixture] {
        guard ids.count >= 2 else { return [] }
        var rotating: [UUID?] = ids.map(Optional.some)
        if rotating.count % 2 == 1 { rotating.append(nil) }
        let size = rotating.count
        var fixtures: [ATHLTHTournamentFixture] = []
        for turn in 0..<(size - 1) {
            for pair in 0..<(size / 2) {
                guard let first = rotating[pair],
                      let second = rotating[size - 1 - pair] else { continue }
                let reverse = (turn + pair).isMultiple(of: 2)
                fixtures.append(
                    ATHLTHTournamentFixture(
                        phase: phase,
                        round: firstRound + turn,
                        groupIndex: groupIndex,
                        homeID: reverse ? second : first,
                        awayID: reverse ? first : second
                    )
                )
            }
            let last = rotating.removeLast()
            rotating.insert(last, at: 1)
        }
        return fixtures
    }

    static func warmups(
        _ roster: [ATHLTHTournamentParticipant],
        rounds: [ATHLTHTournamentWarmupRound]
    ) -> [ATHLTHTournamentFixture] {
        guard roster.count >= 2 else { return [] }
        let all = roundRobin(roster.map(\.id), phase: .warmup)
        let scheduled = Set(all.map(\.round)).sorted()
        return rounds.enumerated().flatMap { index, _ -> [ATHLTHTournamentFixture] in
            let selectedRound = scheduled[index % max(1, scheduled.count)]
            return all.filter { $0.round == selectedRound }.map {
                ATHLTHTournamentFixture(
                    phase: .warmup, round: index + 1,
                    homeID: $0.homeID, awayID: $0.awayID
                )
            }
        }
    }

    static func initialFixtures(for draft: ATHLTHTournamentDraft)
        throws -> [ATHLTHTournamentFixture] {
        try validate(
            draft.participants,
            groupSize: draft.groupSize,
            qualifiersPerGroup: draft.qualifiersPerGroup
        )
        let practices = warmups(draft.participants, rounds: draft.warmupRounds)
        switch draft.format {
        case .league:
            return practices + roundRobin(
                draft.participants.map(\.id), phase: .league
            )
        case .groups:
            let members = ATHLTHTournamentStructure.groups(
                draft.participants, size: draft.groupSize
            )
            let leagueFixtures = members.enumerated().flatMap { index, group in
                roundRobin(group.map(\.id), phase: .group, groupIndex: index)
            }
            return practices + leagueFixtures
        case .cup:
            return practices + firstCupFixtures(draft.participants.map(\.id))
        }
    }

    /// Byes are spread one per match; a bye never creates an automatic score
    /// and does not count as a win in league standings.
    static func firstCupFixtures(
        _ athletes: [UUID], phase: ATHLTHTournamentPhase = .cup,
        round: Int = 1
    ) -> [ATHLTHTournamentFixture] {
        guard !athletes.isEmpty else { return [] }
        let target = ATHLTHTournamentStructure.bracketSize(athletes.count)
        let byes = target - athletes.count
        var index = 0
        return (0..<(target / 2)).map { match in
            let player = athletes[index]
            index += 1
            let rival: UUID?
            if match < byes {
                rival = nil
            } else {
                rival = athletes[index]
                index += 1
            }
            return ATHLTHTournamentFixture(
                phase: phase, round: round, homeID: player, awayID: rival
            )
        }
    }

    static func approve(
        _ fixture: ATHLTHTournamentFixture,
        result: ATHLTHTournamentApprovedResult
    ) throws -> ATHLTHTournamentFixture {
        guard fixture.awayID != nil else {
            throw ATHLTHTournamentEngineError.invalidApprovers
        }
        guard fixture.result == nil else {
            throw ATHLTHTournamentEngineError.resultAlreadyFinal
        }
        guard let rival = fixture.awayID,
              [fixture.homeID, rival].contains(result.proposedBy),
              [fixture.homeID, rival].contains(result.approvedBy)
        else { throw ATHLTHTournamentEngineError.invalidApprovers }
        guard fixture.phase.acceptsDraw ||
                result.homeScore != result.awayScore
        else { throw ATHLTHTournamentEngineError.drawNotPermitted }
        var copy = fixture
        copy.result = result
        return copy
    }

    static func standings(
        for roster: [ATHLTHTournamentParticipant],
        fixtures: [ATHLTHTournamentFixture],
        groupIndex: Int? = nil,
        winPoints: Int = 3, drawPoints: Int = 1
    ) -> [ATHLTHTournamentStanding] {
        var values: [UUID: ATHLTHTournamentStanding] = [:]
        for athlete in roster {
            values[athlete.id] = ATHLTHTournamentStanding(
                id: athlete.id, username: athlete.username
            )
        }
        for match in fixtures {
            guard match.phase.awardsPoints,
                  match.groupIndex == groupIndex,
                  let result = match.result,
                  let other = match.awayID,
                  var home = values[match.homeID], var away = values[other]
            else { continue }
            home.played += 1
            away.played += 1
            home.scored += result.homeScore
            away.scored += result.awayScore
            home.conceded += result.awayScore
            away.conceded += result.homeScore
            if result.homeScore > result.awayScore {
                home.wins += 1
                away.losses += 1
                home.points += winPoints
            } else if result.homeScore < result.awayScore {
                away.wins += 1
                home.losses += 1
                away.points += winPoints
            } else {
                home.draws += 1
                away.draws += 1
                home.points += drawPoints
                away.points += drawPoints
            }
            values[home.id] = home
            values[away.id] = away
        }
        return values.values.sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.difference != b.difference { return a.difference > b.difference }
            if a.scored != b.scored { return a.scored > b.scored }
            if a.wins != b.wins { return a.wins > b.wins }
            return a.username.localizedStandardCompare(b.username) == .orderedAscending
        }
    }

    /// No next cup round until *every* match in the previous round is
    /// independently confirmed. A bye advances, never eliminating a user.
    static func nextKnockoutRound(
        after fixtures: [ATHLTHTournamentFixture],
        phase: ATHLTHTournamentPhase
    ) throws -> [ATHLTHTournamentFixture] {
        let matches = fixtures.filter { $0.phase == phase }
        guard !matches.isEmpty && phase.eliminates else {
            throw ATHLTHTournamentEngineError.matchNotFound
        }
        let round = matches.map(\.round).max() ?? 0
        let current = matches.filter { $0.round == round }
        guard current.allSatisfy(\.isComplete) else {
            throw ATHLTHTournamentEngineError.roundNotComplete
        }
        let winners = current.compactMap(\.approvedWinnerID)
        guard winners.count == current.count else {
            throw ATHLTHTournamentEngineError.roundNotComplete
        }
        if winners.count <= 1 { return [] }
        // Re-seeding is intentionally disabled; match order from the
        // previous round determines the fixed elimination tree.
        return stride(from: 0, to: winners.count, by: 2).map { index in
            ATHLTHTournamentFixture(
                phase: phase,
                round: round + 1,
                homeID: winners[index],
                awayID: index + 1 < winners.count ? winners[index + 1] : nil
            )
        }
    }

    static func qualifiedForPlayoff(
        draft: ATHLTHTournamentDraft,
        fixtures: [ATHLTHTournamentFixture]
    ) throws -> [UUID] {
        guard draft.format == .groups else {
            throw ATHLTHTournamentEngineError.notEnoughQualifiers
        }
        let groups = ATHLTHTournamentStructure.groups(
            draft.participants, size: draft.groupSize
        )
        var qualified: [UUID] = []
        for (index, group) in groups.enumerated() {
            let scheduled = fixtures.filter {
                $0.phase == .group && $0.groupIndex == index
            }
            guard !scheduled.isEmpty && scheduled.allSatisfy(\.isComplete) else {
                throw ATHLTHTournamentEngineError.roundNotComplete
            }
            let standings = standings(
                for: group, fixtures: scheduled, groupIndex: index
            )
            qualified.append(contentsOf:
                standings.prefix(draft.qualifiersPerGroup).map(\.id)
            )
        }
        guard qualified.count >= 2 else {
            throw ATHLTHTournamentEngineError.notEnoughQualifiers
        }
        return qualified
    }
}
