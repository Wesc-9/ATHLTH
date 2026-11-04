import SwiftUI

/// iPad Studio changes only presentation, never the workout's draft,
/// validation, exercise library or AppSessionStore persistence.
private struct ATHLTHStudioFullscreenEditingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var athlthStudioFullscreenEditing: Bool {
        get { self[ATHLTHStudioFullscreenEditingKey.self] }
        set { self[ATHLTHStudioFullscreenEditingKey.self] = newValue }
    }
}

extension View {
    /// Present the exact same iPhone/Watch-aware editor on both devices.
    /// iPhone keeps its existing sheet; Studio on iPad uses a full-screen
    /// workspace. Never copy the editing or save implementation.
    @ViewBuilder
    func athlthStudioEditor<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        useFullScreen: Bool,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Destination
    ) -> some View {
        if useFullScreen {
            fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        } else {
            sheet(item: item, onDismiss: onDismiss, content: content)
        }
    }
}
