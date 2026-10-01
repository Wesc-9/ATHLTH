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


/// Compact Home hero used by the 1.5.3 dashboard.
///
/// The hero has only one primary job: expose today's next action. When no
/// workout is planned it shows two compact Quick Train actions. When a workout
/// exists it becomes the workout launcher. Weather is intentionally secondary
/// and lives on the right edge of the artwork.
struct ATHLTHHomeDashboardHero: View {
    let imageName: String
    let workout: PlannedSession?
    let isStarting: Bool
    let weather: HomeWeatherSnapshot?
    let onStart: () -> Void
    let onQuickRun: () -> Void
    let onQuickStrength: () -> Void
    let onOpenPlan: () -> Void

    private let resolvedHeight: CGFloat = 248

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
                        .init(
                            color: Color.white.opacity(0.10),
                            location: 0
                        ),
                        .init(
                            color: Color.clear,
                            location: 0.42
                        ),
                        .init(
                            color: Color.black.opacity(0.08),
                            location: 0.62
                        ),
                        .init(
                            color: Color.black.opacity(0.47),
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.17),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ATHLTH")
                            .font(
                                .system(
                                    size: 29,
                                    weight: .medium,
                                    design: .rounded
                                )
                            )
                            .tracking(6.6)
                            .foregroundStyle(.white)

                        Text("MOVE  BETTER  LIVE  LONGER")
                            .font(
                                .system(
                                    size: 8.5,
                                    weight: .semibold
                                )
                            )
                            .tracking(2.7)
                            .foregroundStyle(
                                .white.opacity(0.82)
                            )
                    }
                    .padding(.top, 58)

                    Spacer(minLength: 16)

                    if let workout {
                        plannedWorkoutContent(
                            workout
                        )
                    } else {
                        quickTrainContent
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )

                weatherBadge
                    .padding(.trailing, 18)
                    .padding(.top, 118)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topTrailing
                    )
            }
        }
        .frame(height: resolvedHeight)
        .clipped()
    }

    private func plannedWorkoutContent(
        _ workout: PlannedSession
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            Text("NESTE ØKT")
                .font(
                    .system(
                        size: 10.5,
                        weight: .bold
                    )
                )
                .tracking(0.8)
                .foregroundStyle(
                    .white.opacity(0.88)
                )

            Text(workout.title)
                .font(
                    .system(
                        size:
                            UIDevice.current
                                .userInterfaceIdiom == .pad
                                ? 29
                                : 25,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 13) {
                if let distance =
                        workout.targetDistanceKilometers,
                   distance > 0 {
                    heroMetric(
                        icon:
                            workout.kind.systemImage,
                        value:
                            formatDistance(
                                distance
                            )
                    )
                }

                if let pace =
                        workout
                            .targetPaceSecondsPerKilometer,
                   pace > 0 {
                    heroMetric(
                        icon: "speedometer",
                        value:
                            formatPace(pace)
                    )
                }

                if let minutes =
                        workout.durationMinutes,
                   minutes > 0 {
                    heroMetric(
                        icon: "stopwatch",
                        value:
                            formatDuration(
                                minutes
                            )
                    )
                }
            }

            HStack(spacing: 8) {
                Button(action: onStart) {
                    HStack(spacing: 7) {
                        if isStarting {
                            ProgressView()
                                .controlSize(
                                    .mini
                                )
                                .tint(
                                    ATHLTHTheme
                                        .primaryText
                                )
                        } else {
                            Image(
                                systemName:
                                    "play.fill"
                            )
                            .font(
                                .system(
                                    size: 11,
                                    weight: .bold
                                )
                            )
                        }

                        Text(
                            isStarting
                                ? "Starter…"
                                : "Start økt"
                        )
                        .font(
                            .system(
                                size: 12.5,
                                weight: .bold
                            )
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .padding(
                        .horizontal,
                        15
                    )
                    .frame(height: 39)
                    .background(
                        Color.white.opacity(0.97),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(isStarting)

                Button(
                    action: onOpenPlan
                ) {
                    HStack(spacing: 5) {
                        Image(
                            systemName:
                                "calendar"
                        )
                        .font(
                            .system(
                                size: 10.5,
                                weight: .semibold
                            )
                        )

                        Text("Plan")
                            .font(
                                .system(
                                    size: 11.5,
                                    weight: .semibold
                                )
                            )
                    }
                    .foregroundStyle(.white)
                    .padding(
                        .horizontal,
                        12
                    )
                    .frame(height: 37)
                    .background(
                        Color.black
                            .opacity(0.24),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.white
                                    .opacity(0.35),
                                lineWidth: 0.7
                            )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 1)
        }
        .shadow(
            color: Color.black.opacity(0.22),
            radius: 8,
            y: 3
        )
    }

    private var quickTrainContent:
        some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text("Ingen økt planlagt i dag")
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .white.opacity(0.94)
                )

            HStack(spacing: 8) {
                quickTrainButton(
                    title: "Run",
                    icon: "figure.run",
                    tint:
                        ATHLTHTheme.vitality,
                    action: onQuickRun
                )

                quickTrainButton(
                    title: "Strength",
                    icon:
                        "dumbbell.fill",
                    tint:
                        ATHLTHTheme.accentDeep,
                    action:
                        onQuickStrength
                )
            }
        }
        .shadow(
            color: Color.black.opacity(0.18),
            radius: 7,
            y: 3
        )
    }

    private func quickTrainButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(tint)

                Text(title)
                    .font(
                        .system(
                            size: 12.5,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
            }
            .padding(.horizontal, 13)
            .frame(
                minWidth: 96,
                minHeight: 39
            )
            .background(
                Color.white.opacity(0.96),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(0.76),
                        lineWidth: 0.7
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var weatherBadge:
        some View {
        if let weather {
            VStack(
                alignment: .trailing,
                spacing: 1
            ) {
                HStack(spacing: 5) {
                    Image(
                        systemName:
                            weather.symbolName
                    )
                    .symbolRenderingMode(
                        .multicolor
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )

                    Text(
                        "\(Int(weather.temperatureCelsius.rounded()))°"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                }

                if let location =
                        weather.locationName,
                   !location.isEmpty {
                    Text(location)
                        .font(
                            .system(
                                size: 10.5,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(
                            .white.opacity(0.86)
                        )
                        .lineLimit(1)
                }
            }
            .padding(
                .horizontal,
                9
            )
            .padding(
                .vertical,
                6
            )
            .background(
                Color.black.opacity(0.16),
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
        }
    }

    private func heroMetric(
        icon: String,
        value: String
    ) -> some View {
        Label {
            Text(value)
                .font(
                    .system(
                        size: 11.5,
                        weight: .semibold
                    )
                )
        } icon: {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )
        }
        .foregroundStyle(.white)
    }

    private func formatDistance(
        _ kilometers: Double
    ) -> String {
        if kilometers.rounded() ==
            kilometers {
            return
                "\(Int(kilometers)) km"
        }

        return String(
            format: "%.1f km",
            locale: Locale.current,
            kilometers
        )
    }

    private func formatPace(
        _ seconds: Double
    ) -> String {
        let rounded =
            max(
                Int(seconds.rounded()),
                0
            )
        let minutes = rounded / 60
        let remaining = rounded % 60

        return String(
            format: "%d:%02d/km",
            minutes,
            remaining
        )
    }

    private func formatDuration(
        _ minutes: Int
    ) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainder =
            minutes % 60

        if remainder == 0 {
            return "\(hours) t"
        }

        return
            "\(hours)t \(remainder)m"
    }
}
