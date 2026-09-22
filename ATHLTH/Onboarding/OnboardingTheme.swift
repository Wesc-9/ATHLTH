import SwiftUI

enum OnboardingTheme {
    static let accent = Color(red: 0.78, green: 0.58, blue: 0.37)
    static let success = Color(red: 0.34, green: 0.56, blue: 0.43)

    static let green = success
    static let deepGreen = Color(red: 0.23, green: 0.50, blue: 0.34)
    static let warmHighlight = accent

    static let canvasTop = Color.white
    static let canvasBottom = Color(red: 0.985, green: 0.980, blue: 0.970)
    static let primaryText = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let mutedText = Color.black.opacity(0.58)
    static let faintText = Color.black.opacity(0.40)

    static let card = Color.white
    static let cardStrong = Color.white
    static let subtleFill = Color.black.opacity(0.035)
    static let selectedFill = accent.opacity(0.095)
    static let border = Color.black.opacity(0.075)
    static let strongBorder = Color.black.opacity(0.12)
}

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OnboardingTheme.canvasTop,
                    Color.white,
                    OnboardingTheme.canvasBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    OnboardingTheme.accent.opacity(0.065),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 15,
                endRadius: 430
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
            .background(
                OnboardingTheme.card,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(OnboardingTheme.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.055), radius: 20, x: 0, y: 10)
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
                OnboardingTheme.primaryText.opacity(configuration.isPressed ? 0.78 : 0.98),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func onboardingSurface(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(
                OnboardingTheme.card,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(OnboardingTheme.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.055), radius: 18, x: 0, y: 9)
    }
}
