import SwiftUI

enum WatchTheme {
    // High-contrast workout-only palette. Navigation and non-training
    // screens retain their existing light design.
    static let liveCanvas = Color(red: 0.035, green: 0.065, blue: 0.105)
    static let liveCyan = Color(red: 0.32, green: 0.87, blue: 0.98)
    static let liveLime = Color(red: 0.74, green: 0.98, blue: 0.37)
    static let liveHeart = Color(red: 1.00, green: 0.48, blue: 0.60)

    // ATHLTH Watch uses a bright Performance Tiles language. Petrol is the
    // primary action/performance colour; cool slate is reserved for secondary
    // actions so the UI stays calm and data-first.
    static let accent = Color(
        red: 0.078,
        green: 0.490,
        blue: 0.494
    )
    static let accentDeep = Color(
        red: 0.055,
        green: 0.365,
        blue: 0.388
    )
    static let accentSoft = Color(
        red: 0.875,
        green: 0.945,
        blue: 0.937
    )

    static let slate = Color(
        red: 0.278,
        green: 0.490,
        blue: 0.608
    )
    static let slateSoft = Color(
        red: 0.902,
        green: 0.937,
        blue: 0.953
    )

    // Backwards-compatible names used by the existing strength/route views.
    static let green = accent
    static let deepGreen = accentDeep

    static let canvas = Color(
        red: 0.957,
        green: 0.969,
        blue: 0.969
    )
    static let card = Color.white
    static let cardRaised = Color(
        red: 0.925,
        green: 0.945,
        blue: 0.949
    )

    static let textPrimary = Color(
        red: 0.078,
        green: 0.129,
        blue: 0.149
    )
    static let textSecondary = Color(
        red: 0.314,
        green: 0.388,
        blue: 0.420
    )
    static let muted = Color(
        red: 0.455,
        green: 0.529,
        blue: 0.557
    )
    static let border = Color(
        red: 0.855,
        green: 0.890,
        blue: 0.902
    )

    static let danger = Color(
        red: 0.82,
        green: 0.20,
        blue: 0.22
    )
    static let warning = Color(
        red: 0.86,
        green: 0.48,
        blue: 0.12
    )
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
                    lineWidth: 0.75
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
