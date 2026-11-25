import Foundation

enum StrengthDraftMutationOrigin {
    case iPhone
    case watch
}

/// iPhone time targets are edited as whole minutes while the engine, Watch
/// synchronization and HealthKit history continue to use precise seconds.
enum StrengthTimedSetMinuteInput {
    static func minutes(for seconds: Int) -> Int {
        min(max((max(seconds, 0) + 59) / 60, 1), 120)
    }

    static func seconds(for minutes: Int) -> Int {
        min(max(minutes, 1), 120) * 60
    }
}

/// Date-anchored and checkpointed; the displayed seconds do not depend on a
/// foreground Timer continuing to run while the phone is locked.
struct StrengthTimedSetCountdown: Codable, Equatable {
    let workoutID: UUID
    let exerciseID: UUID
    let setID: UUID
    let targetSeconds: Int
    var secondsAtPause: TimeInterval
    var resumedAt: Date?

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(ATHLTHWorkoutSessionClock.remaining(
            secondsAtPause: secondsAtPause,
            resumedAt: resumedAt,
            at: date
        ), 0)
    }

    func secondsRemaining(at date: Date = Date()) -> Int {
        Int(ceil(remaining(at: date)))
    }

    func secondsCompleted(at date: Date = Date()) -> Int {
        min(max(targetSeconds - secondsRemaining(at: date), 0), targetSeconds)
    }

    /// Actual duration continues after the target reaches zero. A paused
    /// countdown retains negative secondsAtPause so overtime is not lost.
    func elapsedSeconds(at date: Date = Date()) -> Int {
        let remaining = ATHLTHWorkoutSessionClock.remaining(
            secondsAtPause: secondsAtPause,
            resumedAt: resumedAt,
            at: date
        )
        return max(Int((Double(targetSeconds) - remaining).rounded(.down)), 0)
    }

    func overtimeSeconds(at date: Date = Date()) -> Int {
        max(elapsedSeconds(at: date) - targetSeconds, 0)
    }

    func isFinished(at date: Date = Date()) -> Bool {
        remaining(at: date) <= 0
    }

    var isRunning: Bool { resumedAt != nil }

    /// Preserve exact negative remaining time (overtime), while freezing
    /// a local timer at the last durable checkpoint on process recovery.
    mutating func pause(at date: Date) {
        guard let resumedAt else { return }
        secondsAtPause = ATHLTHWorkoutSessionClock.remaining(
            secondsAtPause: secondsAtPause,
            resumedAt: resumedAt,
            at: max(date, resumedAt)
        )
        self.resumedAt = nil
    }
}

/// Date-anchored count-up clock. Identity protects against a stale
/// checkpoint displaying time for another set after navigation.
struct StrengthSetEffortClock: Codable, Equatable {
    let workoutID: UUID
    let exerciseID: UUID
    let setID: UUID
    let startedAt: Date

    var pausedAt: Date? = nil
    // Optional for forward-compatible decoding of saved live-workout clocks.
    var totalPausedSeconds: TimeInterval? = nil

    func elapsedSeconds(at now: Date = Date()) -> TimeInterval {
        ATHLTHWorkoutSessionClock.elapsed(
            startedAt: startedAt,
            pausedAt: pausedAt,
            excludedPauseSeconds: totalPausedSeconds ?? 0,
            at: now
        )
    }

    mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        totalPausedSeconds = (totalPausedSeconds ?? 0) +
            max(now.timeIntervalSince(pausedAt), 0)
        self.pausedAt = nil
    }
}


/// Late Watch rest commands must never mutate a different exercise, set or
/// newer rest period. Older commands without indices remain decodable, but
/// an explicit outdated target is always rejected.
enum ATHLTHStrengthWatchRestActionPolicy {
    static func accepts(
        _ command: WatchStrengthCommand,
        exerciseIndex: Int,
        setIndex: Int,
        restStartedAt: Date?
    ) -> Bool {
        if let targetExercise = command.exerciseIndex,
           targetExercise != exerciseIndex { return false }
        if let targetSet = command.setIndex,
           targetSet != setIndex { return false }
        // Allow minor device-clock skew, but reject a command issued before
        // the currently running rest began. This protects against delayed
        // WatchConnectivity packets after a station/round transition.
        if let startedAt = restStartedAt,
           command.sentAt.addingTimeInterval(2) < startedAt { return false }
        return true
    }
}

/// Mutating commands from Watch must belong to the single active workout.
enum ATHLTHStrengthWatchCommandIdentityPolicy {
    static func belongsToActiveWorkout(
        _ command: WatchStrengthCommand, workoutID: UUID
    ) -> Bool {
        command.kind == .requestSnapshot || command.workoutID == workoutID
    }
}


 
/// Idempotent replay per workout across multiple batches in one app session.
/// The WatchConnectivity receiver persists its own handled UUID journal
/// across restarts; this local gate protects repeated replay calls.
struct ATHLTHStrengthWatchReplayDeduplication {
    private var workoutID: UUID?
    private var recentIDs: Set<UUID> = []
    private var orderedIDs: [UUID] = []

    mutating func admit(commandID: UUID, workoutID: UUID) -> Bool {
        if self.workoutID != workoutID {
            self.workoutID = workoutID
            recentIDs.removeAll()
            orderedIDs.removeAll()
        }
        guard recentIDs.insert(commandID).inserted else { return false }
        orderedIDs.append(commandID)
        if orderedIDs.count > 2_048 {
            orderedIDs = Array(orderedIDs.suffix(1_024))
            recentIDs = Set(orderedIDs)
        }
        return true
    }
}

@MainActor
final class StrengthWorkoutStore: ObservableObject {
    @Published private(set) var activeWorkout: StrengthWorkoutLog? { didSet { scheduleCheckpointPersist() } }

    /// Same session-state contract as running, derived from the strength
    /// checkpoint. It cannot create an extra HealthKit session or log.
    var activeSessionState: ATHLTHWorkoutSessionState? {
        activeWorkout.map {
            ATHLTHWorkoutSessionFoundation.strength(
                $0,
                exerciseIndex: currentExerciseIndex,
                isResting: isResting,
                suspendedAt: $0.captureDevice == .iPhone
                    ? recoveredCheckpointSavedAt : nil
            )
        }
    }
    @Published private(set) var currentExerciseIndex = 0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var currentSetIndex = 0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var restEndsAt: Date? { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var restStartedAt: Date? { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var isFreeTrainingBetweenExercises = false {
        didSet { scheduleCheckpointPersist() }
    }
    @Published private(set) var draftReps = 8 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftDurationSeconds = 60 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftWeightKilograms = 20.0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftTreadmillSpeedKilometersPerHour = 0.0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftTreadmillInclinePercent = 0.0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftResistanceLevel = 5 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftRestSeconds = 90 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftRPE = 8.0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftRIR = 2.0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftWarmUp = false { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var timedSetCountdown: StrengthTimedSetCountdown? {
        didSet { scheduleCheckpointPersist() }
    }
    @Published private(set) var setEffortClock: StrengthSetEffortClock? {
        didSet { scheduleCheckpointPersist() }
    }
    @Published private(set) var completedWorkout: StrengthWorkoutLog?
    @Published private(set) var completionSaveError: String?
    @Published private(set) var workoutHistory: [StrengthWorkoutLog] = [] {
        didSet {
            personalRecordMemo.clear()
            repRecordMemo.clear()
        }
    }
    private let personalRecordMemo = ATHLTHProjectionMemo<String, [StrengthPersonalRecord]>()
    private let repRecordMemo = ATHLTHProjectionMemo<String, [StrengthRepPersonalRecord]>()
    /// Completed workouts imported from the signed-in account are merged
    /// into the same local journal, without replacing existing results.
    @Published private(set) var lastPhoneDraftMutationAt:
        Date = .distantPast
    @Published private(set) var recoveredCheckpointSavedAt:
        Date?

    private let staleRecoveryInterval:
        TimeInterval = 12 * 60 * 60

    var hasRecoveredActiveWorkout: Bool {
        activeWorkout != nil &&
        recoveredCheckpointSavedAt != nil
    }

    var recoveredActiveWorkoutNeedsReview: Bool {
        guard activeWorkout != nil,
              let recoveredCheckpointSavedAt
        else {
            return false
        }

        return Date()
            .timeIntervalSince(
                recoveredCheckpointSavedAt
            ) >= staleRecoveryInterval
    }

    var recoveredActiveWorkoutReferenceDate: Date? {
        recoveredCheckpointSavedAt
    }

    /// All strength and hybrid views use this same elapsed source. The
    /// suspended date only applies to this active phone-owned workout,
    /// never a different completed log or an independently running Watch.
    func elapsedSessionSeconds(
        for workout: StrengthWorkoutLog,
        at now: Date = Date()
    ) -> TimeInterval {
        let suspended = activeWorkout?.id == workout.id &&
            workout.captureDevice == .iPhone
            ? recoveredCheckpointSavedAt : nil
        return workout.elapsedSessionSeconds(at: now, suspendedAt: suspended)
    }

    private var accountID: UUID?
    private var loadingAccount = false
    @Published private(set) var activeGhostReferences: [UUID: ATHLTHExerciseProgress.GhostReference] = [:]

    func ghostReference(for exercise: StrengthExerciseLog) -> ATHLTHExerciseProgress.GhostReference? {
        guard let workout = activeWorkout, let reference = activeGhostReferences[exercise.id],
              reference.applies(to: workout.id, exercise: exercise),
              workoutHistory.contains(where: { $0.id == reference.result.id && $0.isFinished })
        else { return nil }
        return reference
    }

    @discardableResult
    func pinGhostReference(workoutID: UUID, exerciseID: UUID, historicalWorkoutID: UUID) -> Bool {
        guard let workout = activeWorkout, workout.id == workoutID,
              let exercise = currentExercise, exercise.id == exerciseID,
              exercise.isEmbeddedRunningInterval != true else { return false }
        let snapshot = exercise.exercise
        let summary = ATHLTHExerciseProgress.liveSummary(
            exercise: exercise, workouts: workoutHistory)
        guard let reference = summary.sessions.first(where: { $0.id == historicalWorkoutID }),
              reference.completedSets > 0 else { return false }
        activeGhostReferences = activeGhostReferences.filter { $0.value.workoutID == workoutID }
        activeGhostReferences[exerciseID] = .init(
            workoutID: workoutID, exerciseID: exerciseID,
            exerciseSnapshot: snapshot, result: reference, exactIdentityVersion: 1)
        persistCheckpointNow()
        return true
    }

    func clearGhostReference(workoutID: UUID, exerciseID: UUID) {
        guard activeWorkout?.id == workoutID else { return }
        activeGhostReferences.removeValue(forKey: exerciseID)
        persistCheckpointNow()
    }

    /// The Watch command observer must not process, publish or acknowledge
    /// account-owned set data before the authoritative store has actually
    /// switched its checkpoint and history to the signed-in athlete.
    func isLoaded(for userID: UUID) -> Bool {
        !loadingAccount && accountID == userID
    }
    private var checkpointSaveTask: Task<Void, Never>?
    private var cardioWatchCaptures: [UUID: StrengthWatchCardioCapture] = [:]
    private var watchCaptureNeedsBaseline = Set<UUID>()
    private var offlineWatchReplayDeduplication =
        ATHLTHStrengthWatchReplayDeduplication()
    private var lastCardioWatchCheckpointAt: Date = .distantPast
    @Published private(set) var hasLegacyHistory = false

    private struct Checkpoint: Codable {
        var workout: StrengthWorkoutLog?
        var exerciseIndex: Int
        var setIndex: Int
        var restEndsAt: Date?
        var restStartedAt: Date? = nil
        var isFreeTrainingBetweenExercises: Bool? = nil
        var reps: Int
        var durationSeconds: Int? = nil
        var weight: Double
        var treadmillSpeedKilometersPerHour: Double? = nil
        var treadmillInclinePercent: Double? = nil
        var resistanceLevel: Int? = nil
        var rest: Int
        var rpe: Double
        var rir: Double? = nil
        var warmUp: Bool? = nil
        var timedSetCountdown: StrengthTimedSetCountdown? = nil
        var setEffortClock: StrengthSetEffortClock? = nil
        var cardioWatchCaptures: [UUID: StrengthWatchCardioCapture]? = nil
        var savedAt: Date? = nil
        var ghostReferences: [UUID: ATHLTHExerciseProgress.GhostReference]? = nil
    }

    init() {
        ATHLTHWorkoutRecordingArbiter.strength = self
    }

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        // Flush an outstanding set/exercise edit before changing ownership.
        // Otherwise the 350 ms debounce can discard the athlete's last set.
        if activeWorkout != nil, checkpointSaveTask != nil {
            persistCheckpointNow()
        }
        checkpointSaveTask?.cancel()
        checkpointSaveTask = nil
        loadingAccount = true
        defer { loadingAccount = false }
        accountID = userID
        activeGhostReferences = [:]
        cardioWatchCaptures = [:]
        watchCaptureNeedsBaseline = []
        completedWorkout = nil
        completionSaveError = nil
        workoutHistory =
            (
                userID.flatMap {
                    AccountLocalStorage.read(
                        [StrengthWorkoutLog].self,
                        name: "strengthHistory",
                        userID: $0
                    )
                } ?? []
            )
            .sorted {
                $0.startedAt > $1.startedAt
            }
        // A durable finish receipt survives a crash between committing the
        // completed history and clearing the active workout checkpoint.
        if let userID,
           !UserDefaults.standard.bool(forKey: AccountLocalStorage.key("deleted", userID: userID)),
           let completed = StrengthWorkoutCompletionJournal.read(userID: userID),
           !workoutHistory.contains(where: { $0.id == completed.id }) {
            workoutHistory.insert(completed, at: 0)
            workoutHistory.sort { $0.startedAt > $1.startedAt }
            persistWorkoutHistory()
        }
        if let userID {
            repairInvalidTimedCoreHistory(for: userID)
        }
        let checkpoint = userID.flatMap { AccountLocalStorage.read(Checkpoint.self, name: "strengthActive", userID: $0) }
        activeWorkout = checkpoint?.workout
        cardioWatchCaptures = checkpoint?.cardioWatchCaptures ?? [:]
        if let workout = activeWorkout,
           !ATHLTHWorkoutSessionFoundation.mayRecoverCheckpoint(
                hasEnded: workout.endedAt != nil,
                alreadyCommitted: workoutHistory.contains {
                    $0.id == workout.id
                }
           ) {
            activeWorkout = nil
        }
        if let workout = activeWorkout {
            activeGhostReferences = (checkpoint?.ghostReferences ?? [:]).filter { _, reference in
                reference.workoutID == workout.id &&
                    workout.exercises.contains(where: { reference.applies(to: workout.id, exercise: $0) }) &&
                    workoutHistory.contains(where: { $0.id == reference.result.id && $0.isFinished })
            }
        }
        recoveredCheckpointSavedAt =
            activeWorkout == nil
                ? nil
                : (
                    checkpoint?.savedAt ??
                    activeWorkout?.startedAt
                )
        // Bound restored indices to the actual recovered exercise list. A
        // stale index after editing/deleting an exercise must not strand Train.
        if let workout = activeWorkout, !workout.exercises.isEmpty {
            currentExerciseIndex = min(max(0, checkpoint?.exerciseIndex ?? 0), workout.exercises.count - 1)
            let sets = workout.exercises[currentExerciseIndex].sets
            currentSetIndex = min(max(0, checkpoint?.setIndex ?? 0), max(0, sets.count - 1))
        } else {
            currentExerciseIndex = 0
            currentSetIndex = 0
        }
        restEndsAt = checkpoint?.restEndsAt
        restStartedAt =
            checkpoint?.restStartedAt
        isFreeTrainingBetweenExercises =
            checkpoint?.isFreeTrainingBetweenExercises ?? false
        draftReps = checkpoint?.reps ?? 8
        draftDurationSeconds =
            checkpoint?.durationSeconds ?? 60
        draftWeightKilograms = checkpoint?.weight ?? 20
        draftTreadmillSpeedKilometersPerHour = checkpoint?.treadmillSpeedKilometersPerHour ?? 0
        draftTreadmillInclinePercent = checkpoint?.treadmillInclinePercent ?? 0
        draftResistanceLevel =
            min(
                max(
                    checkpoint?.resistanceLevel ?? 5,
                    1
                ),
                10
            )
        draftRestSeconds = checkpoint?.rest ?? 90
        draftRPE = checkpoint?.rpe ?? 8
        draftRIR = checkpoint?.rir ?? 2
        draftWarmUp = checkpoint?.warmUp ?? false
        timedSetCountdown = checkpoint?.timedSetCountdown
        setEffortClock = checkpoint?.setEffortClock
        discardStaleTimedSetCountdown()
        discardStaleSetEffortClock()
        // Phone-only timers cannot keep running across a process crash.
        // Watch-owned sessions continue independently in HealthKit and are
        // reconciled through Watch commands instead of inventing phone time.
        if let savedAt = recoveredCheckpointSavedAt,
           activeWorkout?.captureDevice == .iPhone {
            if var countdown = timedSetCountdown {
                countdown.pause(at: savedAt)
                timedSetCountdown = countdown
            }
            if var effort = setEffortClock {
                effort.pause(at: max(savedAt, effort.startedAt))
                setEffortClock = effort
            }
            // Ending the stale rest at the checkpoint preserves the actual
            // measured rest without counting hours while the app was closed.
            if let restStartedAt {
                finalizeActualRestIfNeeded(at: max(savedAt, restStartedAt))
                self.restStartedAt = nil
                restEndsAt = nil
            }
        }
        hasLegacyHistory = userID != nil && UserDefaults.standard.string(forKey: "legacy.strengthClaimedBy") == nil && !Self.loadWorkoutHistory().isEmpty
    }

    enum AccountSyncMergeError: LocalizedError {
        case accountChanged
        var errorDescription: String? {
            "The ATHLTH account changed during strength history synchronization."
        }
    }

    /// Automatically merge immutable completed workouts from the signed-in
    /// account. Existing local records always win by workout ID so private
    /// HealthKit references and any locally edited logs are never replaced.
    /// The active workout and its recovery checkpoint remain untouched.
    @discardableResult
    func mergeAccountSyncedWorkouts(
        _ incoming: [StrengthWorkoutLog],
        for owner: UUID
    ) throws -> Int {
        guard accountID == owner,
              !loadingAccount else {
            throw AccountSyncMergeError.accountChanged
        }
        var seen = Set(workoutHistory.map(\.id))
        var seenHealthKitUUIDs = Set(workoutHistory.compactMap {
            $0.healthMetrics.healthKitWorkoutUUID
        })
        // Remote history is evidence, never a second recording. Reject
        // invalid intervals and duplicate HealthKit ownership while keeping
        // all existing local records authoritative.
        let newWorkouts = incoming.filter { workout in
            guard workout.isFinished,
                  let endedAt = workout.endedAt,
                  endedAt >= workout.startedAt,
                  !seen.contains(workout.id) else { return false }
            if let uuid = workout.healthMetrics.healthKitWorkoutUUID {
                guard !seenHealthKitUUIDs.contains(uuid) else { return false }
                seenHealthKitUUIDs.insert(uuid)
            }
            seen.insert(workout.id)
            return true
        }
        guard !newWorkouts.isEmpty else { return 0 }
        let combined = (workoutHistory + newWorkouts)
            .sorted { $0.startedAt > $1.startedAt }
        // Persist BEFORE publishing to SwiftUI. Failed writes never make
        // the UI claim the imported evidence is durable.
        try AccountLocalStorage.writeChecked(
            combined, name: "strengthHistory", userID: owner
        )
        guard accountID == owner else {
            throw AccountSyncMergeError.accountChanged
        }
        workoutHistory = combined
        ATHLTHTrainingDataChangeSignal.post(userID: owner)
        return newWorkouts.count
    }

    func restoreLegacyHistory() {
        guard let accountID, hasLegacyHistory else { return }
        let ids = Set(workoutHistory.map(\.id))
        workoutHistory += Self.loadWorkoutHistory().filter { !ids.contains($0.id) }
        workoutHistory.sort { $0.startedAt > $1.startedAt }
        repairInvalidTimedCoreHistory(for: accountID)
        persistWorkoutHistory()
        UserDefaults.standard.set(accountID.uuidString, forKey: "legacy.strengthClaimedBy")
        hasLegacyHistory = false
    }

    private func repairInvalidTimedCoreHistory(for userID: UUID) {
        let repaired = StrengthTimedHistoryRepair.clean(workoutHistory)
        guard repaired.changed else { return }
        // Keep a private, per-account original copy so a mistaken
        // classification can be reviewed without irreversible data loss.
        if AccountLocalStorage.read(
            [StrengthWorkoutLog].self,
            name: "strengthHistoryBeforeTimedFixV1",
            userID: userID
        ) == nil {
            AccountLocalStorage.write(
                workoutHistory,
                name: "strengthHistoryBeforeTimedFixV1",
                userID: userID
            )
        }
        workoutHistory = repaired.history
        persistWorkoutHistory()
    }

    private func scheduleCheckpointPersist() {
        guard accountID != nil, !loadingAccount else { return }

        checkpointSaveTask?.cancel()
        checkpointSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistCheckpointNow()
        }
    }

    private func persistCheckpointNow() {
        guard let accountID, !loadingAccount,
              !UserDefaults.standard.bool(forKey: AccountLocalStorage.key("deleted", userID: accountID)) else { return }

        checkpointSaveTask?.cancel()
        checkpointSaveTask = nil

        AccountLocalStorage.write(
            Checkpoint(
                workout: activeWorkout,
                exerciseIndex: currentExerciseIndex,
                setIndex: currentSetIndex,
                restEndsAt: restEndsAt,
                restStartedAt:
                    restStartedAt,
                isFreeTrainingBetweenExercises: isFreeTrainingBetweenExercises,
                reps: draftReps,
                durationSeconds: draftDurationSeconds,
                weight: draftWeightKilograms,
                treadmillSpeedKilometersPerHour: draftTreadmillSpeedKilometersPerHour,
                treadmillInclinePercent: draftTreadmillInclinePercent,
                resistanceLevel: draftResistanceLevel,
                rest: draftRestSeconds,
                rpe: draftRPE,
                rir: draftRIR,
                warmUp: draftWarmUp,
                timedSetCountdown: timedSetCountdown,
                setEffortClock: setEffortClock,
                cardioWatchCaptures: cardioWatchCaptures,
                // Backgrounding a recovered but unacknowledged workout must
                // not move the downtime boundary forward to the current time.
                savedAt: recoveredCheckpointSavedAt ?? Date(),
                ghostReferences: activeWorkout.map { workout in
                    activeGhostReferences.filter { $0.value.workoutID == workout.id }
                }
            ),
            name: "strengthActive",
            userID: accountID
        )
    }

    func checkpoint() {
        persistCheckpointNow()
    }

    func trophySnapshot() -> TrophyStrengthSnapshot {
        let completed = workoutHistory
            .filter(\.isFinished)
            .sorted { $0.startedAt < $1.startedAt }

        let thresholds = [10, 25, 50, 100, 250, 500]
        var reachedAt: [Int: Date] = [:]

        for (index, workout) in completed.enumerated() {
            let count = index + 1
            if thresholds.contains(count) {
                reachedAt[count] = workout.endedAt ?? workout.startedAt
            }
        }

        let volumeThresholds = [
            10_000,
            50_000,
            100_000,
            250_000,
            500_000,
            1_000_000,
            2_500_000
        ]
        var volumeReachedAt: [Int: Date] = [:]
        var totalVolumeKilograms = 0.0

        for workout in completed {
            totalVolumeKilograms +=
                max(
                    workout.totalVolumeKilograms,
                    0
                )

            for threshold in volumeThresholds
            where volumeReachedAt[threshold] == nil &&
                    totalVolumeKilograms >= Double(threshold) {
                volumeReachedAt[threshold] =
                    workout.endedAt ??
                    workout.startedAt
            }
        }

        let firstWeightedSetDate = completed
            .flatMap { workout in
                workout.exercises.flatMap { exercise in
                    exercise.sets.compactMap { set -> Date? in
                        guard set.countsTowardTrainingLoad,
                              let weight = set.completedWeightKilograms,
                              weight > 0
                        else {
                            return nil
                        }

                        return set.completedAt ?? workout.endedAt ?? workout.startedAt
                    }
                }
            }
            .min()

        let workingSetThresholds = [
            1_000,
            2_500
        ]
        let workingRepThresholds = [
            25_000
        ]
        let singleWorkoutVolumeThresholds = [
            10_000,
            20_000
        ]

        var workingSetCount = 0
        var workingSetCountReachedAt: [Int: Date] = [:]
        var totalWorkingRepetitions = 0
        var workingRepetitionCountReachedAt: [Int: Date] = [:]
        var maxWorkoutVolumeKilograms = 0.0
        var workoutVolumeReachedAt: [Int: Date] = [:]

        for workout in completed {
            let workoutDate =
                workout.endedAt ??
                workout.startedAt
            let workoutVolume =
                max(
                    workout.totalVolumeKilograms,
                    0
                )

            maxWorkoutVolumeKilograms =
                max(
                    maxWorkoutVolumeKilograms,
                    workoutVolume
                )

            for threshold in singleWorkoutVolumeThresholds
            where workoutVolumeReachedAt[threshold] == nil &&
                    workoutVolume >= Double(threshold) {
                workoutVolumeReachedAt[threshold] =
                    workoutDate
            }

            for exercise in workout.exercises {
                for set in exercise.sets
                where set.countsTowardTrainingLoad {
                    guard let reps =
                            set.resolvedCompletedReps,
                          reps > 0
                    else {
                        continue
                    }

                    workingSetCount += 1
                    totalWorkingRepetitions += reps

                    let setDate =
                        set.completedAt ??
                        workoutDate

                    for threshold in workingSetThresholds
                    where workingSetCountReachedAt[threshold] == nil &&
                            workingSetCount >= threshold {
                        workingSetCountReachedAt[threshold] =
                            setDate
                    }

                    for threshold in workingRepThresholds
                    where workingRepetitionCountReachedAt[threshold] == nil &&
                            totalWorkingRepetitions >= threshold {
                        workingRepetitionCountReachedAt[threshold] =
                            setDate
                    }
                }
            }
        }

        return TrophyStrengthSnapshot(
            completedWorkoutCount: completed.count,
            workoutCountReachedAt: reachedAt,
            firstWeightedSetDate: firstWeightedSetDate,
            totalVolumeKilograms:
                totalVolumeKilograms,
            volumeReachedAt:
                volumeReachedAt,
            completedWorkingSetCount:
                workingSetCount,
            workingSetCountReachedAt:
                workingSetCountReachedAt,
            totalWorkingRepetitions:
                totalWorkingRepetitions,
            workingRepetitionCountReachedAt:
                workingRepetitionCountReachedAt,
            maxWorkoutVolumeKilograms:
                maxWorkoutVolumeKilograms,
            workoutVolumeReachedAt:
                workoutVolumeReachedAt
        )
    }

    var personalRecords: [StrengthPersonalRecord] {
        personalRecordMemo.value(for: Locale.current.identifier) {
            let signpost = ATHLTHPerformance.begin("StrengthPersonalRecords")
            defer { ATHLTHPerformance.end("StrengthPersonalRecords", id: signpost) }
            return calculatePersonalRecords()
        }
    }

    private func calculatePersonalRecords() -> [StrengthPersonalRecord] {
        var bestSetByExercise: [String: (name: String, weight: Double, reps: Int, date: Date)] = [:]
        var bestEstimatedOneRepMax: (name: String, value: Double, weight: Double, reps: Int, date: Date)?
        var highestVolumeWorkout: StrengthWorkoutLog?

        for workout in workoutHistory where workout.isFinished {
            if workout.totalVolumeKilograms > 0,
               highestVolumeWorkout.map({
                   workout.totalVolumeKilograms > $0.totalVolumeKilograms
               }) ?? true {
                highestVolumeWorkout = workout
            }

            for exercise in workout.exercises {
                let exerciseName = exercise.exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !exerciseName.isEmpty else { continue }
                let key = exerciseName.lowercased()

                for set in exercise.sets
                where set.countsTowardTrainingLoad {
                    let completedAt =
                        set.completedAt ??
                        workout.endedAt ??
                        workout.startedAt

                    for effort in Self.repWeightEfforts(
                        in: set,
                        includeBodyweight: false
                    ) {
                        let weight = effort.weight
                        let reps = effort.reps

                        if let existing =
                                bestSetByExercise[key] {
                            if weight > existing.weight ||
                                (
                                    weight == existing.weight &&
                                    reps > existing.reps
                                ) {
                                bestSetByExercise[key] = (
                                    exerciseName,
                                    weight,
                                    reps,
                                    completedAt
                                )
                            }
                        } else {
                            bestSetByExercise[key] = (
                                exerciseName,
                                weight,
                                reps,
                                completedAt
                            )
                        }

                        if reps <= 12 {
                            let estimatedOneRepMax =
                                weight *
                                (
                                    1 +
                                    Double(reps) /
                                    30.0
                                )
                            if bestEstimatedOneRepMax.map({
                                estimatedOneRepMax >
                                    $0.value
                            }) ?? true {
                                bestEstimatedOneRepMax = (
                                    exerciseName,
                                    estimatedOneRepMax,
                                    weight,
                                    reps,
                                    completedAt
                                )
                            }
                        }
                    }
                }
            }
        }

        var records = bestSetByExercise.values
            .map { record in
                StrengthPersonalRecord(
                    id: "heaviest-set-\(record.name.lowercased())",
                    kind: .heaviestSet,
                    title: record.name,
                    value: "\(Self.formattedKilograms(record.weight)) kg × \(record.reps)",
                    date: record.date,
                    score: record.weight
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.date > rhs.date
                }
                return lhs.score > rhs.score
            }

        if let estimated = bestEstimatedOneRepMax {
            records.append(
                StrengthPersonalRecord(
                    id: "estimated-1rm",
                    kind: .estimatedOneRepMax,
                    title: "Estimated 1RM · \(estimated.name)",
                    value: "\(Self.formattedKilograms(estimated.value)) kg",
                    date: estimated.date,
                    score: estimated.value
                )
            )
        }

        if let volume = highestVolumeWorkout {
            records.append(
                StrengthPersonalRecord(
                    id: "workout-volume",
                    kind: .workoutVolume,
                    title: "Workout Volume",
                    value: "\(Self.formattedKilograms(volume.totalVolumeKilograms)) kg",
                    date: volume.endedAt ?? volume.startedAt,
                    score: volume.totalVolumeKilograms
                )
            )
        }

        return records
    }

    var repPersonalRecords: [StrengthRepPersonalRecord] {
        repRecordMemo.value(for: Locale.current.identifier) {
            let signpost = ATHLTHPerformance.begin("StrengthRepRecords")
            defer { ATHLTHPerformance.end("StrengthRepRecords", id: signpost) }
            return calculateRepPersonalRecords()
        }
    }

    private func calculateRepPersonalRecords() -> [StrengthRepPersonalRecord] {
        struct Candidate {
            let exerciseName: String
            let weightKilograms: Double
            let reps: Int
            let date: Date
            let workoutID: UUID
        }

        var bestByExerciseAndReps: [String: Candidate] = [:]

        for workout in workoutHistory where workout.isFinished {
            for exercise in workout.exercises {
                let exerciseName = exercise.exercise.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !exerciseName.isEmpty else { continue }

                let normalizedExercise = exerciseName.lowercased()

                for set in exercise.sets
                where set.countsTowardTrainingLoad {
                    let date =
                        set.completedAt ??
                        workout.endedAt ??
                        workout.startedAt

                    // Split sets are treated as their actual efforts. A set
                    // logged as 8 x 10 kg + 2 x 8 kg must never become a
                    // fictional 10-rep PR at 10 kg.
                    for effort in Self.repWeightEfforts(
                        in: set,
                        includeBodyweight: true
                    ) {
                        let reps = effort.reps
                        let weight = effort.weight

                        guard reps <= 20 else {
                            continue
                        }

                        let key =
                            "\(normalizedExercise)|\(reps)"
                        let candidate = Candidate(
                            exerciseName: exerciseName,
                            weightKilograms: weight,
                            reps: reps,
                            date: date,
                            workoutID: workout.id
                        )

                        if let existing =
                                bestByExerciseAndReps[key] {
                            if weight >
                                existing.weightKilograms ||
                                (
                                    weight ==
                                        existing.weightKilograms &&
                                    date > existing.date
                                ) {
                                bestByExerciseAndReps[key] =
                                    candidate
                            }
                        } else {
                            bestByExerciseAndReps[key] =
                                candidate
                        }
                    }
                }
            }
        }

        return bestByExerciseAndReps.values
            .map {
                StrengthRepPersonalRecord(
                    exerciseName: $0.exerciseName,
                    weightKilograms: $0.weightKilograms,
                    reps: $0.reps,
                    date: $0.date,
                    sourceWorkoutID: $0.workoutID
                )
            }
            .sorted {
                if $0.date == $1.date {
                    return $0.weightKilograms > $1.weightKilograms
                }
                return $0.date > $1.date
            }
    }

    func workoutPersonalRecords(
        for workout: StrengthWorkoutLog
    ) -> [StrengthWorkoutPersonalRecord] {
        struct Effort {
            let setID: UUID
            let reps: Int
            let weight: Double
        }

        func normalizedName(
            _ value: String
        ) -> String {
            value
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .folding(
                    options: [
                        .diacriticInsensitive,
                        .caseInsensitive
                    ],
                    locale: .current
                )
                .lowercased()
        }

        func efforts(
            in exercise:
                StrengthExerciseLog
        ) -> [Effort] {
            // A historical dummy load on a timed hold must never produce
            // a lifting PR, even when old sets still contain kilograms.
            guard !exercise.exercise.isTimeOnlyBodyweightStrength,
                  !StrengthCardioExercisePolicy.isCardio(exercise.exercise.name)
            else { return [] }

            return exercise.sets.flatMap {
                set -> [Effort] in

                guard set.countsTowardTrainingLoad,
                      set.recordsWeight != false,
                      set.resolvedTargetKind == .reps
                else {
                    return []
                }

                if let segments =
                        set.effortSegments,
                   !segments.isEmpty {
                    return segments
                        .compactMap {
                            segment in

                            guard
                                let reps =
                                    segment.reps,
                                reps > 0,
                                let weight =
                                    segment
                                        .weightKilograms,
                                weight > 0
                            else {
                                return nil
                            }

                            return Effort(
                                setID: set.id,
                                reps: reps,
                                weight: weight
                            )
                        }
                }

                guard
                    let reps =
                        set.completedReps,
                    reps > 0,
                    let weight =
                        set.completedWeightKilograms,
                    weight > 0
                else {
                    return []
                }

                return [
                    Effort(
                        setID: set.id,
                        reps: reps,
                        weight: weight
                    )
                ]
            }
        }

        var result:
            [StrengthWorkoutPersonalRecord] = []

        for exercise in workout.exercises {
            let name =
                exercise.exercise
                    .displayName
            let key =
                normalizedName(
                    exercise.exercise.name
                )

            guard !key.isEmpty else {
                continue
            }

            let current =
                efforts(in: exercise)

            guard !current.isEmpty else {
                continue
            }

            let previousExercises =
                workoutHistory
                    .filter {
                        $0.isFinished &&
                        $0.id != workout.id &&
                        // A record must be compared only with training
                        // evidence available before this workout began.
                        // Later sessions must not change historical PRs.
                        ($0.endedAt ?? .distantFuture) <= workout.startedAt
                    }
                    .flatMap {
                        $0.exercises
                    }
                    .filter {
                        normalizedName(
                            $0.exercise.name
                        ) == key
                    }

            let previous =
                previousExercises
                    .flatMap {
                        efforts(in: $0)
                    }

            // A first logged result establishes the baseline but is not
            // presented as a "new PR". This keeps the celebration meaningful.
            guard !previous.isEmpty else {
                continue
            }

            var exerciseRecords:
                [StrengthWorkoutPersonalRecord] =
                []

            var previousByReps:
                [Int: Double] = [:]
            var currentByReps:
                [Int: Effort] = [:]

            for effort in previous
            where effort.reps <= 20 {
                previousByReps[
                    effort.reps
                ] =
                    max(
                        previousByReps[
                            effort.reps
                        ] ?? 0,
                        effort.weight
                    )
            }

            for effort in current
            where effort.reps <= 20 {
                if let existing =
                        currentByReps[
                            effort.reps
                        ],
                   existing.weight >=
                        effort.weight {
                    continue
                }

                currentByReps[
                    effort.reps
                ] = effort
            }

            for reps in
                currentByReps.keys
                    .sorted() {
                guard
                    let currentEffort =
                        currentByReps[reps],
                    let previousBest =
                        previousByReps[reps],
                    currentEffort.weight >
                        previousBest + 0.01
                else {
                    continue
                }

                exerciseRecords.append(
                    StrengthWorkoutPersonalRecord(
                        id:
                            "rep-(exercise.id.uuidString)-(reps)",
                        exerciseID:
                            exercise.id,
                        exerciseName: name,
                        kind:
                            .repMax(
                                reps: reps
                            ),
                        value:
                            "\(Self.formattedKilograms(currentEffort.weight)) kg × \(reps)",
                        previousValue:
                            "\(Self.formattedKilograms(previousBest)) kg × \(reps)",
                        score:
                            currentEffort.weight,
                        setID:
                            currentEffort.setID
                    )
                )
            }

            if let currentHeaviest =
                    current.max(
                        by: {
                            $0.weight <
                            $1.weight
                        }
                    ),
               let previousHeaviest =
                    previous.map(
                        \.weight
                    ).max(),
               currentHeaviest.weight >
                    previousHeaviest + 0.01,
               !exerciseRecords
                    .contains(
                        where: {
                            $0.setID ==
                                currentHeaviest
                                    .setID
                        }
                    ) {
                exerciseRecords.append(
                    StrengthWorkoutPersonalRecord(
                        id:
                            "weight-(exercise.id.uuidString)",
                        exerciseID:
                            exercise.id,
                        exerciseName: name,
                        kind:
                            .heaviestWeight,
                        value:
                            "\(Self.formattedKilograms(currentHeaviest.weight)) kg",
                        previousValue:
                            "\(Self.formattedKilograms(previousHeaviest)) kg",
                        score:
                            currentHeaviest.weight,
                        setID:
                            currentHeaviest.setID
                    )
                )
            }

            // If no exact rep/heaviest record fired, estimated 1RM can still
            // identify real progression when reps changed between sessions.
            if exerciseRecords.isEmpty {
                let currentOneRM =
                    current
                        .filter {
                            $0.reps <= 12
                        }
                        .map {
                            effort in
                            (
                                effort:
                                    effort,
                                value:
                                    effort.weight *
                                    (
                                        1 +
                                        Double(
                                            effort.reps
                                        ) /
                                        30.0
                                    )
                            )
                        }
                        .max {
                            $0.value <
                            $1.value
                        }

                let previousOneRM =
                    previous
                        .filter {
                            $0.reps <= 12
                        }
                        .map {
                            $0.weight *
                            (
                                1 +
                                Double($0.reps) /
                                30.0
                            )
                        }
                        .max()

                if let currentOneRM,
                   let previousOneRM,
                   currentOneRM.value >
                        previousOneRM + 0.05 {
                    exerciseRecords.append(
                        StrengthWorkoutPersonalRecord(
                            id:
                                "e1rm-(exercise.id.uuidString)",
                            exerciseID:
                                exercise.id,
                            exerciseName:
                                name,
                            kind:
                                .estimatedOneRepMax,
                            value:
                                "\(Self.formattedKilograms(currentOneRM.value)) kg",
                            previousValue:
                                "\(Self.formattedKilograms(previousOneRM)) kg",
                            score:
                                currentOneRM.value,
                            setID:
                                currentOneRM
                                    .effort
                                    .setID
                        )
                    )
                }
            }

            result.append(
                contentsOf:
                    exerciseRecords
            )
        }

        return result.sorted {
            lhs,
            rhs in

            if lhs.exerciseName ==
                rhs.exerciseName {
                return lhs.score >
                    rhs.score
            }

            return lhs.exerciseName
                .localizedCaseInsensitiveCompare(
                    rhs.exerciseName
                ) == .orderedAscending
        }
    }

    var currentExercise: StrengthExerciseLog? {
        guard
            let workout = activeWorkout,
            workout.exercises.indices.contains(currentExerciseIndex)
        else {
            return nil
        }

        return workout.exercises[currentExerciseIndex]
    }

    var currentSet: StrengthSetLog? {
        guard
            let exercise = currentExercise,
            exercise.sets.indices.contains(currentSetIndex)
        else {
            return nil
        }

        return exercise.sets[currentSetIndex]
    }

    /// Per-set readings from the existing Watch strength workout only.
    /// This does not create another HealthKit workout or replace manual speed.
    func ingestWatchCardioSnapshot(_ snapshot: WatchWorkoutLiveSnapshot) {
        guard let workout = activeWorkout,
              workout.captureDevice == .appleWatch,
              let exercise = currentExercise,
              StrengthCardioExercisePolicy.isCardio(exercise.exercise.name),
              let set = currentSet,
              !set.isCompleted,
              set.resolvedTargetKind == .time,
              let countdown = currentTimedSetCountdown,
              countdown.isRunning,
              !isResting,
              snapshot.kind == .strength || snapshot.kind == .functional
        else { return }
        guard snapshot.state == .running,
              let watchStartedAt = snapshot.startedAt,
              abs(watchStartedAt.timeIntervalSince(workout.startedAt)) <= 180,
              snapshot.capturedAt >= workout.startedAt,
              snapshot.capturedAt >= (countdown.resumedAt ?? workout.startedAt),
              snapshot.elapsedTime.isFinite, snapshot.distanceMeters.isFinite,
              snapshot.elapsedTime >= 0, snapshot.distanceMeters >= 0
        else { return }

        let id = set.id
        if var capture = cardioWatchCaptures[id],
           capture.watchWorkoutStartedAt == watchStartedAt {
            if watchCaptureNeedsBaseline.remove(id) != nil {
                // When returning to a postponed set, skip intervening work.
                capture.lastCapturedAt = snapshot.capturedAt
                capture.lastElapsedTime = snapshot.elapsedTime
                capture.lastDistanceMeters = snapshot.distanceMeters
                capture.recordHeartRate(from: snapshot)
            } else {
                capture.ingest(snapshot)
            }
            cardioWatchCaptures[id] = capture
        } else {
            var capture = StrengthWatchCardioCapture(
                watchWorkoutStartedAt: watchStartedAt,
                lastCapturedAt: snapshot.capturedAt,
                lastElapsedTime: snapshot.elapsedTime,
                lastDistanceMeters: snapshot.distanceMeters
            )
            capture.recordHeartRate(from: snapshot)
            cardioWatchCaptures[id] = capture
            watchCaptureNeedsBaseline.remove(id)
        }
        if snapshot.capturedAt.timeIntervalSince(lastCardioWatchCheckpointAt) >= 15 {
            lastCardioWatchCheckpointAt = snapshot.capturedAt
            scheduleCheckpointPersist()
        }
    }

    var currentSetRecordsWeight: Bool {
        guard let set = currentSet else { return true }
        if let explicit = set.recordsWeight { return explicit }
        return !(set.resolvedTargetKind == .time &&
            currentExercise.map {
                StrengthTreadmillWarmUpDefaults.isTreadmill($0.exercise.name) ||
                StrengthTimedBodyweightDefaults.isBodyweightHold($0.exercise.name)
            } == true)
    }

    func setCurrentSetRecordsWeight(_ enabled: Bool) {
        guard var workout = activeWorkout,
              workout.exercises.indices.contains(currentExerciseIndex),
              workout.exercises[currentExerciseIndex].sets.indices.contains(currentSetIndex),
              !workout.exercises[currentExerciseIndex].sets[currentSetIndex].isCompleted
        else { return }
        workout.exercises[currentExerciseIndex].sets[currentSetIndex].recordsWeight = enabled
        activeWorkout = workout
        persistCheckpointNow()
    }

    var isResting: Bool {
        // Rest is a manual gate, not just a countdown. Once a rest period
        // starts it stays active until the athlete explicitly continues,
        // even after the planned duration has elapsed.
        restEndsAt != nil
    }

    var currentExerciseAllSetsCompleted: Bool {
        guard let exercise = currentExercise else { return false }
        // An exercise with every pending set explicitly skipped has no
        // completed set rows, but its completedAt marks a deliberate
        // transition. Without this check the Watch remains stuck on it.
        return exercise.isCompleted ||
            (!exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted))
    }

    var hasNextExercise: Bool {
        guard let workout = activeWorkout else {
            return false
        }

        return workout.exercises
            .enumerated()
            .contains {
                index, exercise in
                index != currentExerciseIndex &&
                !exercise.isCompleted
            }
    }

    // Only the active workout log is reordered: the saved training plan
    // and all completed set records keep their original identifiers.
    var nextPendingExercise: StrengthExerciseLog? {
        guard let workout = activeWorkout else {
            return nil
        }

        let later = workout.exercises.indices
            .dropFirst(currentExerciseIndex + 1)
            .first { !workout.exercises[$0].isCompleted }
        let earlier = workout.exercises.indices
            .prefix(currentExerciseIndex)
            .first { !workout.exercises[$0].isCompleted }
        guard let index = later ?? earlier else {
            return nil
        }
        return workout.exercises[index]
    }

    @discardableResult
    func selectExerciseForNow(_ exerciseID: UUID) -> Bool {
        guard let existing = activeWorkout,
              let targetIndex = existing.exercises.firstIndex(where: {
                  $0.id == exerciseID && !$0.isCompleted
              }) else { return false }

        // Motor change: finish a started timed phase using *actual* elapsed
        // seconds, not its planned duration. A set that was not started stays
        // uncompleted. This applies equally to treadmill intervals and
        // time-based strength sets, with one Watch/HealthKit session throughout.
        if targetIndex != currentExerciseIndex,
           let clock = currentTimedSetCountdown {
            if clock.elapsedSeconds() > 0,
               currentSet?.isCompleted == false {
                completeCurrentDraftSet()
            } else {
                timedSetCountdown = nil
            }
        }

        finalizeActualRestIfNeeded()
        guard var workout = activeWorkout,
              let target = workout.exercises.firstIndex(where: {
                  $0.id == exerciseID && !$0.isCompleted
              })
        else {
            return false
        }

        guard target != currentExerciseIndex else {
            return true
        }

        // Changing stations is deliberate; never mark the postponed
        // exercise complete or erase its partially completed sets.
        restStartedAt = nil
        restEndsAt = nil

        if workout.exercises.indices.contains(currentExerciseIndex),
           let completedAt = workout.exercises[currentExerciseIndex].completedAt {
            workout.exercises[currentExerciseIndex]
                .transitionToNextExerciseSeconds =
                max(Date().timeIntervalSince(completedAt), 0)
        }

        Self.beginStrengthGroup(&workout, selected: target)
        currentExerciseIndex = target
        currentSetIndex = workout.exercises[target].sets
            .firstIndex(where: { !$0.isResolved }) ?? 0
        activeWorkout = workout
        if let id = currentSet?.id {
            watchCaptureNeedsBaseline.insert(id)
        }
        reloadDraftFromCurrentSet()
        // Moving to a timed running/treadmill exercise starts its set immediately.
        // Re-selecting the current exercise does not reset its clock.
        if currentSet?.resolvedTargetKind == .time {
            startOrResumeTimedSet()
        }
        persistCheckpointNow()
        return true
    }

    /// Jump directly to an unfinished set, even within a different exercise.
    /// A completed set can be reviewed but is never implicitly repeated.
    @discardableResult
    func selectSetForNow(exerciseID: UUID, setID: UUID) -> Bool {
        guard let initialWorkout = activeWorkout,
              let exerciseIndex = initialWorkout.exercises.firstIndex(where: {
                  $0.id == exerciseID
              }),
              let setIndex = initialWorkout.exercises[exerciseIndex].sets.firstIndex(
                  where: { $0.id == setID && !$0.isResolved }
              )
        else { return false }

        if currentExerciseIndex == exerciseIndex && currentSetIndex == setIndex {
            return true
        }

        // Do not discard a started timer or effort when changing stations.
        guard currentTimedSetCountdown == nil, currentSetEffortClock == nil else { return false }
        finalizeActualRestIfNeeded()
        guard var workout = activeWorkout, workout.id == initialWorkout.id else { return false }
        // Never carry the timer or draft weight from the previously selected set.
        timedSetCountdown = nil
        restStartedAt = nil
        restEndsAt = nil
        Self.beginStrengthGroup(&workout, selected: exerciseIndex)
        activeWorkout = workout
        currentExerciseIndex = exerciseIndex
        currentSetIndex = setIndex
        isFreeTrainingBetweenExercises = false
        if let id = currentSet?.id {
            watchCaptureNeedsBaseline.insert(id)
        }
        reloadDraftFromCurrentSet()
        if currentSet?.resolvedTargetKind == .time {
            startOrResumeTimedSet()
        }
        persistCheckpointNow()
        return true
    }

    private static func queueTarget(
        _ entry: StrengthLiveQueueEntry, in workout: StrengthWorkoutLog
    ) -> (exercise: Int, set: Int)? {
        if let groupID = entry.groupID {
            var target: (exercise: Int, set: Int)?
            for (index, exercise) in workout.exercises.enumerated() where exercise.groupID == groupID {
                guard exercise.groupStyle == .circuit || exercise.groupStyle == .superset,
                      let set = exercise.sets.firstIndex(where: { !$0.isResolved }) else { continue }
                if target == nil || set < target!.set { target = (index, set) }
            }
            return target
        }
        guard let exercise = workout.exercises.firstIndex(where: {
            $0.id == entry.exerciseID && $0.groupID == nil
        }), let set = workout.exercises[exercise].sets.firstIndex(where: {
            !$0.isResolved && (entry.setID == nil || $0.id == entry.setID)
        }) else { return nil }
        return (exercise, set)
    }

    var pendingExecutionQueue: [StrengthLiveQueueEntry] {
        guard let workout = activeWorkout else { return [] }
        return (workout.liveExecutionQueue ?? []).filter {
            Self.queueTarget($0, in: workout) != nil
        }
    }

    @discardableResult
    func enqueueStrength(exerciseID: UUID, setID: UUID? = nil, next: Bool = false) -> Bool {
        guard var workout = activeWorkout else { return false }
        let exercise = workout.exercises.first { $0.id == exerciseID }
        let groupID = setID == nil ? exercise?.groupID : nil
        if groupID != nil, exercise?.groupStyle != .circuit && exercise?.groupStyle != .superset { return false }
        let entry = StrengthLiveQueueEntry(exerciseID: exerciseID, setID: setID, groupID: groupID)
        guard Self.queueTarget(entry, in: workout) != nil else { return false }
        var entries = pendingExecutionQueue
        // A whole exercise already includes its remaining sets.
        if setID == nil {
            entries.removeAll { $0.exerciseID == exerciseID || (groupID != nil && $0.groupID == groupID) }
        } else {
            if let existing = entries.firstIndex(where: {
                $0.exerciseID == exerciseID && ($0.setID == nil || $0.setID == setID)
            }) {
                guard next, entries[existing].setID == setID else { return false }
                entries.remove(at: existing)
            }
        }
        if next { entries.insert(entry, at: 0) } else { entries.append(entry) }
        workout.liveExecutionQueue = entries
        activeWorkout = workout
        persistCheckpointNow()
        return true
    }

    @discardableResult
    func enqueueStrengthSets(exerciseID: UUID, setIDs: Set<UUID>) -> Bool {
        guard var workout = activeWorkout,
              let exercise = workout.exercises.first(where: { $0.id == exerciseID && $0.groupID == nil })
        else { return false }
        var entries = pendingExecutionQueue
        guard !entries.contains(where: { $0.exerciseID == exerciseID && $0.setID == nil }) else { return false }
        let existing = Set(entries.compactMap(\.setID))
        let additions = exercise.sets.filter {
            !$0.isResolved && setIDs.contains($0.id) && !existing.contains($0.id)
        }.map { StrengthLiveQueueEntry(exerciseID: exerciseID, setID: $0.id) }
        guard !additions.isEmpty else { return false }
        entries.append(contentsOf: additions)
        workout.liveExecutionQueue = entries
        activeWorkout = workout
        persistCheckpointNow()
        return true
    }

    @discardableResult
    func moveQueuedStrength(_ id: UUID, before targetID: UUID) -> Bool {
        guard var workout = activeWorkout, id != targetID else { return false }
        var entries = pendingExecutionQueue
        guard let from = entries.firstIndex(where: { $0.id == id }),
              entries.contains(where: { $0.id == targetID }) else { return false }
        let entry = entries.remove(at: from)
        guard let to = entries.firstIndex(where: { $0.id == targetID }) else { return false }
        entries.insert(entry, at: to)
        workout.liveExecutionQueue = entries
        activeWorkout = workout
        persistCheckpointNow()
        return true
    }

    @discardableResult
    func postponeStrengthExercise(_ id: UUID) -> Bool {
        guard var workout = activeWorkout,
              let index = workout.exercises.firstIndex(where: { $0.id == id && $0.groupID == nil && !$0.isCompleted }),
              workout.exercises.contains(where: { $0.id != id && !$0.isCompleted })
        else { return false }
        if currentExercise?.id == id {
            guard currentTimedSetCountdown == nil, currentSetEffortClock == nil,
                  let next = workout.exercises.first(where: { $0.id != id && !$0.isCompleted }),
                  selectExerciseForNow(next.id), let fresh = activeWorkout else { return false }
            workout = fresh
        }
        guard let from = workout.exercises.firstIndex(where: { $0.id == id }) else { return false }
        let selectedID = currentExercise?.id
        let deferred = workout.exercises.remove(at: from)
        workout.exercises.append(deferred)
        var entries = pendingExecutionQueue
        let moved = entries.filter { $0.exerciseID == id }
        entries.removeAll { $0.exerciseID == id }
        entries.append(contentsOf: moved)
        workout.liveExecutionQueue = entries.isEmpty ? nil : entries
        currentExerciseIndex = workout.exercises.firstIndex(where: { $0.id == selectedID }) ?? 0
        activeWorkout = workout
        persistCheckpointNow()
        return true
    }

    @discardableResult
    func updatePendingStrengthSet(exerciseID: UUID, setID: UUID, reps: Int?,
                                  duration: Int?, weight: Double?, rest: Int, resistance: Int?) -> Bool {
        guard var workout = activeWorkout,
              let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let i = workout.exercises[e].sets.firstIndex(where: { $0.id == setID && !$0.isResolved }),
              !(currentSet?.id == setID && (currentSetEffortClock != nil || currentTimedSetCountdown != nil)),
              workout.exercises[e].groupStyle != .emom && workout.exercises[e].groupStyle != .amrap
        else { return false }
        var set = workout.exercises[e].sets[i]
        if set.resolvedTargetKind == .reps, let reps { set.plannedReps = min(max(reps, 1), 1000) }
        if set.resolvedTargetKind == .time, let duration { set.plannedDurationSeconds = min(max(duration, 1), 7200) }
        if set.resolvedLoadKind == .weightKilograms, let weight, weight.isFinite {
            set.plannedWeightKilograms = min(max(weight, 0), 999.5)
        }
        if set.resolvedLoadKind == .resistanceLevel, let resistance {
            set.plannedResistanceLevel = min(max(resistance, 1), 10)
        }
        set.restSeconds = min(max(rest, 0), 600)
        workout.exercises[e].sets[i] = set
        activeWorkout = workout
        if currentSet?.id == setID { reloadDraftFromCurrentSet() }
        persistCheckpointNow()
        return true
    }

    func setLiveGroupRest(exerciseID: UUID, station: Int, round: Int) {
        guard var workout = activeWorkout,
              let exercise = workout.exercises.first(where: { $0.id == exerciseID }),
              let groupID = exercise.groupID,
              exercise.groupStyle == .circuit || exercise.groupStyle == .superset else { return }
        for index in workout.exercises.indices where workout.exercises[index].groupID == groupID {
            workout.exercises[index].groupStationRestSeconds = min(max(station, 0), 600)
            workout.exercises[index].groupRoundRestSeconds = min(max(round, 0), 600)
        }
        activeWorkout = workout
        persistCheckpointNow()
    }

    func removeQueuedStrength(_ id: UUID) {
        guard var workout = activeWorkout else { return }
        workout.liveExecutionQueue = pendingExecutionQueue.filter { $0.id != id }
        activeWorkout = workout
        persistCheckpointNow()
    }

    func clearStrengthQueue() {
        guard var workout = activeWorkout else { return }
        workout.liveExecutionQueue = nil
        activeWorkout = workout
        persistCheckpointNow()
    }

    func moveQueuedStrengthToFront(_ id: UUID) {
        guard var workout = activeWorkout else { return }
        var entries = pendingExecutionQueue
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        workout.liveExecutionQueue = entries
        activeWorkout = workout
        persistCheckpointNow()
    }

    /// Run explicit queued work at a set boundary, never interrupt a timed
    /// group, change the plan order, or mark any pending set as completed.
    private func advanceLiveExecutionQueue(
        workout: inout StrengthWorkoutLog,
        automaticRestTimer: Bool, restSeconds: Int, at date: Date
    ) -> Bool {
        let entries = (workout.liveExecutionQueue ?? []).filter {
            Self.queueTarget($0, in: workout) != nil
        }
        workout.liveExecutionQueue = entries.isEmpty ? nil : entries
        if let groupID = workout.exercises[currentExerciseIndex].groupID,
           workout.exercises.contains(where: {
               $0.groupID == groupID && $0.sets.contains(where: { !$0.isResolved })
           }) { return false }
        guard let entry = entries.first,
              let target = Self.queueTarget(entry, in: workout) else { return false }
        Self.beginStrengthGroup(&workout, selected: target.exercise, at: date)
        currentExerciseIndex = target.exercise
        currentSetIndex = target.set
        isFreeTrainingBetweenExercises = false
        watchCaptureNeedsBaseline.insert(workout.exercises[target.exercise].sets[target.set].id)
        restStartedAt = automaticRestTimer && restSeconds > 0 ? date : nil
        restEndsAt = restStartedAt?.addingTimeInterval(TimeInterval(restSeconds))
        return true
    }

    func reorderActiveExercises(
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        guard var workout = activeWorkout,
              workout.exercises.indices.contains(currentExerciseIndex),
              !fromOffsets.isEmpty,
              fromOffsets.allSatisfy({
                  workout.exercises.indices.contains($0)
              })
        else {
            return
        }

        let activeID = workout.exercises[currentExerciseIndex].id
        let moving = fromOffsets.sorted().map { workout.exercises[$0] }
        for index in fromOffsets.sorted(by: >) {
            workout.exercises.remove(at: index)
        }

        let removedBeforeDestination =
            fromOffsets.filter { $0 < toOffset }.count
        let insertion = min(
            max(toOffset - removedBeforeDestination, 0),
            workout.exercises.count
        )
        workout.exercises.insert(contentsOf: moving, at: insertion)

        // The selected exercise follows its stable ID, not its old index.
        currentExerciseIndex = workout.exercises.firstIndex {
            $0.id == activeID
        } ?? 0
        activeWorkout = workout
        persistCheckpointNow()
    }

    /// Reorder by stable IDs from drag-and-drop without requiring Edit mode.
    /// Saving a new order does not change the saved plan, completed set IDs,
    /// active set, or the underlying Watch recording.
    @discardableResult
    func moveActiveExercise(_ draggedID: UUID, before targetID: UUID) -> Bool {
        guard var workout = activeWorkout,
              draggedID != targetID,
              let from = workout.exercises.firstIndex(where: { $0.id == draggedID }),
              workout.exercises.contains(where: { $0.id == targetID })
        else { return false }

        let currentID = currentExercise?.id
        let moved = workout.exercises.remove(at: from)
        guard let destination = workout.exercises.firstIndex(where: {
            $0.id == targetID
        }) else { return false }
        workout.exercises.insert(moved, at: destination)
        currentExerciseIndex = workout.exercises.firstIndex(where: {
            $0.id == currentID
        }) ?? 0
        activeWorkout = workout
        persistCheckpointNow()
        return true
    }

    /// Completed sets are history evidence: never delete them from an
    /// in-progress workout. Active running timed sets must be ended first.
    func canRemoveActiveExercise(_ id: UUID) -> Bool {
        guard let workout = activeWorkout,
              let item = workout.exercises.first(where: { $0.id == id }),
              item.sets.allSatisfy({ !$0.isCompleted })
        else { return false }
        return !(currentExercise?.id == id &&
                 currentTimedSetCountdown?.isRunning == true)
    }

    @discardableResult
    func removeActiveExercise(_ id: UUID) -> Bool {
        guard canRemoveActiveExercise(id),
              var workout = activeWorkout,
              let index = workout.exercises.firstIndex(where: { $0.id == id })
        else { return false }

        let previouslySelectedID = currentExercise?.id
        let previouslySelectedSetID = currentSet?.id
        let removed = workout.exercises.remove(at: index)
        for set in removed.sets {
            cardioWatchCaptures.removeValue(forKey: set.id)
            watchCaptureNeedsBaseline.remove(set.id)
        }

        // Preserve the selected exercise when another row disappears.
        // If it was removed, choose an unfinished exercise first.
        let preferred = workout.exercises.firstIndex(where: {
            $0.id == previouslySelectedID
        })
        let next = workout.exercises.firstIndex(where: { !$0.isCompleted })
        currentExerciseIndex = preferred ?? next ??
            max(min(index, workout.exercises.count - 1), 0)
        currentSetIndex = workout.exercises.indices.contains(currentExerciseIndex)
            ? (workout.exercises[currentExerciseIndex].sets.firstIndex(where: {
                $0.id == previouslySelectedSetID
            }) ?? workout.exercises[currentExerciseIndex].sets.firstIndex(where: {
                !$0.isCompleted
            }) ?? 0) : 0

        if previouslySelectedID == id {
            timedSetCountdown = nil
            restStartedAt = nil
            restEndsAt = nil
        }
        activeWorkout = workout
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
        return true
    }

    /// Correct the recorded unit interpretation for an unstarted iPhone
    /// exercise. The workout snapshot is independent of the catalog entry:
    /// never rewrite existing completed sets, other exercises or history.
    /// Watch-owned sessions remain read-only to avoid racing Watch input.
    @discardableResult
    func setActiveExerciseCoachLoadBasis(
        _ exerciseID: UUID,
        basis: ATHLTHStrengthLoadBasis?
    ) -> Bool {
        guard var workout = activeWorkout,
              workout.captureDevice == .iPhone,
              let index = workout.exercises.firstIndex(where: {
                  $0.id == exerciseID
              }),
              workout.exercises[index].sets.contains(where: {
                  $0.resolvedLoadKind == .weightKilograms
              }),
              workout.exercises[index].sets.allSatisfy({
                  !$0.isCompleted && $0.skippedAt == nil
              })
        else { return false }

        guard workout.exercises[index].exercise.coachLoadBasis != basis else {
            return true
        }
        workout.exercises[index].exercise.coachLoadBasis = basis
        activeWorkout = workout
        persistCheckpointNow()
        return true
    }

    /// Bar weight is metadata for the exercise's bar, not an additional load
    /// to add on top of the already-total kg recorded for each set.
    @discardableResult
    func setActiveExerciseBarWeight(_ id: UUID, kilograms: Double?) -> Bool {
        guard var workout = activeWorkout,
              let index = workout.exercises.firstIndex(where: { $0.id == id }),
              kilograms == nil ||
                (kilograms!.isFinite && (0...40).contains(kilograms!))
        else { return false }
        let exercise = workout.exercises[index]
        let oldBar = exercise.barWeightKilograms ??
            suggestedBarWeight(for: exercise)
        let newBar = kilograms ??
            StrengthBarWeightPreferences.mass(
                for: exercise.exercise.name, userID: accountID
            )
        let isEditingCurrentSet = currentExercise?.id == id &&
            currentSet?.isCompleted == false &&
            currentSetRecordsWeight
        workout.exercises[index].barWeightKilograms = kilograms
        activeWorkout = workout
        if isEditingCurrentSet {
            // Preserve the athlete's entered plates when swapping a 20 kg
            // bar for another size. Set records and prescribed targets stay
            // stored as total kilograms and are not recalculated.
            setDraft(weightKilograms: StrengthBarbellLoad.totalPreservingPlates(
                totalKilograms: draftWeightKilograms,
                previousBarKilograms: oldBar,
                newBarKilograms: newBar
            ))
        }
        persistCheckpointNow()
        return true
    }

    func suggestedBarWeight(for exercise: StrengthExerciseLog) -> Double {
        StrengthBarWeightPreferences.mass(
            for: exercise.exercise.name, userID: accountID
        )
    }

    @discardableResult
    func rememberBarWeightForExercise(_ id: UUID, kilograms: Double) -> Bool {
        guard let accountID,
              let exercise = activeWorkout?.exercises.first(where: {
                  $0.id == id
              }),
              StrengthBarbellExercisePolicy.usesBar(exercise),
              kilograms.isFinite, (0...40).contains(kilograms)
        else { return false }
        // Update the active draft before changing the stored preference,
        // otherwise a legacy nil bar can resolve its OLD mass as the new
        // preference and accidentally alter the plate-only input.
        guard setActiveExerciseBarWeight(id, kilograms: kilograms) else {
            return false
        }
        StrengthBarWeightPreferences.setExerciseMass(
            kilograms,
            for: exercise.exercise.name,
            userID: accountID
        )
        return true
    }

    private func applyBarDefaults(_ logs: inout [StrengthExerciseLog]) {
        for index in logs.indices where
            StrengthBarbellExercisePolicy.usesBar(logs[index]) {
            logs[index].barWeightKilograms =
                StrengthBarWeightPreferences.mass(
                    for: logs[index].exercise.name,
                    userID: accountID
                )
        }
    }

    /// Current-set-only timer; never changes the workout or advances sets by itself.
    var currentTimedSetCountdown: StrengthTimedSetCountdown? {
        guard let timedSetCountdown,
              let workout = activeWorkout,
              let exercise = currentExercise,
              let set = currentSet,
              set.resolvedTargetKind == .time,
              !set.isResolved,
              timedSetCountdown.workoutID == workout.id,
              timedSetCountdown.exerciseID == exercise.id,
              timedSetCountdown.setID == set.id
        else { return nil }
        return timedSetCountdown
    }

    private func discardStaleTimedSetCountdown() {
        if timedSetCountdown != nil && currentTimedSetCountdown == nil {
            timedSetCountdown = nil
        }
    }

    /// Start at zero only when the athlete begins the selected set.
    /// This clock is separate from the countdown that timed sets use.
    var currentSetEffortClock: StrengthSetEffortClock? {
        guard let workout = activeWorkout,
              let exercise = currentExercise,
              let set = currentSet, !set.isResolved,
              let clock = setEffortClock,
              clock.workoutID == workout.id,
              clock.exerciseID == exercise.id,
              clock.setID == set.id,
              !isResting else { return nil }
        return clock
    }

    func startCurrentSetEffort(at date: Date = Date()) {
        guard canCompleteCurrentStrengthMode(at: date) else { return }
        guard !isResting, let workout = activeWorkout,
              let exercise = currentExercise, let set = currentSet,
              !set.isResolved else { return }
        if var resumed = currentSetEffortClock {
            resumed.resume(at: date)
            setEffortClock = resumed
            return
        }
        setEffortClock = StrengthSetEffortClock(
            workoutID: workout.id, exerciseID: exercise.id,
            setID: set.id, startedAt: date
        )
    }

    /// Sum of measured working time in this exercise, without any rest.
    var currentExerciseMeasuredSeconds: TimeInterval {
        let recorded = currentExercise?.sets
            .compactMap(\.actualSetElapsedSeconds)
            .filter { $0.isFinite && $0 >= 0 }
            .reduce(0, +) ?? 0
        return recorded + (currentSetEffortClock?.elapsedSeconds() ?? 0)
    }

    private func discardStaleSetEffortClock() {
        guard let clock = setEffortClock else { return }
        let matching = activeWorkout?.id == clock.workoutID &&
            currentExercise?.id == clock.exerciseID &&
            currentSet?.id == clock.setID &&
            currentSet?.isResolved == false
        if !matching { setEffortClock = nil }
    }

    func startOrResumeTimedSet(at date: Date = Date()) {
        guard canCompleteCurrentStrengthMode(at: date) else { return }
        guard !isResting,
              let workout = activeWorkout,
              let exercise = currentExercise,
              let set = currentSet,
              set.resolvedTargetKind == .time,
              !set.isResolved
        else { return }

        let now = date
        startCurrentSetEffort(at: now)
        // An untargeted timed hold uses only the durable count-up effort
        // clock. Do not fabricate a duration or launch a countdown.
        if set.plannedDurationSeconds == nil &&
           (exercise.exercise.isTimeOnlyBodyweightStrength ||
            set.hybridTargetDistanceMeters != nil) {
            timedSetCountdown = nil
            persistCheckpointNow()
            return
        }
        if var countdown = currentTimedSetCountdown {
            guard !countdown.isRunning else { return }
            countdown.resumedAt = now
            timedSetCountdown = countdown
        } else {
            let seconds = min(max(draftDurationSeconds, 15), 7_200)
            timedSetCountdown = StrengthTimedSetCountdown(
                workoutID: workout.id,
                exerciseID: exercise.id,
                setID: set.id,
                targetSeconds: seconds,
                secondsAtPause: TimeInterval(seconds),
                resumedAt: now
            )
        }
        persistCheckpointNow()
    }

    /// Exactly one clock may advance a timed hybrid phase. Watch-owned
    /// workouts replay their own durable set commands; iPhone must not race
    /// the Watch after a mirror delay, screen lock or disconnection.
    var controlsEmbeddedHybridClockOnIPhone: Bool {
        guard let workout = activeWorkout else { return false }
        return workout.captureDevice != .appleWatch ||
            workout.advancedConfiguration?.inputMode == .iPhone
    }

    /// Date-anchored embedded running intervals. Only the phase advances:
    /// HealthKit recording and Apple Watch ownership stay with the parent
    /// strength workout, preventing a second workout or duplicate calories.
    func advanceEmbeddedIntervalIfNeeded(at date: Date = Date()) {
        guard controlsEmbeddedHybridClockOnIPhone else { return }
        var advanced = 0
        // Date anchoring catches up after screen lock, foreground suspension
        // or a temporary Bluetooth handoff. Never count a paused phase.
        while advanced < 80,
              currentExercise?.isEmbeddedRunningInterval == true,
              let timer = currentTimedSetCountdown,
              timer.isRunning,
              timer.remaining(at: date) <= 0,
              currentSet?.isCompleted == false {
            let originalSetID = timer.setID
            let overtime = max(
                date.timeIntervalSince(timer.resumedAt ?? date)
                    - timer.secondsAtPause,
                0
            )

            completeCurrentSet(
                reps: nil,
                durationSeconds: timer.targetSeconds,
                weightKilograms: nil,
                rpe: nil,
                rir: nil,
                restSeconds: 0
            )

            guard currentExercise?.isEmbeddedRunningInterval == true,
                  let next = currentSet,
                  next.id != originalSetID,
                  !next.isCompleted
            else { return }
            startOrResumeTimedSet()

            if overtime > 0, var continuation = currentTimedSetCountdown {
                continuation.resumedAt = date.addingTimeInterval(-overtime)
                timedSetCountdown = continuation
            }
            advanced += 1
        }
    }

    func pauseTimedSet(at date: Date = Date()) {
        guard var countdown = currentTimedSetCountdown,
              countdown.isRunning else { return }
        countdown.pause(at: date)
        timedSetCountdown = countdown
        if var effort = currentSetEffortClock {
            effort.pause(at: date)
            setEffortClock = effort
        }
        persistCheckpointNow()
    }

    func resetTimedSet() {
        guard currentTimedSetCountdown != nil else { return }
        timedSetCountdown = nil
        persistCheckpointNow()
    }

    func setDraft(
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        weightKilograms: Double? = nil,
        resistanceLevel: Int? = nil,
        restSeconds: Int? = nil,
        rpe: Double? = nil,
        rir: Double? = nil,
        warmUp: Bool? = nil,
        treadmillSpeedKilometersPerHour: Double? = nil,
        treadmillInclinePercent: Double? = nil,
        origin:
            StrengthDraftMutationOrigin =
                .iPhone
    ) {
        if let reps {
            draftReps = max(reps, 0)
        }

        if let durationSeconds {
            let updatedDuration = min(max(durationSeconds, 15), 7_200)
            if updatedDuration != draftDurationSeconds {
                // A changed target always starts a fresh countdown.
                timedSetCountdown = nil
            }
            draftDurationSeconds = updatedDuration
        }

        if let weightKilograms {
            draftWeightKilograms = max(weightKilograms, 0)
        }
        if let treadmillSpeedKilometersPerHour {
            draftTreadmillSpeedKilometersPerHour =
                min(max(treadmillSpeedKilometersPerHour, 0), 30)
        }
        if let treadmillInclinePercent {
            draftTreadmillInclinePercent =
                min(max(treadmillInclinePercent, 0), 20)
        }

        if let resistanceLevel {
            draftResistanceLevel =
                min(
                    max(resistanceLevel, 1),
                    10
                )
        }

        if let restSeconds {
            draftRestSeconds = min(
                max(restSeconds, 0),
                600
            )
        }

        if let rpe {
            draftRPE = min(
                max(rpe, 1),
                10
            )
        }

        if let rir {
            draftRIR = min(
                max(rir, 0),
                10
            )
        }

        if let warmUp {
            draftWarmUp = warmUp
        }

        if origin == .iPhone {
            lastPhoneDraftMutationAt =
                Date()
        }
    }

    func reloadDraftFromCurrentSet() {
        discardStaleTimedSetCountdown()
        guard let set = currentSet else {
            draftReps = 8
            draftDurationSeconds = 60
            draftWeightKilograms = 20
            draftTreadmillSpeedKilometersPerHour = 0
            draftTreadmillInclinePercent = 0
            draftResistanceLevel = 5
            draftRestSeconds = 90
            draftRPE = 8
            draftRIR = 2
            draftWarmUp = false
            return
        }

        draftReps =
            set.completedReps ??
            set.plannedReps ??
            8
        draftDurationSeconds =
            set.completedDurationSeconds ??
            set.plannedDurationSeconds ??
            60
        draftWeightKilograms =
            set.completedWeightKilograms ??
            set.plannedWeightKilograms ??
            max(draftWeightKilograms, 20)
        // Keep treadmill values within the same exercise, but never inherit
        // them from an unrelated strength exercise or a different treadmill
        // entry. Completed set history provides the last confirmed manual
        // setting when the athlete returns to the exercise.
        if let exercise = currentExercise,
           StrengthTreadmillWarmUpDefaults.isTreadmill(exercise.exercise.name) {
            let priorSets = exercise.sets.prefix(currentSetIndex).reversed()
            draftTreadmillSpeedKilometersPerHour =
                set.completedTreadmillSpeedKilometersPerHour ??
                priorSets.compactMap(\.completedTreadmillSpeedKilometersPerHour).first ?? 0
            draftTreadmillInclinePercent =
                set.completedTreadmillInclinePercent ??
                priorSets.compactMap(\.completedTreadmillInclinePercent).first ?? 0
        } else {
            draftTreadmillSpeedKilometersPerHour = 0
            draftTreadmillInclinePercent = 0
        }
        draftResistanceLevel =
            min(
                max(
                    set.completedResistanceLevel ??
                        set.plannedResistanceLevel ??
                        draftResistanceLevel,
                    1
                ),
                10
            )
        draftRestSeconds =
            max(set.restSeconds ?? 90, 0)
        draftRPE =
            set.rpe ??
            set.plannedRPE ??
            8
        draftRIR =
            set.rir ??
            set.plannedRIR ??
            2
        draftWarmUp = set.isWarmUp ?? false
    }

    var watchSnapshot: WatchStrengthSessionSnapshot? {
        guard let workout = activeWorkout else {
            return nil
        }

        let exercise = currentExercise
        let set = currentSet
        let totalSets =
            workout.exercises.reduce(0) {
                // Skipped grouped slots still exist in .sets. Do not add
                // their mirrored legacy skip counter a second time.
                let retainedSkips = $1.sets.filter { $0.skippedAt != nil }.count
                let removedSkips = max(
                    ($1.skippedPlannedSetCount ?? 0) - retainedSkips, 0
                )
                return $0 + $1.sets.count + removedSkips
            }
        let allExercisesComplete =
            !workout.exercises.isEmpty &&
            workout.exercises.allSatisfy(\.isCompleted)

        var snapshot = WatchStrengthSessionSnapshot(
            workoutID: workout.id,
            title: workout.title,
            exerciseIndex: currentExerciseIndex,
            exerciseCount: workout.exercises.count,
            exerciseName: exercise?.exercise.name,
            primaryMuscles:
                exercise?.exercise.primaryMuscles ?? [],
            setIndex: currentSetIndex,
            setCount: exercise?.sets.count ?? 0,
            setNumber: set?.setNumber,
            completedSets: workout.totalCompletedSets,
            totalSets: totalSets,
            skippedSets: workout.exercises.reduce(0) {
                $0 + $1.auditedSkippedSets
            },
            draftReps: draftReps,
            draftWeightKilograms: currentSetRecordsWeight ? draftWeightKilograms : 0,
            draftRestSeconds: draftRestSeconds,
            draftDurationSeconds: draftDurationSeconds,
            draftResistanceLevel: draftResistanceLevel,
            manualTreadmillSpeedKilometersPerHour:
                exercise.map {
                    StrengthTreadmillWarmUpDefaults.isTreadmill($0.exercise.name)
                } == true && draftTreadmillSpeedKilometersPerHour > 0
                    ? draftTreadmillSpeedKilometersPerHour : nil,
            manualTreadmillInclinePercent:
                exercise.map {
                    StrengthTreadmillWarmUpDefaults.isTreadmill($0.exercise.name)
                } == true ? draftTreadmillInclinePercent : nil,
            targetKindRaw:
                set?.resolvedTargetKind.rawValue,
            loadKindRaw:
                set?.resolvedLoadKind.rawValue,
            isEmbeddedRunningInterval:
                exercise?.isEmbeddedRunningInterval,
            embeddedRunningPhaseTitle:
                set?.hybridPhaseTitle,
            embeddedRunningPhaseKind:
                set?.hybridPhaseKind,
            embeddedRunningTargetHeartRateZone:
                set?.hybridTargetHeartRateZone,
            embeddedRunningTargetPaceSecondsPerKilometer:
                set?.hybridTargetPaceSecondsPerKilometer,
            embeddedRunningTargetDistanceMeters:
                set?.hybridTargetDistanceMeters,
            isResting: isResting,
            restEndsAt: restEndsAt,
            currentExerciseComplete:
                currentExerciseAllSetsCompleted,
            hasNextExercise: hasNextExercise,
            allExercisesComplete: allExercisesComplete,
            updatedAt: Date(),
            inputMode:
                workout
                    .advancedConfiguration?
                    .inputMode,
            draftRPE: draftRPE,
            draftRIR: draftRIR,
            isWarmUp: draftWarmUp,
            effortMetricRaw:
                workout
                    .advancedConfiguration?
                    .effortMetric?
                    .rawValue,
            exerciseQueue:
                workout.exercises
                    .enumerated()
                    .map {
                        index,
                        item in

                        WatchStrengthExerciseSummary(
                            index: index,
                            name:
                                item.exercise
                                    .name,
                            primaryMuscles:
                                item.exercise
                                    .primaryMuscles,
                            setCount:
                                item.sets.count,
                            instructions:
                                item.exercise
                                    .instructions,
                            secondaryMuscles:
                                item.exercise
                                    .secondaryMuscles,
                            equipment:
                                item.exercise
                                    .equipment,
                            libraryExerciseID:
                                item.exercise
                                    .libraryExerciseID,
                            coachLoadBasisRaw:
                                item.exercise
                                    .coachLoadBasis?
                                    .rawValue,
                            setPlans:
                                item.sets.map {
                                    set in

                                    WatchStrengthSetPlan(
                                        setNumber:
                                            set.setNumber,
                                        reps:
                                            set.plannedReps,
                                        durationSeconds:
                                            set.plannedDurationSeconds,
                                        openEndedTime:
                                            set.resolvedTargetKind == .time &&
                                            set.plannedDurationSeconds == nil &&
                                            item.exercise.isTimeOnlyBodyweightStrength,
                                        weightKilograms:
                                            set.plannedWeightKilograms,
                                        resistanceLevel:
                                            set.plannedResistanceLevel,
                                        restSeconds:
                                            set.restSeconds,
                                        isWarmUp:
                                            set.isWarmUp,
                                        hybridPhaseTitle:
                                            set.hybridPhaseTitle,
                                        hybridPhaseKind:
                                            set.hybridPhaseKind,
                                        hybridTargetHeartRateZone:
                                            set.hybridTargetHeartRateZone,
                                        hybridTargetPaceSecondsPerKilometer:
                                            set.hybridTargetPaceSecondsPerKilometer,
                                        hybridTargetDistanceMeters:
                                            set.hybridTargetDistanceMeters
                                    )
                                },
                            isCompleted:
                                item.isCompleted,
                            firstPendingSetIndex:
                                item.sets
                                    .firstIndex(
                                        where: {
                                            !$0.isResolved
                                        }
                                    ),
                            skippedSets: item.skippedPlannedSetCount,
                            isEmbeddedRunningInterval:
                                item.isEmbeddedRunningInterval,
                            strengthGroupID: item.groupID,
                            strengthGroupStyleRaw: item.groupStyle?.rawValue,
                            strengthGroupClockSeconds: item.groupClockSeconds,
                            strengthGroupStartedAt: item.groupStartedAt
                        )
                    },
            startedAt:
                workout.startedAt,
            plannedSessionID:
                workout.plannedSessionID,
            allowsLiveExerciseBuilding:
                workout
                    .allowsLiveExerciseBuilding,
            timedSetCountdown: currentTimedSetCountdown.map {
                WatchTimedStrengthCountdown(
                    targetSeconds: $0.targetSeconds,
                    secondsAtPause: $0.secondsAtPause,
                    resumedAt: $0.resumedAt
                )
            },
            setEffortStartedAt: currentSetEffortClock?.startedAt,
            isOpenEndedTimedSet: set?.resolvedTargetKind == .time &&
                set?.plannedDurationSeconds == nil &&
                (exercise?.exercise.isTimeOnlyBodyweightStrength == true ||
                 set?.hybridTargetDistanceMeters != nil)
        )
        if let exercise, let id = exercise.groupID {
            let siblings = workout.exercises.filter { $0.groupID == id }
            snapshot.strengthModeRaw = exercise.groupStyle?.rawValue
            snapshot.strengthModeClockSeconds = exercise.groupClockSeconds
            snapshot.strengthModeStartedAt = exercise.groupStartedAt
            snapshot.strengthModeRound = currentSetIndex + 1
            snapshot.strengthModeTotalRounds = exercise.sets.count
            snapshot.strengthModeStationIndex =
                siblings.firstIndex(where: { $0.id == exercise.id }).map { $0 + 1 }
            snapshot.strengthModeStationCount = siblings.count
        }
        // The Watch may show/adjust plates only when the iPhone knows this
        // exercise uses a bar. Nil intentionally preserves legacy total entry
        // for older/offline Watch-created sessions.
        snapshot.barWeightKilograms = exercise.flatMap { item in
            guard currentSetRecordsWeight,
                  set?.resolvedLoadKind == .weightKilograms,
                  StrengthBarbellExercisePolicy.usesBar(item)
            else { return nil }
            return item.barWeightKilograms ?? suggestedBarWeight(for: item)
        }
        return snapshot
    }

    @discardableResult
    func startFromWatchSnapshot(
        _ snapshot:
            WatchStrengthSessionSnapshot,
        watchSessionID: UUID? = nil
    ) -> Bool {
        // A WatchConnectivity request may arrive well after iPhone has
        // created a different workout or committed this exact Watch workout.
        // Neither case grants permission to overwrite the authoritative log.
        guard accountID != nil,
              activeWorkout == nil,
              !workoutHistory.contains(where: { $0.id == snapshot.workoutID }),
              ATHLTHWorkoutRecordingArbiter.mayBootstrapWatchStrength(
                  snapshot: snapshot
              )
        else { return false }
        var configuration =
            StrengthAdvancedConfiguration
                .savedDefaults()
        configuration.inputMode =
            snapshot.inputMode ??
            .appleWatch

        let exerciseLogs =
            (snapshot.exerciseQueue ?? [])
                .sorted {
                    $0.index < $1.index
                }
                .map {
                    item in

                    let plans =
                        item.setPlans ??
                        (1...max(item.setCount, 1))
                            .map {
                                WatchStrengthSetPlan(
                                    setNumber: $0,
                                    reps:
                                        snapshot.draftReps,
                                    weightKilograms:
                                        snapshot
                                            .draftWeightKilograms,
                                    restSeconds:
                                        snapshot
                                            .draftRestSeconds
                                )
                            }

                    let exerciseSnapshot =
                        ExerciseSnapshot(
                            libraryExerciseID: item.libraryExerciseID,
                            coachLoadBasis: item.coachLoadBasisRaw.flatMap(
                                ATHLTHStrengthLoadBasis.init(rawValue:)
                            ),
                            name: item.name,
                            instructions:
                                item.instructions ?? [],
                            primaryMuscles:
                                item.primaryMuscles,
                            secondaryMuscles:
                                item.secondaryMuscles ??
                                [],
                            equipment:
                                item.equipment ?? [],
                            imageURL: nil,
                            videoURL: nil
                        )

                    return StrengthExerciseLog(
                        id: UUID(),
                        plannedExerciseID: nil,
                        exercise:
                            exerciseSnapshot,
                        sets:
                            plans.map {
                                plan in

                                let targetKind:
                                    StrengthExerciseTargetKind =
                                    plan.durationSeconds != nil
                                        ? .time
                                        : .reps
                                let loadKind:
                                    StrengthExerciseLoadKind =
                                    plan.resistanceLevel != nil
                                        ? .resistanceLevel
                                        : .weightKilograms

                                return StrengthSetLog(
                                    id: UUID(),
                                    setNumber:
                                        plan.setNumber,
                                    plannedReps:
                                        targetKind == .reps
                                            ? plan.reps
                                            : nil,
                                    plannedWeightKilograms:
                                        loadKind ==
                                            .weightKilograms
                                            ? plan
                                                .weightKilograms
                                            : nil,
                                    completedReps: nil,
                                    completedWeightKilograms:
                                        nil,
                                    rpe: nil,
                                    completedAt: nil,
                                    restSeconds:
                                        plan.restSeconds,
                                    isWarmUp:
                                        plan.isWarmUp,
                                    targetKind:
                                        targetKind,
                                    plannedDurationSeconds:
                                        targetKind == .time
                                            ? plan
                                                .durationSeconds
                                            : nil,
                                    loadKind:
                                        loadKind,
                                    plannedResistanceLevel:
                                        loadKind ==
                                            .resistanceLevel
                                            ? plan
                                                .resistanceLevel
                                            : nil
                                )
                            },
                        completedAt: nil,
                        groupID: item.strengthGroupID,
                        groupStyle: item.strengthGroupStyleRaw.flatMap {
                            StrengthExerciseGroupStyle(rawValue: $0)
                        },
                        groupClockSeconds: item.strengthGroupClockSeconds,
                        groupStartedAt: item.strengthGroupStartedAt,
                        skippedPlannedSetCount: item.skippedSets
                    )
                }

        recoveredCheckpointSavedAt = nil
        activeWorkout =
            StrengthWorkoutLog(
                id: snapshot.workoutID,
                plannedSessionID:
                    snapshot.plannedSessionID,
                watchSessionID:
                    watchSessionID,
                captureDevice:
                    .appleWatch,
                trackingMode:
                    .advanced,
                title:
                    snapshot.title,
                startedAt:
                    snapshot.startedAt ??
                    Date(),
                endedAt: nil,
                exercises:
                    exerciseLogs,
                healthMetrics:
                    LinkedHealthWorkoutMetrics(
                        healthKitWorkoutUUID:
                            nil,
                        duration: nil,
                        activeCalories: nil,
                        averageHeartRate: nil,
                        maxHeartRate: nil
                    ),
                advancedConfiguration:
                    configuration,
                allowsLiveExerciseBuilding:
                    snapshot
                        .allowsLiveExerciseBuilding ??
                    exerciseLogs.isEmpty
            )

        currentExerciseIndex = 0
        currentSetIndex = 0
        restEndsAt = nil
        restStartedAt = nil
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
        return true
    }

    func replayOfflineWatchCommands(
        _ commands:
            [WatchStrengthCommand]
    ) {
        var seenCommandIDs = Set<UUID>()
        for command in commands.sorted(by: {
            $0.sentAt == $1.sentAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.sentAt < $1.sentAt
        }) {
            guard seenCommandIDs.insert(command.id).inserted else {
                // The same ID may arrive via immediate and durable transport.
                continue
            }
            guard let workout = activeWorkout else { return }
            guard ATHLTHStrengthWatchCommandIdentityPolicy.belongsToActiveWorkout(
                command, workoutID: workout.id
            ) else { continue }
            guard offlineWatchReplayDeduplication.admit(
                commandID: command.id, workoutID: workout.id
            ) else { continue }

            switch command.kind {
            case .requestSnapshot:
                continue

            case .startSetEffort:
                guard (command.exerciseIndex == nil ||
                       command.exerciseIndex == currentExerciseIndex),
                      (command.setIndex == nil ||
                       command.setIndex == currentSetIndex),
                      currentSet?.isResolved == false
                else { continue }
                startCurrentSetEffort(at: command.sentAt)

            case .skipSet:
                guard (command.exerciseIndex == nil ||
                       command.exerciseIndex == currentExerciseIndex),
                      (command.setIndex == nil ||
                       command.setIndex == currentSetIndex),
                      currentSet?.isResolved == false
                else { continue }
                _ = skipCurrentSet()

            case .startTimedSet:
                // An offline Watch request targets only its original
                // exercise/set; never restart the timer on a later set.
                guard command.exerciseIndex == nil ||
                        command.exerciseIndex == currentExerciseIndex,
                      command.setIndex == nil ||
                        command.setIndex == currentSetIndex,
                      currentSet?.resolvedTargetKind == .time,
                      currentSet?.isResolved == false
                else { continue }

                startOrResumeTimedSet(at: command.sentAt)

            case .pauseTimedSet:
                guard command.exerciseIndex == nil ||
                        command.exerciseIndex == currentExerciseIndex,
                      command.setIndex == nil ||
                        command.setIndex == currentSetIndex,
                      currentSet?.resolvedTargetKind == .time,
                      currentSet?.isResolved == false
                else { continue }

                pauseTimedSet(at: command.sentAt)

            case .resetTimedSet:
                guard command.exerciseIndex == nil ||
                        command.exerciseIndex == currentExerciseIndex,
                      command.setIndex == nil ||
                        command.setIndex == currentSetIndex,
                      currentSet?.resolvedTargetKind == .time,
                      currentSet?.isResolved == false
                else { continue }

                resetTimedSet()

            case .updateDraft:
                guard currentSet?.isResolved == false,
                    command.exerciseIndex == nil ||
                    command.exerciseIndex ==
                        currentExerciseIndex,
                    command.setIndex == nil ||
                    command.setIndex ==
                        currentSetIndex
                else {
                    continue
                }

                setDraft(
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
                        command.restSeconds,
                    rpe: command.rpe,
                    rir: command.rir,
                    warmUp:
                        command.isWarmUp,
                    origin: .watch
                )

            case .completeSet:
                guard
                    command.exerciseIndex == nil ||
                    command.exerciseIndex ==
                        currentExerciseIndex,
                    command.setIndex == nil ||
                    command.setIndex ==
                        currentSetIndex
                else {
                    continue
                }

                if currentSet?.isResolved ==
                    true {
                    continue
                }

                setDraft(
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
                        command.restSeconds,
                    rpe: command.rpe,
                    rir: command.rir,
                    warmUp:
                        command.isWarmUp,
                    origin: .watch
                )
                completeCurrentSet(
                    reps:
                        currentSet?
                            .resolvedTargetKind ==
                            .reps
                            ? draftReps
                            : nil,
                    durationSeconds:
                        currentSet?
                            .resolvedTargetKind ==
                            .time
                            ? draftDurationSeconds
                            : nil,
                    weightKilograms:
                        currentSet?
                            .resolvedLoadKind ==
                            .weightKilograms
                            ? draftWeightKilograms
                            : nil,
                    resistanceLevel:
                        currentSet?
                            .resolvedLoadKind ==
                            .resistanceLevel
                            ? draftResistanceLevel
                            : nil,
                    distanceMeters:
                        command
                            .distanceMeters,
                    rpe: draftRPE,
                    rir: draftRIR,
                    isWarmUp:
                        draftWarmUp,
                    restSeconds:
                        draftRestSeconds,
                    completedAt: command.sentAt
                )

            case .completeSetWithoutDetails:
                guard
                    command.exerciseIndex == nil ||
                    command.exerciseIndex ==
                        currentExerciseIndex,
                    command.setIndex == nil ||
                    command.setIndex ==
                        currentSetIndex
                else {
                    continue
                }

                if currentSet?.isResolved !=
                    true {
                    if let rest =
                            command.restSeconds {
                        setDraft(
                            restSeconds: rest,
                            origin: .watch
                        )
                    }
                    completeCurrentSetWithoutDetails(
                        restSeconds: draftRestSeconds,
                        completedAt: command.sentAt
                    )
                }

            case .skipRest:
                guard ATHLTHStrengthWatchRestActionPolicy.accepts(
                    command,
                    exerciseIndex: currentExerciseIndex,
                    setIndex: currentSetIndex,
                    restStartedAt: restStartedAt
                ) else { continue }
                _ = skipRest(at: command.sentAt)

            case .skipRestAndStartTimedSet:
                // Offline Watch commands are replayed against the correct
                // original set only. One command must both release the rest
                // gate and start its clock; never skip or restart a later set.
                guard command.exerciseIndex == currentExerciseIndex,
                      command.setIndex == currentSetIndex,
                      isResting,
                      currentSet?.resolvedTargetKind == .time,
                      currentSet?.isResolved == false
                else { continue }
                guard ATHLTHStrengthWatchRestActionPolicy.accepts(
                    command,
                    exerciseIndex: currentExerciseIndex,
                    setIndex: currentSetIndex,
                    restStartedAt: restStartedAt
                ), skipRest(at: command.sentAt) else { continue }
                startOrResumeTimedSet(at: command.sentAt)

            case .addRest:
                guard ATHLTHStrengthWatchRestActionPolicy.accepts(
                    command,
                    exerciseIndex: currentExerciseIndex,
                    setIndex: currentSetIndex,
                    restStartedAt: restStartedAt
                ) else { continue }
                addRest(
                    seconds: command.addRestSeconds ?? 30,
                    at: command.sentAt
                )

            case .nextExercise:
                if let index =
                        command
                            .exerciseIndex,
                   index !=
                    currentExerciseIndex {
                    continue
                }

                if hasNextExercise {
                    moveToNextExercise(at: command.sentAt)
                }
            }
        }

        persistCheckpointNow()
    }

    func setWorkoutTrainingPlace(_ place: ATHLTHTrainingPlace?) {
        guard var workout = activeWorkout else { return }
        workout.plannedTrainingPlace = place
        activeWorkout = workout
        persistCheckpointNow()
    }

    /// Live pulse-zone target is stored on this workout, not global settings.
    func setLiveHeartRateTargetZone(_ zone: Int?) {
        guard var workout = activeWorkout else { return }
        workout.liveHeartRateTargetZone = zone.flatMap {
            (1...5).contains($0) ? $0 : nil
        }
        activeWorkout = workout
        persistCheckpointNow()
    }

    /// Continue the same workout while no specific exercise is selected.
    /// Waiting time is tracked as rest and finalized on the next movement
    /// or when the workout is saved. Does not fabricate any completed sets.
    @discardableResult
    func continueFreeTrainingBetweenExercises() -> Bool {
        guard let workout = activeWorkout,
              !workout.exercises.isEmpty,
              workout.exercises.allSatisfy(\.isCompleted)
        else { return false }
        if restStartedAt == nil {
            restStartedAt = workout.exercises
                .compactMap(\.completedAt).max() ?? Date()
        }
        restEndsAt = nil
        isFreeTrainingBetweenExercises = true
        persistCheckpointNow()
        return true
    }

    func startFreestyle(
        watchSessionID: UUID?,
        trackingMode: StrengthTrackingMode = .advanced,
        captureDevice: WorkoutCaptureDevice = .iPhone,
        advancedConfiguration:
            StrengthAdvancedConfiguration? = nil
    ) {
        // Never overwrite an unfinished workout or its account checkpoint.
        guard activeWorkout == nil, !loadingAccount,
              ATHLTHWorkoutRecordingArbiter.mayStartStrength() else { return }
        recoveredCheckpointSavedAt = nil
        setEffortClock = nil
        cardioWatchCaptures = [:]
        watchCaptureNeedsBaseline = []
        activeWorkout = StrengthWorkoutLog(
            id: UUID(),
            plannedSessionID: nil,
            watchSessionID: watchSessionID,
            captureDevice: captureDevice,
            trackingMode: trackingMode,
            title: "Freestyle Strength",
            startedAt: Date(),
            endedAt: nil,
            exercises: [],
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: nil,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            ),
            advancedConfiguration:
                advancedConfiguration,
            allowsLiveExerciseBuilding:
                true
        )

        currentExerciseIndex = 0
        currentSetIndex = 0
        restEndsAt = nil
        restStartedAt = nil
        isFreeTrainingBetweenExercises = false
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
    }

    // Classify an exercise without altering completed sets or its planned prescription.
    @discardableResult
    func setWarmUpExercise(_ exerciseID: UUID, isWarmUp: Bool) -> Bool {
        guard var workout = activeWorkout,
              let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              !workout.exercises[exerciseIndex].sets.isEmpty,
              workout.exercises[exerciseIndex].sets.allSatisfy({ !$0.isCompleted })
        else {
            return false
        }

        for setIndex in workout.exercises[exerciseIndex].sets.indices {
            workout.exercises[exerciseIndex].sets[setIndex].isWarmUp = isWarmUp
            workout.exercises[exerciseIndex].sets[setIndex].plannedSetType =
                isWarmUp ? .warmUp : .work
        }

        activeWorkout = workout
        if currentExerciseIndex == exerciseIndex {
            reloadDraftFromCurrentSet()
        }
        persistCheckpointNow()
        return true
    }

    func appendExercise(
        _ exercise: Exercise,
        sets: Int = 3,
        reps: Int? = 8,
        targetKind: StrengthExerciseTargetKind? = nil,
        targetDurationSeconds: Int? = nil,
        loadKind: StrengthExerciseLoadKind? = nil,
        targetWeightKilograms: Double? = nil,
        targetResistanceLevel: Int? = nil,
        restSeconds: Int? = 90,
        warmUpSets: Int = 0,
        recordsWeight: Bool? = nil,
        openEndedTime: Bool = false
    ) {
        finalizeActualRestIfNeeded()
        guard var workout = activeWorkout else { return }
        isFreeTrainingBetweenExercises = false

        let snapshot = exercise.snapshot
        let isHold = StrengthTimedBodyweightDefaults.isBodyweightHold(
            snapshot.name
        ) || snapshot.isTimeOnlyBodyweightStrength
        let resolvedTargetKind =
            targetKind ?? (isHold ? .time : snapshot.defaultStrengthTargetKind)
        let resolvedLoadKind =
            loadKind ??
            exercise
                .snapshot
                .defaultStrengthLoadKind
        let setCount = snapshot.isFreeStrengthTimer ? 1 : max(sets, 1)
        var log = StrengthExerciseLog(
            id: UUID(),
            plannedExerciseID: nil,
            exercise: exercise.snapshot,
            sets: (1...setCount).map { number in
                StrengthSetLog(
                    id: UUID(),
                    setNumber: number,
                    plannedReps:
                        resolvedTargetKind == .reps
                            ? reps
                            : nil,
                    plannedWeightKilograms:
                        resolvedLoadKind == .weightKilograms
                            ? targetWeightKilograms
                            : nil,
                    completedReps: nil,
                    completedWeightKilograms: nil,
                    rpe: nil,
                    completedAt: nil,
                    restSeconds: snapshot.isFreeStrengthTimer ? 0 : restSeconds,
                    isWarmUp:
                        number <= max(
                            min(
                                warmUpSets,
                                setCount
                            ),
                            0
                        )
                            ? true
                            : nil,
                    targetKind: resolvedTargetKind,
                    plannedDurationSeconds:
                        resolvedTargetKind == .time && !openEndedTime
                            ? max(
                                targetDurationSeconds ??
                                    snapshot.defaultStrengthTargetDurationSeconds,
                                15
                            )
                            : nil,
                    loadKind: resolvedLoadKind,
                    plannedResistanceLevel:
                        resolvedLoadKind == .resistanceLevel
                            ? min(
                                max(
                                    targetResistanceLevel ?? 5,
                                    1
                                ),
                                10
                            )
                            : nil
                )
            },
            completedAt: nil
        )

        for index in log.sets.indices {
            log.sets[index].recordsWeight =
                snapshot.isTimeOnlyBodyweightStrength
                    ? false
                    : (recordsWeight ??
                        !(isHold || StrengthTreadmillWarmUpDefaults.isTreadmill(
                            snapshot.name
                        )))
        }
        let wasEmpty =
            workout.exercises.isEmpty
        let previousExercisesComplete =
            !wasEmpty &&
            workout.exercises
                .allSatisfy {
                    $0.isCompleted
                }

        // Barbell/Smith exercises start with a conventional 20 kg bar,
        // but the athlete can select a lighter/heavier bar from live controls.
        // Set weights remain the total load, bar included.
        if StrengthBarbellExercisePolicy.usesBarEquipment(
            name: exercise.snapshot.name,
            equipment: exercise.snapshot.equipment
        ) {
            log.barWeightKilograms = StrengthBarWeightPreferences.mass(
                for: log.exercise.name, userID: accountID
            )
        }
        workout.exercises.append(log)
        activeWorkout = workout

        if wasEmpty ||
            previousExercisesComplete {
            currentExerciseIndex =
                max(
                    workout.exercises.count - 1,
                    0
                )
            currentSetIndex = 0
            restEndsAt = nil
            restStartedAt = nil
            reloadDraftFromCurrentSet()
        }

        persistCheckpointNow()
    }

    /// Session composition uses the same set model as starting a workout;
    /// appending never creates a second HKWorkoutSession/HealthKit entry.
    private static func strengthExerciseLogs(from session: PlannedSession)
        -> [StrengthExerciseLog] {
        // An explicit unified recipe is authoritative for grouped strength.
        // Legacy exercise arrays can also be populated by an older editor,
        // but using those in preference to the group blocks would discard
        // the recorded mode, round order and per-station settings.
        if let recipe = session.workoutBlocks,
           recipe.contains(where: {
               $0.kind == .exercise && $0.groupKind?.isStrengthGroup == true
           }) {
            return strengthExerciseLogsFromBlocks(recipe.sorted {
                $0.sequence < $1.sequence
            })
        }
        // Older workouts use PlannedExercise; newer ones can consist only of
        // blocks. Never launch a blank strength queue for block-only recipes.
        if session.exercises.isEmpty {
            return strengthExerciseLogsFromBlocks(session.resolvedWorkoutBlocks)
        }
        return session.exercises.map { planned in
            let setTargets =
                planned.resolvedSetTargets

            var snapshot = planned.embeddedExercise
            if snapshot.libraryExerciseID == nil {
                snapshot.libraryExerciseID = planned.exerciseID
            }
            var log = StrengthExerciseLog(
                id: UUID(),
                // Use the canonical library ID for cross-workout history,
                // not this session's incidental PlannedExercise row ID.
                plannedExerciseID: planned.exerciseID ?? planned.id,
                exercise: snapshot,
                sets:
                    Array(
                        setTargets.enumerated()
                    )
                    .map { index, target in
                        StrengthSetLog(
                            id: UUID(),
                            setNumber: index + 1,
                            plannedReps:
                                planned.resolvedTargetKind == .reps
                                    ? target.reps
                                    : nil,
                            plannedWeightKilograms:
                                planned.resolvedLoadKind == .weightKilograms
                                    ? target.weightKilograms
                                    : nil,
                            completedReps: nil,
                            completedWeightKilograms: nil,
                            rpe: nil,
                            completedAt: nil,
                            restSeconds:
                                target.restSeconds,
                            plannedRPE:
                                target.targetRPE,
                            plannedRIR:
                                target.targetRIR,
                            plannedSetType:
                                target.setType,
                            plannedTempo:
                                target.tempo,
                            plannedNote:
                                target.notes,
                            rir: nil,
                            isWarmUp:
                                target.isWarmUp,
                            targetKind:
                                planned.resolvedTargetKind,
                            plannedDurationSeconds:
                                planned.resolvedTargetKind == .time
                                    ? target.durationSeconds
                                    : nil,
                            loadKind:
                                planned.resolvedLoadKind,
                            plannedResistanceLevel:
                                planned.resolvedLoadKind == .resistanceLevel
                                    ? target.resistanceLevel
                                    : nil
                        )
                    },
                completedAt: nil,
                targetSpeedKilometersPerHour:
                    planned.targetSpeedKilometersPerHour,
                targetHeartRateZone:
                    planned.targetHeartRateZone
            )
            // Apply account-specific bar defaults after converting the plan.
            return log
        }

    }

    /// Converts a saved grouped recipe into the same authoritative
    /// strength log used by the live iPhone screen and Watch mirror.
    /// Each group member has its own planned sets, but shares group identity
    /// so completion cycles stations in order before the next round.
    static func strengthExerciseLogsFromBlocks(
        _ source: [WorkoutTemplateBlock]
    ) -> [StrengthExerciseLog] {
        var queue: [StrengthExerciseLog] = []
        for block in source {
            if block.kind == .rest {
                let last = queue.indices.last(where: { i in
                    block.groupID == nil ||
                    queue[i].groupID == block.groupID
                })
                if let last, let seconds = block.durationSeconds,
                   seconds.isFinite && seconds >= 0 {
                    let capped = min(Int(seconds.rounded()), 3_600)
                    if block.groupID != nil &&
                       block.groupKind?.canInsertRoundPause == true {
                        // A group pause happens BETWEEN rounds, never after
                        // the last completed round. Keep per-set values instead
                        // of overriding every set on the exercise.
                        queue[last].restSecondsOverride = nil
                        for setIndex in queue[last].sets.indices {
                            queue[last].sets[setIndex].restSeconds =
                                setIndex + 1 < queue[last].sets.count ? capped : 0
                        }
                    } else {
                        queue[last].restSecondsOverride = capped
                        for setIndex in queue[last].sets.indices {
                            queue[last].sets[setIndex].restSeconds = capped
                        }
                    }
                }
                continue
            }
            guard block.kind == .exercise else { continue }
            var snapshot = block.exerciseSnapshot ?? ExerciseSnapshot(
                name: block.title,
                instructions: [],
                primaryMuscles: [],
                equipment: [],
                imageURL: nil
            )
            if snapshot.libraryExerciseID == nil {
                snapshot.libraryExerciseID = block.exerciseID
            }
            // AMRAP has no predetermined number of rounds. Start with
            // one round and extend the queue while its time window is open.
            let setCount = block.groupKind == .amrap ? 1 :
                block.groupKind != nil
                    ? min(max(block.groupRounds ?? 1, 1), 20)
                    : min(max(block.setCount ?? 1, 1), 20)
            let timed = block.durationSeconds != nil
            let sets: [StrengthSetLog] = (0..<setCount).map { index in
                let target = block.individualSetTargets.flatMap { targets in
                    targets.indices.contains(index) ? targets[index] : nil
                }
                return StrengthSetLog(
                    id: UUID(),
                    setNumber: index + 1,
                    plannedReps: timed ? nil :
                        (target?.repetitions ?? block.repetitions ?? 10),
                    plannedWeightKilograms:
                        target?.weightKilograms ?? block.targetWeightKilograms,
                    completedReps: nil,
                    completedWeightKilograms: nil,
                    rpe: nil,
                    completedAt: nil,
                    // No automatic pause inside a drop set or a timed
                    // EMOM/AMRAP. Superset and circuit may opt into a
                    // station transition; their end-of-round pause is
                    // kept separately on the group rest block.
                    restSeconds: [.dropSet, .emom, .amrap].contains(block.groupKind)
                        ? 0
                        : Int(min(max(
                            block.restBetweenSetsSeconds ??
                                (block.groupKind == nil ? 90 : 0),
                            0
                        ), 3_600)),
                    isWarmUp: block.resolvedPhase == .warmup,
                    targetKind: timed ? .time : .reps,
                    plannedDurationSeconds: block.durationSeconds.flatMap { seconds in
                        guard seconds.isFinite && seconds > 0 else { return nil }
                        return min(max(Int(seconds.rounded()), 1), 7_200)
                    }
                )
            }
            let style: StrengthExerciseGroupStyle?
            switch block.groupKind {
            case .superset: style = .superset
            case .circuit: style = .circuit
            case .emom: style = .emom
            case .amrap: style = .amrap
            case .dropSet: style = .dropSet
            case .intervals, nil: style = nil
            }
            queue.append(StrengthExerciseLog(
                id: UUID(),
                plannedExerciseID: block.exerciseID,
                exercise: snapshot,
                sets: sets,
                completedAt: nil,
                groupID: style != nil ? block.groupID : nil,
                groupStyle: style,
                groupClockSeconds: style == .emom ?
                    (block.groupClockSeconds ?? 60) :
                    (style == .amrap ? (block.groupClockSeconds ?? 720) : nil)
            ))
        }
        return queue
    }

    /// Start one group's absolute clock exactly once, including after a
    /// restored checkpoint or switching from an earlier workout section.
    private static func beginStrengthGroup(
        _ workout: inout StrengthWorkoutLog, selected index: Int,
        at now: Date = Date()
    ) {
        guard workout.exercises.indices.contains(index),
              let id = workout.exercises[index].groupID,
              workout.exercises[index].groupStyle != nil,
              workout.exercises[index].groupStartedAt == nil else { return }
        for item in workout.exercises.indices where workout.exercises[item].groupID == id {
            workout.exercises[item].groupStartedAt = now
        }
    }

    /// Append a complete saved workout while preserving the existing active
    /// recording, captured sets, Watch workout ID and original training plan.
    /// Timed run/recovery blocks become one embedded interval exercise with
    /// phase-specific goals. No GPS or distance is invented for a treadmill.
    @discardableResult
    func appendWorkoutDuringSession(_ session: PlannedSession) -> Bool {
        guard var workout = activeWorkout else { return false }

        var additions = Self.strengthExerciseLogs(from: session)

        // Modern advanced workout builders can store only ordered blocks,
        // with no legacy session.exercises. Import those blocks once,
        // preserving their saved repetitions, duration, load and rest.
        if additions.isEmpty {
            for block in session.resolvedWorkoutBlocks {
                if block.kind == .rest {
                    if let lastExercise = additions.indices.last,
                       let lastSet = additions[lastExercise].sets.indices.last,
                       let seconds = block.durationSeconds, seconds > 0 {
                        additions[lastExercise].sets[lastSet].restSeconds =
                            min(Int(seconds.rounded()), 3_600)
                    }
                    continue
                }
                guard block.kind == .exercise else { continue }
                var snapshot = block.exerciseSnapshot ?? ExerciseSnapshot(
                    name: block.title,
                    instructions: [],
                    primaryMuscles: [],
                    equipment: [],
                    imageURL: nil
                )
                if snapshot.libraryExerciseID == nil {
                    snapshot.libraryExerciseID = block.exerciseID
                }
                let timed = block.durationSeconds != nil
                let newSet = StrengthSetLog(
                    id: UUID(),
                    setNumber: 1,
                    plannedReps: timed ? nil : (block.repetitions ?? 8),
                    plannedWeightKilograms: block.targetWeightKilograms,
                    completedReps: nil,
                    completedWeightKilograms: nil,
                    rpe: nil,
                    completedAt: nil,
                    restSeconds: 0,
                    isWarmUp: block.phase == .warmup,
                    targetKind: timed ? .time : .reps,
                    plannedDurationSeconds: block.durationSeconds.flatMap {
                        guard $0.isFinite && $0 > 0 else { return nil }
                        return Int(min(max($0.rounded(), 15), 7_200))
                    }
                )

                if let last = additions.indices.last,
                   let identity = snapshot.libraryExerciseID,
                   additions[last].exercise.libraryExerciseID == identity,
                   ATHLTHExerciseProgress.sameLiveSnapshot(additions[last].exercise, snapshot),
                   additions[last].appendedWorkoutID == nil {
                    var next = newSet
                    next.setNumber = additions[last].sets.count + 1
                    additions[last].sets.append(next)
                } else {
                    additions.append(StrengthExerciseLog(
                        id: UUID(),
                        plannedExerciseID: block.exerciseID,
                        exercise: snapshot,
                        sets: [newSet],
                        completedAt: nil
                    ))
                }
            }
        }

        for idx in additions.indices {
            additions[idx].appendedWorkoutID = session.id
            additions[idx].appendedWorkoutTitle = session.title
        }

        var runningOnly = session
        runningOnly.exercises = []
        // Legacy strength plans produce .rest blocks between strength sets.
        // Those are not running intervals and must not become treadmill sets.
        if let blocks = runningOnly.workoutBlocks {
            runningOnly.workoutBlocks = blocks.filter {
                $0.kind == .run || $0.kind == .rest
            }
        }
        let runBlocks = ATHLTHUnifiedWorkout.editorBlocks(from: runningOnly)
            .filter { $0.kind == .run || $0.kind == .rest }
        if runBlocks.contains(where: { $0.kind == .run }) {
            // This embedded motor is for indoor treadmill intervals only.
            // A saved outdoor route must stay on its real GPS run engine.
            let outdoorGPS =
                workout.captureDevice == .appleWatch &&
                workout.isOutdoorHybrid == true &&
                runBlocks.filter({ $0.kind == .run }).allSatisfy({
                    $0.isIndoor == false
                })
            guard session.routeID == nil,
                  session.resolvedRunningWorkouts.allSatisfy({
                      $0.routeID == nil
                  }),
                  runBlocks.filter({ $0.kind == .run }).allSatisfy({
                      $0.isIndoor != false || outdoorGPS
                  })
            else { return false }

            // Outdoor distance targets use Watch GPS distance and a
            // count-up effort clock, never a guessed time or belt speed.
            guard runBlocks.allSatisfy({ block in
                (block.distanceMeters == nil &&
                 block.durationSeconds.map {
                     $0.isFinite && (15...7_200).contains($0)
                 } == true) ||
                (outdoorGPS && block.kind == .run &&
                 block.durationSeconds == nil &&
                 block.distanceMeters.map {
                     $0.isFinite && (100...50_000).contains($0)
                 } == true)
            }) else { return false }

            let snapshots = ExerciseSnapshot(
                name: outdoorGPS ? "Outdoor Running" : "Treadmill Running",
                instructions: [],
                primaryMuscles: ["Quadriceps", "Gastrocnemius"],
                equipment: outdoorGPS ? [] : ["Treadmill"],
                imageURL: nil
            )
            let sets: [StrengthSetLog] = runBlocks.enumerated().map { i, block in
                StrengthSetLog(
                    id: UUID(),
                    setNumber: i + 1,
                    plannedReps: nil,
                    plannedWeightKilograms: nil,
                    completedReps: nil,
                    completedWeightKilograms: nil,
                    rpe: nil,
                    completedAt: nil,
                    restSeconds: 0,
                    isWarmUp: block.phase == .warmup,
                    targetKind: .time,
                    plannedDurationSeconds: block.durationSeconds.map {
                        min(max(Int($0.rounded()), 15), 7_200)
                    },
                    recordsWeight: false,
                    loadKind: .weightKilograms,
                    hybridPhaseTitle: block.title,
                    hybridPhaseKind: String(describing: block.phase),
                    hybridTargetHeartRateZone: block.targetHeartRateZone,
                    hybridTargetPaceSecondsPerKilometer:
                        block.targetPaceSecondsPerKilometer,
                    hybridTargetDistanceMeters: outdoorGPS
                        ? block.distanceMeters : nil
                )
            }
            additions.append(StrengthExerciseLog(
                id: UUID(),
                plannedExerciseID: nil,
                exercise: snapshots,
                sets: sets,
                completedAt: nil,
                appendedWorkoutTitle: session.title,
                appendedWorkoutID: session.id,
                isEmbeddedRunningInterval: true
            ))
        }

        guard !additions.isEmpty else { return false }
        applyBarDefaults(&additions)
        finalizeActualRestIfNeeded()
        let shouldFocus = workout.exercises.isEmpty ||
            workout.exercises.allSatisfy(\.isCompleted)
        let firstNew = workout.exercises.count
        workout.exercises.append(contentsOf: additions)
        if shouldFocus { Self.beginStrengthGroup(&workout, selected: firstNew) }
        activeWorkout = workout
        isFreeTrainingBetweenExercises = false
        if shouldFocus {
            currentExerciseIndex = firstNew
            currentSetIndex = 0
            restStartedAt = nil
            restEndsAt = nil
            reloadDraftFromCurrentSet()
        }
        persistCheckpointNow()
        return true
    }

    /// Atomically append a full planned workout and optionally switch focus
    /// to its first relevant motor. The parent workout/Watch IDs do not change.
    @discardableResult
    func appendWorkoutDuringSession(
        _ session: PlannedSession,
        startNow: Bool
    ) -> Bool {
        let before = Set(activeWorkout?.exercises.map(\.id) ?? [])
        guard appendWorkoutDuringSession(session) else { return false }
        guard startNow else { return true }

        let added = activeWorkout?.exercises.filter {
            !before.contains($0.id)
        } ?? []
        let first = session.kind == .running
            ? added.first(where: { $0.isEmbeddedRunningInterval == true })
                ?? added.first
            : added.first
        guard let selected = first else { return true }
        if currentExercise?.id != selected.id,
           currentTimedSetCountdown?.isRunning == true {
            // Explicitly choosing "Start now" closes the previous partial
            // timed set with its actual elapsed time before switching motors.
            completeCurrentDraftSet()
        }
        guard selectExerciseForNow(selected.id) else { return false }
        if selected.isEmbeddedRunningInterval == true {
            startOrResumeTimedSet()
        }
        return true
    }

    /// Start a planned strength+treadmill session as ONE durable recording.
    /// All parts were validated before a Watch workout is launched. This
    /// invokes only the established StrengthWorkoutStore capture lifecycle,
    /// not a second standalone run or StructuredWorkoutSession recorder.
    @discardableResult
    func startPlannedHybrid(
        session: PlannedSession,
        validatedParts: [PlannedSession],
        watchSessionID: UUID?,
        trackingMode: StrengthTrackingMode,
        captureDevice: WorkoutCaptureDevice,
        advancedConfiguration: StrengthAdvancedConfiguration? = nil,
        relayRequestID: UUID? = nil,
        admissionID: UUID? = nil
    ) -> Bool {
        guard activeWorkout == nil,
              !loadingAccount,
              ATHLTHWorkoutRecordingArbiter.mayStartStrength(
                  admissionID: admissionID
              ),
              !validatedParts.isEmpty,
              let canonicalParts = ATHLTHHybridWorkoutLaunchPlan.parts(
                  for: session,
                  allowOutdoorGPS: captureDevice == .appleWatch
              ),
              // Validate again against the original plan immediately before
              // recording starts. A caller-supplied parts array can be stale
              // or mutated after the preview was accepted.
              canonicalParts.count == validatedParts.count,
              canonicalParts.map(\.kind) == validatedParts.map(\.kind),
              validatedParts.allSatisfy({ $0.id == session.id })
        else { return false }

        var root = session
        root.kind = .strength
        root.exercises = []
        root.workoutBlocks = nil
        root.runningWorkout = nil
        root.runningWorkouts = nil
        start(
            session: root,
            watchSessionID: watchSessionID,
            trackingMode: trackingMode,
            captureDevice: captureDevice,
            advancedConfiguration: advancedConfiguration,
            relayRequestID: relayRequestID,
            admissionID: admissionID
        )
        // A rejected launch must not append hybrid parts to another workout.
        guard let launched = activeWorkout,
              launched.plannedSessionID == session.id,
              launched.watchSessionID == watchSessionID,
              launched.captureDevice == captureDevice,
              launched.relayRequestID == relayRequestID,
              launched.endedAt == nil else { return false }

        if captureDevice == .appleWatch &&
            ATHLTHHybridWorkoutLaunchPlan.isOutdoorTimedHybrid(session) {
            var marked = launched
            marked.isOutdoorHybrid = true
            activeWorkout = marked
        }

        // Only the freshly validated canonical parts may affect the
        // single recording. Never append caller-controlled snapshots.
        for part in canonicalParts {
            guard appendWorkoutDuringSession(part) else {
                // Never leave a partially constructed hybrid marked live.
                discardActiveWorkout()
                return false
            }
        }

        guard activeWorkout?.plannedSessionID == session.id,
              activeWorkout?.exercises.isEmpty == false,
              activeWorkout?.watchSessionID == watchSessionID
        else {
            discardActiveWorkout()
            return false
        }
        // Keep original identity, history target and single Watch capture.
        return true
    }


    /// Confirm the exact recording after starting either Phone or Watch.
    /// A void start() can be rejected during account recovery or a late
    /// competing launch. A UI must never mark the calendar session started
    /// merely because the function returned.
    func matchesStartedPlannedWorkout(
        sessionID: UUID,
        captureDevice: WorkoutCaptureDevice,
        watchSessionID: UUID?
    ) -> Bool {
        guard let activeWorkout else { return false }
        return activeWorkout.endedAt == nil &&
            activeWorkout.plannedSessionID == sessionID &&
            activeWorkout.captureDevice == captureDevice &&
            activeWorkout.watchSessionID == watchSessionID
    }

    func start(
        session: PlannedSession,
        watchSessionID: UUID?,
        trackingMode: StrengthTrackingMode,
        captureDevice: WorkoutCaptureDevice,
        advancedConfiguration:
            StrengthAdvancedConfiguration? = nil,
        relayRequestID: UUID? = nil,
        admissionID: UUID? = nil
    ) {
        // A reserved original workout may be written only by its owner.
        guard activeWorkout == nil, !loadingAccount,
              ATHLTHWorkoutRecordingArbiter.mayStartStrength(
                  admissionID: admissionID
              ) else { return }
        recoveredCheckpointSavedAt = nil
        setEffortClock = nil
        cardioWatchCaptures = [:]
        watchCaptureNeedsBaseline = []
        var exerciseLogs = Self.strengthExerciseLogs(from: session)
        applyBarDefaults(&exerciseLogs)

        var launchedWorkout = StrengthWorkoutLog(
            id: UUID(),
            plannedSessionID: session.id,
            watchSessionID: watchSessionID,
            captureDevice: captureDevice,
            trackingMode: trackingMode,
            title: session.title,
            startedAt: Date(),
            endedAt: nil,
            exercises: exerciseLogs,
            healthMetrics: LinkedHealthWorkoutMetrics(
                healthKitWorkoutUUID: nil,
                duration: nil,
                activeCalories: nil,
                averageHeartRate: nil,
                maxHeartRate: nil
            ),
            advancedConfiguration:
                advancedConfiguration,
            allowsLiveExerciseBuilding:
                false
        )

        let launchStartedAt = launchedWorkout.startedAt
        Self.beginStrengthGroup(&launchedWorkout, selected: 0,
                                at: launchStartedAt)
        launchedWorkout.relayRequestID = relayRequestID
        launchedWorkout.plannedTrainingPlace = session.plannedTrainingPlace
        launchedWorkout.liveHeartRateTargetZone =
            session.targetAlertConfiguration?.heartRateZone
        activeWorkout = launchedWorkout
        currentExerciseIndex = 0
        currentSetIndex = 0
        restEndsAt = nil
        restStartedAt = nil
        isFreeTrainingBetweenExercises = false
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
    }

    /// The active group is one workout on phone and Watch. Its window
    /// governs whether a new set may be recorded, not the HealthKit session.
    func canCompleteCurrentStrengthMode(at now: Date = Date()) -> Bool {
        guard let workout = activeWorkout,
              workout.exercises.indices.contains(currentExerciseIndex)
        else { return false }
        let item = workout.exercises[currentExerciseIndex]
        guard let id = item.groupID else { return true }
        let members = workout.exercises.filter { $0.groupID == id }
        let station = members.firstIndex(where: { $0.id == item.id }) ?? 0
        return ATHLTHStrengthModeClockPolicy.permitsCompletion(
            modeRaw: item.groupStyle?.rawValue,
            startedAt: item.groupStartedAt,
            clockSeconds: item.groupClockSeconds,
            roundIndex: currentSetIndex,
            stationIndex: station,
            stationCount: members.count,
            at: now
        )
    }

    func completeCurrentSet(
        reps: Int?,
        durationSeconds: Int? = nil,
        weightKilograms: Double?,
        resistanceLevel: Int? = nil,
        distanceMeters: Double? = nil,
        rpe: Double?,
        rir: Double? = nil,
        isWarmUp: Bool? = nil,
        restSeconds: Int? = nil,
        completedAt: Date = Date()
    ) {
        guard
            var workout = activeWorkout,
            workout.exercises.indices.contains(currentExerciseIndex),
            workout.exercises[currentExerciseIndex].sets.indices.contains(currentSetIndex),
            !workout.exercises[currentExerciseIndex].sets[currentSetIndex].isResolved
        else {
            return
        }

        // The clock policy also guards Watch/offline-replayed completions;
        // a blocked command cannot add completed reps, weight or records.
        guard canCompleteCurrentStrengthMode(at: completedAt) else { return }
        var set = workout.exercises[currentExerciseIndex].sets[currentSetIndex]
        let measuredEffort = currentSetEffortClock?.elapsedSeconds(at: completedAt)
        // The timer is an optional aid. It does not own set completion;
        // completion from iPhone or Watch always clears it if it targets this set.
        if currentTimedSetCountdown != nil {
            timedSetCountdown = nil
        }
        set.completedReps =
            set.resolvedTargetKind == .reps
                ? reps.map { max($0, 0) }
                : nil
        set.completedDurationSeconds =
            set.resolvedTargetKind == .time
                ? durationSeconds.map {
                    min(max($0, 0), 7_200)
                }
                : nil
        set.completedWeightKilograms =
            set.resolvedLoadKind == .weightKilograms
                ? weightKilograms.map {
                    max($0, 0)
                }
                : nil
        set.completedResistanceLevel =
            set.resolvedLoadKind == .resistanceLevel
                ? resistanceLevel.map {
                    min(max($0, 1), 10)
                }
                : nil
        set.completedDistanceMeters =
            distanceMeters.map {
                max($0, 0)
            }
        set.effortSegments = [
            StrengthSetEffortSegment(
                reps:
                    set.resolvedTargetKind == .reps
                        ? set.completedReps
                        : nil,
                weightKilograms:
                    set.completedWeightKilograms,
                durationSeconds:
                    set.resolvedTargetKind == .time
                        ? set.completedDurationSeconds
                        : nil,
                distanceMeters:
                    set.completedDistanceMeters,
                resistanceLevel:
                    set.completedResistanceLevel
            )
        ]
        set.rpe = rpe
        set.rir = rir
        if let isWarmUp {
            set.isWarmUp = isWarmUp
        }
        if let restSeconds {
            set.restSeconds = max(restSeconds, 0)
        }
        if StrengthTreadmillWarmUpDefaults.isTreadmill(
            workout.exercises[currentExerciseIndex].exercise.name
        ) {
            set.completedTreadmillSpeedKilometersPerHour =
                draftTreadmillSpeedKilometersPerHour > 0
                    ? draftTreadmillSpeedKilometersPerHour : nil
            set.completedTreadmillInclinePercent = draftTreadmillInclinePercent
            if let elapsed = set.completedDurationSeconds {
                set.manuallyEstimatedTreadmillDistanceMeters =
                    ATHLTHRunningPace.manuallyEstimatedTreadmillDistance(
                        speedKilometersPerHour: draftTreadmillSpeedKilometersPerHour,
                        durationSeconds: Double(elapsed)
                    )
                set.effortSegments = [
                    StrengthSetEffortSegment(durationSeconds: elapsed)
                ]
            }
        }
        if let capture = cardioWatchCaptures.removeValue(forKey: set.id),
           StrengthCardioExercisePolicy.isCardio(
               workout.exercises[currentExerciseIndex].exercise.name
           ) {
            set.watchAverageHeartRateBPM = capture.averageHeartRate
            set.watchMaximumHeartRateBPM = capture.peakHeartRateBPM
            if capture.capturedActiveDuration > 0 {
                set.watchActiveDurationSeconds = capture.capturedActiveDuration
            }
            if capture.measuredDistanceMeters > 0 {
                let measured = capture.measuredDistanceMeters
                set.watchMeasuredDistanceMeters = measured
                set.completedDistanceMeters = measured
                set.effortSegments = [
                    StrengthSetEffortSegment(
                        durationSeconds: set.completedDurationSeconds,
                        distanceMeters: measured
                    )
                ]
            }
            watchCaptureNeedsBaseline.remove(set.id)
        }
        set.completedAt = completedAt
        if let measuredEffort {
            set.actualSetElapsedSeconds = measuredEffort
        }
        setEffortClock = nil

        workout.exercises[currentExerciseIndex].sets[currentSetIndex] = set

        let allSetsCompleted = workout.exercises[currentExerciseIndex].sets.allSatisfy(\.isCompleted)

        if allSetsCompleted {
            workout.exercises[currentExerciseIndex].completedAt = completedAt
        }

        let restConfiguration =
                workout
                    .advancedConfiguration?
                    .restCues

        let automaticRestTimer =
            restConfiguration?
                .automaticRestTimer ??
            true
        let fallbackRestSeconds =
            restConfiguration?
                .defaultRestSeconds ??
            90
        let exerciseRestSeconds =
            workout.exercises[
                currentExerciseIndex
            ].restSecondsOverride
        let resolvedRestSeconds =
            max(
                exerciseRestSeconds ??
                    set.restSeconds ??
                    fallbackRestSeconds,
                0
            )

        if advanceLiveExecutionQueue(workout: &workout, automaticRestTimer: automaticRestTimer,
                                     restSeconds: resolvedRestSeconds, at: completedAt) {
            activeWorkout = workout
            reloadDraftFromCurrentSet()
            persistCheckpointNow()
            return
        }

        if advanceGroupedSetIfNeeded(
            workout: &workout,
            completedExerciseIndex:
                currentExerciseIndex,
            completedSetIndex:
                currentSetIndex,
            automaticRestTimer:
                automaticRestTimer,
            restSeconds:
                resolvedRestSeconds,
            at: completedAt
        ) {
            activeWorkout = workout
            reloadDraftFromCurrentSet()
            persistCheckpointNow()
            return
        }

        if allSetsCompleted {
            let hasNextExercise =
                workout.exercises
                    .enumerated()
                    .contains {
                        index,
                        exercise in

                        index !=
                            currentExerciseIndex &&
                        !exercise.isCompleted
                    }

            // Finishing the final set of an exercise should still enter the
            // programmed rest period before the athlete deliberately starts
            // the next exercise. We keep the current exercise selected until
            // "Ready for next exercise" is tapped so transition time can be
            // measured accurately.
            if hasNextExercise &&
                automaticRestTimer &&
                resolvedRestSeconds > 0 {
                let restStart = completedAt
                restStartedAt =
                    restStart
                restEndsAt =
                    restStart
                        .addingTimeInterval(
                            TimeInterval(
                                resolvedRestSeconds
                            )
                        )
            } else {
                // After the final exercise, keep counting idle time as rest
                // until the next exercise is added or the workout is saved.
                restStartedAt = completedAt
                restEndsAt = nil
            }
        } else {
            if automaticRestTimer &&
                resolvedRestSeconds > 0 {
                let restStart = completedAt
                restStartedAt =
                    restStart
                restEndsAt =
                    restStart
                        .addingTimeInterval(
                            TimeInterval(
                                resolvedRestSeconds
                            )
                        )
            } else {
                restStartedAt = nil
                restEndsAt = nil
            }
            advanceSetIndex(
                in:
                    workout.exercises[
                        currentExerciseIndex
                    ]
            )
        }

        activeWorkout = workout
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
    }

    func completeCurrentDraftSet(completedAt: Date = Date()) {
        let effortMetric =
            activeWorkout?
                .advancedConfiguration?
                .effortMetric ??
            .off

        let targetKind =
            currentSet?.resolvedTargetKind ??
            .reps
        let loadKind =
            currentSet?.resolvedLoadKind ??
            .weightKilograms
        let treadmill = currentExercise.map {
            StrengthTreadmillWarmUpDefaults.isTreadmill($0.exercise.name)
        } ?? false

        completeCurrentSet(
            reps:
                targetKind == .reps
                    ? draftReps
                    : nil,
            durationSeconds:
                targetKind == .time
                    ? (currentSet?.plannedDurationSeconds == nil &&
                       (currentExercise?.exercise.isTimeOnlyBodyweightStrength == true ||
                        currentSet?.hybridTargetDistanceMeters != nil)
                        ? Int((currentSetEffortClock?.elapsedSeconds(at: completedAt) ?? 0).rounded())
                        : (currentTimedSetCountdown?.elapsedSeconds(at: completedAt) ?? draftDurationSeconds))
                    : nil,
            weightKilograms:
                loadKind == .weightKilograms && !treadmill && currentSetRecordsWeight
                    ? draftWeightKilograms
                    : nil,
            resistanceLevel:
                loadKind == .resistanceLevel
                    ? draftResistanceLevel
                    : nil,
            rpe:
                effortMetric == .rpe
                    ? draftRPE
                    : nil,
            rir:
                effortMetric == .rir
                    ? draftRIR
                    : nil,
            isWarmUp: draftWarmUp,
            restSeconds:
                draftRestSeconds,
            completedAt: completedAt
        )
    }

    func updateActiveSetResult(
        exerciseID: UUID,
        setID: UUID,
        segments: [StrengthSetEffortSegment],
        distanceMeters: Double? = nil,
        resistanceLevel: Int? = nil
    ) {
        guard var workout = activeWorkout,
              let exerciseIndex =
                workout.exercises.firstIndex(
                    where: { $0.id == exerciseID }
                ),
              let setIndex =
                workout.exercises[exerciseIndex]
                    .sets
                    .firstIndex(
                        where: { $0.id == setID }
                    )
        else {
            return
        }

        var set =
            workout.exercises[
                exerciseIndex
            ].sets[setIndex]

        let cleaned: [StrengthSetEffortSegment] =
            segments.compactMap { segment in
                let reps = segment.reps.map { value in
                    max(value, 0)
                }
                let weight =
                    segment.weightKilograms.map { value in
                        max(value, 0)
                    }
                let duration =
                    segment.durationSeconds.map { value in
                        min(max(value, 0), 7_200)
                    }
                let distance =
                    segment.distanceMeters.map { value in
                        max(value, 0)
                    }
                let resistance =
                    segment.resistanceLevel.map { value in
                        min(max(value, 1), 10)
                    }

                let hasValue =
                    (reps ?? 0) > 0 ||
                    (weight ?? 0) > 0 ||
                    (duration ?? 0) > 0 ||
                    (distance ?? 0) > 0 ||
                    resistance != nil

                guard hasValue else {
                    return nil
                }

                return StrengthSetEffortSegment(
                    id: segment.id,
                    reps: reps,
                    weightKilograms: weight,
                    durationSeconds: duration,
                    distanceMeters: distance,
                    resistanceLevel: resistance
                )
            }

        set.effortSegments =
            cleaned.isEmpty
                ? nil
                : cleaned

        let totalReps =
            cleaned
                .compactMap { $0.reps }
                .reduce(0, +)
        let totalDuration =
            cleaned
                .compactMap { $0.durationSeconds }
                .reduce(0, +)

        set.completedReps =
            totalReps > 0
                ? totalReps
                : set.completedReps
        set.completedDurationSeconds =
            totalDuration > 0
                ? totalDuration
                : set.completedDurationSeconds

        let segmentWeights =
            cleaned
                .compactMap { $0.weightKilograms }
                .filter { $0 > 0 }
        if !segmentWeights.isEmpty {
            set.completedWeightKilograms =
                segmentWeights.max()
        }

        let segmentResistance =
            cleaned
                .compactMap { $0.resistanceLevel }
                .last
        set.completedResistanceLevel =
            resistanceLevel.map {
                min(max($0, 1), 10)
            } ??
            segmentResistance ??
            set.completedResistanceLevel

        let segmentDistance =
            cleaned
                .compactMap { $0.distanceMeters }
                .reduce(0, +)
        set.completedDistanceMeters =
            distanceMeters.map {
                max($0, 0)
            } ??
            (segmentDistance > 0
                ? segmentDistance
                : set.completedDistanceMeters)

        workout.exercises[
            exerciseIndex
        ].sets[setIndex] = set

        activeWorkout = workout
        persistCheckpointNow()
    }

    func updateActiveSetDistance(
        exerciseID: UUID,
        setID: UUID,
        distanceMeters: Double
    ) {
        guard let workout = activeWorkout,
              let exercise =
                workout.exercises.first(
                    where: { $0.id == exerciseID }
                ),
              let set =
                exercise.sets.first(
                    where: { $0.id == setID }
                )
        else {
            return
        }

        var segments =
            set.effortSegments ?? []

        if segments.isEmpty {
            segments = [
                StrengthSetEffortSegment(
                    reps:
                        set.completedReps,
                    weightKilograms:
                        set.completedWeightKilograms,
                    durationSeconds:
                        set.completedDurationSeconds,
                    resistanceLevel:
                        set.completedResistanceLevel
                )
            ]
        }

        if segments.indices.contains(
            segments.count - 1
        ) {
            segments[
                segments.count - 1
            ].distanceMeters =
                max(distanceMeters, 0)
        }

        updateActiveSetResult(
            exerciseID: exerciseID,
            setID: setID,
            segments: segments,
            distanceMeters:
                max(distanceMeters, 0),
            resistanceLevel:
                set.completedResistanceLevel
        )
    }

    func updateCompletedSetResult(
        workoutID: UUID,
        exerciseID: UUID,
        setID: UUID,
        segments: [StrengthSetEffortSegment],
        distanceMeters: Double? = nil,
        resistanceLevel: Int? = nil
    ) {
        guard let workoutIndex =
                workoutHistory.firstIndex(
                    where: {
                        $0.id == workoutID
                    }
                ),
              let exerciseIndex =
                workoutHistory[
                    workoutIndex
                ].exercises
                .firstIndex(
                    where: {
                        $0.id == exerciseID
                    }
                ),
              let setIndex =
                workoutHistory[
                    workoutIndex
                ].exercises[
                    exerciseIndex
                ].sets
                .firstIndex(
                    where: {
                        $0.id == setID
                    }
                )
        else {
            return
        }

        var workout =
            workoutHistory[workoutIndex]
        var set =
            workout.exercises[
                exerciseIndex
            ].sets[setIndex]

        let cleaned: [StrengthSetEffortSegment] =
            segments.map { segment in
                let reps = segment.reps.map { value in
                    max(value, 0)
                }
                let weight =
                    segment.weightKilograms.map { value in
                        max(value, 0)
                    }
                let duration =
                    segment.durationSeconds.map { value in
                        min(max(value, 0), 7_200)
                    }
                let distance =
                    segment.distanceMeters.map { value in
                        max(value, 0)
                    }
                let resistance =
                    segment.resistanceLevel.map { value in
                        min(max(value, 1), 10)
                    }

                return StrengthSetEffortSegment(
                    id: segment.id,
                    reps: reps,
                    weightKilograms: weight,
                    durationSeconds: duration,
                    distanceMeters: distance,
                    resistanceLevel: resistance
                )
            }

        set.effortSegments = cleaned
        let reps =
            cleaned
                .compactMap { $0.reps }
                .reduce(0, +)
        let duration =
            cleaned
                .compactMap { $0.durationSeconds }
                .reduce(0, +)
        set.completedReps =
            reps > 0 ? reps : nil
        set.completedDurationSeconds =
            duration > 0
                ? duration
                : set.completedDurationSeconds
        set.completedWeightKilograms =
            cleaned
                .compactMap { $0.weightKilograms }
                .max() ??
            set.completedWeightKilograms
        set.completedResistanceLevel =
            resistanceLevel.map {
                min(max($0, 1), 10)
            } ??
            cleaned
                .compactMap { $0.resistanceLevel }
                .last ??
            set.completedResistanceLevel
        let segmentDistance =
            cleaned
                .compactMap { $0.distanceMeters }
                .reduce(0, +)
        set.completedDistanceMeters =
            distanceMeters.map {
                max($0, 0)
            } ??
            (segmentDistance > 0
                ? segmentDistance
                : set.completedDistanceMeters)

        workout.exercises[
            exerciseIndex
        ].sets[setIndex] = set
        workoutHistory[workoutIndex] =
            workout

        if completedWorkout?.id ==
            workoutID {
            completedWorkout = workout
        }

        persistWorkoutHistory()
    }

    /// Edit the prescribed target for an earlier set without changing the
    /// kilograms the athlete actually recorded. The active set index and
    /// ongoing Watch recording must not move.
    @discardableResult
    func updateActiveSetTargetWeight(
        exerciseID: UUID,
        setID: UUID,
        kilograms: Double?
    ) -> Bool {
        guard var workout = activeWorkout,
              let exerciseIndex = workout.exercises.firstIndex(where: {
                  $0.id == exerciseID
              }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: {
                  $0.id == setID
              }),
              workout.exercises[exerciseIndex].sets[setIndex].resolvedLoadKind ==
                  .weightKilograms else { return false }
        if let kilograms {
            guard kilograms.isFinite && kilograms >= 0 && kilograms <= 999.5
            else { return false }
        }

        // Planned load is metadata; completedWeightKilograms and effortSegments
        // contain the historical performed load and stay unmodified.
        workout.exercises[exerciseIndex].sets[setIndex].plannedWeightKilograms =
            kilograms
        activeWorkout = workout
        persistCheckpointNow()
        return true
    }

    func setCurrentExerciseRestSeconds(
        _ seconds: Int
    ) {
        guard var workout = activeWorkout,
              workout.exercises.indices
                .contains(
                    currentExerciseIndex
                )
        else {
            return
        }

        let value =
            min(max(seconds, 0), 600)

        workout.exercises[
            currentExerciseIndex
        ].restSecondsOverride = value

        for index in workout.exercises[
            currentExerciseIndex
        ].sets.indices
        where !workout.exercises[
            currentExerciseIndex
        ].sets[index].isCompleted {
            workout.exercises[
                currentExerciseIndex
            ].sets[index].restSeconds =
                value
        }

        activeWorkout = workout
        draftRestSeconds = value
    }

    func groupExercises(
        ids: [UUID],
        style: StrengthExerciseGroupStyle
    ) {
        guard var workout = activeWorkout else {
            return
        }

        let uniqueIDs =
            Array(Set(ids))
        guard uniqueIDs.count >= 2 else {
            return
        }

        let groupID = UUID()
        var matched = 0

        for index in workout.exercises.indices
        where uniqueIDs.contains(
            workout.exercises[index].id
        ) {
            workout.exercises[index].groupID =
                groupID
            workout.exercises[index].groupStyle =
                style
            matched += 1
        }

        guard matched >= 2 else {
            return
        }

        activeWorkout = workout
        persistCheckpointNow()
    }

    func ungroupExercise(
        _ exerciseID: UUID
    ) {
        guard var workout = activeWorkout,
              let exercise =
                workout.exercises.first(
                    where: {
                        $0.id == exerciseID
                    }
                ),
              let groupID = exercise.groupID
        else {
            return
        }

        for index in workout.exercises.indices
        where workout.exercises[index]
            .groupID == groupID {
            workout.exercises[index].groupID =
                nil
            workout.exercises[index].groupStyle =
                nil
        }

        activeWorkout = workout
        persistCheckpointNow()
    }

    func substituteCurrentExercise(
        with exercise: Exercise
    ) {
        guard var workout = activeWorkout,
              workout.exercises.indices
                .contains(
                    currentExerciseIndex
                )
        else {
            return
        }

        let source =
            workout.exercises[
                currentExerciseIndex
            ]
        let previous =
            source.exercise.name
        let completedSets =
            source.sets.filter(\.isCompleted)
        let remainingSets =
            source.sets.filter {
                !$0.isCompleted
            }

        if completedSets.isEmpty {
            workout.exercises[
                currentExerciseIndex
            ].exercise = exercise.snapshot
            workout.exercises[
                currentExerciseIndex
            ].substitutedFromExerciseName =
                previous

            activeWorkout = workout
            reloadDraftFromCurrentSet()
            return
        }

        guard !remainingSets.isEmpty else {
            return
        }

        workout.exercises[
            currentExerciseIndex
        ].sets = completedSets
        workout.exercises[
            currentExerciseIndex
        ].completedAt = Date()

        let replacementSets =
            remainingSets
                .enumerated()
                .map {
                    offset,
                    set in

                    StrengthSetLog(
                        id: UUID(),
                        setNumber:
                            offset + 1,
                        plannedReps:
                            set.plannedReps,
                        plannedWeightKilograms:
                            set.plannedWeightKilograms,
                        completedReps: nil,
                        completedWeightKilograms:
                            nil,
                        rpe: nil,
                        completedAt: nil,
                        restSeconds:
                            set.restSeconds,
                        rir: nil,
                        isWarmUp:
                            set.isWarmUp,
                        targetKind:
                            set.targetKind,
                        plannedDurationSeconds:
                            set.plannedDurationSeconds,
                        loadKind:
                            set.loadKind,
                        plannedResistanceLevel:
                            set.plannedResistanceLevel
                    )
                }

        let replacement =
            StrengthExerciseLog(
                id: UUID(),
                plannedExerciseID: nil,
                exercise: exercise.snapshot,
                sets: replacementSets,
                completedAt: nil,
                restSecondsOverride:
                    source.restSecondsOverride,
                groupID: source.groupID,
                groupStyle:
                    source.groupStyle,
                substitutedFromExerciseName:
                    previous
            )

        let insertionIndex =
            min(
                currentExerciseIndex + 1,
                workout.exercises.count
            )
        workout.exercises.insert(
            replacement,
            at: insertionIndex
        )

        currentExerciseIndex =
            insertionIndex
        currentSetIndex = 0
        restEndsAt = nil
        restStartedAt = nil
        activeWorkout = workout
        reloadDraftFromCurrentSet()
    }

    func progressionSuggestion(
        for exercise: StrengthExerciseLog
    ) -> StrengthProgressionSuggestion? {
        // ATHLTH Coach owns the read-only evidence boundary. The legacy
        // calculation remains unchanged for now, but it may only evaluate
        // comparable, finished working sets from the same movement and
        // apparatus type. No plan or live set is changed here.
        let targetReps =
            exercise.sets.first(where: { $0.plannedReps != nil })?.plannedReps ??
            draftReps

        let sessions = ATHLTHCoachStrengthComparableHistory.sessions(
            for: exercise,
            in: workoutHistory
        )

        guard let latest = sessions.first,
              !latest.isAmbiguous else { return nil }
        let latestEvidence = ATHLTHCoachStrengthComparableHistory
            .targetEvidence(for: latest.exercise)
        let baselineLoad = exercise.sets
            .compactMap(\.plannedWeightKilograms)
            .first(where: { $0.isFinite && $0 > 0 }) ??
            latestEvidence?.minimumRecordedWeightKg ?? 0

        let assessment = ATHLTHCoachStrengthDecision.assess(
            evidence: sessions.map { record in
                let data = record.isAmbiguous ? nil :
                    ATHLTHCoachStrengthComparableHistory.targetEvidence(
                        for: record.exercise
                    )
                return ATHLTHCoachStrengthDecision.Evidence(
                    workoutID: record.workoutID,
                    date: record.date,
                    workingSetIDs: data?.workingSetIDs ?? [],
                    minimumWorkingWeightKg: data?.minimumRecordedWeightKg ?? 0,
                    metTargets: data?.metAllTargets == true
                )
            },
            prescribedLoadKg: baselineLoad
        )
        // No numerical progression without two recent successful sessions.
        // The review-only decision does not edit a set until tapped by athlete.
        guard assessment.action == .reviewSmallIncrease,
              var suggestion = AthleteStrengthProgression.suggestion(
                  sets: latest.exercise.sets.filter(
                      ATHLTHCoachStrengthComparableHistory.isComparableWorkingSet
                  ),
                  targetReps: targetReps
              ) else {
            return nil
        }
        let increment = suggestion.suggestedWeightKilograms -
            suggestion.previousWeightKilograms
        if increment > max(0.5, baselineLoad * 0.15) || increment > 5 {
            return nil
        }

        let recentSuggestions = sessions.compactMap { record in
            AthleteStrengthProgression.suggestion(
                sets: record.exercise.sets.filter(
                    ATHLTHCoachStrengthComparableHistory.isComparableWorkingSet
                ),
                targetReps: targetReps
            )
        }

        suggestion.recentSessionCount = recentSuggestions.count
        suggestion.recentTrend = AthleteStrengthProgression.recentTrend(
            suggestions: recentSuggestions
        )
        return suggestion
    }

    struct EMOMWindowReconciliation {
        var nextExerciseIndex: Int?
        var nextSetIndex: Int?
        var skippedSlots: Int
        var groupFinished: Bool
    }

    /// Resolve elapsed EMOM slots without ever claiming they were completed.
    /// Slots are chronological: round 1/station 1, station 2, then round 2.
    /// Absolute time means backgrounding, Watch handoff and app resume
    /// cannot extend an already-missed minute.
    static func reconcileEMOMWindows(
        exercises: inout [StrengthExerciseLog],
        groupID: UUID,
        at now: Date
    ) -> EMOMWindowReconciliation? {
        let members = exercises.indices.filter { exercises[$0].groupID == groupID }
        guard let first = members.first,
              exercises[first].groupStyle == .emom,
              let started = exercises[first].groupStartedAt,
              let clock = exercises[first].groupClockSeconds,
              clock.isFinite, clock > 0,
              let rounds = members.map({ exercises[$0].sets.count }).min(),
              rounds > 0 else { return nil }
        let totalSlots = rounds * members.count
        let elapsed = max(now.timeIntervalSince(started), 0)
        let expiredSlots = min(totalSlots, max(0, Int(floor(elapsed / clock))))
        var skipped = 0
        if expiredSlots > 0 {
            for slot in 0..<expiredSlots {
                let exerciseIndex = members[slot % members.count]
                let setIndex = slot / members.count
                guard exercises[exerciseIndex].sets.indices.contains(setIndex),
                      !exercises[exerciseIndex].sets[setIndex].isResolved
                else { continue }
                exercises[exerciseIndex].sets[setIndex].skippedAt =
                    started.addingTimeInterval(Double(slot + 1) * clock)
                exercises[exerciseIndex].skippedPlannedSetCount =
                    (exercises[exerciseIndex].skippedPlannedSetCount ?? 0) + 1
                skipped += 1
            }
        }
        for index in members {
            if !exercises[index].sets.isEmpty &&
                exercises[index].sets.allSatisfy(\.isResolved) {
                exercises[index].completedAt = exercises[index].completedAt ?? now
            }
        }
        for slot in expiredSlots..<totalSlots {
            let exerciseIndex = members[slot % members.count]
            let setIndex = slot / members.count
            if exercises[exerciseIndex].sets.indices.contains(setIndex),
               !exercises[exerciseIndex].sets[setIndex].isResolved {
                return EMOMWindowReconciliation(
                    nextExerciseIndex: exerciseIndex,
                    nextSetIndex: setIndex,
                    skippedSlots: skipped, groupFinished: false
                )
            }
        }
        return EMOMWindowReconciliation(
            nextExerciseIndex: nil, nextSetIndex: nil,
            skippedSlots: skipped, groupFinished: true
        )
    }

    /// Called from the live iPhone mode clock and on restoration. Skipped
    /// work is accounted for but will never appear in completed-set volume.
    @discardableResult
    func reconcileCurrentEMOM(at now: Date = Date()) -> Int {
        guard var workout = activeWorkout,
              workout.exercises.indices.contains(currentExerciseIndex),
              let selected = workout.exercises[currentExerciseIndex].groupID,
              workout.exercises[currentExerciseIndex].groupStyle == .emom,
              let next = Self.reconcileEMOMWindows(
                exercises: &workout.exercises, groupID: selected, at: now
              ) else { return 0 }
        let previousExerciseIndex = currentExerciseIndex
        let previousSetIndex = currentSetIndex
        if let index = next.nextExerciseIndex,
           let set = next.nextSetIndex {
            if currentExerciseIndex != index || currentSetIndex != set {
                currentExerciseIndex = index
                currentSetIndex = set
                restStartedAt = nil
                restEndsAt = nil
                timedSetCountdown = nil
                setEffortClock = nil
            }
        } else if next.groupFinished,
                  let subsequent = workout.exercises.indices.first(where: {
                      workout.exercises[$0].groupID != selected &&
                      !workout.exercises[$0].isCompleted
                  }) {
            Self.beginStrengthGroup(&workout, selected: subsequent, at: now)
            currentExerciseIndex = subsequent
            currentSetIndex = workout.exercises[subsequent].sets
                .firstIndex(where: { !$0.isResolved }) ?? 0
            // Finishing an EMOM group must not carry the old station's
            // rest, effort or timed countdown into a different exercise.
            restStartedAt = nil
            restEndsAt = nil
            timedSetCountdown = nil
            setEffortClock = nil
        }
        let moved = previousExerciseIndex != currentExerciseIndex ||
            previousSetIndex != currentSetIndex
        guard moved || next.skippedSlots > 0 else { return 0 }
        activeWorkout = workout
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
        return next.skippedSlots
    }

    /// Returns one new AMRAP round only after the entire previous round
    /// has been recorded. Does not infer work from timer ticks. A single
    /// exercise AMRAP follows the same rules as a multi-station AMRAP.
    @discardableResult
    static func extendOpenEndedAMRAPGroupIfNeeded(
        exercises: inout [StrengthExerciseLog],
        groupID: UUID,
        at now: Date
    ) -> Bool {
        let indices = exercises.indices.filter { exercises[$0].groupID == groupID }
        guard let firstIndex = indices.first,
              exercises[firstIndex].groupStyle == .amrap,
              !indices.contains(where: { exercises[$0].sets.isEmpty }),
              indices.allSatisfy({ index in
                  exercises[index].sets.allSatisfy(\.isCompleted)
              }),
              ATHLTHStrengthModeClockPolicy.permitsCompletion(
                modeRaw: StrengthExerciseGroupStyle.amrap.rawValue,
                startedAt: exercises[firstIndex].groupStartedAt,
                clockSeconds: exercises[firstIndex].groupClockSeconds,
                roundIndex: 0, stationIndex: 0, stationCount: indices.count,
                at: now
              ) else { return false }

        for index in indices {
            guard let previous = exercises[index].sets.last else { continue }
            var next = StrengthSetLog(
                id: UUID(),
                setNumber: previous.setNumber + 1,
                plannedReps: previous.plannedReps,
                plannedWeightKilograms: previous.plannedWeightKilograms,
                completedReps: nil,
                completedWeightKilograms: nil,
                rpe: nil,
                completedAt: nil,
                restSeconds: 0
            )
            next.targetKind = previous.targetKind
            next.plannedDurationSeconds = previous.plannedDurationSeconds
            next.recordsWeight = previous.recordsWeight
            next.loadKind = previous.loadKind
            next.plannedResistanceLevel = previous.plannedResistanceLevel
            next.plannedRPE = previous.plannedRPE
            next.plannedRIR = previous.plannedRIR
            next.plannedTempo = previous.plannedTempo
            next.plannedSetType = previous.plannedSetType
            next.plannedNote = previous.plannedNote
            next.isWarmUp = previous.isWarmUp
            exercises[index].sets.append(next)
            exercises[index].completedAt = nil
        }
        return true
    }

    private func advanceGroupedSetIfNeeded(
        workout: inout StrengthWorkoutLog,
        completedExerciseIndex: Int,
        completedSetIndex: Int,
        automaticRestTimer: Bool,
        restSeconds: Int,
        at completedAt: Date
    ) -> Bool {
        guard workout.exercises.indices
                .contains(
                    completedExerciseIndex
                ),
              let groupID =
                workout.exercises[
                    completedExerciseIndex
                ].groupID
        else {
            return false
        }

        let groupIndices =
            workout.exercises.indices
                .filter {
                    workout.exercises[$0]
                        .groupID == groupID
                }

        guard groupIndices.count >= 2 ||
              workout.exercises[completedExerciseIndex].groupStyle == .amrap
        else { return false }

        // A completed AMRAP round creates the next round while there is
        // time remaining. This works for one station or many stations,
        // without a preset twenty-round cap.
        _ = Self.extendOpenEndedAMRAPGroupIfNeeded(
            exercises: &workout.exercises,
            groupID: groupID,
            at: completedAt
        )

        if let nextSameRound =
                groupIndices.first(
                    where: { index in
                        index !=
                            completedExerciseIndex &&
                        workout.exercises[index]
                            .sets.indices
                            .contains(
                                completedSetIndex
                            ) &&
                        !workout.exercises[index]
                            .sets[
                                completedSetIndex
                            ]
                            .isResolved
                    }
                ) {
            currentExerciseIndex =
                nextSameRound
            currentSetIndex =
                completedSetIndex
            let stationRest = workout.exercises[completedExerciseIndex].groupStationRestSeconds ?? 0
            restStartedAt = automaticRestTimer && stationRest > 0 ? completedAt : nil
            restEndsAt = restStartedAt?.addingTimeInterval(TimeInterval(stationRest))
            return true
        }

        for index in groupIndices {
            if let nextSetIndex =
                    workout.exercises[index]
                        .sets.firstIndex(
                            where: {
                                !$0.isResolved
                            }
                        ) {
                currentExerciseIndex = index
                currentSetIndex =
                    nextSetIndex
                let roundRest = workout.exercises[completedExerciseIndex].groupRoundRestSeconds ?? restSeconds
                if automaticRestTimer &&
                    roundRest > 0 {
                    let restStart = completedAt
                    restStartedAt =
                        restStart
                    restEndsAt =
                        restStart
                            .addingTimeInterval(
                                TimeInterval(
                                    roundRest
                                )
                            )
                } else {
                    restStartedAt = nil
                    restEndsAt = nil
                }
                return true
            }
        }

        return false
    }

    /// Edits only this live, iPhone-owned strength session.
    /// Watch-owned sessions receive their settings at workout launch.
    /// This never modifies saved defaults or any other sport's coach.
    func updateActiveAudioCoachConfiguration(
        _ coach: StrengthAudioCoachConfiguration
    ) {
        guard var workout = activeWorkout, workout.captureDevice == .iPhone else {
            return
        }
        var advanced = workout.advancedConfiguration ??
            StrengthAdvancedConfiguration.savedDefaults()
        guard advanced.audioCoach != coach else { return }
        advanced.audioCoach = coach
        workout.advancedConfiguration = advanced
        activeWorkout = workout
    }

    func enableAdvancedTracking() {
        guard var workout = activeWorkout else {
            return
        }

        workout.trackingMode = .advanced

        if workout.advancedConfiguration == nil {
            workout.advancedConfiguration =
                StrengthAdvancedConfiguration
                    .savedDefaults()
        }

        activeWorkout = workout
        reloadDraftFromCurrentSet()
    }

    func completeCurrentSetWithoutDetails(
        restSeconds: Int? = nil,
        completedAt: Date = Date()
    ) {
        completeCurrentSet(
            reps: nil,
            weightKilograms: nil,
            rpe: nil,
            rir: nil,
            isWarmUp: draftWarmUp,
            restSeconds: restSeconds,
            completedAt: completedAt
        )
    }

    @discardableResult
    func addExtraSetToCurrentExercise()
        -> Bool {
        guard
            var workout = activeWorkout,
            workout.exercises.indices
                .contains(
                    currentExerciseIndex
                ),
            let source =
                workout.exercises[
                    currentExerciseIndex
                ].sets.last
        else {
            return false
        }

        let targetKind =
            source.resolvedTargetKind
        let loadKind =
            source.resolvedLoadKind
        let newNumber =
            (
                workout.exercises[
                    currentExerciseIndex
                ].sets
                .map(\.setNumber)
                .max() ?? 0
            ) + 1

        let newSet =
            StrengthSetLog(
                id: UUID(),
                setNumber: newNumber,
                plannedReps:
                    targetKind == .reps
                        ? (
                            source
                                .resolvedCompletedReps ??
                            source.plannedReps ??
                            draftReps
                        )
                        : nil,
                plannedWeightKilograms:
                    loadKind ==
                        .weightKilograms
                        ? (
                            source
                                .completedWeightKilograms ??
                            source
                                .plannedWeightKilograms ??
                            draftWeightKilograms
                        )
                        : nil,
                completedReps: nil,
                completedWeightKilograms: nil,
                rpe: nil,
                completedAt: nil,
                restSeconds:
                    source.restSeconds ??
                    workout.exercises[
                        currentExerciseIndex
                    ].restSecondsOverride ??
                    draftRestSeconds,
                rir: nil,
                isWarmUp: workout.exercises[currentExerciseIndex].isWarmUpExercise,
                targetKind:
                    targetKind,
                plannedDurationSeconds:
                    targetKind == .time
                        ? (
                            source
                                .resolvedCompletedDurationSeconds ??
                            source
                                .plannedDurationSeconds ??
                            draftDurationSeconds
                        )
                        : nil,
                completedDurationSeconds:
                    nil,
                loadKind: loadKind,
                plannedResistanceLevel:
                    loadKind ==
                        .resistanceLevel
                        ? (
                            source
                                .completedResistanceLevel ??
                            source
                                .plannedResistanceLevel ??
                            draftResistanceLevel
                        )
                        : nil,
                completedResistanceLevel:
                    nil,
                completedDistanceMeters:
                    nil,
                effortSegments:
                    nil,
                actualRestAfterSeconds:
                    nil
            )

        workout.exercises[
            currentExerciseIndex
        ].sets.append(newSet)
        workout.exercises[
            currentExerciseIndex
        ].completedAt = nil
        workout.exercises[
            currentExerciseIndex
        ].transitionToNextExerciseSeconds =
            nil

        currentSetIndex =
            workout.exercises[
                currentExerciseIndex
            ].sets.count - 1

        // If this was the final exercise there may not have been a rest timer.
        // Reconstruct it from the completion time so deciding on an extra set
        // never loses the true elapsed rest.
        if restStartedAt == nil,
           let completedAt =
                source.completedAt {
            let restSeconds =
                max(
                    newSet.restSeconds ??
                        draftRestSeconds,
                    0
                )

            if restSeconds > 0 {
                restStartedAt =
                    completedAt
                restEndsAt =
                    completedAt
                        .addingTimeInterval(
                            TimeInterval(
                                restSeconds
                            )
                        )
            }
        }

        activeWorkout = workout
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
        return true
    }

    /// Leave rest only when an unresolved set may start in its real window.
    /// A user pressing Next early in an EMOM minute or during a stale Watch
    /// replay must not discard the original rest/countdown checkpoint.
    @discardableResult
    func skipRest(at date: Date = Date()) -> Bool {
        guard let set = currentSet,
              !set.isResolved,
              canCompleteCurrentStrengthMode(at: date)
        else { return false }
        finalizeActualRestIfNeeded(at: date)
        restStartedAt = nil
        restEndsAt = nil
        startCurrentSetEffort(at: date)
        persistCheckpointNow()
        return true
    }

    func addRest(seconds: Int, at date: Date = Date()) {
        guard activeWorkout != nil, seconds > 0, seconds <= 600 else { return }
        if restStartedAt == nil {
            restStartedAt = date
        }

        let base =
            max(
                restEndsAt ?? date,
                date
            )
        restEndsAt =
            base.addingTimeInterval(
                TimeInterval(seconds)
            )
        // Persist the revised deadline before the app can be suspended.
        persistCheckpointNow()
    }

    private func finalizeActualRestIfNeeded(at date: Date = Date()) {
        guard
            let restStartedAt,
            var workout = activeWorkout
        else {
            return
        }

        var candidate:
            (
                exerciseIndex: Int,
                setIndex: Int,
                completedAt: Date
            )?

        for exerciseIndex in
            workout.exercises.indices {
            for setIndex in
                workout.exercises[
                    exerciseIndex
                ].sets.indices {
                let set =
                    workout.exercises[
                        exerciseIndex
                    ].sets[setIndex]

                guard
                    let completedAt =
                        set.completedAt,
                    set.actualRestAfterSeconds ==
                        nil
                else {
                    continue
                }

                if candidate == nil ||
                    completedAt >
                        candidate!.completedAt {
                    candidate = (
                        exerciseIndex:
                            exerciseIndex,
                        setIndex:
                            setIndex,
                        completedAt:
                            completedAt
                    )
                }
            }
        }

        guard let candidate else {
            return
        }

        workout.exercises[
            candidate.exerciseIndex
        ].sets[
            candidate.setIndex
        ].actualRestAfterSeconds =
            max(
                date
                    .timeIntervalSince(
                        restStartedAt
                    ),
                0
            )

        activeWorkout = workout
    }

    /// Change the number of sets in this *active* workout only. A reduction
    /// removes unfinished planned sets, not fake "skipped" performances.
    /// Recorded efforts are protected unless the athlete explicitly confirms
    /// that the last recorded set(s) were logged by mistake.
    @discardableResult
    func adjustActiveExerciseSetCount(
        _ exerciseID: UUID,
        to requestedCount: Int,
        correctRecordedSets: Bool = false
    ) -> Bool {
        guard (1...20).contains(requestedCount),
              var workout = activeWorkout,
              let exerciseIndex = workout.exercises.firstIndex(where: {
                  $0.id == exerciseID
              })
        else { return false }

        var exercise = workout.exercises[exerciseIndex]
        let original = exercise.sets
        guard !original.isEmpty, requestedCount != original.count
        else { return false }

        let completed = original.filter(\.isCompleted)
        guard requestedCount >= completed.count || correctRecordedSets
        else { return false }

        let selectedExerciseID = currentExercise?.id
        let selectedSetID = currentSet?.id
        var updated: [StrengthSetLog]

        if requestedCount < original.count {
            // Keep every actual performance first. Any remaining capacity is
            // filled by the earliest pending sets, preserving their IDs and
            // ordering. Correcting false completed sets is a separate,
            // deliberately confirmed action.
            let keptCompleted = Array(completed.prefix(requestedCount))
            let available = max(requestedCount - keptCompleted.count, 0)
            let keptPending = Array(original.filter {
                !$0.isCompleted
            }.prefix(available))
            let keptIDs = Set((keptCompleted + keptPending).map(\.id))
            let removed = original.filter { !keptIDs.contains($0.id) }
            guard removed.count == original.count - requestedCount else {
                return false
            }

            // A currently running timed/effort set must be completed or
            // stopped before it can be deleted from the workout.
            if selectedExerciseID == exerciseID,
               let selectedSetID, !keptIDs.contains(selectedSetID),
               currentTimedSetCountdown?.isRunning == true ||
                   currentSetEffortClock != nil {
                return false
            }

            for set in removed {
                cardioWatchCaptures.removeValue(forKey: set.id)
                watchCaptureNeedsBaseline.remove(set.id)
            }
            updated = original.filter { keptIDs.contains($0.id) }
        } else {
            // An increase reuses *planning* metadata only; never duplicate
            // the previous set's recorded performance or historical ID.
            guard let template = original.last else { return false }
            updated = original
            for number in (original.count + 1)...requestedCount {
                var pending = StrengthSetLog(
                    id: UUID(),
                    setNumber: number,
                    plannedReps: template.plannedReps,
                    plannedWeightKilograms: template.plannedWeightKilograms,
                    completedReps: nil,
                    completedWeightKilograms: nil,
                    rpe: nil,
                    completedAt: nil,
                    restSeconds: template.restSeconds
                )
                pending.plannedRPE = template.plannedRPE
                pending.plannedRIR = template.plannedRIR
                pending.plannedSetType = template.plannedSetType
                pending.plannedTempo = template.plannedTempo
                pending.plannedNote = template.plannedNote
                pending.isWarmUp = exercise.isWarmUpExercise
                    ? true : nil
                pending.targetKind = template.targetKind
                pending.plannedDurationSeconds = template.plannedDurationSeconds
                pending.recordsWeight = template.recordsWeight
                pending.loadKind = template.loadKind
                pending.plannedResistanceLevel = template.plannedResistanceLevel
                pending.hybridPhaseTitle = template.hybridPhaseTitle
                pending.hybridPhaseKind = template.hybridPhaseKind
                pending.hybridTargetHeartRateZone =
                    template.hybridTargetHeartRateZone
                pending.hybridTargetPaceSecondsPerKilometer =
                    template.hybridTargetPaceSecondsPerKilometer
                updated.append(pending)
            }
        }

        // Renumber only within this live exercise. Stable set IDs preserve
        // historical completion data, progress and any actual load records.
        for index in updated.indices {
            updated[index].setNumber = index + 1
        }
        exercise.sets = updated
        exercise.completedAt = updated.allSatisfy(\.isCompleted)
            ? (exercise.completedAt ?? Date())
            : nil
        workout.exercises[exerciseIndex] = exercise

        if selectedExerciseID == exerciseID {
            // An added pending set must become the active Watch/iPhone set,
            // even if the previous selection was the last completed set.
            currentSetIndex = updated.firstIndex(where: {
                $0.id == selectedSetID && !$0.isCompleted
            }) ?? updated.firstIndex(where: {
                !$0.isCompleted
            }) ?? updated.firstIndex(where: {
                $0.id == selectedSetID
            }) ?? max(updated.count - 1, 0)

            if updated.allSatisfy(\.isCompleted) {
                timedSetCountdown = nil
                setEffortClock = nil
                restStartedAt = nil
                restEndsAt = nil
            } else if original.allSatisfy(\.isCompleted) {
                // Reopening an already finished exercise must not retain
                // its previous post-exercise rest as an active rest timer.
                restStartedAt = nil
                restEndsAt = nil
            }
        }

        activeWorkout = workout
        if selectedExerciseID == exerciseID {
            reloadDraftFromCurrentSet()
        }
        persistCheckpointNow()
        return true
    }

    /// Skip exactly the selected pending set without recording a completed
    /// effort. Plan provenance is preserved by skippedPlannedSetCount; volume,
    /// PRs and completed-set counts never increase. Safe for offline Watch
    /// replay because duplicate/stale commands are rejected by set indices.
    @discardableResult
    func skipCurrentSet() -> Bool {
        guard var workout = activeWorkout,
              workout.exercises.indices.contains(currentExerciseIndex),
              workout.exercises[currentExerciseIndex].sets.indices.contains(currentSetIndex),
              !workout.exercises[currentExerciseIndex].sets[currentSetIndex].isResolved
        else { return false }

        if workout.exercises[currentExerciseIndex].groupID != nil,
           let groupStyle = workout.exercises[currentExerciseIndex].groupStyle {
            let now = Date()
            let selectedExerciseIndex = currentExerciseIndex
            let selectedSetIndex = currentSetIndex
            let selected = workout.exercises[selectedExerciseIndex]
            let set = selected.sets[selectedSetIndex]

            // Keep the original station, round and set ID intact. Removing
            // an array entry shifts the other stations into the wrong round
            // in superset, circuit, drop-set, EMOM and AMRAP workouts.
            workout.exercises[selectedExerciseIndex]
                .sets[selectedSetIndex].skippedAt = now
            workout.exercises[selectedExerciseIndex].skippedPlannedSetCount =
                (selected.skippedPlannedSetCount ?? 0) + 1
            if workout.exercises[selectedExerciseIndex]
                .sets.allSatisfy(\.isResolved) {
                workout.exercises[selectedExerciseIndex].completedAt = now
            }

            timedSetCountdown = nil
            setEffortClock = nil
            restStartedAt = nil
            restEndsAt = nil

            if groupStyle == .emom {
                activeWorkout = workout
                // The original minute indices remain stable; only the
                // authoritative EMOM clock chooses the next live slot.
                _ = reconcileCurrentEMOM(at: now)
            } else {
                let restSeconds = max(
                    selected.restSecondsOverride ??
                        set.restSeconds ?? 0, 0
                )
                let automaticRestTimer =
                    workout.advancedConfiguration?.restCues
                        .automaticRestTimer ?? true
                let advanced = advanceGroupedSetIfNeeded(
                    workout: &workout,
                    completedExerciseIndex: selectedExerciseIndex,
                    completedSetIndex: selectedSetIndex,
                    automaticRestTimer: automaticRestTimer,
                    restSeconds: restSeconds,
                    at: now
                )
                if !advanced,
                   let nextPendingIndex =
                     workout.exercises[selectedExerciseIndex].sets
                        .firstIndex(where: { !$0.isResolved }) {
                    currentSetIndex = nextPendingIndex
                }
                activeWorkout = workout
                reloadDraftFromCurrentSet()
            }
            persistCheckpointNow()
            return true
        }

        var exercise = workout.exercises[currentExerciseIndex]
        let skipped = exercise.sets.remove(at: currentSetIndex)
        cardioWatchCaptures.removeValue(forKey: skipped.id)
        watchCaptureNeedsBaseline.remove(skipped.id)
        exercise.skippedPlannedSetCount = (exercise.skippedPlannedSetCount ?? 0) + 1
        timedSetCountdown = nil
        setEffortClock = nil
        restStartedAt = nil
        restEndsAt = nil

        let nextPending = exercise.sets.firstIndex { !$0.isCompleted }
        if let nextPending {
            currentSetIndex = nextPending
            exercise.completedAt = nil
        } else {
            // The exercise is finished or explicitly omitted. Do not count
            // an omitted set as a training effort.
            exercise.completedAt = Date()
            currentSetIndex = max(exercise.sets.count - 1, 0)
        }
        workout.exercises[currentExerciseIndex] = exercise
        _ = advanceLiveExecutionQueue(workout: &workout, automaticRestTimer: false,
                                      restSeconds: 0, at: Date())
        activeWorkout = workout
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
        return true
    }

    /// End a partially completed exercise without inventing completed
    /// repetitions or touching the scheduled plan. Only pending sets vanish
    /// from this active execution and their count remains auditable.
    @discardableResult
    func omitRemainingSetsOfCurrentExercise() -> Bool {
        guard var workout = activeWorkout,
              workout.exercises.indices.contains(currentExerciseIndex)
        else { return false }

        var exercise = workout.exercises[currentExerciseIndex]
        let completed = exercise.sets.filter { $0.isCompleted }
        let omitted = exercise.sets.count - completed.count
        guard !completed.isEmpty, omitted > 0 else { return false }

        exercise.sets = completed
        exercise.skippedPlannedSetCount = (exercise.skippedPlannedSetCount ?? 0) + omitted
        exercise.completedAt = Date()
        workout.exercises[currentExerciseIndex] = exercise
        currentSetIndex = max(completed.count - 1, 0)
        timedSetCountdown = nil
        let hasOtherPending = workout.exercises.contains {
            !$0.isCompleted
        }
        restStartedAt = hasOtherPending ? nil : Date()
        restEndsAt = nil
        activeWorkout = workout
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
        return true
    }

    func moveToNextExercise(at date: Date = Date()) {
        // Invalid Next commands cannot zero an active rest period. Validate
        // against the authoritative workout before changing any timer.
        guard currentExerciseAllSetsCompleted, hasNextExercise else { return }
        finalizeActualRestIfNeeded(at: date)
        restStartedAt = nil
        guard
            var workout = activeWorkout,
            workout.exercises.indices
                .contains(
                    currentExerciseIndex
                ),
            currentExerciseAllSetsCompleted,
            hasNextExercise
        else {
            return
        }

        let previousIndex = currentExerciseIndex
        if advanceLiveExecutionQueue(workout: &workout, automaticRestTimer: false,
                                     restSeconds: 0, at: date) {
            if let completedAt = workout.exercises[previousIndex].completedAt {
                workout.exercises[previousIndex].transitionToNextExerciseSeconds =
                    max(date.timeIntervalSince(completedAt), 0)
            }
            activeWorkout = workout
            reloadDraftFromCurrentSet()
            if currentSet?.resolvedTargetKind == .time {
                startOrResumeTimedSet(at: date)
            }
            persistCheckpointNow()
            return
        }

        let later =
            workout.exercises.indices
                .dropFirst(
                    currentExerciseIndex + 1
                )
                .first {
                    !workout.exercises[$0]
                        .isCompleted
                }
        let earlier =
            workout.exercises.indices
                .prefix(
                    currentExerciseIndex
                )
                .first {
                    !workout.exercises[$0]
                        .isCompleted
                }

        guard let nextIndex =
                later ?? earlier
        else {
            return
        }

        if let completedAt =
                workout.exercises[
                    currentExerciseIndex
                ].completedAt {
            workout.exercises[
                currentExerciseIndex
            ].transitionToNextExerciseSeconds =
                max(
                    date
                        .timeIntervalSince(
                            completedAt
                        ),
                    0
                )
        }

        Self.beginStrengthGroup(&workout, selected: nextIndex, at: date)
        currentExerciseIndex = nextIndex
        currentSetIndex =
            workout.exercises[nextIndex]
                .sets.firstIndex(
                    where: {
                        !$0.isResolved
                    }
                ) ?? 0
        restEndsAt = nil
        activeWorkout = workout
        reloadDraftFromCurrentSet()
        if currentSet?.resolvedTargetKind == .time {
            startOrResumeTimedSet(at: date)
        }
        persistCheckpointNow()
    }

    @discardableResult
    func finish(
        healthKitWorkoutUUID: UUID? = nil,
        duration: TimeInterval? = nil,
        activeCalories: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        completedAt: Date? = nil
    ) -> Bool {
        guard let currentWorkout = activeWorkout else { return false }
        // Only a phone-owned strength journal is mutable through this
        // phone lifecycle gate. Watch-owned strength still finishes through
        // its existing Watch-authoritative result reconciliation.
        if currentWorkout.captureDevice == .iPhone {
            guard let state = activeSessionState,
                  ATHLTHUniversalWorkoutLifecycle.permits(
                      .finish,
                      state: ATHLTHUniversalActiveCapture.recorded(
                          state, source: .strength
                      ),
                      expectedWorkoutID: currentWorkout.id
                  ) else { return false }
        }
        // When the Watch owns HealthKit, its recorded end is authoritative.
        // Local Finish still defaults to the actual tap time.
        let finishDate = completedAt ?? Date()
        finalizeActualRestIfNeeded(at: finishDate)
        restStartedAt = nil
        restEndsAt = nil

        guard var workout = activeWorkout else { return false }
        completionSaveError = nil

        // A restored phone workout was suspended at its last checkpoint.
        // Closing it without pressing Resume must not count the offline
        // hours as active elapsed workout time.
        if workout.captureDevice == .iPhone,
           let suspended = recoveredCheckpointSavedAt {
            workout.recordRecoveredDowntime(
                from: suspended, until: finishDate
            )
        }

        // A restored checkpoint can be hours old. Its save timestamp
        // must not truncate the real workout's duration on completion.
        workout.liveExecutionQueue = nil
        workout.endedAt = ATHLTHWorkoutSessionFoundation.completionTimestamp(
            startedAt: workout.startedAt,
            finishedAt: finishDate
        )

        let existingMetrics = workout.healthMetrics
        workout.healthMetrics = LinkedHealthWorkoutMetrics(
            healthKitWorkoutUUID:
                healthKitWorkoutUUID ?? existingMetrics.healthKitWorkoutUUID,
            duration:
                duration ?? existingMetrics.duration,
            activeCalories:
                activeCalories ?? existingMetrics.activeCalories,
            averageHeartRate:
                averageHeartRate ?? existingMetrics.averageHeartRate,
            maxHeartRate:
                maxHeartRate ?? existingMetrics.maxHeartRate
        )

        guard let accountID,
              !UserDefaults.standard.bool(forKey: AccountLocalStorage.key("deleted", userID: accountID))
        else {
            completionSaveError = ATHLTHLocalization.choose(
                english: "Could not save this strength workout to an account. Your workout remains open.",
                norwegian: "Kunne ikke lagre styrkeøkten på en konto. Økten holdes åpen."
            )
            return false
        }

        var updatedHistory = workoutHistory.filter { $0.id != workout.id }
        updatedHistory.append(workout)
        updatedHistory.sort { $0.startedAt > $1.startedAt }
        do {
            try StrengthWorkoutCompletionJournal.save(workout, userID: accountID)
            try AccountLocalStorage.writeChecked(
                updatedHistory, name: "strengthHistory", userID: accountID
            )
        } catch {
            // Never discard the in-progress sets until durable storage succeeds.
            completionSaveError = ATHLTHLocalization.choose(
                english: "Could not save the strength workout. It is still open; try finishing again.",
                norwegian: "Styrkeøkten kunne ikke lagres. Den er fortsatt åpen; prøv å avslutte igjen."
            )
            return false
        }

        completedWorkout = workout
        setEffortClock = nil
        cardioWatchCaptures = [:]
        watchCaptureNeedsBaseline = []
        workoutHistory = updatedHistory
        ATHLTHTrainingDataChangeSignal.post(userID: accountID)
        activeWorkout = nil
        isFreeTrainingBetweenExercises = false
        recoveredCheckpointSavedAt = nil
        restEndsAt = nil
        restStartedAt = nil
        currentExerciseIndex = 0
        currentSetIndex = 0
        draftReps = 8
        draftDurationSeconds = 60
        draftWeightKilograms = 20
        draftTreadmillSpeedKilometersPerHour = 0
        draftTreadmillInclinePercent = 0
        draftResistanceLevel = 5
        draftRestSeconds = 90
        draftRPE = 8
        draftRIR = 2
        draftWarmUp = false
        timedSetCountdown = nil
        persistCheckpointNow()
        return true
    }

    func acknowledgeRecoveredWorkout() {
        guard var workout = activeWorkout,
              let suspended = recoveredCheckpointSavedAt
        else { return }

        if workout.captureDevice == .iPhone {
            workout.recordRecoveredDowntime(
                from: suspended, until: Date()
            )
            activeWorkout = workout
        }
        recoveredCheckpointSavedAt = nil
        persistCheckpointNow()
    }

    func discardActiveWorkout() {
        guard activeWorkout != nil else {
            return
        }

        checkpointSaveTask?.cancel()
        checkpointSaveTask = nil
        activeWorkout = nil
        isFreeTrainingBetweenExercises = false
        recoveredCheckpointSavedAt = nil
        currentExerciseIndex = 0
        currentSetIndex = 0
        restEndsAt = nil
        restStartedAt = nil
        draftReps = 8
        draftDurationSeconds = 60
        draftWeightKilograms = 20
        draftTreadmillSpeedKilometersPerHour = 0
        draftTreadmillInclinePercent = 0
        draftResistanceLevel = 5
        draftRestSeconds = 90
        draftRPE = 8
        draftRIR = 2
        draftWarmUp = false
        timedSetCountdown = nil
        setEffortClock = nil
        persistCheckpointNow()
    }

    func goalEvidence(
        for rule: GoalAutomationRule,
        since startDate: Date
    ) -> GoalAutomationEvidence? {
        guard rule.metric == .strengthWeightKilograms,
              let exerciseName = rule.exerciseName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              !exerciseName.isEmpty
        else {
            return nil
        }

        var best: (weight: Double, date: Date)?

        for workout in workoutHistory where workout.startedAt >= startDate && workout.isFinished {
            for exercise in workout.exercises
            where exercise.exercise.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == exerciseName {
                for set in exercise.sets {
                    guard set.countsTowardTrainingLoad,
                          let weight = set.completedWeightKilograms,
                          weight > 0
                    else {
                        continue
                    }

                    let date = set.completedAt ?? workout.endedAt ?? workout.startedAt

                    if best.map({ weight > $0.weight }) ?? true {
                        best = (weight, date)
                    }
                }
            }
        }

        guard let best else { return nil }

        return GoalAutomationEvidence(
            currentValue: best.weight,
            evidenceDate: best.date,
            description: "\(Self.formattedKilograms(best.weight)) kg · \(rule.exerciseName ?? "Strength")"
        )
    }

    /// A late HealthKit save must update the exact finished session only,
    /// never whichever workout happens to be on screen when it returns.
    @discardableResult
    func attachFinishedWorkoutHealthKitUUID(
        _ uuid: UUID,
        workoutID: UUID,
        ownerID: UUID
    ) -> Bool {
        // A HealthKit builder can finish after a new session has started
        // or a different athlete has signed in. Never attach its UUID to
        // anything except its durable phone-owned workout identity.
        guard accountID == ownerID,
              !UserDefaults.standard.bool(
                  forKey: AccountLocalStorage.key("deleted", userID: ownerID)
              ),
              let index = workoutHistory.firstIndex(where: {
                  $0.id == workoutID &&
                  $0.isFinished &&
                  $0.captureDevice == .iPhone
              })
        else { return false }

        // The same HealthKit workout may not be claimed by two different
        // strength sessions, even when callbacks arrive after a later finish.
        guard !workoutHistory.contains(where: {
            $0.id != workoutID &&
            $0.healthMetrics.healthKitWorkoutUUID == uuid
        }) else { return false }

        var updated = workoutHistory
        var saved = updated[index]
        if let alreadyLinked = saved.healthMetrics.healthKitWorkoutUUID {
            // Repeated delivery is idempotent; a different HealthKit
            // workout can never replace previously linked evidence.
            return alreadyLinked == uuid
        }
        saved.healthMetrics.healthKitWorkoutUUID = uuid
        updated[index] = saved
        do {
            try AccountLocalStorage.writeChecked(
                updated, name: "strengthHistory", userID: ownerID
            )
        } catch {
            // Keep the original saved state so a retry can safely reattach.
            return false
        }
        workoutHistory = updated
        if completedWorkout?.id == workoutID {
            completedWorkout = saved
        }
        // This receipt is a LAST-completion recovery record, not a second
        // history store. Never replace a newer workout with an older one.
        if StrengthWorkoutCompletionJournal.read(userID: ownerID)?.id == workoutID {
            try? StrengthWorkoutCompletionJournal.save(saved, userID: ownerID)
        }
        ATHLTHTrainingDataChangeSignal.post(userID: ownerID)
        return true
    }

    /// Backfilled Watch metrics belong to their exact completed history
    /// entry. Never attach them to an unrelated newer active workout, and
    /// never replace another Watch workout's existing HealthKit UUID.
    @discardableResult
    func attachFinishedWatchMetrics(
        _ metrics: LinkedHealthWorkoutMetrics,
        workoutID: UUID,
        ownerID: UUID
    ) -> Bool {
        guard accountID == ownerID,
              let index = workoutHistory.firstIndex(where: {
                  $0.id == workoutID &&
                  $0.isFinished &&
                  $0.captureDevice == .appleWatch
              }),
              !UserDefaults.standard.bool(
                  forKey: AccountLocalStorage.key("deleted", userID: ownerID)
              ) else { return false }
        // A delayed Watch packet cannot erase already-linked HealthKit
        // evidence, steal another workout's UUID, or replace it with a new
        // recording. Reject missing UUID once a recording has been linked.
        let incomingUUID = metrics.healthKitWorkoutUUID
        if let incomingUUID,
           workoutHistory.contains(where: {
               $0.id != workoutID &&
               $0.healthMetrics.healthKitWorkoutUUID == incomingUUID
           }) { return false }
        var updated = workoutHistory
        var finished = updated[index]
        if let existing = finished.healthMetrics.healthKitWorkoutUUID,
           existing != incomingUUID { return false }
        finished.healthMetrics = metrics
        updated[index] = finished
        do {
            try AccountLocalStorage.writeChecked(
                updated, name: "strengthHistory", userID: ownerID
            )
        } catch {
            return false
        }
        workoutHistory = updated
        if completedWorkout?.id == workoutID {
            completedWorkout = finished
        }
        // Do not replace the most recent journal with an older completion.
        if StrengthWorkoutCompletionJournal.read(userID: ownerID)?.id == workoutID {
            try? StrengthWorkoutCompletionJournal.save(finished, userID: ownerID)
        }
        ATHLTHTrainingDataChangeSignal.post(userID: ownerID)
        return true
    }

    func attachHealthMetrics(_ metrics: LinkedHealthWorkoutMetrics) {
        if var activeWorkout {
            activeWorkout.healthMetrics = metrics
            self.activeWorkout = activeWorkout
            return
        }

        if var completedWorkout {
            completedWorkout.healthMetrics = metrics
            self.completedWorkout = completedWorkout
            upsertWorkoutHistory(completedWorkout)
        }
    }

    func removeWorkoutFromHistory(
        matching workoutIDs: Set<UUID>
    ) {
        guard !workoutIDs.isEmpty else {
            return
        }

        if let accountID,
           let receipt = StrengthWorkoutCompletionJournal.read(userID: accountID),
           workoutIDs.contains(receipt.id) ||
           receipt.healthMetrics.healthKitWorkoutUUID.map(workoutIDs.contains) == true {
            StrengthWorkoutCompletionJournal.remove(userID: accountID)
        }
        workoutHistory.removeAll { workout in
            workoutIDs.contains(workout.id) ||
            workout.healthMetrics
                .healthKitWorkoutUUID
                .map(workoutIDs.contains) == true
        }

        if let completedWorkout,
           workoutIDs.contains(completedWorkout.id) ||
            completedWorkout.healthMetrics
                .healthKitWorkoutUUID
                .map(workoutIDs.contains) == true {
            self.completedWorkout = nil
        }

        persistWorkoutHistory()
    }

    private func upsertWorkoutHistory(_ workout: StrengthWorkoutLog) {
        if let index = workoutHistory.firstIndex(where: { $0.id == workout.id }) {
            workoutHistory[index] = workout
        } else {
            workoutHistory.append(workout)
        }

        workoutHistory.sort { $0.startedAt > $1.startedAt }
        persistWorkoutHistory()
    }

    private func persistWorkoutHistory() {
        guard let accountID else { return }
        AccountLocalStorage.write(workoutHistory, name: "strengthHistory", userID: accountID)
        ATHLTHTrainingDataChangeSignal.post(userID: accountID)
    }

    private static func loadWorkoutHistory() -> [StrengthWorkoutLog] {
        guard let url = workoutHistoryURL,
              let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode([StrengthWorkoutLog].self, from: data)
        else {
            return []
        }

        return history.sorted { $0.startedAt > $1.startedAt }
    }

    private static var workoutHistoryURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("strength-workout-history.json", isDirectory: false)
    }

    private static func repWeightEfforts(
        in set: StrengthSetLog,
        includeBodyweight: Bool
    ) -> [(reps: Int, weight: Double)] {
        if let segments =
                set.effortSegments,
           !segments.isEmpty {
            return segments.compactMap {
                segment in

                guard let reps =
                        segment.reps,
                      reps > 0
                else {
                    return nil
                }

                let weight =
                    max(
                        segment
                            .weightKilograms ??
                        0,
                        0
                    )

                if !includeBodyweight &&
                    weight <= 0 {
                    return nil
                }

                return (
                    reps: reps,
                    weight: weight
                )
            }
        }

        guard let reps =
                set.completedReps,
              reps > 0
        else {
            return []
        }

        let weight =
            max(
                set.completedWeightKilograms ??
                0,
                0
            )

        if !includeBodyweight &&
            weight <= 0 {
            return []
        }

        return [
            (
                reps: reps,
                weight: weight
            )
        ]
    }

    private static func formattedKilograms(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return String(Int(rounded))
        }

        return String(format: "%.1f", value)
    }

    private func advanceSetIndex(in exercise: StrengthExerciseLog) {
        if let nextIndex = exercise.sets.indices.first(where: { index in
            index > currentSetIndex && !exercise.sets[index].isCompleted
        }) {
            currentSetIndex = nextIndex
        }
    }
}
