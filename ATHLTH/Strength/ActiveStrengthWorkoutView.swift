import SwiftUI

struct ActiveStrengthWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    @State private var reps = 8
    @State private var weightKilograms = 20.0
    @State private var rpe = 8.0
    @State private var showingFinishConfirmation = false
    @State private var showingExerciseLibrary = false
    @State private var pendingExercise: ExerciseLibraryEntry?

    var body: some View {
        NavigationStack {
            Group {
                if let workout = strength.activeWorkout {
                    ScrollView {
                        VStack(spacing: 18) {
                            workoutHeader(workout)

                            if workout.trackingMode == .advanced {
                                addExerciseCard(workout)
                            }

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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if strength.activeWorkout?.trackingMode == .advanced {
                        Button {
                            showingExerciseLibrary = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add exercise")
                    }

                    Button("Finish") {
                        showingFinishConfirmation = true
                    }
                    .disabled(strength.activeWorkout == nil)
                }
            }
            .sheet(isPresented: $showingExerciseLibrary) {
                NavigationStack {
                    ExerciseLibraryView(
                        selectionTitle: "Add to Active Workout"
                    ) { entry in
                        pendingExercise = entry
                        showingExerciseLibrary = false
                    }
                }
            }
            .sheet(item: $pendingExercise) { entry in
                FreestyleExercisePrescriptionView(entry: entry) {
                    strength.appendExercise(
                        entry.exercise,
                        sets: $0,
                        reps: $1,
                        targetWeightKilograms: $2,
                        restSeconds: $3
                    )
                    pendingExercise = nil
                    loadDefaultsFromCurrentSet()
                }
            }
            .confirmationDialog(
                "Finish the full workout?",
                isPresented: $showingFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish Workout", role: .destructive) {
                    if strength.activeWorkout?.captureDevice == .appleWatch {
                        watchConnection.sendWorkoutCommand(.end)
                    }

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
            return "This finishes the ATHLTH log and ends the linked HealthKit workout on Apple Watch."
        case .iPhone:
            return "This finishes the ATHLTH workout on iPhone. A wearable is not required."
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
                        .foregroundStyle(ATHLTHTheme.accent)

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
    private func addExerciseCard(_ workout: StrengthWorkoutLog) -> some View {
        ATHLTHCard {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        workout.exercises.isEmpty
                            ? "Choose your first exercise"
                            : "Add another exercise"
                    )
                    .font(.headline)

                    Text(
                        "Pick from RepDB or your own exercises while the workout keeps running."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Add") {
                    showingExerciseLibrary = true
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
            }
        }
    }

    @ViewBuilder
    private func simpleTrackingContent(workout: StrengthWorkoutLog) -> some View {
        ATHLTHCard {
            Label("Simple tracking", systemImage: "play.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(ATHLTHTheme.accent)

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
                    .foregroundStyle(ATHLTHTheme.accent)
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
                    .foregroundStyle(ATHLTHTheme.accent)
            }

            Text(
                workout.captureDevice == .appleWatch
                    ? "Logging sets or resting in ATHLTH does not pause the Apple Watch workout. It runs continuously from Start until Finish."
                    : "A wearable is optional. The ATHLTH workout runs continuously on iPhone from Start until Finish."
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
                    set.isCompleted ? ATHLTHTheme.accent.opacity(0.18) : Color.secondary.opacity(0.10),
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
                .foregroundStyle(set.isCompleted ? ATHLTHTheme.accent : .secondary)
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
                    value: String(format: "%.1f kg", weightKilograms),
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
            .tint(ATHLTHTheme.accent)
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
                            .tint(ATHLTHTheme.accent)
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
                    .foregroundStyle(ATHLTHTheme.accent)

                if strength.hasNextExercise {
                    Button {
                        strength.moveToNextExercise()
                    } label: {
                        Label("Next Exercise", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
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
                    .tint(ATHLTHTheme.accent)
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

private struct FreestyleExercisePrescriptionView: View {
    @Environment(\.dismiss) private var dismiss

    let entry: ExerciseLibraryEntry
    let onAdd: (Int, Int?, Double?, Int?) -> Void

    @State private var sets = 3
    @State private var reps = 8
    @State private var restSeconds = 90
    @State private var useWeightTarget = false
    @State private var weightKilograms = 20.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ExerciseArtwork(entry: entry, size: 62)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                                .font(.headline)

                            Text(
                                entry.exercise.primaryMuscles
                                    .prefix(3)
                                    .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Prescription") {
                    Stepper("Sets: \(sets)", value: $sets, in: 1...20)
                    Stepper("Target reps: \(reps)", value: $reps, in: 1...100)
                    Stepper(
                        "Rest: \(restSeconds) sec",
                        value: $restSeconds,
                        in: 0...600,
                        step: 15
                    )

                    Toggle("Target weight", isOn: $useWeightTarget)

                    if useWeightTarget {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField(
                                "kg",
                                value: $weightKilograms,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 95)
                            Text("kg")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("You can log actual reps, weight and RPE set by set. The exercise is added immediately to the running workout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(
                            sets,
                            reps,
                            useWeightTarget ? weightKilograms : nil,
                            restSeconds
                        )
                        dismiss()
                    }
                }
            }
        }
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
