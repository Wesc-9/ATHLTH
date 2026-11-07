import SwiftUI

/// Edits the complete interval recipe as one transaction. Only fields the
/// athlete actually modifies are propagated; changing the repetition count
/// alone must not silently erase per-effort or per-recovery overrides.
struct ATHLTHIntervalGroupAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss

    let groupID: UUID
    let onSave: (Int, Bool, WorkoutTemplateBlock?, WorkoutTemplateBlock?) -> Void

    @State private var rounds: Int
    @State private var finalRecovery: Bool
    @State private var effort: WorkoutTemplateBlock
    @State private var recovery: WorkoutTemplateBlock
    @State private var changedEffort = false
    @State private var changedRecovery = false
    @State private var showingEffort = true
    @State private var showingRecovery = false

    private let bronze = ATHLTHTrainDesign.bronze
    private let ink = ATHLTHTrainDesign.ink

    init(
        groupID: UUID,
        blocks: [WorkoutTemplateBlock],
        onSave: @escaping (
            Int, Bool, WorkoutTemplateBlock?, WorkoutTemplateBlock?
        ) -> Void
    ) {
        self.groupID = groupID
        self.onSave = onSave
        let members = blocks.filter { $0.groupID == groupID }
        let firstEffort = members.first {
            $0.kind == .run && !$0.isActiveRecovery
        } ?? WorkoutTemplateBlock(
            sequence: 0, kind: .run, title: "Run interval",
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 240, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .main
        )
        let firstRecovery = members.first(where: \.isRestOrActiveRecovery)
            ?? WorkoutTemplateBlock(
                sequence: 0, kind: .rest, title: "Recovery",
                exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
                durationSeconds: 60, targetWeightKilograms: nil,
                loadNote: nil, notes: nil, phase: firstEffort.resolvedPhase
            )
        let summary = ATHLTHIntervalRecipeEditing.summary(for: groupID, in: blocks)
        _rounds = State(initialValue: summary?.rounds ?? 4)
        _finalRecovery = State(initialValue: summary?.hasFinalRecovery ?? false)
        _effort = State(initialValue: firstEffort)
        _recovery = State(initialValue: firstRecovery)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var timeBasedEffort: Binding<Bool> {
        Binding(
            get: { effort.durationSeconds != nil },
            set: { timed in
                if timed {
                    effort.durationSeconds = effort.durationSeconds ?? 240
                    effort.distanceMeters = nil
                } else {
                    effort.distanceMeters = effort.distanceMeters ?? 1_000
                    effort.durationSeconds = nil
                }
            }
        )
    }

    private var indoors: Binding<Bool> {
        Binding(
            get: { effort.isIndoor == true },
            set: { indoors in
                effort.isIndoor = indoors
                if !indoors { effort.treadmillInclinePercent = nil }
            }
        )
    }

    private var treadmill: Binding<Bool> {
        Binding(
            get: { effort.treadmillInclinePercent != nil },
            set: { isTreadmill in
                effort.treadmillInclinePercent = isTreadmill
                    ? (effort.treadmillInclinePercent ?? 0) : nil
                if isTreadmill { effort.isIndoor = true }
            }
        )
    }

    private var activeRecovery: Binding<Bool> {
        Binding(
            get: { recovery.isActiveRecovery },
            set: { active in
                recovery = ATHLTHActiveRecovery.convert(recovery, active: active)
                if !active {
                    recovery.treadmillInclinePercent = nil
                    recovery.isIndoor = nil
                }
            }
        )
    }

    private var perceivedEffort: Binding<Int> {
        Binding(
            get: { effort.targetEffortRPE ?? 0 },
            set: { effort.targetEffortRPE = $0 == 0 ? nil : $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("ADJUST INTERVAL", "JUSTER INTERVALL"))
                            .font(.caption.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(bronze)
                        Text(tr("Edit the complete interval", "Juster hele intervallen"))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(ink)
                        Text(tr(
                            "Set the number of efforts and the recovery after the final effort. Expand a section to apply new shared targets.",
                            "Velg antall drag og pause etter siste drag. Åpne en del for å endre varighet, fart og andre mål for alle drag eller pauser."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    card {
                        Label(tr("Interval setup", "Oppsett"),
                              systemImage: "repeat")
                            .font(.headline)
                            .foregroundStyle(ink)
                        Stepper(value: $rounds, in: 1...20) {
                            HStack {
                                Text(tr("Number of efforts", "Antall drag"))
                                Spacer()
                                Text("\(rounds)")
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                        }
                        Toggle(tr("Recovery after final effort",
                                  "Pause etter siste drag"), isOn: $finalRecovery)
                            .tint(bronze)
                        Text("\(rounds) " + tr("efforts", "drag") + " · " +
                             "\(rounds - (finalRecovery ? 0 : 1)) " +
                             tr("recoveries", "pauser"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    card {
                        DisclosureGroup(isExpanded: $showingEffort) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(tr(
                                    "Changing these targets replaces the corresponding targets in every effort, including manually adjusted efforts. You can edit any effort again afterwards.",
                                    "Endringer her oppdaterer alle drag, også drag du tidligere har justert. Du kan overstyre hvert drag igjen etterpå."
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Picker(tr("Effort goal", "Mål for drag"), selection: timeBasedEffort) {
                                    Text(tr("Time", "Tid")).tag(true)
                                    Text(tr("Distance", "Distanse")).tag(false)
                                }
                                .pickerStyle(.segmented)

                                if effort.durationSeconds != nil {
                                    ATHLTHPlannedDurationEditor(
                                        durationSeconds: $effort.durationSeconds
                                    )
                                } else {
                                    Stepper(
                                        value: Binding(
                                            get: { effort.distanceMeters ?? 1_000 },
                                            set: { effort.distanceMeters = $0 }
                                        ),
                                        in: 100...100_000, step: 100
                                    ) {
                                        Text("\(Int(effort.distanceMeters ?? 1_000)) m")
                                    }
                                }

                                Toggle(tr("Indoor", "Innendørs"), isOn: indoors)
                                    .tint(bronze)
                                if effort.isIndoor == true {
                                    Picker(tr("Indoor type", "Innendørstype"),
                                           selection: treadmill) {
                                        Text(tr("Indoor running", "Innendørs")).tag(false)
                                        Text(tr("Treadmill", "Tredemølle")).tag(true)
                                    }
                                    .pickerStyle(.segmented)
                                }
                                if effort.treadmillInclinePercent != nil {
                                    ATHLTHPlannedTreadmillTargetsView(block: $effort)
                                } else {
                                    ATHLTHPlannedPaceTargetView(
                                        targetPaceSecondsPerKilometer:
                                            $effort.targetPaceSecondsPerKilometer
                                    )
                                }
                                ATHLTHPlannedIntensityEditor(block: $effort)
                                Picker(tr("Perceived effort", "Opplevd belastning"),
                                       selection: perceivedEffort) {
                                    Text(tr("No target", "Ingen")).tag(0)
                                    ForEach(1...10, id: \.self) { value in
                                        Text("RPE \(value)").tag(value)
                                    }
                                }
                                .tint(bronze)
                                TextField(
                                    tr("Shared instructions", "Felles instruksjoner"),
                                    text: Binding(
                                        get: { effort.notes ?? "" },
                                        set: { effort.notes = $0.isEmpty ? nil : $0 }
                                    ), axis: .vertical
                                )
                                .lineLimit(2...4)
                            }
                            .padding(.top, 9)
                        } label: {
                            Label(tr("All efforts", "Alle drag"),
                                  systemImage: "figure.run")
                                .font(.headline)
                                .foregroundStyle(ink)
                        }
                        .tint(bronze)
                    }

                    card {
                        DisclosureGroup(isExpanded: $showingRecovery) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(tr(
                                    "These changes apply to all recoveries without changing the number of efforts.",
                                    "Disse endringene gjelder alle pauser, uten å endre antall drag."
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Toggle(tr("Active jogging recovery", "Aktiv joggepause"),
                                       isOn: activeRecovery)
                                    .tint(bronze)
                                if recovery.isActiveRecovery {
                                    ATHLTHPlannedRunStepEditor(block: $recovery)
                                    ATHLTHPlannedIntensityEditor(block: $recovery)
                                } else {
                                    ATHLTHPlannedDurationEditor(
                                        durationSeconds: $recovery.durationSeconds
                                    )
                                }
                                TextField(
                                    tr("Recovery instructions", "Instruksjoner for pause"),
                                    text: Binding(
                                        get: { recovery.notes ?? "" },
                                        set: { recovery.notes = $0.isEmpty ? nil : $0 }
                                    ), axis: .vertical
                                )
                                .lineLimit(2...4)
                            }
                            .padding(.top, 9)
                        } label: {
                            Label(tr("All recoveries", "Alle pauser"),
                                  systemImage: "pause.circle")
                                .font(.headline)
                                .foregroundStyle(ink)
                        }
                        .tint(bronze)
                    }

                    Text(tr(
                        "If you only change the effort count or final recovery, previous individual targets are kept.",
                        "Endrer du bare antall drag eller siste pause, beholder du alle tidligere individuelle justeringer."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
                .padding(17)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Adjust interval", "Juster intervall"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onSave(
                        rounds, finalRecovery,
                        changedEffort ? effort : nil,
                        changedRecovery ? recovery : nil
                    )
                    dismiss()
                } label: {
                    Label(tr("Save interval changes", "Lagre intervalljusteringer"),
                          systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(bronze.gradient,
                                    in: RoundedRectangle(cornerRadius: 15))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
        .onChange(of: effort) { _, _ in changedEffort = true }
        .onChange(of: recovery) { _, _ in changedRecovery = true }
        .presentationDetents([.large])
    }

    private func card<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13, content: content)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.7)
            }
    }
}
