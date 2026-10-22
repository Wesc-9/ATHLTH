import AVFoundation
import Combine
import Foundation

@MainActor
final class StrengthAudioCoachSpeaker:
    NSObject,
    ObservableObject,
    AVSpeechSynthesizerDelegate
{
    private let synthesizer =
        AVSpeechSynthesizer()
    private let azureSpeech = ATHLTHAzureWorkoutSpeech()
    private let audioOwner = "strength-\(UUID().uuidString)"
    private var cueQueue = ATHLTHCoachCueQueue()
    private var eventLedger = ATHLTHCoachEventLedger()
    private var latestConfiguration: StrengthAudioCoachConfiguration?
    private var replayMemory = ATHLTHCoachReplayMemory()

    @Published private(set) var speechPaused = false
    @Published private(set) var lastCoachMessage: String?

    var canReplayLastMessage: Bool {
        latestConfiguration?.enabled == true &&
        !speechPaused &&
        replayMemory.replayableText() != nil
    }

    /// Mutes strength speech only. Recording, rest timers and Watch haptics
    /// run independently and are never touched by this temporary setting.
    func setSpeechPaused(_ paused: Bool) {
        guard latestConfiguration?.enabled == true else {
            speechPaused = false
            return
        }
        guard speechPaused != paused else { return }
        speechPaused = paused
        cueQueue.reset()
        if paused {
            azureSpeech.stop()
            synthesizer.stopSpeaking(at: .immediate)
            deactivateAudioSession()
        }
    }

    func replayLastMessage() {
        guard canReplayLastMessage,
              let text = replayMemory.replayableText(),
              let configuration = latestConfiguration
        else { return }
        speak(
            english: text,
            norwegian: text,
            configuration: configuration,
            rememberForReplay: false
        )
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        english: String,
        norwegian: String,
        configuration:
            StrengthAudioCoachConfiguration,
        cueKind: ATHLTHCoachEventKind = .strengthSet,
        event: ATHLTHCoachEvent? = nil,
        rememberForReplay: Bool = true
    ) {
        guard configuration.enabled else {
            return
        }

        let text: String
        switch configuration.language {
        case .norwegian:
            text = norwegian
        case .english:
            text = english
        case .system:
            let languageCode =
                Locale.autoupdatingCurrent
                    .language
                    .languageCode?
                    .identifier
                    .lowercased()
            text =
                languageCode == "nb" ||
                languageCode == "nn" ||
                languageCode == "no"
                    ? norwegian
                    : english
        }

        guard !text.isEmpty else {
            return
        }

        latestConfiguration = configuration
        guard !speechPaused else { return }

        let resolvedEvent = event ?? ATHLTHCoachEvent(
            kind: cueKind,
            key: UUID().uuidString,
            priority: .structuredStep,
            validFor: cueKind == .strengthRest ? 8 : 20
        )
        guard eventLedger.canDeliver(resolvedEvent) else {
            return
        }

        if synthesizer.isSpeaking || azureSpeech.isBusy {
            cueQueue.enqueue(
                ATHLTHCoachQueuedCue(
                    event: resolvedEvent,
                    text: text
                )
            )
            return
        }
        eventLedger.didDeliver(resolvedEvent)

        let spokenText = rememberForReplay
            ? (configuration.speechStyle ?? .balanced).render(
                text,
                language: configuration.language,
                priority: .structuredStep,
                eventKind: resolvedEvent.kind
            )
            : text
        let utterance =
            AVSpeechUtterance(
                string: spokenText
            )

        // Use the highest-quality installed voice for this language unless
        // the athlete selected a specific speaker.
        utterance.voice = ATHLTHCoachPreferredSystemVoice.resolve(
            selectedIdentifier: configuration.voiceIdentifier,
            language: configuration.language
        )

        utterance.rate =
            Float(
                min(
                    max(
                        configuration
                            .speechRate,
                        0.35
                    ),
                    0.65
                )
            )
        utterance.volume =
            Float(
                min(
                    max(
                        configuration
                            .speechVolume,
                        0.2
                    ),
                    1
                )
            )

        let routedToAzure = azureSpeech.begin(
            spokenText,
            voiceIdentifier: configuration.voiceIdentifier,
            duckMusic: configuration.duckOtherAudio,
            onFallback: { [weak self] in
                guard let self, !self.speechPaused,
                      self.latestConfiguration?.enabled == true
                else { return }
                self.activateLocalAudio(duck: configuration.duckOtherAudio)
                self.synthesizer.speak(utterance)
            },
            onFinished: { [weak self] in
                self?.deliverNextQueuedCue()
            }
        )
        if !routedToAzure {
            activateLocalAudio(duck: configuration.duckOtherAudio)
            synthesizer.speak(utterance)
        }
        if rememberForReplay {
            replayMemory.remember(spokenText, priority: .structuredStep)
            lastCoachMessage = replayMemory.text
        }
    }

    private func deliverNextQueuedCue() {
        guard !synthesizer.isSpeaking,
              !azureSpeech.isBusy,
              let configuration = latestConfiguration,
              configuration.enabled,
              let next = cueQueue.popNext()
        else { return }

        speak(
            english: next.text,
            norwegian: next.text,
            configuration: configuration,
            cueKind: next.event.kind,
            event: next.event
        )
    }

    func stop() {
        cueQueue.reset()
        eventLedger.reset()
        replayMemory.reset()
        lastCoachMessage = nil
        speechPaused = false
        latestConfiguration = nil
        azureSpeech.stop()
        synthesizer.stopSpeaking(
            at: .immediate
        )
        deactivateAudioSession()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.synthesizer.isSpeaking
            else { return }
            self.deactivateAudioSession()
            self.deliverNextQueuedCue()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.synthesizer.isSpeaking
            else { return }
            self.deactivateAudioSession()
            self.deliverNextQueuedCue()
        }
    }

    private func activateLocalAudio(duck: Bool) {
        try? ATHLTHSpokenAudioSession.activate(duckOtherAudio: duck, owner: audioOwner)
    }

    private func deactivateAudioSession() {
        ATHLTHSpokenAudioSession
            .deactivate(owner: audioOwner)
    }
}
