import Combine
import Foundation
import Supabase

/// Minimal completed-strength record for account sync.
/// This purpose-built DTO cannot carry HealthKit identifiers/metrics, sleep,
/// HRV, live HR, GPS positions or workout-place details.
struct ATHLTHStrengthSyncDocument: Codable, Equatable {
    let id: UUID
    let plannedSessionID: UUID?
    let captureDevice: WorkoutCaptureDevice
    let trackingMode: StrengthTrackingMode
    let title: String
    let startedAt: Date
    let endedAt: Date
    let exercises: [StrengthExerciseLog]

    init?(workout: StrengthWorkoutLog) {
        guard workout.isFinished,
              let ended = workout.endedAt, ended >= workout.startedAt else {
            return nil
        }
        id = workout.id
        plannedSessionID = workout.plannedSessionID
        captureDevice = workout.captureDevice
        trackingMode = workout.trackingMode
        title = workout.title
        startedAt = workout.startedAt
        endedAt = ended
        exercises = workout.exercises.map { original in
            var value = original
            value.exercise.instructions = []
            value.targetHeartRateZone = nil
            value.sets = original.sets.map { source in
                var set = source
                set.plannedNote = nil
                set.watchAverageHeartRateBPM = nil
                set.watchMaximumHeartRateBPM = nil
                set.watchMeasuredDistanceMeters = nil
                set.watchActiveDurationSeconds = nil
                set.hybridTargetHeartRateZone = nil
                return set
            }
            return value
        }
    }

    func asWorkout() -> StrengthWorkoutLog {
        StrengthWorkoutLog(
            id: id,
            plannedSessionID: plannedSessionID,
            watchSessionID: nil,
            captureDevice: captureDevice,
            trackingMode: trackingMode,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            exercises: exercises,
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: nil,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            )
        )
    }
}

@MainActor
final class ATHLTHStrengthAccountSyncStore: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var status = "Strength history sync waits for sign-in."

    private struct Record: Codable {
        let user_id: UUID
        let workout_id: UUID
        let started_at: Date
        let ended_at: Date
        let document: ATHLTHStrengthSyncDocument

        init(userID: UUID, document: ATHLTHStrengthSyncDocument) {
            self.user_id = userID
            workout_id = document.id
            started_at = document.startedAt
            ended_at = document.endedAt
            self.document = document
        }

        func validatedWorkout(owner: UUID) -> StrengthWorkoutLog? {
            guard user_id == owner, workout_id == document.id,
                  ended_at >= started_at,
                  abs(document.startedAt.timeIntervalSince(started_at)) < 1,
                  abs(document.endedAt.timeIntervalSince(ended_at)) < 1,
                  document.exercises.count <= 200 else { return nil }
            return document.asWorkout()
        }
    }

    private static var syncingAccounts = Set<UUID>()
    private let client = SupabaseEnvironment.client
    private var accountID: UUID?
    private var task: Task<Void, Never>?
    private var lastSyncedLocalCount = -1

    func switchAccount(_ id: UUID?) {
        guard accountID != id else { return }
        task?.cancel()
        task = nil
        accountID = id
        isBusy = false
        lastSuccessfulSync = nil
        lastSyncedLocalCount = -1
        status = id == nil ? "Sign in to sync training history." :
            "Strength training history syncs automatically with your account."
    }

    func scheduleSync(session: AppSessionStore, strength: StrengthWorkoutStore) {
        guard session.signedIn, !session.previewModeEnabled else { return }
        let id = session.profile.userID
        switchAccount(id)
        task?.cancel()
        task = Task { [weak self, weak session, weak strength] in
            do { try await Task.sleep(for: .milliseconds(1000)) }
            catch { return }
            guard !Task.isCancelled, let self, let session, let strength else {
                return
            }
            await self.sync(session: session, strength: strength)
        }
    }

    func sync(session: AppSessionStore, strength: StrengthWorkoutStore, force: Bool = false) async {
        guard session.signedIn, !session.previewModeEnabled,
              let owner = accountID,
              session.profile.userID == owner,
              client.auth.currentUser?.id == owner,
              !isBusy, !Self.syncingAccounts.contains(owner) else { return }
        // Periodic foreground checks are cheap when nothing changed. Local
        // completed workouts bypass this delay and publish promptly.
        if !force, let lastSuccessfulSync,
           Date().timeIntervalSince(lastSuccessfulSync) < 60,
           lastSyncedLocalCount == strength.workoutHistory.count {
            return
        }

        Self.syncingAccounts.insert(owner)
        isBusy = true
        defer {
            Self.syncingAccounts.remove(owner)
            isBusy = false
        }

        do {
            // First fetch every page; a truncated listing must never cause
            // a server record to be treated as missing or deleted.
            var remote: [Record] = []
            let pageSize = 200
            while true {
                let page: [Record] = try await client
                    .from("account_strength_workout_sync")
                    .select("user_id,workout_id,started_at,ended_at,document")
                    .eq("user_id", value: owner)
                    .order("ended_at", ascending: false)
                    .range(from: remote.count, to: remote.count + pageSize - 1)
                    .execute().value
                guard accountID == owner,
                      session.signedIn,
                      session.profile.userID == owner else { return }
                remote.append(contentsOf: page)
                if page.count < pageSize { break }
            }

            let remoteIDs = Set(remote.map(\.workout_id))
            let local = strength.workoutHistory
            var seenLocal = Set<UUID>()
            let missing = local.compactMap { workout -> Record? in
                guard seenLocal.insert(workout.id).inserted,
                      !remoteIDs.contains(workout.id),
                      let document = ATHLTHStrengthSyncDocument(
                          workout: workout
                      ) else { return nil }
                return Record(userID: owner, document: document)
            }

            // Append-only: a stale device cannot replace a newer/sanitized
            // workout. Offline completions are retried next time when online.
            // Insert individually to survive another device winning a race
            // for the same workout ID, without losing other pending records.
            var pendingUploads = 0
            for row in missing {
                guard accountID == owner,
                      session.signedIn,
                      session.profile.userID == owner,
                      client.auth.currentUser?.id == owner else { return }
                do {
                    try await client.from("account_strength_workout_sync")
                        .insert(row).execute()
                } catch {
                    // Concurrent insertion may have won this ID. Verify on
                    // the next fetch, never overwrite or discard local data.
                    pendingUploads += 1
                }
            }

            guard accountID == owner,
                  session.signedIn,
                  session.profile.userID == owner else { return }
            // Local records always win for the same ID: they may contain
            // private HealthKit associations not sent to the server.
            let downloads = remote.compactMap {
                $0.validatedWorkout(owner: owner)
            }
            let added = try strength.mergeAccountSyncedWorkouts(
                downloads, for: owner
            )
            if pendingUploads > 0 {
                // Do not claim an incomplete upload is fully synchronized.
                lastSuccessfulSync = nil
                lastSyncedLocalCount = -1
                status = "\(pendingUploads) completed workouts will retry sync. " +
                    "\(added) received."
            } else {
                lastSuccessfulSync = Date()
                lastSyncedLocalCount = strength.workoutHistory.count
                status = "Training history synced. \(added) new workouts received."
            }
        } catch {
            if accountID == session.profile.userID {
                status = "Offline or sync unavailable; local workouts remain safe. " +
                    error.localizedDescription
            }
        }
    }
}
