import Foundation
import CoreGraphics

/// Pure presentation rules: no new scoring source or network writes.
/// The comparison is deliberately advisory; accepted direct duels use the
/// existing challenge leaderboard instead.
enum CommunityMatchupVisualPolicy {
    enum Standing: Equatable {
        case leading
        case trailing
        case tied
        case unavailable
    }

    static func standing(mine: Double?, theirs: Double?) -> Standing {
        guard let mine, let theirs,
              mine.isFinite, theirs.isFinite else { return .unavailable }
        if mine > theirs { return .leading }
        if mine < theirs { return .trailing }
        return .tied
    }

    static func share(mine: Double?, theirs: Double?) -> CGFloat {
        guard let mine, let theirs,
              mine.isFinite, theirs.isFinite else { return 0.5 }
        let myScore = max(mine, 0)
        let friendScore = max(theirs, 0)
        let total = myScore + friendScore
        guard total > 0, total.isFinite else { return 0.5 }
        return CGFloat(myScore / total)
    }

    /// Matches the existing 20 + activeMinutes/5 formula (up to 120 minutes
    /// per workout); do not silently award points for missing duration data.
    static func pointsBreakdown(workouts: Double?, activeMinutes: Double?)
        -> (workoutPoints: Double, timePoints: Double)? {
        guard let workouts, workouts.isFinite, workouts >= 0 else { return nil }
        let workoutPoints = workouts * 20
        let cappedMinutes = min(max(activeMinutes ?? 0, 0), workouts * 120)
        return (workoutPoints, cappedMinutes / 5)
    }

    static func fraction(_ numerator: Double?, _ denominator: Double?) -> Double? {
        guard let numerator, let denominator,
              numerator.isFinite, denominator.isFinite,
              numerator >= 0, denominator >= 0,
              numerator + denominator > 0 else { return nil }
        return numerator / (numerator + denominator)
    }
}
