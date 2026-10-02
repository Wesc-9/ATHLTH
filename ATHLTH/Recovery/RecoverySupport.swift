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
    case "Glutes": return "Sete"
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
    let trainingMinutes: Double
}

struct RecoveryTrainingLoadSummary: Equatable {
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
        objectWillChange.send()
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
    let runningMinutes: Double
    let walkingMinutes: Double
    let estimatedRecoveryHours: Double
    let soreness: RecoverySorenessLevel
    let baselineWeeklyStrengthSets: Double?
    let chronicWeeklyTrainingMinutes: Double?
    let acuteToChronicRatio: Double?

    init(
        muscleGroup: String,
        lastTrainedAt: Date?,
        completedSets: Int,
        runningMinutes: Double = 0,
        walkingMinutes: Double = 0,
        estimatedRecoveryHours: Double,
        soreness: RecoverySorenessLevel,
        baselineWeeklyStrengthSets: Double? = nil,
        chronicWeeklyTrainingMinutes: Double? = nil,
        acuteToChronicRatio: Double? = nil
    ) {
        self.muscleGroup = muscleGroup
        self.lastTrainedAt = lastTrainedAt
        self.completedSets = completedSets
        self.runningMinutes = runningMinutes
        self.walkingMinutes = walkingMinutes
        self.estimatedRecoveryHours = estimatedRecoveryHours
        self.soreness = soreness
        self.baselineWeeklyStrengthSets = baselineWeeklyStrengthSets
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

    /// Acute muscle load normalized against the user's recent training capacity.
    /// New or infrequent users therefore reach higher load states sooner than
    /// users who have built a stable training baseline.
    var loadScore: Double {
        let learnedStrengthCapacity =
            max(
                (baselineWeeklyStrengthSets ?? 0) * 1.5,
                6
            )
        let strengthLoad =
            completedSets > 0
                ? min(
                    Double(completedSets) /
                        learnedStrengthCapacity,
                    1
                )
                : 0

        let movementMinutes =
            runningMinutes +
            walkingMinutes
        let learnedMovementCapacity =
            max(
                (chronicWeeklyTrainingMinutes ?? 0) *
                    0.60,
                60
            )
        let movementLoad =
            movementMinutes > 0
                ? min(
                    movementMinutes /
                        learnedMovementCapacity,
                    1
                )
                : 0

        let combined =
            1 -
            (
                (1 - strengthLoad) *
                (1 - movementLoad)
            )

        let spikeMultiplier: Double
        switch acuteToChronicRatio {
        case let ratio? where ratio > 1.50:
            spikeMultiplier = 1.25
        case let ratio? where ratio > 1.25:
            spikeMultiplier = 1.15
        case let ratio? where ratio > 1.00:
            spikeMultiplier = 1.07
        default:
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

    /// What the user should see right now. Recent load fades as the estimated
    /// recovery window progresses, while soreness can keep an area elevated.
    var currentLoadScore: Double {
        let remainingLoad =
            max(
                1 - (progress * 0.85),
                0.08
            )
        var score =
            loadScore *
            remainingLoad

        let sorenessFloor: Double
        switch soreness {
        case .none:
            sorenessFloor = 0
        case .mild:
            sorenessFloor = 0.28
        case .moderate:
            sorenessFloor = 0.55
        case .high:
            sorenessFloor = 0.80
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

    var loadTitle: String {
        switch currentLoadScore {
        case 0.78...:
            return recoveryText("Needs rest", "Trenger pause")
        case 0.58..<0.78:
            return recoveryText("High", "Høy")
        case 0.32..<0.58:
            return recoveryText("Moderate", "Moderat")
        default:
            return recoveryText("Ready", "Klar")
        }
    }

    var sourceSummary: String {
        var sources: [String] = []

        if completedSets > 0 {
            sources.append(recoveryText("Strength", "Styrke"))
        }
        if runningMinutes >= 1 {
            sources.append(recoveryText("Run", "Løp"))
        }
        if walkingMinutes >= 1 {
            sources.append(recoveryText("Walk", "Gange"))
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

        if currentLoadScore >= 0.78 {
            return recoveryText("Short break suggested", "Liten pause anbefales")
        }

        if progress >= 0.95 {
            return soreness == .mild ? recoveryText("Mild soreness", "Lett ømhet") : recoveryText("Ready", "Klar")
        }

        if progress >= 0.55 {
            return recoveryText("Recovering", "Restituerer")
        }

        return recoveryText("Recently trained", "Nylig trent")
    }
}

enum MuscleRecoveryEngine {
    static func statuses(
        history: [StrengthWorkoutLog],
        soreness: RecoverySorenessStore,
        activityLoad: RecoveryTrainingLoadSummary = RecoveryTrendSnapshot.empty.trainingLoad
    ) -> [MuscleRecoveryStatus] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        let baselineStart =
            now.addingTimeInterval(-35 * 86_400)

        var baselineSetTotals:
            [String: Int] = [:]

        for workout in history
        where workout.isFinished &&
            workout.startedAt >= baselineStart &&
            workout.startedAt < cutoff {
            for exercise in workout.exercises {
                let completedSets =
                    exercise.sets
                        .filter(\.countsTowardTrainingLoad)
                        .count

                guard completedSets > 0 else {
                    continue
                }

                let primary =
                    Set(
                        exercise.exercise
                            .primaryMuscles
                            .compactMap(
                                normalizedMuscleGroup
                            )
                    )

                for group in primary {
                    baselineSetTotals[
                        group,
                        default: 0
                    ] += completedSets
                }
            }
        }

        let baselineWeeklyStrengthSets =
            baselineSetTotals
                .mapValues {
                    Double($0) / 4
                }

        struct Accumulator {
            var lastTrainedAt: Date?
            var completedSets = 0
            var runningMinutes: Double = 0
            var walkingMinutes: Double = 0
        }

        var values: [String: Accumulator] = [:]

        for workout in history
        where workout.isFinished && workout.startedAt >= cutoff {
            let workoutDate = workout.endedAt ?? workout.startedAt

            for exercise in workout.exercises {
                let completedSets = exercise.sets.filter(\.countsTowardTrainingLoad).count

                guard completedSets > 0 else {
                    continue
                }

                let primary = Set(
                    exercise.exercise.primaryMuscles.compactMap(
                        normalizedMuscleGroup
                    )
                )

                for group in primary {
                    var item = values[group] ?? Accumulator()
                    item.completedSets += completedSets

                    if item.lastTrainedAt.map({ workoutDate > $0 }) ?? true {
                        item.lastTrainedAt = workoutDate
                    }

                    values[group] = item
                }
            }
        }

        func addMovement(
            group: String,
            runningMinutes: Double = 0,
            walkingMinutes: Double = 0,
            date: Date?
        ) {
            guard runningMinutes > 0 || walkingMinutes > 0 else {
                return
            }

            var item = values[group] ?? Accumulator()
            item.runningMinutes += runningMinutes
            item.walkingMinutes += walkingMinutes

            if let date,
               item.lastTrainedAt.map({ date > $0 }) ?? true {
                item.lastTrainedAt = date
            }

            values[group] = item
        }

        let run = activityLoad.runningMinutes
        let walk = activityLoad.walkingMinutes

        addMovement(
            group: "Quads",
            runningMinutes: run,
            walkingMinutes: walk * 0.48,
            date: maxDate(activityLoad.latestRunningAt, activityLoad.latestWalkingAt)
        )
        addMovement(
            group: "Calves",
            runningMinutes: run,
            walkingMinutes: walk * 0.58,
            date: maxDate(activityLoad.latestRunningAt, activityLoad.latestWalkingAt)
        )
        addMovement(
            group: "Hamstrings",
            runningMinutes: run * 0.82,
            walkingMinutes: walk * 0.28,
            date: maxDate(activityLoad.latestRunningAt, activityLoad.latestWalkingAt)
        )
        addMovement(
            group: "Glutes",
            runningMinutes: run * 0.88,
            walkingMinutes: walk * 0.42,
            date: maxDate(activityLoad.latestRunningAt, activityLoad.latestWalkingAt)
        )
        addMovement(
            group: "Core",
            runningMinutes: run * 0.34,
            walkingMinutes: walk * 0.16,
            date: maxDate(activityLoad.latestRunningAt, activityLoad.latestWalkingAt)
        )

        let allGroups = Set(values.keys)
            .union(soreness.todayRatings.keys)

        return allGroups
            .map { group in
                let item = values[group] ?? Accumulator()
                let sorenessLevel = soreness.level(for: group)

                let strengthRecoveryHours: Double
                switch item.completedSets {
                case 0:
                    strengthRecoveryHours = 0
                case 1...2:
                    strengthRecoveryHours = 36
                case 3...7:
                    strengthRecoveryHours = 48
                default:
                    strengthRecoveryHours = 60
                }

                let movementMinutes =
                    item.runningMinutes + item.walkingMinutes
                let movementRecoveryHours: Double
                switch movementMinutes {
                case 0:
                    movementRecoveryHours = 0
                case 0..<25:
                    movementRecoveryHours = 24
                case 25..<70:
                    movementRecoveryHours = 36
                case 70..<140:
                    movementRecoveryHours = 48
                default:
                    movementRecoveryHours = 60
                }

                let baseRecoveryHours = max(
                    max(strengthRecoveryHours, movementRecoveryHours),
                    24
                )

                let sorenessAdjustment: Double
                switch sorenessLevel {
                case .none: sorenessAdjustment = 0
                case .mild: sorenessAdjustment = 8
                case .moderate: sorenessAdjustment = 16
                case .high: sorenessAdjustment = 24
                }

                return MuscleRecoveryStatus(
                    muscleGroup: group,
                    lastTrainedAt: item.lastTrainedAt,
                    completedSets: item.completedSets,
                    runningMinutes: item.runningMinutes,
                    walkingMinutes: item.walkingMinutes,
                    estimatedRecoveryHours:
                        baseRecoveryHours + sorenessAdjustment,
                    soreness: sorenessLevel,
                    baselineWeeklyStrengthSets:
                        baselineWeeklyStrengthSets[group],
                    chronicWeeklyTrainingMinutes:
                        activityLoad.chronicWeeklyAverageMinutes,
                    acuteToChronicRatio:
                        activityLoad.ratio
                )
            }
            .sorted { lhs, rhs in
                if lhs.currentLoadScore != rhs.currentLoadScore {
                    return lhs.currentLoadScore > rhs.currentLoadScore
                }

                if lhs.soreness.rawValue != rhs.soreness.rawValue {
                    return lhs.soreness.rawValue > rhs.soreness.rawValue
                }

                return lhs.progress < rhs.progress
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

                    PointMark(
                        x: .value(recoveryText("Day", "Dag"), day.date),
                        y: .value(recoveryText("Value", "Verdi"), value)
                    )
                    .symbolSize(10)
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
    let onLogSoreness: () -> Void

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recoveryText("Recently trained areas", "Nylig trente områder"))
                        .font(.title3.weight(.bold))

                    Text(
                        recoveryText("Last 7 days · strength, running and walking all contribute.", "Siste 7 dager · styrke, løping og gange teller med.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(recoveryText("Check in", "Sjekk inn")) {
                    onLogSoreness()
                }
                .font(.caption.weight(.semibold))
            }

            HStack(spacing: 8) {
                sourceBadge(
                    title:
                        recoveryText(
                            "Strength",
                            "Styrke"
                        ),
                    icon: "figure.strengthtraining.traditional"
                )
                sourceBadge(
                    title:
                        recoveryText(
                            "Run",
                            "Løp"
                        ),
                    icon: "figure.run"
                )
                sourceBadge(
                    title:
                        recoveryText(
                            "Walk",
                            "Gange"
                        ),
                    icon: "figure.walk"
                )
            }
            .padding(.top, 10)

            if !unmappedExerciseNames.isEmpty {
                HStack(
                    alignment: .top,
                    spacing: 8
                ) {
                    Image(
                        systemName:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                    Text(
                        missingMuscleGroupWarning
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }

            if statuses.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "figure.mixed.cardio")
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )

                    Text(
                        recoveryText("Complete a tracked strength workout, run or walk and ATHLTH will show which areas have carried the most recent training.", "Fullfør en registrert styrkeøkt, løpetur eller gåtur, så viser ATHLTH hvilke områder som har hatt mest nylig belastning.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 14) {
                    StrengthMuscleMapView(
                        profile: muscleMapProfile,
                        compact: true,
                        style: .recoveryLoad
                    )
                    .frame(height: 158)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Color.primary.opacity(0.025),
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )

                    VStack(spacing: 9) {
                        ForEach(statuses.prefix(8)) { status in
                            muscleRow(status)
                        }
                    }
                }
                .padding(.top, 10)
            }

            Text(
                recoveryText(
                    "Colors compare recent muscle load with your personal training baseline. Green = ready; red = this area may benefit from a short break. ATHLTH estimate only.",
                    "Fargene sammenligner nyere muskelbelastning med ditt personlige treningsnivå. Grønt = klar; rødt = området kan ha godt av en liten pause. Kun ATHLTH-estimat."
                )
            )
            .font(.system(size: 8.5, weight: .regular))
            .foregroundStyle(.secondary)
            .padding(.top, 7)
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
                unmappedExerciseNames.count - 3,
                0
            )
        let suffix =
            remaining > 0
                ? " +\(remaining)"
                : ""

        if unmappedExerciseNames.count == 1 {
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

    private func sourceBadge(
        title: String,
        icon: String
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                ATHLTHTheme.accentSoft.opacity(0.7),
                in: Capsule()
            )
    }

    private func muscleRow(
        _ status: MuscleRecoveryStatus
    ) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(recoveryMuscleName(status.muscleGroup))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(status.sourceSummary)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 7)

                Text(status.loadTitle)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(loadTint(status))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        loadTint(status).opacity(0.10),
                        in: Capsule()
                    )
            }

            ProgressView(value: max(status.currentLoadScore, 0.03))
                .tint(loadTint(status))

            HStack(spacing: 4) {
                Text(
                    ATHLTHLocalization.choose(english: "\(Int((status.progress * 100).rounded()))% recovered", norwegian: "\(Int((status.progress * 100).rounded()))% restituert")
                )
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(statusTint(status))

                Spacer()

                if let last = status.lastTrainedAt {
                    Text(relativeDescription(last))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var muscleMapProfile: StrengthMuscleProfile {
        var scores: [StrengthMuscleRegion: Double] = [:]

        for status in statuses {
            let score =
                status.currentLoadScore

            for region in muscleRegions(
                for: status.muscleGroup
            ) {
                scores[region] = max(
                    scores[region] ?? 0,
                    score
                )
            }
        }

        return StrengthMuscleProfile(
            activations: scores.map {
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
        let normalized = group.lowercased()

        if normalized.contains("chest") {
            return [.chest]
        }
        if normalized.contains("back") {
            return [.lats, .upperBack, .lowerBack]
        }
        if normalized.contains("shoulder") {
            return [.frontDelts, .sideDelts, .rearDelts]
        }
        if normalized.contains("arm") {
            return [.biceps, .triceps, .forearms]
        }
        if normalized.contains("core") ||
            normalized.contains("ab") {
            return [.abs, .obliques]
        }
        if normalized.contains("glute") {
            return [.glutes, .outerHip]
        }
        if normalized.contains("quad") {
            return [.quads]
        }
        if normalized.contains("hamstring") {
            return [.hamstrings]
        }
        if normalized.contains("calf") ||
            normalized.contains("calves") {
            return [.calves]
        }

        return []
    }

    private func relativeDescription(
        _ date: Date
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(
            identifier:
                ATHLTHLocalization.isNorwegian
                    ? "nb_NO"
                    : "en_US"
        )
        return formatter.localizedString(
            for: date,
            relativeTo: Date()
        )
    }

    private func loadTint(
        _ status: MuscleRecoveryStatus
    ) -> Color {
        switch status.currentLoadScore {
        case 0.78...:
            return .red
        case 0.58..<0.78:
            return .orange
        case 0.32..<0.58:
            return Color(
                red: 0.78,
                green: 0.58,
                blue: 0.05
            )
        default:
            return .green
        }
    }

    private func statusTint(
        _ status: MuscleRecoveryStatus
    ) -> Color {
        if status.currentLoadScore >= 0.78 ||
            status.soreness == .high {
            return .red
        }

        if status.currentLoadScore >= 0.58 ||
            status.soreness == .moderate ||
            status.progress < 0.45 {
            return .orange
        }

        if status.currentLoadScore >= 0.32 ||
            status.progress < 0.85 {
            return Color(
                red: 0.78,
                green: 0.58,
                blue: 0.05
            )
        }

        return .green
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
