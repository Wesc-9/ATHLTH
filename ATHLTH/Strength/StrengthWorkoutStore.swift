import Foundation

enum StrengthDraftMutationOrigin {
    case iPhone
    case watch
}

@MainActor
final class StrengthWorkoutStore: ObservableObject {
    @Published private(set) var activeWorkout: StrengthWorkoutLog? { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var currentExerciseIndex = 0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var currentSetIndex = 0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var restEndsAt: Date? { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftReps = 8 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftDurationSeconds = 60 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftWeightKilograms = 20.0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftResistanceLevel = 5 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftRestSeconds = 90 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftRPE = 8.0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftRIR = 2.0 { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var draftWarmUp = false { didSet { scheduleCheckpointPersist() } }
    @Published private(set) var completedWorkout: StrengthWorkoutLog?
    @Published private(set) var workoutHistory: [StrengthWorkoutLog] = []
    @Published private(set) var lastPhoneDraftMutationAt:
        Date = .distantPast

    private var accountID: UUID?
    private var loadingAccount = false
    private var checkpointSaveTask: Task<Void, Never>?
    @Published private(set) var hasLegacyHistory = false

    private struct Checkpoint: Codable {
        var workout: StrengthWorkoutLog?
        var exerciseIndex: Int
        var setIndex: Int
        var restEndsAt: Date?
        var reps: Int
        var durationSeconds: Int? = nil
        var weight: Double
        var resistanceLevel: Int? = nil
        var rest: Int
        var rpe: Double
        var rir: Double? = nil
        var warmUp: Bool? = nil
    }

    init() {}

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        checkpointSaveTask?.cancel()
        checkpointSaveTask = nil
        loadingAccount = true
        defer { loadingAccount = false }
        accountID = userID
        completedWorkout = nil
        workoutHistory = userID.flatMap { AccountLocalStorage.read([StrengthWorkoutLog].self, name: "strengthHistory", userID: $0) } ?? []
        let checkpoint = userID.flatMap { AccountLocalStorage.read(Checkpoint.self, name: "strengthActive", userID: $0) }
        activeWorkout = checkpoint?.workout
        if let workout = activeWorkout, workoutHistory.contains(where: { $0.id == workout.id }) { activeWorkout = nil }
        currentExerciseIndex = checkpoint?.exerciseIndex ?? 0
        currentSetIndex = checkpoint?.setIndex ?? 0
        restEndsAt = checkpoint?.restEndsAt
        draftReps = checkpoint?.reps ?? 8
        draftDurationSeconds =
            checkpoint?.durationSeconds ?? 60
        draftWeightKilograms = checkpoint?.weight ?? 20
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
        hasLegacyHistory = userID != nil && UserDefaults.standard.string(forKey: "legacy.strengthClaimedBy") == nil && !Self.loadWorkoutHistory().isEmpty
    }

    func restoreLegacyHistory() {
        guard let accountID, hasLegacyHistory else { return }
        let ids = Set(workoutHistory.map(\.id))
        workoutHistory += Self.loadWorkoutHistory().filter { !ids.contains($0.id) }
        workoutHistory.sort { $0.startedAt > $1.startedAt }
        persistWorkoutHistory()
        UserDefaults.standard.set(accountID.uuidString, forKey: "legacy.strengthClaimedBy")
        hasLegacyHistory = false
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
        guard let accountID, !loadingAccount else { return }

        checkpointSaveTask?.cancel()
        checkpointSaveTask = nil

        AccountLocalStorage.write(
            Checkpoint(
                workout: activeWorkout,
                exerciseIndex: currentExerciseIndex,
                setIndex: currentSetIndex,
                restEndsAt: restEndsAt,
                reps: draftReps,
                durationSeconds: draftDurationSeconds,
                weight: draftWeightKilograms,
                resistanceLevel: draftResistanceLevel,
                rest: draftRestSeconds,
                rpe: draftRPE,
                rir: draftRIR,
                warmUp: draftWarmUp
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

    var isResting: Bool {
        guard let restEndsAt else { return false }
        return restEndsAt > Date()
    }

    var currentExerciseAllSetsCompleted: Bool {
        guard let exercise = currentExercise else { return false }
        return !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted)
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

    func setDraft(
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        weightKilograms: Double? = nil,
        resistanceLevel: Int? = nil,
        restSeconds: Int? = nil,
        rpe: Double? = nil,
        rir: Double? = nil,
        warmUp: Bool? = nil,
        origin:
            StrengthDraftMutationOrigin =
                .iPhone
    ) {
        if let reps {
            draftReps = max(reps, 0)
        }

        if let durationSeconds {
            draftDurationSeconds =
                min(
                    max(durationSeconds, 15),
                    7_200
                )
        }

        if let weightKilograms {
            draftWeightKilograms = max(weightKilograms, 0)
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
        guard let set = currentSet else {
            draftReps = 8
            draftDurationSeconds = 60
            draftWeightKilograms = 20
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
        draftRPE = set.rpe ?? 8
        draftRIR = set.rir ?? 2
        draftWarmUp = set.isWarmUp ?? false
    }

    var watchSnapshot: WatchStrengthSessionSnapshot? {
        guard let workout = activeWorkout else {
            return nil
        }

        let exercise = currentExercise
        let set = currentSet
        let totalSets =
            workout.exercises
                .flatMap(\.sets)
                .count
        let allExercisesComplete =
            !workout.exercises.isEmpty &&
            workout.exercises.allSatisfy(\.isCompleted)

        return WatchStrengthSessionSnapshot(
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
            draftReps: draftReps,
            draftWeightKilograms: draftWeightKilograms,
            draftRestSeconds: draftRestSeconds,
            draftDurationSeconds: draftDurationSeconds,
            draftResistanceLevel: draftResistanceLevel,
            targetKindRaw:
                set?.resolvedTargetKind.rawValue,
            loadKindRaw:
                set?.resolvedLoadKind.rawValue,
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
                                        weightKilograms:
                                            set.plannedWeightKilograms,
                                        resistanceLevel:
                                            set.plannedResistanceLevel,
                                        restSeconds:
                                            set.restSeconds,
                                        isWarmUp:
                                            set.isWarmUp
                                    )
                                }
                        )
                    },
            startedAt:
                workout.startedAt,
            plannedSessionID:
                workout.plannedSessionID,
            allowsLiveExerciseBuilding:
                workout
                    .allowsLiveExerciseBuilding
        )
    }

    func startFromWatchSnapshot(
        _ snapshot:
            WatchStrengthSessionSnapshot,
        watchSessionID: UUID? = nil
    ) {
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
                        completedAt: nil
                    )
                }

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
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
    }

    func replayOfflineWatchCommands(
        _ commands:
            [WatchStrengthCommand]
    ) {
        for command in commands
            .sorted(by: {
                $0.sentAt < $1.sentAt
            }) {
            guard let workout =
                    activeWorkout
            else {
                return
            }

            if let workoutID =
                    command.workoutID,
               workoutID != workout.id {
                continue
            }

            switch command.kind {
            case .requestSnapshot:
                continue

            case .updateDraft:
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

                if currentSet?.isCompleted ==
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
                        draftRestSeconds
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

                if currentSet?.isCompleted !=
                    true {
                    if let rest =
                            command.restSeconds {
                        setDraft(
                            restSeconds: rest,
                            origin: .watch
                        )
                    }
                    completeCurrentSetWithoutDetails(
                        restSeconds:
                            draftRestSeconds
                    )
                }

            case .skipRest:
                skipRest()

            case .addRest:
                addRest(
                    seconds:
                        command
                            .addRestSeconds ??
                        30
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
                    moveToNextExercise()
                }
            }
        }

        persistCheckpointNow()
    }

    func startFreestyle(
        watchSessionID: UUID?,
        trackingMode: StrengthTrackingMode = .advanced,
        captureDevice: WorkoutCaptureDevice = .iPhone,
        advancedConfiguration:
            StrengthAdvancedConfiguration? = nil
    ) {
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
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
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
        warmUpSets: Int = 0
    ) {
        guard var workout = activeWorkout else { return }

        let resolvedTargetKind =
            targetKind ??
            exercise
                .snapshot
                .defaultStrengthTargetKind
        let resolvedLoadKind =
            loadKind ??
            exercise
                .snapshot
                .defaultStrengthLoadKind
        let setCount = max(sets, 1)
        let log = StrengthExerciseLog(
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
                    restSeconds: restSeconds,
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
                        resolvedTargetKind == .time
                            ? max(
                                targetDurationSeconds ??
                                    exercise
                                        .snapshot
                                        .defaultStrengthTargetDurationSeconds,
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

        let wasEmpty = workout.exercises.isEmpty
        workout.exercises.append(log)
        activeWorkout = workout

        if wasEmpty {
            currentExerciseIndex = 0
            currentSetIndex = 0
            restEndsAt = nil
            reloadDraftFromCurrentSet()
        }
    }

    func start(
        session: PlannedSession,
        watchSessionID: UUID?,
        trackingMode: StrengthTrackingMode,
        captureDevice: WorkoutCaptureDevice,
        advancedConfiguration:
            StrengthAdvancedConfiguration? = nil
    ) {
        let exerciseLogs = session.exercises.map { planned in
            let setCount = max(planned.sets, 1)

            return StrengthExerciseLog(
                id: UUID(),
                plannedExerciseID: planned.id,
                exercise: planned.embeddedExercise,
                sets: (1...setCount).map { setNumber in
                    StrengthSetLog(
                        id: UUID(),
                        setNumber: setNumber,
                        plannedReps:
                            planned.resolvedTargetReps,
                        plannedWeightKilograms:
                            planned.resolvedLoadKind == .weightKilograms
                                ? planned.targetWeightKilograms
                                : nil,
                        completedReps: nil,
                        completedWeightKilograms: nil,
                        rpe: nil,
                        completedAt: nil,
                        restSeconds: planned.restSeconds,
                        targetKind:
                            planned.resolvedTargetKind,
                        plannedDurationSeconds:
                            planned.resolvedTargetDurationSeconds,
                        loadKind:
                            planned.resolvedLoadKind,
                        plannedResistanceLevel:
                            planned.resolvedTargetResistanceLevel
                    )
                },
                completedAt: nil
            )
        }

        activeWorkout = StrengthWorkoutLog(
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

        currentExerciseIndex = 0
        currentSetIndex = 0
        restEndsAt = nil
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
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
        restSeconds: Int? = nil
    ) {
        guard
            var workout = activeWorkout,
            workout.exercises.indices.contains(currentExerciseIndex),
            workout.exercises[currentExerciseIndex].sets.indices.contains(currentSetIndex)
        else {
            return
        }

        var set = workout.exercises[currentExerciseIndex].sets[currentSetIndex]
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
        set.completedAt = Date()

        workout.exercises[currentExerciseIndex].sets[currentSetIndex] = set

        let allSetsCompleted = workout.exercises[currentExerciseIndex].sets.allSatisfy(\.isCompleted)

        if allSetsCompleted {
            workout.exercises[currentExerciseIndex].completedAt = Date()
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

        if advanceGroupedSetIfNeeded(
            workout: &workout,
            completedExerciseIndex:
                currentExerciseIndex,
            completedSetIndex:
                currentSetIndex,
            automaticRestTimer:
                automaticRestTimer,
            restSeconds:
                resolvedRestSeconds
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
            restEndsAt =
                hasNextExercise &&
                automaticRestTimer &&
                resolvedRestSeconds > 0
                    ? Date()
                        .addingTimeInterval(
                            TimeInterval(
                                resolvedRestSeconds
                            )
                        )
                    : nil
        } else {
            restEndsAt =
                automaticRestTimer &&
                resolvedRestSeconds > 0
                    ? Date()
                        .addingTimeInterval(
                            TimeInterval(
                                resolvedRestSeconds
                            )
                        )
                    : nil
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

    func completeCurrentDraftSet() {
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

        completeCurrentSet(
            reps:
                targetKind == .reps
                    ? draftReps
                    : nil,
            durationSeconds:
                targetKind == .time
                    ? draftDurationSeconds
                    : nil,
            weightKilograms:
                loadKind == .weightKilograms
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
                draftRestSeconds
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
        activeWorkout = workout
        reloadDraftFromCurrentSet()
    }

    func progressionSuggestion(
        for exercise:
            StrengthExerciseLog
    ) -> StrengthProgressionSuggestion? {
        let name =
            exercise.exercise.name
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .lowercased()

        guard !name.isEmpty,
              exercise.sets.first?.resolvedTargetKind != .time,
              exercise.sets.first?.resolvedLoadKind != .resistanceLevel
        else {
            return nil
        }

        let targetReps =
            exercise.sets
                .first {
                    $0.plannedReps != nil
                }?
                .plannedReps ??
            draftReps

        let previousExercise = workoutHistory
            .filter(\.isFinished)
            .sorted { $0.startedAt > $1.startedAt }
            .lazy
            .flatMap(\.exercises)
            .first { $0.exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name
                && $0.sets.contains { $0.countsTowardTrainingLoad } }
        guard let previousExercise else { return nil }
        return AthleteStrengthProgression.suggestion(sets: previousExercise.sets, targetReps: targetReps)
    }

    private func advanceGroupedSetIfNeeded(
        workout: inout StrengthWorkoutLog,
        completedExerciseIndex: Int,
        completedSetIndex: Int,
        automaticRestTimer: Bool,
        restSeconds: Int
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

        guard groupIndices.count >= 2 else {
            return false
        }

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
                            .isCompleted
                    }
                ) {
            currentExerciseIndex =
                nextSameRound
            currentSetIndex =
                completedSetIndex
            restEndsAt = nil
            return true
        }

        for index in groupIndices {
            if let nextSetIndex =
                    workout.exercises[index]
                        .sets.firstIndex(
                            where: {
                                !$0.isCompleted
                            }
                        ) {
                currentExerciseIndex = index
                currentSetIndex =
                    nextSetIndex
                restEndsAt =
                    automaticRestTimer &&
                    restSeconds > 0
                        ? Date()
                            .addingTimeInterval(
                                TimeInterval(
                                    restSeconds
                                )
                            )
                        : nil
                return true
            }
        }

        return false
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
        restSeconds: Int? = nil
    ) {
        completeCurrentSet(
            reps: nil,
            weightKilograms: nil,
            rpe: nil,
            rir: nil,
            isWarmUp: draftWarmUp,
            restSeconds: restSeconds
        )
    }

    func skipRest() {
        restEndsAt = nil
    }

    func addRest(seconds: Int) {
        let base = max(restEndsAt ?? Date(), Date())
        restEndsAt = base.addingTimeInterval(TimeInterval(max(seconds, 0)))
    }

    func moveToNextExercise() {
        guard
            var workout = activeWorkout,
            workout.exercises.indices
                .contains(
                    currentExerciseIndex
                ),
            workout.exercises[
                currentExerciseIndex
            ].sets.allSatisfy(\.isCompleted),
            hasNextExercise
        else {
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
                    Date()
                        .timeIntervalSince(
                            completedAt
                        ),
                    0
                )
        }

        currentExerciseIndex = nextIndex
        currentSetIndex =
            workout.exercises[nextIndex]
                .sets.firstIndex(
                    where: {
                        !$0.isCompleted
                    }
                ) ?? 0
        restEndsAt = nil
        activeWorkout = workout
        reloadDraftFromCurrentSet()
        persistCheckpointNow()
    }

    func finish(
        healthKitWorkoutUUID: UUID? = nil,
        duration: TimeInterval? = nil,
        activeCalories: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil
    ) {
        guard var workout = activeWorkout else { return }

        workout.endedAt = Date()

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

        completedWorkout = workout
        upsertWorkoutHistory(workout)
        activeWorkout = nil
        restEndsAt = nil
        currentExerciseIndex = 0
        currentSetIndex = 0
        draftReps = 8
        draftDurationSeconds = 60
        draftWeightKilograms = 20
        draftResistanceLevel = 5
        draftRestSeconds = 90
        draftRPE = 8
        draftRIR = 2
        draftWarmUp = false
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
