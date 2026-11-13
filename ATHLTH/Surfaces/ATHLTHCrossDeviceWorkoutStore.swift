import Foundation
import SwiftUI
import Supabase

/// Read-only, owner-scoped active workout summary for a second signed-in device.
/// The recording and HealthKit ownership always remain on the source iPhone.
struct ATHLTHCrossDeviceWorkoutSnapshot: Codable, Equatable, Identifiable {
    let sessionID: UUID
    let kind: String
    let title: String
    let startedAt: Date
    let elapsedSeconds: TimeInterval
    let distanceMeters: Double?
    let currentStep: String?
    let nextStep: String?
    let completedSets: Int?
    let totalSets: Int?
    var paused: Bool? = nil
    // Read-only interval metadata. Same semantics as phone and Watch Live Activity.
    var runningIntervalOrdinal: Int? = nil
    var runningIntervalTotal: Int? = nil
    var runningInRecovery: Bool? = nil
    var runningStepRemainingSeconds: TimeInterval? = nil
    var capturedAt: Date? = nil

    // Optional live data; older cross-device snapshots remain decodable.
    // Only the source device can publish these values. iPad never measures.
    var sourceDevice: String? = nil
    var heartRateBPM: Double? = nil
    var activeCalories: Double? = nil
    var currentPaceSecondsPerKilometer: Double? = nil
    var targetPaceSecondsPerKilometer: Double? = nil
    var targetHeartRateZone: Int? = nil
    var runningStepProgress: Double? = nil
    var runningOverallProgress: Double? = nil
    var routeTitle: String? = nil
    var ghostRaceTitle: String? = nil
    var ghostDistanceDeltaMeters: Double? = nil
    var ghostTimeDeltaSeconds: Double? = nil
    var runningSteps: [ATHLTHLiveWorkoutStage]? = nil
    var runningStepIndex: Int? = nil
    var runningStepCount: Int? = nil
    var runningStepRemainingMeters: Double? = nil
    var routeProgressPercent: Double? = nil
    var routeRemainingMeters: Double? = nil
    var routeDistanceMeters: Double? = nil
    var strengthSetNumber: Int? = nil
    var strengthSetTotal: Int? = nil
    var strengthReps: Int? = nil
    var strengthWeightKilograms: Double? = nil
    var strengthRestEndsAt: Date? = nil
    var strengthExercises: [ATHLTHLiveStrengthExercise]? = nil
    var paceIsTreadmillTarget: Bool? = nil
    var spotifyPlaying: Bool? = nil
    var audioCoachEnabled: Bool? = nil
    var recentSplits: [ATHLTHLiveWorkoutSplit]? = nil
    // Private one-session spectator metadata: never a full GPS trail.
    // Only a fresh valid position from the source is shared after approval.
    var liveLatitude: Double? = nil
    var liveLongitude: Double? = nil
    var livePositionAt: Date? = nil
    // Only iPhone's observed Spotify track; Watch playback is not inferred.
    var spotifyTrackTitle: String? = nil
    var spotifyArtistName: String? = nil

    var id: UUID { sessionID }
    var symbol: String {
        switch kind {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        case "strength": return "dumbbell.fill"
        case "hiit": return "figure.highintensity.intervaltraining"
        case "functional": return "figure.cross.training"
        case "rowing": return "figure.rower"
        case "stairClimbing": return "figure.stair.stepper"
        case "yoga": return "figure.yoga"
        default: return "figure.mixed.cardio"
        }
    }
}

private struct ATHLTHCrossDeviceWorkoutRow: Codable {
    let userID: UUID
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case snapshot
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}

/// Minimal active-session presence, separate from approved live details.
/// It is private to the same account and contains no health measurements.
struct ATHLTHCrossDevicePresenceRow: Codable, Equatable {
    let userID: UUID
    let sourceDevice: String
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case sourceDevice = "source_device"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}

private struct ATHLTHLiveAccessPushResult: Decodable {
    let queued: Bool
    let reason: String?
}

/// Polling deliberately shares only a compact spectator state; no second
/// HKWorkoutSession, no mirrored GPS track, no public/social presence.
/// Server-side RLS additionally enforces user_id = auth.uid().
@MainActor
final class ATHLTHCrossDeviceWorkoutStore: ObservableObject {
    static let shared = ATHLTHCrossDeviceWorkoutStore()
    @Published private(set) var remote: ATHLTHCrossDeviceWorkoutSnapshot?
    /// Only a same-account active flag; never treated as viewing consent.
    @Published private(set) var remotePresence: ATHLTHCrossDevicePresenceRow?
    @Published private(set) var isExpanded = false
    /// Explicit opt-in only for the next workout, never a saved preference.
    @Published var shareNextWorkout = false
    @Published private(set) var incomingRequest: ATHLTHLiveViewRequest?
    @Published private(set) var outgoingRequestState: ATHLTHLiveViewRequestState = .idle
    @Published private(set) var requestError: String?
    @Published private(set) var sourceWorkoutTitle: String?

    private var lastSourceSessionID: UUID?
    private var approvedSourceSessionID: UUID?
    private var nextWorkoutSharingExpiresAt: Date?
    private var outgoingRequestID: UUID?

    /// Only this phone's live, locally confirmed session authorizes publishing.
    func isApprovedForSession(_ sessionID: UUID) -> Bool {
        !ATHLTHDeviceRole.isIPad && approvedSourceSessionID == sessionID
    }

    var isSharingActiveSession: Bool {
        approvedSourceSessionID != nil &&
        approvedSourceSessionID == lastSourceSessionID
    }

    /// A toggle is armed for one workout only. No account-wide auto-share.
    func prepareOneWorkoutSharing(_ enabled: Bool) {
        guard !ATHLTHDeviceRole.isIPad else { return }
        shareNextWorkout = enabled
        nextWorkoutSharingExpiresAt = enabled
            ? Date().addingTimeInterval(600) : nil
    }

    private func reconcileSession(_ currentID: UUID?, title: String?) {
        guard lastSourceSessionID != currentID else { return }
        approvedSourceSessionID = nil
        incomingRequest = nil
        lastSourceSessionID = currentID
        sourceWorkoutTitle = title
        if let currentID, shareNextWorkout,
           let expiry = nextWorkoutSharingExpiresAt, expiry > .now {
            approvedSourceSessionID = currentID
        }
        if currentID != nil {
            // Even an expired preflight selection is consumed by this launch.
            shareNextWorkout = false
            nextWorkoutSharingExpiresAt = nil
        }
    }

    private let client = SupabaseEnvironment.client
    private var lastPublishedID: UUID?
    private var lastPresencePublished = false
    private var lastPresenceCleanupAt: Date?
    private var lastPresenceExpiry: Date?
    private var lastUnauthorisedCleanupAt: Date?
    private var mirroredStartedAt: Date?
    private var mirroredSessionID: UUID?
    private var lastRemoteExpiry: Date?
    private var hasLoadedRemote = false
    private var foregroundedSinceLastPoll = false
    private var suppressAutoOpenOnNextPoll = false

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    func didBackground() {
        foregroundedSinceLastPoll = false
        // Keep a deliberately opened spectator visible when returning to
        // iPad. Respect a manually minimized spectator across app switching.
        suppressAutoOpenOnNextPoll = !isExpanded
    }

    func didForeground() {
        foregroundedSinceLastPoll = true
    }

    func clearLocalState() {
        remote = nil
        remotePresence = nil
        lastPresenceExpiry = nil
        lastPresencePublished = false
        lastPresenceCleanupAt = nil
        lastPublishedID = nil
        lastUnauthorisedCleanupAt = nil
        shareNextWorkout = false
        nextWorkoutSharingExpiresAt = nil
        incomingRequest = nil
        outgoingRequestID = nil
        outgoingRequestState = .idle
        requestError = nil
        approvedSourceSessionID = nil
        lastSourceSessionID = nil
        sourceWorkoutTitle = nil
        mirroredStartedAt = nil
        mirroredSessionID = nil
        lastRemoteExpiry = nil
        hasLoadedRemote = false
        foregroundedSinceLastPoll = false
        suppressAutoOpenOnNextPoll = false
        isExpanded = false
        ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
    }

    func track(
        signedIn: Bool,
        accountID: UUID,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore,
        spotify: SpotifyPlaybackStore
    ) async {
        guard signedIn else {
            clearLocalState()
            return
        }
        hasLoadedRemote = false
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        while !Task.isCancelled {
            // Do not trust local profile IDs as authorization: every request
            // also requires the active Supabase session to match that ID.
            if client.auth.currentUser?.id == accountID {
                if isPad {
                    await readPresence(accountID: accountID)
                    await readRemote(accountID: accountID)
                    await pollOutgoingRequest(accountID: accountID)
                } else {
                    await publishLocal(
                        accountID: accountID, phone: phone,
                        strength: strength, mirroredWatch: mirroredWatch,
                        spotify: spotify
                    )
                    await pollIncomingRequests(accountID: accountID)
                }
            } else {
                remote = nil
                remotePresence = nil
                ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
            }

            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                break
            }
        }
    }

    private func liveSnapshot(
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore,
        spotify: SpotifyPlaybackStore
    ) -> ATHLTHCrossDeviceWorkoutSnapshot? {
        if let log = strength.activeWorkout {
            let exercise = strength.currentExerciseIndex
            let activeName = log.exercises.indices.contains(exercise)
                ? log.exercises[exercise].exercise.displayName
                : nil
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: log.id,
                kind: "strength",
                title: log.title,
                startedAt: log.startedAt,
                elapsedSeconds: max(0, Date().timeIntervalSince(log.startedAt)),
                distanceMeters: nil,
                currentStep: activeName,
                nextStep: nil,
                completedSets: log.totalCompletedSets,
                totalSets: log.exercises.reduce(0) { $0 + $1.sets.count },
                capturedAt: .now,
                sourceDevice: log.captureDevice == .appleWatch
                    ? "watch" : "iphone",
                strengthSetNumber: strength.currentSet?.setNumber,
                strengthSetTotal: strength.currentExercise?.sets.count,
                strengthReps: strength.currentSet?.plannedReps,
                strengthWeightKilograms:
                    strength.currentSet?.plannedWeightKilograms,
                strengthRestEndsAt: strength.restEndsAt,
                strengthExercises: log.exercises.prefix(30).enumerated().map {
                    index, entry in
                    ATHLTHLiveStrengthExercise(
                        index: index,
                        name: entry.exercise.displayName,
                        completedSets: entry.sets.filter(\.isCompleted).count,
                        totalSets: entry.sets.count
                    )
                },
                spotifyPlaying: log.captureDevice == .appleWatch
                    ? nil : spotify.isPlaying,
                spotifyTrackTitle: log.captureDevice == .iPhone &&
                    spotify.isPlaying ? spotify.watchTrackTitle : nil,
                spotifyArtistName: log.captureDevice == .iPhone &&
                    spotify.isPlaying ? spotify.watchArtistName : nil
            )
        }
        if let run = phone.active {
            let index = run.structuredStepIndex ?? 0
            let steps = run.structuredRunningWorkout?.steps ?? []
            let interval = ATHLTHRunningIntervalPosition.resolve(
                steps: steps, currentIndex: index
            )
            let current = steps.indices.contains(index) ? steps[index] : nil
            let remaining = current?.durationSeconds.map { duration in
                max(0, duration - max(0,
                    run.elapsed(at: Date()) -
                        (run.structuredStepStartElapsedTime ?? 0)
                ))
            }
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: run.id,
                kind: run.walking ? "walking" : "running",
                title: run.title,
                startedAt: run.start,
                elapsedSeconds: max(0, run.elapsed(at: Date())),
                distanceMeters: run.distanceMeters.isFinite
                    ? max(0, run.distanceMeters) : nil,
                currentStep: steps.indices.contains(index)
                    ? steps[index].title : nil,
                nextStep: steps.indices.contains(index + 1)
                    ? steps[index + 1].title : nil,
                completedSets: nil,
                totalSets: nil,
                paused: run.resumedAt == nil,
                runningIntervalOrdinal: interval?.ordinal,
                runningIntervalTotal: interval?.total,
                runningInRecovery: interval?.isRecovery,
                runningStepRemainingSeconds: current?.measure == .time
                    ? remaining : nil,
                capturedAt: .now,
                sourceDevice: "iphone",
                currentPaceSecondsPerKilometer: {
                    if run.runEnvironment == .treadmill {
                        guard let speed = run.treadmillSpeedKilometersPerHour,
                              speed > 0 else { return nil }
                        return 3_600 / speed
                    }
                    return ATHLTHPhoneRunEnvironmentPolicy.isIndoor(
                        run.runEnvironment
                    ) ? nil : run.currentPaceSecondsPerKilometer
                }(),
                targetPaceSecondsPerKilometer:
                    current?.targetPaceMinSecondsPerKilometer,
                targetHeartRateZone: current?.targetHeartRateZone,
                runningStepProgress: {
                    guard let target = current?.durationSeconds,
                          target > 0, let remaining else { return nil }
                    return min(1, max(0, 1 - remaining / target))
                }(),
                runningOverallProgress: {
                    guard !steps.isEmpty, steps.indices.contains(index),
                          let seconds = current?.durationSeconds,
                          seconds > 0, let remaining else { return nil }
                    return ATHLTHRunningStepEngine.overallProgress(
                        steps: steps,
                        index: index,
                        currentStepProgress:
                            min(1, max(0, 1 - remaining / seconds))
                    )
                }(),
                routeTitle: run.plannedRouteTitle,
                ghostRaceTitle: run.ghostRaceTitle,
                ghostDistanceDeltaMeters: run.ghostDistanceDeltaMeters,
                ghostTimeDeltaSeconds: run.ghostTimeDeltaSeconds,
                runningSteps: steps.enumerated().map { index, step in
                    ATHLTHLiveWorkoutStage(
                        index: index,
                        title: step.title,
                        phase: step.phase ?? "unspecified",
                        durationSeconds: step.durationSeconds,
                        distanceMeters: step.distanceMeters
                    )
                },
                runningStepIndex: steps.isEmpty ? nil : index,
                runningStepCount: steps.isEmpty ? nil : steps.count,
                runningStepRemainingMeters: current?.distanceMeters.map {
                    max(0, $0 - max(0, run.distanceMeters -
                        (run.structuredStepStartDistanceMeters ??
                         run.distanceMeters)))
                },
                routeProgressPercent: run.routeProgressPercent,
                routeRemainingMeters: run.routeRemainingMeters,
                routeDistanceMeters:
                    run.plannedRouteDistanceKilometers.map { $0 * 1_000 },
                paceIsTreadmillTarget: run.runEnvironment == .treadmill,
                spotifyPlaying: spotify.isPlaying,
                audioCoachEnabled: run.audioCoachConfiguration?.enabled,
                recentSplits: run.recordedRunningSteps?.suffix(6).map {
                    ATHLTHLiveWorkoutSplit(
                        index: $0.index, title: $0.title,
                        activeSeconds: $0.activeSeconds,
                        distanceMeters: $0.distanceMeters
                    )
                },
                liveLatitude: {
                    guard run.runEnvironment == .outdoor,
                          let point = run.points.last,
                          Self.isFreshPosition(
                              latitude: point.latitude, longitude: point.longitude,
                              sampledAt: point.timestamp, accuracy: point.accuracy
                          ) else { return nil }
                    return point.latitude
                }(),
                liveLongitude: {
                    guard run.runEnvironment == .outdoor,
                          let point = run.points.last,
                          Self.isFreshPosition(
                              latitude: point.latitude, longitude: point.longitude,
                              sampledAt: point.timestamp, accuracy: point.accuracy
                          ) else { return nil }
                    return point.longitude
                }(),
                livePositionAt: {
                    guard run.runEnvironment == .outdoor,
                          let point = run.points.last,
                          Self.isFreshPosition(
                              latitude: point.latitude, longitude: point.longitude,
                              sampledAt: point.timestamp, accuracy: point.accuracy
                          ) else { return nil }
                    return point.timestamp
                }(),
                spotifyTrackTitle: spotify.isPlaying ? spotify.watchTrackTitle : nil,
                spotifyArtistName: spotify.isPlaying ? spotify.watchArtistName : nil
            )
        }
        if let watch = mirroredWatch.snapshot,
           watch.state == .preparing ||
           watch.state == .running ||
           watch.state == .paused {
            // Watch remains the only HealthKit sensor/recording source. The
            // iPhone only relays a private summary to the signed-in iPad.
            let startedAt = watch.startedAt ??
                watch.capturedAt.addingTimeInterval(-watch.confirmedActiveDuration)
            // A Watch snapshot without startedAt may yield a slightly
            // different inferred start every poll. That is not a new
            // workout; rotating the ID would accidentally revoke this
            // session's one-time iPad approval.
            let isNewWatchSession: Bool = {
                guard let previous = mirroredStartedAt else { return true }
                if watch.startedAt != nil { return previous != startedAt }
                return abs(previous.timeIntervalSince(startedAt)) > 5
            }()
            if isNewWatchSession || mirroredSessionID == nil {
                mirroredStartedAt = startedAt
                mirroredSessionID = UUID()
            }
            guard let sessionID = mirroredSessionID else { return nil }
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: sessionID,
                kind: watch.kind.rawValue,
                title: watch.workoutDisplayTitle ?? watch.kind.title,
                startedAt: startedAt,
                elapsedSeconds: watch.confirmedActiveDuration,
                distanceMeters: watch.kind.supportsDistanceMetric &&
                    watch.distanceMeters.isFinite
                    ? max(0, watch.distanceMeters) : nil,
                currentStep: watch.runningStepTitle ?? watch.strengthExerciseName,
                nextStep: watch.runningNextStepTitle ?? watch.strengthNextExerciseName,
                completedSets: nil,
                totalSets: nil,
                paused: watch.state == .paused,
                runningIntervalOrdinal: watch.runningIntervalOrdinal,
                runningIntervalTotal: watch.runningIntervalTotal,
                runningInRecovery: watch.runningInRecovery,
                runningStepRemainingSeconds: watch.runningStepRemainingSeconds,
                capturedAt: watch.capturedAt,
                sourceDevice: "watch",
                heartRateBPM: watch.heartRate > 0
                    ? Double(watch.heartRate) : nil,
                activeCalories: watch.activeCalories > 0
                    ? Double(watch.activeCalories) : nil,
                currentPaceSecondsPerKilometer:
                    watch.currentPaceSecondsPerKilometer,
                targetPaceSecondsPerKilometer:
                    watch.runningStepTargetPaceSecondsPerKilometer,
                targetHeartRateZone: watch.runningStepTargetHeartRateZone,
                runningStepProgress: watch.runningStepProgress,
                runningOverallProgress: watch.runningOverallProgress,
                routeTitle: watch.routeTitle,
                ghostRaceTitle: watch.ghostRaceTitle,
                ghostDistanceDeltaMeters: watch.ghostDistanceDeltaMeters,
                ghostTimeDeltaSeconds: watch.ghostTimeDeltaSeconds,
                runningSteps: watch.runningStageSummaries?.map {
                    ATHLTHLiveWorkoutStage(
                        index: $0.index,
                        title: $0.title,
                        phase: $0.phase ?? "unspecified",
                        durationSeconds: $0.durationSeconds,
                        distanceMeters: $0.distanceMeters
                    )
                },
                runningStepIndex: watch.runningStepIndex,
                runningStepCount: watch.runningStepCount,
                runningStepRemainingMeters: watch.runningStepRemainingMeters,
                routeProgressPercent: watch.routeProgressPercent,
                routeRemainingMeters: watch.routeRemainingMeters,
                routeDistanceMeters: watch.routeDistanceMeters,
                strengthSetNumber: watch.strengthSetIndex,
                strengthSetTotal: watch.strengthSetCount,
                strengthReps: watch.strengthReps,
                strengthWeightKilograms: watch.strengthWeightKilograms,
                strengthRestEndsAt: watch.strengthRestEndsAt,
                audioCoachEnabled: watch.watchAudioCoachEnabled,
                // Watch workout + Spotify playback on the iPhone are separate
                // sources. Relay verified iPhone playback only; never claim
                // to know which track the Watch is playing independently.
                spotifyPlaying: spotify.isPlaying,
                spotifyTrackTitle: spotify.isPlaying
                    ? spotify.watchTrackTitle : nil,
                spotifyArtistName: spotify.isPlaying
                    ? spotify.watchArtistName : nil,
                liveLatitude: {
                    guard let lat = watch.currentLatitude,
                          let lon = watch.currentLongitude,
                          let sampled = watch.currentLocationSampledAt,
                          Self.isFreshPosition(
                              latitude: lat, longitude: lon, sampledAt: sampled
                          ) else { return nil }
                    return lat
                }(),
                liveLongitude: {
                    guard let lat = watch.currentLatitude,
                          let lon = watch.currentLongitude,
                          let sampled = watch.currentLocationSampledAt,
                          Self.isFreshPosition(
                              latitude: lat, longitude: lon, sampledAt: sampled
                          ) else { return nil }
                    return lon
                }(),
                livePositionAt: {
                    guard let lat = watch.currentLatitude,
                          let lon = watch.currentLongitude,
                          let sampled = watch.currentLocationSampledAt,
                          Self.isFreshPosition(
                              latitude: lat, longitude: lon, sampledAt: sampled
                          ) else { return nil }
                    return sampled
                }()
            )
        }
        return nil
    }

    // Only source-provided coordinates are eligible. No location tracking is
    // started by the spectator, and stale coordinates cannot be called live.
    private static func isFreshPosition(
        latitude: Double,
        longitude: Double,
        sampledAt: Date,
        accuracy: Double? = nil,
        now: Date = .now
    ) -> Bool {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              abs(latitude) > 0.00001 || abs(longitude) > 0.00001,
              (-5...30).contains(now.timeIntervalSince(sampledAt))
        else { return false }
        if let accuracy {
            guard accuracy.isFinite, (0...100).contains(accuracy) else {
                return false
            }
        }
        return true
    }

    private func publishLocal(
        accountID: UUID,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore,
        spotify: SpotifyPlaybackStore
    ) async {
        let active = liveSnapshot(
            phone: phone, strength: strength, mirroredWatch: mirroredWatch,
            spotify: spotify
        )
        reconcileSession(active?.id, title: active?.title)
        // Presence is intentionally independent from session-scoped approval.
        // No metrics or workout names enter this table.
        await publishPresence(accountID: accountID, snapshot: active)
        if let active, isApprovedForSession(active.id) {
            let now = Date()
            let row = ATHLTHCrossDeviceWorkoutRow(
                userID: accountID,
                snapshot: active,
                updatedAt: now,
                expiresAt: now.addingTimeInterval(30)
            )
            do {
                try await client.from("private_active_workout_status")
                    .upsert(row, onConflict: "user_id")
                    .execute()
                lastUnauthorisedCleanupAt = nil
                lastPublishedID = active.id
            } catch {
                // Never interrupt a locally recorded workout for spectator sync.
            }
        } else {
            // A restarted iPhone may have lost its in-memory consent while
            // an old network row is still inside its TTL. Clear it even if
            // lastPublishedID was reset by the restart.
            let now = Date()
            let needsCleanup = lastPublishedID != nil ||
                lastUnauthorisedCleanupAt.map {
                    now.timeIntervalSince($0) >= 20
                } ?? true
            if needsCleanup {
                lastUnauthorisedCleanupAt = now
                do {
                    try await client.from("private_active_workout_status")
                        .delete()
                        .eq("user_id", value: accountID)
                        .execute()
                    lastPublishedID = nil
                } catch {
                    // No fallback ever starts a recording or enables viewing.
                    // The previous row expires naturally as a final guard.
                }
            }
        }
    }

    private func publishPresence(
        accountID: UUID,
        snapshot: ATHLTHCrossDeviceWorkoutSnapshot?
    ) async {
        if let snapshot {
            let now = Date()
            let row = ATHLTHCrossDevicePresenceRow(
                userID: accountID,
                sourceDevice: snapshot.sourceDevice == "watch" ? "watch" : "iphone",
                updatedAt: now,
                expiresAt: now.addingTimeInterval(30)
            )
            do {
                try await client.from("private_active_workout_presence")
                    .upsert(row, onConflict: "user_id")
                    .execute()
                lastPresencePublished = true
                lastPresenceCleanupAt = nil
            } catch {
                // A failed heartbeat never interrupts Watch or phone recording.
            }
        } else {
            let now = Date()
            let shouldDelete = lastPresencePublished ||
                lastPresenceCleanupAt.map { now.timeIntervalSince($0) >= 20 } ?? true
            if shouldDelete {
                lastPresenceCleanupAt = now
                do {
                    try await client.from("private_active_workout_presence")
                        .delete()
                        .eq("user_id", value: accountID)
                        .execute()
                    lastPresencePublished = false
                } catch {
                    // Expiring the heartbeat is the offline safety fallback.
                }
            }
        }
    }

    private func readPresence(accountID: UUID) async {
        do {
            let rows: [ATHLTHCrossDevicePresenceRow] = try await client
                .from("private_active_workout_presence")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            let valid = rows.first.flatMap { $0.expiresAt > .now ? $0 : nil }
            remotePresence = valid
            lastPresenceExpiry = valid?.expiresAt
        } catch {
            if lastPresenceExpiry.map({ $0 <= .now }) ?? true {
                remotePresence = nil
                lastPresenceExpiry = nil
            }
        }
    }

    /// iPad can request permission but can never grant it, even for the same
    /// signed-in account. No live metrics are sent until iPhone agrees.
    func requestAccess(accountID: UUID) async {
        guard ATHLTHDeviceRole.isIPad,
              client.auth.currentUser?.id == accountID,
              outgoingRequestState != .sending else { return }

        outgoingRequestState = .sending
        requestError = nil
        let now = Date()
        let request = ATHLTHLiveViewRequest(
            userID: accountID,
            requestID: UUID(),
            requestedAt: now,
            expiresAt: now.addingTimeInterval(120),
            status: "pending",
            respondedAt: nil,
            approvedSessionID: nil
        )
        do {
            try await client.from("private_live_view_requests")
                .upsert(request, onConflict: "user_id")
                .execute()
            outgoingRequestID = request.id
            outgoingRequestState = .pending
            // Best effort APNs only. Sending the request is independent from
            // notification permissions and never grants spectator access.
            Task { await notifyIPhoneAboutRequest(id: request.id, accountID: accountID) }
        } catch {
            outgoingRequestState = .failed
            requestError = ATHLTHLocalization.choose(
                english: "Unable to send the viewing request. Try again.",
                norwegian: "Kunne ikke sende forespørselen. Prøv igjen."
            )
        }
    }

    private func notifyIPhoneAboutRequest(id: UUID, accountID: UUID) async {
        guard ATHLTHDeviceRole.isIPad,
              outgoingRequestID == id,
              client.auth.currentUser?.id == accountID else { return }
        do {
            let reply: ATHLTHLiveAccessPushResult = try await client.functions.invoke(
                "notify-live-workout-request",
                options: FunctionInvokeOptions(
                    body: ["request_id": id.uuidString]
                )
            )
            guard outgoingRequestID == id else { return }
            if !reply.queued,
               reply.reason != "already_notified" {
                requestError = ATHLTHLocalization.choose(
                    english: "Open ATHLTH on your iPhone to approve. A phone notification could not be delivered.",
                    norwegian: "Åpne ATHLTH på iPhone for å godkjenne. Varsel til telefonen kunne ikke leveres."
                )
            }
        } catch {
            guard outgoingRequestID == id else { return }
            requestError = ATHLTHLocalization.choose(
                english: "Open ATHLTH on your iPhone to approve. The request is still waiting.",
                norwegian: "Åpne ATHLTH på iPhone for å godkjenne. Forespørselen venter fortsatt."
            )
        }
    }

    private func pollIncomingRequests(accountID: UUID) async {
        guard !ATHLTHDeviceRole.isIPad,
              lastSourceSessionID != nil,
              !isSharingActiveSession else {
            incomingRequest = nil
            return
        }
        do {
            let rows: [ATHLTHLiveViewRequest] = try await client
                .from("private_live_view_requests")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            let next = rows.first
            incomingRequest = next?.isPending == true ? next : nil
        } catch {
            incomingRequest = nil
        }
    }

    /// The iPhone alone commits the in-memory session grant. Neither an
    /// iPad database update nor a request row can authorize publication.
    func respondToRequest(approve: Bool, accountID: UUID) async {
        guard !ATHLTHDeviceRole.isIPad,
              let request = incomingRequest, request.isPending,
              let exactSessionID = lastSourceSessionID,
              client.auth.currentUser?.id == accountID else { return }

        incomingRequest = nil
        if approve {
            approvedSourceSessionID = exactSessionID
        }
        let decision = ATHLTHLiveViewDecision(
            status: approve ? "approved" : "denied",
            respondedAt: .now,
            approvedSessionID: approve ? exactSessionID : nil
        )
        do {
            try await client.from("private_live_view_requests")
                .update(decision)
                .eq("user_id", value: accountID)
                .eq("request_id", value: request.id)
                .execute()
        } catch {
            // Local permission is decisive; a network error never turns a
            // declined request into an approved session.
        }
    }

    /// Revocation and end-of-workout remove the only live authorization.
    func revokeLiveSharing() {
        approvedSourceSessionID = nil
        shareNextWorkout = false
        nextWorkoutSharingExpiresAt = nil
    }

    private func pollOutgoingRequest(accountID: UUID) async {
        guard ATHLTHDeviceRole.isIPad,
              let requestID = outgoingRequestID,
              client.auth.currentUser?.id == accountID else { return }
        do {
            let rows: [ATHLTHLiveViewRequest] = try await client
                .from("private_live_view_requests")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first, row.id == requestID else {
                outgoingRequestState = .expired
                outgoingRequestID = nil
                return
            }
            if row.expiresAt <= .now {
                outgoingRequestState = .expired
                outgoingRequestID = nil
            } else if row.status == "denied" {
                outgoingRequestState = .denied
                outgoingRequestID = nil
            } else if row.status == "approved" {
                outgoingRequestState = .approved
                outgoingRequestID = nil
            } else {
                outgoingRequestState = .pending
            }
        } catch {
            // A transient network failure must never imply acceptance.
        }
    }

    private func readRemote(accountID: UUID) async {
        do {
            let rows: [ATHLTHCrossDeviceWorkoutRow] = try await client
                .from("private_active_workout_status")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            let row = rows.first
            let next = row.flatMap {
                $0.expiresAt > Date() ? $0.snapshot : nil
            }
            let previous = remote?.id
            if previous != next?.id {
                if foregroundedSinceLastPoll &&
                   !suppressAutoOpenOnNextPoll && next != nil {
                    isExpanded = true
                } else {
                    isExpanded = false
                }
            }
            remote = next
            suppressAutoOpenOnNextPoll = false
            lastRemoteExpiry = next == nil ? nil : row?.expiresAt
            hasLoadedRemote = true
            ATHLTHSurfaceCoordinator.setRemoteWorkout(next.map {
                ATHLTHSurfaceWorkoutSnapshot(
                    title: $0.title,
                    systemImage: $0.symbol,
                    state: $0.paused == true ? "paused" : (
                        $0.kind == "strength" ? "remote_strength" : "running"
                    ),
                    startedAt: $0.startedAt,
                    elapsedTime: $0.elapsedSeconds,
                    distanceMeters: $0.distanceMeters ?? 0,
                    heartRate: 0,
                    updatedAt: row?.updatedAt ?? .now,
                    currentStep: $0.currentStep,
                    nextStep: $0.nextStep,
                    runningIntervalOrdinal: $0.runningIntervalOrdinal,
                    runningIntervalTotal: $0.runningIntervalTotal,
                    runningInRecovery: $0.runningInRecovery,
                    runningStepRemainingSeconds: $0.runningStepRemainingSeconds
                )
            })
        } catch {
            // An offline spectator must not appear permanently live.
            if lastRemoteExpiry.map({ $0 <= Date() }) ?? true {
                remote = nil
                lastRemoteExpiry = nil
                ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
            }
            hasLoadedRemote = true
        }
    }
}
