import Foundation

/// Voice-only session control. This policy never gates haptics, timers,
/// location, HealthKit capture, or remote workout mirroring.
enum ATHLTHCoachVoicePausePolicy {
    static func allowsSpeech(
        coachEnabled: Bool,
        speechPaused: Bool
    ) -> Bool {
        coachEnabled && !speechPaused
    }
}
