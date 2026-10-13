import Foundation

/// One deterministic timeline for Replay and Target Ghost on iPhone and Watch.
/// The caller owns the samples, so live updates do not need to allocate arrays.
enum ATHLTHGhostTimeline {
    struct Bracket {
        let lower: Int
        let upper: Int
        let fraction: Double
    }

    /// Interpolate on an increasing timeline (elapsed seconds or route metres).
    /// Equal neighbouring timestamps/distances are handled without division by zero.
    static func bracket(
        at target: Double,
        count: Int,
        position: (Int) -> Double
    ) -> Bracket? {
        guard count > 0, target.isFinite else { return nil }
        let first = position(0)
        let last = position(count - 1)
        guard first.isFinite, last.isFinite, last >= first else { return nil }

        if count == 1 || target <= first {
            return Bracket(lower: 0, upper: 0, fraction: 0)
        }
        if target >= last {
            return Bracket(lower: count - 1, upper: count - 1, fraction: 0)
        }

        // Upper bound: first position strictly greater than target.
        var low = 1
        var high = count - 1
        while low < high {
            let mid = low + (high - low) / 2
            if position(mid) <= target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let upper = low
        let lower = upper - 1
        let start = position(lower)
        let end = position(upper)
        guard start.isFinite, end.isFinite, end > start else { return nil }
        return Bracket(
            lower: lower,
            upper: upper,
            fraction: min(max((target - start) / (end - start), 0), 1)
        )
    }

    static func interpolate(
        at target: Double,
        count: Int,
        position: (Int) -> Double,
        value: (Int) -> Double
    ) -> Double? {
        guard let bounds = bracket(
            at: target,
            count: count,
            position: position
        ) else { return nil }

        let a = value(bounds.lower)
        let b = value(bounds.upper)
        guard a.isFinite, b.isFinite else { return nil }
        return a + (b - a) * bounds.fraction
    }
}
