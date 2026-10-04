import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Native iOS audio-route control used while a workout is active.
///
/// AVRoutePickerView is intentionally used instead of a custom Bluetooth
/// selector. It lets iOS own AirPods/AirPlay routing and keeps ATHLTH aligned
/// with the route the user actually selected.
struct ATHLTHAudioRouteControl: View {
    var compact: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    Color.white.opacity(
                        compact ? 0.88 : 0.92
                    )
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.black.opacity(0.05),
                            lineWidth: 0.8
                        )
                }

            ATHLTHSystemAudioRoutePicker()
                .frame(
                    width: compact ? 26 : 28,
                    height: compact ? 26 : 28
                )
        }
        .frame(
            width: compact ? 39 : 43,
            height: compact ? 39 : 43
        )
        .contentShape(Circle())
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english: "Audio output",
                norwegian: "Lydutgang"
            )
        )
        .accessibilityHint(
            ATHLTHLocalization.choose(
                english:
                    "Choose where ATHLTH Audio Coach is played.",
                norwegian:
                    "Velg hvor ATHLTH Audio Coach skal spilles."
            )
        )
    }
}

private struct ATHLTHSystemAudioRoutePicker:
    UIViewRepresentable
{
    func makeUIView(
        context: Context
    ) -> AVRoutePickerView {
        let picker =
            AVRoutePickerView(
                frame: .zero
            )
        picker.prioritizesVideoDevices =
            false
        picker.tintColor =
            UIColor.label
        picker.activeTintColor =
            UIColor(
                ATHLTHTheme.accentDeep
            )
        return picker
    }

    func updateUIView(
        _ picker: AVRoutePickerView,
        context: Context
    ) {
        picker.tintColor =
            UIColor.label
        picker.activeTintColor =
            UIColor(
                ATHLTHTheme.accentDeep
            )
    }
}

@MainActor
enum ATHLTHSpokenAudioSession {
    /// Activates an iPhone spoken-audio session without taking ownership away
    /// from Spotify or other music playback. The currently selected system
    /// route (for example AirPods) is preserved.
    static func activate(
        duckOtherAudio: Bool
    ) throws {
        let session =
            AVAudioSession.sharedInstance()

        var options:
            AVAudioSession.CategoryOptions = [
                .mixWithOthers
            ]

        if duckOtherAudio {
            options.insert(.duckOthers)
            options.insert(
                .interruptSpokenAudioAndMixWithOthers
            )
        }

        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: options
        )
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession
            .sharedInstance()
            .setActive(
                false,
                options:
                    .notifyOthersOnDeactivation
            )
    }
}
