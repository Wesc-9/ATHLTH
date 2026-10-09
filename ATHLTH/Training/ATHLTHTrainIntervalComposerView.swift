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
    @State private var notes = ""

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
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleArea
                        blockList
                        blockComposer
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
                    Stepper(paceLabel(paceSeconds),
                            value: $paceSeconds,
                            in: 150...1200,
                            step: 5)
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
                    Text(tr("Add to structure", "Legg til i økten"))
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

    private func addBlock() {
        let intensity: RunningIntensityTarget
        if kind == .work && paceEnabled {
            intensity = RunningIntensityTarget(
                kind: .pace,
                paceMinSecondsPerKilometer: Double(paceSeconds),
                paceMaxSecondsPerKilometer: Double(paceSeconds),
                heartRateZone: nil, rpe: nil
            )
        } else {
            intensity = .easy
        }
        let work = measure == .distance
            ? RunningStepTarget.distance(Double(distanceMeters), intensity: intensity)
            : RunningStepTarget.time(Double(minutes * 60), intensity: intensity)
        let recovery: RunningStepTarget? = kind == .work
            && repetitions > 1 && pauseEnabled
            ? .time(Double(pauseSeconds), intensity: .easy)
            : nil
        blocks.append(RunningWorkoutBlock(
            kind: kind,
            title: kind.title,
            repetitions: kind == .work ? repetitions : 1,
            work: work,
            recovery: recovery,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : notes
        ))
        notes = ""
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
        let result = RunningWorkoutTemplate(
            id: UUID(),
            title: name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: .intervals,
            summary: tr("Custom interval workout", "Egendefinert intervalløkt"),
            blocks: blocks,
            routeID: initial?.routeID,
            isBuiltIn: false,
            createdAt: now,
            updatedAt: now
        )
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
