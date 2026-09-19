import SwiftUI

struct ActiveStrengthWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var appSession: AppSessionStore

    @State private var reps = 8
    @State private var weightKilograms = 20.0
    @State private var rpe = 8.0
    @State private var showingFinishConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let workout = strength.activeWorkout {
                    ScrollView {
                        VStack(spacing: 18) {
                            workoutHeader(workout)

                            if workout.trackingMode == .advanced,
                               let exercise = strength.currentExercise {
                                advancedTrackingContent(workout: workout, exercise: exercise)
                            } else {
                                simpleTrackingContent(workout: workout)
                            }

                            recordingStatusCard(workout)
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "No active strength workout",
                        systemImage: "dumbbell",
                        description: Text("Start a strength session from Train.")
                    )
                }
            }
            .navigationTitle("Strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") {
                        showingFinishConfirmation = true
                    }
                    .disabled(strength.activeWorkout == nil)
                }
            }
            .confirmationDialog(
                "Finish the full workout?",
                isPresented: $showingFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish Workout", role: .destructive) {
                    strength.finish()
                    appSession.endTrainingStatus()
                    dismiss()
                }
                Button("Keep Training", role: .cancel) {}
            } message: {
                Text(finishMessage)
            }
            .onAppear {
                loadDefaultsFromCurrentSet()
            }
            .onChange(of: strength.currentSetIndex) {
                loadDefaultsFromCurrentSet()
            }
            .onChange(of: strength.currentExerciseIndex) {
                loadDefaultsFromCurrentSet()
            }
        }
    }

    private var finishMessage: String {
        guard let workout = strength.activeWorkout else {
            return "Finish the ATHLTH workout."
        }

        switch workout.captureDevice {
        case .appleWatch:
            return "This finishes the ATHLTH log. The production Apple Watch integration will end the linked HealthKit workout at the same point."
        case .iPhone:
            return "This finishes the ATHLTH workout on iPhone. Apple Watch is not required."
        }
    }

    @ViewBuilder
    private func workoutHeader(_ workout: StrengthWorkoutLog) -> some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workout.title)
                        .font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(context.date.timeIntervalSince(workout.startedAt).clockDuration)
                            .font(.largeTitle.monospacedDigit().weight(.bold))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Label(workout.captureDevice.title, systemImage: workout.captureDevice == .appleWatch ? "applewatch" : "iphone")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)

                    Text(workout.trackingMode.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if workout.trackingMode == .advanced {
                        Text("\(workout.totalCompletedSets) sets")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func simpleTrackingContent(workout: StrengthWorkoutLog) -> some View {
        ATHLTHCard {
            Label("Simple tracking", systemImage: "play.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.green)

            Text("Just train. ATHLTH keeps the workout timer running until you press Finish. Sets, reps, weight and rest are not required.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            if !workout.exercises.isEmpty {
                Divider()
                    .padding(.vertical, 12)

                Text("Planned exercises")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(workout.exercises) { exercise in
                        Label(exercise.exercise.name, systemImage: "dumbbell")
                            .font(.subheadline)
                    }
                }
                .padding(.top, 8)

                Button {
                    strength.enableAdvancedTracking()
                    loadDefaultsFromCurrentSet()
                } label: {
                    Label("Enable Advanced Tracking", systemImage: "list.bullet.clipboard.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 14)
            }
        }
    }

    @ViewBuilder
    private func advancedTrackingContent(
        workout: StrengthWorkoutLog,
        exercise: StrengthExerciseLog
    ) -> some View {
        ATHLTHCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Exercise \(strength.currentExerciseIndex + 1) of \(workout.exercises.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(exercise.exercise.name)
                        .font(.title2.weight(.bold))
                    Text(exercise.exercise.primaryMuscles.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "dumbbell.fill")
                    .font(.title)
                    .foregroundStyle(.green)
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(title: "Sets")

            VStack(spacing: 10) {
                ForEach(exercise.sets) { set in
                    setRow(set)
                }
            }
            .padding(.top, 10)
        }

        if strength.currentExerciseAllSetsCompleted {
            exerciseCompleteControls(workout: workout)
        } else if strength.isResting {
            restControls
        } else {
            setEntry
        }
    }

    @ViewBuilder
    private func recordingStatusCard(_ workout: StrengthWorkoutLog) -> some View {
        ATHLTHCard {
            HStack {
                Label(
                    workout.captureDevice == .appleWatch ? "Apple Watch workout" : "iPhone workout",
                    systemImage: workout.captureDevice == .appleWatch ? "applewatch" : "iphone"
                )
                Spacer()
                Text("Running continuously")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Text(
                workout.captureDevice == .appleWatch
                    ? "Logging sets or resting in ATHLTH does not pause the Apple Watch workout. It runs continuously from Start until Finish."
                    : "Apple Watch is optional. The ATHLTH workout runs continuously on iPhone from Start until Finish."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func setRow(_ set: StrengthSetLog) -> some View {
        HStack(spacing: 12) {
            Text("\(set.setNumber)")
                .font(.subheadline.weight(.bold))
                .frame(width: 28, height: 28)
                .background(
                    set.isCompleted ? Color.green.opacity(0.18) : Color.secondary.opacity(0.10),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                if set.isCompleted {
                    if let reps = set.completedReps, let weight = set.completedWeightKilograms {
                        Text("\(reps) reps × \(weight, specifier: "%.1f") kg")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Set completed")
                            .font(.subheadline.weight(.semibold))
                    }

                    if let rpe = set.rpe {
                        Text("RPE \(rpe, specifier: "%.1f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if let plannedReps = set.plannedReps {
                        Text("Target: \(plannedReps) reps")
                            .font(.subheadline.weight(.medium))
                    } else {
                        Text("No rep target")
                            .font(.subheadline.weight(.medium))
                    }

                    Text(set.plannedWeightKilograms.map { String(format: "%.1f kg", $0) } ?? "No weight target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(set.isCompleted ? .green : .secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var setEntry: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Log Set \((strength.currentSet?.setNumber) ?? 1)",
                actionTitle: "Optional details"
            )

            HStack(spacing: 12) {
                valueStepper(
                    title: "Weight",
                    value: "\(weightKilograms, specifier: "%.1f") kg",
                    minus: { weightKilograms = max(0, weightKilograms - 2.5) },
                    plus: { weightKilograms += 2.5 }
                )

                valueStepper(
                    title: "Reps",
                    value: "\(reps)",
                    minus: { reps = max(0, reps - 1) },
                    plus: { reps += 1 }
                )
            }
            .padding(.top, 12)

            HStack {
                Text("RPE")
                    .font(.subheadline.weight(.semibold))
                Slider(value: $rpe, in: 1...10, step: 0.5)
                Text("\(rpe, specifier: "%.1f")")
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 32)
            }
            .padding(.top, 14)

            Button {
                strength.completeCurrentSet(
                    reps: reps,
                    weightKilograms: weightKilograms,
                    rpe: rpe
                )
            } label: {
                Label("Complete Set", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
            .padding(.top, 14)

            Button {
                strength.completeCurrentSetWithoutDetails()
            } label: {
                Text("Complete set without details")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)

            Text("Weight, reps, RPE and rest are optional even in Advanced mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private var restControls: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: "Rest", actionTitle: "Workout keeps running")

            if let restEndsAt = strength.restEndsAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(restEndsAt.timeIntervalSince(context.date), 0)

                    VStack(spacing: 12) {
                        Text(remaining.clockDuration)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        HStack {
                            Button("+30 sec") {
                                strength.addRest(seconds: 30)
                            }
                            .buttonStyle(.bordered)

                            Button("Skip Rest") {
                                strength.skipRest()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseCompleteControls(workout: StrengthWorkoutLog) -> some View {
        ATHLTHCard {
            VStack(spacing: 12) {
                Label("Exercise complete", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)

                if strength.hasNextExercise {
                    Button {
                        strength.moveToNextExercise()
                    } label: {
                        Label("Next Exercise", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                } else {
                    Text("All planned exercises are complete.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        showingFinishConfirmation = true
                    } label: {
                        Label("Finish Workout", systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                }
            }
        }
    }

    @ViewBuilder
    private func valueStepper(
        title: String,
        value: String,
        minus: @escaping () -> Void,
        plus: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
            HStack {
                Button(action: minus) {
                    Image(systemName: "minus")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)

                Button(action: plus) {
                    Image(systemName: "plus")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadDefaultsFromCurrentSet() {
        guard let set = strength.currentSet else { return }
        reps = set.plannedReps ?? 8
        weightKilograms = set.plannedWeightKilograms ?? max(weightKilograms, 20)
        rpe = 8
    }
}

private extension TimeInterval {
    var clockDuration: String {
        let totalSeconds = max(Int(self.rounded(.down)), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}
