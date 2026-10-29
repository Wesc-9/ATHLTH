import Foundation

/// Adds one hypothetical session to a recent *weekly average*. This is
/// arithmetic about logged minutes, not a recovery or performance forecast.
struct ATHLTHInsightsWhatIfComparison: Equatable {
    let historicalWeeklyMinutes: Double?
    let historicalWeeklySessions: Double?
    let additionalMinutes: Int

    var projectedWeeklyMinutes: Double? {
        guard let baseline = historicalWeeklyMinutes,
              baseline.isFinite, baseline >= 0
        else { return nil }
        return baseline + Double(max(additionalMinutes, 0))
    }

    var projectedWeeklySessions: Double? {
        guard let historicalWeeklySessions,
              historicalWeeklySessions.isFinite,
              historicalWeeklySessions >= 0
        else { return nil }
        return historicalWeeklySessions + 1
    }

    var increasePercent: Double? {
        guard let historicalWeeklyMinutes, historicalWeeklyMinutes > 0 else {
            return nil
        }
        return Double(max(additionalMinutes, 0)) / historicalWeeklyMinutes * 100
    }
}
