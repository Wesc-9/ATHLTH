import AVFoundation
import SwiftUI

private struct ATHLTHAudioCoachVoiceOption:
    Identifiable,
    Hashable
{
    let id: String
    let name: String
    let language: String

    var displayTitle: String {
        "\(name) · \(language)"
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

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        language: WatchAudioCoachLanguage,
        voiceIdentifier: String?,
        speechRate: Double,
        speechVolume: Double,
        duckOtherAudio: Bool
    ) {
        synthesizer.stopSpeaking(
            at: .immediate
        )

        let audioSession =
            AVAudioSession.sharedInstance()
        let options:
            AVAudioSession.CategoryOptions =
                duckOtherAudio
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

        let utterance =
            AVSpeechUtterance(
                string:
                    useNorwegian
                        ? "Audio Coach er klar."
                        : "Audio Coach is ready."
            )

        if let voiceIdentifier,
           let selectedVoice =
                AVSpeechSynthesisVoice(
                    identifier: voiceIdentifier
                ) {
            utterance.voice = selectedVoice
        } else if language == .norwegian ||
            (language == .system &&
             useNorwegian) {
            utterance.voice =
                AVSpeechSynthesisVoice(
                    language: "nb-NO"
                )
        } else if language == .english {
            utterance.voice =
                AVSpeechSynthesisVoice(
                    language: "en-US"
                )
        }

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
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            try? AVAudioSession
                .sharedInstance()
                .setActive(
                    false,
                    options:
                        .notifyOthersOnDeactivation
                )
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            try? AVAudioSession
                .sharedInstance()
                .setActive(
                    false,
                    options:
                        .notifyOthersOnDeactivation
                )
        }
    }
}

struct ATHLTHAudioCoachSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        ScrollView {
            ATHLTHPlusFeatureGate(
                feature: .audioCoach,
                title: "Audio Coach is part of ATHLTH+",
                message:
                    "Unlock spoken workout updates, route progress and structured workout guidance."
            ) {
                VStack(spacing: 16) {
                    defaultsCard
                    voiceCard
                    triggerCard
                    contentCard
                    eventCard
                    routeCard
                    structuredWorkoutCard
                    musicCard
                }
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Audio Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var defaultsCard: some View {
        settingsCard(
            title: "Defaults",
            subtitle:
                "These settings are preselected whenever you start a supported workout."
        ) {
            Toggle(
                "Enable by default",
                isOn: $settings.audioCoachEnabledByDefault
            )
        }
    }

    private var triggerCard: some View {
        settingsCard(
            title: "When to speak",
            subtitle:
                "Choose one or both recurring triggers. Structured workout step changes can also speak automatically."
        ) {
            Toggle(
                "Every distance interval",
                isOn: $settings.audioCoachDistanceTriggerEnabled
            )

            if settings.audioCoachDistanceTriggerEnabled {
                pickerRow("Distance interval") {
                    Picker(
                        "Distance interval",
                        selection:
                            $settings.audioCoachDistanceIntervalKilometers
                    ) {
                        Text("0.5 km").tag(0.5)
                        Text("1 km").tag(1.0)
                        Text("2 km").tag(2.0)
                        Text("5 km").tag(5.0)
                    }
                    .pickerStyle(.menu)
                }
            }

            Divider()

            Toggle(
                "Every time interval",
                isOn: $settings.audioCoachTimeTriggerEnabled
            )

            if settings.audioCoachTimeTriggerEnabled {
                pickerRow("Time interval") {
                    Picker(
                        "Time interval",
                        selection:
                            $settings.audioCoachTimeIntervalMinutes
                    ) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var contentCard: some View {
        settingsCard(
            title: "Workout updates",
            subtitle:
                "Choose exactly what recurring Audio Coach updates should include."
        ) {
            Toggle(
                "Distance",
                isOn: $settings.audioCoachAnnounceDistance
            )
            Toggle(
                "Elapsed time",
                isOn: $settings.audioCoachAnnounceElapsedTime
            )
            Toggle(
                "Average pace",
                isOn: $settings.audioCoachAnnounceAveragePace
            )
            Toggle(
                "Current time",
                isOn: $settings.audioCoachAnnounceClockTime
            )
            Toggle(
                "Heart rate",
                isOn: $settings.audioCoachAnnounceHeartRate
            )
        }
    }

    private var routeCard: some View {
        settingsCard(
            title: "Route progress",
            subtitle:
                "Used when the workout has a known ATHLTH route."
        ) {
            Toggle(
                "Remaining distance",
                isOn:
                    $settings.audioCoachAnnounceRemainingRouteDistance
            )
            Toggle(
                "Estimated time remaining",
                isOn:
                    $settings
                        .audioCoachAnnounceEstimatedRemainingRouteTime
            )
        }
    }

    private var structuredWorkoutCard: some View {
        settingsCard(
            title: "Structured workouts",
            subtitle:
                "Guidance for intervals, tempo blocks and other running workout steps."
        ) {
            Toggle(
                "Announce current / next step",
                isOn:
                    $settings.audioCoachAnnounceCurrentWorkoutStep
            )
            Toggle(
                "Remaining time in step",
                isOn:
                    $settings.audioCoachAnnounceRemainingStepTime
            )
            Toggle(
                "Remaining distance in step",
                isOn:
                    $settings.audioCoachAnnounceRemainingStepDistance
            )
        }
    }

    private var musicCard: some View {
        settingsCard(
            title: "Music & other audio",
            subtitle:
                "Controls how Audio Coach behaves while Spotify or another audio app is playing."
        ) {
            Toggle(
                "Lower music while coach speaks",
                isOn: $settings.audioCoachDuckOtherAudio
            )

            Text(
                settings.audioCoachDuckOtherAudio
                    ? "Music is temporarily reduced only while the coach is speaking, then returns automatically."
                    : "Coach speech mixes with other audio at its current level."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            pickerRow(
                ATHLTHLocalization.choose(
                    english: "Quiet period after important alerts",
                    norwegian: "Pause etter viktige varsler"
                )
            ) {
                Picker(
                    "Quiet period",
                    selection:
                        $settings
                            .guidanceQuietPeriodSeconds
                ) {
                    Text("0 s").tag(0)
                    Text("5 s").tag(5)
                    Text("10 s").tag(10)
                    Text("15 s").tag(15)
                    Text("30 s").tag(30)
                }
                .pickerStyle(.menu)
            }

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Prevents routine pace and distance updates from talking over route, interval or target alerts.",
                    norwegian:
                        "Hindrer vanlige tempo- og distanseoppdateringer i å snakke over rute-, intervall- eller målvarsler."
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var voiceCard: some View {
        settingsCard(
            title:
                ATHLTHLocalization.choose(
                    english: "Voice",
                    norwegian: "Stemme"
                ),
            subtitle:
                ATHLTHLocalization.choose(
                    english:
                        "Choose the language, voice, speaking speed and volume used by Audio Coach.",
                    norwegian:
                        "Velg språk, stemme, talehastighet og volum for Audio Coach."
                )
        ) {
            pickerRow(
                ATHLTHLocalization.choose(
                    english: "Language",
                    norwegian: "Språk"
                )
            ) {
                Picker(
                    "Language",
                    selection:
                        $settings.audioCoachLanguage
                ) {
                    ForEach(
                        WatchAudioCoachLanguage
                            .allCases,
                        id: \.rawValue
                    ) { language in
                        Text(language.title)
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
            }

            Divider()

            pickerRow(
                ATHLTHLocalization.choose(
                    english: "Voice",
                    norwegian: "Stemme"
                )
            ) {
                Picker(
                    "Voice",
                    selection:
                        $settings
                            .audioCoachVoiceIdentifier
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Automatic",
                            norwegian: "Automatisk"
                        )
                    )
                    .tag(
                        Optional<String>.none
                    )

                    ForEach(
                        availableVoiceOptions
                    ) { voice in
                        Text(
                            voice.displayTitle
                        )
                        .tag(
                            Optional(voice.id)
                        )
                    }
                }
                .pickerStyle(.menu)
            }

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Voice availability can differ between iPhone and Apple Watch. If the selected voice is unavailable on Watch, ATHLTH falls back to the selected language automatically.",
                    norwegian:
                        "Tilgjengelige stemmer kan være forskjellige på iPhone og Apple Watch. Hvis valgt stemme ikke finnes på klokken, bruker ATHLTH automatisk en stemme for valgt språk."
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Divider()

            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Speaking speed",
                            norwegian: "Talehastighet"
                        )
                    )
                    Spacer()
                    Text(
                        speechRateTitle
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Slider(
                    value:
                        $settings
                            .audioCoachSpeechRate,
                    in: 0.38...0.60,
                    step: 0.01
                )
            }

            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Voice volume",
                            norwegian: "Stemmevolum"
                        )
                    )
                    Spacer()
                    Text(
                        "\(Int((settings.audioCoachSpeechVolume * 100).rounded()))%"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Slider(
                    value:
                        $settings
                            .audioCoachSpeechVolume,
                    in: 0.3...1.0,
                    step: 0.05
                )
            }

            Button {
                ATHLTHAudioCoachPreviewSpeaker
                    .shared
                    .speak(
                        language:
                            settings
                                .audioCoachLanguage,
                        voiceIdentifier:
                            settings
                                .audioCoachVoiceIdentifier,
                        speechRate:
                            settings
                                .audioCoachSpeechRate,
                        speechVolume:
                            settings
                                .audioCoachSpeechVolume,
                        duckOtherAudio:
                            settings
                                .audioCoachDuckOtherAudio
                    )
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Play test voice",
                        norwegian: "Spill av teststemme"
                    ),
                    systemImage:
                        "speaker.wave.2.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)
        }
    }

    private var eventCard: some View {
        settingsCard(
            title:
                ATHLTHLocalization.choose(
                    english: "Workout events",
                    norwegian: "Hendelser i økten"
                ),
            subtitle:
                ATHLTHLocalization.choose(
                    english:
                        "Choose which important workout events Audio Coach should confirm.",
                    norwegian:
                        "Velg hvilke viktige hendelser Audio Coach skal bekrefte."
                )
        ) {
            Toggle(
                ATHLTHLocalization.choose(
                    english: "Workout started",
                    norwegian: "Økten starter"
                ),
                isOn:
                    $settings
                        .audioCoachAnnounceWorkoutStart
            )

            Toggle(
                ATHLTHLocalization.choose(
                    english: "Pause and resume",
                    norwegian: "Pause og fortsett"
                ),
                isOn:
                    $settings
                        .audioCoachAnnouncePauseResume
            )

            Toggle(
                ATHLTHLocalization.choose(
                    english: "Workout completed",
                    norwegian: "Økten fullføres"
                ),
                isOn:
                    $settings
                        .audioCoachAnnounceWorkoutComplete
            )
        }
    }

    private var availableVoiceOptions:
        [ATHLTHAudioCoachVoiceOption] {
        let prefixes: [String]

        switch settings.audioCoachLanguage {
        case .norwegian:
            prefixes = ["nb", "nn", "no"]
        case .english:
            prefixes = ["en"]
        case .system:
            let code =
                Locale.autoupdatingCurrent
                    .language
                    .languageCode?
                    .identifier
                    .lowercased() ??
                "en"
            prefixes =
                ["nb", "nn", "no"]
                    .contains(code)
                    ? ["nb", "nn", "no"]
                    : [code]
        }

        return AVSpeechSynthesisVoice
            .speechVoices()
            .filter { voice in
                let language =
                    voice.language
                        .lowercased()

                return prefixes
                    .contains {
                        language
                            .hasPrefix($0)
                    }
            }
            .map {
                ATHLTHAudioCoachVoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language
                )
            }
            .sorted {
                if $0.name == $1.name {
                    return $0.language <
                        $1.language
                }
                return $0.name < $1.name
            }
    }

    private var speechRateTitle: String {
        switch settings.audioCoachSpeechRate {
        case ..<0.44:
            return ATHLTHLocalization.choose(
                english: "Slow",
                norwegian: "Rolig"
            )
        case 0.54...:
            return ATHLTHLocalization.choose(
                english: "Fast",
                norwegian: "Rask"
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Normal",
                norwegian: "Normal"
            )
        }
    }

    private func pickerRow<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            trailing()
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.05),
                lineWidth: 1
            )
        }
    }
}
