import SwiftUI
import Charts

/// Overview is intentionally not the iPhone Home view stretched to full width.
struct ATHLTHStudioDashboardView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    let onInspect: (WorkoutSummary) -> Void

    @State private var periodDays = 28

    private var snapshot: ATHLTHStudioAnalytics.Snapshot {
        ATHLTHStudioAnalytics.snapshot(from: health.workouts, days: periodDays)
    }

    private var recent: [WorkoutSummary] {
        Array(health.workouts.sorted { $0.startDate > $1.startDate }.prefix(6))
    }

    private var scheduled: [ATHLTHStudioSchedule.Occurrence] {
        ATHLTHStudioSchedule.upcoming(
            plans: session.trainingPlans,
            standalone: session.standalonePlannedSessions,
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: .now,
            days: 14
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "Your training, in perspective",
                            norwegian: "Treningen din, i sammenheng"
                        ))
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "Completed workouts only • from Apple Health",
                            norwegian: "Kun gjennomførte økter • fra Apple Health"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(ATHLTHLocalization.choose(english: "Period", norwegian: "Periode"), selection: $periodDays) {
                        Text("7 d").tag(7)
                        Text("28 d").tag(28)
                        Text("90 d").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 245)
                }
                HStack(spacing: 13) {
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Completed workouts", norwegian: "Gjennomførte økter"),
                        value: "\(snapshot.sessions)",
                        note: "\(periodDays) " + ATHLTHLocalization.choose(english: "days", norwegian: "dager")
                    )
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Training time", norwegian: "Treningstid"),
                        value: String(format: "%.1f t", snapshot.minutes / 60),
                        note: ATHLTHLocalization.choose(english: "Recorded duration", norwegian: "Registrert varighet")
                    )
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse"),
                        value: String(format: "%.1f km", snapshot.distanceKilometers),
                        note: ATHLTHLocalization.choose(english: "Where available", norwegian: "Der målt")
                    )
                    ATHLTHStudioMetricCard(
                        title: ATHLTHLocalization.choose(english: "Run / strength", norwegian: "Løp / styrke"),
                        value: "\(snapshot.runningSessions) / \(snapshot.strengthSessions)",
                        note: ATHLTHLocalization.choose(english: "Recorded activities", norwegian: "Registrerte aktiviteter")
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        trainingChart.frame(maxWidth: .infinity)
                        scheduleCard.frame(width: 320)
                    }
                    VStack(spacing: 16) {
                        trainingChart
                        scheduleCard
                    }
                }

                recentCard
            }
            .padding(26)
            .frame(maxWidth: 1600)
            .frame(maxWidth: .infinity)
        }
    }

    private var trainingChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ATHLTHLocalization.choose(
                english: "Training time over time",
                norwegian: "Treningstid over tid"
            ))
            .font(.headline)
            Text(ATHLTHLocalization.choose(
                english: "Daily hours from completed workouts",
                norwegian: "Timer per dag fra gjennomførte økter"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Chart(snapshot.days) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Hours", day.minutes / 60)
                )
                .foregroundStyle(ATHLTHStudioStyle.gold.gradient)
                .cornerRadius(3)
            }
            .frame(height: 235)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Training time by day chart",
                norwegian: "Graf over treningstid per dag"
            ))
            if snapshot.sessions == 0 {
                Text(ATHLTHLocalization.choose(
                    english: "No recorded workouts for this period. Data may be unavailable or Health access may be limited.",
                    norwegian: "Ingen registrerte økter i perioden. Data kan mangle, eller Health-tilgangen kan være begrenset."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHStudioStyle.paper, in: RoundedRectangle(cornerRadius: 20))
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(ATHLTHLocalization.choose(
                english: "Coming up", norwegian: "Kommende økter"
            ))
            .font(.headline)
            if scheduled.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "No upcoming workouts found in your active plans or independent sessions.",
                    norwegian: "Ingen kommende økter i aktive planer eller frittstående økter."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                ForEach(scheduled.prefix(4)) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.workout.kind.systemImage)
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.workout.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(entry.workout.scheduledStart == nil
                                 ? entry.date.formatted(date: .abbreviated, time: .omitted)
                                 : entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if let source = entry.planTitle {
                                Text(source).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    Divider()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 325, alignment: .top)
        .background(ATHLTHStudioStyle.paper, in: RoundedRectangle(cornerRadius: 20))
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(ATHLTHLocalization.choose(
                english: "Recent workouts", norwegian: "Siste treningsøkter"
            ))
            .font(.headline)
            if recent.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Your workout history appears here when available.",
                    norwegian: "Treningshistorikken din vises her når den er tilgjengelig."
                ))
                .foregroundStyle(.secondary)
            }
            ForEach(recent) { workout in
                Button {
                    onInspect(workout)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: icon(for: workout.activity))
                            .font(.title3)
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.activity.rawValue).font(.subheadline.weight(.semibold))
                            Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(workout.duration / 60)) min")
                        if let distance = workout.distanceKilometers {
                            Text(String(format: "%.1f km", distance))
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHStudioStyle.paper, in: RoundedRectangle(cornerRadius: 20))
    }

    private func icon(for activity: WorkoutActivity) -> String {
        switch activity {
        case .running: "figure.run"
        case .walking, .hiking: "figure.walk"
        case .cycling: "bicycle"
        case .strength: "dumbbell"
        default: "figure.mixed.cardio"
        }
    }
}
