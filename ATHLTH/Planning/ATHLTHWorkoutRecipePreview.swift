import Foundation
import SwiftUI

/// Shared UI-only titles and hints. Never changes saved sessions or the workout engine.
enum ATHLTHWorkoutStepCopy {
    static func isFourByFour(_ title: String) -> Bool {
        ATHLTHWorkoutSearch.normalized(title).contains("4x4")
    }

    static func title(for block: WorkoutTemplateBlock, workoutTitle: String, compact: Bool) -> String {
        let block = ATHLTHZonedLocalization.normalizeLegacyAllOutStep(block)
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

/// Presentation-only grouping over the canonical WorkoutTemplateBlock timeline.
/// Used by both Quick Train/library previews and the shared plan/quick editor.
/// Never edits, expands, reorders or rewrites a user's saved training prescription.
enum ATHLTHSimpleWorkoutOutline {
    struct Item: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let symbol: String
        let repetitions: Int
        let representedSteps: Int
    }

    struct Stage: Identifiable {
        let id: Int
        let phase: WorkoutPhaseKind
        let sourceStepCount: Int
        let plannedSeconds: TimeInterval?
        let items: [Item]
    }

    private struct IndexedBlock {
        let index: Int
        let block: WorkoutTemplateBlock
    }

    /// Recovery belongs to the preceding main exercise for display only.
    /// The source retains its actual recovery phase and execution sequence.
    static func stages(for blocks: [WorkoutTemplateBlock]) -> [Stage] {
        var groups: [(phase: WorkoutPhaseKind, steps: [IndexedBlock])] = []
        var lastWorkPhase: WorkoutPhaseKind = .main
        for (index, block) in blocks.enumerated() {
            let phase: WorkoutPhaseKind
            if block.resolvedPhase == .recovery {
                phase = lastWorkPhase
            } else {
                phase = block.resolvedPhase
                lastWorkPhase = phase
            }
            if let last = groups.indices.last, groups[last].phase == phase {
                groups[last].steps.append(.init(index: index, block: block))
            } else {
                groups.append((phase: phase, steps: [.init(index: index, block: block)]))
            }
        }
        return groups.map { group in
            let times = group.steps.map { $0.block.durationSeconds }
            let sum = times.compactMap { $0 }.filter { $0 > 0 }.reduce(0, +)
            return Stage(
                id: group.steps[0].index,
                phase: group.phase,
                sourceStepCount: group.steps.count,
                plannedSeconds: sum > 0 ? sum : nil,
                items: compactItems(group.steps)
            )
        }
    }

    private static func compactItems(_ steps: [IndexedBlock]) -> [Item] {
        var result: [Item] = []
        var cursor = 0
        while cursor < steps.count {
            let work = steps[cursor]
            let recovery = cursor + 1 < steps.count &&
                isRecovery(steps[cursor + 1].block)
                ? steps[cursor + 1] : nil
            let pairSize = recovery == nil ? 1 : 2
            var count = 1
            var consumed = pairSize

            // Collapse repeated *identical* work/recovery pairs. Different
            // targets, durations or individual variations remain distinct.
            if !isRecovery(work.block) {
                while cursor + consumed < steps.count {
                    let next = steps[cursor + consumed].block
                    guard samePrescription(work.block, next) else { break }
                    if let recovery {
                        let nextRest = cursor + consumed + 1
                        if nextRest < steps.count &&
                            samePrescription(recovery.block, steps[nextRest].block) {
                            consumed += 2
                        } else if nextRest == steps.count {
                            // Final effort may intentionally omit its recovery.
                            consumed += 1
                        } else {
                            break
                        }
                    } else {
                        consumed += 1
                    }
                    count += 1
                }
            }

            let workText = work.block.durationSeconds.map {
                ATHLTHWorkoutStepCopy.duration($0)
            } ?? work.block.targetText ?? (
                (work.block.kind == .run || work.block.kind == .rest)
                    ? ATHLTHLocalization.choose(
                        english: "Manual next", norwegian: "Fortsett manuelt"
                    ) : ""
            )
            let recoveryText = recovery?.block.durationSeconds.map {
                ATHLTHWorkoutStepCopy.duration($0)
            } ?? recovery?.block.targetText

            let detail: String
            if let recoveryText {
                detail = ATHLTHLocalization.choose(
                    english: "\(workText) work · \(recoveryText) recovery",
                    norwegian: "\(workText) arbeid · \(recoveryText) pause"
                )
            } else {
                detail = workText
            }
            let itemTitle = conciseTitle(
                ATHLTHZonedLocalization.normalizeLegacyAllOutStep(work.block).title
            )
            let displayTitle = count > 1 ? "\(count) × \(itemTitle)" : itemTitle
            result.append(Item(
                id: work.index,
                title: displayTitle,
                detail: detail,
                symbol: work.block.kind.systemImage,
                repetitions: count,
                representedSteps: consumed
            ))
            cursor += consumed
        }
        return result
    }

    private static func isRecovery(_ block: WorkoutTemplateBlock) -> Bool {
        block.kind == .rest || block.resolvedPhase == .recovery
    }

    /// Drop only sequence numbers appended by imported interval previews.
    private static func conciseTitle(_ value: String) -> String {
        let parts = value.components(separatedBy: " · ")
        guard let last = parts.last,
              last.contains("/"),
              last.split(separator: "/").count == 2,
              last.split(separator: "/").allSatisfy({
                  Int(String($0).trimmingCharacters(in: .whitespaces)) != nil
              })
        else { return value }
        return parts.dropLast().joined(separator: " · ")
    }

    private static func samePrescription(
        _ a: WorkoutTemplateBlock,
        _ b: WorkoutTemplateBlock
    ) -> Bool {
        conciseTitle(a.title) == conciseTitle(b.title) &&
            a.kind == b.kind &&
            a.resolvedPhase == b.resolvedPhase &&
            a.durationSeconds == b.durationSeconds &&
            a.distanceMeters == b.distanceMeters &&
            a.repetitions == b.repetitions &&
            a.setCount == b.setCount &&
            a.targetPaceSecondsPerKilometer == b.targetPaceSecondsPerKilometer &&
            a.targetHeartRateZone == b.targetHeartRateZone &&
            a.targetWeightKilograms == b.targetWeightKilograms &&
            a.treadmillInclinePercent == b.treadmillInclinePercent &&
            a.targetEffortRPE == b.targetEffortRPE &&
            a.targetHeartRatePercentMin == b.targetHeartRatePercentMin &&
            a.targetHeartRatePercentMax == b.targetHeartRatePercentMax &&
            a.sourceIntensityZoneLabel == b.sourceIntensityZoneLabel &&
            a.individualSetTargets == b.individualSetTargets &&
            a.restBetweenSetsSeconds == b.restBetweenSetsSeconds &&
            a.loadNote == b.loadNote &&
            a.exerciseID == b.exerciseID &&
            a.exerciseSnapshot == b.exerciseSnapshot &&
            a.notes == b.notes &&
            a.groupID == b.groupID &&
            a.groupKind == b.groupKind &&
            a.executionGroupID == b.executionGroupID &&
            a.executionGroupKind == b.executionGroupKind &&
            a.cardioActivity == b.cardioActivity &&
            a.isIndoor == b.isIndoor
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
    @EnvironmentObject private var session: AppSessionStore
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

    private var maximumHeartRateBPM: Double? {
        ATHLTHHeartRateZones.resolvedMaximumBPM(
            configured: session.onboardingProfile?.maximumHeartRateBPM,
            dateOfBirth: session.onboardingProfile?.dateOfBirth
        )
    }

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
            }
            modeControl
            if advanced && !embeddedInDetails {
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
            if advanced {
                expandableOutline
            } else {
                simpleOutline
            }
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
                    ATHLTHWorkoutStepDetails(
                        block: ATHLTHZonedLocalization
                            .normalizeLegacyAllOutStep(item.block),
                        displayTitle: localizedTitle(item.block, compact: false),
                        maximumHeartRateBPM: maximumHeartRateBPM,
                        suggestion: ATHLTHWorkoutStepCopy.suggestedZone(
                            for: item.block, workoutTitle: title
                        )
                    )
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

    /// Mode is immediately below the identity card in every shared preview.
    /// Simple remains a readable recipe; Advanced retains all target details.
    private var modeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("View workout", "Vis økten"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer(minLength: 4)
                Text(advanced
                    ? tr("All details", "Alle detaljer")
                    : tr("At a glance", "Kort oversikt"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            Picker(tr("Detail level", "Detaljnivå"), selection: $advanced) {
                Text(tr("Simple", "Enkel")).tag(false)
                Text(tr("Advanced", "Avansert")).tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("workout-recipe-detail-mode")
            .accessibilityHint(tr(
                "Choose a quick overview or detailed targets and rests.",
                "Velg kort oversikt eller detaljerte mål og pauser."
            ))
        }
        .padding(13)
        .background(
            ATHLTHPlanDesign.selectedSurface.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    /// A quick understanding of WHAT to do, not 26 individual settings.
    /// Changing to Advanced shows the unchanged original step-by-step recipe.
    private var simpleOutline: some View {
        let stages = ATHLTHSimpleWorkoutOutline.stages(for: blocks)
        return VStack(alignment: .leading, spacing: 11) {
            if !stages.isEmpty {
                Text(tr("This is your workout", "Dette skal du gjøre"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
            }

            ForEach(stages) { stage in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 9) {
                        Image(systemName: stage.phase.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(recipeTint)
                            .frame(width: 34, height: 34)
                            .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                        Text(stage.phase.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Spacer(minLength: 4)
                        if let seconds = stage.plannedSeconds {
                            Text(ATHLTHWorkoutDurationEstimator.conciseDuration(seconds))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .monospacedDigit()
                        }
                    }

                    ForEach(Array(stage.items.prefix(3))) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 14))
                                .foregroundStyle(recipeTint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                if !item.detail.isEmpty {
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }

                    if stage.items.count > 3 {
                        Text(tr(
                            "\(stage.items.count - 3) more variations in Advanced",
                            "\(stage.items.count - 3) flere varianter i Avansert"
                        ))
                        .font(.caption)
                        .foregroundStyle(recipeTint)
                    }
                }
                .padding(15)
                .athlthPlanCard(radius: 19)
            }

            if onUpdateBlock != nil && !stages.isEmpty {
                Text(tr(
                    "Need to change pace, rests or individual steps? Choose Advanced above.",
                    "Vil du endre tempo, pauser eller enkeltdrag? Velg Avansert over."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .accessibilityIdentifier("athlth-simple-workout-outline")
    }

    /// Existing library recipes stay in their original warm-up/main/cool-down
    /// phases. A phase opens to a compact exercise list, and each exercise can
    /// open again to reveal rests and the editing action.
    private var expandableOutline: some View {
        let sections = ATHLTHWorkoutPhaseOutline.sections(for: blocks)
        return LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(sections) { section in
                phaseDisclosure(section.phase, count: section.indices.count)
                if !collapsedPhases.contains(section.phase) {
                    ForEach(section.indices, id: \.self) { index in
                        recipeStepCard(blocks[index], index: index)
                            .padding(.leading, 9)
                    }
                }
            }
        }
    }

    private func phaseDisclosure(
        _ phase: WorkoutPhaseKind, count: Int
    ) -> some View {
        let collapsed = collapsedPhases.contains(phase)
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
                            if let pulse = ATHLTHPlannedHeartRatePreview.rangeText(
                                for: block, maximumBPM: maximumHeartRateBPM
                            ) {
                                Text(pulse)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(recipeTint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(
                                (block.kind == .run || block.kind == .rest) &&
                                block.durationSeconds == nil &&
                                block.distanceMeters == nil
                                    ? tr("Open-ended · continue manually",
                                         "Åpen øktdel · fortsett manuelt")
                                    : tr("Open to see workout instructions",
                                         "Åpne for å se øktdetaljer")
                            )
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
                        editingStep = IndexedWorkoutStep(
                            index: index,
                            block: ATHLTHZonedLocalization.normalizeLegacyAllOutStep(block)
                        )
                    } label: {
                        Label(block.kind == .exercise
                                ? tr("Edit sets, weight and targets", "Rediger sett, vekt og mål")
                                : tr("Edit duration and targets", "Rediger varighet og mål"),
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
                            inspectedCardioStep = IndexedWorkoutStep(
                                index: index,
                                block: ATHLTHZonedLocalization.normalizeLegacyAllOutStep(block)
                            )
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
        let block = ATHLTHZonedLocalization.normalizeLegacyAllOutStep(block)
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
        _draft = State(initialValue:
            ATHLTHZonedLocalization.normalizeLegacyAllOutStep(block)
        )
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
                        TextField("—", value: $draft.durationSeconds, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if let seconds = draft.durationSeconds, seconds > 0 {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Workout segment: ",
                                norwegian: "Deløkt: "
                            ) + ATHLTHWorkoutStepCopy.duration(seconds),
                            systemImage: "timer"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    }
                    if draft.durationSeconds == nil &&
                       draft.distanceMeters == nil &&
                       (draft.kind == .run || draft.kind == .rest) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Open-ended: use Next to finish this step.",
                                norwegian: "Åpen øktdel: bruk Neste for å avslutte delen."
                            ),
                            systemImage: "hand.tap"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
                Section(ATHLTHLocalization.choose(english: "Targets", norwegian: "Mål")) {
                    HStack {
                        Text(ATHLTHLocalization.choose(english: "Pace (sec/km)", norwegian: "Tempo (sek/km)"))
                        Spacer()
                        TextField("—", value: $draft.targetPaceSecondsPerKilometer, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Target HR zone", norwegian: "Målpulssone"
                        ),
                        selection: Binding<Int?>(
                            get: { draft.targetHeartRateZone },
                            set: { selected in
                                draft.targetHeartRateZone = selected
                                // A personal override must not retain the
                                // source's older percentage interval/label.
                                // Otherwise the UI and Watch may disagree.
                                draft.sourceIntensityZoneLabel = nil
                                draft.targetHeartRatePercentMin = nil
                                draft.targetHeartRatePercentMax = nil
                            }
                        )
                    ) {
                        Text(ATHLTHLocalization.choose(
                            english: "No target", norwegian: "Ingen målsone"
                        ))
                        .tag(nil as Int?)
                        ForEach(1...5, id: \.self) { zone in
                            Text("Z\(zone)").tag(zone as Int?)
                        }
                    }
                    if let originalZone = ATHLTHWorkoutStepTargetSummary
                        .zoneLabel(for: draft),
                       draft.sourceIntensityZoneLabel != nil {
                        Text(ATHLTHLocalization.choose(
                            english: "Original prescription: ", norwegian: "Planlagt fra biblioteket: "
                        ) + originalZone)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    if draft.kind == .run && draft.isIndoor == true {
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
                Section(ATHLTHLocalization.choose(
                    english: "Workout instructions", norwegian: "Instruksjoner"
                )) {
                    TextEditor(text: Binding(
                        get: { draft.notes ?? "" },
                        set: { draft.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minHeight: 88)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Instructions and notes",
                        norwegian: "Instruksjoner og notater"
                    ))
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
