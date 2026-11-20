import Foundation

/// One fail-closed admission point for the currently implemented strength
/// capture owner. Sharing a planner/engine route does NOT authorize converting
/// cycling, meditation or yoga into a strength HKWorkoutSession.
///
/// No new session is allocated here. The existing recording arbiter still
/// reserves the only recording slot after this validation succeeds.
enum ATHLTHWorkoutCaptureAdmission {
    /// Resolve the correct already-supported Watch HealthKit activity for
    /// an explicitly named simple workout. This is only a capture *choice*;
    /// it does not allocate a new workout, change the saved plan, or claim
    /// support for a mixed scripted Watch session.
    static func watchKind(for workout: PlannedSession) -> WatchWorkoutKind? {
        let category = ATHLTHUnifiedActivityProfile.category(for: workout)
        guard category != "hybrid" else { return nil }

        // Preserve the current dedicated running/walking/strength Watch
        // transfer path and reject contradictory legacy sport metadata.
        switch workout.kind {
        case .running:
            return ["running", "treadmill"].contains(category)
                ? .running : nil
        case .walking:
            return category == "walking" ? .walking : nil
        case .strength:
            return category == "strength" ? .strength : nil
        case .mobility, .recovery, .custom:
            break
        }

        // Other structured recipes may contain multiple timing instructions,
        // strength sets or activity changes. Current prepared Watch payloads
        // cannot execute them and must not silently discard those steps.
        guard !workout.isStructuredWorkout else { return nil }
        switch category {
        case "cycling": return .cycling
        case "rowing": return .rowing
        case "stairclimber": return .stairClimbing
        case "hiit": return .hiit
        case "circuit", "functional": return .functional
        case "mobility":
            let explicit = workout.workoutCategory?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return explicit == "yoga" ? .yoga : .other
        case "sports", "other": return .other
        // Meditation is not a yoga workout. Its dedicated kind does not
        // exist on the current Watch target; never mislabel its HealthKit data.
        default: return nil
        }
    }

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
