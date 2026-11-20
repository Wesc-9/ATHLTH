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

/// Weak links to the two existing authoritative stores. This is a launch
/// arbiter only: it does not persist workouts, own HealthKit or retain stores.
@MainActor
enum ATHLTHWorkoutRecordingArbiter {
    static weak var phone: IPhoneWorkoutStore?
    static weak var strength: StrengthWorkoutStore?
    static weak var mirror: WorkoutMirroringStore?

    private static var mirroredRecordingActive: Bool {
        ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive ||
            mirror?.hasActiveMirroredWorkout == true
    }

    /// One launch reservation spans every asynchronous preflight (social,
    /// HealthKit Watch launch and device relay). Without it, two independent
    /// start tasks can both observe an empty checkpoint before either writes.
    /// This token is deliberately transient: it owns no workout or HealthKit
    /// session and cannot be restored as a recorded activity.
    private static var pendingLaunchID: UUID?

    static func reserveLaunch() throws -> UUID {
        guard pendingLaunchID == nil,
              !ATHLTHManualTimedCapture.hasActiveCapture,
              !ATHLTHStructuredCaptureAdmission.hasActiveCapture,
              ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
                  running: phone?.activeSessionState,
                  runningAuthorizationPending: phone?.hasPendingLaunch == true,
                  strength: strength?.activeSessionState,
                  mirroredWatchRecordingActive: mirroredRecordingActive
              ) else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        let id = UUID()
        pendingLaunchID = id
        return id
    }

    /// A stale completion must not release the newer launch's reservation.
    static func releaseLaunch(_ id: UUID) {
        guard pendingLaunchID == id else { return }
        pendingLaunchID = nil
    }

    static func mayStartRunning() -> Bool {
        !ATHLTHManualTimedCapture.hasActiveCapture &&
            !ATHLTHStructuredCaptureAdmission.hasActiveCapture &&
            strength?.activeSessionState == nil &&
            (!mirroredRecordingActive || pendingLaunchID != nil)
    }

    static func mayStartStrength() -> Bool {
        !ATHLTHManualTimedCapture.hasActiveCapture &&
            !ATHLTHStructuredCaptureAdmission.hasActiveCapture &&
            phone?.activeSessionState == nil &&
            phone?.hasPendingLaunch != true &&
            (!mirroredRecordingActive || pendingLaunchID != nil)
    }

    /// A Watch-started workout may be mirrored before its original
    /// strength log is restored to iPhone. Only that same recording
    /// is allowed to claim the local ATHLTH checkpoint.
    static func mayBootstrapWatchStrength(
        snapshot: WatchStrengthSessionSnapshot? = nil
    ) -> Bool {
        pendingLaunchID == nil &&
            !ATHLTHManualTimedCapture.hasActiveCapture &&
            !ATHLTHStructuredCaptureAdmission.hasActiveCapture &&
            ATHLTHWorkoutSessionFoundation.isRecordingSlotAvailable(
                running: phone?.activeSessionState,
                runningAuthorizationPending: phone?.hasPendingLaunch == true,
                strength: strength?.activeSessionState
            ) &&
            ATHLTHWorkoutSessionFoundation.canBootstrapWatchStrength(
                mirror: mirror?.snapshot,
                mirrorActive: mirroredRecordingActive,
                bootstrap: snapshot
            )
    }
}

enum ATHLTHWorkoutSessionFoundation {
    /// Waiting for outdoor location permission still occupies the one
    /// universal recording slot, even before PhoneWorkout is allocated.
    static func isRecordingSlotAvailable(
        running: ATHLTHWorkoutSessionState?,
        runningAuthorizationPending: Bool,
        strength: ATHLTHWorkoutSessionState?,
        mirroredWatchRecordingActive: Bool = false
    ) -> Bool {
        running == nil && !runningAuthorizationPending &&
            strength == nil && !mirroredWatchRecordingActive
    }

    /// Never reinterpret a mirrored run or another strength workout
    /// as the Watch session requesting offline bootstrap.
    static func canBootstrapWatchStrength(
        mirror: WatchWorkoutLiveSnapshot?,
        mirrorActive: Bool,
        bootstrap: WatchStrengthSessionSnapshot?
    ) -> Bool {
        guard mirrorActive else { return true }
        guard let mirror, let bootstrap,
              mirror.kind == .strength,
              mirror.state == .running ||
                mirror.state == .paused ||
                mirror.state == .preparing ||
                mirror.state == .ending ||
                mirror.state == .completed,
              let mirrorStart = mirror.startedAt,
              let bootstrapStart = bootstrap.startedAt,
              abs(mirrorStart.timeIntervalSince(bootstrapStart)) <= 5
        else { return false }
        if let mirrorID = mirror.strengthWorkoutID {
            return mirrorID == bootstrap.workoutID
        }
        return true
    }

    static func requireNoActiveRecording(
        _ active: ATHLTHWorkoutSessionState?
    ) throws {
        guard active == nil else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
    }

    /// A recovered checkpoint records *when it was saved*, not when the
    /// athlete tapped Finish. Never use that old timestamp as endedAt.
    static func completionTimestamp(
        startedAt: Date,
        finishedAt: Date
    ) -> Date {
        max(startedAt, finishedAt)
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
        // A manual timer is not a running or strength recording projection.
        // Never misreport an available HealthKit slot while one is active.
        guard !ATHLTHManualTimedCapture.hasActiveCapture,
              !ATHLTHStructuredCaptureAdmission.hasActiveCapture else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        return try uniqueActiveSession(
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
        guard !phone.hasPendingLaunch,
              !ATHLTHManualTimedCapture.hasActiveCapture,
              !ATHLTHStructuredCaptureAdmission.hasActiveCapture,
              !ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive
        else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
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
        suspendedAt: Date? = nil,
        at now: Date = Date()
    ) -> ATHLTHWorkoutSessionState {
        let current = workout.exercises.indices.contains(exerciseIndex)
            ? workout.exercises[exerciseIndex] : nil
        let phase: ATHLTHWorkoutSessionPhase
        if workout.endedAt != nil {
            phase = .completed
        } else if suspendedAt != nil && workout.captureDevice == .iPhone {
            phase = .paused
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
            // Whole-session duration includes genuine rest, but excludes
            // explicitly measured offline downtime after phone recovery.
            // Set effort remains separately recorded in the same workout.
            activeElapsedSeconds: workout.elapsedSessionSeconds(
                at: now, suspendedAt: suspendedAt
            ),
            stageIndex: current == nil ? nil : exerciseIndex,
            stageCount: workout.exercises.isEmpty ? nil : workout.exercises.count
        )
    }
}

 
/// A Watch result has its own delivery/result UUID, unrelated to the
/// authoritative strength session UUID. Only the latter may finish a log or
/// attach HealthKit metrics. Older Watch builds without a strength snapshot
/// are accepted only for a phone-initiated Watch session with a very close
/// HealthKit start time. Never match by workout kind or finish time alone.
enum ATHLTHWatchStrengthResultIdentityPolicy {
    /// A completed Watch strength result with the authoritative session
    /// snapshot is NOT a generic workout. When its matching strength log
    /// cannot be restored yet, leave the result in the durable queue
    /// instead of publishing a duplicate generic completion.
    static func canReconcile(
        result: WatchWorkoutResult,
        activeStrength: StrengthWorkoutLog?,
        savedStrength: [StrengthWorkoutLog],
        strengthAccountReady: Bool,
        recordingSlotAvailable: Bool
    ) -> Bool {
        guard result.kind == .strength,
              result.strengthSnapshot != nil else {
            // Legacy results without an ATHLTH strength identity still
            // use the existing Watch completion import path.
            return true
        }
        guard strengthAccountReady else { return false }
        if let activeStrength,
           matches(result: result, workout: activeStrength) {
            return true
        }
        if savedStrength.contains(where: {
            $0.endedAt != nil && matches(result: result, workout: $0)
        }) {
            return true
        }
        // Bootstrap is safe only when neither the iPhone nor Watch already
        // has another workout/launch occupying the universal session slot.
        return activeStrength == nil && recordingSlotAvailable
    }

    static func matches(
        result: WatchWorkoutResult,
        workout: StrengthWorkoutLog
    ) -> Bool {
        guard result.kind == .strength,
              workout.captureDevice == .appleWatch,
              result.startedAt.timeIntervalSince1970.isFinite,
              result.endedAt.timeIntervalSince1970.isFinite,
              result.endedAt >= result.startedAt
        else { return false }

        if let linked = workout.healthMetrics.healthKitWorkoutUUID,
           let fromWatch = result.healthKitWorkoutUUID,
           linked != fromWatch {
            return false
        }

        if let snapshot = result.strengthSnapshot {
            return snapshot.workoutID == workout.id
        }

        // Compatibility-only: Watch-only offline workouts without a stable
        // strengthSnapshot must not be assigned to an unrelated active log.
        guard workout.watchSessionID != nil else { return false }
        return abs(workout.startedAt.timeIntervalSince(result.startedAt)) <= 10
    }
}
