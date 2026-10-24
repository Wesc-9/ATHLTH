import SwiftUI

/// A lightweight running-interval composer using the existing Quick Run
/// RunningWorkoutBlock model. No new execution engine is introduced.
struct ATHLTHTrainIntervalComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    let initial: RunningWorkoutTemplate?
    let onSave: (RunningWorkoutTemplate) -> Void

    @State private var name: String
    @State private var blocks: [RunningWorkoutBlock]
    @State private var kind: RunningBlockKind = .work
    @State private var activityName = ""
    @State private var targetEffort: RunningIntensityKind = .easy
    @State private var showingExercisePicker = false
    @State private var saveAsReusableTemplate = false
    @State private var showingReplaceStructureConfirmation = false
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
    @State private var inclineEnabled = false
    @State private var inclinePercent = 0.0
    @State private var notes = ""
    @State private var phasePlaylist: SpotifyPlaylistReference?
    @State private var showingPhasePlaylistPicker = false
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
    @State private var isComposerExpanded = false
    @State private var pauseAfterWarmupEnabled: Bool
    @State private var pauseAfterWarmupSeconds: Int
    @State private var autoAdvanceTimedSteps: Bool
    @State private var autoStartMainAfterWarmup: Bool
    @State private var coachIntervalEnabled: Bool
    @State private var coachIntervalSeconds: Int
    @State private var coachCountdownEnabled: Bool
    @State private var coachCountdownSeconds: Int

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
        let initialBlocks = initial?.blocks ?? []
        let warmupPause = initialBlocks.first {
            $0.kind == .recovery &&
            ($0.title == "Pause før hoveddel" ||
             $0.title == "Recovery after warm-up")
        }
        _blocks = State(initialValue: initialBlocks.filter {
            $0.id != warmupPause?.id
        })
        _pauseAfterWarmupEnabled = State(initialValue: warmupPause != nil)
        _pauseAfterWarmupSeconds = State(initialValue:
            max(15, Int(warmupPause?.work.durationSeconds ?? 90)))
        _autoAdvanceTimedSteps = State(initialValue:
            initial?.autoAdvanceTimedSteps ?? true)
        _autoStartMainAfterWarmup = State(initialValue: initial?.autoStartMainAfterWarmup == true)
        _coachIntervalEnabled = State(initialValue: initial?.intervalCoachCueEverySeconds != nil)
        _coachIntervalSeconds = State(initialValue: Int(initial?.intervalCoachCueEverySeconds ?? 60))
        _coachCountdownEnabled = State(initialValue: initial?.intervalCoachCountdownSeconds != nil)
        _coachCountdownSeconds = State(initialValue: Int(initial?.intervalCoachCountdownSeconds ?? 15))
        _activityName = State(initialValue: "")
        _ghostEnabled = State(initialValue: initial?.intervalGhostPaceSecondsPerKilometer != nil)
        _ghostPaceSeconds = State(initialValue: Int(initial?.intervalGhostPaceSecondsPerKilometer ?? 300))
        _ghostFollowRecovery = State(initialValue: initial?.intervalGhostFollowRecovery == true)
        _ghostRecoverySlowdownPercent = State(initialValue: initial?.intervalGhostRecoverySlowdownPercent ?? 25)
        _coachBrief = State(initialValue: initial?.coachBrief ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            titleArea
                            blockList
                            blockComposer.id("phaseComposer")
                            sessionGuidance
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(18)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: editingBlockID) { _, selected in
                        guard selected != nil else { return }
                        isComposerExpanded = true
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(.easeInOut(duration: 0.22)) {
                                scroll.scrollTo("phaseComposer", anchor: .top)
                            }
                        }
                    }
                }
                Button(action: save) {
                    HStack {
                        Spacer()
                        Text(tr("Save detailed session", "Lagre detaljert økt"))
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
            .navigationTitle(tr("Advanced session builder", "Avansert øktbygger"))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                tr("Replace current workout structure?", "Erstatte gjeldende øktoppsett?"),
                isPresented: $showingReplaceStructureConfirmation
            ) {
                Button(tr("Use 4 × 4 template", "Bruk 4 × 4-malen")) {
                    loadFourByFour()
                }
                Button(tr("Cancel", "Avbryt"), role: .cancel) {}
            } message: {
                Text(tr(
                    "The current unsaved structure will be replaced.",
                    "Det nåværende ulagrede oppsettet erstattes."
                ))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                        .foregroundStyle(ink)
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                ExerciseLibraryView(
                    source: .library,
                    selectionTitle: tr("Choose exercise", "Velg øvelse")
                ) { exercise in
                    activityName = exercise.name
                    isComposerExpanded = true
                    showingExercisePicker = false
                }
            }
        }
        .sheet(isPresented: $showingPhasePlaylistPicker) {
            SpotifyPlaylistPickerView(
                title: tr("Playlist for this phase", "Spilleliste for denne delen"),
                selection: $phasePlaylist
            )
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
            Text(tr("Design every phase.", "Bygg hver eneste del."))
                .font(.system(size: 29, weight: .regular, design: .serif))
            Text(tr(
                "Mix warm-up, timed or distance-based efforts, recoveries and cool-downs.",
                "Kombiner oppvarming, tid eller distanse, drag, pauser og nedtrapping."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
            Button {
                if blocks.isEmpty {
                    loadFourByFour()
                } else {
                    showingReplaceStructureConfirmation = true
                }
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

    private var estimate: (duration: Double?, distanceMeters: Double?) {
        // Project from the exact recipe being edited, including all per-drag
        // speed and pause overrides. Never persist this as recorded training.
        let now = Date()
        let template = RunningWorkoutTemplate(
            id: UUID(), title: name, type: .intervals, summary: "",
            blocks: blocks, routeID: nil, isBuiltIn: false,
            createdAt: now, updatedAt: now
        )
        return (template.estimatedDurationSeconds, template.estimatedDistanceMeters)
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(tr("YOUR STRUCTURE", "DIN ØKTSTRUKTUR"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(bronze)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(blocks.count) " + tr("blocks", "blokker"))
                        .font(.caption)
                        .foregroundStyle(muted)
                    if let duration = estimate.duration {
                        Text("~\(Int((duration / 60).rounded(.up))) min")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    if let meters = estimate.distanceMeters {
                        Text(tr("Estimated distance", "Estimert distanse") +
                             " · " + String(format: "%.2f km", meters / 1_000))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bronze)
                    } else if !blocks.isEmpty {
                        Text(tr("Set speed for every timed phase to estimate distance",
                                "Velg hastighet for alle tidsdeler for å anslå distanse"))
                            .font(.caption2)
                            .foregroundStyle(muted)
                            .multilineTextAlignment(.trailing)
                    }
                }
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
                        Label(phaseLabel(block.kind), systemImage: phaseIcon(block.kind))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(bronze)
                        Text(block.title)
                            .font(.subheadline.weight(.semibold))
                        Text(summary(block))
                            .font(.caption)
                            .foregroundStyle(muted)
                        if let playlist = block.spotifyPlaylist {
                            Label(playlist.name, systemImage: "music.note")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(bronze)
                                .lineLimit(1)
                        }
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
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isComposerExpanded {
                        editingBlockID = nil
                        isComposerExpanded = false
                    } else {
                        isComposerExpanded = true
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: editingBlockID == nil
                          ? "plus.circle" : "square.and.pencil")
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    Text(editingBlockID == nil
                         ? tr("ADD A NEW PHASE", "LEGG TIL NY DEL")
                         : tr("EDIT SELECTED PHASE", "REDIGER VALGT DEL"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Spacer()
                    Image(systemName: isComposerExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isComposerExpanded {
                VStack(alignment: .leading, spacing: 13) {
                    Picker(tr("Block", "Blokk"), selection: $kind) {
                ForEach(RunningBlockKind.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .tint(ink)
            TextField(tr("Activity name, e.g. jogging, drills or strides",
                         "Aktivitet, f.eks. jogging, løpsdrill eller stigningsløp"),
                      text: $activityName)
                .font(.subheadline)
                .padding(11)
                .background(paper, in: RoundedRectangle(cornerRadius: 10))
            Button {
                showingExercisePicker = true
            } label: {
                Label(tr("Use exercise from library", "Velg øvelse fra biblioteket"),
                      systemImage: "dumbbell.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            Text(tr(
                "You can pin multiple jogging, drills or library exercises to this phase.",
                "Du kan feste flere aktiviteter eller bibliotekøvelser til samme del."
            ))
            .font(.caption)
            .foregroundStyle(muted)
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
                        value: $repetitions, in: 1...40)
                Toggle(tr("Rest between efforts", "Pause mellom drag"),
                       isOn: $pauseEnabled)
                    .tint(ATHLTHPlanDesign.accentInk)
                if pauseEnabled && repetitions > 1 {
                    Stepper("\(pauseSeconds) s " + tr("recovery", "pause"),
                            value: $pauseSeconds, in: 15...900, step: 15)
                }
                Text(tr("Edit speed and pulse zone for each effort or recovery above.",
                        "Tilpass hastighet og pulssone for hvert drag eller hver pause over."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            phaseTargetControls

            Button {
                showingPhasePlaylistPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(bronze)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Playlist for this phase", "Spilleliste for denne delen"))
                            .font(.subheadline.weight(.semibold))
                        Text(phasePlaylist?.name ?? tr("Choose a Spotify playlist", "Velg Spotify-spilleliste"))
                            .font(.caption)
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(ink)
                .padding(12)
                .background(paper, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Text(tr(
                "The playlist is saved with this phase. Automatic music switching between phases is not enabled.",
                "Spillelisten lagres med denne delen. Automatisk musikkbytte mellom deler er ikke aktivert."
            ))
            .font(.caption2)
            .foregroundStyle(muted)

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
                .padding(.top, 12)
            }
        }
        .padding(16)
        .athlthPlanCard(radius: 20)
    }

    /// Every phase supports both speed and a pulse zone. This includes
    /// warm-up, cooldown, steady running and interval repetitions.
    private var phaseTargetControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("TARGETS FOR THIS PHASE", "MÅL FOR DENNE DELEN"))
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

            Toggle(tr("Target speed / pace", "Målhastighet / tempo"),
                   isOn: $paceEnabled)
                .tint(ATHLTHPlanDesign.accentInk)
            if paceEnabled {
                Picker(tr("Enter as", "Angi som"), selection: $speedInputEnabled) {
                    Text(tr("Speed km/h", "Hastighet km/t")).tag(true)
                    Text(tr("Pace min/km", "Tempo min/km")).tag(false)
                }
                .pickerStyle(.segmented)
                if speedInputEnabled {
                    Stepper(String(format: "%.1f km/t", speedKilometersPerHour),
                            value: $speedKilometersPerHour, in: 3...25, step: 0.1)
                } else {
                    Stepper(paceLabel(paceSeconds), value: $paceSeconds,
                            in: 150...1200, step: 5)
                }
            }

            Toggle(tr("Treadmill incline target", "Målstigning på tredemølle"),
                   isOn: $inclineEnabled)
                .tint(ATHLTHPlanDesign.accentInk)
            if inclineEnabled {
                Stepper(String(format: "%.1f %%", inclinePercent),
                        value: $inclinePercent, in: 0...15, step: 0.5)
            }

            Toggle(tr("Heart-rate zone", "Pulssone"), isOn: $heartRateTargetEnabled)
                .tint(ATHLTHPlanDesign.accentInk)
            if heartRateTargetEnabled {
                Stepper(tr("Zone", "Sone") + " \(heartRateZone)",
                        value: $heartRateZone, in: 1...5)
            }
        }
    }

    private var sessionGuidance: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("INTERVAL TOOLS", "VERKTØY FOR INTERVALL"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(bronze)

            Toggle(tr("Start main section automatically after warm-up", "Start hoveddelen automatisk etter oppvarming"),
                   isOn: $autoStartMainAfterWarmup)
                .tint(ATHLTHPlanDesign.accentInk)
            Text(tr(
                "Default: End warm-up, then press Start main section. Automatic mode starts at the planned warm-up time.",
                "Standard: Avslutt oppvarming, og trykk deretter Start hoveddel. Automatisk starter ved planlagt oppvarmingstid."
            ))
            .font(.caption)
            .foregroundStyle(muted)

            Toggle(tr("Automatically advance timed phases", "Automatisk neste ved tidsstyrte deler"),
                   isOn: $autoAdvanceTimedSteps)
                .tint(ATHLTHPlanDesign.accentInk)
            Text(tr(
                "Work intervals and recoveries normally advance automatically. Warm-up waits for End warm-up unless automatic main start is enabled. Cool-down ends manually.",
                "Drag og pauser går normalt automatisk. Oppvarming avsluttes med knappen med mindre automatisk start er valgt. Nedjogging avsluttes manuelt."
            ))
            .font(.caption)
            .foregroundStyle(muted)

            if blocks.contains(where: { $0.kind == .warmup }) && autoStartMainAfterWarmup {
                Toggle(tr("Pause between warm-up and main set",
                          "Pause mellom oppvarming og hoveddel"),
                       isOn: $pauseAfterWarmupEnabled)
                    .tint(ATHLTHPlanDesign.accentInk)
                if pauseAfterWarmupEnabled {
                    Stepper(tr("Pause", "Pause") + " · \(pauseAfterWarmupSeconds) s",
                            value: $pauseAfterWarmupSeconds, in: 15...900, step: 15)
                    Text(tr(
                        "The recovery is an independent, timed step before the main set.",
                        "Pausen blir et eget tidsstyrt øktsteg før hoveddelen."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                }
            }

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

            Toggle(tr("Also save as reusable template", "Lagre også som gjenbrukbar mal"),
                   isOn: $saveAsReusableTemplate)
                .tint(bronze)
            Toggle(tr("Interval voice updates", "Løpende intervalloppdateringer"),
                   isOn: $coachIntervalEnabled)
                .tint(bronze)
            if coachIntervalEnabled {
                Stepper(tr("Every", "Hvert") + " \(coachIntervalSeconds) s",
                        value: $coachIntervalSeconds, in: 15...300, step: 15)
            }
            Toggle(tr("Warn before interval ends", "Varsle før draget er ferdig"),
                   isOn: $coachCountdownEnabled)
                .tint(bronze)
            if coachCountdownEnabled {
                Stepper(tr("Before finish", "Før slutt") + " · \(coachCountdownSeconds) s",
                        value: $coachCountdownSeconds, in: 5...60, step: 5)
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
        isComposerExpanded = false
    }

    private func edit(_ block: RunningWorkoutBlock) {
        editingBlockID = block.id
        isComposerExpanded = true
        kind = block.kind
        activityName = block.title
        targetEffort = block.work.intensity.kind
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
        targetEffort = block.work.intensity.kind
        paceEnabled = block.work.intensity.paceMinSecondsPerKilometer != nil
        paceSeconds = Int(block.work.intensity.paceMinSecondsPerKilometer ?? 300)
        speedInputEnabled = false
        inclineEnabled = block.work.treadmillInclinePercent != nil
        inclinePercent = block.work.treadmillInclinePercent ?? 0
        speedKilometersPerHour = 3_600 / Double(max(paceSeconds, 1))
        heartRateTargetEnabled = block.work.intensity.heartRateZone != nil
        heartRateZone = block.work.intensity.heartRateZone ?? 4
        notes = block.notes ?? ""
        phasePlaylist = block.spotifyPlaylist
    }

    private func addBlock() {
        let resolvedPace = speedInputEnabled
            ? 3_600 / max(speedKilometersPerHour, 0.5) : Double(paceSeconds)
        let intensity = RunningIntensityTarget(
            kind: paceEnabled ? .pace :
                  heartRateTargetEnabled ? .heartRateZone :
                  (targetEffort == .none ? .none : .easy),
            paceMinSecondsPerKilometer: paceEnabled ? resolvedPace : nil,
            paceMaxSecondsPerKilometer: paceEnabled ? resolvedPace : nil,
            heartRateZone: heartRateTargetEnabled ? heartRateZone : nil,
            rpe: nil
        )
        var work = measure == .distance
            ? RunningStepTarget.distance(Double(distanceMeters), intensity: intensity)
            : RunningStepTarget.time(Double(minutes * 60), intensity: intensity)
        work.treadmillInclinePercent = inclineEnabled ? inclinePercent : nil
        let recovery: RunningStepTarget? = kind == .work
            && repetitions > 1 && pauseEnabled
            ? .time(Double(pauseSeconds), intensity: .easy)
            : nil
        let priorOverrides = editingBlockID.flatMap { id in
            blocks.first(where: { $0.id == id })?.repetitionOverrides
        }
        let entry = RunningWorkoutBlock(
            id: editingBlockID ?? UUID(),
            kind: kind,
            title: activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? kind.title : activityName.trimmingCharacters(in: .whitespacesAndNewlines),
            repetitions: kind == .work ? repetitions : 1,
            work: work, recovery: recovery,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : notes,
            repetitionOverrides: priorOverrides?.filter { $0.repetition <= (kind == .work ? repetitions : 1) },
            spotifyPlaylist: phasePlaylist
        )
        if let id = editingBlockID, let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks[index] = entry
        } else {
            blocks.append(entry)
        }
        editingBlockID = nil
        isComposerExpanded = false
        notes = ""
        phasePlaylist = nil
        activityName = ""
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
        let length: String
        switch step.measure {
        case .distance:
            length = "\(Int(step.distanceMeters ?? 0)) m"
        case .time:
            let seconds = Int(step.durationSeconds ?? 0)
            length = "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        case .open:
            length = tr("Open", "Åpent")
        }
        var parts = [length]
        if let pace = step.intensity.paceMinSecondsPerKilometer, pace > 0 {
            parts.append(String(format: "%.1f km/t", 3_600 / pace))
        }
        if let incline = step.treadmillInclinePercent {
            parts.append(String(format: "%.1f %%", incline))
        }
        if let zone = step.intensity.heartRateZone {
            parts.append(tr("HR zone", "Pulssone") + " \(zone)")
        }
        return parts.joined(separator: " · ")
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
        let extra = stepSummary(block.work).split(separator: " · ").dropFirst()
        var description = ([effort] + extra.map(String.init)).joined(separator: " · ")
        if let recovery = block.recovery {
            description += " · " + tr("Recovery", "Pause") + " " + stepSummary(recovery)
        }
        return description
    }

    private func save() {
        let now = Date()
        var savedBlocks = blocks
        if autoStartMainAfterWarmup, pauseAfterWarmupEnabled,
           let warmupIndex = savedBlocks.firstIndex(where: { $0.kind == .warmup }) {
            savedBlocks.insert(RunningWorkoutBlock(
                kind: .recovery,
                title: tr("Recovery after warm-up", "Pause før hoveddel"),
                work: .time(Double(pauseAfterWarmupSeconds), intensity: .easy)
            ), at: warmupIndex + 1)
        }
        var result = RunningWorkoutTemplate(
            id: initial?.isBuiltIn == false ? (initial?.id ?? UUID()) : UUID(),
            title: name.trimmingCharacters(in: .whitespacesAndNewlines),
            type: initial?.type ?? .intervals,
            summary: tr("Advanced structured running session",
                        "Detaljert strukturert løpeøkt"),
            blocks: savedBlocks,
            routeID: initial?.routeID,
            isBuiltIn: false,
            createdAt: initial?.createdAt ?? now,
            updatedAt: now
        )
        result.autoAdvanceTimedSteps = autoAdvanceTimedSteps
        result.autoStartMainAfterWarmup = autoStartMainAfterWarmup
        result.intervalCoachCueEverySeconds = coachIntervalEnabled
            ? TimeInterval(coachIntervalSeconds) : nil
        result.intervalCoachCountdownSeconds = coachCountdownEnabled
            ? TimeInterval(coachCountdownSeconds) : nil
        result.intervalGhostPaceSecondsPerKilometer =
            ghostEnabled ? Double(ghostPaceSeconds) : nil
        result.intervalGhostFollowRecovery = ghostEnabled && ghostFollowRecovery
        result.intervalGhostRecoverySlowdownPercent = ghostRecoverySlowdownPercent
        result.coachBrief = coachBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : String(coachBrief.prefix(300))
        if saveAsReusableTemplate {
            runningLibrary.save(result)
        }
        onSave(result)
        dismiss()
    }

    private func phaseLabel(_ phase: RunningBlockKind) -> String {
        switch phase {
        case .warmup: return tr("PINNED WARM-UP", "FESTET OPPVARMING")
        case .work: return tr("PINNED MAIN SET", "FESTET HOVEDDEL")
        case .recovery: return tr("PINNED RECOVERY", "FESTET PAUSE")
        case .steady: return tr("PINNED STEADY RUN", "FESTET JEVN ØKT")
        case .cooldown: return tr("PINNED COOL-DOWN", "FESTET NEDTRAPPING")
        }
    }

    private func phaseIcon(_ phase: RunningBlockKind) -> String {
        switch phase {
        case .warmup: return "flame"
        case .work: return "figure.run"
        case .recovery: return "pause.circle"
        case .steady: return "figure.walk"
        case .cooldown: return "wind"
        }
    }

    private func paceLabel(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))/km"
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}
