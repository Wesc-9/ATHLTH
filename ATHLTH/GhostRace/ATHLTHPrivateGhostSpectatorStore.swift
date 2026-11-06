import CoreLocation
import Foundation
import Supabase

/// A short-lived, read-only preview for the account owner's iPad.
/// Never contains raw HealthKit records or an actual GPS breadcrumb history.
/// Route geometry is sampled locally and is uploaded ONLY after explicit
/// opt-in; it is still sensitive location data protected by owner-only RLS.
struct ATHLTHPrivateGhostSpectatorSnapshot: Codable, Hashable, Identifiable {
    struct CoursePoint: Codable, Hashable {
        let latitude: Double
        let longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    let id: UUID
    let title: String
    let sourceDevice: String
    let isSimulated: Bool
    let capturedAtEpoch: TimeInterval
    let paused: Bool
    let course: [CoursePoint]
    let routeDistanceMeters: Double
    let runner: CoursePoint?
    let ghost: CoursePoint?
    let runnerProgress: Double?
    let ghostProgress: Double?
    let signedDistanceMeters: Double?
    let signedTimeSeconds: TimeInterval?

    /// The race card disappears after disconnect. It never claims to be
    /// current from a stale record, including while the iPad was asleep.
    func isFresh(at now: Date = .now) -> Bool {
        let age = now.timeIntervalSince1970 - capturedAtEpoch
        return age >= -10 && age < 70 && course.count >= 2 &&
            routeDistanceMeters.isFinite && routeDistanceMeters >= 200
    }

    /// Markers and the live gap expire faster than the course itself.
    func hasFreshPositions(at now: Date = .now) -> Bool {
        let age = now.timeIntervalSince1970 - capturedAtEpoch
        guard isFresh(at: now), !paused, age < 19,
              let runner, let ghost,
              let runnerProgress, let ghostProgress,
              let signedDistanceMeters, let signedTimeSeconds,
              (0...1).contains(runnerProgress),
              (0...1).contains(ghostProgress),
              signedDistanceMeters.isFinite, signedTimeSeconds.isFinite
        else { return false }
        return Self.validCoordinate(runner) &&
            Self.validCoordinate(ghost)
    }

    static func validCoordinate(_ value: CoursePoint) -> Bool {
        value.latitude.isFinite && value.longitude.isFinite &&
            (-90...90).contains(value.latitude) &&
            (-180...180).contains(value.longitude)
    }

    @MainActor
    static func make(
        reference: GhostRaceReference,
        comparison: GhostRaceComparison?,
        sourceDevice: String,
        paused: Bool,
        now: Date = .now
    ) -> Self? {
        guard reference.points.count >= 2,
              reference.routeDistanceMeters.isFinite,
              reference.routeDistanceMeters >= 200
        else { return nil }

        // Keep first/last and intermediate course points, not the athlete's
        // recorded breadcrumb stream. Bound the private payload to 180 points.
        let count = reference.points.count
        let target = min(180, count)
        let indices = (0..<target).map {
            Int((Double($0) * Double(count - 1) /
                 Double(max(target - 1, 1))).rounded())
        }
        let course = indices.map {
            CoursePoint(
                latitude: reference.points[$0].latitude,
                longitude: reference.points[$0].longitude
            )
        }
        guard course.allSatisfy(validCoordinate) else { return nil }

        let accepted = ATHLTHGhostRaceLiveMapPolicy.acceptedComparison(
            comparison, paused: paused, at: now
        )
        return Self(
            id: reference.id,
            title: String(reference.title.prefix(125)),
            sourceDevice: sourceDevice,
            isSimulated: reference.title.hasPrefix("Target ·"),
            capturedAtEpoch: now.timeIntervalSince1970,
            paused: paused,
            course: course,
            routeDistanceMeters: reference.routeDistanceMeters,
            runner: accepted.map {
                CoursePoint(latitude: $0.userLatitude, longitude: $0.userLongitude)
            },
            ghost: accepted.map {
                CoursePoint(latitude: $0.ghostLatitude, longitude: $0.ghostLongitude)
            },
            runnerProgress: accepted?.userProgress,
            ghostProgress: accepted?.ghostProgress,
            signedDistanceMeters: accepted?.signedDistanceMeters,
            signedTimeSeconds: accepted?.signedTimeSeconds
        )
    }
}

/// A same-account, private cross-device relay. Not used by cloud Live Ghost,
/// friends, clubs or the social location sharing setting.
@MainActor
enum ATHLTHPrivateGhostSpectatorStore {
    private static let table = "private_active_ghost_ipad_status"
    private static let preference = "shareFixedGhostRaceWithOwnIPad"
    private static let client = SupabaseEnvironment.client
    private static var lastSentAt: Date?
    private static var lastRaceID: UUID?
    private static var lastPaused: Bool?

    private struct Write: Encodable {
        let user_id: UUID
        let snapshot: ATHLTHPrivateGhostSpectatorSnapshot
        let updated_at: String
        let expires_at: String
    }

    private struct Read: Decodable {
        let snapshot: ATHLTHPrivateGhostSpectatorSnapshot
    }

    static func isEnabled(for userID: UUID) -> Bool {
        AccountLocalStorage.read(Bool.self, name: preference, userID: userID) ?? false
    }

    static func setEnabled(_ enabled: Bool, for userID: UUID) {
        AccountLocalStorage.write(enabled, name: preference, userID: userID)
        if !enabled {
            lastRaceID = nil
            lastSentAt = nil
            lastPaused = nil
            Task { await clear(for: userID) }
        }
    }

    static func publish(
        reference: GhostRaceReference,
        comparison: GhostRaceComparison?,
        sourceDevice: String,
        paused: Bool,
        userID: UUID
    ) async {
        guard !ATHLTHDeviceRole.isIPad,
              client.auth.currentUser?.id == userID,
              isEnabled(for: userID)
        else { return }

        let now = Date()
        if lastRaceID == reference.id, lastPaused == paused,
           let lastSentAt, now.timeIntervalSince(lastSentAt) < 4 {
            return
        }
        guard let snapshot = ATHLTHPrivateGhostSpectatorSnapshot.make(
            reference: reference, comparison: comparison,
            sourceDevice: sourceDevice, paused: paused, now: now
        ) else { return }

        // Throttle before awaiting the network so parallel GPS and Watch
        // updates cannot overwhelm the database.
        lastRaceID = reference.id
        lastPaused = paused
        lastSentAt = now

        let formatter = ISO8601DateFormatter()
        let write = Write(
            user_id: userID,
            snapshot: snapshot,
            updated_at: formatter.string(from: now),
            expires_at: formatter.string(
                from: now.addingTimeInterval(65)
            )
        )
        do {
            try await client.from(table)
                .upsert(write, onConflict: "user_id")
                .execute()
        } catch {
            // Offline running must continue. Readers discard expired data;
            // the publisher retries on the next active GPS update.
        }
    }

    static func clear(for userID: UUID) async {
        guard client.auth.currentUser?.id == userID else { return }
        lastRaceID = nil
        lastPaused = nil
        lastSentAt = nil
        do {
            try await client.from(table)
                .delete()
                .eq("user_id", value: userID)
                .execute()
        } catch {
            // The short expiry and DB purge remove orphaned records.
        }
    }

    static func fetch(for userID: UUID) async -> ATHLTHPrivateGhostSpectatorSnapshot? {
        guard ATHLTHDeviceRole.isIPad,
              client.auth.currentUser?.id == userID else { return nil }
        do {
            let records: [Read] = try await client.from(table)
                .select("snapshot")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            guard let snapshot = records.first?.snapshot,
                  snapshot.isFresh() else { return nil }
            return snapshot
        } catch {
            return nil
        }
    }
}
