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
    @State private var watchFinishTimeoutTask:
        Task<Void, Never>?
    @State private var watchFinishError: String?
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

                            TrainTogetherStatusStrip()

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
                    .disabled(
                        strength.activeWorkout == nil ||
                        finishInProgress
                    )
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
                        restSeconds: $3,
                        warmUpSets: $4
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
            .alert(
                ATHLTHLocalization.choose(
                    english: "Apple Watch",
                    norwegian: "Apple Watch"
                ),
                isPresented:
                    Binding(
                        get: {
                            watchFinishError != nil
                        },
                        set: { shown in
                            if !shown {
                                watchFinishError = nil
                            }
                        }
                    )
            ) {
                Button("OK") {
                    watchFinishError = nil
                }
            } message: {
                Text(
                    watchFinishError ?? ""
                )
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
                watchFinishTimeoutTask?.cancel()
                watchFinishTimeoutTask = nil
                strengthCoach.stop()

                if didDisableIdleTimer {
                    UIApplication.shared
                        .isIdleTimerDisabled = false
                    didDisableIdleTimer = false
                }
            }
            .onChange(
                of:
                    strength
                        .activeWorkout?
                        .id
            ) { oldValue, newValue in
                guard oldValue != nil,
                      newValue == nil
                else {
                    return
                }

                watchFinishTimeoutTask?.cancel()
                watchFinishTimeoutTask = nil
                finishInProgress = false
                appSession.endTrainingStatus()
                dismiss()
            }
            .onChange(of: strength.currentSetIndex) {
                loadDefaultsFromCurrentSet()
            }
            .onChange(
                of:
                    strength
                        .activeWorkout?
                        .trackingMode
            ) { _, newValue in
                guard newValue == .advanced else {
                    return
                }

                configureAdvancedRuntime()
                scheduleStatusCoach()
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
              let workout =
                strength.activeWorkout
        else {
            return
        }

        finishInProgress = true

        switch workout.captureDevice {
        case .appleWatch:
            // Apple Watch owns HealthKit for this workout. iPhone only asks it
            // to finish; the local strength log is finalized when the Watch
            // returns the authoritative result/HealthKit UUID.
            if workoutMirroring
                .hasActiveMirroredWorkout {
                workoutMirroring
                    .sendCommand(.end)
            } else {
                watchConnection
                    .sendWorkoutCommand(
                        .end,
                        workoutID:
                            workout.id
                    )
            }

            watchFinishTimeoutTask?.cancel()
            let workoutID = workout.id

            watchFinishTimeoutTask =
                Task { @MainActor in
                    try? await Task.sleep(
                        for: .seconds(18)
                    )

                    guard !Task.isCancelled,
                          strength
                            .activeWorkout?
                            .id == workoutID
                    else {
                        return
                    }

                    finishInProgress = false
                    watchFinishError =
                        ATHLTHLocalization.choose(
                            english:
                                "ATHLTH has not received confirmation that Apple Watch finished the workout. The strength log is still safe. Finish or retry on the Watch, then ATHLTH will attach the Health data when it arrives.",
                            norwegian:
                                "ATHLTH har ikke fått bekreftet at Apple Watch avsluttet økten. Styrkeloggen er fortsatt trygg. Avslutt eller prøv igjen på klokken, så kobler ATHLTH til Health-data når de kommer."
                        )
                }

            return

        case .iPhone:
            let endDate = Date()
            let ownerID =
                appSession.profile.userID

            // ATHLTH is the source of truth for the strength log. When Health
            // write access is available, also create a real HealthKit workout
            // so Apple Health, Progress and streak all see the same session.
            let healthWorkoutUUID =
                await health
                    .saveManualStrengthWorkout(
                        startDate:
                            workout.startedAt,
                        endDate: endDate,
                        externalID:
                            workout.id
                    )

            guard appSession.signedIn,
                  appSession.profile.userID ==
                    ownerID,
                  strength.activeWorkout?.id ==
                    workout.id
            else {
                finishInProgress = false
                return
            }

            strength.finish(
                healthKitWorkoutUUID:
                    healthWorkoutUUID,
                duration:
                    endDate.timeIntervalSince(
                        workout.startedAt
                    )
            )
            appSession.endTrainingStatus()
            finishInProgress = false
            dismiss()
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

                    HStack(spacing: 6) {
                        if let style =
                                exercise.groupStyle {
                            Label(
                                style.title,
                                systemImage:
                                    style == .superset
                                        ? "link"
                                        : "square.grid.2x2"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                        }

                        if let rest =
                                exercise.restSecondsOverride {
                            Label(
                                "\(rest)s",
                                systemImage: "timer"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }

                        if let substituted =
                                exercise.substitutedFromExerciseName {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Replaced \(substituted)",
                                    norwegian: "Byttet fra \(substituted)"
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Menu {
                    Button {
                        showingExerciseRestEditor =
                            true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Exercise rest",
                                norwegian: "Hvile for øvelsen"
                            ),
                            systemImage: "timer"
                        )
                    }

                    Button {
                        showingExerciseGroupBuilder =
                            true
                    } label: {
                        Label(
                            exercise.groupID == nil
                                ? ATHLTHLocalization.choose(
                                    english: "Superset / circuit",
                                    norwegian: "Supersett / sirkel"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Edit exercise group",
                                    norwegian: "Rediger øvelsesgruppe"
                                ),
                            systemImage: "link"
                        )
                    }

                    Button {
                        showingExerciseSwap = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Swap exercise",
                                norwegian: "Bytt øvelse"
                            ),
                            systemImage:
                                "arrow.triangle.2.circlepath"
                        )
                    }

                    Button {
                        showingPlateCalculator =
                            true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Plate calculator",
                                norwegian: "Skivekalkulator"
                            ),
                            systemImage:
                                "scalemass.fill"
                        )
                    }
                } label: {
                    Image(
                        systemName:
                            "ellipsis.circle.fill"
                    )
                    .font(.title2)
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )
                }
            }
        }

        if let suggestion =
                strength.progressionSuggestion(
                    for: exercise
                ) {
            progressionSuggestionCard(
                suggestion
            )
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

    private func progressionSuggestionCard(
        _ suggestion:
            StrengthProgressionSuggestion
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    "chart.line.uptrend.xyaxis"
            )
            .font(.title3)
            .foregroundStyle(
                ATHLTHTheme.vitality
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                ATHLTHTheme.vitality
                    .opacity(0.10),
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Progression hint",
                        norwegian: "Progresjonsforslag"
                    )
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Last: \(formatWeight(suggestion.previousWeightKilograms)) kg × \(suggestion.previousReps) · Try \(formatWeight(suggestion.suggestedWeightKilograms)) kg × \(suggestion.suggestedReps)",
                        norwegian:
                            "Sist: \(formatWeight(suggestion.previousWeightKilograms)) kg × \(suggestion.previousReps) · Prøv \(formatWeight(suggestion.suggestedWeightKilograms)) kg × \(suggestion.suggestedReps)"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                ATHLTHLocalization.choose(
                    english: "Use",
                    norwegian: "Bruk"
                )
            ) {
                strength.setDraft(
                    reps:
                        suggestion.suggestedReps,
                    weightKilograms:
                        suggestion
                            .suggestedWeightKilograms
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            ATHLTHTheme.vitality
                .opacity(0.055),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private func formatWeight(
        _ value: Double
    ) -> String {
        value.rounded() == value
            ? String(Int(value))
            : String(
                format: "%.1f",
                value
            )
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

                    HStack(spacing: 7) {
                        if set.isWarmUp == true {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Warm-up",
                                    norwegian: "Oppvarming"
                                ),
                                systemImage: "flame"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                        }

                        if let rpe = set.rpe {
                            Text("RPE \(rpe, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let rir = set.rir {
                            Text("RIR \(rir, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

            Toggle(
                ATHLTHLocalization.choose(
                    english: "Warm-up set",
                    norwegian: "Oppvarmingssett"
                ),
                isOn: draftWarmUpBinding
            )
            .font(.subheadline.weight(.semibold))
            .padding(.top, 12)

            if !strength.draftWarmUp {
                switch currentEffortMetric {
                case .rpe:
                    HStack {
                        Text("RPE")
                            .font(.subheadline.weight(.semibold))
                        Slider(
                            value: draftRPEBinding,
                            in: 1...10,
                            step: 0.5
                        )
                        Text("\(strength.draftRPE, specifier: "%.1f")")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 36)
                    }
                    .padding(.top, 10)

                case .rir:
                    HStack {
                        Text("RIR")
                            .font(.subheadline.weight(.semibold))
                        Slider(
                            value: draftRIRBinding,
                            in: 0...10,
                            step: 0.5
                        )
                        Text("\(strength.draftRIR, specifier: "%.1f")")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 36)
                    }
                    .padding(.top, 10)

                case .off:
                    EmptyView()
                }
            }

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

            Text(
                strength.draftWarmUp
                    ? ATHLTHLocalization.choose(
                        english:
                            "Warm-up sets are kept in the workout but do not count toward PRs, training volume or muscle load.",
                        norwegian:
                            "Oppvarmingssett beholdes i økten, men teller ikke mot PR-er, treningsvolum eller muskelbelastning."
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Weight, reps, effort and rest are optional even in Advanced mode.",
                        norwegian:
                            "Vekt, repetisjoner, anstrengelse og hvile er valgfritt også i Avansert."
                    )
            )
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

    private var draftRIRBinding: Binding<Double> {
        Binding(
            get: { strength.draftRIR },
            set: { strength.setDraft(rir: $0) }
        )
    }

    private var draftWarmUpBinding: Binding<Bool> {
        Binding(
            get: { strength.draftWarmUp },
            set: { strength.setDraft(warmUp: $0) }
        )
    }

    private var currentEffortMetric:
        StrengthEffortMetric {
        strength
            .activeWorkout?
            .advancedConfiguration?
            .effortMetric ??
        .off
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
    let onAdd:
        (Int, Int?, Double?, Int?, Int) -> Void

    @State private var sets = 3
    @State private var reps = 8
    @State private var restSeconds = 90
    @State private var warmUpSets = 0
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

                    Stepper(
                        ATHLTHLocalization.format(
                            english: "Warm-up sets: %d",
                            norwegian: "Oppvarmingssett: %d",
                            warmUpSets
                        ),
                        value: $warmUpSets,
                        in: 0...sets
                    )
                    .onChange(of: sets) { _, newValue in
                        warmUpSets =
                            min(
                                warmUpSets,
                                newValue
                            )
                    }

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
                            restSeconds,
                            warmUpSets
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}


private struct StrengthExerciseSwapView: View {
    @Environment(\.dismiss) private var dismiss

    let current: StrengthExerciseLog
    let entries: [ExerciseLibraryEntry]
    let onSelect: (ExerciseLibraryEntry) -> Void

    @State private var searchText = ""

    private var currentMuscles: Set<String> {
        Set(
            current.exercise.primaryMuscles
                .map {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .lowercased()
                }
                .filter { !$0.isEmpty }
        )
    }

    private var candidates: [ExerciseLibraryEntry] {
        entries
            .filter { entry in
                guard entry.name
                    .localizedCaseInsensitiveCompare(
                        current.exercise.name
                    ) != .orderedSame
                else {
                    return false
                }

                let muscles =
                    Set(
                        entry.exercise.primaryMuscles
                            .map {
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .lowercased()
                            }
                    )

                let muscleMatch =
                    currentMuscles.isEmpty ||
                    !currentMuscles
                        .isDisjoint(with: muscles)

                let searchMatch =
                    searchText.isEmpty ||
                    entry.name.localizedCaseInsensitiveContains(
                        searchText
                    ) ||
                    entry.exercise.primaryMuscles
                        .contains {
                            $0.localizedCaseInsensitiveContains(
                                searchText
                            )
                        }

                return muscleMatch &&
                    searchMatch
            }
            .sorted { lhs, rhs in
                let lhsOverlap =
                    Set(
                        lhs.exercise.primaryMuscles
                            .map {
                                $0.lowercased()
                            }
                    )
                    .intersection(currentMuscles)
                    .count
                let rhsOverlap =
                    Set(
                        rhs.exercise.primaryMuscles
                            .map {
                                $0.lowercased()
                            }
                    )
                    .intersection(currentMuscles)
                    .count

                if lhsOverlap == rhsOverlap {
                    return lhs.name
                        .localizedCaseInsensitiveCompare(
                            rhs.name
                        ) == .orderedAscending
                }

                return lhsOverlap > rhsOverlap
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No matching exercises",
                            norwegian: "Ingen passende øvelser"
                        ),
                        systemImage:
                            "arrow.triangle.2.circlepath",
                        description: Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "ATHLTH could not find another exercise for the same primary muscle groups.",
                                norwegian:
                                    "ATHLTH fant ingen annen øvelse for de samme primære muskelgruppene."
                            )
                        )
                    )
                } else {
                    List {
                        Section(
                            ATHLTHLocalization.choose(
                                english: "Same muscle groups",
                                norwegian: "Samme muskelgrupper"
                            )
                        ) {
                            ForEach(candidates) { entry in
                                Button {
                                    onSelect(entry)
                                } label: {
                                    VStack(
                                        alignment: .leading,
                                        spacing: 3
                                    ) {
                                        Text(entry.name)
                                            .font(
                                                .subheadline
                                                    .weight(
                                                        .semibold
                                                    )
                                            )
                                            .foregroundStyle(
                                                .primary
                                            )

                                        Text(
                                            entry.exercise
                                                .primaryMuscles
                                                .prefix(3)
                                                .joined(
                                                    separator:
                                                        " · "
                                                )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(
                text: $searchText,
                prompt:
                    ATHLTHLocalization.choose(
                        english: "Search alternatives",
                        norwegian: "Søk etter alternativer"
                    )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Swap Exercise",
                    norwegian: "Bytt øvelse"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct StrengthExerciseGroupBuilderView: View {
    @Environment(\.dismiss) private var dismiss

    let workout: StrengthWorkoutLog
    let currentExerciseID: UUID
    let onSave:
        ([UUID], StrengthExerciseGroupStyle) -> Void
    let onUngroup: () -> Void

    @State private var selectedIDs: Set<UUID>
    @State private var style:
        StrengthExerciseGroupStyle

    init(
        workout: StrengthWorkoutLog,
        currentExerciseID: UUID,
        onSave: @escaping (
            [UUID],
            StrengthExerciseGroupStyle
        ) -> Void,
        onUngroup: @escaping () -> Void
    ) {
        self.workout = workout
        self.currentExerciseID =
            currentExerciseID
        self.onSave = onSave
        self.onUngroup = onUngroup

        let current =
            workout.exercises.first {
                $0.id ==
                currentExerciseID
            }

        if let groupID = current?.groupID {
            _selectedIDs = State(
                initialValue:
                    Set(
                        workout.exercises
                            .filter {
                                $0.groupID ==
                                groupID
                            }
                            .map(\.id)
                    )
            )
        } else {
            _selectedIDs = State(
                initialValue:
                    Set([currentExerciseID])
            )
        }

        _style = State(
            initialValue:
                current?.groupStyle ??
                .superset
        )
    }

    private var currentIsGrouped: Bool {
        workout.exercises
            .first {
                $0.id ==
                currentExerciseID
            }?
            .groupID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Style",
                            norwegian: "Type"
                        ),
                        selection: $style
                    ) {
                        ForEach(
                            StrengthExerciseGroupStyle
                                .allCases
                        ) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Exercises",
                        norwegian: "Øvelser"
                    )
                ) {
                    ForEach(
                        workout.exercises.filter {
                            !$0.isCompleted ||
                            $0.id ==
                            currentExerciseID
                        }
                    ) { exercise in
                        Button {
                            if exercise.id ==
                                currentExerciseID {
                                return
                            }

                            if selectedIDs
                                .contains(
                                    exercise.id
                                ) {
                                selectedIDs.remove(
                                    exercise.id
                                )
                            } else {
                                selectedIDs.insert(
                                    exercise.id
                                )
                            }
                        } label: {
                            HStack {
                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        exercise
                                            .exercise
                                            .name
                                    )
                                    .foregroundStyle(
                                        .primary
                                    )

                                    Text(
                                        exercise.exercise
                                            .primaryMuscles
                                            .prefix(2)
                                            .joined(
                                                separator:
                                                    " · "
                                            )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        selectedIDs
                                            .contains(
                                                exercise.id
                                            )
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                                .foregroundStyle(
                                    selectedIDs
                                        .contains(
                                            exercise.id
                                        )
                                        ? ATHLTHTheme
                                            .accent
                                        : .secondary
                                )
                            }
                        }
                        .disabled(
                            exercise.id ==
                            currentExerciseID
                        )
                    }
                }

                Section {
                    Text(
                        style == .superset
                            ? ATHLTHLocalization.choose(
                                english:
                                    "ATHLTH moves between the linked exercises before starting the rest timer.",
                                norwegian:
                                    "ATHLTH går mellom de koblede øvelsene før hviletimeren starter."
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Circuit mode rotates through all selected exercises, then rests before the next round.",
                                norwegian:
                                    "Sirkelmodus går gjennom alle valgte øvelser og tar deretter pause før neste runde."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if currentIsGrouped {
                    Section {
                        Button(
                            role: .destructive
                        ) {
                            onUngroup()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Remove from group",
                                    norwegian:
                                        "Fjern øvelsesgruppe"
                                ),
                                systemImage:
                                    "link.badge.minus"
                            )
                        }
                    }
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Superset / Circuit",
                    norwegian:
                        "Supersett / sirkel"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Save",
                            norwegian: "Lagre"
                        )
                    ) {
                        onSave(
                            Array(selectedIDs),
                            style
                        )
                    }
                    .disabled(
                        selectedIDs.count < 2
                    )
                }
            }
        }
    }
}

private struct StrengthExerciseRestEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: StrengthExerciseLog
    let fallbackSeconds: Int
    let onSave: (Int) -> Void

    @State private var seconds: Int

    init(
        exercise: StrengthExerciseLog,
        fallbackSeconds: Int,
        onSave: @escaping (Int) -> Void
    ) {
        self.exercise = exercise
        self.fallbackSeconds =
            fallbackSeconds
        self.onSave = onSave

        _seconds = State(
            initialValue:
                exercise.restSecondsOverride ??
                exercise.sets.first(
                    where: {
                        !$0.isCompleted
                    }
                )?.restSeconds ??
                fallbackSeconds
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    exercise.exercise.name
                ) {
                    Stepper(
                        value: $seconds,
                        in: 0...600,
                        step: 15
                    ) {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Rest",
                                    norwegian: "Hvile"
                                )
                            )
                            Spacer()
                            Text(
                                seconds == 0
                                    ? ATHLTHLocalization.choose(
                                        english: "None",
                                        norwegian: "Ingen"
                                    )
                                    : "\(seconds) s"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "This overrides the workout default for the remaining sets of this exercise.",
                            norwegian:
                                "Dette overstyrer standard hviletid for de resterende settene i denne øvelsen."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Exercise Rest",
                    norwegian: "Hvile for øvelsen"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Save",
                            norwegian: "Lagre"
                        )
                    ) {
                        onSave(seconds)
                    }
                }
            }
        }
    }
}

private struct StrengthPlateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var targetWeight:
        Double
    @State private var barWeight:
        Double = 20

    private let plates:
        [Double] = [
            25,
            20,
            15,
            10,
            5,
            2.5,
            1.25,
            0.5
        ]
    @State private var availablePlates:
        Set<Double>

    init(
        targetWeightKilograms:
            Double
    ) {
        _targetWeight = State(
            initialValue:
                max(
                    targetWeightKilograms,
                    0
                )
        )
        _availablePlates = State(
            initialValue:
                Set([
                    25,
                    20,
                    15,
                    10,
                    5,
                    2.5,
                    1.25
                ])
        )
    }

    private var plateResult:
        (
            plates:
                [(Double, Int)],
            loaded: Double,
            remainder: Double
        ) {
        guard targetWeight >=
                barWeight
        else {
            return (
                [],
                barWeight,
                targetWeight -
                    barWeight
            )
        }

        var remaining =
            (targetWeight - barWeight) /
            2
        var result:
            [(Double, Int)] = []

        for plate in plates
        where availablePlates.contains(plate) {
            let count =
                Int(
                    floor(
                        (
                            remaining +
                            0.0001
                        ) / plate
                    )
                )

            if count > 0 {
                result.append(
                    (plate, count)
                )
                remaining -=
                    Double(count) *
                    plate
            }
        }

        let perSide =
            result.reduce(0.0) {
                partial,
                item in
                partial +
                    item.0 *
                    Double(item.1)
            }

        return (
            result,
            barWeight +
                perSide * 2,
            remaining * 2
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    ATHLTHLocalization.choose(
                        english: "Target",
                        norwegian: "Mål"
                    )
                ) {
                    Stepper(
                        value: $targetWeight,
                        in: 0...500,
                        step: 0.5
                    ) {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Total weight",
                                    norwegian: "Totalvekt"
                                )
                            )
                            Spacer()
                            Text(
                                "\(targetWeight, specifier: "%.1f") kg"
                            )
                            .monospacedDigit()
                        }
                    }

                    Picker(
                        ATHLTHLocalization.choose(
                            english: "Bar",
                            norwegian: "Stang"
                        ),
                        selection: $barWeight
                    ) {
                        Text("20 kg")
                            .tag(20.0)
                        Text("15 kg")
                            .tag(15.0)
                        Text("10 kg")
                            .tag(10.0)
                    }
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Available plates",
                        norwegian: "Tilgjengelige skiver"
                    )
                ) {
                    ForEach(
                        plates,
                        id: \.self
                    ) { plate in
                        Toggle(
                            "\(plate, specifier: "%g") kg",
                            isOn:
                                Binding(
                                    get: {
                                        availablePlates
                                            .contains(
                                                plate
                                            )
                                    },
                                    set: {
                                        enabled in
                                        if enabled {
                                            availablePlates
                                                .insert(
                                                    plate
                                                )
                                        } else {
                                            availablePlates
                                                .remove(
                                                    plate
                                                )
                                        }
                                    }
                                )
                        )
                    }
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Load each side",
                        norwegian: "Legg på hver side"
                    )
                ) {
                    if targetWeight <
                        barWeight {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Target is lighter than the selected bar.",
                                norwegian:
                                    "Målvekten er lavere enn valgt stang."
                            )
                        )
                        .foregroundStyle(.secondary)
                    } else if
                        plateResult.plates
                            .isEmpty {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Bar only",
                                norwegian:
                                    "Kun stang"
                            )
                        )
                    } else {
                        ForEach(
                            Array(
                                plateResult.plates
                                    .enumerated()
                            ),
                            id: \.offset
                        ) { _, item in
                            HStack {
                                Text(
                                    "\(item.0, specifier: "%g") kg"
                                )
                                Spacer()
                                Text(
                                    "× \(item.1)"
                                )
                                .font(
                                    .headline
                                        .monospacedDigit()
                                )
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Loaded weight",
                                norwegian: "Lastet vekt"
                            )
                        )
                        Spacer()
                        Text(
                            "\(plateResult.loaded, specifier: "%.1f") kg"
                        )
                        .font(
                            .headline
                                .monospacedDigit()
                        )
                    }

                    if abs(
                        plateResult.remainder
                    ) > 0.01 {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    String(
                                        format:
                                            "Closest load with the available standard plates. Difference: %.1f kg.",
                                        abs(
                                            plateResult
                                                .remainder
                                        )
                                    ),
                                norwegian:
                                    String(
                                        format:
                                            "Nærmeste last med tilgjengelige standardskiver. Forskjell: %.1f kg.",
                                        abs(
                                            plateResult
                                                .remainder
                                        )
                                    )
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Plate Calculator",
                    norwegian: "Skivekalkulator"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
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
