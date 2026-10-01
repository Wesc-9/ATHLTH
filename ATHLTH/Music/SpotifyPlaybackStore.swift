import CryptoKit
import Foundation
import Security
import UIKit
@preconcurrency import AuthenticationServices
@preconcurrency import SpotifyiOS

struct SpotifyPlaylistReference: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var uri: String
    var artworkURL: URL?
    var ownerName: String?
}

private struct SpotifyPKCESession: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct SpotifyTokenErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum SpotifyConnectionState: Equatable {
    case unavailable
    case disconnected
    case connecting
    case connected
    case error(String)

    var title: String {
        switch self {
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "Needs setup",
                norwegian: "Må konfigureres"
            )
        case .disconnected:
            return ATHLTHLocalization.choose(
                english: "Not connected",
                norwegian: "Ikke tilkoblet"
            )
        case .connecting:
            return ATHLTHLocalization.choose(
                english: "Connecting…",
                norwegian: "Kobler til…"
            )
        case .connected:
            return ATHLTHLocalization.choose(
                english: "Connected",
                norwegian: "Tilkoblet"
            )
        case .error:
            return ATHLTHLocalization.choose(
                english: "Connection issue",
                norwegian: "Tilkoblingsproblem"
            )
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
    private let pkceKeychainAccount = "spotify-pkce-session"

    private var pendingPlaybackURI: String?
    private var pendingPlaybackPlaylist: SpotifyPlaylistReference?
    private var pkceSession: SpotifyPKCESession?
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private var pkceCodeVerifier: String?
    private var pkceAuthorizationState: String?
    private var pkceAuthorizationStarted = false

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
        guard !clientID.isEmpty,
              let url = URL(string: redirectURI),
              let scheme = url.scheme,
              !scheme.isEmpty,
              scheme == scheme.lowercased(),
              redirectURI == redirectURI.lowercased()
        else {
            return false
        }

        return true
    }

    var redirectURIForDiagnostics: String {
        redirectURI
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var setupMessage: String? {
        guard !clientID.isEmpty else {
            return "Spotify client ID is missing from this build."
        }

        guard let url = URL(string: redirectURI),
              let scheme = url.scheme,
              !scheme.isEmpty
        else {
            return "Spotify redirect URI is invalid."
        }

        guard scheme == scheme.lowercased(),
              redirectURI == redirectURI.lowercased()
        else {
            return "Spotify requires the iOS redirect URI to use lowercase characters."
        }

        return nil
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
        guard isConfigured else {
            connectionState = .unavailable
            lastErrorMessage = setupMessage
            return
        }

        // Use Authorization Code + PKCE as the primary authorization path.
        // Spotify iOS SDK 5.0.1 can return unknown_error from app-switch auth
        // even when the callback itself succeeds. App Remote remains the
        // playback transport after ATHLTH has obtained a valid access token.
        connectionState = .connecting
        lastErrorMessage = nil
        sessionManager?.session = nil
        deleteStoredSession()
        pkceAuthorizationStarted = false
        beginPKCEAuthorizationIfNeeded()
    }

    func applicationDidBecomeActive() {
        guard let appRemote,
              !appRemote.isConnected,
              pendingPlaybackPlaylist != nil ||
                activePlaylist != nil
        else {
            return
        }

        Task {
            guard let token =
                    await accessTokenForRequest()
            else {
                return
            }

            appRemote
                .connectionParameters
                .accessToken = token
            appRemote.connect()
        }
    }

    func applicationWillResignActive() {
        guard let appRemote,
              appRemote.isConnected
        else {
            return
        }

        appRemote.disconnect()
    }

    func disconnect() {
        appRemote?.disconnect()
        sessionManager?.session = nil
        webAuthenticationSession?.cancel()
        webAuthenticationSession = nil
        pkceCodeVerifier = nil
        pkceAuthorizationState = nil
        pkceSession = nil
        pkceAuthorizationStarted = false
        deleteStoredSession()
        deleteStoredPKCESession()
        playlists = []
        activePlaylist = nil
        pendingPlaybackURI = nil
        pendingPlaybackPlaylist = nil
        lastStartedAt = nil
        lastErrorMessage = nil
        connectionState = isConfigured ? .disconnected : .unavailable
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard isConfigured else { return false }

        // App Remote app-switch callbacks are handled first. Spotify iOS SDK
        // 5.0.1 can return unknown_error without an access token even after a
        // successful switch. When ATHLTH already has a PKCE session, ignore
        // that broken auth payload and reconnect App Remote with the known
        // valid token instead.
        if let appRemote,
           let parameters =
                appRemote.authorizationParameters(
                    from: url
                ) {
            if let token =
                    parameters[
                        SPTAppRemoteAccessTokenKey
                    ],
               !token.isEmpty {
                appRemote
                    .connectionParameters
                    .accessToken = token
                appRemote.connect()
                return true
            }

            if let message =
                    parameters[
                        SPTAppRemoteErrorDescriptionKey
                    ] {
                if let token =
                        pkceSession?
                            .accessToken,
                   !token.isEmpty {
                    appRemote
                        .connectionParameters
                        .accessToken = token
                    lastErrorMessage = nil
                    appRemote.connect()
                } else {
                    pkceAuthorizationStarted =
                        false
                    if shouldFallbackToPKCE(
                        message
                    ) {
                        beginPKCEAuthorizationIfNeeded()
                    } else {
                        lastErrorMessage =
                            message
                        connectionState =
                            .error(message)
                    }
                }
                return true
            }
        }

        // Kept only for callbacks from older ATHLTH installations. New account
        // connections use PKCE and do not initiate SPTSessionManager auth.
        if let sessionManager,
           sessionManager.application(
                UIApplication.shared,
                open: url,
                options: [:]
           ) {
            return true
        }

        return false
    }

    func refreshPlaylists() async {
        guard isConfigured else {
            connectionState = .unavailable
            return
        }

        guard let token = await accessTokenForRequest() else {
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
        pendingPlaybackPlaylist = playlist

        guard let appRemote else {
            pendingPlaybackURI = nil
            pendingPlaybackPlaylist = nil
            lastErrorMessage =
                "Spotify playback control is unavailable in this build."
            return
        }

        guard let token =
                await accessTokenForRequest()
        else {
            connectionState = .disconnected
            lastErrorMessage =
                "Reconnect Spotify before starting linked playback."
            pendingPlaybackURI = nil
            pendingPlaybackPlaylist = nil
            return
        }

        appRemote.connectionParameters
            .accessToken = token

        if appRemote.isConnected {
            await playThroughConnectedRemote(
                playlist,
                appRemote: appRemote
            )
            return
        }

        // Wake Spotify and return through the registered callback. The callback
        // is NOT trusted for account authorization anymore; ATHLTH already owns
        // a valid PKCE token and reuses it if Spotify returns unknown_error.
        let installed =
            await appRemote.authorizeAndPlayURI(
                playlist.uri
            )

        if !installed {
            lastErrorMessage =
                "Spotify is not installed on this iPhone."
            pendingPlaybackURI = nil
            pendingPlaybackPlaylist = nil
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
                    self?.pendingPlaybackPlaylist = nil
                    continuation.resume()
                }
            }
        }
    }

    private func accessTokenForRequest() async -> String? {
        if var pkceSession {
            if pkceSession.isExpired {
                guard let refreshToken = pkceSession.refreshToken else {
                    self.pkceSession = nil
                    deleteStoredPKCESession()
                    connectionState = .disconnected
                    return nil
                }

                do {
                    let refreshed = try await refreshPKCESession(
                        refreshToken: refreshToken
                    )
                    pkceSession.accessToken = refreshed.accessToken
                    pkceSession.refreshToken =
                        refreshed.refreshToken ?? refreshToken
                    pkceSession.expiresAt = Date().addingTimeInterval(
                        TimeInterval(refreshed.expiresIn)
                    )
                    applyPKCESession(pkceSession, connectRemote: false)
                } catch {
                    self.pkceSession = nil
                    deleteStoredPKCESession()
                    connectionState = .disconnected
                    lastErrorMessage =
                        "Spotify authorization expired. Reconnect Spotify."
                    return nil
                }
            }

            return self.pkceSession?.accessToken
        }

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

    private func beginPKCEAuthorizationIfNeeded() {
        guard isConfigured,
              !pkceAuthorizationStarted,
              webAuthenticationSession == nil
        else {
            return
        }

        pkceAuthorizationStarted = true
        connectionState = .connecting
        lastErrorMessage =
            "Opening secure Spotify sign-in…"

        let verifier = Self.makeCodeVerifier()
        let state = UUID().uuidString
        pkceCodeVerifier = verifier
        pkceAuthorizationState = state

        guard let challenge = Self.codeChallenge(for: verifier),
              let callbackScheme =
                URL(string: redirectURI)?
                    .scheme
        else {
            pkceAuthorizationStarted = false
            connectionState =
                .error(
                    "Could not prepare Spotify login."
                )
            lastErrorMessage =
                "Could not prepare Spotify login."
            return
        }

        var components = URLComponents(
            string: "https://accounts.spotify.com/authorize"
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(
                name: "scope",
                value: [
                    "app-remote-control",
                    "playlist-read-private",
                    "playlist-read-collaborative",
                    "user-read-playback-state",
                    "user-modify-playback-state"
                ].joined(separator: " ")
            ),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authorizationURL =
                components?.url
        else {
            pkceAuthorizationStarted = false
            connectionState =
                .error(
                    "Could not prepare Spotify login."
                )
            lastErrorMessage =
                "Could not prepare Spotify login."
            return
        }

        let authSession = ASWebAuthenticationSession(
            url: authorizationURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.completePKCEAuthorization(
                    callbackURL: callbackURL,
                    error: error,
                    verifier: verifier,
                    expectedState: state
                )
            }
        }

        authSession.presentationContextProvider = self
        authSession.prefersEphemeralWebBrowserSession = false
        webAuthenticationSession = authSession

        if !authSession.start() {
            webAuthenticationSession = nil
            pkceAuthorizationStarted = false
            connectionState =
                .error(
                    "Could not open Spotify login."
                )
            lastErrorMessage =
                "Could not open Spotify login."
        }
    }

    private func completePKCEAuthorization(
        callbackURL: URL?,
        error: Error?,
        verifier: String,
        expectedState: String
    ) async {
        defer {
            webAuthenticationSession = nil
            pkceCodeVerifier = nil
            pkceAuthorizationState = nil
            pkceAuthorizationStarted = false
        }

        if let error {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
               nsError.code ==
                ASWebAuthenticationSessionError.canceledLogin.rawValue {
                connectionState = .disconnected
                lastErrorMessage = nil
            } else {
                connectionState = .error(error.localizedDescription)
                lastErrorMessage = error.localizedDescription
            }
            return
        }

        guard let callbackURL else {
            connectionState =
                .error(
                    "Spotify did not return to ATHLTH."
                )
            lastErrorMessage =
                "Spotify did not return a callback URL to ATHLTH."
            return
        }

        guard callbackMatchesConfiguredRedirect(
            callbackURL
        ) else {
            connectionState =
                .error(
                    "Spotify returned an unexpected callback."
                )
            lastErrorMessage =
                "Spotify returned an unexpected callback location. Expected \(redirectURI), received \(callbackLocationForDiagnostics(callbackURL))."
            return
        }

        guard let components = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        ) else {
            connectionState =
                .error(
                    "Spotify callback could not be read."
                )
            lastErrorMessage =
                "Spotify returned a callback URL that ATHLTH could not parse."
            return
        }

        let values = Dictionary(
            uniqueKeysWithValues:
                (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
        )

        if let spotifyError = values["error"], !spotifyError.isEmpty {
            let message =
                values["error_description"]?.isEmpty == false
                ? values["error_description"]!
                : spotifyError
            connectionState = .error(message)
            lastErrorMessage = message
            return
        }

        guard values["state"] == expectedState,
              let code = values["code"],
              !code.isEmpty
        else {
            connectionState = .error("Spotify login could not be verified.")
            lastErrorMessage = "Spotify login could not be verified."
            return
        }

        do {
            let token = try await exchangeAuthorizationCode(
                code,
                verifier: verifier
            )
            let session = SpotifyPKCESession(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(
                    TimeInterval(token.expiresIn)
                )
            )
            // Account authorization is complete here. App Remote is connected
            // lazily only when ATHLTH actually needs playback control.
            applyPKCESession(
                session,
                connectRemote: false
            )
            await refreshPlaylists()
        } catch {
            connectionState = .error(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    private func callbackMatchesConfiguredRedirect(
        _ callbackURL: URL
    ) -> Bool {
        guard let expected =
                URLComponents(
                    string: redirectURI
                ),
              let received =
                URLComponents(
                    url: callbackURL,
                    resolvingAgainstBaseURL:
                        false
                )
        else {
            return false
        }

        let expectedScheme =
            expected.scheme?
                .lowercased()
        let receivedScheme =
            received.scheme?
                .lowercased()

        // Some iOS/browser callback paths can be represented either as a
        // custom-scheme host ("scheme://callback") or as a path
        // ("scheme:/callback"). Treat those as the same logical callback
        // location while still requiring our exact scheme. OAuth state + PKCE
        // below remain the security checks for the authorization response.
        return expectedScheme == receivedScheme &&
            Self.normalizedCallbackLocation(
                expected
            ) ==
            Self.normalizedCallbackLocation(
                received
            )
    }

    private static func normalizedCallbackLocation(
        _ components: URLComponents
    ) -> String {
        let host =
            components.host?
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "/"
                    )
                )
                .lowercased() ?? ""

        let path =
            components.path
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "/"
                    )
                )
                .lowercased()

        return [host, path]
            .filter {
                !$0.isEmpty
            }
            .joined(separator: "/")
    }

    private func callbackLocationForDiagnostics(
        _ callbackURL: URL
    ) -> String {
        guard let components =
                URLComponents(
                    url: callbackURL,
                    resolvingAgainstBaseURL:
                        false
                )
        else {
            return "<unreadable>"
        }

        let scheme =
            components.scheme ?? "<no-scheme>"
        let host =
            components.host ?? "<no-host>"

        return "\(scheme)://\(host)\(components.path)"
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        verifier: String
    ) async throws -> SpotifyTokenResponse {
        try await requestSpotifyToken([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: verifier)
        ])
    }

    private func refreshPKCESession(
        refreshToken: String
    ) async throws -> SpotifyTokenResponse {
        try await requestSpotifyToken([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientID)
        ])
    }

    private func requestSpotifyToken(
        _ fields: [URLQueryItem]
    ) async throws -> SpotifyTokenResponse {
        guard let url = URL(
            string: "https://accounts.spotify.com/api/token"
        ) else {
            throw SpotifyPlaybackError.invalidResponse
        }

        var form = URLComponents()
        form.queryItems = fields

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody =
            form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) =
            try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SpotifyPlaybackError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if let apiError =
                try? JSONDecoder().decode(
                    SpotifyTokenErrorResponse.self,
                    from: data
                ) {
                let message =
                    apiError.errorDescription ?? apiError.error
                throw SpotifyPlaybackError.authorizationMessage(message)
            }
            throw SpotifyPlaybackError.httpStatus(http.statusCode)
        }

        return try JSONDecoder().decode(
            SpotifyTokenResponse.self,
            from: data
        )
    }

    private func shouldFallbackToPKCE(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("unknown_error")
            || normalized.contains("unknown error")
            || normalized.contains("no access token")
    }

    private func shouldFallbackToPKCE(_ error: Error) -> Bool {
        let nsError = error as NSError
        let details = [
            error.localizedDescription,
            nsError.domain,
            String(describing: nsError.userInfo)
        ].joined(separator: " ")
        return shouldFallbackToPKCE(details)
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        )
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(
        for verifier: String
    ) -> String? {
        guard let data = verifier.data(using: .utf8) else {
            return nil
        }
        return Data(SHA256.hash(data: data))
            .base64URLEncodedString()
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
        if let storedPKCE = readStoredPKCESession() {
            pkceSession = storedPKCE
            appRemote?.connectionParameters.accessToken =
                storedPKCE.accessToken

            if storedPKCE.isExpired {
                connectionState = .connecting
                Task {
                    if await accessTokenForRequest() != nil {
                        connectionState = .connected
                        await refreshPlaylists()
                    }
                }
            } else {
                connectionState = .connected
                Task { await refreshPlaylists() }
            }
            return
        }

        // Older ATHLTH builds stored SPTSession credentials from the SDK
        // authorization flow. Do not renew those after Spotify's OAuth
        // migration; reconnect once using PKCE instead.
        if readStoredSession() != nil {
            deleteStoredSession()
        }

        connectionState = .disconnected
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

    private func storePKCESession(_ session: SpotifyPKCESession) {
        guard let data = try? JSONEncoder().encode(session) else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: pkceKeychainAccount
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

    private func readStoredPKCESession() -> SpotifyPKCESession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: pkceKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
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

        return try? JSONDecoder().decode(
            SpotifyPKCESession.self,
            from: data
        )
    }

    private func deleteStoredPKCESession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: pkceKeychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func applyPKCESession(
        _ session: SpotifyPKCESession,
        connectRemote: Bool
    ) {
        pkceSession = session
        storePKCESession(session)
        sessionManager?.session = nil
        deleteStoredSession()
        appRemote?.connectionParameters.accessToken = session.accessToken
        connectionState = .connected
        lastErrorMessage = nil

        if connectRemote {
            appRemote?.connect()
        }
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
            self.sessionManager?.session = nil
            self.deleteStoredSession()
            self.pkceAuthorizationStarted = false
            self.lastErrorMessage =
                "Spotify sign-in needs to be refreshed securely."
            self.beginPKCEAuthorizationIfNeeded()
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
            self.lastErrorMessage = nil

            guard let playlist =
                    self.pendingPlaybackPlaylist ??
                    self.activePlaylist
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

extension SpotifyPlaybackStore:
    ASWebAuthenticationPresentationContextProviding
{
    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }

            if let keyWindow = scenes
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) {
                return keyWindow
            }

            if let window = scenes.first?.windows.first {
                return window
            }

            return ASPresentationAnchor()
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum SpotifyPlaybackError: LocalizedError {
    case invalidResponse
    case authorizationExpired
    case authorizationMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Spotify returned an invalid response."
        case .authorizationExpired:
            return "Spotify authorization has expired. Reconnect Spotify."
        case .authorizationMessage(let message):
            return message
        case .httpStatus(let status):
            return "Spotify request failed (HTTP \(status))."
        }
    }
}
