import SwiftUI
import Charts

/// One entry point, grouped by purpose rather than a wall of HealthKit data.
/// Cards are native views; the sample source remains local Apple Health.
struct ATHLTHInsightsHealthLibraryView: View {
    @EnvironmentObject private var health: HealthKitManager

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
    }
}

struct ATHLTHInsightsHealthAreaView: View {
    let area: ATHLTHInsightHealthArea
    @EnvironmentObject private var health: HealthKitManager

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
                            Text(metric.formatted(metric.currentValue(in: health)))
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
    }
}

/// Tap-through history is loaded on demand, avoiding 22 HealthKit queries
/// whenever Insight's main page opens.
struct ATHLTHInsightsHealthMetricDetailView: View {
    let metric: ATHLTHInsightHealthMetric
    @EnvironmentObject private var health: HealthKitManager
    @State private var period = 30
    @State private var values: [ATHLTHInsightHealthDay] = []
    @State private var loading = false
    @State private var attempted = false

    private var latest: Double? { values.last?.value ?? metric.currentValue(in: health) }

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
                            description: Text(ATHLTHLocalization.choose(
                                english: "This device may not record this metric, or Apple Health has no readable samples for this period.",
                                norwegian: "Enheten registrerer kanskje ikke målingen, eller Apple Health har ingen lesbare data i denne perioden."
                            ))
                        )
                        .frame(minHeight: 165)
                    } else {
                        Chart(values) { item in
                            if metric == .steps {
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
                    }
                }
                .padding(16)
                .athlthInsightsSurface()

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
        .task(id: period) {
            loading = true
            attempted = true
            let result = await health.insightDailyValues(for: metric, days: period)
            guard !Task.isCancelled else { return }
            values = result
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
                                    .frame(width: max(0, (geo.size.width - 6) * stage.1 / total))
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

/// The overview shows useful context, not 22 miniature diagnostic tiles.
struct ATHLTHInsightsVitalContextCard: View {
    let snapshot: RecoveryTrendSnapshot
    @EnvironmentObject private var health: HealthKitManager

    private func previousAndCurrent(
        _ value: (RecoveryTrendDay) -> Double?
    ) -> (previous: Double, recent: Double)? {
        let days = snapshot.days.suffix(14)
        let prev = Array(days.dropLast(7)).compactMap(value).filter { $0.isFinite && $0 > 0 }
        let curr = Array(days.suffix(7)).compactMap(value).filter { $0.isFinite && $0 > 0 }
        guard prev.count >= 3, curr.count >= 3 else { return nil }
        return (prev.reduce(0,+)/Double(prev.count),
                curr.reduce(0,+)/Double(curr.count))
    }

    private var explanation: String {
        guard let hrv = previousAndCurrent({ $0.hrvMilliseconds }),
              let resting = previousAndCurrent({ $0.restingHeartRate }) else {
            return ATHLTHLocalization.choose(
                english: "Your personal baseline appears after several comparable days of HRV and resting-heart-rate measurements.",
                norwegian: "Din personlige trend vises når vi har flere sammenlignbare dager med HRV og hvilepuls."
            )
        }
        if hrv.recent < hrv.previous * 0.92 && resting.recent > resting.previous * 1.04 {
            return ATHLTHLocalization.choose(
                english: "HRV is below its recent average while resting heart rate is higher. Watch the pattern over several days rather than judging one reading.",
                norwegian: "HRV ligger lavere og hvilepulsen høyere enn nylig gjennomsnitt. Følg utviklingen over flere dager fremfor én enkeltmåling."
            )
        }
        return ATHLTHLocalization.choose(
            english: "Your HRV and resting heart rate can be compared with your own recent measurements. Trends do not provide a diagnosis.",
            norwegian: "HRV og hvilepuls kan sammenlignes med dine egne tidligere målinger. Trendene er ikke en diagnose."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(ATHLTHLocalization.choose(
                english: "Your body's signals",
                norwegian: "Kroppens signaler"
            ), systemImage: "heart.text.square")
                .font(.headline)
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            HStack(spacing: 8) {
                stat(.hrv)
                stat(.restingHeartRate)
                stat(.respiratoryRate)
            }
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                ATHLTHInsightsHealthAreaView(area: .vitalSigns)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "View vital signs", norwegian: "Se kroppens signaler"
                ), systemImage: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHInsightsStyle.accent)
            }
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private func stat(_ metric: ATHLTHInsightHealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.title)
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metric.formatted(metric.currentValue(in: health)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHInsightsStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHInsightsStyle.canvas,
                    in: RoundedRectangle(cornerRadius: 12))
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
