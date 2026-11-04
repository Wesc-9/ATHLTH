import SwiftUI
import Charts

/// Native wide-screen training analytics: deliberately separates completed
/// workout summaries from scheduled sessions and Apple Health's own scores.
struct ATHLTHStudioInsightsView: View {
    @EnvironmentObject private var health: HealthKitManager
    @State private var periodDays = 28
    @State private var showingDetailedInsights = false

    private var result: ATHLTHStudioAnalytics.Snapshot {
        ATHLTHStudioAnalytics.snapshot(from: health.workouts, days: periodDays)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Insights Lab")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text(ATHLTHLocalization.choose(
                            english: "Real trends from workouts recorded in Apple Health.",
                            norwegian: "Faktiske trender fra treningsøkter registrert i Apple Health."
                        ))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(ATHLTHLocalization.choose(english: "Days", norwegian: "Dager"), selection: $periodDays) {
                        Text("7").tag(7)
                        Text("28").tag(28)
                        Text("90").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                HStack(spacing: 12) {
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Total workouts", norwegian: "Totalt antall økter"),
                        value: "\(result.sessions)",
                        note: "\(periodDays) " + ATHLTHLocalization.choose(english: "days", norwegian: "dager")
                    )
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Running", norwegian: "Løping"),
                        value: "\(result.runningSessions)",
                        note: ATHLTHLocalization.choose(english: "sessions", norwegian: "økter")
                    )
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke"),
                        value: "\(result.strengthSessions)",
                        note: ATHLTHLocalization.choose(english: "sessions", norwegian: "økter")
                    )
                }
                HStack(alignment: .top, spacing: 16) {
                    chartCard(
                        title: ATHLTHLocalization.choose(english: "Daily duration", norwegian: "Daglig varighet"),
                        unit: ATHLTHLocalization.choose(english: "hours", norwegian: "timer"),
                        distance: false
                    )
                    chartCard(
                        title: ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                        unit: "km",
                        distance: true
                    )
                }
                Button {
                    showingDetailedInsights = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Open existing detailed training signals",
                        norwegian: "Åpne eksisterende avanserte treningssignaler"
                    ), systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.bordered)
                Text(ATHLTHLocalization.choose(
                    english: "These charts show recorded workout values, not Apple's Health Age or proprietary Insights interpretations.",
                    norwegian: "Grafene viser målte treningsverdier, ikke Apples Health Age eller interne Insights-tolkninger."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(26)
            .frame(maxWidth: 1600)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingDetailedInsights) {
            ATHLTHInsightsView()
        }
    }

    private func chartCard(title: String, unit: String, distance: Bool) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(title).font(.headline)
            Chart(result.days) { day in
                LineMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value(unit, distance ? day.distanceKilometers : day.minutes / 60)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                AreaMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value(unit, distance ? day.distanceKilometers : day.minutes / 60)
                )
                .foregroundStyle(ATHLTHStudioStyle.gold.opacity(0.12))
            }
            .frame(height: 260)
            if result.sessions == 0 {
                Text(ATHLTHLocalization.choose(
                    english: "No recorded workouts in this period.",
                    norwegian: "Ingen registrerte treningsøkter i perioden."
                )).foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}
