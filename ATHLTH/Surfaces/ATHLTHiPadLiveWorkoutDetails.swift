import SwiftUI

/// Shows the actual executable running timeline. The current segment comes
/// from the source engine, never from guessed elapsed-time percentages.
struct ATHLTHiPadLiveTimelinePanel: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    @State private var showingAll = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        if let stages = snapshot.runningSteps, !stages.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label(tr("YOUR WORKOUT", "DIN ØKT"),
                          systemImage: "list.number")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .tracking(1)
                    Spacer()
                    if let i = snapshot.runningStepIndex {
                        Text(tr("Part", "Del") + " \(i + 1) / \(stages.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }

                let selected = snapshot.runningStepIndex ?? 0
                let visible = showingAll ? stages : stages.filter {
                    abs($0.index - selected) <= 2
                }
                ForEach(visible) { part in
                    stageRow(part, current: selected)
                }

                if !showingAll && visible.count < stages.count {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showingAll = true
                        }
                    } label: {
                        Label(tr("View all phases", "Vis alle deløkter"),
                              systemImage: "chevron.down")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(ATHLTHPlanDesign.accentInk)
                } else if showingAll && stages.count > 5 {
                    Button(tr("Show current section", "Vis aktiv del")) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showingAll = false
                        }
                    }
                    .font(.caption.weight(.medium))
                    .tint(ATHLTHPlanDesign.accentInk)
                }
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("athlth-ipad-live-workout-timeline")
        } else if let count = snapshot.runningStepCount, count > 0,
                  let index = snapshot.runningStepIndex {
            VStack(alignment: .leading, spacing: 10) {
                Label(tr("YOUR WORKOUT", "DIN ØKT"), systemImage: "list.number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)

                Text(tr("Part", "Del") + " \(index + 1) / \(count)")
                    .font(.title2.weight(.semibold).monospacedDigit())

                Text(snapshot.currentStep ?? tr("Current phase", "Aktiv del"))
                    .font(.subheadline.weight(.medium))
                ProgressView(value: min(1, max(0, Double(index) / Double(count))))
                    .tint(ATHLTHPlanDesign.accentInk)
                if let next = snapshot.nextStep {
                    Label(tr("Next", "Neste") + ": " + next,
                          systemImage: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private func stageRow(
        _ stage: ATHLTHLiveWorkoutStage, current: Int
    ) -> some View {
        let active = stage.index == current
        let complete = stage.index < current
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: active ? "circle.inset.filled" :
                complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(active ? ATHLTHPlanDesign.accentInk :
                    ATHLTHPlanDesign.secondaryInk)
                .frame(width: 25)

            VStack(alignment: .leading, spacing: 4) {
                Text(stage.title)
                    .font(.subheadline.weight(active ? .semibold : .regular))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(phaseName(stage.phase))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            Spacer(minLength: 4)
            if let seconds = stage.durationSeconds, seconds > 0 {
                Text(ATHLTHiPadLiveMetrics.duration(seconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else if let meters = stage.distanceMeters, meters > 0 {
                Text(String(format: "%.0f m", meters))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            if active {
                Text(tr("NOW", "NÅ"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? ATHLTHPlanDesign.selectedSurface :
            ATHLTHPlanDesign.surface.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 13))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func phaseName(_ phase: String) -> String {
        switch phase.lowercased() {
        case "warmup": return tr("Warm-up", "Oppvarming")
        case "main", "work": return tr("Main", "Hoveddel")
        case "recovery", "rest": return tr("Recovery", "Pause")
        case "cooldown": return tr("Cool-down", "Nedjogg")
        default: return phase
        }
    }
}

/// Head-to-head presentation is derived from the source Ghost comparison.
/// A missing comparison is displayed as unavailable, never a fake lead.
struct ATHLTHiPadLiveGhostDuelPanel: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        if let ghost = snapshot.ghostRaceTitle, !ghost.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.run.circle")
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Text(tr("YOU VS GHOST", "DU MOT GHOST"))
                        .font(.caption.weight(.bold))
                        .tracking(1)
                    Spacer(minLength: 4)
                    Text(ghost)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .foregroundStyle(ATHLTHPlanDesign.ink)

                HStack(alignment: .center, spacing: 14) {
                    runnerBadge(title: tr("You", "Du"), symbol: "figure.run",
                                highlighted: true)
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Spacer()
                    runnerBadge(title: "Ghost", symbol: "figure.run",
                                highlighted: false)
                }

                if let signedMeters = snapshot.ghostDistanceDeltaMeters,
                   signedMeters.isFinite {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gapText(signedMeters))
                            .font(.system(size: 26, weight: .semibold,
                                          design: .rounded))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .monospacedDigit()
                        Text(tr("Distance difference", "Distanseforskjell"))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    if let length = snapshot.routeDistanceMeters,
                       length > 0,
                       let distance = snapshot.distanceMeters,
                       distance.isFinite {
                        let you = min(1, max(0, distance / length))
                        let rival = min(1, max(0, (distance - signedMeters) / length))
                        runnerProgress(tr("You", "Du"), progress: you)
                        runnerProgress("Ghost", progress: rival)
                    }
                } else {
                    Text(tr(
                        "Waiting for the source device's Ghost comparison.",
                        "Venter på Ghost-sammenligning fra treningsenheten."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }

                if let seconds = snapshot.ghostTimeDeltaSeconds,
                   seconds.isFinite {
                    HStack {
                        Label(tr("Time difference", "Tidsforskjell"),
                              systemImage: "timer")
                        Spacer()
                        Text(String(format: "%+.0f s", seconds))
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                }
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("athlth-ipad-live-ghost-duel")
        }
    }

    private func runnerBadge(
        title: String, symbol: String, highlighted: Bool
    ) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .foregroundStyle(highlighted ? Color.white :
                    ATHLTHPlanDesign.accentInk)
                .frame(width: 47, height: 47)
                .background(highlighted ? ATHLTHPlanDesign.accentInk :
                    ATHLTHPlanDesign.selectedSurface, in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
        }
    }

    private func runnerProgress(_ title: String, progress: Double) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((progress * 100).rounded())) %")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            ProgressView(value: progress)
                .tint(ATHLTHPlanDesign.accentInk)
        }
    }

    private func gapText(_ gap: Double) -> String {
        let meters = Int(abs(gap).rounded())
        if meters < 8 { return tr("Neck and neck", "Jevnt løp") }
        return gap > 0
            ? tr("\(meters) m ahead", "\(meters) m foran")
            : tr("\(meters) m behind", "\(meters) m bak")
    }
}

struct ATHLTHiPadLiveStrengthDetailsPanel: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(tr("CURRENT SET", "AKTIVT SETT"),
                  systemImage: "dumbbell")
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

            HStack(spacing: 18) {
                if let set = snapshot.strengthSetNumber {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(set) / \(max(set, snapshot.strengthSetTotal ?? set))")
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text(tr("Set", "Sett"))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
                if let reps = snapshot.strengthReps {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(reps)")
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text(tr("Repetitions", "Repetisjoner"))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
                if let kg = snapshot.strengthWeightKilograms,
                   kg.isFinite {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%.1f kg", kg))
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text(tr("Planned weight", "Planlagt vekt"))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            }
            if let restEnd = snapshot.strengthRestEndsAt {
                HStack {
                    Label(tr("Rest remaining", "Gjenstående pause"),
                          systemImage: "timer")
                    Spacer()
                    Text(restEnd, style: .timer)
                        .font(.title2.weight(.semibold).monospacedDigit())
                }
                .padding(14)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13))
            }

            if let exercises = snapshot.strengthExercises,
               !exercises.isEmpty {
                Divider()
                Text(tr("EXERCISE ORDER", "ØVELSESREKKEFØLGE"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                ForEach(exercises) { entry in
                    HStack(spacing: 9) {
                        Image(systemName:
                            entry.completedSets >= entry.totalSets &&
                                entry.totalSets > 0
                            ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        Text(entry.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(entry.completedSets)/\(entry.totalSets)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            }
        }
        .foregroundStyle(ATHLTHPlanDesign.ink)
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.surface,
                    in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("athlth-ipad-live-strength-details")
    }
}

struct ATHLTHiPadLiveRouteProgressPanel: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        if snapshot.routeTitle != nil ||
           snapshot.routeProgressPercent != nil ||
           snapshot.routeRemainingMeters != nil {
            VStack(alignment: .leading, spacing: 12) {
                Label(tr("ROUTE PROGRESS", "RUTEFREMDRIFT"),
                      systemImage: "map")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                if let route = snapshot.routeTitle {
                    Text(route)
                        .font(.subheadline.weight(.semibold))
                }
                if let remaining = snapshot.routeRemainingMeters,
                   remaining.isFinite, remaining >= 0 {
                    Text(String(format: "%.2f km", remaining / 1000))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text(tr("Remaining", "Gjenstår"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                if let value = snapshot.routeProgressPercent,
                   value.isFinite, (0...100).contains(value) {
                    ProgressView(value: value / 100)
                        .tint(ATHLTHPlanDesign.accentInk)
                }
            }
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
