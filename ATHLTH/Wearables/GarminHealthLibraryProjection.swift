import Foundation

struct GarminLibraryReading {
    let value: Double
    let source: String
}

#if ATHLTH_GARMIN_PERSONAL && DEBUG
extension HomeHealthMetricKind {
    var garminLibraryMetric: ATHLTHInsightHealthMetric? {
        switch self {
        case .sleep: return .sleepDuration
        case .steps: return .steps
        case .hrv: return .hrv
        default: return nil
        }
    }
}

@MainActor
extension GarminPersonalLocalStore {
    func libraryReading(_ metric: ATHLTHInsightHealthMetric, account: UUID,
                        apple: Double?) -> GarminLibraryReading? {
        guard let snapshot = snapshot(for: account),
              Calendar.current.isDateInToday(snapshot.measurementDay) else { return nil }
        let value: Double?
        switch metric {
        case .sleepDuration: value = snapshot.sleepSeconds.map { $0 / 3600 }
        // Garmin light sleep is not Apple Core; only the stages card labels it as light.
        case .sleepDeep: value = snapshot.sleepStages?.deepSleepSeconds.map { $0 / 3600 }
        case .sleepREM: value = snapshot.sleepStages?.remSleepSeconds.map { $0 / 3600 }
        case .sleepAwake: value = snapshot.sleepStages?.awakeSleepSeconds.map { $0 / 3600 }
        case .steps: value = snapshot.steps.map(Double.init)
        case .hrv: value = snapshot.overnightHRV
        case .restingHeartRate: value = snapshot.restingHeartRate
        case .activeEnergy: value = snapshot.activeEnergy
        case .basalEnergy: value = snapshot.basalEnergy
        default: return nil
        }
        guard let value, value.isFinite, value >= 0, value < 1_000_000_000 else { return nil }
        let zeroAllowed = metric == .steps || metric == .activeEnergy || metric == .sleepDeep ||
                          metric == .sleepREM || metric == .sleepAwake
        guard zeroAllowed || value > 0 else { return nil }
        if preference(for: account) != .garmin,
           let apple, apple.isFinite, apple >= 0, (zeroAllowed || apple > 0) { return nil }
        return GarminLibraryReading(value: value, source: metric == .hrv ? "Garmin natt-HRV" : "Garmin")
    }

    func libraryHistory(_ metric: ATHLTHInsightHealthMetric, account: UUID,
                        days: Int) -> [ATHLTHInsightHealthDay] {
        guard let snapshot = snapshot(for: account), days > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(min(days, 30) - 1), to: today) else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        var raw: [String: Double]
        switch metric {
        case .steps: raw = snapshot.stepsHistory
        case .hrv: raw = snapshot.hrvHistory
        case .restingHeartRate: raw = snapshot.restingHeartHistory
        default: raw = [:]
        }
        if let current = libraryReading(metric, account: account, apple: nil) {
            raw[formatter.string(from: snapshot.measurementDay)] = current.value
        }
        return raw.compactMap { key, value -> ATHLTHInsightHealthDay? in
            guard let date = formatter.date(from: key), date >= start, date <= today,
                  value.isFinite, value >= 0, value < 1_000_000_000 else { return nil }
            return ATHLTHInsightHealthDay(date: date, value: value)
        }.sorted { $0.date < $1.date }
    }
}
#endif
