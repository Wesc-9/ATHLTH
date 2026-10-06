import Foundation

@MainActor
final class TrophyStore: ObservableObject {
    @Published private(set) var trophies: [TrophyProgressItem] = []
    @Published private(set) var unlocks: [TrophyUnlockRecord] = []
    @Published private(set) var showcaseIDs: [String] = []
    @Published private(set) var trophyInscriptions:
        [String: TrophyInscription] = [:]
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
    private var stateOwnerUserID: UUID?
    private var showcaseUpdatedAt: Date?

    init() {
        let persisted = Self.loadState()
        unlocks = persisted.unlocks
        showcaseIDs = Array(
            persisted.showcaseIDs
                .prefix(Self.showcaseLimit)
        )
        trophyInscriptions =
            persisted
                .trophyInscriptions ??
            [:]
        hasInitializedShowcase =
            persisted.hasInitializedShowcase
        stateOwnerUserID =
            persisted.ownerUserID
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
                // The shelf picker is intentionally one combined collection:
                // Signature → Epic → Rare → Core, regardless of award class.
                if $0.displayRarity != $1.displayRarity {
                    return $0.displayRarity > $1.displayRarity
                }

                if $0.isPrestigeTrophy != $1.isPrestigeTrophy {
                    return $0.isPrestigeTrophy
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

        if let currentUserID {
            if let owner =
                    stateOwnerUserID,
               owner != currentUserID {
                unlocks = []
                showcaseIDs = []
                trophyInscriptions = [:]
                revealQueue = []
                pendingReveal = nil
                hasInitializedShowcase = false
                showcaseUpdatedAt = nil
            }

            stateOwnerUserID =
                currentUserID
        }

        if currentUserID != nil,
           let remote =
                try? await cloud
                    .loadState() {
            mergeRemoteUnlocks(
                remote.unlocks
            )
            trophyInscriptions
                .merge(
                    remote.inscriptions
                ) {
                    _, remote in
                    remote
                }

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
            } else if !showcaseIDs.isEmpty &&
                      showcaseUpdatedAt == nil {
                showcaseUpdatedAt =
                    Date()
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

                for threshold in [1, 5, 10, 25, 50]
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

            case TrophyCatalog.workoutDayDensity.id:
                value =
                    Double(
                        healthSnapshot?
                            .maxWorkoutsInDay ??
                        0
                    )
                evidence = { threshold in
                    healthSnapshot?
                        .workoutDayDensityReachedAt?[
                            Int(threshold)
                        ]
                }

            case TrophyCatalog.workoutWeekDensity.id:
                value =
                    Double(
                        healthSnapshot?
                            .maxWorkoutsInWeek ??
                        0
                    )
                evidence = { threshold in
                    healthSnapshot?
                        .workoutWeekDensityReachedAt?[
                            Int(threshold)
                        ]
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
                    category: .endurance,
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
                    category: .endurance,
                    rarity: .rare,
                    unlockedAt:
                        healthSnapshot
                            .firstTenKDate
                )
            )

            resolved.append(
                signature(
                    id:
                        PrestigeTrophyCatalog
                            .halfMarathonID,
                    title: "Half Marathon",
                    subtitle: "A verified single run reaching 21.1 kilometres.",
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
                    id:
                        PrestigeTrophyCatalog
                            .longRun30KID,
                    title: "Long Run 30K",
                    subtitle: "A verified single running workout of at least 30 kilometres.",
                    icon: "road.lanes",
                    source: .appleHealth,
                    rarity: .signature,
                    unlockedAt:
                        historicalUnlockDate(
                            for:
                                PrestigeTrophyCatalog
                                    .longRun30KID
                        )
                )
            )

            resolved.append(
                signature(
                    id:
                        PrestigeTrophyCatalog
                            .marathonID,
                    title: "Marathon",
                    subtitle: "A verified 42.195 kilometre run in one recorded workout.",
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
                    id:
                        PrestigeTrophyCatalog
                            .ultra50KID,
                    title: "Ultra 50K",
                    subtitle: "A verified single running workout of at least 50 kilometres.",
                    icon: "mountain.2.fill",
                    source: .appleHealth,
                    rarity: .signature,
                    unlockedAt:
                        historicalUnlockDate(
                            for:
                                PrestigeTrophyCatalog
                                    .ultra50KID
                        )
                )
            )

            resolved.append(
                signature(
                    id:
                        PrestigeTrophyCatalog
                            .running250SessionsID,
                    title: "Run Discipline 250",
                    subtitle: "Complete 250 recorded running workouts.",
                    icon: "figure.run.circle.fill",
                    source: .appleHealth,
                    category: .endurance,
                    rarity: .epic,
                    unlockedAt:
                        healthSnapshot
                            .runningWorkoutCountReachedAt?[
                                250
                            ]
                )
            )

            resolved.append(
                signature(
                    id:
                        PrestigeTrophyCatalog
                            .running500SessionsID,
                    title: "Run Discipline 500",
                    subtitle: "Complete 500 recorded running workouts.",
                    icon: "figure.run.circle.fill",
                    source: .appleHealth,
                    category: .endurance,
                    rarity: .signature,
                    unlockedAt:
                        healthSnapshot
                            .runningWorkoutCountReachedAt?[
                                500
                            ]
                )
            )

            resolved.append(
                signature(
                    id:
                        PrestigeTrophyCatalog
                            .running1000KID,
                    title: "Thousand Kilometre Club",
                    subtitle: "Accumulate 1,000 kilometres of recorded running.",
                    icon: "road.lanes",
                    source: .appleHealth,
                    category: .endurance,
                    rarity: .epic,
                    unlockedAt:
                        healthSnapshot
                            .runningDistanceReachedAt[
                                1_000_000
                            ]
                )
            )

            resolved.append(
                signature(
                    id:
                        PrestigeTrophyCatalog
                            .running5000KID,
                    title: "Five Thousand",
                    subtitle: "Accumulate 5,000 kilometres of recorded running.",
                    icon: "map.fill",
                    source: .appleHealth,
                    category: .endurance,
                    rarity: .signature,
                    unlockedAt:
                        healthSnapshot
                            .runningDistanceReachedAt[
                                5_000_000
                            ]
                )
            )

            resolved.append(
                signature(
                    id:
                        PrestigeTrophyCatalog
                            .running10000KID,
                    title: "Ten Thousand",
                    subtitle: "Accumulate 10,000 kilometres of recorded running.",
                    icon: "globe.europe.africa.fill",
                    source: .appleHealth,
                    category: .endurance,
                    rarity: .signature,
                    unlockedAt:
                        healthSnapshot
                            .runningDistanceReachedAt[
                                10_000_000
                            ]
                )
            )

            resolved.append(
                signature(
                    id: "signature.walk-5k",
                    title: "Five K on Foot",
                    subtitle: "A single recorded walking workout reaching 5 kilometres.",
                    icon: "figure.walk",
                    source: .appleHealth,
                    category: .walking,
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
                    category: .walking,
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
                category: .strength,
                rarity: .core,
                unlockedAt: strengthSnapshot.firstWeightedSetDate
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength100SessionsID,
                title: "Iron Century",
                subtitle: "Complete 100 strength sessions recorded in ATHLTH.",
                icon: "dumbbell.fill",
                source: .athlth,
                category: .strength,
                rarity: .epic,
                unlockedAt:
                    strengthSnapshot
                        .workoutCountReachedAt[
                            100
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength250SessionsID,
                title: "Quarter Thousand",
                subtitle: "Complete 250 strength sessions recorded in ATHLTH.",
                icon: "dumbbell.fill",
                source: .athlth,
                category: .strength,
                rarity: .signature,
                unlockedAt:
                    strengthSnapshot
                        .workoutCountReachedAt[
                            250
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength500SessionsID,
                title: "Five Hundred Strong",
                subtitle: "Complete 500 strength sessions recorded in ATHLTH.",
                icon: "figure.strengthtraining.traditional",
                source: .athlth,
                category: .strength,
                rarity: .signature,
                unlockedAt:
                    strengthSnapshot
                        .workoutCountReachedAt[
                            500
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength100KVolumeID,
                title: "100K Under Load",
                subtitle: "Accumulate 100,000 kg of completed working-set volume.",
                icon: "scalemass.fill",
                source: .athlth,
                category: .strength,
                rarity: .epic,
                unlockedAt:
                    strengthSnapshot
                        .volumeReachedAt[
                            100_000
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength500KVolumeID,
                title: "Half-Million Iron",
                subtitle: "Accumulate 500,000 kg of completed working-set volume.",
                icon: "scalemass.fill",
                source: .athlth,
                category: .strength,
                rarity: .signature,
                unlockedAt:
                    strengthSnapshot
                        .volumeReachedAt[
                            500_000
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strengthMillionVolumeID,
                title: "Million Kilogram Club",
                subtitle: "Accumulate 1,000,000 kg of completed working-set volume.",
                icon: "crown.fill",
                source: .athlth,
                category: .strength,
                rarity: .signature,
                unlockedAt:
                    strengthSnapshot
                        .volumeReachedAt[
                            1_000_000
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength10KSessionVolumeID,
                title: "Ten-Tonne Session",
                subtitle: "Move at least 10,000 kg of working-set volume in one strength session.",
                icon: "bolt.fill",
                source: .athlth,
                category: .strength,
                rarity: .epic,
                unlockedAt:
                    strengthSnapshot
                        .workoutVolumeReachedAt[
                            10_000
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength20KSessionVolumeID,
                title: "Twenty-Tonne Session",
                subtitle: "Move at least 20,000 kg of working-set volume in one strength session.",
                icon: "bolt.circle.fill",
                source: .athlth,
                category: .strength,
                rarity: .signature,
                unlockedAt:
                    strengthSnapshot
                        .workoutVolumeReachedAt[
                            20_000
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength1000SetsID,
                title: "Thousand Working Sets",
                subtitle: "Complete 1,000 working sets in ATHLTH strength sessions.",
                icon: "list.number",
                source: .athlth,
                category: .strength,
                rarity: .epic,
                unlockedAt:
                    strengthSnapshot
                        .workingSetCountReachedAt[
                            1_000
                        ]
            )
        )

        resolved.append(
            signature(
                id:
                    PrestigeTrophyCatalog
                        .strength25000RepsID,
                title: "Twenty-Five Thousand",
                subtitle: "Complete 25,000 working repetitions across ATHLTH strength sessions.",
                icon: "repeat",
                source: .athlth,
                category: .strength,
                rarity: .signature,
                unlockedAt:
                    strengthSnapshot
                        .workingRepetitionCountReachedAt[
                            25_000
                        ]
            )
        )

        resolved.append(
            signature(
                id: "signature.route-rival",
                title: "Route Rival",
                subtitle: "Win an ATHLTH Challenge on a specific verified route.",
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                source: .challenge,
                category: .challenges,
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
                category: .challenges,
                rarity: .rare,
                unlockedAt: strengthWinDates.first
            )
        )

        for goal in goals.goals
        where !goal.milestones.isEmpty {
            let goalAwardID =
                "goal.journey.\(goal.id.uuidString)"
            let completedAt =
                goal.status == .completed
                    ? goal.completedAt
                    : nil
            let currentValue =
                Double(
                    goal.completedMilestones
                )
            let targetValue =
                Double(
                    max(
                        goal.milestones.count,
                        1
                    )
                )

            if let completedAt {
                registerUnlock(
                    stageKey:
                        "\(goalAwardID).complete",
                    trophyID:
                        goalAwardID,
                    stageTitle:
                        "Goal Complete",
                    title:
                        goal.title,
                    rarity:
                        .epic,
                    category:
                        .goals,
                    source:
                        .goal,
                    unlockedAt:
                        completedAt
                )
            }

            let historical =
                unlocks
                    .filter {
                        $0.trophyID ==
                            goalAwardID
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
            let effectiveRarity =
                historical?
                    .rarity ??
                .epic
            let effectiveUnlockedAt =
                historical?
                    .unlockedAt ??
                completedAt
            let currentStage =
                effectiveUnlockedAt
                    .map { _ in
                        TrophyStageDefinition(
                            id:
                                "complete",
                            title:
                                historical?
                                    .stageTitle ??
                                "Goal Complete",
                            threshold:
                                targetValue,
                            displayTarget:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Completed",
                                    norwegian:
                                        "Fullført"
                                ),
                            rarity:
                                effectiveRarity
                        )
                    }

            resolved.append(
                TrophyProgressItem(
                    id:
                        goalAwardID,
                    title:
                        goal.title,
                    subtitle:
                        "Goal Journey · \(goal.completedMilestones) of \(goal.milestones.count) milestones complete.",
                    category:
                        historical?
                            .category ??
                        .goals,
                    verificationSource:
                        .goal,
                    systemImage:
                        goal.category
                            .systemImage,
                    currentValue:
                        effectiveUnlockedAt == nil
                            ? currentValue
                            : max(
                                currentValue,
                                targetValue
                            ),
                    nextTargetValue:
                        effectiveUnlockedAt == nil
                            ? targetValue
                            : nil,
                    currentStage:
                        currentStage,
                    nextStage:
                        effectiveUnlockedAt == nil
                            ? TrophyStageDefinition(
                                id:
                                    "complete",
                                title:
                                    "Complete Journey",
                                threshold:
                                    targetValue,
                                displayTarget:
                                    "\(goal.milestones.count) milestones",
                                rarity:
                                    .epic
                            )
                            : nil,
                    highestRarity:
                        max(
                            effectiveRarity,
                            .epic
                        ),
                    unlockedAt:
                        effectiveUnlockedAt,
                    goalID:
                        goal.id,
                    journeyMilestonesCompleted:
                        goal.completedMilestones,
                    journeyMilestonesTotal:
                        goal.milestones.count
                )
            )
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

    func inscription(
        for trophyID: String
    ) -> TrophyInscription? {
        trophyInscriptions[
            trophyID
        ]
    }

    func cacheInscription(
        _ inscription:
            TrophyInscription,
        for trophyID: String
    ) {
        trophyInscriptions[
            trophyID
        ] = inscription
        persist()
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

    func replaceShowcase(
        _ currentTrophyID: String,
        with replacementTrophyID: String
    ) {
        guard currentTrophyID != replacementTrophyID,
              let index =
                showcaseIDs.firstIndex(
                    of: currentTrophyID
                ),
              !showcaseIDs.contains(
                    replacementTrophyID
              ),
              trophies.contains(
                    where: {
                        $0.id ==
                            replacementTrophyID &&
                        $0.isUnlocked
                    }
              )
        else {
            return
        }

        showcaseIDs[index] =
            replacementTrophyID
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

    @discardableResult
    func presentReveal(
        forStageKey stageKey: String
    ) -> Bool {
        guard let record =
                unlocks.first(
                    where: {
                        $0.stageKey ==
                            stageKey
                    }
                )
        else {
            return false
        }

        // Reveals are now user-driven from the Home notification bell.
        // Replace any stale queue so tapping one notification always opens
        // exactly the award the athlete selected.
        revealQueue = [record]
        pendingReveal = record
        return true
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

        let historicalStage =
            unlocks
                .filter {
                    $0.trophyID ==
                    definition.id
                }
                .compactMap {
                    record in
                    stages.first {
                        stage in
                        record.stageKey ==
                            "\(definition.id).stage.\(stage.id)"
                    }
                }
                .max {
                    $0.threshold <
                        $1.threshold
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
                live.threshold >=
                    old.threshold
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
                    $0.threshold >
                        current.threshold
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
        category: TrophyCategory = .signature,
        rarity: TrophyRarity = .signature,
        unlockedAt: Date?
    ) -> TrophyProgressItem {
        if let unlockedAt {
            registerUnlock(
                stageKey:
                    "\(id).unlocked",
                trophyID: id,
                stageTitle:
                    rarity.title,
                title: title,
                rarity: rarity,
                category: category,
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
        let resolvedRarity:
            TrophyRarity =
            PrestigeTrophyCatalog
                .isPrestigeTrophy(id)
                ? (
                    historical?
                        .rarity ??
                    rarity
                )
                : rarity
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
            category: category,
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
                        .longRun30KID,
                    snapshot
                        .firstThirtyKRunEvidence
                ),
                (
                    PrestigeTrophyCatalog
                        .marathonID,
                    snapshot
                        .firstMarathonEvidence
                ),
                (
                    PrestigeTrophyCatalog
                        .ultra50KID,
                    snapshot
                        .firstFiftyKRunEvidence
                )
            ]

        for claim in claims {
            guard !unlocks.contains(
                where: {
                    $0.trophyID ==
                        claim.id
                }
            ),
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

        // Keep the parameter for call-site compatibility. Unlocks are surfaced
        // through the notification bell and revealed only after an explicit tap.
        _ = allowReveal
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

        // Do not interrupt the athlete with an automatic reveal. The matching
        // bell notification is created by ATHLTHNotificationStore and opens
        // the reveal only when the athlete taps it.
        _ = activationDate
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
            trophyInscriptions:
                trophyInscriptions,
            hasInitializedShowcase: hasInitializedShowcase,
            ownerUserID: stateOwnerUserID,
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
    let trophyInscriptions:
        [String: TrophyInscription]?
    let hasInitializedShowcase: Bool
    let ownerUserID: UUID?
    let showcaseUpdatedAt: Date?

    static let empty = TrophyPersistedState(
        unlocks: [],
        showcaseIDs: [],
        trophyInscriptions: [:],
        hasInitializedShowcase: false,
        ownerUserID: nil,
        showcaseUpdatedAt: nil
    )
}
