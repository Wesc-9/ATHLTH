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
              snapshot.setIndex >= 0, snapshot.exerciseIndex >= 0
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

    func matches(_ snapshot: WatchStrengthSessionSnapshot) -> Bool {
        workoutID == snapshot.workoutID &&
            exerciseIndex == snapshot.exerciseIndex &&
            setIndex == snapshot.setIndex &&
            snapshot.embeddedRunningTargetDistanceMeters == targetMeters
    }

    func measuredProgress(totalMeters: Double) -> Double? {
        guard totalMeters.isFinite, baselineMeters.isFinite,
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
        guard workoutActiveSeconds.isFinite,
              workoutActiveSeconds >= activeElapsedAtStartSeconds
        else { return nil }
        return Int(min(max((workoutActiveSeconds -
            activeElapsedAtStartSeconds).rounded(), 0), 7_200))
    }
}
