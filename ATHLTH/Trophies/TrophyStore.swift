import Foundation

@MainActor
final class TrophyStore: ObservableObject {
    @Published private(set) var trophies: [TrophyProgressItem] = []
    @Published private(set) var unlocks: [TrophyUnlockRecord] = []
    @Published private(set) var showcaseIDs: [String] = []
    @Published private(set) var isRefreshing = false

    private var hasInitializedShowcase = false

    init() {
        let persisted = Self.loadState()
        unlocks = persisted.unlocks
        showcaseIDs = persisted.showcaseIDs
        hasInitializedShowcase = persisted.hasInitializedShowcase
    }

    var unlockedCount: Int {
        trophies.filter(\.isUnlocked).count
    }

    var showcaseTrophies: [TrophyProgressItem] {
        showcaseIDs.compactMap { id in trophies.first(where: { $0.id == id }) }
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

    func refresh(
        health: HealthKitManager,
        strength: StrengthWorkoutStore,
        goals: GoalStore
    ) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let healthSnapshot = try? await health.trophySnapshot()
        let strengthSnapshot = strength.trophySnapshot()
        let completedGoals = goals.goals.filter { $0.status == .completed }
        let completedGoalCount = completedGoals.count

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
                    unlockedAt: healthSnapshot.firstFiveKDate
                )
            )

            resolved.append(
                signature(
                    id: "signature.half-marathon",
                    title: "Half Marathon",
                    subtitle: "A recorded run reaching 21.1 kilometres.",
                    icon: "figure.run",
                    source: .appleHealth,
                    unlockedAt: healthSnapshot.firstHalfMarathonDate
                )
            )

            resolved.append(
                signature(
                    id: "signature.marathon",
                    title: "Marathon",
                    subtitle: "42.195 kilometres recorded in a single run.",
                    icon: "flag.checkered",
                    source: .appleHealth,
                    unlockedAt: healthSnapshot.firstMarathonDate
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
                unlockedAt: strengthSnapshot.firstWeightedSetDate
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
                    rarity: .signature
                )
            }

            resolved.append(
                TrophyProgressItem(
                    id: "goal.journey.\(goal.id.uuidString)",
                    title: goal.title,
                    subtitle: "Goal Journey · \(goal.completedMilestones) of \(goal.milestones.count) milestones complete.",
                    category: .signature,
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
                            rarity: .signature
                        )
                        : nil,
                    highestRarity: .signature,
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
                    rarity: .signature,
                    category: .signature,
                    source: .goal,
                    unlockedAt: unlockedAt
                )
            }
        }

        trophies = resolved.sorted(by: Self.collectionSort)

        if !hasInitializedShowcase {
            showcaseIDs = Array(
                trophies
                    .filter(\.isUnlocked)
                    .sorted(by: Self.showcaseSort)
                    .prefix(3)
                    .map(\.id)
            )
            hasInitializedShowcase = true
        } else {
            showcaseIDs = showcaseIDs.filter { id in
                trophies.contains(where: { $0.id == id && $0.isUnlocked })
            }
        }

        persist()
    }

    func isShowcased(_ trophyID: String) -> Bool {
        showcaseIDs.contains(trophyID)
    }

    func toggleShowcase(_ trophyID: String) {
        guard trophies.contains(where: { $0.id == trophyID && $0.isUnlocked }) else {
            return
        }

        if let index = showcaseIDs.firstIndex(of: trophyID) {
            showcaseIDs.remove(at: index)
        } else {
            guard showcaseIDs.count < 5 else { return }
            showcaseIDs.append(trophyID)
        }

        hasInitializedShowcase = true
        persist()
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
        let stages = definition.stages.sorted { $0.threshold < $1.threshold }
        let completed = stages.filter { value >= $0.threshold }
        let current = completed.last
        let next = stages.first { value < $0.threshold }

        for stage in completed {
            if let date = evidenceDate(stage.threshold) {
                registerUnlock(
                    stageKey: "\(definition.id).stage.\(stage.id)",
                    trophyID: definition.id,
                    stageTitle: stage.title,
                    title: definition.title,
                    rarity: stage.rarity,
                    category: definition.category,
                    source: definition.verificationSource,
                    unlockedAt: date
                )
            }
        }

        let latestUnlock = completed
            .compactMap { stage in
                unlocks.first(where: { $0.stageKey == "\(definition.id).stage.\(stage.id)" })
            }
            .sorted { $0.unlockedAt > $1.unlockedAt }
            .first?
            .unlockedAt

        return TrophyProgressItem(
            id: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            category: definition.category,
            verificationSource: definition.verificationSource,
            systemImage: definition.systemImage,
            currentValue: value,
            nextTargetValue: next?.threshold,
            currentStage: current,
            nextStage: next,
            highestRarity: stages.last?.rarity ?? .core,
            unlockedAt: latestUnlock,
            goalID: nil,
            journeyMilestonesCompleted: nil,
            journeyMilestonesTotal: nil
        )
    }

    private func signature(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        source: TrophyVerificationSource,
        unlockedAt: Date?
    ) -> TrophyProgressItem {
        let stage = unlockedAt.map { _ in
            TrophyStageDefinition(
                id: "unlocked",
                title: "Signature",
                threshold: 1,
                displayTarget: "Unlocked",
                rarity: .signature
            )
        }

        if let unlockedAt {
            registerUnlock(
                stageKey: "\(id).unlocked",
                trophyID: id,
                stageTitle: "Signature",
                title: title,
                rarity: .signature,
                category: .signature,
                source: source,
                unlockedAt: unlockedAt
            )
        }

        return TrophyProgressItem(
            id: id,
            title: title,
            subtitle: subtitle,
            category: .signature,
            verificationSource: source,
            systemImage: icon,
            currentValue: unlockedAt == nil ? 0 : 1,
            nextTargetValue: unlockedAt == nil ? 1 : nil,
            currentStage: stage,
            nextStage: unlockedAt == nil
                ? TrophyStageDefinition(
                    id: "unlocked",
                    title: "Signature",
                    threshold: 1,
                    displayTarget: "Complete",
                    rarity: .signature
                )
                : nil,
            highestRarity: .signature,
            unlockedAt: unlockedAt,
            goalID: nil,
            journeyMilestonesCompleted: nil,
            journeyMilestonesTotal: nil
        )
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

        unlocks.append(
            TrophyUnlockRecord(
                stageKey: stageKey,
                trophyID: trophyID,
                stageTitle: stageTitle,
                title: title,
                rarity: rarity,
                category: category,
                verificationSource: source,
                unlockedAt: unlockedAt
            )
        )
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
            hasInitializedShowcase: hasInitializedShowcase
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

    static let empty = TrophyPersistedState(
        unlocks: [],
        showcaseIDs: [],
        hasInitializedShowcase: false
    )
}
