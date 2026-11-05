import Charts
import SwiftUI

/// Compares *observed* HealthKit training with *scheduled* activity.
/// A duration chart is not a cardiovascular or injury-risk prediction.
struct ATHLTHStudioTrainingLoadView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @State private var showsTrainingSignals = false

    private struct Volume: Identifiable {
        let kind: String
        let period: String
        let minutes: Double
        var id: String { kind + "-" + period }
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var observed: [WorkoutSummary] {
        let start = Calendar.current.date(
            byAdding: .day, value: -7, to: .now
        ) ?? .distantPast
        return health.workouts.filter {
            $0.startDate >= start && $0.startDate <= .now &&
            $0.duration.isFinite && $0.duration > 0
        }
    }

    private var scheduled: [ATHLTHStudioSchedule.Occurrence] {
        ATHLTHStudioSchedule.upcoming(
            plans: session.activePlan.map { [$0] } ?? [],
            standalone: session.standalonePlannedSessions,
            now: .now, days: 7
        )
    }

    private func category(_ activity: WorkoutActivity) -> String {
        if activity == .running { return tr("Running", "Løping") }
        if activity == .strength { return tr("Strength", "Styrke") }
        return tr("Other", "Annet")
    }

    private func category(_ kind: ATHLTHPlannedWorkoutType) -> String {
        if kind == .running { return tr("Running", "Løping") }
        if kind == .strength { return tr("Strength", "Styrke") }
        return tr("Other", "Annet")
    }

    private var volumes: [Volume] {
        let categories = [
            tr("Running", "Løping"),
            tr("Strength", "Styrke"),
            tr("Other", "Annet")
        ]
        return categories.flatMap { name in
            let recorded = observed.filter {
                category($0.activity) == name
            }.reduce(0.0) { $0 + max(0, $1.duration) / 60 }
            let planned = scheduled.filter {
                category($0.workout.kind) == name
            }.reduce(0.0) {
                $0 + Double(max(0, $1.workout.durationMinutes ?? 0))
            }
            return [
                Volume(kind: name,
                       period: tr("Completed", "Gjennomført"),
                       minutes: recorded),
                Volume(kind: name,
                       period: tr("Scheduled", "Planlagt"),
                       minutes: planned)
            ]
        }
    }

    private var recordedTotal: Double {
        observed.reduce(0) { $0 + max(0, $1.duration) / 60 }
    }
    private var plannedTotal: Int {
        scheduled.reduce(0) { $0 + max(0, $1.workout.durationMinutes ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("TRAINING VOLUME", "TRENINGSMENGDE"))
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    Text(tr("Actual and planned, side by side",
                            "Gjennomført og planlagt ved siden av hverandre"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                }
                Spacer(minLength: 0)
                Button {
                    showsTrainingSignals = true
                } label: {
                    Label(tr("Training signals", "Treningssignaler"),
                          systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.bordered)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { metricCards }
                VStack(spacing: 10) { metricCards }
            }
            Chart(volumes) { row in
                BarMark(
                    x: .value(tr("Activity", "Aktivitet"), row.kind),
                    y: .value(tr("Minutes", "Minutter"), row.minutes)
                )
                .position(by: .value(tr("Series", "Serie"), row.period))
                .foregroundStyle(row.period == tr("Completed", "Gjennomført")
                    ? ATHLTHStudioStyle.gold : ATHLTHStudioStyle.ink.opacity(0.7))
            }
            .frame(height: 185)
            HStack(spacing: 15) {
                Label(tr("Recorded · last 7 days",
                         "Gjennomført · siste 7 dager"),
                      systemImage: "checkmark.circle")
                .foregroundStyle(ATHLTHStudioStyle.gold)
                Label(tr("Upcoming · next 7 days",
                         "Planlagt · neste 7 dager"),
                      systemImage: "calendar")
                .foregroundStyle(ATHLTHStudioStyle.ink)
            }
            .font(.caption)
            Text(tr(
                "Only recorded sessions count as completed. Planned durations may be missing. This is training volume, not muscular fatigue, clinical recovery, a readiness score or a forecast of injury.",
                "Kun registrerte økter regnes som gjennomført. Varighet kan mangle i planlagte økter. Dette viser treningsmengde – ikke muskulær utmattelse, medisinsk restitusjon, beredskapsscore eller skaderisiko."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.5))
        }
        .sheet(isPresented: $showsTrainingSignals) {
            ATHLTHInsightsView()
                .presentationDetents([.large])
        }
        .accessibilityIdentifier("athlth-ipad-training-volume")
    }

    @ViewBuilder
    private var metricCards: some View {
        ATHLTHStudioMetricCard(
            title: tr("Last seven days", "Siste syv dager"),
            value: "\(Int(recordedTotal.rounded())) min",
            note: tr("Recorded Health workouts", "Registrerte Health-økter")
        )
        ATHLTHStudioMetricCard(
            title: tr("Next seven days", "Neste syv dager"),
            value: "\(plannedTotal) min",
            note: tr("Known planned duration", "Kjent planlagt varighet")
        )
    }
}
