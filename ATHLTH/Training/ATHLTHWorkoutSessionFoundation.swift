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

    /// A phase transition is always inside the same HealthKit recording.
    static func preservesWorkoutID(_ previous: UUID, _ next: UUID) -> Bool {
        previous == next
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
