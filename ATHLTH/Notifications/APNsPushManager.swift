import Foundation
import Supabase
import UIKit
import UserNotifications

struct ATHLTHPushNavigationTarget:
    Identifiable,
    Equatable
{
    let communityEventID: UUID
    let backendEventID: UUID?

    var id: UUID {
        communityEventID
    }
}

extension Notification.Name {
    static let athlthRemoteNotificationReceived =
        Notification.Name("athlth.remoteNotificationReceived")
    static let athlthRemoteNotificationTapped =
        Notification.Name("athlth.remoteNotificationTapped")
}

@MainActor
final class APNsPushManager: ObservableObject {
    static let shared = APNsPushManager()

    @Published private(set) var lastRegistrationError: String?
    @Published private(set) var isRegisteredWithBackend = false
    @Published private(set) var hasDeviceToken = false
    @Published private(set) var isSystemRegistered = false
    @Published private(set) var lastBackendSyncAt: Date?
    @Published private(set) var pendingNavigationTarget:
        ATHLTHPushNavigationTarget?

    private let client: SupabaseClient
    private var deviceTokenHex: String?
    private var lastSystemRegistrationRequestAt: Date?
    private var registrationRetryTask: Task<Void, Never>?

    private static let storedTokenKey =
        "athlth.apns.deviceToken.v1"

    private init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
        self.deviceTokenHex =
            UserDefaults.standard.string(
                forKey: Self.storedTokenKey
            )
        self.hasDeviceToken =
            !(self.deviceTokenHex?.isEmpty ?? true)
        self.isSystemRegistered =
            UIApplication.shared
                .isRegisteredForRemoteNotifications
    }

    var environmentLabel: String {
        Self.apnsEnvironment == "production"
            ? "Production"
            : "Sandbox"
    }

    func captureTappedNotification(
        _ userInfo:
            [AnyHashable: Any]
    ) {
        guard
            let entityType =
                userInfo[
                    "athlth_entity_type"
                ] as? String,
            entityType
                .lowercased() ==
                "community_event",
            let rawEntityID =
                userInfo[
                    "athlth_entity_id"
                ] as? String,
            let eventID =
                UUID(
                    uuidString:
                        rawEntityID
                )
        else {
            return
        }

        let backendEventID =
            (
                userInfo[
                    "athlth_event_id"
                ] as? String
            )
            .flatMap {
                UUID(
                    uuidString: $0
                )
            }

        pendingNavigationTarget =
            ATHLTHPushNavigationTarget(
                communityEventID:
                    eventID,
                backendEventID:
                    backendEventID
            )
    }

    func clearPendingNavigationTarget() {
        pendingNavigationTarget = nil
    }

    func receive(deviceToken: Data) {
        let token =
            deviceToken
                .map {
                    String(
                        format: "%02x",
                        $0
                    )
                }
                .joined()

        registrationRetryTask?
            .cancel()
        registrationRetryTask = nil

        deviceTokenHex = token
        hasDeviceToken = !token.isEmpty
        isSystemRegistered = true
        UserDefaults.standard.set(
            token,
            forKey: Self.storedTokenKey
        )

        Task {
            await syncCurrentToken()
        }
    }

    func didFailToRegister(_ error: Error) {
        lastRegistrationError =
            error.localizedDescription
        isSystemRegistered = false
        isRegisteredWithBackend = false

        Task { @MainActor [weak self] in
            guard let self,
                  await self
                    .systemNotificationsAllowed()
            else {
                return
            }

            self.scheduleRegistrationRecovery()
        }
    }

    /// Repairs the full client side of the push path without prompting.
    /// Apple recommends requesting alert permission before APNs registration;
    /// this method therefore registers only when permission is already allowed.
    func repairRegistrationIfAuthorized() async {
        isSystemRegistered =
            UIApplication.shared
                .isRegisteredForRemoteNotifications

        guard await systemNotificationsAllowed()
        else {
            await refreshBackendRegistrationStatus()
            return
        }

        ensureSystemRegistration(force: true)

        if hasDeviceToken {
            await syncCurrentToken()
        } else {
            scheduleRegistrationRecovery()
        }
    }

    func refreshBackendRegistrationStatus() async {
        guard let userID =
                client.auth.currentUser?.id
        else {
            isRegisteredWithBackend = false
            return
        }

        do {
            let rows:
                [NotificationDeviceProbe] =
                    try await client
                        .from(
                            "notification_devices"
                        )
                        .select("id")
                        .eq(
                            "user_id",
                            value: userID
                        )
                        .eq(
                            "device_id",
                            value:
                                Self
                                    .deviceIdentifier
                        )
                        .eq(
                            "app_bundle_id",
                            value:
                                Bundle.main
                                    .bundleIdentifier ??
                                "com.wesc9.athlth"
                        )
                        .eq(
                            "apns_environment",
                            value:
                                Self
                                    .apnsEnvironment
                        )
                        .limit(1)
                        .execute()
                        .value

            isRegisteredWithBackend =
                !rows.isEmpty
        } catch {
            isRegisteredWithBackend = false
            lastRegistrationError =
                error.localizedDescription
        }
    }

    func syncCurrentToken() async {
        guard let userID =
                client.auth.currentUser?.id
        else {
            isRegisteredWithBackend = false
            return
        }

        guard let token =
                deviceTokenHex,
              !token.isEmpty
        else {
            hasDeviceToken = false

            // Do not try to register with APNs before notification
            // authorization has been decided. This follows Apple's
            // recommended ordering and avoids silent launch-time failures.
            if await systemNotificationsAllowed() {
                ensureSystemRegistration(
                    force: true
                )
                scheduleRegistrationRecovery()
            }

            isRegisteredWithBackend = false
            return
        }

        hasDeviceToken = true

        let params = RegisterNotificationDeviceParams(
            deviceID: Self.deviceIdentifier,
            platform: "ios",
            appBundleID: Bundle.main.bundleIdentifier ?? "com.wesc9.athlth",
            apnsEnvironment: Self.apnsEnvironment,
            apnsToken: token,
            languageCode:
                ATHLTHLocalization.isNorwegian
                    ? "nb"
                    : "en"
        )

        do {
            try await client
                .rpc("register_notification_device", params: params)
                .execute()

            isRegisteredWithBackend = true
            isSystemRegistered =
                UIApplication.shared
                    .isRegisteredForRemoteNotifications
            lastBackendSyncAt = Date()
            lastRegistrationError = nil
            registrationRetryTask?
                .cancel()
            registrationRetryTask = nil

            // Keep the compiler aware that the current authenticated identity
            // is intentionally authoritative for this registration.
            _ = userID
        } catch {
            isRegisteredWithBackend = false
            lastRegistrationError = error.localizedDescription
        }
    }

    func ensureSystemRegistration(
        force: Bool = false
    ) {
        let now = Date()

        if !force,
           let last =
                lastSystemRegistrationRequestAt,
           now.timeIntervalSince(last) <
                15 {
            return
        }

        lastSystemRegistrationRequestAt =
            now

        UIApplication.shared
            .registerForRemoteNotifications()
        isSystemRegistered =
            UIApplication.shared
                .isRegisteredForRemoteNotifications
    }

    private func systemNotificationsAllowed()
        async -> Bool {
        let settings =
            await UNUserNotificationCenter
                .current()
                .notificationSettings()

        switch settings.authorizationStatus {
        case .authorized,
             .provisional,
             .ephemeral:
            return true

        case .notDetermined,
             .denied:
            return false

        @unknown default:
            return false
        }
    }

    private func scheduleRegistrationRecovery() {
        guard registrationRetryTask == nil
        else {
            return
        }

        registrationRetryTask =
            Task { @MainActor [weak self] in
                let delays:
                    [Duration] = [
                        .seconds(2),
                        .seconds(8),
                        .seconds(30),
                        .seconds(120)
                    ]

                for delay in delays {
                    try? await Task.sleep(
                        for: delay
                    )

                    guard
                        let self,
                        !Task.isCancelled
                    else {
                        return
                    }

                    guard await self
                        .systemNotificationsAllowed()
                    else {
                        self.registrationRetryTask =
                            nil
                        return
                    }

                    if let token =
                            self.deviceTokenHex,
                       !token.isEmpty {
                        self.hasDeviceToken = true
                        self.registrationRetryTask =
                            nil
                        await self
                            .syncCurrentToken()
                        return
                    }

                    self
                        .ensureSystemRegistration(
                            force: true
                        )
                }

                if let self,
                   self.deviceTokenHex?.isEmpty != false {
                    self.hasDeviceToken = false
                    self.lastRegistrationError =
                        "APNs did not return a device token."
                }

                self?
                    .registrationRetryTask =
                    nil
            }
    }

    func syncNotificationPreferences(
        workoutUpdates: Bool,
        friendActivity: Bool,
        challenges: Bool,
        messages: Bool,
        mentions: Bool
    ) async {
        guard let userID = client.auth.currentUser?.id else { return }

        let payload = NotificationPreferenceWrite(
            workoutRemindersEnabled: workoutUpdates,
            friendActivityNotificationsEnabled: friendActivity,
            challengeNotificationsEnabled: challenges,
            messageNotificationsEnabled: messages,
            mentionNotificationsEnabled: mentions
        )

        do {
            try await client
                .from("user_preferences")
                .update(payload)
                .eq("user_id", value: userID)
                .execute()
        } catch {
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
            lastBackendSyncAt = nil
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

private struct NotificationDeviceProbe:
    Decodable
{
    let id: UUID
}

private struct NotificationPreferenceWrite: Encodable {
    let workoutRemindersEnabled: Bool
    let friendActivityNotificationsEnabled: Bool
    let challengeNotificationsEnabled: Bool
    let messageNotificationsEnabled: Bool
    let mentionNotificationsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case workoutRemindersEnabled = "workout_reminders_enabled"
        case friendActivityNotificationsEnabled =
            "friend_activity_notifications_enabled"
        case challengeNotificationsEnabled =
            "challenge_notifications_enabled"
        case messageNotificationsEnabled =
            "message_notifications_enabled"
        case mentionNotificationsEnabled =
            "mention_notifications_enabled"
    }
}

private struct RegisterNotificationDeviceParams: Encodable {
    let deviceID: String
    let platform: String
    let appBundleID: String
    let apnsEnvironment: String
    let apnsToken: String
    let languageCode: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case platform = "p_platform"
        case appBundleID = "p_app_bundle_id"
        case apnsEnvironment = "p_apns_environment"
        case apnsToken = "p_apns_token"
        case languageCode = "p_language_code"
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
        ATHLTHHomeAssistantBackgroundRefresh.register()
        HealthKitManager.shared.prepareBackgroundObserversAtLaunch()

        // Apple recommends requesting user-facing notification permission
        // before registering with APNs. If permission was already granted on
        // a previous launch, repair registration immediately. If it is still
        // undecided, the in-app primer will request it first.
        Task { @MainActor in
            await APNsPushManager.shared
                .repairRegistrationIfAuthorized()
        }
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

    // APNs payloads are JSON. Serialize before crossing to MainActor so
    // Swift 6 does not transfer a non-Sendable [AnyHashable: Any] dictionary.
    // The original payload is reconstructed before dispatching notifications.
    nonisolated private func notificationPayload(
        _ userInfo: [AnyHashable: Any]
    ) -> Data? {
        try? JSONSerialization.data(withJSONObject: userInfo)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = notificationPayload(notification.request.content.userInfo)

        await MainActor.run {
            guard let payload,
                  let userInfo = try? JSONSerialization.jsonObject(with: payload)
                    as? [AnyHashable: Any] else {
                return
            }
            NotificationCenter.default.post(
                name: .athlthRemoteNotificationReceived,
                object: nil,
                userInfo: userInfo
            )
        }

        return [.banner, .sound, .badge, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = notificationPayload(response.notification.request.content.userInfo)

        await MainActor.run {
            guard let payload,
                  let userInfo = try? JSONSerialization.jsonObject(with: payload)
                    as? [AnyHashable: Any] else {
                return
            }

            APNsPushManager.shared.captureTappedNotification(userInfo)

            NotificationCenter.default.post(
                name: .athlthRemoteNotificationReceived,
                object: nil,
                userInfo: userInfo
            )
            NotificationCenter.default.post(
                name: .athlthRemoteNotificationTapped,
                object: nil,
                userInfo: userInfo
            )
        }
    }
}
