import Foundation
import SwiftUI

/// A measured training signal needs a real recorded day, not an inferred
/// value from workout duration, age, or general recovery readiness.
enum ATHLTHInsightsTrainingSignalPolicy {
    static func latest(
        in days: [ATHLTHInsightHealthDay],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ATHLTHInsightHealthDay? {
        let today = calendar.startOfDay(for: now)
        let earliest = calendar.date(
            byAdding: .day, value: -27, to: today
        ) ?? now.addingTimeInterval(-27 * 86_400)

        return days.filter {
            $0.date >= earliest &&
            $0.date <= now &&
            $0.value.isFinite &&
            $0.value > 0
        }
        .max { $0.date < $1.date }
    }
}

/// One editorial training section, not another wall of health metrics.
/// Workout-related measurements remain on-device and are loaded only
/// when the Training tab of Insights is actually opened.
struct ATHLTHInsightsTrainingSignalsCard: View {
    @EnvironmentObject private var health: HealthKitManager
    @State private var runningPower: ATHLTHInsightHealthDay?
    @State private var runningSpeed: ATHLTHInsightHealthDay?
    @State private var isLoadingRunning = true

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("Training signals", "Treningssignaler"))
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Text(tr(
                    "Useful Apple Health measurements connected to your workouts. No invented performance scores.",
                    "Apple Health-målinger som kan brukes i treningen. Ingen kunstige prestasjonsscorer."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }

            sectionHeading(
                tr("Running mechanics", "Løpsmålinger"),
                icon: "figure.run"
            )
            HStack(spacing: 8) {
                metricLink(.runningPower, reading: runningPower, loading: isLoadingRunning)
                metricLink(.runningSpeed, reading: runningSpeed, loading: isLoadingRunning)
            }
            Text(tr(
                "Track power and speed across similar running sessions. These daily averages do not establish running efficiency on their own.",
                "Følg løpskraft og hastighet på sammenlignbare løpeøkter. Dagsgjennomsnitt alene sier ikke hvor effektiv løpingen er."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
            NavigationLink {
                ATHLTHInsightsHealthMetricDetailView(metric: .runningGroundContactTime)
            } label: {
                HStack(spacing: 5) {
                    Text(tr("See ground-contact time", "Se bakkekontakttid"))
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHInsightsStyle.accent)
            }
            .buttonStyle(.plain)

            Divider().overlay(ATHLTHInsightsStyle.track)

            sectionHeading(
                tr("Training and daily movement", "Trening og hverdagsaktivitet"),
                icon: "flame"
            )
            HStack(spacing: 8) {
                todayLink(
                    .activeEnergy,
                    value: health.training.activeEnergyKilocaloriesToday
                )
                todayLink(
                    .exerciseMinutes,
                    value: health.training.exerciseMinutesToday
                )
            }
            Text(tr(
                "Activity energy and exercise minutes include recorded movement outside ATHLTH workouts. They are not calories burned by a particular session.",
                "Aktiv energi og treningsminutter kan også komme fra aktivitet utenom ATHLTH-økter. Tallene er ikke energiforbruket i én bestemt økt."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)

            Divider().overlay(ATHLTHInsightsStyle.track)

            sectionHeading(
                tr("Response after exercise", "Respons etter trening"),
                icon: "heart.text.square"
            )
            NavigationLink {
                ATHLTHInsightsHealthMetricDetailView(metric: .heartRateRecovery)
            } label: {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Heart-rate recovery", "Pulsfall etter økt"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                        Text(tr(
                            "View recorded or measured-derived pulse drop after a workout.",
                            "Se registrert eller beregnet pulsfall fra faktiske pulsmålinger."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                }
                .padding(12)
                .background(
                    ATHLTHInsightsStyle.canvas,
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)

            Text(tr(
                "Look for your personal pattern across comparable workouts, not a diagnosis or automatic intensity target.",
                "Se etter egne mønstre på sammenlignbare økter. Dette er verken en diagnose eller et automatisk intensitetsmål."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
        }
        .padding(16)
        .athlthInsightsSurface()
        .task(id: health.lastSuccessfulRefreshAt) {
            isLoadingRunning = true
            let powerDays = await health.insightDailyValues(
                for: .runningPower, days: 28
            )
            guard !Task.isCancelled else { return }
            let speedDays = await health.insightDailyValues(
                for: .runningSpeed, days: 28
            )
            guard !Task.isCancelled else { return }

            runningPower = ATHLTHInsightsTrainingSignalPolicy.latest(
                in: powerDays
            )
            runningSpeed = ATHLTHInsightsTrainingSignalPolicy.latest(
                in: speedDays
            )
            isLoadingRunning = false
        }
    }

    private func sectionHeading(_ name: String, icon: String) -> some View {
        Label(name, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHInsightsStyle.ink)
    }

    private func metricLink(
        _ metric: ATHLTHInsightHealthMetric,
        reading: ATHLTHInsightHealthDay?,
        loading: Bool
    ) -> some View {
        NavigationLink {
            ATHLTHInsightsHealthMetricDetailView(metric: metric)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                Text(loading ? "…" : metric.formatted(reading?.value))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                Text(reading.map {
                    $0.date.formatted(date: .abbreviated, time: .omitted)
                } ?? tr("No reading", "Ingen måling"))
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                ATHLTHInsightsStyle.canvas,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }

    private func todayLink(
        _ metric: ATHLTHInsightHealthMetric,
        value: Double?
    ) -> some View {
        NavigationLink {
            ATHLTHInsightsHealthMetricDetailView(metric: metric)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                Text(metric.formatted(value))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                Text(tr("Today", "I dag"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                ATHLTHInsightsStyle.canvas,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }
}
