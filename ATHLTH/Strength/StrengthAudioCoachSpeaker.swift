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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        english: String,
        norwegian: String,
        configuration:
            StrengthAudioCoachConfiguration
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

        synthesizer.stopSpeaking(
            at: .immediate
        )

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

    func stop() {
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
            self?.deactivateAudioSession()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        ATHLTHSpokenAudioSession
            .deactivate()
    }
}
