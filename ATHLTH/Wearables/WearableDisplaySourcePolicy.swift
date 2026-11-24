import Foundation

enum WearableDisplayMetric { case sleep, steps, hrv, restingHeartRate }

enum WearableDisplayPreference: String, CaseIterable, Identifiable {
    case automatic, appleHealth, garmin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatisk"
        case .appleHealth: return "Apple Helse først"
        case .garmin: return "Garmin først"
        }
    }
}

struct GarminDisplayReading: Equatable {
    let metric: WearableDisplayMetric
    let value: Double

    var sourceLabel: String { metric == .hrv ? "Garmin natt" : "Garmin" }
    var formattedValue: String {
        switch metric {
        case .sleep:
            let minutes = Int((value / 60).rounded())
            return "\(minutes / 60)t \(minutes % 60)m"
        case .steps: return Int(value.rounded(.down)).formatted()
        case .hrv: return "\(Int(value.rounded())) ms"
        case .restingHeartRate: return "\(Int(value.rounded())) bpm"
        }
    }
}

enum WearableDisplaySourcePolicy {
    /// A display choice, not a health-data write or merged readiness baseline.
    /// Garmin overnight HRV remains separately labelled. Never sum sources.
    static func garminReading(metric: WearableDisplayMetric, apple: Double?,
                              garmin: Double?, preference: WearableDisplayPreference) -> GarminDisplayReading? {
        func valid(_ value: Double?) -> Bool {
            guard let value, value.isFinite, value >= 0, value < 1_000_000_000 else { return false }
            return metric == .steps || value > 0
        }
        guard let garmin, valid(garmin) else { return nil }
        if preference != .garmin && valid(apple) { return nil }
        return GarminDisplayReading(metric: metric, value: garmin)
    }
}
