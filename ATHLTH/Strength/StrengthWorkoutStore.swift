import Foundation

@MainActor
final class StrengthWorkoutStore: ObservableObject {
    @Published private(set) var activeWorkout: StrengthWorkoutLog?
    @Published private(set) var currentExerciseIndex = 0
    @Published private(set) var currentSetIndex = 0
    @Published private(set) var restEndsAt: Date?
    @Published private(set) var completedWorkout: StrengthWorkoutLog?

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
        activeWorkout = nil
        restEndsAt = nil
        currentExerciseIndex = 0
        currentSetIndex = 0
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
        }
    }

    private func advanceSetIndex(in exercise: StrengthExerciseLog) {
        if let nextIndex = exercise.sets.indices.first(where: { index in
            index > currentSetIndex && !exercise.sets[index].isCompleted
        }) {
            currentSetIndex = nextIndex
        }
    }
}
