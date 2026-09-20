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
            return "Checking Apple Watch…"
        case .unsupported:
            return "Apple Watch connection is unavailable on this device"
        case .notPaired:
            return "No paired Apple Watch found"
        case .appNotInstalled:
            return "Install ATHLTH on Apple Watch to continue"
        case .ready:
            return "ATHLTH is installed on Apple Watch"
        }
    }

    var actionTitle: String {
        switch self {
        case .checking:
            return "Checking…"
        case .unsupported:
            return "Help"
        case .notPaired:
            return "Help"
        case .appNotInstalled:
            return "Setup"
        case .ready:
            return "Check"
        }
    }

    var setupHelpMessage: String? {
        switch self {
        case .unsupported:
            return "Apple Watch connectivity is not available on this iPhone."
        case .notPaired:
            return "Pair your Apple Watch with this iPhone in the Watch app, then return to ATHLTH and try again."
        case .appNotInstalled:
            return "Open the Watch app on your iPhone, find ATHLTH under Available Apps, tap Install, then open ATHLTH once on Apple Watch and return here."
        case .checking, .ready:
            return nil
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
    @Published private(set) var connectionDetail: String?
    @Published private(set) var watchHealthAuthorizationInProgress = false
    @Published private(set) var watchHealthAuthorizationDetail: String?

    private let healthStore = HKHealthStore()
    private var verifyWhenActivated = false

    var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    override init() {
        super.init()
        refreshStatus()
    }

    var isReady: Bool {
        state.isReady
    }

    func connect() {
        connectionDetail = nil
        publish(.checking)
        refreshStatus(verifyLiveConnection: true)
    }

    func refreshStatus() {
        refreshStatus(verifyLiveConnection: false)
    }

    private func refreshStatus(verifyLiveConnection: Bool) {
        guard let session else {
            publish(.unsupported)
            return
        }

        session.delegate = self

        if session.activationState == .notActivated {
            verifyWhenActivated = verifyLiveConnection
            publish(.checking)
            session.activate()
            return
        }

        evaluate(
            session,
            verifyLiveConnection: verifyLiveConnection
        )
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
            configuration.locationType = .outdoor
        case .walking:
            configuration.activityType = .walking
            configuration.locationType = .outdoor
        case .strength:
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
        }

        do {
            try await healthStore.startWatchApp(toHandle: configuration)
        } catch {
            workoutLaunchError = error.localizedDescription
            throw error
        }
    }

    func requestWatchHealthAuthorization() {
        guard let session, state.isReady else {
            watchHealthAuthorizationDetail =
                "Apple Watch must be connected before Health access can be configured."
            return
        }

        guard session.isReachable else {
            watchHealthAuthorizationDetail =
                "Open ATHLTH on Apple Watch, then tap Configure Health again."
            return
        }

        watchHealthAuthorizationInProgress = true
        watchHealthAuthorizationDetail =
            "Check your Apple Watch for the Health permission sheet."

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.healthAuthorizationRequest.rawValue
        ]

        session.sendMessage(
            payload,
            replyHandler: { [weak self] reply in
                let status = reply[
                    WatchTransferMetadataKey.status
                ] as? String
                let remoteError = reply[
                    WatchTransferMetadataKey.error
                ] as? String

                DispatchQueue.main.async {
                    self?.watchHealthAuthorizationInProgress = false

                    if status == "authorized" {
                        self?.watchHealthAuthorizationDetail =
                            "Apple Watch Health setup completed."
                    } else {
                        self?.watchHealthAuthorizationDetail =
                            remoteError
                            ?? "Apple Watch Health setup could not be completed."
                    }
                }
            },
            errorHandler: { [weak self] error in
                DispatchQueue.main.async {
                    self?.watchHealthAuthorizationInProgress = false
                    self?.watchHealthAuthorizationDetail =
                        "Open ATHLTH on Apple Watch and try again. \(error.localizedDescription)"
                }
            }
        )
    }

    func clearCompletedWorkout() {
        DispatchQueue.main.async { [weak self] in
            self?.lastCompletedWorkout = nil
        }
    }

    func sendWorkoutCommand(_ command: WatchWorkoutCommand) {
        guard let session, state.isReady else { return }

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

    private func evaluate(
        _ session: WCSession,
        verifyLiveConnection: Bool = false
    ) {
        #if os(iOS)
        if !session.isPaired {
            publish(.notPaired)
            return
        }

        if !session.isWatchAppInstalled {
            publish(.appNotInstalled)
            return
        }

        publish(.ready)

        guard verifyLiveConnection else {
            connectionDetail = "ATHLTH Watch app is installed"
            return
        }

        verifyConnection(with: session)
        #else
        publish(.unsupported)
        #endif
    }

    private func verifyConnection(with session: WCSession) {
        guard session.isReachable else {
            DispatchQueue.main.async { [weak self] in
                self?.connectionDetail = "Installed · open ATHLTH on Apple Watch once to verify the live connection"
            }
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.connectionPing.rawValue
        ]

        session.sendMessage(
            payload,
            replyHandler: { [weak self] reply in
                let status = reply[
                    WatchTransferMetadataKey.status
                ] as? String

                DispatchQueue.main.async {
                    self?.connectionDetail = status == "ok"
                        ? "Connected to ATHLTH on Apple Watch"
                        : "ATHLTH Watch app responded"
                    self?.publish(.ready)
                }
            },
            errorHandler: { [weak self] error in
                DispatchQueue.main.async {
                    self?.connectionDetail =
                        "Installed · open ATHLTH on Apple Watch and try again"
                    self?.workoutLaunchError = error.localizedDescription
                }
            }
        )
    }

    private func publish(_ newState: AppleWatchConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
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
}

extension AppleWatchConnectionStore: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async { [weak self] in
                self?.connectionDetail = error.localizedDescription
            }
            verifyWhenActivated = false
            evaluate(session)
            return
        }

        let shouldVerify = verifyWhenActivated
        verifyWhenActivated = false
        evaluate(
            session,
            verifyLiveConnection: shouldVerify
        )
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        receiveWorkoutResult(from: userInfo)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        refreshStatus()
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        refreshStatus()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
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
