import SwiftUI

/// Editorial daily context followed by a specific, executable recommendation.
/// Only the workout row is interactive; the body assessment is never treated
/// as medical advice or a measured state when Health data is missing.
struct HomeDailyRecommendationCard: View {
    let advice: HomeDailyRecommendationPolicy.Advice
    let onStartRecommendedWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                Text(ATHLTHLocalization.choose(
                    english: "Today's recommendation",
                    norwegian: "Dagens anbefaling"
                ))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }

            Text(advice.dayDescription)
                .font(.system(size: 11.5))
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let evidence = advice.evidence {
                Text(evidence)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Rectangle()
                .fill(ATHLTHTrainDesign.rule.opacity(0.45))
                .frame(height: 0.7)

            Text(ATHLTHLocalization.choose(
                english: "RECOMMENDED WORKOUT", norwegian: "ANBEFALT ØKT"
            ))
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(ATHLTHTrainDesign.bronze)

            Button(action: onStartRecommendedWorkout) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: advice.suggestedWorkout.kind == .walking
                          ? "figure.walk" :
                          advice.suggestedWorkout.kind == .running
                          ? "figure.run" : "play.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 29, height: 29)
                        .background(
                            ATHLTHTrainDesign.paleGold.opacity(0.45),
                            in: RoundedRectangle(cornerRadius: 9)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(advice.suggestedTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(advice.suggestedDetail)
                            .font(.system(size: 10))
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
                .frame(maxWidth: .infinity, minHeight: 43)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(advice.suggestedTitle)
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "Open and start exactly this workout.",
                norwegian: "Åpner oppstart av akkurat denne økten."
            ))
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(
            ATHLTHTrainDesign.paper,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.34),
                              lineWidth: 0.8)
        }
    }
}
