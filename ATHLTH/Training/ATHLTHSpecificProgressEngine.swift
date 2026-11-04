import Foundation

/// One consistent period and identity policy for exercise and interval
/// comparisons. Only completed, recorded values enter these trends.
enum ATHLTHSpecificProgressEngine {
    enum Period: String, CaseIterable, Identifiable {
        case week, month, year, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: return ATHLTHLocalization.choose(english: "Week", norwegian: "Uke")
            case .month: return ATHLTHLocalization.choose(english: "Month", norwegian: "Måned")
            case .year: return ATHLTHLocalization.choose(english: "Year", norwegian: "År")
            case .all: return ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
            }
        }
        func start(now: Date, calendar: Calendar = .current) -> Date {
            switch self {
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
            case .month:
                return calendar.date(byAdding: .month, value: -1, to: now) ?? .distantPast
            case .year:
                return calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
            case .all: return .distantPast
            }
        }
    }

    struct IntervalChoice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// Stable source-workout ID takes precedence over matching a user title.
    /// Title fallback is only used when older recordings have no source ID.
    static func identity(_ recording: ATHLTHCompletedRunningPerformance) -> String {
        if let id = recording.workoutID { return "template:\(id.uuidString)" }
        return "legacy:" + ATHLTHTrainTrendEngine.normalize(recording.title)
    }

    static func isFourByFour(_ recording: ATHLTHCompletedRunningPerformance) -> Bool {
        let work = recording.workSteps
        guard work.count == 4 else { return false }
        // Allow measured effort drift; never infer 4x4 from the title alone.
        return work.allSatisfy { $0.activeSeconds >= 150 && $0.activeSeconds <= 330 }
    }

    static func intervalChoices(
        _ recordings: [ATHLTHCompletedRunningPerformance]
    ) -> [IntervalChoice] {
        let valid = recordings.filter { $0.averageWorkSpeed != nil }
        let unique = Dictionary(grouping: valid, by: identity)
        var choices = unique.compactMap { id, items -> IntervalChoice? in
            guard let latest = items.max(by: { $0.completedAt < $1.completedAt }) else {
                return nil
            }
            return IntervalChoice(id: id, name: latest.title)
        }
        if valid.contains(where: isFourByFour) {
            choices.append(IntervalChoice(
                id: "benchmark:4x4",
                name: ATHLTHLocalization.choose(
                    english: "4 × 4 intervals", norwegian: "4 × 4-intervaller"
                )
            ))
        }
        return choices.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func intervalRecords(
        key: String,
        from all: [ATHLTHCompletedRunningPerformance],
        period: Period,
        now: Date = Date()
    ) -> [ATHLTHCompletedRunningPerformance] {
        var seen = Set<UUID>()
        return all.filter { record in
            record.completedAt <= now &&
            record.completedAt >= period.start(now: now) &&
            record.averageWorkSpeed != nil &&
            (key == "benchmark:4x4" ? isFourByFour(record) : identity(record) == key) &&
            seen.insert(record.id).inserted
        }.sorted { $0.completedAt < $1.completedAt }
    }

    static func speedChange(
        _ runs: [ATHLTHCompletedRunningPerformance]
    ) -> Double? {
        guard runs.count >= 2,
              let first = runs.first?.averageWorkSpeed,
              let last = runs.last?.averageWorkSpeed else { return nil }
        return last - first
    }

    static func weightChange(
        _ points: [ATHLTHTrainTrendEngine.Point]
    ) -> Double? {
        let measured = points.compactMap(\.peakWeightKilograms)
        guard measured.count >= 2 else { return nil }
        return measured[measured.count - 1] - measured[0]
    }
}
