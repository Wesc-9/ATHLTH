import SwiftUI

enum WatchTheme {
    static let green = Color(red: 0.10, green: 0.62, blue: 0.36)
    static let deepGreen = Color(red: 0.05, green: 0.48, blue: 0.27)
    static let canvas = Color(red: 0.965, green: 0.972, blue: 0.958)
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
