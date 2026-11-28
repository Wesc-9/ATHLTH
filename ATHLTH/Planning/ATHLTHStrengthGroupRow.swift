import SwiftUI

/// One exercise on the main timeline, with optional directly editable sets.
struct ATHLTHStrengthGroupRow: View {
    @Binding var block: WorkoutTemplateBlock
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveBy: (Int) -> Void
    let onMoveToPhase: (WorkoutPhaseKind) -> Void
    let onReorderMove: (CGPoint) -> Void
    let onReorderEnd: () -> Void

    private var reorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named("athlthWorkoutStudio")
            ))
            .onChanged { phase in
                if case .second(true, let drag?) = phase {
                    onReorderMove(drag.location)
                }
            }
            .onEnded { _ in onReorderEnd() }
    }

    @State private var expanded = false
    @State private var editingSet: SetSelection?

    private struct SetSelection: Identifiable {
        let id: Int
    }
    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var setCount: Int { min(max(block.setCount ?? 1, 1), 20) }

    private func target(at index: Int) -> ATHLTHStrengthSetTarget {
        guard let targets = block.individualSetTargets,
              targets.indices.contains(index) else {
            return ATHLTHStrengthSetTarget(
                repetitions: block.repetitions,
                weightKilograms: block.targetWeightKilograms
            )
        }
        return targets[index]
    }

    private func weight(at index: Int) -> Binding<Double> {
        Binding(
            get: { target(at: index).weightKilograms ?? block.targetWeightKilograms ?? 0 },
            set: { value in
                var targets = ATHLTHWorkoutSetExpansion.targets(for: block)
                guard targets.indices.contains(index) else { return }
                targets[index].weightKilograms = value
                block.individualSetTargets = targets
            }
        )
    }

    private func reps(at index: Int) -> Binding<Int> {
        Binding(
            get: { target(at: index).repetitions ?? block.repetitions ?? 10 },
            set: { value in
                var targets = ATHLTHWorkoutSetExpansion.targets(for: block)
                guard targets.indices.contains(index) else { return }
                targets[index].repetitions = value
                block.individualSetTargets = targets
            }
        )
    }

    private var recoverySeconds: TimeInterval {
        max(0, block.restBetweenSetsSeconds ?? 0)
    }

    private var isTimed: Bool { (block.durationSeconds ?? 0) > 0 }

    private func setSummary(at index: Int) -> String {
        let value = target(at: index)
        var parts: [String] = []
        if let seconds = block.durationSeconds, seconds > 0 {
            parts.append(ATHLTHWorkoutDurationEstimator.conciseDuration(seconds))
        } else if let repetitions = value.repetitions ?? block.repetitions {
            parts.append("\(repetitions) reps")
        }
        if let weight = value.weightKilograms ?? block.targetWeightKilograms {
            parts.append(weight.formatted(.number.precision(.fractionLength(0...1))) + " kg")
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    private func setRow(_ index: Int) -> some View {
        ATHLTHPlannedWorkoutStepRow(
            block: block,
            position: recoverySeconds > 0 ? index * 2 + 1 : index + 1,
            canMoveUp: false, canMoveDown: false,
            onEdit: { editingSet = SetSelection(id: index) },
            onDelete: {}, onMoveBy: { _ in }, onMoveToPhase: { _ in },
            onReorderMove: { _ in }, onReorderEnd: {},
            allowsStructuralEditing: false,
            titleOverride: ATHLTHWorkoutNameSuggestion.displayStepTitle(block) + " · \(index + 1)/\(setCount)",
            targetSummaryOverride: setSummary(at: index)
        )
    }

    private func restRow(after index: Int) -> some View {
        // A view-only projection. The actual recovery remains on the parent
        // exercise and is expanded by the existing workout execution engine.
        let rest = WorkoutTemplateBlock(
            sequence: index * 2 + 2, kind: .rest, title: tr("Rest", "Pause"),
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: recoverySeconds, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: .recovery
        )
        return ATHLTHPlannedWorkoutStepRow(
            block: rest, position: index * 2 + 2,
            canMoveUp: false, canMoveDown: false,
            onEdit: onEdit, onDelete: {}, onMoveBy: { _ in }, onMoveToPhase: { _ in },
            onReorderMove: { _ in }, onReorderEnd: {},
            allowsStructuralEditing: false
        )
    }

    private func setEditor(_ index: Int) -> some View {
        NavigationStack {
            Form {
                if isTimed, let seconds = block.durationSeconds {
                    LabeledContent(tr("Duration", "Varighet"),
                                   value: ATHLTHWorkoutDurationEstimator.conciseDuration(seconds))
                    Text(tr("Change the shared set duration in the exercise settings.",
                            "Endre felles varighet i øvelsesinnstillingene."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Stepper(value: reps(at: index), in: 1...300) {
                        Text("\(reps(at: index).wrappedValue) reps")
                    }
                }
                Stepper(value: weight(at: index), in: 0...500, step: 2.5) {
                    Text(weight(at: index).wrappedValue.formatted(.number.precision(.fractionLength(0...1))) + " kg")
                }
            }
            .navigationTitle(tr("Set", "Sett") + " \(index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Ferdig")) { editingSet = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ink.opacity(0.31))
                    .frame(width: 21, height: 44)
                    .contentShape(Rectangle())
                    .gesture(reorderGesture)
                    .accessibilityLabel(tr(
                        "Drag to move exercise",
                        "Dra for å flytte øvelsen"
                    ))
                    .accessibilityAction(
                        named: Text(tr("Move up", "Flytt opp"))
                    ) {
                        if canMoveUp { onMoveBy(-1) }
                    }
                    .accessibilityAction(
                        named: Text(tr("Move down", "Flytt ned"))
                    ) {
                        if canMoveDown { onMoveBy(1) }
                    }

                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(bronze)
                    .frame(width: 35, height: 35)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())

                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHWorkoutNameSuggestion.displayStepTitle(block))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Text("\(setCount) " + tr("sets", "sett") +
                             (block.restBetweenSetsSeconds.map {
                                " · \(Int($0)) " + tr("sec rest", "sek pause")
                             } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(tr(
                    "Edit all exercise targets", "Rediger mål for hele øvelsen"
                ))

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                        .frame(width: 38, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded
                    ? tr("Hide sets", "Skjul sett")
                    : tr("Show sets", "Vis sett"))

                Menu {
                    Button(action: onEdit) {
                        Label(tr("Edit whole exercise", "Rediger hele øvelsen"),
                              systemImage: "pencil")
                    }
                    if canMoveUp {
                        Button {
                            onMoveBy(-1)
                        } label: {
                            Label(tr("Move up", "Flytt opp"), systemImage: "arrow.up")
                        }
                    }
                    if canMoveDown {
                        Button {
                            onMoveBy(1)
                        } label: {
                            Label(tr("Move down", "Flytt ned"), systemImage: "arrow.down")
                        }
                    }
                    Menu {
                        ForEach(WorkoutPhaseKind.allCases.filter { $0 != .recovery }) { phase in
                            Button {
                                onMoveToPhase(phase)
                            } label: {
                                Label(phase.title, systemImage: phase.symbol)
                            }
                        }
                    } label: {
                        Label(tr("Move to workout section", "Flytt til øktdel"),
                              systemImage: "arrow.up.arrow.down")
                    }
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label(tr("Delete exercise", "Slett øvelse"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(width: 35, height: 44)
                }
                .accessibilityLabel(tr("Exercise options", "Øvelsesvalg"))
            }
            .frame(minHeight: 50)

            if expanded {
                LazyVStack(spacing: 3) {
                    ForEach(0..<setCount, id: \.self) { index in
                        setRow(index)
                        if index < setCount - 1 && recoverySeconds > 0 {
                            restRow(after: index)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(ATHLTHPlanDesign.canvas,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(bronze.opacity(0.23), lineWidth: 0.8)
        }
        .sheet(item: $editingSet) { selection in
            setEditor(selection.id)
        }
    }
}
