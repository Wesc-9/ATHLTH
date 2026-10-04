import SwiftUI

/// Keeps the high-frequency strength <-> Apple Watch synchronization out of
/// AppRootView so reps/weight/rest edits do not invalidate the entire app
/// hierarchy.
struct ATHLTHStrengthWatchSyncObserver: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    @State private var pendingDraftSnapshotTask: Task<Void, Never>?
    @State private var lastStrengthMutationAtByWorkout:
        [UUID: Date] = [:]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                drainPendingCommands()
                sendSnapshotNow()
            }
            .onDisappear {
                pendingDraftSnapshotTask?.cancel()
                pendingDraftSnapshotTask = nil
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
            }
            .onChange(of: strengthWorkout.currentExerciseIndex) { _, _ in
                sendSnapshotNow()
            }
            .onChange(of: strengthWorkout.currentSetIndex) { _, _ in
                sendSnapshotNow()
            }
            .onChange(of: strengthWorkout.restEndsAt) { _, _ in
                sendSnapshotNow()
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

        guard workout.captureDevice ==
                .appleWatch
        else {
            sendSnapshotNow()
            return true
        }

        if workout
            .advancedConfiguration?
            .inputMode == .iPhone {
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
            command.kind == .completeSet ||
            command.kind ==
                .completeSetWithoutDetails

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

        case .addRest:
            strengthWorkout.addRest(
                seconds: command.addRestSeconds ?? 30
            )

        case .nextExercise:
            strengthWorkout.moveToNextExercise()

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
