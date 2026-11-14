import Foundation
import MapKit
import SwiftUI
import UIKit

/// An offline route is a canonical GPS trace and, when possible, one static
/// map preview. Apple MapKit does not guarantee downloadable/offline basemap
/// tiles; tracing and route launch must work without those tiles.
@MainActor
final class ATHLTHDownloadedRouteStore: ObservableObject {
    @Published private(set) var downloadedIDs: Set<UUID> = []
    @Published private(set) var downloadingRouteID: UUID?
    @Published var errorMessage: String?

    private var accountID: UUID?

    func load(userID: UUID) {
        guard accountID != userID else { return }
        accountID = userID
        downloadedIDs = []
        errorMessage = nil
        guard let folder = try? root(userID) else { return }
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        downloadedIDs = Set(folders.compactMap { folder -> UUID? in
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  FileManager.default.fileExists(
                      atPath: folder.appendingPathComponent("route.json").path
                  ) else { return nil }
            return id
        })
    }

    func has(_ route: TrainingRoute) -> Bool {
        downloadedIDs.contains(route.id) ||
        route.sharedSourceRouteID.map(downloadedIDs.contains) == true
    }

    func remove(_ route: TrainingRoute) {
        guard let userID = accountID else { return }
        let id = downloadedIDs.contains(route.id)
            ? route.id : (route.sharedSourceRouteID ?? route.id)
        guard downloadedIDs.contains(id),
              let folder = try? root(userID)
        else { return }
        do {
            try FileManager.default.removeItem(
                at: folder.appendingPathComponent(id.uuidString, isDirectory: true)
            )
            downloadedIDs.remove(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func download(_ route: TrainingRoute, for userID: UUID) async -> Bool {
        load(userID: userID)
        guard downloadingRouteID == nil, route.coordinates.count >= 2 else {
            return false
        }
        downloadingRouteID = route.id
        errorMessage = nil
        defer { downloadingRouteID = nil }

        do {
            let rootURL = try root(userID)
            let destination = rootURL.appendingPathComponent(
                route.id.uuidString, isDirectory: true
            )
            let temporary = rootURL.appendingPathComponent(
                "incomplete-" + UUID().uuidString, isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: temporary, withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: temporary) }

            let data = try JSONEncoder().encode(route)
            try data.write(
                to: temporary.appendingPathComponent("route.json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )

            let size = CGSize(width: 900, height: 520)
            let identity = RouteMapSnapshotIdentity.key(
                route: route, size: size, scale: 1
            )
            if let image = await RouteMapSnapshotCache.image(
                for: route, size: size, requestID: identity
            ), let png = image.pngData() {
                try png.write(
                    to: temporary.appendingPathComponent("preview.png"),
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            }
            guard !Task.isCancelled else { return false }
            if FileManager.default.fileExists(atPath: destination.path) {
                // Write the replacement first, preserving the previous
                // complete download until the new version is ready.
                let previous = rootURL.appendingPathComponent(
                    "previous-" + UUID().uuidString, isDirectory: true
                )
                try FileManager.default.moveItem(at: destination, to: previous)
                do {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    try? FileManager.default.removeItem(at: previous)
                } catch {
                    try? FileManager.default.moveItem(at: previous, to: destination)
                    throw error
                }
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            downloadedIDs.insert(route.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    static func storedRoute(routeID: UUID, userID: UUID) -> TrainingRoute? {
        guard let folder = try? directory(userID) else { return nil }
        let url = folder.appendingPathComponent(
            routeID.uuidString, isDirectory: true
        ).appendingPathComponent("route.json")
        guard let data = try? Data(contentsOf: url),
              let route = try? JSONDecoder().decode(TrainingRoute.self, from: data),
              route.ownerID != UUID(uuidString: "00000000-0000-0000-0000-000000000000")
        else { return nil }
        return route
    }

    static func snapshot(routeID: UUID, userID: UUID) -> UIImage? {
        guard let folder = try? directory(userID) else { return nil }
        let path = folder.appendingPathComponent(
            routeID.uuidString, isDirectory: true
        ).appendingPathComponent("preview.png").path
        return UIImage(contentsOfFile: path)
    }

    private func root(_ userID: UUID) throws -> URL {
        let folder = try Self.directory(userID)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        var mutable = folder
        try mutable.setResourceValues(resources)
        return folder
    }

    private static func directory(_ userID: UUID) throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("ATHLTHDownloadedRoutes", isDirectory: true)
        .appendingPathComponent(userID.uuidString, isDirectory: true)
    }
}

/// GPX contains exactly the selected route's real GPS coordinates. No
/// fabricated timestamps or elevation samples are added.
enum ATHLTHRouteGPXExport {
    static func document(_ route: TrainingRoute) throws -> Data {
        let points = route.coordinates
            .sorted { $0.sequence < $1.sequence }
            .filter { CLLocationCoordinate2DIsValid($0.coordinate) }
        guard points.count >= 2 else {
            throw GPXError.insufficientCoordinates
        }
        func xml(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
        }
        func decimal(_ value: Double) -> String {
            String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), value)
        }

        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="ATHLTH" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "<metadata><name>\(xml(route.title))</name></metadata>",
            "<trk><name>\(xml(route.title))</name><trkseg>"
        ]
        for point in points {
            var element = "<trkpt lat=\"\(decimal(point.latitude))\" lon=\"\(decimal(point.longitude))\">"
            if let height = point.altitude, height.isFinite {
                element += "<ele>\(decimal(height))</ele>"
            }
            element += "</trkpt>"
            lines.append(element)
        }
        lines.append("</trkseg></trk></gpx>")
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func temporaryFile(_ route: TrainingRoute) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATHLTH-\(route.id.uuidString).gpx")
        try document(route).write(to: file, options: .atomic)
        return file
    }

    enum GPXError: LocalizedError {
        case insufficientCoordinates
        var errorDescription: String? {
            ATHLTHLocalization.choose(
                english: "Route needs at least two valid GPS points to export.",
                norwegian: "Ruten må ha minst to gyldige GPS-punkter for eksport."
            )
        }
    }
}

struct ATHLTHRouteShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ATHLTHRouteShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
