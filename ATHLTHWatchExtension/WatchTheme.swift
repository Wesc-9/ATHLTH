import SwiftUI

enum WatchTheme {
    static let accent = Color(red: 0.29, green: 0.34, blue: 0.43)
    static let accentDeep = Color(red: 0.20, green: 0.24, blue: 0.31)
    static let green = accent
    static let deepGreen = accentDeep
    static let canvas = Color(red: 0.968, green: 0.964, blue: 0.958)
    static let card = Color.white.opacity(0.94)
    static let muted = Color(red: 0.38, green: 0.43, blue: 0.50)
    static let border = Color.black.opacity(0.055)
}

struct WatchSurfaceModifier: ViewModifier {
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                WatchTheme.card,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(WatchTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func watchSurface(radius: CGFloat = 18) -> some View {
        modifier(WatchSurfaceModifier(radius: radius))
    }
}
