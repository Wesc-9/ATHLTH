import Foundation

/// A transparent summary of PLANNED workouts (never actual training load).
/// Keep this presentation independent from readiness and completion scores.
enum ATHLTHStudioPlanWeekSummary {
    struct Snapshot: Equatable {
        let workouts: Int
        let restDays: Int
        let knownMinutes: Int
        let missingDurationCount: Int
        let running: Int
        let strength: Int
        let other: Int
    }

    static func calculate(_ week: TrainingPlanWeek) -> Snapshot {
        let all = week.days.flatMap(\.sessions)
        let workouts = all.filter { !$0.isExplicitRestDay }
        return Snapshot(
            workouts: workouts.count,
            restDays: week.days.filter { day in
                day.sessions.isEmpty || day.sessions.allSatisfy(\.isExplicitRestDay)
            }.count,
            knownMinutes: workouts.reduce(0) { $0 + max(0, $1.durationMinutes ?? 0) },
            missingDurationCount: workouts.filter { $0.durationMinutes == nil }.count,
            running: workouts.filter { $0.kind == .running }.count,
            strength: workouts.filter { $0.kind == .strength }.count,
            other: workouts.filter { $0.kind != .running && $0.kind != .strength }.count
        )
    }

    static func date(
        for day: TrainingPlanDay,
        inWeekIndex index: Int,
        planStart: Date?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let planStart, day.dayIndex >= 1, day.dayIndex <= 7 else {
            return nil
        }
        return calendar.date(
            byAdding: .day,
            value: index * 7 + day.dayIndex - 1,
            to: calendar.startOfDay(for: planStart)
        )
    }
}
