import Foundation

/// A strictly factual read-only summary for the iPad Studio command header.
/// Completed *plan* workouts require their explicit plan/session identity;
/// unrelated Apple Health activity never silently completes a plan item.
struct ATHLTHStudioDashboardHeaderPulse: Equatable {
    let plannedSessions: Int
    let completedSessions: Int
    /// nil means that Health activity is unavailable, not zero activity.
    let recordedMinutes: Int?

    static func make(
        week: ATHLTHStudioHomeWeek.Snapshot,
        completedOccurrenceIDs: Set<String>,
        healthAvailable: Bool
    ) -> Self {
        let planEntries = week.days
            .flatMap(\.planned)
            .filter { $0.planID != nil }
        let completed = planEntries.filter {
            completedOccurrenceIDs.contains($0.id)
        }.count

        let minutes: Int?
        if healthAvailable {
            let seconds = week.days.flatMap(\.recorded)
                .filter { $0.duration.isFinite && $0.duration >= 0 }
                .reduce(0.0) { $0 + $1.duration }
            minutes = Int((seconds / 60).rounded())
        } else {
            minutes = nil
        }

        return Self(
            plannedSessions: planEntries.count,
            completedSessions: completed,
            recordedMinutes: minutes
        )
    }
}
