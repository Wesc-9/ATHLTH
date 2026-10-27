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
    @Binding var scrollPosition: ScrollPosition

    @State private var area: Area = .general
    @State private var progressTab: ProgressTab = .overview
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
    @State private var measuredZoneSeconds = [Double](repeating: 0, count: 5)
    @State private var pulseZonesLoading = false
    @State private var zoneRequestID = UUID()
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


    private enum ProgressTab: String, CaseIterable, Identifiable {
        case overview, trends, records, zones, sessions
        var id: Self { self }
        var label: String {
            switch self {
            case .overview: return ATHLTHLocalization.choose(english: "Overview", norwegian: "Oversikt")
            case .trends: return ATHLTHLocalization.choose(english: "Trends", norwegian: "Trender")
            case .records: return ATHLTHLocalization.choose(english: "Records", norwegian: "Rekorder")
            case .zones: return ATHLTHLocalization.choose(english: "Zones", norwegian: "Soner")
            case .sessions: return ATHLTHLocalization.choose(english: "Sessions", norwegian: "Økter")
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
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                editorialHeading
                editorialBanner
                editorialNavigation
                if isHistoryLimited {
                    Label(tr("Some history could not be loaded. Pull to refresh.",
                             "Noe historikk kunne ikke hentes. Dra ned for å prøve igjen."),
                          systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                switch progressTab {
                case .overview:
                    editorialOverview
                case .trends:
                    editorialTrend
                    if area == .running { ATHLTHRunningSpeedProgressCard() }
                    if area == .strength { strengthContent }
                case .records:
                    editorialRecords
                case .zones:
                    pulseZoneCard
                case .sessions:
                    editorialSessions
                }
                if isLoading || isHistoryLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                Text(tr(
                    "Apple Health and completed ATHLTH workouts. Unavailable measurements are not estimated.",
                    "Apple Health og fullførte ATHLTH-økter. Manglende målinger blir ikke anslått."
                ))
                .font(.system(size: 10)).foregroundStyle(muted).padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: ATHLTHTrainDesign.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
        .refreshable { await refreshAll() }
        .task(id: area) { await loadPulseZones() }
        .task(id: PeriodRequest(accountID: session.profile.userID, period: period)) {
            await loadPeriod()
            await loadPulseZones()
        }
        .task(id: HistoryRequest(accountID: session.profile.userID,
                                 healthWorkouts: health.workouts)) {
            await loadHistory()
            await loadPulseZones()
        }
    }

    private var editorialHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tr("Progress", "Fremdrift"))
                    .font(.system(size: 39, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Menu {
                    Picker(tr("Training type", "Treningstype"), selection: $area) {
                        ForEach(Area.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(area.title).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        LinearGradient(colors: [ATHLTHTrainDesign.gold, ATHLTHTrainDesign.bronze],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                }
            }
            Text(tr("See your development. Build on what works.",
                    "Se utviklingen din. Bygg videre på det som fungerer."))
                .font(.system(size: 13))
                .foregroundStyle(muted)
        }
    }

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }
    private var weeklyValue: String {
        switch area {
        case .general:
            return "\(recentSessions.filter { $0.date >= weekStart }.count)"
        case .running:
            return String(format: "%.1f km",
                          runs.filter { $0.startDate >= weekStart }
                              .compactMap(\.distanceKilometers).reduce(0, +))
        case .strength:
            let kg = lifts.filter { $0.startedAt >= weekStart }
                .reduce(0.0) { $0 + $1.totalVolumeKilograms }
            return kg >= 1_000 ? String(format: "%.1f t", kg / 1_000)
                : String(format: "%.0f kg", kg)
        }
    }

    private var editorialBanner: some View {
        ZStack {
            GeometryReader { geometry in
                Image("ProgressHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            LinearGradient(colors: [
                ATHLTHTrainDesign.paper.opacity(0.97),
                ATHLTHTrainDesign.paper.opacity(0.82),
                ATHLTHTrainDesign.paleGold.opacity(0.46)
            ], startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 10) {
                Image(systemName: area == .running ? "figure.run" :
                      area == .strength ? "dumbbell" : "figure.mixed.cardio")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.78), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(area.title.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.6).foregroundStyle(muted)
                    Text(area == .running ? tr("Stronger runner", "Sterkere løper")
                         : area == .strength ? tr("Growing stronger", "Sterkere for hver økt")
                         : tr("Your training", "Treningen din"))
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(ink).lineLimit(2)
                        .minimumScaleFactor(0.74)
                    Text(tr("One session at a time.", "Utvikling, økt for økt."))
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("This week", "Denne uken"))
                        .font(.system(size: 9)).foregroundStyle(muted)
                    Text(isHistoryLoading && area != .strength ? "—" : weeklyValue)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .monospacedDigit().lineLimit(1)
                        .minimumScaleFactor(0.60)
                    Text(area == .general ? tr("sessions", "økter")
                         : area == .running ? tr("distance", "distanse")
                         : tr("volume", "volum"))
                        .font(.system(size: 9))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                .frame(width: 75, alignment: .leading)
                .padding(10)
                .background(.white.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 11))
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 109)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private var editorialNavigation: some View {
        HStack(spacing: 1) {
            ForEach(ProgressTab.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        progressTab = item
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 10, weight: progressTab == item ? .semibold : .medium))
                        .foregroundStyle(progressTab == item ? ink : muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 37)
                        .background {
                            if progressTab == item {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(progressTab == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(ATHLTHTrainDesign.paleGold.opacity(0.23),
                    in: RoundedRectangle(cornerRadius: 13))
    }

    private var editorialOverview: some View {
        VStack(spacing: 12) {
            editorialMetrics
            editorialTrend
            HStack(alignment: .top, spacing: 9) {
                editorialZonesPreview
                editorialRecordsPreview
            }
            editorialRecent
        }
    }


    private struct RunningTrendWeek: Identifiable {
        let date: Date
        let distanceKM: Double
        let paceSeconds: Double?
        var id: Date { date }
    }

    private var runningTrendWeeks: [RunningTrendWeek] {
        let granularity: Calendar.Component = period == .year ? .month : .weekOfYear
        let grouped = Dictionary(grouping: runs) { workout in
            Calendar.current.dateInterval(of: granularity, for: workout.startDate)?.start
                ?? Calendar.current.startOfDay(for: workout.startDate)
        }
        return grouped.map { date, workouts in
            let distance = workouts.compactMap(\.distanceMeters).reduce(0, +)
            let duration = workouts.reduce(0.0) { $0 + $1.duration }
            let pace = distance >= 500 ? duration / (distance / 1_000) : 0
            return RunningTrendWeek(
                date: date,
                distanceKM: distance / 1_000,
                paceSeconds: (120.0...1_200.0).contains(pace) ? pace : nil
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var visibleRecentSessions: [RecentSession] {
        switch area {
        case .general: return recentSessions
        case .running:
            let ids = Set(
                runs.map { "health-" + $0.id.uuidString } +
                unlinkedPhoneWorkouts.filter { !$0.walking }
                    .map { "phone-" + $0.id.uuidString }
            )
            return recentSessions.filter { ids.contains($0.id) }
        case .strength:
            let ids = Set(
                rangeWorkouts.filter { $0.activity == .strength }
                    .map { "health-" + $0.id.uuidString } +
                unlinkedLifts.map { "strength-" + $0.id.uuidString }
            )
            return recentSessions.filter { ids.contains($0.id) }
        }
    }

    private func sparkValues(_ stat: Stat) -> [Double] {
        if area == .running {
            return runs.sorted { $0.startDate < $1.startDate }.map { run in
                switch stat.icon {
                case "location": return (run.distanceMeters ?? 0) / 1_000
                case "clock": return run.duration / 3_600
                case "figure.run": return 1
                default: return 0
                }
            }
        }
        if area == .strength {
            return lifts.sorted { $0.startedAt < $1.startedAt }.map { lift in
                switch stat.icon {
                case "dumbbell": return 1
                case "chart.bar": return lift.totalVolumeKilograms
                case "square.stack.3d.up": return Double(lift.totalWorkingSets)
                case "figure.strengthtraining.traditional": return Double(lift.exercises.count)
                default: return 0
                }
            }
        }
        guard let snapshot else { return [] }
        return snapshot.buckets.map { bucket in
            switch stat.icon {
            case "clock": return bucket.trainingDuration / 3_600
            case "location": return bucket.workoutDistanceMeters / 1_000
            case "calendar": return Double(bucket.workoutCount)
            default: return 0
            }
        }
    }

        private var editorialMetrics: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(activeStats) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: item.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 28, height: 28)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.55),
                                    in: Circle())
                    Text(item.label)
                        .font(.system(size: 10))
                        .foregroundStyle(muted).lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(isHistoryLoading && area != .strength ? "—" : item.value)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(ink).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.56)
                    if !isHistoryLoading, let change = item.change, change.isFinite {
                        Text(String(format: "%+.0f%%", change))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(change >= 0 ? Color.green : Color.orange)
                    } else {
                        Text(" ").font(.system(size: 9))
                    }
                    let values = sparkValues(item)
                    if values.contains(where: { $0 > 0 }) {
                        Chart {
                            ForEach(values.indices, id: \.self) { index in
                                BarMark(x: .value("Periode", index),
                                        y: .value("Verdi", values[index]))
                                .foregroundStyle(ATHLTHTrainDesign.gold)
                                .cornerRadius(1)
                            }
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden)
                        .frame(height: 23)
                    } else {
                        Rectangle().fill(ATHLTHTrainDesign.paleGold.opacity(0.4))
                            .frame(height: 1).padding(.vertical, 11)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(ATHLTHTrainDesign.rule.opacity(0.35), lineWidth: 0.7)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var editorialTrend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(tr("Development", "Utvikling"))
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
                HStack(spacing: 1) {
                    ForEach([Period.month, .threeMonths, .year]) { option in
                        Button { period = option } label: {
                            Text(option == .month ? tr("4 weeks", "4 uker")
                                 : option == .threeMonths ? tr("12 weeks", "12 uker")
                                 : tr("1 year", "1 år"))
                                .font(.system(size: 10, weight: period == option ? .semibold : .regular))
                                .foregroundStyle(period == option ? ink : muted)
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 7)
                                .frame(height: 28)
                                .background {
                                    if period == option {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.white)
                                            .shadow(color: .black.opacity(0.05), radius: 4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(ATHLTHTrainDesign.canvas,
                            in: RoundedRectangle(cornerRadius: 9))
            }
            HStack(spacing: 14) {
                Label(area == .running ? tr("Pace", "Snittfart")
                      : tr("Training time", "Treningstid"), systemImage: "circle.fill")
                Label(area == .running ? tr("Distance", "Distanse")
                      : tr("Sessions", "Økter"), systemImage: "square.fill")
            }
            .font(.system(size: 9))
            .foregroundStyle(ATHLTHTrainDesign.bronze)
            .frame(maxWidth: .infinity, alignment: .trailing)

            if area == .running {
                if runningTrendWeeks.isEmpty {
                    emptyLine(tr("Record runs to see pace and distance.",
                                 "Registrer løpeøkter for å se fart og distanse."))
                } else {
                    let maximumDistance = max(
                        runningTrendWeeks.map(\.distanceKM).max() ?? 0, 1
                    )
                    Chart {
                        ForEach(runningTrendWeeks) { bucket in
                            BarMark(
                                x: .value("Dato", bucket.date),
                                y: .value("Relativ distanse", bucket.distanceKM / maximumDistance)
                            )
                            .foregroundStyle(ATHLTHTrainDesign.paleGold)
                            .cornerRadius(2)
                            if let pace = bucket.paceSeconds {
                                LineMark(
                                    x: .value("Dato", bucket.date),
                                    y: .value("Relativ fart", (1_200 - pace) / 1_080)
                                )
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                                .lineStyle(StrokeStyle(lineWidth: 2.2))
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Dato", bucket.date),
                                    y: .value("Relativ fart", (1_200 - pace) / 1_080)
                                )
                                .foregroundStyle(ATHLTHTrainDesign.gold)
                                .symbolSize(20)
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 170)
                    HStack(spacing: 12) {
                        Text(tr("Average pace", "Snittfart") + ": " +
                             (runningPace.map(paceText) ?? "—"))
                        Text(tr("Distance", "Distanse") + ": " +
                             String(format: "%.1f km", runningDistance))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    Text(tr("Pace and distance use independent relative scales.",
                            "Fart og distanse vises på hver sin relative skala."))
                        .font(.system(size: 9)).foregroundStyle(muted)
                }
            } else if area == .strength {
                if liftPoints.isEmpty {
                    emptyLine(tr("Complete weighted sets to see your progress.",
                                 "Fullfør vektsett for å se utviklingen."))
                } else {
                    Chart(liftPoints) { item in
                        BarMark(x: .value("Dato", item.month), y: .value("Kg", item.kg))
                            .foregroundStyle(ATHLTHTrainDesign.gold).cornerRadius(2)
                    }
                    .frame(height: 157)
                }
            } else if let snapshot, !snapshot.buckets.isEmpty {
                let maxHours = max(snapshot.buckets.map { $0.trainingDuration / 3_600 }.max() ?? 0, 1)
                let maxCount = max(snapshot.buckets.map { Double($0.workoutCount) }.max() ?? 0, 1)
                Chart(snapshot.buckets) { bucket in
                    BarMark(x: .value("Dato", bucket.startDate),
                            y: .value("Økter relativt", Double(bucket.workoutCount) / maxCount))
                        .foregroundStyle(ATHLTHTrainDesign.paleGold).cornerRadius(2)
                    LineMark(x: .value("Dato", bucket.startDate),
                             y: .value("Timer relativt", bucket.trainingDuration / 3_600 / maxHours))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Dato", bucket.startDate),
                              y: .value("Timer relativt", bucket.trainingDuration / 3_600 / maxHours))
                        .foregroundStyle(ATHLTHTrainDesign.gold)
                        .symbolSize(16)
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9))
                    }
                }
                .frame(height: 153)
                Text(tr("Hours and sessions · separate relative scales",
                        "Timer og økter · ulike relative skalaer"))
                    .font(.system(size: 9)).foregroundStyle(muted)
            } else {
                emptyLine(tr("Recorded development appears here.",
                             "Registrert utvikling vises her."))
            }
        }
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(ATHLTHTrainDesign.rule.opacity(0.4), lineWidth: 0.7)
        }
    }

    private func zoneColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color(red: 0.38, green: 0.67, blue: 0.55)
        case 1: return Color(red: 0.58, green: 0.74, blue: 0.48)
        case 2: return Color(red: 0.86, green: 0.70, blue: 0.35)
        case 3: return Color(red: 0.93, green: 0.55, blue: 0.34)
        default: return Color(red: 0.84, green: 0.34, blue: 0.29)
        }
    }

    private var editorialZonesPreview: some View {
        Button { progressTab = .zones } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(tr("Heart rate zones", "Pulssoner"))
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                let total = measuredZoneSeconds.reduce(0, +)
                if total > 0 {
                    Chart {
                        ForEach(0..<5, id: \.self) { index in
                            SectorMark(
                                angle: .value("Tid", measuredZoneSeconds[index]),
                                innerRadius: .ratio(0.67),
                                angularInset: 1
                            )
                            .foregroundStyle(zoneColor(index))
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 106)
                    .overlay {
                        if let most = measuredZoneSeconds.enumerated()
                            .max(by: { $0.element < $1.element }) {
                            VStack(spacing: 1) {
                                Text(String(format: "%.0f%%", most.element / total * 100))
                                    .font(.system(size: 17, weight: .medium, design: .serif))
                                Text(tr("zone", "sone") + " \(most.offset + 1)")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(ink)
                        }
                    }
                } else {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(ATHLTHTrainDesign.gold)
                        .frame(maxWidth: .infinity, minHeight: 106)
                }
                Text(total > 0 ? tr("View zone distribution", "Se sonefordelingen")
                     : tr("No measured zones yet", "Ingen målte soner ennå"))
                    .font(.system(size: 10)).foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(ATHLTHTrainDesign.rule.opacity(0.4), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var editorialRecordsPreview: some View {
        Button { progressTab = .records } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(tr("Best sessions", "Beste økter"))
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                if area != .strength && !runningRecords.isEmpty {
                    ForEach(runningRecords.prefix(3)) { item in
                        HStack(spacing: 5) {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(ATHLTHTrainDesign.gold)
                            Text(item.kind.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(item.formattedValue)
                                .lineLimit(1).minimumScaleFactor(0.72)
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(ink)
                        .frame(minHeight: 26)
                    }
                } else if area != .running, let item = strength.personalRecords.first {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).lineLimit(2)
                        Text(item.value).fontWeight(.semibold)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
                } else {
                    Text(tr("Your records will appear here.",
                            "Rekordene dine vises her."))
                        .font(.system(size: 10)).foregroundStyle(muted)
                        .frame(maxWidth: .infinity, minHeight: 98)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(ATHLTHTrainDesign.rule.opacity(0.4), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var editorialRecent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Recent sessions", "Siste økter"))
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Spacer()
                Button(tr("See all", "Se alle")) { progressTab = .sessions }
                    .font(.system(size: 11))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
            }
            if visibleRecentSessions.isEmpty {
                emptyLine(tr("Completed workouts appear here.",
                             "Fullførte økter vises her."))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(visibleRecentSessions.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 17))
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                    .frame(width: 30, height: 30)
                                    .background(ATHLTHTrainDesign.paleGold.opacity(0.5),
                                                in: RoundedRectangle(cornerRadius: 8))
                                Text(item.title).font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text(item.value).font(.system(size: 11, design: .serif))
                                    .lineLimit(1)
                                Text(item.subtitle).font(.system(size: 9))
                                    .foregroundStyle(muted).lineLimit(1)
                            }
                            .foregroundStyle(ink)
                            .frame(width: 112, alignment: .leading)
                            .padding(9)
                            .background(.white, in: RoundedRectangle(cornerRadius: 13))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .background(.white.opacity(0.73),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var editorialRecords: some View {
        VStack(spacing: 12) {
            NavigationLink {
                ProgressPersonalRecordsView(
                    healthRecords: area == .strength ? [] : healthRecords,
                    strengthRecords: area == .running ? [] : strength.personalRecords,
                    repRecords: area == .running ? [] : strength.repPersonalRecords
                )
            } label: {
                section(title: tr("Personal records", "Personlige rekorder"),
                        accessory: tr("See all", "Se alle")) {
                    if area != .strength {
                        ForEach(runningRecords.prefix(4)) { item in
                            recordLine(item.kind.title, value: item.formattedValue)
                        }
                    }
                    if area != .running {
                        ForEach(strength.personalRecords.prefix(4)) { item in
                            recordLine(item.title, value: item.value)
                        }
                    }
                    if runningRecords.isEmpty && strength.personalRecords.isEmpty {
                        emptyLine(tr("No personal records yet.",
                                     "Ingen personlige rekorder ennå."))
                    }
                }
            }
            .buttonStyle(.plain)
            ATHLTHTrainAchievementsView(startDate: period.start)
        }
    }

    private var editorialSessions: some View {
        VStack(spacing: 12) {
            NavigationLink {
                WorkoutHistoryView(startDate: period.start, endDate: .now)
            } label: {
                section(title: tr("Recent sessions", "Siste økter"),
                        accessory: tr("Full history", "Hele historikken")) {
                    if visibleRecentSessions.isEmpty {
                        emptyLine(tr("No workouts in this period", "Ingen økter i perioden"))
                    } else {
                        ForEach(visibleRecentSessions.prefix(12)) { item in
                            compactRow(icon: item.icon, title: item.title,
                                       subtitle: item.subtitle, value: item.value)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

        private func loadPulseZones() async {
        let requestID = UUID()
        zoneRequestID = requestID
        measuredZoneSeconds = [Double](repeating: 0, count: 5)
        guard let maximum = session.onboardingProfile?.maximumHeartRateBPM,
              (100...240).contains(maximum) else {
            pulseZonesLoading = false
            return
        }
        pulseZonesLoading = true
        let currentArea = area
        let currentStart = period.start
        let source: [WorkoutSummary] = allHealthWorkouts
            .filter { workout in
                workout.startDate >= currentStart &&
                workout.startDate <= Date() &&
                (currentArea == .general ||
                 (currentArea == .running && workout.activity == .running) ||
                 (currentArea == .strength && workout.activity == .strength))
            }
            .sorted { $0.startDate > $1.startDate }
        var totals = [Double](repeating: 0, count: 5)
        for workout in source.prefix(12) {
            if Task.isCancelled {
                if zoneRequestID == requestID { pulseZonesLoading = false }
                return
            }
            guard zoneRequestID == requestID else { return }
            let points = await health.runningHeartRateTimeline(for: workout.id)
            let durations = ATHLTHRunningHeartRateAnalysis.zoneDurations(
                points, maximumBPM: Double(maximum)
            )
            for duration in durations where (1...5).contains(duration.zone) {
                totals[duration.zone - 1] += duration.seconds
            }
        }
        guard zoneRequestID == requestID else { return }
        measuredZoneSeconds = totals
        pulseZonesLoading = false
    }

    private var pulseZoneCard: some View {
        section(
            title: tr("Heart rate zones", "Pulssoner"),
            subtitle: tr(
                "Measured Apple Health coverage · latest 12 sessions",
                "Målt tid fra Apple Health · inntil 12 siste økter"
            )
        ) {
            if pulseZonesLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if session.onboardingProfile?.maximumHeartRateBPM == nil {
                emptyLine(tr(
                    "Set your maximum heart rate in your profile to see measured zones.",
                    "Legg inn makspuls i profilen for å vise målte pulssoner."
                ))
            } else if measuredZoneSeconds.reduce(0, +) <= 0 {
                emptyLine(tr(
                    "No measured zone durations in this period.",
                    "Ingen målte pulssonetider i denne perioden."
                ))
            } else {
                let total = measuredZoneSeconds.reduce(0, +)
                VStack(spacing: 11) {
                    ForEach(1...5, id: \.self) { zone in
                        let fraction = total > 0 ? measuredZoneSeconds[zone - 1] / total : 0
                        HStack(spacing: 11) {
                            Text(tr("Zone", "Sone") + " \(zone)")
                                .font(.caption.weight(.semibold))
                                .frame(width: 56, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(ATHLTHTheme.champagneSoft)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(ATHLTHTheme.accentDeep)
                                            .frame(width: max(0, proxy.size.width * fraction))
                                    }
                            }
                            .frame(height: 9)
                            Text(String(format: "%.0f%%", fraction * 100))
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                        }
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .task(id: area) {
            await loadPulseZones()
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
            pulseZoneCard
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
                        ForEach(recentSessions.prefix(5)) { item in
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
            pulseZoneCard
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
            pulseZoneCard
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
