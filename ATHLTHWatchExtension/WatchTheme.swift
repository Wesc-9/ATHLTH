import SwiftUI

enum WatchTheme {
    // Match the iPhone training-plan palette on Watch navigation surfaces.
    // These tokens are home-only: active workout metrics keep their own
    // high-contrast colours for readability during exercise.
    static let planCanvas = Color(red: 0.991, green: 0.986, blue: 0.979)
    static let planInk = Color(red: 0.18, green: 0.18, blue: 0.17)
    static let planSecondary = Color(red: 0.43, green: 0.42, blue: 0.41)
    static let planAccent = Color(red: 0.72, green: 0.55, blue: 0.31)
    static let planSelected = Color(red: 0.975, green: 0.958, blue: 0.93)
    static let planBorder = Color(red: 0.89, green: 0.87, blue: 0.84)
    static let planConnected = Color(red: 0.19, green: 0.61, blue: 0.43)

    // One visual system for all ATHLTH Watch training surfaces: warm ivory,
    // ink/slate primary actions and restrained training-plan gold.
    // The metrics-first dark running screen keeps a dark *ink* canvas for
    // outdoor legibility, not the previous unrelated neon/cyan palette.
    static let liveCanvas = Color(red: 0.090, green: 0.110, blue: 0.155)
    static let liveCyan = Color(red: 0.88, green: 0.72, blue: 0.49)
    static let liveLime = Color(red: 0.99, green: 0.94, blue: 0.83)
    static let liveHeart = Color(red: 0.93, green: 0.35, blue: 0.42)
    static let liveStrengthReps = Color(red: 0.33, green: 0.37, blue: 0.48)
    static let liveStrengthLoad = Color(red: 0.54, green: 0.43, blue: 0.30)
    static let liveAction = Color(red: 0.20, green: 0.25, blue: 0.35)

    // Gold highlights are never used as the fill behind white button text:
    // dark ink meets contrast requirements across Watch sizes.
    static let accent = Color(red: 0.25, green: 0.30, blue: 0.41)
    static let accentDeep = Color(red: 0.18, green: 0.22, blue: 0.31)
    static let accentSoft = Color(red: 0.960, green: 0.945, blue: 0.918)
    static let premiumGold = planAccent

    static let slate = Color(red: 0.36, green: 0.39, blue: 0.46)
    static let slateSoft = Color(red: 0.947, green: 0.940, blue: 0.928)

    // Retain legacy symbolic colour names for older screens, but point all
    // of them at the shared ATHLTH brand rather than green/teal.
    static let green = accent
    static let deepGreen = accentDeep

    static let canvas = planCanvas
    static let card = Color.white
    static let cardRaised = planSelected

    static let textPrimary = planInk
    static let textSecondary = planSecondary
    static let muted = Color(red: 0.50, green: 0.48, blue: 0.45)
    static let border = planBorder

    static let danger = Color(red: 0.82, green: 0.20, blue: 0.22)
    static let warning = Color(red: 0.85, green: 0.48, blue: 0.14)
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
