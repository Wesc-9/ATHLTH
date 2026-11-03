import SwiftUI
import Charts

/// One entry point, grouped by purpose rather than a wall of HealthKit data.
/// Cards are native views; the sample source remains local Apple Health.
struct ATHLTHInsightsHealthLibraryView: View {
    @EnvironmentObject private var health: HealthKitManager
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ATHLTHLocalization.choose(
                        english: "Your measurements", norwegian: "Dine helsemålinger"
                    ))
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    Text(ATHLTHLocalization.choose(
                        english: "Only measurements recorded in Apple Health. Open a metric for its history.",
                        norwegian: "Kun registrerte målinger fra Apple Health. Trykk på en måling for historikk."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                }
                .padding(.bottom, 5)

                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(ATHLTHInsightHealthArea.allCases) { area in
                    NavigationLink {
                        ATHLTHInsightsHealthAreaView(area: area)
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: area.icon)
                                .font(.title2.weight(.medium))
                                .foregroundStyle(ATHLTHInsightsStyle.accent)
                                .frame(width: 49, height: 49)
                                .background(ATHLTHInsightsStyle.accent.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(area.title)
                                    .font(.headline)
                                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                                Text(area.detail)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHInsightsStyle.muted)
                        }
                        .padding(15)
                        .athlthInsightsSurface()
                    }
                    .buttonStyle(.plain)
                    }
                } else {
                    let matches = ATHLTHInsightHealthMetric.allCases.filter {
                        $0.title.localizedCaseInsensitiveContains(searchText) ||
                        $0.area.title.localizedCaseInsensitiveContains(searchText)
                    }
                    ForEach(matches) { metric in
                        NavigationLink {
                            ATHLTHInsightsHealthMetricDetailView(metric: metric)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: metric.icon)
                                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(metric.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                                    Text(metric.area.title)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                            }
                            .padding(14)
                            .athlthInsightsSurface()
                        }
                        .buttonStyle(.plain)
                    }
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }

                Text(ATHLTHLocalization.choose(
                    english: "Data depends on your devices and Health permissions. Missing values are never estimated. These trends are not a diagnosis.",
                    norwegian: "Data avhenger av enheter og Helse-tillatelser. Manglende målinger estimeres ikke. Trendene er ikke en diagnose."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .padding(.vertical, 8)
            }
            .padding(17)
            .frame(maxWidth: ATHLTHTrainDesign.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHInsightsStyle.canvas.ignoresSafeArea())
        .navigationTitle(ATHLTHLocalization.choose(english: "Health", norwegian: "Helse"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(
            text: $searchText,
            prompt: ATHLTHLocalization.choose(
                english: "Search health measurements",
                norwegian: "Søk i helsemålinger"
            )
        )
    }
}

struct ATHLTHInsightsHealthAreaView: View {
    let area: ATHLTHInsightHealthArea
    @EnvironmentObject private var health: HealthKitManager
    @State private var latest: [ATHLTHInsightHealthMetric: Double] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 11) {
                    Image(systemName: area.icon)
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(area.title)
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                        Text(area.detail)
                            .font(.caption)
                            .foregroundStyle(ATHLTHInsightsStyle.muted)
                    }
                }
                .padding(.bottom, 8)

                if area == .sleep {
                    ATHLTHInsightsSleepStagesCard()
                }

                ForEach(ATHLTHInsightHealthMetric.allCases.filter { $0.area == area }) { metric in
                    NavigationLink {
                        ATHLTHInsightsHealthMetricDetailView(metric: metric)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: metric.icon)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHInsightsStyle.accent)
                                .frame(width: 31, height: 31)
                                .background(ATHLTHInsightsStyle.accent.opacity(0.09),
                                            in: RoundedRectangle(cornerRadius: 10))
                            Text(metric.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHInsightsStyle.ink)
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            Text(metric.formatted(
                                metric.currentValue(in: health) ?? latest[metric]
                            ))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHInsightsStyle.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.70)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(ATHLTHInsightsStyle.muted)
                        }
                        .padding(14)
                        .athlthInsightsSurface()
                    }
                    .buttonStyle(.plain)
                }
                Text(ATHLTHLocalization.choose(
                    english: "An em dash means no readable measurement. Open a card to retrieve its recorded history.",
                    norwegian: "En strek betyr at målingen ikke er tilgjengelig. Åpne kortet for å hente registrert historikk."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .padding(.top, 5)
            }
            .padding(17)
            .frame(maxWidth: ATHLTHTrainDesign.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHInsightsStyle.canvas.ignoresSafeArea())
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: area) {
            // Read only the opened category, never every Health type at
            // launch. This keeps new body and running metrics visible
            // without an extra tap into each detail chart.
            for metric in ATHLTHInsightHealthMetric.allCases where metric.area == area {
                guard !Task.isCancelled else { return }
                if metric.currentValue(in: health) != nil { continue }
                let samples = await health.insightDailyValues(for: metric, days: 30)
                guard !Task.isCancelled else { return }
                if let value = samples.last?.value {
                    latest[metric] = value
                }
            }
        }
    }
}

/// Tap-through history is loaded on demand, avoiding dozens of HealthKit queries
/// whenever Insight's main page opens.
struct ATHLTHInsightsHealthMetricDetailView: View {
    let metric: ATHLTHInsightHealthMetric
    @EnvironmentObject private var health: HealthKitManager
    @State private var period = 30
    @State private var values: [ATHLTHInsightHealthDay] = []
    @State private var loading = false
    @State private var attempted = false
    @State private var recoveryFullHistory: [ATHLTHInsightHealthDay] = []
    @State private var recoveryHistoryLoaded = false

    private var latest: Double? {
        let lastRecorded = metric == .heartRateRecovery
            ? recoveryFullHistory.last?.value
            : values.last?.value
        return lastRecorded ?? metric.currentValue(in: health)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 11) {
                    Label(metric.area.title, systemImage: metric.area.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                    Text(metric.title)
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                    Text(metric.formatted(latest))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                        .accessibilityLabel(metric.title + ": " + metric.formatted(latest))
                    if metric == .heartRateRecovery,
                       let recent = recoveryFullHistory.last {
                        Text(
                            recent.date.formatted(date: .abbreviated, time: .omitted) +
                            " · " +
                            (recent.isEstimated
                                ? ATHLTHLocalization.choose(
                                    english: "Calculated from recorded pulse",
                                    norwegian: "Beregnet fra registrert puls"
                                  )
                                : ATHLTHLocalization.choose(
                                    english: "Recorded in Apple Health",
                                    norwegian: "Registrert i Apple Helse"
                                  ))
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .athlthInsightsSurface()

                VStack(alignment: .leading, spacing: 13) {
                    Text(ATHLTHLocalization.choose(
                        english: "Recorded history", norwegian: "Registrert historikk"
                    ))
                    .font(.headline)
                    .foregroundStyle(ATHLTHInsightsStyle.ink)

                    Picker(ATHLTHLocalization.choose(
                        english: "Period", norwegian: "Periode"
                    ), selection: $period) {
                        Text("7d").tag(7)
                        Text("30d").tag(30)
                        Text("90d").tag(90)
                        Text("180d").tag(180)
                    }
                    .pickerStyle(.segmented)

                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 165)
                    } else if values.isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english: "No readings available",
                                norwegian: "Ingen målinger tilgjengelig"
                            ),
                            systemImage: "waveform.path.ecg",
                            description: Text(
                                metric == .heartRateRecovery
                                ? ATHLTHLocalization.choose(
                                    english: "A recorded recovery reading or pulse measurements at workout end and about one minute later are needed. Check Apple Health permissions and try a recorded workout.",
                                    norwegian: "Vi trenger registrert pulsfall eller pulsmålinger ved øktslutt og omtrent ett minutt senere. Kontroller Helse-tillatelser og prøv en registrert treningsøkt."
                                  )
                                : ATHLTHLocalization.choose(
                                    english: "This device may not record this metric, or Apple Health has no readable samples for this period.",
                                    norwegian: "Enheten registrerer kanskje ikke målingen, eller Apple Health har ingen lesbare data i denne perioden."
                                  )
                            )
                        )
                        .frame(minHeight: 165)
                    } else {
                        Chart(values) { item in
                            if metric == .heartRateRecovery {
                                BarMark(
                                    x: .value("Dag", item.date),
                                    y: .value("Pulsfall", item.value)
                                )
                                .foregroundStyle(
                                    item.isEstimated
                                        ? ATHLTHInsightsStyle.muted.opacity(0.65)
                                        : ATHLTHInsightsStyle.accent
                                )
                                .cornerRadius(3)
                            } else if metric.cumulative {
                                BarMark(
                                    x: .value("Dag", item.date),
                                    y: .value("Verdi", item.value)
                                )
                                .foregroundStyle(ATHLTHInsightsStyle.accent)
                                .cornerRadius(3)
                            } else {
                                LineMark(
                                    x: .value("Dag", item.date),
                                    y: .value("Verdi", item.value)
                                )
                                .foregroundStyle(ATHLTHInsightsStyle.accent)
                                .interpolationMethod(.linear)
                                PointMark(
                                    x: .value("Dag", item.date),
                                    y: .value("Verdi", item.value)
                                )
                                .foregroundStyle(ATHLTHInsightsStyle.accent)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .frame(height: 185)
                        .accessibilityLabel(metric.title + ", " +
                            ATHLTHLocalization.choose(
                                english: "recorded values by day",
                                norwegian: "registrerte verdier per dag"
                            ))
                        Text(ATHLTHLocalization.choose(
                            english: "\(values.count) days with measurements in this period",
                            norwegian: "\(values.count) dager med målinger i perioden"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                        if metric == .heartRateRecovery {
                            HStack(spacing: 14) {
                                Label {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Apple Health",
                                        norwegian: "Apple Helse"
                                    ))
                                } icon: {
                                    Circle()
                                        .fill(ATHLTHInsightsStyle.accent)
                                        .frame(width: 8, height: 8)
                                }
                                Label {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Calculated",
                                        norwegian: "Beregnet"
                                    ))
                                } icon: {
                                    Circle()
                                        .fill(ATHLTHInsightsStyle.muted.opacity(0.65))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(ATHLTHInsightsStyle.muted)
                        }
                    }
                }
                .padding(16)
                .athlthInsightsSurface()

                if metric == .heartRateRecovery {
                    Text(ATHLTHLocalization.choose(
                        english: "Apple Health's native value uses the exercise peak. When unavailable, ATHLTH calculates a separate one-minute drop from actual pulse near the workout end and about 60 seconds later. Calculated readings are marked and may differ. Missing readings are never estimated.",
                        norwegian: "Apples registrerte pulsfall måles fra treningens høyeste puls. Når det mangler, kan ATHLTH beregne et eget ettminutts pulsfall fra faktisk puls ved øktslutt og omtrent 60 sekunder senere. Beregnede verdier merkes og kan avvike. Manglende pulsmålinger gjettes aldri."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                }

                if metric.area == .sleep && metric != .sleepDuration {
                    Text(ATHLTHLocalization.choose(
                        english: "Sleep stages currently reflect the most recent recorded main sleep session, not estimated earlier nights.",
                        norwegian: "Søvnfasene gjelder foreløpig siste registrerte hovedsøvn, ikke estimerte tidligere netter."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                }

                Text(ATHLTHLocalization.choose(
                    english: "Apple Health · Values may differ by device and recording conditions. A single reading is not a medical diagnosis.",
                    norwegian: "Apple Health · Målinger varierer med enhet og registreringsforhold. En enkeltmåling er ikke en medisinsk diagnose."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
            .padding(17)
            .frame(maxWidth: ATHLTHTrainDesign.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHInsightsStyle.canvas.ignoresSafeArea())
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: period) {
            loading = true
            attempted = true

            if metric == .heartRateRecovery {
                if !recoveryHistoryLoaded {
                    let history = await health.insightDailyValues(
                        for: .heartRateRecovery, days: 180
                    )
                    guard !Task.isCancelled else { return }
                    recoveryFullHistory = history
                    recoveryHistoryLoaded = true
                }
                let start = Calendar.current.date(
                    byAdding: .day, value: -(period - 1),
                    to: Calendar.current.startOfDay(for: Date())
                ) ?? Date().addingTimeInterval(-Double(period) * 86_400)
                values = recoveryFullHistory.filter { $0.date >= start }
            } else {
                let result = await health.insightDailyValues(
                    for: metric, days: period
                )
                guard !Task.isCancelled else { return }
                values = result
            }
            loading = false
        }
    }
}

struct ATHLTHInsightsSleepStagesCard: View {
    @EnvironmentObject private var health: HealthKitManager

    private var stages: [(String, TimeInterval, Color)] {
        [
            (ATHLTHLocalization.choose(english: "Core", norwegian: "Kjerne"),
             health.sleep.core, Color(red: 0.75, green: 0.67, blue: 0.53)),
            (ATHLTHLocalization.choose(english: "Deep", norwegian: "Dyp"),
             health.sleep.deep, Color(red: 0.52, green: 0.49, blue: 0.45)),
            ("REM", health.sleep.rem, Color(red: 0.79, green: 0.80, blue: 0.78))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(ATHLTHLocalization.choose(
                english: "Last night's sleep stages", norwegian: "Siste søvns faser"
            ))
            .font(.headline)
            .foregroundStyle(ATHLTHInsightsStyle.ink)
            let total = stages.reduce(0.0) { $0 + $1.1 }
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(0..<stages.count, id: \.self) { index in
                            let stage = stages[index]
                            if stage.1 > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(stage.2)
                                    .frame(width: max(CGFloat.zero,
                                        (geo.size.width - 6) * CGFloat(stage.1 / total)))
                            }
                        }
                    }
                }
                .frame(height: 13)
                HStack(spacing: 10) {
                    ForEach(0..<stages.count, id: \.self) { index in
                            let stage = stages[index]
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stage.0)
                                .font(.caption2)
                                .foregroundStyle(ATHLTHInsightsStyle.muted)
                            Text("\(Int((stage.1 / 60).rounded())) min")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHInsightsStyle.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "No recorded sleep stages yet.",
                    norwegian: "Ingen registrerte søvnfaser ennå."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
        }
        .padding(15)
        .athlthInsightsSurface()
    }
}

/// Seven *completed* calendar days of ordinary activity, not a second
/// readiness card. Only actual Apple Health records are shown; a missing
/// measurement is distinct from a recorded value of zero.
struct ATHLTHInsightsDailyRhythmCard: View {
    @EnvironmentObject private var health: HealthKitManager
    @State private var stepsHistory: [ATHLTHInsightHealthDay] = []
    @State private var daylightHistory: [ATHLTHInsightHealthDay] = []
    @State private var exerciseHistory: [ATHLTHInsightHealthDay] = []
    @State private var isLoading = true

    private let calendar = Calendar.current

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var completedDays: [Date] {
        (-7 ... -1).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    private func measuredValue(
        on day: Date,
        in history: [ATHLTHInsightHealthDay]
    ) -> Double? {
        history.first(where: {
            calendar.isDate($0.date, inSameDayAs: day) &&
            $0.value.isFinite && $0.value >= 0
        })?.value
    }

    private func measurements(
        in history: [ATHLTHInsightHealthDay],
        fromOffset start: Int,
        throughOffset end: Int
    ) -> [Double] {
        (start ... end).compactMap { offset -> Double? in
            guard let date = calendar.date(
                byAdding: .day, value: offset, to: today
            ) else { return nil }
            return measuredValue(on: date, in: history)
        }
    }

    private var recentSteps: [Double] {
        measurements(in: stepsHistory, fromOffset: -7, throughOffset: -1)
    }

    private var previousSteps: [Double] {
        measurements(in: stepsHistory, fromOffset: -14, throughOffset: -8)
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var stepsAverage: Double? { average(recentSteps) }

    private var daylightAverage: Double? {
        average(measurements(
            in: daylightHistory, fromOffset: -7, throughOffset: -1
        ))
    }

    private var exerciseMinutes: Double? {
        let values = measurements(
            in: exerciseHistory, fromOffset: -7, throughOffset: -1
        )
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var stepsChangePercent: Double? {
        // Avoid making a weekly comparison from one or two isolated days.
        guard recentSteps.count >= 4, previousSteps.count >= 4,
              let recent = average(recentSteps),
              let previous = average(previousSteps),
              previous > 0
        else { return nil }
        return (recent - previous) / previous * 100
    }

    private var context: String {
        if !health.hasRequestedAuthorization {
            return tr(
                "Connect Apple Health to discover your everyday activity pattern.",
                "Koble til Apple Helse for å se mønsteret i hverdagsaktiviteten din."
            )
        }
        if isLoading {
            return tr("Reading recorded activity…", "Henter registrert aktivitet …")
        }
        if let change = stepsChangePercent {
            let percent = Int(abs(change).rounded())
            if change >= 8 {
                return tr(
                    "Average daily steps are up \\(percent)% compared with the previous week.",
                    "Gjennomsnittlig antall skritt per måledag er opp \\(percent) % fra uken før."
                )
            }
            if change <= -8 {
                return tr(
                    "Average daily steps are down \\(percent)% compared with the previous week.",
                    "Gjennomsnittlig antall skritt per måledag er ned \\(percent) % fra uken før."
                )
            }
            return tr(
                "Average daily steps are broadly similar to the previous week.",
                "Gjennomsnittlig antall skritt per måledag er omtrent som uken før."
            )
        }
        if !recentSteps.isEmpty {
            return tr(
                "Steps recorded on \\(recentSteps.count) of 7 days. A weekly comparison needs at least four recorded days in each week.",
                "Skritt registrert på \\(recentSteps.count) av 7 dager. Sammenligning krever minst fire måledager i hver uke."
            )
        }
        if daylightAverage != nil || exerciseMinutes != nil {
            return tr(
                "No recent step data. Other recorded activity is shown without estimating missing days.",
                "Ingen nyere skrittdata. Annen aktivitet vises uten å beregne manglende dager."
            )
        }
        return tr(
            "No recorded activity for the last seven completed days.",
            "Ingen registrert aktivitet de siste sju avsluttede dagene."
        )
    }

    private var highestSteps: Double {
        max(completedDays.compactMap {
            measuredValue(on: $0, in: stepsHistory)
        }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        ATHLTHInsightsStyle.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Everyday rhythm", "Hverdagsrytme"))
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                    Text(tr(
                        "Movement, exercise and daylight",
                        "Bevegelse, trening og dagslys"
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                }
                Spacer(minLength: 2)
                Text(tr("7 days", "7 dager"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .padding(.top, 6)
            }

            HStack(spacing: 8) {
                rhythmMetric(
                    .steps,
                    value: stepsAverage.map {
                        Int($0.rounded()).formatted()
                    } ?? "—",
                    subtitle: tr("per recorded day", "per måledag")
                )
                rhythmMetric(
                    .daylightMinutes,
                    value: daylightAverage.map {
                        "\\(Int($0.rounded())) min"
                    } ?? "—",
                    subtitle: tr("per recorded day", "per måledag")
                )
                rhythmMetric(
                    .exerciseMinutes,
                    value: exerciseMinutes.map {
                        "\\(Int($0.rounded())) min"
                    } ?? "—",
                    subtitle: tr("recorded in 7 days", "registrert på 7 d")
                )
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(tr("Steps through the week", "Skritt gjennom uken"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                    Spacer()
                    Text(tr("Completed days", "Avsluttede dager"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                }
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(completedDays, id: \\.self) { day in
                        let steps = measuredValue(on: day, in: stepsHistory)
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(steps == nil
                                      ? ATHLTHInsightsStyle.track
                                      : ATHLTHInsightsStyle.accent)
                                .frame(
                                    height: steps.map {
                                        max(4, CGFloat($0 / highestSteps) * 45)
                                    } ?? 4
                                )
                                .frame(maxHeight: .infinity, alignment: .bottom)
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(ATHLTHInsightsStyle.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            day.formatted(date: .abbreviated, time: .omitted)
                            + ": " + (steps.map {
                                "\\(Int($0.rounded())) " +
                                    tr("steps", "skritt")
                            } ?? tr("No reading", "Ingen måling"))
                        )
                    }
                }
                .frame(height: 66, alignment: .bottom)
            }
            .padding(12)
            .background(
                ATHLTHInsightsStyle.canvas,
                in: RoundedRectangle(cornerRadius: 15)
            )

            Text(context)
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                ATHLTHInsightsHealthAreaView(area: .activity)
            } label: {
                Label(
                    tr("Explore daily activity", "Utforsk daglig aktivitet"),
                    systemImage: "arrow.up.right"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHInsightsStyle.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .athlthInsightsSurface()
        .task(id: health.lastSuccessfulRefreshAt) {
            await loadActivity()
        }
    }

    private func rhythmMetric(
        _ metric: ATHLTHInsightHealthMetric,
        value: String,
        subtitle: String
    ) -> some View {
        NavigationLink {
            ATHLTHInsightsHealthMetricDetailView(metric: metric)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: .infinity, minHeight: 63, alignment: .leading)
            .padding(10)
            .background(
                ATHLTHInsightsStyle.canvas,
                in: RoundedRectangle(cornerRadius: 13)
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadActivity() async {
        guard health.healthDataAvailable,
              health.hasRequestedAuthorization,
              !health.shouldDeferAutomaticHealthWork else {
            stepsHistory = []
            daylightHistory = []
            exerciseHistory = []
            isLoading = false
            return
        }
        isLoading = true
        // Query in parallel, only while Overview is visible. Fifteen days
        // include the 14 finished days; today's incomplete data is excluded.
        async let steps = health.insightDailyValues(for: .steps, days: 15)
        async let daylight = health.insightDailyValues(for: .daylightMinutes, days: 15)
        async let exercise = health.insightDailyValues(for: .exerciseMinutes, days: 15)
        let (recordedSteps, recordedDaylight, recordedExercise) =
            await (steps, daylight, exercise)
        guard !Task.isCancelled else { return }
        stepsHistory = recordedSteps
        daylightHistory = recordedDaylight
        exerciseHistory = recordedExercise
        isLoading = false
    }
}

struct ATHLTHInsightsHealthLibraryEntry: View {
    var body: some View {
        NavigationLink {
            ATHLTHInsightsHealthLibraryView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.title3)
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .frame(width: 42, height: 42)
                    .background(ATHLTHInsightsStyle.accent.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "All health measurements",
                        norwegian: "Alle helsemålinger"
                    ))
                    .font(.headline)
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                    Text(ATHLTHLocalization.choose(
                        english: "Sleep, vital signs, fitness, movement and body",
                        norwegian: "Søvn, kroppssignaler, kondisjon, bevegelse og kropp"
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
            .padding(15)
            .athlthInsightsSurface()
        }
        .buttonStyle(.plain)
    }
}
