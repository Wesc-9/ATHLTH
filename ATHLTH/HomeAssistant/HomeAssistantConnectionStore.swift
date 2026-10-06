import AuthenticationServices
import CryptoKit
import CoreLocation
import Foundation
import MapKit
import Network
import Security
import UserNotifications
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

enum HomeAssistantSyncMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case smart
    case live
    case efficient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart:
            return ATHLTHLocalization.choose(
                english: "Smart",
                norwegian: "Smart"
            )
        case .live:
            return ATHLTHLocalization.choose(
                english: "Live",
                norwegian: "Live"
            )
        case .efficient:
            return ATHLTHLocalization.choose(
                english: "Battery saver",
                norwegian: "Strømsparing"
            )
        }
    }

    var detail: String {
        switch self {
        case .smart:
            return ATHLTHLocalization.choose(
                english:
                    "Recommended. Important workout events are immediate, while routine health and planning updates are grouped to reduce background work.",
                norwegian:
                    "Anbefalt. Viktige treningshendelser sendes med en gang, mens vanlige helse- og planoppdateringer samles for å redusere bakgrunnsarbeid."
            )
        case .live:
            return ATHLTHLocalization.choose(
                english:
                    "Updates Home Assistant as quickly as practical. Uses more network and battery during active use.",
                norwegian:
                    "Oppdaterer Home Assistant så raskt som praktisk mulig. Bruker mer nettverk og batteri under aktiv bruk."
            )
        case .efficient:
            return ATHLTHLocalization.choose(
                english:
                    "Sends routine snapshots less often. Workout start/stop and milestones still remain immediate.",
                norwegian:
                    "Sender vanlige statusoppdateringer sjeldnere. Start/stopp av økt og milepæler sendes fortsatt med en gang."
            )
        }
    }

    var routineSnapshotMinimumInterval: TimeInterval {
        switch self {
        case .smart:
            return 30
        case .live:
            return 2
        case .efficient:
            return 5 * 60
        }
    }

    var coalescingDelay: TimeInterval {
        switch self {
        case .smart:
            return 1.5
        case .live:
            return 0.35
        case .efficient:
            return 3
        }
    }

    var liveWorkoutInterval: TimeInterval {
        switch self {
        case .smart:
            return 5
        case .live:
            return 2
        case .efficient:
            return 15
        }
    }

    var liveStrengthInterval: TimeInterval {
        switch self {
        case .smart:
            return 1
        case .live:
            return 0.5
        case .efficient:
            return 5
        }
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
    let alternateURL: URL?
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


struct HomeAssistantInboundCommand: Codable, Hashable, Identifiable {
    let id: String
    let type: String
    let title: String?
    let message: String?
    let data: [String: HomeAssistantJSONValue]?

    init(
        id: String,
        type: String,
        title: String? = nil,
        message: String? = nil,
        data: [String: HomeAssistantJSONValue]? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.data = data
    }
}

private struct HomeAssistantWebhookResponse: Decodable {
    let commands: [HomeAssistantInboundCommand]?
    let capabilities: [String]?
}

private struct HomeAssistantWebhookHTTPResult {
    let statusCode: Int
    let data: Data
}

extension Notification.Name {
    static let athlthHomeAssistantCommandReceived =
        Notification.Name(
            "athlth.homeAssistant.commandReceived"
        )
}

struct HomeAssistantCalendarEventPayload: Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let type: String
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

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }
}

func homeAssistantRecoveryStateValue(
    _ state: RecoveryReadinessState
) -> String {
    switch state {
    case .buildingBaseline:
        return "building_baseline"
    case .ready:
        return "ready"
    case .balanced:
        return "balanced"
    case .takeItEasy:
        return "take_it_easy"
    case .recover:
        return "recover"
    }
}

@MainActor
final class HomeAssistantConnectionStore: NSObject, ObservableObject {
    @Published private(set) var connectionState: HomeAssistantConnectionState
    @Published private(set) var discoveredInstances:
        [HomeAssistantDiscoveredInstance] = []
    @Published private(set) var connectedInstanceName: String?
    @Published private(set) var connectedInstanceURL: URL?
    @Published private(set) var connectedAlternateURL: URL? = nil
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastConnectionTestSucceeded = false
    @Published private(set) var lastLocalConnectionTestSucceeded: Bool? = nil
    @Published private(set) var lastAlternateConnectionTestSucceeded: Bool? = nil
    @Published private(set) var pendingDeliveryCount: Int = 0
    // Pairing belongs to one signed-in ATHLTH user, not the app session.
    // Temporarily losing auth must never erase Keychain credentials.
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var pairedAccountID: UUID?
    @Published var syncMode: HomeAssistantSyncMode {
        didSet {
            UserDefaults.standard.set(
                syncMode.rawValue,
                forKey: Self.syncModeKey
            )
        }
    }

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

    @Published var shareWorkoutRouteMap: Bool {
        didSet {
            UserDefaults.standard.set(
                shareWorkoutRouteMap,
                forKey: Self.shareWorkoutRouteMapKey
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

    @Published var shareSleep: Bool {
        didSet {
            UserDefaults.standard.set(
                shareSleep,
                forKey: Self.shareSleepKey
            )
        }
    }

    @Published var shareHRV: Bool {
        didSet {
            UserDefaults.standard.set(
                shareHRV,
                forKey: Self.shareHRVKey
            )
        }
    }

    @Published var shareRestingHeartRate: Bool {
        didSet {
            UserDefaults.standard.set(
                shareRestingHeartRate,
                forKey: Self.shareRestingHeartRateKey
            )
        }
    }

    @Published var shareRespiratoryRate: Bool {
        didSet {
            UserDefaults.standard.set(
                shareRespiratoryRate,
                forKey: Self.shareRespiratoryRateKey
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

    @Published var shareTrainingCalendar: Bool {
        didSet {
            UserDefaults.standard.set(
                shareTrainingCalendar,
                forKey:
                    Self.shareTrainingCalendarKey
            )
        }
    }

    @Published var shareGoals: Bool {
        didSet {
            UserDefaults.standard.set(
                shareGoals,
                forKey: Self.shareGoalsKey
            )
        }
    }

    @Published var shareLiveWorkoutDetails: Bool {
        didSet {
            UserDefaults.standard.set(
                shareLiveWorkoutDetails,
                forKey: Self.shareLiveWorkoutDetailsKey
            )
        }
    }

    @Published var shareStrengthDetails: Bool {
        didSet {
            UserDefaults.standard.set(
                shareStrengthDetails,
                forKey: Self.shareStrengthDetailsKey
            )
        }
    }

    @Published var shareMilestoneEvents: Bool {
        didSet {
            UserDefaults.standard.set(
                shareMilestoneEvents,
                forKey: Self.shareMilestoneEventsKey
            )
        }
    }

    private static let syncModeKey =
        "athlth.homeAssistant.syncMode"
    private static let shareWorkoutStateKey =
        "athlth.homeAssistant.shareWorkoutState"
    private static let shareCompletedWorkoutsKey =
        "athlth.homeAssistant.shareCompletedWorkouts"
    private static let shareWorkoutRouteMapKey =
        "athlth.homeAssistant.shareWorkoutRouteMap"
    private static let shareRecoveryKey =
        "athlth.homeAssistant.shareRecovery"
    private static let shareTrainingLoadKey =
        "athlth.homeAssistant.shareTrainingLoad"
    private static let shareSleepKey =
        "athlth.homeAssistant.shareSleep"
    private static let shareHRVKey =
        "athlth.homeAssistant.shareHRV"
    private static let shareRestingHeartRateKey =
        "athlth.homeAssistant.shareRestingHeartRate"
    private static let shareRespiratoryRateKey =
        "athlth.homeAssistant.shareRespiratoryRate"
    private static let shareWeeklyProgressKey =
        "athlth.homeAssistant.shareWeeklyProgress"
    private static let shareNextWorkoutKey =
        "athlth.homeAssistant.shareNextWorkout"
    private static let shareTrainingCalendarKey =
        "athlth.homeAssistant.shareTrainingCalendar"
    private static let shareGoalsKey =
        "athlth.homeAssistant.shareGoals"
    private static let shareLiveWorkoutDetailsKey =
        "athlth.homeAssistant.shareLiveWorkoutDetails"
    private static let shareStrengthDetailsKey =
        "athlth.homeAssistant.shareStrengthDetails"
    private static let shareMilestoneEventsKey =
        "athlth.homeAssistant.shareMilestoneEvents"
    private static let processedCommandIDsKey =
        "athlth.homeAssistant.processedCommandIDs"
    private static let pairingOwnerAccountKey =
        "athlth.homeAssistant.pairingOwnerAccountID"

    private let keychainService = "com.wesc9.athlth.home-assistant"
    private let keychainAccount = "pairing-v1"
    private let pendingDeliveryAccount = "pending-deliveries-v1"
    private let clientInstallationAccount = "client-installation-v1"
    private static let maxPendingDeliveries = 16
    private static let pendingDeliveryMaxAge: TimeInterval =
        7 * 24 * 60 * 60
    private let discoveryQueue = DispatchQueue(
        label: "com.wesc9.athlth.home-assistant.discovery",
        qos: .userInitiated
    )
    private let routeMonitor = NWPathMonitor()
    private let routeMonitorQueue = DispatchQueue(
        label: "com.wesc9.athlth.home-assistant.route-monitor",
        qos: .utility
    )

    private var browser: NWBrowser?
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private var storedPairing: HomeAssistantStoredPairing?
    private var pendingDeliveries: [HomeAssistantPendingDelivery]
    private var hasPersistedPendingDeliveries = false
    private var lastSnapshotState:
        [String: HomeAssistantJSONValue]?
    private var prefersLocalNetworkRoute = true

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
        guard storedPairing != nil,
              let activeAccountID
        else {
            return false
        }
        return pairedAccountID == nil ||
            pairedAccountID == activeAccountID
    }

    // This is deliberately non-destructive. Authentication restoration can
    // temporarily report signed-out following an app update or cold launch.
    // Only the explicit Disconnect action may revoke/delete the HA pairing.
    func setActiveAccount(_ userID: UUID?) {
        activeAccountID = userID

        // Keychain can be unavailable while protected data is locked at
        // startup. Retry restoring credentials after the account is ready.
        restorePairingIfNeeded()

        guard storedPairing != nil else {
            connectionState = .disconnected
            return
        }

        guard let userID else {
            connectionState = .disconnected
            return
        }

        if let pairedAccountID,
           pairedAccountID != userID {
            let message = ATHLTHLocalization.choose(
                english:
                    "Home Assistant is paired to a different ATHLTH account. Reconnect from this account to use it.",
                norwegian:
                    "Home Assistant er paret med en annen ATHLTH-konto. Koble til fra denne kontoen for å bruke integrasjonen."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        if pairedAccountID == nil {
            // Existing installations have no owner metadata. Bind once to
            // the account that first resumes the previously saved pairing.
            setPairingOwner(userID)
        }

        lastErrorMessage = nil
        connectionState = .connected
    }

    func restorePairingIfNeeded() {
        guard storedPairing == nil else { return }

        guard let restored = Self.readStoredPairing(
            service: keychainService,
            account: keychainAccount
        ) else {
            // Do not mutate either account pairing or the saved retry queue
            // when iOS Keychain isn't readable yet.
            return
        }

        storedPairing = restored
        connectedInstanceName = restored.instanceName
        connectedInstanceURL = restored.instanceURL
        connectedAlternateURL = restored.alternateURL

        let restoredPending = Self.readPendingDeliveries(
            service: keychainService,
            account: pendingDeliveryAccount
        )
        pendingDeliveries = Self.filteredPendingDeliveries(
            restoredPending,
            pairingWebhookID: restored.webhookID
        )
        hasPersistedPendingDeliveries =
            !restoredPending.isEmpty
        updatePendingDeliveryCountIfNeeded()
        if pendingDeliveries.count != restoredPending.count {
            persistPendingDeliveries()
        }
    }

    private func setPairingOwner(_ userID: UUID) {
        pairedAccountID = userID
        UserDefaults.standard.set(
            userID.uuidString,
            forKey: Self.pairingOwnerAccountKey
        )
    }

    var watchConfiguration: WatchHomeAssistantConfiguration {
        guard isConnected,
              shareWorkoutState,
              let pairing = storedPairing
        else {
            return .disabled
        }

        return WatchHomeAssistantConfiguration(
            enabled: true,
            clientID: pairing.clientID,
            webhookURL: pairing.webhookURL,
            fallbackWebhookURL:
                Self.alternateWebhookURL(
                    for: pairing
                ) ??
                Self.fallbackWebhookURL(
                    for: pairing
                ),
            sharedSecret: pairing.sharedSecret,
            updatedAt: Date()
        )
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
        pairedAccountID = defaults.string(
            forKey: Self.pairingOwnerAccountKey
        ).flatMap(UUID.init(uuidString:))
        let restored = Self.readStoredPairing(
            service: "com.wesc9.athlth.home-assistant",
            account: "pairing-v1"
        )
        let restoredPending =
            Self.readPendingDeliveries(
                service: "com.wesc9.athlth.home-assistant",
                account: "pending-deliveries-v1"
            )

        syncMode =
            HomeAssistantSyncMode(
                rawValue:
                    defaults.string(
                        forKey:
                            Self.syncModeKey
                    ) ?? ""
            ) ?? .smart
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
        shareWorkoutRouteMap = Self.storedBool(
            defaults,
            key: Self.shareWorkoutRouteMapKey,
            defaultValue: false
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
        shareSleep = Self.storedBool(
            defaults,
            key: Self.shareSleepKey,
            defaultValue: false
        )
        shareHRV = Self.storedBool(
            defaults,
            key: Self.shareHRVKey,
            defaultValue: false
        )
        shareRestingHeartRate = Self.storedBool(
            defaults,
            key: Self.shareRestingHeartRateKey,
            defaultValue: false
        )
        shareRespiratoryRate = Self.storedBool(
            defaults,
            key: Self.shareRespiratoryRateKey,
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
        shareTrainingCalendar = Self.storedBool(
            defaults,
            key: Self.shareTrainingCalendarKey,
            defaultValue: false
        )
        shareGoals = Self.storedBool(
            defaults,
            key: Self.shareGoalsKey,
            defaultValue: false
        )
        shareLiveWorkoutDetails = Self.storedBool(
            defaults,
            key: Self.shareLiveWorkoutDetailsKey,
            defaultValue: false
        )
        shareStrengthDetails = Self.storedBool(
            defaults,
            key: Self.shareStrengthDetailsKey,
            defaultValue: false
        )
        shareMilestoneEvents = Self.storedBool(
            defaults,
            key: Self.shareMilestoneEventsKey,
            defaultValue: false
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
        connectedAlternateURL = restored?.alternateURL
        connectionState = restored == nil ? .disconnected : .connected
        super.init()

        routeMonitor.pathUpdateHandler = {
            [weak self] path in
            let prefersLocal =
                path.usesInterfaceType(.wifi) ||
                path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor [weak self] in
                self?.prefersLocalNetworkRoute =
                    prefersLocal
            }
        }
        routeMonitor.start(
            queue: routeMonitorQueue
        )

        hasPersistedPendingDeliveries =
            !restoredPending.isEmpty
        updatePendingDeliveryCountIfNeeded()

        if restored != nil,
           pendingDeliveries.count != restoredPending.count {
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

    func pairLocally(
        to instance: HomeAssistantDiscoveredInstance,
        pairingCode: String
    ) {
        guard let baseURL = instance.preferredURL else {
            let message = ATHLTHLocalization.choose(
                english:
                    "Home Assistant was found, but it did not advertise a usable local URL.",
                norwegian:
                    "Home Assistant ble funnet, men annonserte ingen brukbar lokal adresse."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        Task {
            await completeLocalPairing(
                baseURL: baseURL,
                instanceName: instance.name,
                pairingCode: pairingCode,
                alternateURL:
                    instance.externalURL == baseURL
                    ? nil
                    : instance.externalURL
            )
        }
    }

    func pairLocallyManually(
        address: String,
        pairingCode: String
    ) {
        guard let baseURL =
                Self.normalizedBaseURL(
                    from: address
                )
        else {
            let message = ATHLTHLocalization.choose(
                english:
                    "Enter a valid Home Assistant address.",
                norwegian:
                    "Skriv inn en gyldig Home Assistant-adresse."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        Task {
            await completeLocalPairing(
                baseURL: baseURL,
                instanceName:
                    baseURL.host
                    ?? "Home Assistant",
                pairingCode: pairingCode
            )
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
            instanceName: instance.name,
            alternateURL:
                instance.externalURL == baseURL
                ? nil
                : instance.externalURL
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

    func configureAlternateAddress(
        _ address: String
    ) {
        guard let pairing = storedPairing else {
            return
        }

        let trimmed =
            address.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if trimmed.isEmpty {
            updateAlternateURL(
                nil,
                for: pairing
            )
            return
        }

        guard let alternateURL =
                Self.normalizedBaseURL(
                    from: trimmed
                )
        else {
            let message = ATHLTHLocalization.choose(
                english:
                    "Enter a valid VPN or external Home Assistant address.",
                norwegian:
                    "Skriv inn en gyldig VPN- eller ekstern Home Assistant-adresse."
            )
            lastErrorMessage = message
            connectionState = .error(message)
            return
        }

        updateAlternateURL(
            alternateURL,
            for: pairing
        )
    }

    func clearAlternateAddress() {
        guard let pairing = storedPairing else {
            return
        }

        updateAlternateURL(
            nil,
            for: pairing
        )
    }

    private func updateAlternateURL(
        _ alternateURL: URL?,
        for pairing: HomeAssistantStoredPairing
    ) {
        let updated =
            HomeAssistantStoredPairing(
                instanceName:
                    pairing.instanceName,
                instanceURL:
                    pairing.instanceURL,
                alternateURL:
                    alternateURL,
                protocolVersion:
                    pairing.protocolVersion,
                clientID:
                    pairing.clientID,
                webhookID:
                    pairing.webhookID,
                webhookURL:
                    pairing.webhookURL,
                webhookPath:
                    pairing.webhookPath,
                sharedSecret:
                    pairing.sharedSecret,
                signatureAlgorithm:
                    pairing.signatureAlgorithm,
                capabilities:
                    pairing.capabilities,
                pairedAt:
                    pairing.pairedAt
            )

        do {
            try storePairing(updated)
            storedPairing = updated
            connectedAlternateURL =
                alternateURL
            lastLocalConnectionTestSucceeded =
                nil
            lastAlternateConnectionTestSucceeded =
                nil
            lastConnectionTestSucceeded =
                false
            lastErrorMessage = nil
            connectionState = .connected
        } catch {
            lastErrorMessage =
                error.localizedDescription
            connectionState =
                .error(
                    error.localizedDescription
                )
        }
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
        pairedAccountID = nil
        UserDefaults.standard.removeObject(
            forKey: Self.pairingOwnerAccountKey
        )
        clearPendingDeliveries()
        storedPairing = nil
        connectedInstanceName = nil
        connectedInstanceURL = nil
        connectedAlternateURL = nil
        discoveredInstances = []
        lastErrorMessage = nil
        lastConnectionTestSucceeded = false
        lastLocalConnectionTestSucceeded = nil
        lastAlternateConnectionTestSucceeded = nil
        connectionState = .disconnected
        lastSnapshotState = nil
    }

    func send(
        event: String,
        payload: [String: HomeAssistantJSONValue] = [:]
    ) async throws {
        guard isConnected,
              let pairing = storedPairing else {
            throw HomeAssistantConnectionError.notConnected
        }

        let envelope = HomeAssistantWebhookEnvelope(
            event: event,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(envelope)

        let timestamp =
            String(
                Int(
                    Date()
                        .timeIntervalSince1970
                )
            )
        let nonce =
            UUID()
                .uuidString
                .lowercased()
        let signature = Self.signature(
            secret: pairing.sharedSecret,
            timestamp: timestamp,
            nonce: nonce,
            body: body
        )

        let candidates =
            webhookCandidates(
                for: pairing
            )
        guard !candidates.isEmpty else {
            throw HomeAssistantConnectionError
                .webhookUnavailable
        }

        let timeoutInterval:
            TimeInterval =
                candidates.count > 1
                ? 6
                : 15
        var lastFailure: Error =
            HomeAssistantConnectionError
                .webhookUnavailable

        for (
            index,
            url
        ) in candidates.enumerated() {
            do {
                let result =
                    try await Self
                        .sendWebhookRequest(
                            to: url,
                            body: body,
                            timestamp:
                                timestamp,
                            nonce: nonce,
                            signature:
                                signature,
                            clientID:
                                pairing.clientID,
                            timeoutInterval:
                                timeoutInterval
                        )

                if (200..<300)
                    .contains(
                        result.statusCode
                    ) ||
                    result.statusCode == 409 {
                    await handleWebhookResponse(
                        result.data,
                        sourceEvent: event
                    )
                    return
                }

                let requestError =
                    Self.webhookError(
                        for:
                            result.statusCode
                    )
                lastFailure =
                    requestError

                if !Self
                    .shouldTryWebhookFallback(
                        after:
                            result.statusCode
                    ) {
                    throw requestError
                }
            } catch let error as HomeAssistantConnectionError {
                if case .webhookRejected = error {
                    throw error
                }
                lastFailure = error
            } catch {
                lastFailure = error
            }

            if index ==
                candidates.index(
                    before:
                        candidates.endIndex
                ) {
                throw lastFailure
            }
        }

        throw lastFailure
    }

    private func handleWebhookResponse(
        _ data: Data,
        sourceEvent: String
    ) async {
        guard sourceEvent != "command_ack",
              let response =
                try? JSONDecoder().decode(
                    HomeAssistantWebhookResponse.self,
                    from: data
                )
        else {
            return
        }

        if let capabilities =
                response.capabilities,
           !capabilities.isEmpty {
            refreshStoredCapabilities(
                capabilities
            )
        }

        guard let commands =
                response.commands,
              !commands.isEmpty
        else {
            return
        }

        let defaults = UserDefaults.standard
        var processed = Set(
            defaults.stringArray(
                forKey:
                    Self.processedCommandIDsKey
            ) ?? []
        )

        let fresh = commands.filter {
            !processed.contains($0.id)
        }

        for command in fresh {
            processed.insert(command.id)

            switch command.type {
            case "notification",
                 "training_reminder",
                 "show_next_workout":
                await scheduleLocalNotification(
                    for: command
                )
            case "open_planned_workout":
                await scheduleLocalNotification(
                    for: command
                )
                NotificationCenter.default.post(
                    name:
                        .athlthHomeAssistantCommandReceived,
                    object: command
                )
            case "sync_now",
                 "schedule_extra_workout",
                 "move_planned_workout":
                NotificationCenter.default.post(
                    name:
                        .athlthHomeAssistantCommandReceived,
                    object: command
                )
            default:
                break
            }
        }

        let trimmed =
            Array(processed.suffix(64))
        defaults.set(
            trimmed,
            forKey:
                Self.processedCommandIDsKey
        )

        let ids = commands.map {
            HomeAssistantJSONValue.string(
                $0.id
            )
        }

        try? await send(
            event: "command_ack",
            payload: [
                "ids": .array(ids)
            ]
        )
    }

    private func refreshStoredCapabilities(
        _ capabilities: [String]
    ) {
        guard let pairing = storedPairing
        else {
            return
        }

        let normalized =
            Array(
                Set(capabilities)
            )
            .sorted()

        guard normalized !=
                pairing.capabilities
        else {
            return
        }

        let updated =
            HomeAssistantStoredPairing(
                instanceName:
                    pairing.instanceName,
                instanceURL:
                    pairing.instanceURL,
                alternateURL:
                    pairing.alternateURL,
                protocolVersion:
                    pairing.protocolVersion,
                clientID:
                    pairing.clientID,
                webhookID:
                    pairing.webhookID,
                webhookURL:
                    pairing.webhookURL,
                webhookPath:
                    pairing.webhookPath,
                sharedSecret:
                    pairing.sharedSecret,
                signatureAlgorithm:
                    pairing.signatureAlgorithm,
                capabilities:
                    normalized,
                pairedAt:
                    pairing.pairedAt
            )

        guard (try? storePairing(updated)) != nil
        else {
            return
        }

        storedPairing = updated
    }

    private func scheduleLocalNotification(
        for command: HomeAssistantInboundCommand
    ) async {
        let content =
            UNMutableNotificationContent()
        content.title =
            command.title ??
            ATHLTHLocalization.choose(
                english: "ATHLTH",
                norwegian: "ATHLTH"
            )
        content.body =
            command.message ??
            ATHLTHLocalization.choose(
                english:
                    "Home Assistant sent an ATHLTH update.",
                norwegian:
                    "Home Assistant sendte en ATHLTH-oppdatering."
            )
        content.sound = .default

        let request =
            UNNotificationRequest(
                identifier:
                    "athlth-home-assistant-\(command.id)",
                content: content,
                trigger: nil
            )

        try? await UNUserNotificationCenter
            .current()
            .add(request)
    }

    private func sendReliably(
        event: String,
        payload: [String: HomeAssistantJSONValue]
    ) async {
        guard let pairing = storedPairing else {
            return
        }

        if event == "sync_snapshot" {
            let pendingCountBefore =
                pendingDeliveries.count
            pendingDeliveries.removeAll {
                $0.pairingWebhookID ==
                    pairing.webhookID &&
                $0.event == "sync_snapshot"
            }
            if pendingDeliveries.count !=
                pendingCountBefore {
                persistPendingDeliveries()
            }
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

        guard !pendingDeliveries.isEmpty else {
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
        updatePendingDeliveryCountIfNeeded()
    }

    private func updatePendingDeliveryCountIfNeeded() {
        let newCount =
            pendingDeliveries.count
        guard pendingDeliveryCount !=
                newCount
        else {
            return
        }
        pendingDeliveryCount = newCount
    }

    private func persistPendingDeliveries() {
        updatePendingDeliveryCountIfNeeded()

        guard !pendingDeliveries.isEmpty else {
            guard hasPersistedPendingDeliveries
            else {
                return
            }

            Self.deleteSecureItem(
                service: keychainService,
                account:
                    pendingDeliveryAccount
            )
            hasPersistedPendingDeliveries =
                false
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
        hasPersistedPendingDeliveries =
            true
    }

    private func clearPendingDeliveries() {
        guard !pendingDeliveries.isEmpty ||
                hasPersistedPendingDeliveries
        else {
            return
        }

        pendingDeliveries.removeAll()
        updatePendingDeliveryCountIfNeeded()

        if hasPersistedPendingDeliveries {
            Self.deleteSecureItem(
                service: keychainService,
                account:
                    pendingDeliveryAccount
            )
            hasPersistedPendingDeliveries =
                false
        }
    }

    func syncBackgroundHealthSnapshot(
        workouts: [WorkoutSummary],
        sleep: SleepSummary,
        heart: HeartSummary,
        training: TrainingHealthSummary,
        recoveryScore: Int?,
        recoveryState: String?,
        trainingLoad: Double?
    ) async {
        guard isConnected else {
            return
        }

        await flushPendingDeliveries()

        var state:
            [String: HomeAssistantJSONValue] = [:]

        if shareCompletedWorkouts {
            let latestWorkout =
                workouts.max {
                    $0.startDate <
                        $1.startDate
                }

            state["last_workout"] =
                latestWorkout
                    .map {
                        .string(
                            $0.activity.rawValue
                        )
                    }
                ?? .null

            if let latestWorkout {
                state["last_workout_type"] =
                    .string(
                        latestWorkout.activity.rawValue
                    )
                state[
                    "last_workout_duration_seconds"
                ] = .double(
                    max(
                        latestWorkout.duration,
                        0
                    )
                )
                state[
                    "last_workout_distance_meters"
                ] =
                    latestWorkout.distanceMeters
                        .map {
                            .double(max($0, 0))
                        }
                    ?? .null
                state["last_workout_ended_at"] =
                    .string(
                        Self.iso8601(
                            latestWorkout.endDate
                        )
                    )
            }
        }

        state["recovery_score"] =
            shareRecovery &&
                recoveryScore != nil
                ? .int(
                    min(
                        max(
                            recoveryScore ?? 0,
                            0
                        ),
                        100
                    )
                )
                : .null

        state["recovery_state"] =
            shareRecovery
                ? (
                    Self.sanitizedText(
                        recoveryState
                    )
                        .map(
                            HomeAssistantJSONValue
                                .string
                        )
                    ?? .null
                )
                : .null

        state["training_load"] =
            shareTrainingLoad &&
                trainingLoad?.isFinite == true
                ? .double(
                    min(
                        max(
                            trainingLoad ?? 0,
                            0
                        ),
                        10
                    )
                )
                : .null

        state["pending_delivery_count"] =
            .int(pendingDeliveryCount)

        state["sleep_duration_minutes"] =
            shareSleep &&
                sleep.totalAsleep > 0
                ? .double(
                    min(
                        sleep.totalAsleep / 60,
                        1_440
                    )
                )
                : .null

        state["hrv_milliseconds"] =
            shareHRV &&
                heart.hrvMilliseconds?
                    .isFinite == true
                ? .double(
                    min(
                        max(
                            heart.hrvMilliseconds ?? 0,
                            0
                        ),
                        2_000
                    )
                )
                : .null

        state["resting_heart_rate"] =
            shareRestingHeartRate &&
                heart.restingHeartRate?
                    .isFinite == true
                ? .double(
                    min(
                        max(
                            heart.restingHeartRate ?? 20,
                            20
                        ),
                        250
                    )
                )
                : .null

        state["respiratory_rate"] =
            shareRespiratoryRate &&
                training.respiratoryRate?
                    .isFinite == true
                ? .double(
                    min(
                        max(
                            training.respiratoryRate ?? 1,
                            1
                        ),
                        80
                    )
                )
                : .null

        if shareWeeklyProgress {
            var calendar = Calendar.current
            calendar.firstWeekday = 2

            if let week =
                    calendar.dateInterval(
                        of: .weekOfYear,
                        for: Date()
                    ) {
                let current =
                    workouts.filter {
                        week.contains(
                            $0.startDate
                        )
                    }
                let seconds =
                    current.reduce(0.0) {
                        $0 +
                            max(
                                $1.duration,
                                0
                            )
                    }
                let meters =
                    current.reduce(0.0) {
                        $0 +
                            max(
                                $1.distanceMeters ??
                                    0,
                                0
                            )
                    }

                state[
                    "weekly_training_minutes"
                ] = .double(
                    min(
                        seconds / 60,
                        10_080
                    )
                )
                state[
                    "weekly_distance_km"
                ] = .double(
                    min(
                        meters / 1_000,
                        5_000
                    )
                )
            }
        }

        await sendReliably(
            event: "sync_snapshot",
            payload: [
                "state": .object(state)
            ]
        )
    }

    func sendConnectionTest() async {
        guard isConnected,
              let pairing = storedPairing else {
            return
        }

        lastConnectionTestSucceeded = false
        lastLocalConnectionTestSucceeded = nil
        lastAlternateConnectionTestSucceeded = nil

        let localURL =
            Self.fallbackWebhookURL(
                for: pairing
            )
        let alternateURL =
            Self.alternateWebhookURL(
                for: pairing
            )

        var anySucceeded = false

        if let localURL {
            let succeeded =
                await testWebhookRoute(
                    localURL,
                    pairing: pairing
                )
            lastLocalConnectionTestSucceeded =
                succeeded
            anySucceeded =
                anySucceeded || succeeded
        }

        if let alternateURL,
           alternateURL != localURL {
            let succeeded =
                await testWebhookRoute(
                    alternateURL,
                    pairing: pairing
                )
            lastAlternateConnectionTestSucceeded =
                succeeded
            anySucceeded =
                anySucceeded || succeeded
        }

        if pairing.webhookURL != localURL,
           pairing.webhookURL != alternateURL {
            let succeeded =
                await testWebhookRoute(
                    pairing.webhookURL,
                    pairing: pairing
                )
            anySucceeded =
                anySucceeded || succeeded
        }

        lastConnectionTestSucceeded =
            anySucceeded

        if anySucceeded {
            lastErrorMessage = nil
            connectionState = .connected
        } else {
            let message =
                ATHLTHLocalization.choose(
                    english:
                        "Could not reach Home Assistant through the configured connections.",
                    norwegian:
                        "Fikk ikke kontakt med Home Assistant via de konfigurerte tilkoblingene."
                )
            lastErrorMessage = message
            connectionState =
                .error(message)
        }
    }

    private func testWebhookRoute(
        _ url: URL,
        pairing: HomeAssistantStoredPairing
    ) async -> Bool {
        let envelope =
            HomeAssistantWebhookEnvelope(
                event: "sync_snapshot",
                payload: [
                    "state": .object([:])
                ]
            )
        let encoder = JSONEncoder()
        encoder.outputFormatting =
            [.sortedKeys]

        guard let body =
                try? encoder.encode(
                    envelope
                )
        else {
            return false
        }

        let timestamp =
            String(
                Int(
                    Date()
                        .timeIntervalSince1970
                )
            )
        let nonce =
            UUID()
                .uuidString
                .lowercased()
        let signature =
            Self.signature(
                secret:
                    pairing.sharedSecret,
                timestamp:
                    timestamp,
                nonce:
                    nonce,
                body:
                    body
            )

        guard let result =
                try? await Self
                    .sendWebhookRequest(
                        to: url,
                        body: body,
                        timestamp:
                            timestamp,
                        nonce:
                            nonce,
                        signature:
                            signature,
                        clientID:
                            pairing.clientID,
                        timeoutInterval:
                            5
                    )
        else {
            return false
        }

        return (200..<300)
            .contains(
                result.statusCode
            ) ||
            result.statusCode == 409
    }

    func enableAllSharing() {
        shareWorkoutState = true
        shareCompletedWorkouts = true
        shareWorkoutRouteMap = true
        shareRecovery = true
        shareTrainingLoad = true
        shareSleep = true
        shareHRV = true
        shareRestingHeartRate = true
        shareRespiratoryRate = true
        shareWeeklyProgress = true
        shareNextWorkout = true
        shareTrainingCalendar = true
        shareGoals = true
        shareLiveWorkoutDetails = true
        shareStrengthDetails = true
        shareMilestoneEvents = true
    }

    func sendWorkoutStarted(
        name: String?,
        startedAt: Date?,
        type: String? = nil,
        device: String = "iPhone"
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
        if let type = Self.sanitizedText(type) {
            payload["type"] = .string(type)
        }
        payload["device"] = .string(device)

        try? await send(
            event: "workout_started",
            payload: payload
        )
    }


    func sendWorkoutLiveUpdate(
        phase: String,
        name: String?,
        type: String?,
        elapsedSeconds: TimeInterval?,
        distanceMeters: Double?,
        paceSecondsPerKilometer: TimeInterval?,
        speedKilometersPerHour: Double?,
        heartRateBPM: Double? = nil,
        heartRateZone: Int? = nil,
        environment: String?,
        treadmillInclinePercent: Double?,
        device: String = "iPhone"
    ) async {
        guard isConnected,
              shareWorkoutState,
              shareLiveWorkoutDetails
        else {
            return
        }

        let allowedPhases = Set([
            "preparing",
            "warmup",
            "active",
            "rest",
            "cooldown",
            "paused",
            "finished"
        ])
        let resolvedPhase =
            allowedPhases.contains(phase)
                ? phase
                : "active"

        var state: [String: HomeAssistantJSONValue] = [
            "workout_phase": .string(resolvedPhase),
            "active_workout_device": .string(device)
        ]

        if let name = Self.sanitizedText(name) {
            state["active_workout"] = .string(name)
        }
        if let type = Self.sanitizedText(type) {
            state["active_workout_type"] = .string(type)
        }
        if let elapsedSeconds,
           elapsedSeconds.isFinite {
            state["active_workout_elapsed_seconds"] =
                .double(
                    min(
                        max(elapsedSeconds, 0),
                        604_800
                    )
                )
        }
        if let distanceMeters,
           distanceMeters.isFinite {
            state["active_workout_distance_meters"] =
                .double(
                    min(
                        max(distanceMeters, 0),
                        5_000_000
                    )
                )
        }
        if let paceSecondsPerKilometer,
           paceSecondsPerKilometer.isFinite {
            state["active_workout_pace_seconds_per_km"] =
                .double(
                    min(
                        max(
                            paceSecondsPerKilometer,
                            0
                        ),
                        7_200
                    )
                )
        }
        if let speedKilometersPerHour,
           speedKilometersPerHour.isFinite {
            state["active_workout_speed_kmh"] =
                .double(
                    min(
                        max(
                            speedKilometersPerHour,
                            0
                        ),
                        100
                    )
                )
        }
        if let heartRateBPM,
           heartRateBPM.isFinite {
            state["active_workout_heart_rate_bpm"] =
                .double(
                    min(
                        max(heartRateBPM, 20),
                        260
                    )
                )
        }
        if let heartRateZone {
            state["active_workout_heart_rate_zone"] =
                .int(
                    min(
                        max(heartRateZone, 1),
                        5
                    )
                )
        }
        if let environment =
                Self.sanitizedText(environment) {
            state["active_workout_environment"] =
                .string(environment)
        }
        if let treadmillInclinePercent,
           treadmillInclinePercent.isFinite {
            state["treadmill_incline_percent"] =
                .double(
                    min(
                        max(
                            treadmillInclinePercent,
                            -20
                        ),
                        40
                    )
                )
        }

        try? await send(
            event: "workout_updated",
            payload: [
                "phase": .string(resolvedPhase),
                "entity_state": .object(state)
            ]
        )
    }

    func sendStrengthSetUpdate(
        exercise: String,
        exerciseIndex: Int,
        setNumber: Int,
        setIndex: Int,
        setTotal: Int,
        reps: Int?,
        weightKilograms: Double?,
        resistanceLevel: Int?,
        restSeconds: Int?,
        rowDistanceMeters: Double?,
        completed: Bool
    ) async {
        guard isConnected,
              shareWorkoutState,
              shareStrengthDetails
        else {
            return
        }

        var payload: [String: HomeAssistantJSONValue] = [
            "current_exercise":
                .string(
                    Self.sanitizedText(exercise) ??
                    "Exercise"
                ),
            "current_exercise_index":
                .int(max(exerciseIndex, 0)),
            "current_set":
                .int(max(setNumber, 1)),
            "current_set_index":
                .int(max(setIndex, 0)),
            "current_set_total":
                .int(max(setTotal, 1))
        ]

        if let reps {
            payload["current_reps"] =
                .int(
                    min(
                        max(reps, 0),
                        10_000
                    )
                )
        }
        if let weightKilograms,
           weightKilograms.isFinite {
            payload["current_weight_kg"] =
                .double(
                    min(
                        max(weightKilograms, 0),
                        2_000
                    )
                )
        }
        if let resistanceLevel {
            payload["current_resistance_level"] =
                .int(
                    min(
                        max(resistanceLevel, 1),
                        10
                    )
                )
        }
        if let restSeconds {
            payload["current_rest_seconds"] =
                .int(
                    min(
                        max(restSeconds, 0),
                        7_200
                    )
                )
        }
        if let rowDistanceMeters,
           rowDistanceMeters.isFinite {
            payload["current_row_distance_meters"] =
                .double(
                    min(
                        max(rowDistanceMeters, 0),
                        1_000_000
                    )
                )
        }

        try? await send(
            event:
                completed
                    ? "strength_set_completed"
                    : "strength_set_updated",
            payload: payload
        )
    }

    func sendMilestoneEvent(
        event: String,
        title: String,
        detail: String? = nil,
        value: String? = nil
    ) async {
        guard isConnected,
              shareMilestoneEvents,
              [
                "personal_record",
                "achievement_unlocked",
                "goal_completed",
                "challenge_completed"
              ].contains(event)
        else {
            return
        }

        var payload: [String: HomeAssistantJSONValue] = [
            "title":
                .string(
                    Self.sanitizedText(title) ??
                    "ATHLTH"
                )
        ]
        if let detail =
                Self.sanitizedText(detail) {
            payload["detail"] = .string(detail)
        }
        if let value =
                Self.sanitizedText(value) {
            payload["value"] = .string(value)
        }

        await sendReliably(
            event: event,
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
        distanceMeters: Double?,
        activeEnergyKilocalories: Double? = nil,
        averageHeartRateBPM: Double? = nil,
        maxHeartRateBPM: Double? = nil,
        routeMatchPercent: Double? = nil,
        routeLocations: [CLLocation] = [],
        device: String = "iPhone"
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
                ),
                "device": .string(device)
            ]

            if let distanceMeters,
               distanceMeters.isFinite,
               distanceMeters >= 0 {
                payload["distance_meters"] = .double(
                    distanceMeters
                )

                if distanceMeters >= 100,
                   duration.isFinite,
                   duration > 0 {
                    payload["average_pace_seconds_per_km"] =
                        .double(
                            duration /
                            (
                                distanceMeters /
                                1_000
                            )
                        )
                }
            }

            if let activeEnergyKilocalories,
               activeEnergyKilocalories.isFinite,
               activeEnergyKilocalories >= 0 {
                payload["active_energy_kcal"] =
                    .double(
                        activeEnergyKilocalories
                    )
            }

            if let averageHeartRateBPM,
               averageHeartRateBPM.isFinite {
                payload["average_heart_rate_bpm"] =
                    .double(
                        min(
                            max(
                                averageHeartRateBPM,
                                20
                            ),
                            260
                        )
                    )
            }

            if let maxHeartRateBPM,
               maxHeartRateBPM.isFinite {
                payload["max_heart_rate_bpm"] =
                    .double(
                        min(
                            max(
                                maxHeartRateBPM,
                                20
                            ),
                            260
                        )
                    )
            }

            if let routeMatchPercent,
               routeMatchPercent.isFinite {
                payload["route_match_percent"] =
                    .double(
                        min(
                            max(
                                routeMatchPercent,
                                0
                            ),
                            100
                        )
                    )
            }

            await sendReliably(
                event: "workout_finished",
                payload: payload
            )

            if shareWorkoutRouteMap,
               routeLocations.count >= 2,
               storedPairing?
                    .capabilities
                    .contains(
                        "workout_route_map"
                    ) == true {
                await sendCompletedWorkoutRouteMap(
                    name: name,
                    type: type,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    duration: duration,
                    distanceMeters:
                        distanceMeters,
                    activeEnergyKilocalories:
                        activeEnergyKilocalories,
                    averageHeartRateBPM:
                        averageHeartRateBPM,
                    maxHeartRateBPM:
                        maxHeartRateBPM,
                    routeMatchPercent:
                        routeMatchPercent,
                    routeLocations:
                        routeLocations,
                    device: device
                )
            }

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

    private func sendCompletedWorkoutRouteMap(
        name: String,
        type: String,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double?,
        activeEnergyKilocalories: Double?,
        averageHeartRateBPM: Double?,
        maxHeartRateBPM: Double?,
        routeMatchPercent: Double?,
        routeLocations: [CLLocation],
        device: String
    ) async {
        let cleaned =
            routeLocations
                .filter {
                    CLLocationCoordinate2DIsValid(
                        $0.coordinate
                    ) &&
                    $0.horizontalAccuracy >= 0 &&
                    $0.horizontalAccuracy <= 150
                }
                .sorted {
                    $0.timestamp <
                    $1.timestamp
                }

        guard cleaned.count >= 2
        else {
            return
        }

        let sampled =
            Self.downsampleRoute(
                cleaned,
                maximumCount: 64
            )
        let routePoints =
            sampled.map {
                HomeAssistantJSONValue.array([
                    .double(
                        $0.coordinate.latitude
                    ),
                    .double(
                        $0.coordinate.longitude
                    )
                ])
            }

        var payload:
            [String: HomeAssistantJSONValue] = [
                "name":
                    .string(
                        Self.sanitizedText(name) ??
                        "Workout"
                    ),
                "type":
                    .string(
                        Self.sanitizedText(type) ??
                        "workout"
                    ),
                "started_at":
                    .string(
                        Self.iso8601(startedAt)
                    ),
                "ended_at":
                    .string(
                        Self.iso8601(endedAt)
                    ),
                "duration_seconds":
                    .double(
                        max(duration, 0)
                    ),
                "device":
                    .string(device),
                "route_points":
                    .array(routePoints),
                "route_point_count":
                    .int(cleaned.count),
                "elevation_gain_meters":
                    .double(
                        Self.elevationGain(
                            cleaned
                        )
                    )
            ]

        if let distanceMeters,
           distanceMeters.isFinite,
           distanceMeters >= 0 {
            payload["distance_meters"] =
                .double(
                    distanceMeters
                )

            if distanceMeters >= 100,
               duration.isFinite,
               duration > 0 {
                payload["average_pace_seconds_per_km"] =
                    .double(
                        duration /
                        (
                            distanceMeters /
                            1_000
                        )
                    )
            }
        }

        if let activeEnergyKilocalories,
           activeEnergyKilocalories.isFinite,
           activeEnergyKilocalories >= 0 {
            payload["active_energy_kcal"] =
                .double(
                    activeEnergyKilocalories
                )
        }

        if let averageHeartRateBPM,
           averageHeartRateBPM.isFinite {
            payload["average_heart_rate_bpm"] =
                .double(
                    averageHeartRateBPM
                )
        }

        if let maxHeartRateBPM,
           maxHeartRateBPM.isFinite {
            payload["max_heart_rate_bpm"] =
                .double(
                    maxHeartRateBPM
                )
        }

        if let routeMatchPercent,
           routeMatchPercent.isFinite {
            payload["route_match_percent"] =
                .double(
                    min(
                        max(
                            routeMatchPercent,
                            0
                        ),
                        100
                    )
                )
        }

        if let mapData =
                await Self.routeMapJPEG(
                    locations: sampled
                ) {
            payload["map_mime_type"] =
                .string("image/jpeg")
            payload["map_image_base64"] =
                .string(
                    mapData
                        .base64EncodedString()
                )
        }

        try? await send(
            event: "workout_route_map",
            payload: payload
        )
    }

    private static func downsampleRoute(
        _ locations: [CLLocation],
        maximumCount: Int
    ) -> [CLLocation] {
        guard locations.count >
                maximumCount,
              maximumCount >= 2
        else {
            return locations
        }

        let lastIndex =
            locations.count - 1

        return (0..<maximumCount)
            .map { index in
                let progress =
                    Double(index) /
                    Double(
                        maximumCount - 1
                    )
                let sourceIndex =
                    min(
                        Int(
                            (
                                progress *
                                Double(lastIndex)
                            )
                            .rounded()
                        ),
                        lastIndex
                    )
                return locations[
                    sourceIndex
                ]
            }
    }

    private static func elevationGain(
        _ locations: [CLLocation]
    ) -> Double {
        guard locations.count >= 2
        else {
            return 0
        }

        var gain = 0.0

        for index in
            1..<locations.count {
            let previous =
                locations[index - 1]
            let current =
                locations[index]

            guard previous.verticalAccuracy >= 0,
                  current.verticalAccuracy >= 0
            else {
                continue
            }

            let delta =
                current.altitude -
                previous.altitude

            if delta > 0,
               delta < 80 {
                gain += delta
            }
        }

        return gain
    }

    private static func routeMapJPEG(
        locations: [CLLocation]
    ) async -> Data? {
        guard locations.count >= 2
        else {
            return nil
        }

        let coordinates =
            locations.map(
                \.coordinate
            )
        let latitudes =
            coordinates.map(
                \.latitude
            )
        let longitudes =
            coordinates.map(
                \.longitude
            )

        guard let minLatitude =
                latitudes.min(),
              let maxLatitude =
                latitudes.max(),
              let minLongitude =
                longitudes.min(),
              let maxLongitude =
                longitudes.max()
        else {
            return nil
        }

        let center =
            CLLocationCoordinate2D(
                latitude:
                    (
                        minLatitude +
                        maxLatitude
                    ) / 2,
                longitude:
                    (
                        minLongitude +
                        maxLongitude
                    ) / 2
            )
        let options =
            MKMapSnapshotter.Options()
        options.size =
            CGSize(
                width: 520,
                height: 320
            )
        options.scale = 1
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter =
            .excludingAll
        options.region =
            MKCoordinateRegion(
                center: center,
                span:
                    MKCoordinateSpan(
                        latitudeDelta:
                            max(
                                (
                                    maxLatitude -
                                    minLatitude
                                ) * 1.32,
                                0.002
                            ),
                        longitudeDelta:
                            max(
                                (
                                    maxLongitude -
                                    minLongitude
                                ) * 1.32,
                                0.002
                            )
                    )
            )

        let snapshot:
            MKMapSnapshotter.Snapshot

        do {
            snapshot =
                try await withCheckedThrowingContinuation {
                    continuation in
                    MKMapSnapshotter(
                        options: options
                    )
                    .start {
                        snapshot,
                        error in

                        if let snapshot {
                            continuation
                                .resume(
                                    returning:
                                        snapshot
                                )
                        } else {
                            continuation
                                .resume(
                                    throwing:
                                        error ??
                                        HomeAssistantConnectionError
                                            .routeMapFailed
                                )
                        }
                    }
                }
        } catch {
            return nil
        }

        let renderer =
            UIGraphicsImageRenderer(
                size: options.size
            )
        let image =
            renderer.image {
                context in
                snapshot.image.draw(
                    at: .zero
                )

                let path =
                    UIBezierPath()
                for (
                    index,
                    coordinate
                ) in coordinates.enumerated() {
                    let point =
                        snapshot.point(
                            for: coordinate
                        )

                    if index == 0 {
                        path.move(
                            to: point
                        )
                    } else {
                        path.addLine(
                            to: point
                        )
                    }
                }

                context.cgContext
                    .setLineCap(.round)
                context.cgContext
                    .setLineJoin(.round)

                UIColor.white
                    .withAlphaComponent(
                        0.92
                    )
                    .setStroke()
                path.lineWidth = 8
                path.stroke()

                UIColor(
                    red: 0.10,
                    green: 0.48,
                    blue: 0.33,
                    alpha: 1
                )
                .setStroke()
                path.lineWidth = 5
                path.stroke()

                if let start =
                        coordinates.first {
                    let point =
                        snapshot.point(
                            for: start
                        )
                    UIColor(
                        red: 0.10,
                        green: 0.48,
                        blue: 0.33,
                        alpha: 1
                    )
                    .setFill()
                    UIBezierPath(
                        ovalIn:
                            CGRect(
                                x:
                                    point.x - 7,
                                y:
                                    point.y - 7,
                                width: 14,
                                height: 14
                            )
                    )
                    .fill()
                }

                if let finish =
                        coordinates.last {
                    let point =
                        snapshot.point(
                            for: finish
                        )
                    UIColor.black
                        .withAlphaComponent(
                            0.82
                        )
                        .setFill()
                    UIBezierPath(
                        ovalIn:
                            CGRect(
                                x:
                                    point.x - 7,
                                y:
                                    point.y - 7,
                                width: 14,
                                height: 14
                            )
                    )
                    .fill()
                }
            }

        return image.jpegData(
            compressionQuality: 0.58
        )
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
        activeWorkoutStartedAt: Date?,
        lastWorkout: String?,
        recoveryScore: Int?,
        trainingLoad: Double?,
        sleepDurationMinutes: Double?,
        hrvMilliseconds: Double?,
        restingHeartRate: Double?,
        respiratoryRate: Double?,
        recoveryState: String?,
        weeklyProgress: Double?,
        weeklyTrainingMinutes: Double?,
        weeklyDistanceKilometers: Double?,
        weeklyWorkoutCount: Int?,
        trainingStreak: Int?,
        nextWorkout: String?,
        nextWorkoutTime: Date?,
        activeGoal: String?,
        goalProgress: Double?,
        goalDaysRemaining: Int?,
        calendarEvents:
            [HomeAssistantCalendarEventPayload]
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
            state["active_workout_started_at"] =
                activeWorkoutStartedAt
                    .map {
                        .string(
                            Self.iso8601($0)
                        )
                    }
                ?? .null
            state["active_workout_device"] =
                .string("iPhone")
        } else {
            state["workout_active"] = .bool(false)
            state["active_workout"] = .null
            state["active_workout_started_at"] = .null
            state["active_workout_device"] = .null
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

        state["sleep_duration_minutes"] =
            shareSleep &&
                sleepDurationMinutes?.isFinite == true
                ? .double(
                    min(
                        max(sleepDurationMinutes ?? 0, 0),
                        1_440
                    )
                )
                : .null

        state["hrv_milliseconds"] =
            shareHRV &&
                hrvMilliseconds?.isFinite == true
                ? .double(
                    min(
                        max(hrvMilliseconds ?? 0, 0),
                        2_000
                    )
                )
                : .null

        state["resting_heart_rate"] =
            shareRestingHeartRate &&
                restingHeartRate?.isFinite == true
                ? .double(
                    min(
                        max(restingHeartRate ?? 20, 20),
                        250
                    )
                )
                : .null

        state["respiratory_rate"] =
            shareRespiratoryRate &&
                respiratoryRate?.isFinite == true
                ? .double(
                    min(
                        max(respiratoryRate ?? 1, 1),
                        80
                    )
                )
                : .null

        state["recovery_state"] =
            shareRecovery
                ? (
                    Self.sanitizedText(
                        recoveryState
                    )
                        .map(
                            HomeAssistantJSONValue
                                .string
                        )
                    ?? .null
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

        state["weekly_training_minutes"] =
            shareWeeklyProgress &&
                weeklyTrainingMinutes?.isFinite == true
                ? .double(
                    min(
                        max(weeklyTrainingMinutes ?? 0, 0),
                        10_080
                    )
                )
                : .null

        state["weekly_distance_km"] =
            shareWeeklyProgress &&
                weeklyDistanceKilometers?.isFinite == true
                ? .double(
                    min(
                        max(weeklyDistanceKilometers ?? 0, 0),
                        5_000
                    )
                )
                : .null

        state["weekly_workout_count"] =
            shareWeeklyProgress
                ? .int(
                    max(
                        weeklyWorkoutCount ?? 0,
                        0
                    )
                )
                : .null

        state["training_streak"] =
            shareWeeklyProgress
                ? .int(
                    max(
                        trainingStreak ?? 0,
                        0
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

        state["next_workout_time"] =
            shareNextWorkout
                ? (
                    nextWorkoutTime
                        .map {
                            .string(
                                Self.iso8601($0)
                            )
                        }
                    ?? .null
                )
                : .null

        state["active_goal"] =
            shareGoals
                ? (
                    Self.sanitizedText(
                        activeGoal
                    )
                        .map(
                            HomeAssistantJSONValue
                                .string
                        )
                    ?? .null
                )
                : .null

        state["goal_progress"] =
            shareGoals &&
                goalProgress?.isFinite == true
                ? .double(
                    min(
                        max(
                            goalProgress ?? 0,
                            0
                        ),
                        100
                    )
                )
                : .null

        state["goal_days_remaining"] =
            shareGoals
                ? goalDaysRemaining
                    .map {
                        .int(max($0, 0))
                    }
                ?? .null
                : .null

        state["calendar_events"] =
            shareTrainingCalendar
                ? .array(
                    calendarEvents
                        .prefix(64)
                        .map { event in
                            .object([
                                "id":
                                    .string(event.id),
                                "title":
                                    .string(
                                        Self.sanitizedText(
                                            event.title
                                        ) ??
                                        "Workout"
                                    ),
                                "start":
                                    .string(
                                        Self.iso8601(
                                            event.start
                                        )
                                    ),
                                "end":
                                    .string(
                                        Self.iso8601(
                                            event.end
                                        )
                                    ),
                                "type":
                                    .string(
                                        Self.sanitizedText(
                                            event.type
                                        ) ??
                                        "workout"
                                    )
                            ])
                        }
                )
                : .array([])

        state["pending_delivery_count"] =
            .int(pendingDeliveryCount)

        if pendingDeliveries.isEmpty,
           lastSnapshotState == state {
            return
        }

        await sendReliably(
            event: "sync_snapshot",
            payload: [
                "state": .object(state)
            ]
        )

        if pendingDeliveries.isEmpty {
            lastSnapshotState = state
        }
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
        if !shareLiveWorkoutDetails {
            for key in [
                "workout_phase",
                "active_workout_elapsed_seconds",
                "active_workout_distance_meters",
                "active_workout_pace_seconds_per_km",
                "active_workout_speed_kmh",
                "active_workout_heart_rate_bpm",
                "active_workout_heart_rate_zone",
                "active_workout_environment",
                "treadmill_incline_percent"
            ] {
                state[key] = .null
            }
        }
        if !shareStrengthDetails {
            for key in [
                "current_exercise",
                "current_exercise_index",
                "current_set",
                "current_set_index",
                "current_set_total",
                "current_reps",
                "current_weight_kg",
                "current_resistance_level",
                "current_rest_seconds",
                "current_row_distance_meters"
            ] {
                state[key] = .null
            }
        }
        if !shareCompletedWorkouts {
            state["last_workout"] = .null
        }
        if !shareRecovery {
            state["recovery_score"] = .null
            state["recovery_state"] = .null
        }
        if !shareTrainingLoad {
            state["training_load"] = .null
        }
        if !shareSleep {
            state["sleep_duration_minutes"] = .null
        }
        if !shareHRV {
            state["hrv_milliseconds"] = .null
        }
        if !shareRestingHeartRate {
            state["resting_heart_rate"] = .null
        }
        if !shareRespiratoryRate {
            state["respiratory_rate"] = .null
        }
        if !shareWeeklyProgress {
            state["weekly_progress"] = .null
            state["weekly_training_minutes"] = .null
            state["weekly_distance_km"] = .null
        }
        if !shareNextWorkout {
            state["next_workout"] = .null
            state["next_workout_time"] = .null
        }
        if !shareGoals {
            state["active_goal"] = .null
            state["goal_progress"] = .null
            state["goal_days_remaining"] = .null
        }
        if !shareTrainingCalendar {
            state["calendar_events"] = .array([])
        }

        if !shareWorkoutRouteMap,
           storedPairing?
                .capabilities
                .contains(
                    "workout_route_map"
                ) == true {
            try? await send(
                event: "workout_route_map",
                payload: [
                    "clear": .bool(true)
                ]
            )
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

    private func completeLocalPairing(
        baseURL: URL,
        instanceName: String,
        pairingCode: String,
        alternateURL: URL? = nil
    ) async {
        let normalizedCode =
            pairingCode.filter(\.isNumber)

        guard normalizedCode.count == 6 else {
            let message =
                HomeAssistantConnectionError
                    .invalidLocalPairingCode
                    .localizedDescription
            lastErrorMessage = message
            connectionState =
                .error(message)
            return
        }

        stopDiscovery()
        lastErrorMessage = nil
        connectionState = .pairing

        do {
            let response =
                try await requestLocalPairing(
                    pairingCode:
                        normalizedCode,
                    baseURL: baseURL
                )

            try Self.validatePairResponse(
                response
            )

            let pairing =
                HomeAssistantStoredPairing(
                    instanceName:
                        instanceName,
                    instanceURL:
                        baseURL,
                    alternateURL:
                        alternateURL,
                    protocolVersion:
                        response
                            .protocolVersion,
                    clientID:
                        response.clientID,
                    webhookID:
                        response.webhookID,
                    webhookURL:
                        response.webhookURL,
                    webhookPath:
                        response.webhookPath,
                    sharedSecret:
                        response.sharedSecret,
                    signatureAlgorithm:
                        response
                            .signatureAlgorithm,
                    capabilities:
                        response.capabilities,
                    pairedAt: Date()
                )

            try storePairing(pairing)
            storedPairing = pairing
            if let activeAccountID {
                setPairingOwner(activeAccountID)
            }
            connectedInstanceName =
                instanceName
            connectedInstanceURL =
                baseURL
            connectedAlternateURL =
                pairing.alternateURL
            lastErrorMessage = nil
            connectionState = .connected

            await sendReliably(
                event: "sync_snapshot",
                payload: [
                    "state": .object([
                        "workout_active":
                            .bool(false),
                        "active_workout":
                            .null
                    ])
                ]
            )
        } catch {
            lastErrorMessage =
                error.localizedDescription
            connectionState =
                .error(
                    error.localizedDescription
                )
        }
    }

    private func requestLocalPairing(
        pairingCode: String,
        baseURL: URL
    ) async throws
        -> HomeAssistantPairResponse {
        let endpoint =
            baseURL.appending(
                path:
                    "api/athlth/pair/local",
                directoryHint:
                    .notDirectory
            )

        var request =
            URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Accept"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            "no-store",
            forHTTPHeaderField:
                "Cache-Control"
        )
        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: [
                    "pairing_code":
                        pairingCode,
                    "client_id":
                        clientInstallationID(),
                    "client_name":
                        "ATHLTH iPhone"
                ]
            )

        let (data, response) =
            try await URLSession.shared
                .data(for: request)

        guard let httpResponse =
                response
                    as? HTTPURLResponse
        else {
            throw HomeAssistantConnectionError
                .invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder()
                .decode(
                    HomeAssistantPairResponse
                        .self,
                    from: data
                )
        case 401:
            throw HomeAssistantConnectionError
                .invalidLocalPairingCode
        case 403:
            throw HomeAssistantConnectionError
                .localNetworkPairingRequired
        case 404:
            throw HomeAssistantConnectionError
                .integrationMissing
        default:
            throw HomeAssistantConnectionError
                .pairingFailed(
                    Self.errorMessage(
                        from: data
                    )
                )
        }
    }

    private func beginAuthorization(
        baseURL: URL,
        instanceName: String,
        alternateURL: URL? = nil
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
                    alternateURL:
                        alternateURL,
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
        alternateURL: URL?,
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
                    alternateURL:
                        alternateURL,
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
                if let activeAccountID {
                    setPairingOwner(activeAccountID)
                }
                connectedInstanceName = instanceName
                connectedInstanceURL = baseURL
                connectedAlternateURL =
                    pairing.alternateURL
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
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "no-store",
            forHTTPHeaderField: "Cache-Control"
        )
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: [
                "client_id": clientInstallationID(),
                "client_name": "ATHLTH iPhone"
            ]
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

    private func clientInstallationID() -> String {
        if let data = Self.readSecureData(
            service: keychainService,
            account: clientInstallationAccount
        ),
           let value = String(
                data: data,
                encoding: .utf8
           ),
           !value.isEmpty {
            return value
        }

        let value =
            UUID()
                .uuidString
                .lowercased()

        if let data = value.data(
            using: .utf8
        ) {
            _ = Self.writeSecureData(
                data,
                service: keychainService,
                account: clientInstallationAccount
            )
        }

        return value
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
        signature: String,
        clientID: String,
        timeoutInterval: TimeInterval = 15
    ) async throws -> HomeAssistantWebhookHTTPResult {
        var request = URLRequest(url: url)
        request.timeoutInterval =
            timeoutInterval
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            clientID,
            forHTTPHeaderField: "X-ATHLTH-Client-ID"
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

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )

        guard let httpResponse =
                response as? HTTPURLResponse
        else {
            throw HomeAssistantConnectionError
                .invalidResponse
        }

        return HomeAssistantWebhookHTTPResult(
            statusCode:
                httpResponse.statusCode,
            data: data
        )
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

    private func webhookCandidates(
        for pairing: HomeAssistantStoredPairing
    ) -> [URL] {
        let local =
            Self.fallbackWebhookURL(
                for: pairing
            )
        let alternate =
            Self.alternateWebhookURL(
                for: pairing
            )

        let ordered:
            [URL?] =
                prefersLocalNetworkRoute
                ? [
                    local,
                    pairing.webhookURL,
                    alternate
                ]
                : [
                    alternate,
                    pairing.webhookURL,
                    local
                ]

        var seen = Set<String>()
        return ordered
            .compactMap { $0 }
            .filter {
                seen.insert(
                    $0.absoluteString
                )
                .inserted
            }
    }

    private static func fallbackWebhookURL(
        for pairing: HomeAssistantStoredPairing
    ) -> URL? {
        webhookURL(
            baseURL:
                pairing.instanceURL,
            path:
                pairing.webhookPath
        )
    }

    private static func alternateWebhookURL(
        for pairing: HomeAssistantStoredPairing
    ) -> URL? {
        guard let alternateURL =
                pairing.alternateURL
        else {
            return nil
        }

        return webhookURL(
            baseURL:
                alternateURL,
            path:
                pairing.webhookPath
        )
    }

    private static func webhookURL(
        baseURL: URL,
        path: String
    ) -> URL? {
        guard var components =
                URLComponents(
                    url: baseURL,
                    resolvingAgainstBaseURL:
                        false
                )
        else {
            return nil
        }

        components.path = path
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
    case invalidLocalPairingCode
    case localNetworkPairingRequired
    case adminRequired
    case pairingFailed(String)
    case unsupportedProtocol(Int)
    case unsupportedSignatureAlgorithm(String)
    case invalidPairingResponse
    case secureStorageFailed
    case webhookUnavailable
    case webhookRejected
    case routeMapFailed

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
        case .invalidLocalPairingCode:
            return ATHLTHLocalization.choose(
                english:
                    "The Home Assistant pairing code is invalid or has expired. Generate a new code in Home Assistant and try again.",
                norwegian:
                    "Paringskoden fra Home Assistant er ugyldig eller har utløpt. Generer en ny kode i Home Assistant og prøv igjen."
            )
        case .localNetworkPairingRequired:
            return ATHLTHLocalization.choose(
                english:
                    "Code pairing only works on the same local network as Home Assistant. Use Home Assistant sign-in as a fallback.",
                norwegian:
                    "Kodeparing fungerer bare på samme lokalnett som Home Assistant. Bruk Home Assistant-innlogging som reserve."
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
        case .routeMapFailed:
            return ATHLTHLocalization.choose(
                english: "ATHLTH could not create the workout route map.",
                norwegian: "ATHLTH kunne ikke lage kartet for treningsruten."
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
