import Foundation

/// Transparent planning arithmetic. A training-minute comparison is never
/// presented as a prediction of readiness, fitness gains or injury risk.
struct ATHLTHInsightsWhatIfComparison: Equatable {
    let historicalWeeklyMinutes: Double?
    let historicalWeeklySessions: Double?
    let proposedSessions: Int
    let minutesPerSession: Int

    var proposedWeeklyMinutes: Double {
        Double(max(proposedSessions, 0) * max(minutesPerSession, 0))
    }

    var hasHistory: Bool {
        historicalWeeklyMinutes != nil && historicalWeeklySessions != nil
    }

    var differenceMinutes: Double? {
        guard let historicalWeeklyMinutes else { return nil }
        return proposedWeeklyMinutes - historicalWeeklyMinutes
    }

    var changePercent: Double? {
        guard let historicalWeeklyMinutes, historicalWeeklyMinutes > 0 else {
            return nil
        }
        return (proposedWeeklyMinutes - historicalWeeklyMinutes) /
            historicalWeeklyMinutes * 100
    }

    /// Meaningfully different means at least a quarter hour per week;
    /// anything smaller than that is a near match, not a fitness claim.
    var direction: Direction {
        guard let differenceMinutes else { return .unknown }
        if differenceMinutes >= 15 { return .more }
        if differenceMinutes <= -15 { return .less }
        return .similar
    }

    enum Direction: Equatable {
        case unknown, more, less, similar
    }
}
