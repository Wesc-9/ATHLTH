import Charts
import SwiftUI

/// Small, separately typed summary sections keep the workout-detail view
/// lightweight on iOS 27, and never invent values for incomplete GPS logs.
struct ATHLTHRunningResultAnalysisCard: View {
    let splits: [ATHLTHRunningResultInsights.KilometerSplit]
    let elevation: [ATHLTHRunningResultInsights.ElevationPoint]
    let activeEnergyKilocalories: Double?
    let maxHeartRateBPM: Double?
    var pulseSamples: [ATHLTHRunningHeartRatePoint] = []

    private func splitPulse(_ split: ATHLTHRunningResultInsights.KilometerSplit) -> String {
        guard let start = split.startedAt, let end = split.endedAt,
              let value = ATHLTHRunningHeartRateAnalysis.average(
                pulseSamples, from: start, through: end
              ) else { return "—" }
        return "\(Int(value.rounded()))"
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private func pace(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d /km", whole / 60, whole % 60)
    }

    private var highlightContent: [(title: String, value: String, icon: String)] {
        var values: [(title: String, value: String, icon: String)] = []
        if let best = ATHLTHRunningResultInsights.bestKilometer(splits) {
            values.append((
                tr("Fastest full km", "Raskeste hele km"),
                "\(best.kilometer). km · \(pace(best.paceSecondsPerKilometer))",
                "speedometer"
            ))
        }
        if let improvement = ATHLTHRunningResultInsights.strongFinishPercent(splits) {
            values.append((
                tr("Strong finish", "Sterk avslutning"),
                tr("\(improvement)% faster than the first kilometre",
                   "\(improvement) % raskere enn første kilometer"),
                "arrow.up.forward"
            ))
        }
        if let energy = activeEnergyKilocalories, energy.isFinite, energy > 0, values.count < 3 {
            values.append((
                tr("Active energy", "Aktiv energi"),
                "\(Int(energy.rounded())) kcal",
                "flame"
            ))
        }
        if let heartRate = maxHeartRateBPM, heartRate.isFinite,
           heartRate > 0, values.count < 3 {
            values.append((
                tr("Peak heart rate", "Høyeste puls"),
                "\(Int(heartRate.rounded())) bpm",
                "heart"
            ))
        }
        return Array(values.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !highlightContent.isEmpty {
                ATHLTHPlanSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(tr("Workout highlights", "Øktens høydepunkter"),
                              systemImage: "sparkles")
                            .font(.system(size: 21, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                        ForEach(Array(highlightContent.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 11) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    .frame(width: 40, height: 40)
                                    .background(ATHLTHPlanDesign.selectedSurface,
                                                in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    Text(item.value)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHPlanDesign.ink)
                                }
                                Spacer(minLength: 0)
                            }
                            if index < highlightContent.count - 1 {
                                Rectangle()
                                    .fill(ATHLTHPlanDesign.warmDivider)
                                    .frame(height: 0.6)
                            }
                        }
                    }
                }
            }

            if !splits.isEmpty {
                ATHLTHPlanSurface {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tr("Your kilometre rhythm", "Rytmen per kilometer"))
                                    .font(.system(size: 21, weight: .semibold, design: .serif))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(tr(
                                    "Complete, verified outdoor kilometres.",
                                    "Hele, kvalitetssikrede kilometer utendørs."
                                ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "figure.run.circle.fill")
                                .font(.system(size: 25))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }

                        HStack(spacing: 8) {
                            Text("KM").frame(width: 43, alignment: .leading)
                            Text(tr("TIME", "TID"))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(tr("PACE", "TEMPO"))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(tr("PULSE", "PULS"))
                                .frame(width: 53, alignment: .trailing)
                        }
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                        ForEach(splits) { split in
                            VStack(spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(String(format: "%02d", split.kilometer))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        .frame(width: 43, alignment: .leading)
                                    Text(time(split.durationSeconds))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(pace(split.paceSecondsPerKilometer))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(splitPulse(split))
                                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        .frame(width: 53, alignment: .trailing)
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(ATHLTHPlanDesign.ink)

                                GeometryReader { geometry in
                                    let slowest = splits.map(\.durationSeconds).max() ?? 1
                                    let ratio = min(1, slowest /
                                        max(split.durationSeconds, 1) / 1.08)
                                    Capsule()
                                        .fill(ATHLTHPlanDesign.selectedSurface)
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(ATHLTHPlanDesign.accentInk.opacity(0.65))
                                                .frame(width: geometry.size.width * ratio)
                                        }
                                }
                                .frame(height: 4)
                            }
                            .padding(.vertical, 5)
                        }
                        Text(tr(
                            "Pace and time from verified GPS. Pulse from measured HealthKit readings in each kilometre, when available.",
                            "Tid og tempo fra kvalitetssikret GPS. Puls fra registrerte HealthKit-målinger for hver kilometer, når tilgjengelig."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            }

            if elevation.count >= 5 {
                ATHLTHPlanSurface {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(tr("Elevation profile", "Høydeprofil"))
                            .font(.system(size: 21, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(tr("GPS altitude · recorded route only",
                                "GPS-høyde · kun registrert rute"))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        Chart(elevation) { point in
                            AreaMark(
                                x: .value("km", point.distanceKilometers),
                                yStart: .value("Base", elevation.map(\.altitudeMeters).min() ?? 0),
                                yEnd: .value("m", point.altitudeMeters)
                            )
                            .foregroundStyle(ATHLTHPlanDesign.accent.opacity(0.13))
                            LineMark(
                                x: .value("km", point.distanceKilometers),
                                y: .value("m", point.altitudeMeters)
                            )
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .interpolationMethod(.linear)
                        }
                        .chartYAxisLabel("m")
                        .chartXAxisLabel("km")
                        .frame(height: 160)
                        HStack {
                            Text(tr("Lowest", "Laveste") + ": \(Int((elevation.map(\.altitudeMeters).min() ?? 0).rounded())) m")
                            Spacer()
                            Text(tr("Highest", "Høyeste") + ": \(Int((elevation.map(\.altitudeMeters).max() ?? 0).rounded())) m")
                        }
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            }
        }
    }
}
