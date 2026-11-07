import AVFoundation
import SwiftUI

private struct ATHLTHAudioCoachVoiceOption:
    Identifiable,
    Hashable
{
    let id: String
    let name: String
    let language: String
    let qualityRank: Int

    var qualityTitle: String? {
        switch qualityRank {
        case 3...:
            return ATHLTHLocalization.choose(
                english: "Premium",
                norwegian: "Premium"
            )
        case 2:
            return ATHLTHLocalization.choose(
                english: "Enhanced",
                norwegian: "Forbedret"
            )
        default:
            return nil
        }
    }

    var displayTitle: String {
        if let qualityTitle {
            return "\(name) · \(qualityTitle)"
        }

        return name
    }

    var compactTitle: String {
        if let qualityTitle {
            return "\(name) · \(qualityTitle)"
        }

        return name
    }
}

@MainActor
private final class ATHLTHAudioCoachPreviewSpeaker:
    NSObject,
    AVSpeechSynthesizerDelegate
{
    static let shared =
        ATHLTHAudioCoachPreviewSpeaker()

    private let synthesizer =
        AVSpeechSynthesizer()
    private let audioOwner = "audio-coach-preview-\(UUID().uuidString)"
    private var restorationWatchdog: Task<Void, Never>?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        language: WatchAudioCoachLanguage,
        voiceIdentifier: String?,
        speechRate: Double,
        speechVolume: Double,
        duckOtherAudio: Bool,
        speechStyle: ATHLTHCoachSpeechStyle
    ) {
        restorationWatchdog?.cancel()
        restorationWatchdog = nil
        synthesizer.stopSpeaking(
            at: .immediate
        )

        try? ATHLTHSpokenAudioSession.activate(
            duckOtherAudio: duckOtherAudio,
            owner: audioOwner
        )

        let useNorwegian: Bool
        switch language {
        case .norwegian:
            useNorwegian = true
        case .english:
            useNorwegian = false
        case .system:
            let code =
                Locale.autoupdatingCurrent
                    .language
                    .languageCode?
                    .identifier
                    .lowercased()
            useNorwegian =
                code == "nb" ||
                code == "nn" ||
                code == "no"
        }

        // Sample data only: preview exactly how the chosen wording
        // sounds without reading personal HealthKit workout measurements.
        let sample: String
        if speechStyle == .motivating {
            sample = useNorwegian
                ? "Du er godt i gang. Hold fokus på neste drag, du har dette!"
                : "You're making progress. Focus on the next interval, you've got this!"
        } else {
            sample = useNorwegian
                ? "Distanse 2 kilometer. Tid 12 minutter."
                : "Distance 2 kilometers. Time 12 minutes."
        }
        let preview = speechStyle.render(
            sample,
            language: language,
            priority: .routineCoach,
            eventKind: .routineMilestone
        )
        let utterance = AVSpeechUtterance(string: preview)

        utterance.voice = ATHLTHCoachPreferredSystemVoice.resolve(
            selectedIdentifier: voiceIdentifier,
            language: language
        )

        utterance.rate =
            Float(
                min(
                    max(
                        speechRate,
                        0.35
                    ),
                    0.65
                )
            )
        utterance.volume =
            Float(
                min(
                    max(
                        speechVolume,
                        0.2
                    ),
                    1.0
                )
            )
        synthesizer.speak(utterance)
        restorationWatchdog = Task { @MainActor [weak self] in
            let seconds = max(12, min(40, Double(preview.count) / 8 + 10))
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.synthesizer.stopSpeaking(at: .immediate)
            ATHLTHSpokenAudioSession.deactivate(owner: self.audioOwner)
            self.restorationWatchdog = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            self.restorationWatchdog?.cancel()
            self.restorationWatchdog = nil
            ATHLTHSpokenAudioSession.deactivate(
                owner: self.audioOwner
            )
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            self.restorationWatchdog?.cancel()
            self.restorationWatchdog = nil
            ATHLTHSpokenAudioSession.deactivate(
                owner: self.audioOwner
            )
        }
    }
}

struct ATHLTHAudioCoachSettingsView: View {
    var body: some View {
        ATHLTHAudioCoachGlobalEditorView()
            .navigationTitle("Audio Coach")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lists every compatible installed system voice, including improved-quality
/// downloads of the same speaker. Never invents a voice that iOS cannot play.
struct ATHLTHCoachVoiceChoices: View {
    @Binding var selectedIdentifier: String?
    let language: WatchAudioCoachLanguage
    let speechRate: Double
    let speechVolume: Double
    let duckOtherAudio: Bool
    let speechStyle: ATHLTHCoachSpeechStyle

    private var voices: [ATHLTHAudioCoachVoiceOption] {
        let prefix: String
        switch language {
        case .norwegian:
            prefix = "nb"
        case .english:
            prefix = "en"
        case .system:
            prefix = Locale.autoupdatingCurrent.language.languageCode?
                .identifier.lowercased() ?? "en"
        }
        let prefixes: [String] = ["nb", "nn", "no"].contains(prefix)
            ? ["nb", "nn", "no"] : [prefix]

        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let locale = voice.language.lowercased()
                return prefixes.contains { locale.hasPrefix($0) }
            }
            .map {
                ATHLTHAudioCoachVoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    qualityRank: $0.quality.rawValue
                )
            }
            .sorted { lhs, rhs in
                if lhs.qualityRank != rhs.qualityRank {
                    return lhs.qualityRank > rhs.qualityRank
                }
                if lhs.name != rhs.name {
                    return lhs.name < rhs.name
                }
                return lhs.id < rhs.id
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Available voices",
                    norwegian: "Tilgjengelige stemmer"
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                Spacer()
                Text("\(voices.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            HStack(spacing: 10) {
                Button {
                    selectedIdentifier = nil
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedIdentifier == nil
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Automatic · best available",
                                norwegian: "Automatisk · beste tilgjengelige"
                            ))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(ATHLTHLocalization.choose(
                                english: "Best installed voice",
                                norwegian: "Beste installerte stemme"
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selectedIdentifier == nil ? .isSelected : []
                )

                Button {
                    ATHLTHAudioCoachPreviewSpeaker.shared.speak(
                        language: language,
                        voiceIdentifier: nil,
                        speechRate: speechRate,
                        speechVolume: speechVolume,
                        duckOtherAudio: duckOtherAudio,
                        speechStyle: speechStyle
                    )
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Preview automatic voice",
                    norwegian: "Forhåndslytt på automatisk stemme"
                ))
            }
            .padding(10)
            .background(ATHLTHTheme.accentSoft.opacity(0.65),
                        in: RoundedRectangle(cornerRadius: 14))

            ForEach(voices) { voice in
                HStack(spacing: 10) {
                    Button {
                        selectedIdentifier = voice.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedIdentifier == voice.id
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(voice.qualityTitle ?? ATHLTHLocalization.choose(
                                    english: "Standard",
                                    norwegian: "Standard"
                                ))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        selectedIdentifier == voice.id ? .isSelected : []
                    )

                    Button {
                        ATHLTHAudioCoachPreviewSpeaker.shared.speak(
                            language: language,
                            voiceIdentifier: voice.id,
                            speechRate: speechRate,
                            speechVolume: speechVolume,
                            duckOtherAudio: duckOtherAudio,
                            speechStyle: speechStyle
                        )
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english: "Listen to \(voice.displayTitle)",
                            norwegian: "Lytt til \(voice.displayTitle)"
                        )
                    )
                }
                .padding(10)
                .background(
                    ATHLTHTheme.accentSoft.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
        }
    }
}
