import Foundation
import ImageIO
import SwiftUI
import UIKit

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
    static let vitality = Color(red: 0.24, green: 0.47, blue: 0.38)
    static let vitalitySoft = vitality.opacity(0.12)
    static let recoveryBlue = Color(red: 0.31, green: 0.52, blue: 0.72)
    static let recoveryBlueSoft = recoveryBlue.opacity(0.11)

    // Warm stone canvas + subtly tinted surfaces keep the app light without
    // reading as flat white. Existing names are retained to avoid breaking
    // screens that already depend on the theme API.
    static let canvasTop = Color(red: 0.986, green: 0.978, blue: 0.962)
    static let canvasBottom = Color(red: 0.938, green: 0.947, blue: 0.944)
    static let card = Color(red: 0.995, green: 0.992, blue: 0.984).opacity(0.98)
    static let cardWarm = Color(red: 0.975, green: 0.956, blue: 0.922)
    static let surfaceStone = Color(red: 0.955, green: 0.958, blue: 0.950)
    static let surfaceSage = Color(red: 0.925, green: 0.950, blue: 0.934)
    static let primaryText = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let mutedText = Color(red: 0.43, green: 0.46, blue: 0.53)
    static let border = Color.black.opacity(0.055)
    static let divider = Color.black.opacity(0.065)
}

struct ATHLTHCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // Always render the card's ViewBuilder output inside one concrete
        // container before applying the card chrome. Without this wrapper,
        // multiple top-level children can each receive the background,
        // border and shadow separately and look like stacked/nested cards.
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(
                cornerRadius: ATHLTHTheme.cornerRadius,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.card,
                        ATHLTHTheme.cardWarm.opacity(0.62)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: ATHLTHTheme.cornerRadius,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.72),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.075),
            radius: 16,
            x: 0,
            y: 7
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

struct ATHLTHPremiumFormSection<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = ATHLTHTheme.vitality
    @ViewBuilder var content: Content

    var body: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                HStack(spacing: 9) {
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: 3,
                            height: 20
                        )

                    Image(systemName: icon)
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(tint)

                    Text(title)
                        .font(
                            .title3
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                    Spacer(minLength: 0)
                }

                content
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }
}

struct ATHLTHPremiumSelectionRow: View {
    let title: String
    let value: String
    let icon: String
    var subtitle: String? = nil
    var tint: Color = ATHLTHTheme.vitality

    var body: some View {
        HStack(
            alignment: subtitle == nil
                ? .center
                : .top,
            spacing: 12
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                if let subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text(value)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.trailing)
                    .frame(
                        maxWidth: 148,
                        alignment: .trailing
                    )

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(
                    .caption
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }
}

struct ATHLTHPremiumChoiceRow: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var selected: Bool = false
    var tint: Color = ATHLTHTheme.vitality

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
                .foregroundStyle(tint)
                .frame(
                    width: 40,
                    height: 40
                )
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                if let subtitle,
                   !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
            }

            Spacer(minLength: 8)

            Image(
                systemName:
                    selected
                        ? "checkmark.circle.fill"
                        : "circle"
            )
            .font(.title3)
            .foregroundStyle(
                selected
                    ? tint
                    : ATHLTHTheme
                        .mutedText
                        .opacity(0.45)
            )
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            selected
                ? tint.opacity(0.075)
                : Color.white.opacity(0.42),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                selected
                    ? tint.opacity(0.18)
                    : ATHLTHTheme
                        .border,
                lineWidth: 0.8
            )
        }
    }
}

struct ATHLTHPremiumScreenShell<Content: View>: View {
    var accent: Color = ATHLTHTheme.vitality
    var maxContentWidth: CGFloat = 760
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent: accent.opacity(0.18)
            )

            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 34)
                .frame(
                    maxWidth:
                        maxContentWidth
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(
                .interactively
            )
        }
    }
}

struct ATHLTHPremiumScreenHeader<Actions: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = ATHLTHTheme.vitality
    @ViewBuilder var actions: Actions

    var body: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                HStack(
                    alignment: .top,
                    spacing: 14
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 7
                    ) {
                        Text(eyebrow.uppercased())
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .tracking(2)
                            .foregroundStyle(
                                tint
                            )

                        Text(title)
                            .font(
                                .system(
                                    size: 31,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(2)
                            .minimumScaleFactor(
                                0.82
                            )
                    }

                    Spacer(minLength: 8)

                    Image(
                        systemName: icon
                    )
                    .font(
                        .system(
                            size: 26,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(
                        width: 60,
                        height: 60
                    )
                    .background(
                        tint,
                        in: Circle()
                    )
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                actions
            }
        }
    }
}

struct ATHLTHPremiumIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var tint: Color = ATHLTHTheme.vitality
    let action: () -> Void

    var body: some View {
        Button(
            action: action
        ) {
            Image(
                systemName: systemImage
            )
            .font(
                .system(
                    size: 16,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .primaryText
            )
            .frame(
                width: 42,
                height: 42
            )
            .background(
                Color.white.opacity(0.78),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        tint.opacity(0.12),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            accessibilityLabel
        )
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


private struct ATHLTHHeroBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 16
}

extension EnvironmentValues {
    var athlthHeroBottomInset: CGFloat {
        get { self[ATHLTHHeroBottomInsetKey.self] }
        set { self[ATHLTHHeroBottomInsetKey.self] = newValue }
    }
}

struct ATHLTHTabHero: View {
    @Environment(\.athlthHeroBottomInset) private var bottomInset
    let imageName: String
    let title: String
    let subtitle: String
    var height: CGFloat = 190
    var alignment: Alignment = .leading
    var focalOffsetX: CGFloat = 18
    var focalOffsetY: CGFloat = 16
    var titleFontSize: CGFloat = 30
    var copyWidthFraction: CGFloat = 0.74
    var immersiveCopy: Bool = false

    // Extra artwork that sits behind the pinned content sheet. It does not
    // participate in layout, so the hero/content boundary stays exactly where
    // it is. The bleed only becomes visible while the ScrollView is pulled
    // downward, preventing the light app canvas from flashing through.
    private let scrollRevealBleed: CGFloat = 104

    var body: some View {
        GeometryReader { proxy in
            let isTablet =
                UIDevice.current.userInterfaceIdiom == .pad &&
                proxy.size.width >= 700
            let isNarrowPhone =
                proxy.size.width < 390
            let isVeryNarrowPhone =
                proxy.size.width < 360
            let imageScale: CGFloat =
                immersiveCopy
                    ? (
                        isTablet
                            ? 1.01
                            : (
                                isNarrowPhone
                                    ? 1.03
                                    : 1.05
                            )
                    )
                    : (
                        isTablet
                            ? 1.04
                            : (
                                isNarrowPhone
                                    ? 1.08
                                    : 1.12
                            )
                    )
            let horizontalOffset =
                immersiveCopy
                    ? (
                        isTablet
                            ? focalOffsetX * 0.28
                            : focalOffsetX * 0.55
                    )
                    : (
                        isTablet
                            ? focalOffsetX * 0.4
                            : (
                                isNarrowPhone
                                    ? focalOffsetX * 0.72
                                    : focalOffsetX
                            )
                    )
            let verticalOffset =
                immersiveCopy
                    ? (
                        isTablet
                            ? focalOffsetY * 0.20
                            : focalOffsetY * 0.42
                    )
                    : (
                        isTablet
                            ? focalOffsetY * 0.35
                            : (
                                isNarrowPhone
                                    ? focalOffsetY * 0.72
                                    : focalOffsetY
                            )
                    )
            let copyFraction =
                isNarrowPhone
                    ? min(
                        copyWidthFraction + 0.10,
                        0.92
                    )
                    : copyWidthFraction
            let resolvedTitleSize =
                isNarrowPhone
                    ? min(
                        titleFontSize,
                        27
                    )
                    : titleFontSize

            ZStack(alignment: .leading) {
                // Continue the exact same artwork below the normal hero
                // boundary without changing the visible crop. Narrow phones
                // use slightly less overscan so focal subjects are not pushed
                // outside the viewport.
                // A calm, readable background while a tab has no uploaded artwork.
                LinearGradient(
                    colors: [ATHLTHTheme.accentDeep, ATHLTHTheme.accent, Color(red: 0.64, green: 0.66, blue: 0.63)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                if let artwork = UIImage(named: imageName) {
                    Image(uiImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height:
                                proxy.size.height +
                                scrollRevealBleed,
                            alignment: alignment
                        )
                        .scaleEffect(imageScale)
                        .offset(
                            x: horizontalOffset,
                            y: scrollRevealBleed / 2
                        )
                        .clipped()
                        .allowsHitTesting(false)

                    Image(uiImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: alignment
                        )
                        .scaleEffect(imageScale)
                        .offset(
                            x: horizontalOffset,
                            y: verticalOffset
                        )
                        .clipped()

                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(immersiveCopy ? 0.58 : 0.48),
                        Color.black.opacity(immersiveCopy ? 0.22 : 0.16),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                if immersiveCopy {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.46),
                            .init(color: Color.black.opacity(0.05), location: 0.68),
                            .init(color: ATHLTHTheme.canvasTop.opacity(0.30), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.20),
                        Color.clear,
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        ATHLTHTheme.champagne
                            .opacity(0.17),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius:
                        max(
                            proxy.size.width *
                                0.72,
                            240
                        )
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

                VStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    Text("ATHLTH")
                        .font(
                            .system(
                                size:
                                    isVeryNarrowPhone
                                        ? 15
                                        : 17,
                                weight: .black
                            )
                        )
                        .tracking(
                            isVeryNarrowPhone
                                ? 4.2
                                : 5.5
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(
                        "MOVE BETTER · LIVE LONGER"
                    )
                    .font(
                        .system(
                            size:
                                isVeryNarrowPhone
                                    ? 7
                                    : 8,
                            weight: .semibold
                        )
                    )
                    .tracking(
                        isVeryNarrowPhone
                            ? 1.3
                            : 1.7
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 2)

                    Spacer(
                        minLength:
                            isNarrowPhone
                                ? 8
                                : 12
                    )

                    Text(title)
                        .font(
                            .system(
                                size:
                                    resolvedTitleSize,
                                weight: .bold
                            )
                        )
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)

                    Text(subtitle)
                        .font(
                            .system(
                                size:
                                    isNarrowPhone
                                        ? 13
                                        : 15,
                                weight: .regular
                            )
                        )
                        .lineLimit(
                            isNarrowPhone
                                ? 3
                                : 2
                        )
                        .minimumScaleFactor(0.78)
                        .padding(.top, 2)
                }
                .foregroundStyle(.white)
                .shadow(
                    color:
                        .black.opacity(0.30),
                    radius: 5,
                    x: 0,
                    y: 2
                )
                .padding(
                    .leading,
                    isNarrowPhone
                        ? 16
                        : 20
                )
                .padding(
                    .trailing,
                    isNarrowPhone
                        ? 14
                        : 18
                )
                .padding(
                    .top,
                    immersiveCopy
                        ? (isNarrowPhone ? 48 : 54)
                        : (isNarrowPhone ? 44 : 48)
                )
                .padding(.bottom, bottomInset)
                .offset(y: -16)
                .frame(
                    maxWidth:
                        min(
                            proxy.size.width *
                                copyFraction,
                            600
                        ),
                    maxHeight: .infinity,
                    alignment: .leading
                )
            }
        }
        .frame(height: height + bottomInset - 16)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            "\(title). \(subtitle)"
        )
    }
}

private struct ATHLTHTopRoundedSheetShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(
            radius,
            rect.width / 2,
            rect.height / 2
        )

        var path = Path()
        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY + r
            )
        )
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + r,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX - r,
                y: rect.minY
            )
        )
        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY + r
            ),
            control: CGPoint(
                x: rect.maxX,
                y: rect.minY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX,
                y: rect.maxY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.maxY
            )
        )
        path.closeSubpath()

        return path
    }
}

struct ATHLTHPinnedHeroLayout<Hero: View, Content: View>: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    let accent: Color
    let softTransition: Bool
    let immersiveTransition: Bool
    let scrollFadeTransition: Bool
    let pullDownFadeBridge: Bool
    let sheetOverlapOverride: CGFloat?
    private let hero: Hero
    private let content: Content

    @State private var scrollOffset: CGFloat = 0

    // Tab heroes reserve extra space below their copy for the fade and overlap.
    // Other screens retain their existing layout.
    private var sheetOverlap: CGFloat {
        if let sheetOverlapOverride {
            return sheetOverlapOverride
        }

        return immersiveTransition
            ? 38
            : (softTransition ? 24 : 8)
    }
    private var sheetCornerRadius: CGFloat {
        immersiveTransition ? 36 : 30
    }

    private var scrollFadeProgress: CGFloat {
        guard scrollFadeTransition else { return 0 }
        return min(max(scrollOffset / 180, 0), 1)
    }

    private var scrollFadeHeight: CGFloat {
        70 + (94 * scrollFadeProgress)
    }

    private var usesTabletContentWidth: Bool {
        UIDevice.current.userInterfaceIdiom == .pad &&
        horizontalSizeClass == .regular
    }

    private var contentMaximumWidth: CGFloat? {
        usesTabletContentWidth
            ? 1040
            : nil
    }

    init(
        accent: Color,
        softTransition: Bool = false,
        immersiveTransition: Bool = false,
        scrollFadeTransition: Bool = false,
        pullDownFadeBridge: Bool = false,
        sheetOverlapOverride: CGFloat? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.softTransition = softTransition
        self.immersiveTransition = immersiveTransition
        self.scrollFadeTransition = scrollFadeTransition
        self.pullDownFadeBridge = pullDownFadeBridge
        self.sheetOverlapOverride =
            sheetOverlapOverride
        self.hero = hero()
        self.content = content()
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(accent: accent)

            VStack(spacing: -sheetOverlap) {
                hero
                    .ignoresSafeArea(edges: .top)
                    .environment(
                        \.athlthHeroBottomInset,
                        immersiveTransition
                            ? 58
                            : (softTransition ? 40 : 16)
                    )
                    .overlay(alignment: .bottom) {
                        if pullDownFadeBridge {
                            ATHLTHPullDownFadeBridge()
                        } else if !scrollFadeTransition &&
                                    (softTransition || immersiveTransition) {
                            LinearGradient(
                                stops: immersiveTransition
                                    ? [
                                        .init(color: .clear, location: 0),
                                        .init(color: ATHLTHTheme.canvasTop.opacity(0.10), location: 0.22),
                                        .init(color: ATHLTHTheme.canvasTop.opacity(0.52), location: 0.58),
                                        .init(color: ATHLTHTheme.canvasTop.opacity(0.92), location: 0.84),
                                        .init(color: ATHLTHTheme.canvasTop, location: 1)
                                    ]
                                    : [
                                        .init(color: .clear, location: 0),
                                        .init(color: ATHLTHTheme.canvasTop.opacity(0.18), location: 0.35),
                                        .init(color: ATHLTHTheme.canvasTop.opacity(0.86), location: 0.80),
                                        .init(color: ATHLTHTheme.canvasTop, location: 1)
                                    ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: immersiveTransition ? 82 : 40)
                            .allowsHitTesting(false)
                        }
                    }
                    .zIndex(0)

                ScrollView {
                    // The rounded sheet is part of the scrolling content.
                    // This lets its curved top edge move naturally with the
                    // user's drag while the hero artwork remains behind it as
                    // a back-layer. Keeping the ScrollView itself transparent
                    // avoids the fixed rectangular cutoff seen previously.
                    VStack(spacing: 0) {
                        content
                            .frame(
                                maxWidth:
                                    contentMaximumWidth ??
                                    .infinity
                            )
                            .padding(
                                .horizontal,
                                usesTabletContentWidth
                                    ? 22
                                    : 0
                            )
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .background {
                        ATHLTHTopRoundedSheetShape(
                            radius: sheetCornerRadius
                        )
                        .fill(
                            LinearGradient(
                                colors: [
                                    ATHLTHTheme.canvasTop.opacity(
                                        immersiveTransition ? 0.965 : 0.99
                                    ),
                                    ATHLTHTheme.surfaceStone.opacity(
                                        immersiveTransition ? 0.965 : 0.98
                                    ),
                                    ATHLTHTheme.canvasBottom.opacity(0.96)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .clipShape(
                        ATHLTHTopRoundedSheetShape(
                            radius: sheetCornerRadius
                        )
                    )
                    .overlay {
                        ATHLTHTopRoundedSheetShape(
                            radius: sheetCornerRadius
                        )
                        .stroke(
                            Color.white.opacity(
                                immersiveTransition || softTransition
                                    ? 0
                                    : 0.70
                            ),
                            lineWidth: 0.8
                        )
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .top) {
                        if pullDownFadeBridge ||
                            (immersiveTransition && !scrollFadeTransition) {
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(
                                        pullDownFadeBridge ? 0.62 : 0.38
                                    ),
                                    Color.white.opacity(
                                        pullDownFadeBridge ? 0.20 : 0.08
                                    ),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(
                                height:
                                    pullDownFadeBridge ? 54 : 42
                            )
                            .clipShape(
                                ATHLTHTopRoundedSheetShape(
                                    radius: sheetCornerRadius
                                )
                            )
                            .allowsHitTesting(false)
                        }
                    }
                    .shadow(
                        color: ATHLTHTheme.accentDeep.opacity(
                            scrollFadeTransition
                                ? 0
                                : (
                                    immersiveTransition
                                        ? 0.065
                                        : (softTransition ? 0.045 : 0.075)
                                )
                        ),
                        radius:
                            scrollFadeTransition
                                ? 0
                                : (immersiveTransition ? 28 : 20),
                        x: 0,
                        y:
                            scrollFadeTransition
                                ? 0
                                : (
                                    immersiveTransition
                                        ? -2
                                        : (softTransition ? 4 : -4)
                                )
                    )
                    .padding(
                        .horizontal,
                        scrollFadeTransition
                            ? 0
                            : (
                                immersiveTransition
                                    ? 8
                                    : (softTransition ? 10 : 0)
                            )
                    )
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Color.clear)
                .mask {
                    if scrollFadeTransition {
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(
                                        color: Color.clear,
                                        location: 0
                                    ),
                                    .init(
                                        color: Color.clear,
                                        location: 0.10
                                    ),
                                    .init(
                                        color: Color.black.opacity(
                                            0.42 + (0.05 * scrollFadeProgress)
                                        ),
                                        location: 0.30
                                    ),
                                    .init(
                                        color: Color.black.opacity(0.84),
                                        location: 0.62
                                    ),
                                    .init(
                                        color: Color.black,
                                        location: 1
                                    )
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: scrollFadeHeight)

                            Color.black
                        }
                    } else {
                        Color.black
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y)
                } action: { _, newOffset in
                    guard scrollFadeTransition else { return }
                    scrollOffset = newOffset
                }
                .zIndex(1)
            }
        }
        // Apply safe-area expansion to the complete layout rather than only
        // the inner stack. NavigationStack otherwise keeps the hero's layout
        // origin below the status-bar safe area even though the canvas itself
        // can paint behind it.
        .ignoresSafeArea(edges: .top)
    }
}


struct ATHLTHPullDownFadeBridge:
    View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(
                    color: .clear,
                    location: 0
                ),
                .init(
                    color:
                        ATHLTHTheme
                            .canvasTop
                            .opacity(0.08),
                    location: 0.18
                ),
                .init(
                    color:
                        ATHLTHTheme
                            .canvasTop
                            .opacity(0.38),
                    location: 0.48
                ),
                .init(
                    color:
                        ATHLTHTheme
                            .canvasTop
                            .opacity(0.80),
                    location: 0.76
                ),
                .init(
                    color:
                        ATHLTHTheme
                            .canvasTop,
                    location: 1
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 92)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                    ATHLTHTheme.surfaceStone,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    accent.opacity(0.085),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    ATHLTHTheme.premiumGold.opacity(0.070),
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


enum ATHLTHStandardArtwork: String, CaseIterable, Identifiable, Codable, Hashable {
    case sprint
    case walking
    case mountain
    case progress
    case relax
    case running
    case strength
    case endurance
    case recovery
    case consistency
    case event
    case adventure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sprint: return "Sprint"
        case .walking: return "Walking"
        case .mountain: return "Mountain"
        case .progress: return "Progress"
        case .relax: return "Relax"
        case .running: return "Running"
        case .strength: return "Strength"
        case .endurance: return "Endurance"
        case .recovery: return "Recovery"
        case .consistency: return "Consistency"
        case .event: return "Event"
        case .adventure: return "Adventure"
        }
    }

    var assetName: String {
        switch self {
        case .sprint: return "GoalSprint"
        case .walking: return "GoalWalking"
        case .mountain: return "GoalMountain"
        case .progress: return "GoalProgress"
        case .relax: return "GoalRelax"
        case .running: return "GoalRunning"
        case .strength: return "GoalStrength"
        case .endurance: return "GoalEndurance"
        case .recovery: return "GoalRecovery"
        case .consistency: return "GoalConsistency"
        case .event: return "GoalEvent"
        case .adventure: return "GoalAdventure"
        }
    }

    var fallbackAssetName: String {
        switch self {
        case .sprint, .running:
            return "TrainHero"
        case .endurance:
            return "StrengthPostWorkoutHero"
        case .walking, .progress:
            return "HomeHero"
        case .consistency:
            return "ProgressHero"
        case .mountain, .adventure:
            return "OnboardingHero"
        case .event:
            return "CommunityHero"
        case .relax, .recovery:
            return "RecoveryHero"
        case .strength:
            return "TrainHero"
        }
    }

    var thumbnailAssetName: String {
        "\(assetName)Thumbnail"
    }

    var reference: String {
        "athlth-asset://\(assetName)"
    }

    init?(reference: String?) {
        guard
            let reference,
            reference.hasPrefix("athlth-asset://")
        else {
            return nil
        }

        let assetName =
            String(
                reference.dropFirst(
                    "athlth-asset://".count
                )
            )

        guard let match =
                Self.allCases.first(
                    where: {
                        $0.assetName ==
                            assetName
                    }
                )
        else {
            return nil
        }

        self = match
    }

    var resolvedUIImage: UIImage? {
        if let image =
                UIImage(named: assetName),
           image.size.width > 8,
           image.size.height > 8 {
            return image
        }

        return UIImage(
            named: fallbackAssetName
        )
    }

    var resolvedThumbnailUIImage: UIImage? {
        if let image = UIImage(
            named: thumbnailAssetName
        ),
        image.size.width > 8,
        image.size.height > 8 {
            return image
        }

        return resolvedUIImage
    }
}

private struct ATHLTHPreparedRemoteImage:
    @unchecked Sendable {
    let image: UIImage
}

private enum ATHLTHRemoteImageDecoder {
    static func decode(
        _ data: Data,
        maxPixelSize: Int
    ) -> ATHLTHPreparedRemoteImage? {
        guard let source =
                CGImageSourceCreateWithData(
                    data as CFData,
                    nil
                )
        else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize:
                maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let cgImage =
                CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options as CFDictionary
                )
        else {
            return nil
        }

        return ATHLTHPreparedRemoteImage(
            image: UIImage(cgImage: cgImage)
        )
    }
}

@MainActor
private final class ATHLTHRemoteArtworkCache {
    static let shared = ATHLTHRemoteArtworkCache()

    private let images = NSCache<NSString, UIImage>()

    private init() {
        images.countLimit = 28
        images.totalCostLimit = 28 * 1_024 * 1_024
    }

    func image(
        for key: String
    ) -> UIImage? {
        images.object(
            forKey: key as NSString
        )
    }

    func store(
        _ image: UIImage,
        for key: String
    ) {
        let cost = Int(
            image.size.width *
            image.size.height *
            image.scale *
            image.scale *
            4
        )
        images.setObject(
            image,
            forKey: key as NSString,
            cost: cost
        )
    }

    func removeAll() {
        images.removeAllObjects()
    }
}

private struct ATHLTHRemoteArtworkImage: View {
    @Environment(\.athlthImageAccountID) private var accountID
    let url: URL
    let fallbackAssetName: String
    let maxPixelSize: Int

    @State private var image: UIImage?
    @State private var loadedAccountID: UUID?

    private var cacheKey: String {
        "\(maxPixelSize)|\(url.absoluteString)"
    }

    var body: some View {
        Group {
            if loadedAccountID == accountID, let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(fallbackAssetName)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: ATHLTHImageRequestID(url: url, accountID: accountID)) {
            image = nil
            let isPrivate = ATHLTHStorageImageURL.privateWorkoutPath(url) != nil
            if !isPrivate, let cached =
                    ATHLTHRemoteArtworkCache
                        .shared
                        .image(for: cacheKey) {
                image = cached
                loadedAccountID = accountID
                return
            }

            do {
                let resolvedURL = try await ATHLTHStorageImageURL.resolve(url)
                var request = URLRequest(url: resolvedURL)
                if isPrivate {
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                }
                let (data, _) =
                    try await URLSession.shared.data(
                        for: request
                    )

                let prepared =
                    await Task.detached(
                        priority: .utility
                    ) {
                        ATHLTHRemoteImageDecoder.decode(
                            data,
                            maxPixelSize: maxPixelSize
                        )
                    }
                    .value

                guard !Task.isCancelled,
                      let prepared
                else {
                    return
                }

                if !isPrivate {
                    ATHLTHRemoteArtworkCache
                    .shared
                    .store(
                        prepared.image,
                        for: cacheKey
                    )
                }
                loadedAccountID = accountID
                image = prepared.image
            } catch {
                return
            }
        }
    }
}

struct ATHLTHArtworkImage: View {
    let reference: String?
    var fallbackAssetName: String = "CommunityHero"
    var maxPixelSize: Int = 900

    @MainActor
    static func clearRemoteCache() {
        URLCache.shared.removeAllCachedResponses()
        ATHLTHRemoteArtworkCache
            .shared
            .removeAll()
    }

    var body: some View {
        Group {
            if let artwork =
                    ATHLTHStandardArtwork(
                        reference: reference
                    ),
               let image =
                    artwork.resolvedUIImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let reference,
                      let url =
                        URL(string: reference),
                      ["http", "https"]
                        .contains(
                            url.scheme?
                                .lowercased() ?? ""
                        ) {
                ATHLTHRemoteArtworkImage(
                    url: url,
                    fallbackAssetName:
                        fallbackAssetName,
                    maxPixelSize:
                        maxPixelSize
                )
            } else {
                Image(fallbackAssetName)
                    .resizable()
                    .scaledToFill()
            }
        }
    }
}

struct ATHLTHStandardArtworkPicker: View {
    @Binding var selection:
        ATHLTHStandardArtwork?

    var body: some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            LazyHStack(spacing: 10) {
                ForEach(
                    ATHLTHStandardArtwork
                        .allCases
                ) { artwork in
                    let isSelected =
                        selection == artwork

                    Button {
                        selection = artwork
                    } label: {
                        ZStack(
                            alignment:
                                .bottomLeading
                        ) {
                            if let image =
                                    artwork
                                        .resolvedThumbnailUIImage {
                                Image(
                                    uiImage:
                                        image
                                )
                                .resizable()
                                .scaledToFill()
                                .scaleEffect(
                                    1.14,
                                    anchor:
                                        .trailing
                                )
                            } else {
                                ATHLTHTheme
                                    .accentSoft
                            }

                            LinearGradient(
                                colors: [
                                    .clear,
                                    .black
                                        .opacity(
                                            0.64
                                        )
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )

                            Text(
                                artwork.title
                            )
                            .font(
                                .system(
                                    size: 10,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                .white
                            )
                            .padding(8)

                            if isSelected {
                                Image(
                                    systemName:
                                        "checkmark.circle.fill"
                                )
                                .font(
                                    .system(
                                        size: 18,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    .white
                                )
                                .shadow(
                                    color:
                                        .black
                                        .opacity(
                                            0.18
                                        ),
                                    radius: 3
                                )
                                .padding(7)
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    maxHeight:
                                        .infinity,
                                    alignment:
                                        .topTrailing
                                )
                            }
                        }
                        .frame(
                            width: 116,
                            height: 76
                        )
                        .clipped()
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                            .stroke(
                                isSelected
                                    ? ATHLTHTheme
                                        .accentDeep
                                    : Color.black
                                        .opacity(
                                            0.055
                                        ),
                                lineWidth:
                                    isSelected
                                        ? 2
                                        : 0.7
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(
                .vertical,
                2
            )
        }
    }
}
