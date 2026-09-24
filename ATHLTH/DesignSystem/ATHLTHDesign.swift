import SwiftUI

enum ATHLTHTheme {
    static let cornerRadius: CGFloat = 24
    static let smallCornerRadius: CGFloat = 16
    static let contentSpacing: CGFloat = 16

    // ATHLTH brand palette.
    // Slate is the primary interactive accent across iPhone and Apple Watch.
    // Champagne is reserved for ATHLTH+ / premium moments.
    static let accent = Color(red: 0.29, green: 0.34, blue: 0.43)
    static let accentDeep = Color(red: 0.20, green: 0.24, blue: 0.31)
    static let accentSoft = accent.opacity(0.10)
    static let premiumGold = Color(red: 0.72, green: 0.55, blue: 0.31)
    static let premiumGoldSoft = premiumGold.opacity(0.14)
    static let champagne = Color(red: 0.93, green: 0.87, blue: 0.76)
    static let champagneSoft = champagne.opacity(0.18)

    static let canvasTop = Color(red: 0.995, green: 0.992, blue: 0.986)
    static let canvasBottom = Color(red: 0.966, green: 0.962, blue: 0.955)
    static let card = Color.white.opacity(0.97)
    static let cardWarm = Color(red: 0.992, green: 0.985, blue: 0.972)
    static let primaryText = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let mutedText = Color(red: 0.43, green: 0.46, blue: 0.53)
    static let border = Color.black.opacity(0.055)
    static let divider = Color.black.opacity(0.065)
}

struct ATHLTHCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: ATHLTHTheme.cornerRadius,
                    style: .continuous
                )
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ATHLTHTheme.cornerRadius,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                ATHLTHTheme.cardWarm.opacity(0.22),
                                ATHLTHTheme.champagneSoft.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: ATHLTHTheme.cornerRadius,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.90),
                            ATHLTHTheme.premiumGold.opacity(0.10),
                            Color.black.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color: ATHLTHTheme.accentDeep.opacity(0.055),
                radius: 18,
                x: 0,
                y: 9
            )
            .shadow(
                color: ATHLTHTheme.premiumGold.opacity(0.025),
                radius: 26,
                x: 0,
                y: 14
            )
    }
}

struct ATHLTHSectionHeader: View {
    let title: String
    var actionTitle: String? = nil

    var body: some View {
        HStack(spacing: 9) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.premiumGold,
                            ATHLTHTheme.accent
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 19)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Spacer()

            if let actionTitle {
                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.78))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Capsule()
                    )
            }
        }
    }
}

struct ATHLTHMetric: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = ATHLTHTheme.accent

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(
                    tint.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(title)
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ATHLTHProgressRing: View {
    let title: String
    let value: String
    let progress: Double
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Text(value)
                        .font(.headline.weight(.bold))
                }
            }
            .frame(width: 92, height: 92)

            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ATHLTHPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ATHLTH")
                .font(.title3.weight(.black))
                .tracking(6)
            Text("MOVE BETTER · LIVE LONGER")
                .font(.caption2.weight(.medium))
                .tracking(2)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 8)

            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct ATHLTHTabHero: View {
    let imageName: String
    let title: String
    let subtitle: String
    var height: CGFloat = 190
    var alignment: Alignment = .leading
    var focalOffsetX: CGFloat = 18
    var focalOffsetY: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: alignment
                    )
                    // Keep enough overscan on iPhone to move the focal subject
                    // below the status/Dynamic Island zone without exposing
                    // empty image edges. Wide iPad layouts need far less zoom.
                    .scaleEffect(
                        proxy.size.width >= 700
                            ? 1.04
                            : 1.12
                    )
                    .offset(
                        x: proxy.size.width >= 700
                            ? focalOffsetX * 0.4
                            : focalOffsetX,
                        y: proxy.size.width >= 700
                            ? focalOffsetY * 0.35
                            : focalOffsetY
                    )
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.48),
                        Color.black.opacity(0.16),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.20),
                        Color.clear,
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // The hero is intentionally full-bleed, but the top strip is
                // treated as visual breathing room for the iPhone status bar
                // and Dynamic Island. Important subjects are positioned below
                // this zone with focalOffsetY.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        Color.black.opacity(0.07),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 62)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

                RadialGradient(
                    colors: [
                        ATHLTHTheme.champagne.opacity(0.17),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(proxy.size.width * 0.72, 260)
                )
                .blendMode(.screen)
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    Text("ATHLTH")
                        .font(.system(size: 17, weight: .black))
                        .tracking(5.5)

                    Text("MOVE BETTER · LIVE LONGER")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.7)
                        .padding(.top, 2)

                    Spacer(minLength: 12)

                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.subheadline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .padding(.top, 2)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.30), radius: 5, x: 0, y: 2)
                .padding(.leading, 20)
                .padding(.trailing, 18)
                .padding(.top, 48)
                .padding(.bottom, 16)
                .frame(
                    maxWidth: min(proxy.size.width * 0.74, 560),
                    maxHeight: .infinity,
                    alignment: .leading
                )
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}


struct ATHLTHPremiumSegmentedControl: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        selection = index
                    }
                } label: {
                    Text(title)
                        .font(
                            .subheadline.weight(
                                selection == index ? .semibold : .medium
                            )
                        )
                        .foregroundStyle(
                            selection == index
                                ? ATHLTHTheme.primaryText
                                : ATHLTHTheme.mutedText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            if selection == index {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white,
                                                ATHLTHTheme.cardWarm
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay {
                                        Capsule()
                                            .stroke(
                                                ATHLTHTheme.premiumGold.opacity(0.16),
                                                lineWidth: 0.8
                                            )
                                    }
                                    .shadow(
                                        color: ATHLTHTheme.accentDeep.opacity(0.09),
                                        radius: 8,
                                        x: 0,
                                        y: 4
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            ATHLTHTheme.accentDeep.opacity(0.055),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.72), lineWidth: 0.8)
        }
    }
}

struct ATHLTHPremiumCanvas: View {
    var accent: Color = ATHLTHTheme.accent

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    Color.white,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    accent.opacity(0.055),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    ATHLTHTheme.premiumGold.opacity(0.045),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}
