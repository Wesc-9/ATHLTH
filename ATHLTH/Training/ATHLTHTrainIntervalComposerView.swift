import SwiftUI

/// A lightweight running-interval composer using the existing Quick Run
/// RunningWorkoutBlock model. No new execution engine is introduced.
struct ATHLTHTrainIntervalComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let initial: RunningWorkoutTemplate?
    let onSave: (RunningWorkoutTemplate) -> Void

    @State private var name: String
    @State private var blocks: [RunningWorkoutBlock]
    @State private var kind: RunningBlockKind = .work
    @State private var measure: RunningMeasureKind = .distance
    @State private var minutes = 5
    @State private var distanceMeters = 1000
    @State private var repetitions = 5
    @State private var pauseEnabled = true
    @State private var pauseSeconds = 120
    @State private var paceEnabled = false
    @State private var paceSeconds = 300
    @State private var speedInputEnabled = false
    @State private var speedKilometersPerHour = 12.0
    @State private var notes = ""
    @State private var heartRateTargetEnabled = false
    @State private var heartRateZone = 4
    @State private var ghostEnabled: Bool
    @State private var ghostPaceSeconds: Int
    @State private var ghostFollowRecovery: Bool
    @State private var ghostRecoverySlowdownPercent: Int
    @State private var editingRepetition: IntervalRepetitionSelection?
    @State private var coachBrief: String

    private struct IntervalRepetitionSelection: Identifiable {
        let blockID: UUID
        let repetition: Int
        var id: String { blockID.uuidString + "-\(repetition)" }
    }
    @State private var editingBlockID: UUID?

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let muted = Color(red: 0.46, green: 0.44, blue: 0.43)
    private let bronze = Color(red: 0.65, green: 0.53, blue: 0.37)
    private let border = Color(red: 0.88, green: 0.86, blue: 0.83)
    private let paper = Color(red: 0.984, green: 0.976, blue: 0.963)

    init(initial: RunningWorkoutTemplate? = nil,
         onSave: @escaping (RunningWorkoutTemplate) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _name = State(initialValue: initial?.title ?? "")
        _blocks = State(initialValue: initial?.blocks ?? [])
        _ghostEnabled = State(initialValue: initial?.intervalGhostPaceSecondsPerKilometer != nil)
        _ghostPaceSeconds = State(initialValue: Int(initial?.intervalGhostPaceSecondsPerKilometer ?? 300))
        _ghostFollowRecovery = State(initialValue: initial?.intervalGhostFollowRecovery == true)
        _ghostRecoverySlowdownPercent = State(initialValue: initial?.intervalGhostRecoverySlowdownPercent ?? 25)
        _coachBrief = State(initialValue: initial?.coachBrief ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleArea
                        blockList
                        blockComposer
                        sessionGuidance
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                }
                .scrollIndicators(.hidden)
                Button(action: save) {
                    HStack {
                        Spacer()
                        Text(tr("Use interval structure", "Bruk intervalloppsettet"))
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(height: 49)
                    .padding(.horizontal, 15)
                    .background(ink, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(blocks.isEmpty ||
                          name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(blocks.isEmpty ||
                         name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .padding(16)
                .background(.white)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Running intervals", "Løpeintervaller"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                        .foregroundStyle(ink)
                }
            }
        }
        .sheet(item: $editingRepetition) { selection in
            if let block = blocks.first(where: { $0.id == selection.blockID }) {
                ATHLTHIntervalRepetitionEditorView(
                    block: block,
                    repetition: selection.repetition
                ) { modification in
                    guard let blockIndex = blocks.firstIndex(where: { $0.id == selection.blockID }) else { return }
                    var updated = blocks[blockIndex]
                    var overrides = updated.repetitionOverrides ?? []
                    overrides.removeAll { $0.repetition == selection.repetition }
                    overrides.append(modification)
                    updated.repetitionOverrides = overrides.sorted { $0.repetition < $1.repetition }
                    blocks[blockIndex] = updated
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var titleArea: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("RUN YOUR OWN WAY", "BYGG DIN LØPEØKT"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.7)
                .foregroundStyle(bronze)
            Text(tr("Every interval counts.", "Hvert drag teller."))
                .font(.system(size: 29, weight: .regular, design: .serif))
            Text(tr(
                "Mix warm-up, timed or distance-based efforts, recoveries and cool-downs.",
                "Kombiner oppvarming, tid eller distanse, drag, pauser og nedtrapping."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
            Button {
                loadFourByFour()
            } label: {
                Label(tr("Use 4 × 4 preset", "Bruk 4 × 4-mal"),
                      systemImage: "square.stack.3d.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(13)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            TextField(tr("Workout title", "Navn på løpeøkten"), text: $name)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(ink)
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(tr("YOUR STRUCTURE", "DIN ØKTSTRUKTUR"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(bronze)
                Spacer()
                Text("\(blocks.count) " + tr("blocks", "blokker"))
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            if blocks.isEmpty {
                Text(tr("Add your first block below.", "Legg til første blokk nedenfor."))
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                    Image(systemName: block.kind == .work
                          ? "figure.run" : "clock")
                        .foregroundStyle(bronze)
                        .frame(width: 25)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(block.title)
                            .font(.subheadline.weight(.semibold))
                        Text(summary(block))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Button {
                        edit(block)
                    } label: {
                        Text(tr("Edit", "Rediger"))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    Menu {
                        if index > 0 {
                            Button(tr("Move up", "Flytt opp")) {
                                blocks.swapAt(index, index - 1)
                            }
                        }
                        if index < blocks.count - 1 {
                            Button(tr("Move down", "Flytt ned")) {
                                blocks.swapAt(index, index + 1)
                            }
                        }
                        Button(role: .destructive) {
                            blocks.removeAll { $0.id == block.id }
                        } label: {
                            Label(tr("Remove", "Fjern"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(ink)
                            .frame(width: 35, height: 38)
                    }
                    }
                    if block.kind == .work {
                        Text(tr("INDIVIDUAL EFFORTS AND RECOVERIES",
                                "HVERT DRAG OG HVER PAUSE"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(bronze)
                        ForEach(1...max(block.repetitions, 1), id: \.self) { repetition in
                            Button {
                                editingRepetition = IntervalRepetitionSelection(
                                    blockID: block.id, repetition: repetition
                                )
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundStyle(bronze)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tr("Effort", "Drag") + " \(repetition)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(repetitionSummary(block, repetition: repetition))
                                            .font(.caption)
                                            .foregroundStyle(muted)
                                    }
                                    Spacer()
                                    if block.override(for: repetition) != nil {
                                        Text(tr("Custom", "Tilpasset"))
                                            .font(.caption2)
                                            .foregroundStyle(bronze)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(muted)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            if repetition < max(block.repetitions, 1) {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var blockComposer: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("ADD A BLOCK", "LEGG TIL BLOKK"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(bronze)

            Picker(tr("Block", "Blokk"), selection: $kind) {
                ForEach(RunningBlockKind.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .tint(ink)
            Picker(tr("Target", "Mål"), selection: $measure) {
                Text(tr("Distance", "Distanse")).tag(RunningMeasureKind.distance)
                Text(tr("Time", "Tid")).tag(RunningMeasureKind.time)
            }
            .pickerStyle(.segmented)

            if measure == .distance {
                Stepper(
                    "\(distanceMeters) m",
                    value: $distanceMeters,
                    in: 100...42000,
                    step: 100
                )
                .font(.subheadline)
            } else {
                Stepper(
                    "\(minutes) min",
                    value: $minutes,
                    in: 1...180
                )
                .font(.subheadline)
            }

            if kind == .work {
                Stepper("\(repetitions) " + tr("repetitions", "drag"),
                        value: $repetitions,
                        in: 1...40)
                    .font(.subheadline)
                Toggle(tr("Rest between efforts", "Pause mellom drag"),
                       isOn: $pauseEnabled)
                    .tint(bronze)
                if pauseEnabled && repetitions > 1 {
                    Stepper("\(pauseSeconds) s " + tr("recovery", "pause"),
                            value: $pauseSeconds,
                            in: 15...900,
                            step: 15)
                        .font(.subheadline)
                }
                Toggle(tr("Target pace", "Måltempo"), isOn: $paceEnabled)
                    .tint(bronze)
                if paceEnabled {
                    Toggle(tr("Enter target as speed", "Bruk hastighet (km/t)"),
                           isOn: $speedInputEnabled)
                        .tint(bronze)
                    if speedInputEnabled {
                        Stepper(String(format: "%.1f km/t", speedKilometersPerHour),
                                value: $speedKilometersPerHour,
                                in: 3...25, step: 0.5)
                    } else {
                        Stepper(paceLabel(paceSeconds),
                                value: $paceSeconds,
                                in: 150...1200, step: 5)
                    }
                }
                Toggle(tr("Heart-rate zone target", "Målsone for puls"),
                       isOn: $heartRateTargetEnabled)
                    .tint(bronze)
                if heartRateTargetEnabled {
                    Stepper(tr("Zone", "Sone") + " \(heartRateZone)",
                            value: $heartRateZone, in: 1...5)
                        .font(.subheadline)
                }
            }

            TextField(tr("Optional instructions", "Valgfri beskrivelse"),
                      text: $notes,
                      axis: .vertical)
                .lineLimit(1...3)
                .font(.subheadline)

            Button {
                addBlock()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text(editingBlockID == nil
                         ? tr("Add to structure", "Legg til i økten")
                         : tr("Save block changes", "Lagre endringer"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .padding(14)
                .background(paper, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(border, lineWidth: 0.7)
        }
    }

    private var sessionGuidance: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("INTERVAL TOOLS", "VERKTØY FOR INTERVALL"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(bronze)

            Toggle(tr("Virtual Ghost on work efforts", "Virtuell Ghost på drag"),
                   isOn: $ghostEnabled)
                .tint(bronze)
            if ghostEnabled {
                Stepper(tr("Ghost pace", "Ghost-tempo") + " · " + paceLabel(ghostPaceSeconds),
                        value: $ghostPaceSeconds, in: 150...1200, step: 5)
                Toggle(tr("Follow me during recovery", "Følg meg i pausene"),
                       isOn: $ghostFollowRecovery)
                    .tint(bronze)
                if ghostFollowRecovery {
                    Stepper(
                        tr("Follow when pace falls by", "Følg når tempoet faller") +
                        " \(ghostRecoverySlowdownPercent) %",
                        value: $ghostRecoverySlowdownPercent,
                        in: 10...60,
                        step: 5
                    )
                    .font(.subheadline)
                }
                Text(tr(
                    "Each effort has its own Ghost timer. In recovery, Ghost can match your slower pace without counting the pause as lost time.",
                    "Hvert drag har sin egen Ghost-tid. Under pauser kan Ghost følge det lavere tempoet ditt, uten å regne pausen som tapt tid."
                ))
                .font(.caption)
                .foregroundStyle(muted)
            }

            Text(tr("Tell Audio Coach what matters", "Fortell Audio Coach hva som er viktig"))
                .font(.subheadline.weight(.semibold))
            TextField(tr("e.g. Motivate me and focus on pace", "F.eks. Motiver meg og følg med på tempo"),
                      text: $coachBrief, axis: .vertical)
                .lineLimit(2...4)
                .font(.subheadline)
            Text(tr(
                "Coaching preferences are saved with the workout. Voice coaching must be enabled when starting.",
                "Ønskene lagres med økten. Lydcoach må aktiveres ved start."
            ))
            .font(.caption)
            .foregroundStyle(muted)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
    }

    private func loadFourByFour() {
        name = tr("4 × 4 intervals", "4 × 4 intervaller")
        let relaxed = RunningIntensityTarget.easy
        blocks = [
            RunningWorkoutBlock(kind: .warmup,
                                title: tr("Warm-up", "Oppvarming"),
                                work: .time(600, intensity: relaxed)),
            RunningWorkoutBlock(kind: .work,
                                title: tr("Effort", "Drag"),
                                repetitions: 4,
                                work: .time(240, intensity: .easy),
                                recovery: .time(120, intensity: relaxed)),
            RunningWorkoutBlock(kind: .cooldown,
                                title: tr("Cool-down", "Nedjogging"),
                                work: .time(600, intensity: relaxed))
        ]
        editingBlockID = nil
    }

    private func edit(_ block: RunningWorkoutBlock) {
        editingBlockID = block.id
        kind = block.kind
        repetitions = block.repetitions
        if block.work.measure == .distance {
            measure = .distance
            distanceMeters = max(Int(block.work.distanceMeters ?? 1000), 100)
        } else {
            measure = .time
            minutes = max(Int((block.work.durationSeconds ?? 300) / 60), 1)
        }
        if let recovery = block.recovery {
            pauseEnabled = true
            pauseSeconds = Int(recovery.durationSeconds ?? 120)
        } else {
            pauseEnabled = false
        }
        paceEnabled = block.work.intensity.paceMinSecondsPerKilometer != nil
        paceSeconds = Int(block.work.intensity.paceMinSecondsPerKilometer ?? 300)
        speedInputEnabled = false
        speedKilometersPerHour = 3_600 / Double(max(paceSeconds, 1))
        heartRateTargetEnabled = block.work.intensity.heartRateZone != nil
        heartRateZone = block.work.intensity.heartRateZone ?? 4
        notes = block.notes ?? ""
    }

    private func addBlock() {
        let resolvedPace = speedInputEnabled
            ? 3_600 / max(speedKilometersPerHour, 0.5) : Double(paceSeconds)
        let intensity = RunningIntensityTarget(
            kind: paceEnabled ? .pace :
                  heartRateTargetEnabled ? .heartRateZone : .easy,
            paceMinSecondsPerKilometer: paceEnabled ? resolvedPace : nil,
            paceMaxSecondsPerKilometer: paceEnabled ? resolvedPace : nil,
            heartRateZone: heartRateTargetEnabled ? heartRateZone : nil,
            rpe: nil
        )
        let work = measure == .distance
            ? RunningStepTarget.distance(Double(distanceMeters), intensity: intensity)
            : RunningStepTarget.time(Double(minutes * 60), intensity: intensity)
        let recovery: RunningStepTarget? = kind == .work
            && repetitions > 1 && pauseEnabled
            ? .time(Double(pauseSeconds), intensity: .easy)
            : nil
        let priorOverrides = editingBlockID.flatMap { id in
            blocks.first(where: { $0.id == id })?.repetitionOverrides
        }
        let entry = RunningWorkoutBlock(
            id: editingBlockID ?? UUID(),
            kind: kind, title: kind.title,
            repetitions: kind == .work ? repetitions : 1,
            work: work, recovery: recovery,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : notes,
            repetitionOverrides: priorOverrides?.filter { $0.repetition <= (kind == .work ? repetitions : 1) }
        )
        if let id = editingBlockID, let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index] = entry
        } else {
            blocks.append(entry)
        }
        editingBlockID = nil
        notes = ""
    }

    private func repetitionSummary(_ block: RunningWorkoutBlock,
                                   repetition: Int) -> String {
        let work = block.resolvedWork(at: repetition)
        let workText = stepSummary(work)
        guard let recovery = block.resolvedRecovery(after: repetition) else {
            return workText
        }
        return workText + " · " + tr("Recovery", "Pause") + " " + stepSummary(recovery)
    }

    private func stepSummary(_ step: RunningStepTarget) -> String {
        switch step.measure {
        case .distance: return "\(Int(step.distanceMeters ?? 0)) m"
        case .time:
            let seconds = Int(step.durationSeconds ?? 0)
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        case .open: return tr("Open", "Åpent")
        }
    }

    private func summary(_ block: RunningWorkoutBlock) -> String {
        let value: String
        switch block.work.measure {
        case .distance:
            value = "\(Int(block.work.distanceMeters ?? 0)) m"
        case .time:
            value = "\(Int((block.work.durationSeconds ?? 0) / 60)) min"
        case .open:
            value = tr("Open effort", "Åpent drag")
        }
        let effort = block.repetitions > 1 ? "\(block.repetitions) × \(value)" : value
        if let recovery = block.recovery {
            return effort + " · \(Int(recovery.durationSeconds ?? 0)) s "
                + tr("recovery", "pause")
        }
        return effort
    }

    private func save() {
        let now = Date()
        var result = RunningWorkoutTemplate(
            id: initial?.isBuiltIn == false ? initial!.id : UUID(),
            title: name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: .intervals,
            summary: tr("Custom interval workout", "Egendefinert intervalløkt"),
            blocks: blocks,
            routeID: initial?.routeID,
            isBuiltIn: false,
            createdAt: initial?.createdAt ?? now,
            updatedAt: now
        )
        result.intervalGhostPaceSecondsPerKilometer =
            ghostEnabled ? Double(ghostPaceSeconds) : nil
        result.intervalGhostFollowRecovery = ghostEnabled && ghostFollowRecovery
        result.intervalGhostRecoverySlowdownPercent = ghostRecoverySlowdownPercent
        result.coachBrief = coachBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : String(coachBrief.prefix(300))
        onSave(result)
        dismiss()
    }

    private func paceLabel(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))/km"
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}
