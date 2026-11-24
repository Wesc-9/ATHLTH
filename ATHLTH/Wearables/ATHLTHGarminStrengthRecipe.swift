import Foundation

/// The original strength queue is the sole prescription source. The wire
/// identity is allocated once per transfer and preserves the source indices.
struct ATHLTHGarminStrengthRecipe: Equatable {
    enum ProjectionError: Error { case unsupported, invalidSet, tooLarge }
    struct Step: Equatable {
        let id: UUID
        let exerciseIndex: Int
        let setNumber: Int
        let title: String
        let reps: Int?
        let seconds: Int?
        let weight: Double?
        let rest: Int
        var message: [String: Any] {
            var result: [String: Any] = ["id": id.uuidString, "title": title,
                "exerciseIndex": exerciseIndex, "setNumber": setNumber,
                "measure": seconds == nil ? "reps" : "time", "rest": rest]
            if let reps { result["reps"] = reps }
            if let seconds { result["target"] = seconds }
            if let weight { result["weight"] = weight }
            return result
        }
    }
    let title: String
    let sourceWorkoutID: UUID
    let plannedPlanID: UUID?
    let plannedSessionID: UUID?
    let steps: [Step]

    init(snapshot: WatchStrengthSessionSnapshot, plannedPlanID: UUID? = nil,
         plannedSessionID: UUID? = nil) throws {
        guard (plannedPlanID == nil) == (plannedSessionID == nil),
              snapshot.completedSets == 0, (snapshot.skippedSets ?? 0) == 0,
              !snapshot.isResting, !snapshot.allExercisesComplete,
              snapshot.strengthModeRaw == nil,
              snapshot.isEmbeddedRunningInterval != true,
              let queue = snapshot.exerciseQueue, !queue.isEmpty,
              queue.count == snapshot.exerciseCount,
              Set(queue.map(\.index)).count == queue.count
        else { throw ProjectionError.unsupported }
        var projected: [Step] = []
        for exercise in queue {
            guard exercise.index >= 0, exercise.isEmbeddedRunningInterval != true,
                  exercise.strengthGroupID == nil, exercise.strengthGroupStyleRaw == nil,
                  exercise.isCompleted != true, (exercise.skippedSets ?? 0) == 0,
                  let sets = exercise.setPlans, sets.count == exercise.setCount, !sets.isEmpty,
                  Set(sets.map(\.setNumber)).count == sets.count
            else { throw ProjectionError.unsupported }
            for set in sets {
                guard set.setNumber > 0, set.openEndedTime != true,
                      set.resistanceLevel == nil, set.targetRPE == nil, set.targetRIR == nil,
                      set.hybridPhaseKind == nil, set.hybridPhaseTitle == nil,
                      set.hybridTargetDistanceMeters == nil, set.hybridTargetHeartRateZone == nil,
                      set.hybridTargetPaceSecondsPerKilometer == nil,
                      (set.reps != nil) != (set.durationSeconds != nil),
                      set.reps.map({ (1...999).contains($0) }) ?? true,
                      set.durationSeconds.map({ (1...3600).contains($0) }) ?? true,
                      set.weightKilograms.map({ $0.isFinite && (0...2000).contains($0) }) ?? true,
                      (0...3600).contains(set.restSeconds ?? 0)
                else { throw ProjectionError.invalidSet }
                projected.append(Step(id: UUID(), exerciseIndex: exercise.index, setNumber: set.setNumber,
                                      title: exercise.name, reps: set.reps, seconds: set.durationSeconds,
                                      weight: set.weightKilograms, rest: set.restSeconds ?? 0))
            }
        }
        guard !projected.isEmpty, projected.count == snapshot.totalSets,
              projected.count <= 32 else { throw ProjectionError.tooLarge }
        title = snapshot.title
        sourceWorkoutID = snapshot.workoutID
        self.plannedPlanID = plannedPlanID
        self.plannedSessionID = plannedSessionID
        steps = projected
        guard try JSONSerialization.data(withJSONObject: message).count <= 10000 else {
            throw ProjectionError.tooLarge
        }
    }
    var message: [String: Any] {
        var result: [String: Any] = ["title": title, "sourceWorkoutID": sourceWorkoutID.uuidString,
                                     "steps": steps.map(\.message)]
        if let plannedPlanID { result["planID"] = plannedPlanID.uuidString }
        if let plannedSessionID { result["sessionID"] = plannedSessionID.uuidString }
        return result
    }

    static func request(from prepared: WatchPreparedWorkoutTransfer, now: Date = .now) throws -> ATHLTHGarminLiveRequest {
        guard prepared.kind == .strength, prepared.routeID == nil,
              prepared.ghostRace == nil, prepared.audioCoach == nil,
              prepared.runningWorkout == nil, let snapshot = prepared.strengthWorkout
        else { throw ProjectionError.unsupported }
        let recipe = try Self(snapshot: snapshot, plannedPlanID: prepared.plannedPlanID,
                              plannedSessionID: prepared.plannedSessionID)
        return ATHLTHGarminLiveRequest(id: prepared.id, sport: .strength, now: now, strengthRecipe: recipe)
    }
}
