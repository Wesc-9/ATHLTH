import Combine
import Foundation
import HealthKit
import WatchConnectivity

enum AppleWatchConnectionState: Equatable {
    case checking
    case unsupported
    case notPaired
    case appNotInstalled
    case ready

    var isReady: Bool {
        self == .ready
    }

    var subtitle: String {
        switch self {
        case .checking:
            return "Checking Apple Watch"
        case .unsupported:
            return "Apple Watch connection is unavailable on this device"
        case .notPaired:
            return "No paired Apple Watch found"
        case .appNotInstalled:
            return "ATHLTH Watch app is not installed yet"
        case .ready:
            return "ATHLTH Watch app installed"
        }
    }
}

enum AppleWatchWorkoutLaunchError: LocalizedError {
    case watchUnavailable

    var errorDescription: String? {
        switch self {
        case .watchUnavailable:
            return "Apple Watch is not ready to start an ATHLTH workout."
        }
    }
}

final class AppleWatchConnectionStore: NSObject, ObservableObject {
    @Published private(set) var state: AppleWatchConnectionState = .checking
    @Published private(set) var lastCompletedWorkout: WatchWorkoutResult?
    @Published private(set) var workoutLaunchInProgress = false
    @Published private(set) var workoutLaunchError: String?

    // Diagnostics are intentionally separate from isReady. Apple's
    // isReachable only means the counterpart app is currently active;
    // it is not an installation check.
    @Published private(set) var paired: Bool?
    @Published private(set) var watchAppInstalled: Bool?
    @Published private(set) var reachable = false
    @Published private(set) var activationStateText = "Not activated"
    @Published private(set) var lastVerifiedAt: Date?
    @Published private(set) var verificationInProgress = false
    @Published private(set) var connectivityError: String?

    private let healthStore = HKHealthStore()
    private var verificationRequested = true
    private var lastProbeID: String?

    var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    override init() {
        super.init()
        // WatchConnectivity is activated only when Apple Watch is the
        // selected provider or the user explicitly opens Apple Watch setup.
        // This keeps Garmin and no-watch sessions independent of Watch state.
    }

    var isReady: Bool {
        state.isReady
    }

    var statusText: String {
        switch state {
        case .checking:
            return "Checking Apple Watch"
        case .unsupported:
            return "Apple Watch unavailable"
        case .notPaired:
            return "No paired Apple Watch"
        case .appNotInstalled:
            return "ATHLTH Watch app not installed"
        case .ready:
            if lastVerifiedAt != nil {
                return "ATHLTH Watch connection verified"
            }
            if reachable {
                return "ATHLTH Watch app installed · active now"
            }
            return "ATHLTH Watch app installed"
        }
    }

    func connect() {
        refreshStatus(requestVerification: true)
    }

    func refreshStatus() {
        refreshStatus(requestVerification: false)
    }

    private func refreshStatus(requestVerification: Bool) {
        if requestVerification {
            verificationRequested = true
        }

        guard let session else {
            publishSnapshot(
                state: .unsupported,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Unsupported"
            )
            return
        }

        // WCSession's pairing and installation properties are only valid
        // after successful activation. Never classify a Watch while the
        // session is inactive or still activating.
        session.delegate = self

        switch session.activationState {
        case .activated:
            evaluate(session)

        case .notActivated:
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Activating"
            )
            session.activate()

        case .inactive:
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Inactive"
            )

        @unknown default:
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Unknown"
            )
        }
    }

    @MainActor
    func startWorkoutOnWatch(_ kind: WatchWorkoutKind) async throws {
        guard isReady else {
            throw AppleWatchWorkoutLaunchError.watchUnavailable
        }

        workoutLaunchInProgress = true
        workoutLaunchError = nil
        defer { workoutLaunchInProgress = false }

        let configuration = HKWorkoutConfiguration()

        switch kind {
        case .running:
            configuration.activityType = .running
        case .walking:
            configuration.activityType = .walking
        case .strength:
            configuration.activityType = .traditionalStrengthTraining
        case .hiit:
            configuration.activityType = .highIntensityIntervalTraining
        case .functional:
            configuration.activityType = .functionalStrengthTraining
        case .cycling:
            configuration.activityType = .cycling
        case .rowing:
            configuration.activityType = .rowing
        case .stairClimbing:
            configuration.activityType = .stairClimbing
        case .yoga:
            configuration.activityType = .yoga
        case .other:
            configuration.activityType = .other
        }

        configuration.locationType = kind.usesOutdoorLocation
            ? .outdoor
            : .indoor

        do {
            try await healthStore.startWatchApp(toHandle: configuration)
        } catch {
            workoutLaunchError = error.localizedDescription
            throw error
        }
    }

    func clearCompletedWorkout() {
        DispatchQueue.main.async { [weak self] in
            self?.lastCompletedWorkout = nil
        }
    }

    func sendWorkoutCommand(_ command: WatchWorkoutCommand) {
        guard
            let session,
            session.activationState == .activated,
            state.isReady
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind: WatchTransferKind.workoutCommand.rawValue,
            WatchTransferMetadataKey.command: command.rawValue
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                DispatchQueue.main.async {
                    self?.workoutLaunchError = error.localizedDescription
                }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func evaluate(_ session: WCSession) {
        guard session.activationState == .activated else {
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Not activated"
            )
            return
        }

        #if os(iOS)
        let isPaired = session.isPaired
        let isInstalled = isPaired && session.isWatchAppInstalled
        let isReachable = session.isReachable

        let resolvedState: AppleWatchConnectionState
        if !isPaired {
            resolvedState = .notPaired
        } else if !isInstalled {
            resolvedState = .appNotInstalled
        } else {
            resolvedState = .ready
        }

        publishSnapshot(
            state: resolvedState,
            paired: isPaired,
            installed: isInstalled,
            reachable: isReachable,
            activation: "Activated"
        )

        if resolvedState == .ready, verificationRequested {
            verificationRequested = false
            sendConnectivityProbe(session)
        }
        #else
        publishSnapshot(
            state: .unsupported,
            paired: nil,
            installed: nil,
            reachable: false,
            activation: "Unsupported"
        )
        #endif
    }

    private func sendConnectivityProbe(_ session: WCSession) {
        guard
            session.activationState == .activated,
            session.isPaired,
            session.isWatchAppInstalled
        else {
            return
        }

        let probeID = UUID().uuidString
        lastProbeID = probeID

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind: WatchTransferKind.connectivityProbe.rawValue,
            WatchTransferMetadataKey.probeID: probeID,
            WatchTransferMetadataKey.sentAt: Date().timeIntervalSince1970
        ]

        DispatchQueue.main.async { [weak self] in
            self?.verificationInProgress = true
            self?.connectivityError = nil
        }

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: { [weak self] reply in
                    self?.handleConnectivityAck(reply)
                },
                errorHandler: { [weak self, weak session] error in
                    guard let self, let session else { return }

                    DispatchQueue.main.async {
                        self.connectivityError = error.localizedDescription
                    }

                    self.queueConnectivityProbe(payload, on: session)
                }
            )
        } else {
            queueConnectivityProbe(payload, on: session)
        }
    }

    private func queueConnectivityProbe(
        _ payload: [String: Any],
        on session: WCSession
    ) {
        guard session.activationState == .activated else { return }

        _ = session.transferUserInfo(payload)
    }

    private func handleConnectivityAck(_ payload: [String: Any]) {
        guard
            payload[WatchTransferMetadataKey.kind] as? String
                == WatchTransferKind.connectivityAck.rawValue
        else {
            return
        }

        let probeID = payload[WatchTransferMetadataKey.probeID] as? String

        // A launch acknowledgement from the Watch can arrive without matching
        // the most recent explicit probe. Either form proves that the paired
        // ATHLTH Watch app is alive and communicating.
        if let probeID,
           let lastProbeID,
           probeID != lastProbeID,
           probeID != "watch-launch" {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.lastVerifiedAt = Date()
            self?.verificationInProgress = false
            self?.connectivityError = nil
        }
    }

    private func publishSnapshot(
        state newState: AppleWatchConnectionState,
        paired: Bool?,
        installed: Bool?,
        reachable: Bool,
        activation: String
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = newState
            self.paired = paired
            self.watchAppInstalled = installed
            self.reachable = reachable
            self.activationStateText = activation

            if newState != .ready {
                self.verificationInProgress = false
            }
        }
    }

    private func receiveWorkoutResult(
        from userInfo: [String: Any]
    ) {
        guard
            userInfo[WatchTransferMetadataKey.kind] as? String
                == WatchTransferKind.workoutResult.rawValue,
            let data = userInfo[WatchTransferMetadataKey.payload] as? Data,
            let result = try? JSONDecoder().decode(
                WatchWorkoutResult.self,
                from: data
            )
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.lastCompletedWorkout = result
        }
    }

    private func receive(_ payload: [String: Any]) {
        if payload[WatchTransferMetadataKey.kind] as? String
            == WatchTransferKind.connectivityAck.rawValue {
            handleConnectivityAck(payload)
            return
        }

        receiveWorkoutResult(from: payload)
    }
}

extension AppleWatchConnectionStore: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async { [weak self] in
                self?.connectivityError = error.localizedDescription
            }
        }

        guard activationState == .activated else {
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Activation failed"
            )
            return
        }

        evaluate(session)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        receive(message)
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        receive(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        evaluate(session)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        publishSnapshot(
            state: .checking,
            paired: nil,
            installed: nil,
            reachable: false,
            activation: "Inactive"
        )
    }

    func sessionDidDeactivate(_ session: WCSession) {
        verificationRequested = true
        publishSnapshot(
            state: .checking,
            paired: nil,
            installed: nil,
            reachable: false,
            activation: "Reactivating"
        )
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        verificationRequested = true
        evaluate(session)
    }

    func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
    #endif
}
