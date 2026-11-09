import SwiftUI

/// One exercise on the main timeline, with optional directly editable sets.
struct ATHLTHStrengthGroupRow: View {
    @Binding var block: WorkoutTemplateBlock
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveBy: (Int) -> Void

    @State private var expanded = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
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
                VStack(spacing: 6) {
                    ForEach(0..<setCount, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(tr("Set", "Sett") + " \(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                            HStack(spacing: 10) {
                                Stepper(value: weight(at: index),
                                        in: 0...500, step: 2.5) {
                                    Text(String(format: "%.1f kg",
                                                weight(at: index).wrappedValue))
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                Stepper(value: reps(at: index), in: 1...300) {
                                    Text("\(reps(at: index).wrappedValue) reps")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11))

                        if index < setCount - 1,
                           let recovery = block.restBetweenSetsSeconds,
                           recovery > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "pause.fill")
                                Text(tr("Rest", "Pause"))
                                Spacer()
                                Text("\(Int(recovery)) " + tr("sec", "sek"))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 30)
                        }
                    }
                }
                .padding(.leading, 13)
            }
        }
        .padding(10)
        .background(ATHLTHPlanDesign.canvas,
                    in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(bronze.opacity(0.20), lineWidth: 0.8)
        }
    }
}
