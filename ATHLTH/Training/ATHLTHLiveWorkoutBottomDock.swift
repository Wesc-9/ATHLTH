import SwiftUI

/// One fixed bottom action surface shared by iPhone running, strength,
/// and the structured multi-sport workout player.
/// Strength keeps its existing media, instructions and inline set inputs;
/// the content slot provides context without duplicating action buttons.
/// No additional model, timer or HealthKit recording is created here.
struct ATHLTHLiveWorkoutBottomDock<Details: View>: View {
    let mode: ATHLTHLiveWorkoutBottomMode
    let subtitle: String?
    let primaryDisabled: Bool
    let secondaryDisabled: Bool
    let onPrimary: () -> Void
    let onSecondary: (() -> Void)?
    let details: Details

    init(
        mode: ATHLTHLiveWorkoutBottomMode,
        subtitle: String? = nil,
        primaryDisabled: Bool = false,
        secondaryDisabled: Bool = false,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder details: () -> Details
    ) {
        self.mode = mode
        self.subtitle = subtitle
        self.primaryDisabled = primaryDisabled
        self.secondaryDisabled = secondaryDisabled
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: mode.primarySymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .frame(width: 28, height: 28)
                    .background(
                        ATHLTHTheme.premiumGold.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.phaseTitle)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.85)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }

            details

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) {
                    primaryButton
                    secondaryButton
                }
                VStack(spacing: 8) {
                    primaryButton
                    secondaryButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 10)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 23,
                topTrailingRadius: 23
            )
            .fill(ATHLTHTrainDesign.paper)
            .ignoresSafeArea(edges: .bottom)
            .shadow(color: .black.opacity(0.10), radius: 16, y: -4)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ATHLTHTheme.premiumGold.opacity(0.22))
                .frame(height: 1)
        }
        .accessibilityIdentifier("athlth-shared-live-bottom-dock")
    }

    private var primaryButton: some View {
        Button(action: onPrimary) {
            Label(mode.primaryTitle, systemImage: mode.primarySymbol)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .background(
                    ATHLTHTheme.premiumGold,
                    in: RoundedRectangle(cornerRadius: 17)
                )
                .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .disabled(primaryDisabled)
        .opacity(primaryDisabled ? 0.48 : 1)
        .accessibilityIdentifier("athlth-shared-live-primary-action")
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if let onSecondary, let title = mode.secondaryTitle,
           let symbol = mode.secondarySymbol {
            Button(action: onSecondary) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minWidth: 103, minHeight: 54)
                    .padding(.horizontal, 6)
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .background(
                        ATHLTHTrainDesign.rule.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: 17)
                    )
            }
            .buttonStyle(.plain)
            .disabled(secondaryDisabled)
            .opacity(secondaryDisabled ? 0.48 : 1)
            .accessibilityIdentifier("athlth-shared-live-secondary-action")
        }
    }
}
