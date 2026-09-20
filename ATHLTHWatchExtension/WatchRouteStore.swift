import Combine
import Foundation
import WatchConnectivity

final class WatchRouteStore: NSObject, ObservableObject {
    @Published private(set) var routes: [WatchRouteTransfer] = []
    @Published private(set) var connectionText = "Connecting to iPhone"

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
                    ? "Connected to iPhone"
                    : "Connecting to iPhone"
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
