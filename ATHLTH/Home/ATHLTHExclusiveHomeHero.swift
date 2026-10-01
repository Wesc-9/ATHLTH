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

    // Keep the Home hero on the same 236 pt vertical rhythm as
    // Profile so the artwork, sheet transition and first content row line up
    // consistently across the primary personal surfaces.
    private let resolvedHeight: CGFloat = 236

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


/// Home-specific hero that folds today's next planned session into the artwork.
/// This keeps the primary action visible without adding a second workout card
/// below the hero.
struct ATHLTHHomeNextWorkoutHero: View {
    let imageName: String
    let workout: PlannedSession?
    let isStarting: Bool
    let onStart: () -> Void
    let onOpenPlan: () -> Void

    private let resolvedHeight: CGFloat = 330

    var body: some View {
        GeometryReader { proxy in
            ZStack {
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

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.20), location: 0),
                        .init(color: Color.black.opacity(0.05), location: 0.34),
                        .init(color: Color.black.opacity(0.26), location: 0.63),
                        .init(color: Color.black.opacity(0.72), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.28),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATHLTH")
                            .font(
                                .system(
                                    size: 31,
                                    weight: .medium,
                                    design: .rounded
                                )
                            )
                            .tracking(7.0)
                            .foregroundStyle(.white)

                        Text("MOVE  BETTER  LIVE  LONGER")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(3.0)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .padding(.top, 61)

                    Spacer(minLength: 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout == nil ? "I DAG" : "NESTE ØKT")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.86))

                        Text(workout?.title ?? "Restitusjonsdag")
                            .font(
                                .system(
                                    size: UIDevice.current.userInterfaceIdiom == .pad
                                        ? 34
                                        : 31,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        if let workout {
                            HStack(spacing: 17) {
                                if let distance = workout.targetDistanceKilometers,
                                   distance > 0 {
                                    heroMetric(
                                        icon: workout.kind.systemImage,
                                        value: formatDistance(distance)
                                    )
                                } else {
                                    heroMetric(
                                        icon: workout.kind.systemImage,
                                        value: workout.kind.title
                                    )
                                }

                                if let pace = workout.targetPaceSecondsPerKilometer,
                                   pace > 0 {
                                    heroMetric(
                                        icon: "speedometer",
                                        value: formatPace(pace)
                                    )
                                }

                                if let minutes = workout.durationMinutes,
                                   minutes > 0 {
                                    heroMetric(
                                        icon: "stopwatch",
                                        value: formatDuration(minutes)
                                    )
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        } else {
                            Text("Ingen planlagt økt i dag.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.82))
                        }

                        HStack(spacing: 10) {
                            if workout != nil {
                                Button(action: onStart) {
                                    HStack(spacing: 9) {
                                        if isStarting {
                                            ProgressView()
                                                .controlSize(.small)
                                                .tint(ATHLTHTheme.primaryText)
                                        } else {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 13, weight: .bold))
                                        }

                                        Text(isStarting ? "Starter…" : "Start økt")
                                            .font(.subheadline.weight(.bold))
                                    }
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                    .padding(.horizontal, 20)
                                    .frame(height: 46)
                                    .background(
                                        Color.white.opacity(0.97),
                                        in: Capsule()
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isStarting)
                            }

                            Button(action: onOpenPlan) {
                                HStack(spacing: 7) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Se dagens plan")
                                        .font(.caption.weight(.semibold))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 15)
                                .frame(height: 42)
                                .background(
                                    Color.black.opacity(0.34),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            Color.white.opacity(0.34),
                                            lineWidth: 0.8
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 3)
                    }
                    .shadow(
                        color: Color.black.opacity(0.25),
                        radius: 10,
                        y: 3
                    )
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
            }
        }
        .frame(height: resolvedHeight)
        .clipped()
    }

    private func heroMetric(
        icon: String,
        value: String
    ) -> some View {
        Label {
            Text(value)
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
    }

    private func formatDistance(_ kilometers: Double) -> String {
        if kilometers.rounded() == kilometers {
            return "\(Int(kilometers)) km"
        }

        return String(
            format: "%.1f km",
            locale: Locale.current,
            kilometers
        )
    }

    private func formatPace(_ seconds: Double) -> String {
        let rounded = max(Int(seconds.rounded()), 0)
        let minutes = rounded / 60
        let remaining = rounded % 60
        return String(
            format: "%d:%02d/km",
            minutes,
            remaining
        )
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainder = minutes % 60

        if remainder == 0 {
            return "\(hours) t"
        }

        return "\(hours)t \(remainder)m"
    }
}
