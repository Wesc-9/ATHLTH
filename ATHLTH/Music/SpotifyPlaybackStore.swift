import Foundation
import Security
import UIKit
@preconcurrency import SpotifyiOS

struct SpotifyPlaylistReference: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var uri: String
    var artworkURL: URL?
    var ownerName: String?
}

enum SpotifyConnectionState: Equatable {
    case unavailable
    case disconnected
    case connecting
    case connected
    case error(String)

    var title: String {
        switch self {
        case .unavailable: return "Needs setup"
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error: return "Connection issue"
        }
    }
}

@MainActor
final class SpotifyPlaybackStore: NSObject, ObservableObject {
    @Published private(set) var connectionState: SpotifyConnectionState = .disconnected
    @Published private(set) var playlists: [SpotifyPlaylistReference] = []
    @Published private(set) var activePlaylist: SpotifyPlaylistReference?
    @Published private(set) var lastStartedAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isRefreshingPlaylists = false

    private let keychainService = "com.wesc9.athlth.spotify"
    private let keychainAccount = "spotify-session"

    private var pendingPlaybackURI: String?

    private var clientID: String {
        let value =
            (Bundle.main.object(
                forInfoDictionaryKey: "ATHLTHSpotifyClientID"
            ) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !value.isEmpty,
              !value.contains("$(")
        else {
            return ""
        }

        return value
    }

    private var redirectURI: String {
        let configured =
            (Bundle.main.object(forInfoDictionaryKey: "ATHLTHSpotifyRedirectURI") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? "athlth-spotify-login://callback" : configured
    }

    var isConfigured: Bool {
        !clientID.isEmpty && URL(string: redirectURI) != nil
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var setupMessage: String? {
        guard !isConfigured else { return nil }
        return "Add ATHLTH_SPOTIFY_CLIENT_ID to the build configuration and whitelist \(redirectURI) in Spotify Developer Dashboard."
    }

    private lazy var spotifyConfiguration: SPTConfiguration? = {
        guard isConfigured,
              let redirectURL = URL(string: redirectURI)
        else {
            return nil
        }

        let configuration = SPTConfiguration(
            clientID: clientID,
            redirectURL: redirectURL
        )
        configuration.playURI = ""
        return configuration
    }()

    private lazy var sessionManager: SPTSessionManager? = {
        guard let spotifyConfiguration else { return nil }
        return SPTSessionManager(
            configuration: spotifyConfiguration,
            delegate: self
        )
    }()

    private lazy var appRemote: SPTAppRemote? = {
        guard let spotifyConfiguration else { return nil }
        let remote = SPTAppRemote(
            configuration: spotifyConfiguration,
            logLevel: .error
        )
        remote.delegate = self
        return remote
    }()

    override init() {
        super.init()

        guard isConfigured else {
            connectionState = .unavailable
            return
        }

        restoreSessionIfAvailable()
    }

    func connect() {
        guard isConfigured,
              let sessionManager
        else {
            connectionState = .unavailable
            lastErrorMessage = setupMessage
            return
        }

        connectionState = .connecting
        lastErrorMessage = nil

        let scopes: SPTScope = [
            .appRemoteControl,
            .playlistReadPrivate,
            .playlistReadCollaborative,
            .userReadPlaybackState,
            .userModifyPlaybackState
        ]

        sessionManager.initiateSession(
            with: scopes,
            options: .default,
            campaign: nil
        )
    }

    func disconnect() {
        appRemote?.disconnect()
        sessionManager?.session = nil
        deleteStoredSession()
        playlists = []
        activePlaylist = nil
        lastStartedAt = nil
        lastErrorMessage = nil
        connectionState = isConfigured ? .disconnected : .unavailable
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard isConfigured else { return false }

        if let sessionManager,
           sessionManager.application(
                UIApplication.shared,
                open: url,
                options: [:]
           ) {
            return true
        }

        guard let appRemote,
              let parameters =
                appRemote.authorizationParameters(from: url)
        else {
            return false
        }

        if let token = parameters[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
            return true
        }

        if let message = parameters[SPTAppRemoteErrorDescriptionKey] {
            lastErrorMessage = message
            connectionState = .error(message)
            return true
        }

        return false
    }

    func refreshPlaylists() async {
        guard isConfigured else {
            connectionState = .unavailable
            return
        }

        guard let token = accessTokenForRequest() else {
            connectionState = .disconnected
            playlists = []
            return
        }

        isRefreshingPlaylists = true
        defer { isRefreshingPlaylists = false }

        do {
            let fetched = try await fetchPlaylists(accessToken: token)
            playlists = fetched
            connectionState = .connected
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            if isAuthorizationError(error) {
                connectionState = .disconnected
            } else {
                connectionState = .error(error.localizedDescription)
            }
        }
    }

    func startLinkedPlaylist(
        _ playlist: SpotifyPlaylistReference,
        settings: AppSettingsStore
    ) async {
        guard settings.spotifyAutoplayLinkedPlaylists,
              isConfigured
        else {
            return
        }

        activePlaylist = nil
        lastStartedAt = nil
        lastErrorMessage = nil
        pendingPlaybackURI = playlist.uri

        guard let appRemote else { return }

        if let token = accessTokenForRequest() {
            appRemote.connectionParameters.accessToken = token
        }

        if appRemote.isConnected {
            await playThroughConnectedRemote(
                playlist,
                appRemote: appRemote
            )
            return
        }

        // This deliberately opens/wakes Spotify on iPhone. The Watch app does
        // not run this code and never blocks workout start waiting for Spotify.
        appRemote.authorizeAndPlayURI(playlist.uri) { [weak self] installed in
            Task { @MainActor in
                guard let self else { return }

                if installed {
                    self.activePlaylist = playlist
                    self.lastStartedAt = Date()
                } else {
                    self.lastErrorMessage =
                        "Spotify is not installed on this iPhone."
                    self.pendingPlaybackURI = nil
                }
            }
        }
    }

    func pause() {
        appRemote?.playerAPI?.pause { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func resume() {
        appRemote?.playerAPI?.resume { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func skipToNext() {
        appRemote?.playerAPI?.skip(toNext: { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.lastErrorMessage = error.localizedDescription
                }
            }
        })
    }

    func stopPreviewPlaybackState() {
        activePlaylist = nil
        lastStartedAt = nil
    }

    private func playThroughConnectedRemote(
        _ playlist: SpotifyPlaylistReference,
        appRemote: SPTAppRemote
    ) async {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            guard let playerAPI = appRemote.playerAPI else {
                continuation.resume()
                return
            }

            playerAPI.play(playlist.uri) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.lastErrorMessage = error.localizedDescription
                    } else {
                        self?.activePlaylist = playlist
                        self?.lastStartedAt = Date()
                    }
                    self?.pendingPlaybackURI = nil
                    continuation.resume()
                }
            }
        }
    }

    private func accessTokenForRequest() -> String? {
        guard let sessionManager,
              let session = sessionManager.session
        else {
            return nil
        }

        if session.isExpired {
            sessionManager.renewSession()
            return nil
        }

        return session.accessToken
    }

    private func fetchPlaylists(
        accessToken: String
    ) async throws -> [SpotifyPlaylistReference] {
        var all: [SpotifyPlaylistReference] = []
        var offset = 0

        while true {
            var components = URLComponents(
                string: "https://api.spotify.com/v1/me/playlists"
            )
            components?.queryItems = [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: String(offset))
            ]

            guard let url = components?.url else {
                throw SpotifyPlaybackError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )

            let (data, response) =
                try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw SpotifyPlaybackError.invalidResponse
            }

            if http.statusCode == 401 {
                throw SpotifyPlaybackError.authorizationExpired
            }

            guard (200..<300).contains(http.statusCode) else {
                throw SpotifyPlaybackError.httpStatus(http.statusCode)
            }

            let page =
                try JSONDecoder().decode(
                    SpotifyPlaylistPage.self,
                    from: data
                )

            all.append(
                contentsOf:
                    page.items.map {
                        SpotifyPlaylistReference(
                            id: $0.id,
                            name: $0.name,
                            uri: $0.uri,
                            artworkURL:
                                $0.images.first.flatMap {
                                    URL(string: $0.url)
                                },
                            ownerName: $0.owner?.displayName
                        )
                    }
            )

            if page.next == nil || page.items.isEmpty {
                break
            }

            offset += page.items.count
        }

        return all
    }

    private func restoreSessionIfAvailable() {
        guard let data = readStoredSession(),
              let session =
                try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: SPTSession.self,
                    from: data
                ),
              let sessionManager
        else {
            connectionState = .disconnected
            return
        }

        sessionManager.session = session
        appRemote?.connectionParameters.accessToken = session.accessToken

        if session.isExpired {
            connectionState = .connecting
            sessionManager.renewSession()
        } else {
            connectionState = .connected
            Task { await refreshPlaylists() }
        }
    }

    private func storeSession(_ session: SPTSession) {
        guard let data =
                try? NSKeyedArchiver.archivedData(
                    withRootObject: session,
                    requiringSecureCoding: true
                )
        else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func readStoredSession() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(
            query as CFDictionary,
            &item
        ) == errSecSuccess else {
            return nil
        }

        return item as? Data
    }

    private func deleteStoredSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func applySession(_ session: SPTSession) {
        sessionManager?.session = session
        storeSession(session)
        appRemote?.connectionParameters.accessToken = session.accessToken
        connectionState = .connected
        lastErrorMessage = nil

        Task {
            await refreshPlaylists()
        }
    }

    private func isAuthorizationError(_ error: Error) -> Bool {
        guard let spotifyError =
                error as? SpotifyPlaybackError
        else {
            return false
        }

        if case .authorizationExpired = spotifyError {
            return true
        }

        return false
    }
}

extension SpotifyPlaybackStore: SPTSessionManagerDelegate {
    nonisolated func sessionManager(
        manager: SPTSessionManager,
        didInitiate session: SPTSession
    ) {
        Task { @MainActor in
            self.applySession(session)
            self.appRemote?.connect()
        }
    }

    nonisolated func sessionManager(
        manager: SPTSessionManager,
        didFailWith error: Error
    ) {
        Task { @MainActor in
            self.lastErrorMessage = error.localizedDescription
            self.connectionState = .error(error.localizedDescription)
        }
    }

    nonisolated func sessionManager(
        manager: SPTSessionManager,
        didRenew session: SPTSession
    ) {
        Task { @MainActor in
            self.applySession(session)
        }
    }
}

extension SpotifyPlaybackStore: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(
        _ appRemote: SPTAppRemote
    ) {
        Task { @MainActor in
            self.connectionState = .connected

            guard let uri = self.pendingPlaybackURI,
                  let playlist =
                    self.playlists.first(where: { $0.uri == uri })
                        ?? self.activePlaylist
            else {
                return
            }

            await self.playThroughConnectedRemote(
                playlist,
                appRemote: appRemote
            )
        }
    }

    nonisolated func appRemote(
        _ appRemote: SPTAppRemote,
        didFailConnectionAttemptWithError error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func appRemote(
        _ appRemote: SPTAppRemote,
        didDisconnectWithError error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct SpotifyPlaylistPage: Decodable {
    struct Item: Decodable {
        struct Image: Decodable {
            let url: String
        }

        struct Owner: Decodable {
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        let id: String
        let name: String
        let uri: String
        let images: [Image]
        let owner: Owner?
    }

    let items: [Item]
    let next: String?
}

private enum SpotifyPlaybackError: LocalizedError {
    case invalidResponse
    case authorizationExpired
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Spotify returned an invalid response."
        case .authorizationExpired:
            return "Spotify authorization has expired. Reconnect Spotify."
        case .httpStatus(let status):
            return "Spotify request failed (HTTP \(status))."
        }
    }
}
