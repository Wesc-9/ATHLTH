import Foundation

/// Common transition contract compiled into both the iPhone/iPad app and
/// Apple Watch. A lifecycle decision never owns, creates or saves an actual
/// HealthKit workout, session identifier, timer, or exercise journal.
enum ATHLTHWorkoutLifecycleCommand: String, Codable, Hashable {
    case pause
    case resume
    case finish
    case advance
}

enum ATHLTHWorkoutLifecyclePhase: String, Codable, Hashable {
    case work
    case recovery
    case paused
    case completed
}

enum ATHLTHWorkoutLifecycleOwner: String, Codable, Hashable {
    case iPhone
    case appleWatch
}

enum ATHLTHWorkoutLifecycleSource: String, Codable, Hashable {
    case phoneRunWalk
    case strength
    case manualTimer
    case structuredTimer
    case watchRecorder
    /// Mirrored telemetry is not an independent recording or command owner.
    case watchMirror
}

/// Pure, deterministic transition rules shared across the actual recorders.
/// Adapters remain responsible for persisting the ORIGINAL checkpoint and
/// for deciding how to resume a paused interval (work or recovery).
enum ATHLTHWorkoutLifecyclePolicy {
    static func nextPhase(
        for command: ATHLTHWorkoutLifecycleCommand,
        workoutID: UUID,
        expectedWorkoutID: UUID,
        source: ATHLTHWorkoutLifecycleSource,
        recordingOwner: ATHLTHWorkoutLifecycleOwner,
        phase: ATHLTHWorkoutLifecyclePhase,
        requestingOwner: ATHLTHWorkoutLifecycleOwner = .iPhone,
        stageIndex: Int? = nil,
        stageCount: Int? = nil
    ) -> ATHLTHWorkoutLifecyclePhase? {
        guard workoutID == expectedWorkoutID,
              source != .watchMirror,
              recordingOwner == requestingOwner,
              phase != .completed else { return nil }

        switch command {
        case .pause:
            guard phase == .work || phase == .recovery else { return nil }
            return .paused
        case .resume:
            guard phase == .paused else { return nil }
            // The original recorder restores the exact work/rest stage.
            // Here, .work represents an eligible active transition only.
            return .work
        case .finish:
            return .completed
        case .advance:
            guard phase == .work || phase == .recovery,
                  let stageIndex, let stageCount,
                  stageCount > 0, stageIndex >= 0,
                  stageIndex + 1 < stageCount else { return nil }
            return phase
        }
    }
}

/// Pure stage boundary shared by iPhone, iPad presentation and Apple Watch.
/// Completing the last prescribed stage does NOT finish the HealthKit workout:
/// the athlete can continue easy training until an explicit Finish action.
/// Invalid or stale cursors are rejected before any metrics or plan are changed.
enum ATHLTHWorkoutStageDecision: Equatable {
    case advance(nextIndex: Int)
    case prescriptionComplete
}

enum ATHLTHWorkoutStagePolicy {
    static func afterStage(
        at index: Int,
        totalStages: Int
    ) -> ATHLTHWorkoutStageDecision? {
        guard totalStages > 0, index >= 0, index < totalStages else {
            return nil
        }
        if index == totalStages - 1 {
            return .prescriptionComplete
        }
        return .advance(nextIndex: index + 1)
    }
}
