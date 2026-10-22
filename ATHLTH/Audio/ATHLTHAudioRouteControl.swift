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
    // Several independent speakers can coexist: a Watch mirror, local phone
    // workout, strength coach and Azure fallback. One speaker must never
    // unduck another speaker's active cue. Owners identify an active voice,
    // not a workout; only release your own lease.
    private static var owners: [String: Bool] = [:]
    private static var revision = 0
    private static var delayedRestoreTask: Task<Void, Never>?

    static func activate(
        duckOtherAudio: Bool,
        owner: String = "legacy"
    ) throws {
        let session = AVAudioSession.sharedInstance()
        delayedRestoreTask?.cancel()
        delayedRestoreTask = nil

        let previous = owners[owner]
        owners[owner] = duckOtherAudio

        do {
            try configure(session)
            revision += 1
        } catch {
            if let previous {
                owners[owner] = previous
            } else {
                owners.removeValue(forKey: owner)
            }
            if owners.isEmpty {
                try? session.setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            }
            throw error
        }
    }

    private static func configure(_ session: AVAudioSession) throws {
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if owners.values.contains(true) {
            options.insert(.duckOthers)
            options.insert(.interruptSpokenAudioAndMixWithOthers)
        }

        // Spotify/AirPods can reject spokenAudio during handoff. Retry
        // playback without dropping our mix/duck preference.
        do {
            try session.setCategory(
                .playback, mode: .spokenAudio, options: options
            )
            try session.setActive(true)
        } catch {
            try session.setCategory(
                .playback, mode: .default, options: options
            )
            try session.setActive(true)
        }
    }

    static func deactivate(owner: String = "legacy") {
        guard owners.removeValue(forKey: owner) != nil else { return }
        revision += 1

        if !owners.isEmpty {
            // If the last ducking owner finished but a mixing voice remains,
            // remove .duckOthers without deactivating that remaining voice.
            try? configure(AVAudioSession.sharedInstance())
            return
        }

        restoreIfIdle(generation: revision)
    }

    private static func restoreIfIdle(generation: Int) {
        guard owners.isEmpty, generation == revision else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(
                false, options: .notifyOthersOnDeactivation
            )
            delayedRestoreTask?.cancel()
            delayedRestoreTask = nil
        } catch {
            // iOS can transiently reject deactivation during an AirPods
            // route handoff or interruption. Retry only while still idle;
            // a newly started voice invalidates the pending restoration.
            delayedRestoreTask?.cancel()
            delayedRestoreTask = Task { @MainActor in
                for _ in 0..<4 {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled,
                          owners.isEmpty, revision == generation
                    else { return }
                    do {
                        try session.setActive(
                            false, options: .notifyOthersOnDeactivation
                        )
                        delayedRestoreTask = nil
                        return
                    } catch {
                        continue
                    }
                }
                delayedRestoreTask = nil
            }
        }
    }
}
