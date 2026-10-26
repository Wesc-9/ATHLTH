import SwiftUI
import Charts

/// Recorded history with explicit source boundaries. Planning estimates are
/// never promoted to measurements or synthetic fitness scores.
struct ATHLTHTrainProgressReferenceView<Header: View>: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var phone: IPhoneWorkoutStore
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onReturnToToday: () -> Void
    let onOpenPlan: () -> Void
    let header: Header

    @State private var area: Area = .general
    @State private var period: Period = .threeMonths
    @State private var snapshot: HealthProgressSnapshot?
    @State private var allHealthWorkouts: [WorkoutSummary] = []
    @State private var healthRecords: [HealthPersonalRecord] = []
    @State private var isLoading = false
    @State private var historyRequestID = UUID()
    @State private var periodRequestID = UUID()
    @State private var historyAccountID: UUID?
    @State private var isHistoryLoading = true
    @State private var isHistoryLimited = false
    @ScaledMetric(relativeTo: .body) private var metricWidth: CGFloat = 130
    @ScaledMetric(relativeTo: .largeTitle) private var heroFigureSize: CGFloat = 54

    private struct HistoryRequest: Equatable {
        let accountID: UUID
        let healthWorkouts: [WorkoutSummary]
    }

    private struct PeriodRequest: Equatable {
        let accountID: UUID
        let period: Period
    }

    private enum Area: String, CaseIterable, Identifiable {
        case general, running, strength
        var id: Self { self }
        var title: String {
            switch self {
            case .general: return ATHLTHLocalization.choose(english: "All training", norwegian: "All trening")
            case .running: return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
            case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
            }
        }
    }

    private enum Period: String, CaseIterable, Identifiable {
        case week, month, threeMonths, year
        var id: Self { self }
        var title: String {
            switch self {
            case .week: return ATHLTHLocalization.choose(english: "7 days", norwegian: "7 dager")
            case .month: return ATHLTHLocalization.choose(english: "1 month", norwegian: "1 måned")
            case .threeMonths: return ATHLTHLocalization.choose(english: "Last 3 months", norwegian: "Siste 3 mnd")
            case .year: return ATHLTHLocalization.choose(english: "1 year", norwegian: "1 år")
            }
        }
        var start: Date {
            let calendar = Calendar.current
            switch self {
            case .week: return calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
            case .month: return calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
            case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: .now) ?? .now
            case .year: return calendar.date(byAdding: .year, value: -1, to: .now) ?? .now
            }
        }
        var grouping: HealthProgressGrouping {
            switch self {
            case .week: return .day
            case .month, .threeMonths: return .week
            case .year: return .month
            }
        }
    }

    private struct Stat: Identifiable {
        let label: String
        let value: String
        let icon: String
        let change: Double?
        var id: String { label }
    }

    private struct LiftPoint: Identifiable {
        let name: String
        let month: Date
        let kg: Double
        var id: String { name + month.description }
    }

    private struct RecentSession: Identifiable {
        let id: String
        let date: Date
        let icon: String
        let title: String
        let subtitle: String
        let value: String
    }

    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let positive = ATHLTHTheme.vitality

    private var rangeWorkouts: [WorkoutSummary] {
        allHealthWorkouts.filter { $0.startDate >= period.start && $0.startDate <= .now }
    }
    private var runs: [WorkoutSummary] {
        rangeWorkouts.filter { $0.activity == .running }
            .sorted { $0.startDate > $1.startDate }
    }
    private var lifts: [StrengthWorkoutLog] {
        strength.workoutHistory.filter {
            $0.isFinished && $0.startedAt >= period.start && $0.startedAt <= .now
        }
        .sorted { $0.startedAt > $1.startedAt }
    }
    private var completedPhoneWorkouts: [PhoneWorkout] {
        phone.history.filter {
            $0.end != nil && $0.start >= period.start && $0.start <= .now
        }
    }
    private var unlinkedLocalKeys: Set<String> {
        let records = lifts.map {
            ATHLTHRecordedWorkoutIndex.LocalRecord(
                key: "strength-" + $0.id.uuidString,
                healthID: $0.healthMetrics.healthKitWorkoutUUID)
        } + completedPhoneWorkouts.map {
            ATHLTHRecordedWorkoutIndex.LocalRecord(
                key: "phone-" + $0.id.uuidString, healthID: $0.healthID)
        }
        return ATHLTHRecordedWorkoutIndex.unlinkedKeys(
            healthIDs: Set(allHealthWorkouts.map(\.id)), localRecords: records)
    }
    private var unlinkedLifts: [StrengthWorkoutLog] {
        let keys = unlinkedLocalKeys
        return lifts.filter { keys.contains("strength-" + $0.id.uuidString) }
    }
    private var unlinkedPhoneWorkouts: [PhoneWorkout] {
        let keys = unlinkedLocalKeys
        return completedPhoneWorkouts.filter { keys.contains("phone-" + $0.id.uuidString) }
    }
    private var generalCount: Int {
        rangeWorkouts.count + unlinkedLifts.count + unlinkedPhoneWorkouts.count
    }
    private var runningDistance: Double {
        runs.compactMap(\.distanceMeters).reduce(0, +) / 1_000
    }
    private var runTime: TimeInterval { runs.reduce(0) { $0 + $1.duration } }
    private var generalDuration: TimeInterval {
        rangeWorkouts.reduce(0) { $0 + $1.duration } +
        unlinkedLifts.reduce(0) {
            $0 + max(($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt), 0)
        } + unlinkedPhoneWorkouts.reduce(0) {
            $0 + max($1.elapsed(at: $1.end ?? $1.start), 0)
        }
    }
    private var runningPace: Double? {
        let eligible = runs.filter { ($0.distanceMeters ?? 0) >= 500 && $0.duration > 0 }
        let distance = eligible.compactMap(\.distanceMeters).reduce(0, +)
        let duration = eligible.reduce(0) { $0 + $1.duration }
        guard distance > 0 else { return nil }
        let seconds = duration / (distance / 1_000)
        return (120.0...1_200.0).contains(seconds) ? seconds : nil
    }
    private var strengthVolume: Double { lifts.reduce(0) { $0 + $1.totalVolumeKilograms } }
    private var strengthSets: Int { lifts.reduce(0) { $0 + $1.totalWorkingSets } }
    private var recentSessions: [RecentSession] {
        let recorded = rangeWorkouts.map { workout in
            RecentSession(
                id: "health-" + workout.id.uuidString,
                date: workout.startDate,
                icon: workout.activity.icon,
                title: workout.activity == .running
                    ? tr("Running", "Løping")
                    : workout.activity == .strength
                        ? tr("Strength", "Styrke")
                        : workout.activity.rawValue,
                subtitle: workout.startDate.formatted(date: .abbreviated, time: .omitted),
                value: workout.activity == .running
                    ? workout.paceMinutesPerKilometer.map { paceText($0 * 60) } ?? workout.duration.shortDuration
                    : workout.duration.shortDuration
            )
        }
        let strengthOnly = unlinkedLifts.map { workout in
            RecentSession(
                id: "strength-" + workout.id.uuidString,
                date: workout.startedAt,
                icon: "dumbbell",
                title: workout.title,
                subtitle: workout.startedAt.formatted(date: .abbreviated, time: .omitted),
                value: String(format: "%.0f kg", workout.totalVolumeKilograms)
            )
        }
        let phoneOnly = unlinkedPhoneWorkouts.map { workout in
            RecentSession(
                id: "phone-" + workout.id.uuidString,
                date: workout.start,
                icon: workout.walking ? "figure.walk" : "figure.run",
                title: workout.workoutTitle ?? (workout.walking
                    ? tr("Walking", "Gåing") : tr("Running", "Løping")),
                subtitle: workout.start.formatted(date: .abbreviated, time: .omitted)
                    + " · " + tr("Stored on iPhone", "Lagret på iPhone"),
                value: workout.elapsed(at: workout.end ?? workout.start).shortDuration
            )
        }
        return (recorded + strengthOnly + phoneOnly).sorted { $0.date > $1.date }
    }

    private var runningRecords: [HealthPersonalRecord] {
        healthRecords.filter {
            $0.kind == .longestRun ||
            $0.kind == .bestRunningAveragePace ||
            $0.kind.rawValue.hasPrefix("fastest")
        }
    }
    private var timeDescription: String {
        period.title
    }
    private var totalCalories: Double {
        rangeWorkouts.compactMap(\.activeEnergyKilocalories).reduce(0, +)
    }
    private var strengthExerciseCount: Int {
        Set(lifts.flatMap { $0.exercises.map { $0.exercise.name.lowercased() } }).count
    }
    private var heroValue: String {
        if isHistoryLoading && area != .strength { return "—" }
        switch area {
        case .general: return String(generalCount)
        case .running: return String(format: "%.1f", runningDistance)
        case .strength:
            return strengthVolume >= 1_000
                ? String(format: "%.1f", strengthVolume / 1_000)
                : String(Int(strengthVolume.rounded()))
        }
    }
    private var heroUnit: String {
        switch area {
        case .general: return ATHLTHLocalization.choose(english: "RECORDED SESSIONS", norwegian: "REGISTRERTE ØKTER")
        case .running: return ATHLTHLocalization.choose(english: "DISTANCE · KM", norwegian: "DISTANSE · KM")
        case .strength:
            return strengthVolume >= 1_000
                ? ATHLTHLocalization.choose(english: "TRAINING VOLUME · TONNES", norwegian: "TRENING—VOLUM · TONN")
                : ATHLTHLocalization.choose(english: "TRAINING VOLUME · KG", norwegian: "TRENING—VOLUM · KG")
        }
    }
    private var heroSubline: String {
        if isHistoryLoading && area != .strength {
            return tr("Loading recorded history", "Henter registrert historikk")
        }
        switch area {
        case .general:
            return ATHLTHLocalization.choose(english: "Completed in selected period", norwegian: "Gjennomført i valgt periode")
        case .running:
            return ATHLTHLocalization.choose(english: "\(runs.count) runs in Apple Health", norwegian: "\(runs.count) løpeøkter i Apple Health")
        case .strength:
            return ATHLTHLocalization.choose(english: "\(lifts.count) completed strength sessions", norwegian: "\(lifts.count) fullførte styrkeøkter")
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ATHLTHTrainDesign.sectionSpacing) {
                header
                hero
                areaPicker
                    .padding(.bottom, 3)

                if isHistoryLimited {
                    Label(tr("Some history could not be loaded. Pull down to try again.",
                             "Noe historikk kunne ikke hentes. Dra ned for å prøve igjen."),
                          systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .fixedSize(horizontal: false, vertical: true)
                }

                statsCard

                switch area {
                case .general:
                    generalContent
                case .running:
                    runningContent
                case .strength:
                    strengthContent
                }

                if isLoading || isHistoryLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }

                Text(ATHLTHLocalization.choose(
                    english: "Overview includes Apple Health and completed local ATHLTH sessions. Running charts and calories use Apple Health. Strength loads are entered by you; planned duration is an estimate.",
                    norwegian: "Oversikten inkluderer Apple Health og fullførte lokale ATHLTH-økter. Løpegrafer og kalorier bruker Apple Health. Styrkevekter registreres av deg; planlagt varighet er et estimat."
                ))
                .font(.system(size: 11))
                .foregroundStyle(muted)
                .padding(.horizontal, 5)
                .padding(.top, 4)
            }
            .padding(.horizontal, 15)
            .padding(.top, 18)
            .padding(.bottom, 34)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
        .refreshable {
            await refreshAll()
        }
        .task(id: PeriodRequest(accountID: session.profile.userID, period: period)) {
            await loadPeriod()
        }
        .task(id: HistoryRequest(accountID: session.profile.userID,
                                 healthWorkouts: health.workouts)) {
            await loadHistory()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("YOUR TRAINING", "TRENINGEN DIN"))
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Text(tr("Progress", "Fremdrift"))
                        .font(.system(size: 38, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Text(tr("Your development, in one place", "Din utvikling, samlet på ett sted"))
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer(minLength: 8)
                Menu {
                    Picker(tr("Period", "Periode"), selection: $period) {
                        ForEach(Period.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(timeDescription, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(heroValue)
                    .font(.system(size: heroFigureSize, weight: .light, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                Text(heroUnit)
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(heroSubline)
                    .font(.subheadline)
                    .foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .referenceProgressCard()
        }
    }
    private var areaPicker: some View {
        HStack(spacing: 3) {
            ForEach(Area.allCases) { selection in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.20)) {
                        area = selection
                    }
                } label: {
                    Text(selection.title)
                        .font(.system(size: 13, weight: area == selection ? .semibold : .medium))
                        .foregroundStyle(area == selection ? Color.white : ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            area == selection ? ATHLTHTheme.accentDeep : Color.clear,
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(area == selection ? .isSelected : [])
            }
        }
        .padding(4)
        .background(ATHLTHTheme.champagneSoft, in: RoundedRectangle(cornerRadius: 17))
    }
    private var activeStats: [Stat] {
        switch area {
        case .general:
            return [
                Stat(label: tr("Sessions", "Økter"), value: "\(generalCount)", icon: "calendar", change: nil),
                Stat(label: tr("Training time", "Treningstid"), value: generalDuration.shortDuration, icon: "clock", change: nil),
                Stat(label: tr("Calories", "Kalorier"), value: totalCalories > 0 ? "\(Int(totalCalories.rounded()).formatted())" : "—", icon: "flame", change: nil),
                Stat(label: tr("Distance", "Distanse"), value: String(format: "%.1f km", rangeWorkouts.compactMap(\.distanceMeters).reduce(0, +) / 1_000), icon: "location", change: snapshot?.workoutDistanceChangePercent)
            ]
        case .running:
            return [
                Stat(label: tr("Runs", "Løpeøkter"), value: "\(runs.count)", icon: "figure.run", change: nil),
                Stat(label: tr("Distance", "Distanse"), value: String(format: "%.1f km", runningDistance), icon: "location", change: nil),
                Stat(label: tr("Average pace", "Snittempo"), value: runningPace.map(paceText) ?? "—", icon: "stopwatch", change: nil),
                Stat(label: tr("Running time", "Løpetid"), value: runTime.shortDuration, icon: "clock", change: nil)
            ]
        case .strength:
            return [
                Stat(label: tr("Strength sessions", "Styrkeøkter"), value: "\(lifts.count)", icon: "dumbbell", change: nil),
                Stat(label: tr("Volume", "Treningsvolum"), value: strengthVolume >= 1000 ? String(format: "%.1f t", strengthVolume / 1000) : "\(Int(strengthVolume.rounded())) kg", icon: "chart.bar", change: nil),
                Stat(label: tr("Working sets", "Arbeidssett"), value: "\(strengthSets)", icon: "square.stack.3d.up", change: nil),
                Stat(label: tr("Exercises", "Øvelser"), value: "\(strengthExerciseCount)", icon: "figure.strengthtraining.traditional", change: nil)
            ]
        }
    }

    private var statsCard: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(activeStats) { item in
                VStack(alignment: .leading, spacing: 11) {
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    Text(isHistoryLoading && area != .strength ? "—" : item.value)
                        .font(.system(size: 27, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(muted)
                    if !isHistoryLoading, let change = item.change, change.isFinite {
                        Text(String(format: "%+.0f%%", change))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                .padding(15)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 19))
                .overlay {
                    RoundedRectangle(cornerRadius: 19)
                        .stroke(ATHLTHTheme.premiumGold.opacity(0.2), lineWidth: 0.8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
    private var generalTrainingTrend: some View {
        section(
            title: tr("Training development", "Treningsutvikling"),
            subtitle: tr("Recorded training hours by period", "Registrerte treningstimer per periode")
        ) {
            if let snapshot, !snapshot.buckets.isEmpty {
                Chart(snapshot.buckets) { bucket in
                    AreaMark(
                        x: .value("Dato", bucket.startDate),
                        y: .value("Timer", bucket.trainingDuration / 3_600)
                    )
                    .foregroundStyle(ATHLTHTheme.champagneSoft.opacity(0.7))
                    LineMark(
                        x: .value("Dato", bucket.startDate),
                        y: .value("Timer", bucket.trainingDuration / 3_600)
                    )
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 185)
            } else {
                emptyLine(tr(
                    "Recorded sessions will appear in your trend.",
                    "Registrerte økter vises i utviklingsgrafen."
                ))
            }
        }
    }

    private var generalContent: some View {
        VStack(spacing: 12) {
            generalTrainingTrend
            section(
                title: tr("Body & health", "Kropp & helse"),
                subtitle: tr("Latest health data · readiness is an estimate", "Siste helsedata · dagsform er et estimat")
            ) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: metricWidth))],
                          alignment: .leading, spacing: 18) {
                    healthMetric(tr("Sleep", "Søvn"),
                                 value: health.sleep.totalAsleep > 0 ? health.sleep.totalAsleep.shortDuration : "—",
                                 icon: "moon")
                    healthMetric("HRV",
                                 value: health.heart.hrvMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "—",
                                 icon: "heart")
                    healthMetric(tr("Resting HR", "Hvilepuls"),
                                 value: health.heart.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—",
                                 icon: "heart.text.square")
                    healthMetric(tr("Readiness", "Dagsform"),
                                 value: health.recovery.score.map { String($0) } ?? "—",
                                 icon: "waveform.path.ecg")
                }
            }

            NavigationLink {
                ProgressPersonalRecordsView(
                    healthRecords: healthRecords,
                    strengthRecords: strength.personalRecords,
                    repRecords: strength.repPersonalRecords
                )
            } label: {
                section(
                    title: tr("Personal records", "Personlige rekorder"),
                    subtitle: tr("All-time records", "Rekorder fra hele historikken"),
                    accessory: tr("See all", "Se alle")
                ) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metricWidth))],
                              alignment: .leading, spacing: 18) {
                        recordTile(
                            title: tr("Running", "Løping"),
                            value: runningRecords.first?.formattedValue ?? "—",
                            detail: runningRecords.first?.kind.title ?? tr("No record yet", "Ingen rekord ennå"),
                            icon: "figure.run"
                        )
                        recordTile(
                            title: tr("Strength", "Styrke"),
                            value: strength.personalRecords.first?.value ?? "—",
                            detail: strength.personalRecords.first?.title ?? tr("No record yet", "Ingen rekord ennå"),
                            icon: "dumbbell"
                        )
                    }
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                WorkoutHistoryView(startDate: period.start, endDate: .now)
            } label: {
                section(
                    title: tr("Recent sessions", "Siste økter"),
                    accessory: tr("See all", "Se alle")
                ) {
                    if recentSessions.isEmpty {
                        emptyLine(tr("Completed workouts will appear here.", "Fullførte økter vises her."))
                    } else {
                        ForEach(recentSessions.prefix(3)) { item in
                            compactRow(
                                icon: item.icon,
                                title: item.title,
                                subtitle: item.subtitle,
                                value: item.value
                            )
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            ATHLTHTrainAchievementsView(startDate: period.start)

            if let active = session.activePlan {
                Button(action: onOpenPlan) {
                    HStack {
                        Label(tr("Plan progress", "Fremgang i treningsplan"), systemImage: "calendar")
                        Spacer()
                        Text(active.title).lineLimit(1)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(ink)
                    .padding(18)
                    .referenceProgressCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pacePoints: [ATHLTHTrainProgressPaceChartView.Sample] {
        runs.compactMap { workout in
            guard let km = workout.distanceKilometers, km >= 0.5,
                  workout.duration > 0 else { return nil }
            let seconds = workout.duration / km
            guard (120.0...1_200.0).contains(seconds) else { return nil }
            return ATHLTHTrainProgressPaceChartView.Sample(
                id: workout.id, date: workout.startDate,
                minutesPerKilometer: seconds / 60
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var runningContent: some View {
        VStack(spacing: 12) {
            section(
                title: tr("Average pace development", "Utvikling i snittempo"),
                subtitle: tr("Apple Health runs · min/km", "Løpeøkter fra Apple Health · min/km")
            ) {
                if pacePoints.isEmpty {
                    emptyLine(tr("Record a run to see your pace trend.", "Registrer en løpeøkt for å se tempoutviklingen."))
                } else {
                    ATHLTHTrainProgressPaceChartView(samples: pacePoints)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                NavigationLink {
                    RunningProgressDetailView(workouts: runs, records: runningRecords)
                } label: {
                    section(title: tr("Key sessions", "Nøkkeløkter"),
                            accessory: tr("See all", "Se alle")) {
                        if runs.isEmpty {
                            emptyLine(tr("No runs yet", "Ingen løpeøkter ennå"))
                        } else {
                            ForEach(runs.prefix(3)) { run in
                                compactRow(
                                    icon: "figure.run",
                                    title: run.isIndoor == true
                                        ? tr("Indoor run", "Løping inne")
                                        : tr("Running", "Løping"),
                                    subtitle: run.startDate.formatted(date: .abbreviated, time: .omitted),
                                    value: run.distanceKilometers.map { String(format: "%.1f km", $0) } ?? run.duration.shortDuration
                                )
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ProgressPersonalRecordsView(
                        healthRecords: runningRecords,
                        strengthRecords: [],
                        repRecords: []
                    )
                } label: {
                    section(title: tr("Personal records", "Personlige rekorder"),
                            subtitle: tr("All-time records", "Rekorder fra hele historikken"),
                            accessory: tr("See all", "Se alle")) {
                        if runningRecords.isEmpty {
                            emptyLine(tr("No running records yet", "Ingen løperekorder ennå"))
                        } else {
                            ForEach(runningRecords.prefix(3)) { record in
                                recordLine(record.kind.title, value: record.formattedValue)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            section(title: tr("Recent workouts", "Siste økter")) {
                if runs.isEmpty {
                    emptyLine(tr("No runs in this period", "Ingen løpeøkter i perioden"))
                } else {
                    ForEach(runs.prefix(5)) { run in
                        compactRow(
                            icon: "figure.run",
                            title: run.isIndoor == true ? tr("Indoor run", "Løping inne") : tr("Running", "Løping"),
                            subtitle: run.startDate.formatted(date: .abbreviated, time: .omitted),
                            value: run.distanceKilometers.map { String(format: "%.1f km", $0) } ?? run.duration.shortDuration
                        )
                    }
                }
            }
            ATHLTHRunningSpeedProgressCard()
        }
    }

    private var liftPoints: [LiftPoint] {
        let calendar = Calendar.current
        let byExercise = lifts.flatMap { log in
            log.exercises.flatMap { exercise in
                exercise.sets.compactMap { set -> (String, Date, Double)? in
                    guard set.countsTowardTrainingLoad,
                          let weight = set.completedWeightKilograms,
                          weight > 0 else { return nil }
                    return (exercise.exercise.name, log.startedAt, weight)
                }
            }
        }
        let popular = Dictionary(grouping: byExercise, by: { $0.0.lowercased() })
            .sorted { $0.value.count > $1.value.count }
            .prefix(4)
            .map(\.key)
        let filtered = byExercise.filter { popular.contains($0.0.lowercased()) }
        let grouped = Dictionary(grouping: filtered) {
            "\($0.0.lowercased())|\(calendar.dateInterval(of: .month, for: $0.1)?.start.timeIntervalSince1970 ?? 0)"
        }
        return grouped.values.compactMap { group -> LiftPoint? in
            guard let first = group.first,
                  let date = calendar.dateInterval(of: .month, for: first.1)?.start,
                  let peak = group.map(\.2).max() else { return nil }
            return LiftPoint(name: first.0, month: date, kg: peak)
        }
        .sorted { $0.month < $1.month }
    }

    private var strengthContent: some View {
        VStack(spacing: 12) {
            section(
                title: tr("Main lift development", "Utvikling i hovedløft"),
                subtitle: tr("Highest completed working weight per month · kg", "Tyngste fullførte arbeidsvekt per måned · kg")
            ) {
                if liftPoints.isEmpty {
                    emptyLine(tr("Complete weighted sets to see your lift history.", "Fullfør vektsett for å se løfteutviklingen."))
                } else {
                    Chart(liftPoints) { point in
                        BarMark(
                            x: .value("Øvelse", point.name),
                            y: .value("kg", point.kg)
                        )
                        .position(by: .value("Måned", point.month))
                        .foregroundStyle(by: .value("Måned", point.month))
                        .cornerRadius(2)
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .chartXAxis {
                        AxisMarks { AxisValueLabel() }
                    }
                    .frame(height: 185)
                }
            }

            NavigationLink {
                StrengthProgressDetailView(
                    workouts: lifts,
                    records: strength.personalRecords,
                    repRecords: strength.repPersonalRecords
                )
            } label: {
                section(title: tr("Main lifts", "Hovedløft"),
                        accessory: tr("See all", "Se alle")) {
                    if liftPoints.isEmpty {
                        emptyLine(tr("Your exercises appear after completed sets.", "Øvelsene vises etter fullførte sett."))
                    } else {
                        let peak = Dictionary(grouping: liftPoints, by: \.name)
                            .compactMap { key, values -> (String, Double)? in
                                guard let weight = values.map(\.kg).max() else { return nil }
                                return (key, weight)
                            }
                            .sorted { $0.1 > $1.1 }
                        ForEach(Array(peak.indices.prefix(4)), id: \.self) { index in
                            let entry = peak[index]
                            compactRow(
                                icon: "dumbbell",
                                title: entry.0,
                                subtitle: tr("Heaviest completed set", "Tyngste fullførte sett"),
                                value: "\(Int(entry.1.rounded())) kg"
                            )
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                ProgressPersonalRecordsView(
                    healthRecords: [],
                    strengthRecords: strength.personalRecords,
                    repRecords: strength.repPersonalRecords
                )
            } label: {
                section(title: tr("Personal records", "Personlige rekorder"),
                        subtitle: tr("All-time records", "Rekorder fra hele historikken"),
                        accessory: tr("See all", "Se alle")) {
                    let records = strength.personalRecords
                    if records.isEmpty {
                        emptyLine(tr("No strength records yet", "Ingen styrkerekorder ennå"))
                    } else {
                        ForEach(records.prefix(3)) { record in
                            recordLine(record.title, value: record.value)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            latestStrengthSessions
        }
    }

    private var latestStrengthSessions: some View {
        NavigationLink {
            StrengthProgressDetailView(
                workouts: lifts,
                records: strength.personalRecords,
                repRecords: strength.repPersonalRecords
            )
        } label: {
            section(title: tr("Recent workouts", "Siste økter"),
                    accessory: tr("See all", "Se alle")) {
                if lifts.isEmpty {
                    emptyLine(tr("No strength workouts in this period", "Ingen styrkeøkter i perioden"))
                } else {
                    ForEach(lifts.prefix(5)) { lift in
                        compactRow(
                            icon: "dumbbell",
                            title: tr("Strength training", "Styrketrening"),
                            subtitle: lift.startedAt.formatted(date: .abbreviated, time: .omitted),
                            value: "\(lift.totalWorkingSets) " + tr("sets", "arbeidssett")
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(
        title: String,
        subtitle: String? = nil,
        accessory: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ATHLTHTrainDesign.sectionTitle)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                if let accessory {
                    HStack(spacing: 4) {
                        Text(accessory)
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .foregroundStyle(muted)
                }
            }
            content()
        }
        .padding(15)
        .referenceProgressCard()
    }

    private func healthMetric(_ title: String, value: String, icon: String) -> some View {
        ATHLTHTrainMetricTile(title: title, value: value, symbol: icon)
    }

    private func recordTile(title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(muted)
            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(.title2, design: .serif))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ATHLTHTrainDesign.paleGold.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .combine)
    }

    private func compactRow(icon: String, title: String, subtitle: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(ink.opacity(0.8))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(muted)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func recordLine(_ title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "trophy").foregroundStyle(ATHLTHTheme.premiumGold)
            Text(title).lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 12))
        .foregroundStyle(ink)
        .padding(.vertical, 6)
    }

    private func emptyLine(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(muted)
            .frame(maxWidth: .infinity, minHeight: 70)
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private func paceText(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        guard rounded > 0 else { return "—" }
        return String(format: "%d:%02d /km", rounded / 60, rounded % 60)
    }

    private func refreshAll() async {
        await loadHistory()
        await loadPeriod()
    }

    @MainActor
    private func loadHistory() async {
        let requestID = UUID()
        historyRequestID = requestID
        isHistoryLoading = true
        defer {
            if historyRequestID == requestID { isHistoryLoading = false }
        }
        let accountID = session.profile.userID
        if historyAccountID != accountID {
            allHealthWorkouts = []
            healthRecords = []
            historyAccountID = accountID
        }
        guard health.healthDataAvailable, health.hasRequestedAuthorization else {
            allHealthWorkouts = health.workouts
            healthRecords = []
            isHistoryLimited = false
            return
        }
        let loadedWorkouts = try? await health.workoutHistory()
        let workouts = loadedWorkouts ?? health.workouts
        guard !Task.isCancelled, historyRequestID == requestID,
              session.profile.userID == accountID else { return }
        let loadedRecords = try? await health.personalRecords()
        let records = loadedRecords ?? []
        guard !Task.isCancelled, historyRequestID == requestID,
              session.profile.userID == accountID else { return }
        allHealthWorkouts = workouts
        healthRecords = records
        isHistoryLimited = loadedWorkouts == nil || loadedRecords == nil
    }
    @MainActor
    private func loadPeriod() async {
        let requestID = UUID()
        periodRequestID = requestID
        snapshot = nil
        guard health.healthDataAvailable, health.hasRequestedAuthorization else {
            isLoading = false
            return
        }
        isLoading = true
        defer {
            if periodRequestID == requestID { isLoading = false }
        }
        let requestedPeriod = period
        let accountID = session.profile.userID
        let start = requestedPeriod.start
        let previousStart = Calendar.current.date(
            byAdding: .second,
            value: -Int(Date().timeIntervalSince(start)),
            to: start
        ) ?? start
        let result = try? await health.progressSnapshot(
            startDate: start,
            endDate: .now,
            previousStartDate: previousStart,
            previousEndDate: start,
            grouping: requestedPeriod.grouping
        )
        guard !Task.isCancelled, periodRequestID == requestID,
              period == requestedPeriod,
              session.profile.userID == accountID else { return }
        snapshot = result
    }
}

private extension View {
    func referenceProgressCard() -> some View {
        athlthTrainPaper()
    }
}
