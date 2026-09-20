import Foundation
import WatchConnectivity

enum WatchRouteTransferError: LocalizedError {
    case watchUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .watchUnavailable:
            return "Apple Watch is not ready for ATHLTH route transfer."
        case .encodingFailed:
            return "ATHLTH couldn't prepare this route for Apple Watch."
        }
    }
}

extension TrainingRoute {
    var watchTransfer: WatchRouteTransfer {
        WatchRouteTransfer(
            id: id,
            title: title,
            distanceKilometers: distanceKilometers,
            elevationGainMeters: elevationGainMeters,
            points: coordinates.map {
                WatchRoutePoint(
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    altitude: $0.altitude,
                    sequence: $0.sequence
                )
            },
            updatedAt: Date()
        )
    }
}

extension AppleWatchConnectionStore {
    func sendRoute(_ route: TrainingRoute) throws {
        guard let session, state.isReady else {
            throw WatchRouteTransferError.watchUnavailable
        }

        let transfer = route.watchTransfer
        let data: Data

        do {
            data = try JSONEncoder().encode(transfer)
        } catch {
            throw WatchRouteTransferError.encodingFailed
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTHWatchTransfers", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileURL = directory
            .appendingPathComponent(transfer.id.uuidString)
            .appendingPathExtension("athlthroute")

        try data.write(to: fileURL, options: .atomic)

        session.transferFile(
            fileURL,
            metadata: [
                WatchTransferMetadataKey.kind: WatchTransferKind.route.rawValue,
                WatchTransferMetadataKey.routeID: transfer.id.uuidString,
                WatchTransferMetadataKey.title: transfer.title
            ]
        )
    }
}
