import Foundation

@MainActor
final class StrengthWorkoutStore: ObservableObject {
    @Published private(set) var activeWorkout: StrengthWorkoutLog?
    @Published private(set) var currentExerciseIndex = 0
    @Published private(set) var currentSetIndex = 0
    @Published private(set) var restEndsAt: Date?
    @Published private(set) var completedWorkout: StrengthWorkoutLog?
    @Published private(set) var workoutHistory: [StrengthWorkoutLog] = []

    init() {
        workoutHistory = Self.loadWorkoutHistory()
    }

    func trophySnapshot() -> TrophyStrengthSnapshot {
        let completed = workoutHistory
            .filter(\.isFinished)
            .sorted { $0.startedAt < $1.startedAt }

        let thresholds = [10, 25, 50, 100]
        var reachedAt: [Int: Date] = [:]

        for (index, workout) in completed.enumerated() {
            let count = index + 1
            if thresholds.contains(count) {
                reachedAt[count] = workout.endedAt ?? workout.startedAt
            }
        }

        let firstWeightedSetDate = completed
            .flatMap { workout in
                workout.exercises.flatMap { exercise in
                    exercise.sets.compactMap { set -> Date? in
                        guard set.isCompleted,
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

        return TrophyStrengthSnapshot(
            completedWorkoutCount: completed.count,
            workoutCountReachedAt: reachedAt,
            firstWeightedSetDate: firstWeightedSetDate
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

                for set in exercise.sets {
                    guard set.isCompleted,
                          let weight = set.completedWeightKilograms,
                          let reps = set.completedReps,
                          weight > 0,
                          reps > 0
                    else {
                        continue
                    }

                    let completedAt = set.completedAt ?? workout.endedAt ?? workout.startedAt

                    if let existing = bestSetByExercise[key] {
                        if weight > existing.weight ||
                            (weight == existing.weight && reps > existing.reps) {
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
                        let estimatedOneRepMax = weight * (1 + Double(reps) / 30.0)
                        if bestEstimatedOneRepMax.map({
                            estimatedOneRepMax > $0.value
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

                for set in exercise.sets {
                    guard set.isCompleted,
                          let weight = set.completedWeightKilograms,
                          let reps = set.completedReps,
                          weight > 0,
                          reps > 0,
                          reps <= 20
                    else {
                        continue
                    }

                    let date =
                        set.completedAt ??
                        workout.endedAt ??
                        workout.startedAt
                    let key = "\(normalizedExercise)|\(reps)"
                    let candidate = Candidate(
                        exerciseName: exerciseName,
                        weightKilograms: weight,
                        reps: reps,
                        date: date,
                        workoutID: workout.id
                    )

                    if let existing = bestByExerciseAndReps[key] {
                        if weight > existing.weightKilograms ||
                            (
                                weight == existing.weightKilograms &&
                                date > existing.date
                            ) {
                            bestByExerciseAndReps[key] = candidate
                        }
                    } else {
                        bestByExerciseAndReps[key] = candidate
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
        guard let workout = activeWorkout else { return false }
        return currentExerciseIndex + 1 < workout.exercises.count
    }

    func startFreestyle(
        watchSessionID: UUID?,
        trackingMode: StrengthTrackingMode = .advanced,
        captureDevice: WorkoutCaptureDevice = .iPhone
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
            )
        )

        currentExerciseIndex = 0
        currentSetIndex = 0
        restEndsAt = nil
    }

    func appendExercise(
        _ exercise: Exercise,
        sets: Int = 3,
        reps: Int? = 8,
        targetWeightKilograms: Double? = nil,
        restSeconds: Int? = 90
    ) {
        guard var workout = activeWorkout else { return }

        let setCount = max(sets, 1)
        let log = StrengthExerciseLog(
            id: UUID(),
            plannedExerciseID: nil,
            exercise: exercise.snapshot,
            sets: (1...setCount).map { number in
                StrengthSetLog(
                    id: UUID(),
                    setNumber: number,
                    plannedReps: reps,
                    plannedWeightKilograms: targetWeightKilograms,
                    completedReps: nil,
                    completedWeightKilograms: nil,
                    rpe: nil,
                    completedAt: nil,
                    restSeconds: restSeconds
                )
            },
            completedAt: nil
        )

        let wasEmpty = workout.exercises.isEmpty
        workout.exercises.append(log)
        workout.trackingMode = .advanced
        activeWorkout = workout

        if wasEmpty {
            currentExerciseIndex = 0
            currentSetIndex = 0
            restEndsAt = nil
        }
    }

    func start(
        session: PlannedSession,
        watchSessionID: UUID?,
        trackingMode: StrengthTrackingMode,
        captureDevice: WorkoutCaptureDevice
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
                        plannedReps: planned.reps,
                        plannedWeightKilograms: planned.targetWeightKilograms,
                        completedReps: nil,
                        completedWeightKilograms: nil,
                        rpe: nil,
                        completedAt: nil,
                        restSeconds: planned.restSeconds
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
            )
        )

        currentExerciseIndex = 0
        currentSetIndex = 0
        restEndsAt = nil
    }

    func completeCurrentSet(
        reps: Int?,
        weightKilograms: Double?,
        rpe: Double?
    ) {
        guard
            var workout = activeWorkout,
            workout.exercises.indices.contains(currentExerciseIndex),
            workout.exercises[currentExerciseIndex].sets.indices.contains(currentSetIndex)
        else {
            return
        }

        var set = workout.exercises[currentExerciseIndex].sets[currentSetIndex]
        set.completedReps = reps.map { max($0, 0) }
        set.completedWeightKilograms = weightKilograms.map { max($0, 0) }
        set.rpe = rpe
        set.completedAt = Date()

        workout.exercises[currentExerciseIndex].sets[currentSetIndex] = set

        let allSetsCompleted = workout.exercises[currentExerciseIndex].sets.allSatisfy(\.isCompleted)

        if allSetsCompleted {
            workout.exercises[currentExerciseIndex].completedAt = Date()
            restEndsAt = nil
        } else {
            let restSeconds = max(set.restSeconds ?? 0, 0)
            restEndsAt = restSeconds > 0 ? Date().addingTimeInterval(TimeInterval(restSeconds)) : nil
            advanceSetIndex(in: workout.exercises[currentExerciseIndex])
        }

        activeWorkout = workout
    }

    func enableAdvancedTracking() {
        guard var workout = activeWorkout else { return }
        workout.trackingMode = .advanced
        activeWorkout = workout
    }

    func completeCurrentSetWithoutDetails() {
        completeCurrentSet(
            reps: nil,
            weightKilograms: nil,
            rpe: nil
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
            workout.exercises.indices.contains(currentExerciseIndex),
            workout.exercises[currentExerciseIndex].sets.allSatisfy(\.isCompleted),
            hasNextExercise
        else {
            return
        }

        currentExerciseIndex += 1
        currentSetIndex = workout.exercises[currentExerciseIndex].sets.firstIndex(where: { !$0.isCompleted }) ?? 0
        restEndsAt = nil
        activeWorkout = workout
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
                    guard set.isCompleted,
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
        guard let url = Self.workoutHistoryURL else { return }

        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(workoutHistory)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
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
