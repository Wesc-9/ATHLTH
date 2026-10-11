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
