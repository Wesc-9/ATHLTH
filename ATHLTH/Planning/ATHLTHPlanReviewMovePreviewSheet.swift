import SwiftUI

/// A preview, not an implicit reschedule.
struct ATHLTHPlanReviewMovePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFailed = false

    let proposal: ATHLTHPlanReviewMoveProposal.Proposal
    let onApprove: () -> Bool
    let onOpenEditor: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ATHLTHPlanSurface(highlighted: true) {
                        Text("ATHLTH / PLAN STUDIO")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.8)
                            .foregroundStyle(ATHLTHPlanDesign.accent)

                        Text(ATHLTHLocalization.choose(
                            english: "Preview workout move",
                            norwegian: "Forhåndsvis flytting av økt"
                        ))
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                        Text(proposal.workoutTitle)
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                        HStack(spacing: 12) {
                            dateBlock(
                                label: ATHLTHLocalization.choose(
                                    english: "From", norwegian: "Fra"
                                ),
                                date: proposal.sourceDate
                            )
                            Image(systemName: "arrow.right")
                                .foregroundStyle(ATHLTHPlanDesign.accent)
                                .accessibilityHidden(true)
                            dateBlock(
                                label: ATHLTHLocalization.choose(
                                    english: "To", norwegian: "Til"
                                ),
                                date: proposal.targetDate
                            )
                        }

                        Label(
                            proposal.reason,
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(ATHLTHLocalization.choose(
                            english: "The destination has no other planned workouts. Moving this session keeps its exercises and training history unchanged. The scheduled time of day is preserved; if none was set, 18:00 is used.",
                            norwegian: "Måldagen har ingen andre planlagte økter. Flyttingen beholder øvelser og treningshistorikk. Klokkeslettet beholdes, eller settes til 18:00 hvis det mangler."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        if onApprove() {
                            dismiss()
                        } else {
                            showFailed = true
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Approve workout move",
                                norwegian: "Godkjenn flytting"
                            ),
                            systemImage: "checkmark"
                        )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)

                    Button {
                        dismiss()
                        onOpenEditor()
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "Open the day instead",
                            norwegian: "Åpne dagen i stedet"
                        ))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button(ATHLTHLocalization.choose(
                        english: "Keep the plan unchanged",
                        norwegian: "Behold planen uendret"
                    )) {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Workout move", norwegian: "Flytt økt"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) {
                        dismiss()
                    }
                }
            }
            .alert(
                ATHLTHLocalization.choose(
                    english: "The workout could not be moved",
                    norwegian: "Økten kunne ikke flyttes"
                ),
                isPresented: $showFailed
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(ATHLTHLocalization.choose(
                    english: "The plan may have changed, the target day may be occupied, or the session is already completed. Open the day to review it.",
                    norwegian: "Planen kan være endret, måldagen kan være opptatt, eller økten kan allerede være fullført. Åpne dagen og kontroller."
                ))
            }
        }
    }

    private func dateBlock(label: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            ATHLTHPlanDesign.selectedSurface,
            in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius)
        )
    }
}
