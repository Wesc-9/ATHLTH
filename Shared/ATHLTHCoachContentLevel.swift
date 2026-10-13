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
