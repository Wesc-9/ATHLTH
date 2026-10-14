import Foundation

/// Privacy-minimal, read-only values for a user-initiated AI voice question.
/// Never includes GPS coordinates, route geometry, person identifiers, or history.
struct ATHLTHLiveCoachWorkoutStatus: Encodable {
    let availability: String
    let activity: String?
    let state: String?
    let elapsedSeconds: Int?
    let distanceMeters: Int?
    let paceSecondsPerKilometer: Int?
    let heartRateBPM: Int?
    let currentStep: String?
    let nextStep: String?
    let stepNumber: Int?
    let totalSteps: Int?
    let stepRemainingSeconds: Int?
    let stepRemainingMeters: Int?
    let targetPaceMinimumSecondsPerKilometer: Int?
    let targetPaceMaximumSecondsPerKilometer: Int?

    static var unavailable: Self {
        Self(availability: "unavailable", activity: nil, state: nil,
             elapsedSeconds: nil, distanceMeters: nil, paceSecondsPerKilometer: nil,
             heartRateBPM: nil, currentStep: nil, nextStep: nil,
             stepNumber: nil, totalSteps: nil, stepRemainingSeconds: nil,
             stepRemainingMeters: nil, targetPaceMinimumSecondsPerKilometer: nil,
             targetPaceMaximumSecondsPerKilometer: nil)
    }

    static func positiveInteger(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0,
              value < Double(Int.max) else { return nil }
        return Int(value.rounded())
    }

    static func fromWatch(
        _ snapshot: WatchWorkoutLiveSnapshot?,
        now: Date = Date()
    ) -> Self {
        guard let snapshot,
              ATHLTHCoachSensorFreshness.isFresh(
                sampledAt: snapshot.capturedAt,
                maximumAge: ATHLTHCoachSensorFreshness.maximumSnapshotAge,
                now: now
              ),
              snapshot.state == .running || snapshot.state == .paused
        else { return .unavailable }
        let running = snapshot.state == .running
        return Self(
            availability: "available",
            activity: snapshot.kind.rawValue,
            state: snapshot.state.rawValue,
            elapsedSeconds: positiveInteger(snapshot.elapsedTime),
            distanceMeters: positiveInteger(snapshot.distanceMeters),
            paceSecondsPerKilometer: running &&
                ATHLTHCoachSensorFreshness.validPace(
                    snapshot.currentPaceSecondsPerKilometer,
                    sampledAt: snapshot.coachPaceSampleAt, now: now
                ) ? positiveInteger(snapshot.currentPaceSecondsPerKilometer) : nil,
            heartRateBPM: ATHLTHCoachSensorFreshness.validHeartRate(
                snapshot.heartRate, sampledAt: snapshot.coachHeartRateSampleAt,
                now: now
            ) ? positiveInteger(snapshot.heartRate) : nil,
            currentStep: snapshot.runningStepTitle,
            nextStep: snapshot.runningNextStepTitle,
            stepNumber: snapshot.runningStepIndex.map { $0 + 1 },
            totalSteps: snapshot.runningStepCount,
            stepRemainingSeconds: positiveInteger(snapshot.runningStepRemainingSeconds),
            stepRemainingMeters: positiveInteger(snapshot.runningStepRemainingMeters),
            targetPaceMinimumSecondsPerKilometer: nil,
            targetPaceMaximumSecondsPerKilometer: nil
        )
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let value = try? encoder.encode(self),
              let output = String(data: value, encoding: .utf8)
        else { return "{\"availability\":\"unavailable\"}" }
        return output
    }
}
