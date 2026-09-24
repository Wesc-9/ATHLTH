import Combine
import Foundation
import WatchConnectivity

final class WatchRouteStore: NSObject, ObservableObject {
    @Published private(set) var routes: [WatchRouteTransfer] = []
    @Published private(set) var connectionText = "Connecting to iPhone"
    @Published private(set) var companionLinked = false

    private let fileManager = FileManager.default

    override init() {
        super.init()
        loadRoutes()
        activateConnectivity()
    }

    func route(with id: UUID) -> WatchRouteTransfer? {
        routes.first(where: { $0.id == id })
    }

    private func activateConnectivity() {
        guard WCSession.isSupported() else {
            connectionText = "WatchConnectivity unavailable"
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func connectivityAck(probeID: String) -> [String: Any] {
        [
            WatchTransferMetadataKey.kind: WatchTransferKind.connectivityAck.rawValue,
            WatchTransferMetadataKey.probeID: probeID,
            WatchTransferMetadataKey.sentAt: Date().timeIntervalSince1970
        ]
    }

    private func handleConnectivityProbe(
        _ payload: [String: Any],
        replyHandler: (([String: Any]) -> Void)? = nil
    ) -> Bool {
        guard
            payload[WatchTransferMetadataKey.kind] as? String
                == WatchTransferKind.connectivityProbe.rawValue
        else {
            return false
        }

        let probeID = payload[WatchTransferMetadataKey.probeID] as? String
            ?? UUID().uuidString
        let ack = connectivityAck(probeID: probeID)

        if let replyHandler {
            replyHandler(ack)
        } else if WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(ack)
        }

        DispatchQueue.main.async { [weak self] in
            self?.companionLinked = true
            self?.connectionText = "Connected to iPhone"
        }

        return true
    }

    private func announceWatchLaunchIfPossible(_ session: WCSession) {
        guard session.activationState == .activated else { return }

        session.transferUserInfo(
            connectivityAck(probeID: "watch-launch")
        )
    }

    private var storageURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTHWatchRoutes.json")
    }

    private func loadRoutes() {
        guard
            let url = storageURL,
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([WatchRouteTransfer].self, from: data)
        else {
            return
        }

        routes = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persistRoutes() {
        guard let url = storageURL else { return }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(routes)
            try data.write(to: url, options: .atomic)
        } catch {
            connectionText = "Couldn't save route"
        }
    }

    private func handleWorkoutConfiguration(
        _ payload: [String: Any]
    ) -> Bool {
        guard
            let rawKind =
                payload[WatchTransferMetadataKey.kind] as? String,
            let kind = WatchTransferKind(rawValue: rawKind),
            let data =
                payload[WatchTransferMetadataKey.payload] as? Data
        else {
            return false
        }

        switch kind {
        case .audioCoachConfiguration:
            guard let configuration = try? JSONDecoder().decode(
                WatchAudioCoachConfiguration.self,
                from: data
            ) else {
                return false
            }

            DispatchQueue.main.async {
                WatchWorkoutManager.shared
                    .configureAudioCoach(configuration)
            }
            return true

        case .runningWorkout:
            guard let workout = try? JSONDecoder().decode(
                WatchRunningWorkoutTransfer.self,
                from: data
            ) else {
                return false
            }

            DispatchQueue.main.async {
                WatchWorkoutManager.shared
                    .configureRunningWorkout(workout)
            }
            return true

        case .route,
             .workoutResult,
             .workoutCommand,
             .connectivityProbe,
             .connectivityAck:
            return false
        }
    }

    private func handleWorkoutCommand(_ payload: [String: Any]) {
        guard
            payload[WatchTransferMetadataKey.kind] as? String
                == WatchTransferKind.workoutCommand.rawValue,
            let rawCommand = payload[WatchTransferMetadataKey.command] as? String,
            let command = WatchWorkoutCommand(rawValue: rawCommand)
        else {
            return
        }

        DispatchQueue.main.async {
            switch command {
            case .end:
                WatchWorkoutManager.shared.end()
            case .pause:
                WatchWorkoutManager.shared.pause()
            case .resume:
                WatchWorkoutManager.shared.resume()
            }
        }
    }

    private func importRoute(from fileURL: URL) {
        do {
            let data = try Data(contentsOf: fileURL)
            let route = try JSONDecoder().decode(WatchRouteTransfer.self, from: data)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                if let index = self.routes.firstIndex(where: { $0.id == route.id }) {
                    self.routes[index] = route
                } else {
                    self.routes.insert(route, at: 0)
                }

                self.routes.sort { $0.updatedAt > $1.updatedAt }
                self.connectionText = "Route received"
                self.persistRoutes()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.connectionText = "Couldn't import route"
            }
        }
    }
}

extension WatchRouteStore: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            if let error {
                self?.connectionText = error.localizedDescription
            } else {
                self?.connectionText = activationState == .activated
                    ? "Ready for iPhone"
                    : "Connecting to iPhone"
                if activationState != .activated {
                    self?.companionLinked = false
                }
            }
        }

        if activationState == .activated {
            announceWatchLaunchIfPossible(session)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        if handleConnectivityProbe(message) {
            return
        }

        if handleWorkoutConfiguration(message) {
            return
        }

        handleWorkoutCommand(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if handleConnectivityProbe(message, replyHandler: replyHandler) {
            return
        }

        if handleWorkoutConfiguration(message) {
            replyHandler([:])
            return
        }

        handleWorkoutCommand(message)
        replyHandler([:])
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        if handleConnectivityProbe(userInfo) {
            return
        }

        if handleWorkoutConfiguration(userInfo) {
            return
        }

        handleWorkoutCommand(userInfo)
    }


    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            if session.isReachable {
                self?.companionLinked = true
                self?.connectionText = "Connected to iPhone"
            } else if session.activationState == .activated,
                      self?.companionLinked != true {
                self?.connectionText = "Ready for iPhone"
            }
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard
            file.metadata?[WatchTransferMetadataKey.kind] as? String
                == WatchTransferKind.route.rawValue
        else {
            return
        }

        importRoute(from: file.fileURL)
    }
}
