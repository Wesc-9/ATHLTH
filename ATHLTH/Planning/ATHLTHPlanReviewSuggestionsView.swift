import SwiftUI

/// A consent-first review surface. Tapping only navigates to the exact
/// day or week; applying any training-plan edit remains in the normal editor.
struct ATHLTHPlanReviewSuggestionsView: View {
    let plan: TrainingPlan
    let onSelect: (UUID, UUID?) -> Void
    @State private var showAll = false

    var body: some View {
        let suggestions = ATHLTHPlanReviewAdvisor.inspect(plan)

        ATHLTHPlanSurface {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "Make your plan work for you",
                        norwegian: "Gjør planen enklere å følge"
                    ))
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)

                    Text(ATHLTHLocalization.choose(
                        english: "Suggestions from the plan structure. Open a day to review a possible adjustment; nothing is changed automatically.",
                        norwegian: "Forslag basert på planoppsettet. Åpne en dag for å vurdere en endring. Ingenting endres automatisk."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if suggestions.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "No upcoming scheduling suggestions right now.",
                        norwegian: "Ingen forslag til kommende økter akkurat nå."
                    ),
                    systemImage: "checkmark.circle"
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(suggestions.prefix(
                        showAll ? suggestions.count : 3
                    ))) { suggestion in
                        Button {
                            onSelect(suggestion.weekID, suggestion.dayID)
                        } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: symbol(for: suggestion.kind))
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHPlanDesign.accent)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Text(suggestion.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ATHLTHPlanDesign.ink)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Text(ATHLTHLocalization.choose(
                                            english: "W\(suggestion.weekNumber)",
                                            norwegian: "U\(suggestion.weekNumber)"
                                        ))
                                        .font(.caption2.weight(.medium))
                                        .monospacedDigit()
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    }
                                    Text(suggestion.detail)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Label(
                                        suggestion.dayID == nil
                                            ? ATHLTHLocalization.choose(
                                                english: "Review week",
                                                norwegian: "Se uken"
                                            )
                                            : ATHLTHLocalization.choose(
                                                english: "Review day",
                                                norwegian: "Se dagen"
                                            ),
                                        systemImage: "arrow.up.right"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .accessibilityHidden(true)
                            }
                            .padding(12)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(
                                    cornerRadius: ATHLTHPlanDesign.fieldRadius
                                )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(ATHLTHLocalization.choose(
                            english: "Open the plan editor without changing any workouts.",
                            norwegian: "Åpner planoversikten uten å endre økter."
                        ))
                    }
                }
                if suggestions.count > 3 {
                    Button {
                        showAll.toggle()
                    } label: {
                        Label(
                            showAll
                                ? ATHLTHLocalization.choose(
                                    english: "Show fewer", norwegian: "Vis færre"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Show all \(suggestions.count) suggestions",
                                    norwegian: "Vis alle \(suggestions.count) forslag"
                                ),
                            systemImage: showAll ? "chevron.up" : "chevron.down"
                        )
                        .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func symbol(
        for kind: ATHLTHPlanReviewAdvisor.Kind
    ) -> String {
        switch kind {
        case .missingDuration: return "clock.badge.exclamationmark"
        case .longDay: return "calendar.badge.clock"
        case .consecutiveRuns: return "figure.run"
        case .consecutiveStrength: return "dumbbell"
        case .crowdedWeek: return "calendar"
        case .mixedDay: return "square.stack.3d.up"
        case .increasingFrequency: return "chart.line.uptrend.xyaxis"
        }
    }
}
