import Foundation

/// Read-only aggregates of locally available workout summaries.
/// No health values leave the device and no planned session counts as completed.
enum ATHLTHStudioAnalytics {
    struct Day: Identifiable {
        let date: Date
        let minutes: Double
        let distanceKilometers: Double
        let sessions: Int
        var id: Date { date }
    }

    struct Snapshot {
        let sessions: Int
        let minutes: Double
        let distanceKilometers: Double
        let runningSessions: Int
        let strengthSessions: Int
        let days: [Day]
    }

    static func snapshot(
        from workouts: [WorkoutSummary],
        days: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Snapshot {
        let count = max(1, min(days, 365))
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        let inRange = workouts.filter {
            $0.startDate >= first && $0.startDate <= now && $0.duration.isFinite && $0.duration >= 0
        }
        let groups = Dictionary(grouping: inRange) { calendar.startOfDay(for: $0.startDate) }
        let series: [Day] = (0..<count).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: first) else { return nil }
            let rows = groups[date] ?? []
            return Day(
                date: date,
                minutes: rows.reduce(0) { $0 + $1.duration / 60 },
                distanceKilometers: rows.reduce(0) { $0 + max(0, $1.distanceKilometers ?? 0) },
                sessions: rows.count
            )
        }
        return Snapshot(
            sessions: inRange.count,
            minutes: series.reduce(0) { $0 + $1.minutes },
            distanceKilometers: series.reduce(0) { $0 + $1.distanceKilometers },
            runningSessions: inRange.filter { $0.activity == .running }.count,
            strengthSessions: inRange.filter { $0.activity == .strength }.count,
            days: series
        )
    }
}
