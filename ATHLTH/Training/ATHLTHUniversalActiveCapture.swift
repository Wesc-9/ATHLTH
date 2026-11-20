import Foundation

/// One read-only live state across the existing workout engines.
/// This does not open another HealthKit session, persist a shadow workout,
/// or turn manual time/distance into verified sensor measurements.
enum ATHLTHUniversalCaptureSource: String, Codable, Hashable {
    case phoneRunWalk
    case strength
    case manualTimer
    case structuredTimer

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
        let result = try unique(
            running: running, strength: strength,
            manual: manual, structured: structured, at: now
        )
        // A Watch mirror may still own the real session before its phone
        // checkpoint is available. Never report that state as an empty slot.
        if result == nil && (
            ATHLTHWorkoutRecordingArbiter.hasPendingLaunch ||
            ATHLTHWorkoutRecordingArbiter.phone?.hasPendingLaunch == true ||
            ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive ||
            ATHLTHWorkoutRecordingArbiter.mirror?.hasActiveMirroredWorkout == true
        ) {
            throw ATHLTHWorkoutSessionLaunchError.alreadyRecording
        }
        return result
    }
}
