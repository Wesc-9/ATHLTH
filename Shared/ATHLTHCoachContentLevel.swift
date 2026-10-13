import Foundation

/// Audio Coach information density. Trigger intervals and voice delivery
/// are intentionally independent and never overwritten by a content preset.
enum ATHLTHCoachContentLevel: String, CaseIterable, Identifiable, Codable {
    case simple
    case standard
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple:
            return ATHLTHLocalization.choose(
                english: "Simple", norwegian: "Enkel"
            )
        case .standard:
            return ATHLTHLocalization.choose(
                english: "Standard", norwegian: "Standard"
            )
        case .advanced:
            return ATHLTHLocalization.choose(
                english: "Advanced", norwegian: "Avansert"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .simple:
            return ATHLTHLocalization.choose(
                english: "The essentials",
                norwegian: "Kun det viktigste"
            )
        case .standard:
            return ATHLTHLocalization.choose(
                english: "Balanced guidance",
                norwegian: "Balansert veiledning"
            )
        case .advanced:
            return ATHLTHLocalization.choose(
                english: "Detailed workout insight",
                norwegian: "Detaljerte treningsdata"
            )
        }
    }

    /// Caller preserves on/off, language, distance/time intervals, voice,
    /// quiet period, Watch ownership and user-selected output route.
    func applying(
        to original: WatchAudioCoachConfiguration
    ) -> WatchAudioCoachConfiguration {
        var value = original
        value.announceDistance = true
        value.announceElapsedTime = true
        value.announceAveragePace = self != .simple
        value.announceClockTime = self == .advanced
        value.announceHeartRate = self == .advanced
        value.announceRemainingRouteDistance = self != .simple
        value.announceEstimatedRemainingRouteTime = self == .advanced
        value.announceCurrentWorkoutStep = true
        value.announceRemainingStepTime = self != .simple
        value.announceRemainingStepDistance = self == .advanced
        // Start/pause/end cues are useful at every level.
        value.announceWorkoutStart = true
        value.announcePauseResume = true
        value.announceWorkoutComplete = true
        return value
    }

    static func matching(
        _ configuration: WatchAudioCoachConfiguration
    ) -> ATHLTHCoachContentLevel? {
        allCases.first { level in
            let match = level.applying(to: configuration)
            return Self.contentSignature(match) ==
                Self.contentSignature(configuration)
        }
    }

    private static func contentSignature(
        _ value: WatchAudioCoachConfiguration
    ) -> [Bool] {
        [
            value.announceDistance,
            value.announceElapsedTime,
            value.announceAveragePace,
            value.announceClockTime,
            value.announceHeartRate,
            value.announceRemainingRouteDistance,
            value.announceEstimatedRemainingRouteTime,
            value.announceCurrentWorkoutStep,
            value.announceRemainingStepTime,
            value.announceRemainingStepDistance,
            value.shouldAnnounceWorkoutStart,
            value.shouldAnnouncePauseResume,
            value.shouldAnnounceWorkoutComplete
        ]
    }
}

 
/// Consistent user-facing coaching intensity across supported workouts.
/// The underlying content, voice, delivery and device models remain unchanged.
enum ATHLTHCoachExperiencePreset: String, CaseIterable, Identifiable {
    case calm, balanced, active

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return ATHLTHLocalization.choose(english: "Calm", norwegian: "Rolig")
        case .balanced: return ATHLTHLocalization.choose(english: "Balanced", norwegian: "Balansert")
        case .active: return ATHLTHLocalization.choose(english: "Active", norwegian: "Aktiv")
        }
    }

    var subtitle: String {
        switch self {
        case .calm: return ATHLTHLocalization.choose(
            english: "Key moments only", norwegian: "Bare det viktigste")
        case .balanced: return ATHLTHLocalization.choose(
            english: "Regular guidance", norwegian: "Passe mye veiledning")
        case .active: return ATHLTHLocalization.choose(
            english: "More detailed updates", norwegian: "Tett oppfølging")
        }
    }

    var contentLevel: ATHLTHCoachContentLevel {
        switch self {
        case .calm: return .simple
        case .balanced: return .standard
        case .active: return .advanced
        }
    }

    var speechStyle: ATHLTHCoachSpeechStyle {
        switch self {
        case .calm: return .minimal
        case .balanced: return .balanced
        case .active: return .motivating
        }
    }

    var distanceIntervalKilometers: Double {
        switch self {
        case .calm: return 2.0
        case .balanced: return 1.0
        case .active: return 0.5
        }
    }
}


extension ATHLTHCoachExperiencePreset {
    /// Watch-facing preset. Preserves audio route, voice, safety notifications
    /// and active HealthKit session settings. Does not require new wire fields.
    func applying(
        to original: WatchAudioCoachConfiguration,
        kind: WatchWorkoutKind
    ) -> WatchAudioCoachConfiguration {
        var value = original
        if kind == .strength {
            value.announceStrengthRestComplete = true
            value.announceStrengthNextExercise = true
            switch self {
            case .calm:
                value.announceStrengthSetComplete = false
                value.announceStrengthRestStarted = false
                value.announceStrengthRestCountdown = false
                value.announceStrengthNextSetDetails = false
                value.announceStrengthExerciseProgress = false
                value.strengthStatusIntervalSeconds = nil
            case .balanced:
                value.announceStrengthSetComplete = true
                value.announceStrengthRestStarted = false
                value.announceStrengthRestCountdown = true
                value.announceStrengthNextSetDetails = true
                value.announceStrengthExerciseProgress = false
                value.strengthStatusIntervalSeconds = nil
            case .active:
                value.announceStrengthSetComplete = true
                value.announceStrengthRestStarted = true
                value.announceStrengthRestCountdown = true
                value.announceStrengthNextSetDetails = true
                value.announceStrengthExerciseProgress = true
                value.strengthStatusIntervalSeconds = 15 * 60
            }
        } else {
            value = contentLevel.applying(to: value)
            if kind == .running || kind == .walking {
                value.distanceIntervalMeters = distanceIntervalKilometers * 1_000
                value.timeIntervalSeconds = nil
            } else {
                // No GPS distance requirement for HIIT, yoga or other sports.
                value.distanceIntervalMeters = nil
                switch self {
                case .calm: value.timeIntervalSeconds = 15 * 60
                case .balanced: value.timeIntervalSeconds = 10 * 60
                case .active: value.timeIntervalSeconds = 5 * 60
                }
            }
        }
        value.enabled = true
        value.speechStyle = speechStyle
        return value
    }

    func matches(
        _ configuration: WatchAudioCoachConfiguration,
        kind: WatchWorkoutKind
    ) -> Bool {
        guard configuration.enabled,
              (configuration.speechStyle ?? .balanced) == speechStyle
        else { return false }

        let expected = applying(to: configuration, kind: kind)
        if kind == .strength {
            return configuration.shouldAnnounceStrengthSetComplete ==
                expected.shouldAnnounceStrengthSetComplete
                && configuration.shouldAnnounceStrengthRestStarted ==
                expected.shouldAnnounceStrengthRestStarted
                && configuration.shouldAnnounceStrengthRestCountdown ==
                expected.shouldAnnounceStrengthRestCountdown
                && configuration.shouldAnnounceStrengthRestComplete ==
                expected.shouldAnnounceStrengthRestComplete
                && configuration.shouldAnnounceStrengthNextExercise ==
                expected.shouldAnnounceStrengthNextExercise
                && configuration.shouldAnnounceStrengthNextSetDetails ==
                expected.shouldAnnounceStrengthNextSetDetails
                && configuration.shouldAnnounceStrengthExerciseProgress ==
                expected.shouldAnnounceStrengthExerciseProgress
                && configuration.strengthStatusIntervalSeconds ==
                expected.strengthStatusIntervalSeconds
        }
        return ATHLTHCoachContentLevel.matching(configuration) == contentLevel
            && configuration.distanceIntervalMeters ==
                expected.distanceIntervalMeters
            && configuration.timeIntervalSeconds ==
                expected.timeIntervalSeconds
    }
}
