import Foundation

/// One read-only live state across the existing workout engines.
/// This does not open another HealthKit session, persist a shadow workout,
/// or turn manual time/distance into verified sensor measurements.
enum ATHLTHUniversalCaptureSource: String, Codable, Hashable {
    case phoneRunWalk
    case strength
    case manualTimer
    case structuredTimer
    /// Read-only projection of the original, identity-proven Watch session.
    /// HealthKit ownership remains exclusively on the Watch.
    case watchMirror

    var isManualTiming: Bool {
        self == .manualTimer || self == .structuredTimer
    }
}

struct ATHLTHUniversalActiveCaptureState: Equatable {
    let workoutID: UUID
    let plannedSessionID: UUID?
    let recordingOwner: ATHLTHWorkoutRecordingOwner
    let source: ATHLTHUniversalCaptureSource
    let activityCategory: String
    let engine: ATHLTHLiveWorkoutEngine
    let phase: ATHLTHWorkoutSessionPhase
    let startedAt: Date
    let elapsedSeconds: TimeInterval
    let stageIndex: Int?
    let stageCount: Int?
}

/// One set of lifecycle commands across the existing workout recorders.
/// A command authorizes a change to an ORIGINAL owner-owned workout; this
/// reducer never starts HealthKit, creates a new ID, or saves a second journal.
// Keep call-site compatibility while both applications use one command type.
typealias ATHLTHUniversalWorkoutCommand = ATHLTHWorkoutLifecycleCommand

enum ATHLTHUniversalWorkoutLifecycle {
    /// Translate the original iPhone capture projection into the one policy
    /// that is also compiled into WatchWorkoutManager.
    static func nextPhase(
        for command: ATHLTHUniversalWorkoutCommand,
        workoutID: UUID,
        expectedWorkoutID: UUID,
        source: ATHLTHUniversalCaptureSource,
        recordingOwner: ATHLTHWorkoutRecordingOwner,
        phase: ATHLTHWorkoutSessionPhase,
        requestingOwner: ATHLTHWorkoutRecordingOwner = .iPhone,
        stageIndex: Int? = nil,
        stageCount: Int? = nil
    ) -> ATHLTHWorkoutSessionPhase? {
        guard let sharedSource = ATHLTHWorkoutLifecycleSource(
                  rawValue: source.rawValue
              ),
              let sharedOwner = ATHLTHWorkoutLifecycleOwner(
                  rawValue: recordingOwner.rawValue
              ),
              let caller = ATHLTHWorkoutLifecycleOwner(
                  rawValue: requestingOwner.rawValue
              ),
              let sharedPhase = ATHLTHWorkoutLifecyclePhase(
                  rawValue: phase.rawValue
              ) else { return nil }

        return ATHLTHWorkoutLifecyclePolicy.nextPhase(
            for: command,
            workoutID: workoutID,
            expectedWorkoutID: expectedWorkoutID,
            source: sharedSource,
            recordingOwner: sharedOwner,
            phase: sharedPhase,
            requestingOwner: caller,
            stageIndex: stageIndex,
            stageCount: stageCount
        ).flatMap { ATHLTHWorkoutSessionPhase(rawValue: $0.rawValue) }
    }

    static func permits(
        _ command: ATHLTHUniversalWorkoutCommand,
        state: ATHLTHUniversalActiveCaptureState,
        expectedWorkoutID: UUID,
        requestingOwner: ATHLTHWorkoutRecordingOwner = .iPhone
    ) -> Bool {
        nextPhase(
            for: command,
            workoutID: state.workoutID,
            expectedWorkoutID: expectedWorkoutID,
            source: state.source,
            recordingOwner: state.recordingOwner,
            phase: state.phase,
            requestingOwner: requestingOwner,
            stageIndex: state.stageIndex,
            stageCount: state.stageCount
        ) != nil
    }
}

/// An active Watch HealthKit session may exist before the first iPhone
/// mirror packet. Its recording slot is occupied even without a renderable
/// live projection. Only an already-owned original Watch strength journal
/// may coexist with that pre-mirror activity; it is not a second recording.
enum ATHLTHPreMirrorWatchCapturePolicy {
    static func permitsExisting(
        _ state: ATHLTHUniversalActiveCaptureState?,
        watchActive: Bool
    ) -> Bool {
        guard watchActive else { return true }
        guard let state else { return false }
        return state.recordingOwner == .appleWatch &&
            state.source == .strength
    }
}

enum ATHLTHUniversalActiveCapture {
    /// Fail closed when two different original recordings are simultaneously
    /// visible after reconnect. An iPhone/Watch hybrid projection may overlap
    /// only when the existing stores prove the SAME recorded workout.
    static func sourcesConsistent(
        running: ATHLTHWorkoutSessionState?,
        strength: ATHLTHWorkoutSessionState?,
        manualActive: Bool,
        structuredActive: Bool,
        watchMirrorActive: Bool,
        mirrorStrengthWorkoutID: UUID?,
        mirrorStartedAt: Date?
    ) -> Bool {
        if running != nil && strength != nil {
            guard (try? ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
                running: running, strength: strength
            )) != nil else { return false }
        }

        let timedCount = (manualActive ? 1 : 0) +
            (structuredActive ? 1 : 0)
        guard timedCount <= 1 else { return false }
        if timedCount > 0 {
            guard running == nil, strength == nil,
                  !watchMirrorActive else { return false }
        }
        if watchMirrorActive {
            // A mirrored Watch recording cannot share the slot with an
            // unrelated iPhone recording. Watch-run has no durable local ID,
            // so never guess that a running phone checkpoint is the mirror.
            guard running == nil else { return false }
            if let strength {
                guard strength.recordingOwner == .appleWatch,
                      mirrorStrengthWorkoutID == strength.workoutID,
                      let mirrorStartedAt,
                      abs(strength.startedAt.timeIntervalSince(
                          mirrorStartedAt
                      )) <= 5 else { return false }
            }
        }
        return true
    }

    /// One canonical ACTIVE sport for the old run/strength recording states.
    /// A strength-owned hybrid keeps its original strength HealthKit session,
    /// while an embedded run interval uses the endurance live presentation.
    /// Pausing freezes the current sport; recovery is its own active phase.
    /// This is a read-only projection and never changes activity in HealthKit.
    static func activeRecordedSport(
        _ state: ATHLTHWorkoutSessionState
    ) -> ATHLTHWorkoutSportMode {
        if state.phase == .recovery || state.engine == .recovery {
            return .recovery
        }
        switch state.activity {
        case .running: return .running
        case .walking: return .walking
        case .strength:
            return state.engine == .endurance ? .running : .strength
        }
    }

    /// Running and strength continue to own their historical checkpoints,
    /// HealthKit writer, and final results. No extra mutable store is created.
    static func recorded(
        _ state: ATHLTHWorkoutSessionState,
        source: ATHLTHUniversalCaptureSource
    ) -> ATHLTHUniversalActiveCaptureState {
        ATHLTHUniversalActiveCaptureState(
            workoutID: state.workoutID,
            plannedSessionID: state.plannedSessionID,
            recordingOwner: state.recordingOwner,
            source: source,
            activityCategory: activeRecordedSport(state).category,
            engine: state.engine,
            phase: state.phase,
            startedAt: state.startedAt,
            elapsedSeconds: state.activeElapsedSeconds,
            stageIndex: state.stageIndex,
            stageCount: state.stageCount
        )
    }

    /// An iPhone timer is a genuine timer, NOT a sensor/HealthKit recording.
    /// Interval positions are derived from the original saved configuration.
    static func manual(
        _ checkpoint: ATHLTHManualTimedCheckpoint,
        at now: Date = Date()
    ) -> ATHLTHUniversalActiveCaptureState? {
        guard checkpoint.isValid, now.timeIntervalSince1970.isFinite else {
            return nil
        }
        let category = checkpoint.activity.rawValue
        let activityEngine = ATHLTHWorkoutSportMode(category: category).engine

        let elapsed = checkpoint.elapsed(at: now)
        guard let timeline = ATHLTHCustomWorkoutTimeline.state(
            method: checkpoint.method,
            durationMinutes: checkpoint.durationMinutes,
            workSeconds: checkpoint.workSeconds,
            restSeconds: checkpoint.restSeconds,
            rounds: checkpoint.rounds,
            elapsedSeconds: elapsed,
            isPaused: checkpoint.resumedAt == nil
        ) else { return nil }
        return ATHLTHUniversalActiveCaptureState(
            workoutID: checkpoint.id,
            plannedSessionID: nil,
            recordingOwner: .iPhone,
            source: .manualTimer,
            activityCategory: category,
            engine: timeline.phase == .recovery ? .recovery : activityEngine,
            phase: timeline.phase,
            startedAt: checkpoint.startedAt,
            elapsedSeconds: elapsed,
            stageIndex: timeline.stageIndex,
            stageCount: timeline.stageCount
        )
    }

    /// The original structured checkpoint is the only active cursor.
    /// There is no trustworthy source-plan ID in this legacy checkpoint,
    /// so the live projection deliberately leaves that field empty.
    static func structured(
        _ checkpoint: ATHLTHStructuredWorkoutCheckpoint,
        at now: Date = Date()
    ) -> ATHLTHUniversalActiveCaptureState? {
        guard checkpoint.executionBlocks.indices.contains(checkpoint.currentIndex),
              checkpoint.startedAt.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite else {
            return nil
        }
        let current = checkpoint.executionBlocks[checkpoint.currentIndex]
        // The original workout can be mixed; its ACTIVE stage cannot.
        // Do not advertise a cycling segment as a "hybrid" sport or
        // incorrectly inherit the previous running interval's metrics.
        let activeSport = ATHLTHWorkoutSportMode.forBlock(current)
        let inRest = current.kind == .rest || current.isActiveRecovery
        let category = inRest ? ATHLTHWorkoutSportMode.recovery.category :
            activeSport.category
        guard let activeSeconds = ATHLTHStructuredWorkoutClock.elapsed(
            start: checkpoint.startedAt, now: now,
            pause: checkpoint.pausedAt,
            pausedSeconds: checkpoint.completedPauseSeconds ?? 0
        ) else { return nil }
        return ATHLTHUniversalActiveCaptureState(
            workoutID: checkpoint.workoutID,
            // A linked structured workout's ID is its planned session ID.
            // The plan UUID itself remains on the original checkpoint.
            plannedSessionID: checkpoint.sourcePlanID == nil
                ? nil : checkpoint.workoutID,
            recordingOwner: .iPhone,
            source: .structuredTimer,
            activityCategory: category,
            engine: inRest ? .recovery : activeSport.engine,
            phase: checkpoint.pausedAt != nil ? .paused : (inRest ? .recovery : .work),
            startedAt: checkpoint.startedAt,
            elapsedSeconds: activeSeconds,
            stageIndex: checkpoint.currentIndex,
            stageCount: checkpoint.executionBlocks.count
        )
    }

    /// All native Watch sports share one original HealthKit session and
    /// its confirmed active time. iPhone makes NO new ID or HK recording.
    static func mirroredWatch(
        _ snapshot: WatchWorkoutLiveSnapshot,
        at now: Date = Date()
    ) -> ATHLTHUniversalActiveCaptureState? {
        guard snapshot.state == .running || snapshot.state == .paused,
              let start = snapshot.startedAt,
              start.timeIntervalSince1970.isFinite,
              snapshot.capturedAt.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite,
              start <= snapshot.capturedAt,
              snapshot.elapsedTime.isFinite,
              snapshot.elapsedTime >= 0,
              snapshot.elapsedTime <= snapshot.capturedAt.timeIntervalSince(start) + 10,
              now.timeIntervalSince(snapshot.capturedAt) >= -10,
              now.timeIntervalSince(snapshot.capturedAt) <= 35
        else { return nil }
        let id: UUID
        if snapshot.kind == .strength {
            guard let original = snapshot.strengthWorkoutID,
                  snapshot.universalWorkoutID == nil ||
                      snapshot.universalWorkoutID == original else { return nil }
            id = original
        } else {
            guard let original = snapshot.universalWorkoutID else { return nil }
            id = original
        }
        // Use the original Watch's actual active hybrid segment. The
        // source HKWorkoutSession and universal workout ID stay unchanged.
        let category = ATHLTHWatchLiveSportPolicy.activityCategory(snapshot)
        let engine = ATHLTHWorkoutSportMode(category: category).engine
        // Universal stages are the original EXERCISES, not strength sets.
        // The original Watch exercise cursor is zero-based just like
        // the iPhone strength journal. One-based set labels stay separate
        // on the original strength UI and do not imply extra workout stages.
        let index: Int?
        let count: Int?
        if snapshot.kind == .strength {
            index = snapshot.strengthExerciseIndex
            count = snapshot.strengthExerciseCount
        } else if snapshot.kind == .running || snapshot.kind == .walking {
            index = snapshot.runningStepIndex
            count = snapshot.runningStepCount
        } else {
            index = nil
            count = nil
        }
        let verified: Int?
        if let index, let count, count > 0, index >= 0, index < count {
            verified = index
        } else {
            verified = nil
        }
        return ATHLTHUniversalActiveCaptureState(
            workoutID: id,
            plannedSessionID: snapshot.plannedCalendarSessionID,
            recordingOwner: .appleWatch, source: .watchMirror,
            activityCategory: category, engine: engine,
            phase: snapshot.state == .paused ? .paused :
                (category == "recovery" ? .recovery : .work),
            startedAt: start, elapsedSeconds: snapshot.elapsedTime,
            stageIndex: verified, stageCount: verified == nil ? nil : count
        )
    }

    /// The universal current-account projection additionally requires
    /// proof of the exact original Watch owner. A signed-out or re-paired
    /// Watch may still hold a real HealthKit session, but cannot expose its
    /// metrics as the new account's workout.
    static func mirroredWatch(
        _ snapshot: WatchWorkoutLiveSnapshot,
        for ownerID: UUID,
        at now: Date = Date()
    ) -> ATHLTHUniversalActiveCaptureState? {
        guard snapshot.accountOwnerID == ownerID else { return nil }
        return mirroredWatch(snapshot, at: now)
    }

    static func mirroredStrength(
        _ snapshot: WatchWorkoutLiveSnapshot,
        at now: Date = Date()
    ) -> ATHLTHUniversalActiveCaptureState? {
        guard snapshot.kind == .strength else { return nil }
        return mirroredWatch(snapshot, at: now)
    }

    /// A hybrid run+strength may have TWO projections of the SAME recorded
    /// workout. Every other overlap is unsafe and must fail closed.
    static func unique(
        running: ATHLTHWorkoutSessionState?,
        strength: ATHLTHWorkoutSessionState?,
        manual: ATHLTHManualTimedCheckpoint?,
        structured: ATHLTHStructuredWorkoutCheckpoint?,
        at now: Date = Date()
    ) throws -> ATHLTHUniversalActiveCaptureState? {
        let recordedState = try ATHLTHWorkoutSessionFoundation.uniqueActiveSession(
            running: running, strength: strength
        )
        let timedState = manual.flatMap { self.manual($0, at: now) }
        let structuredState = structured.flatMap {
            self.structured($0, at: now)
        }
        guard (manual == nil || timedState != nil),
              (structured == nil || structuredState != nil) else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        let occupied = [recordedState != nil, timedState != nil,
                        structuredState != nil].filter { $0 }.count
        guard occupied <= 1 else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        if let recordedState {
            // The same hybrid may be projected by both original stores.
            // After identity validation, prefer the strength stage cursor
            // rather than displaying the run projection as a strength phase.
            return recorded(
                strength ?? recordedState,
                source: strength == nil ? .phoneRunWalk : .strength
            )
        }
        return timedState ?? structuredState
    }

    /// Existing stores and checkpoints are read only for the current account.
    /// Unknown or unreadable checkpoints are protected, never silently
    /// treated as an empty recording slot.
    @MainActor
    static func current(
        for userID: UUID,
        at now: Date = Date(),
        defaults: UserDefaults = .standard
    ) throws -> ATHLTHUniversalActiveCaptureState? {
        let manual = ATHLTHManualTimedCapture.current(for: userID)
        let structured = ATHLTHStructuredCaptureAdmission.activeCheckpoint(
            for: userID, defaults: defaults
        )
        guard !ATHLTHManualTimedCapture.hasActiveCapture || manual != nil,
              !ATHLTHStructuredCaptureAdmission.hasActiveCapture ||
                structured != nil else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        let running = ATHLTHWorkoutRecordingArbiter.phone?.activeSessionState
        let strength = ATHLTHWorkoutRecordingArbiter.strength?.activeSessionState
        let mirror = ATHLTHWorkoutRecordingArbiter.mirror
        let mirrorActive = ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive ||
            mirror?.hasActiveMirroredWorkout == true
        guard sourcesConsistent(
            running: running, strength: strength,
            manualActive: ATHLTHManualTimedCapture.hasActiveCapture,
            structuredActive: ATHLTHStructuredCaptureAdmission.hasActiveCapture,
            watchMirrorActive: mirrorActive,
            mirrorStrengthWorkoutID: mirror?.snapshot?.strengthWorkoutID,
            mirrorStartedAt: mirror?.snapshot?.startedAt
        ) else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        // Validate the ORIGINAL Watch account even when a matching
        // Watch-owned strength journal is already available on iPhone.
        // An old or cross-account mirror cannot authorize live telemetry.
        if mirrorActive {
            // Check immutable account ownership for every mirror. A
            // disconnected Watch may leave its last sample stale while the
            // original, account-scoped strength checkpoint is still valid.
            // Freshness is required below ONLY to project mirror telemetry.
            guard mirror?.snapshot?.accountOwnerID == userID else {
                throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
            }
        }
        let result = try unique(
            running: running, strength: strength,
            manual: manual, structured: structured, at: now
        )
        // Pending starts cannot be mistaken for an existing confirmed
        // Watch or phone workout. Recover only a fresh, identity-proven
        // Watch strength mirror; otherwise protect its occupied slot.
        guard !ATHLTHWorkoutRecordingArbiter.hasPendingLaunch,
              ATHLTHWorkoutRecordingArbiter.phone?.hasPendingLaunch != true
        else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        if result == nil && mirrorActive {
            guard let snapshot = mirror?.snapshot,
                  let confirmed = mirroredWatch(
                      snapshot, for: userID, at: now
                  ) else {
                throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
            }
            return confirmed
        }
        // A genuine Watch launch/pre-mirror HKWorkoutSession is still using
        // the one recording slot. Never present an empty idle state or
        // prefer a simultaneous unrelated phone workout after reconnect.
        guard ATHLTHPreMirrorWatchCapturePolicy.permitsExisting(
            result,
            watchActive:
                ATHLTHWorkoutRecordingArbiter.unmirroredWatchRecordingActive
        ) else {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        return result
    }
}
