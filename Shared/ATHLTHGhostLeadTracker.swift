import Foundation

/// Stabilizes Ghost lead changes without delaying ordinary distance metrics.
/// One noisy GPS point must never create a permanent overtake statistic or
/// trigger a spoken "you passed" event. There is no wall-clock timer.
struct ATHLTHGhostLeadTracker {
    private(set) var confirmedSign = 0
    private var candidateSign = 0
    private var candidateStart: TimeInterval?
    private var lastSampleElapsed: TimeInterval?

    mutating func reset() {
        confirmedSign = 0
        candidateSign = 0
        candidateStart = nil
        lastSampleElapsed = nil
    }

    mutating func invalidatePending() {
        candidateSign = 0
        candidateStart = nil
    }

    /// Returns true only when an established lead has reversed and the
    /// opposite leader has remained ahead over multiple unique GPS samples.
    mutating func observe(
        signedGapMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> Bool {
        guard signedGapMeters.isFinite,
              elapsedSeconds.isFinite,
              elapsedSeconds >= 0 else {
            invalidatePending()
            return false
        }
        if let lastSampleElapsed {
            guard elapsedSeconds > lastSampleElapsed else {
                // Duplicate snapshots cannot confirm a lead change.
                if elapsedSeconds < lastSampleElapsed { invalidatePending() }
                return false
            }
        }
        lastSampleElapsed = elapsedSeconds

        let direction: Int
        if signedGapMeters >= 8 {
            direction = 1
        } else if signedGapMeters <= -8 {
            direction = -1
        } else {
            direction = 0
        }

        if direction == 0 || direction == confirmedSign {
            invalidatePending()
            return false
        }
        if confirmedSign == 0 {
            confirmedSign = direction
            invalidatePending()
            return false
        }
        if direction != candidateSign {
            candidateSign = direction
            candidateStart = elapsedSeconds
            return false
        }

        guard let since = candidateStart,
              elapsedSeconds - since >= 2 else { return false }
        confirmedSign = direction
        invalidatePending()
        return true
    }
}
