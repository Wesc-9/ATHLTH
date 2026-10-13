import SwiftUI

/// Arena-specific light canvas and restrained premium surfaces.
/// Kept separate from the global app theme so other tabs are unchanged.
enum ATHLTHArenaLightStyle {
    // Shared editorial palette from Training Plan. All Arena surfaces use
    // these tokens, rather than introducing a competing green dashboard.
    static let paper = Color(red: 0.986, green: 0.978, blue: 0.963)
    static let canvas = paper
    static let surface = Color.white
    static let ink = Color(red: 0.18, green: 0.18, blue: 0.17)
    static let secondary = Color(red: 0.48, green: 0.46, blue: 0.43)
    static let warmGold = Color(red: 0.65, green: 0.53, blue: 0.35)
    static let soft = Color(red: 0.964, green: 0.951, blue: 0.929)
    static let line = Color(red: 0.89, green: 0.87, blue: 0.84)
    // Retain contrast on older dark competitive hero sections.
    static let action = Color(red: 0.075, green: 0.31, blue: 0.255)
    static let forest = Color(red: 0.055, green: 0.215, blue: 0.185)
    static let evergreen = Color(red: 0.105, green: 0.385, blue: 0.31)

    static func editorialTitle(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static var eyebrow: Font {
        .system(size: 10, weight: .semibold)
    }

    static var canvasBackground: some View {
        LinearGradient(
            colors: [
                Color.white,
                paper,
                soft
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
                    .stroke(line, lineWidth: 0.8)
            }
            .shadow(
                color: ink.opacity(0.045),
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
