import SwiftUI

/// Keeps the high-frequency strength <-> Apple Watch synchronization out of
/// AppRootView so reps/weight/rest edits do not invalidate the entire app
/// hierarchy.
struct ATHLTHStrengthWatchSyncObserver: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    @State private var processedCommandIDs: Set<UUID> = []
    @State private var pendingDraftSnapshotTask: Task<Void, Never>?
    @State private var lastStrengthMutationAtByWorkout:
        [UUID: Date] = [:]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                sendSnapshotNow()
            }
            .onDisappear {
                pendingDraftSnapshotTask?.cancel()
                pendingDraftSnapshotTask = nil
            }
            .onChange(of: watchConnection.lastStrengthCommand) { _, command in
                guard let command else { return }
                handle(command)
                watchConnection.clearStrengthCommand()
            }
            .onChange(of: strengthWorkout.activeWorkout) { _, _ in
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
    ) {
        guard !processedCommandIDs.contains(command.id) else {
            return
        }

        processedCommandIDs.insert(command.id)
        if processedCommandIDs.count > 200 {
            processedCommandIDs =
                Set(processedCommandIDs.suffix(100))
        }

        if command.kind == .requestSnapshot {
            sendSnapshotNow()
            return
        }

        guard let workout = strengthWorkout.activeWorkout,
              workout.captureDevice == .appleWatch
        else {
            return
        }

        if workout
            .advancedConfiguration?
            .inputMode == .iPhone {
            sendSnapshotNow()
            return
        }

        if let workoutID = command.workoutID,
           workoutID != workout.id {
            sendSnapshotNow()
            return
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
            return
        }

        if setScopedCommand,
           let setIndex =
                command.setIndex,
           setIndex !=
                strengthWorkout
                    .currentSetIndex {
            sendSnapshotNow()
            return
        }

        if command.kind == .nextExercise,
           let exerciseIndex =
                command.exerciseIndex,
           exerciseIndex !=
                strengthWorkout
                    .currentExerciseIndex {
            sendSnapshotNow()
            return
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
            return
        }

        switch command.kind {
        case .updateDraft:
            strengthWorkout.setDraft(
                reps: command.reps,
                weightKilograms: command.weightKilograms,
                restSeconds: command.restSeconds,
                rpe: command.rpe,
                rir: command.rir,
                warmUp: command.isWarmUp
            )

        case .completeSet:
            strengthWorkout.setDraft(
                reps: command.reps,
                weightKilograms: command.weightKilograms,
                restSeconds: command.restSeconds,
                rpe: command.rpe,
                rir: command.rir,
                warmUp: command.isWarmUp
            )
            strengthWorkout.completeCurrentDraftSet()

        case .completeSetWithoutDetails:
            if let restSeconds = command.restSeconds {
                strengthWorkout.setDraft(
                    restSeconds: restSeconds
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
