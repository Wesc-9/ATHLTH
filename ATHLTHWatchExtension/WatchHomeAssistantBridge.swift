import CryptoKit
import Foundation
import Security
import WatchConnectivity

@MainActor
final class WatchHomeAssistantBridge {
    static let shared = WatchHomeAssistantBridge()

    private let keychainService =
        "com.wesc9.athlth.watch.home-assistant"
    private let keychainAccount =
        "configuration-v1"

    private var configuration:
        WatchHomeAssistantConfiguration?

    private init() {
        configuration =
            Self.readConfiguration(
                service: keychainService,
                account: keychainAccount
            )
    }

    func apply(
        _ configuration:
            WatchHomeAssistantConfiguration
    ) {
        guard configuration.enabled,
              configuration.clientID != nil,
              configuration.webhookURL != nil,
              configuration.sharedSecret != nil
        else {
            self.configuration = nil
            Self.deleteConfiguration(
                service: keychainService,
                account: keychainAccount
            )
            return
        }

        self.configuration = configuration
        Self.writeConfiguration(
            configuration,
            service: keychainService,
            account: keychainAccount
        )
    }

    func workoutStarted(
        kind: WatchWorkoutKind,
        startedAt: Date?
    ) {
        guard shouldSendDirectly else {
            return
        }

        var payload: [String: Any] = [
            "name": kind.title,
            "type": kind.rawValue
        ]

        if let startedAt {
            payload["started_at"] =
                ISO8601DateFormatter()
                    .string(from: startedAt)
        }

        Task {
            await send(
                event: "workout_started",
                payload: payload
            )
        }
    }

    func workoutStopped() {
        guard shouldSendDirectly else {
            return
        }

        Task {
            await send(
                event: "sync_snapshot",
                payload: [
                    "state": [
                        "workout_active": false,
                        "active_workout": NSNull()
                    ]
                ]
            )
        }
    }

    private var shouldSendDirectly: Bool {
        guard configuration?.enabled == true
        else {
            return false
        }

        guard WCSession.isSupported()
        else {
            return true
        }

        let session = WCSession.default
        return !(
            session.activationState ==
                .activated &&
            session.isReachable
        )
    }

    private func send(
        event: String,
        payload: [String: Any]
    ) async {
        guard let configuration,
              configuration.enabled,
              let clientID =
                configuration.clientID,
              let webhookURL =
                configuration.webhookURL,
              let sharedSecret =
                configuration.sharedSecret
        else {
            return
        }

        let envelope: [String: Any] = [
            "event": event,
            "payload": payload
        ]

        guard JSONSerialization
                .isValidJSONObject(
                    envelope
                ),
              let body =
                try? JSONSerialization.data(
                    withJSONObject: envelope,
                    options: [.sortedKeys]
                )
        else {
            return
        }

        let timestamp =
            String(
                Int(
                    Date()
                        .timeIntervalSince1970
                )
            )
        let nonce =
            UUID()
                .uuidString
                .lowercased()
        let signature =
            Self.signature(
                secret: sharedSecret,
                timestamp: timestamp,
                nonce: nonce,
                body: body
            )

        let status =
            try? await Self.sendRequest(
                to: webhookURL,
                clientID: clientID,
                timestamp: timestamp,
                nonce: nonce,
                signature: signature,
                body: body
            )

        if let status,
           (200..<300).contains(status) ||
            status == 409 {
            return
        }

        guard Self.shouldTryFallback(
            status
        ),
              let fallback =
                configuration
                    .fallbackWebhookURL,
              fallback != webhookURL
        else {
            return
        }

        _ = try? await Self.sendRequest(
            to: fallback,
            clientID: clientID,
            timestamp: timestamp,
            nonce: nonce,
            signature: signature,
            body: body
        )
    }

    private static func shouldTryFallback(
        _ status: Int?
    ) -> Bool {
        guard let status else {
            return true
        }

        return status == 404 ||
            status == 408 ||
            status == 410 ||
            status == 429 ||
            status >= 500
    }

    private static func sendRequest(
        to url: URL,
        clientID: String,
        timestamp: String,
        nonce: String,
        signature: String,
        body: Data
    ) async throws -> Int {
        var request =
            URLRequest(url: url)
        request.timeoutInterval = 12
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )
        request.setValue(
            clientID,
            forHTTPHeaderField:
                "X-ATHLTH-Client-ID"
        )
        request.setValue(
            timestamp,
            forHTTPHeaderField:
                "X-ATHLTH-Timestamp"
        )
        request.setValue(
            nonce,
            forHTTPHeaderField:
                "X-ATHLTH-Nonce"
        )
        request.setValue(
            "sha256=\(signature)",
            forHTTPHeaderField:
                "X-ATHLTH-Signature"
        )

        let (_, response) =
            try await URLSession.shared
                .data(for: request)

        guard let httpResponse =
                response as?
                    HTTPURLResponse
        else {
            throw URLError(
                .badServerResponse
            )
        }

        return httpResponse.statusCode
    }

    private static func signature(
        secret: String,
        timestamp: String,
        nonce: String,
        body: Data
    ) -> String {
        let signed =
            Data(
                "\(timestamp).\(nonce)."
                    .utf8
            ) + body

        let key =
            SymmetricKey(
                data: Data(secret.utf8)
            )
        let code =
            HMAC<SHA256>
                .authenticationCode(
                    for: signed,
                    using: key
                )

        return code.map {
            String(
                format: "%02x",
                $0
            )
        }
        .joined()
    }

    private static func readConfiguration(
        service: String,
        account: String
    ) -> WatchHomeAssistantConfiguration? {
        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String:
                service,
            kSecAttrAccount as String:
                account,
            kSecReturnData as String:
                true,
            kSecMatchLimit as String:
                kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(
            query as CFDictionary,
            &item
        ) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }

        return try? JSONDecoder()
            .decode(
                WatchHomeAssistantConfiguration
                    .self,
                from: data
            )
    }

    private static func writeConfiguration(
        _ configuration:
            WatchHomeAssistantConfiguration,
        service: String,
        account: String
    ) {
        guard let data =
                try? JSONEncoder()
                    .encode(configuration)
        else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String:
                service,
            kSecAttrAccount as String:
                account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String:
                data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status =
            SecItemUpdate(
                query as CFDictionary,
                attributes as CFDictionary
            )

        if status == errSecItemNotFound {
            var item = query
            attributes.forEach {
                item[$0.key] =
                    $0.value
            }
            SecItemAdd(
                item as CFDictionary,
                nil
            )
        }
    }

    private static func deleteConfiguration(
        service: String,
        account: String
    ) {
        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String:
                service,
            kSecAttrAccount as String:
                account
        ]
        SecItemDelete(
            query as CFDictionary
        )
    }
}
