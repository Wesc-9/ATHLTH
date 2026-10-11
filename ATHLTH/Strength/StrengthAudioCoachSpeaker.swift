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
    private var cueQueue = ATHLTHCoachCueQueue()
    private var eventLedger = ATHLTHCoachEventLedger()
    private var latestConfiguration: StrengthAudioCoachConfiguration?

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
        event: ATHLTHCoachEvent? = nil
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
        let resolvedEvent = event ?? ATHLTHCoachEvent(
            kind: cueKind,
            key: UUID().uuidString,
            priority: .structuredStep,
            validFor: cueKind == .strengthRest ? 8 : 20
        )
        guard eventLedger.canDeliver(resolvedEvent) else {
            return
        }

        if synthesizer.isSpeaking {
            cueQueue.enqueue(
                ATHLTHCoachQueuedCue(
                    event: resolvedEvent,
                    text: text
                )
            )
            return
        }
        eventLedger.didDeliver(resolvedEvent)

        let audioSession =
            AVAudioSession.sharedInstance()
        let options:
            AVAudioSession.CategoryOptions =
                configuration.duckOtherAudio
                    ? [
                        .duckOthers,
                        .interruptSpokenAudioAndMixWithOthers
                    ]
                    : [.mixWithOthers]

        try? audioSession.setCategory(
            .playback,
            mode: .spokenAudio,
            options: options
        )
        try? audioSession.setActive(true)

        let utterance =
            AVSpeechUtterance(
                string: text
            )

        if let voiceIdentifier =
                configuration
                    .voiceIdentifier,
           let voice =
                AVSpeechSynthesisVoice(
                    identifier:
                        voiceIdentifier
                ) {
            utterance.voice = voice
        } else {
            switch configuration.language {
            case .norwegian:
                utterance.voice =
                    AVSpeechSynthesisVoice(
                        language: "nb-NO"
                    )
            case .english:
                utterance.voice =
                    AVSpeechSynthesisVoice(
                        language: "en-US"
                    )
            case .system:
                break
            }
        }

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

        synthesizer.speak(utterance)
    }

    private func deliverNextQueuedCue() {
        guard !synthesizer.isSpeaking,
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
        latestConfiguration = nil
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

    private func deactivateAudioSession() {
        ATHLTHSpokenAudioSession
            .deactivate()
    }
}
