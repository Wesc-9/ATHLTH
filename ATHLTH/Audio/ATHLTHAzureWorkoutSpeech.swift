import AVFoundation
import Foundation
import Supabase

/// IDs travel through existing optional voiceIdentifier fields without
/// changing Watch transfer Codable models. Watch always uses Apple TTS.
enum ATHLTHAzureCoachVoice {
    static let prefix = "azure:"
    static let supported: [String] = ["finn", "iselin", "pernille"]

    static func key(_ identifier: String?) -> String? {
        guard let identifier, identifier.hasPrefix(prefix) else {
            return nil
        }
        let value = String(identifier.dropFirst(prefix.count))
        if supported.contains(value) { return value }
        // New Norwegian neural voices are verified against Azure's live voice
        // directory on the server. Accept only safe, full Azure ShortNames.
        let range = value.range(
            of: #"^nb-NO-[A-Za-z0-9]+Neural$"#,
            options: .regularExpression
        )
        return range != nil ? value : nil
    }

    static var consentGranted: Bool {
        UserDefaults.standard.bool(
            forKey: "settings.audioCoach.azureThirdPartyConsent"
        )
    }
}

/// Best-effort remote TTS for iPhone Quick Train. On errors, offline/denied
/// access, 3.5s latency or exhausted F0 budget, the caller speaks locally.
/// It never blocks workout capture, watches, haptics or Spotify controls.
@MainActor
final class ATHLTHAzureWorkoutSpeech:
    NSObject, AVAudioPlayerDelegate
{
    private struct Request: Encodable {
        let voice: String
        let text: String
    }
    private struct Reply: Decodable {
        let voice: String
        let audioBase64: String
    }

    private var audio: AVAudioPlayer?
    private let audioOwner = "azure-\(UUID().uuidString)"

    private var requestTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var identity = UUID()
    private var finishHandler: (() -> Void)?
    private var fallbackHandler: (() -> Void)?
    private(set) var isBusy = false
    private var ownsAudioSession = false
    private var consecutiveFailures = 0
    private var retryAfter: Date?

    @discardableResult
    func begin(
        _ phrase: String,
        voiceIdentifier: String?,
        duckMusic: Bool,
        onFallback: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) -> Bool {
        guard let key = ATHLTHAzureCoachVoice.key(voiceIdentifier),
              ATHLTHAzureCoachVoice.consentGranted,
              consecutiveFailures < 3,
              (retryAfter == nil || Date() >= retryAfter!),
              !phrase.isEmpty,
              phrase.count <= 220,
              !isBusy
        else { return false }

        identity = UUID()
        let generation = identity
        isBusy = true
        fallbackHandler = onFallback
        finishHandler = onFinished

        // Never wait for an external service before giving workout feedback.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5.0))
            guard !Task.isCancelled else { return }
            self?.fallback(generation)
        }

        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response: Reply = try await
                    SupabaseEnvironment.client.functions.invoke(
                        "azure-coach-voice",
                        options: FunctionInvokeOptions(
                            body: Request(voice: key, text: phrase)
                        )
                    )
                guard self.identity == generation,
                      !Task.isCancelled,
                      response.voice == key,
                      let data = Data(base64Encoded: response.audioBase64),
                      !data.isEmpty,
                      data.count <= 250_000
                else {
                    self.fallback(generation)
                    return
                }

                let player = try AVAudioPlayer(data: data)
                guard self.identity == generation else { return }
                do {
                    try ATHLTHSpokenAudioSession.activate(
                        duckOtherAudio: duckMusic,
                        owner: audioOwner
                    )
                    self.ownsAudioSession = true
                    player.delegate = self
                    guard player.prepareToPlay(), player.play() else {
                        self.fallback(generation)
                        return
                    }
                    self.audio = player
                    self.consecutiveFailures = 0
                    self.retryAfter = nil
                    self.timeoutTask?.cancel()
                    self.requestTask = nil
                    // Some Bluetooth routes omit AVAudioPlayer's finish
                    // callback after an interruption. Always release the
                    // music lease even if the delegate never fires.
                    self.timeoutTask = Task { [weak self] in
                        let seconds = min(max(player.duration + 4, 6), 70)
                        try? await Task.sleep(for: .seconds(seconds))
                        guard !Task.isCancelled,
                              let self,
                              self.identity == generation,
                              self.audio === player
                        else { return }
                        let done = self.finishHandler
                        self.cleanup()
                        done?()
                    }
                } catch {
                    self.fallback(generation)
                }
            } catch {
                self.fallback(generation)
            }
        }
        return true
    }

    private func fallback(_ generation: UUID) {
        guard identity == generation, isBusy else { return }
        // Transient cold starts should not disable the chosen voice for the
        // entire session. Retry at most twice with a short backoff.
        consecutiveFailures += 1
        retryAfter = Date().addingTimeInterval(30 * Double(consecutiveFailures))
        let callback = fallbackHandler
        cleanup()
        callback?()
    }

    func stop() {
        cleanup()
    }

    private func cleanup() {
        identity = UUID()
        requestTask?.cancel()
        timeoutTask?.cancel()
        requestTask = nil
        timeoutTask = nil
        audio?.stop()
        audio = nil
        if ownsAudioSession {
            ATHLTHSpokenAudioSession.deactivate(owner: audioOwner)
            ownsAudioSession = false
        }
        isBusy = false
        fallbackHandler = nil
        finishHandler = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.audio === player else { return }
            let callback = self.finishHandler
            self.cleanup()
            callback?()
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer, error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.audio === player else { return }
            let callback = self.finishHandler
            self.cleanup()
            callback?()
        }
    }

}
