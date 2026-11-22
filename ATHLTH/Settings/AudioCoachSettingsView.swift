import AVFoundation
import SwiftUI

@MainActor
final class ATHLTHAudioCoachPreviewSpeaker:
    NSObject,
    AVSpeechSynthesizerDelegate
{
    static let shared =
        ATHLTHAudioCoachPreviewSpeaker()

    private let synthesizer =
        AVSpeechSynthesizer()
    private let azureSpeech = ATHLTHAzureWorkoutSpeech()
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
        speechStyle: ATHLTHCoachSpeechStyle,
        sampleText: String? = nil
    ) {
        restorationWatchdog?.cancel()
        restorationWatchdog = nil
        synthesizer.stopSpeaking(
            at: .immediate
        )
        azureSpeech.stop()

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
            sampleText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? String((sampleText ?? sample).prefix(350))
                : sample,
            language: language,
            priority: .routineCoach,
            eventKind: .routineMilestone
        )
        // Premium voices use their real configured Azure voice, not an
        // unrelated local voice. If Azure is offline/denied, fallback to
        // Apple's selected voice without delaying the UI.
        // Azure's TTS request has a 220-character limit. Never cut off
        // part of the athlete's group preview; for longer groups use the
        // local voice for the complete message instead.
        let startedAzure = preview.count <= 220 && azureSpeech.begin(
            preview,
            voiceIdentifier: voiceIdentifier,
            duckMusic: duckOtherAudio,
            onFallback: { [weak self] in
                self?.speakLocally(
                    preview,
                    language: language,
                    voiceIdentifier: voiceIdentifier,
                    speechRate: speechRate,
                    speechVolume: speechVolume
                )
            },
            onStarted: {},
            onFinished: { [weak self] in
                guard let self else { return }
                ATHLTHSpokenAudioSession.deactivate(owner: self.audioOwner)
            }
        )
        if startedAzure { return }
        speakLocally(
            preview,
            language: language,
            voiceIdentifier: voiceIdentifier,
            speechRate: speechRate,
            speechVolume: speechVolume
        )
    }

    private func speakLocally(
        _ preview: String,
        language: WatchAudioCoachLanguage,
        voiceIdentifier: String?,
        speechRate: Double,
        speechVolume: Double
    ) {
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

    private var voices: [ATHLTHCoachVoiceDescriptor] {
        let code: String
        switch language {
        case .norwegian: code = "nb"
        case .english: code = "en"
        case .system:
            code = Locale.autoupdatingCurrent.language.languageCode?
                .identifier.lowercased() ?? "en"
        }

        let installed = AVSpeechSynthesisVoice.speechVoices().map {
            ATHLTHCoachVoiceDescriptor(
                id: $0.identifier,
                name: $0.name,
                language: $0.language,
                qualityRank: $0.quality.rawValue
            )
        }
        return ATHLTHCoachVoiceCatalog.featured(
            from: installed,
            languageCode: code,
            selectedIdentifier: selectedIdentifier
        )
    }

    /// Old selections of basic/novelty voices become Automatic. Keep any
    /// selected Azure voice or a voice installed only on another device.
    private func removeObsoleteLocalSelection() {
        guard let identifier = selectedIdentifier,
              !identifier.hasPrefix(ATHLTHAzureCoachVoice.prefix),
              let installed = AVSpeechSynthesisVoice(identifier: identifier),
              installed.quality.rawValue < 2 ||
                  ATHLTHCoachVoiceCatalog.isNovelty(name: installed.name)
        else { return }
        selectedIdentifier = nil
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
                    subtitle: voice.qualityRank >= 3
                        ? "Premium"
                        : ATHLTHLocalization.choose(
                            english: "Enhanced", norwegian: "Forbedret"
                        ),
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

            if voices.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Install an Enhanced or Premium Apple voice in iOS Settings to see more natural options.",
                        norwegian: "Last ned en forbedret Apple-stemme eller en Premium-stemme i iPhone-innstillingene for flere naturlige alternativer."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: removeObsoleteLocalSelection)
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
