import SwiftUI

/// Explicit Watch actions remain available even when the iPhone owns
/// resistance, repetitions and timing settings. This permission boundary
/// must not allow Watch-originated edits to the athlete's prescribed values.
enum ATHLTHStrengthWatchControlPolicy {
    static func permits(
        _ command: WatchStrengthCommandKind,
        whenIPhoneControls: Bool
    ) -> Bool {
        guard whenIPhoneControls else { return true }
        switch command {
        case .completeSet, .skipSet, .skipRest, .skipRestAndStartTimedSet,
             .startTimedSet, .nextExercise:
            return true
        case .updateDraft, .completeSetWithoutDetails, .addRest,
             .pauseTimedSet, .resetTimedSet, .requestSnapshot:
            return false
        }
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
                if let latest = workoutMirroring.snapshot {
                    strengthWorkout.ingestWatchCardioSnapshot(latest)
                }
            }
            // Private, opt-in, read-only status for another device on the
            // same account. Refreshes while a live strength workout is open,
            // so a long rest does not appear disconnected on iPad.
            .task(id: appSession.profile.userID) {
                guard !ATHLTHDeviceRole.isIPad else { return }
                while !Task.isCancelled {
                    if appSession.signedIn {
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
            .onChange(of: workoutMirroring.snapshot) { _, latest in
                if let latest {
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
            .onChange(of: strengthWorkout.timedSetCountdown) { _, _ in
                sendSnapshotNow()
            }
    }

    @MainActor
    private func schedulePrivateStatusUpdate() {
        guard !ATHLTHDeviceRole.isIPad, appSession.signedIn else { return }
        pendingPrivateStatusTask?.cancel()
        pendingPrivateStatusTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await ATHLTHPrivateLiveStrengthStatusStore.publish(
                ATHLTHPrivateLiveStrengthSnapshot.make(from: strengthWorkout),
                userID: appSession.profile.userID
            )
        }
    }

    @MainActor
    private func handle(
        _ command: WatchStrengthCommand
    ) -> Bool {
        if command.kind == .requestSnapshot {
            if strengthWorkout.activeWorkout == nil,
               command.initiatedOnWatch == true {
                guard appSession.signedIn else {
                    // Keep the request queued until account restoration has
                    // selected the correct per-user strength checkpoint.
                    return false
                }

                if let bootstrap =
                        command
                            .bootstrapSnapshot {
                    strengthWorkout
                        .startFromWatchSnapshot(
                            bootstrap,
                            watchSessionID:
                                command.id
                        )
                } else {
                    var configuration =
                        StrengthAdvancedConfiguration
                            .savedDefaults()
                    configuration.inputMode =
                        .both

                    strengthWorkout.startFreestyle(
                        watchSessionID:
                            command.id,
                        trackingMode:
                            .advanced,
                        captureDevice:
                            .appleWatch,
                        advancedConfiguration:
                            configuration
                    )
                }
            }

            sendSnapshotNow()
            return
                strengthWorkout.activeWorkout !=
                nil ||
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
        let watchMayRecordSets =
            workout.captureDevice == .appleWatch ||
            inputMode == .both
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

        if let workoutID = command.workoutID,
           workoutID != workout.id {
            sendSnapshotNow()
            return true
        }

        let setScopedCommand =
            command.kind == .updateDraft ||
            command.kind == .skipSet ||
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
                                .draftRestSeconds
                    )
            } else {
                strengthWorkout
                    .completeCurrentDraftSet()
            }

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
                restSeconds: strengthWorkout.draftRestSeconds
            )

        case .skipRest:
            strengthWorkout.skipRest()

        case .skipRestAndStartTimedSet:
            // Skip the rest and start the already selected next time-based
            // set as one authoritative mutation. Never double-start or
            // jump past a set when a Watch command is replayed.
            if strengthWorkout.isResting,
               strengthWorkout.currentSet?.resolvedTargetKind == .time {
                strengthWorkout.skipRest()
                strengthWorkout.startOrResumeTimedSet(at: command.sentAt)
            }

        case .addRest:
            strengthWorkout.addRest(
                seconds: command.addRestSeconds ?? 30
            )

        case .nextExercise:
            strengthWorkout.moveToNextExercise()

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
        while let command =
                watchConnection
                    .pendingStrengthCommands
                    .first {
            guard handle(command) else {
                break
            }

            watchConnection
                .consumeStrengthCommand(
                    command.id
                )
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

        guard strengthWorkout
                .activeWorkout?
                .captureDevice == .appleWatch,
              let snapshot =
                strengthWorkout.watchSnapshot
        else {
            return
        }

        watchConnection.sendStrengthSnapshot(
            snapshot
        )
    }
}
