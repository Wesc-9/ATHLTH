import SwiftUI
import UIKit

/// Home-only hero rebuilt for ATHLTH 1.5.0.
///
/// The artwork is intentionally rendered once, at its natural 2:1-ish crop,
/// with no overscan, duplicated image layers, focal-point offsets, or
/// scroll-driven scaling. The premium feel comes from proportion, typography,
/// restrained contrast, and the transition into the content sheet.
struct ATHLTHExclusiveHomeHero: View {
    let imageName: String
    let title: String
    let subtitle: String

    private var resolvedHeight: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 216
        }

        return UIScreen.main.bounds.width < 390 ? 188 : 202
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .accessibilityHidden(true)

                // One restrained tonal treatment for legibility. The artwork
                // remains the only visual source in the hero.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.16),
                        .init(color: Color.black.opacity(0.08), location: 0.48),
                        .init(color: Color.black.opacity(0.58), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.22), location: 0),
                        .init(color: .clear, location: 0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(112, proxy.size.height * 0.56))
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 5) {
                    Text("ATHLTH")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(3.0)
                        .foregroundStyle(.white.opacity(0.78))

                    Text(title)
                        .font(
                            .system(
                                size: UIDevice.current.userInterfaceIdiom == .pad
                                    ? 31
                                    : 28,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .shadow(
                    color: Color.black.opacity(0.22),
                    radius: 10,
                    y: 3
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 29)
                .frame(
                    maxWidth: UIDevice.current.userInterfaceIdiom == .pad
                        ? min(proxy.size.width * 0.62, 560)
                        : proxy.size.width * 0.72,
                    alignment: .leading
                )
            }
        }
        .frame(height: resolvedHeight)
        .clipped()
    }
}

struct ATHLTHExclusiveHomeHeroLayout<Hero: View, Content: View>: View {
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    let accent: Color
    private let showsTopSheen: Bool
    private let hero: Hero
    private let content: Content

    private let overlap: CGFloat = 22
    private let sheetRadius: CGFloat = 28

    private var usesTabletContentWidth: Bool {
        UIDevice.current.userInterfaceIdiom == .pad &&
            horizontalSizeClass == .regular
    }

    private var contentMaximumWidth: CGFloat? {
        usesTabletContentWidth ? 1040 : nil
    }

    init(
        accent: Color,
        showsTopSheen: Bool = true,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.showsTopSheen = showsTopSheen
        self.hero = hero()
        self.content = content()
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(accent: accent)

            VStack(spacing: -overlap) {
                hero
                    .ignoresSafeArea(edges: .top)
                    .zIndex(0)

                ScrollView {
                    VStack(spacing: 0) {
                        content
                            .frame(
                                maxWidth:
                                    contentMaximumWidth ??
                                    .infinity
                            )
                            .padding(
                                .horizontal,
                                usesTabletContentWidth ? 22 : 0
                            )
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .background {
                        ATHLTHExclusiveHomeSheetShape(
                            radius: sheetRadius
                        )
                        .fill(
                            LinearGradient(
                                colors: [
                                    ATHLTHTheme.canvasTop,
                                    ATHLTHTheme.surfaceStone.opacity(0.985),
                                    ATHLTHTheme.canvasBottom.opacity(0.97)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .clipShape(
                        ATHLTHExclusiveHomeSheetShape(
                            radius: sheetRadius
                        )
                    )
                    .overlay(alignment: .top) {
                        if showsTopSheen {
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.72),
                                    Color.white.opacity(0.18),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 34)
                            .clipShape(
                                ATHLTHExclusiveHomeSheetShape(
                                    radius: sheetRadius
                                )
                            )
                            .allowsHitTesting(false)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .zIndex(1)
            }
        }
    }
}

private struct ATHLTHExclusiveHomeSheetShape: Shape {
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
