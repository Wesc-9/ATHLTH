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
        guard canContinue(
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
        nextSettings.startsAt = nil
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
