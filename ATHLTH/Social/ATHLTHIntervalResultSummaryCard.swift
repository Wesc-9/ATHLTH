import SwiftUI
import Charts

/// Result-first post-run analysis. Work efforts are the hero; recovery,
/// warm-up and cool-down never inflate the interval averages.
struct ATHLTHIntervalResultSummaryCard: View {
    let performance: ATHLTHCompletedRunningPerformance
    @State private var showSupportingPhases = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var work: [ATHLTHRecordedRunningStep] {
        performance.workSteps.sorted { $0.index < $1.index }
    }

    private var recovery: [ATHLTHRecordedRunningStep] {
        performance.steps.filter {
            ["recovery", "rest"].contains(($0.phase ?? "").lowercased())
        }
    }

    private var supporting: [ATHLTHRecordedRunningStep] {
        performance.steps.filter {
            ["warmup", "cooldown"].contains(($0.phase ?? "").lowercased())
        }
    }

    private var workSeconds: Double {
        work.reduce(0) { $0 + $1.activeSeconds }
    }

    private var workMeters: Double {
        work.reduce(0) { $0 + $1.distanceMeters }
    }

    private var recoverySeconds: Double {
        recovery.reduce(0) { $0 + $1.activeSeconds }
    }

    private var fastest: Double? {
        work.compactMap(\.actualSpeedKilometersPerHour).max()
    }

    private var slowest: Double? {
        work.compactMap(\.actualSpeedKilometersPerHour).min()
    }

    private func pace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d /km", value / 60, value % 60)
    }

    private func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func speed(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        return String(format: "%.1f km/t", value)
    }

    private func samplePulse(for index: Int) -> String? {
        let values = (performance.minutes ?? []).filter {
            $0.stepIndex == index
        }.compactMap { $0.watchHeartRateBPM }.filter {
            $0.isFinite && $0 > 0
        }
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        return "\(Int(mean.rounded())) bpm"
    }

    private var evenness: String? {
        guard let fastest, let slowest, fastest > 0,
              work.count >= 2 else { return nil }
        let percent = 100 * (fastest - slowest) / fastest
        return String(format: "%.0f %%", percent)
    }

    var body: some View {
        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label(tr("MAIN SECTION", "HOVEDDEL"),
                          systemImage: "figure.run.circle.fill")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Spacer()
                    Text(tr("Completed", "Fullført"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Text(tr("How did your intervals go?", "Slik gikk intervallene"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)

                HStack(alignment: .top, spacing: 12) {
                    headline(tr("AVERAGE SPEED", "SNITTHASTIGHET"),
                             value: speed(performance.averageWorkSpeed))
                    Spacer(minLength: 0)
                    headline(tr("MAIN DISTANCE", "DISTANSE HOVEDDEL"),
                             value: String(format: "%.2f km", workMeters / 1_000))
                }
                HStack(alignment: .top, spacing: 12) {
                    headline(tr("WORK TIME", "DRAGTID"),
                             value: duration(workSeconds))
                    Spacer(minLength: 0)
                    headline(tr("RECOVERY TIME", "PAUSETID"),
                             value: duration(recoverySeconds))
                }

                if work.count >= 2 {
                    Chart {
                        ForEach(Array(work.enumerated()), id: \.offset) { offset, effort in
                            if let kmh = effort.actualSpeedKilometersPerHour {
                                BarMark(
                                    x: .value("Drag", offset + 1),
                                    y: .value("km/t", kmh)
                                )
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(height: 150)
                    .chartXAxisLabel(tr("Interval", "Drag"))
                    .accessibilityLabel(tr(
                        "Speed by work interval", "Hastighet per intervall"
                    ))
                }

                HStack(spacing: 10) {
                    if let fastest {
                        smallStat(tr("Fastest interval", "Raskeste drag"), speed(fastest))
                    }
                    if let evenness {
                        smallStat(tr("Speed variation", "Fartsvariasjon"), evenness)
                    }
                }

                Rectangle().fill(ATHLTHPlanDesign.warmDivider).frame(height: 1)

                Text(tr("EVERY INTERVAL", "HVERT ENKELT DRAG"))
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)

                ForEach(Array(work.enumerated()), id: \.offset) { number, effort in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(tr("Interval", "Drag") + " \(number + 1)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(speed(effort.actualSpeedKilometersPerHour))
                                .font(.headline.weight(.semibold))
                                .monospacedDigit()
                        }
                        HStack(spacing: 7) {
                            Text(duration(effort.activeSeconds))
                            Text("·")
                            Text(String(format: "%.0f m", effort.distanceMeters))
                            let observedPace = effort.distanceMeters > 0
                                ? effort.activeSeconds * 1_000 / effort.distanceMeters : nil
                            Text("·")
                            Text(pace(observedPace))
                        }
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                        HStack(spacing: 7) {
                            if let target = effort.targetPaceSecondsPerKilometer,
                               target.isFinite, target > 0 {
                                Text(tr("Target", "Mål") + " " +
                                     String(format: "%.1f km/t", 3_600 / target))
                            }
                            if let pulse = samplePulse(for: effort.index) {
                                Label(pulse, systemImage: "heart.fill")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        if let rest = recovery.first(where: { $0.index == effort.index + 1 }) {
                            Text(tr("Recovery", "Pause") + ": " +
                                 duration(rest.activeSeconds) + " · " +
                                 String(format: "%.0f m", rest.distanceMeters))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .padding(.vertical, 8)
                    if number < work.count - 1 {
                        Rectangle().fill(ATHLTHPlanDesign.warmDivider).frame(height: 0.5)
                    }
                }

                if !supporting.isEmpty {
                    DisclosureGroup(
                        tr("Warm-up & cool-down", "Oppvarming og nedjogging"),
                        isExpanded: $showSupportingPhases
                    ) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(supporting, id: \.index) { item in
                                HStack {
                                    Text((item.phase ?? "").lowercased() == "warmup"
                                        ? tr("Warm-up", "Oppvarming")
                                        : tr("Cool-down", "Nedjogging"))
                                    Spacer()
                                    Text(duration(item.activeSeconds) + " · " +
                                        String(format: "%.0f m", item.distanceMeters))
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.medium))
                }

                Text(performance.userReported
                     ? tr("Treadmill speed depends on user-entered belt settings; distance can be estimated.",
                          "Møllehastighet bygger på oppgitte mølleverdier. Distanse kan være estimert.")
                     : tr("Recorded distance and active time determine pace. Pulse is shown only for available sampled moments.",
                          "Tempo beregnes fra registrert distanse og aktiv tid. Puls vises bare der målepunkter er tilgjengelige."))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
    }

    private func headline(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(ATHLTHPlanDesign.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(value).font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 12))
    }
}
