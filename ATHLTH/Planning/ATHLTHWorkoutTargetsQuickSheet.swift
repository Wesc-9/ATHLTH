import SwiftUI

/// Both modes edit the original executable workout blocks. Basic presents one
/// shared work target and one recovery target; Advanced opens every real step.
struct ATHLTHWorkoutTargetsQuickSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var blocks: [WorkoutTemplateBlock]
    var advanced = false
    /// The selected Basic exercise, if opened from its own card. Global
    /// workout settings keep nil and edit the entire running prescription.
    var includedBlockIDs: Set<UUID>? = nil

    private let bronze = ATHLTHTrainDesign.bronze
    private let ink = ATHLTHPlanDesign.ink

    private var treadmillSelected: Bool {
        blocks.contains {
            $0.kind == .run && $0.isIndoor == true &&
                $0.treadmillInclinePercent != nil
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private func isTarget(_ block: WorkoutTemplateBlock, recovery: Bool) -> Bool {
        if let includedBlockIDs,
           !includedBlockIDs.contains(block.editorDragID) { return false }
        if recovery { return block.isRestOrActiveRecovery }
        return block.kind == .run && !block.isRestOrActiveRecovery
    }

    private func matchingBlocks(recovery: Bool) -> [WorkoutTemplateBlock] {
        blocks.filter { isTarget($0, recovery: recovery) }
    }

    private func paceEnabled(recovery: Bool) -> Binding<Bool> {
        Binding(
            get: {
                matchingBlocks(recovery: recovery).contains {
                    $0.targetPaceSecondsPerKilometer != nil
                }
            },
            set: { enabled in
                let previous = matchingBlocks(recovery: recovery)
                    .compactMap(\.targetPaceSecondsPerKilometer).first ?? 360
                for index in blocks.indices where
                    isTarget(blocks[index], recovery: recovery) {
                    blocks[index].targetPaceSecondsPerKilometer =
                        enabled ? previous : nil
                }
            }
        )
    }

    private func paceValue(recovery: Bool) -> Binding<Int> {
        Binding(
            get: {
                Int((matchingBlocks(recovery: recovery)
                    .compactMap(\.targetPaceSecondsPerKilometer)
                    .first ?? 360).rounded())
            },
            set: { seconds in
                guard (120...960).contains(seconds) else { return }
                for index in blocks.indices where
                    isTarget(blocks[index], recovery: recovery) {
                    blocks[index].targetPaceSecondsPerKilometer = Double(seconds)
                }
            }
        )
    }

    private func speedValue(recovery: Bool) -> Binding<Double> {
        Binding(
            get: {
                let seconds = paceValue(recovery: recovery).wrappedValue
                return 3_600.0 / Double(max(120, seconds))
            },
            set: { speed in
                guard speed.isFinite, (3...25).contains(speed) else { return }
                for index in blocks.indices where
                    isTarget(blocks[index], recovery: recovery) {
                    blocks[index].targetPaceSecondsPerKilometer = 3_600.0 / speed
                }
            }
        )
    }

    private func zoneValue(recovery: Bool) -> Binding<Int> {
        Binding(
            get: {
                guard let range = ATHLTHPlannedWorkoutMetrics
                    .plannedHeartRateZoneRange(
                        for: matchingBlocks(recovery: recovery)
                    ) else { return 0 }
                return range == (4...5) ? 45 : range.lowerBound
            },
            set: { zone in
                for index in blocks.indices where
                    isTarget(blocks[index], recovery: recovery) {
                    blocks[index].targetHeartRateZone =
                        (1...5).contains(zone) ? zone : nil
                    blocks[index].sourceIntensityZoneLabel =
                        zone == 45 ? "Z4–Z5" : nil
                    blocks[index].targetHeartRatePercentMin = nil
                    blocks[index].targetHeartRatePercentMax = nil
                }
            }
        )
    }

    private func zoneText(recovery: Bool) -> String {
        guard let range = ATHLTHPlannedWorkoutMetrics.plannedHeartRateZoneRange(
            for: matchingBlocks(recovery: recovery)
        ) else { return tr("No HR target", "Ingen pulsmål") }
        let prefix = ATHLTHLocalization.isNorwegian ? "S" : "Z"
        return range.lowerBound == range.upperBound
            ? "\(prefix)\(range.lowerBound)"
            : "\(prefix)\(range.lowerBound)–\(prefix)\(range.upperBound)"
    }

    private var basicEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("One target for the whole exercise",
                            "Ett mål for hele øvelsen"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Apply the same pace and heart-rate target to all efforts or all recoveries. Individual steps remain available in Advanced.",
                        "Sett felles tempo og puls for alle drag eller alle pauser. Hver deløkt kan tilpasses i Avansert."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .padding(.bottom, 4)

                if !matchingBlocks(recovery: false).isEmpty {
                    targetCard(recovery: false)
                }
                if !matchingBlocks(recovery: true).isEmpty {
                    targetCard(recovery: true)
                }
                Label(
                    tr("Planned targets only — not measured heart rate.",
                       "Kun planlagte mål – ikke målt puls."),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .padding(17)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
        .accessibilityIdentifier("athlth-basic-shared-running-targets")
    }

    private func targetCard(recovery: Bool) -> some View {
        let target = matchingBlocks(recovery: recovery)
        let pace = paceValue(recovery: recovery)
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 11) {
                Image(systemName: recovery ? "pause.fill" : "figure.run")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(bronze)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(recovery ? tr("Recoveries", "Pauser")
                                  : tr("Work intervals", "Arbeidsdrag"))
                        .font(.headline)
                        .foregroundStyle(ink)
                    Text("\(target.count) " +
                         (recovery ? tr("recovery steps", "pauser")
                                   : tr("work steps", "drag")) +
                         " · " + zoneText(recovery: recovery))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "heart")
                    .foregroundStyle(bronze)
                Text(tr("Heart-rate zone", "Pulssone"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker(tr("Zone", "Sone"), selection: zoneValue(recovery: recovery)) {
                    Text(tr("No target", "Uten mål")).tag(0)
                    ForEach(1...5, id: \.self) { zone in
                        Text((ATHLTHLocalization.isNorwegian ? "S" : "Z") +
                             "\(zone)").tag(zone)
                    }
                    Text(tr("Z4–Z5", "S4–S5")).tag(45)
                }
                .pickerStyle(.menu)
                .tint(bronze)
            }

            Divider().overlay(ATHLTHPlanDesign.outline)

            Toggle(isOn: paceEnabled(recovery: recovery)) {
                Label(tr("Target pace", "Måltempo"), systemImage: "speedometer")
                    .font(.subheadline.weight(.medium))
            }
            .tint(bronze)

            if paceEnabled(recovery: recovery).wrappedValue {
                VStack(alignment: .leading, spacing: 7) {
                    if treadmillSelected {
                        Stepper(value: speedValue(recovery: recovery),
                                in: 3...25, step: 0.1) {
                            Text(speedValue(recovery: recovery).wrappedValue
                                .formatted(.number.precision(.fractionLength(1))) +
                                (ATHLTHLocalization.isNorwegian ? " km/t" : " km/h"))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(ink)
                        }
                        Text(String(format: "%d:%02d min/km",
                                    pace.wrappedValue / 60,
                                    pace.wrappedValue % 60))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    } else {
                        Stepper(value: pace, in: 120...960, step: 1) {
                            Text(String(format: "%d:%02d min/km",
                                        pace.wrappedValue / 60,
                                        pace.wrappedValue % 60))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(ink)
                        }
                        Text((3_600.0 / Double(max(120, pace.wrappedValue)))
                            .formatted(.number.precision(.fractionLength(1))) +
                            (ATHLTHLocalization.isNorwegian ? " km/t" : " km/h"))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.surface,
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
    }

    private var advancedEditor: some View {
        List {
            Section {
                ForEach(blocks.indices, id: \.self) { index in
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ATHLTHPlannedIntensityEditor(block: $blocks[index])
                                if blocks[index].kind == .run ||
                                   blocks[index].isRestOrActiveRecovery {
                                    ATHLTHPlannedRunStepEditor(block: $blocks[index])
                                }
                            }
                            .padding(16)
                        }
                        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                        .navigationTitle(
                            ATHLTHWorkoutNameSuggestion.displayStepTitle(blocks[index])
                        )
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: blocks[index].isRestOrActiveRecovery
                                  ? "pause.fill" : blocks[index].kind.systemImage)
                                .foregroundStyle(bronze)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ATHLTHWorkoutNameSuggestion.displayStepTitle(
                                    blocks[index]
                                ))
                                .font(.subheadline.weight(.semibold))
                                if let seconds = blocks[index].durationSeconds {
                                    Text("\(Int(seconds / 60)) min · " +
                                         (blocks[index].isRestOrActiveRecovery
                                          ? tr("Recovery", "Pause")
                                          : tr("Effort", "Drag")))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(tr("Edit every workout step", "Rediger hver deløkt"))
            } footer: {
                Text(tr(
                    "Targets are planned, not live heart-rate measurements.",
                    "Målene er planlagte, ikke målt puls."
                ))
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if blocks.isEmpty {
                    ContentUnavailableView(
                        tr("Add a step first", "Legg til en deløkt først"),
                        systemImage: "heart.text.square",
                        description: Text(tr(
                            "Choose an exercise before setting pace or heart rate.",
                            "Velg en øvelse før du setter tempo eller pulsmål."
                        ))
                    )
                } else if advanced {
                    advancedEditor
                } else if matchingBlocks(recovery: false).isEmpty &&
                          matchingBlocks(recovery: true).isEmpty {
                    ContentUnavailableView(
                        tr("No running targets", "Ingen løpemål"),
                        systemImage: "figure.run",
                        description: Text(tr(
                            "Running pace targets are available for running segments.",
                            "Måltempo kan settes for løpedeløkter."
                        ))
                    )
                } else {
                    basicEditor
                }
            }
            .navigationTitle(tr("Heart rate and pace", "Puls og tempo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
        }
    }
}


/// Tapping the single exercise in Basic must open its full prescribed
/// sequence. The source workout remains unchanged; the separate target editor
/// only modifies explicitly selected blocks, not unrelated exercises.
struct ATHLTHBasicWorkoutExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var blocks: [WorkoutTemplateBlock]
    let includedBlockIDs: Set<UUID>
    let exerciseTitle: String

    @State private var showingTargets = false

    private let ink = ATHLTHPlanDesign.ink
    private let muted = ATHLTHPlanDesign.secondaryInk
    private let bronze = ATHLTHTrainDesign.bronze

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var exerciseBlocks: [WorkoutTemplateBlock] {
        blocks.filter { includedBlockIDs.contains($0.editorDragID) }
    }

    private var isFourByFour: Bool {
        ATHLTHCompoundExerciseCatalog.fourByFourRecovery(exerciseBlocks) != nil
    }

    private var headerTitle: String {
        if isFourByFour { return tr("4 × 4 intervals", "4 × 4 intervaller") }
        return exerciseTitle.isEmpty
            ? (exerciseBlocks.first?.title ?? tr("Exercise", "Øvelse"))
            : exerciseTitle
    }

    private var plannedZone: String? {
        let effort = exerciseBlocks.filter { !$0.isRestOrActiveRecovery }
        if let range = ATHLTHPlannedWorkoutMetrics.plannedHeartRateZoneRange(
            for: effort
        ) {
            let prefix = ATHLTHLocalization.isNorwegian ? "S" : "Z"
            return range.lowerBound == range.upperBound
                ? "\(prefix)\(range.lowerBound)"
                : "\(prefix)\(range.lowerBound)–\(prefix)\(range.upperBound)"
        }
        return isFourByFour
            ? (ATHLTHLocalization.isNorwegian ? "S4–S5" : "Z4–Z5")
            : nil
    }

    private var plannedSeconds: TimeInterval? {
        ATHLTHWorkoutDurationEstimator.previewSeconds(for: exerciseBlocks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ATHLTHWorkoutDetailsCard(
                        activityTitle: headerTitle,
                        symbol: exerciseBlocks.contains {
                            $0.kind == .run &&
                            $0.treadmillInclinePercent != nil
                        } ? "figure.run.treadmill" : "figure.run",
                        showsTimingLabel: false
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                if let plannedSeconds {
                                    Label(
                                        ATHLTHWorkoutDurationEstimator
                                            .conciseDuration(plannedSeconds),
                                        systemImage: "clock"
                                    )
                                }
                                if let plannedZone {
                                    Label(plannedZone, systemImage: "heart")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bronze)

                            Text(isFourByFour
                                ? tr(
                                    "Four 4-minute efforts, with active recovery between efforts. Follow your own pace and heart-rate targets; each recovery stays directly after its effort.",
                                    "Fire drag på fire minutter, med aktiv pause mellom dragene. Følg dine egne tempo- og pulsmål. Hver pause ligger rett etter tilhørende drag."
                                  )
                                : tr(
                                    "Review each step and its planned targets before the workout.",
                                    "Se alle deløktene og de planlagte målene før treningsøkten."
                                  ))
                                .font(.subheadline)
                                .foregroundStyle(muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label(tr("Exercise contents", "Øvelsens innhold"),
                              systemImage: "list.number")
                            .font(.headline)
                            .foregroundStyle(ink)
                        ForEach(exerciseBlocks, id: \.editorDragID) { block in
                            exerciseStepRow(block)
                        }
                    }
                    .padding(15)
                    .athlthPlanCard(radius: 20)
                    .accessibilityIdentifier("athlth-basic-exercise-timeline")
                }
                .padding(16)
            }
            .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
            .navigationTitle(tr("Exercise details", "Øvelsesdetaljer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    showingTargets = true
                } label: {
                    Label(tr("Edit pace and heart-rate targets",
                             "Juster tempo og pulssone"),
                          systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(bronze)
                .disabled(exerciseBlocks.isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showingTargets) {
            ATHLTHWorkoutTargetsQuickSheet(
                blocks: $blocks,
                advanced: false,
                includedBlockIDs: includedBlockIDs
            )
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("athlth-basic-exercise-details")
    }

    private func exerciseStepRow(_ block: WorkoutTemplateBlock) -> some View {
        let guidance = ATHLTHWorkoutStepGuidance.detail(
            for: block, in: exerciseBlocks
        )
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: block.isActiveRecovery
                  ? "figure.walk" : block.isRestOrActiveRecovery
                    ? "pause.fill" : "figure.run")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(bronze)
                .frame(width: 39, height: 39)
                .background(ATHLTHPlanDesign.surface,
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(guidance.context)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text(guidance.instructions)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if let duration = block.durationSeconds,
                       duration.isFinite, duration > 0 {
                        Label(ATHLTHWorkoutStepCopy.duration(duration),
                              systemImage: "timer")
                    }
                    if let pace = block.targetPaceSecondsPerKilometer,
                       pace.isFinite, pace > 0 {
                        let rounded = Int(pace.rounded())
                        Label(String(format: "%d:%02d min/km",
                                     rounded / 60, rounded % 60),
                              systemImage: "speedometer")
                    }
                    if let zone = guidance.zone {
                        Label(zone, systemImage: "heart")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(bronze)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(ATHLTHPlanDesign.selectedSurface.opacity(0.53),
                    in: RoundedRectangle(cornerRadius: 14))
    }
}
