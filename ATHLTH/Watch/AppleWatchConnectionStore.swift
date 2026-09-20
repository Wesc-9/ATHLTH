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
            return "Connected"
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

    private let healthStore = HKHealthStore()

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
        refreshStatus()
    }

    func refreshStatus() {
        guard let session else {
            publish(.unsupported)
            return
        }

        session.delegate = self

        if session.activationState == .notActivated {
            publish(.checking)
            session.activate()
            return
        }

        evaluate(session)
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

    private func evaluate(_ session: WCSession) {
        #if os(iOS)
        if !session.isPaired {
            publish(.notPaired)
        } else if !session.isWatchAppInstalled {
            publish(.appNotInstalled)
        } else {
            publish(.ready)
        }
        #else
        publish(.unsupported)
        #endif
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
        if error != nil {
            evaluate(session)
            return
        }

        evaluate(session)
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
