import SwiftUI

/// Explicit Watch actions remain available even when the iPhone owns
/// resistance, repetitions and timing settings. This permission boundary
/// must not allow Watch-originated edits to the athlete's prescribed values.
enum ATHLTHStrengthWatchControlPolicy {
    static func acceptsSetCommands(
        captureDevice: WorkoutCaptureDevice,
        inputMode: WatchStrengthInputMode
    ) -> Bool {
        // The HealthKit recording device is not the set-logging authority.
        // Users selecting Both or Watch must still log from Watch when the
        // iPhone owns the workout recording session.
        captureDevice == .appleWatch || inputMode == .both || inputMode == .appleWatch
    }

    static func permits(
        _ command: WatchStrengthCommandKind,
        whenIPhoneControls: Bool
    ) -> Bool {
        guard whenIPhoneControls else { return true }
        switch command {
        case .completeSet, .startSetEffort, .skipSet, .skipRest, .skipRestAndStartTimedSet,
             .startTimedSet, .nextExercise:
            return true
        case .updateDraft, .completeSetWithoutDetails, .addRest,
             .pauseTimedSet, .resetTimedSet, .requestSnapshot:
            return false
        }
    }
}


/// A Watch request received after account sign-out or switching accounts
/// cannot automatically bootstrap a new workout for a different athlete.
/// The ownership ID is bound to the Watch workout's recording start.
enum ATHLTHStrengthWatchBootstrapOwnershipPolicy {
    static func permitsBootstrap(
        _ command: WatchStrengthCommand, currentAccountID: UUID
    ) -> Bool {
        guard command.kind == .requestSnapshot,
              command.initiatedOnWatch == true,
              let owner = command.accountOwnerID,
              owner == currentAccountID
        else { return false }
        // Without a real authoritative snapshot, starting a new freestyle
        // workout here would generate a different UUID and strand the
        // original Watch journal. Require both exact identity and state.
        guard let snapshot = command.bootstrapSnapshot,
              command.workoutID == snapshot.workoutID
        else { return false }
        return true
    }
}


/// A Watch bootstrap can claim the recording slot only when neither a
/// previously completed result nor an existing local workout owns it.
enum ATHLTHStrengthWatchBootstrapAdmissionPolicy {
    static func canRestore(
        snapshot: WatchStrengthSessionSnapshot,
        activeWorkoutID: UUID?,
        completedWorkoutIDs: Set<UUID>,
        slotAvailable: Bool
    ) -> Bool {
        activeWorkoutID == nil &&
            !completedWorkoutIDs.contains(snapshot.workoutID) &&
            slotAvailable
    }
}

/// Keep an offline Watch journal for its owner instead of consuming entries
/// while a different account is signed in. Legacy commands may be applied
/// only to an already-restored workout with the exact same workout UUID.
enum ATHLTHStrengthWatchCommandRoutingPolicy {
    /// Replaying a command for a completed local workout cannot add
    /// another set. Acknowledge it only if the immutable workout ID is
    /// already committed to the currently loaded account's history.
    static func mayAcknowledgeCommitted(
        _ command: WatchStrengthCommand,
        signedInAccountID: UUID,
        completedWorkoutIDs: Set<UUID>
    ) -> Bool {
        guard let workoutID = command.workoutID,
              completedWorkoutIDs.contains(workoutID),
              command.accountOwnerID == nil ||
                command.accountOwnerID == signedInAccountID
        else { return false }
        return true
    }

    /// HealthKit / WatchConnectivity may deliver offline set actions before
    /// the snapshot required to reconstruct their source session. Bootstrap
    /// first, then replay the set actions in their original chronological
    /// order. Never use arrival order as the workout clock.
    static func orderedForReplay(
        _ commands: [WatchStrengthCommand]
    ) -> [WatchStrengthCommand] {
        commands.sorted { left, right in
            let leftBootstrap = left.kind == .requestSnapshot &&
                left.initiatedOnWatch == true
            let rightBootstrap = right.kind == .requestSnapshot &&
                right.initiatedOnWatch == true
            if leftBootstrap != rightBootstrap {
                return leftBootstrap
            }
            if left.sentAt != right.sentAt {
                return left.sentAt < right.sentAt
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    static func mayProcess(
        _ command: WatchStrengthCommand,
        signedInAccountID: UUID,
        activeWorkoutID: UUID?
    ) -> Bool {
        if let owner = command.accountOwnerID {
            guard owner == signedInAccountID else { return false }
            if command.kind == .requestSnapshot {
                // A Watch-started recording may bootstrap while no
                // strength workout exists locally. If another workout
                // is active, keep this request for the correct session.
                if command.initiatedOnWatch == true {
                    return activeWorkoutID == nil ||
                        command.workoutID == activeWorkoutID
                }
                // Nonmutating legacy snapshot refresh requests are safe.
                return true
            }
            // Same athlete can have several offline Watch sessions queued
            // at once. NEVER consume a future workout's set commands merely
            // because an unrelated local workout happens to be active.
            guard let activeWorkoutID,
                  let workoutID = command.workoutID
            else { return false }
            return workoutID == activeWorkoutID
        }
        guard command.kind != .requestSnapshot,
              let workoutID = command.workoutID,
              let activeWorkoutID
        else { return false }
        return workoutID == activeWorkoutID
    }
}

/// Keeps the high-frequency strength <-> Apple Watch synchronization out of
/// AppRootView so reps/weight/rest edits do not invalidate the entire app
/// hierarchy.
struct ATHLTHStrengthWatchSyncObserver: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore

    @State private var pendingDraftSnapshotTask: Task<Void, Never>?
    @State private var pendingPrivateStatusTask: Task<Void, Never>?
    @State private var lastStrengthMutationAtByWorkout:
        [UUID: Date] = [:]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                drainPendingCommands()
                sendSnapshotNow()
                if appSession.signedIn,
                   strengthWorkout.isLoaded(for: appSession.profile.userID),
                   let latest = workoutMirroring.snapshot {
                    strengthWorkout.ingestWatchCardioSnapshot(latest)
                }
            }
            // Private, opt-in, read-only status for another device on the
            // same account. Refreshes while a live strength workout is open,
            // so a long rest does not appear disconnected on iPad.
            .task(id: appSession.profile.userID) {
                guard !ATHLTHDeviceRole.isIPad else { return }
                while !Task.isCancelled {
                    if appSession.signedIn &&
                        strengthWorkout.isLoaded(for: appSession.profile.userID) {
                        await ATHLTHPrivateLiveStrengthStatusStore.publish(
                            ATHLTHPrivateLiveStrengthSnapshot.make(
                                from: strengthWorkout
                            ),
                            userID: appSession.profile.userID
                        )
                    }
                    try? await Task.sleep(for: .seconds(25))
                }
            }
            .onChange(of: appSession.signedIn) { _, signedIn in
                if signedIn { drainPendingCommands() }
            }
            .onChange(of: appSession.profile.userID) { _, _ in
                drainPendingCommands()
            }
            .onChange(of: workoutMirroring.snapshot) { _, latest in
                if appSession.signedIn,
                   strengthWorkout.isLoaded(for: appSession.profile.userID),
                   let latest {
                    strengthWorkout.ingestWatchCardioSnapshot(latest)
                }
            }
            .onDisappear {
                pendingDraftSnapshotTask?.cancel()
                pendingDraftSnapshotTask = nil
                pendingPrivateStatusTask?.cancel()
                pendingPrivateStatusTask = nil
            }
            .onChange(
                of:
                    watchConnection
                        .pendingStrengthCommands
            ) { _, _ in
                drainPendingCommands()
            }
            .onChange(of: strengthWorkout.activeWorkout) { _, _ in
                drainPendingCommands()
                sendSnapshotNow()
                schedulePrivateStatusUpdate()
            }
            .onChange(of: strengthWorkout.currentExerciseIndex) { _, _ in
                sendSnapshotNow()
            }
            .onChange(of: strengthWorkout.currentSetIndex) { _, _ in
                sendSnapshotNow()
            }
            .onChange(of: strengthWorkout.restEndsAt) { _, _ in
                sendSnapshotNow()
                schedulePrivateStatusUpdate()
            }
            .onChange(of: strengthWorkout.draftReps) { _, _ in
                scheduleDraftSnapshot()
            }
            .onChange(of: strengthWorkout.draftWeightKilograms) { _, _ in
                scheduleDraftSnapshot()
            }
            .onChange(of: strengthWorkout.draftRestSeconds) { _, _ in
                scheduleDraftSnapshot()
            }
            .onChange(of: strengthWorkout.draftRPE) { _, _ in
                scheduleDraftSnapshot()
            }
            .onChange(of: strengthWorkout.draftRIR) { _, _ in
                scheduleDraftSnapshot()
            }
            .onChange(of: strengthWorkout.draftWarmUp) { _, _ in
                scheduleDraftSnapshot()
            }
            .onChange(of: strengthWorkout.setEffortClock) { _, _ in
                sendSnapshotNow()
            }
            .onChange(of: strengthWorkout.timedSetCountdown) { _, _ in
                sendSnapshotNow()
            }
    }

    @MainActor
    private func schedulePrivateStatusUpdate() {
        guard !ATHLTHDeviceRole.isIPad,
              appSession.signedIn,
              strengthWorkout.isLoaded(for: appSession.profile.userID)
        else { return }
        pendingPrivateStatusTask?.cancel()
        pendingPrivateStatusTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled,
                  appSession.signedIn,
                  strengthWorkout.isLoaded(for: appSession.profile.userID)
            else { return }
            let owner = appSession.profile.userID
            await ATHLTHPrivateLiveStrengthStatusStore.publish(
                ATHLTHPrivateLiveStrengthSnapshot.make(from: strengthWorkout),
                userID: owner
            )
        }
    }

    @MainActor
    private func handle(
        _ command: WatchStrengthCommand
    ) -> Bool {
        guard appSession.signedIn,
              strengthWorkout.isLoaded(for: appSession.profile.userID)
        else { return false }

        if command.kind == .requestSnapshot {
            if strengthWorkout.activeWorkout == nil,
               command.initiatedOnWatch == true {
                guard appSession.signedIn else {
                    // Keep the request queued until account restoration has
                    // selected the correct per-user strength checkpoint.
                    return false
                }
                guard ATHLTHStrengthWatchBootstrapOwnershipPolicy.permitsBootstrap(
                    command, currentAccountID: appSession.profile.userID
                ) else {
                    // Never reinterpret a legacy/unowned Watch request as
                    // consent to record under a different signed-in account.
                    // Keep the pending command intact until a compatible
                    // account/bootstrap becomes available; never claim it.
                    return false
                }

                guard let bootstrap = command.bootstrapSnapshot else {
                    return false
                }
                let completedIDs = Set(strengthWorkout.workoutHistory.map(\.id))
                if completedIDs.contains(bootstrap.workoutID) {
                    // This Watch session is already durable. Replaying its
                    // bootstrap must neither recreate a session nor retain
                    // the request indefinitely.
                    return true
                }
                guard ATHLTHStrengthWatchBootstrapAdmissionPolicy.canRestore(
                    snapshot: bootstrap,
                    activeWorkoutID: strengthWorkout.activeWorkout?.id,
                    completedWorkoutIDs: completedIDs,
                    slotAvailable: ATHLTHWorkoutRecordingArbiter.mayBootstrapWatchStrength()
                ), strengthWorkout.startFromWatchSnapshot(
                    bootstrap, watchSessionID: command.id
                ) else {
                    // A running/walking workout or an async start owns the
                    // recording slot. Preserve this Watch request until a
                    // legitimate restore can occur; never replace the run.
                    return false
                }
            }

            if command.initiatedOnWatch == true,
               command.workoutID != strengthWorkout.activeWorkout?.id {
                // Do not consume a different Watch workout's snapshot while
                // another local strength workout is active.
                return false
            }
            sendSnapshotNow()
            return strengthWorkout.activeWorkout != nil ||
                command.initiatedOnWatch != true
        }

        guard let workout =
                strengthWorkout.activeWorkout
        else {
            // Keep queued commands until account/workout checkpoint restore has
            // had a chance to recreate the authoritative iPhone strength log.
            return false
        }

        // A phone-initiated workout can still accept Watch set logging
        // when the athlete chose "Both". Capture device denotes who owns
        // the HealthKit workout, not which device can record sets.
        let inputMode = workout.advancedConfiguration?.inputMode ?? .both
        let watchMayRecordSets = ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
            captureDevice: workout.captureDevice,
            inputMode: inputMode
        )
        guard watchMayRecordSets else {
            sendSnapshotNow()
            return true
        }

        if !ATHLTHStrengthWatchControlPolicy.permits(
            command.kind,
            whenIPhoneControls:
                workout.advancedConfiguration?.inputMode == .iPhone
        ) {
            sendSnapshotNow()
            return true
        }

        guard ATHLTHStrengthWatchCommandIdentityPolicy.belongsToActiveWorkout(
            command, workoutID: workout.id
        ) else {
            // A mismatched command is not an instruction to this workout.
            // Leave it pending for the correct restored workout, rather
            // than acknowledging and permanently losing its set evidence.
            return false
        }

        let setScopedCommand =
            command.kind == .updateDraft ||
            command.kind == .skipSet ||
            command.kind == .startSetEffort ||
            command.kind == .completeSet ||
            command.kind ==
                .completeSetWithoutDetails ||
            command.kind == .startTimedSet ||
            command.kind == .pauseTimedSet ||
            command.kind == .resetTimedSet ||
            command.kind == .skipRestAndStartTimedSet

        if setScopedCommand,
           let exerciseIndex =
                command.exerciseIndex,
           exerciseIndex !=
                strengthWorkout
                    .currentExerciseIndex {
            sendSnapshotNow()
            return true
        }

        if setScopedCommand,
           let setIndex =
                command.setIndex,
           setIndex !=
                strengthWorkout
                    .currentSetIndex {
            sendSnapshotNow()
            return true
        }

        if (command.kind == .skipRest ||
            command.kind == .addRest ||
            command.kind == .skipRestAndStartTimedSet),
           !ATHLTHStrengthWatchRestActionPolicy.accepts(
               command,
               exerciseIndex: strengthWorkout.currentExerciseIndex,
               setIndex: strengthWorkout.currentSetIndex,
               restStartedAt: strengthWorkout.restStartedAt
           ) {
            sendSnapshotNow()
            return true
        }

        let requiresOpenSet =
            command.kind == .updateDraft ||
            command.kind == .completeSet ||
            command.kind == .completeSetWithoutDetails ||
            command.kind == .startSetEffort ||
            command.kind == .skipSet ||
            command.kind == .startTimedSet ||
            command.kind == .pauseTimedSet ||
            command.kind == .resetTimedSet ||
            command.kind == .skipRestAndStartTimedSet
        if requiresOpenSet,
           strengthWorkout.currentSet?.isResolved != false {
            sendSnapshotNow()
            return true
        }

        if command.kind == .nextExercise,
           let exerciseIndex =
                command.exerciseIndex,
           exerciseIndex !=
                strengthWorkout
                    .currentExerciseIndex {
            sendSnapshotNow()
            return true
        }

        if command.kind == .updateDraft,
           let lastMutationAt =
                lastStrengthMutationAtByWorkout[
                    workout.id
                ],
           command.sentAt <= lastMutationAt {
            // A draft edit that was sent before a set/rest/exercise action
            // must never arrive later and overwrite the new authoritative
            // iPhone state.
            sendSnapshotNow()
            return true
        }

        switch command.kind {
        case .updateDraft:
            guard command.sentAt >=
                    strengthWorkout
                        .lastPhoneDraftMutationAt
            else {
                sendSnapshotNow()
                return true
            }

            strengthWorkout.setDraft(
                reps: command.reps,
                durationSeconds:
                    command.durationSeconds,
                weightKilograms:
                    command.weightKilograms,
                resistanceLevel:
                    command.resistanceLevel,
                restSeconds:
                    command.restSeconds,
                rpe: command.rpe,
                rir: command.rir,
                warmUp:
                    command.isWarmUp,
                origin: .watch
            )

        case .completeSet:
            // Completing on Watch is an explicit action, but a payload that
            // predates a newer iPhone edit must not overwrite the iPhone's
            // current reps/weight. In that case complete the authoritative
            // iPhone draft instead.
            if command.sentAt >=
                strengthWorkout
                    .lastPhoneDraftMutationAt {
                strengthWorkout.setDraft(
                    reps: command.reps,
                    durationSeconds:
                        command
                            .durationSeconds,
                    weightKilograms:
                        command
                            .weightKilograms,
                    resistanceLevel:
                        command
                            .resistanceLevel,
                    restSeconds:
                        command
                            .restSeconds,
                    rpe: command.rpe,
                    rir: command.rir,
                    warmUp:
                        command.isWarmUp,
                    origin: .watch
                )
            }

            if command.distanceMeters != nil {
                let set =
                    strengthWorkout
                        .currentSet
                strengthWorkout
                    .completeCurrentSet(
                        reps:
                            set?
                                .resolvedTargetKind ==
                                .reps
                                ? strengthWorkout
                                    .draftReps
                                : nil,
                        durationSeconds:
                            set?
                                .resolvedTargetKind ==
                                .time
                                ? strengthWorkout
                                    .draftDurationSeconds
                                : nil,
                        weightKilograms:
                            set?
                                .resolvedLoadKind ==
                                .weightKilograms
                                ? strengthWorkout
                                    .draftWeightKilograms
                                : nil,
                        resistanceLevel:
                            set?
                                .resolvedLoadKind ==
                                .resistanceLevel
                                ? strengthWorkout
                                    .draftResistanceLevel
                                : nil,
                        distanceMeters:
                            command
                                .distanceMeters,
                        rpe:
                            strengthWorkout
                                .draftRPE,
                        rir:
                            strengthWorkout
                                .draftRIR,
                        isWarmUp:
                            strengthWorkout
                                .draftWarmUp,
                        restSeconds:
                            strengthWorkout
                                .draftRestSeconds,
                        completedAt: command.sentAt
                    )
            } else {
                strengthWorkout
                    .completeCurrentDraftSet(completedAt: command.sentAt)
            }

        case .startSetEffort:
            strengthWorkout.startCurrentSetEffort(at: command.sentAt)

        case .skipSet:
            _ = strengthWorkout.skipCurrentSet()

        case .completeSetWithoutDetails:
            if let restSeconds = command.restSeconds {
                strengthWorkout.setDraft(
                    restSeconds: restSeconds,
                    origin: .watch
                )
            }
            strengthWorkout.completeCurrentSetWithoutDetails(
                restSeconds: strengthWorkout.draftRestSeconds,
                completedAt: command.sentAt
            )

        case .skipRest:
            _ = strengthWorkout.skipRest(at: command.sentAt)

        case .skipRestAndStartTimedSet:
            // Skip the rest and start the already selected next time-based
            // set as one authoritative mutation. Never double-start or
            // jump past a set when a Watch command is replayed.
            if strengthWorkout.isResting,
               strengthWorkout.currentSet?.resolvedTargetKind == .time {
                if strengthWorkout.skipRest(at: command.sentAt) {
                    strengthWorkout.startOrResumeTimedSet(at: command.sentAt)
                }
            }

        case .addRest:
            strengthWorkout.addRest(
                seconds: command.addRestSeconds ?? 30,
                at: command.sentAt
            )

        case .nextExercise:
            strengthWorkout.moveToNextExercise(at: command.sentAt)

        case .startTimedSet:
            // The authoritative store guards against duplicate starts,
            // completed sets and non-time-based exercises.
            strengthWorkout.startOrResumeTimedSet(at: command.sentAt)

        case .pauseTimedSet:
            strengthWorkout.pauseTimedSet(at: command.sentAt)

        case .resetTimedSet:
            strengthWorkout.resetTimedSet()

        case .requestSnapshot:
            break
        }

        if command.kind != .updateDraft &&
            command.kind != .requestSnapshot {
            let previous =
                lastStrengthMutationAtByWorkout[
                    workout.id
                ] ?? .distantPast
            lastStrengthMutationAtByWorkout[
                workout.id
            ] = max(
                previous,
                command.sentAt
            )
        }

        // Commands represent explicit Watch actions and should receive the
        // resulting state immediately. Only free-form draft edits are
        // coalesced.
        sendSnapshotNow()
        return true
    }

    @MainActor
    private func drainPendingCommands() {
        guard appSession.signedIn,
              strengthWorkout.isLoaded(for: appSession.profile.userID)
        else { return }
        // A journal may contain several offline Watch sessions for one
        // athlete. First restore each eligible session identity, then replay
        // its chronologically ordered set events without crossing IDs.
        let owner = appSession.profile.userID
        let completedIDs = Set(
            strengthWorkout.workoutHistory
                .filter { $0.endedAt != nil }
                .map(\.id)
        )
        let queued = ATHLTHStrengthWatchCommandRoutingPolicy.orderedForReplay(
            watchConnection.pendingStrengthCommands
        )
        for command in queued {
            // Only a confirmed durable history item can consume a late
            // command without applying it. This prevents an ever-growing
            // offline queue while preserving original set evidence.
            if ATHLTHStrengthWatchCommandRoutingPolicy.mayAcknowledgeCommitted(
                command, signedInAccountID: owner,
                completedWorkoutIDs: completedIDs
            ) {
                watchConnection.consumeStrengthCommand(command.id)
                continue
            }
            guard ATHLTHStrengthWatchCommandRoutingPolicy.mayProcess(
                command,
                signedInAccountID: owner,
                activeWorkoutID: strengthWorkout.activeWorkout?.id
            ) else { continue }
            guard handle(command) else {
                // The correct account's checkpoint may not be restored yet.
                // Keep this command intact for a later Watch or account restore.
                continue
            }
            watchConnection.consumeStrengthCommand(command.id)
        }
    }

    @MainActor
    private func scheduleDraftSnapshot() {
        pendingDraftSnapshotTask?.cancel()

        pendingDraftSnapshotTask = Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(150)
            )
            guard !Task.isCancelled else { return }
            sendSnapshotNow()
        }
    }

    @MainActor
    private func sendSnapshotNow() {
        pendingDraftSnapshotTask?.cancel()
        pendingDraftSnapshotTask = nil

        guard appSession.signedIn,
              strengthWorkout.isLoaded(for: appSession.profile.userID),
              let workout = strengthWorkout.activeWorkout,
              ATHLTHStrengthWatchControlPolicy.acceptsSetCommands(
                  captureDevice: workout.captureDevice,
                  inputMode: workout.advancedConfiguration?.inputMode ?? .both
              ),
              let snapshot = strengthWorkout.watchSnapshot
        else {
            return
        }

        watchConnection.sendStrengthSnapshot(
            snapshot
        )
    }
}
