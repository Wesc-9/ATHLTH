import Foundation

/// One fail-closed admission point for the currently implemented strength
/// capture owner. Sharing a planner/engine route does NOT authorize converting
/// cycling, meditation or yoga into a strength HKWorkoutSession.
///
/// No new session is allocated here. The existing recording arbiter still
/// reserves the only recording slot after this validation succeeds.
/// One physical recorder choice per complete planned recipe, irrespective
/// of whether the start action originated in Train, Home or the calendar.
/// This never creates an extra HealthKit session or rewrites a saved plan.
enum ATHLTHPlannedWorkoutCaptureRoute: Equatable {
    case phoneEndurance
    case phoneStrength
    case phoneStructuredManual
    case phoneHybridStrength
    case watchEndurance
    case watchStrength
    case watchSport(WatchWorkoutKind)
    case watchHybridStrength
    case unavailable

    /// Only these routes can be represented by the existing Today payload.
    /// A Watch hybrid requires its own validated one-session start path.
    var canUsePreparedWatchTransfer: Bool {
        switch self {
        case .watchEndurance, .watchStrength, .watchSport:
            return true
        default:
            return false
        }
    }

    static func resolve(
        _ workout: PlannedSession, device: WorkoutCaptureDevice
    ) -> Self {
        guard !workout.isExplicitRestDay else { return .unavailable }
        if ATHLTHHybridWorkoutLaunchPlan.isCandidate(workout) {
            guard ATHLTHHybridWorkoutLaunchPlan.parts(
                for: workout, allowOutdoorGPS: device == .appleWatch
            ) != nil else { return .unavailable }
            return device == .iPhone ? .phoneHybridStrength : .watchHybridStrength
        }

        let category = ATHLTHUnifiedActivityProfile.category(for: workout)
        let endurance = (workout.kind == .running &&
            ["running", "treadmill"].contains(category)) ||
            (workout.kind == .walking && category == "walking")
        let strength = workout.kind == .strength && category == "strength"
        // Explicit note steps may contain technique, effort or recovery
        // instructions. Current measured run/Watch transfers cannot
        // promise to execute them in sequence. Keep the whole recipe in
        // the existing block-based iPhone player, not a truncated export.
        let hasInstructionSteps = workout.resolvedWorkoutBlocks.contains {
            $0.kind == .note
        }

        if workout.isStructuredWorkout {
            if device == .iPhone {
                // Run-only plans keep their measured run recorder; mixed
                // plans stay intact in the original structured manual player.
                return endurance && !hasInstructionSteps
                    ? .phoneEndurance : .phoneStructuredManual
            }
            guard !hasInstructionSteps else { return .unavailable }
            if endurance { return .watchEndurance }
            if strength { return .watchStrength }
            // Watch's current prepared transfer cannot execute an arbitrary
            // run+yoga, strength+rowing or other mixed block timeline.
            return .unavailable
        }
        if endurance {
            return device == .iPhone ? .phoneEndurance : .watchEndurance
        }
        if strength {
            return device == .iPhone ? .phoneStrength : .watchStrength
        }
        if device == .iPhone {
            return ATHLTHUnifiedWorkout.timedNonCardioProjection(
                from: workout
            ) != nil ? .phoneStructuredManual : .unavailable
        }
        guard workout.routeID == nil,
              let kind = ATHLTHWorkoutCaptureAdmission.watchKind(
                for: workout
              ) else { return .unavailable }
        return .watchSport(kind)
    }
}

/// The start slot is shared across all existing authoritative recorders.
/// Checkpoint recovery and pending HealthKit/Watch preflight both occupy it.
/// The arbiter token remains mandatory for asynchronous actual starts.
@MainActor
enum ATHLTHUniversalWorkoutAdmission {
    static func isOccupied(
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        remoteWatchActive: Bool
    ) -> Bool {
        phone.active != nil || phone.activeSessionState != nil ||
        phone.hasPendingLaunch ||
        strength.activeWorkout != nil || strength.activeSessionState != nil ||
        ATHLTHManualTimedCapture.hasActiveCapture ||
        ATHLTHStructuredCaptureAdmission.hasActiveCapture ||
        ATHLTHWorkoutRecordingArbiter.hasPendingLaunch ||
        ATHLTHWorkoutRecordingArbiter.unmirroredWatchRecordingActive ||
        ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive ||
        ATHLTHWorkoutRecordingArbiter.mirror?.hasActiveMirroredWorkout == true ||
        remoteWatchActive
    }
}

enum ATHLTHWorkoutCaptureAdmission {
    /// A legacy Watch result without an explicit source workout ID may be
    /// reconciled only with one pending plan of exactly the recorded sport.
    /// Time-window + unique pending ID checks stay in AppSessionStore.
    static func matchesCompletedWatchKind(
        _ workout: PlannedSession, actual: WatchWorkoutKind
    ) -> Bool {
        watchKind(for: workout) == actual
    }

    /// Resolve the correct already-supported Watch HealthKit activity for
    /// an explicitly named simple workout. This is only a capture *choice*;
    /// it does not allocate a new workout, change the saved plan, or claim
    /// support for a mixed scripted Watch session.
    static func watchKind(for workout: PlannedSession) -> WatchWorkoutKind? {
        let category = ATHLTHUnifiedActivityProfile.category(for: workout)
        guard category != "hybrid",
              !workout.resolvedWorkoutBlocks.contains(where: {
                  $0.kind == .note
              }) else { return nil }

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


    /// Validate the entire original plan before any Quick run/walk launch
    /// can open HealthKit, relay to iPad/Watch or invite other athletes.
    /// A mixed or instruction-bearing plan needs its full structured player,
    /// not an accidental loss of steps through a run/walk transfer.
    static func requireSupportedEnduranceCapture(
        for workout: PlannedSession,
        expectedKind: WorkoutKind,
        device: WorkoutCaptureDevice
    ) throws {
        guard (expectedKind == .running || expectedKind == .walking),
              workout.kind == expectedKind else {
            throw Rejection.requiresDedicatedActivityCapture
        }
        let approved: ATHLTHPlannedWorkoutCaptureRoute =
            device == .iPhone ? .phoneEndurance : .watchEndurance
        guard ATHLTHPlannedWorkoutCaptureRoute.resolve(
            workout, device: device
        ) == approved else {
            throw Rejection.requiresDedicatedActivityCapture
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
