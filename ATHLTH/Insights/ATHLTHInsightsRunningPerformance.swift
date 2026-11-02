import Foundation
import SwiftUI
import Charts

/// Every value belongs to one accepted HKWorkout. Do not join daily
/// averages from different workouts, sources, or time windows.
struct ATHLTHInsightsRunPerformanceSession: Identifiable, Equatable {
    let id: UUID
    let endDate: Date
    let durationMinutes: Double
    let averageHeartRateBPM: Double?
    let averageRunningPowerWatts: Double?
    let averageSpeedKPH: Double?
    /// True if average speed came from that workout's total distance/time,
    /// not from a HealthKit running-speed sample.
    let speedFromDistance: Bool

    var hasCompleteMeasurements: Bool {
        guard let averageHeartRateBPM, let averageRunningPowerWatts,
              let averageSpeedKPH else { return false }
        return (35...245).contains(averageHeartRateBPM) &&
            (30...1500).contains(averageRunningPowerWatts) &&
            (3...30).contains(averageSpeedKPH)
    }
}

/// An observed before/after comparison, not an efficiency score or evidence
/// that training caused a heart-rate or power change.
enum ATHLTHInsightsRunComparisonPolicy {
    struct Comparison: Equatable {
        let current: ATHLTHInsightsRunPerformanceSession
        let previous: ATHLTHInsightsRunPerformanceSession

        var heartRateChange: Double {
            (current.averageHeartRateBPM ?? 0) -
                (previous.averageHeartRateBPM ?? 0)
        }
        var powerChange: Double {
            (current.averageRunningPowerWatts ?? 0) -
                (previous.averageRunningPowerWatts ?? 0)
        }
        var speedChange: Double {
            (current.averageSpeedKPH ?? 0) -
                (previous.averageSpeedKPH ?? 0)
        }
    }

    static func closestComparable(
        to current: ATHLTHInsightsRunPerformanceSession,
        among sessions: [ATHLTHInsightsRunPerformanceSession]
    ) -> Comparison? {
        guard current.hasCompleteMeasurements,
              let currentSpeed = current.averageSpeedKPH,
              current.durationMinutes >= 15 else { return nil }
        let candidates = sessions.filter { previous in
            guard previous.id != current.id,
                  previous.endDate < current.endDate,
                  previous.hasCompleteMeasurements,
                  previous.speedFromDistance == current.speedFromDistance,
                  let speed = previous.averageSpeedKPH,
                  currentSpeed > 0 else { return false }
            return abs(speed - currentSpeed) / currentSpeed <= 0.08 &&
                abs(previous.durationMinutes - current.durationMinutes) /
                    current.durationMinutes <= 0.25
        }
        // Favor the closest speed and duration, not the "best looking"
        // heart-rate or power result.
        let reference = candidates.min { a, b in
            func distance(_ item: ATHLTHInsightsRunPerformanceSession) -> Double {
                let speedDifference = abs(
                    (item.averageSpeedKPH ?? currentSpeed) - currentSpeed
                ) / currentSpeed
                let durationDifference = abs(
                    item.durationMinutes - current.durationMinutes
                ) / current.durationMinutes
                return speedDifference * 2 + durationDifference
            }
            let da = distance(a), db = distance(b)
            return da == db ? a.endDate > b.endDate : da < db
        }
        guard let reference else { return nil }
        return Comparison(current: current, previous: reference)
    }
}

/// Lazy detail destination, only queries HealthKit after the user chooses
/// running comparison in Insights > Training.
struct ATHLTHInsightsRunningPerformanceView: View {
    @EnvironmentObject private var health: HealthKitManager
    @State private var periodDays = 90
    @State private var sessions: [ATHLTHInsightsRunPerformanceSession] = []
    @State private var loading = true
    @State private var failed = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var completeSessions: [ATHLTHInsightsRunPerformanceSession] {
        sessions.filter(\.hasCompleteMeasurements)
    }

    private var latestComplete: ATHLTHInsightsRunPerformanceSession? {
        completeSessions.first
    }

    private var comparison: ATHLTHInsightsRunComparisonPolicy.Comparison? {
        guard let latestComplete else { return nil }
        return ATHLTHInsightsRunComparisonPolicy.closestComparable(
            to: latestComplete, among: completeSessions
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("One workout. Three measurements.",
                            "Én økt. Tre målinger."))
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHInsightsStyle.ink)
                    Text(tr(
                        "Average pulse, running power and speed from the same recorded run.",
                        "Gjennomsnittspuls, løpskraft og hastighet fra samme registrerte løpetur."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                }

                Picker(tr("Period", "Periode"), selection: $periodDays) {
                    Text("30d").tag(30)
                    Text("90d").tag(90)
                    Text("180d").tag(180)
                }
                .pickerStyle(.segmented)

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if sessions.isEmpty {
                    ContentUnavailableView(
                        tr("No recorded runs", "Ingen registrerte løpeøkter"),
                        systemImage: "figure.run",
                        description: Text(tr(
                            "Record a run in ATHLTH or approve an imported workout to compare its health measurements.",
                            "Registrer en løpetur i ATHLTH, eller godkjenn en importert økt for å sammenligne målingene."
                        ))
                    )
                } else {
                    if let run = latestComplete {
                        latestRunCard(run)
                    } else {
                        unavailableCard
                    }

                    if let comparison {
                        comparisonCard(comparison)
                    } else if latestComplete != nil {
                        explanationCard(
                            title: tr("No comparable run yet", "Ingen sammenlignbar økt ennå"),
                            detail: tr(
                                "A comparison needs two recorded runs with pulse, power and speed, within 8% speed and 25% duration.",
                                "Sammenligning krever to løpeturer med puls, watt og hastighet, innenfor 8 % hastighet og 25 % varighet."
                            )
                        )
                    }

                    if completeSessions.count >= 2 {
                        trendChart
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Recorded runs", "Registrerte løpeturer"))
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .foregroundStyle(ATHLTHInsightsStyle.ink)
                        ForEach(sessions) { item in
                            sessionRow(item)
                        }
                    }
                    .padding(16)
                    .athlthInsightsSurface()
                }

                Text(tr(
                    "Numbers reflect measurements associated with each workout. Changes can also be affected by route, elevation, weather, pauses and sensor quality. No medical or training-efficiency conclusions are drawn.",
                    "Tallene er hentet fra den enkelte økten. Endringer kan også skyldes rute, stigning, vær, pauser og sensorforhold. Vi trekker ikke medisinske konklusjoner eller gir en automatisk effektivitetsvurdering."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
            .padding(17)
            .frame(maxWidth: ATHLTHTrainDesign.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHInsightsStyle.canvas.ignoresSafeArea())
        .navigationTitle(tr("Running comparison", "Sammenlign løping"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: periodDays) { await load() }
        .refreshable { await load() }
    }

    private var unavailableCard: some View {
        explanationCard(
            title: tr("More data needed", "Trenger flere målinger"),
            detail: tr(
                "The recorded runs do not yet contain all three measurements. Power requires a compatible device and Health permission. Missing values stay blank.",
                "De registrerte øktene har foreløpig ikke alle tre målingene. Watt krever kompatibel enhet og Helse-tilgang. Manglende verdier forblir tomme."
            )
        )
    }

    private func explanationCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthInsightsSurface()
    }

    private func latestRunCard(
        _ run: ATHLTHInsightsRunPerformanceSession
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Latest run with complete measurements",
                    "Siste økt med komplette målinger"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHInsightsStyle.accent)
            Text(run.endDate.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            metricTriplet(run)
            Text(tr(
                run.speedFromDistance
                    ? "Speed = recorded distance / workout duration; other metrics are recorded averages."
                    : "All three values are averages recorded for this workout.",
                run.speedFromDistance
                    ? "Fart = registrert distanse / øktvarighet; øvrige tall er registrerte gjennomsnitt."
                    : "Alle tre verdiene er gjennomsnitt fra denne treningsøkten."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private func comparisonCard(
        _ result: ATHLTHInsightsRunComparisonPolicy.Comparison
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("At similar running speed", "Ved lignende løpshastighet"))
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            Text(
                result.previous.endDate.formatted(date: .abbreviated, time: .omitted)
                    + " → " +
                result.current.endDate.formatted(date: .abbreviated, time: .omitted)
            )
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)

            HStack(spacing: 8) {
                changeTile(tr("Pulse", "Puls"), result.heartRateChange, "bpm")
                changeTile(tr("Power", "Watt"), result.powerChange, "W")
                changeTile(tr("Speed", "Fart"), result.speedChange, "km/t", 1)
            }
            Text(tr(
                "Differences are observed, not a fitness score. The comparison matches running speed (±8%) and session duration (±25%), but cannot control terrain or conditions.",
                "Dette er registrerte forskjeller, ikke en formscore. Øktene har lignende fart (±8 %) og varighet (±25 %), men terreng og forhold er ikke kontrollert."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private func changeTile(
        _ title: String, _ value: Double, _ unit: String, _ decimals: Int = 0
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            Text(
                (value > 0 ? "+" : "") +
                    value.formatted(.number.precision(.fractionLength(decimals))) +
                    " " + unit
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHInsightsStyle.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            ATHLTHInsightsStyle.canvas,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func metricTriplet(
        _ session: ATHLTHInsightsRunPerformanceSession
    ) -> some View {
        HStack(spacing: 8) {
            metric(tr("Pulse", "Puls"), session.averageHeartRateBPM, "bpm", 0)
            metric(tr("Power", "Watt"), session.averageRunningPowerWatts, "W", 0)
            metric(tr("Speed", "Fart"), session.averageSpeedKPH, "km/t", 1)
        }
    }

    private func metric(
        _ label: String, _ value: Double?, _ unit: String, _ decimals: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            Text(value.map {
                $0.formatted(.number.precision(.fractionLength(decimals))) +
                    " " + unit
            } ?? "—")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHInsightsStyle.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            ATHLTHInsightsStyle.canvas,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Pulse at recorded speed", "Puls ved registrert hastighet"))
                .font(.headline)
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            Chart(completeSessions) { item in
                if let speed = item.averageSpeedKPH,
                   let heart = item.averageHeartRateBPM {
                    PointMark(
                        x: .value("km/t", speed),
                        y: .value("bpm", heart)
                    )
                    .symbolSize(70)
                    .foregroundStyle(ATHLTHInsightsStyle.accent)
                }
            }
            .chartXAxisLabel("km/t")
            .chartYAxisLabel("bpm")
            .frame(height: 178)
            Text(tr(
                "Each point is a recorded run; watt for that run is listed below.",
                "Hvert punkt er en registrert løpetur. Watt for økten vises i listen under."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHInsightsStyle.muted)
        }
        .padding(16)
        .athlthInsightsSurface()
    }

    private func sessionRow(
        _ item: ATHLTHInsightsRunPerformanceSession
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(item.endDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Spacer()
                Text(
                    "\(Int(item.durationMinutes.rounded())) " +
                        tr("min", "min")
                )
                .font(.caption)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
            metricTriplet(item)
            if item.speedFromDistance {
                Text(tr(
                    "Speed calculated from workout distance/time",
                    "Fart beregnet fra øktens distanse og tid"
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        failed = false
        let fetched = await health.insightRunningPerformanceSessions(
            days: periodDays
        )
        guard !Task.isCancelled else { return }
        sessions = fetched
        loading = false
    }
}
