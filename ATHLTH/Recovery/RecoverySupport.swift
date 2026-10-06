import Charts
import Combine
import Foundation
import SwiftUI

private func recoveryText(
    _ english: String,
    _ norwegian: String
) -> String {
    ATHLTHLocalization.choose(
        english: english,
        norwegian: norwegian
    )
}

private func recoveryMuscleName(
    _ value: String
) -> String {
    guard ATHLTHLocalization.isNorwegian else {
        return value
    }

    switch value {
    case "Chest": return "Bryst"
    case "Back": return "Rygg"
    case "Shoulders": return "Skuldre"
    case "Arms": return "Armer"
    case "Core": return "Kjerne"
    case "Glutes": return "Setemuskler"
    case "Quads": return "Forside lår"
    case "Hamstrings": return "Bakside lår"
    case "Calves": return "Legger"
    default: return value
    }
}

struct RecoveryTrendDay: Identifiable, Equatable {
    var id: Date { date }

    let date: Date
    let sleepDuration: TimeInterval?
    let hrvMilliseconds: Double?
    let restingHeartRate: Double?
    let respiratoryRate: Double?
    let trainingMinutes: Double
}

struct RecoveryTrainingLoadSummary: Equatable, Hashable, Sendable {
    let acuteMinutes: Double
    let chronicWeeklyAverageMinutes: Double?
    let strengthMinutes: Double
    let runningMinutes: Double
    let walkingMinutes: Double
    let otherMinutes: Double
    let latestStrengthAt: Date?
    let latestRunningAt: Date?
    let latestWalkingAt: Date?

    init(
        acuteMinutes: Double,
        chronicWeeklyAverageMinutes: Double?,
        strengthMinutes: Double = 0,
        runningMinutes: Double = 0,
        walkingMinutes: Double = 0,
        otherMinutes: Double = 0,
        latestStrengthAt: Date? = nil,
        latestRunningAt: Date? = nil,
        latestWalkingAt: Date? = nil
    ) {
        self.acuteMinutes = acuteMinutes
        self.chronicWeeklyAverageMinutes = chronicWeeklyAverageMinutes
        self.strengthMinutes = strengthMinutes
        self.runningMinutes = runningMinutes
        self.walkingMinutes = walkingMinutes
        self.otherMinutes = otherMinutes
        self.latestStrengthAt = latestStrengthAt
        self.latestRunningAt = latestRunningAt
        self.latestWalkingAt = latestWalkingAt
    }

    var ratio: Double? {
        guard let chronicWeeklyAverageMinutes,
              chronicWeeklyAverageMinutes > 0 else {
            return nil
        }

        return acuteMinutes / chronicWeeklyAverageMinutes
    }

    var movementMinutes: Double {
        runningMinutes + walkingMinutes
    }

    var hasStrengthRunOrWalk: Bool {
        strengthMinutes > 0 || runningMinutes > 0 || walkingMinutes > 0
    }

    var title: String {
        guard let ratio else {
            return recoveryText("Building load baseline", "Bygger belastningsgrunnlag")
        }

        switch ratio {
        case ..<0.75:
            return recoveryText("Below recent load", "Under nyere belastning")
        case 0.75...1.25:
            return recoveryText("Near recent load", "Nær nyere belastning")
        case 1.25...1.50:
            return recoveryText("Elevated load", "Forhøyet belastning")
        default:
            return recoveryText("High load", "Høy belastning")
        }
    }
}

struct RecoveryTrendSnapshot: Equatable {
    let days: [RecoveryTrendDay]
    let trainingLoad: RecoveryTrainingLoadSummary

    static let empty = RecoveryTrendSnapshot(
        days: [],
        trainingLoad: RecoveryTrainingLoadSummary(
            acuteMinutes: 0,
            chronicWeeklyAverageMinutes: nil
        )
    )
}

enum RecoverySorenessLevel: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case mild = 1
    case moderate = 2
    case high = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return recoveryText("None", "Ingen")
        case .mild: return recoveryText("Mild", "Lett")
        case .moderate: return recoveryText("Moderate", "Moderat")
        case .high: return recoveryText("High", "Høy")
        }
    }

    var shortTitle: String {
        switch self {
        case .none: return recoveryText("Ready", "Klar")
        case .mild: return recoveryText("Mild", "Lett")
        case .moderate: return recoveryText("Sore", "Øm")
        case .high: return recoveryText("Very sore", "Svært øm")
        }
    }
}

struct RecoverySorenessEntry: Codable, Hashable {
    let date: Date
    var ratings: [String: RecoverySorenessLevel]
    var energy: Int?
    var stress: Int?
    var overallSoreness: Int?
    var motivation: Int?
}

final class RecoverySorenessStore: ObservableObject {
    @Published private(set) var entries: [RecoverySorenessEntry]

    private let defaults: UserDefaults
    private let storageKey = "recovery.soreness.entries"

    static let muscleGroups = [
        "Chest",
        "Back",
        "Shoulders",
        "Arms",
        "Core",
        "Glutes",
        "Quads",
        "Hamstrings",
        "Calves"
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(
                [RecoverySorenessEntry].self,
                from: data
           ) {
            entries = decoded
        } else {
            entries = []
        }

        trimAndPersistIfNeeded()
    }

    private var todayEntry: RecoverySorenessEntry? {
        let calendar = Calendar.current
        return entries.first {
            calendar.isDateInToday($0.date)
        }
    }

    var todayRatings: [String: RecoverySorenessLevel] {
        todayEntry?.ratings ?? [:]
    }

    var todayEnergy: Int? {
        todayEntry?.energy
    }

    var todayStress: Int? {
        todayEntry?.stress
    }

    var todayOverallSoreness: Int? {
        todayEntry?.overallSoreness
    }

    var todayMotivation: Int? {
        todayEntry?.motivation
    }

    var hasTodayCheckIn: Bool {
        todayEnergy != nil ||
        todayStress != nil ||
        todayOverallSoreness != nil ||
        todayMotivation != nil ||
        !todayRatings.isEmpty
    }

    var highestTodayLevel: RecoverySorenessLevel {
        todayRatings.values.max {
            $0.rawValue < $1.rawValue
        } ?? .none
    }

    func level(for muscleGroup: String) -> RecoverySorenessLevel {
        todayRatings[muscleGroup] ?? .none
    }

    func setEnergy(_ value: Int) {
        updateTodayEntry {
            $0.energy = Self.normalizedCheckInValue(value)
        }
    }

    func setStress(_ value: Int) {
        updateTodayEntry {
            $0.stress = Self.normalizedCheckInValue(value)
        }
    }

    func setOverallSoreness(_ value: Int) {
        updateTodayEntry {
            $0.overallSoreness =
                Self.normalizedCheckInValue(value)
        }
    }

    func setMotivation(_ value: Int) {
        updateTodayEntry {
            $0.motivation = Self.normalizedCheckInValue(value)
        }
    }

    func set(
        _ level: RecoverySorenessLevel,
        for muscleGroup: String
    ) {
        updateTodayEntry {
            $0.ratings[muscleGroup] = level
        }
    }

    private func updateTodayEntry(
        _ update: (inout RecoverySorenessEntry) -> Void
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let index = entries.firstIndex(
            where: {
                calendar.isDate(
                    $0.date,
                    inSameDayAs: today
                )
            }
        ) {
            update(&entries[index])
        } else {
            var entry = RecoverySorenessEntry(
                date: today,
                ratings: [:],
                energy: nil,
                stress: nil,
                overallSoreness: nil,
                motivation: nil
            )
            update(&entry)
            entries.insert(entry, at: 0)
        }

        trimAndPersistIfNeeded()
    }

    private static func normalizedCheckInValue(
        _ value: Int
    ) -> Int {
        min(max(value, 1), 5)
    }

    private func trimAndPersistIfNeeded() {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -30,
            to: Date()
        ) ?? Date().addingTimeInterval(-2_592_000)

        entries = entries
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }

        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

struct MuscleRecoveryStatus: Identifiable, Equatable {
    var id: String { muscleGroup }

    let muscleGroup: String
    let lastTrainedAt: Date?
    let completedSets: Int
    let strengthMinutes: Double
    let runningMinutes: Double
    let walkingMinutes: Double
    let estimatedRecoveryHours: Double
    let soreness: RecoverySorenessLevel
    let baselineWeeklyStrengthSets: Double?
    let baselineWeeklyStrengthMinutes: Double?
    let chronicWeeklyTrainingMinutes: Double?
    let acuteToChronicRatio: Double?

    init(
        muscleGroup: String,
        lastTrainedAt: Date?,
        completedSets: Int,
        strengthMinutes: Double = 0,
        runningMinutes: Double = 0,
        walkingMinutes: Double = 0,
        estimatedRecoveryHours: Double,
        soreness: RecoverySorenessLevel,
        baselineWeeklyStrengthSets: Double? = nil,
        baselineWeeklyStrengthMinutes: Double? = nil,
        chronicWeeklyTrainingMinutes: Double? = nil,
        acuteToChronicRatio: Double? = nil
    ) {
        self.muscleGroup = muscleGroup
        self.lastTrainedAt = lastTrainedAt
        self.completedSets = completedSets
        self.strengthMinutes = strengthMinutes
        self.runningMinutes = runningMinutes
        self.walkingMinutes = walkingMinutes
        self.estimatedRecoveryHours = estimatedRecoveryHours
        self.soreness = soreness
        self.baselineWeeklyStrengthSets = baselineWeeklyStrengthSets
        self.baselineWeeklyStrengthMinutes = baselineWeeklyStrengthMinutes
        self.chronicWeeklyTrainingMinutes = chronicWeeklyTrainingMinutes
        self.acuteToChronicRatio = acuteToChronicRatio
    }

    var progress: Double {
        guard let lastTrainedAt else {
            return soreness == .none ? 1 : 0.45
        }

        let hours = max(
            Date().timeIntervalSince(lastTrainedAt) / 3_600,
            0
        )

        return min(
            max(hours / max(estimatedRecoveryHours, 1), 0),
            1
        )
    }

    var trainingMinutes: Double {
        strengthMinutes + runningMinutes + walkingMinutes
    }

    /// A minute-weighted load score with a deliberate low-load dead zone.
    /// Short or easy sessions should stay neutral instead of looking alarming.
    var loadScore: Double {
        let learnedStrengthSetCapacity =
            max(
                (baselineWeeklyStrengthSets ?? 0) * 1.6,
                10
            )
        let strengthSetLoad =
            completedSets > 1
                ? min(
                    Double(completedSets - 1) /
                        learnedStrengthSetCapacity,
                    1
                )
                : 0

        let learnedStrengthMinuteCapacity =
            max(
                (baselineWeeklyStrengthMinutes ?? 0) * 1.5,
                75
            )
        let strengthMinuteDose =
            max(strengthMinutes - 6, 0)
        let strengthMinuteLoad =
            min(
                strengthMinuteDose /
                    learnedStrengthMinuteCapacity,
                1
            )
        let strengthLoad =
            min(
                strengthMinuteLoad * 0.62 +
                strengthSetLoad * 0.38,
                1
            )

        let movementMinutes =
            runningMinutes +
            walkingMinutes
        let learnedMovementCapacity =
            max(
                (chronicWeeklyTrainingMinutes ?? 0) *
                    0.75,
                180
            )
        let movementDose =
            max(movementMinutes - 12, 0)
        let movementLoad =
            min(
                movementDose /
                    learnedMovementCapacity,
                1
            )

        var combined =
            1 -
            (
                (1 - strengthLoad) *
                (1 - movementLoad)
            )

        // Tiny sessions should register as activity without creating a
        // "high load" visual state.
        if trainingMinutes < 10 &&
            completedSets <= 1 &&
            soreness == .none {
            combined *= 0.20
        }

        let spikeMultiplier: Double
        if combined >= 0.35 &&
            trainingMinutes >= 30 {
            switch acuteToChronicRatio {
            case let ratio? where ratio > 1.50:
                spikeMultiplier = 1.18
            case let ratio? where ratio > 1.25:
                spikeMultiplier = 1.10
            case let ratio? where ratio > 1.00:
                spikeMultiplier = 1.04
            default:
                spikeMultiplier = 1
            }
        } else {
            spikeMultiplier = 1
        }

        return min(
            max(
                combined * spikeMultiplier,
                0
            ),
            1
        )
    }

    /// Current load fades as the recovery window progresses. Manual soreness
    /// can still keep an area elevated, but normal low-volume training stays
    /// green or neutral.
    var currentLoadScore: Double {
        let remainingLoad =
            max(
                1 - (progress * 0.88),
                0.05
            )
        var score =
            loadScore *
            remainingLoad

        let sorenessFloor: Double
        switch soreness {
        case .none:
            sorenessFloor = 0
        case .mild:
            sorenessFloor = 0.24
        case .moderate:
            sorenessFloor = 0.52
        case .high:
            sorenessFloor = 0.84
        }

        score = max(
            score,
            sorenessFloor
        )

        return min(
            max(score, 0),
            1
        )
    }

    var readinessScore: Double {
        min(
            max(1 - currentLoadScore, 0),
            1
        )
    }

    var loadTitle: String {
        switch currentLoadScore {
        case 0.84...:
            return recoveryText("Needs rest", "Trenger pause")
        case 0.65..<0.84:
            return recoveryText("High", "Høy")
        case 0.44..<0.65:
            return recoveryText("Moderate", "Moderat")
        case 0.20..<0.44:
            return recoveryText("Light", "Lett")
        default:
            return recoveryText("Ready", "Klar")
        }
    }

    var sourceSummary: String {
        var sources: [String] = []

        if completedSets > 0 || strengthMinutes >= 1 {
            let minutes =
                Int(strengthMinutes.rounded())
            if minutes > 0 {
                sources.append(
                    recoveryText(
                        "Strength · \(minutes) min",
                        "Styrke · \(minutes) min"
                    )
                )
            } else {
                sources.append(
                    recoveryText(
                        "Strength · \(completedSets) sets",
                        "Styrke · \(completedSets) sett"
                    )
                )
            }
        }
        if runningMinutes >= 1 {
            let minutes =
                Int(runningMinutes.rounded())
            sources.append(
                recoveryText(
                    "Run · \(minutes) min",
                    "Løp · \(minutes) min"
                )
            )
        }
        if walkingMinutes >= 1 {
            let minutes =
                Int(walkingMinutes.rounded())
            sources.append(
                recoveryText(
                    "Walk · \(minutes) min",
                    "Gange · \(minutes) min"
                )
            )
        }

        return sources.isEmpty ? recoveryText("Check-in", "Innsjekk") : sources.joined(separator: " + ")
    }

    var statusTitle: String {
        if soreness == .high {
            return recoveryText("Very sore", "Svært øm")
        }

        if soreness == .moderate {
            return recoveryText("Sore", "Øm")
        }

        switch currentLoadScore {
        case 0.84...:
            return recoveryText(
                "Short break suggested",
                "Liten pause anbefales"
            )
        case 0.65..<0.84:
            return recoveryText("High load", "Høy belastning")
        case 0.44..<0.65:
            return recoveryText(
                "Moderate load",
                "Moderat belastning"
            )
        case 0.20..<0.44:
            return recoveryText("Light load", "Lett belastning")
        default:
            return soreness == .mild
                ? recoveryText("Mild soreness", "Lett ømhet")
                : recoveryText("Ready", "Klar")
        }
    }

}

enum MuscleRecoveryEngine {
    static func statuses(
        history: [StrengthWorkoutLog],
        soreness: RecoverySorenessStore,
        activityLoad: RecoveryTrainingLoadSummary = RecoveryTrendSnapshot.empty.trainingLoad
    ) -> [MuscleRecoveryStatus] {
        statuses(
            history: history,
            sorenessRatings: soreness.todayRatings,
            activityLoad: activityLoad
        )
    }

    static func statuses(
        history: [StrengthWorkoutLog],
        sorenessRatings: [String: RecoverySorenessLevel],
        activityLoad: RecoveryTrainingLoadSummary = RecoveryTrendSnapshot.empty.trainingLoad
    ) -> [MuscleRecoveryStatus] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        let baselineStart =
            now.addingTimeInterval(-35 * 86_400)

        struct StrengthContribution {
            let group: String
            let completedSets: Int
            let minutes: Double
        }

        func contributions(
            for workout: StrengthWorkoutLog
        ) -> [StrengthContribution] {
            let exerciseLoads =
                workout.exercises.compactMap {
                    exercise
                    -> (
                        groups: [String],
                        sets: Int
                    )? in
                    let completedSets =
                        exercise.sets
                            .filter(
                                \.countsTowardTrainingLoad
                            )
                            .count
                    guard completedSets > 0 else {
                        return nil
                    }

                    let groups =
                        Array(
                            Set(
                                exercise.exercise
                                    .primaryMuscles
                                    .compactMap(
                                        normalizedMuscleGroup
                                    )
                            )
                        )

                    guard !groups.isEmpty else {
                        return nil
                    }

                    return (
                        groups,
                        completedSets
                    )
                }

            let totalSets =
                exerciseLoads.reduce(0) {
                    $0 + $1.sets
                }

            guard totalSets > 0 else {
                return []
            }

            let workoutMinutes =
                max(
                    (
                        workout.endedAt ??
                        workout.startedAt
                    )
                    .timeIntervalSince(
                        workout.startedAt
                    ) / 60,
                    0
                )

            var result:
                [StrengthContribution] = []

            for load in exerciseLoads {
                let exerciseMinutes =
                    workoutMinutes *
                    Double(load.sets) /
                    Double(totalSets)
                let minutesPerGroup =
                    exerciseMinutes /
                    Double(load.groups.count)

                for group in load.groups {
                    result.append(
                        StrengthContribution(
                            group: group,
                            completedSets:
                                load.sets,
                            minutes:
                                minutesPerGroup
                        )
                    )
                }
            }

            return result
        }

        var baselineSetTotals:
            [String: Int] = [:]
        var baselineMinuteTotals:
            [String: Double] = [:]

        for workout in history
        where workout.isFinished &&
            workout.startedAt >= baselineStart &&
            workout.startedAt < cutoff {
            for contribution in
                contributions(for: workout) {
                baselineSetTotals[
                    contribution.group,
                    default: 0
                ] += contribution.completedSets
                baselineMinuteTotals[
                    contribution.group,
                    default: 0
                ] += contribution.minutes
            }
        }

        let baselineWeeklyStrengthSets =
            baselineSetTotals
                .mapValues {
                    Double($0) / 4
                }
        let baselineWeeklyStrengthMinutes =
            baselineMinuteTotals
                .mapValues {
                    $0 / 4
                }

        struct Accumulator {
            var lastTrainedAt: Date?
            var completedSets = 0
            var strengthMinutes: Double = 0
            var runningMinutes: Double = 0
            var walkingMinutes: Double = 0
        }

        var values: [String: Accumulator] = [:]

        for workout in history
        where workout.isFinished &&
            workout.startedAt >= cutoff {
            let workoutDate =
                workout.endedAt ??
                workout.startedAt

            for contribution in
                contributions(for: workout) {
                var item =
                    values[contribution.group] ??
                    Accumulator()

                item.completedSets +=
                    contribution.completedSets
                item.strengthMinutes +=
                    contribution.minutes

                if item.lastTrainedAt.map({
                    workoutDate > $0
                }) ?? true {
                    item.lastTrainedAt =
                        workoutDate
                }

                values[contribution.group] =
                    item
            }
        }

        func addMovement(
            group: String,
            runningMinutes: Double = 0,
            walkingMinutes: Double = 0,
            date: Date?
        ) {
            guard runningMinutes > 0 ||
                    walkingMinutes > 0
            else {
                return
            }

            var item =
                values[group] ??
                Accumulator()
            item.runningMinutes +=
                runningMinutes
            item.walkingMinutes +=
                walkingMinutes

            if let date,
               item.lastTrainedAt.map({
                   date > $0
               }) ?? true {
                item.lastTrainedAt =
                    date
            }

            values[group] =
                item
        }

        let run =
            activityLoad.runningMinutes
        let walk =
            activityLoad.walkingMinutes

        addMovement(
            group: "Quads",
            runningMinutes: run,
            walkingMinutes: walk * 0.48,
            date: maxDate(
                activityLoad.latestRunningAt,
                activityLoad.latestWalkingAt
            )
        )
        addMovement(
            group: "Calves",
            runningMinutes: run,
            walkingMinutes: walk * 0.58,
            date: maxDate(
                activityLoad.latestRunningAt,
                activityLoad.latestWalkingAt
            )
        )
        addMovement(
            group: "Hamstrings",
            runningMinutes: run * 0.82,
            walkingMinutes: walk * 0.28,
            date: maxDate(
                activityLoad.latestRunningAt,
                activityLoad.latestWalkingAt
            )
        )
        addMovement(
            group: "Glutes",
            runningMinutes: run * 0.88,
            walkingMinutes: walk * 0.42,
            date: maxDate(
                activityLoad.latestRunningAt,
                activityLoad.latestWalkingAt
            )
        )
        addMovement(
            group: "Core",
            runningMinutes: run * 0.34,
            walkingMinutes: walk * 0.16,
            date: maxDate(
                activityLoad.latestRunningAt,
                activityLoad.latestWalkingAt
            )
        )

        let allGroups =
            Set(values.keys)
                .union(
                    sorenessRatings.keys
                )

        return allGroups
            .map { group in
                let item =
                    values[group] ??
                    Accumulator()
                let sorenessLevel =
                    sorenessRatings[group] ?? .none

                let strengthDoseMinutes =
                    max(
                        item.strengthMinutes,
                        Double(item.completedSets) *
                            3.5
                    )
                let strengthRecoveryHours:
                    Double
                switch strengthDoseMinutes {
                case 0:
                    strengthRecoveryHours = 0
                case 0..<10:
                    strengthRecoveryHours = 8
                case 10..<30:
                    strengthRecoveryHours = 18
                case 30..<60:
                    strengthRecoveryHours = 30
                case 60..<90:
                    strengthRecoveryHours = 42
                default:
                    strengthRecoveryHours = 54
                }

                let movementMinutes =
                    item.runningMinutes +
                    item.walkingMinutes
                let movementRecoveryHours:
                    Double
                switch movementMinutes {
                case 0:
                    movementRecoveryHours = 0
                case 0..<15:
                    movementRecoveryHours = 8
                case 15..<35:
                    movementRecoveryHours = 16
                case 35..<75:
                    movementRecoveryHours = 28
                case 75..<140:
                    movementRecoveryHours = 40
                default:
                    movementRecoveryHours = 52
                }

                var baseRecoveryHours =
                    max(
                        strengthRecoveryHours,
                        movementRecoveryHours
                    )

                if baseRecoveryHours == 0 &&
                    sorenessLevel != .none {
                    baseRecoveryHours = 12
                }

                let sorenessAdjustment:
                    Double
                switch sorenessLevel {
                case .none:
                    sorenessAdjustment = 0
                case .mild:
                    sorenessAdjustment = 6
                case .moderate:
                    sorenessAdjustment = 12
                case .high:
                    sorenessAdjustment = 24
                }

                return MuscleRecoveryStatus(
                    muscleGroup: group,
                    lastTrainedAt:
                        item.lastTrainedAt,
                    completedSets:
                        item.completedSets,
                    strengthMinutes:
                        item.strengthMinutes,
                    runningMinutes:
                        item.runningMinutes,
                    walkingMinutes:
                        item.walkingMinutes,
                    estimatedRecoveryHours:
                        max(
                            baseRecoveryHours +
                                sorenessAdjustment,
                            1
                        ),
                    soreness:
                        sorenessLevel,
                    baselineWeeklyStrengthSets:
                        baselineWeeklyStrengthSets[
                            group
                        ],
                    baselineWeeklyStrengthMinutes:
                        baselineWeeklyStrengthMinutes[
                            group
                        ],
                    chronicWeeklyTrainingMinutes:
                        activityLoad
                            .chronicWeeklyAverageMinutes,
                    acuteToChronicRatio:
                        activityLoad.ratio
                )
            }
            .sorted { lhs, rhs in
                if lhs.currentLoadScore !=
                    rhs.currentLoadScore {
                    return lhs.currentLoadScore >
                        rhs.currentLoadScore
                }

                if lhs.soreness.rawValue !=
                    rhs.soreness.rawValue {
                    return lhs.soreness.rawValue >
                        rhs.soreness.rawValue
                }

                return lhs.readinessScore <
                    rhs.readinessScore
            }
    }

    static func unmappedExerciseNames(
        history: [StrengthWorkoutLog],
        days: Int = 7
    ) -> [String] {
        let cutoff =
            Date().addingTimeInterval(
                -Double(max(days, 1)) *
                    86_400
            )

        var names = Set<String>()

        for workout in history
        where workout.isFinished &&
            workout.startedAt >= cutoff {
            for exercise in workout.exercises {
                let completedSets =
                    exercise.sets
                        .filter(\.countsTowardTrainingLoad)
                        .count

                guard completedSets > 0 else {
                    continue
                }

                let mapped =
                    exercise.exercise
                        .primaryMuscles
                        .contains { muscle in
                            normalizedMuscleGroup(
                                muscle
                            ) != nil
                        }

                if !mapped {
                    names.insert(
                        exercise.exercise.name
                    )
                }
            }
        }

        return names.sorted {
            $0.localizedCaseInsensitiveCompare(
                $1
            ) == .orderedAscending
        }
    }

    private static func maxDate(
        _ lhs: Date?,
        _ rhs: Date?
    ) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private static func normalizedMuscleGroup(
        _ raw: String
    ) -> String? {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if value.contains("chest") ||
            value.contains("pectoral") {
            return "Chest"
        }

        if value.contains("lat") ||
            value.contains("back") ||
            value.contains("trap") {
            return "Back"
        }

        if value.contains("shoulder") ||
            value.contains("delt") {
            return "Shoulders"
        }

        if value.contains("bicep") ||
            value.contains("tricep") ||
            value.contains("forearm") ||
            value == "arms" {
            return "Arms"
        }

        if value.contains("ab") ||
            value.contains("core") ||
            value.contains("oblique") {
            return "Core"
        }

        if value.contains("glute") {
            return "Glutes"
        }

        if value.contains("quad") {
            return "Quads"
        }

        if value.contains("hamstring") {
            return "Hamstrings"
        }

        if value.contains("calf") ||
            value.contains("calves") {
            return "Calves"
        }

        return nil
    }
}

enum RecoveryTool: String, CaseIterable, Identifiable {
    case stretch
    case mobility
    case breathing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stretch: return recoveryText("Full-body reset", "Nullstill hele kroppen")
        case .mobility: return recoveryText("Mobility flow", "Mobilitetsflyt")
        case .breathing: return recoveryText("Downshift breathing", "Rolig pust")
        }
    }

    var subtitle: String {
        switch self {
        case .stretch: return recoveryText("8 min · gentle stretch", "8 min · rolig tøying")
        case .mobility: return recoveryText("10 min · hips, spine & shoulders", "10 min · hofter, rygg og skuldre")
        case .breathing: return recoveryText("5 min · calm breathing", "5 min · rolig pust")
        }
    }

    var icon: String {
        switch self {
        case .stretch: return "figure.flexibility"
        case .mobility: return "figure.cooldown"
        case .breathing: return "wind"
        }
    }

    var steps: [RecoveryToolStep] {
        switch self {
        case .stretch:
            return [
                .init(title: recoveryText("Cat-cow", "Katt-ku"), seconds: 60),
                .init(title: recoveryText("Hip flexor · left", "Hoftebøyer · venstre"), seconds: 60),
                .init(title: recoveryText("Hip flexor · right", "Hoftebøyer · høyre"), seconds: 60),
                .init(title: recoveryText("Hamstring fold", "Bakside lår"), seconds: 90),
                .init(title: recoveryText("Chest opener", "Bryståpner"), seconds: 60),
                .init(title: recoveryText("Child’s pose", "Barnets posisjon"), seconds: 90),
                .init(title: recoveryText("Easy reset", "Rolig avslutning"), seconds: 60)
            ]

        case .mobility:
            return [
                .init(title: recoveryText("Ankle rocks", "Ankelmobilitet"), seconds: 75),
                .init(title: recoveryText("90/90 hips", "90/90 hofter"), seconds: 90),
                .init(title: recoveryText("World’s greatest stretch", "Dynamisk helkroppsstrekk"), seconds: 120),
                .init(title: recoveryText("Thoracic rotations", "Rotasjon i brystrygg"), seconds: 90),
                .init(title: recoveryText("Shoulder circles", "Skuldersirkler"), seconds: 75),
                .init(title: recoveryText("Deep squat hold", "Dyp knebøy-hold"), seconds: 90),
                .init(title: recoveryText("Easy reset", "Rolig avslutning"), seconds: 60)
            ]

        case .breathing:
            return [
                .init(
                    title: "Inhale 4 sec · exhale 6 sec",
                    seconds: 300
                )
            ]
        }
    }
}

struct RecoveryToolStep: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let seconds: Int
}

struct RecoveryReadinessBreakdownCard: View {
    let recovery: RecoveryReadinessSummary
    let sleep: SleepSummary
    let heart: HeartSummary

    var body: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: recoveryText("Why this score", "Hvorfor denne scoren"),
                actionTitle: recoveryText("Today", "I dag")
            )

            VStack(spacing: 12) {
                factorRow(
                    title: recoveryText("Sleep", "Søvn"),
                    icon: "moon.fill",
                    weight: "45%",
                    value: sleepValue,
                    score: sleepFactor
                )

                factorRow(
                    title: "HRV",
                    icon: "waveform.path.ecg",
                    weight: "35%",
                    value: hrvValue,
                    score: hrvFactor
                )

                factorRow(
                    title: recoveryText("Resting HR", "Hvilepuls"),
                    icon: "heart.fill",
                    weight: "20%",
                    value: restingHRValue,
                    score: restingFactor
                )
            }
            .padding(.top, 12)

            Text(
                recoveryText("Each factor is compared with your own recent baseline. The weights above are the same ones used for the readiness score shown on Home.", "Hver faktor sammenlignes med din egen nyere grunnlinje. Vektingen er den samme som brukes for dagsformscoren på Home.")
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
    }

    private func factorRow(
        title: String,
        icon: String,
        weight: String,
        value: String,
        score: Double?
    ) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(weight)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.mutedText)

                Text(factorLabel(score))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        factorTint(score)
                    )
                    .frame(width: 68, alignment: .trailing)
            }

            ProgressView(value: score ?? 0)
                .tint(factorTint(score))
        }
    }

    private var sleepFactor: Double? {
        guard sleep.totalAsleep > 0,
              let baseline = recovery.averageSleepDuration,
              baseline > 0 else {
            return nil
        }

        let reference = max(baseline, 7.5 * 3_600)
        return min(max(sleep.totalAsleep / reference, 0.45), 1)
    }

    private var hrvFactor: Double? {
        guard let current = heart.hrvMilliseconds,
              let baseline = recovery.baselineHRVMilliseconds,
              baseline > 0 else {
            return nil
        }

        return min(max(current / baseline, 0.55), 1)
    }

    private var restingFactor: Double? {
        guard let current = heart.restingHeartRate,
              current > 0,
              let baseline = recovery.baselineRestingHeartRate,
              baseline > 0 else {
            return nil
        }

        return min(max(baseline / current, 0.60), 1)
    }

    private var sleepValue: String {
        guard sleep.totalAsleep > 0 else { return recoveryText("No data", "Ingen data") }

        if let baseline = recovery.averageSleepDuration {
            return "\(sleep.totalAsleep.shortDuration) · \(comparison(current: sleep.totalAsleep, baseline: baseline, higherIsBetter: true))"
        }

        return sleep.totalAsleep.shortDuration
    }

    private var hrvValue: String {
        guard let current = heart.hrvMilliseconds else {
            return recoveryText("No data", "Ingen data")
        }

        if let baseline = recovery.baselineHRVMilliseconds {
            return "\(Int(current.rounded())) ms · \(comparison(current: current, baseline: baseline, higherIsBetter: true))"
        }

        return "\(Int(current.rounded())) ms"
    }

    private var restingHRValue: String {
        guard let current = heart.restingHeartRate else {
            return recoveryText("No data", "Ingen data")
        }

        if let baseline = recovery.baselineRestingHeartRate {
            return "\(Int(current.rounded())) bpm · \(comparison(current: current, baseline: baseline, higherIsBetter: false))"
        }

        return "\(Int(current.rounded())) bpm"
    }

    private func comparison(
        current: Double,
        baseline: Double,
        higherIsBetter: Bool
    ) -> String {
        guard baseline > 0 else { return recoveryText("No baseline", "Ingen grunnlinje") }

        let percent = ((current - baseline) / baseline) * 100
        let rounded = Int(abs(percent).rounded())

        guard rounded >= 2 else {
            return recoveryText("near baseline", "nær grunnlinjen")
        }

        let favorable =
            higherIsBetter ? percent > 0 : percent < 0

        return favorable
            ? "\(rounded)% favorable"
            : "\(rounded)% below target"
    }

    private func factorLabel(
        _ score: Double?
    ) -> String {
        guard let score else { return recoveryText("Learning", "Lærer") }

        switch score {
        case 0.90...: return recoveryText("Strong", "Sterk")
        case 0.75..<0.90: return recoveryText("Good", "God")
        case 0.60..<0.75: return recoveryText("Low", "Lav")
        default: return recoveryText("Limited", "Begrenset")
        }
    }

    private func factorTint(
        _ score: Double?
    ) -> Color {
        guard let score else {
            return ATHLTHTheme.mutedText
        }

        switch score {
        case 0.90...: return .green
        case 0.75..<0.90: return ATHLTHTheme.accent
        case 0.60..<0.75: return .orange
        default: return .red
        }
    }
}

struct RecoveryTrendsCard: View {
    let snapshot: RecoveryTrendSnapshot
    let sleep: SleepSummary

    var body: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: recoveryText("Recent signals", "Nylige signaler"),
                actionTitle: recoveryText("14 days", "14 dager")
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                trendTile(
                    title: recoveryText("Sleep", "Søvn"),
                    value: sleepTrendValue,
                    subtitle: sleepQualityText,
                    icon: "moon.fill",
                    metric: .sleep
                )

                trendTile(
                    title: "HRV",
                    value: latestHRVText,
                    subtitle: recoveryText("Nightly / daily signal", "Nattlig / daglig signal"),
                    icon: "waveform.path.ecg",
                    metric: .hrv
                )

                trendTile(
                    title: recoveryText("Resting HR", "Hvilepuls"),
                    value: latestRestingHRText,
                    subtitle: recoveryText("Lower vs baseline can be favorable", "Lavere enn grunnlinjen kan være positivt"),
                    icon: "heart.fill",
                    metric: .restingHR
                )

                trendTile(
                    title: recoveryText("Training load", "Treningsbelastning"),
                    value: acuteLoadText,
                    subtitle: loadSubtitle,
                    icon: "chart.line.uptrend.xyaxis",
                    metric: .training
                )
            }
            .padding(.top, 12)
        }
    }

    private enum Metric {
        case sleep
        case hrv
        case restingHR
        case training
    }

    private func trendTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        metric: Metric
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)

                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer()
            }

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Chart(snapshot.days) { day in
                if let value = chartValue(
                    for: day,
                    metric: metric
                ) {
                    LineMark(
                        x: .value(recoveryText("Day", "Dag"), day.date),
                        y: .value(recoveryText("Value", "Verdi"), value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(ATHLTHTheme.accent)

                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 52)

            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func chartValue(
        for day: RecoveryTrendDay,
        metric: Metric
    ) -> Double? {
        switch metric {
        case .sleep:
            return day.sleepDuration.map { $0 / 3_600 }
        case .hrv:
            return day.hrvMilliseconds
        case .restingHR:
            return day.restingHeartRate
        case .training:
            return day.trainingMinutes
        }
    }

    private var sleepTrendValue: String {
        guard sleep.totalAsleep > 0 else { return "—" }
        return sleep.totalAsleep.shortDuration
    }

    private var sleepQualityText: String {
        guard sleep.totalAsleep > 0 else {
            return recoveryText("Sleep quality unavailable", "Søvnkvalitet ikke tilgjengelig")
        }

        let durationHours = sleep.totalAsleep / 3_600
        let stageTotal = sleep.core + sleep.deep + sleep.rem
        let restorativeRatio = stageTotal > 0
            ? (sleep.deep + sleep.rem) / stageTotal
            : nil
        let awakeRatio =
            (sleep.totalAsleep + sleep.awake) > 0
                ? sleep.awake / (sleep.totalAsleep + sleep.awake)
                : 0

        let quality: String

        if durationHours >= 7,
           durationHours <= 9.5,
           restorativeRatio.map({ $0 >= 0.25 }) ?? true,
           awakeRatio < 0.18 {
            quality = recoveryText("Good quality", "God kvalitet")
        } else if durationHours >= 6,
                  awakeRatio < 0.25 {
            quality = recoveryText("Fair quality", "Middels kvalitet")
        } else {
            quality = recoveryText("Low quality", "Lav kvalitet")
        }

        return ATHLTHLocalization.choose(
                        english:
                            ATHLTHLocalization.choose(
                            english:
                                "\(quality) · duration + available stages",
                            norwegian:
                                "\(quality) · varighet + tilgjengelige søvnstadier"
                        ),
                        norwegian:
                            "\(quality) · varighet + tilgjengelige søvnstadier"
                    )
    }

    private var latestHRVText: String {
        guard let value = snapshot.days
            .reversed()
            .compactMap(\.hrvMilliseconds)
            .first else {
            return "—"
        }

        return "\(Int(value.rounded())) ms"
    }

    private var latestRestingHRText: String {
        guard let value = snapshot.days
            .reversed()
            .compactMap(\.restingHeartRate)
            .first else {
            return "—"
        }

        return "\(Int(value.rounded())) bpm"
    }

    private var acuteLoadText: String {
        let minutes = Int(
            snapshot.trainingLoad.acuteMinutes.rounded()
        )
        return ATHLTHLocalization.choose(english: "\(minutes) min / 7d", norwegian: "\(minutes) min / 7 d")
    }

    private var loadSubtitle: String {
        let load = snapshot.trainingLoad

        guard let chronic = load.chronicWeeklyAverageMinutes else {
            return load.title
        }

        return ATHLTHLocalization.choose(english: "\(load.title) · 28d avg \(Int(chronic.rounded())) min/week", norwegian: "\(load.title) · 28 d snitt \(Int(chronic.rounded())) min/uke")
    }
}

struct RecoveryLastNightCard: View {
    let sleep: SleepSummary

    var body: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: recoveryText("Last night", "I natt"),
                actionTitle: nightLabel
            )

            HStack(alignment: .firstTextBaseline) {
                Text(sleep.totalAsleep.shortDuration)
                    .font(
                        .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    recoveryText(
                        "asleep",
                        "sovet"
                    )
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let start = sleep.sleepStart,
                   let end = sleep.sleepEnd {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(
                            "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(recoveryText("Bed → wake", "Seng → våken"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 12)

            HStack(spacing: 8) {
                stageTile(
                    recoveryText("Deep", "Dyp"),
                    value: sleep.deep,
                    icon: "moon.zzz.fill"
                )
                stageTile(
                    "REM",
                    value: sleep.rem,
                    icon: "brain.head.profile"
                )
                stageTile(
                    recoveryText(
                        "Core",
                        "Kjerne"
                    ),
                    value: sleep.core,
                    icon: "moon.fill"
                )
                stageTile(
                    recoveryText("Awake", "Våken"),
                    value: sleep.awake,
                    icon: "eye.fill"
                )
            }
            .padding(.top, 12)

            Text(sleepQualityText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
    }

    private func stageTile(
        _ title: String,
        value: TimeInterval,
        icon: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)

            Text(value > 0 ? value.shortDuration : "—")
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var nightLabel: String? {
        guard let end = sleep.sleepEnd else {
            return nil
        }

        if Calendar.current.isDateInToday(end) {
            return recoveryText("Today", "I dag")
        }

        return end.formatted(
            .dateTime.weekday(.abbreviated)
        )
    }

    private var sleepQualityText: String {
        let durationHours = sleep.totalAsleep / 3_600
        let stageTotal = sleep.core + sleep.deep + sleep.rem
        let restorativeRatio = stageTotal > 0
            ? (sleep.deep + sleep.rem) / stageTotal
            : nil
        let awakeRatio =
            (sleep.totalAsleep + sleep.awake) > 0
                ? sleep.awake /
                    (sleep.totalAsleep + sleep.awake)
                : 0

        if durationHours >= 7,
           durationHours <= 9.5,
           restorativeRatio.map({ $0 >= 0.25 }) ?? true,
           awakeRatio < 0.18 {
            return recoveryText("Good sleep quality from duration and available sleep stages.", "God søvnkvalitet basert på varighet og tilgjengelige søvnstadier.")
        }

        if durationHours >= 6,
           awakeRatio < 0.25 {
            return recoveryText("Fair sleep quality. Recovery also considers HRV and resting heart rate.", "Middels søvnkvalitet. Restitusjon vurderer også HRV og hvilepuls.")
        }

        return recoveryText("Sleep was below your usual recovery-friendly range.", "Søvnen var under ditt vanlige restitusjonsvennlige nivå.")
    }
}

struct RecoveryDailyCheckInCard: View {
    @ObservedObject var store: RecoverySorenessStore
    let onCheckIn: () -> Void

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recoveryText("Daily check-in", "Daglig innsjekk"))
                        .font(.title3.weight(.bold))

                    Text(
                        recoveryText("How you feel can refine today's guidance without changing your wearable score.", "Hvordan du føler deg kan forbedre dagens anbefaling uten å endre scoren fra klokken.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(
                    store.hasTodayCheckIn
                        ? recoveryText("Update", "Oppdater")
                        : recoveryText("Check in", "Sjekk inn")
                ) {
                    onCheckIn()
                }
                .font(.caption.weight(.semibold))
            }

            if store.hasTodayCheckIn {
                HStack(spacing: 8) {
                    checkInMetric(
                        title: recoveryText("Energy", "Energi"),
                        value: store.todayEnergy,
                        icon: "bolt.fill",
                        inverted: false
                    )
                    checkInMetric(
                        title: recoveryText("Stress", "Stress"),
                        value: store.todayStress,
                        icon: "waveform.path.ecg",
                        inverted: true
                    )
                    checkInMetric(
                        title: recoveryText("Soreness", "Ømhet"),
                        value: store.todayOverallSoreness,
                        icon: "figure.walk.motion",
                        inverted: true
                    )
                    checkInMetric(
                        title: recoveryText("Motivation", "Motivasjon"),
                        value: store.todayMotivation,
                        icon: "flame.fill",
                        inverted: false
                    )
                }
                .padding(.top, 12)
            } else {
                Button {
                    onCheckIn()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "list.clipboard.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 12
                                )
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(recoveryText("Add today's context", "Legg til dagens status"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                            Text(
                                recoveryText("Energy, stress, soreness and motivation.", "Energi, stress, ømhet og motivasjon.")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func checkInMetric(
        title: String,
        value: Int?,
        icon: String,
        inverted: Bool
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)

            Text(value.map { "\($0)/5" } ?? "—")
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(
                cornerRadius: 13,
                style: .continuous
            )
        )
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english:
                    "\(title), \(value.map(String.init) ?? "not logged") out of 5",
                norwegian:
                    "\(title), \(value.map(String.init) ?? "ikke registrert") av 5"
            )
        )
    }
}

struct MuscleRecoveryCard: View {
    let statuses: [MuscleRecoveryStatus]
    var unmappedExerciseNames: [String] = []
    var trendDays: [RecoveryTrendDay] = []
    let onLogSoreness: () -> Void

    private var forest: Color {
        Color(
            red: 0.025,
            green: 0.30,
            blue: 0.21
        )
    }

    private var emerald: Color {
        Color(
            red: 0.13,
            green: 0.67,
            blue: 0.33
        )
    }

    private var mint: Color {
        Color(
            red: 0.91,
            green: 0.97,
            blue: 0.92
        )
    }

    private var amber: Color {
        Color(
            red: 0.95,
            green: 0.67,
            blue: 0.08
        )
    }

    private var coral: Color {
        Color(
            red: 0.93,
            green: 0.34,
            blue: 0.28
        )
    }

    var body: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                header

                if statuses.isEmpty {
                    emptyState
                } else {
                    heroRecoveryPanel
                    readinessLegend
                    muscleGroupPanel
                    loadTrendPanel
                    assessmentPanel

                    if !unmappedExerciseNames
                        .isEmpty {
                        missingMappingWarning
                    }

                    HStack {
                        Text(
                            recoveryText(
                                "Estimated from recorded training and soreness data.",
                                "Estimert fra registrert trening og ømhetsdata."
                            )
                        )
                        .font(
                            .system(
                                size: 8.5,
                                weight: .regular
                            )
                        )
                        .foregroundStyle(
                            .tertiary
                        )

                        Spacer()

                        Button {
                            onLogSoreness()
                        } label: {
                            Label(
                                recoveryText(
                                    "Check in",
                                    "Sjekk inn"
                                ),
                                systemImage:
                                    "plus.circle.fill"
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight:
                                        .semibold
                                )
                            )
                            .foregroundStyle(
                                forest
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var header:
        some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            Image(
                systemName:
                    "waveform.path.ecg"
            )
            .font(
                .system(
                    size: 18,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                emerald
            )
            .frame(
                width: 42,
                height: 42
            )
            .background(
                mint,
                in:
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    recoveryText(
                        "Muscle recovery",
                        "Muskelrestitusjon"
                    )
                )
                .font(
                    .title3
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

                Text(
                    recoveryText(
                        "See how ready your muscle groups are for new load.",
                        "Se hvor restituerte muskelgruppene dine er."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer(
                minLength: 4
            )

            HStack(spacing: 5) {
                Image(
                    systemName:
                        "clock.fill"
                )
                .font(
                    .system(
                        size: 9,
                        weight:
                            .semibold
                    )
                )

                Text(
                    recoveryText(
                        "Updated today",
                        "Oppdatert i dag"
                    )
                )
                .lineLimit(1)
            }
            .font(
                .system(
                    size: 9,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                forest
            )
            .padding(
                .horizontal,
                8
            )
            .frame(height: 28)
            .background(
                mint,
                in: Capsule()
            )
        }
    }

    private var heroRecoveryPanel:
        some View {
        HStack(
            alignment: .center,
            spacing: 8
        ) {
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            overallTint
                        )
                        .frame(
                            width: 7,
                            height: 7
                        )

                    Text(
                        recoveryText(
                            "TOTAL STATUS",
                            "TOTAL STATUS"
                        )
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .tracking(1.1)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Text(
                    overallTitle
                )
                .font(
                    .system(
                        size: 24,
                        weight: .bold,
                        design: .serif
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .minimumScaleFactor(
                    0.78
                )

                Text(
                    overallDetail
                )
                .font(
                    .system(
                        size: 10.5
                    )
                )
                .foregroundStyle(
                    .secondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                readinessRing
                    .frame(
                        width: 88,
                        height: 88
                    )
                    .padding(.top, 2)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            StrengthMuscleMapView(
                profile:
                    muscleMapProfile,
                compact: true,
                style:
                    .recoveryLoad,
                presentation:
                    .insight
            )
            .frame(height: 205)
            .frame(
                maxWidth: 176
            )
            .padding(
                .vertical,
                6
            )
        }
        .padding(13)
        .background(
            LinearGradient(
                colors: [
                    mint.opacity(
                        0.86
                    ),
                    Color.white
                        .opacity(0.90)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                emerald.opacity(
                    0.12
                ),
                lineWidth: 0.8
            )
        }
    }

    private var readinessRing:
        some View {
        ZStack {
            Circle()
                .stroke(
                    Color.black
                        .opacity(0.07),
                    lineWidth: 9
                )

            Circle()
                .trim(
                    from: 0,
                    to:
                        overallReadiness /
                        100
                )
                .stroke(
                    overallTint,
                    style:
                        StrokeStyle(
                            lineWidth: 9,
                            lineCap: .round
                        )
                )
                .rotationEffect(
                    .degrees(-90)
                )

            VStack(spacing: 0) {
                Text(
                    "\(Int(overallReadiness.rounded()))%"
                )
                .font(
                    .title3
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .contentTransition(
                    .numericText()
                )

                Text(
                    recoveryText(
                        "READY",
                        "KLAR"
                    )
                )
                .font(
                    .system(
                        size: 7.5,
                        weight: .bold
                    )
                )
                .tracking(0.7)
                .foregroundStyle(
                    .secondary
                )
            }
        }
    }

    private var readinessLegend:
        some View {
        HStack(spacing: 6) {
            legendItem(
                title:
                    recoveryText(
                        "Ready",
                        "Klar"
                    ),
                detail: "70–100%",
                tint: emerald
            )

            legendItem(
                title:
                    recoveryText(
                        "Moderate",
                        "Moderat"
                    ),
                detail: "40–69%",
                tint: amber
            )

            legendItem(
                title:
                    recoveryText(
                        "Needs rest",
                        "Trenger hvile"
                    ),
                detail: "0–39%",
                tint: coral
            )
        }
        .padding(9)
        .background(
            Color.white
                .opacity(0.66),
            in:
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
            .stroke(
                Color.black
                    .opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private func legendItem(
        title: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(
                    width: 8,
                    height: 8
                )

            VStack(
                alignment: .leading,
                spacing: 0
            ) {
                Text(title)
                    .font(
                        .system(
                            size: 8.5,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                Text(detail)
                    .font(
                        .system(
                            size: 7.5
                        )
                    )
                    .foregroundStyle(
                        .secondary
                    )
            }

            Spacer(
                minLength: 0
            )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private var muscleGroupPanel:
        some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text(
                recoveryText(
                    "MUSCLE GROUPS",
                    "MUSKELGRUPPER"
                )
            )
            .font(
                .system(
                    size: 9.5,
                    weight: .bold
                )
            )
            .tracking(0.8)
            .foregroundStyle(
                .secondary
            )

            ForEach(
                displayedStatuses
            ) { status in
                compactMuscleRow(
                    status
                )
            }
        }
        .padding(12)
        .background(
            Color.primary
                .opacity(0.022),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
    }

    private func compactMuscleRow(
        _ status:
            MuscleRecoveryStatus
    ) -> some View {
        let percent =
            Int(
                (
                    status
                        .readinessScore *
                    100
                )
                .rounded()
            )
        let tint =
            readinessTint(
                status
                    .readinessScore
            )

        return HStack(
            spacing: 9
        ) {
            Image(
                systemName:
                    muscleIcon(
                        status
                            .muscleGroup
                    )
            )
            .font(
                .system(
                    size: 12,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                tint
            )
            .frame(
                width: 30,
                height: 30
            )
            .background(
                tint.opacity(
                    0.09
                ),
                in: Circle()
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                HStack {
                    Text(
                        recoveryMuscleName(
                            status
                                .muscleGroup
                        )
                    )
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                    Spacer()

                    Text(
                        "\(percent)%"
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .monospacedDigit()
                }

                GeometryReader {
                    proxy in

                    ZStack(
                        alignment: .leading
                    ) {
                        Capsule()
                            .fill(
                                Color.black
                                    .opacity(
                                        0.06
                                    )
                            )

                        Capsule()
                            .fill(tint)
                            .frame(
                                width:
                                    max(
                                        3,
                                        proxy
                                            .size
                                            .width *
                                        status
                                            .readinessScore
                                    )
                            )
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(
            children: .combine
        )
    }

    private var loadTrendPanel:
        some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Image(
                    systemName:
                        "chart.line.uptrend.xyaxis"
                )
                .font(
                    .system(
                        size: 11,
                        weight:
                            .semibold
                    )
                )
                .foregroundStyle(
                    forest
                )

                Text(
                    recoveryText(
                        "LOAD · LAST 7 DAYS",
                        "BELASTNING · SISTE 7 DAGER"
                    )
                )
                .font(
                    .system(
                        size: 9.5,
                        weight: .bold
                    )
                )
                .tracking(0.65)
                .foregroundStyle(
                    .secondary
                )

                Spacer()

                if let total =
                    sevenDayTrainingMinutes {
                    Text(
                        "\(Int(total.rounded())) min"
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        forest
                    )
                }
            }

            if recentTrendDays
                .isEmpty {
                Text(
                    recoveryText(
                        "Training-load history will appear here when recent data is available.",
                        "Belastningshistorikk vises her når det finnes nok data."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 54,
                    alignment: .leading
                )
            } else {
                Chart(
                    recentTrendDays
                ) { day in
                    LineMark(
                        x: .value(
                            recoveryText(
                                "Day",
                                "Dag"
                            ),
                            day.date
                        ),
                        y: .value(
                            recoveryText(
                                "Minutes",
                                "Minutter"
                            ),
                            day.trainingMinutes
                        )
                    )
                    .interpolationMethod(
                        .catmullRom
                    )
                    .foregroundStyle(
                        forest
                    )

                    AreaMark(
                        x: .value(
                            recoveryText(
                                "Day",
                                "Dag"
                            ),
                            day.date
                        ),
                        y: .value(
                            recoveryText(
                                "Minutes",
                                "Minutter"
                            ),
                            day.trainingMinutes
                        )
                    )
                    .interpolationMethod(
                        .catmullRom
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                emerald
                                    .opacity(
                                        0.24
                                    ),
                                emerald
                                    .opacity(
                                        0.02
                                    )
                            ],
                            startPoint:
                                .top,
                            endPoint:
                                .bottom
                        )
                    )

                }
                .chartXAxis {
                    AxisMarks(
                        values:
                            .stride(
                                by: .day
                            )
                    ) {
                        value in

                        AxisValueLabel(
                            format:
                                .dateTime
                                    .weekday(
                                        .narrow
                                    )
                        )
                        .font(
                            .system(
                                size: 8
                            )
                        )
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 92)
            }
        }
        .padding(12)
        .background(
            Color.white
                .opacity(0.70),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black
                    .opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private var assessmentPanel:
        some View {
        HStack(
            alignment: .top,
            spacing: 11
        ) {
            Image(
                systemName:
                    "sparkles"
            )
            .font(
                .system(
                    size: 14,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                forest
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                mint,
                in:
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    recoveryText(
                        "Today's assessment",
                        "Dagens vurdering"
                    )
                )
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

                Text(
                    assessmentTitle
                )
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                Text(
                    assessmentDetail
                )
                .font(
                    .system(
                        size: 9.5
                    )
                )
                .foregroundStyle(
                    .secondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer(
                minLength: 0
            )
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    mint.opacity(
                        0.74
                    ),
                    Color.white
                        .opacity(0.82)
                ],
                startPoint:
                    .leading,
                endPoint:
                    .trailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
    }

    private var emptyState:
        some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    "figure.strengthtraining.traditional"
            )
            .font(
                .title3
            )
            .foregroundStyle(
                forest
            )
            .frame(
                width: 44,
                height: 44
            )
            .background(
                mint,
                in:
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    recoveryText(
                        "No muscle-recovery data yet",
                        "Ingen muskeldata ennå"
                    )
                )
                .font(
                    .subheadline
                        .weight(
                            .semibold
                        )
                )

                Text(
                    recoveryText(
                        "Complete a tracked strength workout, run or walk and ATHLTH will build your muscle-recovery view here.",
                        "Fullfør en registrert styrkeøkt, løpetur eller gåtur, så bygger ATHLTH muskelrestitusjonen her."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var missingMappingWarning:
        some View {
        HStack(
            alignment: .top,
            spacing: 8
        ) {
            Image(
                systemName:
                    "exclamationmark.triangle.fill"
            )
            .font(
                .system(
                    size: 10
                )
            )
            .foregroundStyle(
                .orange
            )
            .padding(.top, 1)

            Text(
                missingMuscleGroupWarning
            )
            .font(
                .system(
                    size: 8.5
                )
            )
            .foregroundStyle(
                .secondary
            )
            .fixedSize(
                horizontal: false,
                vertical: true
            )

            Spacer()
        }
    }

    private var displayedStatuses:
        [MuscleRecoveryStatus] {
        Array(
            statuses
                .sorted {
                    muscleSortIndex(
                        $0.muscleGroup
                    ) <
                    muscleSortIndex(
                        $1.muscleGroup
                    )
                }
                .prefix(7)
        )
    }

    private var overallReadiness:
        Double {
        guard !statuses.isEmpty
        else {
            return 100
        }

        return (
            statuses.reduce(0) {
                $0 +
                $1.readinessScore
            } /
            Double(
                statuses.count
            )
        ) * 100
    }

    private var overallTint:
        Color {
        readinessTint(
            overallReadiness /
                100
        )
    }

    private var overallTitle:
        String {
        switch overallReadiness {
        case 70...:
            return recoveryText(
                "Ready for strength",
                "Klar for styrke"
            )
        case 40..<70:
            return recoveryText(
                "Train with care",
                "Tren med omtanke"
            )
        default:
            return recoveryText(
                "Prioritize recovery",
                "Prioriter restitusjon"
            )
        }
    }

    private var overallDetail:
        String {
        switch overallReadiness {
        case 70...:
            return recoveryText(
                "Most muscle groups are recovered and ready for new load.",
                "De fleste muskelgruppene er restituert og klare for ny belastning."
            )
        case 40..<70:
            return recoveryText(
                "Some areas still need recovery. Adjust volume or muscle focus.",
                "Noen områder trenger fortsatt restitusjon. Juster volum eller muskelfokus."
            )
        default:
            return recoveryText(
                "Several muscle groups still carry meaningful recent load.",
                "Flere muskelgrupper har fortsatt tydelig belastning fra nylig trening."
            )
        }
    }

    private var assessmentTitle:
        String {
        let lowest =
            statuses
                .sorted {
                    $0.readinessScore <
                    $1.readinessScore
                }

        guard let first =
                lowest.first
        else {
            return recoveryText(
                "Build your recovery baseline.",
                "Bygg opp restitusjonsgrunnlaget ditt."
            )
        }

        let firstName =
            recoveryMuscleName(
                first.muscleGroup
            )
                .lowercased()

        if first.readinessScore >=
            0.70 {
            return recoveryText(
                "Your tracked muscle groups look ready today.",
                "De registrerte muskelgruppene ser klare ut i dag."
            )
        }

        if lowest.count > 1,
           lowest[1]
                .readinessScore <
                0.70 {
            let secondName =
                recoveryMuscleName(
                    lowest[1]
                        .muscleGroup
                )
                    .lowercased()

            return recoveryText(
                "\(firstName.capitalized) and \(secondName) need more recovery.",
                "\(firstName.capitalized) og \(secondName) trenger mer hvile."
            )
        }

        return recoveryText(
            "\(firstName.capitalized) needs more recovery.",
            "\(firstName.capitalized) trenger mer hvile."
        )
    }

    private var assessmentDetail:
        String {
        switch overallReadiness {
        case 70...:
            return recoveryText(
                "Your current muscle-load profile supports normal training. Keep the planned intensity sensible.",
                "Dagens muskelprofil støtter normal trening. Hold den planlagte intensiteten fornuftig."
            )
        case 40..<70:
            return recoveryText(
                "Consider shifting focus toward the greener muscle groups or reducing volume in fatigued areas.",
                "Vurder å flytte fokuset mot de grønnere muskelgruppene eller redusere volumet i slitne områder."
            )
        default:
            return recoveryText(
                "A lighter session, mobility work or extra recovery may fit better today.",
                "En lettere økt, mobilitet eller ekstra restitusjon kan passe bedre i dag."
            )
        }
    }

    private var recentTrendDays:
        [RecoveryTrendDay] {
        Array(
            trendDays
                .sorted {
                    $0.date <
                    $1.date
                }
                .suffix(7)
        )
    }

    private var sevenDayTrainingMinutes:
        Double? {
        guard !recentTrendDays
            .isEmpty
        else {
            return nil
        }

        return recentTrendDays
            .reduce(0) {
                $0 +
                $1.trainingMinutes
            }
    }

    private var missingMuscleGroupWarning:
        String {
        let visibleNames =
            unmappedExerciseNames
                .prefix(3)
                .joined(separator: ", ")
        let remaining =
            max(
                unmappedExerciseNames.count -
                3,
                0
            )
        let suffix =
            remaining > 0
                ? " +\(remaining)"
                : ""

        if unmappedExerciseNames.count ==
            1 {
            return recoveryText(
                "1 trained exercise is missing a muscle group and is not included in the muscle map: \(visibleNames).",
                "1 trent øvelse mangler muskelgruppe og er ikke med i muskelkartet: \(visibleNames)."
            )
        }

        return recoveryText(
            "\(unmappedExerciseNames.count) trained exercises are missing a muscle group and are not included in the muscle map: \(visibleNames)\(suffix).",
            "\(unmappedExerciseNames.count) trente øvelser mangler muskelgruppe og er ikke med i muskelkartet: \(visibleNames)\(suffix)."
        )
    }

    private var muscleMapProfile:
        StrengthMuscleProfile {
        var scores:
            [StrengthMuscleRegion: Double] =
                [:]

        for status in statuses {
            for region in muscleRegions(
                for:
                    status
                        .muscleGroup
            ) {
                scores[region] =
                    max(
                        scores[region] ??
                        0,
                        status
                            .currentLoadScore
                    )
            }
        }

        return StrengthMuscleProfile(
            activations:
                scores.map {
                    StrengthMuscleActivation(
                        region: $0.key,
                        score: $0.value
                    )
                }
        )
    }

    private func muscleRegions(
        for group: String
    ) -> [StrengthMuscleRegion] {
        let normalized =
            group.lowercased()

        if normalized.contains(
            "chest"
        ) {
            return [.chest]
        }
        if normalized.contains(
            "back"
        ) {
            return [
                .lats,
                .upperBack,
                .lowerBack
            ]
        }
        if normalized.contains(
            "shoulder"
        ) {
            return [
                .frontDelts,
                .sideDelts,
                .rearDelts
            ]
        }
        if normalized.contains(
            "arm"
        ) {
            return [
                .biceps,
                .triceps,
                .forearms
            ]
        }
        if normalized.contains(
            "core"
        ) ||
            normalized.contains(
                "ab"
            ) {
            return [
                .abs,
                .obliques
            ]
        }
        if normalized.contains(
            "glute"
        ) {
            return [
                .glutes,
                .outerHip
            ]
        }
        if normalized.contains(
            "quad"
        ) {
            return [.quads]
        }
        if normalized.contains(
            "hamstring"
        ) {
            return [.hamstrings]
        }
        if normalized.contains(
            "calf"
        ) ||
            normalized.contains(
                "calves"
            ) {
            return [.calves]
        }

        return []
    }

    private func readinessTint(
        _ readiness: Double
    ) -> Color {
        switch readiness {
        case 0.70...:
            return emerald
        case 0.40..<0.70:
            return amber
        default:
            return coral
        }
    }

    private func muscleSortIndex(
        _ group: String
    ) -> Int {
        let normalized =
            group.lowercased()

        if normalized.contains(
            "shoulder"
        ) {
            return 0
        }
        if normalized.contains(
            "chest"
        ) {
            return 1
        }
        if normalized.contains(
            "back"
        ) {
            return 2
        }
        if normalized.contains(
            "core"
        ) {
            return 3
        }
        if normalized.contains(
            "arm"
        ) {
            return 4
        }
        if normalized.contains(
            "quad"
        ) {
            return 5
        }
        if normalized.contains(
            "hamstring"
        ) {
            return 6
        }
        if normalized.contains(
            "glute"
        ) {
            return 7
        }
        if normalized.contains(
            "calf"
        ) {
            return 8
        }

        return 99
    }

    private func muscleIcon(
        _ group: String
    ) -> String {
        let normalized =
            group.lowercased()

        if normalized.contains(
            "shoulder"
        ) {
            return "figure.strengthtraining.traditional"
        }
        if normalized.contains(
            "chest"
        ) {
            return "figure.strengthtraining.traditional"
        }
        if normalized.contains(
            "back"
        ) {
            return "figure.strengthtraining.traditional"
        }
        if normalized.contains(
            "core"
        ) {
            return "figure.strengthtraining.traditional"
        }
        if normalized.contains(
            "arm"
        ) {
            return "dumbbell.fill"
        }
        if normalized.contains(
            "quad"
        ) ||
            normalized.contains(
                "hamstring"
            ) ||
            normalized.contains(
                "glute"
            ) {
            return "figure.walk"
        }
        if normalized.contains(
            "calf"
        ) {
            return "figure.run"
        }

        return "figure.strengthtraining.traditional"
    }
}

struct RecoveryToolsCard: View {
    let onSelect: (RecoveryTool) -> Void

    var body: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: recoveryText("Recovery tools", "Restitusjonsverktøy"),
                actionTitle: recoveryText("Do something now", "Gjør noe nå")
            )

            VStack(spacing: 9) {
                ForEach(RecoveryTool.allCases) { tool in
                    Button {
                        onSelect(tool)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(tool.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.accent)
                        }
                        .padding(11)
                        .background(
                            Color.primary.opacity(0.025),
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
        }
    }
}

struct RecoverySorenessLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: RecoverySorenessStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        recoveryText("Your check-in can influence Today's Guidance and muscle-recovery suggestions. It never changes the wearable Readiness score.", "Innsjekken kan påvirke dagens anbefaling og forslag til muskelrestitusjon. Den endrer aldri dagsformscoren fra klokken.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section(recoveryText("How you feel", "Hvordan du føler deg")) {
                    checkInScale(
                        title: recoveryText("Energy", "Energi"),
                        subtitle: recoveryText("Low → high", "Lav → høy"),
                        icon: "bolt.fill",
                        value: store.todayEnergy,
                        onSelect: store.setEnergy
                    )

                    checkInScale(
                        title: recoveryText("Stress", "Stress"),
                        subtitle: recoveryText("Low → high", "Lav → høy"),
                        icon: "waveform.path.ecg",
                        value: store.todayStress,
                        onSelect: store.setStress
                    )

                    checkInScale(
                        title: recoveryText("Overall soreness", "Generell ømhet"),
                        subtitle: recoveryText("None → very sore", "Ingen → svært øm"),
                        icon: "figure.walk.motion",
                        value: store.todayOverallSoreness,
                        onSelect: store.setOverallSoreness
                    )

                    checkInScale(
                        title: recoveryText("Motivation", "Motivasjon"),
                        subtitle: recoveryText("Low → high", "Lav → høy"),
                        icon: "flame.fill",
                        value: store.todayMotivation,
                        onSelect: store.setMotivation
                    )
                }

                Section(recoveryText("Muscle soreness", "Muskelømhet")) {
                    ForEach(
                        RecoverySorenessStore.muscleGroups,
                        id: \.self
                    ) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(group)
                                .font(.headline)

                            HStack(spacing: 6) {
                                ForEach(
                                    RecoverySorenessLevel.allCases
                                ) { level in
                                    Button {
                                        store.set(
                                            level,
                                            for: group
                                        )
                                    } label: {
                                        Text(level.title)
                                            .font(
                                                .caption2
                                                    .weight(.semibold)
                                            )
                                            .frame(
                                                maxWidth: .infinity
                                            )
                                            .padding(.vertical, 8)
                                            .foregroundStyle(
                                                store.level(
                                                    for: group
                                                ) == level
                                                    ? Color.white
                                                    : ATHLTHTheme.primaryText
                                            )
                                            .background(
                                                store.level(
                                                    for: group
                                                ) == level
                                                    ? ATHLTHTheme.accent
                                                    : Color.primary
                                                        .opacity(0.05),
                                                in: RoundedRectangle(
                                                    cornerRadius: 10
                                                )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(recoveryText("Daily Check-in", "Daglig innsjekk"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(recoveryText("Done", "Ferdig")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func checkInScale(
        title: String,
        subtitle: String,
        icon: String,
        value: Int?,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        onSelect(score)
                    } label: {
                        Text("\(score)")
                            .font(.caption.weight(.bold))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 34
                            )
                            .foregroundStyle(
                                value == score
                                    ? Color.white
                                    : ATHLTHTheme.primaryText
                            )
                            .background(
                                value == score
                                    ? ATHLTHTheme.accent
                                    : Color.primary.opacity(0.05),
                                in: RoundedRectangle(
                                    cornerRadius: 10,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecoveryMethodInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ATHLTHCard {
                        ATHLTHSectionHeader(
                            title: recoveryText("Readiness score", "Dagsformscore"),
                            actionTitle: "0–100"
                        )

                        Text(
                            recoveryText("ATHLTH compares your latest sleep, HRV and resting heart rate with your own recent baseline.", "ATHLTH sammenligner nyeste søvn, HRV og hvilepuls med din egen nyere grunnlinje.")
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)

                        VStack(spacing: 10) {
                            methodRow(
                                recoveryText("Sleep", "Søvn"),
                                weight: "45%",
                                icon: "moon.fill"
                            )
                            methodRow(
                                "HRV",
                                weight: "35%",
                                icon: "waveform.path.ecg"
                            )
                            methodRow(
                                recoveryText("Resting HR", "Hvilepuls"),
                                weight: "20%",
                                icon: "heart.fill"
                            )
                        }
                        .padding(.top, 12)
                    }

                    ATHLTHCard {
                        Text(recoveryText("Your baseline", "Din grunnlinje"))
                            .font(.headline)

                        Text(
                            recoveryText("The baseline uses usable days from the recent 14-day window where Sleep, HRV and Resting HR are all available. At least five usable days are required before ATHLTH shows a readiness score.", "Grunnlinjen bruker gyldige dager fra de siste 14 dagene der søvn, HRV og hvilepuls finnes. Minst fem gyldige dager kreves før ATHLTH viser en dagsformscore.")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                    }

                    ATHLTHCard {
                        Label(
                            recoveryText("Training guidance, not a medical assessment", "Treningsveiledning, ikke en medisinsk vurdering"),
                            systemImage: "info.circle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)

                        Text(
                            recoveryText("Daily Check-in responses may refine Today's Guidance, but they do not alter the wearable readiness score.", "Svar fra daglig innsjekk kan forbedre dagens anbefaling, men endrer ikke dagsformscoren fra klokken.")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                    }
                }
                .padding(16)
            }
            .navigationTitle(recoveryText("How Recovery Works", "Slik fungerer restitusjon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(recoveryText("Done", "Ferdig")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func methodRow(
        _ title: String,
        weight: String,
        icon: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 30, height: 30)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 9
                    )
                )

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(weight)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}

struct RecoveryGuidedToolView: View {
    @Environment(\.dismiss) private var dismiss

    let tool: RecoveryTool

    @State private var stepIndex = 0
    @State private var remainingSeconds = 0
    @State private var running = false

    private let timer = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                Image(systemName: tool.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 76, height: 76)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )

                VStack(spacing: 7) {
                    Text(tool.title)
                        .font(.title2.weight(.bold))

                    Text(
                        ATHLTHLocalization.choose(
                        english:
                            "Step \(stepIndex + 1) of \(tool.steps.count)",
                        norwegian:
                            "Steg \(stepIndex + 1) av \(tool.steps.count)"
                    )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(currentStep.title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }

                Text(timeText)
                    .font(
                        .system(
                            size: 52,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()

                ProgressView(
                    value: Double(
                        currentStep.seconds - remainingSeconds
                    ),
                    total: Double(currentStep.seconds)
                )
                .tint(ATHLTHTheme.accent)
                .padding(.horizontal, 36)

                HStack(spacing: 12) {
                    Button {
                        previousStep()
                    } label: {
                        Image(systemName: "backward.fill")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(stepIndex == 0)

                    Button {
                        running.toggle()
                    } label: {
                        Label(
                            running ? recoveryText("Pause", "Pause") : recoveryText("Start", "Start"),
                            systemImage:
                                running
                                    ? "pause.fill"
                                    : "play.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)

                    Button {
                        nextStep()
                    } label: {
                        Image(systemName: "forward.fill")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding()
            .navigationTitle(recoveryText("Recovery", "Restitusjon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(recoveryText("Close", "Lukk")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                remainingSeconds = currentStep.seconds
            }
            .onReceive(timer) { _ in
                guard running else { return }

                if remainingSeconds > 1 {
                    remainingSeconds -= 1
                } else {
                    nextStep()
                }
            }
        }
    }

    private var currentStep: RecoveryToolStep {
        tool.steps[
            min(
                max(stepIndex, 0),
                tool.steps.count - 1
            )
        ]
    }

    private var timeText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func previousStep() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        remainingSeconds = currentStep.seconds
        running = false
    }

    private func nextStep() {
        if stepIndex < tool.steps.count - 1 {
            stepIndex += 1
            remainingSeconds = currentStep.seconds
            running = true
        } else {
            running = false
            remainingSeconds = 0
        }
    }
}
