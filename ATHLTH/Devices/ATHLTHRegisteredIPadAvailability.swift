import Foundation
import Combine
import Supabase

/// Use an existing, authenticated device registration as a conservative
/// signal before offering remote iPad live sharing. APNs may be disabled;
/// absence of a registration must hide the option, never invent a device.
/// Never read or expose APNs tokens.
@MainActor
final class ATHLTHRegisteredIPadAvailability: ObservableObject {
    @Published private(set) var hasRegisteredIPad = false

    private struct DeviceRegistration: Decodable {
        let device_id: String
    }

    private let client: SupabaseClient
    private var lastCheckedAccountID: UUID?
    private var lastCheckedAt: Date?

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func refresh(for userID: UUID) async {
        guard client.auth.currentUser?.id == userID else {
            hasRegisteredIPad = false
            lastCheckedAt = nil
            lastCheckedAccountID = nil
            return
        }

        if lastCheckedAccountID == userID,
           let lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < 90 {
            return
        }
        lastCheckedAccountID = userID
        lastCheckedAt = Date()
        // The iPad has to have registered on this same account recently.
        // A stale device token does not prove that the app is still installed.
        let recent = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-120 * 86_400)
        )
        do {
            let devices: [DeviceRegistration] = try await client
                .from("notification_devices")
                .select("device_id")
                .eq("user_id", value: userID)
                .eq("device_family", value: "ipad")
                .eq("app_bundle_id", value:
                    Bundle.main.bundleIdentifier ?? "com.wesc9.athlth")
                .gte("last_seen_at", value: recent)
                .limit(1)
                .execute()
                .value

            guard client.auth.currentUser?.id == userID else {
                hasRegisteredIPad = false
                return
            }
            hasRegisteredIPad = !devices.isEmpty
        } catch {
            // Registration status is optional. On a read/RLS/network failure
            // fail closed: never imply that another device is available.
            hasRegisteredIPad = false
        }
    }
}


/// A recent, phone-observed WatchConnectivity status, without any health data.
struct ATHLTHWorkoutDeviceHeartbeat: Codable, Equatable {
    let userID: UUID
    let deviceID: String
    let watchPaired: Bool
    let watchInstalled: Bool
    let watchReachable: Bool
    let observedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case watchPaired = "watch_paired"
        case watchInstalled = "watch_installed"
        case watchReachable = "watch_reachable"
        case observedAt = "observed_at"
    }

    func isFresh(at now: Date = .now) -> Bool {
        (-5...35).contains(now.timeIntervalSince(observedAt))
    }
}

/// Registration remains a fallback, not a live connection or Watch pairing.
@MainActor
final class ATHLTHRegisteredPhoneAvailability: ObservableObject {
    enum Status: Equatable { case checking, registered, notRegistered, unknown }
    @Published private(set) var status: Status = .checking
    @Published private(set) var heartbeats: [ATHLTHWorkoutDeviceHeartbeat] = []
    private let client: SupabaseClient
    private var generation = UUID()
    private var checkedAccount: UUID?

    var phoneOnline: Bool { heartbeats.contains { $0.isFresh() } }
    var watchAvailable: Bool {
        heartbeats.contains { $0.isFresh() && $0.watchPaired && $0.watchInstalled }
    }
    var watchReachable: Bool {
        heartbeats.contains { $0.isFresh() && $0.watchPaired && $0.watchInstalled && $0.watchReachable }
    }

    private struct DeviceRegistration: Decodable { let device_id: String }

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func refresh(for userID: UUID) async {
        let request = UUID()
        generation = request
        if checkedAccount != userID {
            status = .checking
            heartbeats = []
            checkedAccount = userID
        }
        guard client.auth.currentUser?.id == userID else {
            heartbeats = []
            status = .unknown
            return
        }
        do {
            let live: [ATHLTHWorkoutDeviceHeartbeat] = try await client
                .from("private_workout_device_availability")
                .select()
                .eq("user_id", value: userID)
                .gte("observed_at", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-35)))
                .limit(20)
                .execute().value
            guard generation == request, client.auth.currentUser?.id == userID,
                  !Task.isCancelled else { return }
            heartbeats = live.filter { $0.userID == userID && $0.isFresh() }
            if phoneOnline {
                status = .registered
                return
            }
        } catch {
            guard generation == request, client.auth.currentUser?.id == userID,
                  !Task.isCancelled else { return }
            heartbeats = []
        }
        let recent = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-120 * 86_400)
        )
        do {
            let devices: [DeviceRegistration] = try await client
                .from("notification_devices")
                .select("device_id")
                .eq("user_id", value: userID)
                .eq("device_family", value: "iphone")
                .eq("app_bundle_id", value: Bundle.main.bundleIdentifier ?? "com.wesc9.athlth")
                .gte("last_seen_at", value: recent)
                .limit(1)
                .execute().value
            guard generation == request, client.auth.currentUser?.id == userID,
                  !Task.isCancelled else { return }
            status = devices.isEmpty ? .notRegistered : .registered
        } catch {
            guard generation == request, client.auth.currentUser?.id == userID,
                  !Task.isCancelled else { return }
            status = .unknown
        }
    }
}
