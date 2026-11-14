import CoreLocation
import Foundation

/// Non-sensitive, public trail snapshots only. Account-owned/private routes
/// are deliberately excluded and continue to use their existing scoped store.
actor ATHLTHPublicTrailDiskCache {
    static let shared = ATHLTHPublicTrailDiskCache()

    struct CachedData: Sendable {
        let payload: Data
        let attribution: String
        let savedAt: Date
    }

    private struct Entry: Codable {
        let latitude: Double
        let longitude: Double
        let radiusKilometers: Double
        let savedAt: Date
        let attribution: String
        let payload: Data
    }

    private let maximumEntries = 6
    private let maximumBytes = 7_000_000
    private let maximumAge: TimeInterval = 7 * 24 * 60 * 60
    private var loaded: [Entry]?

    private var fileURL: URL? {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(
            "athlth-public-trails-v1.json",
            isDirectory: false
        )
    }

    func cached(
        latitude: Double,
        longitude: Double,
        radiusKilometers: Double
    ) -> CachedData? {
        let entries = readEntries()
        let now = Date()
        let center = CLLocation(latitude: latitude, longitude: longitude)
        let best = entries
            .filter { entry in
                guard now.timeIntervalSince(entry.savedAt) < maximumAge,
                      entry.radiusKilometers.isFinite,
                      entry.radiusKilometers > 0,
                      radiusKilometers > 0 else { return false }
                let delta = abs(entry.radiusKilometers - radiusKilometers)
                let centerDistance = center.distance(from: CLLocation(
                    latitude: entry.latitude,
                    longitude: entry.longitude
                ))
                // Allow a small pan, but never show a cache for another city.
                return delta <= max(2, radiusKilometers * 0.35) &&
                    centerDistance <= max(750, radiusKilometers * 350)
            }
            .max { $0.savedAt < $1.savedAt }

        guard let best else { return nil }
        return CachedData(
            payload: best.payload,
            attribution: best.attribution,
            savedAt: best.savedAt
        )
    }

    func store(
        payload: Data,
        attribution: String,
        latitude: Double,
        longitude: Double,
        radiusKilometers: Double
    ) {
        guard !payload.isEmpty, payload.count < maximumBytes,
              latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180,
              radiusKilometers.isFinite, radiusKilometers > 0 else { return }

        let now = Date()
        let nearby = CLLocation(latitude: latitude, longitude: longitude)
        var entries = readEntries().filter { entry in
            guard now.timeIntervalSince(entry.savedAt) < maximumAge else {
                return false
            }
            let distance = nearby.distance(from: CLLocation(
                latitude: entry.latitude,
                longitude: entry.longitude
            ))
            return distance > 1_000 ||
                abs(entry.radiusKilometers - radiusKilometers) > 2
        }
        entries.insert(Entry(
            latitude: latitude,
            longitude: longitude,
            radiusKilometers: radiusKilometers,
            savedAt: now,
            attribution: attribution,
            payload: payload
        ), at: 0)
        entries.sort { $0.savedAt > $1.savedAt }
        entries = Array(entries.prefix(maximumEntries))

        while entries.count > 1,
              entries.reduce(0, { $0 + $1.payload.count }) > maximumBytes {
            entries.removeLast()
        }

        loaded = entries
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func readEntries() -> [Entry] {
        if let loaded { return loaded }
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            loaded = []
            return []
        }
        loaded = entries
        return entries
    }
}
