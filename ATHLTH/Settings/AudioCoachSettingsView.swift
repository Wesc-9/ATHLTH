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
                        ? "Audio Coach er klar. Ha en god økt."
                        : "Audio Coach is ready. Have a great workout."
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
        ZStack {
            premiumBackground

            ScrollView {
                ATHLTHPlusFeatureGate(
                    feature: .audioCoach,
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Audio Coach is part of ATHLTH+",
                            norwegian:
                                "Audio Coach er en del av ATHLTH+"
                        ),
                    message:
                        ATHLTHLocalization.choose(
                            english:
                                "Unlock spoken workout updates, route progress and structured workout guidance.",
                            norwegian:
                                "Få talte treningsoppdateringer, rutefremdrift og veiledning i strukturerte økter."
                        )
                ) {
                    VStack(spacing: 0) {
                        defaultsSection
                        voiceSection
                        triggerSection
                        updateSection
                        eventSection
                        routeAndStructureSection
                        musicSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 42)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Audio Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var premiumBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    Color.white,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.055),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var defaultsSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "Default",
                norwegian: "Standard"
            )
        ) {
            premiumCard {
                premiumRow(
                    icon: "waveform.and.mic",
                    iconTint:
                        ATHLTHTheme.premiumGold,
                    iconBackground:
                        ATHLTHTheme.premiumGoldSoft,
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Enable by default",
                            norwegian:
                                "Aktiver som standard"
                        ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Preselected whenever you start a supported workout",
                            norwegian:
                                "Forhåndsvalgt når du starter en støttet økt"
                        )
                ) {
                    Toggle(
                        "",
                        isOn:
                            $settings
                                .audioCoachEnabledByDefault
                    )
                    .labelsHidden()
                    .tint(ATHLTHTheme.accent)
                }
            }
        }
    }

    private var voiceSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "Voice",
                norwegian: "Stemme"
            )
        ) {
            premiumCard {
                languageMenu

                premiumDivider

                voiceMenu

                premiumDivider

                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    sliderSetting(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Speaking speed",
                                norwegian:
                                    "Talehastighet"
                            ),
                        valueTitle:
                            speechRateTitle,
                        value:
                            $settings
                                .audioCoachSpeechRate,
                        range:
                            0.38...0.60,
                        step: 0.01
                    )

                    sliderSetting(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Voice volume",
                                norwegian:
                                    "Stemmevolum"
                            ),
                        valueTitle:
                            "\(Int((settings.audioCoachSpeechVolume * 100).rounded()))%",
                        value:
                            $settings
                                .audioCoachSpeechVolume,
                        range:
                            0.3...1.0,
                        step: 0.05
                    )

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
                        HStack(spacing: 10) {
                            Image(
                                systemName:
                                    "speaker.wave.2.fill"
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .premiumGold
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Play test voice",
                                    norwegian:
                                        "Spill av teststemme"
                                )
                            )
                            .foregroundStyle(
                                Color.white
                            )
                        }
                        .font(
                            .headline
                        )
                        .frame(
                            maxWidth: .infinity
                        )
                        .frame(height: 52)
                        .background(
                            ATHLTHTheme.primaryText,
                            in:
                                RoundedRectangle(
                                    cornerRadius: 17,
                                    style: .continuous
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    HStack(
                        alignment: .top,
                        spacing: 8
                    ) {
                        Image(
                            systemName:
                                "info.circle"
                        )
                        .font(.caption)
                        .padding(.top, 1)

                        Text(
                            voiceAvailabilityText
                        )
                        .font(.caption)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
                .padding(16)
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(
                WatchAudioCoachLanguage
                    .allCases,
                id: \.rawValue
            ) { language in
                Button {
                    settings
                        .audioCoachLanguage =
                        language
                } label: {
                    if settings
                        .audioCoachLanguage ==
                        language {
                        Label(
                            language.title,
                            systemImage:
                                "checkmark"
                        )
                    } else {
                        Text(
                            language.title
                        )
                    }
                }
            }
        } label: {
            premiumRow(
                icon: "globe",
                title:
                    ATHLTHLocalization.choose(
                        english: "Language",
                        norwegian: "Språk"
                    ),
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Language used for spoken guidance",
                        norwegian:
                            "Språket som brukes i talte tilbakemeldinger"
                    )
            ) {
                menuValue(
                    settings
                        .audioCoachLanguage
                        .title
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var voiceMenu: some View {
        Menu {
            Button {
                settings
                    .audioCoachVoiceIdentifier =
                    nil
            } label: {
                if settings
                    .audioCoachVoiceIdentifier ==
                    nil {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Automatic",
                            norwegian:
                                "Automatisk"
                        ),
                        systemImage:
                            "checkmark"
                    )
                } else {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Automatic",
                            norwegian:
                                "Automatisk"
                        )
                    )
                }
            }

            if !availableVoiceOptions
                .isEmpty {
                Divider()

                ForEach(
                    availableVoiceOptions
                ) { voice in
                    Button {
                        settings
                            .audioCoachVoiceIdentifier =
                            voice.id
                    } label: {
                        if settings
                            .audioCoachVoiceIdentifier ==
                            voice.id {
                            Label(
                                voice.displayTitle,
                                systemImage:
                                    "checkmark"
                            )
                        } else {
                            Text(
                                voice.displayTitle
                            )
                        }
                    }
                }
            }
        } label: {
            premiumRow(
                icon: "waveform",
                iconTint:
                    ATHLTHTheme.premiumGold,
                iconBackground:
                    ATHLTHTheme.premiumGoldSoft,
                title:
                    ATHLTHLocalization.choose(
                        english: "Voice",
                        norwegian: "Stemme"
                    ),
                subtitle:
                    voiceSubtitle
            ) {
                menuValue(
                    selectedVoiceTitle
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var triggerSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "When to speak",
                norwegian: "Når skal den snakke"
            )
        ) {
            premiumCard {
                premiumToggleRow(
                    icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Every distance interval",
                            norwegian:
                                "Hvert distanseintervall"
                        ),
                    isOn:
                        $settings
                            .audioCoachDistanceTriggerEnabled
                )

                if settings
                    .audioCoachDistanceTriggerEnabled {
                    premiumDivider

                    valueMenuRow(
                        icon: "ruler",
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Distance interval",
                                norwegian:
                                    "Distanseintervall"
                            ),
                        value:
                            distanceIntervalTitle
                    ) {
                        Button("0.5 km") {
                            settings
                                .audioCoachDistanceIntervalKilometers =
                                0.5
                        }
                        Button("1 km") {
                            settings
                                .audioCoachDistanceIntervalKilometers =
                                1.0
                        }
                        Button("2 km") {
                            settings
                                .audioCoachDistanceIntervalKilometers =
                                2.0
                        }
                        Button("5 km") {
                            settings
                                .audioCoachDistanceIntervalKilometers =
                                5.0
                        }
                    }
                }

                premiumDivider

                premiumToggleRow(
                    icon: "timer",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Every time interval",
                            norwegian:
                                "Hvert tidsintervall"
                        ),
                    isOn:
                        $settings
                            .audioCoachTimeTriggerEnabled
                )

                if settings
                    .audioCoachTimeTriggerEnabled {
                    premiumDivider

                    valueMenuRow(
                        icon: "clock",
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Time interval",
                                norwegian:
                                    "Tidsintervall"
                            ),
                        value:
                            "\(settings.audioCoachTimeIntervalMinutes) min"
                    ) {
                        ForEach(
                            [5, 10, 15, 30],
                            id: \.self
                        ) { minutes in
                            Button(
                                "\(minutes) min"
                            ) {
                                settings
                                    .audioCoachTimeIntervalMinutes =
                                    minutes
                            }
                        }
                    }
                }
            }
        }
    }

    private var updateSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "Workout updates",
                norwegian: "Oppdateringer"
            )
        ) {
            premiumCard {
                premiumToggleRow(
                    icon: "arrow.left.and.right",
                    title:
                        ATHLTHLocalization.choose(
                            english: "Distance",
                            norwegian: "Distanse"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceDistance
                )

                premiumDivider

                premiumToggleRow(
                    icon: "stopwatch",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Elapsed time",
                            norwegian:
                                "Tid i økten"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceElapsedTime
                )

                premiumDivider

                premiumToggleRow(
                    icon: "speedometer",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Average pace",
                            norwegian:
                                "Gjennomsnittstempo"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceAveragePace
                )

                premiumDivider

                premiumToggleRow(
                    icon: "clock",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Current time",
                            norwegian:
                                "Klokkeslett"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceClockTime
                )

                premiumDivider

                premiumToggleRow(
                    icon: "heart.fill",
                    iconTint: .pink,
                    iconBackground:
                        Color.pink.opacity(0.10),
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Heart rate",
                            norwegian: "Puls"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceHeartRate
                )
            }
        }
    }

    private var eventSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "Workout events",
                norwegian: "Hendelser i økten"
            )
        ) {
            premiumCard {
                premiumToggleRow(
                    icon: "play.fill",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Workout started",
                            norwegian:
                                "Økten starter"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceWorkoutStart
                )

                premiumDivider

                premiumToggleRow(
                    icon: "pause.fill",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Pause and resume",
                            norwegian:
                                "Pause og fortsett"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnouncePauseResume
                )

                premiumDivider

                premiumToggleRow(
                    icon: "checkmark.circle.fill",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Workout completed",
                            norwegian:
                                "Økten fullføres"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceWorkoutComplete
                )
            }
        }
    }

    private var routeAndStructureSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english:
                    "Route & structured workouts",
                norwegian:
                    "Rute og strukturert økt"
            )
        ) {
            premiumCard {
                premiumToggleRow(
                    icon: "map",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Remaining route distance",
                            norwegian:
                                "Gjenstående rutedistanse"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceRemainingRouteDistance
                )

                premiumDivider

                premiumToggleRow(
                    icon: "clock.arrow.circlepath",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Estimated route time remaining",
                            norwegian:
                                "Estimert tid igjen på ruten"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceEstimatedRemainingRouteTime
                )

                premiumDivider

                premiumToggleRow(
                    icon: "list.number",
                    iconTint:
                        ATHLTHTheme.premiumGold,
                    iconBackground:
                        ATHLTHTheme.premiumGoldSoft,
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Current / next workout step",
                            norwegian:
                                "Nåværende / neste øktsteg"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceCurrentWorkoutStep
                )

                premiumDivider

                premiumToggleRow(
                    icon: "timer",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Remaining time in step",
                            norwegian:
                                "Gjenstående tid i steg"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceRemainingStepTime
                )

                premiumDivider

                premiumToggleRow(
                    icon: "arrow.left.and.right",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Remaining distance in step",
                            norwegian:
                                "Gjenstående distanse i steg"
                        ),
                    isOn:
                        $settings
                            .audioCoachAnnounceRemainingStepDistance
                )
            }
        }
    }

    private var musicSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "Music & audio",
                norwegian: "Musikk og lyd"
            )
        ) {
            premiumCard {
                premiumToggleRow(
                    icon: "music.note",
                    iconTint:
                        ATHLTHTheme.premiumGold,
                    iconBackground:
                        ATHLTHTheme.premiumGoldSoft,
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Lower music while coach speaks",
                            norwegian:
                                "Senk musikken mens coachen snakker"
                        ),
                    subtitle:
                        ATHLTHLocalization.choose(
                            english:
                                "Music returns automatically after the message",
                            norwegian:
                                "Musikken går automatisk tilbake etter meldingen"
                        ),
                    isOn:
                        $settings
                            .audioCoachDuckOtherAudio
                )

                premiumDivider

                valueMenuRow(
                    icon: "speaker.wave.2",
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Quiet period after important alerts",
                            norwegian:
                                "Pause etter viktige varsler"
                        ),
                    value:
                        "\(settings.guidanceQuietPeriodSeconds) s"
                ) {
                    ForEach(
                        [0, 5, 10, 15, 30],
                        id: \.self
                    ) { seconds in
                        Button(
                            "\(seconds) s"
                        ) {
                            settings
                                .guidanceQuietPeriodSeconds =
                                seconds
                        }
                    }
                }
            }
        }
    }

    private var availableVoiceOptions:
        [ATHLTHAudioCoachVoiceOption] {
        let prefixes: [String]

        switch settings.audioCoachLanguage {
        case .norwegian:
            prefixes = [
                "nb",
                "nn",
                "no"
            ]
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
                [
                    "nb",
                    "nn",
                    "no"
                ]
                .contains(code)
                    ? [
                        "nb",
                        "nn",
                        "no"
                    ]
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
            .map { voice in
                ATHLTHAudioCoachVoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    qualityRank:
                        voice.quality.rawValue
                )
            }
            .sorted { lhs, rhs in
                if lhs.qualityRank !=
                    rhs.qualityRank {
                    return lhs.qualityRank >
                        rhs.qualityRank
                }

                if lhs.language !=
                    rhs.language {
                    return lhs.language <
                        rhs.language
                }

                if lhs.name != rhs.name {
                    return lhs.name <
                        rhs.name
                }

                return lhs.id < rhs.id
            }
    }

    private var selectedVoiceTitle: String {
        guard let identifier =
            settings
                .audioCoachVoiceIdentifier,
              let voice =
                availableVoiceOptions
                    .first(
                        where: {
                            $0.id ==
                                identifier
                        }
                    )
        else {
            return ATHLTHLocalization.choose(
                english: "Automatic",
                norwegian: "Automatisk"
            )
        }

        return voice.compactTitle
    }

    private var voiceSubtitle: String {
        let count =
            availableVoiceOptions.count

        guard settings
            .audioCoachLanguage ==
            .norwegian
        else {
            return ATHLTHLocalization.choose(
                english:
                    "Choose from the voices available on this device",
                norwegian:
                    "Velg blant stemmene som finnes på denne enheten"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "\(count) Norwegian voice\(count == 1 ? "" : "s") available on this device",
            norwegian:
                "\(count) norske stemme\(count == 1 ? "" : "r") tilgjengelig på denne enheten"
        )
    }

    private var voiceAvailabilityText: String {
        ATHLTHLocalization.choose(
            english:
                "The voice menu is built from every compatible voice iOS exposes for the selected language, including enhanced variants when available. Apple Watch can have a different voice selection and will fall back automatically.",
            norwegian:
                "Stemmemenyen henter alle kompatible stemmer iOS tilbyr for valgt språk, inkludert forbedrede varianter når de finnes. Apple Watch kan ha et annet utvalg og bruker automatisk en passende reserve."
        )
    }

    private var speechRateTitle: String {
        switch settings
            .audioCoachSpeechRate {
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

    private var distanceIntervalTitle:
        String {
        let value =
            settings
                .audioCoachDistanceIntervalKilometers

        if value.rounded() == value {
            return "\(Int(value)) km"
        }

        return String(
            format: "%.1f km",
            value
        )
    }

    @ViewBuilder
    private func premiumSection<
        Content: View
    >(
        _ title: String,
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text(
                title.uppercased()
            )
            .font(
                .caption.weight(
                    .semibold
                )
            )
            .tracking(2.8)
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.82)
            )
            .padding(.leading, 16)

            content()
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func premiumCard<
        Content: View
    >(
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            ATHLTHTheme.card,
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.035),
            radius: 20,
            x: 0,
            y: 10
        )
    }

    private var premiumDivider:
        some View {
        Rectangle()
            .fill(
                ATHLTHTheme.divider
            )
            .frame(height: 0.5)
            .padding(
                .leading,
                74
            )
            .padding(
                .trailing,
                16
            )
    }

    @ViewBuilder
    private func premiumRow<
        Trailing: View
    >(
        icon: String,
        iconTint: Color =
            ATHLTHTheme.primaryText,
        iconBackground: Color =
            ATHLTHTheme.accentSoft,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing:
            () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 18,
                    weight: .medium
                )
            )
            .foregroundStyle(
                iconTint
            )
            .frame(
                width: 44,
                height: 44
            )
            .background(
                iconBackground,
                in:
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .system(
                            size: 16.5,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            trailing()
        }
        .padding(
            .horizontal,
            16
        )
        .padding(
            .vertical,
            13
        )
        .contentShape(
            Rectangle()
        )
    }

    @ViewBuilder
    private func premiumToggleRow(
        icon: String,
        iconTint: Color =
            ATHLTHTheme.primaryText,
        iconBackground: Color =
            ATHLTHTheme.accentSoft,
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        premiumRow(
            icon: icon,
            iconTint: iconTint,
            iconBackground:
                iconBackground,
            title: title,
            subtitle: subtitle
        ) {
            Toggle(
                "",
                isOn: isOn
            )
            .labelsHidden()
            .tint(
                ATHLTHTheme.accent
            )
        }
    }

    @ViewBuilder
    private func valueMenuRow<
        MenuContent: View
    >(
        icon: String,
        title: String,
        value: String,
        @ViewBuilder menuContent:
            () -> MenuContent
    ) -> some View {
        Menu {
            menuContent()
        } label: {
            premiumRow(
                icon: icon,
                title: title
            ) {
                menuValue(value)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menuValue(
        _ value: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.82
                )

            Image(
                systemName:
                    "chevron.up.chevron.down"
            )
            .font(
                .caption2.weight(
                    .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
                    .opacity(0.72)
            )
        }
    }

    @ViewBuilder
    private func sliderSetting(
        title: String,
        valueTitle: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.medium)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Spacer()

                Text(valueTitle)
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
            }

            Slider(
                value: value,
                in: range,
                step: step
            )
            .tint(
                ATHLTHTheme
                    .accentDeep
            )
        }
    }
}
