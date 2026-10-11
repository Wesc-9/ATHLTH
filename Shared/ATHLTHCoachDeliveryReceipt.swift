import Foundation

/// A minimal, best-effort notice of a mirrored spoken cue attempt.
///
/// The message contains no spoken text, sensor values, GPS position, name or
/// health data. Only routine/step cues with stable event keys may travel here.
/// Older app versions safely ignore the standalone JSON payload.
struct ATHLTHCoachDeliveryReceipt: Codable, Hashable {
    var workoutStartedAt: Date
    var eventKind: ATHLTHCoachEventKind
    var eventKey: String
    var sentAt: Date

    var deliveryID: String {
        eventKind.rawValue + ":" + eventKey
    }

    func isValid(
        for workoutStart: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let workoutStart,
              abs(workoutStart.timeIntervalSince(workoutStartedAt)) <= 1,
              eventKey.count > 0,
              eventKey.count <= 80,
              now.timeIntervalSince(sentAt) >= -2,
              now.timeIntervalSince(sentAt) <= 12
        else { return false }

        switch eventKind {
        case .workoutStart, .runningStep, .routineMilestone:
            return true
        default:
            return false
        }
    }
}


/// A receipt may arrive in the same HealthKit mirroring batch as a newer
/// workout snapshot. Validate against that snapshot, never an older session.
/// Receipt text and health measurements are intentionally not persisted.
enum ATHLTHCoachReceiptAcceptance {
    static func verifiedWorkoutStart(
        for receipt: ATHLTHCoachDeliveryReceipt,
        latestSnapshot: WatchWorkoutLiveSnapshot?,
        previousSnapshot: WatchWorkoutLiveSnapshot?,
        now: Date = Date()
    ) -> Date? {
        guard let current = latestSnapshot ?? previousSnapshot,
              current.state == .running || current.state == .paused,
              receipt.isValid(for: current.startedAt, now: now)
        else { return nil }
        return current.startedAt
    }
}
