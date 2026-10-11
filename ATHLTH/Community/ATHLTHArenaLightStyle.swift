import SwiftUI

/// Arena-specific light canvas and restrained premium surfaces.
/// Kept separate from the global app theme so other tabs are unchanged.
enum ATHLTHArenaLightStyle {
    static let canvas = Color(red: 0.975, green: 0.978, blue: 0.974)
    static let surface = Color.white
    static let ink = Color(red: 0.105, green: 0.145, blue: 0.19)
    static let secondary = Color(red: 0.42, green: 0.47, blue: 0.52)
    static let action = Color(red: 0.075, green: 0.39, blue: 0.70)

    static var canvasBackground: some View {
        LinearGradient(
            colors: [
                Color.white,
                canvas,
                Color(red: 0.955, green: 0.975, blue: 0.985)
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
                    .stroke(Color(red: 0.86, green: 0.90, blue: 0.93), lineWidth: 0.75)
            }
            .shadow(
                color: Color(red: 0.12, green: 0.28, blue: 0.38).opacity(0.045),
                radius: 14,
                y: 6
            )
    }
}
