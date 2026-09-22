import Foundation

@MainActor
final class GoalStore: ObservableObject {
    @Published private(set) var goals: [ATHLTHGoal] = []

    init() {
        goals = Self.loadGoals()
    }

    var activeGoals: [ATHLTHGoal] {
        goals
            .filter { $0.status == .active || $0.status == .paused }
            .sorted {
                if $0.isPrimary != $1.isPrimary { return $0.isPrimary && !$1.isPrimary }
                return $0.createdAt > $1.createdAt
            }
    }

    var primaryGoal: ATHLTHGoal? {
        goals.first { $0.isPrimary && ($0.status == .active || $0.status == .paused) }
    }

    func add(_ goal: ATHLTHGoal) {
        var newGoal = goal

        if goals.isEmpty {
            newGoal.isPrimary = true
        }

        if newGoal.isPrimary {
            goals = goals.map { existing in
                var copy = existing
                copy.isPrimary = false
                return copy
            }
        }

        goals.append(newGoal)
        normalizePrimaryGoal()
        persist()
    }

    func update(_ goal: ATHLTHGoal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }

        if goal.isPrimary {
            for otherIndex in goals.indices where goals[otherIndex].id != goal.id {
                goals[otherIndex].isPrimary = false
            }
        }

        goals[index] = goal
        normalizePrimaryGoal()
        persist()
    }

    func delete(_ goalID: UUID) {
        let wasPrimary = goals.first(where: { $0.id == goalID })?.isPrimary == true
        goals.removeAll { $0.id == goalID }

        if wasPrimary {
            normalizePrimaryGoal()
        }

        persist()
    }

    func setPrimary(_ goalID: UUID) {
        guard goals.contains(where: { $0.id == goalID }) else { return }

        for index in goals.indices {
            goals[index].isPrimary = goals[index].id == goalID
        }

        persist()
    }

    func setStatus(_ status: GoalStatus, for goalID: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }

        goals[index].status = status

        if status == .completed {
            goals[index].completedAt = goals[index].completedAt ?? Date()
        } else if status == .active || status == .paused {
            goals[index].completedAt = nil
        }

        normalizePrimaryGoal()
        persist()
    }

    func toggleMilestone(goalID: UUID, milestoneID: UUID) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalID }),
              let milestoneIndex = goals[goalIndex].milestones.firstIndex(where: { $0.id == milestoneID })
        else {
            return
        }

        let wasCompleted = goals[goalIndex].milestones[milestoneIndex].isCompleted

        if wasCompleted {
            goals[goalIndex].milestones[milestoneIndex].completedAt = nil
            goals[goalIndex].milestones[milestoneIndex].completionMethod = nil
            goals[goalIndex].milestones[milestoneIndex].manualOverride = .forceIncomplete

            if goals[goalIndex].status == .completed &&
                goals[goalIndex].milestones[milestoneIndex].completesGoal {
                goals[goalIndex].status = .active
                goals[goalIndex].completedAt = nil
            }
        } else {
            goals[goalIndex].milestones[milestoneIndex].completedAt = Date()
            goals[goalIndex].milestones[milestoneIndex].completionMethod = .manual
            goals[goalIndex].milestones[milestoneIndex].manualOverride = .forceCompleted

            if goals[goalIndex].milestones[milestoneIndex].completesGoal {
                goals[goalIndex].status = .completed
                goals[goalIndex].completedAt = Date()
            }
        }

        normalizePrimaryGoal()
        persist()
    }

    func resumeAutomaticTracking(goalID: UUID, milestoneID: UUID) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalID }),
              let milestoneIndex = goals[goalIndex].milestones.firstIndex(where: { $0.id == milestoneID })
        else {
            return
        }

        goals[goalIndex].milestones[milestoneIndex].manualOverride = .none
        persist()
    }

    func replaceMilestones(_ milestones: [GoalMilestone], for goalID: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[index].milestones = milestones
        persist()
    }

    func saveImageData(_ data: Data, for goalID: UUID) throws -> String {
        guard let directory = Self.goalImagesDirectory else {
            throw GoalStoreError.storageUnavailable
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let filename = "\(goalID.uuidString).jpg"
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    func imageURL(for goal: ATHLTHGoal) -> URL? {
        guard let filename = goal.imageFilename,
              let directory = Self.goalImagesDirectory
        else {
            return nil
        }

        return directory.appendingPathComponent(filename)
    }

    func refreshAutomaticMilestones(
        health: HealthKitManager,
        strength: StrengthWorkoutStore
    ) async {
        var changed = false

        for goalIndex in goals.indices {
            guard goals[goalIndex].status == .active else { continue }

            for milestoneIndex in goals[goalIndex].milestones.indices {
                let milestone = goals[goalIndex].milestones[milestoneIndex]

                guard !milestone.isCompleted,
                      milestone.manualOverride == .none,
                      let rule = milestone.automationRule,
                      rule.isEnabled,
                      rule.dataSource != .manual
                else {
                    continue
                }

                let evidenceStart = rule.countEvidenceOnlyAfterGoalCreation
                    ? max(goals[goalIndex].startDate, milestone.createdAt)
                    : goals[goalIndex].startDate

                let evidence: GoalAutomationEvidence?

                switch rule.dataSource {
                case .appleHealth:
                    evidence = try? await health.goalEvidence(
                        for: rule,
                        since: evidenceStart
                    )
                case .athlth:
                    evidence = strength.goalEvidence(
                        for: rule,
                        since: evidenceStart
                    )
                case .manual:
                    evidence = nil
                }

                goals[goalIndex].milestones[milestoneIndex].lastEvaluatedAt = Date()

                guard let evidence else {
                    continue
                }

                goals[goalIndex].milestones[milestoneIndex].lastEvidenceDescription =
                    evidence.description

                guard Self.ruleIsSatisfied(rule, by: evidence.currentValue) else {
                    changed = true
                    continue
                }

                goals[goalIndex].milestones[milestoneIndex].completedAt = evidence.evidenceDate
                goals[goalIndex].milestones[milestoneIndex].completionMethod =
                    rule.dataSource == .appleHealth ? .automaticAppleHealth : .automaticATHLTH
                changed = true

                if goals[goalIndex].milestones[milestoneIndex].completesGoal {
                    goals[goalIndex].status = .completed
                    goals[goalIndex].completedAt = evidence.evidenceDate
                }
            }
        }

        if changed {
            normalizePrimaryGoal()
            persist()
        }
    }

    private static func ruleIsSatisfied(
        _ rule: GoalAutomationRule,
        by currentValue: Double
    ) -> Bool {
        switch rule.comparison {
        case .atLeast:
            return currentValue >= rule.targetValue
        case .atMost:
            return currentValue <= rule.targetValue
        case .decreaseFromBaseline:
            guard let baseline = rule.baselineValue else { return false }
            return baseline - currentValue >= rule.targetValue
        case .increaseFromBaseline:
            guard let baseline = rule.baselineValue else { return false }
            return currentValue - baseline >= rule.targetValue
        }
    }

    private func normalizePrimaryGoal() {
        let eligibleIndices = goals.indices.filter {
            goals[$0].status == .active || goals[$0].status == .paused
        }

        let primaryIndices = eligibleIndices.filter { goals[$0].isPrimary }

        if primaryIndices.count > 1 {
            let keep = primaryIndices[0]
            for index in primaryIndices where index != keep {
                goals[index].isPrimary = false
            }
        } else if primaryIndices.isEmpty, let first = eligibleIndices.first {
            goals[first].isPrimary = true
        }

        for index in goals.indices where goals[index].status == .completed || goals[index].status == .abandoned {
            goals[index].isPrimary = false
        }
    }

    private func persist() {
        guard let url = Self.goalsURL else { return }

        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(goals)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private static func loadGoals() -> [ATHLTHGoal] {
        guard let url = goalsURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ATHLTHGoal].self, from: data)
        else {
            return []
        }

        return decoded
    }

    private static var supportDirectory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
    }

    private static var goalsURL: URL? {
        supportDirectory?.appendingPathComponent("goals-v1.json", isDirectory: false)
    }

    private static var goalImagesDirectory: URL? {
        supportDirectory?.appendingPathComponent("GoalImages", isDirectory: true)
    }
}

enum GoalStoreError: LocalizedError {
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "ATHLTH could not access local goal storage."
        }
    }
}
