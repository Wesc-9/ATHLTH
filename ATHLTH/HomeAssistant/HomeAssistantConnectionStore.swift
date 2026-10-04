import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
import UIKit

struct HomeAssistantDiscoveredInstance: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let internalURL: URL?
    let externalURL: URL?
    let version: String?

    var preferredURL: URL? {
        internalURL ?? externalURL
    }

    var displayURL: String {
        preferredURL?.absoluteString ?? "Address unavailable"
    }
}

enum HomeAssistantConnectionState: Equatable {
    case disconnected
    case discovering
    case authorizing
    case pairing
    case connected
    case error(String)

    var title: String {
        switch self {
        case .disconnected:
            return ATHLTHLocalization.choose(
                english: "Connect",
                norwegian: "Koble til"
            )
        case .discovering:
            return ATHLTHLocalization.choose(
                english: "Searching",
                norwegian: "Søker"
            )
        case .authorizing:
            return ATHLTHLocalization.choose(
                english: "Authorizing",
                norwegian: "Godkjenner"
            )
        case .pairing:
            return ATHLTHLocalization.choose(
                english: "Pairing",
                norwegian: "Kobler"
            )
        case .connected:
            return ATHLTHLocalization.choose(
                english: "Connected",
                norwegian: "Tilkoblet"
            )
        case .error:
            return ATHLTHLocalization.choose(
                english: "Needs attention",
                norwegian: "Krever oppmerksomhet"
            )
        }
    }
}

private struct HomeAssistantOAuthTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

private struct HomeAssistantPairResponse: Decodable {
    let protocolVersion: Int
    let clientID: String
    let webhookID: String
    let webhookURL: URL
    let webhookPath: String
    let sharedSecret: String
    let signatureAlgorithm: String
    let capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case clientID = "client_id"
        case webhookID = "webhook_id"
        case webhookURL = "webhook_url"
        case webhookPath = "webhook_path"
        case sharedSecret = "shared_secret"
        case signatureAlgorithm = "signature_algorithm"
        case capabilities
    }
}

private struct HomeAssistantStoredPairing: Codable {
    let instanceName: String
    let instanceURL: URL
    let protocolVersion: Int
    let clientID: String
    let webhookID: String
    let webhookURL: URL
    let webhookPath: String
    let sharedSecret: String
    let signatureAlgorithm: String
    let capabilities: [String]
    let pairedAt: Date
}

private struct HomeAssistantWebhookEnvelope: Encodable {
    let event: String
    let payload: [String: HomeAssistantJSONValue]
}

private struct HomeAssistantPendingDelivery: Codable, Identifiable {
    let id: UUID
    let pairingWebhookID: String
    let event: String
    let payload: [String: HomeAssistantJSONValue]
    let createdAt: Date
}

enum HomeAssistantJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: HomeAssistantJSONValue])
    case array([HomeAssistantJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(
            [String: HomeAssistantJSONValue].self
        ) {
            self = .object(value)
        } else {
            self = .array(
                try container.decode([HomeAssistantJSONValue].self)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

@MainActor
final class HomeAssistantConnectionStore: NSObject, ObservableObject {
    @Published private(set) var connectionState: HomeAssistantConnectionState
    @Published private(set) var discoveredInstances:
        [HomeAssistantDiscoveredInstance] = []
    @Published private(set) var connectedInstanceName: String?
    @Published private(set) var connectedInstanceURL: URL?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var pendingDeliveryCount: Int = 0

    @Published var shareWorkoutState: Bool {
        didSet {
            UserDefaults.standard.set(
                shareWorkoutState,
                forKey: Self.shareWorkoutStateKey
            )
        }
    }

    @Published var shareCompletedWorkouts: Bool {
        didSet {
            UserDefaults.standard.set(
                shareCompletedWorkouts,
                forKey: Self.shareCompletedWorkoutsKey
            )
        }
    }

    @Published var shareRecovery: Bool {
        didSet {
            UserDefaults.standard.set(
                shareRecovery,
                forKey: Self.shareRecoveryKey
            )
        }
    }

    @Published var shareTrainingLoad: Bool {
        didSet {
            UserDefaults.standard.set(
                shareTrainingLoad,
                forKey: Self.shareTrainingLoadKey
            )
        }
    }

    @Published var shareWeeklyProgress: Bool {
        didSet {
            UserDefaults.standard.set(
                shareWeeklyProgress,
                forKey: Self.shareWeeklyProgressKey
            )
        }
    }

    @Published var shareNextWorkout: Bool {
        didSet {
            UserDefaults.standard.set(
                shareNextWorkout,
                forKey: Self.shareNextWorkoutKey
            )
        }
    }

    private static let shareWorkoutStateKey =
        "athlth.homeAssistant.shareWorkoutState"
    private static let shareCompletedWorkoutsKey =
        "athlth.homeAssistant.shareCompletedWorkouts"
    private static let shareRecoveryKey =
        "athlth.homeAssistant.shareRecovery"
    private static let shareTrainingLoadKey =
        "athlth.homeAssistant.shareTrainingLoad"
    private static let shareWeeklyProgressKey =
        "athlth.homeAssistant.shareWeeklyProgress"
    private static let shareNextWorkoutKey =
        "athlth.homeAssistant.shareNextWorkout"

    private let keychainService = "com.wesc9.athlth.home-assistant"
    private let keychainAccount = "pairing-v1"
    private let pendingDeliveryAccount = "pending-deliveries-v1"
    private static let maxPendingDeliveries = 16
    private static let pendingDeliveryMaxAge: TimeInterval =
        7 * 24 * 60 * 60
    private let discoveryQueue = DispatchQueue(
        label: "com.wesc9.athlth.home-assistant.discovery",
        qos: .userInitiated
    )

    private var browser: NWBrowser?
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private var storedPairing: HomeAssistantStoredPairing?
    private var pendingDeliveries: [HomeAssistantPendingDelivery]

    private var oauthClientID: String {
        configuredInfoValue("ATHLTHHomeAssistantClientID")
    }

    private var redirectURI: String {
        let configured = configuredInfoValue(
            "ATHLTHHomeAssistantRedirectURI"
        )
        return configured.isEmpty
            ? "athlth://home-assistant"
            : configured
    }

    var isOAuthClientConfigured: Bool {
        guard let url = URL(string: oauthClientID),
              url.scheme?.lowercased() == "https",
              url.host != nil
        else {
            return false
        }
        return true
    }

    var isConnected: Bool {
        storedPairing != nil
    }

    var connectionSubtitle: String {
        if let name = connectedInstanceName {
            return ATHLTHLocalization.choose(
                english: "Secure webhook · \(name)",
                norwegian: "Sikker webhook · \(name)"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Connect without API keys",
            norwegian: "Koble til uten API-nøkler"
        )
    }

    override init() {
        let defaults = UserDefaults.standard
        let restored = Self.readStoredPairing(
            service: "com.wesc9.athlth.home-assistant",
            account: "pairing-v1"
        )
        let restoredPending =
            Self.readPendingDeliveries(
                service: "com.wesc9.athlth.home-assistant",
                account: "pending-deliveries-v1"
            )

        shareWorkoutState = Self.storedBool(
            defaults,
            key: Self.shareWorkoutStateKey,
            defaultValue: true
        )
        shareCompletedWorkouts = Self.storedBool(
            defaults,
            key: Self.shareCompletedWorkoutsKey,
            defaultValue: true
        )
        shareRecovery = Self.storedBool(
            defaults,
            key: Self.shareRecoveryKey,
            defaultValue: false
        )
        shareTrainingLoad = Self.storedBool(
            defaults,
            key: Self.shareTrainingLoadKey,
            defaultValue: false
        )
        shareWeeklyProgress = Self.storedBool(
            defaults,
            key: Self.shareWeeklyProgressKey,
            defaultValue: true
        )
        shareNextWorkout = Self.storedBool(
            defaults,
            key: Self.shareNextWorkoutKey,
            defaultValue: true
        )

        storedPairing = restored
        pendingDeliveries =
            Self.filteredPendingDeliveries(
                restoredPending,
                pairingWebhookID:
                    restored?.webhookID
            )
        connectedInstanceName = restored?.instanceName
        connectedInstanceURL = restored?.instanceURL
        connectionState = restored == nil ? .disconnected : .connected
        super.init()
        pendingDeliveryCount = pendingDeliveries.count

        if pendingDeliveries.count !=
            restoredPending.count {
            persistPendingDeliveries()
        }
    }

    func startDiscovery() {
        guard !isConnected else {
            connectionState = .connected
            return
        }

        browser?.cancel()
        discoveredInstances = []
        lastErrorMessage = nil
        connectionState = .discovering

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false

        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(
                type: "_home-assistant._tcp",
                domain: "local."
            ),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                Task { @MainActor [weak self] in
                    self?.lastErrorMessage = error.localizedDescription
                    self?.connectionState = .error(
                        error.localizedDescription
                    )
                }
            case .cancelled:
                break
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = {
            [weak self] results, _ in
            let instances = results.compactMap {
                Self.instance(from: $0)
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }

            Task { @MainActor [weak self] in
                guard let self, !self.isConnected else {
                    return
                }
                self.discoveredInstances = instances
                self.connectionState = .discovering
            }
        }

        self.browser = browser
        browser.start(queue: discoveryQueue)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        if !isConnected,
           case .discovering = connectionState {
            connectionState = .disconnected
        }
    }

    func connect(to instance: HomeAssistantDiscoveredInstance) {
        guard let baseURL = instance.preferredURL else {
            lastErrorMessage = ATHLTHLocalization.choose(
                english:
                    "Home Assistant was found, but it did not advertise a usable URL.",
                norwegian:
                    "Home Assistant ble funnet, men annonserte ingen brukbar URL."
            )
            connectionState = .error(lastErrorMessage ?? "")
            return
        }

        beginAuthorization(
            baseURL: baseURL,
            instanceName: instance.name
        )
    }

    func connectManually(address: String) {
        guard let baseURL = Self.normalizedBaseURL(from: address)
        else {
            let message = ATHLTHLocalization.choose(
                english: "Enter a valid Home Assistant address.",
                norwegian: "Skriv inn en gyldig Home Assistant-adresse."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        beginAuthorization(
            baseURL: baseURL,
            instanceName:
                baseURL.host
                ?? ATHLTHLocalization.choose(
                    english: "Home Assistant",
                    norwegian: "Home Assistant"
                )
        )
    }

    func disconnect() async {
        if isConnected {
            try? await send(event: "unpair")
        }

        webAuthenticationSession?.cancel()
        webAuthenticationSession = nil
        browser?.cancel()
        browser = nil

        Self.deleteStoredPairing(
            service: keychainService,
            account: keychainAccount
        )
        clearPendingDeliveries()
        storedPairing = nil
        connectedInstanceName = nil
        connectedInstanceURL = nil
        discoveredInstances = []
        lastErrorMessage = nil
        connectionState = .disconnected
    }

    func send(
        event: String,
        payload: [String: HomeAssistantJSONValue] = [:]
    ) async throws {
        guard let pairing = storedPairing else {
            throw HomeAssistantConnectionError.notConnected
        }

        let envelope = HomeAssistantWebhookEnvelope(
            event: event,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(envelope)

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString.lowercased()
        let signature = Self.signature(
            secret: pairing.sharedSecret,
            timestamp: timestamp,
            nonce: nonce,
            body: body
        )

        do {
            let status = try await Self.sendWebhookRequest(
                to: pairing.webhookURL,
                body: body,
                timestamp: timestamp,
                nonce: nonce,
                signature: signature
            )

            guard (200..<300).contains(status) else {
                if Self.shouldTryWebhookFallback(
                    after: status
                ),
                   let fallback =
                    Self.fallbackWebhookURL(
                        for: pairing
                    ),
                   fallback != pairing.webhookURL {
                    let fallbackStatus =
                        try await Self.sendWebhookRequest(
                            to: fallback,
                            body: body,
                            timestamp: timestamp,
                            nonce: nonce,
                            signature: signature
                        )

                    guard (200..<300)
                        .contains(
                            fallbackStatus
                        ) ||
                        fallbackStatus == 409
                    else {
                        throw Self.webhookError(
                            for: fallbackStatus
                        )
                    }
                    return
                }

                throw Self.webhookError(
                    for: status
                )
            }
        } catch let error as HomeAssistantConnectionError {
            throw error
        } catch {
            guard let fallback =
                    Self.fallbackWebhookURL(
                        for: pairing
                    ),
                  fallback != pairing.webhookURL
            else {
                throw error
            }

            let fallbackStatus =
                try await Self.sendWebhookRequest(
                    to: fallback,
                    body: body,
                    timestamp: timestamp,
                    nonce: nonce,
                    signature: signature
                )

            guard (200..<300).contains(fallbackStatus) ||
                    fallbackStatus == 409
            else {
                throw Self.webhookError(
                    for: fallbackStatus
                )
            }
        }
    }

    private func sendReliably(
        event: String,
        payload: [String: HomeAssistantJSONValue]
    ) async {
        guard let pairing = storedPairing else {
            return
        }

        if event == "sync_snapshot" {
            pendingDeliveries.removeAll {
                $0.pairingWebhookID ==
                    pairing.webhookID &&
                $0.event == "sync_snapshot"
            }
            persistPendingDeliveries()
        }

        await flushPendingDeliveries()

        let delivery =
            HomeAssistantPendingDelivery(
                id: UUID(),
                pairingWebhookID:
                    pairing.webhookID,
                event: event,
                payload: payload,
                createdAt: Date()
            )

        do {
            try await sendPendingDelivery(
                delivery
            )
        } catch let error as HomeAssistantConnectionError {
            switch error {
            case .notConnected,
                 .webhookRejected:
                return
            default:
                enqueuePendingDelivery(
                    delivery
                )
            }
        } catch {
            enqueuePendingDelivery(
                delivery
            )
        }
    }

    func flushPendingDeliveries() async {
        guard let pairing = storedPairing else {
            clearPendingDeliveries()
            return
        }

        prunePendingDeliveries(
            pairingWebhookID:
                pairing.webhookID
        )

        let deliveries =
            pendingDeliveries
                .sorted {
                    $0.createdAt <
                        $1.createdAt
                }

        for delivery in deliveries {
            guard pendingDeliveries
                .contains(
                    where: {
                        $0.id == delivery.id
                    }
                )
            else {
                continue
            }

            do {
                try await sendPendingDelivery(
                    delivery
                )
                pendingDeliveries
                    .removeAll {
                        $0.id ==
                            delivery.id
                    }
                persistPendingDeliveries()
            } catch {
                break
            }
        }
    }

    private func sendPendingDelivery(
        _ delivery: HomeAssistantPendingDelivery
    ) async throws {
        guard let pairing = storedPairing,
              pairing.webhookID ==
                delivery.pairingWebhookID
        else {
            throw HomeAssistantConnectionError
                .notConnected
        }

        var payload = delivery.payload
        payload["delivery_id"] = .string(
            delivery.id
                .uuidString
                .lowercased()
        )

        try await send(
            event: delivery.event,
            payload: payload
        )
    }

    private func enqueuePendingDelivery(
        _ delivery: HomeAssistantPendingDelivery
    ) {
        guard let pairing = storedPairing,
              pairing.webhookID ==
                delivery.pairingWebhookID
        else {
            return
        }

        if delivery.event == "sync_snapshot" {
            pendingDeliveries.removeAll {
                $0.pairingWebhookID ==
                    pairing.webhookID &&
                $0.event ==
                    "sync_snapshot"
            }
        }

        pendingDeliveries.append(delivery)
        prunePendingDeliveries(
            pairingWebhookID:
                pairing.webhookID
        )

        if pendingDeliveries.count >
            Self.maxPendingDeliveries {
            pendingDeliveries =
                Array(
                    pendingDeliveries
                        .sorted {
                            $0.createdAt >
                                $1.createdAt
                        }
                        .prefix(
                            Self.maxPendingDeliveries
                        )
                        .reversed()
                )
        }

        persistPendingDeliveries()
    }

    private func prunePendingDeliveries(
        pairingWebhookID: String
    ) {
        let cutoff =
            Date().addingTimeInterval(
                -Self.pendingDeliveryMaxAge
            )

        pendingDeliveries.removeAll {
            $0.pairingWebhookID !=
                pairingWebhookID ||
            $0.createdAt < cutoff
        }
        pendingDeliveryCount =
            pendingDeliveries.count
    }

    private func persistPendingDeliveries() {
        pendingDeliveryCount =
            pendingDeliveries.count

        guard !pendingDeliveries.isEmpty else {
            Self.deleteSecureItem(
                service: keychainService,
                account:
                    pendingDeliveryAccount
            )
            return
        }

        guard let data =
                try? JSONEncoder()
                    .encode(
                        pendingDeliveries
                    )
        else {
            return
        }

        _ = Self.writeSecureData(
            data,
            service: keychainService,
            account:
                pendingDeliveryAccount
        )
    }

    private func clearPendingDeliveries() {
        pendingDeliveries.removeAll()
        pendingDeliveryCount = 0
        Self.deleteSecureItem(
            service: keychainService,
            account:
                pendingDeliveryAccount
        )
    }

    func sendConnectionTest() async {
        guard isConnected else {
            return
        }

        do {
            try await send(
                event: "sync_snapshot",
                payload: [
                    "state": .object([:])
                ]
            )
            lastErrorMessage = nil
            connectionState = .connected
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionState = .error(error.localizedDescription)
        }
    }

    func sendWorkoutStarted(
        name: String?,
        startedAt: Date?
    ) async {
        guard isConnected,
              shareWorkoutState
        else {
            return
        }

        var payload: [String: HomeAssistantJSONValue] = [:]
        if let name = Self.sanitizedText(name) {
            payload["name"] = .string(name)
        }
        if let startedAt {
            payload["started_at"] = .string(
                Self.iso8601(startedAt)
            )
        }

        try? await send(
            event: "workout_started",
            payload: payload
        )
    }

    func sendWorkoutStopped() async {
        guard isConnected,
              shareWorkoutState
        else {
            return
        }

        await sendReliably(
            event: "sync_snapshot",
            payload: [
                "state": .object([
                    "workout_active": .bool(false),
                    "active_workout": .null
                ])
            ]
        )
    }

    func sendWorkoutCancelled() async {
        guard isConnected,
              shareWorkoutState
        else {
            return
        }

        try? await send(
            event: "workout_cancelled"
        )
    }

    func sendCompletedWorkout(
        name: String,
        type: String,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double?
    ) async {
        guard isConnected else {
            return
        }

        if shareCompletedWorkouts {
            var payload: [String: HomeAssistantJSONValue] = [
                "completed": .bool(true),
                "name": .string(
                    Self.sanitizedText(name) ?? "Workout"
                ),
                "type": .string(
                    Self.sanitizedText(type) ?? "workout"
                ),
                "started_at": .string(
                    Self.iso8601(startedAt)
                ),
                "ended_at": .string(
                    Self.iso8601(endedAt)
                ),
                "duration_seconds": .double(
                    max(duration, 0)
                )
            ]

            if let distanceMeters,
               distanceMeters.isFinite,
               distanceMeters >= 0 {
                payload["distance_meters"] = .double(
                    distanceMeters
                )
            }

            await sendReliably(
                event: "workout_finished",
                payload: payload
            )
            return
        }

        if shareWorkoutState {
            await sendReliably(
                event: "sync_snapshot",
                payload: [
                    "state": .object([
                        "workout_active": .bool(false),
                        "active_workout": .null
                    ])
                ]
            )
        }
    }

    func sendRecovery(score: Int?) async {
        guard isConnected,
              shareRecovery,
              let score
        else {
            return
        }

        try? await send(
            event: "recovery_updated",
            payload: [
                "score": .int(
                    min(max(score, 0), 100)
                )
            ]
        )
    }

    func sendTrainingLoad(ratio: Double?) async {
        guard isConnected,
              shareTrainingLoad,
              let ratio,
              ratio.isFinite
        else {
            return
        }

        try? await send(
            event: "training_load_updated",
            payload: [
                "load": .double(
                    min(max(ratio, 0), 10)
                )
            ]
        )
    }

    func sendWeeklyProgress(percent: Double?) async {
        guard isConnected,
              shareWeeklyProgress,
              let percent,
              percent.isFinite
        else {
            return
        }

        try? await send(
            event: "weekly_progress_updated",
            payload: [
                "percent": .double(
                    min(max(percent, 0), 100)
                )
            ]
        )
    }

    func sendNextWorkout(
        name: String?
    ) async {
        guard isConnected,
              shareNextWorkout
        else {
            return
        }

        try? await send(
            event: "next_workout_updated",
            payload: [
                "name":
                    Self.sanitizedText(name)
                        .map(HomeAssistantJSONValue.string)
                    ?? .null
            ]
        )
    }

    func syncSnapshot(
        workoutActive: Bool,
        activeWorkout: String?,
        lastWorkout: String?,
        recoveryScore: Int?,
        trainingLoad: Double?,
        weeklyProgress: Double?,
        nextWorkout: String?
    ) async {
        guard isConnected else {
            return
        }

        var state: [String: HomeAssistantJSONValue] = [:]

        if shareWorkoutState {
            state["workout_active"] = .bool(workoutActive)
            state["active_workout"] =
                Self.sanitizedText(activeWorkout)
                    .map(HomeAssistantJSONValue.string)
                ?? .null
        } else {
            state["workout_active"] = .bool(false)
            state["active_workout"] = .null
        }

        state["last_workout"] =
            shareCompletedWorkouts
                ? (
                    Self.sanitizedText(lastWorkout)
                        .map(HomeAssistantJSONValue.string)
                    ?? .null
                )
                : .null

        state["recovery_score"] =
            shareRecovery && recoveryScore != nil
                ? .int(
                    min(
                        max(recoveryScore ?? 0, 0),
                        100
                    )
                )
                : .null

        state["training_load"] =
            shareTrainingLoad &&
                trainingLoad?.isFinite == true
                ? .double(
                    min(
                        max(trainingLoad ?? 0, 0),
                        10
                    )
                )
                : .null

        state["weekly_progress"] =
            shareWeeklyProgress &&
                weeklyProgress?.isFinite == true
                ? .double(
                    min(
                        max(weeklyProgress ?? 0, 0),
                        100
                    )
                )
                : .null

        state["next_workout"] =
            shareNextWorkout
                ? (
                    Self.sanitizedText(nextWorkout)
                        .map(HomeAssistantJSONValue.string)
                    ?? .null
                )
                : .null

        await sendReliably(
            event: "sync_snapshot",
            payload: [
                "state": .object(state)
            ]
        )
    }

    func clearDisabledValues() async {
        guard isConnected else {
            return
        }

        var state: [String: HomeAssistantJSONValue] = [:]

        if !shareWorkoutState {
            state["workout_active"] = .bool(false)
            state["active_workout"] = .null
        }
        if !shareCompletedWorkouts {
            state["last_workout"] = .null
        }
        if !shareRecovery {
            state["recovery_score"] = .null
        }
        if !shareTrainingLoad {
            state["training_load"] = .null
        }
        if !shareWeeklyProgress {
            state["weekly_progress"] = .null
        }
        if !shareNextWorkout {
            state["next_workout"] = .null
        }

        guard !state.isEmpty else {
            return
        }

        await sendReliably(
            event: "sync_snapshot",
            payload: [
                "state": .object(state)
            ]
        )
    }

    private func beginAuthorization(
        baseURL: URL,
        instanceName: String
    ) {
        guard isOAuthClientConfigured else {
            let message = ATHLTHLocalization.choose(
                english:
                    "Home Assistant OAuth client metadata is not configured in this build yet.",
                norwegian:
                    "OAuth-klientmetadata for Home Assistant er ikke konfigurert i denne versjonen ennå."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        guard webAuthenticationSession == nil,
              let callbackScheme = URL(string: redirectURI)?.scheme
        else {
            return
        }

        stopDiscovery()
        lastErrorMessage = nil
        connectionState = .authorizing

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        guard let authorizationURL = Self.authorizationURL(
            baseURL: baseURL,
            clientID: oauthClientID,
            redirectURI: redirectURI,
            state: state,
            challenge: challenge
        ) else {
            let message = ATHLTHLocalization.choose(
                english: "Could not prepare Home Assistant sign-in.",
                norwegian:
                    "Kunne ikke klargjøre innlogging til Home Assistant."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        let authSession = ASWebAuthenticationSession(
            url: authorizationURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                await self?.completeAuthorization(
                    callbackURL: callbackURL,
                    error: error,
                    baseURL: baseURL,
                    instanceName: instanceName,
                    verifier: verifier,
                    expectedState: state
                )
            }
        }

        authSession.presentationContextProvider = self
        authSession.prefersEphemeralWebBrowserSession = false
        webAuthenticationSession = authSession

        if !authSession.start() {
            webAuthenticationSession = nil
            let message = ATHLTHLocalization.choose(
                english: "Could not open Home Assistant sign-in.",
                norwegian:
                    "Kunne ikke åpne innlogging til Home Assistant."
            )
            lastErrorMessage = message
            connectionState = .error(message)
        }
    }

    private func completeAuthorization(
        callbackURL: URL?,
        error: Error?,
        baseURL: URL,
        instanceName: String,
        verifier: String,
        expectedState: String
    ) async {
        defer {
            webAuthenticationSession = nil
        }

        if let error {
            let nsError = error as NSError
            if nsError.domain ==
                ASWebAuthenticationSessionError.errorDomain,
               nsError.code ==
                ASWebAuthenticationSessionError
                    .canceledLogin.rawValue {
                connectionState = .disconnected
                lastErrorMessage = nil
            } else {
                lastErrorMessage = error.localizedDescription
                connectionState = .error(
                    error.localizedDescription
                )
            }
            return
        }

        guard let callbackURL,
              Self.callbackMatches(
                callbackURL,
                redirectURI: redirectURI
              ),
              let components = URLComponents(
                url: callbackURL,
                resolvingAgainstBaseURL: false
              )
        else {
            let message = ATHLTHLocalization.choose(
                english:
                    "Home Assistant returned an unexpected callback.",
                norwegian:
                    "Home Assistant returnerte en uventet callback."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        let values = Dictionary(
            uniqueKeysWithValues:
                (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
        )

        if let authError = values["error"], !authError.isEmpty {
            lastErrorMessage = authError
            connectionState = .error(authError)
            return
        }

        guard values["state"] == expectedState,
              let code = values["code"],
              !code.isEmpty
        else {
            let message = ATHLTHLocalization.choose(
                english:
                    "Home Assistant sign-in could not be verified.",
                norwegian:
                    "Innloggingen til Home Assistant kunne ikke verifiseres."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        do {
            let token = try await exchangeAuthorizationCode(
                code,
                verifier: verifier,
                baseURL: baseURL
            )

            do {
                connectionState = .pairing

                let pairResponse = try await requestPairing(
                    accessToken: token.accessToken,
                    baseURL: baseURL
                )

                try Self.validatePairResponse(
                    pairResponse
                )

                let pairing = HomeAssistantStoredPairing(
                    instanceName: instanceName,
                    instanceURL: baseURL,
                    protocolVersion: pairResponse.protocolVersion,
                    clientID: pairResponse.clientID,
                    webhookID: pairResponse.webhookID,
                    webhookURL: pairResponse.webhookURL,
                    webhookPath: pairResponse.webhookPath,
                    sharedSecret: pairResponse.sharedSecret,
                    signatureAlgorithm:
                        pairResponse.signatureAlgorithm,
                    capabilities: pairResponse.capabilities,
                    pairedAt: Date()
                )

                try storePairing(pairing)
                storedPairing = pairing
                connectedInstanceName = instanceName
                connectedInstanceURL = baseURL
                lastErrorMessage = nil
                connectionState = .connected

                await sendReliably(
                    event: "sync_snapshot",
                    payload: [
                        "state": .object([
                            "workout_active": .bool(false),
                            "active_workout": .null
                        ])
                    ]
                )
            } catch {
                if let refreshToken = token.refreshToken {
                    await revoke(
                        refreshToken: refreshToken,
                        baseURL: baseURL
                    )
                }
                throw error
            }

            if let refreshToken = token.refreshToken {
                await revoke(
                    refreshToken: refreshToken,
                    baseURL: baseURL
                )
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionState = .error(error.localizedDescription)
        }
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        verifier: String,
        baseURL: URL
    ) async throws -> HomeAssistantOAuthTokenResponse {
        let endpoint = baseURL.appending(
            path: "auth/token",
            directoryHint: .notDirectory
        )

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formEncodedBody([
            URLQueryItem(
                name: "grant_type",
                value: "authorization_code"
            ),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: oauthClientID),
            URLQueryItem(
                name: "code_verifier",
                value: verifier
            )
        ])

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw HomeAssistantConnectionError.authorizationFailed(
                Self.errorMessage(from: data)
            )
        }

        return try JSONDecoder().decode(
            HomeAssistantOAuthTokenResponse.self,
            from: data
        )
    }

    private func requestPairing(
        accessToken: String,
        baseURL: URL
    ) async throws -> HomeAssistantPairResponse {
        let endpoint = baseURL.appending(
            path: "api/athlth/pair",
            directoryHint: .notDirectory
        )

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "no-store",
            forHTTPHeaderField: "Cache-Control"
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HomeAssistantConnectionError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw HomeAssistantConnectionError.integrationMissing
            }
            if httpResponse.statusCode == 401 ||
                httpResponse.statusCode == 403 {
                throw HomeAssistantConnectionError.adminRequired
            }
            throw HomeAssistantConnectionError.pairingFailed(
                Self.errorMessage(from: data)
            )
        }

        return try JSONDecoder().decode(
            HomeAssistantPairResponse.self,
            from: data
        )
    }

    private func revoke(
        refreshToken: String,
        baseURL: URL
    ) async {
        let endpoint = baseURL.appending(
            path: "auth/revoke",
            directoryHint: .notDirectory
        )

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formEncodedBody([
            URLQueryItem(name: "token", value: refreshToken)
        ])

        _ = try? await URLSession.shared.data(for: request)
    }

    private func storePairing(
        _ pairing: HomeAssistantStoredPairing
    ) throws {
        let data = try JSONEncoder().encode(pairing)

        guard Self.writeSecureData(
            data,
            service: keychainService,
            account: keychainAccount
        ) else {
            throw HomeAssistantConnectionError
                .secureStorageFailed
        }
    }

    private func configuredInfoValue(_ key: String) -> String {
        let value =
            (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !value.isEmpty,
              !value.contains("$(")
        else {
            return ""
        }

        return value
    }

    private static func readPendingDeliveries(
        service: String,
        account: String
    ) -> [HomeAssistantPendingDelivery] {
        guard let data = readSecureData(
            service: service,
            account: account
        ) else {
            return []
        }

        return (
            try? JSONDecoder().decode(
                [HomeAssistantPendingDelivery].self,
                from: data
            )
        ) ?? []
    }

    private static func filteredPendingDeliveries(
        _ deliveries:
            [HomeAssistantPendingDelivery],
        pairingWebhookID: String?
    ) -> [HomeAssistantPendingDelivery] {
        guard let pairingWebhookID else {
            return []
        }

        let cutoff =
            Date().addingTimeInterval(
                -pendingDeliveryMaxAge
            )

        return deliveries
            .filter {
                $0.pairingWebhookID ==
                    pairingWebhookID &&
                $0.createdAt >= cutoff
            }
            .sorted {
                $0.createdAt < $1.createdAt
            }
            .suffix(maxPendingDeliveries)
            .map { $0 }
    }

    private static func readSecureData(
        service: String,
        account: String
    ) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String:
                service,
            kSecAttrAccount as String:
                account,
            kSecReturnData as String: true,
            kSecMatchLimit as String:
                kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(
            query as CFDictionary,
            &item
        ) == errSecSuccess
        else {
            return nil
        }

        return item as? Data
    }

    private static func writeSecureData(
        _ data: Data,
        service: String,
        account: String
    ) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String:
                service,
            kSecAttrAccount as String:
                account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String:
                data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if status == errSecItemNotFound {
            var item = query
            attributes.forEach {
                item[$0.key] =
                    $0.value
            }

            return SecItemAdd(
                item as CFDictionary,
                nil
            ) == errSecSuccess
        }

        return status == errSecSuccess
    }

    private static func deleteSecureItem(
        service: String,
        account: String
    ) {
        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String:
                service,
            kSecAttrAccount as String:
                account
        ]
        SecItemDelete(
            query as CFDictionary
        )
    }

    private static func readStoredPairing(
        service: String,
        account: String
    ) -> HomeAssistantStoredPairing? {
        guard let data = readSecureData(
            service: service,
            account: account
        ) else {
            return nil
        }

        return try? JSONDecoder().decode(
            HomeAssistantStoredPairing.self,
            from: data
        )
    }

    private static func deleteStoredPairing(
        service: String,
        account: String
    ) {
        deleteSecureItem(
            service: service,
            account: account
        )
    }

    nonisolated private static func instance(
        from result: NWBrowser.Result
    ) -> HomeAssistantDiscoveredInstance? {
        guard case .bonjour(let txtRecord) = result.metadata
        else {
            return nil
        }

        let properties = txtRecord.dictionary
        let name =
            Self.nonEmpty(properties["location_name"])
            ?? Self.serviceName(from: result.endpoint)
            ?? "Home Assistant"
        let identifier =
            Self.nonEmpty(properties["uuid"])
            ?? name
        let internalURL = Self.url(
            from: properties["internal_url"]
        )
        let externalURL = Self.url(
            from: properties["external_url"]
        )
        let version = Self.nonEmpty(properties["version"])

        return HomeAssistantDiscoveredInstance(
            id: identifier,
            name: name,
            internalURL: internalURL,
            externalURL: externalURL,
            version: version
        )
    }

    nonisolated private static func serviceName(
        from endpoint: NWEndpoint
    ) -> String? {
        guard case let .service(name, _, _, _) = endpoint
        else {
            return nil
        }
        return nonEmpty(name)
    }

    nonisolated private static func url(from raw: String?) -> URL? {
        guard let raw = nonEmpty(raw),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return nil
        }
        return url
    }

    private static func normalizedBaseURL(
        from raw: String
    ) -> URL? {
        var value = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else {
            return nil
        }

        if !value.contains("://") {
            let lower = value.lowercased()
            let looksLocal =
                lower.contains(".local") ||
                lower.hasPrefix("localhost") ||
                lower.range(
                    of: #"^\d{1,3}(\.\d{1,3}){3}(:\d+)?$"#,
                    options: .regularExpression
                ) != nil

            value = (looksLocal ? "http://" : "https://") + value
        }

        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil
        else {
            return nil
        }

        components.fragment = nil
        components.query = nil

        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }

    private static func authorizationURL(
        baseURL: URL,
        clientID: String,
        redirectURI: String,
        state: String,
        challenge: String
    ) -> URL? {
        let endpoint = baseURL.appending(
            path: "auth/authorize",
            directoryHint: .notDirectory
        )
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(
                name: "response_type",
                value: "code"
            ),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(
                name: "redirect_uri",
                value: redirectURI
            ),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(
                name: "code_challenge_method",
                value: "S256"
            ),
            URLQueryItem(
                name: "code_challenge",
                value: challenge
            )
        ]
        return components.url
    }

    private static func callbackMatches(
        _ callbackURL: URL,
        redirectURI: String
    ) -> Bool {
        guard let expected = URL(string: redirectURI) else {
            return false
        }

        return callbackURL.scheme?.lowercased() ==
            expected.scheme?.lowercased()
            && callbackURL.host?.lowercased() ==
                expected.host?.lowercased()
            && callbackURL.path == expected.path
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        )

        if status == errSecSuccess {
            return Data(bytes).base64URLEncodedString()
        }

        return UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            + UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
    }

    private static func codeChallenge(
        for verifier: String
    ) -> String {
        let data = Data(verifier.utf8)
        return Data(SHA256.hash(data: data))
            .base64URLEncodedString()
    }

    private static func signature(
        secret: String,
        timestamp: String,
        nonce: String,
        body: Data
    ) -> String {
        var signedData = Data(
            "\(timestamp).\(nonce).".utf8
        )
        signedData.append(body)

        let key = SymmetricKey(data: Data(secret.utf8))
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: signedData,
            using: key
        )

        return authenticationCode.map {
            String(format: "%02x", $0)
        }
        .joined()
    }

    private static func formEncodedBody(
        _ items: [URLQueryItem]
    ) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?.data(
            using: .utf8
        )
    }

    private static func sendWebhookRequest(
        to url: URL,
        body: Data,
        timestamp: String,
        nonce: String,
        signature: String
    ) async throws -> Int {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            timestamp,
            forHTTPHeaderField: "X-ATHLTH-Timestamp"
        )
        request.setValue(
            nonce,
            forHTTPHeaderField: "X-ATHLTH-Nonce"
        )
        request.setValue(
            "sha256=\(signature)",
            forHTTPHeaderField: "X-ATHLTH-Signature"
        )

        let (_, response) =
            try await URLSession.shared.data(
                for: request
            )

        guard let httpResponse =
                response as? HTTPURLResponse
        else {
            throw HomeAssistantConnectionError
                .invalidResponse
        }

        return httpResponse.statusCode
    }

    private static func webhookError(
        for statusCode: Int
    ) -> HomeAssistantConnectionError {
        if statusCode == 408 ||
            statusCode == 429 ||
            statusCode >= 500 {
            return .webhookUnavailable
        }

        return .webhookRejected
    }

    private static func shouldTryWebhookFallback(
        after statusCode: Int
    ) -> Bool {
        statusCode == 404 ||
            statusCode == 408 ||
            statusCode == 410 ||
            statusCode == 429 ||
            statusCode >= 500
    }

    private static func fallbackWebhookURL(
        for pairing: HomeAssistantStoredPairing
    ) -> URL? {
        guard var components = URLComponents(
            url: pairing.instanceURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        components.path = pairing.webhookPath
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func validatePairResponse(
        _ response: HomeAssistantPairResponse
    ) throws {
        guard response.protocolVersion == 1 else {
            throw HomeAssistantConnectionError.unsupportedProtocol(
                response.protocolVersion
            )
        }

        guard response.signatureAlgorithm
            .caseInsensitiveCompare("HMAC-SHA256") ==
                .orderedSame
        else {
            throw HomeAssistantConnectionError
                .unsupportedSignatureAlgorithm(
                    response.signatureAlgorithm
                )
        }

        guard !response.webhookID.isEmpty,
              !response.sharedSecret.isEmpty,
              response.sharedSecret.count >= 32,
              let scheme =
                response.webhookURL.scheme?
                    .lowercased(),
              scheme == "https" ||
                scheme == "http",
              response.webhookURL.host != nil,
              response.capabilities.contains(
                "sync_snapshot"
              ),
              response.capabilities.contains(
                "unpair"
              )
        else {
            throw HomeAssistantConnectionError.invalidPairingResponse
        }
    }

    private static func storedBool(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        guard defaults.object(
            forKey: key
        ) != nil else {
            return defaultValue
        }

        return defaults.bool(
            forKey: key
        )
    }

    private static func sanitizedText(
        _ value: String?
    ) -> String? {
        guard let value = value?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
              !value.isEmpty
        else {
            return nil
        }

        return String(value.prefix(200))
    }

    private static func iso8601(
        _ date: Date
    ) -> String {
        ISO8601DateFormatter()
            .string(from: date)
    }

    private static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(
                with: data
              ) as? [String: Any]
        else {
            return "Unknown Home Assistant error"
        }

        if let message = object["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let description =
            object["error_description"] as? String,
           !description.isEmpty {
            return description
        }

        if let error = object["error"] as? String,
           !error.isEmpty {
            return error
        }

        return "Unknown Home Assistant error"
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

extension HomeAssistantConnectionStore:
    ASWebAuthenticationPresentationContextProviding
{
    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }

            if let keyWindow = scenes
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) {
                return keyWindow
            }

            if let window = scenes.first?.windows.first {
                return window
            }

            return ASPresentationAnchor()
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum HomeAssistantConnectionError: LocalizedError {
    case notConnected
    case invalidResponse
    case authorizationFailed(String)
    case integrationMissing
    case adminRequired
    case pairingFailed(String)
    case unsupportedProtocol(Int)
    case unsupportedSignatureAlgorithm(String)
    case invalidPairingResponse
    case secureStorageFailed
    case webhookUnavailable
    case webhookRejected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return ATHLTHLocalization.choose(
                english: "Home Assistant is not connected.",
                norwegian: "Home Assistant er ikke tilkoblet."
            )
        case .invalidResponse:
            return ATHLTHLocalization.choose(
                english: "Home Assistant returned an invalid response.",
                norwegian:
                    "Home Assistant returnerte et ugyldig svar."
            )
        case .authorizationFailed(let message):
            return ATHLTHLocalization.choose(
                english:
                    "Home Assistant authorization failed: \(message)",
                norwegian:
                    "Godkjenning mot Home Assistant feilet: \(message)"
            )
        case .integrationMissing:
            return ATHLTHLocalization.choose(
                english:
                    "Install and add the ATHLTH integration in Home Assistant first.",
                norwegian:
                    "Installer og legg til ATHLTH-integrasjonen i Home Assistant først."
            )
        case .adminRequired:
            return ATHLTHLocalization.choose(
                english:
                    "An administrator must approve ATHLTH pairing in Home Assistant.",
                norwegian:
                    "En administrator må godkjenne ATHLTH-paringen i Home Assistant."
            )
        case .pairingFailed(let message):
            return ATHLTHLocalization.choose(
                english: "Pairing failed: \(message)",
                norwegian: "Paringen feilet: \(message)"
            )
        case .unsupportedProtocol(let version):
            return ATHLTHLocalization.choose(
                english:
                    "This Home Assistant integration uses unsupported ATHLTH protocol version \(version). Update ATHLTH and the Home Assistant integration.",
                norwegian:
                    "Home Assistant-integrasjonen bruker en ATHLTH-protokollversjon som ikke støttes (\(version)). Oppdater ATHLTH og Home Assistant-integrasjonen."
            )
        case .unsupportedSignatureAlgorithm(let algorithm):
            return ATHLTHLocalization.choose(
                english:
                    "Unsupported Home Assistant signing algorithm: \(algorithm).",
                norwegian:
                    "Home Assistant bruker en signeringsalgoritme som ikke støttes: \(algorithm)."
            )
        case .invalidPairingResponse:
            return ATHLTHLocalization.choose(
                english:
                    "Home Assistant returned incomplete or unsafe pairing information.",
                norwegian:
                    "Home Assistant returnerte ufullstendig eller usikker paringsinformasjon."
            )
        case .secureStorageFailed:
            return ATHLTHLocalization.choose(
                english:
                    "ATHLTH could not store the Home Assistant connection securely.",
                norwegian:
                    "ATHLTH kunne ikke lagre Home Assistant-tilkoblingen sikkert."
            )
        case .webhookUnavailable:
            return ATHLTHLocalization.choose(
                english:
                    "Home Assistant is temporarily unavailable. ATHLTH will retry important updates.",
                norwegian:
                    "Home Assistant er midlertidig utilgjengelig. ATHLTH prøver viktige oppdateringer på nytt."
            )
        case .webhookRejected:
            return ATHLTHLocalization.choose(
                english:
                    "Home Assistant rejected the signed webhook request.",
                norwegian:
                    "Home Assistant avviste den signerte webhook-forespørselen."
            )
        }
    }
}
