import SwiftUI
import Charts

/// Active Insight training distribution and wellness check-in views.
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
                  minutes: load.runningMinutes,
                  color: ATHLTHInsightsStyle.accent),
            Slice(title: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke"),
                  minutes: load.strengthMinutes,
                  color: Color(red: 0.46, green: 0.42, blue: 0.37)),
            Slice(title: ATHLTHLocalization.choose(english: "Walking", norwegian: "Gå"),
                  minutes: load.walkingMinutes,
                  color: Color(red: 0.80, green: 0.80, blue: 0.73)),
            Slice(title: ATHLTHLocalization.choose(english: "Other", norwegian: "Annet"),
                  minutes: load.otherMinutes,
                  color: Color(red: 0.66, green: 0.72, blue: 0.73))
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
