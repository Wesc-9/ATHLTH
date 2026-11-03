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

/// Real recorded heart-rate time; this is NOT a readiness or performance score.
/// Percentages exclude gaps and readings below 50% of the user's HRmax.
struct ATHLTHInsightZoneDistribution: Equatable {
    let zoneSeconds: [Double]
    let matchedWorkouts: Int
    let maximumHeartRateBPM: Int

    var totalSeconds: Double { zoneSeconds.reduce(0, +) }

    func fraction(for index: Int) -> Double {
        guard zoneSeconds.indices.contains(index), totalSeconds > 0 else {
            return 0
        }
        return zoneSeconds[index] / totalSeconds
    }
}

/// Advanced, training-specific Insights. All colors and surfaces are reused
/// from ATHLTHInsightsStyle; no global theme or Overview changes are made.
struct ATHLTHInsightsTrainingSignalsCard: View {
    let trainingLoad: RecoveryTrainingLoadSummary
    let trainingDays: [ATHLTHInsightsTrainingDay]

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore

    @State private var zones: ATHLTHInsightZoneDistribution?
    @State private var runs: [ATHLTHInsightsRunPerformanceSession] = []
    @State private var recoveryDays: [ATHLTHInsightHealthDay] = []
    @State private var isLoading = true

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var count: Int { trainingDays.reduce(0) { $0 + $1.sessions } }
    private var activeDays: Int { trainingDays.filter { $0.sessions > 0 }.count }
    private var restDays: Int { max(0, trainingDays.count - activeDays) }

    private var loadPercent: Double? {
        guard health.hasRequestedAuthorization, health.healthDataAvailable,
              let reference = trainingLoad.chronicWeeklyAverageMinutes,
              reference > 0 else { return nil }
        return (trainingLoad.acuteMinutes / reference - 1) * 100
    }

    private func percentLabel(_ value: Double) -> String {
        let rounded = Int(abs(value).rounded())
        return (value >= 0 ? "+" : "−") + "\(rounded) %"
    }

    private func durationLabel(_ minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        let hours = total / 60
        let remainder = total % 60
        return hours > 0
            ? tr("\(hours)h \(remainder)m", "\(hours) t \(remainder) min")
            : "\(remainder) min"
    }

    private var primaryLoadText: String {
        guard health.hasRequestedAuthorization,
              health.healthDataAvailable else { return "—" }
        return durationLabel(trainingLoad.acuteMinutes)
    }

    private var signalsRefreshKey: String {
        "\(health.lastSuccessfulRefreshAt?.timeIntervalSince1970 ?? 0):" +
            "\(session.profile.maximumHeartRateBPM ?? 0)"
    }

    private var loadExplanation: String {
        guard health.hasRequestedAuthorization,
              health.healthDataAvailable else {
            return tr(
                "Connect Apple Health to view your training load.",
                "Koble til Apple Helse for å se treningsbelastningen din."
            )
        }
        guard let change = loadPercent else {
            return tr(
                "A four-week comparison will appear after more recorded workouts.",
                "Sammenligning med fireukerssnittet vises når flere økter er registrert."
            )
        }
        if change >= 50 {
            return tr(
                "Your recorded training time is much higher than your four-week average. Consider your recovery and the distribution of hard sessions.",
                "Registrert treningstid er betydelig over fireukerssnittet. Vurder restitusjon og fordelingen av harde økter."
            )
        }
        if change >= 15 {
            return tr(
                "Training time is above your recent average. Follow the trend across several weeks.",
                "Treningstiden er høyere enn normalt. Følg utviklingen over flere uker."
            )
        }
        if change <= -25 {
            return tr(
                "Training time is below your recent average. This can reflect a lighter week or fewer recorded sessions.",
                "Treningstiden er under snittet. Det kan være en lettere uke eller færre registrerte økter."
            )
        }
        return tr(
            "Recorded weekly training time is close to your four-week average.",
            "Registrert ukentlig treningstid ligger nær fireukerssnittet."
        )
    }

    private var latestRun: ATHLTHInsightsRunPerformanceSession? {
        runs.first {
            $0.averageRunningPowerWatts != nil ||
            $0.averageSpeedKPH != nil
        }
    }

    private var runComparison: ATHLTHInsightsRunComparisonPolicy.Comparison? {
        guard let latestRun else { return nil }
        return ATHLTHInsightsRunComparisonPolicy.closestComparable(
            to: latestRun, among: runs
        )
    }

    private func runDelta(_ isPower: Bool) -> String {
        guard let comparison = runComparison else {
            return tr("No comparable session", "Ingen sammenlignbar økt")
        }
        let current = isPower
            ? comparison.current.averageRunningPowerWatts
            : comparison.current.averageSpeedKPH
        let previous = isPower
            ? comparison.previous.averageRunningPowerWatts
            : comparison.previous.averageSpeedKPH
        guard let current, let previous, previous > 0 else {
            return tr("No comparison", "Ingen sammenligning")
        }
        return percentLabel((current / previous - 1) * 100) +
            tr(" vs similar run", " mot lignende løp")
    }

    private var lastRecovery: ATHLTHInsightHealthDay? {
        ATHLTHInsightsTrainingSignalPolicy.latest(in: recoveryDays)
    }

    private var recoveryDifference: Double? {
        guard let current = lastRecovery else { return nil }
        let start = current.date.addingTimeInterval(-28 * 86_400)
        let previous = recoveryDays.filter {
            $0.date < current.date && $0.date >= start &&
            $0.value.isFinite && $0.value > 0
        }
        guard previous.count >= 3 else { return nil }
        let average = previous.reduce(0.0) { $0 + $1.value } /
            Double(previous.count)
        return current.value - average
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("Training signals", "Treningssignaler"))
                    .font(.system(size: 23, weight: .regular, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Text(tr(
                    "Understand training load, quality and response.",
                    "Forstå belastning, kvalitet og respons for å trene smartere."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
            .padding(.horizontal, 2)

            loadCard
            qualityCard
            responseCard
            coachingCard
        }
        .task(id: signalsRefreshKey) {
            await refreshMeasuredSignals()
        }
    }

    private var loadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(tr("Load and balance", "Belastning og balanse"),
                    icon: "chart.bar.xaxis")

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Weekly volume", "Ukesbelastning"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                    Text(primaryLoadText)
                        .font(.system(size: 30, weight: .medium, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if let change = loadPercent {
                        Text(percentLabel(change) + tr(
                            " vs four-week average", " mot 4-ukers snitt"
                        ))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                    } else {
                        Text(tr("Four-week baseline unavailable",
                                "Mangler fireukersgrunnlag"))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHInsightsStyle.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(trainingLoad.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHInsightsStyle.accent)
                    Text(loadExplanation)
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(ATHLTHInsightsStyle.track)

            HStack(alignment: .top, spacing: 8) {
                miniMetric(
                    tr("Training time", "Treningstid"),
                    value: primaryLoadText,
                    detail: tr("Last 7 days", "Siste 7 dager"),
                    symbol: "timer"
                )
                miniMetric(
                    tr("Workouts", "Økter"),
                    value: health.hasRequestedAuthorization &&
                        health.healthDataAvailable ? "\(count)" : "—",
                    detail: tr("Last 7 days", "Siste 7 dager"),
                    symbol: "figure.run"
                )
                miniMetric(
                    tr("No workout", "Uten økt"),
                    value: health.hasRequestedAuthorization &&
                        health.healthDataAvailable &&
                        trainingDays.count == 7
                        ? "\(restDays)" : "—",
                    detail: tr("of 7 days", "av 7 dager"),
                    symbol: "calendar"
                )
            }
            Text(tr(
                "Load here means recorded workout minutes, not an invented AU score. A day without a workout is not necessarily a recovery day.",
                "Belastning betyr registrerte treningsminutter, ikke en beregnet AU-score. En dag uten økt er ikke nødvendigvis en hviledag."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            heading(tr("Workout quality", "Kvalitet i øktene"),
                    icon: "bolt.fill")
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Heart-rate zone distribution",
                        "Fordeling i pulssoner"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Spacer(minLength: 0)
                Text(tr("7 days", "7 dager"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
            }

            if let zones {
                ForEach(0..<5, id: \.self) { zone in
                    HStack(spacing: 10) {
                        Text("Z\(zone + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                            .frame(width: 24, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(ATHLTHInsightsStyle.track)
                                Capsule()
                                    .fill(ATHLTHInsightsStyle.accent)
                                    .frame(width: max(
                                        0,
                                        geometry.size.width *
                                            zones.fraction(for: zone)
                                    ))
                            }
                        }
                        .frame(height: 9)
                        Text("\(Int((zones.fraction(for: zone) * 100).rounded())) %")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Text(tr(
                    "Recorded heart-rate time across \(zones.matchedWorkouts) workouts. Sensor gaps and readings below Z1 are excluded.",
                    "Målt pulstid fra \(zones.matchedWorkouts) økter. Sensorhull og puls under Z1 er utelatt."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            } else {
                Label(
                    isLoading
                        ? tr("Reading heart-rate data…", "Henter pulsdata …")
                        : tr(
                            "Zones require a configured maximum heart rate and enough recorded workout heart-rate data.",
                            "Pulssoner krever angitt makspuls og tilstrekkelige pulsmålinger fra treningsøkter."
                        ),
                    systemImage: "heart.text.square"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHInsightsStyle.canvas,
                            in: RoundedRectangle(cornerRadius: 13))
            }

            Divider().overlay(ATHLTHInsightsStyle.track)

            Text(tr("Running measurements", "Løpsmålinger"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            HStack(spacing: 9) {
                performanceMetric(
                    .runningPower,
                    value: latestRun?.averageRunningPowerWatts,
                    delta: runDelta(true)
                )
                performanceMetric(
                    .runningSpeed,
                    value: latestRun?.averageSpeedKPH,
                    delta: runDelta(false)
                )
            }
            if let latestRun {
                Text(tr(
                    "Both values refer to the run on \(latestRun.endDate.formatted(date: .abbreviated, time: .omitted)). Comparisons only appear for similar sessions.",
                    "Målingene gjelder løpeøkten \(latestRun.endDate.formatted(date: .abbreviated, time: .omitted)). Sammenligning vises bare for lignende økter."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }

            NavigationLink {
                ATHLTHInsightsRunningPerformanceView()
            } label: {
                Label(tr("Compare running workouts", "Sammenlign løpeøkter"),
                      systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(tr("Response after training", "Respons etter trening"),
                    icon: "heart.text.square")

            NavigationLink {
                ATHLTHInsightsHealthMetricDetailView(metric: .heartRateRecovery)
            } label: {
                HStack(alignment: .top, spacing: 13) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Heart-rate recovery", "Pulsfall etter økt"))
                            .font(.caption)
                            .foregroundStyle(ATHLTHInsightsStyle.muted)
                        Text(lastRecovery.map {
                            ATHLTHInsightHealthMetric.heartRateRecovery.formatted(
                                $0.value
                            )
                        } ?? "—")
                            .font(.system(size: 27, weight: .medium,
                                          design: .serif))
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                            .monospacedDigit()
                        if let delta = recoveryDifference {
                            Text(
                                (delta >= 0 ? "+" : "−") +
                                "\(Int(abs(delta).rounded())) " +
                                tr("beats vs previous 28-day readings",
                                   "slag mot forrige 28-dagers målinger")
                            )
                            .font(.caption2)
                            .foregroundStyle(ATHLTHInsightsStyle.accent)
                        } else {
                            Text(tr("Not enough comparable readings",
                                    "For få sammenlignbare målinger"))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHInsightsStyle.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Label(tr("Measured response", "Målt respons"),
                              systemImage: "waveform.path.ecg")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHInsightsStyle.accent)
                        Text(tr(
                            "Heart-rate drop after exercise is one observation. Compare similar workouts rather than interpreting a single value as your fitness.",
                            "Pulsfall etter trening er én observasjon. Sammenlign lignende økter fremfor å tolke én måling som kondisjon."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHInsightsStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        if lastRecovery?.isEstimated == true {
                            Text(tr("Calculated from real pulse samples",
                                    "Beregnet fra faktiske pulsmålinger"))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHInsightsStyle.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private var coachingTitle: String {
        if let change = loadPercent, change >= 50 {
            return tr("A bigger training week",
                      "En betydelig tyngre treningsuke")
        }
        if let zones, zones.fraction(for: 3) +
            zones.fraction(for: 4) >= 0.25 {
            return tr("A lot of high-intensity time",
                      "Stor andel høy intensitet")
        }
        if loadPercent != nil || zones != nil || lastRecovery != nil {
            return tr("See the full pattern", "Se etter helheten")
        }
        return tr("Building your training picture",
                  "Bygger opp treningsbildet")
    }

    private var coachingDetail: String {
        if let change = loadPercent, change >= 50 {
            return tr(
                "Weekly volume is well above your four-week average. Look at how hard sessions and easier days are distributed before adding more.",
                "Ukesvolumet ligger godt over fireukerssnittet. Se på fordelingen av harde økter og lettere dager før du øker mer."
            )
        }
        if let zones, zones.fraction(for: 3) +
            zones.fraction(for: 4) >= 0.25 {
            return tr(
                "At least a quarter of recorded HR-zone time is in Z4–Z5. Check how that intensity is spread across sessions.",
                "Minst en fjerdedel av målt pulstid er i Z4–Z5. Se hvordan intensiteten fordeler seg mellom øktene."
            )
        }
        if loadPercent != nil || zones != nil || lastRecovery != nil {
            return tr(
                "Review load, measured intensity and post-exercise pulse together over several weeks. One metric alone cannot define training progress.",
                "Vurder belastning, målt intensitet og pulsfall samlet over flere uker. Én måling alene sier ikke om formen har blitt bedre."
            )
        }
        return tr(
            "Record workouts and relevant heart-rate data to see more specific training patterns. No performance values are estimated.",
            "Registrer økter og pulsdata for å se tydeligere treningsmønstre. Prestasjonsverdier blir ikke anslått."
        )
    }

    private var coachingCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(ATHLTHInsightsStyle.accent)
                .frame(width: 36, height: 36)
                .background(ATHLTHInsightsStyle.accent.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 7) {
                Text(tr("Training insight", "Treningsinnsikt"))
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Text(coachingTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Text(coachingDetail)
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthInsightsSurface()
    }

    private func heading(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 20, weight: .medium, design: .serif))
            .foregroundStyle(ATHLTHInsightsStyle.ink)
    }

    private func miniMetric(
        _ label: String,
        value: String,
        detail: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.accent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ATHLTHInsightsStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func performanceMetric(
        _ metric: ATHLTHInsightHealthMetric,
        value: Double?,
        delta: String
    ) -> some View {
        NavigationLink {
            ATHLTHInsightsHealthMetricDetailView(metric: metric)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(metric.formatted(value))
                    .font(.system(size: 19, weight: .semibold,
                                  design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(delta)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 87, alignment: .leading)
            .padding(11)
            .background(ATHLTHInsightsStyle.canvas,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func refreshMeasuredSignals() async {
        guard health.hasRequestedAuthorization,
              health.healthDataAvailable,
              !health.shouldDeferAutomaticHealthWork else {
            zones = nil
            runs = []
            recoveryDays = []
            isLoading = false
            return
        }

        isLoading = true
        let hrMax = session.profile.maximumHeartRateBPM
        async let zoneQuery = health.insightHeartRateZoneDistribution(
            maximumHeartRateBPM: hrMax, days: 7
        )
        async let runningQuery = health.insightRunningPerformanceSessions(days: 90)
        async let recoveryQuery = health.insightDailyValues(
            for: .heartRateRecovery, days: 56
        )

        let (distribution, runValues, recoveryValues) = await (
            zoneQuery, runningQuery, recoveryQuery
        )
        guard !Task.isCancelled else { return }
        zones = distribution
        runs = runValues.sorted { $0.endDate > $1.endDate }
        recoveryDays = recoveryValues
        isLoading = false
    }
}
