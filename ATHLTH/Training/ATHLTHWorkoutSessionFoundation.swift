import Foundation

/// Shared read-only interpretation of a single authoritative recorded
/// workout. A run, strength or hybrid workout never creates a second
/// recording when its current UI phase changes.
enum ATHLTHWorkoutRecordingOwner: String, Codable, Hashable {
    case iPhone
    case appleWatch
}

enum ATHLTHWorkoutSessionActivity: String, Codable, Hashable {
    case running
    case walking
    case strength
}

enum ATHLTHWorkoutSessionPhase: String, Codable, Hashable {
    case work
    case recovery
    case paused
    case completed
}

/// An immutable projection, NOT another persisted workout or progress store.
/// Existing PhoneWorkout / StrengthWorkoutLog checkpoints remain the only
/// writable source. This is intentionally safe for legacy workout decoding.
struct ATHLTHWorkoutSessionState: Equatable {
    let workoutID: UUID
    let plannedSessionID: UUID?
    let recordingOwner: ATHLTHWorkoutRecordingOwner
    let activity: ATHLTHWorkoutSessionActivity
    let phase: ATHLTHWorkoutSessionPhase
    let engine: ATHLTHLiveWorkoutEngine
    let startedAt: Date
    let activeElapsedSeconds: TimeInterval
    let stageIndex: Int?
    let stageCount: Int?

    var isFinished: Bool { phase == .completed }
}

/// Refuses a second local recording without stopping or overwriting the
/// first. In-progress checkpoints must be resumed or deliberately ended.
enum ATHLTHWorkoutSessionLaunchError: LocalizedError {
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return ATHLTHLocalization.choose(
                english: "Another workout is already active. Resume or finish it before starting a new one.",
                norwegian: "En økt pågår allerede. Fortsett eller avslutt den før du starter en ny."
            )
        }
    }
}

enum ATHLTHWorkoutSessionFoundation {
    static func requireNoActiveRecording(
        _ active: ATHLTHWorkoutSessionState?
    ) throws {
        guard active == nil else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
    }

    /// Completion must win over a stale active checkpoint after a crash.
    /// No history item or HealthKit UUID is regenerated during recovery.
    static func mayRecoverCheckpoint(
        hasEnded: Bool,
        alreadyCommitted: Bool
    ) -> Bool {
        !hasEnded && !alreadyCommitted
    }

    /// A phase transition is always inside the same HealthKit recording.
    static func preservesWorkoutID(_ previous: UUID, _ next: UUID) -> Bool {
        previous == next
    }

    /// A change of activity or live engine is not permission to transfer
    /// HealthKit ownership. Explicit owner handoff needs its own verified
    /// recording lifecycle and cannot happen as a side effect of routing.
    static func preservesRecordingOwnership(
        _ previous: ATHLTHWorkoutSessionState,
        _ next: ATHLTHWorkoutSessionState
    ) -> Bool {
        previous.workoutID == next.workoutID &&
            previous.recordingOwner == next.recordingOwner
    }

    /// Read-only arbitration across existing recording stores. Never select
    /// one arbitrarily if both stores report different active workouts:
    /// doing so could hide a second HealthKit recording after recovery.
    static func uniqueActiveSession(
        running: ATHLTHWorkoutSessionState?,
        strength: ATHLTHWorkoutSessionState?
    ) throws -> ATHLTHWorkoutSessionState? {
        switch (running, strength) {
        case (nil, nil):
            return nil
        case (let session?, nil), (nil, let session?):
            return session
        case (let first?, let second?):
            guard preservesRecordingOwnership(first, second),
                  first.plannedSessionID == second.plannedSessionID,
                  first.startedAt == second.startedAt,
                  !first.isFinished, !second.isFinished else {
                throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
            }
            // Same ID, owner, plan and start can be two projections of one hybrid session.
            // Neither projection creates a new recording or changes history.
            return first
        }
    }

    /// Resolve the actual active stores at the moment of a launch or restore.
    /// This does not mutate either store, start HealthKit or create a shadow
    /// session. A conflict must be surfaced rather than silently preferred.
    @MainActor
    static func currentSession(
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore
    ) throws -> ATHLTHWorkoutSessionState? {
        try uniqueActiveSession(
            running: phone.activeSessionState,
            strength: strength.activeSessionState
        )
    }

    /// All activity-specific launch paths can call this before allocating a
    /// recording. A recovered workout is a live workout, not a free slot.
    @MainActor
    static func requireAvailableRecordingSlot(
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore
    ) throws {
        try requireNoActiveRecording(currentSession(phone: phone, strength: strength))
    }

    /// A device message must not rewind a running session. Wall-clock
    /// timestamps can arrive out of order after an offline Watch replay;
    /// the elapsed counter is the monotonic progress authority here.
    static func acceptsProgressUpdate(
        current: ATHLTHWorkoutSessionState,
        incoming: ATHLTHWorkoutSessionState
    ) -> Bool {
        guard acceptsDeviceSnapshot(current: current, incoming: incoming) else {
            return false
        }
        return incoming.activeElapsedSeconds.isFinite &&
            incoming.activeElapsedSeconds >= 0 &&
            incoming.activeElapsedSeconds >= current.activeElapsedSeconds
    }

    /// No duplicate completion may be produced from a late Watch replay.
    /// Completion is idempotent by the stable workout ID, independent of
    /// which live engine was visible when the workout ended.
    static func shouldCommitCompletion(
        workoutID: UUID,
        committedWorkoutIDs: Set<UUID>
    ) -> Bool {
        !committedWorkoutIDs.contains(workoutID)
    }

    /// Verify a restored checkpoint before exposing it as the active session.
    /// A completed record must never be resurrected by a late Watch or iPad
    /// snapshot, even if the snapshot has a matching workout identifier.
    static func recoverableSession(
        _ session: ATHLTHWorkoutSessionState?,
        alreadyCommittedWorkoutIDs: Set<UUID>
    ) -> ATHLTHWorkoutSessionState? {
        guard let session,
              mayRecoverCheckpoint(
                  hasEnded: session.isFinished,
                  alreadyCommitted: alreadyCommittedWorkoutIDs.contains(session.workoutID)
              ) else { return nil }
        return session
    }

    /// An incoming device snapshot can update the current workout only when
    /// both immutable identity and capture ownership match. This check does
    /// not grant iPad write access or transfer a HealthKit session.
    static func acceptsDeviceSnapshot(
        current: ATHLTHWorkoutSessionState,
        incoming: ATHLTHWorkoutSessionState
    ) -> Bool {
        !current.isFinished && !incoming.isFinished &&
            preservesRecordingOwnership(current, incoming) &&
            current.plannedSessionID == incoming.plannedSessionID &&
            incoming.startedAt == current.startedAt
    }

    static func running(
        _ workout: PhoneWorkout,
        at now: Date = Date()
    ) -> ATHLTHWorkoutSessionState {
        let steps = workout.structuredRunningWorkout?.steps ?? []
        let index = workout.structuredStepIndex
        let current = index.flatMap { steps.indices.contains($0) ? steps[$0] : nil }
        let phase: ATHLTHWorkoutSessionPhase
        if workout.end != nil {
            phase = .completed
        } else if workout.resumedAt == nil {
            phase = .paused
        } else if current?.phase == "recovery" {
            phase = .recovery
        } else {
            phase = .work
        }

        return ATHLTHWorkoutSessionState(
            workoutID: workout.id,
            plannedSessionID: workout.plannedSessionID,
            recordingOwner: .iPhone,
            activity: workout.walking ? .walking : .running,
            phase: phase,
            engine: phase == .recovery ? .recovery : .endurance,
            startedAt: workout.start,
            activeElapsedSeconds: workout.elapsed(at: workout.end ?? now),
            stageIndex: current == nil ? nil : index,
            stageCount: steps.isEmpty ? nil : steps.count
        )
    }

    static func strength(
        _ workout: StrengthWorkoutLog,
        exerciseIndex: Int,
        isResting: Bool,
        at now: Date = Date()
    ) -> ATHLTHWorkoutSessionState {
        let current = workout.exercises.indices.contains(exerciseIndex)
            ? workout.exercises[exerciseIndex] : nil
        let phase: ATHLTHWorkoutSessionPhase
        if workout.endedAt != nil {
            phase = .completed
        } else if isResting {
            phase = .recovery
        } else {
            phase = .work
        }
        let engine: ATHLTHLiveWorkoutEngine
        if phase == .recovery {
            engine = .recovery
        } else if current?.isEmbeddedRunningInterval == true {
            engine = .endurance
        } else {
            engine = .strength
        }
        return ATHLTHWorkoutSessionState(
            workoutID: workout.id,
            plannedSessionID: workout.plannedSessionID,
            recordingOwner: workout.captureDevice == .appleWatch
                ? .appleWatch : .iPhone,
            activity: .strength,
            phase: phase,
            engine: engine,
            startedAt: workout.startedAt,
            // Whole-session duration includes rest. Set effort is measured
            // separately and never adds a second HealthKit workout.
            activeElapsedSeconds: max(
                (workout.endedAt ?? now).timeIntervalSince(workout.startedAt), 0
            ),
            stageIndex: current == nil ? nil : exerciseIndex,
            stageCount: workout.exercises.isEmpty ? nil : workout.exercises.count
        )
    }
}
