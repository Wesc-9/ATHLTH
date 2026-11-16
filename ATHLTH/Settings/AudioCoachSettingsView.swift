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
        VStack(alignment: .leading, spacing: 9) {
            Text(ATHLTHLocalization.choose(
                english: "APPLE VOICES", norwegian: "APPLE-STEMMER"
            ))
            .font(.caption2.weight(.bold))
            .tracking(1.3)
            .foregroundStyle(ATHLTHPlanDesign.accentInk)

            ATHLTHCoachVoiceRow(
                title: ATHLTHLocalization.choose(
                    english: "Automatic", norwegian: "Automatisk"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Best installed voice", norwegian: "Beste installerte stemme"
                ),
                selected: selectedIdentifier == nil,
                locked: false,
                busy: false,
                onSelect: { selectedIdentifier = nil },
                onPreview: {
                    ATHLTHAudioCoachPreviewSpeaker.shared.speak(
                        language: language,
                        voiceIdentifier: nil,
                        speechRate: speechRate,
                        speechVolume: speechVolume,
                        duckOtherAudio: duckOtherAudio,
                        speechStyle: speechStyle
                    )
                }
            )
            .accessibilityIdentifier("athlth-coach-voice-automatic")

            ForEach(voices) { voice in
                ATHLTHCoachVoiceRow(
                    title: voice.name,
                    subtitle: voice.qualityTitle ?? voice.language,
                    selected: selectedIdentifier == voice.id,
                    locked: false,
                    busy: false,
                    onSelect: { selectedIdentifier = voice.id },
                    onPreview: {
                        ATHLTHAudioCoachPreviewSpeaker.shared.speak(
                            language: language,
                            voiceIdentifier: voice.id,
                            speechRate: speechRate,
                            speechVolume: speechVolume,
                            duckOtherAudio: duckOtherAudio,
                            speechStyle: speechStyle
                        )
                    }
                )
                .accessibilityIdentifier("athlth-coach-voice-apple")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared row for Apple, Azure and future voice providers.
/// Selection and preview share the same hit sizes and colors.
struct ATHLTHCoachVoiceRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let locked: Bool
    let busy: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onSelect) {
                HStack(spacing: 11) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .accessibilityAddTraits(selected ? .isSelected : [])

            if locked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .frame(width: 36, height: 40)
            } else {
                Button(action: onPreview) {
                    Group {
                        if busy {
                            ProgressView()
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english: "Preview " + title, norwegian: "Forhåndslytt på " + title
                    )
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            selected ? ATHLTHPlanDesign.selectedSurface : Color.white,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(ATHLTHPlanDesign.warmDivider, lineWidth: 1)
        }
        .opacity(locked ? 0.55 : 1)
    }
}
