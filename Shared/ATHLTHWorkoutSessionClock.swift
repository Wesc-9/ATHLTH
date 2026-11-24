import Foundation

/// One date-anchored clock policy for the running and strength engines.
///
/// The recording stores remain authoritative for their persisted timestamps.
/// This pure helper adds no timer, second recording or parallel checkpoint:
/// the UI can always reconstruct the exact same elapsed time after a lock,
/// process suspension, Watch handoff or account-scoped checkpoint restore.
enum ATHLTHWorkoutSessionClock {
    static func finiteInterval(from start: Date, to end: Date) -> TimeInterval? {
        guard start.timeIntervalSince1970.isFinite,
              end.timeIntervalSince1970.isFinite else { return nil }
        let interval = end.timeIntervalSince(start)
        return interval.isFinite ? interval : nil
    }

    private static func activeInterval(from start: Date, to end: Date) -> TimeInterval {
        max(finiteInterval(from: start, to: end) ?? 0, 0)
    }

    /// Time accumulated before the last resume plus the active interval.
    /// A paused workout has no resumedAt and therefore cannot advance.
    static func elapsed(
        activeBeforeResume: TimeInterval,
        resumedAt: Date?,
        at date: Date
    ) -> TimeInterval {
        let stored = activeBeforeResume.isFinite
            ? max(activeBeforeResume, 0) : 0
        let total = stored + (resumedAt.map { activeInterval(from: $0, to: date) } ?? 0)
        return total.isFinite ? total : stored
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
        return max(activeInterval(from: startedAt, to: pausedAt ?? date) - ignored, 0)
    }

    /// Countdown state persists the amount left at pause and its resume date.
    /// Do not clamp here: negative time is needed for honest overtime display.
    static func remaining(
        secondsAtPause: TimeInterval,
        resumedAt: Date?,
        at date: Date
    ) -> TimeInterval {
        let stored = secondsAtPause.isFinite ? secondsAtPause : 0
        let remaining = stored - (resumedAt.map { activeInterval(from: $0, to: date) } ?? 0)
        return remaining.isFinite ? remaining : stored
    }
}
