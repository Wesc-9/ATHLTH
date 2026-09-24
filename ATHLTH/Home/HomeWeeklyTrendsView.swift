import Charts
import SwiftUI

private enum HomeWeeklyMetric: CaseIterable, Identifiable {
    case movement
    case workouts
    case sleep

    var id: String { title }

    var title: String {
        switch self {
        case .movement: return "Movement"
        case .workouts: return "Workouts"
        case .sleep: return "Sleep"
        }
    }

    var subtitle: String {
        switch self {
        case .movement: return "Daily steps"
        case .workouts: return "Training minutes"
        case .sleep: return "Hours per night"
        }
    }

    var icon: String {
        switch self {
        case .movement: return "figure.walk.motion"
        case .workouts: return "dumbbell.fill"
        case .sleep: return "moon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .movement: return .green
        case .workouts: return ATHLTHTheme.accent
        case .sleep: return .purple
        }
    }
}

private struct HomeWeeklyTrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

struct HomeWeeklyTrendsCard: View {
    let snapshot: HealthProgressSnapshot?
    let isLoading: Bool
    let hasHealthAccess: Bool

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Week")
                        .font(.title3.weight(.bold))

                    Text("A quick 7-day view of movement, training and sleep.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                Text("7 DAYS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.72))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading your week…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            } else if let snapshot,
                      snapshotHasData(snapshot) {
                VStack(spacing: 0) {
                    ForEach(
                        Array(HomeWeeklyMetric.allCases.enumerated()),
                        id: \.element.id
                    ) { index, metric in
                        HomeWeeklyTrendRow(
                            metric: metric,
                            summary: summary(metric, snapshot: snapshot),
                            change: change(metric, snapshot: snapshot),
                            points: points(metric, snapshot: snapshot)
                        )

                        if index < HomeWeeklyMetric.allCases.count - 1 {
                            Divider()
                                .overlay(ATHLTHTheme.divider.opacity(0.7))
                                .padding(.leading, 46)
                        }
                    }
                }
                .padding(.top, 10)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(
                        systemName: hasHealthAccess
                            ? "chart.xyaxis.line"
                            : "heart.text.square"
                    )
                    .font(.title3)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            hasHealthAccess
                                ? "Your weekly charts will appear here"
                                : "Connect Apple Health for weekly charts"
                        )
                        .font(.subheadline.weight(.semibold))

                        Text(
                            hasHealthAccess
                                ? "ATHLTH needs a few days of movement, workout or sleep data before the weekly view becomes useful."
                                : "Movement, workout and sleep trends stay hidden until compatible Health data is available."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.top, 14)
            }
        }
    }

    private func snapshotHasData(
        _ snapshot: HealthProgressSnapshot
    ) -> Bool {
        snapshot.workoutCount > 0 ||
        (snapshot.totalSteps ?? 0) > 0 ||
        (snapshot.averageSleepDuration ?? 0) > 0 ||
        snapshot.trainingDuration > 0
    }

    private func points(
        _ metric: HomeWeeklyMetric,
        snapshot: HealthProgressSnapshot
    ) -> [HomeWeeklyTrendPoint] {
        snapshot.buckets.map { bucket in
            let value: Double

            switch metric {
            case .movement:
                value = bucket.averageDailySteps ?? 0
            case .workouts:
                value = bucket.trainingDuration / 60
            case .sleep:
                value = (bucket.averageSleepDuration ?? 0) / 3_600
            }

            return HomeWeeklyTrendPoint(
                date: bucket.startDate,
                value: max(value, 0)
            )
        }
    }

    private func summary(
        _ metric: HomeWeeklyMetric,
        snapshot: HealthProgressSnapshot
    ) -> String {
        switch metric {
        case .movement:
            guard let steps = snapshot.averageDailySteps,
                  steps > 0
            else {
                return "—"
            }

            if steps >= 1_000 {
                return String(
                    format: "%.1fk/day",
                    steps / 1_000
                )
            }

            return "\(Int(steps.rounded()))/day"

        case .workouts:
            if snapshot.trainingDuration <= 0 {
                return snapshot.workoutCount > 0
                    ? "\(snapshot.workoutCount) workouts"
                    : "—"
            }

            return snapshot.trainingDuration.shortDuration

        case .sleep:
            guard let duration = snapshot.averageSleepDuration,
                  duration > 0
            else {
                return "—"
            }

            return duration.shortDuration
        }
    }

    private func change(
        _ metric: HomeWeeklyMetric,
        snapshot: HealthProgressSnapshot
    ) -> Double? {
        switch metric {
        case .movement:
            return snapshot.stepsChangePercent
        case .workouts:
            return snapshot.trainingDurationChangePercent
        case .sleep:
            return snapshot.sleepChangePercent
        }
    }
}

private struct HomeWeeklyTrendRow: View {
    let metric: HomeWeeklyMetric
    let summary: String
    let change: Double?
    let points: [HomeWeeklyTrendPoint]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: metric.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(metric.tint)
                .frame(width: 36, height: 36)
                .background(
                    metric.tint.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                HStack(spacing: 6) {
                    Text(summary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    if let change,
                       change.isFinite {
                        Text(changeText(change))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                change >= 0 ? Color.green : Color.orange
                            )
                    }
                }

                Text(metric.subtitle)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer(minLength: 4)

            trendChart
                .frame(width: 128, height: 58)
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var trendChart: some View {
        Chart(points) { point in
            switch metric {
            case .sleep:
                AreaMark(
                    x: .value("Day", point.date),
                    y: .value("Hours", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            metric.tint.opacity(0.20),
                            metric.tint.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", point.date),
                    y: .value("Hours", point.value)
                )
                .foregroundStyle(metric.tint)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2.2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .interpolationMethod(.catmullRom)

            case .movement, .workouts:
                BarMark(
                    x: .value("Day", point.date),
                    y: .value("Value", point.value),
                    width: .fixed(9)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            metric.tint,
                            metric.tint.opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(Color.clear)
        }
    }

    private func changeText(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(Int(value.rounded()))%"
    }
}
