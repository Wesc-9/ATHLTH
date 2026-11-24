import Foundation

/// Versioned transport boundary. Connect IQ is not a HealthKit recorder.
enum ATHLTHGarminLiveSport: String, Codable, CaseIterable {
    case running, walking, strength
}

struct ATHLTHGarminLiveRequest: Equatable {
    let id: UUID
    let sport: ATHLTHGarminLiveSport
    let expiresAt: Date

    init(id: UUID = UUID(), sport: ATHLTHGarminLiveSport, now: Date = .now) {
        self.id = id
        self.sport = sport
        self.expiresAt = now.addingTimeInterval(90)
    }

    var message: [String: Any] {
        ["v": 1, "kind": "prepare", "id": id.uuidString, "sport": sport.rawValue,
         "expires": Int(expiresAt.timeIntervalSince1970)]
    }
}

enum ATHLTHGarminLivePhase: String, Codable {
    case ready, recording, paused, saved, cancelled, expired, error
    var terminal: Bool {
        self == .saved || self == .cancelled || self == .expired || self == .error
    }
}

struct ATHLTHGarminLiveEvent: Equatable {
    let requestID: UUID
    let sequence: Int
    let phase: ATHLTHGarminLivePhase
    let seconds: Double?
    let meters: Double?
    let bpm: Double?

    init?(message: [String: Any]) {
        guard message["v"] as? Int == 1, message["kind"] as? String == "event",
              let raw = message["id"] as? String, let id = UUID(uuidString: raw),
              let sequence = message["seq"] as? Int, sequence > 0,
              let state = message["state"] as? String, let phase = ATHLTHGarminLivePhase(rawValue: state)
        else { return nil }
        func measurement(_ key: String, maximum: Double) -> Double? {
            guard let number = message[key] as? NSNumber,
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.doubleValue <= maximum else { return nil }
            return number.doubleValue
        }
        requestID = id
        self.sequence = sequence
        self.phase = phase
        seconds = measurement("seconds", maximum: 172800)
        meters = measurement("meters", maximum: 1000000)
        bpm = measurement("bpm", maximum: 300).flatMap { $0 > 0 ? $0 : nil }
    }
}

/// No UI or local workout is created from Bluetooth delivery success.
/// Only a matching watch event may confirm the actual recording state.
struct ATHLTHGarminLiveHandshake {
    let request: ATHLTHGarminLiveRequest
    let deviceID: UUID
    private(set) var latest: ATHLTHGarminLiveEvent?

    var confirmedRecording: Bool {
        latest?.phase == .recording || latest?.phase == .paused
    }

    var needsReconciliation: Bool {
        // A timeout or disconnect is not evidence that recording has stopped.
        latest?.phase.terminal != true
    }

    mutating func receive(_ event: ATHLTHGarminLiveEvent, from device: UUID) -> Bool {
        guard device == deviceID, event.requestID == request.id,
              event.sequence > (latest?.sequence ?? 0),
              latest?.phase.terminal != true else { return false }
        if let previous = latest?.phase {
            switch (previous, event.phase) {
            case (.recording, .ready), (.paused, .ready),
                 (.recording, .cancelled), (.paused, .cancelled),
                 (.recording, .expired), (.paused, .expired):
                return false
            default: break
            }
        }
        latest = event
        return true
    }
}

/// The same universal launch arbiter is mandatory once a real SDK transport
/// is installed. This protocol is deliberately not registered as a live provider
/// yet; a synced Garmin account is not proof of live connectivity.
@MainActor
protocol ATHLTHGarminLiveTransport: AnyObject {
    var selectedDeviceID: UUID? { get }
    var isReady: Bool { get }
    func prepare(_ request: ATHLTHGarminLiveRequest) throws
    func requestStatus(id: UUID) throws
    func cancelPrepared(id: UUID) throws
}
