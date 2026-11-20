import Combine
import Foundation
import WatchConnectivity

// A WatchConnectivity reply block can outlive its caller. Transport it
// explicitly across the MainActor hop without capturing the delegate closure
// in a potentially concurrently executing SwiftUI render transaction.
private final class WatchWorkoutActivityQueryReply: @unchecked Sendable {
    private let callback: ([String: Any]) -> Void

    init(_ callback: @escaping ([String: Any]) -> Void) {
        self.callback = callback
    }

    func send(_ activity: WatchWorkoutActivityState) {
        guard let data = try? JSONEncoder().encode(activity) else {
            callback([:])
            return
        }
        callback([
            WatchTransferMetadataKey.kind:
                WatchTransferKind.workoutActivityState.rawValue,
            WatchTransferMetadataKey.payload: data,
            WatchTransferMetadataKey.sentAt:
                activity.updatedAt.timeIntervalSince1970
        ])
    }
}

// The WatchConnectivity callback crosses an actor boundary only after the
// pending launch identity is durably staged by WatchWorkoutManager.
private final class WatchRemoteLaunchIdentityReply: @unchecked Sendable {
    private let callback: ([String: Any]) -> Void

    init(_ callback: @escaping ([String: Any]) -> Void) {
        self.callback = callback
    }

    func send(requestID: UUID, accepted: Bool) {
        callback([
            WatchTransferMetadataKey.kind:
                WatchTransferKind.workoutRemoteLaunchIdentity.rawValue,
            WatchTransferMetadataKey.relayRequestID: requestID.uuidString,
            WatchTransferMetadataKey.workoutAllowed: accepted
        ])
    }
}

@MainActor
final class WatchRouteStore: NSObject, ObservableObject {
    // One WCSession delegate and prepared-workout cache shared by the Watch
    // SwiftUI root and the HealthKit remote-launch delegate.
    static let shared = WatchRouteStore()

    @Published private(set) var automaticStartCountdownSeconds: Int?

    func setAutomaticStartCountdown(_ seconds: Int?) {
        automaticStartCountdownSeconds = seconds
    }

    @Published private(set) var routes: [WatchRouteTransfer] = []
    @Published private(set) var connectionText = "Connecting to iPhone"
    @Published private(set) var companionLinked = false
    @Published private(set) var todayWorkout: WatchTodayWorkoutTransfer?
    @Published private(set) var todayWorkouts: [WatchTodayWorkoutTransfer] = []
    @Published private(set) var preparedWorkout: WatchPreparedWorkoutTransfer?
    // One transient preflight at a time, before any card can mutate the
    // shared manager's route, coach or interval configuration.
    private var pendingPreparedLaunchID: UUID?
    @Published private(set) var petCatalog: [WatchPetIdentity] = []
    @Published private(set) var selectedPetIDs: Set<UUID> = []
    private(set) var companionAccountID: UUID?
    private var latestCompanionAccountUpdatedAt = Date.distantPast
    private let accountIdentityDefaultsKey =
        "athlth.watch.accountIdentity.v1"
    private var petOwnerID: UUID?
    private var petSegments: [WatchPetParticipationSegment] = []
    private let petCatalogDefaultsKey = "athlth.watch.pet-catalog.v1"
    @Published private(set) var spotifyPlaybackState =
        WatchSpotifyPlaybackState.unavailable

    private let fileManager = FileManager.default
    private let todayWorkoutDefaultsKey =
        "athlth.watch.todayWorkout.v1"
    private let todayWorkoutsDefaultsKey = "athlth.watch.todayWorkouts.v1"
    private let preparedWorkoutDefaultsKey =
        "athlth.watch.preparedWorkout.v1"
    private let preparedWorkoutSnapshotDateKey =
        "athlth.watch.preparedWorkoutSnapshotDate.v1"
    private let confirmedTodayLaunchesKey =
        "athlth.watch.confirmedTodayLaunches.v1"
    private var confirmedTodayLaunches: [ATHLTHWatchTodayLaunchReceipt] = []
    private var pendingWorkoutRouteID: UUID?
    private var latestTransportTimestampByKind:
        [String: TimeInterval] = [:]

    override init() {
        super.init()
        restoreCompanionAccountIdentity()
        restoreConfirmedTodayLaunches()
        loadRoutes()
        loadTodayWorkout()
        loadTodayWorkouts()
        loadPreparedWorkout()
        restorePetCatalog()
        activateConnectivity()
    }

    private func restoreCompanionAccountIdentity() {
        guard let data = UserDefaults.standard.data(
            forKey: accountIdentityDefaultsKey
        ),
        let transfer = try? JSONDecoder().decode(
            WatchAccountIdentityTransfer.self, from: data
        ) else { return }
        companionAccountID = transfer.ownerID
        latestCompanionAccountUpdatedAt = transfer.updatedAt
    }

    private func applyCompanionAccountIdentity(
        _ transfer: WatchAccountIdentityTransfer
    ) {
        guard transfer.updatedAt >= latestCompanionAccountUpdatedAt else {
            return
        }
        // Do not alter the account captured by an already-running workout.
        companionAccountID = transfer.ownerID
        latestCompanionAccountUpdatedAt = transfer.updatedAt
        if let data = try? JSONEncoder().encode(transfer) {
            UserDefaults.standard.set(data, forKey: accountIdentityDefaultsKey)
        }
    }

    private func restorePetCatalog() {
        guard let data = UserDefaults.standard.data(forKey: petCatalogDefaultsKey),
              let catalog = try? JSONDecoder().decode(WatchPetCatalogTransfer.self, from: data)
        else { return }
        petOwnerID = catalog.ownerID
        petCatalog = catalog.pets
        selectedPetIDs = Set(catalog.selectedPetIDs).intersection(Set(catalog.pets.map(\.id)))
        petSegments = selectedPetIDs.map {
            WatchPetParticipationSegment(
                petID: $0, enteredAt: nil, exitedAt: nil,
                enteredMeters: nil, exitedMeters: nil)
        }
    }

    private func applyPetCatalog(_ catalog: WatchPetCatalogTransfer) {
        if let previous = petOwnerID, previous != catalog.ownerID {
            petSegments = []
            selectedPetIDs = []
        }
        petOwnerID = catalog.ownerID
        petCatalog = catalog.pets
        let available = Set(catalog.pets.map(\.id))
        if !WatchWorkoutManager.shared.isActive {
            selectedPetIDs = Set(catalog.selectedPetIDs).intersection(available)
            petSegments = selectedPetIDs.map {
                WatchPetParticipationSegment(
                    petID: $0, enteredAt: nil, exitedAt: nil,
                    enteredMeters: nil, exitedMeters: nil)
            }
        } else {
            selectedPetIDs.formIntersection(available)
        }
        persistPetCatalog()
    }

    private func persistPetCatalog() {
        guard let ownerID = petOwnerID else { return }
        let snapshot = WatchPetCatalogTransfer(
            ownerID: ownerID, pets: petCatalog,
            selectedPetIDs: Array(selectedPetIDs), updatedAt: Date())
        if let bytes = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(bytes, forKey: petCatalogDefaultsKey)
        }
    }

    func setSelectedPetIDs(_ ids: Set<UUID>, distanceMeters: Double? = nil) {
        let selected = ids.intersection(Set(petCatalog.map(\.id)))
        let isRecording = WatchWorkoutManager.shared.isActive
        let now = Date()
        if isRecording {
            let existing = selectedPetIDs
            for i in petSegments.indices where
                petSegments[i].exitedAt == nil &&
                existing.subtracting(selected).contains(petSegments[i].petID) {
                petSegments[i].exitedAt = now
                petSegments[i].exitedMeters = distanceMeters
            }
            for id in selected.subtracting(existing) {
                petSegments.append(WatchPetParticipationSegment(
                    petID: id, enteredAt: now, exitedAt: nil,
                    enteredMeters: distanceMeters, exitedMeters: nil))
            }
        } else {
            petSegments = selected.map {
                WatchPetParticipationSegment(
                    petID: $0, enteredAt: nil, exitedAt: nil,
                    enteredMeters: nil, exitedMeters: nil)
            }
        }
        selectedPetIDs = selected
        persistPetCatalog()
        guard let ownerID = petOwnerID,
              WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
        let transfer = WatchPetSelectionTransfer(
            ownerID: ownerID, selectedPetIDs: Array(selected),
            segments: petSegments, updatedAt: now, workoutStartedAt: nil)
        guard let data = try? JSONEncoder().encode(transfer) else { return }
        let payload: [String: Any] = [
            WatchTransferMetadataKey.kind: WatchTransferKind.petSelection.rawValue,
            WatchTransferMetadataKey.payload: data,
            WatchTransferMetadataKey.sentAt: now.timeIntervalSince1970
        ]
        // Durable path handles an offline iPhone; fast path updates live.
        WCSession.default.transferUserInfo(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    func completedPetSegments() -> [WatchPetParticipationSegment] {
        petSegments
    }

    func clearCompletedPetSelection() {
        selectedPetIDs = []
        petSegments = []
        persistPetCatalog()
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
        // Incoming next-card routes must not replace a recorder awaiting
        // authorization for the original prepared card.
        if pendingPreparedLaunchID != nil ||
            WatchWorkoutManager.shared.isActive {
            pendingWorkoutRouteID = UUID(uuidString: rawRouteID)
            return
        }
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

    private func restoreConfirmedTodayLaunches() {
        guard let data = UserDefaults.standard.data(
            forKey: confirmedTodayLaunchesKey
        ), let receipts = try? JSONDecoder().decode(
            [ATHLTHWatchTodayLaunchReceipt].self, from: data
        ) else { return }
        confirmedTodayLaunches = Array(receipts.filter {
            let age = Date().timeIntervalSince($0.confirmedAt)
            return age >= 0 &&
                age < ATHLTHWatchTodayReplayPolicy.retention
        }.suffix(120))
    }

    private func wasTodaySessionLaunched(_ id: UUID) -> Bool {
        ATHLTHWatchTodayReplayPolicy.wasConfirmed(
            sessionID: id, ownerID: companionAccountID,
            receipts: confirmedTodayLaunches
        )
    }

    func canLaunchTodayWorkout(_ id: UUID) -> Bool {
        !wasTodaySessionLaunched(id)
    }

    private func recordConfirmedTodayLaunch(_ sessionID: UUID) {
        guard todayWorkouts.contains(where: { $0.workoutID == sessionID }) ||
              todayWorkout?.workoutID == sessionID,
              !wasTodaySessionLaunched(sessionID) else { return }
        confirmedTodayLaunches.append(ATHLTHWatchTodayLaunchReceipt(
            sessionID: sessionID, ownerID: companionAccountID,
            confirmedAt: Date()
        ))
        confirmedTodayLaunches = Array(confirmedTodayLaunches.suffix(120))
        if let data = try? JSONEncoder().encode(confirmedTodayLaunches) {
            UserDefaults.standard.set(data, forKey: confirmedTodayLaunchesKey)
        }
        todayWorkouts.removeAll { $0.workoutID == sessionID }
        if todayWorkout?.workoutID == sessionID {
            todayWorkout = nil
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

        todayWorkout = wasTodaySessionLaunched(workout.workoutID)
            ? nil : workout
    }

    private func storeTodayWorkout(
        _ workout: WatchTodayWorkoutTransfer?
    ) {
        todayWorkout = workout.flatMap {
            wasTodaySessionLaunched($0.workoutID) ? nil : $0
        }

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

    private func loadTodayWorkouts() {
        guard let data = UserDefaults.standard.data(forKey: todayWorkoutsDefaultsKey),
              let snapshot = try? JSONDecoder().decode(WatchTodaySnapshot.self, from: data),
              Date().timeIntervalSince(snapshot.updatedAt) < 8 * 86_400 else {
            todayWorkouts = todayWorkout.map { [$0] } ?? []
            return
        }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        todayWorkouts = snapshot.scheduledWorkouts.filter { workout in
            guard let start = workout.scheduledStart else {
                return Calendar.current.isDateInToday(snapshot.updatedAt)
            }
            return start >= startOfToday &&
                !wasTodaySessionLaunched(workout.workoutID)
        }
    }

    private func storeTodayWorkouts(_ workouts: [WatchTodayWorkoutTransfer]) {
        todayWorkouts = workouts.filter {
            !wasTodaySessionLaunched($0.workoutID)
        }
        let snapshot = WatchTodaySnapshot(
            workout: workouts.first, updatedAt: Date(), workouts: workouts)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: todayWorkoutsDefaultsKey)
        }
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

    // Reused by both the manual START card and iPhone-triggered launch.
    // Applying the payload before HealthKit starts preserves route, audio
    // coach, Ghost and treadmill configuration on the first live frame.
    @discardableResult
    func launchPreparedWorkout(
        _ workout: WatchPreparedWorkoutTransfer,
        manager: WatchWorkoutManager,
        initiatedByIPhone: Bool = false
    ) async -> Bool {
        guard manager.canAcceptPreparedWorkout(),
              ATHLTHWatchPreparedPlanIdentityPolicy.allows(
                  planID: workout.plannedPlanID,
                  sessionID: workout.plannedSessionID
              ),
              ATHLTHWatchPreparedRecipeAdmissionPolicy.permits(
                  kind: workout.kind,
                  hasRunningRecipe: workout.runningWorkout != nil,
                  hasStrengthRecipe: workout.strengthWorkout != nil,
                  hasRoute: workout.routeID != nil
              ),
              workout.plannedSessionID.map({
                  !wasTodaySessionLaunched($0)
              }) ?? true else {
            return false
        }

        let route = workout.routeID.flatMap {
            self.route(with: $0)
        }
        guard workout.routeID == nil || route != nil,
              ATHLTHWatchPreparedLaunchReservationPolicy.mayBegin(
                  pendingID: pendingPreparedLaunchID
              ) else { return false }

        pendingPreparedLaunchID = workout.id
        defer {
            if pendingPreparedLaunchID == workout.id {
                pendingPreparedLaunchID = nil
            }
        }

        // Remove staged configuration from an earlier rejected attempt
        // before configuring THIS original workout. Never reset active HK.
        guard manager.prepareForIncomingWatchWorkout() else { return false }

        // Claim the preflight synchronously on the MainActor before the
        // asynchronous phone check; another card cannot replace this payload.
        manager.configureCalendarSessionID(workout.plannedSessionID)
        manager.configurePlannedRoute(route)
        manager.configureAudioCoach(workout.audioCoach ?? .disabled)
        manager.configureGhostRace(workout.ghostRace)

        if workout.kind == .strength, let strength = workout.strengthWorkout {
            manager.configureStrengthSession(strength)
        }
        if let running = workout.runningWorkout {
            manager.configureRunningWorkout(running)
        } else if workout.kind == .running || workout.kind == .walking {
            manager.configureRunningWorkout(
                WatchRunningWorkoutTransfer(
                    title: workout.title,
                    steps: [],
                    routeAlerts: .standard
                )
            )
        }

        let launchedWorkoutID = await manager.startPreparedWorkout(
            kind: workout.kind,
            route: route,
            indoor: workout.indoor,
            initiatedByIPhone: initiatedByIPhone
        )

        // An unrelated session may have started during the asynchronous
        // Watch preflight. Only this exact HealthKit invocation can consume
        // the prepared card; a generic .running state is never sufficient.
        guard ATHLTHWatchPreparedLaunchConfirmationPolicy.confirms(
            acknowledgedWorkoutID: launchedWorkoutID,
            currentWorkoutID: manager.activeWorkoutIdentity,
            requestedKind: workout.kind,
            activeKind: manager.kind,
            isRecording: manager.state == .running ||
                manager.state == .paused
        ) else { return false }

        if let sessionID = workout.plannedSessionID {
            recordConfirmedTodayLaunch(sessionID)
        }
        consumePreparedWorkout(workout.id)
        // A Today card has a fresh transport UUID, but may represent the
        // same previously prepared calendar session. Hide only the older
        // matching card once the original HealthKit workout was confirmed.
        if let sessionID = workout.plannedSessionID,
           let existing = preparedWorkout,
           existing.plannedSessionID == sessionID,
           existing.updatedAt <= workout.updatedAt {
            consumePreparedWorkout(existing.id)
        }
        return true
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

        // A prepared workout owns the route selection. This also clears any
        // stale pending route from an older workout when the new one has no
        // route, and waits for the correct route file when it is still in
        // transit.
        applyRouteSelection(
            rawRouteID:
                workout.routeID?
                    .uuidString ??
                ""
        )
    }

    // Called by WatchHomeView on appear as well as by WCSession activation.
    // Keep transport internals private, but expose this idempotent request.
    func requestTodayWorkoutSnapshot() {
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
        case .accountIdentity:
            guard let transfer = try? JSONDecoder().decode(
                WatchAccountIdentityTransfer.self, from: data
            ) else { return }
            applyCompanionAccountIdentity(transfer)

        case .aiCoachConversationState:
            guard let active = try? JSONDecoder().decode(Bool.self, from: data)
            else { return }
            WatchWorkoutManager.shared.setAIConversationVoiceSuppressed(active)

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
            storeTodayWorkout(snapshot.workout)
            storeTodayWorkouts(snapshot.scheduledWorkouts)

        case .strengthSnapshot:
            guard let snapshot = try? JSONDecoder().decode(
                WatchStrengthSessionSnapshot.self,
                from: data
            ) else {
                return
            }

            WatchWorkoutManager.shared
                .configureStrengthSession(snapshot)

        case .petCatalog:
            guard let catalog = try? JSONDecoder().decode(
                WatchPetCatalogTransfer.self, from: data
            ) else { return }
            applyPetCatalog(catalog)

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

        case .workoutActivityState:
            guard let state =
                    try? JSONDecoder().decode(
                        WatchWorkoutActivityState.self,
                        from: data
                    )
            else {
                return
            }

            WatchWorkoutManager.shared
                .configureCompanionWorkoutActivity(
                    state
                )

        case .route,
             .petSelection,
             .aiCoachConversationRequest,
             .workoutResult,
             .workoutActivityQuery,
             .workoutRemoteLaunchCompletion,
             .workoutRemoteLaunchIdentity,
             .workoutStartGuard,
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
        case .setTreadmillIncline, .setTreadmillTargetPace,
             .setTreadmillBeltSpeed:
            // Treadmill adjustments require numeric values delivered
            // with the authorized workout mirror. A raw WCSession command
            // carries neither value and must not overwrite live settings.
            break
        case .returnToStart:
            // Require the workout-scoped identity carried by the live
            // HealthKit mirror, never act on a stale WCSession command.
            break
        case .appendRunningWorkout, .advanceRunningStep:
            // Structured phases need the workout token and intended step
            // index delivered through the authorized HealthKit mirror.
            break
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
            WatchWorkoutManager.shared
                .syncWorkoutActivityStateToPhone()
            WatchWorkoutManager.shared
                .replayRelayCompletionProofs(durable: false)
        } else if activated {
            companionLinked = false
            // WCSession reachability is false when the companion iPhone
            // app sleeps. That does not make Watch workouts unavailable.
            connectionText =
                "Watch ready · iPhone in background"
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

        if rawKind == WatchTransferKind.workoutRemoteLaunchIdentity.rawValue {
            guard let replyHandler,
                  let data = payload[WatchTransferMetadataKey.payload] as? Data,
                  let identity = try? JSONDecoder().decode(
                    WatchRemoteLaunchIdentity.self, from: data
                  )
            else {
                replyHandler?([:])
                return
            }
            let reply = WatchRemoteLaunchIdentityReply(replyHandler)
            Task { @MainActor in
                let accepted = WatchWorkoutManager.shared
                    .stageRemoteLaunchIdentity(identity)
                reply.send(requestID: identity.requestID, accepted: accepted)
            }
            return
        }

        if rawKind == WatchTransferKind.workoutActivityQuery.rawValue {
            if let replyHandler {
                let reply = WatchWorkoutActivityQueryReply(replyHandler)
                Task { @MainActor in
                    let manager = WatchWorkoutManager.shared
                    // Check for a HealthKit session that has not yet been
                    // restored into the Watch UI after process relaunch.
                    if manager.state == .idle {
                        await manager.recoverActiveWorkout()
                    }
                    reply.send(manager.currentWorkoutActivityForProbe())
                }
            } else {
                Task { @MainActor in
                    WatchWorkoutManager.shared
                        .syncWorkoutActivityStateToPhone()
                }
            }
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
           transferKind == .aiCoachConversationState ||
           transferKind == .ghostRace ||
           transferKind == .liveSurfaceConfiguration ||
           transferKind == .liveSurfaceContext ||
           transferKind == .todayWorkout ||
           transferKind == .strengthSnapshot ||
           transferKind == .petCatalog ||
           transferKind == .accountIdentity ||
           transferKind == .workoutActivityState ||
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

                if transferKind == .aiCoachConversationState,
                   !ATHLTHAIWatchCoachRequestPolicy.accepts(sentAt: sentAt) {
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
            // Recover the latest queued launch configuration immediately
            // after process activation; don't wait for a new live message.
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                receive(context)
            }
            session.transferUserInfo(
                Self.connectivityAck(
                    probeID: "watch-launch"
                )
            )

            Task { @MainActor [weak self] in
                self?.requestTodayWorkoutSnapshot()
                self?.requestSpotifyPlaybackState()
                WatchWorkoutManager.shared
                    .syncWorkoutActivityStateToPhone()
                // Requeue tiny completion proofs if Watch terminated after
                // saving HealthKit but before the iPhone received the result.
                WatchWorkoutManager.shared.replayRelayCompletionProofs()
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
