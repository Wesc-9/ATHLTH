import SwiftUI

struct RunningWorkoutLibraryView: View {
    @EnvironmentObject private var library: RunningWorkoutLibraryStore

    let selectionTitle: String?
    let onSelect: ((RunningWorkoutTemplate) -> Void)?

    @State private var selectedType: RunningWorkoutType?
    @State private var showingBuilder = false

    init(
        selectionTitle: String? = nil,
        onSelect: ((RunningWorkoutTemplate) -> Void)? = nil
    ) {
        self.selectionTitle = selectionTitle
        self.onSelect = onSelect
    }

    private var templates: [RunningWorkoutTemplate] {
        guard let selectedType else {
            return library.allTemplates
        }

        return library.allTemplates.filter { $0.type == selectedType }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        selectedType = nil
                    } label: {
                        typeChip("All", selected: selectedType == nil)
                    }
                    .buttonStyle(.plain)

                    ForEach(RunningWorkoutType.allCases) { type in
                        Button {
                            selectedType = type
                        } label: {
                            typeChip(
                                type.title,
                                selected: selectedType == type
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(templates) { workout in
                        NavigationLink {
                            RunningWorkoutDetailView(
                                workout: workout,
                                selectionTitle: selectionTitle,
                                onSelect: onSelect
                            )
                        } label: {
                            workoutCard(workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(selectionTitle ?? "Running Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingBuilder = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingBuilder) {
            RunningWorkoutBuilderView()
                .environmentObject(library)
        }
    }

    private func typeChip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                selected ? ATHLTHTheme.accent : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
    }

    private func workoutCard(_ workout: RunningWorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: workout.type.systemImage)
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(ATHLTHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(workout.type.title)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                Spacer()

                if !workout.isBuiltIn {
                    Text("MY WORKOUT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(ATHLTHTheme.accent.opacity(0.10), in: Capsule())
                }
            }

            Text(workout.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 10) {
                Label(
                    "\(workout.blocks.count) blocks",
                    systemImage: "list.number"
                )

                if let distance = workout.estimatedDistanceMeters {
                    Label(
                        String(format: "%.1f km", distance / 1_000),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }

                Spacer()

                Image(systemName: "chevron.right")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}

struct RunningWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RunningWorkoutLibraryStore

    let workout: RunningWorkoutTemplate
    let selectionTitle: String?
    let onSelect: ((RunningWorkoutTemplate) -> Void)?

    @State private var showingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.accent.opacity(0.90),
                            Color.black.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    ATHLTHMarkShape()
                        .fill(.white.opacity(0.10))
                        .frame(width: 180, height: 130)
                        .offset(x: 170, y: -35)

                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            workout.type.title.uppercased(),
                            systemImage: workout.type.systemImage
                        )
                        .font(.caption2.bold())
                        .tracking(1.2)

                        Text(workout.title)
                            .font(.largeTitle.bold())

                        Text(workout.summary)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .foregroundStyle(.white)
                    .padding(20)
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 26))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Workout Structure")
                        .font(.title3.bold())

                    ForEach(Array(workout.blocks.enumerated()), id: \.element.id) { index, block in
                        RunningWorkoutBlockRow(
                            index: index + 1,
                            block: block
                        )
                    }
                }

                if let onSelect {
                    Button {
                        onSelect(workout)
                        dismiss()
                    } label: {
                        Label(
                            selectionTitle ?? "Use Workout",
                            systemImage: "plus.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                }

                if workout.isBuiltIn {
                    Button {
                        _ = library.duplicate(workout)
                    } label: {
                        Label("Save Editable Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Delete Workout", role: .destructive) {
                        showingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Running Workout")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this running workout?",
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                library.delete(workout.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct RunningWorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: RunningWorkoutLibraryStore

    @State private var title = "My Running Workout"
    @State private var type: RunningWorkoutType = .custom
    @State private var summary = ""
    @State private var blocks: [RunningWorkoutBlock] = []
    @State private var showingBlockEditor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Title", text: $title)

                    Picker("Type", selection: $type) {
                        ForEach(RunningWorkoutType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }

                    TextField(
                        "Description",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section("Structure") {
                    if blocks.isEmpty {
                        Text("Add a block for warm-up, steady running, intervals, recovery or cool-down.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            RunningWorkoutBlockRow(
                                index: index + 1,
                                block: block
                            )
                            .swipeActions {
                                Button(role: .destructive) {
                                    blocks.removeAll { $0.id == block.id }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { offsets, destination in
                            blocks.move(
                                fromOffsets: offsets,
                                toOffset: destination
                            )
                        }
                    }

                    Button {
                        showingBlockEditor = true
                    } label: {
                        Label("Add Block", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    Text("A block can repeat work + recovery several times. This structure is also suitable for later Apple Watch workout guidance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Build Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.save(
                            RunningWorkoutTemplate(
                                id: UUID(),
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                type: type,
                                summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                                blocks: blocks,
                                routeID: nil,
                                isBuiltIn: false,
                                createdAt: Date(),
                                updatedAt: Date()
                            )
                        )
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        blocks.isEmpty
                    )
                }
            }
            .sheet(isPresented: $showingBlockEditor) {
                RunningBlockEditorView { block in
                    blocks.append(block)
                }
            }
        }
    }
}

struct RunningBlockEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (RunningWorkoutBlock) -> Void

    @State private var kind: RunningBlockKind = .work
    @State private var title = "Work"
    @State private var repetitions = 1

    @State private var measure: RunningMeasureKind = .distance
    @State private var distanceMeters = 1_000.0
    @State private var durationMinutes = 5.0

    @State private var intensityKind: RunningIntensityKind = .rpe
    @State private var rpe = 7.0
    @State private var heartRateZone = 3
    @State private var paceMinutes = 5
    @State private var paceSeconds = 0

    @State private var recoveryEnabled = false
    @State private var recoveryMeasure: RunningMeasureKind = .time
    @State private var recoveryMeters = 200.0
    @State private var recoverySeconds = 90.0

    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Block") {
                    Picker("Phase", selection: $kind) {
                        ForEach(RunningBlockKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    TextField("Title", text: $title)

                    if kind == .work {
                        Stepper(
                            "Repeats: \(repetitions)",
                            value: $repetitions,
                            in: 1...50
                        )
                    }
                }

                Section("Work") {
                    Picker("Measure", selection: $measure) {
                        ForEach(RunningMeasureKind.allCases) { measure in
                            Text(measure.title).tag(measure)
                        }
                    }
                    .pickerStyle(.segmented)

                    if measure == .distance {
                        HStack {
                            Text("Distance")
                            Spacer()
                            TextField(
                                "1000",
                                value: $distanceMeters,
                                format: .number.precision(.fractionLength(0))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            Text("m")
                                .foregroundStyle(.secondary)
                        }
                    } else if measure == .time {
                        HStack {
                            Text("Duration")
                            Spacer()
                            TextField(
                                "5",
                                value: $durationMinutes,
                                format: .number.precision(.fractionLength(0...1))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            Text("min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Intensity") {
                    Picker("Target", selection: $intensityKind) {
                        ForEach(RunningIntensityKind.allCases) { intensity in
                            Text(intensity.title).tag(intensity)
                        }
                    }

                    if intensityKind == .rpe {
                        HStack {
                            Text("RPE")
                            Slider(value: $rpe, in: 1...10, step: 0.5)
                            Text("\(rpe, specifier: "%.1f")")
                                .monospacedDigit()
                        }
                    } else if intensityKind == .heartRateZone {
                        Stepper(
                            "Heart-rate zone: \(heartRateZone)",
                            value: $heartRateZone,
                            in: 1...5
                        )
                    } else if intensityKind == .pace {
                        Stepper(
                            "Pace minutes: \(paceMinutes)",
                            value: $paceMinutes,
                            in: 2...15
                        )
                        Stepper(
                            "Pace seconds: \(paceSeconds)",
                            value: $paceSeconds,
                            in: 0...55,
                            step: 5
                        )
                    }
                }

                if kind == .work && repetitions > 1 {
                    Section("Recovery between reps") {
                        Toggle(
                            "Add recovery",
                            isOn: $recoveryEnabled
                        )

                        if recoveryEnabled {
                            Picker(
                                "Measure",
                                selection: $recoveryMeasure
                            ) {
                                Text("Time").tag(RunningMeasureKind.time)
                                Text("Distance").tag(RunningMeasureKind.distance)
                            }
                            .pickerStyle(.segmented)

                            if recoveryMeasure == .time {
                                Stepper(
                                    "Recovery: \(Int(recoverySeconds)) sec",
                                    value: $recoverySeconds,
                                    in: 15...900,
                                    step: 15
                                )
                            } else {
                                Stepper(
                                    "Recovery: \(Int(recoveryMeters)) m",
                                    value: $recoveryMeters,
                                    in: 50...2_000,
                                    step: 50
                                )
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField(
                        "Optional cues",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }
            }
            .navigationTitle("Add Running Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(makeBlock())
                        dismiss()
                    }
                }
            }
            .onChange(of: kind) { _, kind in
                if title == "Work" || title.isEmpty {
                    title = kind.title
                }

                if kind != .work {
                    repetitions = 1
                }
            }
        }
    }

    private func makeBlock() -> RunningWorkoutBlock {
        let target: RunningStepTarget

        switch measure {
        case .distance:
            target = .distance(
                max(distanceMeters, 1),
                intensity: intensityTarget
            )
        case .time:
            target = .time(
                max(durationMinutes, 0.1) * 60,
                intensity: intensityTarget
            )
        case .open:
            target = RunningStepTarget(
                measure: .open,
                distanceMeters: nil,
                durationSeconds: nil,
                intensity: intensityTarget
            )
        }

        let recovery: RunningStepTarget?
        if recoveryEnabled && repetitions > 1 {
            if recoveryMeasure == .distance {
                recovery = .distance(
                    max(recoveryMeters, 1),
                    intensity: .easy
                )
            } else {
                recovery = .time(
                    max(recoverySeconds, 1),
                    intensity: .easy
                )
            }
        } else {
            recovery = nil
        }

        return RunningWorkoutBlock(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? kind.title
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            repetitions: max(repetitions, 1),
            work: target,
            recovery: recovery,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var intensityTarget: RunningIntensityTarget {
        switch intensityKind {
        case .none:
            return .none
        case .easy:
            return .easy
        case .pace:
            let pace = Double(paceMinutes * 60 + paceSeconds)
            return RunningIntensityTarget(
                kind: .pace,
                paceMinSecondsPerKilometer: pace,
                paceMaxSecondsPerKilometer: pace,
                heartRateZone: nil,
                rpe: nil
            )
        case .heartRateZone:
            return RunningIntensityTarget(
                kind: .heartRateZone,
                paceMinSecondsPerKilometer: nil,
                paceMaxSecondsPerKilometer: nil,
                heartRateZone: heartRateZone,
                rpe: nil
            )
        case .rpe:
            return RunningIntensityTarget(
                kind: .rpe,
                paceMinSecondsPerKilometer: nil,
                paceMaxSecondsPerKilometer: nil,
                heartRateZone: nil,
                rpe: rpe
            )
        }
    }
}

struct RunningWorkoutBlockRow: View {
    let index: Int
    let block: RunningWorkoutBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.bold())
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 28, height: 28)
                .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(block.title)
                        .font(.subheadline.weight(.semibold))

                    if block.repetitions > 1 {
                        Text("× \(block.repetitions)")
                            .font(.caption.bold())
                            .foregroundStyle(ATHLTHTheme.accent)
                    }
                }

                Text(stepDescription(block.work))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let recovery = block.recovery {
                    Text("Recovery · \(stepDescription(recovery))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let notes = block.notes {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: phaseIcon(block.kind))
                .foregroundStyle(ATHLTHTheme.accent)
        }
        .padding(12)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func stepDescription(_ step: RunningStepTarget) -> String {
        var pieces: [String] = []

        switch step.measure {
        case .distance:
            if let meters = step.distanceMeters {
                if meters >= 1_000 {
                    pieces.append(
                        String(format: "%.2g km", meters / 1_000)
                    )
                } else {
                    pieces.append("\(Int(meters.rounded())) m")
                }
            }
        case .time:
            if let duration = step.durationSeconds {
                if duration >= 60 {
                    pieces.append(
                        String(format: "%.0f min", duration / 60)
                    )
                } else {
                    pieces.append("\(Int(duration.rounded())) sec")
                }
            }
        case .open:
            pieces.append("Open")
        }

        switch step.intensity.kind {
        case .none:
            break
        case .easy:
            pieces.append("Easy")
        case .pace:
            if let pace = step.intensity.paceMinSecondsPerKilometer {
                pieces.append("\(paceString(pace))/km")
            }
        case .heartRateZone:
            if let zone = step.intensity.heartRateZone {
                pieces.append("HR Z\(zone)")
            }
        case .rpe:
            if let rpe = step.intensity.rpe {
                pieces.append(String(format: "RPE %.1f", rpe))
            }
        }

        return pieces.joined(separator: " · ")
    }

    private func paceString(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func phaseIcon(_ kind: RunningBlockKind) -> String {
        switch kind {
        case .warmup: return "flame"
        case .work: return "bolt.fill"
        case .recovery: return "arrow.counterclockwise"
        case .steady: return "figure.run"
        case .cooldown: return "snowflake"
        }
    }
}
