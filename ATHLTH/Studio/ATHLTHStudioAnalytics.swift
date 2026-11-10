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
        // One pass through HealthKit and locally completed workouts.
        // Home can redraw after many unrelated Health changes; avoid creating
        // filtered workout arrays and scanning each day again for the chart.
        var totalsByDay: [Date: (sessions: Int, minutes: Double, distance: Double)] = [:]
        var sessions = 0
        var totalMinutes = 0.0
        var totalDistance = 0.0
        var runningSessions = 0
        var strengthSessions = 0
        for workout in workouts {
            guard workout.startDate >= first,
                  workout.startDate <= now,
                  workout.duration.isFinite,
                  workout.duration >= 0 else { continue }

            let date = calendar.startOfDay(for: workout.startDate)
            let minutes = workout.duration / 60
            let distance = max(0, workout.distanceKilometers ?? 0)
            var day = totalsByDay[date] ?? (sessions: 0, minutes: 0, distance: 0)
            day.sessions += 1
            day.minutes += minutes
            day.distance += distance
            totalsByDay[date] = day
            sessions += 1
            totalMinutes += minutes
            totalDistance += distance
            if workout.activity == .running { runningSessions += 1 }
            if workout.activity == .strength { strengthSessions += 1 }
        }
        let series: [Day] = (0..<count).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: first)
            else { return nil }
            let day = totalsByDay[date] ?? (sessions: 0, minutes: 0, distance: 0)
            return Day(
                date: date,
                minutes: day.minutes,
                distanceKilometers: day.distance,
                sessions: day.sessions
            )
        }
        return Snapshot(
            sessions: sessions,
            minutes: totalMinutes,
            distanceKilometers: totalDistance,
            runningSessions: runningSessions,
            strengthSessions: strengthSessions,
            days: series
        )
    }
}
