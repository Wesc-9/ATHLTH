import SwiftUI

/// All values below come from the canonical workout block. This is not a
/// second recipe or a prose-only description of the session.
enum ATHLTHWorkoutStepTargetSummary {
    static func zoneLabel(for block: WorkoutTemplateBlock) -> String? {
        if let label = block.sourceIntensityZoneLabel,
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label.replacingOccurrences(of: "-", with: "–")
        }
        if let zone = block.targetHeartRateZone, (1...5).contains(zone) {
            return "Z\(zone)"
        }
        return nil
    }

    static func percentRange(for block: WorkoutTemplateBlock) -> ClosedRange<Int>? {
        if let lower = block.targetHeartRatePercentMin,
           let upper = block.targetHeartRatePercentMax,
           lower.isFinite, upper.isFinite,
           (30...100).contains(lower), (30...100).contains(upper),
           lower <= upper {
            return Int(lower.rounded())...Int(upper.rounded())
        }
        if let zone = block.targetHeartRateZone, (1...5).contains(zone) {
            let boundaries = [50, 60, 70, 80, 90, 100]
            return boundaries[zone - 1]...boundaries[zone]
        }
        return nil
    }

    static func highlightedZones(for block: WorkoutTemplateBlock) -> Set<Int> {
        if let range = percentRange(for: block) {
            let boundaries = [50, 60, 70, 80, 90, 100]
            return Set((1...5).filter { zone in
                // Exclude mere boundary contact, e.g. Z1 at 60 is not Z2.
                range.lowerBound < boundaries[zone] &&
                    range.upperBound > boundaries[zone - 1]
            })
        }
        return block.targetHeartRateZone.map { [$0] }.map(Set.init) ?? []
    }

    static func hasHeartRateTarget(_ block: WorkoutTemplateBlock) -> Bool {
        !highlightedZones(for: block).isEmpty
    }

    static func phaseDescription(for block: WorkoutTemplateBlock) -> String {
        if block.resolvedPhase == .recovery || block.kind == .rest {
            return ATHLTHLocalization.choose(english: "Recovery", norwegian: "Pause")
        }
        return block.resolvedPhase.title
    }
}

/// A proper step-inspection surface for both the library and saved recipes.
/// Previously this screen showed only title + combined targetText and left
/// most of a large iPad sheet blank, concealing executable targets.
struct ATHLTHWorkoutStepDetails: View {
    let block: WorkoutTemplateBlock
    let displayTitle: String
    let maximumHeartRateBPM: Double?
    let suggestion: String?

    private var ink: Color { ATHLTHPlanDesign.ink }
    private var accent: Color { ATHLTHPlanDesign.accentInk }
    private var muted: Color { ATHLTHPlanDesign.secondaryInk }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var isRecovery: Bool {
        block.resolvedPhase == .recovery || block.kind == .rest
    }

    private var zone: String? {
        ATHLTHWorkoutStepTargetSummary.zoneLabel(for: block)
    }

    private var zonePercent: ClosedRange<Int>? {
        ATHLTHWorkoutStepTargetSummary.percentRange(for: block)
    }

    private var bpmRange: ClosedRange<Int>? {
        ATHLTHPlannedHeartRatePreview.expectedBPM(
            for: block,
            maximumBPM: maximumHeartRateBPM
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    ATHLTHWorkoutStepTargetSummary.phaseDescription(for: block),
                    systemImage: isRecovery ? "pause.circle" : block.kind.systemImage
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)

                Text(displayTitle)
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(tr(
                    "Prescribed targets from this workout",
                    "Planlagte mål for denne øktdelen"
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10),
                          GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                if let seconds = block.durationSeconds, seconds > 0 {
                    targetTile(
                        tr("Duration", "Varighet"),
                        ATHLTHWorkoutStepCopy.duration(seconds),
                        symbol: "timer"
                    )
                }
                if let distance = block.distanceMeters, distance > 0 {
                    targetTile(
                        tr("Distance", "Distanse"),
                        distance >= 1000
                            ? String(format: "%.2f km", distance / 1000)
                            : "\(Int(distance.rounded())) m",
                        symbol: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
                if let zone {
                    targetTile(
                        tr("Heart-rate zone", "Pulssone"),
                        zone,
                        symbol: "heart"
                    )
                }
                if let pace = block.targetPaceSecondsPerKilometer,
                   pace.isFinite, pace > 0 {
                    let seconds = Int(pace.rounded())
                    targetTile(
                        tr("Target pace", "Måltempo"),
                        String(format: "%d:%02d /km", seconds / 60, seconds % 60),
                        symbol: "speedometer"
                    )
                }
                if let incline = block.treadmillInclinePercent,
                   incline.isFinite, (0...20).contains(incline) {
                    targetTile(
                        tr("Incline", "Stigning"),
                        String(format: "%.1f %%", incline),
                        symbol: "mountain.2"
                    )
                }
                if let sets = block.setCount, sets > 0 {
                    targetTile(tr("Sets", "Sett"), "\(sets)", symbol: "square.stack.3d.up")
                }
                if let repetitions = block.repetitions, repetitions > 0 {
                    let maximum = block.targetRepetitionsMaximum
                    let detail = maximum.map {
                        $0 > repetitions ? "\(repetitions)–\($0)" : "\(repetitions)"
                    } ?? "\(repetitions)"
                    targetTile(tr("Repetitions", "Repetisjoner"), detail,
                               symbol: "repeat")
                }
                if let rest = block.restBetweenSetsSeconds, rest > 0 {
                    targetTile(tr("Set rest", "Settpause"),
                               ATHLTHWorkoutStepCopy.duration(rest),
                               symbol: "pause.circle")
                }
                if let rir = block.targetRepsInReserve, (0...10).contains(rir) {
                    targetTile(tr("Reps in reserve", "Repetisjoner i reserve"),
                               "\(rir) RIR", symbol: "gauge.medium")
                }
                if let movementTempo = block.targetMovementTempo,
                   !movementTempo.isEmpty {
                    targetTile(tr("Movement tempo", "Bevegelsestempo"),
                               movementTempo, symbol: "timer")
                }
                if let power = block.targetVMAPercent, power.isFinite {
                    targetTile(tr("VMA target", "VMA-mål"),
                               String(format: "%.0f %%", power), symbol: "gauge")
                }
                if let intensity = block.targetIntensityType,
                   !intensity.isEmpty {
                    targetTile(tr("Intensity type", "Intensitetstype"),
                               intensity, symbol: "flame")
                }
                if let metres = block.targetElevationGainMeters,
                   metres.isFinite {
                    targetTile(tr("Elevation gain", "Høydemeter"),
                               String(format: "%.0f m", metres),
                               symbol: "mountain")
                }
                if let gradient = block.targetGradientPercent,
                   gradient.isFinite {
                    targetTile(tr("Outdoor gradient", "Stigning ute"),
                               String(format: "%.1f %%", gradient),
                               symbol: "mountain.2")
                }
                if let terrain = block.targetTerrainType,
                   !terrain.isEmpty {
                    targetTile(tr("Terrain", "Terreng"),
                               ATHLTHZonedLocalization.text(terrain),
                               symbol: "map")
                }
                if let index = block.sourceSupersetGroupIndex {
                    targetTile(tr("Source superset", "Supersettgruppe"),
                               "\(index)", symbol: "square.stack")
                }
                if let choices = block.sourceLoadAlternativesKilograms,
                   !choices.isEmpty {
                    targetTile(
                        tr("Race load options", "Vektalternativer"),
                        choices.map { String(format: "%g kg", $0) }
                            .joined(separator: " / "),
                        symbol: "dumbbell"
                    )
                }
                if let load = block.targetWeightKilograms, load >= 0 {
                    targetTile(tr("Planned weight", "Planlagt vekt"),
                               String(format: "%.1f kg", load),
                               symbol: "dumbbell")
                }
                if let rpe = block.targetEffortRPE, (1...10).contains(rpe) {
                    targetTile(
                        tr("Effort", "Anstrengelse"),
                        "\(rpe)/10",
                        symbol: "bolt"
                    )
                }
            }

            if let zone, let zonePercent {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            tr("Target heart-rate intensity", "Målintensitet for puls"),
                            systemImage: "heart.text.square"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        Spacer(minLength: 2)
                        Text(zone)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent)
                    }

                    HStack(spacing: 5) {
                        ForEach(1...5, id: \.self) { index in
                            let active = ATHLTHWorkoutStepTargetSummary
                                .highlightedZones(for: block).contains(index)
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(active
                                        ? accent
                                        : ATHLTHPlanDesign.selectedSurface)
                                    .frame(height: 12)
                                Text("Z\(index)")
                                    .font(.caption2.weight(active ? .bold : .regular))
                                    .foregroundStyle(active ? ink : muted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityLabel(
                        tr("Target zone ", "Målsone ") + zone
                    )

                    Text("\(zonePercent.lowerBound)–\(zonePercent.upperBound) % " +
                         tr("of maximum heart rate", "av makspuls"))
                        .font(.subheadline)
                        .foregroundStyle(ink)

                    if let bpmRange {
                        Label(
                            tr("Estimated from your heart-rate profile: ",
                               "Beregnet fra makspulsen i profilen din: ") +
                            "\(bpmRange.lowerBound)–\(bpmRange.upperBound) bpm",
                            systemImage: "waveform.path.ecg"
                        )
                        .font(.caption)
                        .foregroundStyle(muted)
                    } else {
                        Text(tr(
                            "Set your maximum heart rate in your profile to see an estimated bpm range.",
                            "Legg inn makspuls i profilen for å se beregnet pulsområde i slag/min."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                    }
                }
                .padding(16)
                .background(
                    ATHLTHPlanDesign.selectedSurface.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .accessibilityIdentifier("athlth-workout-step-structured-zone")
            } else if let suggestion {
                Label(suggestion, systemImage: "heart")
                    .font(.subheadline)
                    .foregroundStyle(accent)
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
            }

            if let notes = ATHLTHZonedLocalization
                .normalizeLegacyAllOutStep(block).notes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("Workout instructions", "Instruksjoner"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
            }

            if block.durationSeconds == nil && block.distanceMeters == nil {
                Label(
                    tr("No time or distance was specified for this step.",
                       "Ingen bestemt tid eller distanse er oppgitt for denne delen."),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(muted)
            }

            Text(tr(
                "These are workout targets, not recorded results. Edit your personal copy in My Workouts to change the prescription.",
                "Dette er øktmål, ikke registrerte resultater. Rediger din egen kopi under Mine økter for å endre målene."
            ))
            .font(.caption)
            .foregroundStyle(muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("athlth-workout-step-structured-details")
    }

    private func targetTile(
        _ label: String,
        _ value: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(label.uppercased(), systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
