import Foundation

/// A deterministic, optional final-phase cue. Never suggest a pace when
/// the target has already finished or GPS progress is not trustworthy.
enum ATHLTHGhostFinishPaceCoach {
    static func requiredSecondsPerKilometre(
        remainingMeters: Double,
        elapsedSeconds: TimeInterval,
        ghostFinishSeconds: TimeInterval
    ) -> TimeInterval? {
        guard remainingMeters.isFinite,
              (20...5_000).contains(remainingMeters),
              elapsedSeconds.isFinite, elapsedSeconds >= 0,
              ghostFinishSeconds.isFinite,
              ghostFinishSeconds > elapsedSeconds else { return nil }

        let timeRemaining = ghostFinishSeconds - elapsedSeconds
        let required = timeRemaining * 1_000 / remainingMeters
        // Never encourage an unrealistic sprint, and do not turn a
        // meaningless GPS jump into an actionable training instruction.
        guard required.isFinite, (180...1_200).contains(required)
        else { return nil }
        return required
    }

    static func minuteSecondText(_ seconds: TimeInterval) -> String {
        let rounded = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
