import SwiftUI

/// Compact Home editorial tile. Beside the calendar on iPhone; accessibility
/// type stacks the cards without clipping the reasoning or action.
struct HomeDailyRecommendationCard: View {
    let advice: HomeDailyRecommendationPolicy.Advice
    let onOpen: () -> Void

    private var heading: String {
        ATHLTHLocalization.choose(
            english: "Today's recommendation",
            norwegian: "Dagens anbefaling"
        )
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                    Text(heading)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: advice.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 28, height: 28)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.40),
                                    in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityHidden(true)
                    Text(advice.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(advice.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                if let evidence = advice.evidence {
                    Text(evidence)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    Text(advice.destination == .insights
                         ? ATHLTHLocalization.choose(
                            english: "See why", norwegian: "Se hvorfor")
                         : ATHLTHLocalization.choose(
                            english: "View training", norwegian: "Se trening"))
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .background(ATHLTHTrainDesign.paper,
                        in: RoundedRectangle(cornerRadius: 20,
                                             style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.34),
                                  lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            [heading, advice.title, advice.detail, advice.evidence,
             advice.source].compactMap { $0 }.joined(separator: ". ")
        )
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Open training or the health detail.",
            norwegian: "Åpner trening eller helseinnsikt."))
    }
}
