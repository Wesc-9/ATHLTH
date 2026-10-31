import SwiftUI
import UniformTypeIdentifiers

/// The single Plan-specific presentation for the unified workout recipe.
/// No parallel workout model: every row is a real editable WorkoutTemplateBlock.
/// Phases are optional; an empty scratch workout has no preset sections.
struct ATHLTHPlannedWorkoutStudioView: View {
    @Binding var blocks: [WorkoutTemplateBlock]
    @Binding var visiblePhases: Set<WorkoutPhaseKind>
    @Binding var selectedPhase: WorkoutPhaseKind

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

    @State private var collapsedPhases: Set<WorkoutPhaseKind> = []
    @State private var draggingID: UUID?

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
        block.resolvedPhase == .recovery && !visiblePhases.contains(.recovery)
            ? .main : block.resolvedPhase
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

            if phases.isEmpty {
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

            ForEach(phases) { phase in
                phaseCard(phase)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: visiblePhases)
    }

    private var addSectionMenu: some View {
        Menu {
            ForEach(WorkoutPhaseKind.allCases) { phase in
                Button {
                    visiblePhases.insert(phase)
                    selectedPhase = phase
                    collapsedPhases.remove(phase)
                } label: {
                    Label(phase.title, systemImage: phase.symbol)
                }
            }
            Divider()
            Button {
                selectedPhase = .main
                onSelectRoute(.main)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Route as whole workout", norwegian: "Rute som hele økten"
                ), systemImage: "map")
            }
            Button {
                selectedPhase = .main
                onBuildRoute(.main)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Create route", norwegian: "Lag egen rute"
                ), systemImage: "pencil.and.scribble")
            }
        } label: {
            Label(ATHLTHLocalization.choose(
                english: "Add section", norwegian: "Legg til del"
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
        let expanded = !collapsedPhases.contains(phase)
        let totalSeconds = rows.expandedForExecution()
            .compactMap(\.durationSeconds).reduce(0, +)
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
                            ) + (totalSeconds > 0
                                ? " · \(Int(totalSeconds / 60)) min" : ""))
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
                    Button {
                        visiblePhases.remove(phase)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Hide empty section", norwegian: "Skjul tom del"
                        ), systemImage: "eye.slash")
                    }
                    .disabled(!rows.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(ink)
                        .frame(width: 35, height: 44)
                }
            }
            .padding(.horizontal, 10)
            .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
                moveDragged(to: phase, before: nil)
            }

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
                            stepRow(block, position: position + 1, phase: phase)
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
    }

    private func stepRow(
        _ block: WorkoutTemplateBlock,
        position: Int,
        phase: WorkoutPhaseKind
    ) -> some View {
        let isPause = block.isRestOrActiveRecovery
        let time = block.durationSeconds.map { "\(Int($0 / 60)) min" }
            ?? block.distanceMeters.map { "\(Int($0)) m" } ?? "–"
        let zone = block.targetHeartRateZone.map { "Z\($0)" }
            ?? (isPause ? "Pause" : "–")
        return Button {
            onEdit(block.editorDragID)
        } label: {
            HStack(spacing: 9) {
                Text("\(position)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPause ? .secondary : bronze)
                    .frame(width: 23)
                Image(systemName: isPause ? "pause.fill" : block.kind.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(isPause ? .secondary : ink)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPause
                        ? ATHLTHLocalization.choose(
                            english: "Recovery", norwegian: "Pause"
                          )
                        : block.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Text(time)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(zone)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
                    .frame(minWidth: 30)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 49)
            .background(
                isPause ? ATHLTHPlanDesign.warmSurface.opacity(0.56)
                    : ATHLTHPlanDesign.canvas,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Edit duration, zone, pace and activity type",
            norwegian: "Endre tid, sone, tempo og aktivitetstype"
        ))
        .contextMenu {
            Button(role: .destructive) {
                onRemove(block.editorDragID)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Remove step", norwegian: "Fjern deløkt"
                ), systemImage: "trash")
            }
            ForEach(WorkoutPhaseKind.allCases) { target in
                Button {
                    onMove(block.editorDragID, target, nil)
                } label: {
                    Label(target.title, systemImage: target.symbol)
                }
            }
        }
        .onDrag {
            draggingID = block.editorDragID
            return NSItemProvider(object: block.editorDragID.uuidString as NSString)
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
            moveDragged(to: phase, before: block.editorDragID)
        }
    }

    private func moveDragged(
        to phase: WorkoutPhaseKind, before targetID: UUID?
    ) -> Bool {
        guard let draggingID, draggingID != targetID else { return false }
        visiblePhases.insert(phase)
        selectedPhase = phase
        onMove(draggingID, phase, targetID)
        self.draggingID = nil
        return true
    }

    private func addContentMenu(_ phase: WorkoutPhaseKind) -> some View {
        Menu {
            Button {
                onAddRun(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Run / activity", norwegian: "Løp / aktivitet"
                ), systemImage: "figure.run")
            }
            Button {
                onAddExercise(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Exercise from library", norwegian: "Øvelse fra bibliotek"
                ), systemImage: "dumbbell")
            }
            Button {
                onAddWorkout(phase)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Complete workout", norwegian: "Hel treningsøkt"
                ), systemImage: "rectangle.stack")
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
