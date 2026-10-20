import Charts
import SwiftUI

/// Small, separately typed summary sections keep the workout-detail view
/// lightweight on iOS 27, and never invent values for incomplete GPS logs.
struct ATHLTHRunningResultAnalysisCard: View {
    let splits: [ATHLTHRunningResultInsights.KilometerSplit]
    let elevation: [ATHLTHRunningResultInsights.ElevationPoint]
    let activeEnergyKilocalories: Double?
    let maxHeartRateBPM: Double?

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
                    VStack(alignment: .leading, spacing: 11) {
                        Text(tr("Kilometre splits", "Kilometersplits"))
                            .font(.system(size: 21, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(tr("Only completed kilometres from a continuous, verified GPS track.",
                                "Bare hele kilometer fra et sammenhengende, kvalitetssikret GPS-spor."))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                        ForEach(splits) { split in
                            HStack(spacing: 10) {
                                Text("\(split.kilometer). km")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .frame(width: 55, alignment: .leading)
                                GeometryReader { geometry in
                                    let slowest = splits.map(\.durationSeconds).max() ?? 1
                                    let fraction = max(0.2, min(1, slowest / max(split.durationSeconds, 1) / 1.65))
                                    Capsule()
                                        .fill(ATHLTHPlanDesign.accent.opacity(0.55))
                                        .frame(width: geometry.size.width * fraction)
                                }
                                .frame(height: 8)
                                Text(pace(split.paceSecondsPerKilometer))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .frame(width: 73, alignment: .trailing)
                            }
                            .frame(height: 30)
                        }
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
