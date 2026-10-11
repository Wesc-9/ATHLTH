import SwiftUI

/// Arena-specific light canvas and restrained premium surfaces.
/// Kept separate from the global app theme so other tabs are unchanged.
enum ATHLTHArenaLightStyle {
    static let canvas = Color(red: 0.976, green: 0.979, blue: 0.968)
    static let surface = Color.white
    static let ink = Color(red: 0.105, green: 0.18, blue: 0.16)
    static let secondary = Color(red: 0.40, green: 0.46, blue: 0.43)
    static let action = Color(red: 0.075, green: 0.31, blue: 0.255)
    static let forest = Color(red: 0.055, green: 0.215, blue: 0.185)
    static let evergreen = Color(red: 0.105, green: 0.385, blue: 0.31)

    static var canvasBackground: some View {
        LinearGradient(
            colors: [
                Color.white,
                canvas,
                Color(red: 0.950, green: 0.969, blue: 0.956)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    static func card(_ cornerRadius: CGFloat = 22) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(surface)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(red: 0.83, green: 0.89, blue: 0.85), lineWidth: 0.8)
            }
            .shadow(
                color: forest.opacity(0.055),
                radius: 16,
                y: 7
            )
    }

    /// A consistent premium accent surface for Arena entry points and
    /// competition headers. Decorations are clipped and noninteractive.
    static func heroSurface(_ cornerRadius: CGFloat = 26) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [forest, action, evergreen],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: 190, height: 190)
                    .offset(x: 65, y: -85)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.045))
                    .frame(width: 132, height: 132)
                    .offset(x: 37, y: 49)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: forest.opacity(0.13), radius: 18, y: 9)
    }
}
