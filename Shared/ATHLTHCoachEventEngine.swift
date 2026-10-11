import Foundation

/// Stage 2A: an offline, bounded delivery ledger for Audio Coach cues.
///
/// Each recording device owns its own ledger. Handoff acknowledgements decide
/// which device may speak; cross-device event receipts are a separate step.
/// This model intentionally stores event IDs, never health metrics or phrases.
enum ATHLTHCoachEventKind: String, Codable, Hashable {
    case workoutStart
    case workoutPause
    case workoutResume
    case workoutComplete
    case runningStep
    case routineMilestone
    case targetAlert
    case routeAlert
    case ghostUpdate
    case strengthSet
    case strengthRest
    case manualStatus
}

struct ATHLTHCoachEvent: Hashable {
    let kind: ATHLTHCoachEventKind
    let key: String
    let priority: ATHLTHGuidancePriority
    let createdAt: Date
    let expiresAt: Date

    init(
        kind: ATHLTHCoachEventKind,
        key: String,
        priority: ATHLTHGuidancePriority,
        createdAt: Date = Date(),
        validFor: TimeInterval = 12
    ) {
        self.kind = kind
        self.key = key
        self.priority = priority
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(
            max(validFor, 0)
        )
    }

    var deliveryID: String {
        kind.rawValue + ":" + key
    }

    func isFresh(at now: Date = Date()) -> Bool {
        !key.isEmpty &&
        now.timeIntervalSince(createdAt) >= -2 &&
        now <= expiresAt
    }
}

/// Only mark a cue after voice priority/ownership has accepted it; a dropped
/// routine cue must not consume a real future opportunity to speak it.
struct ATHLTHCoachEventLedger {
    private(set) var deliveredIDs: Set<String> = []
    private var deliveryOrder: [String] = []
    static let maxEntries = 256

    func canDeliver(
        _ event: ATHLTHCoachEvent,
        now: Date = Date()
    ) -> Bool {
        event.isFresh(at: now) &&
        !deliveredIDs.contains(event.deliveryID)
    }

    mutating func didDeliver(
        _ event: ATHLTHCoachEvent,
        now: Date = Date()
    ) {
        guard canDeliver(event, now: now) else {
            return
        }

        let id = event.deliveryID
        deliveredIDs.insert(id)
        deliveryOrder.append(id)

        // Keep the entire recent workout window without unbounded growth.
        if deliveryOrder.count > Self.maxEntries {
            let discarded = deliveryOrder.removeFirst()
            deliveredIDs.remove(discarded)
        }
    }

    /// A validated receipt from the companion marks the same cue as used,
    /// avoiding a replay when voice ownership moves back to Watch.
    mutating func noteCompanionDelivery(id: String) {
        guard !id.isEmpty,
              id.count <= 110,
              !deliveredIDs.contains(id)
        else { return }

        deliveredIDs.insert(id)
        deliveryOrder.append(id)
        if deliveryOrder.count > Self.maxEntries {
            deliveredIDs.remove(deliveryOrder.removeFirst())
        }
    }

    mutating func reset() {
        deliveredIDs.removeAll(keepingCapacity: true)
        deliveryOrder.removeAll(keepingCapacity: true)
    }
}
