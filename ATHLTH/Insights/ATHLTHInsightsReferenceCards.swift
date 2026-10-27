import SwiftUI
import Charts

/// Reference-inspired cards backed exclusively by Apple Health and the
/// ATHLTH daily check-in. Missing measurements stay missing, never demo data.
enum ATHLTHInsightReferenceMetric: String, CaseIterable, Identifiable {
    case sleep, restingHeartRate, hrv, respiratory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return ATHLTHLocalization.choose(english: "Sleep", norwegian: "Søvn")
        case .restingHeartRate:
            return ATHLTHLocalization.choose(english: "Resting heart rate", norwegian: "Hvilepuls")
        case .hrv: return "HRV"
        case .respiratory:
            return ATHLTHLocalization.choose(english: "Respiratory rate", norwegian: "Respirasjon")
        }
    }

    var icon: String {
        switch self {
        case .sleep: return "moon.stars.fill"
        case .restingHeartRate: return "heart"
        case .hrv: return "waveform.path.ecg"
        case .respiratory: return "lungs"
        }
    }

    func value(_ day: RecoveryTrendDay) -> Double? {
        switch self {
        case .sleep: return day.sleepDuration.map { $0 / 3_600 }
        case .restingHeartRate: return day.restingHeartRate
        case .hrv: return day.hrvMilliseconds
        case .respiratory: return day.respiratoryRate
        }
    }

    func label(_ number: Double) -> String {
        switch self {
        case .sleep:
            let minutes = Int((number * 60).rounded())
            return "\(minutes / 60) t \(minutes % 60) min"
        case .restingHeartRate:
            return "\(Int(number.rounded())) bpm"
        case .hrv:
            return "\(Int(number.rounded())) ms"
        case .respiratory:
            return String(format: "%.1f/min", number)
        }
    }
}

struct ATHLTHInsightsReferenceSignalCard: View {
    let metric: ATHLTHInsightReferenceMetric
    let snapshot: RecoveryTrendSnapshot
    let onMore: () -> Void

    private var recentDays: [RecoveryTrendDay] {
        Array(snapshot.days.suffix(7))
    }

    private var latest: Double? {
        recentDays.reversed().compactMap { metric.value($0) }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: metric.icon)
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .font(.system(size: 19))
                Text(metric.title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Spacer(minLength: 4)
                Text(ATHLTHLocalization.choose(
                    english: "Last 7 days", norwegian: "Siste 7 dager"
                ))
                .font(.system(size: 10))
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            HStack(alignment: .center, spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(latest.map { metric.label($0) } ?? "—")
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(latest == nil
                        ? ATHLTHLocalization.choose(
                            english: "Not enough measurements",
                            norwegian: "Mangler målinger")
                        : ATHLTHLocalization.choose(
                            english: "Recorded in Apple Health",
                            norwegian: "Registrert i Apple Health"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                Spacer(minLength: 3)
                Button(action: onMore) {
                    HStack(spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "See more", norwegian: "Se mer"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 35)
                    .background(ATHLTHInsightsStyle.track,
                                in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if recentDays.contains(where: { metric.value($0) != nil }) {
                Chart(recentDays) { day in
                    if let value = metric.value(day) {
                        if metric == .sleep {
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Hours", value)
                            )
                            .foregroundStyle(ATHLTHInsightsStyle.accent.opacity(0.78))
                            .cornerRadius(5)
                        } else {
                            LineMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Value", value)
                            )
                            .foregroundStyle(ATHLTHInsightsStyle.accent)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Value", value)
                            )
                            .foregroundStyle(ATHLTHInsightsStyle.accent)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: recentDays.map(\.date)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 128)
                .accessibilityLabel(metric.title + " · " +
                    ATHLTHLocalization.choose(english: "7 day trend", norwegian: "7-dagerstrend"))
            } else {
                Label(ATHLTHLocalization.choose(
                    english: "The trend appears when Apple Health has measurements.",
                    norwegian: "Trenden vises når Apple Health har målinger."
                ), systemImage: "chart.xyaxis.line")
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
            }
        }
        .padding(17)
        .athlthInsightsSurface()
    }
}

struct ATHLTHInsightsReferenceLoadCard: View {
    let snapshot: RecoveryTrendSnapshot
    let onMore: () -> Void

    private var lastWeek: [RecoveryTrendDay] {
        Array(snapshot.days.suffix(7))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(
                ATHLTHLocalization.choose(english: "Training load", norwegian: "Treningsbelastning"),
                icon: "chart.bar.xaxis")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(snapshot.trainingLoad.acuteMinutes.rounded())) min")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                    Text(snapshot.trainingLoad.title)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                Spacer()
                if let ratio = snapshot.trainingLoad.ratio,
                   ratio.isFinite {
                    Text(String(format: "%+.0f %%", (ratio - 1) * 100))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                    Text(ATHLTHLocalization.choose(
                        english: "vs. 4-week average",
                        norwegian: "mot 4-ukers snitt"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
            }
            if !lastWeek.isEmpty {
                Chart(lastWeek) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", max(0, day.trainingMinutes))
                    )
                    .foregroundStyle(ATHLTHInsightsStyle.accent.opacity(0.75))
                    .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: lastWeek.map(\.date)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 126)
            }
            Text(ATHLTHLocalization.choose(
                english: "Training minutes, not an invented load score.",
                norwegian: "Viser treningsminutter, ikke en beregnet belastningsscore."))
                .font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .padding(17)
        .athlthInsightsSurface()
    }

    private func heading(_ label: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHTrainDesign.ink)
            Spacer()
            Button(action: onMore) {
                Image(systemName: "arrow.right")
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .frame(width: 36, height: 32)
                    .background(ATHLTHInsightsStyle.track,
                                in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "See training load details",
                norwegian: "Se treningsbelastning"))
        }
    }
}

struct ATHLTHInsightsReferenceTimeCard: View {
    let days: [ATHLTHInsightsTrainingDay]

    private var minutes: Int {
        Int(days.reduce(0) { $0 + $1.minutes }.rounded())
    }

    private var count: Int {
        days.reduce(0) { $0 + $1.sessions }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(ATHLTHLocalization.choose(
                english: "Training time", norwegian: "Treningstid"),
                  systemImage: "stopwatch")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHTrainDesign.ink)
            HStack(alignment: .firstTextBaseline) {
                Text("\(minutes / 60) t \(minutes % 60) min")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text("\(count) " + ATHLTHLocalization.choose(
                    english: "workouts", norwegian: "økter"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            Text(ATHLTHLocalization.choose(
                english: "Completed sessions in the last 7 days",
                norwegian: "Registrert trening de siste 7 dagene"))
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            if !days.isEmpty {
                Chart(days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", max(0, day.minutes))
                    )
                    .foregroundStyle(ATHLTHInsightsStyle.accent.opacity(0.72))
                    .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: days.map(\.date)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 95)
            }
        }
        .foregroundStyle(ATHLTHTrainDesign.ink)
        .padding(17)
        .athlthInsightsSurface()
    }
}

struct ATHLTHInsightsReferenceDistributionCard: View {
    let load: RecoveryTrainingLoadSummary
    let sessionCount: Int

    private struct Slice: Identifiable {
        let title: String
        let minutes: Double
        let color: Color
        var id: String { title }
    }

    private var segments: [Slice] {
        [
            Slice(title: ATHLTHLocalization.choose(english: "Running", norwegian: "Løping"),
                  minutes: load.runningMinutes, color: ATHLTHInsightsStyle.accent),
            Slice(title: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke"),
                  minutes: load.strengthMinutes, color: ATHLTHInsightsStyle.accent),
            Slice(title: ATHLTHLocalization.choose(english: "Walking", norwegian: "Gå"),
                  minutes: load.walkingMinutes, color: ATHLTHInsightsStyle.track),
            Slice(title: ATHLTHLocalization.choose(english: "Other", norwegian: "Annet"),
                  minutes: load.otherMinutes, color: ATHLTHTrainDesign.secondary.opacity(0.50))
        ].filter { $0.minutes > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Training distribution", norwegian: "Treningsfordeling"))
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "Last 7 days", norwegian: "Siste 7 dager"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            if segments.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "No workouts recorded for this period.",
                    norwegian: "Ingen registrerte økter i perioden."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            } else {
                HStack(spacing: 22) {
                    Chart(segments) { slice in
                        SectorMark(
                            angle: .value("Minutes", slice.minutes),
                            innerRadius: .ratio(0.66),
                            angularInset: 2
                        )
                        .foregroundStyle(slice.color)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 150, height: 150)
                    .overlay {
                        VStack(spacing: 1) {
                            Text("\(sessionCount)")
                                .font(.title2.bold())
                            Text(ATHLTHLocalization.choose(english: "workouts", norwegian: "økter"))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTrainDesign.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(segments) { slice in
                            HStack(spacing: 7) {
                                Circle().fill(slice.color).frame(width: 8, height: 8)
                                Text(slice.title).font(.caption)
                                Spacer(minLength: 0)
                                Text("\(Int(slice.minutes.rounded())) min")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                }
                Text(ATHLTHLocalization.choose(
                    english: "Distribution by recorded minutes",
                    norwegian: "Fordeling etter registrerte minutter"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
        .padding(17)
        .athlthInsightsSurface()
    }
}

struct ATHLTHInsightsDailyCheckInCard: View {
    @ObservedObject var store: RecoverySorenessStore
    let onCheckIn: () -> Void

    private var lastFortnight: [RecoverySorenessEntry] {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        return store.entries
            .filter { $0.date >= cutoff && $0.date <= Date() && $0.energy != nil }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "face.smiling")
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                Text(ATHLTHLocalization.choose(
                    english: "How you've been feeling", norwegian: "Hvordan du har hatt det"))
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Spacer(minLength: 0)
                Button(action: onCheckIn) {
                    Text(store.hasTodayCheckIn
                        ? ATHLTHLocalization.choose(english: "Update", norwegian: "Oppdater")
                        : ATHLTHLocalization.choose(english: "Check in", norwegian: "Registrer"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                }
            }
            if let today = store.todayEnergy {
                Text(ATHLTHLocalization.choose(
                    english: "Today's energy", norwegian: "Dagens energi") + ": \(today)/5")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            if lastFortnight.count > 1 {
                Chart(lastFortnight, id: \.date) { entry in
                    if let energy = entry.energy {
                        LineMark(
                            x: .value("Day", entry.date, unit: .day),
                            y: .value("Energy", energy)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                        PointMark(
                            x: .value("Day", entry.date, unit: .day),
                            y: .value("Energy", energy)
                        )
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                    }
                }
                .chartYScale(domain: 1...5)
                .frame(height: 116)
                Text(ATHLTHLocalization.choose(
                    english: "Your own energy ratings over the last 14 days",
                    norwegian: "Egenrapportert energi de siste 14 dagene"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "Your trend appears after multiple daily check-ins.",
                    norwegian: "Din personlige trend vises etter flere daglige innsjekker."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
        .padding(17)
        .athlthInsightsSurface()
    }
}
