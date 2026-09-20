import SwiftUI

enum OnboardingTheme {
    static let green = Color(red: 0.10, green: 0.62, blue: 0.36)
    static let deepGreen = Color(red: 0.05, green: 0.48, blue: 0.27)
    static let canvas = Color(red: 0.965, green: 0.972, blue: 0.958)
    static let card = Color.white.opacity(0.92)
    static let border = Color.black.opacity(0.055)
}

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            OnboardingTheme.canvas

            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    Color.green.opacity(0.035),
                    Color.blue.opacity(0.025),
                    Color.white.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.82),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
        }
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
                    .stroke(OnboardingTheme.border, lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(0.045),
                radius: 18,
                x: 0,
                y: 8
            )
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        OnboardingTheme.green.opacity(configuration.isPressed ? 0.78 : 0.88),
                        OnboardingTheme.deepGreen.opacity(configuration.isPressed ? 0.82 : 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(
                color: OnboardingTheme.green.opacity(configuration.isPressed ? 0.08 : 0.18),
                radius: configuration.isPressed ? 7 : 13,
                x: 0,
                y: 7
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(OnboardingSurfaceModifier(cornerRadius: 22))
    }
}

extension View {
    func onboardingSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(OnboardingSurfaceModifier(cornerRadius: cornerRadius))
    }
}
