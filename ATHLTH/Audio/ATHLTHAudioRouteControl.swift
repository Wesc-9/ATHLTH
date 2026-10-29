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
    private static var ownerExpiryTasks: [String: Task<Void, Never>] = [:]
    private static var ownerGenerations: [String: UUID] = [:]
    private static var routeObserver: NSObjectProtocol?
    private static var interruptionObserver: NSObjectProtocol?

    /// iOS may decline deactivation while AirPods / Spotify change routes.
    /// Keep a retry trigger registered for as long as a voice is ever used.
    private static func installRestorationObserversIfNeeded() {
        if routeObserver == nil {
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { _ in
                Task { @MainActor in
                    guard owners.isEmpty else { return }
                    restoreIfIdle(generation: revision)
                }
            }
        }
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { event in
                // Do not race Apple's interruption start. Retry after it ends.
                guard let raw = event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended
                else { return }
                Task { @MainActor in
                    guard owners.isEmpty else { return }
                    restoreIfIdle(generation: revision)
                }
            }
        }
    }

    static func activate(
        duckOtherAudio: Bool,
        owner: String = "legacy"
    ) throws {
        installRestorationObserversIfNeeded()
        let session = AVAudioSession.sharedInstance()
        delayedRestoreTask?.cancel()
        delayedRestoreTask = nil

        let previous = owners[owner]
        owners[owner] = duckOtherAudio

        do {
            try configure(session)
            revision += 1
            ownerExpiryTasks[owner]?.cancel()
            let generation = UUID()
            ownerGenerations[owner] = generation
            // A system speech delegate can occasionally fail to return
            // after a route change. A short cue cannot own ducking forever.
            ownerExpiryTasks[owner] = Task { @MainActor in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled,
                      ownerGenerations[owner] == generation
                else { return }
                deactivate(owner: owner)
            }
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
        ownerExpiryTasks.removeValue(forKey: owner)?.cancel()
        ownerGenerations.removeValue(forKey: owner)
        revision += 1

        if !owners.isEmpty {
            // When a ducking voice ends while a non-ducking voice still
            // speaks, reconfigure without .duckOthers. iOS may reject this
            // during a Bluetooth handoff, so retry without interrupting the
            // remaining speaker.
            reconfigureRemainingOwners(generation: revision)
            return
        }

        restoreIfIdle(generation: revision)
    }

    private static func reconfigureRemainingOwners(generation: Int) {
        delayedRestoreTask?.cancel()
        delayedRestoreTask = nil
        do {
            try configure(AVAudioSession.sharedInstance())
        } catch {
            delayedRestoreTask = Task { @MainActor in
                // Retry while active, but only for the matching voice
                // generation; never override a newer coach lease.
                for _ in 0..<18 {
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                    guard !Task.isCancelled,
                          !owners.isEmpty,
                          revision == generation else { return }
                    do {
                        try configure(AVAudioSession.sharedInstance())
                        delayedRestoreTask = nil
                        return
                    } catch { continue }
                }
                delayedRestoreTask = nil
            }
        }
    }

    private static func restoreIfIdle(generation: Int) {
        guard owners.isEmpty, generation == revision else { return }
        delayedRestoreTask?.cancel()
        delayedRestoreTask = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // When iOS rejects deactivation during a Bluetooth/Spotify route
            // handoff, remove duckOthers first. Otherwise the music can
            // remain quiet until the asynchronous deactivation finally works.
            // This is only safe with no remaining speech owners.
            try? session.setCategory(
                .playback, mode: .default, options: [.mixWithOthers]
            )
            // Retry notifyOthersOnDeactivation without interrupting a new cue.
            delayedRestoreTask = Task { @MainActor in
                let delays: [Duration] = [
                    .milliseconds(150),
                    .milliseconds(300),
                    .milliseconds(500),
                    .seconds(1), .seconds(2), .seconds(3),
                    .seconds(5), .seconds(5), .seconds(5),
                    .seconds(8)
                ]
                for delay in delays {
                    do {
                        try await Task.sleep(for: delay)
                    } catch { return }
                    guard !Task.isCancelled,
                          owners.isEmpty,
                          revision == generation else { return }

                    do {
                        try session.setActive(
                            false,
                            options: .notifyOthersOnDeactivation
                        )
                        delayedRestoreTask = nil
                        return
                    } catch {
                        continue
                    }
                }
                // Bluetooth can stay in a failed handoff for longer than
                // this initial retry window. Continue at low frequency until
                // iOS accepts notifyOthersOnDeactivation or a new voice starts.
                while !Task.isCancelled,
                      owners.isEmpty,
                      revision == generation {
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return }
                    guard !Task.isCancelled,
                          owners.isEmpty,
                          revision == generation else { return }
                    do {
                        try session.setActive(
                            false, options: .notifyOthersOnDeactivation
                        )
                        delayedRestoreTask = nil
                        return
                    } catch { continue }
                }
                delayedRestoreTask = nil
            }
        }
    }
}
