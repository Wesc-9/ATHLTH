import Charts
import SwiftUI

/// ATHLTH's post-run physiology surface. Charts measured HealthKit samples;
/// uncovered periods and missing maximum heart rate remain explicitly unknown.
struct ATHLTHRunningPulseResultCard: View {
    let points: [ATHLTHRunningHeartRatePoint]
    let averageBPM: Double?
    let maximumBPM: Double?
    let athleteMaximumBPM: Double?
    let isStructured: Bool

    private struct ChartPoint: Identifiable {
        let date: Date
        let bpm: Double
        let segment: Int
        var id: Date { date }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var plotted: [ChartPoint] {
        let reduced = ATHLTHRunningHeartRateAnalysis.chartPoints(points)
        var group = 0
        var previous: Date?
        return reduced.map { point in
            if let previous, point.date.timeIntervalSince(previous) > 90 {
                group += 1
            }
            previous = point.date
            return ChartPoint(date: point.date, bpm: point.bpm, segment: group)
        }
    }

    private var zones: [ATHLTHRunningHeartRateAnalysis.ZoneDuration] {
        ATHLTHRunningHeartRateAnalysis.zoneDurations(
            points, maximumBPM: athleteMaximumBPM
        )
    }

    private var zoneTotal: Double {
        zones.reduce(0) { $0 + $1.seconds }
    }

    private var observedPeak: Double? {
        points.map(\.bpm).max()
    }

    private func bpmText(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        return "\(Int(value.rounded()))"
    }

    private func timeText(_ seconds: Double) -> String {
        let time = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", time / 60, time % 60)
    }

    var body: some View {
        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 33, height: 33)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Pulse through the run", "Pulsen gjennom økten"))
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(isStructured
                             ? tr("See the responses to each effort and recovery.",
                                  "Se hvordan pulsen reagerte på drag og pauser.")
                             : tr("Measured pulse across the workout.",
                                  "Registrerte pulsmålinger gjennom løpeturen."))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }

                HStack(spacing: 16) {
                    pulseStat(tr("AVERAGE", "SNITT"), bpmText(averageBPM))
                    Rectangle().fill(ATHLTHPlanDesign.warmDivider)
                        .frame(width: 1, height: 35)
                    pulseStat(tr("MAXIMUM", "MAKS"), bpmText(maximumBPM ?? observedPeak))
                }

                if plotted.count >= 2 {
                    Chart(plotted) { point in
                        LineMark(
                            x: .value(tr("Time", "Tid"), point.date),
                            y: .value(tr("Pulse", "Puls"), point.bpm),
                            series: .value("Measured segment", point.segment)
                        )
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                    .chartYScale(domain: 40...max(
                        110, min(240, (plotted.map(\.bpm).max() ?? 170) + 14)
                    ))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) {
                            AxisValueLabel(format: .dateTime.hour().minute())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 185)
                    .accessibilityLabel(tr(
                        "Recorded pulse over time with gaps where the sensor has no readings.",
                        "Registrert puls over tid, med brudd der sensoren mangler målinger."
                    ))
                } else {
                    Text(tr("No pulse timeline available for this workout.",
                            "Ingen pulstidslinje tilgjengelig for denne økten."))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 55)
                }

                Rectangle().fill(ATHLTHPlanDesign.warmDivider).frame(height: 0.6)

                HStack {
                    Text(tr("TIME IN HEART-RATE ZONES", "TID I PULSSONER"))
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Spacer()
                    if zoneTotal > 0 {
                        Text(timeText(zoneTotal) + " " +
                             tr("measured", "målt"))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }

                if athleteMaximumBPM != nil && zoneTotal > 0 {
                    VStack(spacing: 9) {
                        ForEach(zones) { zone in
                            HStack(spacing: 9) {
                                Text(tr("Zone", "Sone") + " \(zone.zone)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .frame(width: 53, alignment: .leading)

                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(ATHLTHPlanDesign.selectedSurface)
                                        Capsule().fill(ATHLTHPlanDesign.accentInk.opacity(
                                            0.28 + Double(zone.zone) * 0.12
                                        ))
                                        .frame(width: geometry.size.width *
                                               CGFloat(zone.seconds / max(zoneTotal, 1)))
                                    }
                                }
                                .frame(height: 9)

                                Text(timeText(zone.seconds))
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .frame(width: 45, alignment: .trailing)
                            }
                        }
                    }
                    Text(tr(
                        "Zones use your configured maximum heart rate. Times cover available sensor samples; gaps are not counted.",
                        "Sonene bruker din registrerte makspuls. Tidene dekker tilgjengelige sensormålinger; manglende data telles ikke."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } else {
                    Text(athleteMaximumBPM == nil
                         ? tr("Set your maximum heart rate in your profile to see measured time in zones.",
                              "Legg inn makspuls i profilen for å se registrert tid i pulssonene.")
                         : tr("Not enough continuous pulse samples to calculate zone times.",
                              "For få sammenhengende pulsmålinger til å beregne tid i sonene."))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
        }
    }

    private func pulseStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text("bpm")
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
