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
        duckOtherAudio: Bool,
        speechStyle: ATHLTHCoachSpeechStyle
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
    @State private var showAdvancedSettings = false
    @State private var showGuidanceChoices = false
    @State private var showingCustomTimeInterval = false
    @State private var customTimeMinutes = 5
    @State private var customTimeSeconds = 0

    var body: some View {
        ZStack {
            premiumBackground
            ScrollView {
                VStack(spacing: 0) {
                    // ATHLTH+ applies to premium voices and workout features,
                    // not to discovering local voices or editing preferences.
                    experienceSection
                    speakingToneQuickSection
                    voiceSection
                    advancedOptionsToggle
                    if showAdvancedSettings {
                        triggerSection
                        updateSection
                        eventSection
                        routeAndStructureSection
                        fuelHydrationSection
                        musicSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 42)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Audio Coach")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCustomTimeInterval) {
            customTimeIntervalSheet
        }
    }

    /// Keep both the new second-accurate value and the older minute setting
    /// in sync, so older versions can still interpret a reasonable fallback.
    private func setTimeInterval(seconds: Int) {
        let value = min(max(seconds, 15), 7_200)
        settings.audioCoachTimeIntervalSeconds = value
        settings.audioCoachTimeIntervalMinutes = max(1, Int((Double(value) / 60).rounded()))
    }

    private var customTimeTotalSeconds: Int {
        customTimeMinutes * 60 + customTimeSeconds
    }

    private var customTimeIsValid: Bool {
        (15...7_200).contains(customTimeTotalSeconds)
    }

    private func openCustomTimeInterval() {
        let current = min(max(settings.audioCoachTimeIntervalSeconds, 15), 7_200)
        customTimeMinutes = current / 60
        customTimeSeconds = current % 60
        showingCustomTimeInterval = true
    }

    private var timeIntervalTitle: String {
        let seconds = min(max(settings.audioCoachTimeIntervalSeconds, 15), 7_200)
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 {
            return "\(remainder) " + ATHLTHLocalization.choose(
                english: "sec", norwegian: "sek"
            )
        }
        if remainder == 0 { return "\(minutes) min" }
        return "\(minutes) min \(remainder) " +
            ATHLTHLocalization.choose(english: "sec", norwegian: "sek")
    }

    private var customTimeIntervalSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "Custom time interval", norwegian: "Egendefinert tidsintervall"
                    ))
                    .font(.title3.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "How often should Audio Coach speak?",
                        norwegian: "Hvor ofte skal Audio Coach gi oppdateringer?"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 4) {
                Picker(ATHLTHLocalization.choose(
                    english: "Minutes", norwegian: "Minutter"
                ), selection: $customTimeMinutes) {
                    ForEach(0...120, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker(ATHLTHLocalization.choose(
                    english: "Seconds", norwegian: "Sekunder"
                ), selection: $customTimeSeconds) {
                    ForEach(0...59, id: \.self) { seconds in
                        Text("\(seconds) " + ATHLTHLocalization.choose(
                            english: "sec", norwegian: "sek"
                        )).tag(seconds)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 140)

            Text(ATHLTHLocalization.choose(
                english: "Choose between 15 seconds and 120 minutes.",
                norwegian: "Velg mellom 15 sekunder og 120 minutter."
            ))
            .font(.caption)
            .foregroundStyle(customTimeIsValid
                ? ATHLTHTheme.mutedText : Color.red)

            Button {
                setTimeInterval(seconds: customTimeTotalSeconds)
                showingCustomTimeInterval = false
            } label: {
                Text(ATHLTHLocalization.choose(
                    english: "Use interval", norwegian: "Bruk intervallet"
                ))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accentDeep)
            .disabled(!customTimeIsValid)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
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
                    iconTint: ATHLTHTheme.premiumGold,
                    iconBackground: ATHLTHTheme.premiumGoldSoft,
                    title: ATHLTHLocalization.choose(
                        english: "Off when a workout starts",
                        norwegian: "Av når en økt starter"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Enable Audio Coach when you want it. Your chosen voice and guidance settings are saved.",
                        norwegian: "Aktiver Audio Coach når du ønsker det. Valgt stemme og veiledning beholdes."
                    )
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }
        }
    }

    private var selectedExperience: ATHLTHCoachExperiencePreset? {
        ATHLTHCoachExperiencePreset.allCases.first { preset in
            currentContentLevel == preset.contentLevel
                && settings.audioCoachDistanceTriggerEnabled
                && !settings.audioCoachTimeTriggerEnabled
                && abs(settings.audioCoachDistanceIntervalKilometers
                       - preset.distanceIntervalKilometers) < 0.001
        }
    }

    private func applyExperience(_ preset: ATHLTHCoachExperiencePreset) {
        // Intentional selection; never resets language, voice, volume or output.
        selectContentLevel(preset.contentLevel)
        settings.audioCoachDistanceTriggerEnabled = true
        settings.audioCoachTimeTriggerEnabled = false
        settings.audioCoachDistanceIntervalKilometers =
            preset.distanceIntervalKilometers
    }

    /// Single, tappable guidance control. The previous second guidance-level
    /// card exposed the same settings and caused conflicting UI states.
    private var experienceSection: some View {
        premiumSection(ATHLTHLocalization.choose(
            english: "Guidance", norwegian: "Veiledning"
        )) {
            premiumCard {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showGuidanceChoices.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.path")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 32, height: 32)
                                .background(ATHLTHTheme.accentSoft,
                                            in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ATHLTHLocalization.choose(
                                    english: "How much guidance?",
                                    norwegian: "Hvor mye veiledning?"
                                ))
                                .font(.subheadline.weight(.semibold))
                                Text(selectedExperience?.title ??
                                     ATHLTHLocalization.choose(
                                        english: "Custom", norwegian: "Tilpasset"
                                     ))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: showGuidanceChoices
                                  ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Show or hide guidance levels",
                        norwegian: "Vis eller skjul veiledningsnivåer"
                    ))
                    .accessibilityValue(showGuidanceChoices
                        ? ATHLTHLocalization.choose(english: "Expanded", norwegian: "Utvidet")
                        : ATHLTHLocalization.choose(english: "Collapsed", norwegian: "Lukket"))

                    if showGuidanceChoices {
                        premiumDivider
                        VStack(spacing: 8) {
                            ForEach(ATHLTHCoachExperiencePreset.allCases) { preset in
                                Button {
                                    applyExperience(preset)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(preset.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text(preset.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(
                                                    selectedExperience == preset
                                                        ? Color.white.opacity(0.8)
                                                        : ATHLTHTheme.mutedText
                                                )
                                        }
                                        Spacer(minLength: 0)
                                        if selectedExperience == preset {
                                            Image(systemName: "checkmark.circle.fill")
                                        }
                                    }
                                    .foregroundStyle(selectedExperience == preset
                                        ? Color.white : ATHLTHTheme.primaryText)
                                    .padding(13)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selectedExperience == preset
                                        ? ATHLTHTheme.accentDeep : ATHLTHTheme.accentSoft,
                                        in: RoundedRectangle(cornerRadius: 13))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(
                                    selectedExperience == preset ? .isSelected : []
                                )
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
    }

    private var speakingToneQuickSection: some View {
        premiumSection(ATHLTHLocalization.choose(
            english: "Speaking style", norwegian: "Talemåte"
        )) {
            premiumCard {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                        Button {
                            settings.audioCoachSpeechStyle = style
                        } label: {
                            HStack(spacing: 7) {
                                Text(style.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                                if settings.audioCoachSpeechStyle == style {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(settings.audioCoachSpeechStyle == style
                                ? Color.white : ATHLTHTheme.primaryText)
                            .background(settings.audioCoachSpeechStyle == style
                                ? ATHLTHTheme.accentDeep : ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 13))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            settings.audioCoachSpeechStyle == style ? .isSelected : []
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    private var advancedOptionsToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAdvancedSettings.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "More settings", norwegian: "Flere innstillinger"
                ))
                .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: showAdvancedSettings ? "chevron.up" : "chevron.down")
                    .font(.caption.bold())
            }
            .foregroundStyle(ATHLTHTheme.primaryText)
            .padding(16)
            .background(Color.white.opacity(0.84),
                in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private var currentContentLevel: ATHLTHCoachContentLevel? {
        var draft = AudioCoachDraft()
        draft.load(from: settings)
        return ATHLTHCoachContentLevel.matching(
            draft.configuration()
        )
    }

    private func selectContentLevel(
        _ level: ATHLTHCoachContentLevel
    ) {
        var draft = AudioCoachDraft()
        draft.load(from: settings)
        let preset = level.applying(to: draft.configuration())

        // Intentionally keep distance/time triggers and speech frequency,
        // selected voice, volume, ducking and enabled state unchanged.
        settings.audioCoachAnnounceDistance = preset.announceDistance
        settings.audioCoachAnnounceElapsedTime = preset.announceElapsedTime
        settings.audioCoachAnnounceAveragePace = preset.announceAveragePace
        settings.audioCoachAnnounceClockTime = preset.announceClockTime
        settings.audioCoachAnnounceHeartRate = preset.announceHeartRate
        settings.audioCoachAnnounceRemainingRouteDistance =
            preset.announceRemainingRouteDistance
        settings.audioCoachAnnounceEstimatedRemainingRouteTime =
            preset.announceEstimatedRemainingRouteTime
        settings.audioCoachAnnounceCurrentWorkoutStep =
            preset.announceCurrentWorkoutStep
        settings.audioCoachAnnounceRemainingStepTime =
            preset.announceRemainingStepTime
        settings.audioCoachAnnounceRemainingStepDistance =
            preset.announceRemainingStepDistance
        settings.audioCoachAnnounceWorkoutStart =
            preset.shouldAnnounceWorkoutStart
        settings.audioCoachAnnouncePauseResume =
            preset.shouldAnnouncePauseResume
        settings.audioCoachAnnounceWorkoutComplete =
            preset.shouldAnnounceWorkoutComplete
    }

    private var contentLevelSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "Guidance level",
                norwegian: "Veiledningsnivå"
            )
        ) {
            premiumCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                        Text(ATHLTHLocalization.choose(
                            english: "What should the coach say?",
                            norwegian: "Hva skal coachen fortelle?"
                        ))
                        .font(.subheadline.weight(.semibold))
                    }

                    HStack(spacing: 8) {
                        ForEach(ATHLTHCoachContentLevel.allCases) { level in
                            Button {
                                selectContentLevel(level)
                            } label: {
                                VStack(spacing: 5) {
                                    Text(level.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(level.subtitle)
                                        .font(.system(size: 10))
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                }
                                .frame(maxWidth: .infinity, minHeight: 66)
                                .foregroundStyle(
                                    currentContentLevel == level
                                        ? Color.white
                                        : ATHLTHTheme.primaryText
                                )
                                .background(
                                    currentContentLevel == level
                                        ? ATHLTHTheme.accentDeep
                                        : ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 15,
                                        style: .continuous
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "These presets change content, not how often you hear it. Fine-tune individual options below.",
                        norwegian: "Nivåene styrer innhold, ikke hyppighet. Du kan tilpasse enkeltvalg lenger ned."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                    if currentContentLevel == nil {
                        Text(ATHLTHLocalization.choose(
                            english: "Custom setup",
                            norwegian: "Tilpasset oppsett"
                        ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                }
                .padding(16)
            }
        }
    }

    private var speechStyleSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "Speaking style",
                norwegian: "Talemåte"
            )
        ) {
            premiumCard {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                            Button {
                                settings.audioCoachSpeechStyle = style
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(style.title)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer(minLength: 0)
                                        if settings.audioCoachSpeechStyle == style {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                        }
                                    }
                                    Text(style.subtitle)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .leading
                                        )
                                }
                                .foregroundStyle(
                                    settings.audioCoachSpeechStyle == style
                                        ? Color.white
                                        : ATHLTHTheme.primaryText
                                )
                                .frame(maxWidth: .infinity, minHeight: 57)
                                .padding(12)
                                .background(
                                    settings.audioCoachSpeechStyle == style
                                        ? ATHLTHTheme.accentDeep
                                        : ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 16,
                                        style: .continuous
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "Your default tone. It only changes phrasing; the guidance level, cue frequency, safety alerts and voice speed stay the same.",
                        norwegian: "Din standard talemåte. Den endrer bare ordlyden. Veiledningsnivå, talefrekvens, sikkerhetsvarsler og talehastighet beholdes."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(16)
            }
        }
    }

    private var voiceSection: some View {
        premiumSection(ATHLTHLocalization.choose(
            english: "Voices", norwegian: "Stemmer"
        )) {
            premiumCard {
                languageMenu
                premiumDivider
                VStack(alignment: .leading, spacing: 0) {
                    ATHLTHCoachVoiceChoices(
                        selectedIdentifier: $settings.audioCoachVoiceIdentifier,
                        language: settings.audioCoachLanguage,
                        speechRate: settings.audioCoachSpeechRate,
                        speechVolume: settings.audioCoachSpeechVolume,
                        duckOtherAudio: settings.audioCoachDuckOtherAudio,
                        speechStyle: settings.audioCoachSpeechStyle
                    )
                    if settings.audioCoachLanguage == .norwegian {
                        ATHLTHAzureCoachVoicePreviewView()
                    }
                    if showAdvancedSettings {
                        Divider().padding(.vertical, 8)
                        sliderSetting(
                            title: ATHLTHLocalization.choose(
                                english: "Speaking speed", norwegian: "Talehastighet"
                            ),
                            valueTitle: speechRateTitle,
                            value: $settings.audioCoachSpeechRate,
                            range: 0.38...0.60,
                            step: 0.01
                        )
                        sliderSetting(
                            title: ATHLTHLocalization.choose(
                                english: "Voice volume", norwegian: "Stemmevolum"
                            ),
                            valueTitle: "\(Int((settings.audioCoachSpeechVolume * 100).rounded()))%",
                            value: $settings.audioCoachSpeechVolume,
                            range: 0.3...1.0,
                            step: 0.05
                        )
                    }
                }
                .padding(14)
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
                    settings.audioCoachLanguage = language
                    settings.audioCoachVoiceIdentifier = nil
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
                        value: timeIntervalTitle
                    ) {
                        ForEach([5, 10, 15, 30], id: \.self) { minutes in
                            Button {
                                setTimeInterval(seconds: minutes * 60)
                            } label: {
                                if settings.audioCoachTimeIntervalSeconds == minutes * 60 {
                                    Label("\(minutes) min", systemImage: "checkmark")
                                } else {
                                    Text("\(minutes) min")
                                }
                            }
                        }

                        Button {
                            openCustomTimeInterval()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Custom…", norwegian: "Egendefinert…"
                                ),
                                systemImage: "slider.horizontal.3"
                            )
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

    private var fuelHydrationSection: some View {
        premiumSection(
            ATHLTHLocalization.choose(
                english: "Nutrition during workouts",
                norwegian: "Energi og væske under økten"
            )
        ) {
            premiumCard {
                NavigationLink {
                    AthleteFuelView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(ATHLTHTheme.recoveryBlue)
                            .frame(width: 44, height: 44)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 14)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(ATHLTHLocalization.choose(
                                english: "Fuel & Hydration",
                                norwegian: "Energi og væske"
                            ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                            Text(ATHLTHLocalization.choose(
                                english: "Spoken reminders only · no notifications",
                                norwegian: "Bare tale · ingen varsler"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        if let key = ATHLTHAzureCoachVoice.key(
            settings.audioCoachVoiceIdentifier
        ) {
            return key.capitalized + " · Azure ATHLTH+"
        }

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
                        Text(ATHLTHLocalization.choose(
                            english: "Prefers a higher-quality installed voice",
                            norwegian: "Foretrekker en installert stemme med høyere kvalitet"
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

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
        .padding(.horizontal, 0)
    }
}
