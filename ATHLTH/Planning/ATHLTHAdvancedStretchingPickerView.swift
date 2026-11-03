import SwiftUI

/// Advanced plan stretching uses the SAME wellness guide catalog / block
/// model as Workout Studio. No unfiltered strength exercises appear here.
struct ATHLTHAdvancedStretchingPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let phase: WorkoutPhaseKind
    let onAdd: ([WorkoutTemplateBlock]) -> Void

    private var guides: [ATHLTHWellnessGuide] {
        ATHLTHWellnessBlockFactory.stretching
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.flexibility")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 46, height: 46)
                            .background(ATHLTHPlanDesign.selectedSurface,
                                        in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Stretching exercises", "Uttøyningsøvelser"))
                                .font(.system(size: 24, weight: .semibold, design: .serif))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(tr("Choose a stretch to add to this day.",
                                    "Velg en uttøyningsøvelse for denne dagen."))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .padding(.bottom, 5)

                    ForEach(guides) { guide in
                        Button {
                            let block = ATHLTHWellnessBlockFactory.block(
                                for: guide, phase: phase
                            )
                            onAdd([block])
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: guide.icon)
                                    .font(.system(size: 17))
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    .frame(width: 45, height: 45)
                                    .background(ATHLTHPlanDesign.selectedSurface,
                                                in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(guide.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHPlanDesign.ink)
                                    Text(guide.instructions)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                        .lineLimit(2)
                                    Text(guide.durationText)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                }
                                Spacer(minLength: 6)
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            }
                            .padding(13)
                            .background(.white.opacity(0.94),
                                        in: RoundedRectangle(cornerRadius: 18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(ATHLTHPlanDesign.warmDivider.opacity(0.5), lineWidth: 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(guide.title)
                    }
                }
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Stretching", "Uttøyning"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
        }
    }
}
