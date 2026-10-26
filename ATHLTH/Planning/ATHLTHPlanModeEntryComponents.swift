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
    var compact: Bool = false
    let onSelect: () -> Void

    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let gold = ATHLTHTrainDesign.gold

    // These images were adapted from the approved plan-entry visual and
    // bundled in Assets.xcassets, so the first step is available offline.
    private var photoName: String {
        symbol == "sparkles" ? "PlanEntrySimple" : "PlanEntryAdvanced"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                introduction
                Rectangle()
                    .fill(bronze.opacity(0.14))
                    .frame(height: 0.6)
                    .padding(.horizontal, 12)
                featureStrip
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 19))
            .clipShape(RoundedRectangle(cornerRadius: 19))
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(
                        selected ? gold.opacity(0.98) :
                            ATHLTHTrainDesign.rule.opacity(0.46),
                        lineWidth: selected ? 1.4 : 0.75
                    )
            }
            .shadow(color: ink.opacity(selected ? 0.10 : 0.045),
                    radius: selected ? 14 : 10, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Select this planning mode, then continue.",
            norwegian: "Velg denne planleggingsmåten, og trykk deretter Fortsett."
        ))
    }

    private var introduction: some View {
        ZStack(alignment: .leading) {
            GeometryReader { bounds in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(photoName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width * 0.51,
                               height: bounds.size.height)
                        .clipped()
                }
            }
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.98), location: 0.34),
                    .init(color: .white.opacity(0.77), location: 0.57),
                    .init(color: .white.opacity(0.0), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                Text(title)
                    .font(.system(size: compact ? 26 : 31,
                                  weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(.system(size: compact ? 11.5 : 13.5))
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(compact ? 3 : 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, compact ? 15 : 19)
            .padding(.trailing, compact ? 118 : 145)

            VStack {
                HStack {
                    Spacer()
                    Image(systemName: selected ? "checkmark" : "circle")
                        .font(.system(size: selected ? 13 : 27,
                                      weight: .semibold))
                        .foregroundStyle(selected ? Color.white :
                                         ink.opacity(0.34))
                        .frame(width: 34, height: 34)
                        .background {
                            if selected {
                                Circle().fill(gold)
                            }
                        }
                }
                Spacer()
            }
            .padding(14)
            .accessibilityHidden(true)
        }
        .frame(height: compact ? 116 : 140)
    }

    private var featureStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: compact ? 6 : 9) {
                ForEach(features) { item in
                    feature(item)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(features) { item in feature(item) }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, compact ? 9 : 11)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.99))
    }

    private func feature(_ item: Feature) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.symbol)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(bronze)
                .accessibilityHidden(true)
            Text(item.title)
                .font(.system(size: compact ? 9 : 10))
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
    }
}

struct ATHLTHPlanExistingChoice: View {
    let title: String
    let subtitle: String
    let symbol: String
    var compact: Bool = false
    let action: () -> Void

    private let ink = ATHLTHPlanDesign.ink
    private let muted = ATHLTHPlanDesign.secondaryInk
    private let gold = ATHLTHPlanDesign.accent

    var body: some View {
        Button(action: action) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            symbolBadge
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(muted)
                                .accessibilityHidden(true)
                        }

                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                } else {
                    HStack(spacing: 10) {
                        symbolBadge
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
            }
            .padding(compact ? 12 : 14)
            .background(
                LinearGradient(
                    colors: [.white, Color(red: 0.99, green: 0.975, blue: 0.948)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(ATHLTHPlanDesign.outline, lineWidth: 0.85)
            }
            .shadow(color: ink.opacity(0.045), radius: 10, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + ". " + subtitle)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Open your plans.",
            norwegian: "Åpne planene."
        ))
    }

    private var symbolBadge: some View {
        Image(systemName: symbol)
            .font(.system(size: compact ? 17 : 20, weight: .medium))
            .foregroundStyle(gold)
            .frame(width: compact ? 35 : 42, height: compact ? 35 : 42)
            .background(
                gold.opacity(0.095),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .accessibilityHidden(true)
    }
}
