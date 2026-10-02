import Foundation

@MainActor
final class TrophyStore: ObservableObject {
    @Published private(set) var trophies: [TrophyProgressItem] = []
    @Published private(set) var unlocks: [TrophyUnlockRecord] = []
    @Published private(set) var showcaseIDs: [String] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var pendingReveal: TrophyUnlockRecord?

    static let showcaseLimit = 4

    private var hasInitializedShowcase = false
    private var revealQueue: [TrophyUnlockRecord] = []
    private let activationDate: Date
    private let cloud =
        TrophyCloudService()
    private var activeUserID: UUID?
    private var activeUsername: String?
    private var showcaseUpdatedAt: Date?

    init() {
        let persisted = Self.loadState()
        unlocks = persisted.unlocks
        showcaseIDs = Array(
            persisted.showcaseIDs
                .prefix(Self.showcaseLimit)
        )
        hasInitializedShowcase =
            persisted.hasInitializedShowcase
        showcaseUpdatedAt =
            persisted.showcaseUpdatedAt
        activationDate = Self.loadOrCreateActivationDate()
    }

    var unlockedCount: Int {
        trophies.filter(\.isUnlocked).count
    }

    var unlockedAchievementCount: Int {
        trophies.filter {
            $0.isUnlocked &&
            !$0.isPrestigeTrophy
        }.count
    }

    var unlockedPrestigeTrophyCount: Int {
        trophies.filter {
            $0.isUnlocked &&
            $0.isPrestigeTrophy
        }.count
    }

    var prestigeTrophies: [TrophyProgressItem] {
        trophies.filter(\.isPrestigeTrophy)
    }

    var unlockedPrestigeTrophies: [TrophyProgressItem] {
        prestigeTrophies.filter(\.isUnlocked)
    }

    var showcaseTrophies: [TrophyProgressItem] {
        showcaseIDs.compactMap { id in
            trophies.first {
                $0.id == id &&
                $0.isUnlocked
            }
        }
    }

    var unlockedCabinetCandidates: [TrophyProgressItem] {
        trophies
            .filter(\.isUnlocked)
            .sorted {
                if $0.isPrestigeTrophy != $1.isPrestigeTrophy {
                    return $0.isPrestigeTrophy
                }

                if $0.displayRarity != $1.displayRarity {
                    return $0.displayRarity > $1.displayRarity
                }

                return ($0.unlockedAt ?? .distantPast) >
                    ($1.unlockedAt ?? .distantPast)
            }
    }

    var nextTrophies: [TrophyProgressItem] {
        trophies
            .filter { !$0.isComplete }
            .sorted {
                if $0.progress == $1.progress {
                    return $0.displayRarity > $1.displayRarity
                }
                return $0.progress > $1.progress
            }
    }

    var nextAchievements: [TrophyProgressItem] {
        trophies
            .filter {
                !$0.isPrestigeTrophy &&
                !$0.isComplete
            }
            .sorted {
                if $0.progress == $1.progress {
                    return $0.displayRarity > $1.displayRarity
                }
                return $0.progress > $1.progress
            }
    }

    func refresh(
        health: HealthKitManager,
        strength: StrengthWorkoutStore,
        goals: GoalStore,
        challenges: ChallengeStore? = nil,
        currentUserID: UUID? = nil,
        username: String? = nil
    ) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        activeUserID =
            currentUserID
        activeUsername =
            username?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        if currentUserID != nil,
           let remote =
                try? await cloud
                    .loadState() {
            mergeRemoteUnlocks(
                remote.unlocks
            )

            if let remoteUpdated =
                    remote
                        .cabinetUpdatedAt,
               showcaseUpdatedAt == nil ||
               remoteUpdated >
                    (
                        showcaseUpdatedAt ??
                        .distantPast
                    ) {
                showcaseIDs =
                    Array(
                        remote
                            .showcaseIDs
                            .prefix(
                                Self
                                    .showcaseLimit
                            )
                    )
                showcaseUpdatedAt =
                    remoteUpdated
                hasInitializedShowcase =
                    true
            }
        }

        let healthSnapshot = try? await health.trophySnapshot()
        let strengthSnapshot = strength.trophySnapshot()

        if currentUserID != nil,
           let healthSnapshot {
            await claimPrestigeTrophies(
                from: healthSnapshot
            )
        }

        let completedGoals = goals.goals.filter { $0.status == .completed }
        let completedGoalCount = completedGoals.count

        let allChallenges = challenges?.challenges ?? []
        let userChallenges: [ATHLTHChallenge]
        if let currentUserID {
            userChallenges = allChallenges.filter { challenge in
                challenge.creatorID == currentUserID ||
                challenge.participants.contains(where: { $0.userID == currentUserID })
            }
        } else {
            userChallenges = []
        }

        let participationDates = userChallenges
            .map(\.createdAt)
            .sorted()

        var winDates: [Date] = []
        var routeWinDates: [Date] = []
        var strengthWinDates: [Date] = []

        if let currentUserID, let challenges {
            for challenge in userChallenges where challenge.status == .completed {
                guard let entry = challenges.leaderboard(for: challenge.id).first(where: {
                    $0.participant.userID == currentUserID
                }),
                entry.rank == 1
                else {
                    continue
                }

                let date = challenge.rules.endsAt
                    ?? entry.bestAttempt?.submittedAt
                    ?? challenge.createdAt
                winDates.append(date)

                if challenge.rules.scoring == .fastestRoute {
                    routeWinDates.append(date)
                }

                if challenge.sport == .strength {
                    strengthWinDates.append(date)
                }
            }
        }

        winDates.sort()
        routeWinDates.sort()
        strengthWinDates.sort()

        let createdChallenges = currentUserID.map { userID in
            allChallenges.filter { $0.creatorID == userID }.sorted { $0.createdAt < $1.createdAt }
        } ?? []

        var uniqueInvitees = Set<String>()
        var inviteThresholdDates: [Int: Date] = [:]

        for challenge in createdChallenges {
            for participant in challenge.participants where participant.state != .creator {
                let identity = participant.userID?.uuidString
                    ?? participant.username?.lowercased()
                    ?? participant.displayName.lowercased()
                uniqueInvitees.insert(identity)

                for threshold in [1, 5, 10]
                where inviteThresholdDates[threshold] == nil &&
                        uniqueInvitees.count >= threshold {
                    inviteThresholdDates[threshold] = challenge.createdAt
                }
            }
        }

        var resolved: [TrophyProgressItem] = []

        for definition in TrophyCatalog.allSeries {
            let value: Double
            let evidence: (Double) -> Date?

            switch definition.id {
            case TrophyCatalog.workoutMomentum.id:
                value = Double(healthSnapshot?.workoutCount ?? 0)
                evidence = { threshold in
                    healthSnapshot?.workoutCountReachedAt[Int(threshold)]
                }

            case TrophyCatalog.walkingDistance.id:
                value =
                    healthSnapshot?
                        .totalWalkingDistanceMeters ??
                    0
                evidence = { threshold in
                    healthSnapshot?
                        .walkingDistanceReachedAt?[
                            Int(threshold)
                        ]
                }

            case TrophyCatalog.walkingSessions.id:
                value =
                    Double(
                        healthSnapshot?
                            .walkingWorkoutCount ??
                        0
                    )
                evidence = { threshold in
                    healthSnapshot?
                        .walkingWorkoutCountReachedAt?[
                            Int(threshold)
                        ]
                }

            case TrophyCatalog.runningDistance.id:
                value = healthSnapshot?.totalRunningDistanceMeters ?? 0
                evidence = { threshold in
                    healthSnapshot?.runningDistanceReachedAt[Int(threshold)]
                }

            case TrophyCatalog.streak.id:
                value = Double(healthSnapshot?.longestWorkoutStreakDays ?? 0)
                evidence = { threshold in
                    healthSnapshot?.workoutStreakReachedAt[Int(threshold)]
                }

            case TrophyCatalog.strengthSessions.id:
                value = Double(strengthSnapshot.completedWorkoutCount)
                evidence = { threshold in
                    strengthSnapshot.workoutCountReachedAt[Int(threshold)]
                }

            case TrophyCatalog.strengthVolume.id:
                value =
                    strengthSnapshot
                        .totalVolumeKilograms
                evidence = { threshold in
                    strengthSnapshot
                        .volumeReachedAt[
                            Int(threshold)
                        ]
                }

            case TrophyCatalog.recoveryNights.id:
                value = Double(healthSnapshot?.qualifyingSleepNights ?? 0)
                evidence = { threshold in
                    healthSnapshot?.qualifyingSleepNightsReachedAt[Int(threshold)]
                }

            case TrophyCatalog.completedGoals.id:
                value = Double(completedGoalCount)
                evidence = { threshold in
                    let count = Int(threshold)
                    let sorted = completedGoals
                        .compactMap { goal -> (Date, ATHLTHGoal)? in
                            guard let date = goal.completedAt else { return nil }
                            return (date, goal)
                        }
                        .sorted { $0.0 < $1.0 }
                    guard sorted.count >= count else { return nil }
                    return sorted[count - 1].0
                }

            case TrophyCatalog.challengeParticipation.id:
                value = Double(participationDates.count)
                evidence = { threshold in
                    let count = Int(threshold)
                    guard participationDates.count >= count else { return nil }
                    return participationDates[count - 1]
                }

            case TrophyCatalog.challengeWins.id:
                value = Double(winDates.count)
                evidence = { threshold in
                    let count = Int(threshold)
                    guard winDates.count >= count else { return nil }
                    return winDates[count - 1]
                }

            case TrophyCatalog.friendsChallenged.id:
                value = Double(uniqueInvitees.count)
                evidence = { threshold in
                    inviteThresholdDates[Int(threshold)]
                }

            default:
                value = 0
                evidence = { _ in nil }
            }

            resolved.append(
                resolveSeries(
                    definition,
                    value: value,
                    evidenceDate: evidence
                )
            )
        }

        if let healthSnapshot {
            resolved.append(
                signature(
                    id: "signature.first-5k",
                    title: "First 5K",
                    subtitle: "Your first recorded running workout of at least 5 kilometres.",
                    icon: "5.circle.fill",
                    source: .appleHealth,
                    rarity: .core,
                    unlockedAt: healthSnapshot.firstFiveKDate
                )
            )

            resolved.append(
                signature(
                    id: "signature.first-10k",
                    title: "First 10K",
                    subtitle: "Your first recorded running workout of at least 10 kilometres.",
                    icon: "figure.run",
                    source: .appleHealth,
                    rarity: .rare,
                    unlockedAt:
                        healthSnapshot
                            .firstTenKDate
                )
            )

            resolved.append(
                signature(
                    id: "signature.half-marathon",
                    title: "Half Marathon",
                    subtitle: "A recorded run reaching 21.1 kilometres.",
                    icon: "figure.run",
                    source: .appleHealth,
                    rarity: .signature,
                    unlockedAt:
                        historicalUnlockDate(
                            for:
                                PrestigeTrophyCatalog
                                    .halfMarathonID
                        )
                )
            )

            resolved.append(
                signature(
                    id: "signature.marathon",
                    title: "Marathon",
                    subtitle: "42.195 kilometres recorded in a single run.",
                    icon: "flag.checkered",
                    source: .appleHealth,
                    rarity: .signature,
                    unlockedAt:
                        historicalUnlockDate(
                            for:
                                PrestigeTrophyCatalog
                                    .marathonID
                        )
                )
            )

            resolved.append(
                signature(
                    id: "signature.walk-5k",
                    title: "Five K on Foot",
                    subtitle: "A single recorded walking workout reaching 5 kilometres.",
                    icon: "figure.walk",
                    source: .appleHealth,
                    rarity: .core,
                    unlockedAt:
                        healthSnapshot
                            .firstFiveKWalkDate
                )
            )

            resolved.append(
                signature(
                    id: "signature.walk-10k",
                    title: "Ten K Trek",
                    subtitle: "A single recorded walking workout reaching 10 kilometres.",
                    icon: "shoeprints.fill",
                    source: .appleHealth,
                    rarity: .rare,
                    unlockedAt:
                        healthSnapshot
                            .firstTenKWalkDate
                )
            )
        }

        resolved.append(
            signature(
                id: "signature.first-strength-log",
                title: "Strength Recorded",
                subtitle: "Your first weighted set logged in ATHLTH.",
                icon: "dumbbell.fill",
                source: .athlth,
                rarity: .core,
                unlockedAt: strengthSnapshot.firstWeightedSetDate
            )
        )

        resolved.append(
            signature(
                id: "signature.route-rival",
                title: "Route Rival",
                subtitle: "Win an ATHLTH Challenge on a specific verified route.",
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                source: .challenge,
                rarity: .rare,
                unlockedAt: routeWinDates.first
            )
        )

        resolved.append(
            signature(
                id: "signature.strength-rival",
                title: "Strength Rival",
                subtitle: "Win a strength challenge against your competition.",
                icon: "dumbbell.fill",
                source: .challenge,
                rarity: .rare,
                unlockedAt: strengthWinDates.first
            )
        )

        for goal in goals.goals where !goal.milestones.isEmpty {
            let unlockedAt = goal.status == .completed ? goal.completedAt : nil
            let currentValue = Double(goal.completedMilestones)
            let targetValue = Double(max(goal.milestones.count, 1))
            let stage = unlockedAt.map { _ in
                TrophyStageDefinition(
                    id: "complete",
                    title: "Goal Complete",
                    threshold: targetValue,
                    displayTarget: "Completed",
                    rarity: .epic
                )
            }

            resolved.append(
                TrophyProgressItem(
                    id: "goal.journey.\(goal.id.uuidString)",
                    title: goal.title,
                    subtitle: "Goal Journey · \(goal.completedMilestones) of \(goal.milestones.count) milestones complete.",
                    category: .goals,
                    verificationSource: .goal,
                    systemImage: goal.category.systemImage,
                    currentValue: currentValue,
                    nextTargetValue: unlockedAt == nil ? targetValue : nil,
                    currentStage: stage,
                    nextStage: unlockedAt == nil
                        ? TrophyStageDefinition(
                            id: "complete",
                            title: "Complete Journey",
                            threshold: targetValue,
                            displayTarget: "\(goal.milestones.count) milestones",
                            rarity: .epic
                        )
                        : nil,
                    highestRarity: .epic,
                    unlockedAt: unlockedAt,
                    goalID: goal.id,
                    journeyMilestonesCompleted: goal.completedMilestones,
                    journeyMilestonesTotal: goal.milestones.count
                )
            )

            if let unlockedAt {
                registerUnlock(
                    stageKey: "goal.journey.\(goal.id.uuidString).complete",
                    trophyID: "goal.journey.\(goal.id.uuidString)",
                    stageTitle: "Goal Complete",
                    title: goal.title,
                    rarity: .epic,
                    category: .goals,
                    source: .goal,
                    unlockedAt: unlockedAt
                )
            }
        }

        trophies = resolved.sorted(by: Self.collectionSort)

        if !hasInitializedShowcase {
            // The cabinet is intentionally empty until the user chooses
            // which trophies represent them on the profile.
            showcaseIDs = []
            hasInitializedShowcase = true
        } else {
            showcaseIDs = Array(
                showcaseIDs
                    .filter { id in
                        trophies.contains(
                            where: {
                                $0.id == id &&
                                $0.isUnlocked
                            }
                        )
                    }
                    .prefix(Self.showcaseLimit)
            )
        }

        if currentUserID != nil {
            try? await cloud
                .syncAchievements(
                    unlocks,
                    trophies: trophies,
                    username:
                        activeUsername
                )

            if showcaseUpdatedAt != nil {
                if let cloudDate =
                        try? await cloud
                            .saveCabinet(
                                showcaseIDs
                            ) {
                    showcaseUpdatedAt =
                        cloudDate
                }
            }
        }

        persist()
    }

    func isShowcased(_ trophyID: String) -> Bool {
        showcaseIDs.contains(trophyID)
    }

    func toggleShowcase(_ trophyID: String) {
        guard trophies.contains(where: {
            $0.id == trophyID &&
            $0.isUnlocked
        }) else {
            return
        }

        if let index = showcaseIDs.firstIndex(of: trophyID) {
            showcaseIDs.remove(at: index)
        } else {
            guard showcaseIDs.count < Self.showcaseLimit else { return }
            showcaseIDs.append(trophyID)
        }

        hasInitializedShowcase = true
        showcaseUpdatedAt = Date()
        persist()

        guard activeUserID != nil
        else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if let cloudDate =
                    try? await self
                        .cloud
                        .saveCabinet(
                            self
                                .showcaseIDs
                        ) {
                self.showcaseUpdatedAt =
                    cloudDate
                self.persist()
            }
        }
    }

    func dismissCurrentReveal() {
        if !revealQueue.isEmpty {
            revealQueue.removeFirst()
        }

        pendingReveal = revealQueue.first
    }

    func unlockRecordsSince(_ date: Date) -> [TrophyUnlockRecord] {
        unlocks
            .filter { $0.unlockedAt >= date }
            .sorted { $0.unlockedAt > $1.unlockedAt }
    }

    private func resolveSeries(
        _ definition: TrophySeriesDefinition,
        value: Double,
        evidenceDate: (Double) -> Date?
    ) -> TrophyProgressItem {
        let stages =
            definition.stages
                .sorted {
                    $0.threshold <
                    $1.threshold
                }
        let completed =
            stages.filter {
                value >=
                $0.threshold
            }

        for stage in completed {
            if let date =
                    evidenceDate(
                        stage.threshold
                    ) {
                registerUnlock(
                    stageKey:
                        "\(definition.id).stage.\(stage.id)",
                    trophyID:
                        definition.id,
                    stageTitle:
                        stage.title,
                    title:
                        definition.title,
                    rarity:
                        stage.rarity,
                    category:
                        definition.category,
                    source:
                        definition
                            .verificationSource,
                    unlockedAt:
                        date
                )
            }
        }

        let historical =
            unlocks
                .filter {
                    $0.trophyID ==
                    definition.id
                }
                .max {
                    if $0.rarity !=
                        $1.rarity {
                        return $0.rarity <
                            $1.rarity
                    }

                    return $0.unlockedAt <
                        $1.unlockedAt
                }

        let historicalStage =
            historical.flatMap {
                record in
                stages.last {
                    $0.rarity <=
                        record.rarity
                }
            }
        let liveStage =
            completed.last
        let current:
            TrophyStageDefinition?

        switch (
            liveStage,
            historicalStage
        ) {
        case let (live?, old?):
            current =
                live.rarity >=
                    old.rarity
                    ? live
                    : old
        case let (live?, nil):
            current = live
        case let (nil, old?):
            current = old
        case (nil, nil):
            current = nil
        }

        let next =
            current.flatMap {
                current in
                stages.first {
                    $0.rarity >
                        current.rarity
                }
            } ??
            stages.first {
                stage in
                current == nil &&
                value <
                    stage.threshold
            }

        let effectiveValue =
            max(
                value,
                current?
                    .threshold ??
                0
            )
        let latestUnlock =
            unlocks
                .filter {
                    $0.trophyID ==
                    definition.id
                }
                .max {
                    $0.unlockedAt <
                    $1.unlockedAt
                }?
                .unlockedAt

        return TrophyProgressItem(
            id: definition.id,
            title:
                definition.title,
            subtitle:
                definition.subtitle,
            category:
                definition.category,
            verificationSource:
                definition
                    .verificationSource,
            systemImage:
                definition.systemImage,
            currentValue:
                effectiveValue,
            nextTargetValue:
                next?.threshold,
            currentStage:
                current,
            nextStage:
                next,
            highestRarity:
                stages.last?
                    .rarity ??
                .core,
            unlockedAt:
                latestUnlock,
            goalID: nil,
            journeyMilestonesCompleted:
                nil,
            journeyMilestonesTotal:
                nil
        )
    }

    private func signature(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        source: TrophyVerificationSource,
        rarity: TrophyRarity = .signature,
        unlockedAt: Date?
    ) -> TrophyProgressItem {
        if let unlockedAt,
           !PrestigeTrophyCatalog
                .isPrestigeTrophy(id) {
            registerUnlock(
                stageKey:
                    "\(id).unlocked",
                trophyID: id,
                stageTitle:
                    rarity.title,
                title: title,
                rarity: rarity,
                category: .signature,
                source: source,
                unlockedAt:
                    unlockedAt
            )
        }

        let historical =
            unlocks
                .filter {
                    $0.trophyID == id
                }
                .max {
                    if $0.rarity !=
                        $1.rarity {
                        return $0.rarity <
                            $1.rarity
                    }

                    return $0.unlockedAt <
                        $1.unlockedAt
                }
        let resolvedUnlockedAt =
            historical?
                .unlockedAt ??
            (
                PrestigeTrophyCatalog
                    .isPrestigeTrophy(id)
                    ? nil
                    : unlockedAt
            )
        let resolvedRarity =
            historical.map {
                max(
                    $0.rarity,
                    rarity
                )
            } ??
            rarity
        let stage =
            resolvedUnlockedAt.map {
                _ in
                TrophyStageDefinition(
                    id: "unlocked",
                    title:
                        resolvedRarity
                            .title,
                    threshold: 1,
                    displayTarget:
                        ATHLTHLocalization.choose(
                            english:
                                "Unlocked",
                            norwegian:
                                "Låst opp"
                        ),
                    rarity:
                        resolvedRarity
                )
            }

        return TrophyProgressItem(
            id: id,
            title: title,
            subtitle: subtitle,
            category: .signature,
            verificationSource:
                source,
            systemImage: icon,
            currentValue:
                resolvedUnlockedAt == nil
                    ? 0
                    : 1,
            nextTargetValue:
                resolvedUnlockedAt == nil
                    ? 1
                    : nil,
            currentStage:
                stage,
            nextStage:
                resolvedUnlockedAt == nil
                    ? TrophyStageDefinition(
                        id: "unlocked",
                        title:
                            rarity.title,
                        threshold: 1,
                        displayTarget:
                            ATHLTHLocalization.choose(
                                english:
                                    "Complete",
                                norwegian:
                                    "Fullfør"
                            ),
                        rarity:
                            rarity
                    )
                    : nil,
            highestRarity:
                resolvedRarity,
            unlockedAt:
                resolvedUnlockedAt,
            goalID: nil,
            journeyMilestonesCompleted:
                nil,
            journeyMilestonesTotal:
                nil
        )
    }

    private func historicalUnlockDate(
        for trophyID: String
    ) -> Date? {
        unlocks
            .filter {
                $0.trophyID ==
                    trophyID
            }
            .map(\.unlockedAt)
            .min()
    }

    private func claimPrestigeTrophies(
        from snapshot:
            TrophyHealthSnapshot
    ) async {
        let claims:
            [
                (
                    id: String,
                    evidence:
                        PrestigeRunEvidence?
                )
            ] = [
                (
                    PrestigeTrophyCatalog
                        .halfMarathonID,
                    snapshot
                        .firstHalfMarathonEvidence
                ),
                (
                    PrestigeTrophyCatalog
                        .marathonID,
                    snapshot
                        .firstMarathonEvidence
                )
            ]

        for claim in claims {
            guard
                historicalUnlockDate(
                    for: claim.id
                ) == nil,
                let evidence =
                    claim.evidence
            else {
                continue
            }

            if let record =
                    try? await cloud
                        .claimPrestigeTrophy(
                            trophyID:
                                claim.id,
                            evidence:
                                evidence,
                            username:
                                activeUsername
                        ) {
                registerCloudUnlock(
                    record,
                    allowReveal: true
                )
            }
        }
    }

    private func mergeRemoteUnlocks(
        _ remote:
            [TrophyUnlockRecord]
    ) {
        for record in remote {
            registerCloudUnlock(
                record,
                allowReveal: false
            )
        }
    }

    private func registerCloudUnlock(
        _ record:
            TrophyUnlockRecord,
        allowReveal: Bool
    ) {
        if let index =
            unlocks.firstIndex(
                where: {
                    $0.stageKey ==
                        record.stageKey
                }
            ) {
            // The server is the immutable source of truth once a row exists.
            unlocks[index] =
                record
            return
        }

        unlocks.append(record)

        guard allowReveal,
              record.unlockedAt >=
                activationDate
        else {
            return
        }

        revealQueue.append(record)

        if pendingReveal == nil {
            pendingReveal =
                revealQueue.first
        }
    }

    private func registerUnlock(
        stageKey: String,
        trophyID: String,
        stageTitle: String,
        title: String,
        rarity: TrophyRarity,
        category: TrophyCategory,
        source: TrophyVerificationSource,
        unlockedAt: Date
    ) {
        guard !unlocks.contains(where: { $0.stageKey == stageKey }) else { return }

        let record = TrophyUnlockRecord(
            stageKey: stageKey,
            trophyID: trophyID,
            stageTitle: stageTitle,
            title: title,
            rarity: rarity,
            category: category,
            verificationSource: source,
            unlockedAt: unlockedAt
        )

        unlocks.append(record)

        if unlockedAt >= activationDate {
            revealQueue.append(record)

            if pendingReveal == nil {
                pendingReveal = revealQueue.first
            }
        }
    }

    private static func collectionSort(_ lhs: TrophyProgressItem, _ rhs: TrophyProgressItem) -> Bool {
        if lhs.category == .signature && rhs.category != .signature { return true }
        if rhs.category == .signature && lhs.category != .signature { return false }
        if lhs.isUnlocked != rhs.isUnlocked { return lhs.isUnlocked }
        if lhs.displayRarity != rhs.displayRarity { return lhs.displayRarity > rhs.displayRarity }
        return lhs.title < rhs.title
    }

    private static func showcaseSort(_ lhs: TrophyProgressItem, _ rhs: TrophyProgressItem) -> Bool {
        if lhs.displayRarity != rhs.displayRarity { return lhs.displayRarity > rhs.displayRarity }
        return (lhs.unlockedAt ?? .distantPast) > (rhs.unlockedAt ?? .distantPast)
    }

    private func persist() {
        let state = TrophyPersistedState(
            unlocks: unlocks,
            showcaseIDs: showcaseIDs,
            hasInitializedShowcase: hasInitializedShowcase,
            showcaseUpdatedAt: showcaseUpdatedAt
        )

        guard let url = Self.stateURL,
              let data = try? JSONEncoder().encode(state)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private static func loadState() -> TrophyPersistedState {
        guard let url = stateURL,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(TrophyPersistedState.self, from: data)
        else {
            return .empty
        }

        return state
    }

    private static func loadOrCreateActivationDate() -> Date {
        let defaults = UserDefaults.standard
        let key = "athlth.trophies.activationDate"

        if let existing = defaults.object(forKey: key) as? Date {
            return existing
        }

        let now = Date()
        defaults.set(now, forKey: key)
        return now
    }

    private static var stateURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("trophies-v1.json", isDirectory: false)
    }
}

private struct TrophyPersistedState: Codable {
    let unlocks: [TrophyUnlockRecord]
    let showcaseIDs: [String]
    let hasInitializedShowcase: Bool
    let showcaseUpdatedAt: Date?

    static let empty = TrophyPersistedState(
        unlocks: [],
        showcaseIDs: [],
        hasInitializedShowcase: false,
        showcaseUpdatedAt: nil
    )
}
