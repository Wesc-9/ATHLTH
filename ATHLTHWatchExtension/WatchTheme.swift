import SwiftUI

enum WatchTheme {
    // Watch is intentionally dark-first: OLED friendly, high contrast and
    // independent of the user's iPhone appearance.
    static let accent = Color(
        red: 0.70,
        green: 0.95,
        blue: 0.56
    )
    static let accentDeep = Color(
        red: 0.39,
        green: 0.66,
        blue: 0.30
    )

    // Backwards-compatible names used by the existing strength/route views.
    static let green = accent
    static let deepGreen = accentDeep

    static let canvas = Color.black
    static let card = Color(
        red: 0.075,
        green: 0.082,
        blue: 0.092
    )
    static let cardRaised = Color(
        red: 0.11,
        green: 0.12,
        blue: 0.135
    )

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let muted = Color.white.opacity(0.52)
    static let border = Color.white.opacity(0.09)
    static let danger = Color(
        red: 1.0,
        green: 0.28,
        blue: 0.26
    )
    static let warning = Color.orange
}

struct WatchSurfaceModifier: ViewModifier {
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .foregroundStyle(WatchTheme.textPrimary)
            .background(
                WatchTheme.card,
                in: RoundedRectangle(
                    cornerRadius: radius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: radius,
                    style: .continuous
                )
                .stroke(
                    WatchTheme.border,
                    lineWidth: 1
                )
            }
    }
}

extension View {
    func watchSurface(
        radius: CGFloat = 18
    ) -> some View {
        modifier(
            WatchSurfaceModifier(radius: radius)
        )
    }
}
