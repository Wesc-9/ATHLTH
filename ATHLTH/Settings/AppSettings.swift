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

    var title: String {
        switch self {
        case .system: return "iPhone"
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
        case .system: return "iphone"
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
        case .metric: return "Metric"
        case .imperial: return "Imperial"
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

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
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
        case .none: return "No watch"
        }
    }

    var subtitle: String {
        switch self {
        case .appleWatch:
            return "Live workouts, heart rate, routes and HealthKit sync"
        case .garmin:
            return "Prepared for Garmin Connect · authorization pending"
        case .none:
            return "Use ATHLTH and iPhone without a wearable"
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
        case .automatic: return "Automatic"
        case .iPhone: return "iPhone"
        case .appleWatch: return "Apple Watch"
        }
    }
}

enum StrengthTrackingPreference: String, CaseIterable, Identifiable, Codable {
    case simple
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
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
    @Published var appearance: AppAppearance { didSet { persist() } }

    @Published var profileVisibility: ProfileVisibility { didSet { persist() } }
    @Published var defaultActivityVisibility: ProfileVisibility { didSet { persist() } }
    @Published var shareTrainingPresence: Bool { didSet { persist() } }
    @Published var hideRouteStartAndEnd: Bool { didSet { persist() } }

    @Published var trainingDeviceProvider: TrainingDeviceProvider { didSet { persist() } }
    @Published var preferredWorkoutCapture: WorkoutCapturePreference { didSet { persist() } }
    @Published var defaultStrengthTracking: StrengthTrackingPreference { didSet { persist() } }
    @Published var autoPauseOutdoorWorkouts: Bool { didSet { persist() } }
    @Published var backgroundHealthSyncEnabled: Bool { didSet { persist() } }
    @Published var autoPublishCompletedWorkouts: Bool { didSet { persist() } }
    @Published var audioCuesEnabled: Bool { didSet { persist() } }
    @Published var hapticCuesEnabled: Bool { didSet { persist() } }

    @Published var workoutRemindersEnabled: Bool { didSet { persist() } }
    @Published var friendActivityNotificationsEnabled: Bool { didSet { persist() } }
    @Published var challengeNotificationsEnabled: Bool { didSet { persist() } }
    @Published var messageNotificationsEnabled: Bool { didSet { persist() } }

    @Published var spotifyAutoplayLinkedPlaylists: Bool { didSet { persist() } }

    @Published var healthConnected: Bool = false
    @Published var watchConnected: Bool { didSet { persist() } }
    @Published var spotifyConnected: Bool { didSet { persist() } }
    @Published var homeAssistantConnected: Bool { didSet { persist() } }

    private let defaults: UserDefaults
    private var isInitializing = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // ATHLTH currently ships in English with a Light-only interface.
        // Keep the underlying types in place so localization/themes can expand later.
        language = .english
        measurementPreference = MeasurementPreference(rawValue: defaults.string(forKey: "settings.measurement") ?? "") ?? .metric
        appearance = .light

        profileVisibility = ProfileVisibility(rawValue: defaults.string(forKey: "settings.profileVisibility") ?? "") ?? .friends
        defaultActivityVisibility = ProfileVisibility(rawValue: defaults.string(forKey: "settings.defaultActivityVisibility") ?? "") ?? .friends
        shareTrainingPresence = defaults.object(forKey: "settings.shareTrainingPresence") as? Bool ?? true
        hideRouteStartAndEnd = defaults.object(forKey: "settings.hideRouteStartAndEnd") as? Bool ?? true

        if let storedProvider = defaults.string(forKey: "settings.trainingDeviceProvider"),
           let provider = TrainingDeviceProvider(rawValue: storedProvider) {
            trainingDeviceProvider = provider
        } else if defaults.object(forKey: "settings.watchConnected") as? Bool == true ||
                    defaults.string(forKey: "settings.preferredWorkoutCapture") ==
                        WorkoutCapturePreference.appleWatch.rawValue {
            trainingDeviceProvider = .appleWatch
        } else {
            trainingDeviceProvider = .none
        }

        preferredWorkoutCapture = WorkoutCapturePreference(rawValue: defaults.string(forKey: "settings.preferredWorkoutCapture") ?? "") ?? .automatic
        if trainingDeviceProvider != .appleWatch &&
            preferredWorkoutCapture == .appleWatch {
            preferredWorkoutCapture = .iPhone
            defaults.set(
                WorkoutCapturePreference.iPhone.rawValue,
                forKey: "settings.preferredWorkoutCapture"
            )
        }

        defaultStrengthTracking = StrengthTrackingPreference(rawValue: defaults.string(forKey: "settings.defaultStrengthTracking") ?? "") ?? .simple
        autoPauseOutdoorWorkouts = defaults.object(forKey: "settings.autoPauseOutdoor") as? Bool ?? true
        backgroundHealthSyncEnabled = defaults.object(forKey: "settings.backgroundHealthSyncEnabled") as? Bool ?? true
        autoPublishCompletedWorkouts = defaults.object(forKey: "settings.autoPublishCompletedWorkouts") as? Bool ?? false
        audioCuesEnabled = defaults.object(forKey: "settings.audioCues") as? Bool ?? true
        hapticCuesEnabled = defaults.object(forKey: "settings.hapticCues") as? Bool ?? true

        workoutRemindersEnabled = defaults.object(forKey: "settings.workoutReminders") as? Bool ?? true
        friendActivityNotificationsEnabled = defaults.object(forKey: "settings.friendActivityNotifications") as? Bool ?? true
        challengeNotificationsEnabled = defaults.object(forKey: "settings.challengeNotifications") as? Bool ?? true
        messageNotificationsEnabled = defaults.object(forKey: "settings.messageNotifications") as? Bool ?? true

        spotifyAutoplayLinkedPlaylists = defaults.object(forKey: "settings.spotifyAutoplayLinkedPlaylists") as? Bool ?? true
        watchConnected = defaults.object(forKey: "settings.watchConnected") as? Bool ?? false
        spotifyConnected = defaults.object(forKey: "settings.spotifyConnected") as? Bool ?? false
        homeAssistantConnected = defaults.object(forKey: "settings.homeAssistantConnected") as? Bool ?? false

        isInitializing = false
    }

    private func persist() {
        guard !isInitializing else { return }

        defaults.set(language.rawValue, forKey: "settings.language")
        defaults.set(measurementPreference.rawValue, forKey: "settings.measurement")
        defaults.set(appearance.rawValue, forKey: "settings.appearance")

        defaults.set(profileVisibility.rawValue, forKey: "settings.profileVisibility")
        defaults.set(defaultActivityVisibility.rawValue, forKey: "settings.defaultActivityVisibility")
        defaults.set(shareTrainingPresence, forKey: "settings.shareTrainingPresence")
        defaults.set(hideRouteStartAndEnd, forKey: "settings.hideRouteStartAndEnd")

        defaults.set(trainingDeviceProvider.rawValue, forKey: "settings.trainingDeviceProvider")
        defaults.set(preferredWorkoutCapture.rawValue, forKey: "settings.preferredWorkoutCapture")
        defaults.set(defaultStrengthTracking.rawValue, forKey: "settings.defaultStrengthTracking")
        defaults.set(autoPauseOutdoorWorkouts, forKey: "settings.autoPauseOutdoor")
        defaults.set(backgroundHealthSyncEnabled, forKey: "settings.backgroundHealthSyncEnabled")
        defaults.set(autoPublishCompletedWorkouts, forKey: "settings.autoPublishCompletedWorkouts")
        defaults.set(audioCuesEnabled, forKey: "settings.audioCues")
        defaults.set(hapticCuesEnabled, forKey: "settings.hapticCues")

        defaults.set(workoutRemindersEnabled, forKey: "settings.workoutReminders")
        defaults.set(friendActivityNotificationsEnabled, forKey: "settings.friendActivityNotifications")
        defaults.set(challengeNotificationsEnabled, forKey: "settings.challengeNotifications")
        defaults.set(messageNotificationsEnabled, forKey: "settings.messageNotifications")

        defaults.set(spotifyAutoplayLinkedPlaylists, forKey: "settings.spotifyAutoplayLinkedPlaylists")
        defaults.set(watchConnected, forKey: "settings.watchConnected")
        defaults.set(spotifyConnected, forKey: "settings.spotifyConnected")
        defaults.set(homeAssistantConnected, forKey: "settings.homeAssistantConnected")
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
