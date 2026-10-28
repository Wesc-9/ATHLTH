import SwiftUI

/// Inline Plan presentation reads the same ordered blocks that the workout
/// engine executes. Only the UI changes; no duplicate session model is saved.
enum ATHLTHPlanWorkoutCardPresentation {
    struct Entry: Identifiable {
        let id: Int
        let block: WorkoutTemplateBlock
        let sourceIndex: Int
        let groupTitle: String?
        let groupSteps: [WorkoutTemplateBlock]?
        let groupStepIndex: Int?
    }

    struct Section: Identifiable {
        let id: Int
        let phase: WorkoutPhaseKind
        var entries: [Entry]
        var activityCount: Int {
            let work = entries.filter { $0.block.kind != .rest }.count
            return work > 0 ? work : entries.count
        }
    }

    static func entries(from blocks: [WorkoutTemplateBlock]) -> [Entry] {
        var entries: [Entry] = []
        var index = 0
        while index < blocks.count && entries.count < 1_000 {
            let sourceIndex = index
            let first = blocks[index]
            if let groupID = first.groupID, let groupKind = first.groupKind {
                while index < blocks.count && blocks[index].groupID == groupID {
                    index += 1
                }
                let expanded = Array(blocks[sourceIndex..<index]).expandedForExecution()
                let rounds = Swift.min(Swift.max(first.groupRounds ?? 1, 1), 20)
                let name = groupKind.title + " · \(rounds) " +
                    ATHLTHLocalization.choose(english: "rounds", norwegian: "runder")
                for (stepIndex, item) in expanded.enumerated() where entries.count < 1_000 {
                    entries.append(Entry(
                        id: entries.count, block: item, sourceIndex: sourceIndex,
                        groupTitle: name, groupSteps: expanded,
                        groupStepIndex: stepIndex
                    ))
                }
            } else {
                index += 1
                // Individual strength sets include recovery only between sets.
                for item in [first].expandedForExecution() where entries.count < 1_000 {
                    entries.append(Entry(
                        id: entries.count, block: item, sourceIndex: sourceIndex,
                        groupTitle: nil, groupSteps: nil, groupStepIndex: nil
                    ))
                }
            }
        }
        return entries
    }

    static func sections(for blocks: [WorkoutTemplateBlock]) -> [Section] {
        var sections: [Section] = []
        for entry in entries(from: blocks) {
            // The pause inherits the preceding phase instead of being
            // collected in a separate pause section after the final interval.
            let phase = entry.block.kind == .rest
                ? (sections.last?.phase ?? entry.block.resolvedPhase)
                : entry.block.resolvedPhase
            if let last = sections.indices.last, sections[last].phase == phase {
                sections[last].entries.append(entry)
            } else {
                sections.append(Section(id: sections.count, phase: phase, entries: [entry]))
            }
        }
        return sections
    }

    /// Show explicit targets only; never synthesize a zero incline/pace.
    static func facts(for block: WorkoutTemplateBlock, workoutTitle: String? = nil) -> [String] {
        var facts: [String] = []
        if let seconds = block.durationSeconds, seconds.isFinite, seconds > 0 {
            let whole = Int(seconds.rounded())
            let mins = whole / 60, remainder = whole % 60
            facts.append(mins > 0
                ? (remainder == 0 ? "\(mins) min" : "\(mins) min \(remainder) s")
                : "\(remainder) s")
        }
        if let distance = block.distanceMeters, distance.isFinite, distance > 0 {
            facts.append(distance >= 1_000
                ? String(format: "%.1f km", distance / 1_000)
                : "\(Int(distance.rounded())) m")
        }
        if let sets = block.setCount, sets > 1, block.kind == .exercise {
            facts.append("\(sets) sett")
        }
        if let reps = block.repetitions, reps > 0 { facts.append("\(reps) reps") }
        if let kilograms = block.targetWeightKilograms,
           kilograms.isFinite, kilograms >= 0 {
            facts.append(String(format: "%.1f kg", kilograms))
        }
        if let pace = block.targetPaceSecondsPerKilometer,
           pace.isFinite, pace > 0 {
            let seconds = Int(pace.rounded())
            facts.append(ATHLTHLocalization.choose(
                english: "Pace ", norwegian: "Tempo "
            ) + String(format: "%d:%02d/km", seconds / 60, seconds % 60))
        }
        if let incline = block.treadmillInclinePercent,
           incline.isFinite, (0...20).contains(incline) {
            facts.append(ATHLTHLocalization.choose(
                english: "Incline ", norwegian: "Stigning "
            ) + String(format: "%.1f %%", incline))
        }
        if let zone = block.targetHeartRateZone, (1...5).contains(zone) {
            facts.append(ATHLTHLocalization.choose(
                english: "HR zone Z", norwegian: "Pulssone S"
            ) + "\(zone)")
        } else if let workoutTitle,
                  let suggestion = ATHLTHWorkoutStepCopy.suggestedZone(
                    for: block, workoutTitle: workoutTitle
                  ) {
            facts.append(suggestion)
        }
        if let rpe = block.targetEffortRPE, (1...10).contains(rpe) {
            facts.append("RPE \(rpe)/10")
        }
        if let between = block.restBetweenSetsSeconds, between > 0,
           block.kind == .exercise {
            facts.append("\(Int(between.rounded())) s " +
                ATHLTHLocalization.choose(english: "between sets", norwegian: "mellom sett"))
        }
        return facts
    }
}

struct ATHLTHPlanWorkoutExpandableCard: View {
    let workout: PlannedSession
    let completed: Bool
    let skipped: Bool
    let onEditBlock: (Int?, Int?) -> Void

    @State private var expanded = false
    @State private var selectedDetail: Selection?
    @State private var editAfterDismiss = false
    @State private var editSourceIndex: Int?
    @State private var editGroupStepIndex: Int?
    @State private var viewingEntireInterval = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Selection: Identifiable {
        let id = UUID()
        let title: String
        let blocks: [WorkoutTemplateBlock]
        let groupSteps: [WorkoutTemplateBlock]?
        let sourceIndex: Int?
        let groupStepIndex: Int?
    }

    private let ink = ATHLTHTrainDesign.ink
    private let secondary = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let paper = ATHLTHTrainDesign.canvas

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var sourceBlocks: [WorkoutTemplateBlock] {
        ATHLTHUnifiedWorkout.editorBlocks(from: workout)
    }

    private var timeline: [ATHLTHPlanWorkoutCardPresentation.Entry] {
        ATHLTHPlanWorkoutCardPresentation.entries(from: sourceBlocks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    Image(workout.kind == .running ? "GoalRunning" :
                        (workout.kind == .strength ? "StrengthQuickHero" : "GoalWalking"))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 59, height: 59)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(workout.title)
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 5) {
                            if let duration = ATHLTHPlannedWorkoutPresentation.duration(for: workout) {
                                Text(duration)
                            }
                            Text("·")
                            Text(workout.kind.title)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(secondary)
                        Text(completed ? tr("Completed", "Fullført") :
                             skipped ? tr("Skipped", "Hoppet over") :
                             expanded ? tr("Tap to collapse", "Trykk for å lukke") :
                             tr("Tap for all exercise details", "Trykk for alle øktdetaljer"))
                            .font(.system(size: 10))
                            .foregroundStyle(completed ? Color.green : secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(bronze)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(paper.opacity(0.68), in: RoundedRectangle(cornerRadius: 15))
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr(
                "Expand or collapse workout steps", "Utvid eller lukk øktens detaljer"
            ))
            if expanded {
                // Virtualize large mixed strength / interval timelines while
                // preserving the complete ordered list for the user.
                LazyVStack(alignment: .leading, spacing: 11) {
                    if sourceBlocks.isEmpty {
                        Text(tr("No detailed steps yet.", "Ingen detaljerte øktblokker ennå."))
                            .font(.caption)
                            .foregroundStyle(secondary)
                    } else {
                        HStack {
                            Text(tr("Workout timeline", "Øktens tidslinje"))
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Text("\(timeline.count) " + tr("steps", "steg"))
                                .font(.caption).foregroundStyle(secondary)
                        }
                        ForEach(ATHLTHPlanWorkoutCardPresentation.sections(for: sourceBlocks)) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 7) {
                                    Image(systemName: section.phase.symbol)
                                    Text(section.phase.title)
                                    Text("(\(section.activityCount))").foregroundStyle(secondary)
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ink)
                                ForEach(section.entries) { entry in
                                    Button {
                                        viewingEntireInterval = false
                                        selectedDetail = Selection(
                                            title: ATHLTHWorkoutStepCopy.title(
                                                for: entry.block,
                                                workoutTitle: workout.title,
                                                compact: false
                                            ),
                                            blocks: [entry.block],
                                            groupSteps: entry.groupSteps,
                                            sourceIndex: entry.sourceIndex,
                                            groupStepIndex: entry.groupStepIndex
                                        )
                                    } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: entry.block.kind == .rest
                                                ? "pause.circle.fill" :
                                                entry.block.kind == .exercise
                                                    ? "dumbbell" : "figure.run")
                                                .font(.system(size: 12))
                                                .foregroundStyle(bronze)
                                                .frame(width: 22)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(ATHLTHWorkoutStepCopy.title(
                                                    for: entry.block,
                                                    workoutTitle: workout.title,
                                                    compact: false
                                                ))
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(ink)
                                                let facts = ATHLTHPlanWorkoutCardPresentation.facts(
                                                    for: entry.block, workoutTitle: workout.title)
                                                if !facts.isEmpty {
                                                    Text(facts.joined(separator: " · "))
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(secondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                                if entry.groupTitle != nil {
                                                    Text(tr("Open entire interval group",
                                                            "Åpne hele intervallserien"))
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(bronze)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundStyle(secondary)
                                        }
                                        .padding(10)
                                        .background(entry.block.kind == .rest
                                            ? ATHLTHTrainDesign.paleGold.opacity(0.35)
                                            : paper.opacity(0.72),
                                            in: RoundedRectangle(cornerRadius: 11))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HStack(spacing: 9) {
                        Button {
                            selectedDetail = Selection(
                                title: workout.title, blocks: timeline.map(\.block),
                                groupSteps: nil, sourceIndex: nil, groupStepIndex: nil
                            )
                        } label: {
                            Label(tr("Entire workout", "Hele økten"), systemImage: "list.bullet")
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.bordered)
                        Button { onEditBlock(nil, nil) } label: {
                            Label(tr("Edit workout", "Rediger økt"),
                                  systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.semibold))
                    .tint(bronze)
                }
                .padding(.horizontal, 7)
                .padding(.top, 12)
                .padding(.bottom, 5)
            }
        }
        .sheet(item: $selectedDetail, onDismiss: {
            if editAfterDismiss {
                editAfterDismiss = false
                onEditBlock(editSourceIndex, editGroupStepIndex)
                editSourceIndex = nil
                editGroupStepIndex = nil
            }
        }) { selection in
            detailSheet(selection)
                .presentationDragIndicator(.visible)
        }
    }

    private func detailSheet(_ selection: Selection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text(selection.title)
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let allSteps = selection.groupSteps {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewingEntireInterval.toggle()
                            }
                        } label: {
                            Label(
                                viewingEntireInterval
                                    ? tr("Show selected effort", "Vis valgt drag")
                                    : tr("Show entire interval series", "Vis hele intervallserien"),
                                systemImage: viewingEntireInterval
                                    ? "chevron.up" : "list.number"
                            )
                            .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.bordered)
                        Text("\(allSteps.count) " + tr("steps in the series", "deler i serien"))
                            .font(.caption)
                            .foregroundStyle(secondary)
                    }
                    ForEach(Array((viewingEntireInterval
                        ? (selection.groupSteps ?? selection.blocks)
                        : selection.blocks).enumerated()), id: \.offset) { _, block in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(block.title).font(.headline).foregroundStyle(ink)
                            Text(block.resolvedPhase.title)
                                .font(.caption)
                                .foregroundStyle(bronze)
                            let facts = ATHLTHPlanWorkoutCardPresentation.facts(for: block)
                            if !facts.isEmpty {
                                Text(facts.joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let notes = block.notes, !notes.isEmpty {
                                Text(notes).font(.subheadline).foregroundStyle(secondary)
                            }
                            if let loading = block.loadNote, !loading.isEmpty {
                                Text(loading).font(.caption).foregroundStyle(secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button {
                        editSourceIndex = selection.sourceIndex
                        editGroupStepIndex = selection.groupStepIndex
                        editAfterDismiss = true
                        selectedDetail = nil
                    } label: {
                        Label(tr("Edit in workout builder", "Rediger i øktbygger"),
                              systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(bronze.gradient,
                                        in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Workout details", "Øktdetaljer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Done", "Ferdig")) { selectedDetail = nil }
                }
            }
        }
    }
}
