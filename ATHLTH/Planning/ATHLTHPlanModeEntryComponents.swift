import SwiftUI

/// Lightweight illustration for the first plan step. Everything is native
/// SwiftUI so it renders offline without a heavyweight image asset.
struct ATHLTHPlanModeIllustration: View {
    private let gold = ATHLTHPlanDesign.accent
    private let ink = ATHLTHPlanDesign.ink
    private let cream = Color(red: 0.97, green: 0.947, blue: 0.907)

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [cream.opacity(0.85), cream.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 110
                    )
                )
                .frame(width: 215, height: 215)

            clipboard
                .rotationEffect(.degrees(9))
                .offset(x: -2, y: -7)

            Image(systemName: "dumbbell.fill")
                .font(.system(size: 59, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.22, blue: 0.24),
                                 Color(red: 0.40, green: 0.40, blue: 0.39)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(-17))
                .shadow(color: ink.opacity(0.16), radius: 4, y: 7)
                .offset(x: -27, y: 55)

            bottle
                .offset(x: 73, y: 38)
        }
        .frame(width: 190, height: 177)
        .accessibilityHidden(true)
    }

    private var clipboard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(red: 0.98, green: 0.974, blue: 0.953))
                .frame(width: 105, height: 143)
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(gold.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: ink.opacity(0.10), radius: 12, x: 4, y: 9)

            VStack(alignment: .leading, spacing: 15) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(gold.opacity(0.7))
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule()
                                .fill(gold.opacity(0.17))
                                .frame(width: index == 1 ? 45 : 50, height: 4)
                            Capsule()
                                .fill(gold.opacity(0.10))
                                .frame(width: 33, height: 4)
                        }
                    }
                }
            }
            .padding(.top, 29)

            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [gold.opacity(0.71), gold.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 37, height: 15)
                .offset(y: -6)
        }
    }

    private var bottle: some View {
        VStack(spacing: -1) {
            RoundedRectangle(cornerRadius: 4)
                .fill(ink.opacity(0.83))
                .frame(width: 28, height: 12)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.94, green: 0.91, blue: 0.85),
                                 Color(red: 0.86, green: 0.82, blue: 0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 87)
                .overlay {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(gold.opacity(0.55))
                }
        }
        .shadow(color: ink.opacity(0.12), radius: 5, x: 3, y: 5)
    }
}

/// Mode selection does not navigate. The explicit CTA in the plan wizard
/// advances only after the user has seen both choices.
struct ATHLTHPlanEntryModeCard: View {
    struct Feature: Identifiable {
        let symbol: String
        let title: String
        var id: String { symbol + title }
    }

    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let features: [Feature]
    let onSelect: () -> Void

    private let ink = ATHLTHPlanDesign.ink
    private let muted = ATHLTHPlanDesign.secondaryInk
    private let gold = ATHLTHPlanDesign.accent

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 13) {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(selected ? gold : ink)
                        .frame(width: 58, height: 58)
                        .background(
                            selected ? gold.opacity(0.095) : ink.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(ink)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(selected ? gold : muted.opacity(0.33))
                        .accessibilityHidden(true)
                }

                Rectangle()
                    .fill(gold.opacity(selected ? 0.18 : 0.10))
                    .frame(height: 0.7)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ForEach(features) { item in feature(item) }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(features) { item in feature(item) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: selected
                                ? [Color.white, Color(red: 0.99, green: 0.975, blue: 0.948)]
                                : [Color.white, Color(red: 0.997, green: 0.993, blue: 0.986)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(
                        selected ? gold.opacity(0.90) : ATHLTHPlanDesign.outline,
                        lineWidth: selected ? 1.3 : 0.85
                    )
            }
            .shadow(
                color: ink.opacity(selected ? 0.07 : 0.045),
                radius: selected ? 15 : 10, y: 6
            )
            .contentShape(RoundedRectangle(cornerRadius: 23))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(
            ATHLTHLocalization.choose(
                english: "Select planning mode, then continue.",
                norwegian: "Velg planleggingsmåte, og trykk deretter Fortsett."
            )
        )
    }

    private func feature(_ item: Feature) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(gold)
                .accessibilityHidden(true)
            Text(item.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct ATHLTHPlanExistingChoice: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                Color(red: 0.965, green: 0.958, blue: 0.950),
                in: RoundedRectangle(cornerRadius: 22)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + ". " + subtitle)
    }
}
