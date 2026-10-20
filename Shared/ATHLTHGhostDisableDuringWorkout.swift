import Foundation

/// An explicit stop command for a local target Ghost. No social live duel or
/// HealthKit workout is cancelled by this message.
struct ATHLTHGhostDisableDuringWorkout: Codable, Equatable {
    let workoutStartedAt: Date
    let requestedAt: Date

    func isValid(workoutStart: Date?, now: Date = Date()) -> Bool {
        guard let workoutStart,
              abs(workoutStartedAt.timeIntervalSince(workoutStart)) < 5
        else { return false }
        let age = now.timeIntervalSince(requestedAt)
        return age >= -5 && age < 30
    }
}
