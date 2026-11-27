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
    var elapsedSeconds: TimeInterval
    var distanceMeters: Double?
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
    /// Original recorder; optional for compatibility with old snapshots.
    var captureEvidence: String? = nil
    var heartRateBPM: Double? = nil
    var activeCalories: Double? = nil
    var currentPaceSecondsPerKilometer: Double? = nil
    var targetPaceSecondsPerKilometer: Double? = nil
    var targetHeartRateZone: Int? = nil
    // Only shared once this specific session is explicitly approved on iPhone.
    // Values describe the *current* programmed step, not recorded health data.
    var maximumHeartRateBPM: Double? = nil
    var appleLiveHeartRateZones: [ATHLTHRecordedHeartRateZone]? = nil
    var targetHeartRateMinimumBPM: Double? = nil
    var targetHeartRateMaximumBPM: Double? = nil
    var targetHeartRatePercentMin: Double? = nil
    var targetHeartRatePercentMax: Double? = nil
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
    /// Only the active exercise's user-recorded weight interpretation.
    /// Optional to decode older owner-approved cross-device snapshots.
    var strengthLoadBasisRaw: String? = nil
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
    // Optional, per-session, source-issued control capability. A viewing
    // grant by itself never includes these values.
    var controlGrantID: UUID? = nil
    var controlDeviceID: String? = nil
    var supportedControls: [ATHLTHRemoteWorkoutAction]? = nil
    // Only a small library reference, never a private media URL or file.
    var gymExerciseGuide: ATHLTHGymExerciseReference? = nil
    var gymStageDuration: TimeInterval? = nil

    var id: UUID { sessionID }
    var symbol: String {
        ATHLTHWorkoutSportMode(category: kind).systemImage
    }
}

 
/// A guide is tied to a specific exercise, not a similar display name.
struct ATHLTHGymExerciseReference: Codable, Equatable {
    let exerciseID: UUID?
    let slug: String?
    let title: String
    let upcoming: Bool

    static func select(blocks: [WorkoutTemplateBlock], index: Int, waiting: Bool = false) -> WorkoutTemplateBlock? {
        guard blocks.indices.contains(index) else { return nil }
        let current = blocks[index]
        if !waiting && current.kind == .exercise && !current.isActiveRecovery { return current }
        guard waiting || current.kind == .rest || current.isActiveRecovery else { return nil }
        // Only look forward through recovery; never show a later strength
        // exercise in place of the next running or other activity.
        return blocks.dropFirst(index + 1)
            .first { $0.kind != .rest && !$0.isActiveRecovery }
            .flatMap { $0.kind == .exercise ? $0 : nil }
    }

    static func make(blocks: [WorkoutTemplateBlock], index: Int, waiting: Bool = false) -> Self? {
        guard let block = select(blocks: blocks, index: index, waiting: waiting) else { return nil }
        return Self(exerciseID: block.exerciseID ?? block.exerciseSnapshot?.libraryExerciseID,
                    slug: block.exerciseSlug, title: String(block.title.prefix(160)),
                    upcoming: waiting || blocks[index].id != block.id)
    }
}

/// Shared read-only sensor provenance and sport-unit eligibility.
/// A spectator is NEVER another recording owner.
enum ATHLTHSpectatorSportMetricPolicy {
    static func supportsDistance(_ category: String) -> Bool {
        switch ATHLTHWorkoutSportMode(category: category) {
        case .running, .walking, .cycling, .rowing: return true
        default: return false
        }
    }

    static func supportsRunningPace(_ category: String) -> Bool {
        switch ATHLTHWorkoutSportMode(category: category) {
        case .running, .walking: return true
        default: return false
        }
    }

    static func showsHeartRateZones(_ category: String) -> Bool {
        switch ATHLTHWorkoutSportMode(category: category) {
        case .running, .walking, .cycling, .rowing, .stairClimber,
             .hiit, .circuit, .functional: return true
        default: return false
        }
    }

    static func isManual(_ evidence: String?) -> Bool {
        evidence == "manualTimer" || evidence == "structuredManual"
    }
}

/// Presentation derived from the original recorded strength session.
struct ATHLTHStrengthSpectatorPresentation: Equatable {
    let kind: String
    let elapsedSeconds: TimeInterval
    let paused: Bool
}

/// The strength journal stays authoritative. When a fresh, same-owner
/// same-UUID Watch mirror is available it can describe the current hybrid
/// segment and HealthKit active clock without creating another recording.
enum ATHLTHStrengthSpectatorLivePolicy {
    static func resolve(
        workoutID: UUID,
        startedAt: Date,
        recordingOwner: ATHLTHWorkoutRecordingOwner,
        local: ATHLTHWorkoutSessionState?,
        journalElapsedSeconds: TimeInterval,
        mirror: WatchWorkoutLiveSnapshot?,
        accountID: UUID?,
        at now: Date = Date()
    ) -> ATHLTHStrengthSpectatorPresentation {
        let original = local.flatMap {
            $0.workoutID == workoutID &&
                $0.recordingOwner == recordingOwner &&
                abs($0.startedAt.timeIntervalSince(startedAt)) <= 5
                ? $0 : nil
        }
        // No wall-clock subtraction: the strength journal owns pause and
        // offline downtime. A non-finite value is not a sensor measurement.
        let baseSeconds = original?.activeElapsedSeconds ?? journalElapsedSeconds
        let seconds = baseSeconds.isFinite && baseSeconds >= 0 ? baseSeconds : 0
        let base = ATHLTHStrengthSpectatorPresentation(
            kind: original?.engine == .endurance ? "running" : "strength",
            elapsedSeconds: seconds,
            paused: original?.phase == .paused
        )

        guard recordingOwner == .appleWatch,
              let mirror, mirror.kind == .strength,
              let accountID,
              let verified = ATHLTHUniversalActiveCapture.mirroredWatch(
                mirror, for: accountID, at: now
              ),
              verified.workoutID == workoutID,
              verified.recordingOwner == .appleWatch,
              abs(verified.startedAt.timeIntervalSince(startedAt)) <= 5
        else { return base }

        return ATHLTHStrengthSpectatorPresentation(
            kind: verified.activityCategory,
            elapsedSeconds: verified.elapsedSeconds,
            paused: verified.phase == .paused
        )
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

enum ATHLTHRemoteWorkoutAction: String, Codable, CaseIterable, Hashable {
    case pause, resume, end, next
    case skipRest = "skip_rest"
}

struct ATHLTHRemoteWorkoutControlCommand: Codable, Identifiable {
    let id: UUID
    let userID: UUID
    let sessionID: UUID
    let targetDeviceID: String
    let grantID: UUID
    let action: ATHLTHRemoteWorkoutAction
    let expectedStep: Int?
    let expectedRestEnd: Date?
    let requestedAt: Date
    let expiresAt: Date
    var status: String = "pending"

    enum CodingKeys: String, CodingKey {
        case id, action, status
        case userID = "user_id"
        case sessionID = "session_id"
        case targetDeviceID = "target_device_id"
        case grantID = "grant_id"
        case expectedStep = "expected_step"
        case expectedRestEnd = "expected_rest_end"
        case requestedAt = "requested_at"
        case expiresAt = "expires_at"
    }
}

enum ATHLTHRemoteWorkoutControlPolicy {
    static func accepts(_ command: ATHLTHRemoteWorkoutControlCommand,
                        accountID: UUID, sessionID: UUID, deviceID: String,
                        grantID: UUID, available: [ATHLTHRemoteWorkoutAction],
                        at now: Date = .now) -> Bool {
        command.userID == accountID && command.sessionID == sessionID &&
        command.targetDeviceID == deviceID && command.grantID == grantID &&
        command.expiresAt > now &&
        (-5...25).contains(now.timeIntervalSince(command.requestedAt)) &&
        command.expiresAt.timeIntervalSince(command.requestedAt) <= 30 &&
        available.contains(command.action)
    }
}

private struct ATHLTHLiveAccessPushResult: Decodable {
    let queued: Bool
    let reason: String?
}

/// A structured iPhone workout uses its own recorder, not IPhoneWorkoutStore.
/// Expose only its *real execution state* to the same privacy-gated publisher.
/// This is not a second recording engine or a source of HealthKit readings.
struct ATHLTHLocalStructuredWorkoutStatus {
    let ownerID: UUID
    let workoutID: UUID
    let title: String
    let kind: String
    let startedAt: Date
    let steps: [ATHLTHLiveWorkoutStage]
    var stepIndex: Int
    var stepEnteredAt: Date
    var completedCount: Int
    var pausedAt: Date? = nil
    var completedPauseSeconds: TimeInterval = 0
    var gymExerciseGuide: ATHLTHGymExerciseReference? = nil

    /// Derive the iPad spectator's live model exclusively from the original
    /// committed, account-scoped structured checkpoint after app restart.
    /// This has no effect on live-sharing authorization or HealthKit.
    static func restored(
        from checkpoint: ATHLTHStructuredWorkoutCheckpoint,
        ownerID: UUID
    ) -> ATHLTHLocalStructuredWorkoutStatus? {
        guard checkpoint.executionBlocks.indices.contains(checkpoint.currentIndex),
              checkpoint.startedAt.timeIntervalSince1970.isFinite,
              checkpoint.stepEnteredAt.timeIntervalSince1970.isFinite,
              checkpoint.completedPauseSeconds.map({
                  $0.isFinite && $0 >= 0
              }) ?? true else { return nil }
        let current = checkpoint.executionBlocks[checkpoint.currentIndex]
        let category = current.kind == .rest || current.isActiveRecovery
            ? ATHLTHWorkoutSportMode.recovery.category
            : ATHLTHWorkoutSportMode.forBlock(current).category
        return ATHLTHLocalStructuredWorkoutStatus(
            ownerID: ownerID,
            workoutID: checkpoint.workoutID,
            title: checkpoint.sourceTitle ?? ATHLTHLocalization.choose(
                english: "Workout", norwegian: "Treningsøkt"
            ),
            kind: category,
            startedAt: checkpoint.startedAt,
            steps: checkpoint.executionBlocks.enumerated().map { index, block in
                ATHLTHLiveWorkoutStage(
                    index: index,
                    title: block.title,
                    phase: block.resolvedPhase.rawValue,
                    durationSeconds: block.durationSeconds,
                    distanceMeters: block.distanceMeters
                )
            },
            stepIndex: checkpoint.currentIndex,
            stepEnteredAt: checkpoint.stepEnteredAt,
            completedCount: checkpoint.completedIDs.count,
            pausedAt: checkpoint.pausedAt,
            completedPauseSeconds: checkpoint.completedPauseSeconds ?? 0,
            gymExerciseGuide: ATHLTHGymExerciseReference.make(
                blocks: checkpoint.executionBlocks, index: checkpoint.currentIndex,
                waiting: checkpoint.emomWaiting)
        )
    }
}

/// The private spectator relays ONE original structured checkpoint with
/// manual-source evidence, and never turns programmed targets into sensors.
enum ATHLTHStructuredSpectatorSnapshot {
    static func make(
        _ structured: ATHLTHLocalStructuredWorkoutStatus,
        at now: Date = Date()
    ) -> ATHLTHCrossDeviceWorkoutSnapshot? {
        guard structured.steps.indices.contains(structured.stepIndex),
              let elapsed = ATHLTHStructuredWorkoutClock.elapsed(
                start: structured.startedAt,
                now: now,
                pause: structured.pausedAt,
                pausedSeconds: structured.completedPauseSeconds
              ) else { return nil }
        let step = structured.steps[structured.stepIndex]
        let nextIndex = structured.stepIndex + 1
        let effective = ATHLTHStructuredWorkoutClock.at(
            now, pause: structured.pausedAt
        ) ?? now
        let remaining = step.durationSeconds.map {
            max(0, $0 - effective.timeIntervalSince(structured.stepEnteredAt))
        }
        return ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: structured.workoutID,
            kind: structured.kind,
            title: structured.title,
            startedAt: structured.startedAt,
            elapsedSeconds: elapsed,
            distanceMeters: nil,
            currentStep: step.title,
            nextStep: structured.steps.indices.contains(nextIndex)
                ? structured.steps[nextIndex].title : nil,
            completedSets: structured.completedCount,
            totalSets: structured.steps.count,
            paused: structured.pausedAt != nil,
            runningStepRemainingSeconds: remaining,
            capturedAt: now,
            sourceDevice: "iphone",
            captureEvidence: "structuredManual",
            runningSteps: structured.steps,
            runningStepIndex: structured.stepIndex,
            runningStepCount: structured.steps.count,
            gymExerciseGuide: structured.gymExerciseGuide,
            gymStageDuration: step.durationSeconds
        )
    }
}

/// Read-only same-account manual timer rendering. It contains no HealthKit
/// measurements and uses the original saved Custom Quick ID and clock.
/// This is NOT a second recorder or a permission to publish without consent.
enum ATHLTHManualSpectatorSnapshot {
    static func make(
        _ checkpoint: ATHLTHManualTimedCheckpoint,
        at now: Date = Date()
    ) -> ATHLTHCrossDeviceWorkoutSnapshot? {
        guard let session = ATHLTHUniversalActiveCapture.manual(
            checkpoint, at: now
        ), let timeline = ATHLTHCustomWorkoutTimeline.state(
            method: checkpoint.method,
            durationMinutes: checkpoint.durationMinutes,
            workSeconds: checkpoint.workSeconds,
            restSeconds: checkpoint.restSeconds,
            rounds: checkpoint.rounds,
            elapsedSeconds: session.elapsedSeconds,
            isPaused: session.phase == .paused
        ) else { return nil }

        let label: String?
        if session.phase == .paused {
            label = ATHLTHLocalization.choose(
                english: "Paused", norwegian: "Pauset"
            )
        } else if timeline.stageIndex != nil {
            label = timeline.inRestInterval
                ? ATHLTHLocalization.choose(
                    english: "Rest", norwegian: "Pause"
                ) : ATHLTHLocalization.choose(
                    english: "Work", norwegian: "Arbeid"
                )
        } else {
            label = nil
        }

        return ATHLTHCrossDeviceWorkoutSnapshot(
            sessionID: checkpoint.id,
            kind: checkpoint.activity.rawValue,
            title: checkpoint.titleOverride ?? checkpoint.activity.localizedTitle,
            startedAt: checkpoint.startedAt,
            elapsedSeconds: session.elapsedSeconds,
            distanceMeters: nil,
            currentStep: label,
            nextStep: nil,
            completedSets: nil,
            totalSets: nil,
            paused: session.phase == .paused,
            runningIntervalOrdinal: timeline.stageIndex.map { $0 + 1 },
            runningIntervalTotal: timeline.stageCount,
            runningInRecovery: timeline.inRestInterval,
            runningStepRemainingSeconds: timeline.remainingSeconds,
            capturedAt: now,
            sourceDevice: "iphone",
            captureEvidence: "manualTimer"
        )
    }
}

/// Session identity and account authorization for the existing private
/// Watch-to-iPad spectator. It is read-only; it never starts a workout.
enum ATHLTHWatchSpectatorSessionPolicy {
    /// The spectator uses the same active-sport policy as the universal
    /// recorder projection. Strength-owned run/rest hybrids must not
    /// become a second HealthKit workout just to display their phase.
    static func activeCategory(_ watch: WatchWorkoutLiveSnapshot) -> String {
        ATHLTHWatchLiveSportPolicy.activityCategory(watch)
    }

    /// Only native Watch running/walking sources can supply MEASURED pace.
    /// A treadmill target carried inside a strength-owned hybrid is a
    /// prescription, never proof that HealthKit sampled current run pace.
    static func measuredPace(
        _ watch: WatchWorkoutLiveSnapshot,
        at now: Date = Date()
    ) -> Double? {
        ATHLTHWatchVerifiedLiveMetrics.measuredPaceSecondsPerKilometer(
            from: watch, at: now
        )
    }

    static func canRelay(
        _ snapshot: WatchWorkoutLiveSnapshot,
        to accountID: UUID?
    ) -> Bool {
        guard let accountID,
              let sourceOwner = snapshot.accountOwnerID else {
            return false
        }
        return sourceOwner == accountID
    }

    static func hasContradictoryIdentity(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> Bool {
        snapshot.kind == .strength &&
            snapshot.universalWorkoutID != nil &&
            snapshot.strengthWorkoutID != nil &&
            snapshot.universalWorkoutID != snapshot.strengthWorkoutID
    }

    static func verifiedID(
        _ snapshot: WatchWorkoutLiveSnapshot
    ) -> UUID? {
        guard !hasContradictoryIdentity(snapshot) else { return nil }
        if snapshot.kind == .strength {
            return snapshot.strengthWorkoutID ?? snapshot.universalWorkoutID
        }
        return snapshot.universalWorkoutID
    }
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
    // Presence transport status is separate from consent-protected metrics.
    // Avoid silently treating a failed request as "no workout".
    @Published private(set) var presenceConnectionIssue = false
    @Published private(set) var hasCheckedPresence = false
    /// Explicit opt-in only for the next workout, never a saved preference.
    @Published var shareNextWorkout = false
    @Published private(set) var incomingRequest: ATHLTHLiveViewRequest?
    @Published private(set) var outgoingRequestState: ATHLTHLiveViewRequestState = .idle
    @Published private(set) var requestError: String?
    @Published private(set) var sourceWorkoutTitle: String?
    @Published private(set) var pendingRemoteControlID: UUID?
    @Published private(set) var remoteControlMessage: String?
    private var pendingRemoteControlExpiry: Date?
    private var pendingRemoteControlSessionID: UUID?
    private var controlGrantID: UUID?
    private var lastDeviceHeartbeatAt: Date?

    private var lastSourceSessionID: UUID?
    private var lastSourceStartedAt: Date?
    private var trackingAccountID: UUID?
    private var trackingGeneration = UUID()

    private func ownsTracking(_ accountID: UUID, generation: UUID) -> Bool {
        !Task.isCancelled && trackingGeneration == generation &&
            trackingAccountID == accountID && client.auth.currentUser?.id == accountID
    }

    private var structuredSession: ATHLTHLocalStructuredWorkoutStatus?
    private var approvedSourceSessionID: UUID?
    private var nextWorkoutSharingExpiresAt: Date?
    private var outgoingRequestID: UUID?
    private var outgoingRequestExpiresAt: Date?
    private var pollingLease = ATHLTHCrossDevicePollingLease()
    private var foregroundSceneIDs: Set<UUID> = []
    private var autoPresentedSessionID: UUID?

    /// Only this phone's live, locally confirmed session authorizes publishing.
    func isApprovedForSession(_ sessionID: UUID) -> Bool {
        !ATHLTHDeviceRole.isIPad && approvedSourceSessionID == sessionID
    }

    var isSharingActiveSession: Bool {
        approvedSourceSessionID != nil &&
        approvedSourceSessionID == lastSourceSessionID
    }

    func updateStructuredSession(_ status: ATHLTHLocalStructuredWorkoutStatus) {
        guard !ATHLTHDeviceRole.isIPad,
              status.ownerID == trackingAccountID else { return }
        structuredSession = status
    }

    func endStructuredSession(workoutID: UUID) {
        guard structuredSession?.workoutID == workoutID else { return }
        structuredSession = nil
        // Poller clears its private presence and metrics on its next cycle.
        reconcileSession(nil, title: nil)
    }

    /// A toggle is armed for one workout only. No account-wide auto-share.
    func prepareOneWorkoutSharing(_ enabled: Bool) {
        guard !ATHLTHDeviceRole.isIPad else { return }
        shareNextWorkout = enabled
        nextWorkoutSharingExpiresAt = enabled
            ? Date().addingTimeInterval(600) : nil
    }

    private func reconcileSession(
        _ currentID: UUID?, title: String?, startedAt: Date? = nil
    ) {
        guard lastSourceSessionID != currentID else { return }
        approvedSourceSessionID = nil
        controlGrantID = nil
        incomingRequest = nil
        lastSourceSessionID = currentID
        lastSourceStartedAt = startedAt
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
    private var lastPublishedPresenceSessionID: UUID?
    private var lastPublishedPresenceSource: String?
    private var lastPublishedPresenceAt: Date?
    private var lastSpotifySpectatorRefreshAt: Date?
    private var lastPresenceCleanupAt: Date?
    private var lastPresenceExpiry: Date?
    private var lastUnauthorisedCleanupAt: Date?
    private var mirroredStartedAt: Date?
    private var mirroredSessionID: UUID?
    // Invalidate overlapping polls (and responses from an old account).
    // A late response must not restore revoked or expired spectator data.
    private var remoteReadGeneration: UInt64 = 0
    private var presenceReadGeneration: UInt64 = 0
    private var lastRemoteExpiry: Date?
    private var hasLoadedRemote = false
    /// Scene lifecycle is per-window. A backgrounded Stage Manager scene
    /// cannot mark another active scene as backgrounded.
    func setSceneActive(_ active: Bool, sceneID: UUID) {
        if active {
            foregroundSceneIDs.insert(sceneID)
            expireOutgoingRequestIfNeeded()
        } else {
            foregroundSceneIDs.remove(sceneID)
        }
    }

    /// At most ONE iPad window may automatically present a newly approved
    /// recording. Other windows can still open it explicitly. A reconnect
    /// to the same session cannot silently undo manual minimization.
    func claimInitialPresentation(
        sessionID: UUID?,
        sceneID: UUID
    ) -> Bool {
        guard ATHLTHDeviceRole.isIPad,
              let sessionID,
              foregroundSceneIDs.contains(sceneID),
              autoPresentedSessionID != sessionID else { return false }
        autoPresentedSessionID = sessionID
        return true
    }

    private func expireOutgoingRequestIfNeeded(at now: Date = Date()) {
        guard ATHLTHiPadLiveRequestExpiryPolicy.isExpired(
            state: outgoingRequestState,
            expiry: outgoingRequestExpiresAt,
            at: now
        ) else { return }
        outgoingRequestState = .expired
        outgoingRequestID = nil
        outgoingRequestExpiresAt = nil
    }

    func clearLocalState() {
        trackingGeneration = UUID()
        remoteReadGeneration &+= 1
        presenceReadGeneration &+= 1
        pollingLease.reset()
        // Foreground scene tokens represent active UI windows, not any
        // account's data. Keep them through auth refresh so a session
        // loaded just after sign-in can still be presented once. The
        // account-bound recording and auto-open identity are reset below.
        autoPresentedSessionID = nil
        remote = nil
        remotePresence = nil
        presenceConnectionIssue = false
        hasCheckedPresence = false
        trackingAccountID = nil
        structuredSession = nil
        lastPresenceExpiry = nil
        lastPresencePublished = false
        lastPublishedPresenceSessionID = nil
        lastPublishedPresenceSource = nil
        lastPublishedPresenceAt = nil
        lastPresenceCleanupAt = nil
        lastSpotifySpectatorRefreshAt = nil
        lastPublishedID = nil
        lastUnauthorisedCleanupAt = nil
        shareNextWorkout = false
        nextWorkoutSharingExpiresAt = nil
        incomingRequest = nil
        outgoingRequestID = nil
        outgoingRequestExpiresAt = nil
        outgoingRequestState = .idle
        requestError = nil
        approvedSourceSessionID = nil
        controlGrantID = nil
        lastDeviceHeartbeatAt = nil
        pendingRemoteControlID = nil
        pendingRemoteControlExpiry = nil
        pendingRemoteControlSessionID = nil
        remoteControlMessage = nil
        lastSourceSessionID = nil
        lastSourceStartedAt = nil
        sourceWorkoutTitle = nil
        mirroredStartedAt = nil
        mirroredSessionID = nil
        lastRemoteExpiry = nil
        hasLoadedRemote = false
        ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
    }

    func track(
        signedIn: Bool,
        accountID: UUID,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore,
        spotify: SpotifyPlaybackStore,
        watchConnection: AppleWatchConnectionStore? = nil,
        appSession: AppSessionStore? = nil
    ) async {
        guard signedIn else {
            clearLocalState()
            return
        }
        // Shared Store survives scenes; never display another account's
        // transient live status while a new account authenticates.
        if trackingAccountID != accountID {
            clearLocalState()
            trackingAccountID = accountID
        }
        let generation = trackingGeneration
        let isPad = ATHLTHDeviceRole.isIPad
        let thisPoller = UUID()
        defer {
            pollingLease.release(thisPoller)
        }
        while !Task.isCancelled && trackingAccountID == accountID && trackingGeneration == generation {
            // Expiration is local: a network outage or auth refresh cannot
            // keep a superseded iPad permission request pending indefinitely.
            if isPad { expireOutgoingRequestIfNeeded() }
            // Only one scene of a signed-in account may poll/update
            // Supabase at a time. A standby scene never clears the live
            // UI while the owner is still reading network responses.
            let ownsPolling = pollingLease.claim(thisPoller)
            // Do not trust local profile IDs as authorization: every request
            // also requires the active Supabase session to match that ID.
            if ownsPolling && client.auth.currentUser?.id == accountID {
                if isPad {
                    await readPresence(accountID: accountID)
                    guard ownsTracking(accountID, generation: generation) else { break }
                    await readRemote(accountID: accountID)
                    guard ownsTracking(accountID, generation: generation) else { break }
                    await pollOutgoingRequest(accountID: accountID)
                    guard ownsTracking(accountID, generation: generation) else { break }
                    await pollRemoteControlReceipt(accountID: accountID)
                } else {
                    // The Web API may report an active Spotify Connect player
                    // on Watch even when the iPhone App Remote is not attached.
                    // Read-only refreshes are throttled and never start music.
                    if mirroredWatch.hasActiveMirroredWorkout,
                       spotify.isConnected {
                        let now = Date()
                        if lastSpotifySpectatorRefreshAt.map({
                            now.timeIntervalSince($0) >= 20
                        }) ?? true {
                            lastSpotifySpectatorRefreshAt = now
                            await spotify.refreshPlaybackForLiveSpectator()
                        }
                    }
                    guard ownsTracking(accountID, generation: generation) else { break }
                    await publishLocal(
                        accountID: accountID, phone: phone,
                        strength: strength, mirroredWatch: mirroredWatch,
                        spotify: spotify
                    )
                    guard ownsTracking(accountID, generation: generation) else { break }
                    await pollIncomingRequests(accountID: accountID)
                    guard ownsTracking(accountID, generation: generation) else { break }
                    await publishDeviceHeartbeat(accountID: accountID, watchConnection: watchConnection)
                    guard ownsTracking(accountID, generation: generation) else { break }
                    await pollRemoteControlCommands(accountID: accountID, phone: phone,
                        strength: strength, mirroredWatch: mirroredWatch, spotify: spotify,
                        appSession: appSession)
                }
            } else if ownsPolling && isPad {
                // Authentication may be refreshing after launch. This isn't
                // proof that the iPhone is idle; show a reconnecting status.
                remote = nil
                remotePresence = nil
                presenceConnectionIssue = true
                hasCheckedPresence = true
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
        // This spectator can only publish one verified source at a time.
        // No priority branch may hide a second competing active journal.
        guard ATHLTHUniversalActiveCapture.sourcesConsistent(
            running: phone.activeSessionState,
            strength: strength.activeSessionState,
            manualActive: ATHLTHManualTimedCapture.hasActiveCapture,
            structuredActive: ATHLTHStructuredCaptureAdmission.hasActiveCapture,
            watchMirrorActive: mirroredWatch.hasActiveMirroredWorkout ||
                ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive,
            mirrorStrengthWorkoutID:
                mirroredWatch.snapshot?.strengthWorkoutID,
            mirrorStartedAt: mirroredWatch.snapshot?.startedAt
        ) else { return nil }
        if let log = strength.activeWorkout {
            let now = Date()
            let display = ATHLTHStrengthSpectatorLivePolicy.resolve(
                workoutID: log.id,
                startedAt: log.startedAt,
                recordingOwner: log.captureDevice == .appleWatch
                    ? .appleWatch : .iPhone,
                local: strength.activeSessionState,
                journalElapsedSeconds: log.elapsedSessionSeconds(
                    at: now, suspendedAt: nil
                ),
                mirror: mirroredWatch.snapshot,
                accountID: trackingAccountID,
                at: now
            )
            let exercise = strength.currentExerciseIndex
            let activeName = log.exercises.indices.contains(exercise)
                ? log.exercises[exercise].exercise.displayName
                : nil
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: log.id,
                kind: display.kind,
                title: log.title,
                startedAt: log.startedAt,
                elapsedSeconds: display.elapsedSeconds,
                distanceMeters: nil,
                currentStep: activeName,
                nextStep: strength.nextExecutionLabel,
                completedSets: log.totalCompletedSets,
                totalSets: log.exercises.reduce(0) { $0 + $1.sets.count },
                paused: display.paused,
                capturedAt: now,
                sourceDevice: log.captureDevice == .appleWatch
                    ? "watch" : "iphone",
                captureEvidence: log.captureDevice == .appleWatch
                    ? "watchHealthKit" : "strengthLog",
                strengthSetNumber: strength.currentSet?.setNumber,
                strengthSetTotal: strength.currentExercise?.sets.count,
                strengthReps: strength.currentSet?.plannedReps,
                strengthWeightKilograms:
                    strength.currentSet?.plannedWeightKilograms,
                strengthLoadBasisRaw:
                    strength.currentExercise?.exercise.coachLoadBasis?.rawValue,
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
                    spotify.isPlaying ? spotify.watchArtistName : nil,
                gymExerciseGuide: strength.currentExercise.map {
                    ATHLTHGymExerciseReference(exerciseID: $0.exercise.libraryExerciseID,
                        slug: nil, title: String($0.exercise.displayName.prefix(160)),
                        upcoming: strength.restEndsAt.map { $0 > now } ?? false)
                },
                gymStageDuration: strength.restStartedAt.flatMap { start in
                    strength.restEndsAt.map { $0.timeIntervalSince(start) }
                }
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
                captureEvidence: run.runEnvironment == .treadmill
                    ? "treadmillEstimate" : "phoneGPS",
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
                maximumHeartRateBPM:
                    run.structuredRunningWorkout?.heartRateZoneMaximumBPM ??
                    run.audioCoachConfiguration?.smartPrompts?.maximumHeartRateBPM,
                targetHeartRatePercentMin: current?.targetHeartRatePercentMin,
                targetHeartRatePercentMax: current?.targetHeartRatePercentMax,
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
        // SwiftUI's transient live status is lost on process termination.
        // Restore only from the same-account, original persisted checkpoint.
        // This remains behind reconcileSession's existing opt-in consent.
        // While the original screen is open, use its committed status:
        // avoid decoding a possibly large multi-sport recipe each poll.
        // Only a missing transient status requires account-scoped recovery.
        let liveStructured = structuredSession?.ownerID == trackingAccountID
            ? structuredSession : nil
        let recoveredStructured: ATHLTHLocalStructuredWorkoutStatus? =
            liveStructured == nil ? trackingAccountID.flatMap { accountID in
                ATHLTHStructuredCaptureAdmission.activeCheckpoint(
                    for: accountID
                ).flatMap {
                    ATHLTHLocalStructuredWorkoutStatus.restored(
                        from: $0, ownerID: accountID
                    )
                }
            } : nil
        let activeStructured = liveStructured ?? recoveredStructured
        if let activeStructured,
           !mirroredWatch.hasActiveMirroredWorkout {
            return ATHLTHStructuredSpectatorSnapshot.make(activeStructured)
        }
        // Manual timed sessions now participate in the same opt-in iPad
        // spectator pipeline. Never publish a false pulse, pace, calorie,
        // distance or GPS sample from a timer.
        if let accountID = trackingAccountID,
           let manual = ATHLTHManualTimedCapture.current(for: accountID),
           !mirroredWatch.hasActiveMirroredWorkout {
            return ATHLTHManualSpectatorSnapshot.make(manual)
        }
        if let watch = mirroredWatch.snapshot,
           (watch.state == .preparing ||
            watch.state == .running ||
            watch.state == .paused),
           ATHLTHWatchSpectatorSessionPolicy.canRelay(
               watch, to: trackingAccountID
           ),
           !ATHLTHWatchSpectatorSessionPolicy.hasContradictoryIdentity(
               watch
           ) {
            // Watch remains the only HealthKit sensor/recording source. The
            // iPhone only relays a private summary to the signed-in iPad.
            let startedAt = watch.startedAt ??
                watch.capturedAt.addingTimeInterval(-watch.confirmedActiveDuration)
            // A Watch snapshot without startedAt may yield a slightly
            // different inferred start every poll. That is not a new
            // workout; rotating the ID would accidentally revoke this
            // session's one-time iPad approval.
            let verifiedWatchID =
                ATHLTHWatchSpectatorSessionPolicy.verifiedID(watch)
            let isNewWatchSession: Bool = {
                // For current Watch sessions, the original UUID replaces
                // ephemeral timestamp correlation. A reconnect must retain
                // the same spectator identity and one-time consent.
                if let verifiedWatchID {
                    return mirroredSessionID != verifiedWatchID
                }
                guard let previous = mirroredStartedAt else { return true }
                if watch.startedAt != nil { return previous != startedAt }
                return abs(previous.timeIntervalSince(startedAt)) > 5
            }()
            if isNewWatchSession || mirroredSessionID == nil {
                mirroredStartedAt = startedAt
                // Older Watch versions have no stable workout UUID.
                // Preserve their existing ephemeral, source-local ID.
                mirroredSessionID = verifiedWatchID ?? UUID()
            }
            guard let sessionID = mirroredSessionID else { return nil }
            // Split the large snapshot into typed assignments: a single
            // 45-field memberwise initializer exhausted Swift's type checker.
            let verifiedPosition: (latitude: Double, longitude: Double, at: Date)? = {
                guard let latitude = watch.currentLatitude,
                      let longitude = watch.currentLongitude,
                      let sampled = watch.currentLocationSampledAt,
                      Self.isFreshPosition(
                          latitude: latitude, longitude: longitude, sampledAt: sampled
                      ) else { return nil }
                return (latitude, longitude, sampled)
            }()
            let freshHeartRate =
                ATHLTHWatchVerifiedLiveMetrics.measuredHeartRateBPM(
                    from: watch
                )
            var snapshot = ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: sessionID,
                kind: ATHLTHWatchSpectatorSessionPolicy.activeCategory(watch),
                title: watch.workoutDisplayTitle ?? watch.kind.title,
                startedAt: startedAt,
                elapsedSeconds: watch.confirmedActiveDuration,
                distanceMeters:
                    ATHLTHWatchVerifiedLiveMetrics.measuredDistanceMeters(
                        from: watch
                    ),
                currentStep: watch.runningStepTitle ?? watch.strengthExerciseName,
                nextStep: watch.runningNextStepTitle ?? watch.strengthNextExerciseName,
                completedSets: nil,
                totalSets: nil
            )
            snapshot.paused = watch.state == .paused
            snapshot.runningIntervalOrdinal = watch.runningIntervalOrdinal
            snapshot.runningIntervalTotal = watch.runningIntervalTotal
            // A Watch-owned strength hybrid carries its real rest phase
            // without changing the original strength recording category.
            snapshot.runningInRecovery =
                watch.kind == .strength && watch.strengthRecoveryActive == true
                ? true : watch.runningInRecovery
            snapshot.runningStepRemainingSeconds = watch.runningStepRemainingSeconds
            snapshot.capturedAt = watch.capturedAt
            snapshot.sourceDevice = "watch"
            snapshot.captureEvidence = "watchHealthKit"
            snapshot.heartRateBPM = freshHeartRate
            snapshot.activeCalories =
                ATHLTHWatchVerifiedLiveMetrics.measuredActiveCalories(
                    from: watch
                )
            snapshot.currentPaceSecondsPerKilometer =
                ATHLTHWatchSpectatorSessionPolicy.measuredPace(watch)
            // A target may remain visible on a strength-owned running
            // interval; it must never be presented as measured speed.
            snapshot.targetPaceSecondsPerKilometer =
                watch.runningStepTargetPaceSecondsPerKilometer
            snapshot.targetHeartRateZone =
                watch.runningStepTargetHeartRateZone ?? watch.heartRateTargetZone
            snapshot.maximumHeartRateBPM = watch.coachResolvedMaximumHeartRateBPM
            snapshot.appleLiveHeartRateZones = watch.appleLiveHeartRateZones.flatMap(ATHLTHRecordedHeartRateZones.validated)
            snapshot.targetHeartRateMinimumBPM = watch.heartRateTargetMinimumBPM
            snapshot.targetHeartRateMaximumBPM = watch.heartRateTargetMaximumBPM
            snapshot.runningStepProgress = watch.runningStepProgress
            snapshot.runningOverallProgress = watch.runningOverallProgress
            snapshot.routeTitle = watch.routeTitle
            snapshot.ghostRaceTitle = watch.ghostRaceTitle
            snapshot.ghostDistanceDeltaMeters = watch.ghostDistanceDeltaMeters
            snapshot.ghostTimeDeltaSeconds = watch.ghostTimeDeltaSeconds
            snapshot.runningSteps = watch.runningStageSummaries?.map {
                ATHLTHLiveWorkoutStage(
                    index: $0.index,
                    title: $0.title,
                    phase: $0.phase ?? "unspecified",
                    durationSeconds: $0.durationSeconds,
                    distanceMeters: $0.distanceMeters
                )
            }
            snapshot.runningStepIndex = watch.runningStepIndex
            snapshot.runningStepCount = watch.runningStepCount
            snapshot.runningStepRemainingMeters = watch.runningStepRemainingMeters
            snapshot.routeProgressPercent = watch.routeProgressPercent
            snapshot.routeRemainingMeters = watch.routeRemainingMeters
            snapshot.routeDistanceMeters = watch.routeDistanceMeters
            snapshot.strengthSetNumber = watch.strengthSetIndex
            snapshot.strengthSetTotal = watch.strengthSetCount
            snapshot.strengthReps = watch.strengthReps
            snapshot.strengthWeightKilograms = watch.strengthWeightKilograms
            snapshot.strengthRestEndsAt = watch.strengthRestEndsAt
            if watch.kind == .strength, let index = watch.strengthExerciseIndex,
               let entry = watch.socialStrengthExerciseQueue?.first(where: { $0.index == index }),
               entry.isEmbeddedRunningInterval != true {
                snapshot.gymExerciseGuide = ATHLTHGymExerciseReference(
                    exerciseID: entry.libraryExerciseID, slug: nil,
                    title: String(entry.name.prefix(160)),
                    upcoming: watch.strengthRestEndsAt.map { $0 > watch.capturedAt } ?? false)
            }
            snapshot.audioCoachEnabled = watch.watchAudioCoachEnabled
            // Spotify is only shown when account playback is confirmed.
            snapshot.spotifyPlaying = spotify.isPlaying
            snapshot.spotifyTrackTitle = spotify.isPlaying
                ? spotify.watchTrackTitle : nil
            snapshot.spotifyArtistName = spotify.isPlaying
                ? spotify.watchArtistName : nil
            snapshot.liveLatitude = verifiedPosition?.latitude
            snapshot.liveLongitude = verifiedPosition?.longitude
            snapshot.livePositionAt = verifiedPosition?.at
            return snapshot
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

    /// Supabase rejects snapshots larger than its 16 KB JSONB limit. Long
    /// interval plans must keep publishing live progress rather than silently
    /// losing iPad updates. Prefer the current phase, nearby steps and recent
    /// splits; every omitted field remains optional on the read-only viewer.
    static func boundedSpectatorSnapshot(
        _ input: ATHLTHCrossDeviceWorkoutSnapshot
    ) -> ATHLTHCrossDeviceWorkoutSnapshot {
        var output = input
        func finite(_ value: Double?) -> Double? {
            guard let value, value.isFinite else { return nil }
            return value
        }
        output.elapsedSeconds = input.elapsedSeconds.isFinite
            ? max(0, input.elapsedSeconds) : 0
        output.distanceMeters = finite(input.distanceMeters)
        output.heartRateBPM = finite(input.heartRateBPM)
        output.activeCalories = finite(input.activeCalories)
        output.currentPaceSecondsPerKilometer = finite(
            input.currentPaceSecondsPerKilometer
        )
        output.targetPaceSecondsPerKilometer = finite(
            input.targetPaceSecondsPerKilometer
        )
        // min/km only applies to running and walking. Cycling and rowing
        // calculate their sport-specific average from measured distance.
        if !ATHLTHSpectatorSportMetricPolicy.supportsRunningPace(input.kind) {
            output.currentPaceSecondsPerKilometer = nil
            output.targetPaceSecondsPerKilometer = nil
            output.paceIsTreadmillTarget = nil
        }
        if !ATHLTHSpectatorSportMetricPolicy.supportsDistance(input.kind) {
            output.distanceMeters = nil
        }
        output.maximumHeartRateBPM = finite(input.maximumHeartRateBPM)
        output.appleLiveHeartRateZones = input.appleLiveHeartRateZones.flatMap(ATHLTHRecordedHeartRateZones.validated)
        output.targetHeartRateMinimumBPM = finite(
            input.targetHeartRateMinimumBPM
        )
        output.targetHeartRateMaximumBPM = finite(
            input.targetHeartRateMaximumBPM
        )
        output.targetHeartRatePercentMin = finite(input.targetHeartRatePercentMin)
        output.targetHeartRatePercentMax = finite(input.targetHeartRatePercentMax)
        output.runningStepProgress = finite(input.runningStepProgress)
        output.runningOverallProgress = finite(input.runningOverallProgress)
        output.runningStepRemainingSeconds = finite(
            input.runningStepRemainingSeconds
        )
        output.gymStageDuration = finite(input.gymStageDuration)
        if let guide = output.gymExerciseGuide {
            output.gymExerciseGuide = ATHLTHGymExerciseReference(
                exerciseID: guide.exerciseID, slug: guide.slug.map { String($0.prefix(160)) },
                title: String(guide.title.prefix(160)), upcoming: guide.upcoming)
        }
        output.runningStepRemainingMeters = finite(
            input.runningStepRemainingMeters
        )
        output.routeProgressPercent = finite(input.routeProgressPercent)
        output.routeRemainingMeters = finite(input.routeRemainingMeters)
        output.routeDistanceMeters = finite(input.routeDistanceMeters)
        output.ghostDistanceDeltaMeters = finite(input.ghostDistanceDeltaMeters)
        output.ghostTimeDeltaSeconds = finite(input.ghostTimeDeltaSeconds)
        output.strengthWeightKilograms = finite(
            input.strengthWeightKilograms
        )
        // Never forward arbitrary labels: only supported, explicit choices
        // recorded on the source exercise may appear on the companion.
        output.strengthLoadBasisRaw = input.kind == "strength"
            ? input.strengthLoadBasisRaw.flatMap {
                ATHLTHStrengthLoadBasis(rawValue: $0)?.rawValue
            } : nil
        output.liveLatitude = finite(input.liveLatitude)
        output.liveLongitude = finite(input.liveLongitude)
        // Never treat timer-based iPhone activities as HealthKit telemetry.
        if ATHLTHSpectatorSportMetricPolicy.isManual(input.captureEvidence) {
            output.distanceMeters = nil
            output.currentPaceSecondsPerKilometer = nil
            output.heartRateBPM = nil
            output.activeCalories = nil
            output.liveLatitude = nil
            output.liveLongitude = nil
            output.livePositionAt = nil
        }
        if output.liveLatitude == nil || output.liveLongitude == nil {
            output.liveLatitude = nil
            output.liveLongitude = nil
            output.livePositionAt = nil
        }
        if let steps = output.runningSteps {
            output.runningSteps = steps.filter {
                ($0.durationSeconds?.isFinite ?? true) &&
                ($0.distanceMeters?.isFinite ?? true)
            }
        }
        if let splits = output.recentSplits,
           (try? JSONEncoder().encode(splits)) == nil {
            output.recentSplits = nil
        }
        if let steps = output.runningSteps, steps.count > 24 {
            let index = max(0, output.runningStepIndex ?? 0)
            let start = min(max(0, index - 8), steps.count - 24)
            output.runningSteps = Array(steps[start..<(start + 24)])
        }
        if let exercises = output.strengthExercises, exercises.count > 20 {
            output.strengthExercises = Array(exercises.prefix(20))
        }
        if let splits = output.recentSplits, splits.count > 8 {
            output.recentSplits = Array(splits.suffix(8))
        }
        // Leave headroom for JSONB's representation and database constraints.
        if let size = try? JSONEncoder().encode(output).count, size > 12_000 {
            output.runningSteps = nil
            output.strengthExercises = nil
            output.recentSplits = nil
        }
        return output
    }

    private func publishLocal(
        accountID: UUID,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore,
        spotify: SpotifyPlaybackStore
    ) async {
        let generation = trackingGeneration
        guard ownsTracking(accountID, generation: generation) else { return }
        var active = liveSnapshot(
            phone: phone, strength: strength, mirroredWatch: mirroredWatch,
            spotify: spotify
        )
        reconcileSession(active?.id, title: active?.title,
                         startedAt: active?.startedAt)
        if let snapshot = active, let grant = controlGrantID,
           isApprovedForSession(snapshot.id) {
            let actions = availableRemoteActions(snapshot, phone: phone, strength: strength,
                                                 mirroredWatch: mirroredWatch)
            if !actions.isEmpty {
                active?.controlGrantID = grant
                active?.controlDeviceID = ATHLTHDeviceRole.persistentDeviceID
                active?.supportedControls = actions
            }
        }
        // Presence is intentionally independent from session-scoped approval.
        // No metrics or workout names enter this table.
        await publishPresence(accountID: accountID, snapshot: active)
        guard ownsTracking(accountID, generation: generation) else { return }
        // A workout may end or change while the presence request is suspended.
        // Do not publish a stale frame or control grant from that recording.
        let latestID = liveSnapshot(phone: phone, strength: strength,
                                    mirroredWatch: mirroredWatch, spotify: spotify)?.id
        guard latestID == active?.id else { return }
        if var active, isApprovedForSession(active.id) {
            if controlGrantID != active.controlGrantID {
                active.controlGrantID = nil
                active.controlDeviceID = nil
                active.supportedControls = nil
            }
            let now = Date()
            let row = ATHLTHCrossDeviceWorkoutRow(
                userID: accountID,
                snapshot: Self.boundedSpectatorSnapshot(active),
                updatedAt: now,
                expiresAt: now.addingTimeInterval(30)
            )
            do {
                let signpost = ATHLTHPerformance.begin("CrossDeviceWorkoutPublish")
                defer { ATHLTHPerformance.end("CrossDeviceWorkoutPublish", id: signpost) }
                try await client.from("private_active_workout_status")
                    .upsert(row, onConflict: "user_id")
                    .execute()
                guard ownsTracking(accountID, generation: generation) else { return }
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
                    guard ownsTracking(accountID, generation: generation) else { return }
                    lastPublishedID = nil
                } catch {
                    // No fallback ever starts a recording or enables viewing.
                    // The previous row expires naturally as a final guard.
                }
            }
        }
    }

    private func publishDeviceHeartbeat(accountID: UUID, watchConnection: AppleWatchConnectionStore?) async {
        guard ATHLTHDeviceRole.isIPhone, trackingAccountID == accountID,
              client.auth.currentUser?.id == accountID, !Task.isCancelled,
              lastDeviceHeartbeatAt.map({ Date().timeIntervalSince($0) >= 12 }) ?? true else { return }
        lastDeviceHeartbeatAt = .now
        let paired = watchConnection?.paired == true
        let installed = paired && watchConnection?.watchAppInstalled == true
        let row = ATHLTHWorkoutDeviceHeartbeat(userID: accountID,
            deviceID: ATHLTHDeviceRole.persistentDeviceID, watchPaired: paired,
            watchInstalled: installed, watchReachable: installed && watchConnection?.reachable == true,
            observedAt: .now)
        do {
            try await client.from("private_workout_device_availability")
                .upsert(row, onConflict: "user_id,device_id").execute()
        } catch { /* optional presence never interrupts recording */ }
    }

    private func availableRemoteActions(
        _ snapshot: ATHLTHCrossDeviceWorkoutSnapshot, phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore, mirroredWatch: WorkoutMirroringStore
    ) -> [ATHLTHRemoteWorkoutAction] {
        if snapshot.sourceDevice == "watch" {
            guard let watch = mirroredWatch.snapshot,
                  ATHLTHWatchSpectatorSessionPolicy.canRelay(watch, to: trackingAccountID),
                  ATHLTHWatchSpectatorSessionPolicy.verifiedID(watch) == snapshot.id,
                  (-5...15).contains(Date().timeIntervalSince(watch.capturedAt)),
                  watch.state == .running || watch.state == .paused else { return [] }
            var actions: [ATHLTHRemoteWorkoutAction] = [watch.state == .paused ? .resume : .pause, .end]
            if watch.state == .running, watch.runningManualAdvanceRequired == true,
               watch.runningStepIndex != nil { actions.append(.next) }
            return actions
        }
        if let run = phone.active, run.id == snapshot.id, run.end == nil {
            var actions: [ATHLTHRemoteWorkoutAction] = [run.resumedAt == nil ? .resume : .pause, .end]
            if run.resumedAt != nil, run.structuredWorkoutComplete != true,
               phone.currentStructuredStep != nil,
               run.awaitingMainStart == true || phone.nextStructuredStep != nil {
                actions.append(.next)
            }
            return actions
        }
        if let log = strength.activeWorkout, log.id == snapshot.id, log.captureDevice == .iPhone {
            var actions: [ATHLTHRemoteWorkoutAction] = [.end]
            if let rest = strength.restEndsAt, rest > .now { actions.append(.skipRest) }
            return actions
        }
        // Manual/structured timers require their original local player.
        return []
    }

    func enqueueRemoteControl(
        _ action: ATHLTHRemoteWorkoutAction, snapshot: ATHLTHCrossDeviceWorkoutSnapshot,
        accountID: UUID
    ) async {
        guard ATHLTHDeviceRole.isIPad, trackingAccountID == accountID,
              client.auth.currentUser?.id == accountID,
              pendingRemoteControlID == nil, let current = remote,
              current.id == snapshot.id, let grant = current.controlGrantID,
              grant == snapshot.controlGrantID, let target = current.controlDeviceID,
              current.supportedControls?.contains(action) == true,
              let capturedAt = current.capturedAt,
              (-5...15).contains(Date().timeIntervalSince(capturedAt))
        else {
            remoteControlMessage = ATHLTHLocalization.choose(
                english: "Control is unavailable or the live view is out of date.",
                norwegian: "Fjernstyring er utilgjengelig eller livevisningen er utdatert.")
            return
        }
        // An advance/skip must still refer to the step/rest visible at tap time.
        guard action != .next || (snapshot.runningStepIndex != nil && snapshot.runningStepIndex == current.runningStepIndex),
              action != .skipRest || (snapshot.strengthRestEndsAt != nil && snapshot.strengthRestEndsAt == current.strengthRestEndsAt)
        else { return }
        let now = Date()
        let request = ATHLTHRemoteWorkoutControlCommand(
            id: UUID(), userID: accountID, sessionID: current.id, targetDeviceID: target,
            grantID: grant, action: action, expectedStep: current.runningStepIndex,
            expectedRestEnd: current.strengthRestEndsAt, requestedAt: now,
            expiresAt: now.addingTimeInterval(25))
        pendingRemoteControlID = request.id
        pendingRemoteControlExpiry = request.expiresAt
        pendingRemoteControlSessionID = current.id
        remoteControlMessage = nil
        do {
            // Old commands cannot accumulate indefinitely.
            try? await client.from("private_workout_control_commands").delete()
                .eq("user_id", value: accountID)
                .lt("expires_at", value: ISO8601DateFormatter().string(from: now.addingTimeInterval(-60)))
                .execute()
            guard trackingAccountID == accountID, client.auth.currentUser?.id == accountID,
                  pendingRemoteControlID == request.id, !Task.isCancelled else { return }
            try await client.from("private_workout_control_commands").insert(request).execute()
        } catch {
            guard trackingAccountID == accountID, pendingRemoteControlID == request.id else { return }
            pendingRemoteControlID = nil
            pendingRemoteControlExpiry = nil
            pendingRemoteControlSessionID = nil
            remoteControlMessage = error.localizedDescription
        }
    }

    private func pollRemoteControlReceipt(accountID: UUID) async {
        guard let id = pendingRemoteControlID else { return }
        let now = Date()
        if pendingRemoteControlExpiry.map({ $0 <= now }) ?? true {
            pendingRemoteControlID = nil
            pendingRemoteControlExpiry = nil
            pendingRemoteControlSessionID = nil
            remoteControlMessage = ATHLTHLocalization.choose(
                english: "No confirmation from the recording device. Check it before retrying.",
                norwegian: "Ingen bekreftelse fra treningsenheten. Kontroller den før du prøver igjen.")
            return
        }
        do {
            let rows: [ATHLTHRemoteWorkoutControlCommand] = try await client
                .from("private_workout_control_commands").select()
                .eq("user_id", value: accountID).eq("id", value: id).limit(1).execute().value
            guard trackingAccountID == accountID, pendingRemoteControlID == id,
                  client.auth.currentUser?.id == accountID, !Task.isCancelled,
                  let row = rows.first, row.sessionID == pendingRemoteControlSessionID,
                  row.status == "sent" || row.status == "rejected" else { return }
            pendingRemoteControlID = nil
            pendingRemoteControlExpiry = nil
            pendingRemoteControlSessionID = nil
            remoteControlMessage = row.status == "sent"
                ? ATHLTHLocalization.choose(english: "Command sent to recorder. Live data confirms the result.", norwegian: "Kommando sendt til treningsenheten. Livevisningen bekrefter resultatet.")
                : ATHLTHLocalization.choose(english: "Command rejected. Check the active workout.", norwegian: "Kommando avvist. Kontroller den aktive økten.")
        } catch { /* expiry remains decisive */ }
    }

    private func pollRemoteControlCommands(
        accountID: UUID, phone: IPhoneWorkoutStore, strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore, spotify: SpotifyPlaybackStore,
        appSession: AppSessionStore?
    ) async {
        guard ATHLTHDeviceRole.isIPhone, trackingAccountID == accountID,
              client.auth.currentUser?.id == accountID, let grant = controlGrantID,
              let sessionID = lastSourceSessionID, isApprovedForSession(sessionID)
        else { return }
        let deviceID = ATHLTHDeviceRole.persistentDeviceID
        do {
            let rows: [ATHLTHRemoteWorkoutControlCommand] = try await client
                .from("private_workout_control_commands").select()
                .eq("user_id", value: accountID).eq("target_device_id", value: deviceID)
                .eq("session_id", value: sessionID).eq("grant_id", value: grant)
                .eq("status", value: "pending")
                .gt("expires_at", value: ISO8601DateFormatter().string(from: .now))
                .order("requested_at", ascending: true).limit(1).execute().value
            guard let command = rows.first, trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID, controlGrantID == grant,
                  isApprovedForSession(sessionID), !Task.isCancelled else { return }
            // Claim once before any side effect; a reconnect never replays a claimed command.
            let claimed: [ATHLTHRemoteWorkoutControlCommand] = try await client
                .from("private_workout_control_commands").update(["status": "claimed"])
                .eq("user_id", value: accountID).eq("id", value: command.id)
                .eq("status", value: "pending").select().execute().value
            guard claimed.count == 1, claimed.first?.id == command.id,
                  trackingAccountID == accountID, client.auth.currentUser?.id == accountID,
                  controlGrantID == grant, isApprovedForSession(sessionID), !Task.isCancelled,
                  let snapshot = liveSnapshot(phone: phone, strength: strength,
                                               mirroredWatch: mirroredWatch, spotify: spotify),
                  snapshot.id == sessionID else { return }
            let available = availableRemoteActions(snapshot, phone: phone, strength: strength,
                                                  mirroredWatch: mirroredWatch)
            var sent = false
            if ATHLTHRemoteWorkoutControlPolicy.accepts(command, accountID: accountID,
                sessionID: sessionID, deviceID: deviceID, grantID: grant, available: available) {
                if snapshot.sourceDevice == "watch" {
                    switch command.action {
                    case .pause: sent = mirroredWatch.sendCommand(.pause)
                    case .resume: sent = mirroredWatch.sendCommand(.resume)
                    case .end: sent = mirroredWatch.sendCommand(.end)
                    case .next:
                        if let index = command.expectedStep, let watch = mirroredWatch.snapshot {
                            sent = mirroredWatch.advanceRunningStep(expectedIndex: index, startedAt: watch.startedAt)
                        }
                    case .skipRest: break
                    }
                } else if let run = phone.active, run.id == sessionID {
                    switch command.action {
                    case .pause: phone.pause(); sent = phone.active?.resumedAt == nil
                    case .resume: phone.resume(); sent = phone.active?.resumedAt != nil
                    case .end: await phone.finish(); sent = phone.active?.id != sessionID
                    case .next:
                        if let index = command.expectedStep, index == run.structuredStepIndex {
                            phone.advanceStructuredStepManually()
                            sent = phone.active?.structuredStepIndex != index ||
                                phone.active?.awaitingMainStart != run.awaitingMainStart
                        }
                    case .skipRest: break
                    }
                } else if let log = strength.activeWorkout, log.id == sessionID,
                          log.captureDevice == .iPhone {
                    switch command.action {
                    case .end:
                        if let appSession, appSession.profile.userID == accountID, appSession.signedIn {
                            sent = strength.finish(duration: strength.elapsedSessionSeconds(for: log, at: .now))
                            if sent { appSession.endTrainingStatus() }
                        }
                    case .skipRest:
                        if let expected = command.expectedRestEnd, let actual = strength.restEndsAt,
                           abs(expected.timeIntervalSince(actual)) < 0.5, actual > .now {
                            sent = strength.skipRest()
                        }
                    default: break
                    }
                }
            }
            guard trackingAccountID == accountID, client.auth.currentUser?.id == accountID else { return }
            try await client.from("private_workout_control_commands")
                .update(["status": sent ? "sent" : "rejected"])
                .eq("user_id", value: accountID).eq("id", value: command.id)
                .eq("status", value: "claimed").execute()
        } catch { /* do not retry a claimed command */ }
    }

    private func publishPresence(
        accountID: UUID,
        snapshot: ATHLTHCrossDeviceWorkoutSnapshot?
    ) async {
        let generation = trackingGeneration
        guard ownsTracking(accountID, generation: generation) else { return }
        if let snapshot {
            let now = Date()
            let source = snapshot.sourceDevice == "watch" ? "watch" : "iphone"
            // Presence has a 30-second TTL, independent of 4-second metric and
            // command polling. Refresh sooner on every source/session change.
            if lastPresencePublished, !ATHLTHCrossDevicePresenceRefreshPolicy.needsWrite(
                sessionID: snapshot.id, source: source, previousSessionID: lastPublishedPresenceSessionID,
                previousSource: lastPublishedPresenceSource, previousWrite: lastPublishedPresenceAt,
                now: now) { return }
            let signpost = ATHLTHPerformance.begin("CrossDevicePresenceWrite")
            defer { ATHLTHPerformance.end("CrossDevicePresenceWrite", id: signpost) }
            let row = ATHLTHCrossDevicePresenceRow(
                userID: accountID,
                sourceDevice: source,
                updatedAt: now,
                expiresAt: now.addingTimeInterval(30)
            )
            do {
                try await client.from("private_active_workout_presence")
                    .upsert(row, onConflict: "user_id")
                    .execute()
                guard ownsTracking(accountID, generation: generation) else { return }
                lastPresencePublished = true
                lastPublishedPresenceSessionID = snapshot.id
                lastPublishedPresenceSource = source
                lastPublishedPresenceAt = now
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
                    guard ownsTracking(accountID, generation: generation) else { return }
                    lastPresencePublished = false
                    lastPublishedPresenceSessionID = nil
                    lastPublishedPresenceSource = nil
                    lastPublishedPresenceAt = nil
                } catch {
                    // Expiring the heartbeat is the offline safety fallback.
                }
            }
        }
    }

    func refreshPresenceNow(accountID: UUID) async {
        guard ATHLTHDeviceRole.isIPad,
              trackingAccountID == accountID,
              client.auth.currentUser?.id == accountID else { return }
        await readPresence(accountID: accountID)
        guard trackingAccountID == accountID,
              client.auth.currentUser?.id == accountID else { return }
        await readRemote(accountID: accountID)
    }

    private func readPresence(accountID: UUID) async {
        presenceReadGeneration &+= 1
        let requestGeneration = presenceReadGeneration
        do {
            let rows: [ATHLTHCrossDevicePresenceRow] = try await client
                .from("private_active_workout_presence")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            guard requestGeneration == presenceReadGeneration,
                  trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID,
                  !Task.isCancelled else {
                return
            }
            let valid = rows.first.flatMap { $0.expiresAt > .now ? $0 : nil }
            remotePresence = valid
            lastPresenceExpiry = valid?.expiresAt
            presenceConnectionIssue = false
            hasCheckedPresence = true
        } catch {
            guard requestGeneration == presenceReadGeneration,
                  trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID,
                  !Task.isCancelled else {
                return
            }
            hasCheckedPresence = true
            presenceConnectionIssue = true
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
        // Invalidate callbacks from any earlier request before sending
        // a replacement; a delayed error must not overwrite new UI state.
        outgoingRequestID = nil
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
        outgoingRequestExpiresAt = request.expiresAt
        do {
            try await client.from("private_live_view_requests")
                .upsert(request, onConflict: "user_id")
                .execute()
            guard trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID,
                  !Task.isCancelled else { return }
            outgoingRequestID = request.id
            outgoingRequestState = .pending
            expireOutgoingRequestIfNeeded()
            // Best effort APNs only. Sending the request is independent from
            // notification permissions and never grants spectator access.
            Task { await notifyIPhoneAboutRequest(id: request.id, accountID: accountID) }
        } catch {
            guard trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID,
                  !Task.isCancelled else { return }
            outgoingRequestState = .failed
            outgoingRequestExpiresAt = nil
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
              controlGrantID == nil else {
            incomingRequest = nil
            return
        }
        let expectedSession = lastSourceSessionID
        let expectedStartedAt = lastSourceStartedAt
        do {
            let rows: [ATHLTHLiveViewRequest] = try await client
                .from("private_live_view_requests")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            guard trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID,
                  lastSourceSessionID == expectedSession,
                  lastSourceStartedAt == expectedStartedAt,
                  !Task.isCancelled else { return }
            incomingRequest = rows.first.flatMap {
                ATHLTHLiveViewSessionRequestPolicy.mayPromptOwner(
                    $0, accountID: accountID, sourceStartedAt: expectedStartedAt
                ) ? $0 : nil
            }
        } catch {
            guard trackingAccountID == accountID,
                  lastSourceSessionID == expectedSession,
                  !Task.isCancelled else { return }
            incomingRequest = nil
        }
    }

    /// The iPhone alone commits the in-memory session grant. Neither an
    /// iPad database update nor a request row can authorize publication.
    func respondToRequest(approve: Bool, accountID: UUID, allowControl: Bool = false) async {
        guard !ATHLTHDeviceRole.isIPad,
              let request = incomingRequest,
              let exactSessionID = lastSourceSessionID,
              trackingAccountID == accountID,
              ATHLTHLiveViewSessionRequestPolicy.mayPromptOwner(
                  request, accountID: accountID,
                  sourceStartedAt: lastSourceStartedAt
              ),
              client.auth.currentUser?.id == accountID else { return }

        incomingRequest = nil
        if approve {
            approvedSourceSessionID = exactSessionID
            controlGrantID = allowControl ? UUID() : nil
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
        controlGrantID = nil
        shareNextWorkout = false
        nextWorkoutSharingExpiresAt = nil
    }

    private func pollOutgoingRequest(accountID: UUID) async {
        expireOutgoingRequestIfNeeded()
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
            guard trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID,
                  outgoingRequestID == requestID,
                  !Task.isCancelled else { return }
            guard let row = rows.first, row.id == requestID else {
                outgoingRequestState = .expired
                outgoingRequestID = nil
                outgoingRequestExpiresAt = nil
                return
            }
            if row.expiresAt <= .now {
                outgoingRequestState = .expired
                outgoingRequestID = nil
                outgoingRequestExpiresAt = nil
            } else if row.status == "denied" {
                outgoingRequestState = .denied
                outgoingRequestID = nil
                outgoingRequestExpiresAt = nil
            } else if row.status == "approved" {
                outgoingRequestState = .approved
                outgoingRequestID = nil
                outgoingRequestExpiresAt = nil
            } else {
                outgoingRequestExpiresAt = row.expiresAt
                outgoingRequestState = .pending
            }
        } catch {
            // A transient network failure must never imply acceptance.
        }
    }

    private func readRemote(accountID: UUID) async {
        remoteReadGeneration &+= 1
        let requestGeneration = remoteReadGeneration
        do {
            let rows: [ATHLTHCrossDeviceWorkoutRow] = try await client
                .from("private_active_workout_status")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            guard requestGeneration == remoteReadGeneration,
                  trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID,
                  !Task.isCancelled else { return }
            let row = rows.first
            let candidate = row.flatMap {
                ATHLTHCrossDeviceLiveReadPolicy.accepts(
                    $0.snapshot,
                    updatedAt: $0.updatedAt,
                    expiresAt: $0.expiresAt
                ) ? Self.boundedSpectatorSnapshot($0.snapshot) : nil
            }
            let order = ATHLTHCrossDeviceSnapshotOrderPolicy.decision(
                current: remote,
                incoming: candidate,
                currentExpiry: lastRemoteExpiry
            )
            if order == .keepCurrent { return }
            // If the existing verified frame expired, never resurrect it
            // from an older snapshot for the same session.
            let next = order == .clearExpired ? nil : candidate
            // Do not touch window presentation from a shared network poll.
            // Each AppRootView reacts to the verified session ID separately.
            remote = next
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
            guard requestGeneration == remoteReadGeneration,
                  trackingAccountID == accountID,
                  client.auth.currentUser?.id == accountID,
                  !Task.isCancelled else { return }
            presenceConnectionIssue = true
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
