import SwiftUI

/// Strength targets are the primary planned intensity. Heart-rate targets are
/// secondary for strength, but retain their existing functionality.
struct ATHLTHPlannedIntensityEditor: View {
    @Binding var block: WorkoutTemplateBlock

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var zone: Binding<Int> {
        Binding(
            get: { block.targetHeartRateZone ?? 0 },
            set: { selected in
                block.targetHeartRateZone = (1...5).contains(selected) ? selected : nil
                block.sourceIntensityZoneLabel = nil
                block.targetHeartRatePercentMin = nil
                block.targetHeartRatePercentMax = nil
            }
        )
    }

    private var weight: Binding<Double> {
        Binding(
            get: { block.targetWeightKilograms ?? 0 },
            set: { value in
                block.targetWeightKilograms = value
                if var targets = block.individualSetTargets {
                    for index in targets.indices { targets[index].weightKilograms = value }
                    block.individualSetTargets = targets
                }
            }
        )
    }

    private var repetitions: Binding<Int> {
        Binding(
            get: { block.repetitions ?? 10 },
            set: { value in
                block.repetitions = value
                if var targets = block.individualSetTargets {
                    for index in targets.indices { targets[index].repetitions = value }
                    block.individualSetTargets = targets
                }
            }
        )
    }

    private func weight(for set: Int) -> Binding<Double> {
        Binding(
            get: {
                guard let values = block.individualSetTargets,
                      values.indices.contains(set) else {
                    return block.targetWeightKilograms ?? 0
                }
                return values[set].weightKilograms ?? block.targetWeightKilograms ?? 0
            },
            set: { value in
                guard var values = block.individualSetTargets,
                      values.indices.contains(set) else { return }
                values[set].weightKilograms = value
                block.individualSetTargets = values
            }
        )
    }

    private func reps(for set: Int) -> Binding<Int> {
        Binding(
            get: {
                guard let values = block.individualSetTargets,
                      values.indices.contains(set) else { return block.repetitions ?? 10 }
                return values[set].repetitions ?? block.repetitions ?? 10
            },
            set: { value in
                guard var values = block.individualSetTargets,
                      values.indices.contains(set) else { return }
                values[set].repetitions = value
                block.individualSetTargets = values
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("PLANNED INTENSITY", "PLANLAGT INTENSITET"))
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(ATHLTHTrainDesign.bronze)

            if block.kind == .exercise {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Weight", "Vekt"))
                            .font(.subheadline.weight(.semibold))
                        Stepper(value: weight, in: 0...500, step: 2.5) {
                            Text(String(format: "%.1f kg", block.targetWeightKilograms ?? 0))
                                .font(.caption.weight(.medium))
                        }
                        .accessibilityLabel(tr("Weight for all sets", "Vekt for alle sett"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Repetitions", "Repetisjoner"))
                            .font(.subheadline.weight(.semibold))
                        Stepper(value: repetitions, in: 1...300) {
                            Text("\(block.repetitions ?? 10) reps")
                                .font(.caption.weight(.medium))
                        }
                        .accessibilityLabel(tr("Repetitions for all sets", "Reps for alle sett"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if (block.setCount ?? 1) > 1 && block.groupID == nil {
                    Button {
                        if block.individualSetTargets == nil {
                            block.individualSetTargets = ATHLTHWorkoutSetExpansion.targets(for: block)
                        } else {
                            block.individualSetTargets = nil
                        }
                    } label: {
                        Label(
                            block.individualSetTargets == nil
                                ? tr("Customize each set", "Tilpass hvert sett")
                                : tr("Use same targets for all sets", "Bruk samme mål for alle sett"),
                            systemImage: "slider.horizontal.3"
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 40)
                    }
                    .buttonStyle(.plain)
                }

                if let targets = block.individualSetTargets, !targets.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(tr("INDIVIDUAL SETS", "INDIVIDUELLE SETT"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(targets.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(tr("Set", "Sett") + " \(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                HStack(spacing: 10) {
                                    Stepper(value: weight(for: index),
                                            in: 0...500, step: 2.5) {
                                        Text(String(format: "%.1f kg",
                                            weight(for: index).wrappedValue))
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                    Stepper(value: reps(for: index), in: 1...300) {
                                        Text("\(reps(for: index).wrappedValue) reps")
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(11)
                            .background(.white.opacity(0.76),
                                        in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                Divider().padding(.top, 5)
            }

            HStack(spacing: 10) {
                Image(systemName: "heart")
                    .foregroundStyle(block.kind == .exercise
                        ? Color.secondary : ATHLTHTrainDesign.bronze)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Heart rate zone", "Pulssone"))
                        .font(.subheadline.weight(.semibold))
                    Text(block.kind == .exercise
                        ? tr("Optional for strength", "Valgfritt for styrke")
                        : tr("Zone 1–5", "Sone 1–5"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(tr("Heart rate zone", "Pulssone"), selection: zone) {
                    Text(tr("None", "Ingen")).tag(0)
                    ForEach(1...5, id: \.self) { value in
                        Text((ATHLTHLocalization.isNorwegian ? "S" : "Z") + "\(value)")
                            .tag(value)
                    }
                }
                .pickerStyle(.menu)
                .tint(ATHLTHTrainDesign.bronze)
            }
            .frame(minHeight: 49)

            if block.kind != .exercise {
                Text(tr(
                    "Planned heart-rate target, not a live measurement.",
                    "Planlagt pulssone, ikke en målt pulsverdi."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(ATHLTHPlanDesign.selectedSurface.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}
