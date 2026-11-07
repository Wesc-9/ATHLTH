import Foundation
import SwiftUI

/// Shared UI-only titles and hints. Never changes saved sessions or the workout engine.
enum ATHLTHWorkoutStepCopy {
    static func isFourByFour(_ title: String) -> Bool {
        ATHLTHWorkoutSearch.normalized(title).contains("4x4")
    }

    static func title(for block: WorkoutTemplateBlock, workoutTitle: String, compact: Bool) -> String {
        guard block.kind != .exercise else { return block.title }
        let source = ATHLTHWorkoutSearch.normalized(block.title)
        if block.kind == .run && block.resolvedPhase == .warmup &&
            ["oppvarming", "warm up", "warmup"].contains(source) {
            return block.cardioActivity == .walking
                ? ATHLTHLocalization.choose(english: "Walking", norwegian: "Gange")
                : ATHLTHLocalization.choose(english: "Jogging", norwegian: "Jogging")
        }
        if isFourByFour(workoutTitle) && block.resolvedPhase == .main && block.kind == .run {
            let pieces = block.title.components(separatedBy: "·")
            let base = ATHLTHWorkoutSearch.normalized(pieces[0])
            if ["intervall", "interval"].contains(base), pieces.count == 2 {
                let repetition = pieces[1].trimmingCharacters(in: .whitespaces)
                if repetition.contains("/") {
                    return ATHLTHLocalization.choose(
                        english: "4x4 intervals · rep " + repetition,
                        norwegian: "4x4 intervall · drag " + repetition
                    )
                }
            }
        }
        if block.resolvedPhase == .recovery && (block.isActiveRecovery || isFourByFour(workoutTitle)) {
            if compact {
                return ATHLTHLocalization.choose(
                    english: "Active recovery · easy jog", norwegian: "Aktiv pause · rolig jogg"
                )
            }
            return ATHLTHLocalization.choose(english: "Easy jog", norwegian: "Rolig jogg")
        }
        return block.title
    }

    /// Coach guidance only, not a measured value or modification to the prescribed workout.
    static func suggestedZone(for block: WorkoutTemplateBlock, workoutTitle: String) -> String? {
        guard isFourByFour(workoutTitle), block.kind == .run,
              block.targetHeartRateZone == nil else { return nil }
        let isWork = block.resolvedPhase == .main
        return ATHLTHLocalization.choose(
            english: isWork ? "Suggested HR zone Z4" : "Suggested HR zone Z1–Z2",
            norwegian: isWork ? "Anbefalt pulssone S4" : "Anbefalt pulssone S1–S2"
        )
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        let minutes = whole / 60, remaining = whole % 60
        if minutes == 0 { return "\(remaining) s" }
        if remaining == 0 { return "\(minutes) min" }
        return "\(minutes) min \(remaining) s"
    }
}

/// Read-only workout presentation shared by running, strength and hybrid
/// recipes. It uses the same light plan tokens and phase-oriented timeline as
/// WorkoutTemplateBuilderView, without exposing editing controls by accident.
struct ATHLTHWorkoutRecipePreview: View {
    let title: String
    let summary: String
    let category: String
    let symbol: String
    let difficulty: String?
    let durationMinutes: Int?
    let blocks: [WorkoutTemplateBlock]
    // Hide the duplicate hero/statistics when this detailed timeline is
    // embedded below an existing workout overview sheet.
    var embeddedInDetails = false
    var onUpdateBlock: ((Int, WorkoutTemplateBlock) -> Void)? = nil

    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @AppStorage("athlth.workoutPreview.advanced.v1") private var advanced = false
    @State private var selectedExercise: WorkoutTemplateBlock?
    @State private var editingStep: IndexedWorkoutStep?
    @State private var inspectedCardioStep: IndexedWorkoutStep?
    // All recipe categories start compact; each category and its steps can be
    // opened independently without losing the underlying workout prescription.
    @State private var collapsedPhases: Set<WorkoutPhaseKind> = Set(WorkoutPhaseKind.allCases)
    @State private var expandedStepIndices: Set<Int> = []

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var recipeTint: Color { ATHLTHPlanDesign.accentInk }

    private var categoryTitle: String {
        switch category {
        case "running": return tr("RUNNING", "LØPING")
        case "strength": return tr("STRENGTH", "STYRKE")
        case "hybrid": return tr("HYBRID", "HYBRID")
        case "walking": return tr("WALKING", "GÅING")
        case "mobility": return tr("MOBILITY", "MOBILITET")
        default: return tr("WORKOUT", "TRENINGSØKT")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            if !embeddedInDetails {
                introduction
                statistics
            }
            if let meters = ATHLTHRunningEstimate.distanceMeters(for: blocks),
               category == "running" || category == "walking" {
                Label(
                    tr("Estimated distance", "Estimert distanse") + " · " +
                    String(format: "%.2f km", meters / 1_000),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHint(tr(
                    "Calculated from planned speeds and distances, not a recorded result",
                    "Beregnet fra planlagte hastigheter og distanser – ikke en registrert økt"
                ))
            }
            modeControl
            expandableOutline
        }
        .sheet(item: $editingStep) { item in
            ATHLTHWorkoutStepEditor(block: item.block) { updated in
                onUpdateBlock?(item.index, updated)
            }
        }
        .sheet(item: $selectedExercise) { step in
            ATHLTHLinkedExerciseDetailView(block: step)
        }
        .sheet(item: $inspectedCardioStep) { item in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(item.block.resolvedPhase.title,
                              systemImage: item.block.resolvedPhase.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        Text(localizedTitle(item.block, compact: false))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        if let target = item.block.targetText {
                            Text(target)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        if let suggestion = ATHLTHWorkoutStepCopy.suggestedZone(
                            for: item.block, workoutTitle: title
                        ) {
                            Label(suggestion, systemImage: "heart")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                        if let incline = item.block.treadmillInclinePercent,
                           incline.isFinite, (0...20).contains(incline) {
                            Label(
                                tr("Incline", "Stigning") +
                                    String(format: " %.1f %%", incline),
                                systemImage: "mountain.2"
                            )
                            .font(.subheadline)
                        }
                        if let notes = item.block.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
                .navigationTitle(tr("Step details", "Detaljer for øktdel"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done", "Ferdig")) { inspectedCardioStep = nil }
                    }
                }
            }
        }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(recipeTint)
                .frame(width: 55, height: 55)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 17))

            VStack(alignment: .leading, spacing: 7) {
                Text(categoryTitle)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(recipeTint)

                Text(title)
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [ATHLTHPlanDesign.surface, ATHLTHPlanDesign.selectedSurface],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
    }

    private var statistics: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 9),
            GridItem(.flexible(), spacing: 9),
            GridItem(.flexible(), spacing: 9)
        ], spacing: 9) {
            metric(
                value: "\(blocks.count)",
                label: tr("Steps", "Deler"), icon: "square.stack"
            )
            metric(
                value: difficulty ?? tr("All levels", "Alle nivåer"),
                label: tr("Level", "Nivå"), icon: "figure.strengthtraining.traditional"
            )
            metric(
                value: durationMinutes.map { "~\($0) min" } ?? "—",
                label: tr("Duration", "Varighet"), icon: "clock"
            )
        }
    }

    private func metric(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(recipeTint)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(13)
        .athlthPlanCard(radius: 19)
    }

    private var modeControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(embeddedInDetails
                     ? tr("WORKOUT PROGRAM", "ØKTPROGRAM")
                     : tr("SESSION DETAILS", "ØKTDETALJER"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                Spacer()
                Text(advanced
                     ? tr("Targets and recovery", "Mål og pauser")
                     : tr("Quick overview", "Enkel oversikt"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Picker(tr("Detail level", "Detaljnivå"), selection: $advanced) {
                Text(tr("Simple", "Enkel")).tag(false)
                Text(tr("Advanced", "Avansert")).tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityHint(tr(
                "Choose a quick overview or full training details.",
                "Velg en enkel oversikt eller alle treningsdetaljene."
            ))
        }
    }

    /// Existing library recipes stay in their original warm-up/main/cool-down
    /// phases. A phase opens to a compact exercise list, and each exercise can
    /// open again to reveal rests and the editing action.
    private var expandableOutline: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if beginsPhase(at: index) {
                    phaseDisclosure(at: index)
                }
                if !collapsedPhases.contains(displayPhase(at: index)) {
                    recipeStepCard(block, index: index)
                        .padding(.leading, 9)
                }
            }
        }
    }

    /// Recovery intervals belong visually to the preceding training block.
    /// This does not change their underlying phase or execution order.
    private func displayPhase(at index: Int) -> WorkoutPhaseKind {
        let phase = blocks[index].resolvedPhase
        guard phase == .recovery else { return phase }
        return blocks.prefix(index).reversed()
            .first(where: { $0.resolvedPhase != .recovery })?.resolvedPhase ?? .recovery
    }

    private func beginsPhase(at index: Int) -> Bool {
        index == 0 || displayPhase(at: index) != displayPhase(at: index - 1)
    }

    private func phaseStepCount(at start: Int) -> Int {
        let phase = displayPhase(at: start)
        return (start..<blocks.count)
            .prefix(while: { displayPhase(at: $0) == phase }).count
    }

    private func phaseDisclosure(at index: Int) -> some View {
        let phase = displayPhase(at: index)
        let collapsed = collapsedPhases.contains(phase)
        let count = phaseStepCount(at: index)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if collapsed {
                    collapsedPhases.remove(phase)
                } else {
                    collapsedPhases.insert(phase)
                }
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: phase.symbol)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(phase.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                    Text(tr("Steps: ", "Øktdeler: ") + "\(count)")
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer()
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(recipeTint)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase.title)
        .accessibilityValue(tr(collapsed ? "Collapsed" : "Expanded",
                               collapsed ? "Lukket" : "Utvidet"))
        .accessibilityHint(tr("Double tap to show or hide this workout section",
                              "Dobbelttrykk for å vise eller skjule øktdelen"))
    }

    private func recipeStepCard(_ block: WorkoutTemplateBlock, index: Int) -> some View {
        let expanded = expandedStepIndices.contains(index)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if expanded {
                        expandedStepIndices.remove(index)
                    } else {
                        expandedStepIndices.insert(index)
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: 11) {
                    thumbnail(for: block)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedTitle(block, compact: true))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let target = block.targetText, !target.isEmpty {
                            Text(target)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .multilineTextAlignment(.leading)
                                .lineLimit(expanded ? nil : 2)
                        } else {
                            Text(tr("Tap for goals and rest", "Trykk for mål og pauser"))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(recipeTint)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localizedTitle(block, compact: true))
            .accessibilityValue(tr(expanded ? "Expanded" : "Collapsed",
                                   expanded ? "Utvidet" : "Lukket"))
            .accessibilityHint(tr("Double tap to show targets and recovery",
                                  "Dobbelttrykk for å vise mål og pauser"))

            if expanded {
                Divider()
                    .padding(.vertical, 11)

                let details = advancedDetails(for: block)
                if !details.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(details, id: \.self) { detail in
                            Label(detail, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 12)
                }
                if advanced, let suggested = ATHLTHWorkoutStepCopy.suggestedZone(
                    for: block, workoutTitle: title
                ) {
                    Label(suggested, systemImage: "heart")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(recipeTint)
                        .padding(.bottom, 12)
                }

                if onUpdateBlock != nil {
                    Button {
                        editingStep = IndexedWorkoutStep(index: index, block: block)
                    } label: {
                        Label(tr("Edit sets, weight and targets",
                                 "Rediger sett, vekt og mål"),
                              systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(recipeTint)
                } else {
                    Button {
                        if block.kind == .exercise {
                            selectedExercise = block
                        } else {
                            inspectedCardioStep = IndexedWorkoutStep(index: index, block: block)
                        }
                    } label: {
                        Label(tr("View step details", "Se øktdetaljer"),
                              systemImage: "info.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(recipeTint)
                }
            }
        }
        .padding(14)
        .athlthPlanCard(radius: 19, warm: block.resolvedPhase != .recovery)
        .overlay(alignment: .leading) {
            if block.resolvedPhase == .recovery {
                RoundedRectangle(cornerRadius: 3)
                    .fill(recipeTint.opacity(0.65))
                    .frame(width: 4)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for block: WorkoutTemplateBlock) -> some View {
        if let match = ATHLTHExerciseReferenceResolver.resolve(
            block, in: exerciseLibrary.allExercises
        ) {
            ExerciseArtwork(entry: match, size: 39)
        } else {
            Image(systemName: blockIcon(block))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(recipeTint)
                .frame(width: 39, height: 39)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func localizedTitle(_ block: WorkoutTemplateBlock, compact: Bool) -> String {
        guard block.kind == .exercise else {
            return ATHLTHWorkoutStepCopy.title(
                for: block, workoutTitle: title, compact: compact
            )
        }
        if let match = ATHLTHExerciseReferenceResolver.resolve(
            block, in: exerciseLibrary.allExercises
        ) {
            return exerciseLibrary.localizedExerciseName(match)
        }
        if ATHLTHLocalization.isNorwegian {
            return ATHLTHExerciseNameLocalization.norwegianName(
                for: block.exerciseSnapshot?.name ?? block.title
            )
        }
        return block.exerciseSnapshot?.name ?? block.title
    }

    private func blockIcon(_ block: WorkoutTemplateBlock) -> String {
        if block.resolvedPhase == .recovery { return "pause.fill" }
        if block.kind == .run && block.cardioActivity == .walking { return "figure.walk" }
        return block.kind.systemImage
    }

    private func advancedDetails(for block: WorkoutTemplateBlock) -> [String] {
        var result: [String] = []
        if let sets = block.setCount, sets > 0, block.kind == .exercise {
            result.append("\(sets) " + tr("sets", "sett"))
        }
        if let rest = block.restBetweenSetsSeconds, rest > 0 {
            result.append(tr("Rest between sets: ", "Pause mellom sett: ") +
                          "\(Int(rest)) " + tr("sec", "sek"))
        }
        if let weight = block.targetWeightKilograms, weight > 0 {
            result.append(tr("Target load: ", "Målvekt: ") + "\(weight) kg")
        }
        if let pace = block.targetPaceSecondsPerKilometer, pace > 0 {
            let seconds = Int(pace.rounded())
            result.append(tr("Target pace: ", "Måltempo: ") +
                          String(format: "%d:%02d min/km", seconds / 60, seconds % 60))
        }
        if let group = block.groupKind {
            let rounds = block.groupRounds.map { "\($0) × " } ?? ""
            result.append(rounds + group.title)
        }
        if let load = block.loadNote, !load.isEmpty {
            result.append(load)
        }
        if let notes = block.notes, !notes.isEmpty {
            result.append(notes)
        }
        return result
    }
}

private struct IndexedWorkoutStep: Identifiable {
    let index: Int
    let block: WorkoutTemplateBlock
    var id: Int { index }
}

private struct ATHLTHWorkoutStepEditor: View {
    @Environment(\.dismiss) private var dismiss
    let block: WorkoutTemplateBlock
    let onSave: (WorkoutTemplateBlock) -> Void
    @State private var draft: WorkoutTemplateBlock

    init(block: WorkoutTemplateBlock, onSave: @escaping (WorkoutTemplateBlock) -> Void) {
        self.block = block
        self.onSave = onSave
        _draft = State(initialValue: block)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(ATHLTHLocalization.choose(english: "Step", norwegian: "Øktdel")) {
                    TextField(ATHLTHLocalization.choose(english: "Name", norwegian: "Navn"),
                              text: $draft.title)
                    HStack {
                        Text(ATHLTHLocalization.choose(english: "Duration (sec)", norwegian: "Varighet (sek)"))
                        Spacer()
                        TextField("0", value: $draft.durationSeconds, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section(ATHLTHLocalization.choose(english: "Targets", norwegian: "Mål")) {
                    HStack {
                        Text(ATHLTHLocalization.choose(english: "Pace (sec/km)", norwegian: "Tempo (sek/km)"))
                        Spacer()
                        TextField("0", value: $draft.targetPaceSecondsPerKilometer, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text(ATHLTHLocalization.choose(english: "Heart-rate zone (Z1–Z5)", norwegian: "Pulssone (S1–S5)"))
                        Spacer()
                        TextField(ATHLTHLocalization.choose(english: "Z1–Z5", norwegian: "S1–S5"), value: $draft.targetHeartRateZone, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if draft.kind == .run {
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Speed (km/h)", norwegian: "Fart (km/t)"
                            ))
                            Spacer()
                            TextField("—", value: Binding<Double?>(
                                get: {
                                    guard let pace = draft.targetPaceSecondsPerKilometer,
                                          pace.isFinite, pace > 0 else { return nil }
                                    return 3_600 / pace
                                },
                                set: { speed in
                                    if let speed, speed.isFinite, speed > 0 {
                                        draft.targetPaceSecondsPerKilometer = 3_600 / speed
                                    } else {
                                        draft.targetPaceSecondsPerKilometer = nil
                                    }
                                }
                            ), format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Treadmill incline (%)",
                                norwegian: "Stigning på tredemølle (%)"
                            ))
                            Spacer()
                            TextField("—", value: Binding<Double?>(
                                get: { draft.treadmillInclinePercent },
                                set: { incline in
                                    draft.treadmillInclinePercent = incline
                                    if incline != nil { draft.isIndoor = true }
                                }
                            ), format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                    if draft.kind == .exercise {
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Sets", norwegian: "Sett"
                            ))
                            Spacer()
                            TextField("—", value: $draft.setCount, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Repetitions", norwegian: "Repetisjoner"
                            ))
                            Spacer()
                            TextField("—", value: $draft.repetitions, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Personal weight (kg)",
                                norwegian: "Personlig vekt (kg)"
                            ))
                            Spacer()
                            TextField("—", value: $draft.targetWeightKilograms, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if draft.kind == .exercise || draft.kind == .run {
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Target effort (RPE 1–10)",
                                norwegian: "Målintensitet (RPE 1–10)"
                            ))
                            Spacer()
                            TextField("—", value: $draft.targetEffortRPE, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    HStack {
                        Text(ATHLTHLocalization.choose(english: "Rest (sec)", norwegian: "Pause (sek)"))
                        Spacer()
                        TextField("—", value: $draft.restBetweenSetsSeconds, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section(ATHLTHLocalization.choose(english: "Notes", norwegian: "Notater")) {
                    TextField(ATHLTHLocalization.choose(english: "Optional", norwegian: "Valgfritt"),
                              text: Binding(get: { draft.notes ?? "" },
                                            set: { draft.notes = $0.isEmpty ? nil : $0 }))
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(english: "Edit step", norwegian: "Rediger øktdel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Save", norwegian: "Lagre")) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (draft.durationSeconds ?? 0) < 0 ||
                              (draft.restBetweenSetsSeconds ?? 0) < 0 ||
                              (draft.targetPaceSecondsPerKilometer ?? 0) < 0 ||
                              (draft.treadmillInclinePercent.map {
                                  !$0.isFinite || !(0...20).contains($0)
                              } ?? false) ||
                              (draft.targetWeightKilograms.map { !$0.isFinite || $0 < 0 } ?? false) ||
                              (draft.setCount.map { !(1...100).contains($0) } ?? false) ||
                              (draft.repetitions.map { !(1...1000).contains($0) } ?? false) ||
                              (draft.targetEffortRPE.map { !(1...10).contains($0) } ?? false) ||
                              (draft.targetHeartRateZone != nil &&
                               !(1...5).contains(draft.targetHeartRateZone!)))
                }
            }
        }
    }
}

/// Convert an existing detailed running prescription into the same read-only
/// timeline as a structured workout. All reps and recovery overrides survive.
extension RunningWorkoutTemplate {
    var recipePreviewBlocks: [WorkoutTemplateBlock] {
        var steps: [WorkoutTemplateBlock] = []
        for block in blocks {
            let phase: WorkoutPhaseKind
            switch block.kind {
            case .warmup: phase = .warmup
            case .cooldown: phase = .cooldown
            case .recovery: phase = .recovery
            case .work, .steady: phase = .main
            }

            for repetition in 1...min(max(block.repetitions, 1), 60) {
                let work = block.resolvedWork(at: repetition)
                let label = block.repetitions > 1
                    ? "\(block.title) · \(repetition)/\(block.repetitions)"
                    : block.title
                steps.append(previewStep(
                    title: label, target: work, phase: phase,
                    notes: block.override(for: repetition)?.notes ?? block.notes,
                    sequence: steps.count + 1
                ))
                if let recovery = block.resolvedRecovery(after: repetition) {
                    steps.append(previewStep(
                        title: ATHLTHLocalization.choose(
                            english: "Recovery", norwegian: "Pause"
                        ),
                        target: recovery, phase: .recovery, notes: nil,
                        sequence: steps.count + 1
                    ))
                }
            }
        }
        return steps
    }

    private func previewStep(
        title: String, target: RunningStepTarget, phase: WorkoutPhaseKind,
        notes: String?, sequence: Int
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: sequence, kind: .run, title: title,
            exerciseSlug: nil, distanceMeters: target.distanceMeters,
            repetitions: nil, durationSeconds: target.durationSeconds,
            targetWeightKilograms: nil, loadNote: nil, notes: notes,
            phase: phase,
            targetPaceSecondsPerKilometer:
                target.intensity.kind == .pace
                    ? target.intensity.paceMinSecondsPerKilometer : nil,
            targetHeartRateZone:
                target.intensity.kind == .heartRateZone
                    ? target.intensity.heartRateZone : nil
        )
    }
}
