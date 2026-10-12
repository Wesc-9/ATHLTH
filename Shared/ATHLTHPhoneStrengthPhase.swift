import Foundation

/// Read-only state for iPhone strength headings. Never starts, advances,
/// completes or persists a set: StrengthWorkoutStore is authoritative.
enum ATHLTHPhoneStrengthPhase: Equatable {
    case workingSet
    case timedReady
    case timedRunning
    case timedPaused
    case timedFinished
    case resting
    case restReady
    case exerciseComplete
    case workoutComplete
}

enum ATHLTHPhoneStrengthPhaseResolver {
    static func resolve(
        workoutComplete: Bool,
        exerciseComplete: Bool,
        isResting: Bool,
        restEndsAt: Date?,
        isTimedSet: Bool,
        timerStarted: Bool,
        timerRunning: Bool,
        timerRemaining: TimeInterval?,
        now: Date = Date()
    ) -> ATHLTHPhoneStrengthPhase {
        if workoutComplete { return .workoutComplete }
        // A running rest clock is still relevant after the previous exercise.
        if isResting {
            guard let restEndsAt else { return .resting }
            return restEndsAt <= now ? .restReady : .resting
        }
        if exerciseComplete { return .exerciseComplete }
        if !isTimedSet { return .workingSet }
        if !timerStarted { return .timedReady }
        if let timerRemaining, timerRemaining <= 0 {
            return .timedFinished
        }
        return timerRunning ? .timedRunning : .timedPaused
    }
}

/// Mirrored HealthKit capture continues on Watch when the phone goes offline.
/// The phone must not pretend an old snapshot is still live.
enum ATHLTHPhoneMirroredClock {
    static func isFresh(
        snapshotAt: Date,
        now: Date = Date()
    ) -> Bool {
        ATHLTHCoachSensorFreshness.isFresh(
            sampledAt: snapshotAt,
            maximumAge: ATHLTHCoachSensorFreshness.maximumSnapshotAge,
            now: now
        )
    }

    static func elapsed(
        recorded: TimeInterval,
        capturedAt: Date,
        state: WatchWorkoutMirrorState,
        now: Date = Date()
    ) -> TimeInterval {
        let safe = recorded.isFinite ? max(recorded, 0) : 0
        guard state == .running, isFresh(snapshotAt: capturedAt, now: now)
        else { return safe }
        let age = now.timeIntervalSince(capturedAt)
        return safe + max(age, 0)
    }
}
