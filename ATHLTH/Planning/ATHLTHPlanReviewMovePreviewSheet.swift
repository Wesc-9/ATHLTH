import SwiftUI

/// A preview, not an implicit reschedule.
struct ATHLTHPlanReviewMovePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFailed = false
    @State private var selectedDayID: UUID?

    let proposal: ATHLTHPlanReviewMoveProposal.Proposal
    let plan: TrainingPlan
    let onApprove: (ATHLTHPlanReviewMoveProposal.Proposal) -> Bool
    let onOpenEditor: () -> Void

    var body: some View {
        let alternatives = ATHLTHPlanMoveWeekPreview.destinations(
            proposal, in: plan
        )
        let adjusted = ATHLTHPlanMoveWeekPreview.choosing(
            selectedDayID ?? proposal.targetDayID,
            from: proposal, in: plan
        )
        let impact = adjusted.flatMap {
            ATHLTHPlanMoveWeekPreview.summarize($0, in: plan)
        }

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
                                date: adjusted?.targetDate ?? proposal.targetDate
                            )
                        }

                        if alternatives.count > 1 {
                            Menu {
                                ForEach(alternatives) { destination in
                                    Button(
                                        destination.date.formatted(
                                            .dateTime.weekday(.wide).day().month()
                                        )
                                    ) {
                                        selectedDayID = destination.dayID
                                    }
                                }
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Choose another free day",
                                        norwegian: "Velg en annen ledig dag"
                                    ),
                                    systemImage: "calendar"
                                )
                                .font(.subheadline.weight(.medium))
                            }
                        }

                        if let impact {
                            weekImpact(impact)
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
                        if let adjusted, onApprove(adjusted) {
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
                    .disabled(adjusted == nil)

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

    private func weekImpact(
        _ impact: ATHLTHPlanMoveWeekPreview.Summary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ATHLTHLocalization.choose(
                english: "The whole week · before and after",
                norwegian: "Hele uken · før og etter"
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.ink)

            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Days with workouts",
                    norwegian: "Dager med økter"
                ))
                Spacer(minLength: 0)
                Text("\(impact.activeDaysBefore) → \(impact.activeDaysAfter)")
                    .monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ATHLTHPlanDesign.ink)

            ForEach(impact.days) { day in
                HStack(spacing: 10) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .frame(width: 43, alignment: .leading)
                    Text("\(day.beforeCount)")
                        .frame(width: 23)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text("\(day.afterCount)")
                        .fontWeight(day.changed ? .semibold : .regular)
                        .frame(width: 23)
                    if day.changed {
                        Text(ATHLTHLocalization.choose(
                            english: "Changed", norwegian: "Endres"
                        ))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .accessibilityElement(children: .combine)
            }
            Text(ATHLTHLocalization.choose(
                english: "Numbers are workout counts, not training load.",
                norwegian: "Tallene viser antall økter, ikke treningsbelastning."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            if impact.usesFreeDay {
                Label(
                    ATHLTHLocalization.choose(
                        english: "This move uses a previously workout-free day. Consider whether you want to keep it for rest.",
                        norwegian: "Flyttingen bruker en tidligere treningsfri dag. Vurder om du heller ønsker å beholde den som hviledag."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            ATHLTHPlanDesign.selectedSurface,
            in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius)
        )
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
