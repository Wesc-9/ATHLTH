import SwiftUI

enum OnboardingTheme {
    static let green = Color(red: 0.12, green: 0.61, blue: 0.34)
    static let brightGreen = Color(red: 0.20, green: 0.72, blue: 0.42)
    static let deepGreen = Color(red: 0.035, green: 0.39, blue: 0.22)

    static let canvas = Color(red: 0.973, green: 0.969, blue: 0.944)
    static let canvasGreen = Color(red: 0.925, green: 0.958, blue: 0.925)
    static let card = Color.white.opacity(0.88)
    static let elevatedCard = Color.white.opacity(0.96)

    static let ink = Color(red: 0.055, green: 0.065, blue: 0.058)
    static let mutedInk = Color(red: 0.39, green: 0.41, blue: 0.39)
    static let border = Color.black.opacity(0.055)

    static let screenHorizontalPadding: CGFloat = 22
    static let cardRadius: CGFloat = 26
    static let buttonRadius: CGFloat = 18
}

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            OnboardingTheme.canvas

            LinearGradient(
                colors: [
                    Color.white.opacity(0.95),
                    OnboardingTheme.canvas.opacity(0.98),
                    OnboardingTheme.canvasGreen.opacity(0.66),
                    Color.white.opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(OnboardingTheme.green.opacity(0.085))
                .frame(width: 360, height: 360)
                .blur(radius: 34)
                .offset(x: -160, y: 240)

            Circle()
                .fill(Color.white.opacity(0.78))
                .frame(width: 330, height: 330)
                .blur(radius: 18)
                .offset(x: 180, y: -260)

            RadialGradient(
                colors: [
                    Color.white.opacity(0.72),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 420
            )
        }
    }
}

struct OnboardingHeroArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            OnboardingTheme.canvasGreen.opacity(0.93)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)

            Circle()
                .fill(OnboardingTheme.green.opacity(0.10))
                .frame(width: 190, height: 190)
                .offset(x: -112, y: 60)

            Circle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 150, height: 150)
                .offset(x: 130, y: -56)

            routeArtwork

            VStack {
                HStack {
                    metricPill(
                        icon: "heart.fill",
                        value: "142",
                        suffix: "BPM"
                    )

                    Spacer()

                    metricPill(
                        icon: "figure.run",
                        value: "5.2",
                        suffix: "KM"
                    )
                }

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ATHLTH")
                            .font(.caption2.weight(.bold))
                            .tracking(2.2)
                            .foregroundStyle(OnboardingTheme.deepGreen)

                        Text("Move better.")
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(OnboardingTheme.ink)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.90))
                            .frame(width: 62, height: 62)
                            .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)

                        Image(systemName: "figure.run")
                            .font(.system(size: 29, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.green)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .shadow(
            color: OnboardingTheme.deepGreen.opacity(0.10),
            radius: 24,
            x: 0,
            y: 14
        )
        .accessibilityHidden(true)
    }

    private var routeArtwork: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height

                path.move(to: CGPoint(x: width * 0.20, y: height * 0.65))
                path.addCurve(
                    to: CGPoint(x: width * 0.48, y: height * 0.43),
                    control1: CGPoint(x: width * 0.30, y: height * 0.72),
                    control2: CGPoint(x: width * 0.37, y: height * 0.37)
                )
                path.addCurve(
                    to: CGPoint(x: width * 0.79, y: height * 0.55),
                    control1: CGPoint(x: width * 0.60, y: height * 0.49),
                    control2: CGPoint(x: width * 0.68, y: height * 0.33)
                )
            }
            .stroke(
                LinearGradient(
                    colors: [
                        OnboardingTheme.green.opacity(0.24),
                        OnboardingTheme.green.opacity(0.78)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(
                    lineWidth: 5,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [4, 10]
                )
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
    }

    private func metricPill(
        icon: String,
        value: String,
        suffix: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OnboardingTheme.green)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingTheme.ink)

            Text(suffix)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(OnboardingTheme.mutedInk)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.white.opacity(0.88), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
    }
}

struct OnboardingSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                OnboardingTheme.card,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.94),
                                OnboardingTheme.border
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: Color.black.opacity(0.045),
                radius: 20,
                x: 0,
                y: 10
            )
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(minHeight: 56)
            .background(
                LinearGradient(
                    colors: [
                        OnboardingTheme.brightGreen.opacity(configuration.isPressed ? 0.78 : 0.96),
                        OnboardingTheme.deepGreen.opacity(configuration.isPressed ? 0.84 : 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(
                    cornerRadius: OnboardingTheme.buttonRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: OnboardingTheme.buttonRadius,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(
                color: OnboardingTheme.deepGreen.opacity(configuration.isPressed ? 0.08 : 0.20),
                radius: configuration.isPressed ? 7 : 14,
                x: 0,
                y: 8
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct OnboardingCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(
            OnboardingSurfaceModifier(
                cornerRadius: OnboardingTheme.cardRadius
            )
        )
    }
}

extension View {
    func onboardingSurface(
        cornerRadius: CGFloat = OnboardingTheme.cardRadius
    ) -> some View {
        modifier(OnboardingSurfaceModifier(cornerRadius: cornerRadius))
    }
}
