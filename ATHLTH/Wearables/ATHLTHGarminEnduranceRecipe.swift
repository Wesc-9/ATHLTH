import Foundation

/// Compact wire projection of the existing Apple Watch prescription, NOT a
/// second planner. Keep the original ordered steps and their source identity.
struct ATHLTHGarminEnduranceRecipe: Equatable {
    enum ProjectionError: Error { case unsupported, invalidStep, tooLarge }
    struct Step: Equatable {
        let id: UUID
        let title: String
        let measure: WatchRunningStepMeasure
        let target: Double?
        let phase: String?
        let paceMin: Double?
        let paceMax: Double?
        let zone: Int?
        var message: [String: Any] {
            var result: [String: Any] = ["id": id.uuidString, "title": title, "measure": measure.rawValue]
            if let target { result["target"] = target }
            if let phase { result["phase"] = phase }
            if let paceMin { result["paceMin"] = paceMin }
            if let paceMax { result["paceMax"] = paceMax }
            if let zone { result["zone"] = zone }
            return result
        }
    }
    let title: String
    let sourceWorkoutID: UUID?
    let plannedPlanID: UUID?
    let plannedSessionID: UUID?
    let steps: [Step]
    let autoAdvance: Bool
    let autoStartMain: Bool

    init(transfer: WatchRunningWorkoutTransfer, plannedPlanID: UUID? = nil,
         plannedSessionID: UUID? = nil) throws {
        guard (plannedPlanID == nil) == (plannedSessionID == nil),
              transfer.treadmillInclinePercent == nil,
              transfer.initialBeltSpeedKilometersPerHour == nil,
              transfer.quickBeltSpeedsKilometersPerHour?.isEmpty != false,
              transfer.autoPauseEnabled != true, transfer.deferRouteUntilMain != true,
              transfer.intervalGhostConfiguration == nil,
              transfer.intervalCoachCueEverySeconds == nil,
              transfer.intervalCoachCountdownSeconds == nil,
              transfer.targetAlerts?.heartRateEnabled != true,
              transfer.targetAlerts?.paceAlertsEnabled != true else { throw ProjectionError.unsupported }
        guard !transfer.steps.isEmpty, transfer.steps.count <= 32,
              Set(transfer.steps.map(\.id)).count == transfer.steps.count else { throw ProjectionError.tooLarge }
        title = transfer.title
        sourceWorkoutID = transfer.sourceWorkoutID
        self.plannedPlanID = plannedPlanID
        self.plannedSessionID = plannedSessionID
        autoAdvance = transfer.autoAdvanceTimedSteps != false
        autoStartMain = transfer.autoStartMainAfterWarmup != false
        steps = try transfer.steps.map { step in
            guard step.targetTreadmillInclinePercent == nil, step.ghostPaceSecondsPerKilometer == nil,
                  step.ghostFollowsRecovery != true, step.ghostRecoverySlowdownPercent == nil,
                  step.coachBrief == nil, step.intervalMotivation == nil, step.spokenReport == nil,
                  step.targetHeartRatePercentMin == nil, step.targetHeartRatePercentMax == nil
            else { throw ProjectionError.unsupported }
            let target: Double?
            switch step.measure {
            case .time: target = step.durationSeconds
            case .distance: target = step.distanceMeters
            case .open: target = nil
            }
            if step.measure != .open {
                guard let target, target.isFinite, target > 0, target <= 172800
                else { throw ProjectionError.invalidStep }
            }
            for pace in [step.targetPaceMinSecondsPerKilometer, step.targetPaceMaxSecondsPerKilometer].compactMap({ $0 }) {
                guard pace.isFinite, pace > 0, pace <= 3600 else { throw ProjectionError.invalidStep }
            }
            if let low = step.targetPaceMinSecondsPerKilometer,
               let high = step.targetPaceMaxSecondsPerKilometer, low > high { throw ProjectionError.invalidStep }
            if let zone = step.targetHeartRateZone, !(1...5).contains(zone) { throw ProjectionError.invalidStep }
            return Step(id: step.id, title: step.title, measure: step.measure, target: target,
                        phase: step.phase, paceMin: step.targetPaceMinSecondsPerKilometer,
                        paceMax: step.targetPaceMaxSecondsPerKilometer, zone: step.targetHeartRateZone)
        }
        let bytes = try JSONSerialization.data(withJSONObject: message).count
        guard bytes <= 10000 else { throw ProjectionError.tooLarge }
    }

    var message: [String: Any] {
        var result: [String: Any] = ["title": title, "steps": steps.map(\.message),
            "autoAdvance": autoAdvance, "autoStartMain": autoStartMain]
        if let sourceWorkoutID { result["sourceWorkoutID"] = sourceWorkoutID.uuidString }
        if let plannedPlanID { result["planID"] = plannedPlanID.uuidString }
        if let plannedSessionID { result["sessionID"] = plannedSessionID.uuidString }
        return result
    }

    /// Use the exact same prepared payload already produced for Apple Watch.
    /// Unsupported prescriptions must never silently become a free workout.
    static func request(from prepared: WatchPreparedWorkoutTransfer, now: Date = .now) throws -> ATHLTHGarminLiveRequest {
        guard prepared.routeID == nil, prepared.ghostRace == nil, prepared.audioCoach == nil,
              prepared.indoor != true, prepared.strengthWorkout == nil,
              let running = prepared.runningWorkout else { throw ProjectionError.unsupported }
        let sport: ATHLTHGarminLiveSport
        switch prepared.kind {
        case .running: sport = .running
        case .walking: sport = .walking
        default: throw ProjectionError.unsupported
        }
        let recipe = try Self(transfer: running, plannedPlanID: prepared.plannedPlanID,
                              plannedSessionID: prepared.plannedSessionID)
        return ATHLTHGarminLiveRequest(id: prepared.id, sport: sport, now: now, recipe: recipe)
    }
}
