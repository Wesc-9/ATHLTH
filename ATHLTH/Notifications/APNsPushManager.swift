import Foundation
import Supabase
import UIKit
import UserNotifications

extension Notification.Name {
    static let athlthRemoteNotificationTapped =
        Notification.Name("athlth.remoteNotificationTapped")
}

@MainActor
final class APNsPushManager: ObservableObject {
    static let shared = APNsPushManager()

    @Published private(set) var lastRegistrationError: String?
    @Published private(set) var isRegisteredWithBackend = false

    private let client: SupabaseClient
    private var deviceTokenHex: String?

    private init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func receive(deviceToken: Data) {
        deviceTokenHex = deviceToken
            .map { String(format: "%02x", $0) }
            .joined()

        Task {
            await syncCurrentToken()
        }
    }

    func didFailToRegister(_ error: Error) {
        lastRegistrationError = error.localizedDescription
        isRegisteredWithBackend = false
    }

    func syncCurrentToken() async {
        guard let userID = client.auth.currentUser?.id,
              let token = deviceTokenHex,
              !token.isEmpty
        else {
            return
        }

        let params = RegisterNotificationDeviceParams(
            deviceID: Self.deviceIdentifier,
            platform: "ios",
            appBundleID: Bundle.main.bundleIdentifier ?? "com.wesc9.athlth",
            apnsEnvironment: Self.apnsEnvironment,
            apnsToken: token
        )

        do {
            try await client
                .rpc("register_notification_device", params: params)
                .execute()

            isRegisteredWithBackend = true
            lastRegistrationError = nil

            // Keep the compiler aware that the current authenticated identity
            // is intentionally authoritative for this registration.
            _ = userID
        } catch {
            isRegisteredWithBackend = false
            lastRegistrationError = error.localizedDescription
        }
    }

    func unregisterCurrentDevice() async {
        guard client.auth.currentUser != nil else { return }

        let params = UnregisterNotificationDeviceParams(
            deviceID: Self.deviceIdentifier,
            appBundleID: Bundle.main.bundleIdentifier ?? "com.wesc9.athlth",
            apnsEnvironment: Self.apnsEnvironment
        )

        do {
            try await client
                .rpc("unregister_notification_device", params: params)
                .execute()
            isRegisteredWithBackend = false
        } catch {
            lastRegistrationError = error.localizedDescription
        }
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private static var deviceIdentifier: String {
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            return vendorID.lowercased()
        }

        let key = "athlth.notificationDeviceID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }

        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

private struct RegisterNotificationDeviceParams: Encodable {
    let deviceID: String
    let platform: String
    let appBundleID: String
    let apnsEnvironment: String
    let apnsToken: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case platform = "p_platform"
        case appBundleID = "p_app_bundle_id"
        case apnsEnvironment = "p_apns_environment"
        case apnsToken = "p_apns_token"
    }
}

private struct UnregisterNotificationDeviceParams: Encodable {
    let deviceID: String
    let appBundleID: String
    let apnsEnvironment: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case appBundleID = "p_app_bundle_id"
        case apnsEnvironment = "p_apns_environment"
    }
}

@MainActor
final class ATHLTHAppDelegate: NSObject,
    UIApplicationDelegate,
    UNUserNotificationCenterDelegate
{
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // APNs registration is independent from alert permission. The user
        // still controls alert/sound/badge permission in ATHLTH Settings/iOS.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        APNsPushManager.shared.receive(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        APNsPushManager.shared.didFailToRegister(error)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        NotificationCenter.default.post(
            name: .athlthRemoteNotificationTapped,
            object: nil,
            userInfo: userInfo
        )
    }
}
