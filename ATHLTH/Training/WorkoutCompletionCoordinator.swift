import Combine
import Foundation

enum WorkoutCompletionImpactKind: String, Codable, Hashable {
    case goal
    case challenge
    case gear
    case achievement
}

struct WorkoutCompletionImpactItem: Identifiable, Codable, Hashable {
    let id: String
    let kind: WorkoutCompletionImpactKind
    let title: String
    let detail: String
    let systemImage: String
}

struct WorkoutCompletionImpact: Identifiable, Codable, Hashable {
    var id: UUID { workoutID }

    let workoutID: UUID
    let generatedAt: Date
    let items: [WorkoutCompletionImpactItem]
}

/// A deliberately small bridge around workout completion.
///
/// ATHLTH already has mature stores for Health, Goals, Challenges, Gear and
/// Trophies. Replacing all of those side effects in one release would be a
/// regression risk. This coordinator gives every completion one canonical
/// before/after context now, so Watch and iPhone completions can surface the
/// same "what changed?" result while the existing store responsibilities stay
/// intact. More completion side effects can move behind this boundary
/// incrementally after the bridge has proven stable.
@MainActor
final class WorkoutCompletionCoordinator: ObservableObject {
    @Published private(set) var impacts: [UUID: WorkoutCompletionImpact]

    private struct GoalState {
        let progress: Double
        let status: GoalStatus
        let completedMilestoneIDs: Set<UUID>
    }

    private struct ChallengeState {
        let attemptIDs: Set<UUID>
    }

    private struct WeeklyState {
        let value: Double
        let completed: Bool
    }

    private struct GearState {
        let workoutCount: Int
        let duration: TimeInterval
        let distanceMeters: Double
    }

    private struct Baseline {
        let startedAt: Date
        var sourceIDs: Set<UUID>
        let goals: [UUID: GoalState]
        let challenges: [UUID: ChallengeState]
        let weekly: [UUID: WeeklyState]
        let gear: [UUID: GearState]
        let trophyKeys: Set<String>
    }

    private var baselines: [UUID: Baseline] = [:]

    init() {
        impacts = Self.loadImpacts()
        trimPersistedImpacts()
    }

    func impact(
        for workoutID: UUID
    ) -> WorkoutCompletionImpact? {
        impacts[workoutID]
    }

    func begin(
        workout: SocialPublishableWorkout,
        baselineKey: UUID? = nil,
        sourceIDs: Set<UUID>,
        goals: GoalStore,
        challenges: ChallengeStore,
        officialWeekly: OfficialWeeklyChallengeStore,
        healthWorkouts: [WorkoutSummary],
        gear: ProfileGearStore,
        trophies: TrophyStore
    ) {
        cleanupBaselines()

        let key = baselineKey ?? workout.id

        if var existing = baselines[key] {
            existing.sourceIDs.formUnion(sourceIDs)
            existing.sourceIDs.insert(workout.id)
            baselines[key] = existing
            return
        }

        let goalStates = Dictionary(
            uniqueKeysWithValues:
                goals.goals.map { goal in
                    (
                        goal.id,
                        GoalState(
                            progress: goal.progress,
                            status: goal.status,
                            completedMilestoneIDs:
                                Set(
                                    goal.milestones
                                        .filter(\.isCompleted)
                                        .map(\.id)
                                )
                        )
                    )
                }
        )

        let challengeStates = Dictionary(
            uniqueKeysWithValues:
                challenges.challenges.map { challenge in
                    (
                        challenge.id,
                        ChallengeState(
                            attemptIDs:
                                Set(
                                    challenge.attempts
                                        .map(\.id)
                                )
                        )
                    )
                }
        )

        var weeklyStates: [UUID: WeeklyState] = [:]
        for challenge in officialWeekly.challenges
        where officialWeekly.isJoined(challenge.id) {
            let value =
                OfficialWeeklyChallengeProgress.currentValue(
                    challenge: challenge,
                    workouts: healthWorkouts
                )

            weeklyStates[challenge.id] =
                WeeklyState(
                    value: value,
                    completed:
                        value >= challenge.targetValue
                )
        }

        let gearStates = Dictionary(
            uniqueKeysWithValues:
                gear.items.map { item in
                    let stats = gear.usageStats(for: item)
                    return (
                        item.id,
                        GearState(
                            workoutCount:
                                stats.workoutCount,
                            duration:
                                stats.totalDuration,
                            distanceMeters:
                                stats.totalDistanceMeters
                        )
                    )
                }
        )

        var resolvedSourceIDs = sourceIDs
        resolvedSourceIDs.insert(workout.id)

        baselines[key] =
            Baseline(
                startedAt: Date(),
                sourceIDs: resolvedSourceIDs,
                goals: goalStates,
                challenges: challengeStates,
                weekly: weeklyStates,
                gear: gearStates,
                trophyKeys:
                    Set(
                        trophies.unlocks
                            .map(\.stageKey)
                    )
            )
    }

    /// Re-running finalize is intentional. The first pass can populate Goals,
    /// Challenge and Gear impacts before the review appears; a later pass can
    /// add a Trophy that becomes available after trophy refresh completes.
    func finalize(
        workout: SocialPublishableWorkout,
        baselineKey: UUID? = nil,
        sourceIDs: Set<UUID>,
        userID: UUID,
        goals: GoalStore,
        challenges: ChallengeStore,
        officialWeekly: OfficialWeeklyChallengeStore,
        healthWorkouts: [WorkoutSummary],
        gear: ProfileGearStore,
        trophies: TrophyStore
    ) {
        let key = baselineKey ?? workout.id

        guard var baseline = baselines[key] else {
            begin(
                workout: workout,
                baselineKey: key,
                sourceIDs: sourceIDs,
                goals: goals,
                challenges: challenges,
                officialWeekly: officialWeekly,
                healthWorkouts: healthWorkouts,
                gear: gear,
                trophies: trophies
            )
            return
        }

        baseline.sourceIDs.formUnion(sourceIDs)
        baseline.sourceIDs.insert(workout.id)
        baselines[key] = baseline

        var items: [WorkoutCompletionImpactItem] = []

        items.append(
            contentsOf:
                goalImpacts(
                    baseline: baseline,
                    goals: goals
                )
        )

        items.append(
            contentsOf:
                weeklyChallengeImpacts(
                    workout: workout,
                    baseline: baseline,
                    officialWeekly: officialWeekly,
                    healthWorkouts: healthWorkouts
                )
        )

        items.append(
            contentsOf:
                challengeImpacts(
                    baseline: baseline,
                    userID: userID,
                    challenges: challenges
                )
        )

        items.append(
            contentsOf:
                gearImpacts(
                    workout: workout,
                    baseline: baseline,
                    gear: gear
                )
        )

        items.append(
            contentsOf:
                trophyImpacts(
                    workout: workout,
                    baseline: baseline,
                    trophies: trophies
                )
        )

        let impact =
            WorkoutCompletionImpact(
                workoutID: workout.id,
                generatedAt: Date(),
                items: Array(items.prefix(8))
            )

        impacts[workout.id] = impact
        trimPersistedImpacts()
        persistImpacts()
    }

    private func goalImpacts(
        baseline: Baseline,
        goals: GoalStore
    ) -> [WorkoutCompletionImpactItem] {
        var results: [WorkoutCompletionImpactItem] = []

        for goal in goals.goals {
            guard let before = baseline.goals[goal.id] else {
                continue
            }

            let newlyCompletedMilestones =
                goal.milestones.filter {
                    $0.isCompleted &&
                    !before.completedMilestoneIDs.contains($0.id)
                }

            let becameCompleted =
                before.status != .completed &&
                goal.status == .completed

            guard becameCompleted ||
                    goal.progress > before.progress + 0.0001 ||
                    !newlyCompletedMilestones.isEmpty
            else {
                continue
            }

            let detail: String

            if becameCompleted {
                detail = "Goal completed"
            } else if let milestone =
                        newlyCompletedMilestones.first {
                detail =
                    "Milestone reached · \(milestone.title) · \(percentage(goal.progress)) complete"
            } else {
                detail =
                    "\(percentage(before.progress)) → \(percentage(goal.progress)) complete"
            }

            results.append(
                WorkoutCompletionImpactItem(
                    id: "goal-\(goal.id.uuidString)",
                    kind: .goal,
                    title: goal.title,
                    detail: detail,
                    systemImage: "target"
                )
            )
        }

        return results
    }

    private func weeklyChallengeImpacts(
        workout: SocialPublishableWorkout,
        baseline: Baseline,
        officialWeekly: OfficialWeeklyChallengeStore,
        healthWorkouts: [WorkoutSummary]
    ) -> [WorkoutCompletionImpactItem] {
        guard workout.activity == .running ||
                workout.activity == .walking
        else {
            return []
        }

        var results: [WorkoutCompletionImpactItem] = []

        for challenge in officialWeekly.challenges
        where officialWeekly.isJoined(challenge.id) &&
                workout.startDate >= challenge.startsAt &&
                workout.startDate < challenge.endsAt {
            let before =
                baseline.weekly[challenge.id] ??
                WeeklyState(
                    value: 0,
                    completed: false
                )

            let after =
                OfficialWeeklyChallengeProgress.currentValue(
                    challenge: challenge,
                    workouts: healthWorkouts
                )

            guard after > before.value + 0.0001 else {
                continue
            }

            let completed =
                !before.completed &&
                after >= challenge.targetValue

            results.append(
                WorkoutCompletionImpactItem(
                    id:
                        "weekly-\(challenge.id.uuidString)",
                    kind: .challenge,
                    title: challenge.title,
                    detail:
                        weeklyChallengeDetail(
                            kind: challenge.kind,
                            before: before.value,
                            after: after,
                            target: challenge.targetValue,
                            completed: completed
                        ),
                    systemImage: "trophy.fill"
                )
            )
        }

        return results
    }

    private func challengeImpacts(
        baseline: Baseline,
        userID: UUID,
        challenges: ChallengeStore
    ) -> [WorkoutCompletionImpactItem] {
        var results: [WorkoutCompletionImpactItem] = []

        for challenge in challenges.challenges {
            let oldAttemptIDs =
                baseline.challenges[challenge.id]?
                    .attemptIDs ?? []

            guard let attempt =
                    challenge.attempts
                        .filter({
                            !oldAttemptIDs.contains($0.id) &&
                            $0.userID == userID &&
                            $0.sourceWorkoutID.map(
                                baseline.sourceIDs.contains
                            ) == true
                        })
                        .sorted(by: {
                            $0.submittedAt >
                            $1.submittedAt
                        })
                        .first
            else {
                continue
            }

            let detail: String

            if attempt.isEligible {
                let rank =
                    challenges
                        .leaderboard(
                            for: challenge.id
                        )
                        .first(
                            where: {
                                $0.participant
                                    .userID ==
                                    userID
                            }
                        )?
                        .rank

                if let rank {
                    detail =
                        "\(attempt.detail) · rank #\(rank)"
                } else {
                    detail = attempt.detail
                }
            } else {
                detail =
                    attempt.ineligibilityReason
                        .map {
                            "Attempt checked · \($0)"
                        }
                    ?? "Attempt checked against challenge rules"
            }

            results.append(
                WorkoutCompletionImpactItem(
                    id:
                        "challenge-\(challenge.id.uuidString)-\(attempt.id.uuidString)",
                    kind: .challenge,
                    title: challenge.title,
                    detail: detail,
                    systemImage:
                        challenge.sport.systemImage
                )
            )
        }

        return results
    }

    private func gearImpacts(
        workout: SocialPublishableWorkout,
        baseline: Baseline,
        gear: ProfileGearStore
    ) -> [WorkoutCompletionImpactItem] {
        let workoutGearIDs =
            gear.gearIDs(
                for: workout.id
            )

        guard !workoutGearIDs.isEmpty else {
            return []
        }

        return gear.items.compactMap { item in
            guard workoutGearIDs.contains(item.id) else {
                return nil
            }

            let current =
                gear.usageStats(for: item)
            let previous =
                baseline.gear[item.id] ??
                GearState(
                    workoutCount: 0,
                    duration: 0,
                    distanceMeters: 0
                )

            let distanceDelta =
                max(
                    current.totalDistanceMeters -
                    previous.distanceMeters,
                    0
                )
            let durationDelta =
                max(
                    current.totalDuration -
                    previous.duration,
                    0
                )

            guard current.workoutCount >
                    previous.workoutCount ||
                    distanceDelta > 1 ||
                    durationDelta > 1
            else {
                return nil
            }

            let detail: String

            if distanceDelta >= 50 {
                detail =
                    "+\(distanceText(distanceDelta)) · \(distanceText(current.totalDistanceMeters)) total"
            } else {
                detail =
                    "+\(durationText(durationDelta)) · \(current.workoutCount) workouts total"
            }

            return WorkoutCompletionImpactItem(
                id:
                    "gear-\(item.id.uuidString)",
                kind: .gear,
                title: item.name,
                detail: detail,
                systemImage:
                    item.category.systemImage
            )
        }
    }

    private func trophyImpacts(
        workout: SocialPublishableWorkout,
        baseline: Baseline,
        trophies: TrophyStore
    ) -> [WorkoutCompletionImpactItem] {
        trophies.unlocks
            .filter {
                !baseline.trophyKeys.contains(
                    $0.stageKey
                ) &&
                abs(
                    $0.unlockedAt
                        .timeIntervalSince(
                            workout.endDate
                        )
                ) <= 600
            }
            .sorted {
                $0.unlockedAt >
                $1.unlockedAt
            }
            .prefix(2)
            .map { unlock in
                WorkoutCompletionImpactItem(
                    id:
                        "trophy-\(unlock.stageKey)",
                    kind: .achievement,
                    title: unlock.title,
                    detail:
                        "\(unlock.stageTitle) unlocked",
                    systemImage: "medal.fill"
                )
            }
    }

    private func weeklyChallengeDetail(
        kind: OfficialRunningChallengeKind,
        before: Double,
        after: Double,
        target: Double,
        completed: Bool
    ) -> String {
        if completed {
            return "Challenge completed · \(weeklyValue(after, kind: kind)) / \(weeklyValue(target, kind: kind))"
        }

        let delta = max(after - before, 0)

        return
            "+\(weeklyValue(delta, kind: kind)) · \(weeklyValue(after, kind: kind)) / \(weeklyValue(target, kind: kind))"
    }

    private func weeklyValue(
        _ value: Double,
        kind: OfficialRunningChallengeKind
    ) -> String {
        switch kind {
        case .distance:
            return String(
                format: "%.1f km",
                value
            )
        case .sessions:
            return
                "\(Int(value.rounded(.down))) workout\(Int(value.rounded(.down)) == 1 ? "" : "s")"
        case .minutes:
            return
                "\(Int(value.rounded())) min"
        case .streak:
            return
                "\(Int(value.rounded(.down))) day\(Int(value.rounded(.down)) == 1 ? "" : "s")"
        }
    }

    private func percentage(
        _ value: Double
    ) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private func distanceText(
        _ meters: Double
    ) -> String {
        if meters >= 1_000 {
            return String(
                format: "%.1f km",
                meters / 1_000
            )
        }

        return "\(Int(meters.rounded())) m"
    }

    private func durationText(
        _ seconds: TimeInterval
    ) -> String {
        let minutes =
            max(
                Int((seconds / 60).rounded()),
                1
            )

        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder > 0
                ? "\(hours)h \(remainder)m"
                : "\(hours)h"
        }

        return "\(minutes) min"
    }

    private func cleanupBaselines() {
        let cutoff =
            Date()
                .addingTimeInterval(-7_200)

        baselines =
            baselines.filter {
                $0.value.startedAt >= cutoff
            }
    }

    private func trimPersistedImpacts() {
        let cutoff =
            Date()
                .addingTimeInterval(
                    -14 * 86_400
                )

        let sorted =
            impacts.values
                .filter {
                    $0.generatedAt >= cutoff
                }
                .sorted {
                    $0.generatedAt >
                    $1.generatedAt
                }

        impacts =
            Dictionary(
                uniqueKeysWithValues:
                    sorted.prefix(50)
                        .map {
                            ($0.workoutID, $0)
                        }
            )
    }

    private func persistImpacts() {
        guard let url = Self.impactsURL else {
            return
        }

        do {
            let directory =
                url.deletingLastPathComponent()

            try FileManager.default
                .createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )

            let data =
                try JSONEncoder()
                    .encode(
                        Array(impacts.values)
                    )

            try data.write(
                to: url,
                options: .atomic
            )
        } catch {
            return
        }
    }

    private static func loadImpacts()
        -> [UUID: WorkoutCompletionImpact] {
        guard let url = impactsURL,
              let data =
                try? Data(
                    contentsOf: url
                ),
              let decoded =
                try? JSONDecoder().decode(
                    [WorkoutCompletionImpact].self,
                    from: data
                )
        else {
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues:
                decoded.map {
                    ($0.workoutID, $0)
                }
        )
    }

    private static var impactsURL: URL? {
        FileManager.default
            .urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )
            .first?
            .appendingPathComponent(
                "ATHLTH",
                isDirectory: true
            )
            .appendingPathComponent(
                "workout-completion-impacts-v1.json",
                isDirectory: false
            )
    }
}
