import Foundation

/// Pauses routine/structured Audio Coach speech without changing independent
/// Route Guardian, target or Ghost voice choices and without gating haptics,
/// timers, HealthKit capture or location recording.
enum ATHLTHCoachVoicePausePolicy {
    static func allowsSpeech(
        coachEnabled: Bool,
        speechPaused: Bool,
        priority: ATHLTHGuidancePriority
    ) -> Bool {
        switch priority {
        case .routineCoach, .structuredStep:
            return coachEnabled && !speechPaused
        case .ghostPeriodic, .ghostImportant,
             .targetCritical, .routeCritical:
            // These alerts have their own user-controlled enable/delivery
            // settings; an Audio Coach-only mute must not override them.
            return true
        }
    }
}
