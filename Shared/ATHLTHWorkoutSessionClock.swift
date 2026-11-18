import Foundation

/// One date-anchored clock policy for the running and strength engines.
///
/// The recording stores remain authoritative for their persisted timestamps.
/// This pure helper adds no timer, second recording or parallel checkpoint:
/// the UI can always reconstruct the exact same elapsed time after a lock,
/// process suspension, Watch handoff or account-scoped checkpoint restore.
enum ATHLTHWorkoutSessionClock {
    /// Time accumulated before the last resume plus the active interval.
    /// A paused workout has no resumedAt and therefore cannot advance.
    static func elapsed(
        activeBeforeResume: TimeInterval,
        resumedAt: Date?,
        at date: Date
    ) -> TimeInterval {
        let stored = activeBeforeResume.isFinite
            ? max(activeBeforeResume, 0) : 0
        return stored + (resumedAt.map {
            max(date.timeIntervalSince($0), 0)
        } ?? 0)
    }

    /// Date-based work clock, excluding explicit pauses. Rest between
    /// strength sets is NOT an explicit workout pause.
    static func elapsed(
        startedAt: Date,
        pausedAt: Date?,
        excludedPauseSeconds: TimeInterval,
        at date: Date
    ) -> TimeInterval {
        let ignored = excludedPauseSeconds.isFinite
            ? max(excludedPauseSeconds, 0) : 0
        return max((pausedAt ?? date).timeIntervalSince(startedAt) - ignored, 0)
    }

    /// Countdown state persists the amount left at pause and its resume date.
    /// Do not clamp here: negative time is needed for honest overtime display.
    static func remaining(
        secondsAtPause: TimeInterval,
        resumedAt: Date?,
        at date: Date
    ) -> TimeInterval {
        secondsAtPause - (resumedAt.map {
            max(date.timeIntervalSince($0), 0)
        } ?? 0)
    }
}
