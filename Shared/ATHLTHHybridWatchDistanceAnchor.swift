import Foundation

/// Last verified distance baseline of one Watch-owned outdoor running set.
/// Stored with the existing Watch recovery checkpoint; never creates a
/// workout, a HealthKit sample or a synthetic GPS measurement.
struct ATHLTHHybridWatchDistanceAnchor: Codable, Hashable {
    let workoutID: UUID
    let exerciseIndex: Int
    let setIndex: Int
    let baselineMeters: Double
    let activeElapsedAtStartSeconds: TimeInterval
    let targetMeters: Double

    static func make(
        snapshot: WatchStrengthSessionSnapshot,
        measuredTotalMeters: Double,
        activeElapsedSeconds: TimeInterval
    ) -> Self? {
        guard snapshot.isEmbeddedRunningInterval == true,
              let target = snapshot.embeddedRunningTargetDistanceMeters,
              target.isFinite, (100...50_000).contains(target),
              measuredTotalMeters.isFinite, measuredTotalMeters >= 0,
              activeElapsedSeconds.isFinite, activeElapsedSeconds >= 0,
              snapshot.setIndex >= 0, snapshot.exerciseIndex >= 0,
              snapshot.setCount > 0, snapshot.exerciseCount > 0,
              snapshot.setIndex < snapshot.setCount,
              snapshot.exerciseIndex < snapshot.exerciseCount,
              !snapshot.isResting, !snapshot.currentExerciseComplete
        else { return nil }
        return Self(
            workoutID: snapshot.workoutID,
            exerciseIndex: snapshot.exerciseIndex,
            setIndex: snapshot.setIndex,
            baselineMeters: measuredTotalMeters,
            activeElapsedAtStartSeconds: activeElapsedSeconds,
            targetMeters: target
        )
    }

    /// Check recovered, potentially stale/corrupt checkpoints before using
    /// their values for GPS progress, automatic completion or duration.
    private var isValidCheckpoint: Bool {
        exerciseIndex >= 0 && setIndex >= 0 &&
            baselineMeters.isFinite && baselineMeters >= 0 &&
            activeElapsedAtStartSeconds.isFinite &&
            activeElapsedAtStartSeconds >= 0 &&
            targetMeters.isFinite && (100...50_000).contains(targetMeters)
    }

    func matches(_ snapshot: WatchStrengthSessionSnapshot) -> Bool {
        isValidCheckpoint &&
            snapshot.isEmbeddedRunningInterval == true &&
            workoutID == snapshot.workoutID &&
            exerciseIndex == snapshot.exerciseIndex &&
            setIndex == snapshot.setIndex &&
            snapshot.embeddedRunningTargetDistanceMeters == targetMeters
    }

    func measuredProgress(totalMeters: Double) -> Double? {
        guard isValidCheckpoint, totalMeters.isFinite,
              totalMeters >= baselineMeters else { return nil }
        return totalMeters - baselineMeters
    }

    func hasReached(totalMeters: Double) -> Bool {
        guard let progress = measuredProgress(totalMeters: totalMeters)
        else { return false }
        return progress >= targetMeters
    }

    /// Watch builder active elapsed time already excludes HealthKit pauses.
    func activeDurationSeconds(workoutActiveSeconds: TimeInterval) -> Int? {
        guard isValidCheckpoint, workoutActiveSeconds.isFinite,
              workoutActiveSeconds >= activeElapsedAtStartSeconds
        else { return nil }
        return Int(min(max((workoutActiveSeconds -
            activeElapsedAtStartSeconds).rounded(), 0), 7_200))
    }
}
