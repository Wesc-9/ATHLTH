import Foundation

/// Keeps the Today agenda consistent with its primary card. A live recording
/// replaces the scheduled hero; it must not cause that same session to be
/// duplicated under "Also today".
enum ATHLTHTrainTodayAgendaPolicy {
    static func remainingSessions(
        _ sessions: [PlannedSession],
        primaryWorkoutID: UUID?,
        completedIDs: Set<UUID>,
        hasPlan: Bool,
        hasActiveWorkout: Bool
    ) -> [PlannedSession] {
        let unfinished = sessions.contains {
            !$0.isExplicitRestDay && !completedIDs.contains($0.id)
        }
        let excludedPrimaryID = hasPlan && (hasActiveWorkout || unfinished)
            ? primaryWorkoutID : nil
        return sessions.filter {
            !$0.isExplicitRestDay && $0.id != excludedPrimaryID
        }
    }
}
