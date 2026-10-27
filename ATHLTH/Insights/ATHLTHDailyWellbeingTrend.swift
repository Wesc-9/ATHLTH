import Charts
import SwiftUI

/// Each field is a self-reported answer to the existing daily check-in.
/// These are not HRV, recovery scores, medical diagnoses, or AI estimates.
enum ATHLTHCheckInMetric: String, CaseIterable, Identifiable {
    case energy, stress, motivation, soreness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .energy:
            return ATHLTHLocalization.choose(english: "Energy", norwegian: "Energi")
        case .stress:
            return ATHLTHLocalization.choose(english: "Stress", norwegian: "Stress")
        case .motivation:
            return ATHLTHLocalization.choose(english: "Motivation", norwegian: "Motivasjon")
        case .soreness:
            return ATHLTHLocalization.choose(english: "Soreness", norwegian: "Ømhet")
        }
    }

    var symbol: String {
        switch self {
        case .energy: "bolt.fill"
        case .stress: "waveform.path.ecg"
        case .motivation: "flame.fill"
        case .soreness: "figure.cooldown"
        }
    }

    var lowerIsBetter: Bool {
        self == .stress || self == .soreness
    }

    func value(in entry: RecoverySorenessEntry) -> Int? {
        let answer: Int?
        switch self {
        case .energy: answer = entry.energy
        case .stress: answer = entry.stress
        case .motivation: answer = entry.motivation
        case .soreness: answer = entry.overallSoreness
        }
        guard let answer, (1...5).contains(answer) else { return nil }
        return answer
    }
}

enum ATHLTHCheckInPeriod: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week:
            ATHLTHLocalization.choose(english: "7 days", norwegian: "7 dager")
        case .month:
            ATHLTHLocalization.choose(english: "30 days", norwegian: "30 dager")
        }
    }
}

struct ATHLTHCheckInPoint: Identifiable, Equatable {
    let date: Date
    let value: Int
    var id: Date { date }
}

/// All calculations use actual responses. Missing days and missing fields
/// are omitted, never interpreted as zero or silently interpolated.
enum ATHLTHCheckInTrends {
    static func points(
        entries: [RecoverySorenessEntry],
        metric: ATHLTHCheckInMetric,
        days: Int,
        at now: Date = Date(),
        calendar: Calendar = .current,
        offsetDays: Int = 0
    ) -> [ATHLTHCheckInPoint] {
        let today = calendar.startOfDay(for: now)
        guard days > 0,
              let end = calendar.date(byAdding: .day, value: -offsetDays, to: today),
              let start = calendar.date(byAdding: .day, value: 1 - days, to: end)
        else { return [] }

        // One answer per calendar day. The store normally guarantees this,
        // but favor the newest if imported history contains duplicates.
        let sorted = entries.sorted { $0.date > $1.date }
        var values: [Date: Int] = [:]
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= start && day <= end, values[day] == nil,
                  let answer = metric.value(in: entry) else { continue }
            values[day] = answer
        }
        return values.map { ATHLTHCheckInPoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    static func average(_ points: [ATHLTHCheckInPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return Double(points.reduce(0) { $0 + $1.value }) / Double(points.count)
    }

    /// A comparison is shown only with at least three answered days on
    /// each side; otherwise it is too easily mistaken for a stable trend.
    static func change(
        entries: [RecoverySorenessEntry],
        metric: ATHLTHCheckInMetric,
        days: Int,
        at now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        let current = points(
            entries: entries, metric: metric, days: days,
            at: now, calendar: calendar
        )
        let prior = points(
            entries: entries, metric: metric, days: days,
            at: now, calendar: calendar, offsetDays: days
        )
        guard current.count >= 3, prior.count >= 3,
              let currentAverage = average(current),
              let priorAverage = average(prior) else { return nil }
        return currentAverage - priorAverage
    }
}

/// A compact entry point on Insights → Overview, deliberately distinct from
/// the calculated readiness ring and independent of Apple Health availability.
struct ATHLTHDailyWellbeingSummaryCard: View {
    let entries: [RecoverySorenessEntry]
    let onEdit: () -> Void
    let onViewTrend: () -> Void

    private var today: RecoverySorenessEntry? {
        entries.first { Calendar.current.isDateInToday($0.date) }
    }

    private var answers: [(String, Int)] {
        guard let today else { return [] }
        return ATHLTHCheckInMetric.allCases.compactMap { metric in
            metric.value(in: today).map { (metric.title, $0) }
        }
    }

    private func t(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                Text(t("How you feel", "Slik har du det"))
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Spacer(minLength: 4)
                Text(t("Your answers", "Dine svar"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            Text(t(
                "Your own daily assessment, separate from Apple Watch readiness.",
                "Din egen dagsform, uavhengig av beregnet dagsform på Apple Watch."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTrainDesign.secondary)

            if answers.isEmpty {
                Text(t("No answers registered today.", "Ingen svar registrert i dag."))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(answers, id: \.0) { title, value in
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTrainDesign.secondary)
                            Spacer(minLength: 1)
                            Text("\(value)/5")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(ATHLTHTrainDesign.ink)
                        }
                        .padding(10)
                        .background(ATHLTHTrainDesign.canvas.opacity(0.8),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Label(
                        answers.isEmpty
                            ? t("Check in today", "Registrer i dag")
                            : t("Update today", "Oppdater i dag"),
                        systemImage: "plus.circle"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(ATHLTHTrainDesign.bronze, in: Capsule())

                Button(action: onViewTrend) {
                    HStack(spacing: 5) {
                        Text(t("View trend", "Se trend"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(minHeight: 42)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .athlthTrainPaper()
    }
}

/// Displayed in Insights → Trends. Nothing here creates an aggregate
/// "wellbeing score": stress and soreness run in the opposite direction
/// from energy and motivation and must be evaluated independently.
struct ATHLTHDailyWellbeingTrendCard: View {
    let entries: [RecoverySorenessEntry]
    let onEdit: () -> Void

    @State private var metric: ATHLTHCheckInMetric = .energy
    @State private var period: ATHLTHCheckInPeriod = .week

    private func t(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var samples: [ATHLTHCheckInPoint] {
        ATHLTHCheckInTrends.points(
            entries: entries, metric: metric, days: period.rawValue
        )
    }

    private var average: Double? {
        ATHLTHCheckInTrends.average(samples)
    }

    private var comparison: Double? {
        ATHLTHCheckInTrends.change(
            entries: entries, metric: metric, days: period.rawValue
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Your wellbeing over time", "Din opplevde form over tid"))
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                    Text(t(
                        "The actual answers from your daily check-ins.",
                        "Det du selv har svart i de daglige innsjekkene."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                Spacer(minLength: 3)
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
            }

            Picker(t("Period", "Periode"), selection: $period) {
                ForEach(ATHLTHCheckInPeriod.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            // Compact two-by-two selection works at narrow iPhone widths.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ATHLTHCheckInMetric.allCases) { option in
                    metricButton(option)
                }
            }

            if let average {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(average.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 35, weight: .medium, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                    Text("/ 5")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    Spacer()
                    Text("\(samples.count) " + t("answered days", "dager med svar"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                Text(t("Average · ", "Snitt · ") + metric.title)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)

                chart

                if let comparison, abs(comparison) >= 0.05 {
                    let improving = metric.lowerIsBetter
                        ? comparison < 0 : comparison > 0
                    let prefix = comparison > 0 ? "+" : ""
                    let value = prefix + comparison.formatted(
                        .number.precision(.fractionLength(1))
                    )
                    HStack(spacing: 7) {
                        Image(systemName: improving ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                        Text(
                            value + " " + t(
                                "vs the previous \(period.rawValue) days",
                                "mot forrige \(period.rawValue) dager"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                    }
                } else {
                    Text(t(
                        "Compare periods after at least three answers in each.",
                        "Perioder sammenlignes når du har minst tre svar i hver."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Text(t(
                        "No answers for this measure in the selected period.",
                        "Ingen svar på denne målingen i valgt periode."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                Text(t(
                    "Scores are 1–5. Lower stress/soreness is better; higher energy/motivation is better. Unanswered days are not counted.",
                    "Skala 1–5. Lavere stress/ømhet og høyere energi/motivasjon er bedre. Dager uten svar teller ikke."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }

            Button(action: onEdit) {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text(t("Register today's check-in", "Registrer dagens innsjekk"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .padding(13)
                .background(ATHLTHTrainDesign.canvas.opacity(0.8),
                            in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .athlthTrainPaper()
    }

    private func metricButton(_ option: ATHLTHCheckInMetric) -> some View {
        let selected = option == metric
        return Button {
            metric = option
        } label: {
            HStack(spacing: 7) {
                Image(systemName: option.symbol)
                    .font(.caption)
                Text(option.title)
                    .font(.caption.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : ATHLTHTrainDesign.ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 39)
            .background(selected ? ATHLTHTrainDesign.bronze : ATHLTHTrainDesign.canvas,
                        in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var chart: some View {
        Chart(samples) { point in
            BarMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Rating", point.value)
            )
            .foregroundStyle(ATHLTHTrainDesign.gold)
            .cornerRadius(5)
        }
        .chartYScale(domain: 0...5)
        .frame(height: 186)
        .accessibilityLabel(t(
            "Your \(metric.title) ratings over the last \(period.rawValue) days",
            "Dine svar for \(metric.title) de siste \(period.rawValue) dagene"
        ))
    }
}
