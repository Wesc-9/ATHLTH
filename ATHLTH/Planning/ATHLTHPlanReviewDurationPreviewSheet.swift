import SwiftUI

/// The proposed change is disclosed before any save is attempted.
struct ATHLTHPlanReviewDurationPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFailed = false

    let proposal: ATHLTHPlanReviewDurationProposal.Proposal
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
                            english: "Preview your adjustment",
                            norwegian: "Forhåndsvis justeringen"
                        ))
                        .font(.system(size: 27, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                        Text(proposal.workoutTitle)
                            .font(.headline)
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                        HStack(spacing: 14) {
                            valueBlock(
                                title: ATHLTHLocalization.choose(
                                    english: "Current", norwegian: "Nå"
                                ),
                                value: proposal.previousMinutes.map {
                                    "\($0) min"
                                } ?? ATHLTHLocalization.choose(
                                    english: "No target", norwegian: "Uten mål"
                                )
                            )
                            Image(systemName: "arrow.right")
                                .font(.headline)
                                .foregroundStyle(ATHLTHPlanDesign.accent)
                                .accessibilityHidden(true)
                            valueBlock(
                                title: ATHLTHLocalization.choose(
                                    english: "Suggested", norwegian: "Forslag"
                                ),
                                value: "\(proposal.suggestedMinutes) min"
                            )
                        }

                        Label(
                            ATHLTHLocalization.choose(
                                english: "Based on \(proposal.comparableSessionCount) similar \(proposal.workoutKind.title.lowercased()) sessions in your current plan. The median is rounded to five-minute steps.",
                                norwegian: "Basert på \(proposal.comparableSessionCount) lignende økter av samme type i din egen plan. Medianen er avrundet til nærmeste fem minutter."
                            ),
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(ATHLTHLocalization.choose(
                            english: "This changes only the time target of this workout. It will not edit the exercises, other days, workout history or your training load.",
                            norwegian: "Dette endrer bare tidsmålet for denne økten. Øvelser, andre dager, treningshistorikk og treningsbelastning endres ikke."
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
                                english: "Approve time target",
                                norwegian: "Godkjenn tidsmålet"
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
                            english: "Review in day editor instead",
                            norwegian: "Vurder selv i dagsvisningen"
                        ))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button(
                        ATHLTHLocalization.choose(
                            english: "Keep plan unchanged",
                            norwegian: "Behold planen uendret"
                        )
                    ) {
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
                english: "Plan adjustment", norwegian: "Planjustering"
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
                    english: "The plan has changed",
                    norwegian: "Planen er endret"
                ),
                isPresented: $showFailed
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(ATHLTHLocalization.choose(
                    english: "The proposal could not be saved. The plan may have changed, or this session is already completed. Open the day to review it.",
                    norwegian: "Forslaget kunne ikke lagres. Planen kan ha blitt oppdatert, eller økten er allerede fullført. Åpne dagen og kontroller den."
                ))
            }
        }
    }

    private func valueBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(value)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .minimumScaleFactor(0.75)
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
