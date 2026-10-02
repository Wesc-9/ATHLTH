import SwiftUI
import UIKit

struct ActiveStrengthWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    @State private var showingFinishConfirmation = false
    @State private var finishInProgress = false
    @State private var showingExerciseLibrary = false
    @State private var pendingExercise: ExerciseLibraryEntry?
    @State private var showingExerciseSwap = false
    @State private var showingExerciseGroupBuilder = false
    @State private var showingExerciseRestEditor = false
    @State private var showingPlateCalculator = false
    @StateObject private var strengthCoach =
        StrengthAudioCoachSpeaker()
    @State private var restCueTask:
        Task<Void, Never>?
    @State private var statusCoachTask:
        Task<Void, Never>?
    @State private var didDisableIdleTimer = false

    var body: some View {
        NavigationStack {
            Group {
                if let workout = strength.activeWorkout {
                    ScrollView {
                        VStack(spacing: 18) {
                            workoutHeader(workout)

                            addExerciseCard(workout)

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
                    if strength.activeWorkout != nil {
                        Button {
                            showingExerciseLibrary = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english: "Add exercise",
                                norwegian: "Legg til øvelse"
                            )
                        )
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
            .sheet(
                isPresented:
                    $showingExerciseSwap
            ) {
                if let exercise =
                        strength.currentExercise {
                    StrengthExerciseSwapView(
                        current: exercise,
                        entries:
                            exerciseLibrary
                                .allExercises
                    ) { selected in
                        strength
                            .substituteCurrentExercise(
                                with:
                                    selected.exercise
                            )
                        showingExerciseSwap =
                            false
                    }
                }
            }
            .sheet(
                isPresented:
                    $showingExerciseGroupBuilder
            ) {
                if let workout =
                        strength.activeWorkout,
                   let exercise =
                        strength.currentExercise {
                    StrengthExerciseGroupBuilderView(
                        workout: workout,
                        currentExerciseID:
                            exercise.id
                    ) { ids, style in
                        strength.groupExercises(
                            ids: ids,
                            style: style
                        )
                        showingExerciseGroupBuilder =
                            false
                    } onUngroup: {
                        strength.ungroupExercise(
                            exercise.id
                        )
                        showingExerciseGroupBuilder =
                            false
                    }
                }
            }
            .sheet(
                isPresented:
                    $showingExerciseRestEditor
            ) {
                if let exercise =
                        strength.currentExercise {
                    StrengthExerciseRestEditorView(
                        exercise: exercise,
                        fallbackSeconds:
                            strength
                                .draftRestSeconds
                    ) { seconds in
                        strength
                            .setCurrentExerciseRestSeconds(
                                seconds
                            )
                        showingExerciseRestEditor =
                            false
                    }
                }
            }
            .sheet(
                isPresented:
                    $showingPlateCalculator
            ) {
                StrengthPlateCalculatorView(
                    targetWeightKilograms:
                        strength
                            .draftWeightKilograms
                )
            }
            .confirmationDialog(
                "Finish the full workout?",
                isPresented: $showingFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish Workout", role: .destructive) {
                    Task {
                        await finishWorkout()
                    }
                }
                .disabled(finishInProgress)
                Button("Keep Training", role: .cancel) {}
            } message: {
                Text(finishMessage)
            }
            .onAppear {
                loadDefaultsFromCurrentSet()
                configureAdvancedRuntime()
                scheduleRestCues(
                    for: strength.restEndsAt
                )
                scheduleStatusCoach()
            }
            .onDisappear {
                restCueTask?.cancel()
                statusCoachTask?.cancel()
                strengthCoach.stop()

                if didDisableIdleTimer {
                    UIApplication.shared
                        .isIdleTimerDisabled = false
                    didDisableIdleTimer = false
                }
            }
            .onChange(of: strength.currentSetIndex) {
                loadDefaultsFromCurrentSet()
            }
            .onChange(
                of: strength.currentExerciseIndex
            ) { oldValue, newValue in
                loadDefaultsFromCurrentSet()
                guard oldValue != newValue else {
                    return
                }
                announceNextExerciseIfNeeded()
            }
            .onChange(
                of:
                    strength
                        .activeWorkout?
                        .totalCompletedSets
            ) { oldValue, newValue in
                guard let oldValue,
                      let newValue,
                      newValue > oldValue
                else {
                    return
                }

                announceCompletedSetIfNeeded()
            }
            .onChange(
                of: strength.restEndsAt
            ) { _, newValue in
                scheduleRestCues(
                    for: newValue
                )
            }
        }
    }

    @MainActor
    private func configureAdvancedRuntime() {
        guard let workout =
                strength.activeWorkout,
              workout.trackingMode ==
                .advanced,
              let configuration =
                workout
                    .advancedConfiguration
        else {
            return
        }

        if configuration.keepScreenAwake {
            UIApplication.shared
                .isIdleTimerDisabled = true
            didDisableIdleTimer = true
        }

        if workout.captureDevice == .iPhone,
           configuration.audioCoach.enabled {
            strengthCoach.speak(
                english:
                    "Audio Coach is ready for your strength workout.",
                norwegian:
                    "Audio Coach er klar for styrkeøkten din.",
                configuration:
                    configuration.audioCoach
            )
        }
    }

    @MainActor
    private func announceCompletedSetIfNeeded() {
        guard let workout =
                strength.activeWorkout,
              workout.captureDevice ==
                .iPhone,
              let configuration =
                workout
                    .advancedConfiguration,
              configuration.audioCoach.enabled,
              configuration.audioCoach
                .announceSetComplete,
              let completed =
                workout.exercises
                    .flatMap(\.sets)
                    .filter(\.isCompleted)
                    .max(
                        by: {
                            ($0.completedAt ?? .distantPast) <
                            ($1.completedAt ?? .distantPast)
                        }
                    )
        else {
            return
        }

        let setNumber =
            completed.setNumber

        if let reps =
                completed.completedReps,
           let weight =
                completed
                    .completedWeightKilograms {
            let formattedWeight =
                weight.rounded() == weight
                    ? String(
                        Int(weight)
                    )
                    : String(
                        format: "%.1f",
                        weight
                    )

            strengthCoach.speak(
                english:
                    "Set \(setNumber) complete. \(reps) reps at \(formattedWeight) kilograms.",
                norwegian:
                    "Sett \(setNumber) fullført. \(reps) repetisjoner på \(formattedWeight) kilo.",
                configuration:
                    configuration.audioCoach
            )
        } else {
            strengthCoach.speak(
                english:
                    "Set \(setNumber) complete.",
                norwegian:
                    "Sett \(setNumber) fullført.",
                configuration:
                    configuration.audioCoach
            )
        }
    }

    @MainActor
    private func announceNextExerciseIfNeeded() {
        guard let workout =
                strength.activeWorkout,
              workout.captureDevice ==
                .iPhone,
              let configuration =
                workout
                    .advancedConfiguration,
              configuration.audioCoach.enabled,
              configuration.audioCoach
                .announceNextExercise,
              let exercise =
                strength.currentExercise
        else {
            return
        }

        strengthCoach.speak(
            english:
                "Next exercise. \(exercise.exercise.name).",
            norwegian:
                "Neste øvelse. \(exercise.exercise.name).",
            configuration:
                configuration.audioCoach
        )
    }

    @MainActor
    private func scheduleRestCues(
        for restEndsAt: Date?
    ) {
        restCueTask?.cancel()
        restCueTask = nil

        guard let restEndsAt,
              let workout =
                strength.activeWorkout,
              workout.captureDevice ==
                .iPhone,
              let configuration =
                workout
                    .advancedConfiguration,
              configuration.restCues
                .automaticRestTimer
        else {
            return
        }

        let coachConfiguration =
            configuration.audioCoach
        let countdownSeconds =
            coachConfiguration
                .restCountdownSeconds
        let initialRemaining =
            max(
                Int(
                    restEndsAt
                        .timeIntervalSinceNow
                        .rounded()
                ),
                0
            )

        if coachConfiguration.enabled &&
            coachConfiguration
                .announceRestStarted {
            strengthCoach.speak(
                english:
                    "Rest started. \(initialRemaining) seconds.",
                norwegian:
                    "Hvile startet. \(initialRemaining) sekunder.",
                configuration:
                    coachConfiguration
            )
        }

        restCueTask =
            Task { @MainActor in
                let countdownDelay =
                    restEndsAt
                        .timeIntervalSinceNow -
                    TimeInterval(
                        countdownSeconds
                    )

                if countdownDelay > 0 {
                    try? await Task.sleep(
                        for:
                            .seconds(
                                countdownDelay
                            )
                    )
                }

                guard !Task.isCancelled,
                      strength.restEndsAt ==
                        restEndsAt
                else {
                    return
                }

                if coachConfiguration.enabled &&
                    coachConfiguration
                        .announceRestCountdown {
                    strengthCoach.speak(
                        english:
                            "\(countdownSeconds) seconds left.",
                        norwegian:
                            "\(countdownSeconds) sekunder igjen.",
                        configuration:
                            coachConfiguration
                    )
                }

                let finalDelay =
                    restEndsAt
                        .timeIntervalSinceNow

                if finalDelay > 0 {
                    try? await Task.sleep(
                        for:
                            .seconds(
                                finalDelay
                            )
                    )
                }

                guard !Task.isCancelled,
                      strength.restEndsAt ==
                        restEndsAt
                else {
                    return
                }

                if configuration
                    .restCues
                    .hapticsEnabled {
                    UINotificationFeedbackGenerator()
                        .notificationOccurred(
                            .success
                        )
                }

                if coachConfiguration.enabled &&
                    coachConfiguration
                        .announceRestComplete {
                    strengthCoach.speak(
                        english:
                            "Rest complete. Ready for the next set.",
                        norwegian:
                            "Hvilen er ferdig. Klar for neste sett.",
                        configuration:
                            coachConfiguration
                    )
                }
            }
    }

    @MainActor
    private func scheduleStatusCoach() {
        statusCoachTask?.cancel()
        statusCoachTask = nil

        guard let workout =
                strength.activeWorkout,
              workout.captureDevice ==
                .iPhone,
              let configuration =
                workout
                    .advancedConfiguration,
              configuration.audioCoach.enabled,
              configuration.audioCoach
                .announceWorkoutStatus
        else {
            return
        }

        let interval =
            max(
                configuration.audioCoach
                    .workoutStatusIntervalMinutes,
                5
            )

        statusCoachTask =
            Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(
                        for:
                            .seconds(
                                Double(
                                    interval *
                                    60
                                )
                            )
                    )

                    guard !Task.isCancelled,
                          let active =
                            strength.activeWorkout,
                          active.id ==
                            workout.id
                    else {
                        return
                    }

                    let exerciseName =
                        strength
                            .currentExercise?
                            .exercise
                            .name ??
                        active.title

                    strengthCoach.speak(
                        english:
                            "\(active.totalCompletedSets) sets complete. Current exercise: \(exerciseName).",
                        norwegian:
                            "\(active.totalCompletedSets) sett fullført. Nåværende øvelse: \(exerciseName).",
                        configuration:
                            configuration.audioCoach
                    )
                }
            }
    }

    @MainActor
    private func finishWorkout() async {
        guard !finishInProgress,
              let workout = strength.activeWorkout
        else {
            return
        }

        finishInProgress = true
        defer { finishInProgress = false }

        let endDate = Date()
        let ownerID = appSession.profile.userID

        switch workout.captureDevice {
        case .appleWatch:
            watchConnection.sendWorkoutCommand(.end)
            strength.finish(
                duration: endDate.timeIntervalSince(workout.startedAt)
            )

        case .iPhone:
            // ATHLTH is the source of truth for the strength log. When Health
            // write access is available, also create a real HealthKit workout
            // so Apple Health, Progress and streak all see the same session.
            let healthWorkoutUUID = await health.saveManualStrengthWorkout(
                startDate: workout.startedAt,
                endDate: endDate,
                externalID: workout.id
            )

            guard appSession.signedIn, appSession.profile.userID == ownerID,
                  strength.activeWorkout?.id == workout.id else { return }
            strength.finish(
                healthKitWorkoutUUID: healthWorkoutUUID,
                duration: endDate.timeIntervalSince(workout.startedAt)
            )
        }

        appSession.endTrainingStatus()
        dismiss()
    }

    private var finishMessage: String {
        guard let workout = strength.activeWorkout else {
            return "Finish the ATHLTH workout."
        }

        switch workout.captureDevice {
        case .appleWatch:
            return "This finishes the ATHLTH log and ends the linked HealthKit workout on Apple Watch."
        case .iPhone:
            return health.canWriteWorkouts
                ? "This finishes the ATHLTH workout on iPhone and saves it to Apple Health."
                : "This finishes the ATHLTH workout on iPhone. It will still count toward your ATHLTH streak even without Health write access."
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
                        Text(ATHLTHLocalization.counted(
                            workout.totalCompletedSets,
                            englishSingular: "set",
                            englishPlural: "sets",
                            norwegianSingular: "sett",
                            norwegianPlural: "sett"
                        ))
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
                            ? ATHLTHLocalization.choose(
                                english: "Choose your first exercise",
                                norwegian: "Velg første øvelse"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Add another exercise",
                                norwegian: "Legg til en øvelse"
                            )
                    )
                    .font(.headline)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Choose from the exercise library or your own exercises while the workout keeps running.",
                            norwegian:
                                "Velg fra øvelsesbiblioteket eller dine egne øvelser mens økten fortsetter."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(
                    ATHLTHLocalization.choose(
                        english: "Add",
                        norwegian: "Legg til"
                    )
                ) {
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
                    Text(ATHLTHLocalization.format(
                            english: "Exercise %d of %d",
                            norwegian: "Øvelse %d av %d",
                            strength.currentExerciseIndex + 1,
                            workout.exercises.count
                        ))
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

        if !canLogOnIPhone(workout) {
            watchInputCompanionCard(
                workout: workout
            )
        } else if strength.currentExerciseAllSetsCompleted {
            exerciseCompleteControls(
                workout: workout
            )
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
                Text(
                    strengthWatchSnapshot != nil
                        ? "Live"
                        : "Running continuously"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accent)
            }

            if let snapshot = strengthWatchSnapshot {
                Divider()
                    .padding(.vertical, 10)

                HStack(spacing: 0) {
                    strengthWatchMetric(
                        icon: "heart.fill",
                        value: snapshot.heartRate > 0
                            ? "\(Int(snapshot.heartRate.rounded()))"
                            : "—",
                        label: "BPM"
                    )

                    Divider()
                        .frame(height: 36)

                    strengthWatchMetric(
                        icon: "flame.fill",
                        value: "\(Int(snapshot.activeCalories.rounded()))",
                        label: "KCAL"
                    )

                    Divider()
                        .frame(height: 36)

                    strengthWatchMetric(
                        icon: "clock.fill",
                        value: snapshot.elapsedTime.clockDuration,
                        label: "WATCH"
                    )
                }
            }

            Text(
                workout.captureDevice == .appleWatch
                    ? "Apple Watch records heart rate, calories and duration while ATHLTH keeps weight, reps, sets and rest on this screen."
                    : "A wearable is optional. The ATHLTH workout runs continuously on iPhone from Start until Finish."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
    }

    private var strengthWatchSnapshot: WatchWorkoutLiveSnapshot? {
        guard let snapshot = workoutMirroring.snapshot,
              snapshot.kind == .strength ||
              snapshot.kind == .functional
        else {
            return nil
        }

        return snapshot
    }

    private func canLogOnIPhone(
        _ workout: StrengthWorkoutLog
    ) -> Bool {
        guard workout.captureDevice ==
                .appleWatch
        else {
            return true
        }

        return
            workout
                .advancedConfiguration?
                .inputMode != .appleWatch
    }

    @ViewBuilder
    private func watchInputCompanionCard(
        workout: StrengthWorkoutLog
    ) -> some View {
        ATHLTHCard {
            VStack(spacing: 10) {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Log this set on Apple Watch",
                        norwegian:
                            "Registrer dette settet på Apple Watch"
                    )
                )
                .font(.headline)
                .multilineTextAlignment(.center)

                if let restEndsAt =
                        strength.restEndsAt {
                    TimelineView(
                        .periodic(
                            from: .now,
                            by: 1
                        )
                    ) { context in
                        let remaining =
                            max(
                                restEndsAt
                                    .timeIntervalSince(
                                        context.date
                                    ),
                                0
                            )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Rest · \(remaining.clockDuration)",
                                norwegian:
                                    "Hvile · \(remaining.clockDuration)"
                            )
                        )
                        .font(
                            .subheadline
                                .monospacedDigit()
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }
                } else {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "iPhone stays synchronized and can still add exercises or finish the workout.",
                            norwegian:
                                "iPhone holdes synkronisert og kan fortsatt legge til øvelser eller avslutte økten."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func strengthWatchMetric(
        icon: String,
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accent)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .lineLimit(1)

            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                        Text(ATHLTHLocalization.format(
                            english: "Target: %d reps",
                            norwegian: "Mål: %d repetisjoner",
                            plannedReps
                        ))
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
                    value: String(format: "%.1f kg", strength.draftWeightKilograms),
                    minus: { strength.setDraft(weightKilograms: max(0, strength.draftWeightKilograms - 2.5)) },
                    plus: { strength.setDraft(weightKilograms: strength.draftWeightKilograms + 2.5) }
                )

                valueStepper(
                    title: "Reps",
                    value: "\(strength.draftReps)",
                    minus: { strength.setDraft(reps: max(0, strength.draftReps - 1)) },
                    plus: { strength.setDraft(reps: strength.draftReps + 1) }
                )
            }
            .padding(.top, 12)

            HStack(spacing: 12) {
                Label(
                    "Rest",
                    systemImage: "timer"
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    strength.setDraft(restSeconds: max(0, strength.draftRestSeconds - 15))
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)

                Text(restDurationText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 62)

                Button {
                    strength.setDraft(restSeconds: min(600, strength.draftRestSeconds + 15))
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 14)

            HStack {
                Text("RPE")
                    .font(.subheadline.weight(.semibold))
                Slider(value: draftRPEBinding, in: 1...10, step: 0.5)
                Text("\(strength.draftRPE, specifier: "%.1f")")
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 32)
            }
            .padding(.top, 14)

            Button {
                strength.completeCurrentDraftSet()
            } label: {
                Label("Complete Set", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(ATHLTHTheme.accent)
            .padding(.top, 14)

            Button {
                strength.completeCurrentSetWithoutDetails(
                    restSeconds: strength.draftRestSeconds
                )
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

                    Group {
                        if remaining > 0 {
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
                        } else {
                            Label(
                                "Ready for next set",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.accent)
                            .onAppear {
                                strength.skipRest()
                            }
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
        strength.reloadDraftFromCurrentSet()
    }

    private var draftRPEBinding: Binding<Double> {
        Binding(
            get: { strength.draftRPE },
            set: { strength.setDraft(rpe: $0) }
        )
    }

    private var restDurationText: String {
        let restSeconds = strength.draftRestSeconds

        if restSeconds == 0 {
            return "None"
        }

        if restSeconds >= 60,
           restSeconds % 60 == 0 {
            return "\(restSeconds / 60) min"
        }

        return "\(restSeconds) sec"
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
