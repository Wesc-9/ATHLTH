import SwiftUI

enum OnboardingTheme {
    static let green = Color(red: 0.43, green: 0.72, blue: 0.52)
    static let deepGreen = Color(red: 0.23, green: 0.50, blue: 0.34)
    static let warmHighlight = Color(red: 0.88, green: 0.69, blue: 0.48)

    static let canvasTop = Color(red: 0.12, green: 0.105, blue: 0.095)
    static let canvasBottom = Color(red: 0.035, green: 0.035, blue: 0.035)
    static let card = Color.white.opacity(0.10)
    static let cardStrong = Color.white.opacity(0.16)
    static let border = Color.white.opacity(0.15)
    static let mutedText = Color.white.opacity(0.66)
    static let faintText = Color.white.opacity(0.42)
}

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OnboardingTheme.canvasTop,
                    Color(red: 0.075, green: 0.067, blue: 0.061),
                    OnboardingTheme.canvasBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    OnboardingTheme.warmHighlight.opacity(0.13),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 430
            )

            RadialGradient(
                colors: [
                    OnboardingTheme.green.opacity(0.07),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 360
            )
        }
    }
}

struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(
                OnboardingTheme.card,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(OnboardingTheme.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                Color.black.opacity(configuration.isPressed ? 0.76 : 0.94),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.20), radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
