import Foundation

/// Minimal training schedule and goals the athlete permits Coach to inspect
/// for a single question. Never includes private training addresses, user
/// notes, medical information, friend's IDs or invitation details.
enum ATHLTHCoachTrainingContext {
    struct UpcomingSession: Codable, Equatable {
        let title: String
        let activity: String
        let date: String
        let durationMinutes: Int?
    }

    struct Snapshot: Codable, Equatable {
        let planTitle: String?
        let planVersion: Int?
        let upcoming: [UpcomingSession]
        let goalTitles: [String]
    }

    static func snapshot(
        activePlan: TrainingPlan?,
        goals: [ATHLTHGoal],
        now: Date = Date()
    ) -> Snapshot {
        let calendar = Calendar.current
        let iso = ISO8601DateFormatter()
        let upcoming: [UpcomingSession]
        if let plan = activePlan, let startDate = plan.startDate {
            let start = calendar.startOfDay(for: startDate)
            upcoming = plan.weeks.flatMap { week in
                week.days.flatMap { day -> [(Date, PlannedSession)] in
                    guard let date = calendar.date(
                        byAdding: .day,
                        value: max(week.weekNumber - 1, 0) * 7 +
                            max(day.dayIndex - 1, 0),
                        to: start
                    ), date >= calendar.startOfDay(for: now) else { return [] }
                    return day.sessions.map { (date, $0) }
                }
            }
            .sorted { $0.0 < $1.0 }
            .prefix(12)
            .map { date, session in
                UpcomingSession(
                    title: String(session.title.prefix(100)),
                    activity: session.kind.rawValue,
                    date: iso.string(from: date),
                    durationMinutes: session.durationMinutes
                )
            }
        } else {
            upcoming = []
        }
        return Snapshot(
            planTitle: activePlan.map { String($0.title.prefix(100)) },
            planVersion: activePlan?.version,
            upcoming: upcoming,
            goalTitles: goals.prefix(6).map { String($0.title.prefix(100)) }
        )
    }
}
