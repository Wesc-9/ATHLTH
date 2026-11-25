import Foundation

/// A league or cup may be renewed only after its verified final state is
/// completed. Renewal never mutates the previous tournament, its fixtures,
/// its standings or its participants' accepted scores. The next season is a
/// fresh invitation and a fresh server-owned tournament identifier.
enum ATHLTHTournamentSeasonContinuation {
    static func canContinue(
        format: ATHLTHTournamentFormat,
        status: String,
        ownerID: UUID,
        currentUserID: UUID
    ) -> Bool {
        status == "completed" && ownerID == currentUserID &&
            [.league, .groups, .cup].contains(format)
    }

    /// Follow only explicit, visible season links, never titles or club IDs.
    /// Missing ancestors remain private; a cycle cannot cause an infinite walk.
    static func history(
        current: ATHLTHTournamentRemote,
        visible: [ATHLTHTournamentRemote]
    ) -> [ATHLTHTournamentRemote] {
        guard !current.singleEventMode, !current.isDuel else { return [] }
        var byID: [UUID: ATHLTHTournamentRemote] = [current.id: current]
        for season in visible where !season.singleEventMode && !season.isDuel &&
            season.ownerID == current.ownerID && season.format == current.format {
            if byID[season.id] == nil { byID[season.id] = season }
        }
        var neighbors: [UUID: [UUID]] = [:]
        for season in byID.values {
            guard let previous = season.raceRules.previousCompetitionID,
                  byID[previous] != nil else { continue }
            neighbors[season.id, default: []].append(previous)
            neighbors[previous, default: []].append(season.id)
        }
        var visited: Set<UUID> = [current.id]
        var pending = [current.id]
        while let id = pending.popLast() {
            for neighbor in neighbors[id, default: []] {
                if visited.insert(neighbor).inserted { pending.append(neighbor) }
            }
        }
        return visited.compactMap { byID[$0] }.sorted {
            let lhs = $0.raceRules.seasonNumber ?? 1
            let rhs = $1.raceRules.seasonNumber ?? 1
            if lhs != rhs { return lhs > rhs }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func nextTitle(from previous: String) -> String {
        let clean = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)(?:\s*[·—-]\s*)?sesong\s+([0-9]+)\s*$"#
        var base = clean
        var nextNumber = 2
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
                in: clean, range: NSRange(clean.startIndex..., in: clean)
           ),
           let entire = Range(match.range, in: clean),
           let digits = Range(match.range(at: 1), in: clean) {
            nextNumber = min(999, (Int(clean[digits]) ?? 1) + 1)
            base = String(clean[..<entire.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let suffix = " · Sesong \(nextNumber)"
        return String(base.prefix(max(0, 80 - suffix.count))) + suffix
    }

    static func nextDraft(
        from completed: ATHLTHTournamentRemote,
        entries: [ATHLTHTournamentRemoteEntry],
        athleteNames: [UUID: String],
        currentUserID: UUID,
        now: Date = Date()
    ) -> ATHLTHTournamentDraft? {
        guard !completed.singleEventMode, canContinue(
            format: completed.format, status: completed.status,
            ownerID: completed.ownerID,
            currentUserID: currentUserID
        ) else { return nil }

        let eligible = entries
            .filter { $0.response == "accepted" && $0.removedAt == nil }
            .sorted { $0.seed < $1.seed }
        guard eligible.contains(where: { $0.userID == completed.ownerID }) else {
            return nil
        }

        var seen = Set<UUID>()
        let participants = eligible.compactMap { entry -> ATHLTHTournamentParticipant? in
            guard seen.insert(entry.userID).inserted else { return nil }
            return ATHLTHTournamentParticipant(
                id: entry.userID,
                username: athleteNames[entry.userID] ?? "Utøver"
            )
        }
        guard participants.count >= 2,
              participants.count >= (completed.format == .cup ? 4 : 2),
              (try? ATHLTHTournamentEngine.validate(
                participants, groupSize: completed.groupSize,
                qualifiersPerGroup: completed.qualifiersPerGroup
              )) != nil else { return nil }

        // Preserve agreed competition rules, but require the organizer
        // to select a fresh start for the new season. No old result, vote,
        // prize payment or athlete consent is carried across.
        var nextSettings = ATHLTHTournamentCompetitionSettings()
        nextSettings.unlock = ATHLTHCompetitionUnlock(
            rawValue: completed.releaseMode
        ) ?? .interval
        nextSettings.unit = ATHLTHCompetitionIntervalUnit(
            rawValue: completed.releaseUnit
        ) ?? .day
        nextSettings.every = min(
            max(1, completed.releaseEvery),
            nextSettings.unit.maximumCount
        )
        nextSettings.completionHours = completed.completionHours
        nextSettings.invitationPermission = ATHLTHCompetitionInvitePermission(
            rawValue: completed.invitationPermission
        ) ?? .admin
        nextSettings.joinApproval = ATHLTHCompetitionJoinApproval(
            rawValue: completed.joinApproval
        ) ?? .admin
        nextSettings.agreement = ATHLTHCompetitionAgreement(
            allowed: completed.allowedActions,
            prohibited: completed.prohibitedActions,
            firstPrize: completed.prizeFirst,
            secondPrize: completed.prizeSecond,
            thirdPrize: completed.prizeThird,
            loserConsequence: completed.loserConsequence
        )
        nextSettings.race = completed.raceRules
        nextSettings.race.previousCompetitionID = completed.id
        nextSettings.race.seasonNumber = (completed.raceRules.seasonNumber ?? 1) + 1
        nextSettings.race.duelMode = nil
        nextSettings.startsAt = nil
        nextSettings.endsAt = nil
        nextSettings.race.competitionEndsAt = nil
        nextSettings.startMode =
            completed.startMode == "scheduled" ? .manual :
            ATHLTHCompetitionStartMode(rawValue: completed.startMode) ?? .manual
        nextSettings.environment =
            ATHLTHCompetitionEnvironment(rawValue: completed.requiredEnvironment)
            ?? .any
        nextSettings.meetingPlace = completed.meetingPlace ?? ""
        nextSettings.meetingLat = completed.meetingLat
        nextSettings.meetingLon = completed.meetingLon
        // A new season always gets a new, independently approved exercise list.
        nextSettings.coachExerciseIDs = []
        nextSettings.invitationDays = completed.invitationDays
        nextSettings.unansweredPolicy =
            ATHLTHCompetitionUnansweredPolicy(rawValue:
                completed.unansweredPolicy) ?? .cancel
        nextSettings.allowFeedPost = completed.allowFeedPost

        // Deliberately do not re-use the previous club season ID. The owner
        // chooses a new club season (if applicable) in the full editor.
        // Proposal/vote deadlines are reset for this new group of invites.
        return ATHLTHTournamentDraft(
            ownerID: completed.ownerID,
            clubID: completed.clubID,
            seasonID: nil,
            title: nextTitle(from: completed.title),
            format: completed.format,
            groupSize: completed.groupSize,
            qualifiersPerGroup: completed.qualifiersPerGroup,
            participants: participants,
            warmupRounds: [],
            exerciseMode: completed.exerciseMode,
            exerciseCount: completed.exerciseCount,
            proposalsCloseAt: completed.exerciseMode == .vote
                ? now.addingTimeInterval(2 * 86_400) : nil,
            votesCloseAt: completed.exerciseMode == .vote
                ? now.addingTimeInterval(3 * 86_400) : nil,
            approvePlayerChanges: completed.approvePlayerChanges,
            allowedActivities: completed.allowedActivities,
            rulesAuthority: completed.rulesAuthority,
            cadenceDays: completed.cadenceDays,
            completionHours: completed.completionHours,
            rotationMode: completed.rotationMode,
            restWeekdays: completed.restWeekdays,
            proofMode: completed.proofMode,
            publicResults: completed.publicResults,
            allowExtensions: completed.allowExtensions,
            winPoints: completed.winPoints,
            drawPoints: completed.drawPoints,
            competitionSettings: nextSettings
        )
    }
}


/// The previous invitee takes the next turn as organizer. New rules and
/// measurements are independent of the completed duel.
enum ATHLTHDuelRematch {
    static func canRematch(_ previous: ATHLTHTournamentRemote,
                          entries: [ATHLTHTournamentRemoteEntry], userID: UUID) -> Bool {
        previous.isDuel && previous.status == "completed" && previous.ownerID != userID &&
        Set(entries.filter { $0.response == "accepted" && $0.removedAt == nil }.map(\.userID)) ==
            Set([previous.ownerID, userID])
    }

    static func draft(from previous: ATHLTHTournamentRemote,
                      entries: [ATHLTHTournamentRemoteEntry], names: [UUID: String],
                      userID: UUID, exerciseIDs: [UUID]) -> ATHLTHTournamentDraft? {
        guard canRematch(previous, entries: entries, userID: userID),
              (1...12).contains(exerciseIDs.count), Set(exerciseIDs).count == exerciseIDs.count else { return nil }
        var settings = ATHLTHTournamentCompetitionSettings()
        settings.race = previous.raceRules
        settings.race.previousCompetitionID = previous.id
        settings.race.seasonNumber = nil
        settings.race.competitionEndsAt = nil
        settings.race.duelMode = true
        settings.race.exerciseScoringVersion = 2
        settings.race.discipline = .workout
        settings.startMode = .manual
        settings.unlock = ATHLTHCompetitionUnlock(rawValue: previous.releaseMode) ?? .interval
        settings.unit = ATHLTHCompetitionIntervalUnit(rawValue: previous.releaseUnit) ?? .day
        settings.every = min(max(1, previous.releaseEvery), settings.unit.maximumCount)
        settings.completionHours = previous.completionHours
        settings.environment = ATHLTHCompetitionEnvironment(rawValue: previous.requiredEnvironment) ?? .any
        settings.invitationDays = previous.invitationDays
        settings.selectedExerciseIDs = exerciseIDs
        let base = previous.title.replacingOccurrences(of: #"(?i)\s*·\s*rematch$"#, with: "", options: .regularExpression)
        return ATHLTHTournamentDraft(ownerID: userID, clubID: nil, seasonID: nil,
            title: String(base.prefix(70)) + " · Rematch", format: .league, singleEventMode: true,
            groupSize: previous.groupSize, qualifiersPerGroup: previous.qualifiersPerGroup,
            participants: [userID, previous.ownerID].map { ATHLTHTournamentParticipant(id: $0, username: names[$0] ?? "Utøver") },
            warmupRounds: [], exerciseMode: .owner, exerciseCount: exerciseIDs.count,
            proposalsCloseAt: nil, votesCloseAt: nil, approvePlayerChanges: false,
            allowedActivities: previous.allowedActivities, rulesAuthority: .owner,
            cadenceDays: previous.cadenceDays, completionHours: previous.completionHours,
            rotationMode: .all, restWeekdays: [], proofMode: .opponent, publicResults: false,
            allowExtensions: false, winPoints: previous.winPoints, drawPoints: previous.drawPoints,
            competitionSettings: settings)
    }
}
