import SwiftUI
import Charts

/// Result-first post-run analysis. Work efforts are the hero; recovery,
/// warm-up and cool-down never inflate the interval averages.
struct ATHLTHIntervalResultSummaryCard: View {
    let performance: ATHLTHCompletedRunningPerformance
    var athleteMaximumBPM: Double? = nil
    var measuredHeartRate: [ATHLTHRunningHeartRatePoint] = []
    var workoutStartDate: Date? = nil
    var workoutEndDate: Date? = nil
    @State private var showPhaseTimeline = true
    @State private var showMinuteBreakdown = false

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

    private var phases: [ATHLTHRecordedRunningStep] {
        performance.steps.sorted { $0.index < $1.index }
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

    private func measuredPhasePulse(_ index: Int) -> [ATHLTHRunningHeartRatePoint] {
        guard let workoutStartDate, let workoutEndDate else { return [] }
        return ATHLTHRunningHeartRateAnalysis.phasePoints(
            measuredHeartRate, phaseIndex: index, steps: phases,
            startedAt: workoutStartDate, endedAt: workoutEndDate
        )
    }

    /// Use exact HealthKit timestamps where an uninterrupted timeline aligns.
    /// Otherwise fall back to Watch checkpoints attached to the step ID.
    private func sampledPulseBPM(for index: Int) -> Double? {
        let health = measuredPhasePulse(index)
        if !health.isEmpty {
            return health.reduce(0.0) { $0 + $1.bpm } / Double(health.count)
        }
        let values = phaseSamples(index).compactMap(\.watchHeartRateBPM).filter {
            $0.isFinite && (30...240).contains($0)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var phasePulseAvailable: Bool {
        (work + recovery).contains { sampledPulseBPM(for: $0.index) != nil }
    }

    private func samplePulse(for index: Int) -> String? {
        guard let pulse = sampledPulseBPM(for: index) else { return nil }
        return "\(Int(pulse.rounded())) bpm"
    }

    private var sampledWorkPulse: String? {
        let health = work.flatMap { measuredPhasePulse($0.index) }
        if !health.isEmpty {
            let mean = health.reduce(0.0) { $0 + $1.bpm } / Double(health.count)
            return "\(Int(mean.rounded())) bpm"
        }
        let indices = Set(work.map(\.index))
        let pulse = (performance.minutes ?? [])
            .filter { indices.contains($0.stepIndex) }
            .compactMap(\.watchHeartRateBPM)
            .filter { $0.isFinite && (30...240).contains($0) }
        guard !pulse.isEmpty else { return nil }
        return "\(Int((pulse.reduce(0, +) / Double(pulse.count)).rounded())) bpm"
    }

    private var detailedSamples: [ATHLTHRecordedRunningMinute] {
        (performance.minutes ?? []).filter { $0.activeSeconds > 0 }
    }

    private func phaseSamples(_ index: Int) -> [ATHLTHRecordedRunningMinute] {
        (performance.minutes ?? [])
            .filter { $0.stepIndex == index }
            .sorted { $0.stepElapsedAtEndSeconds < $1.stepElapsedAtEndSeconds }
    }

    private func observedPulsePeak(_ index: Int) -> Double? {
        let health = measuredPhasePulse(index)
        if !health.isEmpty { return health.map(\.bpm).max() }
        return phaseSamples(index).compactMap(\.watchHeartRateBPM)
            .filter { $0.isFinite && (30...240).contains($0) }.max()
    }

    private func lastPulse(_ index: Int) -> Double? {
        if let last = measuredPhasePulse(index).last { return last.bpm }
        return phaseSamples(index).compactMap(\.watchHeartRateBPM)
            .filter { $0.isFinite && (30...240).contains($0) }.last
    }

    private func observedZone(_ index: Int) -> Int? {
        guard let pulse = sampledPulseBPM(for: index) else { return nil }
        return ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: pulse, maximumBPM: athleteMaximumBPM
        )
    }

    private var averageRecoverySpeed: Double? {
        let elapsed = recovery.reduce(0.0) { $0 + $1.activeSeconds }
        let meters = recovery.reduce(0.0) { $0 + $1.distanceMeters }
        guard elapsed > 0, meters > 0 else { return nil }
        return meters * 3.6 / elapsed
    }

    private var targetComparison: (onTarget: Int, compared: Int)? {
        let pairs = work.compactMap { step -> (Double, Double)? in
            guard let pace = step.targetPaceSecondsPerKilometer,
                  pace.isFinite, pace > 0,
                  let actual = step.actualSpeedKilometersPerHour else { return nil }
            return (actual, 3_600 / pace)
        }
        guard !pairs.isEmpty else { return nil }
        return (pairs.filter { abs($0.0 - $0.1) / $0.1 <= 0.05 }.count,
                pairs.count)
    }

    private func phaseName(_ phase: ATHLTHRecordedRunningStep,
                           effortNumber: Int) -> String {
        switch (phase.phase ?? "main").lowercased() {
        case "warmup": return tr("Warm-up", "Oppvarming")
        case "cooldown": return tr("Cool-down", "Nedjogging")
        case "recovery", "rest": return tr("Recovery", "Pause")
        default: return tr("Effort", "Drag") + " \(effortNumber)"
        }
    }

    private func pulseRecovery(_ recoveryPhase: ATHLTHRecordedRunningStep) -> String? {
        guard let before = phases.last(where: { $0.index < recoveryPhase.index &&
            !["warmup", "cooldown", "recovery", "rest"].contains(($0.phase ?? "").lowercased())
        }), let previousBPM = lastPulse(before.index),
            let lastBPM = lastPulse(recoveryPhase.index) else {
            return nil
        }
        return "\(Int(previousBPM.rounded())) → \(Int(lastBPM.rounded())) bpm"
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
                Text(performance.title)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                HStack(spacing: 8) {
                    Label("\(work.count) " + tr("completed efforts", "fullførte drag"),
                          systemImage: "checkmark.seal.fill")
                    Text("·")
                    Text(performance.source)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

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

                HStack(spacing: 10) {
                    if let pace = performance.averageWorkSpeed, pace > 0 {
                        smallStat(tr("Work pace", "Tempo i drag"),
                                  self.pace(3_600 / pace))
                    }
                    if let recoverySpeed = averageRecoverySpeed {
                        smallStat(tr("Recovery speed", "Fart i pausene"),
                                  speed(recoverySpeed))
                    }
                }

                if let pulse = sampledWorkPulse {
                    Label(tr("Available heart-rate measurements during efforts",
                             "Tilgjengelige pulsmålinger i dragene") + " · " + pulse,
                          systemImage: "heart.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
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
                            if let target = effort.targetPaceSecondsPerKilometer,
                               target > 0 {
                                PointMark(
                                    x: .value("Drag", offset + 1),
                                    y: .value(tr("Target speed", "Målfart"), 3_600 / target)
                                )
                                .symbolSize(80)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            }
                        }
                    }
                    .frame(height: 150)
                    .chartXAxisLabel(tr("Interval", "Drag"))
                    .accessibilityLabel(tr(
                        "Recorded speed bars and planned target speed points for each effort.",
                        "Stolper viser registrert fart og punkter viser planlagt målfart."
                    ))
                    Text(tr("Bars: recorded speed · Dots: planned speed",
                            "Stolper: registrert fart · Punkter: planlagt fart"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }

                if phasePulseAvailable {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Pulse by effort and recovery", "Puls per drag og pause"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Chart {
                            ForEach(performance.steps, id: \.index) { phase in
                                if !["warmup", "cooldown"].contains(
                                    (phase.phase ?? "").lowercased()
                                ), let bpm = sampledPulseBPM(for: phase.index) {
                                    BarMark(
                                        x: .value(tr("Phase", "Del"), phase.index + 1),
                                        y: .value("bpm", bpm)
                                    )
                                    .foregroundStyle(
                                        ["recovery", "rest"].contains(
                                            (phase.phase ?? "").lowercased()
                                        )
                                        ? ATHLTHPlanDesign.accentInk.opacity(0.25)
                                        : ATHLTHPlanDesign.accentInk
                                    )
                                    .cornerRadius(3)
                                }
                            }
                        }
                        .frame(height: 115)
                        Text(tr(
                            "Dark bars are efforts; light bars are recoveries. Pulse is based on available Watch checkpoints.",
                            "Mørke stolper er drag, lyse er pauser. Puls bygger på tilgjengelige målepunkter fra klokken."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
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

                DisclosureGroup(
                    tr("Full session timeline", "Hele øktforløpet"),
                    isExpanded: $showPhaseTimeline
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(phases, id: \.index) { phase in
                            phaseRow(phase)
                            if phase.index != phases.last?.index {
                                Rectangle().fill(ATHLTHPlanDesign.warmDivider)
                                    .frame(height: 0.6)
                            }
                        }
                    }
                    .padding(.top, 9)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)

                if let targetComparison {
                    Label(
                        tr("Within 5% of target speed on",
                           "Innen 5 % av målfart på") +
                        " \(targetComparison.onTarget)/\(targetComparison.compared) " +
                        tr("efforts with both values recorded.",
                           "drag med både mål og faktisk fart."),
                        systemImage: "scope"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                } else {
                    Text(tr(
                        "No reliable target-versus-actual speed comparison is available. The app does not substitute planned speed for a recorded result.",
                        "Ingen sikker sammenligning av målfart og faktisk fart er tilgjengelig. Planlagt fart brukes aldri som registrert resultat."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }

                if !detailedSamples.isEmpty {
                    DisclosureGroup(
                        tr("Minute-by-minute interval data", "Intervallene minutt for minutt"),
                        isExpanded: $showMinuteBreakdown
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(detailedSamples.enumerated()), id: \.offset) { _, sample in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(tr("Phase", "Del") + " \(sample.stepIndex + 1) · " +
                                            duration(sample.stepElapsedAtEndSeconds))
                                            .font(.caption.weight(.medium))
                                        Spacer()
                                        Text(sample.activeSeconds > 0
                                             ? speed(sample.recordedDistanceMeters * 3.6 /
                                                     sample.activeSeconds)
                                             : "—")
                                            .font(.caption.weight(.semibold))
                                    }
                                    HStack(spacing: 7) {
                                        if let bpm = sample.watchHeartRateBPM {
                                            Text("\(Int(bpm.rounded())) bpm")
                                        }
                                        if let target = sample.targetPaceSecondsPerKilometer,
                                           target > 0 {
                                            Text(tr("Target", "Mål") + " " +
                                                speed(3_600 / target))
                                        }
                                        if let incline = sample.manuallyEnteredTreadmillInclinePercent {
                                            let from = max(0, sample.stepElapsedAtEndSeconds -
                                                           sample.activeSeconds)
                                            Text(tr("Incline", "Stigning") + " " +
                                                 duration(from) + "–" +
                                                 duration(sample.stepElapsedAtEndSeconds) +
                                                 String(format: " · %.1f %% (manuelt)", incline))
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                            }
                        }
                        .padding(.top, 7)
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

    @ViewBuilder
    private func phaseRow(_ phase: ATHLTHRecordedRunningStep) -> some View {
        let kind = (phase.phase ?? "main").lowercased()
        let isWork = !["warmup", "cooldown", "recovery", "rest"].contains(kind)
        let index = work.firstIndex(where: { $0.index == phase.index })
        let label = phaseName(phase, effortNumber: (index ?? 0) + 1)
        let pulse = sampledPulseBPM(for: phase.index)
        let samples = phaseSamples(phase.index)
        let incline = samples.filter {
            guard let value = $0.manuallyEnteredTreadmillInclinePercent else { return false }
            return value.isFinite && (0...30).contains(value)
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isWork ? "figure.run.circle.fill" :
                    (kind == "recovery" || kind == "rest" ? "pause.circle" : "clock"))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer(minLength: 0)
                Text(duration(phase.activeSeconds))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHPlanDesign.ink)
            }

            HStack(spacing: 10) {
                Text(String(format: "%.0f m", phase.distanceMeters))
                Text(speed(phase.actualSpeedKilometersPerHour))
                if phase.actualSpeedKilometersPerHour != nil {
                    Text(pace(phase.activeSeconds * 1_000 /
                              max(phase.distanceMeters, 1)))
                }
            }
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            if let planned = phase.targetDurationSeconds, planned > 0 {
                Text(tr("Planned", "Plan") + " " + duration(planned) + " · " +
                     tr("Actual", "Faktisk") + " " + duration(phase.activeSeconds))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            if let plannedPace = phase.targetPaceSecondsPerKilometer,
               plannedPace > 0 {
                Label(tr("Target speed", "Målfart") + " " +
                      speed(3_600 / plannedPace), systemImage: "scope")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
            if let pulse {
                HStack(spacing: 8) {
                    Label("\(Int(pulse.rounded())) bpm " +
                          tr("(sample average)", "(snitt målepunkter)"),
                          systemImage: "heart.fill")
                    if let peak = observedPulsePeak(phase.index) {
                        Text(tr("Highest sample", "Høyeste målepunkt") +
                             " \(Int(peak.rounded()))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                HStack(spacing: 8) {
                    if let zone = observedZone(phase.index) {
                        Text(tr("Observed zone", "Registrert sone") + " \(zone)")
                    }
                    if let targetZone = phase.targetHeartRateZone {
                        Text(tr("Target zone", "Målsone") + " \(targetZone)")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            } else if let zone = phase.targetHeartRateZone {
                Text(tr("Target HR zone", "Målpulssone") + " \(zone) · " +
                     tr("Pulse not recorded", "Puls ikke registrert"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            if ["rest", "recovery"].contains(kind),
               let drop = pulseRecovery(phase) {
                Label(tr("Pulse checkpoints", "Puls ved kontrollpunkter") +
                      " " + drop, systemImage: "heart.text.square")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }

            if let plannedIncline = phase.targetTreadmillInclinePercent,
               plannedIncline.isFinite {
                Text(tr("Planned incline for this phase", "Planlagt stigning i denne fasen") +
                     String(format: " · %.1f %%", plannedIncline))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            if !incline.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Entered incline by time", "Oppgitt stigning per tidspunkt"))
                        .font(.caption2.weight(.semibold))
                    ForEach(Array(incline.enumerated()), id: \.offset) { _, sample in
                        let from = max(0, sample.stepElapsedAtEndSeconds -
                                        sample.activeSeconds)
                        HStack(spacing: 6) {
                            Text(duration(from) + "–" +
                                 duration(sample.stepElapsedAtEndSeconds))
                            Spacer(minLength: 4)
                            Text(String(format: "%.1f %%", 
                                sample.manuallyEnteredTreadmillInclinePercent ?? 0))
                        }
                        .font(.caption2)
                        .monospacedDigit()
                    }
                }
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .padding(9)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 10))
            }
            if phase.isUserReported {
                Text(tr("Treadmill speed/distance are user-reported or estimated.",
                        "Møllefart/-distanse er oppgitt eller estimert."))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
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
