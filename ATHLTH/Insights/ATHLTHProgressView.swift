import Charts
import Combine
import MapKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

private enum ProgressPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"
    case year = "Year"

    var id: String { rawValue }
}

struct ATHLTHProgressView: View {
    private enum TrainingScope: String, CaseIterable, Identifiable {
        case all, running, strength
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All trening"
            case .running: return "Løping"
            case .strength: return "Styrke"
            }
        }
    }
    @State private var trainingScope: TrainingScope = .all

    private var trainingScopePicker: some View {
        Menu {
            ForEach(TrainingScope.allCases) { choice in
                Button {
                    trainingScope = choice
                } label: {
                    if trainingScope == choice {
                        Label(choice.label, systemImage: "checkmark")
                    } else {
                        Text(choice.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(trainingScope.label)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(ATHLTHTheme.champagneSoft, in: Capsule())
        }
        .accessibilityLabel("Treningstype: \(trainingScope.label)")
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRENING")
                .font(.caption.weight(.medium))
                .tracking(3)
                .foregroundStyle(ATHLTHTheme.mutedText)
            Text("Fremdrift")
                .font(.system(size: 40, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
            HStack(alignment: .center) {
                Text("Se utviklingen din. Bygg videre på det som fungerer.")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                Spacer(minLength: 8)
                trainingScopePicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var trophyStore: TrophyStore

    @State private var period: ProgressPeriod = .week
    @State private var progressSnapshot: HealthProgressSnapshot?
    @State private var consistencySnapshot: HealthProgressSnapshot?
    @State private var personalRecords: [HealthPersonalRecord] = []
    @State private var workoutHistory: [WorkoutSummary] = []
    @State private var trendMetric: ProgressTrendMetric = .training
    @State private var progressLoading = false
    @State private var progressError: String?

    private let green = ATHLTHTheme.accent
    private let blue = Color(red: 0.20, green: 0.56, blue: 0.96)
    private let purple = Color(red: 0.42, green: 0.36, blue: 0.95)
    private let canvas = Color(red: 0.965, green: 0.972, blue: 0.968)

    var body: some View {
        return NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: ATHLTHTheme.premiumGold.opacity(0.18),
                softTransition: true,
                immersiveTransition: false,
                scrollFadeTransition: false
            ) {
                Color.clear.frame(height: 1)
            } content: {
                LazyVStack(spacing: 15) {
                    progressHeader
                    periodPicker
                    let selected = selectedPeriodWorkouts
                    premiumOverview(runs: selected.runs, lifts: selected.lifts)
                    premiumTrend(runs: selected.runs, lifts: selected.lifts)
                    if trainingScope == .all {
                        if let snapshot = progressSnapshot {
                            ProgressConsistencyCard(snapshot: consistencySnapshot)
                            ProgressTrendCard(snapshot: snapshot, metric: $trendMetric)
                        } else {
                            progressWithoutHealthCard
                        }
                    }
                    ProgressPerformanceCard(
                        runningWorkouts: trainingScope == .strength ? [] : selected.runs,
                        strengthWorkouts: trainingScope == .running ? [] : selected.lifts,
                        healthRecords: trainingScope == .strength ? [] : personalRecords,
                        strengthRecords: trainingScope == .running ? [] : strengthWorkout.personalRecords,
                        repRecords: trainingScope == .running ? [] : strengthWorkout.repPersonalRecords
                    )
                    personalRecordsCard
                    recentActivity(runs: selected.runs, lifts: selected.lifts)
                    if trainingScope == .all { achievementsCard }
                    if progressLoading {
                        ProgressView().controlSize(.small)
                    } else if let progressError, trainingScope == .all {
                        Text(progressError)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                async let selected: Void = loadProgressData()
                async let support: Void = loadSupportingProgressData()
                _ = await (selected, support)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: period) {
            await loadProgressData()
        }
        .task {
            await loadSupportingProgressData()
            await goalStore.refreshAutomaticMilestones(
                health: health,
                strength: strengthWorkout
            )
            await trophyStore.refresh(
                health: health,
                strength: strengthWorkout,
                goals: goalStore
            )
        }
    }

    private func premiumOverview(runs: [WorkoutSummary], lifts: [StrengthWorkoutLog]) -> some View {
        let runDuration = runs.reduce(0.0) { $0 + $1.duration }
        let liftDuration = lifts.reduce(0.0) {
            $0 + max(0, ($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt))
        }
        let distance = runs.compactMap(\.distanceMeters).reduce(0, +) / 1_000
        let volume = lifts.reduce(0.0) { $0 + $1.totalVolumeKilograms }
        let workoutCount = trainingScope == .all
            ? (progressSnapshot?.workoutCount ?? (runs.count + lifts.count))
            : (trainingScope == .running ? runs.count : lifts.count)
        let activeDayCount = trainingScope == .all
            ? (progressSnapshot?.activeWorkoutDays.count ?? 0)
            : Set(runs.map { Calendar.current.startOfDay(for: $0.startDate) }).count
        let duration = trainingScope == .all
            ? (progressSnapshot?.trainingDuration ?? (runDuration + liftDuration))
            : (trainingScope == .running ? runDuration : liftDuration)
        let cards: [(String, String, String)] = [
            ("Økter", "\(workoutCount)", "calendar"),
            ("Treningstid", duration.shortDuration, "clock"),
            (trainingScope == .strength ? "Treningsvolum" : "Distanse",
             trainingScope == .strength ? String(format: "%.0f kg", volume) :
                String(format: "%.1f km", trainingScope == .all
                    ? (progressSnapshot?.workoutDistanceMeters ?? (distance * 1_000)) / 1_000
                    : distance), trainingScope == .strength ? "dumbbell" : "figure.run"),
            (trainingScope == .strength ? "Arbeidssett" : "Aktive dager",
             trainingScope == .strength
                 ? "\(lifts.reduce(0) { $0 + $1.totalWorkingSets })"
                 : "\(activeDayCount)",
             "chart.bar")
        ]
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Oversikt")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                Spacer()
                Text(period.rawValue)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(cards.indices, id: \.self) { index in
                    let card = cards[index]
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: card.2)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        Text(card.1)
                            .font(.system(size: 27, weight: .medium, design: .serif))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(card.0)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 19))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19)
                            .stroke(ATHLTHTheme.premiumGold.opacity(0.18), lineWidth: 0.8)
                    }
                }
            }
        }
    }

    private func premiumTrend(runs: [WorkoutSummary], lifts: [StrengthWorkoutLog]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(trainingScope == .running ? "Utvikling i distanse"
                : trainingScope == .strength ? "Utvikling i treningsvolum"
                : "Treningsutvikling")
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
            Text(trainingScope == .running ? "Kilometer per økt"
                : trainingScope == .strength ? "Kilogram per økt"
                : "Treningstimer over tid")
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

            if trainingScope == .running {
                if runs.isEmpty {
                    emptyTrend
                } else {
                    Chart(runs) { workout in
                        BarMark(
                            x: .value("Dato", workout.startDate),
                            y: .value("km", (workout.distanceMeters ?? 0) / 1_000)
                        )
                        .foregroundStyle(ATHLTHTheme.accentDeep.gradient)
                        .cornerRadius(3)
                    }
                    .frame(height: 178)
                }
            } else if trainingScope == .strength {
                if lifts.isEmpty {
                    emptyTrend
                } else {
                    Chart(lifts) { workout in
                        BarMark(
                            x: .value("Dato", workout.startedAt),
                            y: .value("kg", workout.totalVolumeKilograms)
                        )
                        .foregroundStyle(ATHLTHTheme.accentDeep.gradient)
                        .cornerRadius(3)
                    }
                    .frame(height: 178)
                }
            } else if let snapshot = progressSnapshot, !snapshot.buckets.isEmpty {
                Chart(snapshot.buckets) { bucket in
                    AreaMark(
                        x: .value("Dato", bucket.startDate),
                        y: .value("Timer", bucket.trainingDuration / 3_600)
                    )
                    .foregroundStyle(ATHLTHTheme.champagneSoft)
                    LineMark(
                        x: .value("Dato", bucket.startDate),
                        y: .value("Timer", bucket.trainingDuration / 3_600)
                    )
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .frame(height: 178)
            } else {
                emptyTrend
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyTrend: some View {
        Label("Ingen registrerte økter for denne perioden", systemImage: "chart.xyaxis.line")
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .frame(maxWidth: .infinity, minHeight: 170)
    }

    private func recentActivity(runs: [WorkoutSummary], lifts: [StrengthWorkoutLog]) -> some View {
        let runEntries = runs.map {
            (date: $0.startDate, title: "Løping", detail:
                String(format: "%.1f km", ($0.distanceMeters ?? 0) / 1_000),
             symbol: "figure.run")
        }
        let strengthEntries = lifts.map {
            (date: $0.startedAt, title: "Styrketrening",
             detail: "\($0.totalWorkingSets) arbeidssett", symbol: "dumbbell")
        }
        let entries = (trainingScope == .strength ? [] : runEntries) +
            (trainingScope == .running ? [] : strengthEntries)
        let sorted = entries.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 13) {
            Text("Siste økter")
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
            if sorted.isEmpty {
                Label("Ingen registrerte økter i perioden", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            } else {
                ForEach(Array(sorted.prefix(5).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 35, height: 35)
                            .background(ATHLTHTheme.champagneSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Text(item.detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    if item.date != sorted.prefix(5).last?.date {
                        Divider().overlay(ATHLTHTheme.divider)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var progressWithoutHealthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(green)
                    .frame(width: 48, height: 48)
                    .background(
                        green.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        health.hasRequestedAuthorization
                            ? ATHLTHLocalization.choose(
                                english: "No readable Apple Health progress yet",
                                norwegian: "Ingen lesbare helsedata ennå"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Progress without Apple Health",
                                norwegian: "Fremgang uten Apple Health"
                            )
                    )
                    .font(.headline)

                    Text(
                        health.hasRequestedAuthorization
                            ? ATHLTHLocalization.choose(
                                english: "Apple Health permissions have been reviewed, but no readable workouts, steps or sleep data were found for this period. This can also happen if read access was not granted. You can review access in the Health app.",
                                norwegian: "Apple Health-tillatelsene er gjennomgått, men vi fant ingen lesbare økter, skritt eller søvndata for perioden. Dette kan også skje hvis lesetilgang ikke ble gitt. Du kan kontrollere tilgangen i Helse-appen."
                            )
                            : ATHLTHLocalization.choose(
                                english: "Health-based charts are hidden until you review Apple Health access. Strength records, goals and ATHLTH progress remain available.",
                                norwegian: "Helsebaserte grafer skjules til du har gjennomgått Apple Health-tilgangen. Styrkeøkter, mål og ATHLTH-fremgang er fortsatt tilgjengelig."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private var progressHasHealthData: Bool {
        guard let snapshot = progressSnapshot else { return false }

        return snapshot.workoutCount > 0 ||
            (snapshot.totalSteps ?? 0) > 0 ||
            (snapshot.averageSleepDuration ?? 0) > 0 ||
            snapshot.trainingDuration > 0
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProgressPeriod.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        period = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(period == option ? .semibold : .medium))
                        .foregroundStyle(period == option ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            period == option ? green : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    ATHLTHTheme.cardWarm.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    ATHLTHTheme.premiumGold.opacity(0.12),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.07),
            radius: 12,
            x: 0,
            y: 6
        )
    }


    private var personalRecordsCard: some View {
        let healthRecords = Array((trainingScope == .strength ? [] : personalRecords).prefix(2))
        let strengthRecords = Array(
            (trainingScope == .running ? [] : strengthWorkout.personalRecords)
                .filter { $0.kind == .heaviestSet }
                .prefix(2)
        )
        let totalRecordCount =
            (trainingScope == .strength ? 0 : personalRecords.count) +
            (trainingScope == .running ? 0 : strengthWorkout.personalRecords.count + strengthWorkout.repPersonalRecords.count)

        return NavigationLink {
            ProgressPersonalRecordsView(
                healthRecords: trainingScope == .strength ? [] : personalRecords,
                strengthRecords:
                    trainingScope == .running ? [] : strengthWorkout.personalRecords,
                repRecords:
                    trainingScope == .running ? [] : strengthWorkout.repPersonalRecords
            )
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personlige rekorder")
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text("Dine beste registrerte prestasjoner.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if totalRecordCount >
                        healthRecords.count +
                        strengthRecords.count {
                        Text(
                            "+\(totalRecordCount - healthRecords.count - strengthRecords.count)"
                        )
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(green)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                if healthRecords.isEmpty &&
                    strengthRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "trophy")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Text("Ingen rekorder ennå")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Text(
                            "Rekorder vises når du har registrert treningsøkter."
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(healthRecords) { record in
                        recordRow(
                            record.kind.title,
                            value: record.formattedValue,
                            date: record.date.formatted(
                                .dateTime
                                    .month(.abbreviated)
                                    .day()
                                    .year()
                            ),
                            icon: record.kind.systemImage
                        )
                    }

                    if !healthRecords.isEmpty &&
                        !strengthRecords.isEmpty {
                        Divider()
                            .overlay(
                                Color.black.opacity(0.05)
                            )
                    }

                    ForEach(strengthRecords) { record in
                        recordRow(
                            record.title,
                            value: record.value,
                            date: record.date.formatted(
                                .dateTime
                                    .month(.abbreviated)
                                    .day()
                                    .year()
                            ),
                            icon: record.kind.systemImage
                        )
                    }
                }
            }
            .padding(16)
            .progressReferenceCard()
        }
        .buttonStyle(.plain)
    }

    private var achievementsCard: some View {
        TrophyProgressCard()
    }






    private var overviewTitle: String {
        switch period {
        case .week: return "Weekly Overview"
        case .month: return "Monthly Overview"
        case .threeMonths: return "3 Month Overview"
        case .year: return "Year Overview"
        }
    }

    private var comparisonLabel: String {
        switch period {
        case .week: return "vs. prior 7 days"
        case .month: return "vs. prior month"
        case .threeMonths: return "vs. prior 3 mo."
        case .year: return "vs. prior year"
        }
    }

    private var periodSummaryLabel: String {
        switch period {
        case .week: return "last 7 days"
        case .month: return "last month"
        case .threeMonths: return "last 3 months"
        case .year: return "last year"
        }
    }

    private var periodDateLabel: String {
        let range = progressRange
        let start = range.start.formatted(.dateTime.month(.abbreviated).day())
        let end = range.end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    private var stepsChartUpperBound: Double {
        let maximum = progressSnapshot?.buckets
            .compactMap(\.averageDailySteps)
            .max() ?? 0
        let rounded = ceil(maximum / 5_000) * 5_000
        return max(10_000, rounded)
    }



    private var progressGrouping: HealthProgressGrouping {
        switch period {
        case .week:
            return .day
        case .month, .threeMonths:
            return .week
        case .year:
            return .month
        }
    }

    private var progressRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()

        // Progress periods are rolling windows anchored to the current
        // moment. They must not reset at the start of a calendar
        // week/month/year; otherwise Monday would contain only Monday
        // and the first day of a month would contain only that day.
        let start: Date
        let previousStart: Date

        switch period {
        case .week:
            start =
                calendar.date(
                    byAdding: .day,
                    value: -7,
                    to: now
                ) ??
                now.addingTimeInterval(-604_800)
            previousStart =
                calendar.date(
                    byAdding: .day,
                    value: -7,
                    to: start
                ) ??
                start.addingTimeInterval(-604_800)

        case .month:
            start =
                calendar.date(
                    byAdding: .month,
                    value: -1,
                    to: now
                ) ??
                now.addingTimeInterval(-2_592_000)
            previousStart =
                calendar.date(
                    byAdding: .month,
                    value: -1,
                    to: start
                ) ??
                start.addingTimeInterval(-2_592_000)

        case .threeMonths:
            start =
                calendar.date(
                    byAdding: .month,
                    value: -3,
                    to: now
                ) ??
                now.addingTimeInterval(-7_776_000)
            previousStart =
                calendar.date(
                    byAdding: .month,
                    value: -3,
                    to: start
                ) ??
                start.addingTimeInterval(-7_776_000)

        case .year:
            start =
                calendar.date(
                    byAdding: .year,
                    value: -1,
                    to: now
                ) ??
                now.addingTimeInterval(-31_536_000)
            previousStart =
                calendar.date(
                    byAdding: .year,
                    value: -1,
                    to: start
                ) ??
                start.addingTimeInterval(-31_536_000)
        }

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: start
        )
    }

    private var selectedPeriodWorkouts: (runs: [WorkoutSummary], lifts: [StrengthWorkoutLog]) {
        let signpost = ATHLTHPerformance.begin("ProgressPeriodProjection")
        defer { ATHLTHPerformance.end("ProgressPeriodProjection", id: signpost) }
        let range = progressRange
        let runs = workoutHistory.filter {
            $0.activity == .running &&
            $0.startDate >= range.start &&
            $0.startDate <= range.end
        }
        let lifts = strengthWorkout.workoutHistory.filter {
            $0.isFinished &&
            $0.startedAt >= range.start &&
            $0.startedAt <= range.end
        }
        return (runs, lifts)
    }

    private var consistencyRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-7_776_000)
        let previousStart = calendar.date(byAdding: .day, value: -90, to: start)
            ?? start.addingTimeInterval(-7_776_000)

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: start
        )
    }

    private func loadSupportingProgressData() async {
        let performanceID =
            ATHLTHPerformance.begin("ProgressSupportingData")
        defer {
            ATHLTHPerformance.end(
                "ProgressSupportingData",
                id: performanceID
            )
        }

        guard health.healthDataAvailable,
              health.hasRequestedAuthorization
        else {
            consistencySnapshot = nil
            personalRecords = []
            workoutHistory = []
            return
        }

        let consistency = consistencyRange

        async let consistencyData = health.progressSnapshot(
            startDate: consistency.start,
            endDate: consistency.end,
            previousStartDate: consistency.previousStart,
            previousEndDate: consistency.previousEnd,
            grouping: .day
        )

        // Load the shared workout history once. personalRecords() then reuses
        // HealthKitManager's historical cache instead of issuing a second
        // unbounded workout query at the same time.
        workoutHistory =
            (try? await health.workoutHistory()) ?? []
        personalRecords =
            (try? await health.personalRecords()) ?? []
        consistencySnapshot = try? await consistencyData
    }

    private func loadProgressData() async {
        let performanceID =
            ATHLTHPerformance.begin("ProgressRangeLoad")
        defer {
            ATHLTHPerformance.end(
                "ProgressRangeLoad",
                id: performanceID
            )
        }

        guard health.healthDataAvailable else {
            progressSnapshot = nil
            progressError = "Apple Health is unavailable on this device."
            return
        }

        guard health.hasRequestedAuthorization else {
            progressSnapshot = nil
            progressError = ATHLTHLocalization.choose(
                english: "Review Apple Health access to show health-based progress.",
                norwegian: "Gjennomgå Apple Health-tilgang for å vise helsebasert fremgang."
            )
            return
        }

        progressLoading = true
        progressError = nil
        defer { progressLoading = false }

        let range = progressRange

        do {
            progressSnapshot = try await health.progressSnapshot(
                startDate: range.start,
                endDate: range.end,
                previousStartDate: range.previousStart,
                previousEndDate: range.previousEnd,
                grouping: progressGrouping
            )
        } catch {
            progressSnapshot = nil
            progressError = error.localizedDescription
        }
    }

    private func recordRow(
        _ title: String,
        value: String,
        date: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(date)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.caption.weight(.bold))
        }
    }



}
