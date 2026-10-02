import Combine
import Foundation
@preconcurrency import HealthKit
@preconcurrency import WatchConnectivity

enum AppleWatchConnectionState: Equatable {
    case checking
    case unsupported
    case notPaired
    case appNotInstalled
    case ready

    var isReady: Bool {
        self == .ready
    }

    var subtitle: String {
        switch self {
        case .checking:
            return "Checking Apple Watch"
        case .unsupported:
            return "Apple Watch connection is unavailable on this device"
        case .notPaired:
            return "No paired Apple Watch found"
        case .appNotInstalled:
            return "ATHLTH Watch app is not installed yet"
        case .ready:
            return "ATHLTH Watch app installed"
        }
    }
}

enum AppleWatchWorkoutLaunchError: LocalizedError {
    case watchUnavailable

    var errorDescription: String? {
        switch self {
        case .watchUnavailable:
            return "Apple Watch is not ready to start an ATHLTH workout."
        }
    }
}

private struct IncomingWatchPayload: Sendable {
    let kind: String?
    let probeID: String?
    let data: Data?

    init(_ payload: [String: Any]) {
        kind = payload[WatchTransferMetadataKey.kind] as? String
        probeID = payload[WatchTransferMetadataKey.probeID] as? String
        data = payload[WatchTransferMetadataKey.payload] as? Data
    }
}

@MainActor
final class AppleWatchConnectionStore: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var state: AppleWatchConnectionState = .checking
    @Published private(set) var lastCompletedWorkout: WatchWorkoutResult?
    @Published private(set) var pendingWorkoutResults:
        [WatchWorkoutResult] = []
    @Published private(set) var lastStrengthCommand: WatchStrengthCommand?
    @Published private(set) var pendingStrengthCommands:
        [WatchStrengthCommand] = []
    @Published private(set) var lastSpotifyCommand: WatchSpotifyCommand?
    @Published private(set) var workoutLaunchInProgress = false
    @Published private(set) var workoutLaunchError: String?

    // Diagnostics are intentionally separate from isReady. Apple's
    // isReachable only means the counterpart app is currently active;
    // it is not an installation check.
    @Published private(set) var paired: Bool?
    @Published private(set) var watchAppInstalled: Bool?
    @Published private(set) var reachable = false
    @Published private(set) var activationStateText = "Not activated"
    @Published private(set) var lastVerifiedAt: Date?
    @Published private(set) var verificationInProgress = false
    @Published private(set) var connectivityError: String?

    private let healthStore = HKHealthStore()
    private var verificationRequested = true
    private var lastProbeID: String?
    private var handledWorkoutResultIDs:
        [UUID] = []
    private var handledStrengthCommandIDs:
        [UUID] = []
    private static let handledWorkoutResultsKey =
        "athlth.watch.handledWorkoutResultIDs.v1"
    private static let handledStrengthCommandsKey =
        "athlth.watch.handledStrengthCommandIDs.v1"
    private static let pendingStrengthCommandsKey =
        "athlth.watch.pendingStrengthCommands.v1"
    private static let pendingWorkoutResultsKey =
        "athlth.watch.pendingWorkoutResults.v1"
    private var lastSpotifyCommandSentAt:
        Date = .distantPast
    private var latestTodaySnapshot =
        WatchTodaySnapshot(
            workout: nil,
            updatedAt: .distantPast
        )

    var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    override init() {
        if let stored =
                UserDefaults.standard
                    .stringArray(
                        forKey:
                            Self.handledWorkoutResultsKey
                    ) {
            handledWorkoutResultIDs =
                stored
                    .compactMap(
                        UUID.init(uuidString:)
                    )
        }

        if let stored =
                UserDefaults.standard
                    .stringArray(
                        forKey:
                            Self.handledStrengthCommandsKey
                    ) {
            handledStrengthCommandIDs =
                stored
                    .compactMap(
                        UUID.init(uuidString:)
                    )
        }

        if let data =
                UserDefaults.standard.data(
                    forKey:
                        Self.pendingWorkoutResultsKey
                ),
           let pending =
                try? JSONDecoder().decode(
                    [WatchWorkoutResult].self,
                    from: data
                ) {
            pendingWorkoutResults =
                pending
                    .filter {
                        !handledWorkoutResultIDs
                            .contains($0.id)
                    }
                    .sorted {
                        $0.endedAt < $1.endedAt
                    }
            lastCompletedWorkout =
                pendingWorkoutResults.first
        }

        if let data =
                UserDefaults.standard.data(
                    forKey:
                        Self.pendingStrengthCommandsKey
                ),
           let pending =
                try? JSONDecoder().decode(
                    [WatchStrengthCommand].self,
                    from: data
                ) {
            pendingStrengthCommands =
                pending
                    .filter {
                        !handledStrengthCommandIDs
                            .contains($0.id)
                    }
                    .sorted {
                        $0.sentAt < $1.sentAt
                    }
            lastStrengthCommand =
                pendingStrengthCommands.first
        }

        super.init()
        // WatchConnectivity tracks Apple Watch availability independently
        // of workout capture. The user chooses iPhone or Apple Watch when
        // starting each workout; this store only reports Watch readiness.
    }

    var isReady: Bool {
        state.isReady
    }

    var statusText: String {
        switch state {
        case .checking:
            return "Checking Apple Watch"
        case .unsupported:
            return "Apple Watch unavailable"
        case .notPaired:
            return "No paired Apple Watch"
        case .appNotInstalled:
            return "ATHLTH Watch app not installed"
        case .ready:
            if lastVerifiedAt != nil {
                return "ATHLTH Watch connection verified"
            }
            if reachable {
                return "ATHLTH Watch app installed · active now"
            }
            return "ATHLTH Watch app installed"
        }
    }

    func connect() {
        refreshStatus(requestVerification: true)
    }

    func refreshStatus() {
        refreshStatus(requestVerification: false)
    }

    private func refreshStatus(requestVerification: Bool) {
        if requestVerification {
            verificationRequested = true
        }

        guard let session else {
            publishSnapshot(
                state: .unsupported,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Unsupported"
            )
            return
        }

        // WCSession's pairing and installation properties are only valid
        // after successful activation. Never classify a Watch while the
        // session is inactive or still activating.
        session.delegate = self

        switch session.activationState {
        case .activated:
            evaluate(session)

        case .notActivated:
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Activating"
            )
            session.activate()

        case .inactive:
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Inactive"
            )

        @unknown default:
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Unknown"
            )
        }
    }

    @MainActor
    func startWorkoutOnWatch(_ kind: WatchWorkoutKind) async throws {
        guard isReady else {
            throw AppleWatchWorkoutLaunchError.watchUnavailable
        }

        workoutLaunchInProgress = true
        workoutLaunchError = nil
        defer { workoutLaunchInProgress = false }

        let configuration = HKWorkoutConfiguration()

        switch kind {
        case .running:
            configuration.activityType = .running
        case .walking:
            configuration.activityType = .walking
        case .strength:
            configuration.activityType = .traditionalStrengthTraining
        case .hiit:
            configuration.activityType = .highIntensityIntervalTraining
        case .functional:
            configuration.activityType = .functionalStrengthTraining
        case .cycling:
            configuration.activityType = .cycling
        case .rowing:
            configuration.activityType = .rowing
        case .stairClimbing:
            configuration.activityType = .stairClimbing
        case .yoga:
            configuration.activityType = .yoga
        case .other:
            configuration.activityType = .other
        }

        configuration.locationType = kind.usesOutdoorLocation
            ? .outdoor
            : .indoor

        // Queue the current display preferences before the Watch workout
        // starts. Delivery is independent of the workout launch itself.
        sendLiveSurfaceConfiguration(
            ATHLTHLiveWorkoutPreferencesStore.load()
        )
        sendLiveSurfaceContext(
            ATHLTHLiveWorkoutContextStore.load()
        )

        do {
            try await healthStore.startWatchApp(toHandle: configuration)
        } catch {
            workoutLaunchError = error.localizedDescription
            throw error
        }
    }

    func sendWorkoutRouteSelection(
        _ routeID: UUID?
    ) {
        guard
            let session,
            session.activationState == .activated
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.workoutRouteSelection.rawValue,
            WatchTransferMetadataKey.routeID:
                routeID?.uuidString ?? "",
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler: Self.makeDurableMessageErrorHandler(
                    session: session,
                    payload: payload,
                    store: self
                )
            )
        } else {
            session.transferUserInfo(payload)
        }
    }

    func sendAudioCoachConfiguration(
        _ configuration: WatchAudioCoachConfiguration
    ) {
        sendWatchPayload(
            configuration,
            kind: .audioCoachConfiguration
        )
    }

    func sendRunningWorkout(
        _ workout: WatchRunningWorkoutTransfer
    ) {
        sendWatchPayload(
            workout,
            kind: .runningWorkout
        )
    }

    func sendGhostRace(
        _ ghost: WatchGhostRaceTransfer
    ) {
        sendWatchPayload(
            ghost,
            kind: .ghostRace
        )
    }

    func sendTodayWorkout(
        _ workout: WatchTodayWorkoutTransfer?
    ) {
        let snapshot =
            WatchTodaySnapshot(
                workout: workout,
                updatedAt: Date()
            )
        latestTodaySnapshot = snapshot
        sendWatchPayload(
            snapshot,
            kind: .todayWorkout
        )
    }

    func sendLiveSurfaceConfiguration(
        _ configuration: ATHLTHLiveWorkoutSurfaceConfiguration
    ) {
        ATHLTHLiveWorkoutPreferencesStore.save(configuration)

        sendWatchPayload(
            configuration,
            kind: .liveSurfaceConfiguration
        )
    }

    func sendLiveSurfaceContext(
        _ context: ATHLTHLiveWorkoutContext
    ) {
        ATHLTHLiveWorkoutContextStore.save(context)

        sendWatchPayload(
            context,
            kind: .liveSurfaceContext
        )
    }

    func sendSpotifyPlaybackState(
        _ playbackState: WatchSpotifyPlaybackState
    ) {
        sendWatchPayload(
            playbackState,
            kind: .spotifyPlaybackState
        )
    }

    func clearGhostRace() {
        sendGhostRace(
            WatchGhostRaceTransfer(
                title: "",
                referenceDuration: 0,
                routeDistanceMeters: 0,
                points: []
            )
        )
    }

    func sendStrengthSnapshot(
        _ snapshot: WatchStrengthSessionSnapshot
    ) {
        guard
            let session,
            session.activationState == .activated,
            let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.strengthSnapshot.rawValue,
            WatchTransferMetadataKey.payload: data,
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]

        // applicationContext keeps only the newest strength state, which is
        // exactly what reconnect needs. Avoid queueing stale set snapshots.
        try? session.updateApplicationContext(
            payload
        )

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler: nil
            )
        }
    }

    func clearStrengthCommand() {
        guard let command =
                lastStrengthCommand
        else {
            return
        }

        consumeStrengthCommand(
            command.id
        )
    }

    func consumeStrengthCommand(
        _ id: UUID
    ) {
        pendingStrengthCommands
            .removeAll {
                $0.id == id
            }

        if !handledStrengthCommandIDs
            .contains(id) {
            handledStrengthCommandIDs
                .append(id)

            if handledStrengthCommandIDs
                .count > 256 {
                handledStrengthCommandIDs =
                    Array(
                        handledStrengthCommandIDs
                            .suffix(128)
                    )
            }
        }

        persistStrengthCommandState()
        lastStrengthCommand =
            pendingStrengthCommands.first
    }

    private func persistStrengthCommandState() {
        UserDefaults.standard.set(
            handledStrengthCommandIDs
                .map(\.uuidString),
            forKey:
                Self.handledStrengthCommandsKey
        )

        if let data =
                try? JSONEncoder().encode(
                    pendingStrengthCommands
                ) {
            UserDefaults.standard.set(
                data,
                forKey:
                    Self.pendingStrengthCommandsKey
            )
        }
    }

    func clearSpotifyCommand() {
        lastSpotifyCommand = nil
    }

    private func sendWatchPayload<T: Encodable>(
        _ value: T,
        kind: WatchTransferKind
    ) {
        guard
            let session,
            session.activationState == .activated,
            let data = try? JSONEncoder().encode(value)
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind: kind.rawValue,
            WatchTransferMetadataKey.payload: data,
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler: Self.makeDurableMessageErrorHandler(
                    session: session,
                    payload: payload,
                    store: self
                )
            )
        } else {
            session.transferUserInfo(payload)
        }
    }

    func clearCompletedWorkout() {
        guard let id =
                lastCompletedWorkout?.id
        else {
            return
        }

        consumeCompletedWorkout(id)
    }

    func consumeCompletedWorkout(
        _ id: UUID
    ) {
        pendingWorkoutResults
            .removeAll {
                $0.id == id
            }

        if !handledWorkoutResultIDs
            .contains(id) {
            handledWorkoutResultIDs
                .append(id)

            if handledWorkoutResultIDs.count > 128 {
                handledWorkoutResultIDs =
                    Array(
                        handledWorkoutResultIDs
                            .suffix(64)
                    )
            }
        }

        persistWorkoutResultState()
        lastCompletedWorkout =
            pendingWorkoutResults.first
    }

    private func persistWorkoutResultState() {
        UserDefaults.standard.set(
            handledWorkoutResultIDs
                .map(\.uuidString),
            forKey:
                Self.handledWorkoutResultsKey
        )

        if let data =
                try? JSONEncoder().encode(
                    pendingWorkoutResults
                ) {
            UserDefaults.standard.set(
                data,
                forKey:
                    Self.pendingWorkoutResultsKey
            )
        }
    }

    func sendWorkoutCommand(
        _ command: WatchWorkoutCommand,
        workoutID: UUID? = nil
    ) {
        guard
            let session,
            session.activationState == .activated,
            state.isReady
        else {
            return
        }

        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.workoutCommand.rawValue,
            WatchTransferMetadataKey.command:
                command.rawValue,
            WatchTransferMetadataKey.workoutID:
                workoutID?.uuidString ?? "",
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil,
                errorHandler:
                    command == .end
                        ? Self.makeDurableMessageErrorHandler(
                            session: session,
                            payload: payload,
                            store: self
                        )
                        : Self.makeMessageErrorHandler(
                            store: self
                        )
            )
        } else if command == .end {
            session.transferUserInfo(payload)
        } else {
            workoutLaunchError =
                ATHLTHLocalization.choose(
                    english:
                        "Apple Watch is not reachable. Pause or resume directly on the Watch.",
                    norwegian:
                        "Apple Watch er ikke tilgjengelig. Pause eller fortsett direkte på klokken."
                )
        }
    }

    // WatchConnectivity invokes reply/error blocks on its own operation
    // queues. These factories are deliberately nonisolated so Swift 6 does
    // not attach MainActor isolation to the Objective-C callback blocks.
    // Any mutation of observable app state is explicitly hopped back to
    // MainActor inside the returned block.
    nonisolated private static func makeDurableMessageErrorHandler(
        session: WCSession,
        payload: [String: Any],
        store: AppleWatchConnectionStore?
    ) -> (Error) -> Void {
        { [weak store] error in
            session.transferUserInfo(payload)
            let message = error.localizedDescription

            Task { @MainActor [weak store] in
                store?.workoutLaunchError = message
            }
        }
    }

    nonisolated private static func makeMessageErrorHandler(
        store: AppleWatchConnectionStore?
    ) -> (Error) -> Void {
        { [weak store] error in
            let message = error.localizedDescription

            Task { @MainActor [weak store] in
                store?.workoutLaunchError = message
            }
        }
    }

    nonisolated private static func makeConnectivityReplyHandler(
        store: AppleWatchConnectionStore?
    ) -> ([String: Any]) -> Void {
        { [weak store] reply in
            let incoming = IncomingWatchPayload(reply)

            Task { @MainActor [weak store] in
                store?.handleConnectivityAck(incoming)
            }
        }
    }

    nonisolated private static func makeConnectivityErrorHandler(
        store: AppleWatchConnectionStore?,
        probeID: String
    ) -> (Error) -> Void {
        { [weak store] error in
            let message = error.localizedDescription

            Task { @MainActor [weak store] in
                guard let store else { return }

                store.connectivityError = message

                guard let currentSession = store.session,
                      currentSession.activationState == .activated
                else {
                    return
                }

                store.queueConnectivityProbe(
                    probeID: probeID,
                    on: currentSession
                )
            }
        }
    }

    private func evaluate(_ session: WCSession) {
        guard session.activationState == .activated else {
            publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Not activated"
            )
            return
        }

        #if os(iOS)
        let isPaired = session.isPaired
        let isInstalled = isPaired && session.isWatchAppInstalled
        let isReachable = session.isReachable

        let resolvedState: AppleWatchConnectionState
        if !isPaired {
            resolvedState = .notPaired
        } else if !isInstalled {
            resolvedState = .appNotInstalled
        } else {
            resolvedState = .ready
        }

        publishSnapshot(
            state: resolvedState,
            paired: isPaired,
            installed: isInstalled,
            reachable: isReachable,
            activation: "Activated"
        )

        if resolvedState == .ready, verificationRequested {
            verificationRequested = false
            sendConnectivityProbe(session)
        }
        #else
        publishSnapshot(
            state: .unsupported,
            paired: nil,
            installed: nil,
            reachable: false,
            activation: "Unsupported"
        )
        #endif
    }

    private func sendConnectivityProbe(_ session: WCSession) {
        guard
            session.activationState == .activated,
            session.isPaired,
            session.isWatchAppInstalled
        else {
            return
        }

        let probeID = UUID().uuidString
        lastProbeID = probeID
        verificationInProgress = true
        connectivityError = nil

        let payload = connectivityProbePayload(probeID: probeID)

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: Self.makeConnectivityReplyHandler(
                    store: self
                ),
                errorHandler: Self.makeConnectivityErrorHandler(
                    store: self,
                    probeID: probeID
                )
            )
        } else {
            queueConnectivityProbe(
                probeID: probeID,
                on: session
            )
        }
    }

    private func connectivityProbePayload(
        probeID: String
    ) -> [String: Any] {
        [
            WatchTransferMetadataKey.kind:
                WatchTransferKind.connectivityProbe.rawValue,
            WatchTransferMetadataKey.probeID: probeID,
            WatchTransferMetadataKey.sentAt:
                Date().timeIntervalSince1970
        ]
    }

    private func queueConnectivityProbe(
        probeID: String,
        on session: WCSession
    ) {
        guard session.activationState == .activated else { return }

        _ = session.transferUserInfo(
            connectivityProbePayload(probeID: probeID)
        )
    }

    private func handleConnectivityAck(
        _ payload: IncomingWatchPayload
    ) {
        guard
            payload.kind == WatchTransferKind.connectivityAck.rawValue
        else {
            return
        }

        let probeID = payload.probeID

        // A launch acknowledgement from the Watch can arrive without matching
        // the most recent explicit probe. Either form proves that the paired
        // ATHLTH Watch app is alive and communicating.
        if let probeID,
           let lastProbeID,
           probeID != lastProbeID,
           probeID != "watch-launch" {
            return
        }

        lastVerifiedAt = Date()
        verificationInProgress = false
        connectivityError = nil
    }

    private func publishSnapshot(
        state newState: AppleWatchConnectionState,
        paired: Bool?,
        installed: Bool?,
        reachable: Bool,
        activation: String
    ) {
        state = newState
        self.paired = paired
        watchAppInstalled = installed
        self.reachable = reachable
        activationStateText = activation

        if newState != .ready {
            verificationInProgress = false
        }
    }

    private func receiveStrengthCommand(
        from payload: IncomingWatchPayload
    ) -> Bool {
        guard
            payload.kind == WatchTransferKind.strengthCommand.rawValue,
            let data = payload.data,
            let command = try? JSONDecoder().decode(
                WatchStrengthCommand.self,
                from: data
            )
        else {
            return false
        }

        guard !handledStrengthCommandIDs
                .contains(command.id),
              !pendingStrengthCommands
                .contains(
                    where: {
                        $0.id == command.id
                    }
                )
        else {
            return true
        }

        pendingStrengthCommands
            .append(command)
        pendingStrengthCommands.sort {
            $0.sentAt < $1.sentAt
        }

        if pendingStrengthCommands.count > 256 {
            pendingStrengthCommands =
                Array(
                    pendingStrengthCommands
                        .suffix(256)
                )
        }

        persistStrengthCommandState()
        lastStrengthCommand =
            pendingStrengthCommands.first
        return true
    }

    private func receiveSpotifyCommand(
        from payload: IncomingWatchPayload
    ) -> Bool {
        guard
            payload.kind == WatchTransferKind.spotifyCommand.rawValue,
            let data = payload.data,
            let command = try? JSONDecoder().decode(
                WatchSpotifyCommand.self,
                from: data
            )
        else {
            return false
        }

        guard command.sentAt >
                lastSpotifyCommandSentAt
        else {
            return true
        }

        lastSpotifyCommandSentAt =
            command.sentAt
        lastSpotifyCommand = command
        return true
    }

    private func receiveWorkoutResult(
        from payload: IncomingWatchPayload
    ) {
        guard
            payload.kind == WatchTransferKind.workoutResult.rawValue,
            let data = payload.data,
            let result = try? JSONDecoder().decode(
                WatchWorkoutResult.self,
                from: data
            )
        else {
            return
        }

        guard !handledWorkoutResultIDs
                .contains(result.id),
              !pendingWorkoutResults
                .contains(
                    where: {
                        $0.id == result.id
                    }
                )
        else {
            return
        }

        pendingWorkoutResults
            .append(result)
        pendingWorkoutResults.sort {
            $0.endedAt < $1.endedAt
        }

        if pendingWorkoutResults.count > 32 {
            pendingWorkoutResults =
                Array(
                    pendingWorkoutResults
                        .suffix(32)
                )
        }

        persistWorkoutResultState()
        lastCompletedWorkout =
            pendingWorkoutResults.first
    }

    private func receive(_ payload: IncomingWatchPayload) {
        if payload.kind ==
            WatchTransferKind.todayWorkoutRequest.rawValue {
            sendWatchPayload(
                latestTodaySnapshot,
                kind: .todayWorkout
            )
            return
        }

        if payload.kind == WatchTransferKind.connectivityAck.rawValue {
            handleConnectivityAck(payload)
            return
        }

        if receiveStrengthCommand(from: payload) {
            return
        }

        if receiveSpotifyCommand(from: payload) {
            return
        }

        receiveWorkoutResult(from: payload)
    }
}

extension AppleWatchConnectionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let rawActivationState = activationState.rawValue
        let errorMessage = error?.localizedDescription

        Task { @MainActor [weak self] in
            guard let self else { return }

            if let errorMessage {
                self.connectivityError = errorMessage
            }

            guard
                let resolvedState =
                    WCSessionActivationState(
                        rawValue: rawActivationState
                    ),
                resolvedState == .activated,
                let currentSession = self.session
            else {
                self.publishSnapshot(
                    state: .checking,
                    paired: nil,
                    installed: nil,
                    reachable: false,
                    activation: "Activation failed"
                )
                return
            }

            self.evaluate(currentSession)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        let incoming = IncomingWatchPayload(message)

        Task { @MainActor [weak self] in
            self?.receive(incoming)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        let incoming = IncomingWatchPayload(userInfo)

        Task { @MainActor [weak self] in
            self?.receive(incoming)
        }
    }

    nonisolated func sessionReachabilityDidChange(
        _ session: WCSession
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  let currentSession = self.session
            else {
                return
            }

            self.evaluate(currentSession)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(
        _ session: WCSession
    ) {
        Task { @MainActor [weak self] in
            self?.publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Inactive"
            )
        }
    }

    nonisolated func sessionDidDeactivate(
        _ session: WCSession
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            self.verificationRequested = true
            self.publishSnapshot(
                state: .checking,
                paired: nil,
                installed: nil,
                reachable: false,
                activation: "Reactivating"
            )
            self.session?.activate()
        }
    }

    nonisolated func sessionWatchStateDidChange(
        _ session: WCSession
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  let currentSession = self.session
            else {
                return
            }

            self.verificationRequested = true
            self.evaluate(currentSession)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let fileURL = fileTransfer.file.fileURL
        try? FileManager.default.removeItem(at: fileURL)
    }
    #endif
}
