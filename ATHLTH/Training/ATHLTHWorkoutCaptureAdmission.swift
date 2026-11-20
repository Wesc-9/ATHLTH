import Foundation

/// One fail-closed admission point for the currently implemented strength
/// capture owner. Sharing a planner/engine route does NOT authorize converting
/// cycling, meditation or yoga into a strength HKWorkoutSession.
///
/// No new session is allocated here. The existing recording arbiter still
/// reserves the only recording slot after this validation succeeds.
enum ATHLTHWorkoutCaptureAdmission {
    enum Rejection: LocalizedError, Equatable {
        case requiresDedicatedActivityCapture

        var errorDescription: String? {
            switch self {
            case .requiresDedicatedActivityCapture:
                return ATHLTHLocalization.choose(
                    english: "This activity needs a supported workout recorder. Edit the workout or choose the correct activity before starting.",
                    norwegian: "Denne aktiviteten trenger en støttet treningsopptaker. Endre økten eller velg riktig aktivitet før du starter."
                )
            }
        }
    }

    /// Existing supported starts:
    /// - ordinary strength;
    /// - already validated running + strength hybrids.
    /// Rest, instructions and active recovery remain inside the same workout.
    ///
    /// A cycling/wellness segment must NOT be silently recorded as strength,
    /// even if the parent plan was saved with an old 'strength' kind.
    static func requireSupportedStrengthCapture(
        for workout: PlannedSession
    ) throws {
        let blocks = workout.resolvedWorkoutBlocks
        let hasOtherActivity = blocks.contains {
            ATHLTHWorkoutActivityTagPolicy.activity(for: $0) != nil
        }
        let hasWellness = blocks.contains { $0.wellnessKind != nil }
        let hasRunning = blocks.contains {
            $0.kind == .run && !$0.isActiveRecovery
        }
        let hasStrength = !workout.exercises.isEmpty ||
            blocks.contains { $0.kind == .exercise }
        let category = ATHLTHUnifiedActivityProfile.category(for: workout)

        guard !hasOtherActivity, !hasWellness else {
            throw Rejection.requiresDedicatedActivityCapture
        }
        // A run-only or unrelated 'custom' session cannot be started
        // through the strength engine just because a caller chose it.
        if hasRunning && !hasStrength {
            throw Rejection.requiresDedicatedActivityCapture
        }
        guard ["strength", "hybrid", "custom"].contains(category) else {
            throw Rejection.requiresDedicatedActivityCapture
        }
        // Some old plans keep a broad .strength kind even after their
        // explicit sport category changes. Never record those as strength.
        let declared = workout.workoutCategory?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !hasStrength, let declared,
           !["strength", "custom"].contains(declared) {
            throw Rejection.requiresDedicatedActivityCapture
        }
        if category == "hybrid" && !(hasStrength && hasRunning) {
            throw Rejection.requiresDedicatedActivityCapture
        }
        if !hasStrength && workout.kind != .strength {
            throw Rejection.requiresDedicatedActivityCapture
        }
    }
}
