import SwiftUI

/// The goal tile on Home is replaced by a compact, readable daily suggestion.
/// The existing calendar remains beside this card on regular iPhone widths.
/// Subviews deliberately keep SwiftUI's type-checking expressions small.
struct HomeDailyRecommendationCard: View {
    let advice: HomeDailyRecommendationPolicy.Advice
    let onOpen: () -> Void

    private var recommendationLabel: String {
        ATHLTHLocalization.choose(
            english: "Today's suggestion",
            norwegian: "Dagens anbefaling"
        )
    }

    private var accessibilityDescription: String {
        [recommendationLabel, advice.title, advice.detail, advice.source]
            .joined(separator: ". ")
    }

    var body: some View {
        Button(action: onOpen) {
            recommendationPanel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(
            ATHLTHLocalization.choose(
                english: "Opens the relevant training or insights tab.",
                norwegian: "Åpner Trening eller Innsikt for flere detaljer."
            )
        )
    }

    private var recommendationPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            mainAdvice
            footer
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.92),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(recommendationLabel)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .foregroundStyle(ATHLTHTheme.primaryText)

            Spacer(minLength: 1)

            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .accessibilityHidden(true)
        }
    }

    private var mainAdvice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: advice.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 32, height: 32)
                .background(ATHLTHTheme.champagneSoft, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(advice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(advice.detail)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 82, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(advice.source)
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Spacer(minLength: 2)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .accessibilityHidden(true)
        }
    }
}
