import AVFoundation
import SwiftUI
import UIKit

/// The proof-of-concept exercise alone may use a bundled demonstration video.
/// There is no placeholder network request, autoplay in scrolling list cells,
/// or change to the normal licensed exercise catalog.
enum ATHLTHCatalogExerciseVideoAsset {
    static let squatTestIdentifier = "athlth-native-test-bodyweight-squat"

    static func resourceName(for sourceIdentifier: String?) -> String? {
        sourceIdentifier == squatTestIdentifier ? "ATHLTHTestSquat" : nil
    }

    static func localURL(for sourceIdentifier: String?) -> URL? {
        guard let resourceName = resourceName(for: sourceIdentifier) else {
            return nil
        }
        return Bundle.main.url(forResource: resourceName, withExtension: "mp4")
    }
}

/// Play a real MP4 with AVFoundation instead of assembling a choppy GIF.
/// A missing asset falls back to existing exercise artwork at the call site.
struct ATHLTHCatalogExerciseVideoView: View {
    @StateObject private var playback: Playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(url: URL) {
        _playback = StateObject(wrappedValue: Playback(url: url))
    }

    var body: some View {
        PlayerSurface(player: playback.player)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Exercise technique demonstration video",
                norwegian: "Demonstrasjonsvideo av øvelsesteknikk"
            ))
            .onAppear {
                if !reduceMotion { playback.player.play() }
            }
            .onDisappear { playback.player.pause() }
            .onChange(of: reduceMotion) { _, enabled in
                if enabled { playback.player.pause() }
                else { playback.player.play() }
            }
    }
}

@MainActor
private final class Playback: ObservableObject {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    init(url: URL) {
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .none
        player = queue
        looper = AVPlayerLooper(
            player: queue,
            templateItem: AVPlayerItem(url: url)
        )
    }

    deinit {
        player.pause()
    }
}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainer {
        let view = PlayerContainer()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainer, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class PlayerContainer: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = UIColor(white: 0.09, alpha: 1)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspectFill
    }
}
