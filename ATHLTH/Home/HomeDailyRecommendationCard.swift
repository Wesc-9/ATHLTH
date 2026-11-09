import SwiftUI

/// Shared exact card height for the side-by-side Home recommendation/calendar.
enum HomeTodayTwinCardLayout {
    static let height: CGFloat = 174
}

/// Editorial daily context followed by a specific, executable recommendation.
/// Tapping the assessment opens its detailed explanation, while the workout
/// row preserves its separate launch action. Neither is medical advice.
struct HomeDailyRecommendationCard: View {
    let advice: HomeDailyRecommendationPolicy.Advice
    let onShowDetails: () -> Void
    let onStartRecommendedWorkout: () -> Void
    /// Dense presentation in Home's two-column row; accessibility remains naturally sized.
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Button(action: onShowDetails) {
                VStack(alignment: .leading, spacing: compact ? 8 : 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                            .accessibilityHidden(true)

                        Text(ATHLTHLocalization.choose(
                            english: "Today's recommendation",
                            norwegian: "Dagens anbefaling"
                        ))
                        .font(.system(size: compact ? 11.5 : 12, weight: .bold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                        Spacer(minLength: 0)

                        Image(systemName: "info.circle")
                            .font(.system(size: compact ? 11 : 12))
                            .foregroundStyle(ATHLTHTrainDesign.bronze.opacity(0.8))
                            .accessibilityHidden(true)
                    }

                    Text(advice.shortDescription)
                        .font(.system(size: compact ? 10.5 : 11.5))
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                        .lineSpacing(compact ? 1 : 2)
                        .lineLimit(compact ? 2 : 3)
                        .minimumScaleFactor(0.93)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Today's recommendation. \(advice.shortDescription)",
                norwegian: "Dagens anbefaling. \(advice.shortDescription)"
            ))
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "Open the detailed explanation behind this recommendation",
                norwegian: "Åpner en detaljert forklaring på anbefalingen"
            ))
            .accessibilityIdentifier("home-daily-recommendation-details")

            // Give today's explanation its own open, calm area. Push the
            // divider and recommended workout down to the bottom of the
            // existing card without changing the shared calendar-card height.
            Spacer(minLength: 0)

            Rectangle()
                .fill(ATHLTHTrainDesign.rule.opacity(0.45))
                .frame(height: 0.7)

            Text(ATHLTHLocalization.choose(
                english: "RECOMMENDED WORKOUT", norwegian: "ANBEFALT ØKT"
            ))
            .font(.system(size: compact ? 9 : 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(ATHLTHTrainDesign.bronze)

            Button(action: onStartRecommendedWorkout) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: advice.suggestedWorkout.kind == .walking
                          ? "figure.walk" :
                          advice.suggestedWorkout.kind == .running
                          ? "figure.run" :
                          advice.suggestedWorkout.kind == .strength
                          ? "dumbbell" :
                          advice.suggestedWorkout == .restDay
                          ? "moon.stars" : "play.circle.fill")
                        .font(.system(size: compact ? 14 : 15, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: compact ? 27 : 29, height: compact ? 27 : 29)
                        .background(
                            ATHLTHTrainDesign.paleGold.opacity(0.45),
                            in: RoundedRectangle(cornerRadius: 9)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(advice.suggestedTitle)
                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .lineLimit(compact ? 2 : nil)
                            .fixedSize(horizontal: false, vertical: !compact)
                        Text(advice.suggestedDetail)
                            .font(.system(size: compact ? 9.5 : 10))
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .lineLimit(compact ? 2 : nil)
                            .fixedSize(horizontal: false, vertical: !compact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 37 : 43)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(advice.suggestedTitle)
            .accessibilityHint(
                advice.suggestedWorkout == .restDay
                ? ATHLTHLocalization.choose(
                    english: "Open Train. No workout starts automatically.",
                    norwegian: "Åpner Tren. Ingen økt starter automatisk."
                )
                : ATHLTHLocalization.choose(
                    english: "Open the recommended workout for review and start.",
                    norwegian: "Åpner anbefalt økt for gjennomgang og oppstart."
                )
            )

        }
        .padding(compact ? 9 : 11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(
            minHeight: compact ? nil : 180,
            alignment: .topLeading
        )
        .frame(
            height: compact ? HomeTodayTwinCardLayout.height : nil,
            alignment: .topLeading
        )
        .background {
            // Also make the card's empty space open the explanation.
            // The visible workout Button above keeps its own tap handling.
            Button(action: onShowDetails) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(ATHLTHTrainDesign.paper)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.34),
                              lineWidth: 0.8)
        }
    }
}
