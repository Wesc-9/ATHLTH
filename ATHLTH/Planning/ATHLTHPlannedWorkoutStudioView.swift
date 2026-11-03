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
    let onAddRest: (WorkoutPhaseKind) -> Void
    let onAddActiveRest: (WorkoutPhaseKind) -> Void
    let onAddWorkout: (WorkoutPhaseKind) -> Void
    let onSelectRoute: (WorkoutPhaseKind) -> Void
    let onBuildRoute: (WorkoutPhaseKind) -> Void
    let onEdit: (UUID) -> Void
    let onMove: (UUID, WorkoutPhaseKind, UUID?) -> Void
    let onRemove: (UUID) -> Void
    let onRemovePhase: (WorkoutPhaseKind) -> Void
    let onUpdateIntervalGroup: (UUID, Int, Bool) -> Void
    let onCopyIntervalTargets: (UUID) -> Void
    let onUngroupIntervals: (UUID) -> Void

    @State private var phasePendingDeletion: WorkoutPhaseKind?
    @State private var collapsedPhases: Set<WorkoutPhaseKind> = []
    @State private var expandedIntervalGroups: Set<UUID> = []
    @State private var draggingID: UUID?
    @State private var dragPoint: CGPoint = .zero
    @State private var dragFingerOffsetY: CGFloat = 0
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var phaseFrames: [WorkoutPhaseKind: CGRect] = [:]

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
                            onAddRun(.main)
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
                ForEach(phases) { phase in
                    phaseCard(phase)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: visiblePhases)
        .coordinateSpace(name: "athlthWorkoutStudio")
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
               let frame = rowFrames[draggingID] {
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
                            if let groupID = ATHLTHIntervalRecipeEditing.explicitGroupID(
                                for: block, in: rows
                            ) {
                                if !rows.prefix(position).contains(where: {
                                    $0.groupID == groupID
                                }) {
                                    intervalGroupCard(groupID, rows: rows, phase: phase)
                                }
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
            if phaseFrames[phase] != frame { phaseFrames[phase] = frame }
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
                        Text(ATHLTHLocalization.choose(
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
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 37, height: 44)
                        .foregroundStyle(ink)
                }
            }

            if let summary {
                HStack(spacing: 8) {
                    Text(ATHLTHLocalization.choose(
                        english: "Efforts", norwegian: "Antall drag"
                    ))
                    .font(.subheadline)
                    Spacer()
                    Stepper(value: Binding(
                        get: { summary.rounds },
                        set: { onUpdateIntervalGroup(id, $0, summary.hasFinalRecovery) }
                    ), in: 1...20) {
                        Text("\(summary.rounds)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .fixedSize()
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Number of efforts", norwegian: "Antall drag"
                    ))
                }
                .padding(.horizontal, 5)
                Toggle(
                    ATHLTHLocalization.choose(
                        english: "Recovery after final effort",
                        norwegian: "Pause etter siste drag"
                    ),
                    isOn: Binding(
                        get: { summary.hasFinalRecovery },
                        set: { onUpdateIntervalGroup(id, summary.rounds, $0) }
                    )
                )
                .font(.subheadline)
                .tint(bronze)
                .padding(.horizontal, 5)
            }

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
        return ATHLTHPlannedWorkoutStepRow(
            block: block,
            position: position,
            canMoveUp: position > 1,
            canMoveDown: position < rows.count,
            onEdit: { onEdit(block.editorDragID) },
            onDelete: { onRemove(block.editorDragID) },
            onMoveBy: { delta in
                let destination = position - 1 + delta
                guard rows.indices.contains(destination) else { return }
                onMove(block.editorDragID, phase, rows[destination].editorDragID)
            },
            onReorderMove: { point in
                liveReorder(block.editorDragID, finger: point)
            },
            onReorderEnd: endLiveReorder
        )
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("athlthWorkoutStudio"))
        } action: { _, frame in
            if rowFrames[block.editorDragID] != frame {
                rowFrames[block.editorDragID] = frame
            }
        }
        .opacity(draggingID == block.editorDragID ? 0.13 : 1)
    }

    private func liveReorder(_ id: UUID, finger: CGPoint) {
        guard let item = blocks.first(where: { $0.editorDragID == id }) else { return }
        if draggingID == nil {
            guard let startFrame = rowFrames[id] else { return }
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
            guard let frame = phaseFrames[phase] else { return false }
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
                guard let frame = rowFrames[other.editorDragID] else {
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
                guard let frame = rowFrames[other.editorDragID] else {
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

    private func addContentMenu(_ phase: WorkoutPhaseKind) -> some View {
        Menu {
            Button {
                onAddRun(phase)
            } label: {
                Label(
                    activity == .strength
                        ? ATHLTHLocalization.choose(
                            english: "Strength exercise", norwegian: "Styrkeøvelse"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Running exercise", norwegian: "Løpeøvelse"
                        ),
                    systemImage: activity == .strength ? "dumbbell" : "figure.run"
                )
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
