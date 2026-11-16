import Foundation

/// A plan-day quick walk does not necessarily carry an explicit activity
/// parameter into Workout Studio. Preserve its canonical walking block when
/// the athlete selects a route, instead of silently turning it into running.
enum ATHLTHWalkingRouteAssignmentPolicy {
    static func isWalking(
        initialActivity: ATHLTHPlannedWorkoutType?,
        blocks: [WorkoutTemplateBlock],
        phase: WorkoutPhaseKind
    ) -> Bool {
        initialActivity == .walking || blocks.contains {
            $0.kind == .run && $0.cardioActivity == .walking &&
                $0.resolvedPhase == phase
        }
    }
}
