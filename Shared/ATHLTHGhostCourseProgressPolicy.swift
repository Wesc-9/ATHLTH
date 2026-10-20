import Foundation

/// Fixed-course Ghost comparisons never credit raw workout distance as route
/// progress. Extra distance during a detour costs time, not free course metres.
enum ATHLTHGhostCourseProgressPolicy {
    /// GPS locations within this corridor are eligible for a comparison.
    /// The route's own alert threshold can be tighter than this cap.
    static func trustedCorridorMeters(alertThresholdMeters: Double) -> Double {
        guard alertThresholdMeters.isFinite else { return 35 }
        return max(20, min(alertThresholdMeters, 50))
    }

    static func isReliableOnRoute(
        horizontalAccuracy: Double,
        deviationMeters: Double,
        alertThresholdMeters: Double
    ) -> Bool {
        horizontalAccuracy.isFinite &&
            (0...30).contains(horizontalAccuracy) &&
            deviationMeters.isFinite &&
            (0...trustedCorridorMeters(
                alertThresholdMeters: alertThresholdMeters
            )).contains(deviationMeters)
    }

    /// Prevent impossible progress teleports after GPS loss, crossings or
    /// off-route detours. The elapsed interval permits a genuine later rejoin
    /// without mistaking unrecorded route distance for a completed lap.
    static func plausibleCourseAdvance(
        previousMeters: Double?,
        previousElapsed: TimeInterval?,
        candidateMeters: Double,
        elapsed: TimeInterval
    ) -> Bool {
        guard candidateMeters.isFinite, candidateMeters >= 0,
              elapsed.isFinite, elapsed >= 0 else { return false }
        guard let previousMeters, let previousElapsed else { return true }
        guard previousMeters.isFinite, previousElapsed.isFinite,
              elapsed >= previousElapsed else { return false }

        // Allow small backward GPS corrections, but no major rewind.
        if candidateMeters < previousMeters {
            return previousMeters - candidateMeters <= 35
        }
        let seconds = elapsed - previousElapsed
        return candidateMeters - previousMeters <= 35 + seconds * 9
    }

    /// A positive result means the Ghost is farther along the specified route.
    static func ghostLeadPercent(
        runnerCourseMeters: Double,
        ghostCourseMeters: Double,
        routeLengthMeters: Double
    ) -> Double? {
        guard runnerCourseMeters.isFinite, ghostCourseMeters.isFinite,
              routeLengthMeters.isFinite, routeLengthMeters >= 500 else {
            return nil
        }
        let own = min(max(runnerCourseMeters, 0), routeLengthMeters)
        let ghost = min(max(ghostCourseMeters, 0), routeLengthMeters)
        return (ghost - own) / routeLengthMeters * 100
    }

    /// Announce only significant changes, not a repeated status on every
    /// good GPS fix after returning to the planned course.
    static func shouldAnnouncePercentGap(
        ghostLeadPercent: Double,
        lastAnnouncedPercent: Double?,
        secondsSinceLast: TimeInterval?
    ) -> Bool {
        guard ghostLeadPercent.isFinite,
              abs(ghostLeadPercent) >= 5 else { return false }

        guard let lastAnnouncedPercent else { return true }
        guard let secondsSinceLast, secondsSinceLast >= 480 else {
            return false
        }
        return abs(ghostLeadPercent - lastAnnouncedPercent) >= 5
    }
}
