import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system = "system"
    case english = "en"
    case norwegian = "nb"
    case spanish = "es"
    case italian = "it"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    static var currentlySupported:
        [AppLanguage] {
        [
            .english,
            .norwegian
        ]
    }

    var title: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .norwegian: return "Norsk"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .chineseSimplified: return "简体中文"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        default:
            return Locale(identifier: rawValue)
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "globe"
        default: return "globe"
        }
    }
}

enum MeasurementPreference: String, CaseIterable, Identifiable, Codable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: return ATHLTHLocalization.string( "Metric")
        case .imperial: return ATHLTHLocalization.string( "Imperial")
        }
    }

    var distanceUnit: String { self == .metric ? "km" : "mi" }
    var weightUnit: String { self == .metric ? "kg" : "lb" }
    var heightUnit: String { self == .metric ? "cm" : "ft/in" }
    var temperatureUnit: String { self == .metric ? "°C" : "°F" }

    func distance(fromKilometers kilometers: Double) -> String {
        if self == .metric {
            return String(format: "%.1f km", kilometers)
        }

        return String(format: "%.1f mi", kilometers * 0.621371)
    }

    func weight(fromKilograms kilograms: Double) -> String {
        if self == .metric {
            return String(format: "%.1f kg", kilograms)
        }

        return String(format: "%.1f lb", kilograms * 2.20462)
    }
}

enum TimeFormatPreference: String, CaseIterable, Identifiable, Codable {
    case twentyFourHour
    case twelveHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twentyFourHour: return "24-hour"
        case .twelveHour: return "12-hour"
        }
    }

    var example: String {
        switch self {
        case .twentyFourHour: return "21:45"
        case .twelveHour: return "9:45 PM"
        }
    }

    var locale: Locale {
        switch self {
        case .twentyFourHour:
            return Locale(identifier: "en_GB")
        case .twelveHour:
            return Locale(identifier: "en_US")
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return ATHLTHLocalization.string( "System")
        case .light: return ATHLTHLocalization.string( "Light")
        case .dark: return ATHLTHLocalization.string( "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}


enum TrainingDeviceProvider: String, CaseIterable, Identifiable, Codable {
    case appleWatch
    case garmin
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .garmin: return "Garmin"
        case .none: return "iPhone"
        }
    }

    var subtitle: String {
        switch self {
        case .appleWatch:
            return ATHLTHLocalization.string( "Live workouts, heart rate, routes and HealthKit sync")
        case .garmin:
            return ATHLTHLocalization.string( "Coming soon · Garmin Connect")
        case .none:
            return ATHLTHLocalization.string( "Record outdoor runs and walks. Carry your iPhone throughout the workout.")
        }
    }

    var systemImage: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .garmin: return "watch.analog"
        case .none: return "iphone"
        }
    }

    var usesAppleWatchConnectivity: Bool {
        self == .appleWatch
    }

    var supportsLiveWatchLaunch: Bool {
        self == .appleWatch
    }
}

enum WorkoutCapturePreference: String, CaseIterable, Identifiable, Codable {
    case automatic
    case iPhone
    case appleWatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return ATHLTHLocalization.string( "Automatic")
        case .iPhone: return "iPhone"
        case .appleWatch: return "Apple Watch"
        }
    }
}

enum WorkoutAutoPausePreference: String, CaseIterable, Identifiable, Codable {
    case appDefault
    case on
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appDefault:
            return ATHLTHLocalization.choose(
                english: "Use app default",
                norwegian: "Bruk standard"
            )
        case .on:
            return ATHLTHLocalization.choose(
                english: "On",
                norwegian: "På"
            )
        case .off:
            return ATHLTHLocalization.choose(
                english: "Off",
                norwegian: "Av"
            )
        }
    }

    var overrideValue: Bool? {
        switch self {
        case .appDefault: return nil
        case .on: return true
        case .off: return false
        }
    }

    func resolved(
        appDefault: Bool
    ) -> Bool {
        overrideValue ?? appDefault
    }

    init(overrideValue: Bool?) {
        switch overrideValue {
        case true?: self = .on
        case false?: self = .off
        case nil: self = .appDefault
        }
    }
}

enum StrengthTrackingPreference: String, CaseIterable, Identifiable, Codable {
    case simple
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return ATHLTHLocalization.string( "Simple")
        case .advanced: return ATHLTHLocalization.string( "Advanced")
        }
    }
}

enum ExternalWorkoutImportMode: String, CaseIterable, Identifiable, Codable {
    case ask
    case automatic
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return ATHLTHLocalization.string( "Ask before importing")
        case .automatic: return ATHLTHLocalization.string( "Automatically import")
        case .never: return ATHLTHLocalization.string( "Don't import")
        }
    }

    var shortTitle: String {
        switch self {
        case .ask: return ATHLTHLocalization.string( "Ask")
        case .automatic: return ATHLTHLocalization.string( "Automatic")
        case .never: return ATHLTHLocalization.string( "Off")
        }
    }
}

enum AchievementEffectPreference:
    String,
    CaseIterable,
    Identifiable,
    Codable
{
    case full
    case reduced
    case off

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .full:
            return ATHLTHLocalization.choose(
                english: "Full",
                norwegian: "Full"
            )
        case .reduced:
            return ATHLTHLocalization.choose(
                english: "Reduced",
                norwegian: "Redusert"
            )
        case .off:
            return ATHLTHLocalization.choose(
                english: "Off",
                norwegian: "Av"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .full:
            return ATHLTHLocalization.choose(
                english:
                    "Particles, glow and Signature tilt effects",
                norwegian:
                    "Partikler, glød og Signature-effekt ved tilt"
            )
        case .reduced:
            return ATHLTHLocalization.choose(
                english:
                    "Keeps premium surfaces with calmer motion",
                norwegian:
                    "Beholder premium-overflatene med roligere bevegelse"
            )
        case .off:
            return ATHLTHLocalization.choose(
                english:
                    "Static achievement surfaces only",
                norwegian:
                    "Kun statiske achievement-overflater"
            )
        }
    }
}

enum IntegrationKind: String, CaseIterable, Identifiable {
    case appleHealth
    case appleWatch
    case spotify
    case homeAssistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .appleWatch: return "Apple Watch"
        case .spotify: return "Spotify"
        case .homeAssistant: return "Home Assistant"
        }
    }

    var systemImage: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .appleWatch: return "applewatch"
        case .spotify: return "music.note"
        case .homeAssistant: return "house.and.flag.fill"
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var language: AppLanguage { didSet { persist() } }
    @Published var measurementPreference: MeasurementPreference { didSet { persist() } }
    @Published var timeFormatPreference: TimeFormatPreference { didSet { persist() } }
    @Published var appearance: AppAppearance { didSet { persist() } }

    @Published var profileVisibility: ProfileVisibility { didSet { persist() } }
    @Published var defaultActivityVisibility: ProfileVisibility { didSet { persist() } }
    @Published var shareTrainingPresence: Bool { didSet { persist() } }
    @Published var hideRouteStartAndEnd: Bool { didSet { persist() } }

    @Published var profileSetupPromptDismissed: Bool { didSet { persist() } }
    @Published var profileSetupCompleted: Bool { didSet { persist() } }
    @Published var showTrainingFocusOnProfile: Bool { didSet { persist() } }
    @Published var showTrainingStatusOnProfile: Bool { didSet { persist() } }
    @Published var showCurrentGoalOnProfile: Bool { didSet { persist() } }
    @Published var showProfileStatsOnProfile: Bool { didSet { persist() } }
    @Published var showPerformanceStatsOnProfile: Bool { didSet { persist() } }
    @Published var showWorkoutHistoryOnProfile: Bool { didSet { persist() } }

    @Published var trainingDeviceProvider: TrainingDeviceProvider { didSet { persist() } }
    @Published var preferredWorkoutCapture: WorkoutCapturePreference { didSet { persist() } }
    @Published var defaultStrengthTracking: StrengthTrackingPreference { didSet { persist() } }
    @Published var autoPauseOutdoorWorkouts: Bool { didSet { persist() } }
    @Published var backgroundHealthSyncEnabled: Bool { didSet { persist() } }
    @Published var externalWorkoutImportMode: ExternalWorkoutImportMode { didSet { persist() } }
    @Published var autoPublishCompletedWorkouts: Bool { didSet { persist() } }
    @Published var workoutSharingChoiceCompleted: Bool { didSet { persist() } }
    @Published var audioCuesEnabled: Bool { didSet { persist() } }
    @Published var hapticCuesEnabled: Bool { didSet { persist() } }
    @Published var achievementEffects:
        AchievementEffectPreference {
        didSet { persist() }
    }
    @Published var achievementUnlockSoundsEnabled:
        Bool {
        didSet { persist() }
    }
    @Published var achievementUnlockHapticsEnabled:
        Bool {
        didSet { persist() }
    }

    @Published var routeAlertsEnabled: Bool { didSet { persist() } }
    @Published var routeAlertDeviationMeters: Double { didSet { persist() } }
    @Published var routeAlertGraceSeconds: Int { didSet { persist() } }
    @Published var routeAlertRepeatSeconds: Int { didSet { persist() } }
    @Published var routeAlertDelivery: WatchAlertDelivery { didSet { persist() } }
    @Published var routeAlertAnnounceBackOnRoute: Bool { didSet { persist() } }

    @Published var audioCoachEnabledByDefault: Bool { didSet { persist() } }
    @Published var audioCoachLanguage: WatchAudioCoachLanguage {
        didSet {
            audioCoachVoiceIdentifier = nil
            persist()
        }
    }
    @Published var audioCoachDistanceTriggerEnabled: Bool { didSet { persist() } }
    @Published var audioCoachTimeTriggerEnabled: Bool { didSet { persist() } }
    @Published var audioCoachDistanceIntervalKilometers: Double { didSet { persist() } }
    @Published var audioCoachTimeIntervalMinutes: Int { didSet { persist() } }
    @Published var audioCoachAnnounceDistance: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceElapsedTime: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceAveragePace: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceClockTime: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceHeartRate: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceRemainingRouteDistance: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceEstimatedRemainingRouteTime: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceCurrentWorkoutStep: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceRemainingStepTime: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceRemainingStepDistance: Bool { didSet { persist() } }
    @Published var audioCoachDuckOtherAudio: Bool { didSet { persist() } }
    @Published var audioCoachVoiceIdentifier: String? { didSet { persist() } }
    @Published var audioCoachSpeechRate: Double { didSet { persist() } }
    @Published var audioCoachSpeechVolume: Double { didSet { persist() } }
    @Published var audioCoachAnnounceWorkoutStart: Bool { didSet { persist() } }
    @Published var audioCoachAnnouncePauseResume: Bool { didSet { persist() } }
    @Published var audioCoachAnnounceWorkoutComplete: Bool { didSet { persist() } }
    @Published var guidanceQuietPeriodSeconds: Int { didSet { persist() } }

    @Published var ghostRaceAudioEnabled: Bool { didSet { persist() } }
    @Published var ghostRaceAudioDistanceIntervalKilometers: Double { didSet { persist() } }
    @Published var ghostRaceAudioTimeIntervalMinutes: Int { didSet { persist() } }
    @Published var ghostRaceAudioUseDistance: Bool { didSet { persist() } }
    @Published var ghostRaceAudioUseTime: Bool { didSet { persist() } }
    @Published var ghostRaceAudioAnnounceLeadChanges: Bool { didSet { persist() } }
    @Published var ghostRaceAudioLeadChangeMeters: Double { didSet { persist() } }
    @Published var ghostRaceAudioDelivery: WatchAlertDelivery { didSet { persist() } }
    @Published var ghostRaceAudioLeadChangeDelivery: WatchAlertDelivery { didSet { persist() } }
    @Published var ghostRaceAudioImportantLeadChangeDelivery: WatchAlertDelivery { didSet { persist() } }
    @Published var ghostRaceAudioImportantLeadChangeMeters: Double { didSet { persist() } }

    @Published var workoutRemindersEnabled: Bool { didSet { persist() } }
    @Published var friendActivityNotificationsEnabled: Bool { didSet { persist() } }
    @Published var challengeNotificationsEnabled: Bool { didSet { persist() } }
    @Published var messageNotificationsEnabled: Bool { didSet { persist() } }
    @Published var mentionNotificationsEnabled: Bool { didSet { persist() } }

    @Published var spotifyAutoplayLinkedPlaylists: Bool { didSet { persist() } }
    @Published var spotifyDefaultPlaylist:
        SpotifyPlaylistReference? { didSet { persist() } }

    var interfaceLocale: Locale {
        var components =
            Locale.Components(
                locale:
                    language.locale
            )
        components.hourCycle =
            timeFormatPreference ==
                .twentyFourHour
                ? .zeroToTwentyThree
                : .oneToTwelve
        return Locale(
            components: components
        )
    }

    @Published var healthConnected: Bool = false
    @Published var watchConnected: Bool { didSet { persist() } }
    @Published var spotifyConnected: Bool { didSet { persist() } }
    @Published var homeAssistantConnected: Bool { didSet { persist() } }

    private let defaults: UserDefaults
    private var isInitializing = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedLanguage =
            AppLanguage(
                rawValue:
                    defaults.string(
                        forKey:
                            "settings.language"
                    ) ?? ""
            )

        if storedLanguage == .system {
            let preferredLanguage =
                Locale.preferredLanguages
                    .first?
                    .lowercased() ?? ""

            let migratedLanguage: AppLanguage =
                preferredLanguage.hasPrefix("nb") ||
                preferredLanguage.hasPrefix("no") ||
                preferredLanguage.hasPrefix("nn")
                    ? .norwegian
                    : .english

            language = migratedLanguage
            defaults.set(
                migratedLanguage.rawValue,
                forKey: "settings.language"
            )
        } else {
            language = storedLanguage ?? .english
        }

        let resolvedMeasurementPreference =
            MeasurementPreference(
                rawValue: defaults.string(
                    forKey: "settings.measurement"
                ) ?? ""
            ) ?? .metric
        measurementPreference = resolvedMeasurementPreference

        timeFormatPreference =
            TimeFormatPreference(
                rawValue: defaults.string(
                    forKey: "settings.timeFormat"
                ) ?? ""
            )
            ?? (resolvedMeasurementPreference == .metric
                ? .twentyFourHour
                : .twelveHour)

        appearance = .light

        profileVisibility = ProfileVisibility(rawValue: defaults.string(forKey: "settings.profileVisibility") ?? "") ?? .publicProfile
        defaultActivityVisibility = ProfileVisibility(rawValue: defaults.string(forKey: "settings.defaultActivityVisibility") ?? "") ?? .friends
        shareTrainingPresence = defaults.object(forKey: "settings.shareTrainingPresence") as? Bool ?? false
        hideRouteStartAndEnd = defaults.object(forKey: "settings.hideRouteStartAndEnd") as? Bool ?? true

        profileSetupPromptDismissed = defaults.object(forKey: "settings.profileSetupPromptDismissed") as? Bool ?? false
        let resolvedProfileSetupCompleted =
            defaults.object(forKey: "settings.profileSetupCompleted") as? Bool
            ?? false
        profileSetupCompleted = resolvedProfileSetupCompleted

        if !resolvedProfileSetupCompleted {
            defaultActivityVisibility = .friends
            defaults.set(
                ProfileVisibility.friends.rawValue,
                forKey: "settings.defaultActivityVisibility"
            )
        }

        showTrainingFocusOnProfile = defaults.object(forKey: "settings.showTrainingFocusOnProfile") as? Bool ?? false
        showTrainingStatusOnProfile = defaults.object(forKey: "settings.showTrainingStatusOnProfile") as? Bool ?? false
        showCurrentGoalOnProfile = defaults.object(forKey: "settings.showCurrentGoalOnProfile") as? Bool ?? false
        showProfileStatsOnProfile = defaults.object(forKey: "settings.showProfileStatsOnProfile") as? Bool ?? false
        showPerformanceStatsOnProfile = defaults.object(forKey: "settings.showPerformanceStatsOnProfile") as? Bool ?? false
        showWorkoutHistoryOnProfile = defaults.object(forKey: "settings.showWorkoutHistoryOnProfile") as? Bool ?? false

        let resolvedProvider: TrainingDeviceProvider
        if let storedProvider = defaults.string(
            forKey: "settings.trainingDeviceProvider"
        ),
           let provider = TrainingDeviceProvider(rawValue: storedProvider) {
            resolvedProvider = provider == .garmin ? .none : provider
        } else if defaults.object(forKey: "settings.watchConnected") as? Bool == true ||
                    defaults.string(forKey: "settings.preferredWorkoutCapture") ==
                        WorkoutCapturePreference.appleWatch.rawValue {
            resolvedProvider = .appleWatch
        } else {
            resolvedProvider = .none
        }

        let storedCapture = WorkoutCapturePreference(
            rawValue: defaults.string(
                forKey: "settings.preferredWorkoutCapture"
            ) ?? ""
        ) ?? .automatic
        let resolvedCapture: WorkoutCapturePreference
        if resolvedProvider != .appleWatch &&
            storedCapture == .appleWatch {
            resolvedCapture = .iPhone
            defaults.set(
                WorkoutCapturePreference.iPhone.rawValue,
                forKey: "settings.preferredWorkoutCapture"
            )
        } else {
            resolvedCapture = storedCapture
        }

        trainingDeviceProvider = resolvedProvider
        preferredWorkoutCapture = resolvedCapture

        defaultStrengthTracking = StrengthTrackingPreference(rawValue: defaults.string(forKey: "settings.defaultStrengthTracking") ?? "") ?? .simple
        autoPauseOutdoorWorkouts = defaults.object(forKey: "settings.autoPauseOutdoor") as? Bool ?? false
        backgroundHealthSyncEnabled = defaults.object(forKey: "settings.backgroundHealthSyncEnabled") as? Bool ?? true
        externalWorkoutImportMode = ExternalWorkoutImportMode(
            rawValue: defaults.string(forKey: "settings.externalWorkoutImportMode") ?? ""
        ) ?? .ask
        autoPublishCompletedWorkouts = defaults.object(forKey: "settings.autoPublishCompletedWorkouts") as? Bool ?? false
        workoutSharingChoiceCompleted = defaults.object(
            forKey: "settings.workoutSharingChoiceCompleted"
        ) as? Bool ?? false
        audioCuesEnabled = defaults.object(forKey: "settings.audioCues") as? Bool ?? true
        hapticCuesEnabled = defaults.object(forKey: "settings.hapticCues") as? Bool ?? true
        achievementEffects =
            AchievementEffectPreference(
                rawValue:
                    defaults.string(
                        forKey:
                            "settings.achievements.effects"
                    ) ?? ""
            ) ?? .full
        achievementUnlockSoundsEnabled =
            defaults.object(
                forKey:
                    "settings.achievements.unlockSounds"
            ) as? Bool ?? true
        achievementUnlockHapticsEnabled =
            defaults.object(
                forKey:
                    "settings.achievements.unlockHaptics"
            ) as? Bool ?? true

        routeAlertsEnabled =
            defaults.object(
                forKey: "settings.routeAlerts.enabled"
            ) as? Bool ?? true
        routeAlertDeviationMeters =
            defaults.object(
                forKey: "settings.routeAlerts.deviationMeters"
            ) as? Double ?? 80
        routeAlertGraceSeconds =
            defaults.object(
                forKey: "settings.routeAlerts.graceSeconds"
            ) as? Int ?? 10
        routeAlertRepeatSeconds =
            defaults.object(
                forKey: "settings.routeAlerts.repeatSeconds"
            ) as? Int ?? 120
        routeAlertDelivery =
            WatchAlertDelivery(
                rawValue: defaults.string(
                    forKey: "settings.routeAlerts.delivery"
                ) ?? ""
            ) ?? .both
        routeAlertAnnounceBackOnRoute =
            defaults.object(
                forKey: "settings.routeAlerts.announceBackOnRoute"
            ) as? Bool ?? true

        audioCoachEnabledByDefault =
            defaults.object(
                forKey: "settings.audioCoach.enabledByDefault"
            ) as? Bool ?? false
        audioCoachLanguage =
            WatchAudioCoachLanguage(
                rawValue: defaults.string(
                    forKey: "settings.audioCoach.language"
                ) ?? ""
            ) ?? .system
        audioCoachDistanceTriggerEnabled =
            defaults.object(
                forKey: "settings.audioCoach.distanceTriggerEnabled"
            ) as? Bool ?? true
        audioCoachTimeTriggerEnabled =
            defaults.object(
                forKey: "settings.audioCoach.timeTriggerEnabled"
            ) as? Bool ?? false
        audioCoachDistanceIntervalKilometers =
            defaults.object(
                forKey: "settings.audioCoach.distanceIntervalKilometers"
            ) as? Double ?? 1.0
        audioCoachTimeIntervalMinutes =
            defaults.object(
                forKey: "settings.audioCoach.timeIntervalMinutes"
            ) as? Int ?? 10
        audioCoachAnnounceDistance =
            defaults.object(
                forKey: "settings.audioCoach.announceDistance"
            ) as? Bool ?? true
        audioCoachAnnounceElapsedTime =
            defaults.object(
                forKey: "settings.audioCoach.announceElapsedTime"
            ) as? Bool ?? true
        audioCoachAnnounceAveragePace =
            defaults.object(
                forKey: "settings.audioCoach.announceAveragePace"
            ) as? Bool ?? true
        audioCoachAnnounceClockTime =
            defaults.object(
                forKey: "settings.audioCoach.announceClockTime"
            ) as? Bool ?? false
        audioCoachAnnounceHeartRate =
            defaults.object(
                forKey: "settings.audioCoach.announceHeartRate"
            ) as? Bool ?? false
        audioCoachAnnounceRemainingRouteDistance =
            defaults.object(
                forKey: "settings.audioCoach.announceRemainingRouteDistance"
            ) as? Bool ?? true
        audioCoachAnnounceEstimatedRemainingRouteTime =
            defaults.object(
                forKey: "settings.audioCoach.announceEstimatedRemainingRouteTime"
            ) as? Bool ?? true
        audioCoachAnnounceCurrentWorkoutStep =
            defaults.object(
                forKey: "settings.audioCoach.announceCurrentWorkoutStep"
            ) as? Bool ?? true
        audioCoachAnnounceRemainingStepTime =
            defaults.object(
                forKey: "settings.audioCoach.announceRemainingStepTime"
            ) as? Bool ?? true
        audioCoachAnnounceRemainingStepDistance =
            defaults.object(
                forKey: "settings.audioCoach.announceRemainingStepDistance"
            ) as? Bool ?? true
        audioCoachDuckOtherAudio =
            defaults.object(
                forKey: "settings.audioCoach.duckOtherAudio"
            ) as? Bool ?? true
        audioCoachVoiceIdentifier =
            defaults.string(
                forKey: "settings.audioCoach.voiceIdentifier"
            )
        audioCoachSpeechRate =
            defaults.object(
                forKey: "settings.audioCoach.speechRate"
            ) as? Double ?? 0.48
        audioCoachSpeechVolume =
            defaults.object(
                forKey: "settings.audioCoach.speechVolume"
            ) as? Double ?? 1.0
        audioCoachAnnounceWorkoutStart =
            defaults.object(
                forKey: "settings.audioCoach.announceWorkoutStart"
            ) as? Bool ?? true
        audioCoachAnnouncePauseResume =
            defaults.object(
                forKey: "settings.audioCoach.announcePauseResume"
            ) as? Bool ?? true
        audioCoachAnnounceWorkoutComplete =
            defaults.object(
                forKey: "settings.audioCoach.announceWorkoutComplete"
            ) as? Bool ?? true
        guidanceQuietPeriodSeconds =
            defaults.object(
                forKey: "settings.guidance.quietPeriodSeconds"
            ) as? Int ?? 10

        ghostRaceAudioEnabled =
            defaults.object(
                forKey: "settings.ghostRace.audio.enabled"
            ) as? Bool ?? true
        ghostRaceAudioDistanceIntervalKilometers =
            defaults.object(
                forKey: "settings.ghostRace.audio.distanceKilometers"
            ) as? Double ?? 1.0
        ghostRaceAudioTimeIntervalMinutes =
            defaults.object(
                forKey: "settings.ghostRace.audio.timeMinutes"
            ) as? Int ?? 5
        ghostRaceAudioUseDistance =
            defaults.object(
                forKey: "settings.ghostRace.audio.useDistance"
            ) as? Bool ?? true
        ghostRaceAudioUseTime =
            defaults.object(
                forKey: "settings.ghostRace.audio.useTime"
            ) as? Bool ?? false
        ghostRaceAudioAnnounceLeadChanges =
            defaults.object(
                forKey: "settings.ghostRace.audio.leadChanges"
            ) as? Bool ?? true
        ghostRaceAudioLeadChangeMeters =
            defaults.object(
                forKey: "settings.ghostRace.audio.leadChangeMeters"
            ) as? Double ?? 25
        ghostRaceAudioDelivery =
            WatchAlertDelivery(
                rawValue: defaults.string(
                    forKey: "settings.ghostRace.audio.delivery"
                ) ?? ""
            ) ?? .voice
        ghostRaceAudioLeadChangeDelivery =
            WatchAlertDelivery(
                rawValue: defaults.string(
                    forKey:
                        "settings.ghostRace.audio.leadChangeDelivery"
                ) ?? ""
            ) ?? .haptic
        ghostRaceAudioImportantLeadChangeDelivery =
            WatchAlertDelivery(
                rawValue: defaults.string(
                    forKey:
                        "settings.ghostRace.audio.importantLeadChangeDelivery"
                ) ?? ""
            ) ?? .both
        ghostRaceAudioImportantLeadChangeMeters =
            defaults.object(
                forKey:
                    "settings.ghostRace.audio.importantLeadChangeMeters"
            ) as? Double ?? 50

        workoutRemindersEnabled = defaults.object(forKey: "settings.workoutReminders") as? Bool ?? true
        friendActivityNotificationsEnabled = defaults.object(forKey: "settings.friendActivityNotifications") as? Bool ?? true
        challengeNotificationsEnabled = defaults.object(forKey: "settings.challengeNotifications") as? Bool ?? true
        messageNotificationsEnabled = defaults.object(forKey: "settings.messageNotifications") as? Bool ?? true
        mentionNotificationsEnabled = defaults.object(forKey: "settings.mentionNotifications") as? Bool ?? true

        spotifyAutoplayLinkedPlaylists =
            defaults.object(
                forKey: "settings.spotifyAutoplayLinkedPlaylists"
            ) as? Bool ?? true
        if let playlistData =
                defaults.data(
                    forKey:
                        "settings.spotifyDefaultPlaylist"
                ),
           let playlist =
                try? JSONDecoder().decode(
                    SpotifyPlaylistReference.self,
                    from: playlistData
                ) {
            spotifyDefaultPlaylist = playlist
        } else {
            spotifyDefaultPlaylist = nil
        }
        watchConnected = defaults.object(forKey: "settings.watchConnected") as? Bool ?? false
        spotifyConnected =
            defaults.object(
                forKey: "settings.spotifyConnected"
            ) as? Bool ?? false
        homeAssistantConnected = defaults.object(forKey: "settings.homeAssistantConnected") as? Bool ?? false

        isInitializing = false
    }

    private func persist() {
        guard !isInitializing else { return }

        defaults.set(language.rawValue, forKey: "settings.language")
        defaults.set(measurementPreference.rawValue, forKey: "settings.measurement")
        defaults.set(timeFormatPreference.rawValue, forKey: "settings.timeFormat")
        defaults.set(appearance.rawValue, forKey: "settings.appearance")

        defaults.set(profileVisibility.rawValue, forKey: "settings.profileVisibility")
        defaults.set(defaultActivityVisibility.rawValue, forKey: "settings.defaultActivityVisibility")
        defaults.set(shareTrainingPresence, forKey: "settings.shareTrainingPresence")
        defaults.set(hideRouteStartAndEnd, forKey: "settings.hideRouteStartAndEnd")

        defaults.set(profileSetupPromptDismissed, forKey: "settings.profileSetupPromptDismissed")
        defaults.set(profileSetupCompleted, forKey: "settings.profileSetupCompleted")
        defaults.set(showTrainingFocusOnProfile, forKey: "settings.showTrainingFocusOnProfile")
        defaults.set(showTrainingStatusOnProfile, forKey: "settings.showTrainingStatusOnProfile")
        defaults.set(showCurrentGoalOnProfile, forKey: "settings.showCurrentGoalOnProfile")
        defaults.set(showProfileStatsOnProfile, forKey: "settings.showProfileStatsOnProfile")
        defaults.set(showPerformanceStatsOnProfile, forKey: "settings.showPerformanceStatsOnProfile")
        defaults.set(showWorkoutHistoryOnProfile, forKey: "settings.showWorkoutHistoryOnProfile")

        defaults.set(trainingDeviceProvider.rawValue, forKey: "settings.trainingDeviceProvider")
        defaults.set(preferredWorkoutCapture.rawValue, forKey: "settings.preferredWorkoutCapture")
        defaults.set(defaultStrengthTracking.rawValue, forKey: "settings.defaultStrengthTracking")
        defaults.set(autoPauseOutdoorWorkouts, forKey: "settings.autoPauseOutdoor")
        defaults.set(backgroundHealthSyncEnabled, forKey: "settings.backgroundHealthSyncEnabled")
        defaults.set(externalWorkoutImportMode.rawValue, forKey: "settings.externalWorkoutImportMode")
        defaults.set(autoPublishCompletedWorkouts, forKey: "settings.autoPublishCompletedWorkouts")
        defaults.set(
            workoutSharingChoiceCompleted,
            forKey: "settings.workoutSharingChoiceCompleted"
        )
        defaults.set(audioCuesEnabled, forKey: "settings.audioCues")
        defaults.set(hapticCuesEnabled, forKey: "settings.hapticCues")
        defaults.set(
            achievementEffects.rawValue,
            forKey:
                "settings.achievements.effects"
        )
        defaults.set(
            achievementUnlockSoundsEnabled,
            forKey:
                "settings.achievements.unlockSounds"
        )
        defaults.set(
            achievementUnlockHapticsEnabled,
            forKey:
                "settings.achievements.unlockHaptics"
        )

        defaults.set(
            routeAlertsEnabled,
            forKey: "settings.routeAlerts.enabled"
        )
        defaults.set(
            routeAlertDeviationMeters,
            forKey: "settings.routeAlerts.deviationMeters"
        )
        defaults.set(
            routeAlertGraceSeconds,
            forKey: "settings.routeAlerts.graceSeconds"
        )
        defaults.set(
            routeAlertRepeatSeconds,
            forKey: "settings.routeAlerts.repeatSeconds"
        )
        defaults.set(
            routeAlertDelivery.rawValue,
            forKey: "settings.routeAlerts.delivery"
        )
        defaults.set(
            routeAlertAnnounceBackOnRoute,
            forKey: "settings.routeAlerts.announceBackOnRoute"
        )

        defaults.set(
            audioCoachEnabledByDefault,
            forKey: "settings.audioCoach.enabledByDefault"
        )
        defaults.set(
            audioCoachLanguage.rawValue,
            forKey: "settings.audioCoach.language"
        )
        defaults.set(
            audioCoachDistanceTriggerEnabled,
            forKey: "settings.audioCoach.distanceTriggerEnabled"
        )
        defaults.set(
            audioCoachTimeTriggerEnabled,
            forKey: "settings.audioCoach.timeTriggerEnabled"
        )
        defaults.set(
            audioCoachDistanceIntervalKilometers,
            forKey: "settings.audioCoach.distanceIntervalKilometers"
        )
        defaults.set(
            audioCoachTimeIntervalMinutes,
            forKey: "settings.audioCoach.timeIntervalMinutes"
        )
        defaults.set(
            audioCoachAnnounceDistance,
            forKey: "settings.audioCoach.announceDistance"
        )
        defaults.set(
            audioCoachAnnounceElapsedTime,
            forKey: "settings.audioCoach.announceElapsedTime"
        )
        defaults.set(
            audioCoachAnnounceAveragePace,
            forKey: "settings.audioCoach.announceAveragePace"
        )
        defaults.set(
            audioCoachAnnounceClockTime,
            forKey: "settings.audioCoach.announceClockTime"
        )
        defaults.set(
            audioCoachAnnounceHeartRate,
            forKey: "settings.audioCoach.announceHeartRate"
        )
        defaults.set(
            audioCoachAnnounceRemainingRouteDistance,
            forKey: "settings.audioCoach.announceRemainingRouteDistance"
        )
        defaults.set(
            audioCoachAnnounceEstimatedRemainingRouteTime,
            forKey: "settings.audioCoach.announceEstimatedRemainingRouteTime"
        )
        defaults.set(
            audioCoachAnnounceCurrentWorkoutStep,
            forKey: "settings.audioCoach.announceCurrentWorkoutStep"
        )
        defaults.set(
            audioCoachAnnounceRemainingStepTime,
            forKey: "settings.audioCoach.announceRemainingStepTime"
        )
        defaults.set(
            audioCoachAnnounceRemainingStepDistance,
            forKey: "settings.audioCoach.announceRemainingStepDistance"
        )
        defaults.set(
            audioCoachDuckOtherAudio,
            forKey: "settings.audioCoach.duckOtherAudio"
        )
        if let audioCoachVoiceIdentifier {
            defaults.set(
                audioCoachVoiceIdentifier,
                forKey: "settings.audioCoach.voiceIdentifier"
            )
        } else {
            defaults.removeObject(
                forKey: "settings.audioCoach.voiceIdentifier"
            )
        }
        defaults.set(
            audioCoachSpeechRate,
            forKey: "settings.audioCoach.speechRate"
        )
        defaults.set(
            audioCoachSpeechVolume,
            forKey: "settings.audioCoach.speechVolume"
        )
        defaults.set(
            audioCoachAnnounceWorkoutStart,
            forKey: "settings.audioCoach.announceWorkoutStart"
        )
        defaults.set(
            audioCoachAnnouncePauseResume,
            forKey: "settings.audioCoach.announcePauseResume"
        )
        defaults.set(
            audioCoachAnnounceWorkoutComplete,
            forKey: "settings.audioCoach.announceWorkoutComplete"
        )
        defaults.set(
            guidanceQuietPeriodSeconds,
            forKey: "settings.guidance.quietPeriodSeconds"
        )

        defaults.set(
            ghostRaceAudioEnabled,
            forKey: "settings.ghostRace.audio.enabled"
        )
        defaults.set(
            ghostRaceAudioDistanceIntervalKilometers,
            forKey: "settings.ghostRace.audio.distanceKilometers"
        )
        defaults.set(
            ghostRaceAudioTimeIntervalMinutes,
            forKey: "settings.ghostRace.audio.timeMinutes"
        )
        defaults.set(
            ghostRaceAudioUseDistance,
            forKey: "settings.ghostRace.audio.useDistance"
        )
        defaults.set(
            ghostRaceAudioUseTime,
            forKey: "settings.ghostRace.audio.useTime"
        )
        defaults.set(
            ghostRaceAudioAnnounceLeadChanges,
            forKey: "settings.ghostRace.audio.leadChanges"
        )
        defaults.set(
            ghostRaceAudioLeadChangeMeters,
            forKey: "settings.ghostRace.audio.leadChangeMeters"
        )
        defaults.set(
            ghostRaceAudioDelivery.rawValue,
            forKey: "settings.ghostRace.audio.delivery"
        )
        defaults.set(
            ghostRaceAudioLeadChangeDelivery.rawValue,
            forKey:
                "settings.ghostRace.audio.leadChangeDelivery"
        )
        defaults.set(
            ghostRaceAudioImportantLeadChangeDelivery.rawValue,
            forKey:
                "settings.ghostRace.audio.importantLeadChangeDelivery"
        )
        defaults.set(
            ghostRaceAudioImportantLeadChangeMeters,
            forKey:
                "settings.ghostRace.audio.importantLeadChangeMeters"
        )

        defaults.set(workoutRemindersEnabled, forKey: "settings.workoutReminders")
        defaults.set(friendActivityNotificationsEnabled, forKey: "settings.friendActivityNotifications")
        defaults.set(challengeNotificationsEnabled, forKey: "settings.challengeNotifications")
        defaults.set(messageNotificationsEnabled, forKey: "settings.messageNotifications")
        defaults.set(mentionNotificationsEnabled, forKey: "settings.mentionNotifications")

        defaults.set(spotifyAutoplayLinkedPlaylists, forKey: "settings.spotifyAutoplayLinkedPlaylists")
        if let spotifyDefaultPlaylist,
           let playlistData =
                try? JSONEncoder().encode(
                    spotifyDefaultPlaylist
                ) {
            defaults.set(
                playlistData,
                forKey:
                    "settings.spotifyDefaultPlaylist"
            )
        } else {
            defaults.removeObject(
                forKey:
                    "settings.spotifyDefaultPlaylist"
            )
        }
        defaults.set(watchConnected, forKey: "settings.watchConnected")
        defaults.set(spotifyConnected, forKey: "settings.spotifyConnected")
        defaults.set(homeAssistantConnected, forKey: "settings.homeAssistantConnected")
    }

    var routeAlertConfiguration: WatchRouteAlertConfiguration {
        WatchRouteAlertConfiguration(
            enabled: routeAlertsEnabled,
            deviationMeters:
                min(
                    max(routeAlertDeviationMeters, 20),
                    500
                ),
            graceSeconds:
                TimeInterval(
                    min(
                        max(routeAlertGraceSeconds, 0),
                        120
                    )
                ),
            repeatSeconds:
                TimeInterval(
                    min(
                        max(routeAlertRepeatSeconds, 30),
                        600
                    )
                ),
            delivery: routeAlertDelivery,
            announceBackOnRoute:
                routeAlertAnnounceBackOnRoute
        )
    }

    func audioCoachConfiguration(
        enabled: Bool,
        routeDistanceMeters: Double? = nil
    ) -> WatchAudioCoachConfiguration {
        WatchAudioCoachConfiguration(
            enabled: enabled,
            language: audioCoachLanguage,
            distanceIntervalMeters:
                audioCoachDistanceTriggerEnabled
                    ? audioCoachDistanceIntervalKilometers * 1_000
                    : nil,
            timeIntervalSeconds:
                audioCoachTimeTriggerEnabled
                    ? Double(audioCoachTimeIntervalMinutes * 60)
                    : nil,
            announceDistance: audioCoachAnnounceDistance,
            announceElapsedTime: audioCoachAnnounceElapsedTime,
            announceAveragePace: audioCoachAnnounceAveragePace,
            announceClockTime: audioCoachAnnounceClockTime,
            announceHeartRate: audioCoachAnnounceHeartRate,
            announceRemainingRouteDistance:
                audioCoachAnnounceRemainingRouteDistance,
            announceEstimatedRemainingRouteTime:
                audioCoachAnnounceEstimatedRemainingRouteTime,
            routeDistanceMeters: routeDistanceMeters,
            announceCurrentWorkoutStep:
                audioCoachAnnounceCurrentWorkoutStep,
            announceRemainingStepTime:
                audioCoachAnnounceRemainingStepTime,
            announceRemainingStepDistance:
                audioCoachAnnounceRemainingStepDistance,
            duckOtherAudio:
                audioCoachDuckOtherAudio,
            guidanceQuietPeriodSeconds:
                TimeInterval(
                    min(
                        max(
                            guidanceQuietPeriodSeconds,
                            0
                        ),
                        30
                    )
                ),
            voiceIdentifier:
                audioCoachVoiceIdentifier,
            speechRate:
                Float(
                    min(
                        max(
                            audioCoachSpeechRate,
                            0.35
                        ),
                        0.65
                    )
                ),
            speechVolume:
                Float(
                    min(
                        max(
                            audioCoachSpeechVolume,
                            0.2
                        ),
                        1.0
                    )
                ),
            announceWorkoutStart:
                audioCoachAnnounceWorkoutStart,
            announcePauseResume:
                audioCoachAnnouncePauseResume,
            announceWorkoutComplete:
                audioCoachAnnounceWorkoutComplete
        )
    }

    var ghostRaceAudioConfiguration:
        WatchGhostRaceAudioConfiguration {
        WatchGhostRaceAudioConfiguration(
            enabled: ghostRaceAudioEnabled,
            distanceIntervalMeters:
                ghostRaceAudioUseDistance
                    ? max(
                        ghostRaceAudioDistanceIntervalKilometers,
                        0.25
                    ) * 1_000
                    : nil,
            timeIntervalSeconds:
                ghostRaceAudioUseTime
                    ? TimeInterval(
                        max(
                            ghostRaceAudioTimeIntervalMinutes,
                            1
                        ) * 60
                    )
                    : nil,
            announceLeadChanges:
                ghostRaceAudioAnnounceLeadChanges,
            leadChangeThresholdMeters:
                min(
                    max(
                        ghostRaceAudioLeadChangeMeters,
                        10
                    ),
                    250
                ),
            delivery:
                ghostRaceAudioDelivery,
            periodicDelivery:
                ghostRaceAudioDelivery,
            leadChangeDelivery:
                ghostRaceAudioLeadChangeDelivery,
            importantLeadChangeDelivery:
                ghostRaceAudioImportantLeadChangeDelivery,
            importantLeadChangeMeters:
                min(
                    max(
                        ghostRaceAudioImportantLeadChangeMeters,
                        ghostRaceAudioLeadChangeMeters
                    ),
                    500
                )
        )
    }

    var shouldShowProfileSetupPrompt: Bool {
        !profileSetupPromptDismissed && !profileSetupCompleted
    }

    func dismissProfileSetupPrompt() {
        profileSetupPromptDismissed = true
    }

    func markProfileSetupCompleted() {
        profileSetupCompleted = true
        profileSetupPromptDismissed = true
    }

    func connectionState(for integration: IntegrationKind) -> Bool {
        switch integration {
        case .appleHealth: return healthConnected
        case .appleWatch: return watchConnected
        case .spotify: return spotifyConnected
        case .homeAssistant: return homeAssistantConnected
        }
    }
}
