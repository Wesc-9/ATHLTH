import SwiftUI

/// The single Plan-specific presentation for the unified workout recipe.
/// No parallel workout model: every row is a real editable WorkoutTemplateBlock.
/// Phases are optional; an empty scratch workout has no preset sections.
struct ATHLTHPlannedWorkoutStudioView: View {
    @Binding var blocks: [WorkoutTemplateBlock]
    @Binding var visiblePhases: Set<WorkoutPhaseKind>
    @Binding var selectedPhase: WorkoutPhaseKind

    let advanced: Bool
    let activity: ATHLTHPlannedWorkoutType?
    let hasSelectedRoute: Bool
    let onAddRun: (WorkoutPhaseKind) -> Void
    let onAddIntervals: (WorkoutPhaseKind) -> Void
    let onAddExercise: (WorkoutPhaseKind) -> Void
    let onAddFreeStrength: (WorkoutPhaseKind) -> Void
    let onAddSuperset: (WorkoutPhaseKind) -> Void
    let onAddCircuit: (WorkoutPhaseKind) -> Void
    let onAddStrengthMode: (WorkoutPhaseKind, WorkoutBlockGroupKind) -> Void
    let onSetGroupClock: (UUID, TimeInterval) -> Void
    let onSetStationTransition: (UUID, Int) -> Void
    let onAddDropStage: (UUID) -> Void
    let onAddExerciseToSuperset: (WorkoutPhaseKind, UUID) -> Void
    let onAddRestToSuperset: (WorkoutPhaseKind, UUID) -> Void
    let onMoveSupersetMember: (UUID, UUID) -> Void
    let onSetSupersetRounds: (UUID, Int) -> Void
    let onUngroupSuperset: (UUID) -> Void
    let onDeleteSuperset: (UUID) -> Void
    let onAddRest: (WorkoutPhaseKind) -> Void
    let onAddActiveRest: (WorkoutPhaseKind) -> Void
    let onAddWorkout: (WorkoutPhaseKind) -> Void
    let onImportWorkout: () -> Void
    let onSelectRoute: (WorkoutPhaseKind) -> Void
    let onBuildRoute: (WorkoutPhaseKind) -> Void
    let onEdit: (UUID) -> Void
    let onMove: (UUID, WorkoutPhaseKind, UUID?) -> Void
    let onRemove: (UUID) -> Void
    let onRemovePhase: (WorkoutPhaseKind) -> Void
    let onUpdateIntervalGroup: (UUID, Int, Bool) -> Void
    let onAdjustInterval: (
        UUID, Int, Bool, WorkoutTemplateBlock?, WorkoutTemplateBlock?
    ) -> Void
    let onCopyIntervalTargets: (UUID) -> Void
    let onUngroupIntervals: (UUID) -> Void
    let onDeleteInterval: (UUID) -> Void

    @State private var phasePendingDeletion: WorkoutPhaseKind?
    @State private var collapsedPhases: Set<WorkoutPhaseKind> = []
    @State private var expandedIntervalGroups: Set<UUID> = []
    @State private var collapsedSupersetGroups: Set<UUID> = []
    @State private var intervalToAdjust: IntervalSelection?
    @State private var intervalPendingDeletion: UUID?
    @State private var draggingID: UUID?

    private struct IntervalSelection: Identifiable {
        let id: UUID
    }
    @State private var dragPoint: CGPoint = .zero
    @State private var dragFingerOffsetY: CGFloat = 0
    @State private var dragGeometry = ATHLTHStudioDragGeometry()

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze
    private let paper = ATHLTHPlanDesign.surface

    private var phases: [WorkoutPhaseKind] {
        WorkoutPhaseKind.allCases.filter { phase in
            visiblePhases.contains(phase) || blocks.contains {
                presentationPhase(for: $0) == phase
            }
        }
    }

    private func presentationPhase(for block: WorkoutTemplateBlock) -> WorkoutPhaseKind {
        // Recovery steps remain inside the selected work phase unless the
        // athlete explicitly added a standalone recovery section.
        ATHLTHWorkoutPhaseDeletionPolicy.presentedPhase(
            for: block, visiblePhases: visiblePhases
        )
    }

    private var routeAsWholeWorkout: WorkoutTemplateBlock? {
        guard hasSelectedRoute, visiblePhases.isEmpty,
              blocks.count == 1, blocks[0].kind == .run,
              blocks[0].distanceMeters != nil else { return nil }
        return blocks[0]
    }

    private func entries(in phase: WorkoutPhaseKind) -> [WorkoutTemplateBlock] {
        blocks.filter { presentationPhase(for: $0) == phase }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ØKTINNHOLD")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(bronze)
                    Text(ATHLTHLocalization.choose(
                        english: "Build your workout", norwegian: "Bygg økten"
                    ))
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                }
                Spacer(minLength: 2)
                addSectionMenu
            }

            Button(action: onImportWorkout) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Import a workout from a file",
                        norwegian: "Importer treningsøkt fra fil"
                    ),
                    systemImage: "square.and.arrow.down"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(bronze)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
            }
            .buttonStyle(.bordered)
            .tint(bronze)
            .accessibilityIdentifier("athlth-import-planned-workout-file")

            if advanced && activity == .strength {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        strengthHelp("Superset", "Supersett", "Two or more exercises in sequence before resting.", "To eller flere øvelser etter hverandre før pause.")
                        strengthHelp("Circuit", "Sirkeltrening", "Repeat a round of stations with an optional transition between them.", "Gjenta en runde med stasjoner, med valgfri overgangspause.")
                        strengthHelp("EMOM", "EMOM", "Start the prescribed work each minute. Rest for the remaining time.", "Start arbeidet hvert minutt. Hvil resten av minuttet.")
                        strengthHelp("AMRAP", "AMRAP", "Complete as many controlled rounds or repetitions as you can in the chosen time.", "Gjør så mange kontrollerte runder eller repetisjoner du rekker innen valgt tid.")
                        strengthHelp("Drop set", "Dropsett", "Lower the weight between stages and continue with little rest.", "Reduser vekten mellom delene og fortsett med kort pause.")
                        strengthHelp("Free strength", "Fri styrketrening", "Record a strength workout without predefined exercises.", "Registrer styrketrening uten forhåndsbestemte øvelser.")
                    }.padding(.top, 8)
                } label: {
                    Label(ATHLTHLocalization.choose(english: "What do the training modes mean?", norwegian: "Hva betyr treningsformene?"), systemImage: "info.circle")
                        .font(.subheadline)
                }
                .tint(bronze)
                .padding(12)
                .background(paper, in: RoundedRectangle(cornerRadius: 14))
            }

            if let routeBlock = routeAsWholeWorkout {
                VStack(alignment: .leading, spacing: 9) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Route as complete workout",
                            norwegian: "Rute som hele økten"
                        ), systemImage: "map"
                    )
                    .font(.headline)
                    .foregroundStyle(ink)
                    stepRow(routeBlock, position: 1, phase: .main)
                    addContentMenu(.main)
                }
                .padding(12)
                .athlthPlanCard(radius: 19)
            } else if phases.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 25))
                        .foregroundStyle(bronze)
                    Text(ATHLTHLocalization.choose(
                        english: "Start with a blank workout",
                        norwegian: "Start med en tom økt"
                    ))
                    .font(.headline)
                    Text(ATHLTHLocalization.choose(
                        english: "Add an activity, a route, or a workout section. No warm-up or main set is required.",
                        norwegian: "Legg til en øvelse, rute eller øktdel. Oppvarming og hoveddel er valgfrie."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Button {
                            // Strength always enters the exercise library.
                            // Other activities keep the existing quick-add path.
                            if activity == .strength {
                                onAddExercise(.main)
                            } else {
                                onAddRun(.main)
                            }
                            visiblePhases.insert(.main)
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Add activity", norwegian: "Legg til øvelse"
                            ), systemImage: "plus")
                        }
                        Button {
                            onSelectRoute(.main)
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Route", norwegian: "Rute"
                            ), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(bronze)
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .athlthPlanCard(radius: 22)
            }

            if routeAsWholeWorkout == nil {
                if advanced {
                    ForEach(phases) { phase in
                        phaseCard(phase)
                    }
                } else {
                    simpleBuilderOutline
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: visiblePhases)
        .coordinateSpace(name: "athlthWorkoutStudio")
        .sheet(item: $intervalToAdjust) { selection in
            ATHLTHIntervalGroupAdjustmentView(
                groupID: selection.id, blocks: blocks
            ) { rounds, finalRecovery, work, recovery in
                onAdjustInterval(
                    selection.id, rounds, finalRecovery, work, recovery
                )
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Delete entire interval?",
                norwegian: "Slette hele intervallen?"
            ),
            isPresented: Binding(
                get: { intervalPendingDeletion != nil },
                set: { if !$0 { intervalPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Delete entire interval",
                norwegian: "Slett hele intervallen"
            ), role: .destructive) {
                if let id = intervalPendingDeletion {
                    onDeleteInterval(id)
                    expandedIntervalGroups.remove(id)
                }
                intervalPendingDeletion = nil
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {
                intervalPendingDeletion = nil
            }
        } message: {
            let count = blocks.filter { $0.groupID == intervalPendingDeletion }.count
            Text(ATHLTHLocalization.format(
                english: "All %d efforts and recoveries in this interval will be deleted. Other workout sections are kept.",
                norwegian: "Alle %d drag og pauser i intervallen slettes. Resten av treningsøkten beholdes.",
                count
            ))
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Delete workout section?",
                norwegian: "Slette hele kategorien?"
            ),
            isPresented: Binding(
                get: { phasePendingDeletion != nil },
                set: { if !$0 { phasePendingDeletion = nil } }
            )
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Delete section", norwegian: "Slett kategori"
            ), role: .destructive) {
                if let phase = phasePendingDeletion {
                    onRemovePhase(phase)
                }
                phasePendingDeletion = nil
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {
                phasePendingDeletion = nil
            }
        } message: {
            let count = phasePendingDeletion.map { entries(in: $0).count } ?? 0
            Text(ATHLTHLocalization.format(
                english: "All %d workout steps in this section will also be deleted. This cannot be undone.",
                norwegian: "Alle %d deløkter i kategorien slettes også. Dette kan ikke angres.",
                count
            ))
        }
        // The floating copy follows the finger independently of the rows
        // changing places. The original keeps its layout slot during dragging.
        .overlay(alignment: .topLeading) {
            if let draggingID,
               let block = blocks.first(where: { $0.editorDragID == draggingID }),
               let frame = dragGeometry.rowFrames[draggingID] {
                ATHLTHPlannedWorkoutStepRow(
                    block: block,
                    position: (entries(in: presentationPhase(for: block))
                        .firstIndex(where: { $0.editorDragID == draggingID }) ?? 0) + 1,
                    canMoveUp: false,
                    canMoveDown: false,
                    onEdit: {},
                    onDelete: {},
                    onMoveBy: { _ in },
                    onReorderMove: { _ in },
                    onReorderEnd: {}
                )
                .frame(width: frame.width, height: frame.height)
                .background(ATHLTHPlanDesign.surface,
                            in: RoundedRectangle(cornerRadius: 13))
                .scaleEffect(1.035)
                .shadow(color: .black.opacity(0.19), radius: 12, y: 7)
                .position(x: frame.midX, y: dragPoint.y - dragFingerOffsetY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(100)
            }
        }
    }

    /// One shared compact presentation of the SAME canonical recipe used by
    /// Quick Train and planned workouts; no separate easy-mode editor model.
    /// Advanced still owns per-step edits, targets, reordering and all groups.
    private var simpleBuilderOutline: some View {
        let outlines = ATHLTHSimpleWorkoutOutline.stages(
            for: blocks.expandedForExecution()
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text(ATHLTHLocalization.choose(
                english: "Your workout at a glance",
                norwegian: "Økten din – kort fortalt"
            ))
            .font(.headline)
            .foregroundStyle(ink)

            ForEach(phases) { phase in
                let stageRows = outlines.filter { $0.phase == phase }
                let items = stageRows.flatMap(\.items)
                let plannedSeconds = stageRows.compactMap(\.plannedSeconds)
                    .reduce(0, +)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: phase.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(bronze)
                            .frame(width: 36, height: 36)
                            .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                        Text(phase.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ink)
                        Spacer(minLength: 4)
                        if plannedSeconds > 0 {
                            Text(ATHLTHWorkoutDurationEstimator.conciseDuration(
                                plannedSeconds
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }

                    if items.isEmpty {
                        Text(ATHLTHLocalization.choose(
                            english: "Nothing added yet", norwegian: "Ingen deler lagt til"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    } else {
                        ForEach(Array(items.prefix(3))) { item in
                            HStack(spacing: 9) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(bronze)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(ink)
                                    if !item.detail.isEmpty {
                                        Text(item.detail)
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }

                        if items.count > 3 {
                            Text(ATHLTHLocalization.choose(
                                english: "\(items.count - 3) more variations · see Advanced",
                                norwegian: "\(items.count - 3) flere varianter · se Avansert"
                            ))
                            .font(.caption)
                            .foregroundStyle(bronze)
                        }
                    }

                    simplePhaseAddMenu(phase)
                }
                .padding(14)
                .athlthPlanCard(radius: 19)
            }

            if !blocks.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Need different pace, rest, targets or individual steps? Switch to Advanced. Your workout stays the same.",
                    norwegian: "Vil du endre tempo, pauser, mål eller enkeltdrag? Bytt til Avansert. Økten beholdes som den er."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .padding(.horizontal, 5)
            }
        }
        .accessibilityIdentifier("athlth-simple-workout-builder-outline")
    }

    private func simplePhaseAddMenu(_ phase: WorkoutPhaseKind) -> some View {
        Menu {
            if activity == .strength {
                Button {
                    onAddExercise(phase)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Exercise", norwegian: "Øvelse"
                    ), systemImage: "dumbbell")
                }
                Button {
                    onAddFreeStrength(phase)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Free strength", norwegian: "Fri styrke"
                    ), systemImage: "figure.strengthtraining.traditional")
                }
            } else {
                Button {
                    onAddRun(phase)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Activity", norwegian: "Aktivitet"
                    ), systemImage: "figure.run")
                }
                if activity == .running || activity == .walking {
                    Button {
                        onAddIntervals(phase)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Intervals", norwegian: "Intervaller"
                        ), systemImage: "timer")
                    }
                }
            }
            Button {
                onAddRest(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Recovery", norwegian: "Pause"
                ), systemImage: "pause")
            }
        } label: {
            Label(ATHLTHLocalization.choose(
                english: "Add to section", norwegian: "Legg til i øktdelen"
            ), systemImage: "plus")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(bronze)
            .frame(maxWidth: .infinity, minHeight: 43)
            .background(
                ATHLTHPlanDesign.selectedSurface,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
    }

    private var addSectionMenu: some View {
        Menu {
            ForEach(WorkoutPhaseKind.allCases.filter { $0 != .recovery }) { phase in
                Button {
                    visiblePhases.insert(phase)
                    selectedPhase = phase
                    collapsedPhases.remove(phase)
                } label: {
                    Label(phase.title, systemImage: phase.symbol)
                }
            }
            // Routes belong in the contents menu of each category, not
            // alongside categories in the outer Add category menu.
        } label: {
            Label(ATHLTHLocalization.choose(
                english: "Add category", norwegian: "Legg til kategori"
            ), systemImage: "plus.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(bronze.gradient, in: Capsule())
        }
    }

    private func phaseCard(_ phase: WorkoutPhaseKind) -> some View {
        let rows = entries(in: phase)
        let expanded = advanced && !collapsedPhases.contains(phase)
        let durationSeconds = ATHLTHWorkoutDurationEstimator.previewSeconds(
            for: rows,
            defaultActivity: activity == .walking ? .walking : .running
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(ink.opacity(0.42))
                    .accessibilityHidden(true)
                Image(systemName: phase.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(bronze)
                    .frame(width: 39, height: 39)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if expanded { collapsedPhases.insert(phase) }
                        else { collapsedPhases.remove(phase) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(phase.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ink)
                        Text("\(rows.count) " +
                            ATHLTHLocalization.choose(
                                english: "steps", norwegian: "deløkter"
                            ) + (durationSeconds.map {
                                " · ~" + ATHLTHWorkoutDurationEstimator.conciseDuration($0)
                            } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(ink)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                Menu {
                    Button(role: .destructive) {
                        if rows.isEmpty {
                            onRemovePhase(phase)
                        } else {
                            phasePendingDeletion = phase
                        }
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Delete section", norwegian: "Slett kategori"
                        ), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(ink)
                        .frame(width: 35, height: 44)
                }
            }
            .padding(.horizontal, 10)

            if expanded {
                if rows.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "No exercises added", norwegian: "Ingen øvelser lagt til"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 15)
                } else {
                    VStack(spacing: 3) {
                        ForEach(Array(rows.enumerated()), id: \.element.editorDragID) { position, block in
                            if block.groupKind?.isStrengthGroup == true,
                               let groupID = block.groupID {
                                if !rows.prefix(position).contains(where: {
                                    $0.groupID == groupID
                                }) {
                                    strengthGroupCard(groupID, rows: rows, phase: phase)
                                }
                            } else if let groupID = ATHLTHIntervalRecipeEditing.explicitGroupID(
                                for: block, in: rows
                            ) {
                                if !rows.prefix(position).contains(where: {
                                    $0.groupID == groupID
                                }) {
                                    intervalGroupCard(groupID, rows: rows, phase: phase)
                                }
                            } else if block.kind == .exercise,
                                      block.groupID == nil,
                                      (block.setCount ?? 1) > 1,
                                      let liveIndex = blocks.firstIndex(where: {
                                          $0.editorDragID == block.editorDragID
                                      }) {
                                ATHLTHStrengthGroupRow(
                                    block: $blocks[liveIndex],
                                    canMoveUp: position > 0,
                                    canMoveDown: position + 1 < rows.count,
                                    onEdit: { onEdit(block.editorDragID) },
                                    onDelete: { onRemove(block.editorDragID) },
                                    onMoveBy: { offset in
                                        let destination = position + offset
                                        guard rows.indices.contains(destination) else { return }
                                        onMove(block.editorDragID, phase,
                                               rows[destination].editorDragID)
                                    }
                                )
                            } else {
                                stepRow(block, position: position + 1, phase: phase)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                addContentMenu(phase)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, expanded ? 3 : 9)
        .background(paper, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(
                    selectedPhase == phase ? bronze.opacity(0.43)
                        : ATHLTHPlanDesign.outline, lineWidth: 1
                )
        }
        .shadow(color: bronze.opacity(0.055), radius: 10, y: 5)
        .zIndex(draggingID.map { id in
            entries(in: phase).contains { $0.editorDragID == id }
        } == true ? 5 : 0)
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("athlthWorkoutStudio"))
        } action: { _, frame in
            if dragGeometry.phaseFrames[phase] != frame { dragGeometry.phaseFrames[phase] = frame }
        }
    }

    /// Superset and circuit are separate persisted kinds, sharing one
    /// premium group editor and the same ordered workout execution engine.
    private func strengthGroupCard(
        _ id: UUID, rows: [WorkoutTemplateBlock], phase: WorkoutPhaseKind
    ) -> some View {
        let kind = rows.first(where: { $0.groupID == id })?.groupKind ?? .superset
        let members = rows.filter {
            $0.groupID == id && $0.groupKind == kind
        }
        let exercises = members.filter { $0.kind == .exercise }
        let rounds = members.first?.groupRounds ?? 3
        let clock = members.first?.groupClockSeconds
        let transition = Int(members.first?.restBetweenSetsSeconds ?? 0)
        let collapsed = collapsedSupersetGroups.contains(id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(bronze)
                    .frame(width: 38, height: 38)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if collapsed { collapsedSupersetGroups.remove(id) }
                        else { collapsedSupersetGroups.insert(id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        Text(groupSummary(kind: kind, exerciseCount: exercises.count,
                                          rounds: rounds, clockSeconds: clock))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                Menu {
                    if kind != .amrap && kind != .dropSet {
                        ForEach(1...20, id: \.self) { count in
                            Button("\(count) " + ATHLTHLocalization.choose(
                                english: kind == .emom ? "cycles" : "rounds",
                                norwegian: kind == .emom ? "sykluser" : "runder"
                            )) {
                                onSetSupersetRounds(id, count)
                            }
                        }
                        Divider()
                    }
                    if kind == .amrap {
                        ForEach([5, 8, 10, 12, 15, 20, 25, 30], id: \.self) { minutes in
                            Button("\(minutes) min") {
                                onSetGroupClock(id, Double(minutes * 60))
                            }
                        }
                        Divider()
                    }
                    if kind == .emom {
                        Menu(ATHLTHLocalization.choose(
                            english: "Time per station", norwegian: "Tid per stasjon"
                        )) {
                            ForEach([60, 90, 120, 180], id: \.self) { seconds in
                                Button("\(seconds) s") {
                                    onSetGroupClock(id, Double(seconds))
                                }
                            }
                        }
                        Divider()
                    }
                    if kind.canInsertRoundPause {
                        Menu(ATHLTHLocalization.choose(
                            english: "Station transition", norwegian: "Pause ved øvelsesbytte"
                        )) {
                            ForEach([0, 10, 15, 30, 45, 60], id: \.self) { seconds in
                                Button("\(seconds) s") {
                                    onSetStationTransition(id, seconds)
                                }
                            }
                        }
                        Divider()
                    }
                    Button {
                        onUngroupSuperset(id)
                        collapsedSupersetGroups.remove(id)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Ungroup", norwegian: "Løs opp gruppe"
                        ), systemImage: "square.stack.3d.up.slash")
                    }
                    Button(role: .destructive) {
                        onDeleteSuperset(id)
                        collapsedSupersetGroups.remove(id)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Delete \(kind.title)", norwegian: "Slett \(kind.title.lowercased())"
                        ), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 36, height: 44)
                        .foregroundStyle(ink)
                }
            }

            if !collapsed {
                if kind.canInsertRoundPause {
                    Label(ATHLTHLocalization.choose(
                        english: "Between stations: \(transition) s",
                        norwegian: "Mellom stasjoner: \(transition) sek"
                    ), systemImage: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if kind == .dropSet {
                    Label(ATHLTHLocalization.choose(
                        english: "Set a positive weight for every stage, with each weight lower than the previous one. Tap a stage to edit repetitions and kg.",
                        norwegian: "Angi vekt for hvert trinn. Vekten må være lavere enn i forrige trinn. Trykk på et trinn for å justere repetisjoner og kg."
                    ), systemImage: "arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(bronze)
                } else if kind == .emom {
                    Label(ATHLTHLocalization.choose(
                        english: "Each station starts on a new minute. Remaining seconds become rest.",
                        norwegian: "Hver stasjon starter på et nytt minutt. Resterende sekunder blir pause."
                    ), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(bronze)
                } else if kind == .amrap {
                    Label(ATHLTHLocalization.choose(
                        english: "Select the total time in the options menu, then finish as many rounds as possible.",
                        norwegian: "Velg totaltiden i menyen, og gjennomfør så mange runder du rekker."
                    ), systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(bronze)
                }
                if exercises.count < kind.minimumStrengthExercises {
                    Label(ATHLTHLocalization.choose(
                        english: kind == .circuit
                            ? "Add at least three exercises to complete the circuit."
                            : "Add exercises to complete this group.",
                        norwegian: kind == .circuit
                            ? "Legg til minst tre øvelser for å fullføre sirkeltreningen."
                            : "Legg til flere øvelser for å fullføre gruppen."
                    ), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(spacing: 3) {
                    ForEach(Array(members.enumerated()), id: \.element.editorDragID) { index, member in
                        let position = rows.firstIndex(where: {
                            $0.editorDragID == member.editorDragID
                        }).map { $0 + 1 } ?? (index + 1)
                        stepRow(member, position: position, phase: phase)
                    }
                }

                if kind.allowsAdditionalStations || kind == .dropSet {
                    Button {
                        if kind == .dropSet {
                            onAddDropStage(id)
                        } else {
                            onAddExerciseToSuperset(phase, id)
                        }
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: kind == .dropSet ? "Add weight drop" : "Add exercise",
                            norwegian: kind == .dropSet ? "Legg til vekttrinn" : "Legg til øvelse"
                        ), systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(bronze)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                if kind.canInsertRoundPause &&
                   !members.contains(where: { $0.isRestOrActiveRecovery }) {
                    Button {
                        onAddRestToSuperset(phase, id)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Add rest between rounds",
                            norwegian: "Legg til pause mellom runder"
                        ), systemImage: "pause.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(bronze)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            } else if exercises.count < kind.minimumStrengthExercises &&
                      kind.allowsAdditionalStations {
                Button {
                    collapsedSupersetGroups.remove(id)
                    onAddExerciseToSuperset(phase, id)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Add next exercise", norwegian: "Legg til neste øvelse"
                    ), systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(bronze)
            }
        }
        .padding(11)
        .background(ATHLTHPlanDesign.canvas,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(bronze.opacity(0.23), lineWidth: 0.8)
        }
    }

    private func groupSummary(
        kind: WorkoutBlockGroupKind, exerciseCount: Int,
        rounds: Int, clockSeconds: TimeInterval?
    ) -> String {
        let count = "\(exerciseCount) " + ATHLTHLocalization.choose(
            english: kind == .dropSet ? "weight stages" : "exercises",
            norwegian: kind == .dropSet ? "vekttrinn" : "øvelser"
        )
        switch kind {
        case .emom:
            return count + " · \(rounds) " + ATHLTHLocalization.choose(
                english: "cycles", norwegian: "sykluser"
            ) + " · \(Int(clockSeconds ?? 60)) s " + ATHLTHLocalization.choose(
                english: "per station", norwegian: "per stasjon"
            )
        case .amrap:
            return count + " · \(Int((clockSeconds ?? 720) / 60)) min"
        case .dropSet:
            return count + " · " + ATHLTHLocalization.choose(
                english: "no rest", norwegian: "uten pause"
            )
        case .circuit, .superset, .intervals:
            return count + " · \(rounds) " + ATHLTHLocalization.choose(
                english: "rounds", norwegian: "runder"
            )
        }
    }

    /// Collapsed by default so 30/30 remains one concise premium card,
    /// while the execution recipe still contains all 40 editable rows.
    private func intervalGroupCard(
        _ id: UUID, rows: [WorkoutTemplateBlock], phase: WorkoutPhaseKind
    ) -> some View {
        let members = Array(rows.enumerated()).filter { $0.element.groupID == id }
        let summary = ATHLTHIntervalRecipeEditing.summary(for: id, in: rows)
        let isExpanded = expandedIntervalGroups.contains(id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "repeat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(bronze)
                    .frame(width: 37, height: 37)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded { expandedIntervalGroups.remove(id) }
                        else { expandedIntervalGroups.insert(id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary?.displayName ?? ATHLTHLocalization.choose(
                            english: "Interval sequence", norwegian: "Intervallrekke"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        if let summary {
                            Text("\(summary.rounds) " + ATHLTHLocalization.choose(
                                english: "efforts", norwegian: "drag"
                            ) + " · \(summary.recoveryCount) " +
                                ATHLTHLocalization.choose(
                                    english: "recoveries", norwegian: "pauser"
                                ) + (summary.exactSeconds.map {
                                    " · " + ATHLTHWorkoutDurationEstimator.conciseDuration($0)
                                } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                Menu {
                    Button {
                        intervalToAdjust = IntervalSelection(id: id)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Adjust whole interval",
                            norwegian: "Endre / juster intervall"
                        ), systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button {
                        onCopyIntervalTargets(id)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Copy first effort targets to all efforts",
                            norwegian: "Kopier mål fra første drag til alle"
                        ), systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        onUngroupIntervals(id)
                        expandedIntervalGroups.remove(id)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Ungroup all steps", norwegian: "Løs opp gruppen"
                        ), systemImage: "square.stack.3d.up.slash")
                    }
                    Divider()
                    Button(role: .destructive) {
                        intervalPendingDeletion = id
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Delete entire interval",
                            norwegian: "Slett hele intervallen"
                        ), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 37, height: 44)
                        .foregroundStyle(ink)
                }
            }

            // Repetition count and final recovery belong to the complete
            // interval editor in the ellipsis menu, not this compact card.
            if isExpanded {
                VStack(spacing: 3) {
                    ForEach(members, id: \.element.editorDragID) { member in
                        stepRow(
                            member.element, position: member.offset + 1,
                            phase: phase
                        )
                    }
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedIntervalGroups.insert(id)
                    }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Edit individual efforts and recoveries",
                        norwegian: "Rediger enkeltdrag og pauser"
                    ), systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(ATHLTHPlanDesign.canvas,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(
                bronze.opacity(0.23), lineWidth: 0.8
            )
        }
    }

    private func stepRow(
        _ block: WorkoutTemplateBlock,
        position: Int,
        phase: WorkoutPhaseKind
    ) -> some View {
        let rows = entries(in: phase)
        let supersetMembers = block.groupKind?.isStrengthGroup == true
            ? rows.filter {
                $0.groupID == block.groupID && $0.groupKind == block.groupKind
            }
            : []
        let supersetIndex = supersetMembers.firstIndex(where: {
            $0.editorDragID == block.editorDragID
        })
        return ATHLTHPlannedWorkoutStepRow(
            block: block,
            position: position,
            canMoveUp: supersetIndex.map { $0 > 0 } ?? (position > 1),
            canMoveDown: supersetIndex.map { $0 + 1 < supersetMembers.count }
                ?? (position < rows.count),
            onEdit: { onEdit(block.editorDragID) },
            onDelete: { onRemove(block.editorDragID) },
            onMoveBy: { delta in
                if let supersetIndex {
                    let target = supersetIndex + delta
                    guard supersetMembers.indices.contains(target) else { return }
                    onMoveSupersetMember(
                        block.editorDragID, supersetMembers[target].editorDragID
                    )
                } else {
                    let destination = position - 1 + delta
                    guard rows.indices.contains(destination) else { return }
                    onMove(block.editorDragID, phase, rows[destination].editorDragID)
                }
            },
            onReorderMove: { point in
                if supersetIndex != nil {
                    liveReorderSupersetMember(block.editorDragID, finger: point)
                } else {
                    liveReorder(block.editorDragID, finger: point)
                }
            },
            onReorderEnd: endLiveReorder
        )
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("athlthWorkoutStudio"))
        } action: { _, frame in
            if dragGeometry.rowFrames[block.editorDragID] != frame {
                dragGeometry.rowFrames[block.editorDragID] = frame
            }
        }
        .opacity(draggingID == block.editorDragID ? 0.13 : 1)
    }

    /// The ordinary drag policy moves a whole group. Within supersets or
    /// circuits, move only the selected station among its siblings.
    private func liveReorderSupersetMember(_ id: UUID, finger: CGPoint) {
        guard let block = blocks.first(where: { $0.editorDragID == id }),
              let groupID = block.groupID,
              block.groupKind?.isStrengthGroup == true else { return }
        if draggingID == nil {
            guard let startFrame = dragGeometry.rowFrames[id] else { return }
            dragFingerOffsetY = finger.y - startFrame.midY
            draggingID = id
        }
        guard draggingID == id else { return }
        dragPoint = finger
        let centerY = finger.y - dragFingerOffsetY
        let members = blocks.filter {
            $0.groupID == groupID && $0.groupKind == block.groupKind
        }
        guard let index = members.firstIndex(where: {
            $0.editorDragID == id
        }) else { return }
        if index + 1 < members.count {
            let below = members.dropFirst(index + 1)
            if let crossed = below.last(where: { neighbor in
                guard let frame = dragGeometry.rowFrames[neighbor.editorDragID]
                else { return false }
                return centerY >= frame.midY
            }) {
                onMoveSupersetMember(id, crossed.editorDragID)
                return
            }
        }
        if index > 0 {
            let above = members.prefix(index)
            if let crossed = above.first(where: { neighbor in
                guard let frame = dragGeometry.rowFrames[neighbor.editorDragID]
                else { return false }
                return centerY <= frame.midY
            }) {
                onMoveSupersetMember(id, crossed.editorDragID)
            }
        }
    }

    private func liveReorder(_ id: UUID, finger: CGPoint) {
        guard let item = blocks.first(where: { $0.editorDragID == id }) else { return }
        if draggingID == nil {
            guard let startFrame = dragGeometry.rowFrames[id] else { return }
            dragFingerOffsetY = finger.y - startFrame.midY
            draggingID = id
        }
        guard draggingID == id else { return }
        dragPoint = finger
        let centerY = finger.y - dragFingerOffsetY
        let currentPhase = presentationPhase(for: item)

        // Moving across sections uses the same authoritative move callback
        // as the workout editor. Empty phases are also valid destinations.
        if let destination = phases.first(where: { phase in
            guard let frame = dragGeometry.phaseFrames[phase] else { return false }
            return centerY >= frame.minY + 10 && centerY <= frame.maxY - 10
        }), destination != currentPhase {
            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                visiblePhases.insert(destination)
                collapsedPhases.remove(destination)
                selectedPhase = destination
                onMove(id, destination, nil)
            }
            return
        }

        let rows = entries(in: currentPhase)
        guard let currentIndex = rows.firstIndex(where: {
            $0.editorDragID == id
        }) else { return }

        // Each time the floating row's center passes a neighbor's midpoint,
        // reorder the underlying timeline immediately. All other rows
        // animate into their new positions while the copy follows the finger.
        if currentIndex + 1 < rows.count {
            let below = rows.dropFirst(currentIndex + 1)
            if let crossed = below.last(where: { other in
                guard let frame = dragGeometry.rowFrames[other.editorDragID] else {
                    return false
                }
                return centerY >= frame.midY
            }) {
                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                    onMove(id, currentPhase, crossed.editorDragID)
                }
                return
            }
        }

        if currentIndex > 0 {
            let above = rows.prefix(currentIndex)
            if let crossed = above.first(where: { other in
                guard let frame = dragGeometry.rowFrames[other.editorDragID] else {
                    return false
                }
                return centerY <= frame.midY
            }) {
                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                    onMove(id, currentPhase, crossed.editorDragID)
                }
            }
        }
    }

    private func endLiveReorder() {
        withAnimation(.easeOut(duration: 0.16)) {
            draggingID = nil
        }
    }

    private func strengthHelp(_ title: String, _ norwegianTitle: String, _ detail: String, _ norwegianDetail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ATHLTHLocalization.choose(english: title, norwegian: norwegianTitle)).font(.subheadline.weight(.semibold))
            Text(ATHLTHLocalization.choose(english: detail, norwegian: norwegianDetail)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addContentMenu(_ phase: WorkoutPhaseKind) -> some View {
        Menu {
            // Strength uses the existing library picker below. The former
            // "Strength exercise" action opened that same picker twice.
            if activity != .strength {
                Button {
                    onAddRun(phase)
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Running exercise", norwegian: "Løpeøvelse"
                        ),
                        systemImage: "figure.run"
                    )
                }
            }
            Button {
                onAddExercise(phase)
            } label: {
                Label(activity == .running
                    ? ATHLTHLocalization.choose(
                        english: "Running exercises from library",
                        norwegian: "Løpeøvelser fra bibliotek"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Exercise from library",
                        norwegian: "Øvelse fra bibliotek"
                    ),
                    systemImage: activity == .running ? "figure.run" : "dumbbell")
            }
            if activity == .strength {
                Button {
                    onAddFreeStrength(phase)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Free strength training", norwegian: "Fri styrketrening"
                    ), systemImage: "stopwatch")
                }
                Button {
                    onAddSuperset(phase)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Superset", norwegian: "Supersett"
                    ), systemImage: "square.stack.3d.up")
                }
                Button {
                    onAddCircuit(phase)
                } label: {
                    Label(WorkoutBlockGroupKind.circuit.title,
                          systemImage: WorkoutBlockGroupKind.circuit.symbol)
                }
                ForEach([WorkoutBlockGroupKind.emom, .amrap, .dropSet],
                        id: \.self) { kind in
                    Button {
                        onAddStrengthMode(phase, kind)
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }
            if activity != .running {
                Button {
                    onAddWorkout(phase)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Complete workout", norwegian: "Hel treningsøkt"
                    ), systemImage: "rectangle.stack")
                }
            }
            Button {
                onAddIntervals(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Interval sequence", norwegian: "Intervallrekke"
                ), systemImage: "repeat")
            }
            Button {
                onAddRest(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Rest", norwegian: "Pause"
                ), systemImage: "pause")
            }
            Button {
                onAddActiveRest(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Active recovery", norwegian: "Aktiv joggepause"
                ), systemImage: "figure.walk")
            }
            Divider()
            Button {
                onSelectRoute(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Choose route", norwegian: "Velg rute"
                ), systemImage: "map")
            }
            Button {
                onBuildRoute(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Create route", norwegian: "Lag egen rute"
                ), systemImage: "pencil.and.scribble")
            }
        } label: {
            Label(ATHLTHLocalization.choose(
                english: "Add exercise, workout or route",
                norwegian: "Legg til øvelse, økt eller rute"
            ), systemImage: "plus")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(bronze)
            .frame(maxWidth: .infinity, minHeight: 45)
            .background(ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 13))
        }
    }
}
