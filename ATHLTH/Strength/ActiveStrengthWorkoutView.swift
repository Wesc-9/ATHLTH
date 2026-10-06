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
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var social: SocialStore

    @StateObject private var socialCompanion =
        SocialWorkoutCompanionStore()
    @State private var showingFinishConfirmation = false
    @State private var finishInProgress = false
    @State private var watchFinishTimeoutTask:
        Task<Void, Never>?
    @State private var watchFinishError: String?
    @State private var showingExerciseLibrary = false
    @State private var pendingExercise: ExerciseLibraryEntry?
    @State private var editingSetResult:
        StrengthSetResultEditTarget?
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
    @State private var focusedExerciseMediaIndex = 0
    @State private var showingExerciseInstructions = false

    var body: some View {
        NavigationStack {
            Group {
                if let workout = strength.activeWorkout {
                    if workout.exercises.isEmpty {
                        ScrollView {
                            VStack(spacing: 18) {
                                workoutHeader(workout)
                                TrainTogetherStatusStrip()
                                addExerciseCard(workout)
                                simpleTrackingContent(
                                    workout: workout
                                )
                                recordingStatusCard(
                                    workout
                                )
                            }
                            .padding()
                        }
                    } else if let exercise =
                                strength
                                    .currentExercise {
                        ScrollView {
                            focusedStrengthContent(
                                workout: workout,
                                exercise: exercise
                            )
                            .padding(
                                .horizontal,
                                16
                            )
                            .padding(.top, 12)
                            .padding(
                                .bottom,
                                36
                            )
                        }
                        .scrollIndicators(.hidden)
                    } else {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "Workout is ready",
                                norwegian:
                                    "Økten er klar"
                            ),
                            systemImage:
                                "checkmark.circle",
                            description: Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Finish the workout when you are done.",
                                    norwegian:
                                        "Avslutt økten når du er ferdig."
                                )
                            )
                        )
                    }
                } else {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english:
                                "No active strength workout",
                            norwegian:
                                "Ingen aktiv styrkeøkt"
                        ),
                        systemImage: "dumbbell",
                        description: Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Start a strength session from Train.",
                                norwegian:
                                    "Start en styrkeøkt fra Trening."
                            )
                        )
                    )
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Strength",
                    norwegian: "Styrke"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(
                    placement:
                        .topBarTrailing
                ) {
                    // Adding exercises while the timer is running is reserved
                    // for explicit freestyle / no-plan workouts. Planned
                    // sessions stay distraction-free once training starts.
                    if strength
                        .activeWorkout?
                        .allowsLiveExerciseBuilding ==
                        true {
                        Button {
                            showingExerciseLibrary =
                                true
                        } label: {
                            Image(
                                systemName: "plus"
                            )
                        }
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Add exercise",
                                norwegian:
                                    "Legg til øvelse"
                            )
                        )
                    }

                    Button(
                        ATHLTHLocalization.choose(
                            english: "Finish",
                            norwegian: "Avslutt"
                        )
                    ) {
                        showingFinishConfirmation =
                            true
                    }
                    .disabled(
                        strength.activeWorkout ==
                            nil ||
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
                        targetKind: $2,
                        targetDurationSeconds: $3,
                        loadKind: $4,
                        targetWeightKilograms: $5,
                        targetResistanceLevel: $6,
                        restSeconds: $7,
                        warmUpSets: $8
                    )
                    pendingExercise = nil
                    loadDefaultsFromCurrentSet()
                }
            }
            .sheet(
                item: $editingSetResult
            ) { target in
                StrengthSetResultEditorView(
                    target: target
                ) {
                    segments,
                    distanceMeters,
                    resistanceLevel in

                    strength.updateActiveSetResult(
                        exerciseID:
                            target.exerciseID,
                        setID:
                            target.set.id,
                        segments:
                            segments,
                        distanceMeters:
                            distanceMeters,
                        resistanceLevel:
                            resistanceLevel
                    )
                    editingSetResult = nil
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
                Button(
                    ATHLTHLocalization.choose(
                        english: "Try Again",
                        norwegian: "Prøv igjen"
                    )
                ) {
                    watchFinishError = nil

                    Task {
                        await finishWorkout()
                    }
                }

                Button(
                    "OK",
                    role: .cancel
                ) {
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
                spotify.endLinkedWorkoutPlaybackSession()
                appSession.endTrainingStatus()
                dismiss()
            }
            .onChange(
                of:
                    workoutMirroring
                        .snapshot?
                        .state
            ) { _, newState in
                guard newState == .completed else {
                    return
                }

                finalizeWatchStrengthFromMirrorIfNeeded()
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

                focusedExerciseMediaIndex = 0
                showingExerciseInstructions = false
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
        .task(
            id:
                social
                    .currentJoinedWorkoutSessionID ??
                social
                    .activeWorkoutSession?
                    .id
        ) {
            guard
                let sessionID =
                    social
                        .currentJoinedWorkoutSessionID ??
                    social
                        .activeWorkoutSession?
                        .id,
                let userID =
                    social.currentUserID
            else {
                return
            }

            while !Task.isCancelled {
                guard let workout =
                        strength.activeWorkout
                else {
                    return
                }

                await socialCompanion
                    .publishStrength(
                        sessionID:
                            sessionID,
                        userID:
                            userID,
                        displayName:
                            appSession
                                .profile
                                .displayName,
                        workout:
                            workout,
                        currentExerciseIndex:
                            strength
                                .currentExerciseIndex,
                        currentSetIndex:
                            strength
                                .currentSetIndex,
                        isResting:
                            strength
                                .isResting
                    )

                try? await Task.sleep(
                    for: .seconds(3)
                )
            }
        }
        // A strength workout is a true full-screen surface. Spotify can
        // temporarily move ATHLTH to the background while App Remote wakes the
        // Spotify app. When iOS restores this fullScreenCover, an explicit
        // opaque canvas prevents the underlying Home/Train hierarchy and tab
        // bar from being composited through the workout.
        .background {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .vitality
                        .opacity(0.22)
            )
        }
        .toolbarBackground(
            ATHLTHTheme.canvasTop,
            for: .navigationBar
        )
        .toolbarBackground(
            .visible,
            for: .navigationBar
        )
        .presentationBackground(
            ATHLTHTheme.canvasTop
        )
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
                "Next exercise. \(exercise.exercise.displayName).",
            norwegian:
                "Neste øvelse. \(exercise.exercise.displayName).",
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
            // Use both transports. HealthKit mirroring is the fastest route
            // when attached, while WatchConnectivity keeps a durable .end
            // command queued if the mirrored channel disappears mid-finish.
            if workoutMirroring
                .hasActiveMirroredWorkout {
                _ = workoutMirroring
                    .sendCommand(.end)
            }

            watchConnection
                .sendWorkoutCommand(
                    .end,
                    workoutID:
                        workout.id
                )

            watchFinishTimeoutTask?.cancel()
            let workoutID = workout.id

            watchFinishTimeoutTask =
                Task { @MainActor in
                    // HealthKit may need several seconds to end collection and
                    // persist the workout. Retry the durable command once
                    // before treating the finish as delayed.
                    try? await Task.sleep(
                        for: .seconds(10)
                    )

                    guard !Task.isCancelled,
                          strength
                            .activeWorkout?
                            .id == workoutID
                    else {
                        return
                    }

                    if workoutMirroring
                        .snapshot?
                        .state == .completed {
                        finalizeWatchStrengthFromMirrorIfNeeded()
                        return
                    }

                    watchConnection
                        .sendWorkoutCommand(
                            .end,
                            workoutID:
                                workoutID
                        )

                    try? await Task.sleep(
                        for: .seconds(35)
                    )

                    guard !Task.isCancelled,
                          strength
                            .activeWorkout?
                            .id == workoutID
                    else {
                        return
                    }

                    if workoutMirroring
                        .snapshot?
                        .state == .completed {
                        finalizeWatchStrengthFromMirrorIfNeeded()
                        return
                    }

                    // If the Watch is explicitly in its HealthKit ending
                    // phase, do not show a false error after the old 18-second
                    // deadline. Give final persistence/delivery extra time.
                    if workoutMirroring
                        .snapshot?
                        .state == .ending {
                        try? await Task.sleep(
                            for: .seconds(30)
                        )

                        guard !Task.isCancelled,
                              strength
                                .activeWorkout?
                                .id == workoutID
                        else {
                            return
                        }

                        if workoutMirroring
                            .snapshot?
                            .state == .completed {
                            finalizeWatchStrengthFromMirrorIfNeeded()
                            return
                        }
                    }

                    finishInProgress = false
                    watchFinishError =
                        ATHLTHLocalization.choose(
                            english:
                                "Apple Watch has not confirmed the finish yet. Your ATHLTH strength log is safe. You can try again here; if the Watch has already finished, ATHLTH will attach its Health data automatically when it arrives.",
                            norwegian:
                                "Apple Watch har ikke bekreftet avslutningen ennå. Styrkeloggen i ATHLTH er trygg. Du kan prøve igjen her; hvis klokken allerede er ferdig, kobler ATHLTH automatisk til Health-data når de kommer."
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

    @MainActor
    private func finalizeWatchStrengthFromMirrorIfNeeded() {
        guard let workout =
                strength.activeWorkout,
              workout.captureDevice ==
                .appleWatch,
              let snapshot =
                workoutMirroring.snapshot,
              snapshot.kind == .strength,
              snapshot.state == .completed
        else {
            return
        }

        if let mirroredStartedAt =
                snapshot.startedAt,
           abs(
                mirroredStartedAt
                    .timeIntervalSince(
                        workout.startedAt
                    )
           ) >= 180 {
            return
        }

        watchFinishTimeoutTask?.cancel()
        watchFinishTimeoutTask = nil
        watchFinishError = nil
        finishInProgress = false

        // The mirrored completed state is authoritative proof that the Watch
        // session ended. Finish the local strength log immediately so the UI
        // never gets stuck waiting for WCSession delivery. The later
        // WatchWorkoutResult attaches the HealthKit UUID and final metrics.
        strength.finish(
            healthKitWorkoutUUID: nil,
            duration:
                max(
                    snapshot.elapsedTime,
                    Date()
                        .timeIntervalSince(
                            workout.startedAt
                        )
                ),
            activeCalories:
                snapshot.activeCalories,
            averageHeartRate:
                snapshot.averageHeartRate,
            maxHeartRate:
                snapshot.maxHeartRate
        )
        appSession.endTrainingStatus()
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
    private func focusedStrengthContent(
        workout: StrengthWorkoutLog,
        exercise: StrengthExerciseLog
    ) -> some View {
        let workoutComplete =
            workout.exercises
                .allSatisfy {
                    $0.isCompleted
                }

        VStack(spacing: 14) {
            focusedWorkoutStatus(
                workout
            )

            if workoutComplete {
                focusedWorkoutCompletionHero(
                    workout
                )

                focusedWorkoutSummaryMetrics(
                    workout
                )

                focusedWorkoutRestSummary(
                    workout
                )

                focusedWorkoutExerciseReview(
                    workout
                )

                Button {
                    showingFinishConfirmation =
                        true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Finish workout",
                            norwegian:
                                "Avslutt økten"
                        ),
                        systemImage:
                            "flag.checkered"
                    )
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 56
                    )
                    .background(
                        LinearGradient(
                            colors: [
                                ATHLTHTheme
                                    .accentDeep,
                                ATHLTHTheme
                                    .vitality
                            ],
                            startPoint:
                                .leading,
                            endPoint:
                                .trailing
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 20,
                                style:
                                    .continuous
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                focusedExerciseHero(
                    workout: workout,
                    exercise: exercise
                )

                if let suggestion =
                        strength
                            .progressionSuggestion(
                                for: exercise
                            ) {
                    focusedProgressionHint(
                        suggestion
                    )
                }

                if !canLogOnIPhone(
                    workout
                ) {
                    watchInputCompanionCard(
                        workout: workout
                    )
                } else if strength
                    .currentExerciseAllSetsCompleted {
                    VStack(spacing: 12) {
                        focusedExerciseTransition(
                            workout: workout,
                            exercise: exercise
                        )

                        if let latest =
                                latestCompletedSet(
                                    in: exercise
                                ) {
                            postSetResultButton(
                                exercise: exercise,
                                set: latest
                            )
                        }
                    }
                } else if strength.isResting {
                    VStack(spacing: 12) {
                        focusedSetRest(
                            exercise: exercise
                        )

                        if let latest =
                                latestCompletedSet(
                                    in: exercise
                                ) {
                            postSetResultButton(
                                exercise: exercise,
                                set: latest
                            )
                        }
                    }
                } else {
                    focusedSetEntry(
                        exercise: exercise
                    )
                }
            }
        }
    }

    private func focusedWorkoutCompletionHero(
        _ workout: StrengthWorkoutLog
    ) -> some View {
        ZStack(
            alignment: .bottomLeading
        ) {
            Image(
                "StrengthPostWorkoutHero"
            )
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .athlthBoundedFill()
            .frame(height: 190)
            .clipped()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black
                        .opacity(0.68)
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Workout complete",
                        norwegian:
                            "Økten er gjennomført"
                    ),
                    systemImage:
                        "checkmark.seal.fill"
                )
                .font(
                    .caption.weight(.bold)
                )
                .foregroundStyle(
                    .white.opacity(0.86)
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Review before saving",
                        norwegian:
                            "Se gjennom før du lagrer"
                    )
                )
                .font(
                    .title2.weight(.bold)
                )
                .foregroundStyle(.white)

                Text(
                    ATHLTHLocalization.format(
                        english:
                            "%d exercises · %d working sets",
                        norwegian:
                            "%d øvelser · %d arbeidssett",
                        workout.exercises.count,
                        workout.totalWorkingSets
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .white.opacity(0.82)
                )
            }
            .padding(16)
        }
        .frame(height: 190)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.45),
                lineWidth: 0.8
            )
        }
    }

    private func focusedWorkoutSummaryMetrics(
        _ workout: StrengthWorkoutLog
    ) -> some View {
        TimelineView(
            .periodic(
                from: .now,
                by: 1
            )
        ) { context in
            let totalDuration =
                max(
                    context.date
                        .timeIntervalSince(
                            workout.startedAt
                        ),
                    0
                )
            let restDuration =
                workout
                    .totalActualRestSeconds
            let activeDuration =
                max(
                    totalDuration -
                    restDuration,
                    0
                )

            LazyVGrid(
                columns: [
                    GridItem(
                        .flexible(),
                        spacing: 10
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 10
                    )
                ],
                spacing: 10
            ) {
                completionMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Total time",
                            norwegian:
                                "Total tid"
                        ),
                    value:
                        totalDuration
                            .clockDuration,
                    icon: "clock.fill"
                )

                completionMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Active time",
                            norwegian:
                                "Aktiv tid"
                        ),
                    value:
                        activeDuration
                            .clockDuration,
                    icon: "bolt.fill"
                )

                completionMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Rest",
                            norwegian: "Pause"
                        ),
                    value:
                        restDuration
                            .clockDuration,
                    icon:
                        "pause.circle.fill"
                )

                completionMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Volume",
                            norwegian: "Volum"
                        ),
                    value:
                        formatWorkoutVolume(
                            workout
                                .totalVolumeKilograms
                        ),
                    icon: "scalemass.fill"
                )

                completionMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Reps",
                            norwegian:
                                "Repetisjoner"
                        ),
                    value:
                        "\(workout.totalCompletedReps)",
                    icon: "repeat"
                )

                completionMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "Working sets",
                            norwegian:
                                "Arbeidssett"
                        ),
                    value:
                        "\(workout.totalWorkingSets)",
                    icon: "list.number"
                )
            }
        }
    }

    private func completionMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            HStack(spacing: 6) {
                Image(
                    systemName: icon
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )

                Text(title)
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }

            Text(value)
                .font(
                    .title3
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(14)
        .background(
            .ultraThinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.72),
                lineWidth: 0.8
            )
        }
    }

    @ViewBuilder
    private func focusedWorkoutRestSummary(
        _ workout: StrengthWorkoutLog
    ) -> some View {
        let rests =
            workout.exercises
                .flatMap { exercise in
                    exercise.sets
                        .compactMap {
                            $0.actualRestAfterSeconds
                        }
                }

        if !rests.isEmpty {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Rest overview",
                            norwegian:
                                "Pauseoversikt"
                        ),
                        systemImage:
                            "stopwatch.fill"
                    )
                    .font(.headline)

                    Spacer()

                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "%d rests",
                            norwegian:
                                "%d pauser",
                            rests.count
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                HStack(spacing: 10) {
                    restSummaryPill(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Average",
                                norwegian:
                                    "Snitt"
                            ),
                        value:
                            workout
                                .averageActualRestSeconds
                                .clockDuration
                    )

                    restSummaryPill(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Longest",
                                norwegian:
                                    "Lengste"
                            ),
                        value:
                            workout
                                .longestActualRestSeconds
                                .clockDuration
                    )
                }

                ForEach(
                    workout.exercises
                ) { exercise in
                    let exerciseRests =
                        exercise.sets
                            .compactMap {
                                $0.actualRestAfterSeconds
                            }

                    if !exerciseRests.isEmpty {
                        HStack {
                            Text(
                                exercise.exercise
                                    .displayName
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .lineLimit(1)

                            Spacer()

                            Text(
                                exerciseRests
                                    .map {
                                        $0.clockDuration
                                    }
                                    .joined(
                                        separator: " · "
                                    )
                            )
                            .font(
                                .caption
                                    .monospacedDigit()
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                    }
                }
            }
            .padding(16)
            .background(
                .ultraThinMaterial,
                in:
                    RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.vitality
                        .opacity(0.12),
                    lineWidth: 1
                )
            }
        }
    }

    private func restSummaryPill(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            Text(value)
                .font(
                    .headline
                        .monospacedDigit()
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(12)
        .background(
            ATHLTHTheme
                .surfaceSage
                .opacity(0.55),
            in:
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
        )
    }

    private func focusedWorkoutExerciseReview(
        _ workout: StrengthWorkoutLog
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Exercise results",
                            norwegian:
                                "Øvelsesresultater"
                        )
                    )
                    .font(.headline)

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Tap a set to correct reps, weight or load splits before saving.",
                            norwegian:
                                "Trykk på et sett for å rette reps, vekt eller belastningsendringer før du lagrer."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }

            ForEach(
                workout.exercises
            ) { exercise in
                completionExerciseCard(
                    exercise
                )
            }
        }
    }

    private func completionExerciseCard(
        _ exercise:
            StrengthExerciseLog
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        exercise.exercise
                            .displayName
                    )
                    .font(
                        .subheadline
                            .weight(.bold)
                    )

                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "%d completed sets",
                            norwegian:
                                "%d fullførte sett",
                            exercise.sets
                                .filter {
                                    $0.isCompleted
                                }
                                .count
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                let volume =
                    exercise.sets
                        .reduce(0.0) {
                            $0 +
                            $1.volumeKilograms
                        }

                if volume > 0 {
                    Text(
                        formatWorkoutVolume(
                            volume
                        )
                    )
                    .font(
                        .caption
                            .monospacedDigit()
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                }
            }

            Divider()

            ForEach(
                exercise.sets.filter {
                    $0.isCompleted
                }
            ) { set in
                Button {
                    editingSetResult =
                        StrengthSetResultEditTarget(
                            exerciseID:
                                exercise.id,
                            exerciseName:
                                exercise.exercise
                                    .displayName,
                            exercise:
                                exercise.exercise,
                            set: set
                        )
                } label: {
                    HStack(spacing: 10) {
                        Text(
                            "\(set.setNumber)"
                        )
                        .font(
                            .caption
                                .monospacedDigit()
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )
                        .frame(
                            width: 28,
                            height: 28
                        )
                        .background(
                            ATHLTHTheme
                                .vitalitySoft,
                            in: Circle()
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                strengthSetResultText(
                                    set
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                            if let rest =
                                    set
                                        .actualRestAfterSeconds {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Rest after set: \(rest.clockDuration)",
                                        norwegian:
                                            "Pause etter sett: \(rest.clockDuration)"
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }
                        }

                        Spacer()

                        Image(
                            systemName:
                                "pencil"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                        .frame(
                            width: 32,
                            height: 32
                        )
                        .background(
                            Color.white
                                .opacity(0.62),
                            in: Circle()
                        )
                    }
                    .contentShape(
                        Rectangle()
                    )
                }
                .buttonStyle(.plain)

                if set.id !=
                    exercise.sets
                        .filter({
                            $0.isCompleted
                        })
                        .last?
                        .id {
                    Divider()
                }
            }
        }
        .padding(15)
        .background(
            .ultraThinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.72),
                lineWidth: 0.8
            )
        }
    }

    private func strengthSetResultText(
        _ set: StrengthSetLog
    ) -> String {
        if let segments =
                set.effortSegments,
           segments.count > 1 {
            let parts =
                segments.compactMap {
                    segment -> String? in

                    guard let reps =
                            segment.reps
                    else {
                        return nil
                    }

                    if let weight =
                            segment
                                .weightKilograms {
                        return
                            "\(reps)×\(formatWeight(weight)) kg"
                    }

                    return "\(reps) reps"
                }

            if !parts.isEmpty {
                return parts.joined(
                    separator: " + "
                )
            }
        }

        if set.resolvedTargetKind ==
            .time {
            return
                TimeInterval(
                    set.resolvedCompletedDurationSeconds ??
                    0
                )
                .clockDuration
        }

        let reps =
            set.resolvedCompletedReps ??
            0

        if set.resolvedLoadKind ==
            .resistanceLevel {
            return
                ATHLTHLocalization.choose(
                    english:
                        "\(reps) reps · level \(set.completedResistanceLevel ?? set.plannedResistanceLevel ?? 0)",
                    norwegian:
                        "\(reps) reps · steg \(set.completedResistanceLevel ?? set.plannedResistanceLevel ?? 0)"
                )
        }

        if let weight =
                set.completedWeightKilograms {
            return
                "\(reps) × " +
                formatWeight(weight) +
                " kg"
        }

        return "\(reps) reps"
    }

    private func formatWorkoutVolume(
        _ value: Double
    ) -> String {
        if value >= 1_000 {
            let tonnes =
                value / 1_000
            return
                String(
                    format: "%.1f t",
                    tonnes
                )
        }

        return
            formatWeight(value) +
            " kg"
    }

    private func focusedWorkoutStatus(
        _ workout: StrengthWorkoutLog
    ) -> some View {
        HStack(spacing: 10) {
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(workout.title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                TimelineView(
                    .periodic(
                        from: .now,
                        by: 1
                    )
                ) { context in
                    Text(
                        context.date
                            .timeIntervalSince(
                                workout.startedAt
                            )
                            .clockDuration
                    )
                    .font(
                        .title3
                            .monospacedDigit()
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                }
            }

            Spacer()

            Label(
                workout.captureDevice.title,
                systemImage:
                    workout.captureDevice ==
                        .appleWatch
                        ? "applewatch"
                        : "iphone"
            )
            .font(
                .caption
                    .weight(.semibold)
            )
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
        }
        .padding(
            .horizontal,
            4
        )
    }

    private func focusedExerciseHero(
        workout: StrengthWorkoutLog,
        exercise: StrengthExerciseLog
    ) -> some View {
        let mediaURLs =
            focusedExerciseMediaURLs(
                exercise
            )

        return VStack(spacing: 0) {
            ZStack(
                alignment:
                    .bottomLeading
            ) {
                focusedExerciseMediaCarousel(
                    exercise,
                    urls: mediaURLs
                )
                .frame(height: 205)
                .frame(
                    maxWidth: .infinity
                )
                .clipped()

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black
                            .opacity(0.66)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "Exercise %d of %d",
                            norwegian:
                                "Øvelse %d av %d",
                            strength
                                .currentExerciseIndex +
                                1,
                            workout.exercises.count
                        )
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        .white.opacity(0.78)
                    )

                    Text(
                        exercise.exercise.displayName
                    )
                    .font(
                        .title2
                            .weight(.bold)
                    )
                    .foregroundStyle(.white)
                    .lineLimit(2)

                    if !exercise
                        .exercise
                        .primaryMuscles
                        .isEmpty {
                        Text(
                            exercise
                                .exercise
                                .primaryMuscles
                                .prefix(3)
                                .joined(
                                    separator: " · "
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .white.opacity(0.78)
                        )
                        .lineLimit(1)
                    }
                }
                .padding(16)
                .allowsHitTesting(false)

                if mediaURLs.count > 1 {
                    VStack {
                        HStack {
                            Spacer()

                            Text(
                                "\(min(focusedExerciseMediaIndex + 1, mediaURLs.count)) / \(mediaURLs.count)"
                            )
                            .font(
                                .caption2
                                    .monospacedDigit()
                                    .weight(.bold)
                            )
                            .foregroundStyle(.white)
                            .padding(
                                .horizontal,
                                9
                            )
                            .padding(
                                .vertical,
                                5
                            )
                            .background(
                                Color.black
                                    .opacity(0.30),
                                in: Capsule()
                            )
                            .background(
                                .ultraThinMaterial,
                                in: Capsule()
                            )
                        }

                        Spacer()

                        HStack(spacing: 5) {
                            Spacer()

                            ForEach(
                                mediaURLs.indices,
                                id: \.self
                            ) { index in
                                Capsule()
                                    .fill(
                                        index ==
                                            focusedExerciseMediaIndex
                                            ? Color.white
                                            : Color.white
                                                .opacity(0.42)
                                    )
                                    .frame(
                                        width:
                                            index ==
                                                focusedExerciseMediaIndex
                                                ? 15
                                                : 5,
                                        height: 5
                                    )
                                    .animation(
                                        .easeOut(
                                            duration: 0.18
                                        ),
                                        value:
                                            focusedExerciseMediaIndex
                                    )
                            }
                        }
                    }
                    .padding(12)
                    .allowsHitTesting(false)
                }
            }

            focusedExerciseInstructionDisclosure(
                exercise
            )

            HStack(spacing: 0) {
                focusedHeroMetric(
                    value:
                        "\((strength.currentSet?.setNumber) ?? max(exercise.sets.count, 1)) / \(max(exercise.sets.count, 1))",
                    label:
                        ATHLTHLocalization.choose(
                            english: "SET",
                            norwegian: "SETT"
                        ),
                    icon:
                        "list.number"
                )

                focusedHeroDivider

                focusedHeroMetric(
                    value:
                        currentStrengthTargetKind == .time
                            ? TimeInterval(
                                strength
                                    .draftDurationSeconds
                            )
                            .clockDuration
                            : "\(strength.draftReps)",
                    label:
                        currentStrengthTargetKind == .time
                            ? ATHLTHLocalization.choose(
                                english: "TIME",
                                norwegian: "TID"
                            )
                            : ATHLTHLocalization.choose(
                                english: "REPS",
                                norwegian: "REPS"
                            ),
                    icon:
                        currentStrengthTargetKind == .time
                            ? "timer"
                            : "repeat"
                )

                focusedHeroDivider

                focusedHeroMetric(
                    value:
                        currentStrengthLoadKind ==
                            .resistanceLevel
                            ? "\(strength.draftResistanceLevel)"
                            : formatWeight(
                                strength
                                    .draftWeightKilograms
                            ) + " kg",
                    label:
                        currentStrengthLoadKind ==
                            .resistanceLevel
                            ? ATHLTHLocalization.choose(
                                english: "RESIST.",
                                norwegian: "MOTST."
                            )
                            : ATHLTHLocalization.choose(
                                english: "WEIGHT",
                                norwegian: "VEKT"
                            ),
                    icon:
                        currentStrengthLoadKind ==
                            .resistanceLevel
                            ? "dial.medium"
                            : "scalemass"
                )

                focusedHeroDivider

                focusedHeroMetric(
                    value:
                        "\(strength.draftRestSeconds)s",
                    label:
                        ATHLTHLocalization.choose(
                            english: "REST",
                            norwegian: "PAUSE"
                        ),
                    icon: "timer"
                )
            }
            .padding(.vertical, 12)
            .background(
                Color.white.opacity(0.90)
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border,
                lineWidth: 1
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.06),
            radius: 18,
            y: 8
        )
    }

    @ViewBuilder
    private func focusedExerciseMediaCarousel(
        _ exercise: StrengthExerciseLog,
        urls: [URL]
    ) -> some View {
        if urls.count > 1 {
            TabView(
                selection:
                    $focusedExerciseMediaIndex
            ) {
                ForEach(
                    Array(
                        urls.enumerated()
                    ),
                    id: \.offset
                ) { index, url in
                    focusedExerciseArtwork(
                        url: url,
                        exercise: exercise
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(
                .page(
                    indexDisplayMode: .never
                )
            )
        } else if let url =
                    urls.first {
            focusedExerciseArtwork(
                url: url,
                exercise: exercise
            )
        } else {
            focusedExerciseArtworkFallback(
                exercise
            )
        }
    }

    @ViewBuilder
    private func focusedExerciseArtwork(
        url: URL,
        exercise: StrengthExerciseLog
    ) -> some View {
        if url.isFileURL,
           let image =
                UIImage(
                    contentsOfFile:
                        url.path
                ) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ATHLTHStorageImage(
                url: url
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    focusedExerciseArtworkFallback(
                        exercise
                    )

                case .empty:
                    ZStack {
                        focusedExerciseArtworkFallback(
                            exercise
                        )

                        ProgressView()
                            .tint(
                                ATHLTHTheme
                                    .accentDeep
                            )
                    }

                @unknown default:
                    focusedExerciseArtworkFallback(
                        exercise
                    )
                }
            }
        }
    }

    private func focusedExerciseMediaURLs(
        _ exercise: StrengthExerciseLog
    ) -> [URL] {
        var values: [URL] = []

        func appendUnique(
            _ url: URL?
        ) {
            guard let url,
                  !values.contains(
                    where: {
                        $0.absoluteString ==
                            url.absoluteString
                    }
                  )
            else {
                return
            }

            values.append(url)
        }

        if let entry =
                focusedExerciseLibraryEntry(
                    exercise
                ) {
            // RepDB commonly exposes start + peak frames. Keep that
            // movement order instead of showing arbitrary alternate art.
            appendUnique(
                entry.imageStartURL
            )
            appendUnique(
                entry.imagePeakURL
            )
            appendUnique(
                entry.exercise.imageURL
            )
        }

        appendUnique(
            exercise.exercise.imageURL
        )

        return values
    }

    private func focusedExerciseLibraryEntry(
        _ exercise: StrengthExerciseLog
    ) -> ExerciseLibraryEntry? {
        let snapshotName =
            exercise.exercise.name
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

        if let snapshotURL =
                exercise.exercise.imageURL,
           let exactMediaMatch =
                exerciseLibrary
                    .allExercises
                    .first(
                        where: {
                            $0.exercise.imageURL ==
                                snapshotURL ||
                            $0.imageStartURL ==
                                snapshotURL ||
                            $0.imagePeakURL ==
                                snapshotURL
                        }
                    ) {
            return exactMediaMatch
        }

        let nameMatches =
            exerciseLibrary
                .allExercises
                .filter {
                    $0.exercise.name
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
                        .lowercased() ==
                    snapshotName
                }

        // Prefer the richer source when duplicate catalog entries exist.
        return
            nameMatches.first(
                where: {
                    $0.imagePeakURL != nil
                }
            ) ??
            nameMatches.first(
                where: {
                    !$0.exercise
                        .instructions
                        .isEmpty
                }
            ) ??
            nameMatches.first
    }

    private func focusedExerciseInstructionSteps(
        _ exercise: StrengthExerciseLog
    ) -> [String] {
        let snapshotSteps =
            exercise.exercise
                .instructions
                .map {
                    $0.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                }
                .filter {
                    !$0.isEmpty
                }

        if !snapshotSteps.isEmpty {
            return snapshotSteps
        }

        return
            focusedExerciseLibraryEntry(
                exercise
            )?
            .exercise
            .instructions
            .map {
                $0.trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
            }
            .filter {
                !$0.isEmpty
            } ?? []
    }

    private func focusedExerciseSummary(
        _ exercise: StrengthExerciseLog
    ) -> String? {
        let value =
            focusedExerciseLibraryEntry(
                exercise
            )?
            .summary?
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard let value,
              !value.isEmpty
        else {
            return nil
        }

        return value
    }

    private func focusedExerciseTips(
        _ exercise: StrengthExerciseLog
    ) -> [String] {
        focusedExerciseLibraryEntry(
            exercise
        )?
        .tips
        .map {
            $0.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
        }
        .filter {
            !$0.isEmpty
        } ?? []
    }

    private func focusedExerciseInstructionDisclosure(
        _ exercise: StrengthExerciseLog
    ) -> some View {
        let steps =
            focusedExerciseInstructionSteps(
                exercise
            )
        let tips =
            focusedExerciseTips(
                exercise
            )
        let summary =
            focusedExerciseSummary(
                exercise
            )

        return VStack(spacing: 0) {
            Button {
                withAnimation(
                    .easeInOut(
                        duration: 0.22
                    )
                ) {
                    showingExerciseInstructions
                        .toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(
                        systemName:
                            "book.pages.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                    .frame(
                        width: 30,
                        height: 30
                    )
                    .background(
                        ATHLTHTheme
                            .vitalitySoft,
                        in: RoundedRectangle(
                            cornerRadius: 10,
                            style:
                                .continuous
                        )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "How to do this exercise",
                                norwegian:
                                    "Slik gjør du øvelsen"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                        Text(
                            steps.isEmpty
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Description",
                                    norwegian:
                                        "Beskrivelse"
                                )
                                : ATHLTHLocalization.format(
                                    english:
                                        "%d steps",
                                    norwegian:
                                        "%d steg",
                                    steps.count
                                )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }

                    Spacer()

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                showingExerciseInstructions
                                    ? "Less"
                                    : "Show",
                            norwegian:
                                showingExerciseInstructions
                                    ? "Skjul"
                                    : "Vis"
                        )
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Image(
                        systemName:
                            showingExerciseInstructions
                                ? "chevron.up"
                                : "chevron.down"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
                .padding(
                    .horizontal,
                    14
                )
                .padding(
                    .vertical,
                    11
                )
            }
            .buttonStyle(.plain)

            if showingExerciseInstructions {
                Divider()
                    .overlay(
                        ATHLTHTheme.divider
                    )

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    if let summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                            .fixedSize(
                                horizontal:
                                    false,
                                vertical: true
                            )
                    }

                    if !steps.isEmpty {
                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(
                                Array(
                                    steps.enumerated()
                                ),
                                id: \.offset
                            ) { index, step in
                                HStack(
                                    alignment: .top,
                                    spacing: 10
                                ) {
                                    Text(
                                        "\(index + 1)"
                                    )
                                    .font(
                                        .caption2
                                            .monospacedDigit()
                                            .weight(
                                                .bold
                                            )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .vitality
                                    )
                                    .frame(
                                        width: 24,
                                        height: 24
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .vitalitySoft,
                                        in: Circle()
                                    )

                                    Text(step)
                                        .font(
                                            .subheadline
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .primaryText
                                        )
                                        .fixedSize(
                                            horizontal:
                                                false,
                                            vertical:
                                                true
                                        )
                                }
                            }
                        }
                    }

                    if !tips.isEmpty {
                        Divider()

                        VStack(
                            alignment: .leading,
                            spacing: 7
                        ) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Tips",
                                    norwegian: "Tips"
                                ),
                                systemImage:
                                    "sparkles"
                            )
                            .font(
                                .caption
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme.vitality
                            )

                            ForEach(
                                Array(
                                    tips.enumerated()
                                ),
                                id: \.offset
                            ) { _, tip in
                                HStack(
                                    alignment: .top,
                                    spacing: 7
                                ) {
                                    Circle()
                                        .fill(
                                            ATHLTHTheme
                                                .premiumGold
                                        )
                                        .frame(
                                            width: 5,
                                            height: 5
                                        )
                                        .padding(
                                            .top,
                                            6
                                        )

                                    Text(tip)
                                        .font(.caption)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                }
                            }
                        }
                    }

                    if summary == nil &&
                        steps.isEmpty &&
                        tips.isEmpty {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "No exercise description is available yet.",
                                norwegian:
                                    "Det finnes ingen øvelsesbeskrivelse ennå."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }
                .padding(
                    .horizontal,
                    14
                )
                .padding(
                    .top,
                    12
                )
                .padding(
                    .bottom,
                    14
                )
                .transition(
                    .opacity.combined(
                        with:
                            .move(
                                edge: .top
                            )
                    )
                )
            }
        }
        .background(
            Color.white
                .opacity(0.94)
        )
    }

    private func focusedExerciseArtworkFallback(
        _ exercise: StrengthExerciseLog
    ) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    ATHLTHTheme
                        .accentSoft,
                    ATHLTHTheme
                        .premiumGoldSoft
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            )

            Image(
                systemName:
                    "figure.strengthtraining.traditional"
            )
            .font(
                .system(
                    size: 72,
                    weight: .light
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.55)
            )
        }
    }

    private func focusedHeroMetric(
        value: String,
        label: String,
        icon: String
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )

            Text(value)
                .font(
                    .system(
                        size: 13,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(label)
                .font(
                    .system(
                        size: 7.5,
                        weight: .bold
                    )
                )
                .tracking(0.6)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var focusedHeroDivider:
        some View {
        Rectangle()
            .fill(
                ATHLTHTheme.divider
            )
            .frame(
                width: 0.5,
                height: 44
            )
    }

    private func focusedProgressionHint(
        _ suggestion:
            StrengthProgressionSuggestion
    ) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    suggestion
                        .suggestedWeightKilograms >
                    suggestion
                        .previousWeightKilograms +
                    0.01
                        ? "arrow.up.right.circle.fill"
                        : "chart.line.uptrend.xyaxis"
            )
            .font(.title3)
            .foregroundStyle(
                ATHLTHTheme.vitality
            )
            .frame(
                width: 34,
                height: 34
            )
            .background(
                ATHLTHTheme.vitality
                    .opacity(0.10),
                in: Circle()
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Last time · \(formatWeight(suggestion.previousWeightKilograms)) kg × \(suggestion.previousReps)",
                        norwegian:
                            "Sist · \(formatWeight(suggestion.previousWeightKilograms)) kg × \(suggestion.previousReps)"
                    )
                )
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

                Text(
                    focusedProgressionTrendText(
                        suggestion
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button(
                ATHLTHLocalization.choose(
                    english: "Use",
                    norwegian: "Bruk"
                )
            ) {
                strength.setDraft(
                    reps:
                        suggestion
                            .suggestedReps,
                    weightKilograms:
                        suggestion
                            .suggestedWeightKilograms
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(
            .horizontal,
            12
        )
        .padding(
            .vertical,
            10
        )
        .background(
            ATHLTHTheme
                .surfaceSage
                .opacity(0.72),
            in:
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.vitality
                    .opacity(0.14),
                lineWidth: 1
            )
        }
    }

    private func focusedProgressionTrendText(
        _ suggestion:
            StrengthProgressionSuggestion
    ) -> String {
        switch suggestion.recentTrend {
        case let .readyRepeated(
            readySessions,
            totalSessions
        ):
            return
                ATHLTHLocalization.format(
                    english:
                        "You had reps in reserve in %d of your last %d sessions. A small increase to %@ kg looks reasonable.",
                    norwegian:
                        "Du hadde kapasitet igjen i %d av de siste %d øktene. En liten økning til %@ kg ser fornuftig ut.",
                    readySessions,
                    totalSessions,
                    formatWeight(
                        suggestion
                            .suggestedWeightKilograms
                    )
                )

        case let .readyLatest(
            totalSessions
        ):
            return
                ATHLTHLocalization.format(
                    english:
                        "The latest of your last %d sessions looked controlled. %@ kg can be worth trying if warm-up feels good.",
                    norwegian:
                        "Den siste av de siste %d øktene så kontrollert ut. %@ kg kan være verdt å prøve hvis oppvarmingen kjennes bra.",
                    totalSessions,
                    formatWeight(
                        suggestion
                            .suggestedWeightKilograms
                    )
                )

        case let .improving(
            totalSessions
        ):
            return
                ATHLTHLocalization.format(
                    english:
                        "Load has progressed across your last %d sessions. Keep building gradually.",
                    norwegian:
                        "Belastningen har økt gjennom de siste %d øktene. Fortsett gradvis.",
                    totalSessions
                )

        case let .stable(
            totalSessions
        ):
            return
                ATHLTHLocalization.format(
                    english:
                        "Your last %d sessions are fairly stable. %@",
                    norwegian:
                        "De siste %d øktene er ganske stabile. %@",
                    totalSessions,
                    suggestion.reason ?? ""
                )

        case let .heavy(
            totalSessions
        ):
            return
                ATHLTHLocalization.format(
                    english:
                        "The latest of your last %d sessions was very hard. %@",
                    norwegian:
                        "Den siste av de siste %d øktene var svært tung. %@",
                    totalSessions,
                    suggestion.reason ?? ""
                )

        case nil:
            return
                suggestion.reason ??
                ATHLTHLocalization.choose(
                    english:
                        "Use the previous session as a reference and adjust by feel.",
                    norwegian:
                        "Bruk forrige økt som referanse og juster etter dagsform."
                )
        }
    }

    private func focusedSetEntry(
        exercise: StrengthExerciseLog
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.format(
                                english:
                                    "Set %d of %d",
                                norwegian:
                                    "Sett %d av %d",
                                strength
                                    .currentSet?
                                    .setNumber ??
                                    1,
                                max(
                                    exercise
                                        .sets
                                        .count,
                                    1
                                )
                            )
                        )
                        .font(
                            .title3
                                .weight(.bold)
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Enter what you actually completed.",
                                norwegian:
                                    "Registrer det du faktisk gjennomførte."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(
                                ATHLTHTheme
                                    .premiumGold
                            )
                            .frame(
                                width: 5,
                                height: 5
                            )

                        Text(
                            "\(strength.draftRestSeconds)s"
                        )
                        .font(
                            .caption
                                .monospacedDigit()
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }
                }

                HStack(spacing: 10) {
                    if currentStrengthLoadKind ==
                        .resistanceLevel {
                        focusedIntegerField(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Resistance",
                                    norwegian: "Motstand"
                                ),
                            value:
                                draftResistanceBinding
                        )
                    } else {
                        focusedNumberField(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Weight",
                                    norwegian: "Vekt"
                                ),
                            value:
                                draftWeightBinding,
                            suffix: "kg"
                        )
                    }

                    if currentStrengthTargetKind == .time {
                        focusedDurationField
                    } else {
                        focusedIntegerField(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Reps",
                                    norwegian:
                                        "Repetisjoner"
                                ),
                            value:
                                draftRepsBinding
                        )
                    }
                }

                HStack(spacing: 10) {
                    Image(
                        systemName: "timer"
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 1
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Rest after set",
                                norwegian:
                                    "Pause etter sett"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Starts automatically when the set is completed.",
                                norwegian:
                                    "Starter automatisk når settet fullføres."
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    Button {
                        strength.setDraft(
                            restSeconds:
                                max(
                                    0,
                                    strength
                                        .draftRestSeconds -
                                        15
                                )
                        )
                    } label: {
                        Image(
                            systemName: "minus"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text(
                        "\(strength.draftRestSeconds)s"
                    )
                    .font(
                        .subheadline
                            .monospacedDigit()
                            .weight(.bold)
                    )
                    .frame(minWidth: 46)

                    Button {
                        strength.setDraft(
                            restSeconds:
                                min(
                                    600,
                                    strength
                                        .draftRestSeconds +
                                        15
                                )
                        )
                    } label: {
                        Image(
                            systemName: "plus"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    strength
                        .completeCurrentDraftSet()
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Complete set",
                            norwegian:
                                "Fullfør sett"
                        ),
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .font(
                        .headline
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 52)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme
                        .accentDeep
                )
                .clipShape(
                    Capsule()
                )
                .shadow(
                    color:
                        ATHLTHTheme
                            .accentDeep
                            .opacity(0.16),
                    radius: 14,
                    x: 0,
                    y: 7
                )
            }
        }
    }

    private func focusedNumberField(
        title: String,
        value: Binding<Double>,
        suffix: String
    ) -> some View {
        premiumSetInputField(
            title: title,
            suffix: suffix,
            decrement: {
                value.wrappedValue =
                    max(
                        0,
                        value.wrappedValue - 0.5
                    )
            },
            increment: {
                value.wrappedValue =
                    min(
                        999.5,
                        value.wrappedValue + 0.5
                    )
            }
        ) {
            TextField(
                "0",
                value: value,
                format:
                    .number
                    .precision(
                        .fractionLength(
                            0...1
                        )
                    )
            )
            .keyboardType(.decimalPad)
            .font(
                .system(
                    size: 28,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .multilineTextAlignment(.leading)
        }
    }

    private func focusedIntegerField(
        title: String,
        value: Binding<Int>
    ) -> some View {
        premiumSetInputField(
            title: title,
            suffix: nil,
            decrement: {
                value.wrappedValue =
                    max(
                        0,
                        value.wrappedValue - 1
                    )
            },
            increment: {
                value.wrappedValue =
                    min(
                        999,
                        value.wrappedValue + 1
                    )
            }
        ) {
            TextField(
                "0",
                value: value,
                format: .number
            )
            .keyboardType(.numberPad)
            .font(
                .system(
                    size: 28,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .multilineTextAlignment(.leading)
        }
    }

    private func premiumSetInputField<Content: View>(
        title: String,
        suffix: String?,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(
                        ATHLTHTheme
                            .premiumGold
                    )
                    .frame(
                        width: 3,
                        height: 14
                    )

                Text(title)
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
            }

            HStack(spacing: 8) {
                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 5
                ) {
                    content()
                        .frame(
                            minWidth: 34
                        )

                    if let suffix {
                        Text(suffix)
                            .font(
                                .subheadline
                                    .weight(.semibold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                    }
                }

                Spacer(minLength: 2)

                VStack(spacing: 3) {
                    Button(action: increment) {
                        Image(
                            systemName:
                                "chevron.up"
                        )
                        .font(
                            .system(
                                size: 12,
                                weight: .bold
                            )
                        )
                        .frame(
                            width: 34,
                            height: 27
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(width: 22)

                    Button(action: decrement) {
                        Image(
                            systemName:
                                "chevron.down"
                        )
                        .font(
                            .system(
                                size: 12,
                                weight: .bold
                            )
                        )
                        .frame(
                            width: 34,
                            height: 27
                        )
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .background(
                    .white.opacity(0.78),
                    in:
                        RoundedRectangle(
                            cornerRadius: 12,
                            style:
                                .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .stroke(
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.18),
                        lineWidth: 0.8
                    )
                }
            }
        }
        .padding(14)
        .frame(
            maxWidth: .infinity
        )
        .background(
            LinearGradient(
                colors: [
                    .white.opacity(0.92),
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.12),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.035),
            radius: 12,
            x: 0,
            y: 6
        )
    }

    private var draftWeightBinding:
        Binding<Double> {
        Binding(
            get: {
                strength
                    .draftWeightKilograms
            },
            set: { value in
                strength.setDraft(
                    weightKilograms:
                        max(value, 0)
                )
            }
        )
    }

    private var draftResistanceBinding:
        Binding<Int> {
        Binding(
            get: {
                strength.draftResistanceLevel
            },
            set: { value in
                strength.setDraft(
                    resistanceLevel:
                        min(max(value, 1), 10)
                )
            }
        )
    }

    private var draftRepsBinding:
        Binding<Int> {
        Binding(
            get: {
                strength.draftReps
            },
            set: { value in
                strength.setDraft(
                    reps:
                        max(value, 0)
                )
            }
        )
    }

    private var draftDurationBinding:
        Binding<Int> {
        Binding(
            get: {
                strength
                    .draftDurationSeconds
            },
            set: { value in
                strength.setDraft(
                    durationSeconds:
                        min(
                            max(value, 15),
                            7_200
                        )
                )
            }
        )
    }

    private var focusedDurationField:
        some View {
        premiumSetInputField(
            title:
                ATHLTHLocalization.choose(
                    english: "Duration",
                    norwegian: "Varighet"
                ),
            suffix: nil,
            decrement: {
                draftDurationBinding
                    .wrappedValue =
                    max(
                        15,
                        draftDurationBinding
                            .wrappedValue -
                            15
                    )
            },
            increment: {
                draftDurationBinding
                    .wrappedValue =
                    min(
                        7_200,
                        draftDurationBinding
                            .wrappedValue +
                            15
                    )
            }
        ) {
            Text(
                TimeInterval(
                    strength
                        .draftDurationSeconds
                )
                .clockDuration
            )
            .font(
                .system(
                    size: 28,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()
        }
    }

    private func focusedSetRest(
        exercise: StrengthExerciseLog
    ) -> some View {
        ATHLTHCard {
            VStack(spacing: 12) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Rest",
                        norwegian: "Pause"
                    )
                )
                .font(
                    .caption
                        .weight(.bold)
                )
                .tracking(1.6)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )

                if let restEndsAt =
                        strength
                            .restEndsAt {
                    TimelineView(
                        .periodic(
                            from: .now,
                            by: 1
                        )
                    ) { context in
                        let rawRemaining =
                            restEndsAt
                                .timeIntervalSince(
                                    context.date
                                )
                        let remaining =
                            max(
                                rawRemaining,
                                0
                            )
                        let overtime =
                            max(
                                -rawRemaining,
                                0
                            )

                        VStack(spacing: 10) {
                            if remaining > 0 {
                                Text(
                                    remaining
                                        .clockDuration
                                )
                                .font(
                                    .system(
                                        size: 52,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .monospacedDigit()
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )

                                Text(
                                    ATHLTHLocalization.format(
                                        english:
                                            "Next: set %d of %d",
                                        norwegian:
                                            "Neste: sett %d av %d",
                                        strength
                                            .currentSet?
                                            .setNumber ??
                                            1,
                                        max(
                                            exercise
                                                .sets
                                                .count,
                                            1
                                        )
                                    )
                                )
                                .font(.subheadline)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            } else {
                                Text(
                                    "+" +
                                    overtime
                                        .clockDuration
                                )
                                .font(
                                    .system(
                                        size: 52,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .monospacedDigit()
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .premiumGold
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Extra rest · continue when you're ready",
                                        norwegian:
                                            "Ekstra pause · fortsett når du er klar"
                                    )
                                )
                                .font(.subheadline)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }

                            Button {
                                strength
                                    .skipRest()
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Next set",
                                        norwegian:
                                            "Neste sett"
                                    ),
                                    systemImage:
                                        "arrow.right"
                                )
                                .font(.headline)
                                .frame(
                                    maxWidth:
                                        .infinity
                                )
                                .frame(height: 48)
                            }
                            .buttonStyle(
                                .borderedProminent
                            )
                            .tint(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .padding(.top, 2)
                        }
                    }
                }
            }
            .frame(
                maxWidth: .infinity
            )
            .padding(
                .vertical,
                8
            )
        }
    }

    private func focusedExerciseTransition(
        workout: StrengthWorkoutLog,
        exercise: StrengthExerciseLog
    ) -> some View {
        TimelineView(
            .periodic(
                from: .now,
                by: 1
            )
        ) { context in
            let completedAt =
                exercise.completedAt ??
                context.date
            let elapsed =
                max(
                    context.date
                        .timeIntervalSince(
                            completedAt
                        ),
                    0
                )
            let rawRemaining =
                strength
                    .restEndsAt?
                    .timeIntervalSince(
                        context.date
                    ) ?? 0
            let remaining =
                max(
                    rawRemaining,
                    0
                )
            let overtime =
                max(
                    -rawRemaining,
                    0
                )
            let hasTimedRest =
                strength.restEndsAt != nil

            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            ATHLTHTheme
                                                .premiumGold
                                                .opacity(0.30),
                                            ATHLTHTheme
                                                .vitality
                                                .opacity(0.16)
                                        ],
                                        startPoint:
                                            .topLeading,
                                        endPoint:
                                            .bottomTrailing
                                    )
                                )
                                .frame(
                                    width: 48,
                                    height: 48
                                )

                            Image(
                                systemName:
                                    strength
                                        .hasNextExercise
                                        ? "arrow.right"
                                        : "checkmark"
                            )
                            .font(
                                .system(
                                    size: 19,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                        }

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                strength
                                    .hasNextExercise
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Exercise complete",
                                        norwegian:
                                            "Øvelse fullført"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english:
                                            "Workout exercises complete",
                                        norwegian:
                                            "Alle øvelser fullført"
                                    )
                            )
                            .font(
                                .title3
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                            if strength.hasNextExercise {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "The rest is a recommendation — continue whenever you feel ready.",
                                        norwegian:
                                            "Pausen er en anbefaling – gå videre når du føler deg klar."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                            }
                        }

                        Spacer()
                    }

                    if strength.hasNextExercise {
                        VStack(spacing: 6) {
                            Text(
                                remaining > 0
                                    ? remaining
                                        .clockDuration
                                    : hasTimedRest
                                        ? "+" +
                                            overtime
                                                .clockDuration
                                        : ATHLTHLocalization.choose(
                                            english: "Ready",
                                            norwegian: "Klar"
                                        )
                            )
                            .font(
                                .system(
                                    size: 52,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()
                            .foregroundStyle(
                                remaining > 0
                                    ? ATHLTHTheme
                                        .primaryText
                                    : ATHLTHTheme
                                        .premiumGold
                            )

                            Text(
                                remaining > 0
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Recommended rest",
                                        norwegian:
                                            "Anbefalt pause"
                                    )
                                    : hasTimedRest
                                        ? ATHLTHLocalization.choose(
                                            english:
                                                "Extra rest",
                                            norwegian:
                                                "Ekstra pause"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english:
                                                "Continue when ready",
                                            norwegian:
                                                "Fortsett når du er klar"
                                        )
                            )
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }

                        HStack(spacing: 6) {
                            Image(
                                systemName:
                                    "stopwatch"
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Between exercises: \(elapsed.clockDuration)",
                                    norwegian:
                                        "Mellom øvelser: \(elapsed.clockDuration)"
                                )
                            )
                            .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        Button {
                            // Rest never blocks navigation. Clearing the timer
                            // first also guarantees that the next exercise
                            // starts in its normal logging state.
                            strength.skipRest()
                            strength
                                .moveToNextExercise()
                        } label: {
                            HStack(spacing: 10) {
                                Image(
                                    systemName:
                                        "arrow.right"
                                )
                                .font(
                                    .system(
                                        size: 16,
                                        weight: .bold
                                    )
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Next exercise now",
                                        norwegian:
                                            "Neste øvelse nå"
                                    )
                                )
                                .font(
                                    .headline
                                )

                                Spacer()

                                Image(
                                    systemName:
                                        "chevron.right"
                                )
                                .font(
                                    .caption
                                        .weight(.bold)
                                )
                                .opacity(0.82)
                            }
                            .foregroundStyle(
                                .white
                            )
                            .padding(
                                .horizontal,
                                18
                            )
                            .frame(
                                maxWidth:
                                    .infinity,
                                minHeight: 54
                            )
                            .background(
                                LinearGradient(
                                    colors: [
                                        ATHLTHTheme
                                            .accentDeep,
                                        ATHLTHTheme
                                            .vitality
                                    ],
                                    startPoint:
                                        .leading,
                                    endPoint:
                                        .trailing
                                ),
                                in:
                                    RoundedRectangle(
                                        cornerRadius: 19,
                                        style:
                                            .continuous
                                    )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 19,
                                    style:
                                        .continuous
                                )
                                .stroke(
                                    Color.white
                                        .opacity(0.22),
                                    lineWidth: 1
                                )
                            }
                            .shadow(
                                color:
                                    ATHLTHTheme
                                        .accentDeep
                                        .opacity(0.16),
                                radius: 12,
                                y: 6
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            ATHLTHLocalization.choose(
                                english:
                                    "Skips the remaining recommended rest and opens the next exercise.",
                                norwegian:
                                    "Hopper over resten av den anbefalte pausen og åpner neste øvelse."
                            )
                        )
                    } else {
                        VStack(spacing: 10) {
                            Image(
                                systemName:
                                    "checkmark.seal.fill"
                            )
                            .font(.title2)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .vitality
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "All planned exercises are complete.",
                                    norwegian:
                                        "Alle planlagte øvelser er fullført."
                                )
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                    }
                }
                .padding(20)
            }
            .background(
                .ultraThinMaterial,
                in:
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
            )
            .background(
                LinearGradient(
                    colors: [
                        Color.white
                            .opacity(0.62),
                        ATHLTHTheme
                            .surfaceSage
                            .opacity(0.26),
                        ATHLTHTheme
                            .premiumGoldSoft
                            .opacity(0.18)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white
                                .opacity(0.90),
                            ATHLTHTheme
                                .premiumGold
                                .opacity(0.16),
                            ATHLTHTheme
                                .vitality
                                .opacity(0.12)
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(
                color:
                    ATHLTHTheme
                        .accentDeep
                        .opacity(0.07),
                radius: 20,
                y: 9
            )
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
                        Label(exercise.exercise.displayName, systemImage: "dumbbell")
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
                    Text(exercise.exercise.displayName)
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
                    setRow(
                        set,
                        exercise: exercise
                    )
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
                if suggestion.recentTrend != nil {
                    Text(
                        focusedProgressionTrendText(
                            suggestion
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                } else if let reason =
                            suggestion.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                }
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
    private func setRow(
        _ set: StrengthSetLog,
        exercise: StrengthExerciseLog
    ) -> some View {
        let row =
            HStack(spacing: 12) {
                Text("\(set.setNumber)")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(
                        set.isCompleted
                            ? ATHLTHTheme.accent.opacity(0.18)
                            : Color.secondary.opacity(0.10),
                        in: Circle()
                    )

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    if set.isCompleted {
                        Text(
                            completedSetSummary(set)
                        )
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                        HStack(spacing: 7) {
                            if let distance =
                                    set.resolvedCompletedDistanceMeters,
                               distance > 0 {
                                Text(
                                    String(
                                        format:
                                            "%.0f m",
                                        distance
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

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
                                Text(
                                    "RPE \(rpe, specifier: "%.1f")"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if let rir = set.rir {
                                Text(
                                    "RIR \(rir, specifier: "%.1f")"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(
                            plannedSetSummary(set)
                        )
                        .font(.subheadline.weight(.medium))

                        Text(
                            plannedLoadSummary(set)
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(
                    systemName:
                        set.isCompleted
                            ? "pencil.circle.fill"
                            : "circle"
                )
                .foregroundStyle(
                    set.isCompleted
                        ? ATHLTHTheme.accent
                        : .secondary
                )
            }
            .padding(10)
            .background(
                .ultraThinMaterial,
                in:
                    RoundedRectangle(
                        cornerRadius: 14
                    )
            )

        if set.isCompleted {
            Button {
                editingSetResult =
                    StrengthSetResultEditTarget(
                        exerciseID:
                            exercise.id,
                        exerciseName:
                            exercise.exercise.displayName,
                        exercise:
                            exercise.exercise,
                        set: set
                    )
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func completedSetSummary(
        _ set: StrengthSetLog
    ) -> String {
        if let segments = set.effortSegments,
           segments.count > 1 {
            let values =
                segments.compactMap {
                    segment -> String? in

                    if let reps = segment.reps,
                       let weight =
                            segment.weightKilograms {
                        return
                            "\(reps) × \(formatWeight(weight)) kg"
                    }

                    if let reps = segment.reps,
                       let resistance =
                            segment.resistanceLevel {
                        return
                            "\(reps) × " +
                            ATHLTHLocalization.choose(
                                english: "level \(resistance)",
                                norwegian: "steg \(resistance)"
                            )
                    }

                    if let duration =
                            segment.durationSeconds {
                        return
                            TimeInterval(duration)
                                .clockDuration
                    }

                    return nil
                }

            if !values.isEmpty {
                return values.joined(
                    separator: " + "
                )
            }
        }

        if set.resolvedTargetKind == .time,
           let duration =
                set.resolvedCompletedDurationSeconds {
            var value =
                TimeInterval(duration)
                    .clockDuration

            if set.resolvedLoadKind ==
                .resistanceLevel,
               let resistance =
                    set.completedResistanceLevel {
                value +=
                    " · " +
                    ATHLTHLocalization.choose(
                        english:
                            "level \(resistance)",
                        norwegian:
                            "steg \(resistance)"
                    )
            } else if let weight =
                        set.completedWeightKilograms {
                value +=
                    " · \(formatWeight(weight)) kg"
            }

            return value
        }

        let reps =
            set.resolvedCompletedReps

        if set.resolvedLoadKind ==
            .resistanceLevel,
           let resistance =
                set.completedResistanceLevel {
            return
                (reps.map {
                    "\($0) reps · "
                } ?? "") +
                ATHLTHLocalization.choose(
                    english: "level \(resistance)",
                    norwegian: "steg \(resistance)"
                )
        }

        if let reps,
           let weight =
                set.completedWeightKilograms {
            return
                "\(reps) reps × \(formatWeight(weight)) kg"
        }

        if let reps {
            return "\(reps) reps"
        }

        return ATHLTHLocalization.choose(
            english: "Set completed",
            norwegian: "Sett fullført"
        )
    }

    private func plannedSetSummary(
        _ set: StrengthSetLog
    ) -> String {
        if set.resolvedTargetKind == .time,
           let duration =
                set.plannedDurationSeconds {
            return ATHLTHLocalization.choose(
                english:
                    "Target: \(TimeInterval(duration).clockDuration)",
                norwegian:
                    "Mål: \(TimeInterval(duration).clockDuration)"
            )
        }

        if let reps =
                set.plannedReps {
            return ATHLTHLocalization.format(
                english: "Target: %d reps",
                norwegian: "Mål: %d repetisjoner",
                reps
            )
        }

        return ATHLTHLocalization.choose(
            english: "No target",
            norwegian: "Ingen mål"
        )
    }

    private func plannedLoadSummary(
        _ set: StrengthSetLog
    ) -> String {
        if set.resolvedLoadKind ==
            .resistanceLevel {
            if let level =
                    set.plannedResistanceLevel {
                return ATHLTHLocalization.choose(
                    english:
                        "Resistance level \(level)",
                    norwegian:
                        "Motstand steg \(level)"
                )
            }

            return ATHLTHLocalization.choose(
                english: "No resistance target",
                norwegian: "Ingen motstandsmål"
            )
        }

        return set.plannedWeightKilograms.map {
            String(
                format:
                    "%.1f kg",
                $0
            )
        } ??
        ATHLTHLocalization.choose(
            english: "No weight target",
            norwegian: "Ingen vektmål"
        )
    }

    private var setEntry: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Log Set \((strength.currentSet?.setNumber) ?? 1)",
                actionTitle: "Optional details"
            )

            HStack(spacing: 12) {
                if currentStrengthLoadKind ==
                    .resistanceLevel {
                    valueStepper(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Resistance",
                                norwegian: "Motstand"
                            ),
                        value:
                            "\(strength.draftResistanceLevel)",
                        minus: {
                            strength.setDraft(
                                resistanceLevel:
                                    max(
                                        1,
                                        strength
                                            .draftResistanceLevel -
                                            1
                                    )
                            )
                        },
                        plus: {
                            strength.setDraft(
                                resistanceLevel:
                                    min(
                                        10,
                                        strength
                                            .draftResistanceLevel +
                                            1
                                    )
                            )
                        }
                    )
                } else {
                    valueStepper(
                        title: "Weight",
                        value: String(format: "%.1f kg", strength.draftWeightKilograms),
                        minus: { strength.setDraft(weightKilograms: max(0, strength.draftWeightKilograms - 2.5)) },
                        plus: { strength.setDraft(weightKilograms: strength.draftWeightKilograms + 2.5) }
                    )
                }

                if currentStrengthTargetKind == .time {
                    valueStepper(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Duration",
                                norwegian: "Varighet"
                            ),
                        value:
                            TimeInterval(
                                strength
                                    .draftDurationSeconds
                            )
                            .clockDuration,
                        minus: {
                            strength.setDraft(
                                durationSeconds:
                                    max(
                                        15,
                                        strength
                                            .draftDurationSeconds -
                                            15
                                    )
                            )
                        },
                        plus: {
                            strength.setDraft(
                                durationSeconds:
                                    min(
                                        7_200,
                                        strength
                                            .draftDurationSeconds +
                                            15
                                    )
                            )
                        }
                    )
                } else {
                    valueStepper(
                        title: "Reps",
                        value: "\(strength.draftReps)",
                        minus: { strength.setDraft(reps: max(0, strength.draftReps - 1)) },
                        plus: { strength.setDraft(reps: strength.draftReps + 1) }
                    )
                }
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
            ATHLTHSectionHeader(
                title:
                    ATHLTHLocalization.choose(
                        english: "Rest",
                        norwegian: "Pause"
                    ),
                actionTitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Workout keeps running",
                        norwegian:
                            "Økten fortsetter"
                    )
            )

            if let restEndsAt =
                    strength.restEndsAt {
                TimelineView(
                    .periodic(
                        from: .now,
                        by: 1
                    )
                ) { context in
                    let rawRemaining =
                        restEndsAt
                            .timeIntervalSince(
                                context.date
                            )
                    let remaining =
                        max(
                            rawRemaining,
                            0
                        )
                    let overtime =
                        max(
                            -rawRemaining,
                            0
                        )

                    VStack(spacing: 12) {
                        Text(
                            remaining > 0
                                ? remaining
                                    .clockDuration
                                : "+" +
                                    overtime
                                        .clockDuration
                        )
                        .font(
                            .system(
                                size: 48,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(
                            remaining > 0
                                ? ATHLTHTheme
                                    .primaryText
                                : ATHLTHTheme
                                    .premiumGold
                        )

                        Text(
                            remaining > 0
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Planned rest",
                                    norwegian:
                                        "Planlagt pause"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Extra rest · continue when you're ready",
                                    norwegian:
                                        "Ekstra pause · fortsett når du er klar"
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                        HStack {
                            Button(
                                ATHLTHLocalization.choose(
                                    english: "+30 sec",
                                    norwegian: "+30 sek"
                                )
                            ) {
                                strength
                                    .addRest(
                                        seconds: 30
                                    )
                            }
                            .buttonStyle(.bordered)

                            Button {
                                strength
                                    .skipRest()
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Next set",
                                        norwegian:
                                            "Neste sett"
                                    ),
                                    systemImage:
                                        "arrow.right"
                                )
                            }
                            .buttonStyle(
                                .borderedProminent
                            )
                            .tint(
                                ATHLTHTheme
                                    .accent
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity
                    )
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

    private var currentStrengthTargetKind:
        StrengthExerciseTargetKind {
        strength
            .currentSet?
            .resolvedTargetKind ??
        .reps
    }

    private var currentStrengthLoadKind:
        StrengthExerciseLoadKind {
        strength
            .currentSet?
            .resolvedLoadKind ??
        strength
            .currentExercise?
            .exercise
            .defaultStrengthLoadKind ??
        .weightKilograms
    }

    private func latestCompletedSet(
        in exercise: StrengthExerciseLog
    ) -> StrengthSetLog? {
        exercise.sets
            .filter(\.isCompleted)
            .max {
                ($0.completedAt ?? .distantPast) <
                ($1.completedAt ?? .distantPast)
            }
    }

    private func postSetResultButton(
        exercise: StrengthExerciseLog,
        set: StrengthSetLog
    ) -> some View {
        let supportsDistance =
            exercise.exercise
                .supportsStrengthDistanceResult

        return Button {
            editingSetResult =
                StrengthSetResultEditTarget(
                    exerciseID: exercise.id,
                    exerciseName:
                        exercise.exercise.displayName,
                    exercise:
                        exercise.exercise,
                    set: set
                )
        } label: {
            HStack {
                Image(
                    systemName:
                        supportsDistance
                            ? "ruler.fill"
                            : "pencil.line"
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        supportsDistance
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Add rowed distance",
                                norwegian:
                                    "Legg inn rodd distanse"
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Edit last set",
                                norwegian:
                                    "Rediger siste sett"
                            )
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(
                        supportsDistance
                            ? (
                                set.resolvedCompletedDistanceMeters.map {
                                    String(
                                        format:
                                            "%.0f m registered · tap to edit",
                                        $0
                                    )
                                } ??
                                ATHLTHLocalization.choose(
                                    english:
                                        "Enter the meter result while you rest.",
                                    norwegian:
                                        "Registrer meterresultatet mens du hviler."
                                )
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Correct reps or split the load before the next set.",
                                norwegian:
                                    "Rett repetisjoner eller del belastningen før neste sett."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                Color.white.opacity(0.88),
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
            )
        }
        .buttonStyle(.plain)
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
        (
            Int,
            Int?,
            StrengthExerciseTargetKind,
            Int?,
            StrengthExerciseLoadKind,
            Double?,
            Int?,
            Int?,
            Int
        ) -> Void

    @State private var sets = 3
    @State private var targetKind:
        StrengthExerciseTargetKind
    @State private var reps = 8
    @State private var durationSeconds: Int
    @State private var loadKind:
        StrengthExerciseLoadKind
    @State private var restSeconds = 90
    @State private var warmUpSets = 0
    @State private var useLoadTarget: Bool
    @State private var weightKilograms = 20.0
    @State private var resistanceLevel = 5

    init(
        entry: ExerciseLibraryEntry,
        onAdd: @escaping (
            Int,
            Int?,
            StrengthExerciseTargetKind,
            Int?,
            StrengthExerciseLoadKind,
            Double?,
            Int?,
            Int?,
            Int
        ) -> Void
    ) {
        self.entry = entry
        self.onAdd = onAdd

        let snapshot =
            entry.exercise.snapshot
        let initialTarget =
            snapshot.defaultStrengthTargetKind
        let initialLoad =
            snapshot.defaultStrengthLoadKind

        _targetKind = State(
            initialValue: initialTarget
        )
        _durationSeconds = State(
            initialValue:
                snapshot
                    .defaultStrengthTargetDurationSeconds
        )
        _loadKind = State(
            initialValue: initialLoad
        )
        _useLoadTarget = State(
            initialValue:
                initialLoad == .resistanceLevel
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ExerciseArtwork(
                            entry: entry,
                            size: 62
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(entry.name)
                                .font(.headline)

                            Text(
                                entry.exercise
                                    .primaryMuscles
                                    .prefix(3)
                                    .joined(
                                        separator: " · "
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Planned setup",
                        norwegian: "Planlagt oppsett"
                    )
                ) {
                    Stepper(
                        ATHLTHLocalization.format(
                            english: "Sets: %d",
                            norwegian: "Sett: %d",
                            sets
                        ),
                        value: $sets,
                        in: 1...20
                    )

                    targetRow

                    Toggle(
                        loadKind == .resistanceLevel
                            ? ATHLTHLocalization.choose(
                                english: "Resistance target",
                                norwegian: "Motstandsmål"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Target weight",
                                norwegian: "Målvekt"
                            ),
                        isOn: $useLoadTarget
                    )

                    if useLoadTarget {
                        loadTargetRow
                    }

                    Stepper(
                        ATHLTHLocalization.format(
                            english: "Rest: %d sec",
                            norwegian: "Hvile: %d sek",
                            restSeconds
                        ),
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
                    .onChange(of: sets) {
                        _,
                        newValue in

                        warmUpSets =
                            min(
                                warmUpSets,
                                newValue
                            )
                    }
                }

                if entry.exercise.snapshot
                    .supportsStrengthDistanceResult {
                    Section {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Rowed distance is entered immediately after the set or from the completed set row.",
                                norwegian:
                                    "Rodd distanse legges inn rett etter settet eller ved å trykke på det fullførte settet."
                            ),
                            systemImage:
                                "ruler"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Targets are only the plan. During the workout you can edit the actual result, including split loads such as 8 × 10 kg + 2 × 8 kg.",
                            norwegian:
                                "Målene er bare planen. Under økten kan du redigere faktisk resultat, også delt belastning som 8 × 10 kg + 2 × 8 kg."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Add Exercise",
                    norwegian: "Legg til øvelse"
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

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Add",
                            norwegian: "Legg til"
                        )
                    ) {
                        onAdd(
                            sets,
                            targetKind == .reps
                                ? reps
                                : nil,
                            targetKind,
                            targetKind == .time
                                ? durationSeconds
                                : nil,
                            loadKind,
                            useLoadTarget &&
                            loadKind == .weightKilograms
                                ? weightKilograms
                                : nil,
                            useLoadTarget &&
                            loadKind == .resistanceLevel
                                ? resistanceLevel
                                : nil,
                            restSeconds,
                            warmUpSets
                        )
                        dismiss()
                    }
                }
            }
        }
    }

    private var loadTargetRow:
        some View {
        Group {
            if loadKind == .resistanceLevel {
                Stepper(
                    value: $resistanceLevel,
                    in: 1...10
                ) {
                    loadMenu(
                        value:
                            ATHLTHLocalization.choose(
                                english: "Level \(resistanceLevel)",
                                norwegian: "Steg \(resistanceLevel)"
                            )
                    )
                }
            } else {
                HStack {
                    loadMenu(
                        value:
                            String(
                                format:
                                    "%.1f kg",
                                weightKilograms
                            )
                    )

                    Spacer()

                    TextField(
                        "kg",
                        value: $weightKilograms,
                        format:
                            .number
                            .precision(
                                .fractionLength(0...2)
                            )
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)

                    Text("kg")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadMenu(
        value: String
    ) -> some View {
        Menu {
            Button {
                loadKind =
                    .weightKilograms
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Weight",
                        norwegian: "Vekt"
                    ),
                    systemImage:
                        loadKind == .weightKilograms
                            ? "checkmark"
                            : "scalemass"
                )
            }

            Button {
                loadKind =
                    .resistanceLevel
                useLoadTarget = true
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Resistance",
                        norwegian: "Motstand"
                    ),
                    systemImage:
                        loadKind == .resistanceLevel
                            ? "checkmark"
                            : "dial.medium"
                )
            }
        } label: {
            HStack(spacing: 5) {
                Text(
                    "\(loadKind.title): \(value)"
                )
                .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetRow:
        some View {
        Group {
            if targetKind == .reps {
                Stepper(
                    value: $reps,
                    in: 1...100
                ) {
                    targetMenu(
                        value: "\(reps)"
                    )
                }
            } else {
                Stepper(
                    value: $durationSeconds,
                    in: 15...7_200,
                    step: 15
                ) {
                    targetMenu(
                        value:
                            TimeInterval(
                                durationSeconds
                            )
                            .clockDuration
                    )
                }
            }
        }
    }

    private func targetMenu(
        value: String
    ) -> some View {
        Menu {
            Button {
                targetKind = .reps
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Target reps",
                        norwegian: "Målreps"
                    ),
                    systemImage:
                        targetKind == .reps
                            ? "checkmark"
                            : "repeat"
                )
            }

            Button {
                targetKind = .time
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Duration",
                        norwegian: "Varighet"
                    ),
                    systemImage:
                        targetKind == .time
                            ? "checkmark"
                            : "timer"
                )
            }
        } label: {
            HStack(spacing: 5) {
                Text(
                    "\(targetKind.title): \(value)"
                )
                .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StrengthSetResultEditTarget: Identifiable {
    var id: UUID {
        return self.set.id
    }
    let exerciseID: UUID
    let exerciseName: String
    let exercise: ExerciseSnapshot
    let set: StrengthSetLog
}

struct StrengthSetResultEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let target: StrengthSetResultEditTarget
    let onSave:
        (
            [StrengthSetEffortSegment],
            Double?,
            Int?
        ) -> Void

    @State private var segments:
        [StrengthSetEffortSegment]
    @State private var distanceMeters: Double
    @State private var resistanceLevel: Int
    @FocusState private var focusedWeightIndex:
        Int?

    init(
        target: StrengthSetResultEditTarget,
        onSave: @escaping (
            [StrengthSetEffortSegment],
            Double?,
            Int?
        ) -> Void
    ) {
        self.target = target
        self.onSave = onSave

        let set = target.set
        let existing =
            set.effortSegments?.isEmpty == false
                ? set.effortSegments!
                : [
                    StrengthSetEffortSegment(
                        reps:
                            set.completedReps,
                        weightKilograms:
                            set.completedWeightKilograms,
                        durationSeconds:
                            set.completedDurationSeconds,
                        distanceMeters:
                            set.completedDistanceMeters,
                        resistanceLevel:
                            set.completedResistanceLevel
                    )
                ]

        _segments = State(
            initialValue: existing
        )
        _distanceMeters = State(
            initialValue:
                set.resolvedCompletedDistanceMeters ??
                0
        )
        _resistanceLevel = State(
            initialValue:
                set.completedResistanceLevel ??
                set.plannedResistanceLevel ??
                5
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .vitality
                            .opacity(0.15)
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 16
                    ) {
                        editorIntro

                        ForEach(
                            Array(
                                segments.indices
                            ),
                            id: \.self
                        ) { index in
                            segmentGhostCard(
                                index
                            )
                        }

                        if target.set
                            .resolvedTargetKind !=
                            .time {
                            addLoadChangeButton
                        }

                        if target.exercise
                            .supportsStrengthDistanceResult {
                            machineResultCard
                        }

                        exampleCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 38)
                }
                .scrollDismissesKeyboard(
                    .interactively
                )
            }
            .navigationTitle(
                "\(target.exerciseName) · " +
                ATHLTHLocalization.format(
                    english: "Set %d",
                    norwegian: "Sett %d",
                    target.set.setNumber
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
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

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Save",
                            norwegian: "Lagre"
                        )
                    ) {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(
                .ultraThinMaterial,
                for: .navigationBar
            )
            .toolbarBackground(
                .visible,
                for: .navigationBar
            )
        }
        .presentationBackground(
            ATHLTHTheme.canvasTop
        )
    }

    private var editorIntro: some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    "slider.horizontal.3"
            )
            .font(.title3)
            .foregroundStyle(
                ATHLTHTheme.vitality
            )
            .frame(
                width: 42,
                height: 42
            )
            .background(
                ATHLTHTheme
                    .vitalitySoft,
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Actual result",
                        norwegian: "Faktisk resultat"
                    )
                )
                .font(
                    .title3.weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Adjust what you actually completed.",
                        norwegian:
                            "Juster det du faktisk gjennomførte."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func segmentGhostCard(
        _ index: Int
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                HStack(spacing: 7) {
                    Text(
                        segments.count > 1
                            ? ATHLTHLocalization.format(
                                english: "Part %d",
                                norwegian: "Del %d",
                                index + 1
                            )
                            : ATHLTHLocalization.choose(
                                english: "Set result",
                                norwegian: "Settresultat"
                            )
                    )
                    .font(
                        .caption.weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    if segments.count > 1 {
                        Text(
                            "\(index + 1)/\(segments.count)"
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }

                Spacer()

                if segments.count > 1 {
                    Button(
                        role: .destructive
                    ) {
                        focusedWeightIndex = nil
                        segments.remove(
                            at: index
                        )
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Remove",
                                norwegian: "Fjern"
                            ),
                            systemImage:
                                "minus.circle"
                        )
                        .font(
                            .caption.weight(.semibold)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(
                    ATHLTHTheme
                        .divider
                )

            if target.set
                .resolvedTargetKind ==
                .time {
                ghostIntegerRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Duration",
                            norwegian: "Varighet"
                        ),
                    value:
                        TimeInterval(
                            durationBinding(index)
                                .wrappedValue
                        )
                        .clockDuration,
                    minus: {
                        durationBinding(index)
                            .wrappedValue =
                            max(
                                0,
                                durationBinding(index)
                                    .wrappedValue -
                                    15
                            )
                    },
                    plus: {
                        durationBinding(index)
                            .wrappedValue =
                            min(
                                7_200,
                                durationBinding(index)
                                    .wrappedValue +
                                    15
                            )
                    }
                )
            } else {
                ghostIntegerRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Reps",
                            norwegian: "Repetisjoner"
                        ),
                    value:
                        "\(repsBinding(index).wrappedValue)",
                    minus: {
                        repsBinding(index)
                            .wrappedValue =
                            max(
                                0,
                                repsBinding(index)
                                    .wrappedValue -
                                    1
                            )
                    },
                    plus: {
                        repsBinding(index)
                            .wrappedValue =
                            min(
                                200,
                                repsBinding(index)
                                    .wrappedValue +
                                    1
                            )
                    }
                )
            }

            if target.set
                .resolvedLoadKind ==
                .resistanceLevel {
                ghostIntegerRow(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Resistance",
                            norwegian: "Motstand"
                        ),
                    value:
                        ATHLTHLocalization.choose(
                            english:
                                "Level \(resistanceBinding(index).wrappedValue)",
                            norwegian:
                                "Steg \(resistanceBinding(index).wrappedValue)"
                        ),
                    minus: {
                        resistanceBinding(index)
                            .wrappedValue =
                            max(
                                1,
                                resistanceBinding(index)
                                    .wrappedValue -
                                    1
                            )
                    },
                    plus: {
                        resistanceBinding(index)
                            .wrappedValue =
                            min(
                                10,
                                resistanceBinding(index)
                                    .wrappedValue +
                                    1
                            )
                    }
                )
            } else {
                ghostWeightRow(index)
            }
        }
        .padding(16)
        .background(
            .ultraThinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.60),
                    ATHLTHTheme
                        .surfaceSage
                        .opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                focusedWeightIndex ==
                    index
                    ? ATHLTHTheme
                        .vitality
                        .opacity(0.42)
                    : Color.white
                        .opacity(0.78),
                lineWidth:
                    focusedWeightIndex ==
                        index
                        ? 1.4
                        : 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.055),
            radius: 18,
            y: 8
        )
    }

    private func ghostWeightRow(
        _ index: Int
    ) -> some View {
        HStack(spacing: 12) {
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Weight",
                        norwegian: "Vekt"
                    )
                )
                .font(
                    .subheadline.weight(.semibold)
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Adjust by 2.5 kg or type a value",
                        norwegian:
                            "Juster 2,5 kg eller skriv inn verdi"
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer(minLength: 8)

            ghostRoundButton(
                systemImage: "minus"
            ) {
                adjustWeight(
                    at: index,
                    by: -2.5
                )
            }

            HStack(
                alignment:
                    .firstTextBaseline,
                spacing: 4
            ) {
                TextField(
                    "0",
                    value:
                        weightBinding(index),
                    format:
                        .number
                        .precision(
                            .fractionLength(
                                0...2
                            )
                        )
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(
                    .trailing
                )
                .font(
                    .title3
                        .monospacedDigit()
                        .weight(.bold)
                )
                .frame(width: 64)
                .focused(
                    $focusedWeightIndex,
                    equals: index
                )

                Text("kg")
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(
                Color.white
                    .opacity(0.76),
                in: RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.16),
                    lineWidth: 0.8
                )
            }

            ghostRoundButton(
                systemImage: "plus"
            ) {
                adjustWeight(
                    at: index,
                    by: 2.5
                )
            }
        }
    }

    private func ghostIntegerRow(
        title: String,
        value: String,
        minus: @escaping () -> Void,
        plus: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(
                    .subheadline.weight(.semibold)
                )

            Spacer()

            Text(value)
                .font(
                    .title3
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .frame(
                    minWidth: 54,
                    alignment: .trailing
                )

            HStack(spacing: 1) {
                Button(action: minus) {
                    Image(
                        systemName: "minus"
                    )
                    .font(
                        .system(
                            size: 14,
                            weight: .bold
                        )
                    )
                    .frame(
                        width: 40,
                        height: 36
                    )
                }

                Rectangle()
                    .fill(
                        ATHLTHTheme
                            .divider
                    )
                    .frame(
                        width: 0.5,
                        height: 24
                    )

                Button(action: plus) {
                    Image(
                        systemName: "plus"
                    )
                    .font(
                        .system(
                            size: 14,
                            weight: .bold
                        )
                    )
                    .frame(
                        width: 40,
                        height: 36
                    )
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .background(
                Color.white
                    .opacity(0.72),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.black
                            .opacity(0.055),
                        lineWidth: 0.8
                    )
            }
        }
    }

    private func ghostRoundButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(
                systemName: systemImage
            )
            .font(
                .system(
                    size: 14,
                    weight: .bold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                Color.white
                    .opacity(0.78),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        Color.black
                            .opacity(0.055),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var addLoadChangeButton:
        some View {
        Button {
            focusedWeightIndex = nil
            addSegment()
        } label: {
            HStack(spacing: 11) {
                Image(
                    systemName:
                        "plus.circle.fill"
                )
                .font(.title3)
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Add load change",
                            norwegian:
                                "Legg til belastningsendring"
                        )
                    )
                    .font(
                        .subheadline.weight(.semibold)
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Split the set if weight changed during the set.",
                            norwegian:
                                "Del opp settet hvis vekten ble endret underveis."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(.caption.bold())
                .foregroundStyle(
                    .tertiary
                )
            }
            .padding(14)
            .background(
                ATHLTHTheme
                    .surfaceSage
                    .opacity(0.66),
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme.vitality
                        .opacity(0.14),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var machineResultCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Machine result",
                    norwegian: "Maskinresultat"
                ),
                systemImage:
                    "gauge.with.dots.needle.50percent"
            )
            .font(.headline)
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )

            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Distance",
                        norwegian: "Distanse"
                    )
                )
                .font(
                    .subheadline.weight(.semibold)
                )

                Spacer()

                TextField(
                    "0",
                    value: $distanceMeters,
                    format:
                        .number
                        .precision(
                            .fractionLength(
                                0...0
                            )
                        )
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(
                    .trailing
                )
                .font(
                    .title3
                        .monospacedDigit()
                        .weight(.bold)
                )
                .frame(width: 82)

                Text("m")
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }

            Divider()

            ghostIntegerRow(
                title:
                    ATHLTHLocalization.choose(
                        english: "Resistance",
                        norwegian: "Motstand"
                    ),
                value:
                    ATHLTHLocalization.choose(
                        english:
                            "Level \(resistanceLevel)",
                        norwegian:
                            "Steg \(resistanceLevel)"
                    ),
                minus: {
                    resistanceLevel =
                        max(
                            1,
                            resistanceLevel - 1
                        )
                },
                plus: {
                    resistanceLevel =
                        min(
                            10,
                            resistanceLevel + 1
                        )
                }
            )
        }
        .padding(16)
        .background(
            .ultraThinMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.74),
                lineWidth: 0.8
            )
        }
    }

    private var exampleCard:
        some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            Image(
                systemName: "sparkles"
            )
            .foregroundStyle(
                ATHLTHTheme.vitality
            )

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Example: if 10 reps were planned at 10 kg, record 8 × 10 kg and add a second part with 2 × 8 kg. ATHLTH calculates volume from what you actually did.",
                    norwegian:
                        "Eksempel: Var målet 10 repetisjoner på 10 kg, kan du registrere 8 × 10 kg og legge til en ny del med 2 × 8 kg. ATHLTH beregner volum fra det du faktisk gjorde."
                )
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .fixedSize(
                horizontal: false,
                vertical: true
            )
        }
        .padding(14)
        .background(
            Color.white
                .opacity(0.48),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
    }

    private func save() {
        focusedWeightIndex = nil

        onSave(
            segments,
            target.exercise
                .supportsStrengthDistanceResult
                ? max(
                    distanceMeters,
                    0
                )
                : nil,
            target.set
                .resolvedLoadKind ==
                .resistanceLevel ||
            target.exercise
                .supportsStrengthDistanceResult
                ? resistanceLevel
                : nil
        )
        dismiss()
    }

    private func adjustWeight(
        at index: Int,
        by delta: Double
    ) {
        guard segments.indices
            .contains(index)
        else {
            return
        }

        let current =
            segments[index]
                .weightKilograms ??
            0
        let updated =
            max(
                0,
                current + delta
            )

        // Keep values on half-kilo boundaries after button changes while
        // preserving free manual input in the text field.
        segments[index]
            .weightKilograms =
            (updated * 2)
                .rounded() /
            2
    }

    private func addSegment() {
        let last =
            segments.last

        segments.append(
            StrengthSetEffortSegment(
                reps: 1,
                weightKilograms:
                    target.set
                        .resolvedLoadKind ==
                        .weightKilograms
                        ? last?
                            .weightKilograms ??
                            target.set
                                .completedWeightKilograms ??
                            target.set
                                .plannedWeightKilograms
                        : nil,
                resistanceLevel:
                    target.set
                        .resolvedLoadKind ==
                        .resistanceLevel
                        ? last?
                            .resistanceLevel ??
                            target.set
                                .completedResistanceLevel ??
                            target.set
                                .plannedResistanceLevel ??
                            5
                        : nil
            )
        )
    }

    private func repsBinding(
        _ index: Int
    ) -> Binding<Int> {
        Binding(
            get: {
                segments[index]
                    .reps ?? 0
            },
            set: {
                segments[index].reps =
                    max($0, 0)
            }
        )
    }

    private func durationBinding(
        _ index: Int
    ) -> Binding<Int> {
        Binding(
            get: {
                segments[index]
                    .durationSeconds ?? 0
            },
            set: {
                segments[index]
                    .durationSeconds =
                    min(
                        max($0, 0),
                        7_200
                    )
            }
        )
    }

    private func weightBinding(
        _ index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                segments[index]
                    .weightKilograms ?? 0
            },
            set: {
                segments[index]
                    .weightKilograms =
                    max($0, 0)
            }
        )
    }

    private func resistanceBinding(
        _ index: Int
    ) -> Binding<Int> {
        Binding(
            get: {
                segments[index]
                    .resistanceLevel ??
                resistanceLevel
            },
            set: {
                let value =
                    min(max($0, 1), 10)
                segments[index]
                    .resistanceLevel =
                    value
                resistanceLevel =
                    value
            }
        )
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
                guard entry.canonicalName
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
                    exercise.exercise.displayName
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
