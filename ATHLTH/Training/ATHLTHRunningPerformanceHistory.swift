import Foundation

/// Actual per-effort speeds, stored only for a completely finished recording.
/// Never use planned target pace as proof of a performed result.
struct ATHLTHCompletedRunningPerformance: Identifiable, Codable, Hashable {
    let id: UUID
    let workoutID: UUID?
    let title: String
    let completedAt: Date
    let source: String
    let steps: [ATHLTHRecordedRunningStep]

    var workSteps: [ATHLTHRecordedRunningStep] {
        steps.filter { !["warmup", "cooldown", "recovery", "rest"]
            .contains(($0.phase ?? "main").lowercased()) }
    }

    var averageWorkSpeed: Double? {
        let measured = workSteps.filter { $0.actualSpeedKilometersPerHour != nil }
        let elapsed = measured.reduce(0.0) { $0 + $1.activeSeconds }
        guard elapsed > 0 else { return nil }
        let meters = measured.reduce(0.0) { $0 + $1.distanceMeters }
        let speed = meters * 3.6 / elapsed
        return speed.isFinite && speed > 0 ? speed : nil
    }

    var userReported: Bool { workSteps.contains { $0.isUserReported } }

    static func validFullRecording(
        _ steps: [ATHLTHRecordedRunningStep],
        expectedCount: Int
    ) -> Bool {
        guard expectedCount > 0,
              steps.count == expectedCount,
              Set(steps.map(\.index)) == Set(0..<expectedCount),
              steps.allSatisfy({
                  $0.activeSeconds >= 10 && $0.activeSeconds.isFinite &&
                  $0.distanceMeters >= 0 && $0.distanceMeters.isFinite
              })
        else { return false }
        return steps.contains {
            !["warmup", "cooldown", "recovery", "rest"]
                .contains(($0.phase ?? "main").lowercased()) &&
                $0.actualSpeedKilometersPerHour != nil
        }
    }

    init?(phone: PhoneWorkout) {
        guard let finished = phone.end,
              phone.structuredWorkoutComplete == true,
              let recipe = phone.structuredRunningWorkout,
              let recorded = phone.recordedRunningSteps,
              Self.validFullRecording(recorded, expectedCount: recipe.steps.count)
        else { return nil }
        id = phone.id
        workoutID = phone.plannedSessionID ?? recipe.sourceWorkoutID
        title = phone.workoutTitle?.isEmpty == false ? phone.workoutTitle! : recipe.title
        completedAt = finished
        source = "iPhone"
        steps = recorded
    }

    init?(watch: WatchWorkoutResult) {
        guard watch.structuredWorkoutFullyCompleted == true,
              let recorded = watch.recordedRunningSteps,
              Self.validFullRecording(recorded, expectedCount: recorded.count)
        else { return nil }
        id = watch.id
        workoutID = watch.structuredWorkoutSourceID
        title = watch.structuredWorkoutTitle ?? "Intervaller"
        completedAt = watch.endedAt
        source = "Apple Watch"
        steps = recorded
    }
}

/// A consumed Watch result remains available for the athlete's progression.
/// Account scoping, stable result IDs and known workout IDs prevent duplicates
/// and cross-account attribution.
enum ATHLTHRunningPerformanceHistory {
    private static let name = "completedRunningPerformance"

    static func load(userID: UUID) -> [ATHLTHCompletedRunningPerformance] {
        AccountLocalStorage.read(
            [ATHLTHCompletedRunningPerformance].self, name: name, userID: userID
        ) ?? []
    }

    static func saveWatch(
        _ result: WatchWorkoutResult,
        userID: UUID,
        knownWorkoutIDs: Set<UUID>
    ) {
        guard let record = ATHLTHCompletedRunningPerformance(watch: result),
              let workoutID = record.workoutID,
              knownWorkoutIDs.contains(workoutID) else { return }
        var history = load(userID: userID)
        guard !history.contains(where: { $0.id == record.id }) else { return }
        history.insert(record, at: 0)
        if history.count > 300 { history = Array(history.prefix(300)) }
        AccountLocalStorage.write(history, name: name, userID: userID)
        ATHLTHTrainingDataChangeSignal.post(userID: userID)
    }
}
