import SwiftUI
import Charts

/// Native wide-screen training analytics: deliberately separates completed
/// workout summaries from scheduled sessions and Apple Health's own scores.
struct ATHLTHStudioInsightsView: View {
    @EnvironmentObject private var health: HealthKitManager
    @SceneStorage("athlth.studio.insights.periodDays") private var periodDays = 28
    @State private var showingDetailedInsights = false
    @State private var showingSpecificProgress = false
    @State private var showingReportExport = false
    @State private var showingWorkoutComparison = false
    @State private var inspectedComparisonWorkout: WorkoutSummary?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func trainingTimeChange(
        result: ATHLTHStudioAnalytics.Snapshot,
        previousPeriod: ATHLTHStudioAnalytics.Snapshot
    ) -> String {
        guard previousPeriod.minutes > 0 else {
            return ATHLTHLocalization.choose(english: "No previous baseline", norwegian: "Ingen tidligere sammenligning")
        }
        let delta = (result.minutes - previousPeriod.minutes) / previousPeriod.minutes * 100
        return String(format: "%+.0f%%", delta)
    }

    var body: some View {
        GeometryReader { geometry in
            // Aggregate once per render, rather than re-filtering the complete
            // history for every metric and both charts.
            let anchor = Date.now
            let result = ATHLTHStudioAnalytics.snapshot(from: health.workouts, days: periodDays, now: anchor)
            let previousPeriod = ATHLTHStudioAnalytics.snapshot(
                from: health.workouts, days: periodDays,
                now: Calendar.current.date(byAdding: .day, value: -periodDays, to: anchor) ?? anchor
            )
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 12),
                count: dynamicTypeSize.isAccessibilitySize ? 1 :
                    (geometry.size.width >= 1130 ? 3 : geometry.size.width >= 670 ? 2 : 1)
            )
            let sideBySideCharts = geometry.size.width >= 890 && !dynamicTypeSize.isAccessibilitySize
            ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Insights Lab")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text(ATHLTHLocalization.choose(
                            english: "Real trends from workouts recorded in Apple Health.",
                            norwegian: "Faktiske trender fra treningsøkter registrert i Apple Health."
                        ))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Picker(ATHLTHLocalization.choose(english: "Days", norwegian: "Dager"), selection: $periodDays) {
                        Text("7").tag(7)
                        Text("28").tag(28)
                        Text("90").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: geometry.size.width < 480 ? 125 : 170)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
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
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Current duration", norwegian: "Nåværende varighet"),
                        value: String(format: "%.1f h", result.minutes / 60),
                        note: ATHLTHLocalization.choose(english: "Selected period", norwegian: "Valgt periode")
                    )
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Previous duration", norwegian: "Forrige varighet"),
                        value: String(format: "%.1f h", previousPeriod.minutes / 60),
                        note: ATHLTHLocalization.choose(english: "Prior equal-length period", norwegian: "Foregående like lange periode")
                    )
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Duration change", norwegian: "Endring i varighet"),
                        value: trainingTimeChange(result: result, previousPeriod: previousPeriod),
                        note: ATHLTHLocalization.choose(english: "Descriptive, not a readiness score", norwegian: "Beskrivende, ikke restitusjonsscore")
                    )
                }
                Group {
                    if sideBySideCharts {
                        HStack(alignment: .top, spacing: 16) {
                            chartCard(
                                title: ATHLTHLocalization.choose(
                                    english: "Daily duration", norwegian: "Daglig varighet"
                                ),
                                unit: ATHLTHLocalization.choose(
                                    english: "hours", norwegian: "timer"
                                ),
                                distance: false, result: result
                            )
                            chartCard(
                                title: ATHLTHLocalization.choose(
                                    english: "Distance", norwegian: "Distanse"
                                ),
                                unit: "km",
                                distance: true, result: result
                            )
                        }
                    } else {
                        VStack(spacing: 15) {
                            chartCard(
                                title: ATHLTHLocalization.choose(
                                    english: "Daily duration", norwegian: "Daglig varighet"
                                ),
                                unit: ATHLTHLocalization.choose(
                                    english: "hours", norwegian: "timer"
                                ),
                                distance: false, result: result
                            )
                            chartCard(
                                title: ATHLTHLocalization.choose(
                                    english: "Distance", norwegian: "Distanse"
                                ),
                                unit: "km",
                                distance: true, result: result
                            )
                        }
                    }
                }
                ATHLTHStudioTrainingLoadView()
                ATHLTHStudioProgressExplorerView()
                Button {
                    showingWorkoutComparison = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Compare two recorded workouts",
                        norwegian: "Sammenlign to gjennomførte økter"
                    ), systemImage: "rectangle.split.2x1")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("athlth-ipad-insights-compare")
                Button {
                    showingReportExport = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Create a personal training PDF report",
                        norwegian: "Lag personlig treningsrapport som PDF"
                    ), systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("athlth-ipad-create-report")
                Button {
                    showingSpecificProgress = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Analyze a specific exercise or 4 × 4 interval",
                        norwegian: "Analyser en bestemt øvelse eller 4 × 4-intervall"
                    ), systemImage: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.bordered)
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
            .padding(geometry.size.width < 660 ? 14 : 26)
            .frame(maxWidth: 1600)
            .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingWorkoutComparison) {
            NavigationStack {
                ATHLTHStudioHistoryView(onInspect: { inspectedComparisonWorkout = $0 })
                    .sheet(item: $inspectedComparisonWorkout) { workout in
                        NavigationStack {
                            ATHLTHStudioWorkoutInspectionView(workout: workout)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button(ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")) {
                                            inspectedComparisonWorkout = nil
                                        }
                                    }
                                }
                        }
                        .presentationDetents([.large])
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")) {
                                showingWorkoutComparison = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingReportExport) {
            ATHLTHStudioReportExportView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingDetailedInsights) {
            ATHLTHInsightsView()
        }
        .sheet(isPresented: $showingSpecificProgress) {
            NavigationStack {
                ATHLTHSpecificProgressView()
                    .navigationTitle(ATHLTHLocalization.choose(
                        english: "Specific training progress",
                        norwegian: "Spesifikk treningsutvikling"
                    ))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
        }
    }

    private func chartCard(title: String, unit: String, distance: Bool,
                           result: ATHLTHStudioAnalytics.Snapshot) -> some View {
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
