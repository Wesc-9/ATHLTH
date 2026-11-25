import Foundation

/// Versioned transport boundary. Connect IQ is not a HealthKit recorder.
enum ATHLTHGarminLiveSport: String, Codable, CaseIterable {
    case running, walking, strength
}

struct ATHLTHGarminLiveRequest: Equatable {
    let id: UUID
    let sport: ATHLTHGarminLiveSport
    let expiresAt: Date
    let recipe: ATHLTHGarminEnduranceRecipe?
    let strengthRecipe: ATHLTHGarminStrengthRecipe?
    let offlineCoach: ATHLTHGarminOfflineCoachPlan?

    var recipeVersion: Int { strengthRecipe != nil ? 3 : (recipe == nil ? 1 : 2) }

    init(id: UUID = UUID(), sport: ATHLTHGarminLiveSport, now: Date = .now,
         recipe: ATHLTHGarminEnduranceRecipe? = nil,
         strengthRecipe: ATHLTHGarminStrengthRecipe? = nil,
         offlineCoach: ATHLTHGarminOfflineCoachPlan? = nil) {
        self.id = id
        self.sport = sport
        self.expiresAt = now.addingTimeInterval(90)
        self.recipe = recipe
        self.strengthRecipe = strengthRecipe
        self.offlineCoach = offlineCoach
    }

    var message: [String: Any] {
        var payload: [String: Any] = ["v": offlineCoach == nil ? recipeVersion : 4,
            "kind": "prepare", "id": id.uuidString, "sport": sport.rawValue,
            "expires": Int(expiresAt.timeIntervalSince1970)]
        if let recipe { payload["recipe"] = recipe.message }
        if let strengthRecipe { payload["recipe"] = strengthRecipe.message }
        if let offlineCoach {
            payload["recipeVersion"] = recipeVersion
            payload["coach"] = offlineCoach.message
        }
        return payload
    }
}

enum ATHLTHGarminLivePhase: String, Codable {
    case ready, recording, paused, saved, cancelled, expired, error
    var terminal: Bool {
        self == .saved || self == .cancelled || self == .expired
    }
}

struct ATHLTHGarminLiveEvent: Equatable {
    let requestID: UUID
    let sequence: Int
    let phase: ATHLTHGarminLivePhase
    let seconds: Double?
    let meters: Double?
    let bpm: Double?
    let stepIndex: Int?
    let stepID: UUID?
    let recipeComplete: Bool?
    let version: Int
    let completedSets: Int?
    let resting: Bool?
    let coachStatus: String?
    let firmwareVersion: String?
    let partNumber: String?

    init?(message: [String: Any]) {
        guard let version = message["v"] as? Int, [1, 2, 3, 4].contains(version),
              message["kind"] as? String == "event",
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
        self.version = version
        requestID = id
        self.sequence = sequence
        self.phase = phase
        seconds = measurement("seconds", maximum: 172800)
        meters = measurement("meters", maximum: 1000000)
        bpm = measurement("bpm", maximum: 300).flatMap { $0 > 0 ? $0 : nil }
        stepIndex = (message["stepIndex"] as? Int).flatMap { $0 >= 0 && $0 < 32 ? $0 : nil }
        stepID = (message["stepID"] as? String).flatMap(UUID.init(uuidString:))
        recipeComplete = message["recipeComplete"] as? Bool
        completedSets = (message["completedSets"] as? Int).flatMap { (0...32).contains($0) ? $0 : nil }
        resting = message["resting"] as? Bool
        coachStatus = message["coachStatus"] as? String
        func boundedMetadata(_ key: String) -> String? {
            guard let value = message[key] as? String,
                  !value.isEmpty, value.count <= 64,
                  value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { return nil }
            return value
        }
        firmwareVersion = boundedMetadata("firmwareVersion")
        partNumber = boundedMetadata("partNumber")
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
        let expectedVersion = request.offlineCoach == nil ? request.recipeVersion : 4
        guard event.version == expectedVersion else { return false }
        if request.offlineCoach != nil {
            guard let status = event.coachStatus,
                  ["ready", "playing", "error"].contains(status) else { return false }
        }
        if let recipe = request.recipe {
            guard let index = event.stepIndex,
                  recipe.steps.indices.contains(index),
                  event.stepID == recipe.steps[index].id,
                  index >= (latest?.stepIndex ?? 0),
                  event.recipeComplete != true || index == recipe.steps.count - 1,
                  latest?.recipeComplete != true || event.recipeComplete == true
            else { return false }
        } else if let strength = request.strengthRecipe {
            guard let index = event.stepIndex,
                  strength.steps.indices.contains(index),
                  event.stepID == strength.steps[index].id,
                  let count = event.completedSets, let resting = event.resting,
                  count >= (latest?.completedSets ?? 0),
                  index >= (latest?.stepIndex ?? 0),
                  count == index + (resting || event.recipeComplete == true ? 1 : 0),
                  event.recipeComplete != true || (count == strength.steps.count && !resting),
                  latest?.recipeComplete != true || event.recipeComplete == true
            else { return false }
        }
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
