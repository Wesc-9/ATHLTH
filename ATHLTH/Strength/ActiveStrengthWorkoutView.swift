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
                if let workout = strength.activeWorkout,
                   let exercise = strength.currentExercise {
                    ScrollView {
                        VStack(spacing: 18) {
                            workoutHeader(workout)

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

                            ATHLTHCard {
                                HStack {
                                    Label("Apple Watch workout", systemImage: "applewatch")
                                    Spacer()
                                    Text("Running continuously")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                }

                                Text("Logging sets or resting here does not pause the HealthKit workout. Watch runs from workout start until you finish the full session.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                            }
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
                Text("This ends the ATHLTH strength log. The production Watch implementation will end the linked HealthKit workout at the same point.")
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
                    Text("\(workout.totalCompletedSets)")
                        .font(.title2.weight(.bold))
                    Text("sets logged")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(Int(workout.totalVolumeKilograms)) kg")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
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
                    Text("\(set.completedReps ?? 0) reps × \(set.completedWeightKilograms ?? 0, specifier: "%.1f") kg")
                        .font(.subheadline.weight(.semibold))
                    if let rpe = set.rpe {
                        Text("RPE \(rpe, specifier: "%.1f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Target: \(set.plannedReps.map(String.init) ?? "—") reps")
                        .font(.subheadline.weight(.medium))
                    Text(set.plannedWeightKilograms.map { "\($0, specifier: "%.1f") kg" } ?? "Choose weight")
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
                actionTitle: "Watch keeps running"
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
        }
    }

    private var restControls: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: "Rest", actionTitle: "Health workout still running")

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
