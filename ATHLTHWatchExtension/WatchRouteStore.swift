import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchRouteStore: NSObject, ObservableObject {
    @Published private(set) var routes: [WatchRouteTransfer] = []
    @Published private(set) var connectionText = "Connecting to iPhone"
    @Published private(set) var companionLinked = false
    @Published private(set) var todayWorkout: WatchTodayWorkoutTransfer?
    @Published private(set) var preparedWorkout: WatchPreparedWorkoutTransfer?
    @Published private(set) var spotifyPlaybackState =
        WatchSpotifyPlaybackState.unavailable

    private let fileManager = FileManager.default
    private let todayWorkoutDefaultsKey =
        "athlth.watch.todayWorkout.v1"
    private let preparedWorkoutDefaultsKey =
        "athlth.watch.preparedWorkout.v1"
    private let preparedWorkoutSnapshotDateKey =
        "athlth.watch.preparedWorkoutSnapshotDate.v1"
    private var pendingWorkoutRouteID: UUID?
    private var latestTransportTimestampByKind:
        [String: TimeInterval] = [:]

    override init() {
        super.init()
        loadRoutes()
        loadTodayWorkout()
        loadPreparedWorkout()
        activateConnectivity()
    }

    func route(with id: UUID) -> WatchRouteTransfer? {
        routes.first(where: { $0.id == id })
    }

    private func activateConnectivity() {
        guard WCSession.isSupported() else {
            connectionText = "WatchConnectivity unavailable"
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    nonisolated private static func connectivityAck(
        probeID: String
    ) -> [String: Any] {
        [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.connectivityAck.rawValue,
            WatchTransferMetadataKey.probeID:
                probeID,
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]
    }

    nonisolated private static func makeTransferFallbackErrorHandler(
        payload: [String: Any]
    ) -> (Error) -> Void {
        { _ in
            WCSession.default.transferUserInfo(
                payload
            )
        }
    }

    nonisolated private static func makeEphemeralSpotifyErrorHandler()
        -> (Error) -> Void {
        { _ in
            // Ephemeral remote-control commands are intentionally dropped.
        }
    }

    private func markCompanionConnected() {
        companionLinked = true
        connectionText = "Connected to iPhone"
    }

    private func applyRouteSelection(
        rawRouteID: String
    ) {
        guard !rawRouteID.isEmpty,
              let routeID = UUID(uuidString: rawRouteID)
        else {
            pendingWorkoutRouteID = nil
            WatchWorkoutManager.shared
                .configurePlannedRoute(nil)
            return
        }

        pendingWorkoutRouteID = routeID

        if let route = route(with: routeID) {
            WatchWorkoutManager.shared
                .configurePlannedRoute(route)
        }
    }

    private func loadTodayWorkout() {
        guard let data =
                UserDefaults.standard.data(
                    forKey: todayWorkoutDefaultsKey
                ),
              let workout =
                try? JSONDecoder().decode(
                    WatchTodayWorkoutTransfer.self,
                    from: data
                )
        else {
            return
        }

        guard Calendar.current
                .isDateInToday(
                    workout.updatedAt
                )
        else {
            UserDefaults.standard
                .removeObject(
                    forKey:
                        todayWorkoutDefaultsKey
                )
            todayWorkout = nil
            return
        }

        todayWorkout = workout
    }

    private func storeTodayWorkout(
        _ workout: WatchTodayWorkoutTransfer?
    ) {
        todayWorkout = workout

        guard let workout else {
            UserDefaults.standard.removeObject(
                forKey: todayWorkoutDefaultsKey
            )
            return
        }

        guard let data =
                try? JSONEncoder().encode(workout)
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: todayWorkoutDefaultsKey
        )
    }

    private func loadPreparedWorkout() {
        guard let data =
                UserDefaults.standard.data(
                    forKey: preparedWorkoutDefaultsKey
                ),
              let workout =
                try? JSONDecoder().decode(
                    WatchPreparedWorkoutTransfer.self,
                    from: data
                )
        else {
            return
        }

        guard Date().timeIntervalSince(
                workout.updatedAt
            ) < 24 * 60 * 60
        else {
            UserDefaults.standard.removeObject(
                forKey: preparedWorkoutDefaultsKey
            )
            preparedWorkout = nil
            return
        }

        preparedWorkout = workout
    }

    private func storePreparedWorkout(
        _ workout: WatchPreparedWorkoutTransfer
    ) {
        preparedWorkout = workout

        guard let data =
                try? JSONEncoder().encode(workout)
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: preparedWorkoutDefaultsKey
        )
        UserDefaults.standard.set(
            workout.updatedAt,
            forKey: preparedWorkoutSnapshotDateKey
        )
    }

    func consumePreparedWorkout(
        _ id: UUID
    ) {
        guard preparedWorkout?.id == id else {
            return
        }

        preparedWorkout = nil
        UserDefaults.standard.removeObject(
            forKey: preparedWorkoutDefaultsKey
        )
    }

    private func applyPreparedWorkout(
        data: Data
    ) {
        guard let workout =
                try? JSONDecoder().decode(
                    WatchPreparedWorkoutTransfer.self,
                    from: data
                )
        else {
            return
        }

        let currentUpdatedAt =
            preparedWorkout?.updatedAt ??
            UserDefaults.standard.object(
                forKey:
                    preparedWorkoutSnapshotDateKey
            ) as? Date ??
            .distantPast

        // Immediate delivery and the durable queued delivery contain the same
        // payload. Only a strictly newer prepared workout may replace the one
        // already shown on Watch.
        guard workout.updatedAt >
                currentUpdatedAt
        else {
            return
        }

        storePreparedWorkout(workout)
    }

    private func requestTodayWorkoutSnapshot() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.todayWorkoutRequest.rawValue,
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler:
                    Self.makeTransferFallbackErrorHandler(
                        payload: payload
                    )
            )
        } else {
            WCSession.default.transferUserInfo(
                payload
            )
        }
    }

    func requestSpotifyPlaybackState() {
        sendSpotifyCommand(.requestState)
    }

    func sendSpotifyCommand(
        _ kind: WatchSpotifyCommandKind
    ) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(
                WatchSpotifyCommand(kind: kind)
              )
        else {
            // Spotify control is intentionally not queued. A delayed pause,
            // resume or skip arriving when the phone reconnects would control
            // music long after the user tapped the Watch.
            spotifyPlaybackState = .unavailable
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.spotifyCommand.rawValue,
            WatchTransferMetadataKey.payload:
                data,
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]

        WCSession.default.sendMessage(
            payload,
            replyHandler: nil,
            errorHandler:
                Self.makeEphemeralSpotifyErrorHandler()
        )
    }

    private func applyWorkoutConfiguration(
        kind rawKind: String,
        data: Data
    ) {
        guard let kind = WatchTransferKind(rawValue: rawKind)
        else {
            return
        }

        switch kind {
        case .audioCoachConfiguration:
            guard let configuration = try? JSONDecoder().decode(
                WatchAudioCoachConfiguration.self,
                from: data
            ) else {
                return
            }

            WatchWorkoutManager.shared
                .configureAudioCoach(configuration)

        case .runningWorkout:
            guard let workout = try? JSONDecoder().decode(
                WatchRunningWorkoutTransfer.self,
                from: data
            ) else {
                return
            }

            WatchWorkoutManager.shared
                .configureRunningWorkout(workout)

        case .ghostRace:
            guard let ghost = try? JSONDecoder().decode(
                WatchGhostRaceTransfer.self,
                from: data
            ) else {
                return
            }

            WatchWorkoutManager.shared
                .configureGhostRace(
                    ghost.points.isEmpty
                        ? nil
                        : ghost
                )

        case .liveSurfaceConfiguration:
            guard let configuration = try? JSONDecoder().decode(
                ATHLTHLiveWorkoutSurfaceConfiguration.self,
                from: data
            ) else {
                return
            }

            WatchWorkoutManager.shared
                .configureLiveSurface(configuration)

        case .liveSurfaceContext:
            guard let context = try? JSONDecoder().decode(
                ATHLTHLiveWorkoutContext.self,
                from: data
            ) else {
                return
            }

            WatchWorkoutManager.shared
                .configureLiveSurfaceContext(context)

        case .todayWorkout:
            guard let snapshot =
                    try? JSONDecoder().decode(
                        WatchTodaySnapshot.self,
                        from: data
                    )
            else {
                return
            }

            let currentUpdatedAt =
                todayWorkout?.updatedAt ??
                UserDefaults.standard.object(
                    forKey:
                        "athlth.watch.todayWorkoutSnapshotDate.v1"
                ) as? Date ??
                .distantPast

            // A newer snapshot always wins. This protects against older queued
            // transferUserInfo payloads arriving after a fresh clear/update.
            guard snapshot.updatedAt >= currentUpdatedAt else {
                return
            }

            UserDefaults.standard.set(
                snapshot.updatedAt,
                forKey:
                    "athlth.watch.todayWorkoutSnapshotDate.v1"
            )
            storeTodayWorkout(
                snapshot.workout
            )

        case .strengthSnapshot:
            guard let snapshot = try? JSONDecoder().decode(
                WatchStrengthSessionSnapshot.self,
                from: data
            ) else {
                return
            }

            WatchWorkoutManager.shared
                .configureStrengthSession(snapshot)

        case .spotifyPlaybackState:
            guard let playbackState = try? JSONDecoder().decode(
                WatchSpotifyPlaybackState.self,
                from: data
            ) else {
                return
            }

            spotifyPlaybackState = playbackState

        case .homeAssistantConfiguration:
            guard let configuration =
                    try? JSONDecoder().decode(
                        WatchHomeAssistantConfiguration.self,
                        from: data
                    )
            else {
                return
            }

            WatchHomeAssistantBridge.shared
                .apply(configuration)

        case .route,
             .workoutResult,
             .workoutCommand,
             .workoutRouteSelection,
             .todayWorkoutRequest,
             .strengthCommand,
             .spotifyCommand,
             .spotifyCredentials,
             .connectivityProbe,
             .connectivityAck:
            break
        }
    }

    private func applyWorkoutCommand(
        rawCommand: String,
        workoutID: UUID?
    ) {
        guard let command =
                WatchWorkoutCommand(rawValue: rawCommand)
        else {
            return
        }

        if let workoutID,
           let strengthSession =
                WatchWorkoutManager.shared
                    .strengthSession,
           strengthSession.workoutID !=
                workoutID {
            // A durable END from an older iPhone strength workout must never
            // terminate a newer Watch workout after reconnect.
            return
        }

        switch command {
        case .end:
            WatchWorkoutManager.shared.end()
        case .pause:
            WatchWorkoutManager.shared.pause()
        case .resume:
            WatchWorkoutManager.shared.resume()
        }
    }

    private var storageURL: URL? {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first?
        .appendingPathComponent(
            "ATHLTHWatchRoutes.json"
        )
    }

    private func loadRoutes() {
        guard
            let url = storageURL,
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(
                [WatchRouteTransfer].self,
                from: data
            )
        else {
            return
        }

        routes = decoded.sorted {
            $0.updatedAt > $1.updatedAt
        }
    }

    private func persistRoutes() {
        guard let url = storageURL else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(
                routes
            )
            try data.write(
                to: url,
                options: .atomic
            )
        } catch {
            connectionText =
                "Couldn't save route"
        }
    }

    private func importRouteData(
        _ data: Data
    ) {
        do {
            let route = try JSONDecoder().decode(
                WatchRouteTransfer.self,
                from: data
            )

            if let index = routes.firstIndex(
                where: { $0.id == route.id }
            ) {
                routes[index] = route
            } else {
                routes.insert(route, at: 0)
            }

            routes.sort {
                $0.updatedAt > $1.updatedAt
            }
            connectionText = "Route received"
            persistRoutes()

            if pendingWorkoutRouteID == route.id {
                WatchWorkoutManager.shared
                    .configurePlannedRoute(route)
            }
        } catch {
            connectionText =
                "Couldn't import route"
        }
    }

    private func applyActivationResult(
        activated: Bool,
        errorDescription: String?
    ) {
        if let errorDescription {
            connectionText = errorDescription
        } else {
            connectionText = activated
                ? "Ready for iPhone"
                : "Connecting to iPhone"

            if !activated {
                companionLinked = false
            }
        }
    }

    private func applyReachability(
        reachable: Bool,
        activated: Bool
    ) {
        if reachable {
            companionLinked = true
            connectionText =
                "Connected to iPhone"

            if WatchWorkoutManager.shared.kind
                == .strength,
               WatchWorkoutManager.shared.isActive {
                WatchWorkoutManager.shared
                    .requestStrengthSnapshot()
            }

            requestSpotifyPlaybackState()
        } else if activated {
            companionLinked = false
            connectionText =
                "iPhone not reachable"
            spotifyPlaybackState =
                .unavailable
        }
    }

    private func shouldAcceptTransport(
        kind: String,
        sentAt: TimeInterval?
    ) -> Bool {
        guard let sentAt else {
            // Keep compatibility with older iPhone builds.
            return true
        }

        if let latest =
                latestTransportTimestampByKind[
                    kind
                ],
           sentAt < latest {
            return false
        }

        latestTransportTimestampByKind[
            kind
        ] = sentAt
        return true
    }

    nonisolated private func receive(
        _ payload: [String: Any],
        replyHandler:
            (([String: Any]) -> Void)? = nil
    ) {
        guard let rawKind =
                payload[
                    WatchTransferMetadataKey.kind
                ] as? String
        else {
            replyHandler?([:])
            return
        }

        if rawKind ==
            WatchTransferKind
                .connectivityProbe.rawValue {
            let probeID =
                payload[
                    WatchTransferMetadataKey.probeID
                ] as? String
                ?? UUID().uuidString
            let ack =
                Self.connectivityAck(
                    probeID: probeID
                )

            if let replyHandler {
                replyHandler(ack)
            } else if WCSession.default
                .activationState == .activated {
                WCSession.default
                    .transferUserInfo(ack)
            }

            Task { @MainActor [weak self] in
                self?.markCompanionConnected()
            }
            return
        }

        if rawKind ==
            WatchPreparedWorkoutTransport.kind,
           let data =
                payload[
                    WatchTransferMetadataKey.payload
                ] as? Data {
            let sentAt =
                payload[
                    WatchTransferMetadataKey.sentAt
                ] as? TimeInterval

            Task { @MainActor [weak self] in
                guard let self,
                      self.shouldAcceptTransport(
                        kind: rawKind,
                        sentAt: sentAt
                      )
                else {
                    return
                }

                self.applyPreparedWorkout(
                    data: data
                )
            }

            replyHandler?([:])
            return
        }

        if rawKind ==
            WatchTransferKind
                .workoutRouteSelection.rawValue {
            let rawRouteID =
                payload[
                    WatchTransferMetadataKey.routeID
                ] as? String
                ?? ""

            let sentAt =
                payload[
                    WatchTransferMetadataKey.sentAt
                ] as? TimeInterval

            Task { @MainActor [weak self] in
                guard let self,
                      self.shouldAcceptTransport(
                        kind: rawKind,
                        sentAt: sentAt
                      )
                else {
                    return
                }

                self.applyRouteSelection(
                    rawRouteID: rawRouteID
                )
            }

            replyHandler?([:])
            return
        }

        if let data =
            payload[
                WatchTransferMetadataKey.payload
            ] as? Data,
           let transferKind =
            WatchTransferKind(
                rawValue: rawKind
            ),
           transferKind ==
                .audioCoachConfiguration ||
           transferKind == .runningWorkout ||
           transferKind == .ghostRace ||
           transferKind == .liveSurfaceConfiguration ||
           transferKind == .liveSurfaceContext ||
           transferKind == .todayWorkout ||
           transferKind == .strengthSnapshot ||
           transferKind == .spotifyPlaybackState ||
           transferKind == .homeAssistantConfiguration {
            let sentAt =
                payload[
                    WatchTransferMetadataKey.sentAt
                ] as? TimeInterval

            Task { @MainActor [weak self] in
                guard let self,
                      self.shouldAcceptTransport(
                        kind: rawKind,
                        sentAt: sentAt
                      )
                else {
                    return
                }

                self.applyWorkoutConfiguration(
                    kind: rawKind,
                    data: data
                )
            }

            replyHandler?([:])
            return
        }

        if rawKind ==
            WatchTransferKind
                .workoutCommand.rawValue,
           let rawCommand =
            payload[
                WatchTransferMetadataKey.command
            ] as? String {
            let sentAt =
                payload[
                    WatchTransferMetadataKey.sentAt
                ] as? TimeInterval
            let workoutID =
                (
                    payload[
                        WatchTransferMetadataKey
                            .workoutID
                    ] as? String
                )
                .flatMap(UUID.init(uuidString:))

            Task { @MainActor [weak self] in
                guard let self,
                      self.shouldAcceptTransport(
                        kind: rawKind,
                        sentAt: sentAt
                      )
                else {
                    return
                }

                self.applyWorkoutCommand(
                    rawCommand: rawCommand,
                    workoutID: workoutID
                )
            }
        }

        replyHandler?([:])
    }
}

extension WatchRouteStore:
    WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith
            activationState:
                WCSessionActivationState,
        error: Error?
    ) {
        let activated =
            activationState == .activated
        let errorDescription =
            error?.localizedDescription

        Task { @MainActor [weak self] in
            self?.applyActivationResult(
                activated: activated,
                errorDescription:
                    errorDescription
            )
        }

        if activated {
            session.transferUserInfo(
                Self.connectivityAck(
                    probeID: "watch-launch"
                )
            )

            Task { @MainActor [weak self] in
                self?.requestTodayWorkoutSnapshot()
                self?.requestSpotifyPlaybackState()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage
            message: [String: Any]
    ) {
        receive(message)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage
            message: [String: Any],
        replyHandler:
            @escaping ([String: Any]) -> Void
    ) {
        receive(
            message,
            replyHandler: replyHandler
        )
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo
            userInfo: [String: Any] = [:]
    ) {
        receive(userInfo)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext
            applicationContext:
                [String: Any]
    ) {
        receive(applicationContext)
    }

    nonisolated func
        sessionReachabilityDidChange(
            _ session: WCSession
        ) {
        let reachable =
            session.isReachable
        let activated =
            session.activationState
                == .activated

        Task { @MainActor [weak self] in
            self?.applyReachability(
                reachable: reachable,
                activated: activated
            )
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceive file: WCSessionFile
    ) {
        guard
            file.metadata?[
                WatchTransferMetadataKey.kind
            ] as? String
                == WatchTransferKind
                    .route.rawValue
        else {
            return
        }

        guard let data =
                try? Data(
                    contentsOf: file.fileURL
                )
        else {
            Task { @MainActor [weak self] in
                self?.connectionText =
                    "Couldn't import route"
            }
            return
        }

        Task { @MainActor [weak self] in
            self?.importRouteData(data)
        }
    }
}
