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
            activityCategory: state.activity.rawValue,
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
        let activityEngine: ATHLTHLiveWorkoutEngine
        switch checkpoint.activity {
        case .cycling: activityEngine = .cycling
        case .rowing, .stairClimber: activityEngine = .endurance
        case .mobility, .yoga: activityEngine = .mobility
        case .hiit, .circuit, .functional, .sports, .other:
            activityEngine = .instructions
        }

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
        let category = ATHLTHUnifiedActivityProfile(
            blocks: checkpoint.executionBlocks
        ).category
        let inRest = current.kind == .rest || current.isActiveRecovery
        guard let activeSeconds = ATHLTHStructuredWorkoutClock.elapsed(
            start: checkpoint.startedAt, now: now,
            pause: checkpoint.pausedAt,
            pausedSeconds: checkpoint.completedPauseSeconds ?? 0
        ) else { return nil }
        return ATHLTHUniversalActiveCaptureState(
            workoutID: checkpoint.workoutID,
            plannedSessionID: nil,
            recordingOwner: .iPhone,
            source: .structuredTimer,
            activityCategory: category,
            engine: inRest ? .recovery :
                ATHLTHLiveWorkoutEngineRouter.engine(for: current),
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
        let category: String
        let engine: ATHLTHLiveWorkoutEngine
        switch snapshot.kind {
        case .running: category = "running"; engine = .endurance
        case .walking: category = "walking"; engine = .endurance
        case .strength: category = "strength"; engine = .strength
        case .cycling: category = "cycling"; engine = .cycling
        case .rowing: category = "rowing"; engine = .endurance
        case .stairClimbing: category = "stairclimber"; engine = .endurance
        case .hiit: category = "hiit"; engine = .instructions
        case .functional: category = "functional"; engine = .instructions
        case .yoga: category = "yoga"; engine = .mobility
        case .other: category = "other"; engine = .instructions
        }
        let endurance = snapshot.kind == .running || snapshot.kind == .walking
        let index = endurance ? snapshot.runningStepIndex : nil
        let count = endurance ? snapshot.runningStepCount : nil
        let verified: Int?
        if let index, let count, count > 0, index >= 0, index < count {
            verified = index
        } else {
            verified = nil
        }
        return ATHLTHUniversalActiveCaptureState(
            workoutID: id, plannedSessionID: nil,
            recordingOwner: .appleWatch, source: .watchMirror,
            activityCategory: category, engine: engine,
            phase: snapshot.state == .paused ? .paused : .work,
            startedAt: start, elapsedSeconds: snapshot.elapsedTime,
            stageIndex: verified, stageCount: verified == nil ? nil : count
        )
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
                  let confirmed = mirroredWatch(snapshot, at: now) else {
                throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
            }
            return confirmed
        }
        return result
    }
}
