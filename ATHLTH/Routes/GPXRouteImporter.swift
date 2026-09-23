import CoreLocation
import Foundation

enum GPXImportError: LocalizedError {
    case invalidDocument
    case noCoordinates

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "The selected file is not a valid GPX document."
        case .noCoordinates:
            return "No route or track coordinates were found in the GPX file."
        }
    }
}

final class GPXRouteImporter: NSObject, RouteImporting, XMLParserDelegate {
    private let ownerID: UUID
    private var coordinates: [RouteCoordinate] = []

    init(ownerID: UUID) {
        self.ownerID = ownerID
        super.init()
    }
    private var currentAltitudeText = ""
    private var activePointIndex: Int?
    private var parseError: Error?

    func importGPX(data: Data, filename: String?) async throws -> TrainingRoute {
        coordinates = []
        currentAltitudeText = ""
        activePointIndex = nil
        parseError = nil

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parseError ?? parser.parserError ?? GPXImportError.invalidDocument
        }

        guard coordinates.count >= 2 else {
            throw GPXImportError.noCoordinates
        }

        let distanceMeters = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { partial, pair in
            let start = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let end = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return partial + end.distance(from: start)
        }

        let elevationGain = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { partial, pair in
            guard let first = pair.0.altitude, let second = pair.1.altitude else { return partial }
            return partial + max(second - first, 0)
        }

        let title = filename?
            .replacingOccurrences(of: ".gpx", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "_", with: " ")
            ?? "Imported Route"

        return TrainingRoute(
            id: UUID(),
            ownerID: ownerID,
            title: title,
            visibility: .privateOnly,
            coordinates: coordinates,
            distanceKilometers: distanceMeters / 1_000,
            elevationGainMeters: elevationGain,
            importedFilename: filename,
            createdAt: Date()
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "trkpt" || elementName == "rtept" {
            guard
                let latText = attributeDict["lat"],
                let lonText = attributeDict["lon"],
                let latitude = Double(latText),
                let longitude = Double(lonText)
            else {
                return
            }

            activePointIndex = coordinates.count
            coordinates.append(
                RouteCoordinate(
                    latitude: latitude,
                    longitude: longitude,
                    altitude: nil,
                    sequence: coordinates.count
                )
            )
        }

        if elementName == "ele" {
            currentAltitudeText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentAltitudeText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "ele",
           let index = activePointIndex,
           coordinates.indices.contains(index),
           let altitude = Double(currentAltitudeText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            coordinates[index].altitude = altitude
        }

        if elementName == "trkpt" || elementName == "rtept" {
            activePointIndex = nil
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}
