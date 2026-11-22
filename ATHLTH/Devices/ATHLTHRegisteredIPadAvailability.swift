import Foundation
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
