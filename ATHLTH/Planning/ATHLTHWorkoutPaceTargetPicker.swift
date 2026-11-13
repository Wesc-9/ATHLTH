import SwiftUI

/// Scoped personal pace editing. The published workout timeline remains
/// unchanged; these controls edit only the athlete's target overlay.
struct ATHLTHWorkoutPaceTargetPicker: View {
    let steps: [WorkoutTemplateBlock]
    let commonSeconds: Int
    let maximumBPM: Double?
    @Binding var scope: ATHLTHWorkoutPacePlan.Scope
    @Binding var selectedIndices: Set<Int>
    @Binding var individualPaces: [Int: Int]

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var eligible: [Int] {
        ATHLTHWorkoutPacePlan.eligibleIndices(in: steps)
    }

    private var work: [Int] {
        ATHLTHWorkoutPacePlan.suggestedWorkIndices(in: steps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Apply pace to", "Bruk måltempo på"))
                .font(.subheadline.weight(.semibold))

            Picker(tr("Target scope", "Målomfang"), selection: $scope) {
                Text(tr("Work intervals", "Alle drag"))
                    .tag(ATHLTHWorkoutPacePlan.Scope.allWork)
                Text(tr("Choose steps", "Velg deler"))
                    .tag(ATHLTHWorkoutPacePlan.Scope.selectedSteps)
                Text(tr("Each step", "Per del"))
                    .tag(ATHLTHWorkoutPacePlan.Scope.individual)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("athlth-pace-scope")

            if scope == .allWork {
                Label(
                    tr(
                        "Same pace on \(work.count) work intervals. Warm-up and recovery stay as prescribed.",
                        "Lik fart på \(work.count) arbeidsdrag. Oppvarming og pauser beholdes som planlagt."
                    ),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                HStack {
                    Text(tr(
                        "\(selectedIndices.intersection(Set(eligible)).count) selected",
                        "\(selectedIndices.intersection(Set(eligible)).count) valgt"
                    ))
                    .font(.caption.weight(.semibold))
                    Spacer()
                    Button(tr("Work only", "Bare drag")) {
                        selectedIndices = Set(work)
                    }
                    Button(tr("Select all", "Velg alle")) {
                        selectedIndices = Set(eligible)
                    }
                }
                .font(.caption)
                .tint(ATHLTHPlanDesign.accentInk)

                LazyVStack(spacing: 8) {
                    ForEach(steps.indices, id: \.self) { index in
                        stepRow(index)
                    }
                }
            }

            Text(tr(
                "The intervals retain their distance, duration and source HR zones. Heart rate rises gradually during each interval.",
                "Distanse, varighet og anbefalte pulssoner beholdes. Pulsen stiger gradvis under hvert drag."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("athlth-pace-target-picker")
    }

    private func stepRow(_ index: Int) -> some View {
        let step = steps[index]
        let eligible = step.kind == .run
        let selected = selectedIndices.contains(index)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Button {
                    if selected {
                        selectedIndices.remove(index)
                    } else if eligible {
                        selectedIndices.insert(index)
                    }
                } label: {
                    Image(systemName: selected && eligible
                          ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(
                            selected && eligible
                                ? ATHLTHPlanDesign.accentInk
                                : ATHLTHPlanDesign.secondaryInk
                        )
                        .frame(width: 34, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(!eligible)
                .accessibilityLabel(tr(
                    selected ? "Deselect step" : "Select step",
                    selected ? "Fjern valg" : "Velg øktdel"
                ))
                .accessibilityIdentifier("athlth-pace-step-\(index)")

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(index + 1). " + step.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Text(step.resolvedPhase.title)
                        if let duration = step.durationSeconds, duration > 0 {
                            Text("·")
                            Text(ATHLTHWorkoutDurationEstimator.conciseDuration(duration))
                        } else if let meters = step.distanceMeters, meters > 0 {
                            Text("·")
                            Text(String(format: "%.1f km", meters / 1_000))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 0)
            }

            if let pulse = ATHLTHPlannedHeartRatePreview.rangeText(
                for: step, maximumBPM: maximumBPM
            ) {
                Text(pulse)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .padding(.leading, 42)
            }

            if !eligible {
                Text(tr(
                    "Passive recovery: no pace target",
                    "Passiv pause: ikke noe måltempo"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 42)
            } else if scope == .individual && selected {
                Stepper(
                    value: Binding(
                        get: { individualPaces[index] ?? commonSeconds },
                        set: { individualPaces[index] = $0 }
                    ),
                    in: 120...959,
                    step: 5
                ) {
                    Text(
                        tr("Target: ", "Mål: ") +
                        paceString(individualPaces[index] ?? commonSeconds)
                    )
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                }
                .tint(ATHLTHPlanDesign.accentInk)
                .padding(.leading, 42)
            }
        }
        .padding(10)
        .background(
            selected && eligible ? ATHLTHPlanDesign.selectedSurface : Color.white,
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func paceString(_ total: Int) -> String {
        String(format: "%d:%02d min/km", total / 60, total % 60)
    }
}
