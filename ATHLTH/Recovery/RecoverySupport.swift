import Charts
import Combine
import Foundation
import SwiftUI

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

    var ratio: Double? {
        guard let chronicWeeklyAverageMinutes,
              chronicWeeklyAverageMinutes > 0 else {
            return nil
        }

        return acuteMinutes / chronicWeeklyAverageMinutes
    }

    var title: String {
        guard let ratio else {
            return "Building load baseline"
        }

        switch ratio {
        case ..<0.75:
            return "Below recent load"
        case 0.75...1.25:
            return "Near recent load"
        case 1.25...1.50:
            return "Elevated load"
        default:
            return "High load"
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
        case .none: return "None"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    var shortTitle: String {
        switch self {
        case .none: return "Ready"
        case .mild: return "Mild"
        case .moderate: return "Sore"
        case .high: return "Very sore"
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
    let estimatedRecoveryHours: Double
    let soreness: RecoverySorenessLevel

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

    var statusTitle: String {
        if soreness == .high {
            return "Very sore"
        }

        if soreness == .moderate {
            return "Sore"
        }

        if progress >= 0.95 {
            return soreness == .mild ? "Mild soreness" : "Ready"
        }

        if progress >= 0.55 {
            return "Recovering"
        }

        return "Recently trained"
    }
}

enum MuscleRecoveryEngine {
    static func statuses(
        history: [StrengthWorkoutLog],
        soreness: RecoverySorenessStore
    ) -> [MuscleRecoveryStatus] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-5 * 86_400)

        struct Accumulator {
            var lastTrainedAt: Date?
            var completedSets = 0
        }

        var values: [String: Accumulator] = [:]

        for workout in history
        where workout.isFinished && workout.startedAt >= cutoff {
            let workoutDate = workout.endedAt ?? workout.startedAt

            for exercise in workout.exercises {
                let completedSets = exercise.sets.filter(\.isCompleted).count

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

        let allGroups = Set(values.keys)
            .union(soreness.todayRatings.keys)

        return allGroups
            .map { group in
                let item = values[group] ?? Accumulator()
                let sorenessLevel = soreness.level(for: group)

                let baseRecoveryHours: Double
                switch item.completedSets {
                case 0...2:
                    baseRecoveryHours = 36
                case 3...7:
                    baseRecoveryHours = 48
                default:
                    baseRecoveryHours = 60
                }

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
                    estimatedRecoveryHours:
                        baseRecoveryHours + sorenessAdjustment,
                    soreness: sorenessLevel
                )
            }
            .sorted { lhs, rhs in
                if lhs.soreness.rawValue != rhs.soreness.rawValue {
                    return lhs.soreness.rawValue >
                        rhs.soreness.rawValue
                }

                if lhs.progress != rhs.progress {
                    return lhs.progress < rhs.progress
                }

                return lhs.muscleGroup < rhs.muscleGroup
            }
    }

    private static func normalizedMuscleGroup(
        _ rawValue: String
    ) -> String? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !value.isEmpty else {
            return nil
        }

        if value.contains("chest") ||
            value.contains("pectoral") {
            return "Chest"
        }

        if value.contains("lat") ||
            value.contains("back") ||
            value.contains("trap") ||
            value.contains("rhomboid") {
            return "Back"
        }

        if value.contains("shoulder") ||
            value.contains("deltoid") {
            return "Shoulders"
        }

        if value.contains("bicep") ||
            value.contains("tricep") ||
            value.contains("forearm") ||
            value.contains("brach") {
            return "Arms"
        }

        if value.contains("abdominal") ||
            value.contains("abs") ||
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
            value.contains("gastrocnemius") ||
            value.contains("soleus") {
            return "Calves"
        }

        return rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }
}

enum RecoveryTool: String, CaseIterable, Identifiable {
    case stretch
    case mobility
    case breathing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stretch: return "Full-body reset"
        case .mobility: return "Mobility flow"
        case .breathing: return "Downshift breathing"
        }
    }

    var subtitle: String {
        switch self {
        case .stretch: return "8 min · gentle stretch"
        case .mobility: return "10 min · hips, spine & shoulders"
        case .breathing: return "5 min · calm breathing"
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
                .init(title: "Cat-cow", seconds: 60),
                .init(title: "Hip flexor · left", seconds: 60),
                .init(title: "Hip flexor · right", seconds: 60),
                .init(title: "Hamstring fold", seconds: 90),
                .init(title: "Chest opener", seconds: 60),
                .init(title: "Child’s pose", seconds: 90),
                .init(title: "Easy reset", seconds: 60)
            ]

        case .mobility:
            return [
                .init(title: "Ankle rocks", seconds: 75),
                .init(title: "90/90 hips", seconds: 90),
                .init(title: "World’s greatest stretch", seconds: 120),
                .init(title: "Thoracic rotations", seconds: 90),
                .init(title: "Shoulder circles", seconds: 75),
                .init(title: "Deep squat hold", seconds: 90),
                .init(title: "Easy reset", seconds: 60)
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
                title: "Why this score",
                actionTitle: "Today"
            )

            VStack(spacing: 12) {
                factorRow(
                    title: "Sleep",
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
                    title: "Resting HR",
                    icon: "heart.fill",
                    weight: "20%",
                    value: restingHRValue,
                    score: restingFactor
                )
            }
            .padding(.top, 12)

            Text(
                "Each factor is compared with your own recent baseline. The weights above are the same ones used for the readiness score shown on Home."
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
        guard sleep.totalAsleep > 0 else { return "No data" }

        if let baseline = recovery.averageSleepDuration {
            return "\(sleep.totalAsleep.shortDuration) · \(comparison(current: sleep.totalAsleep, baseline: baseline, higherIsBetter: true))"
        }

        return sleep.totalAsleep.shortDuration
    }

    private var hrvValue: String {
        guard let current = heart.hrvMilliseconds else {
            return "No data"
        }

        if let baseline = recovery.baselineHRVMilliseconds {
            return "\(Int(current.rounded())) ms · \(comparison(current: current, baseline: baseline, higherIsBetter: true))"
        }

        return "\(Int(current.rounded())) ms"
    }

    private var restingHRValue: String {
        guard let current = heart.restingHeartRate else {
            return "No data"
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
        guard baseline > 0 else { return "No baseline" }

        let percent = ((current - baseline) / baseline) * 100
        let rounded = Int(abs(percent).rounded())

        guard rounded >= 2 else {
            return "near baseline"
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
        guard let score else { return "Learning" }

        switch score {
        case 0.90...: return "Strong"
        case 0.75..<0.90: return "Good"
        case 0.60..<0.75: return "Low"
        default: return "Limited"
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
                title: "Recent signals",
                actionTitle: "14 days"
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                trendTile(
                    title: "Sleep",
                    value: sleepTrendValue,
                    subtitle: sleepQualityText,
                    icon: "moon.fill",
                    metric: .sleep
                )

                trendTile(
                    title: "HRV",
                    value: latestHRVText,
                    subtitle: "Nightly / daily signal",
                    icon: "waveform.path.ecg",
                    metric: .hrv
                )

                trendTile(
                    title: "Resting HR",
                    value: latestRestingHRText,
                    subtitle: "Lower vs baseline can be favorable",
                    icon: "heart.fill",
                    metric: .restingHR
                )

                trendTile(
                    title: "Training load",
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
                        x: .value("Day", day.date),
                        y: .value("Value", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(ATHLTHTheme.accent)

                    PointMark(
                        x: .value("Day", day.date),
                        y: .value("Value", value)
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
            return "Sleep quality unavailable"
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
            quality = "Good quality"
        } else if durationHours >= 6,
                  awakeRatio < 0.25 {
            quality = "Fair quality"
        } else {
            quality = "Low quality"
        }

        return "\(quality) · duration + available stages"
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
        return "\(minutes) min / 7d"
    }

    private var loadSubtitle: String {
        let load = snapshot.trainingLoad

        guard let chronic = load.chronicWeeklyAverageMinutes else {
            return load.title
        }

        return "\(load.title) · 28d avg \(Int(chronic.rounded())) min/week"
    }
}

struct RecoveryLastNightCard: View {
    let sleep: SleepSummary

    var body: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Last night",
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

                Text("asleep")
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

                        Text("Bed → wake")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 12)

            HStack(spacing: 8) {
                stageTile(
                    "Deep",
                    value: sleep.deep,
                    icon: "moon.zzz.fill"
                )
                stageTile(
                    "REM",
                    value: sleep.rem,
                    icon: "brain.head.profile"
                )
                stageTile(
                    "Core",
                    value: sleep.core,
                    icon: "moon.fill"
                )
                stageTile(
                    "Awake",
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
            return "Today"
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
            return "Good sleep quality from duration and available sleep stages."
        }

        if durationHours >= 6,
           awakeRatio < 0.25 {
            return "Fair sleep quality. Recovery also considers HRV and resting heart rate."
        }

        return "Sleep was below your usual recovery-friendly range."
    }
}

struct RecoveryDailyCheckInCard: View {
    @ObservedObject var store: RecoverySorenessStore
    let onCheckIn: () -> Void

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily check-in")
                        .font(.title3.weight(.bold))

                    Text(
                        "How you feel can refine today's guidance without changing your wearable score."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(
                    store.hasTodayCheckIn
                        ? "Update"
                        : "Check in"
                ) {
                    onCheckIn()
                }
                .font(.caption.weight(.semibold))
            }

            if store.hasTodayCheckIn {
                HStack(spacing: 8) {
                    checkInMetric(
                        title: "Energy",
                        value: store.todayEnergy,
                        icon: "bolt.fill",
                        inverted: false
                    )
                    checkInMetric(
                        title: "Stress",
                        value: store.todayStress,
                        icon: "waveform.path.ecg",
                        inverted: true
                    )
                    checkInMetric(
                        title: "Soreness",
                        value: store.todayOverallSoreness,
                        icon: "figure.walk.motion",
                        inverted: true
                    )
                    checkInMetric(
                        title: "Motivation",
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
                            Text("Add today's context")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                            Text(
                                "Energy, stress, soreness and motivation."
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
            "\(title), \(value.map(String.init) ?? "not logged") out of 5"
        )
    }
}

struct MuscleRecoveryCard: View {
    let statuses: [MuscleRecoveryStatus]
    let onLogSoreness: () -> Void

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Muscle recovery")
                        .font(.title3.weight(.bold))
                    Text("Based on recent strength work and your soreness log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Check in") {
                    onLogSoreness()
                }
                .font(.caption.weight(.semibold))
            }

            if statuses.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text(
                        "Complete a tracked strength workout or log soreness to start muscle recovery guidance."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(statuses.prefix(6)) { status in
                        HStack(spacing: 11) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(status.muscleGroup)
                                        .font(.subheadline.weight(.semibold))

                                    Spacer()

                                    Text(status.statusTitle)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(
                                            statusTint(status)
                                        )
                                }

                                ProgressView(value: status.progress)
                                    .tint(statusTint(status))

                                HStack {
                                    if status.completedSets > 0 {
                                        Text(
                                            "\(status.completedSets) recent sets"
                                        )
                                    }

                                    if let last = status.lastTrainedAt {
                                        Text(
                                            relativeDescription(last)
                                        )
                                    }

                                    if status.soreness != .none {
                                        Text(
                                            "Logged: \(status.soreness.title)"
                                        )
                                    }
                                }
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 12)
            }

            Text(
                "Recovery time is an estimate from recent training volume and your feedback, not a medical measurement."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
    }

    private func relativeDescription(
        _ date: Date
    ) -> String {
        RelativeDateTimeFormatter()
            .localizedString(
                for: date,
                relativeTo: Date()
            )
    }

    private func statusTint(
        _ status: MuscleRecoveryStatus
    ) -> Color {
        if status.soreness == .high ||
            status.progress < 0.45 {
            return .red
        }

        if status.soreness == .moderate ||
            status.progress < 0.85 {
            return .orange
        }

        return .green
    }
}

struct RecoveryToolsCard: View {
    let onSelect: (RecoveryTool) -> Void

    var body: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Recovery tools",
                actionTitle: "Do something now"
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
                        "Your check-in can influence Today's Guidance and muscle-recovery suggestions. It never changes the wearable Readiness score."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("How you feel") {
                    checkInScale(
                        title: "Energy",
                        subtitle: "Low → high",
                        icon: "bolt.fill",
                        value: store.todayEnergy,
                        onSelect: store.setEnergy
                    )

                    checkInScale(
                        title: "Stress",
                        subtitle: "Low → high",
                        icon: "waveform.path.ecg",
                        value: store.todayStress,
                        onSelect: store.setStress
                    )

                    checkInScale(
                        title: "Overall soreness",
                        subtitle: "None → very sore",
                        icon: "figure.walk.motion",
                        value: store.todayOverallSoreness,
                        onSelect: store.setOverallSoreness
                    )

                    checkInScale(
                        title: "Motivation",
                        subtitle: "Low → high",
                        icon: "flame.fill",
                        value: store.todayMotivation,
                        onSelect: store.setMotivation
                    )
                }

                Section("Muscle soreness") {
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
            .navigationTitle("Daily Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
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
                            title: "Readiness score",
                            actionTitle: "0–100"
                        )

                        Text(
                            "ATHLTH compares your latest sleep, HRV and resting heart rate with your own recent baseline."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)

                        VStack(spacing: 10) {
                            methodRow(
                                "Sleep",
                                weight: "45%",
                                icon: "moon.fill"
                            )
                            methodRow(
                                "HRV",
                                weight: "35%",
                                icon: "waveform.path.ecg"
                            )
                            methodRow(
                                "Resting HR",
                                weight: "20%",
                                icon: "heart.fill"
                            )
                        }
                        .padding(.top, 12)
                    }

                    ATHLTHCard {
                        Text("Your baseline")
                            .font(.headline)

                        Text(
                            "The baseline uses usable days from the recent 14-day window where Sleep, HRV and Resting HR are all available. At least five usable days are required before ATHLTH shows a readiness score."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                    }

                    ATHLTHCard {
                        Label(
                            "Training guidance, not a medical assessment",
                            systemImage: "info.circle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)

                        Text(
                            "Daily Check-in responses may refine Today's Guidance, but they do not alter the wearable readiness score."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                    }
                }
                .padding(16)
            }
            .navigationTitle("How Recovery Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
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
                        "Step \(stepIndex + 1) of \(tool.steps.count)"
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
                            running ? "Pause" : "Start",
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
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
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
