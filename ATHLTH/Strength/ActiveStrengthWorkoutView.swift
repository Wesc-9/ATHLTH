import AVKit
import SwiftUI
import UIKit

struct ActiveStrengthWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var runningWorkoutLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var social: SocialStore

    @StateObject private var socialCompanion =
        SocialWorkoutCompanionStore()
    @State private var showingFinishConfirmation = false
    @State private var finishInProgress = false
    @State private var watchFinishTimeoutTask:
        Task<Void, Never>?
    @State private var watchFinishError: String?
    @State private var showingExerciseLibrary = false
    @State private var showingAppendWorkout = false

    @State private var showingAIExercisePlanner = false
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
    @State private var focusedExerciseMediaIndex = 0
    @State private var showingExerciseInstructions = false
    @State private var showingWorkoutReview = false
    @State private var showingExerciseQueue = false
    @State private var showingSpotifyControls = false
    @State private var showingNextExerciseDetails = false
    @State private var showingOmitRemainingSetsConfirmation = false
    @State private var showingTrainingPlacePicker = false

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
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
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
            .safeAreaInset(edge: .top, spacing: 0) {
                if showingSpotifyControls && spotify.isConnected &&
                   strength.activeWorkout != nil {
                    HStack(spacing: 0) {
                        inlineSpotifyBar
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 80)
                    .padding(.top, 3)
                    .padding(.bottom, 5)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
                ToolbarItemGroup(placement: .topBarLeading) {
                    if strength.activeWorkout != nil {
                        Button {
                            // Keep the recording, completed sets and active
                            // timers alive; only close this live presentation.
                            strength.checkpoint()
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 40, height: 40)
                                .background(ATHLTHTheme.champagneSoft, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Minimize workout",
                            norwegian: "Legg ned økten"
                        ))
                        .accessibilityHint(ATHLTHLocalization.choose(
                            english: "Keep tracking your workout and return to ATHLTH",
                            norwegian: "Fortsett å registrere økten og gå tilbake til ATHLTH"
                        ))
                    }

                    if strength.activeWorkout?.exercises.isEmpty == false {
                        Button {
                            showingExerciseQueue = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 40, height: 40)
                                .background(ATHLTHTheme.champagneSoft, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Exercises and order",
                            norwegian: "Øvelser og rekkefølge"
                        ))
                    }

                    if spotify.isConnected {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showingSpotifyControls.toggle()
                            }
                        } label: {
                            ATHLTHSpotifyGlyph()
                                .frame(width: 30, height: 30)
                                .frame(width: 38, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Spotify controls",
                            norwegian: "Spotify-kontroller"
                        ))
                    }
                }

                ToolbarItemGroup(
                    placement:
                        .topBarTrailing
                ) {
                    if strength.activeWorkout != nil {
                        Menu {
                            Button {
                                showingExerciseLibrary = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Exercise", norwegian: "Øvelse"
                                    ),
                                    systemImage: "dumbbell"
                                )
                            }

                            Button {
                                showingAppendWorkout = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Entire workout",
                                        norwegian: "Hel treningsøkt"
                                    ),
                                    systemImage: "rectangle.stack.badge.plus"
                                )
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Add exercise or workout",
                            norwegian: "Legg til øvelse eller treningsøkt"
                        ))
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
            .sheet(isPresented: $showingTrainingPlacePicker) {
                ATHLTHPlanTrainingPlacePicker(
                    initial: strength.activeWorkout?.plannedTrainingPlace
                ) { place in
                    strength.setWorkoutTrainingPlace(place)
                }
                .environmentObject(appSession)
            }
            .sheet(isPresented: $showingAppendWorkout) {
                ActiveHybridWorkoutPicker { session, startNow in
                    strength.appendWorkoutDuringSession(
                        session,
                        startNow: startNow
                    )
                }
                .environmentObject(appSession)
                .environmentObject(runningWorkoutLibrary)
            }
            .sheet(isPresented: $showingExerciseQueue) {
                StrengthActiveExerciseQueueView()
                    .environmentObject(strength)
            }
            .sheet(isPresented: $showingExerciseLibrary) {
                NavigationStack {
                    ExerciseLibraryView(
                        selectionTitle:
                            ATHLTHLocalization.choose(
                                english: "Add to active workout",
                                norwegian: "Legg til i økten"
                            ),
                        selectedExerciseCounts: Dictionary(
                            activeExistingPlannedExercises.compactMap(\.exerciseID).map { ($0, 1) },
                            uniquingKeysWith: +
                        )
                    ) { entry in
                        pendingExercise = entry
                        showingExerciseLibrary = false
                    }
                }
            }
            .sheet(
                isPresented:
                    $showingAIExercisePlanner
            ) {
                StrengthAIExercisePlannerView(
                    existingExercises:
                        activeExistingPlannedExercises,
                    recentWorkouts:
                        strength
                            .workoutHistory
                ) {
                    additions in

                    appendAIExercises(
                        additions
                    )
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
                    showingWorkoutReview = false
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
                    showingWorkoutReview =
                        strength
                            .activeWorkout?
                            .exercises
                            .allSatisfy {
                                $0.isCompleted
                            } ?? false
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
                    targetWeightKilograms: strength.draftWeightKilograms,
                    initialBarWeightKilograms:
                        strength.currentExercise?.barWeightKilograms ?? 20,
                    onBarWeightChange: { kilograms in
                        if let active = strength.currentExercise {
                            _ = strength.setActiveExerciseBarWeight(
                                active.id, kilograms: kilograms
                            )
                        }
                    }
                )
            }
            .sheet(isPresented: $showingFinishConfirmation) {
                strengthFinishConfirmationSheet
                    .presentationDetents([.height(510), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ATHLTHTrainDesign.canvas)
                    .interactiveDismissDisabled(finishInProgress)
            }
            .alert(
                ATHLTHLocalization.choose(
                    english: "Workout",
                    norwegian: "Treningsøkt"
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
                updateScreenAwakeState()
            }
            .onDisappear {
                restCueTask?.cancel()
                statusCoachTask?.cancel()
                watchFinishTimeoutTask?.cancel()
                watchFinishTimeoutTask = nil
                strengthCoach.stop()

                ATHLTHWorkoutScreenAwake.set(
                    false,
                    reason:
                        "iphone-strength-workout"
                )
            }
            .onChange(
                of:
                    strength
                        .activeWorkout?
                        .id
            ) { oldValue, newValue in
                updateScreenAwakeState()

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
                of: scenePhase
            ) { _, phase in
                updateScreenAwakeState()
                if phase == .background {
                    strength.checkpoint()
                } else if phase == .active &&
                          strength.controlsEmbeddedHybridClockOnIPhone {
                    strength.advanceEmbeddedIntervalIfNeeded()
                }
            }
            .onReceive(
                Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            ) { timestamp in
                if strength.controlsEmbeddedHybridClockOnIPhone &&
                    strength.currentExercise?.isEmbeddedRunningInterval == true {
                    strength.advanceEmbeddedIntervalIfNeeded(at: timestamp)
                }
            }
            .onChange(
                of:
                    workoutMirroring
                        .snapshot?
                        .state
            ) { previousState, newState in
                if let workout = strength.activeWorkout,
                   workout.captureDevice == .appleWatch,
                   strength.currentExercise?.isEmbeddedRunningInterval == true,
                   strength.controlsEmbeddedHybridClockOnIPhone,
                   (workoutMirroring.snapshot?.kind == .strength ||
                    workoutMirroring.snapshot?.kind == .functional) {
                    if newState == .paused {
                        strength.pauseTimedSet()
                    } else if previousState == .paused &&
                              newState == .running {
                        strength.startOrResumeTimedSet()
                    }
                }
                if newState == .completed {
                    finalizeWatchStrengthFromMirrorIfNeeded()
                }
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
                showingWorkoutReview = false
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
                social.recordingWorkoutSessionID
        ) {
            guard
                let sessionID =
                    social.recordingWorkoutSessionID,
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
        // The current set is a stable bottom surface. Scrolling exercise
        // media/instructions never scrolls away load, reps or the main action.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let workout = strength.activeWorkout,
               let exercise = strength.currentExercise,
               !workout.exercises.allSatisfy({ $0.isCompleted }),
               !strength.currentExerciseAllSetsCompleted,
               !strength.isFreeTrainingBetweenExercises,
               exercise.isEmbeddedRunningInterval != true,
               canLogOnIPhone(workout) {
                compactLiveStrengthDock(exercise: exercise)
            }
        }
        // Keep Spotify/coach controls visible directly beneath the live
        // navigation bar instead of hiding them below long set-entry cards.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let workout = strength.activeWorkout {
                ATHLTHWorkoutAudioDock(
                    showSpotifyLauncher: false,
                    coachVisible:
                        workout.advancedConfiguration?.audioCoach.enabled == true,
                    coachEnabled:
                        workout.advancedConfiguration?.audioCoach.enabled == true,
                    coachPaused: strengthCoach.speechPaused,
                    coachManagedOnWatch: workout.captureDevice == .appleWatch,
                    canReplayCoach: strengthCoach.canReplayLastMessage,
                    onCoachStatus: { announceStrengthCoachStatusNow() },
                    onCoachTogglePause: {
                        strengthCoach.setSpeechPaused(!strengthCoach.speechPaused)
                    },
                    onCoachReplay: { strengthCoach.replayLastMessage() },
                    onCoachSettings: nil
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
    private func updateScreenAwakeState() {
        ATHLTHWorkoutScreenAwake.set(
            strength.activeWorkout != nil &&
                scenePhase == .active,
            reason:
                "iphone-strength-workout"
        )
    }

    @MainActor
    private func configureAdvancedRuntime() {
        guard let workout =
                strength.activeWorkout,
              let configuration =
                workout
                    .advancedConfiguration
        else {
            return
        }

        if workout.captureDevice == .iPhone,
           configuration.audioCoach.enabled {
            strengthCoach.speak(
                english:
                    "Audio Coach is ready for your strength workout.",
                norwegian:
                    "Audio Coach er klar for styrkeøkten din.",
                configuration:
                    configuration.audioCoach,
                cueKind: .workoutStart
            )
        }
    }

    /// Speaks a fresh summary using the same set/exercise state displayed
    /// on screen. Never advances the session or changes rest deadlines.
    @MainActor
    private func announceStrengthCoachStatusNow() {
        guard let workout = strength.activeWorkout,
              workout.captureDevice == .iPhone,
              let configuration = workout.advancedConfiguration?.audioCoach,
              configuration.enabled,
              !strengthCoach.speechPaused
        else { return }

        let totalSets = workout.exercises
            .flatMap(\.sets)
            .filter { $0.hybridPhaseKind == nil }
            .count
        let exerciseName =
            strength.currentExercise?.exercise.displayName ??
            workout.title
        let now = Date()
        let english = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: workout.totalCompletedSets,
            totalSets: totalSets,
            exerciseName: exerciseName,
            restEndsAt: strength.restEndsAt,
            now: now,
            norwegian: false
        )
        let norwegian = ATHLTHStrengthCoachStatusMessage.make(
            completedSets: workout.totalCompletedSets,
            totalSets: totalSets,
            exerciseName: exerciseName,
            restEndsAt: strength.restEndsAt,
            now: now,
            norwegian: true
        )
        strengthCoach.speak(
            english: english,
            norwegian: norwegian,
            configuration: configuration,
            cueKind: .manualStatus
        )
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

        let phrase =
            nextExerciseCoachPhrase(
                workout: workout,
                exercise: exercise,
                configuration:
                    configuration
            )

        strengthCoach.speak(
            english:
                phrase.english,
            norwegian:
                phrase.norwegian,
            configuration:
                configuration.audioCoach
        )
    }

    private func nextExerciseCoachPhrase(
        workout: StrengthWorkoutLog,
        exercise: StrengthExerciseLog,
        configuration:
            StrengthAdvancedConfiguration
    ) -> (
        english: String,
        norwegian: String
    ) {
        var english = [
            "Next exercise. \(exercise.exercise.displayName)."
        ]
        var norwegian = [
            "Neste øvelse. \(exercise.exercise.displayName)."
        ]

        if configuration.audioCoach
            .shouldAnnounceExerciseProgress {
            english.append(
                "Exercise \(strength.currentExerciseIndex + 1) of \(workout.exercises.count)."
            )
            norwegian.append(
                "Øvelse \(strength.currentExerciseIndex + 1) av \(workout.exercises.count)."
            )
        }

        let remainingSets =
            exercise.sets
                .filter {
                    !$0.isCompleted
                }

        if !remainingSets.isEmpty {
            english.append(
                "\(remainingSets.count) sets remaining."
            )
            norwegian.append(
                "\(remainingSets.count) sett gjenstår."
            )
        }

        if let first =
                remainingSets.first {
            let target =
                strengthTargetCoachPhrase(
                    set: first,
                    fallbackReps: nil,
                    fallbackDurationSeconds:
                        nil,
                    fallbackWeightKilograms:
                        nil,
                    fallbackResistanceLevel:
                        nil
                )

            if !target.english.isEmpty {
                english.append(
                    "First target. \(target.english)"
                )
                norwegian.append(
                    "Første mål. \(target.norwegian)"
                )
            }

            let rest =
                exercise
                    .restSecondsOverride ??
                first.restSeconds ??
                configuration
                    .restCues
                    .defaultRestSeconds

            if rest > 0 {
                english.append(
                    "\(rest) seconds rest."
                )
                norwegian.append(
                    "\(rest) sekunder hvile."
                )
            }
        }

        return (
            english.joined(
                separator: " "
            ),
            norwegian.joined(
                separator: " "
            )
        )
    }

    private func nextSetCoachPhrase()
        -> (
            english: String,
            norwegian: String
        )? {
        guard
            let workout =
                strength.activeWorkout,
            let configuration =
                workout
                    .advancedConfiguration,
            configuration.audioCoach
                .shouldAnnounceNextSetDetails,
            !strength
                .currentExerciseAllSetsCompleted,
            let exercise =
                strength.currentExercise,
            let set =
                strength.currentSet
        else {
            return nil
        }

        let target =
            strengthTargetCoachPhrase(
                set: set,
                fallbackReps:
                    strength.draftReps,
                fallbackDurationSeconds:
                    strength
                        .draftDurationSeconds,
                fallbackWeightKilograms:
                    strength
                        .draftWeightKilograms,
                fallbackResistanceLevel:
                    strength
                        .draftResistanceLevel
            )

        var english =
            "Next set. Set \(set.setNumber) of \(exercise.sets.count)."
        var norwegian =
            "Neste sett. Sett \(set.setNumber) av \(exercise.sets.count)."

        if !target.english.isEmpty {
            english +=
                " \(target.english)"
            norwegian +=
                " \(target.norwegian)"
        }

        return (
            english,
            norwegian
        )
    }

    private func upcomingExerciseCoachPhrase()
        -> (
            english: String,
            norwegian: String
        )? {
        guard
            let workout =
                strength.activeWorkout,
            strength
                .currentExerciseAllSetsCompleted,
            strength.hasNextExercise
        else {
            return nil
        }

        let currentIndex =
            strength.currentExerciseIndex
        let later =
            workout.exercises.indices
                .dropFirst(
                    currentIndex + 1
                )
                .first {
                    !workout
                        .exercises[$0]
                        .isCompleted
                }
        let earlier =
            workout.exercises.indices
                .prefix(currentIndex)
                .first {
                    !workout
                        .exercises[$0]
                        .isCompleted
                }

        guard let nextIndex =
                later ?? earlier
        else {
            return nil
        }

        let exercise =
            workout.exercises[
                nextIndex
            ]
        guard let set =
                exercise.sets.first(
                    where: {
                        !$0.isCompleted
                    }
                )
        else {
            return (
                "Next exercise. \(exercise.exercise.displayName).",
                "Neste øvelse. \(exercise.exercise.displayName)."
            )
        }

        let target =
            strengthTargetCoachPhrase(
                set: set,
                fallbackReps: nil,
                fallbackDurationSeconds:
                    nil,
                fallbackWeightKilograms:
                    nil,
                fallbackResistanceLevel:
                    nil
            )

        var english =
            "Next exercise. \(exercise.exercise.displayName)."
        var norwegian =
            "Neste øvelse. \(exercise.exercise.displayName)."

        if !target.english.isEmpty {
            english += " \(target.english)"
            norwegian += " \(target.norwegian)"
        }

        return (
            english,
            norwegian
        )
    }

    private func strengthTargetCoachPhrase(
        set: StrengthSetLog,
        fallbackReps: Int?,
        fallbackDurationSeconds: Int?,
        fallbackWeightKilograms:
            Double?,
        fallbackResistanceLevel: Int?
    ) -> (
        english: String,
        norwegian: String
    ) {
        var english = ""
        var norwegian = ""

        switch set.resolvedTargetKind {
        case .reps:
            if let reps =
                    fallbackReps ??
                    set.plannedReps,
               reps > 0 {
                english =
                    "\(reps) reps"
                norwegian =
                    "\(reps) repetisjoner"
            }

        case .time:
            if let seconds =
                    fallbackDurationSeconds ??
                    set
                        .plannedDurationSeconds,
               seconds > 0 {
                let duration =
                    coachDurationPhrase(
                        seconds
                    )
                english =
                    duration.english
                norwegian =
                    duration.norwegian
            }
        }

        switch set.resolvedLoadKind {
        case .weightKilograms:
            if let weight =
                    fallbackWeightKilograms ??
                    set
                        .plannedWeightKilograms,
               weight > 0 {
                let formatted =
                    weight.rounded() ==
                        weight
                        ? String(
                            Int(weight)
                        )
                        : String(
                            format:
                                "%.1f",
                            weight
                        )

                english +=
                    english.isEmpty
                        ? "\(formatted) kilograms"
                        : " at \(formatted) kilograms"
                norwegian +=
                    norwegian.isEmpty
                        ? "\(formatted) kilo"
                        : " på \(formatted) kilo"
            }

        case .resistanceLevel:
            if let level =
                    fallbackResistanceLevel ??
                    set
                        .plannedResistanceLevel,
               level > 0 {
                english +=
                    english.isEmpty
                        ? "Resistance level \(level)"
                        : " at resistance level \(level)"
                norwegian +=
                    norwegian.isEmpty
                        ? "Motstand \(level)"
                        : " på motstand \(level)"
            }
        }

        if !english.isEmpty {
            english += "."
            norwegian += "."
        }

        return (
            english,
            norwegian
        )
    }

    private func coachDurationPhrase(
        _ seconds: Int
    ) -> (
        english: String,
        norwegian: String
    ) {
        let bounded =
            max(seconds, 0)
        let minutes =
            bounded / 60
        let remainder =
            bounded % 60

        if minutes > 0,
           remainder > 0 {
            return (
                "\(minutes) minutes and \(remainder) seconds",
                "\(minutes) minutter og \(remainder) sekunder"
            )
        }

        if minutes > 0 {
            return (
                "\(minutes) minutes",
                "\(minutes) minutter"
            )
        }

        return (
            "\(remainder) seconds",
            "\(remainder) sekunder"
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
                    coachConfiguration,
                cueKind: .strengthRest
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
                            coachConfiguration,
                        cueKind: .strengthRest
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

                if coachConfiguration.enabled {
                    var englishParts:
                        [String] = []
                    var norwegianParts:
                        [String] = []

                    if coachConfiguration
                        .announceRestComplete {
                        englishParts.append(
                            strength
                                .currentExerciseAllSetsCompleted
                                ? "Rest complete. Ready for the next exercise."
                                : "Rest complete."
                        )
                        norwegianParts.append(
                            strength
                                .currentExerciseAllSetsCompleted
                                ? "Hvilen er ferdig. Klar for neste øvelse."
                                : "Hvilen er ferdig."
                        )
                    }

                    if strength
                        .currentExerciseAllSetsCompleted {
                        if coachConfiguration
                            .announceNextExercise,
                           let nextExercise =
                                upcomingExerciseCoachPhrase() {
                            englishParts.append(
                                nextExercise.english
                            )
                            norwegianParts.append(
                                nextExercise.norwegian
                            )
                        }
                    } else if let nextSet =
                                nextSetCoachPhrase() {
                        englishParts.append(
                            nextSet.english
                        )
                        norwegianParts.append(
                            nextSet.norwegian
                        )
                    }

                    if !englishParts.isEmpty {
                        strengthCoach.speak(
                            english:
                                englishParts
                                    .joined(
                                        separator:
                                            " "
                                    ),
                            norwegian:
                                norwegianParts
                                    .joined(
                                        separator:
                                            " "
                                    ),
                            configuration:
                                coachConfiguration,
                            cueKind: .strengthRest
                        )
                    }
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
                            .displayName ??
                        active.title
                    let totalSets =
                        active.exercises
                            .flatMap(\.sets)
                            .filter { $0.hybridPhaseKind == nil }
                            .count
                    let exercisePosition =
                        min(
                            strength
                                .currentExerciseIndex +
                            1,
                            max(
                                active
                                    .exercises
                                    .count,
                                1
                            )
                        )

                    var english =
                        "\(active.totalCompletedSets) of \(totalSets) sets complete. Current exercise: \(exerciseName)."
                    var norwegian =
                        "\(active.totalCompletedSets) av \(totalSets) sett fullført. Nåværende øvelse: \(exerciseName)."

                    if configuration
                        .audioCoach
                        .shouldAnnounceExerciseProgress {
                        english +=
                            " Exercise \(exercisePosition) of \(active.exercises.count)."
                        norwegian +=
                            " Øvelse \(exercisePosition) av \(active.exercises.count)."
                    }

                    strengthCoach.speak(
                        english: english,
                        norwegian:
                            norwegian,
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

            guard strength.finish(
                healthKitWorkoutUUID:
                    healthWorkoutUUID,
                duration:
                    endDate.timeIntervalSince(
                        workout.startedAt
                    )
            ) else {
                finishInProgress = false
                watchFinishError = strength.completionSaveError
                return
            }
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
        guard strength.finish(
            healthKitWorkoutUUID: nil,
            duration:
                snapshot.confirmedActiveDuration,
            activeCalories:
                snapshot.activeCalories,
            averageHeartRate:
                snapshot.averageHeartRate,
            maxHeartRate:
                snapshot.maxHeartRate
        ) else {
            watchFinishError = strength.completionSaveError
            return
        }
        appSession.endTrainingStatus()
    }

    /// Confirming is a save action, not a destructive delete.
    /// The active workout remains untouched until the primary action is tapped.
    @ViewBuilder
    /// A single thin line tucked under the Spotify toolbar button.
    /// Reuses the playback commands without opening a modal sheet.
    private var inlineSpotifyBar: some View {
        HStack(spacing: 7) {
            ATHLTHSpotifyGlyph()
                .frame(width: 17, height: 17)
                .accessibilityHidden(true)
            Text("Spotify")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ATHLTHTrainDesign.ink)
            Spacer(minLength: 0)
            Button {
                Task {
                    await spotify.handleIPhoneAudioDockCommand(
                        spotify.isPlaying ? .pause : .resume
                    )
                }
            } label: {
                Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 31, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spotify.isPlaying
                ? ATHLTHLocalization.choose(
                    english: "Pause Spotify", norwegian: "Pause Spotify"
                  )
                : ATHLTHLocalization.choose(
                    english: "Play Spotify", norwegian: "Spill Spotify"
                  ))
            Button {
                Task {
                    await spotify.handleIPhoneAudioDockCommand(.next)
                }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 31, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Next Spotify track", norwegian: "Neste Spotify-låt"
            ))
        }
        .foregroundStyle(ATHLTHTrainDesign.ink)
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(width: 207, height: 40)
        .background(ATHLTHTrainDesign.paper, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
        .shadow(color: ATHLTHTrainDesign.ink.opacity(0.05),
                radius: 6, x: 0, y: 2)
    }

    private var strengthFinishConfirmationSheet: some View {
        if let workout = strength.activeWorkout {
            let plannedSetCount = workout.exercises.reduce(0) {
                $0 + $1.sets.filter { $0.hybridPhaseKind == nil }.count
                    + ($1.skippedPlannedSetCount ?? 0)
            }
            let completedSetCount = min(max(workout.totalCompletedSets, 0),
                                        max(plannedSetCount, 0))
            let remainingSets = max(plannedSetCount - completedSetCount, 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                            .frame(width: 52, height: 52)
                            .background(ATHLTHTrainDesign.paleGold.opacity(0.56),
                                        in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ATHLTHLocalization.choose(
                                english: "Finish your workout?",
                                norwegian: "Avslutte treningsøkten?"
                            ))
                            .font(.system(size: 27, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHTrainDesign.ink)
                            Text(ATHLTHLocalization.choose(
                                english: "Review your progress before saving.",
                                norwegian: "Se over økten før du lagrer."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        HStack(spacing: 16) {
                            finishMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Elapsed", norwegian: "Varighet"
                                ),
                                value: "\(max(Int(Date().timeIntervalSince(workout.startedAt) / 60), 0)) min",
                                symbol: "clock"
                            )
                            finishMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Sets completed", norwegian: "Fullførte sett"
                                ),
                                value: "\(completedSetCount) / \(plannedSetCount)",
                                symbol: "dumbbell"
                            )
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ATHLTHTrainDesign.rule.opacity(0.65))
                                Capsule()
                                    .fill(ATHLTHTrainDesign.gold)
                                    .frame(width: geometry.size.width *
                                        (plannedSetCount > 0
                                            ? CGFloat(completedSetCount) / CGFloat(plannedSetCount)
                                            : 0))
                            }
                        }
                        .frame(height: 5)
                        .accessibilityHidden(true)

                        if remainingSets > 0 {
                            Label(ATHLTHLocalization.choose(
                                english: "\(remainingSets) sets remain. You can still save the session as it is.",
                                norwegian: "\(remainingSets) sett gjenstår. Du kan likevel lagre økten slik den er."
                            ), systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(ATHLTHTrainDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .athlthTrainPaper()

                    Label(finishSaveExplanation(for: workout),
                          systemImage: workout.captureDevice == .appleWatch
                            ? "applewatch" : "heart.text.square")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 21)
                .padding(.top, 25)
                .padding(.bottom, 18)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    Button {
                        guard !finishInProgress else { return }
                        showingFinishConfirmation = false
                        Task { await finishWorkout() }
                    } label: {
                        HStack(spacing: 10) {
                            if finishInProgress {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "Finish and save workout",
                                norwegian: "Avslutt og lagre økten"
                            ))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(
                            LinearGradient(
                                colors: [ATHLTHTrainDesign.bronze, ATHLTHTrainDesign.gold],
                                startPoint: .leading, endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(finishInProgress)

                    Button {
                        showingFinishConfirmation = false
                    } label: {
                        Text(ATHLTHLocalization.choose(
                            english: "Keep training", norwegian: "Fortsett treningen"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .frame(maxWidth: .infinity, minHeight: 43)
                    }
                    .buttonStyle(.plain)
                    .disabled(finishInProgress)
                }
                .padding(.horizontal, 21)
                .padding(.top, 13)
                .padding(.bottom, 8)
                .background(ATHLTHTrainDesign.canvas)
            }
        }
    }

    private func finishMetric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ATHLTHTrainDesign.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finishSaveExplanation(for workout: StrengthWorkoutLog) -> String {
        switch workout.captureDevice {
        case .appleWatch:
            return ATHLTHLocalization.choose(
                english: "Apple Watch will finish the recording. ATHLTH will update the workout when the Watch confirms it.",
                norwegian: "Apple Watch avslutter registreringen. ATHLTH oppdaterer økten når klokken bekrefter avslutningen."
            )
        case .iPhone:
            return health.canWriteWorkouts
                ? ATHLTHLocalization.choose(
                    english: "Your workout is saved in ATHLTH and also sent to Apple Health when available.",
                    norwegian: "Økten lagres i ATHLTH og sendes også til Apple Helse når det er tilgjengelig."
                )
                : ATHLTHLocalization.choose(
                    english: "Your workout is saved in ATHLTH. Apple Health requires write permission.",
                    norwegian: "Økten lagres i ATHLTH. Apple Helse krever skrivetilgang."
                )
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
                focusedBetweenExerciseRestCard(workout)
            }

            if strength.isFreeTrainingBetweenExercises {
                ATHLTHPlanSurface(density: .compact) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Free strength training",
                            norwegian: "Fri styrketrening"
                        ),
                        systemImage: "figure.strengthtraining.traditional"
                    )
                    .font(.headline)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(ATHLTHLocalization.choose(
                        english: "The workout stays active. Add an exercise whenever you're ready.",
                        norwegian: "Økten fortsetter uten valgt øvelse. Legg til en øvelse når du er klar."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Button {
                        showingExerciseLibrary = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Add exercise",
                                norwegian: "Legg til øvelse"
                            ),
                            systemImage: "plus"
                        )
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHPlanDesign.accentInk)
                }
            } else if workoutComplete &&
                showingWorkoutReview {
                focusedWorkoutCompletionHero(
                    workout
                )

                focusedWorkoutPRSummary(
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
                    _ = strength.continueFreeTrainingBetweenExercises()
                    showingWorkoutReview = false
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Continue strength training without an exercise",
                            norwegian: "Fortsett styrketrening uten bestemt øvelse"
                        ),
                        systemImage: "figure.strengthtraining.traditional"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHPlanDesign.accentInk)

                Button {
                    showingExerciseLibrary =
                        true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Add another exercise",
                            norwegian:
                                "Legg til en øvelse"
                        ),
                        systemImage:
                            "plus.rectangle.on.rectangle"
                    )
                    .font(.headline)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 50
                    )
                }
                .buttonStyle(.bordered)
                .tint(
                    ATHLTHTheme.vitality
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
                if exercise.isEmbeddedRunningInterval == true &&
                    !strength.currentExerciseAllSetsCompleted {
                    embeddedIntervalCard(exercise: exercise)
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
                    // Rest countdown and continuation stay visible in the
                    // bottom dock even when the athlete scrolls the hero.
                    EmptyView()
                } else {
                    // Live set registration is now anchored outside ScrollView
                    // to keep the current set visible at every scroll offset.
                    EmptyView()
                }
                }
            }

            if let upcoming = strength.nextPendingExercise,
               !workoutComplete {
                focusedNextExercisePreview(upcoming)
            }
        }
    }

    /// Running-only live presentation within the active strength recording.
    /// Timed 4×4/recovery phases have their own pace, HR and countdown, while
    /// Apple Watch HealthKit continues reporting ONE strength workout.
    @ViewBuilder
    private func embeddedIntervalCard(exercise: StrengthExerciseLog) -> some View {
        if let set = strength.currentSet {
            ATHLTHPlanSurface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 9) {
                        Image(systemName: "figure.run")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 42, height: 42)
                            .background(
                                ATHLTHTheme.champagneSoft,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "RUNNING INSIDE STRENGTH",
                                norwegian: "LØPING I STYRKEØKTEN"
                            ))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            Text(exercise.appendedWorkoutTitle ??
                                 ATHLTHLocalization.choose(
                                     english: "Treadmill intervals",
                                     norwegian: "Mølleintervaller"
                                 ))
                                .font(.headline)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                        }
                        Spacer()
                        Text("\(set.setNumber)/\(exercise.sets.count)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }

                    Text(set.hybridPhaseTitle ?? ATHLTHLocalization.choose(
                        english: "Running", norwegian: "Løping"
                    ))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(ATHLTHPlanDesign.ink)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = strength.currentTimedSetCountdown?
                            .secondsRemaining(at: context.date)
                            ?? set.plannedDurationSeconds ?? 0
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(TimeInterval(seconds).clockDuration)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Spacer(minLength: 2)
                            Text(ATHLTHLocalization.choose(
                                english: "remaining", norwegian: "igjen"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }

                    HStack(spacing: 8) {
                        if let zone = set.hybridTargetHeartRateZone {
                            Label(ATHLTHLocalization.choose(
                                english: "Target zone \(zone)",
                                norwegian: "Målsone \(zone)"
                            ), systemImage: "heart")
                        }
                        if let pace = set.hybridTargetPaceSecondsPerKilometer {
                            Label(
                                TimeInterval(pace).clockDuration + " min/km",
                                systemImage: "speedometer"
                            )
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)

                    HStack(spacing: 10) {
                        focusedNumberField(
                            title: ATHLTHLocalization.choose(
                                english: "Manual speed", norwegian: "Manuell fart"
                            ),
                            value: treadmillSpeedBinding,
                            suffix: "km/t"
                        )
                        focusedNumberField(
                            title: ATHLTHLocalization.choose(
                                english: "Incline", norwegian: "Stigning"
                            ),
                            value: treadmillInclineBinding,
                            suffix: "%"
                        )
                    }

                    HStack(spacing: 10) {
                        Button {
                            if strength.currentTimedSetCountdown?.isRunning == true {
                                strength.pauseTimedSet()
                            } else {
                                strength.startOrResumeTimedSet()
                            }
                        } label: {
                            Label(
                                strength.currentTimedSetCountdown?.isRunning == true
                                    ? ATHLTHLocalization.choose(
                                        english: "Pause phase", norwegian: "Sett på pause"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Resume phase", norwegian: "Start / fortsett"
                                    ),
                                systemImage:
                                    strength.currentTimedSetCountdown?.isRunning == true
                                        ? "pause.fill" : "play.fill"
                            )
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHPlanDesign.accentInk)

                        Button {
                            strength.completeCurrentDraftSet()
                            if strength.currentExercise?.isEmbeddedRunningInterval == true,
                               strength.currentSet?.isCompleted == false {
                                strength.startOrResumeTimedSet()
                            }
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .frame(width: 43, height: 46)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Finish current phase now",
                            norwegian: "Fullfør fasen nå"
                        ))
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "Watch pulse and any measured distance remain attached to this workout. Manually entered speed only estimates pace and distance.",
                        norwegian: "Puls og eventuell målt distanse fra klokken beholdes i samme økt. Manuell fart gir bare estimert tempo og distanse."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
        }
    }

    @ViewBuilder
    private func focusedNextExercisePreview(_ upcoming: StrengthExerciseLog) -> some View {
        let artwork = focusedExerciseMediaURLs(upcoming).first
        let first = upcoming.sets.first
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Group {
                    if let artwork {
                        focusedExerciseArtwork(url: artwork, exercise: upcoming)
                    } else {
                        focusedExerciseArtworkFallback(upcoming)
                    }
                }
                .frame(width: 94, height: 94)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "UP NEXT", norwegian: "NESTE ØVELSE"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)

                    Text(upcoming.exercise.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(ATHLTHLocalization.choose(
                        english: "\(upcoming.sets.count) sets",
                        norwegian: "\(upcoming.sets.count) sett"
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                    if let duration = first?.plannedDurationSeconds,
                       duration > 0 {
                        Label(TimeInterval(duration).clockDuration,
                              systemImage: "timer")
                            .font(.caption.weight(.semibold))
                    } else if let reps = first?.plannedReps {
                        Text("\(reps) reps")
                            .font(.caption.weight(.semibold))
                    }
                    if let weight = first?.plannedWeightKilograms,
                       weight > 0 {
                        Text(String(format: "%.1f kg", weight))
                            .font(.caption.weight(.semibold))
                    }
                    if let speed = upcoming.targetSpeedKilometersPerHour,
                       speed > 0 {
                        Text(String(format: "Målfart %.1f km/t", speed))
                            .font(.caption.weight(.semibold))
                    }
                    if let zone = upcoming.targetHeartRateZone {
                        Text("Målpuls: sone \(zone)")
                            .font(.caption.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                // Existing engine keeps completed sets intact and never
                // edits the original training plan.
                _ = strength.selectExerciseForNow(upcoming.id)
            } label: {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Open next exercise",
                        norwegian: "Åpne neste øvelse"
                    ))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .padding(.horizontal, 15)
                .frame(minHeight: 44)
                .background(ATHLTHTheme.champagne, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ATHLTHTheme.premiumGold.opacity(0.20), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }

    /// Count the interval after the last completed exercise as rest, not as
    /// an extension of its training time. Date anchors survive app suspension.
    private func focusedBetweenExerciseRestCard(
        _ workout: StrengthWorkoutLog
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let ended = workout.exercises.compactMap(\.completedAt).max()
            let restStart = strength.restStartedAt ?? ended ?? timeline.date
            let seconds = max(0, timeline.date.timeIntervalSince(restStart))
            HStack(spacing: 10) {
                Image(systemName: "pause.circle")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ATHLTHLocalization.choose(
                        english: "Rest after planned exercises",
                        norwegian: "Pause etter planlagte øvelser"
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Text(seconds.clockDuration)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                }
                Spacer()
            }
            .padding(14)
            .background(
                ATHLTHPlanDesign.warmSurface,
                in: RoundedRectangle(cornerRadius: 17)
            )
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

    @ViewBuilder
    private func focusedWorkoutPRSummary(
        _ workout: StrengthWorkoutLog
    ) -> some View {
        let records =
            strength
                .workoutPersonalRecords(
                    for: workout
                )

        if !records.isEmpty {
            VStack(
                alignment: .leading,
                spacing: 13
            ) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                ATHLTHTheme
                                    .premiumGoldSoft
                            )
                            .frame(
                                width: 42,
                                height: 42
                            )

                        Image(
                            systemName:
                                "medal.fill"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            ATHLTHTheme
                                .premiumGold
                        )
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "New personal records",
                                norwegian:
                                    "Nye personlige rekorder"
                            )
                        )
                        .font(
                            .headline.weight(
                                .bold
                            )
                        )

                        Text(
                            ATHLTHLocalization.format(
                                english:
                                    "%d new PRs in this workout",
                                norwegian:
                                    "%d nye PR-er i denne økten",
                                records.count
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()
                }

                ForEach(records) {
                    record in
                    HStack(spacing: 11) {
                        Image(
                            systemName:
                                prSystemImage(
                                    record.kind
                                )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .premiumGold
                        )
                        .frame(
                            width: 32,
                            height: 32
                        )
                        .background(
                            ATHLTHTheme
                                .premiumGoldSoft,
                            in: Circle()
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            HStack(spacing: 6) {
                                Text(
                                    record
                                        .exerciseName
                                )
                                .font(
                                    .subheadline
                                        .weight(
                                            .semibold
                                        )
                                )
                                .lineLimit(1)

                                Text(
                                    prShortTitle(
                                        record.kind
                                    )
                                )
                                .font(
                                    .caption2
                                        .weight(.bold)
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .premiumGold
                                )
                                .padding(
                                    .horizontal,
                                    6
                                )
                                .padding(
                                    .vertical,
                                    2
                                )
                                .background(
                                    ATHLTHTheme
                                        .premiumGoldSoft,
                                    in: Capsule()
                                )
                            }

                            Text(
                                record.previousValue +
                                "  →  " +
                                record.value
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

                        Spacer()

                        Image(
                            systemName:
                                "sparkles"
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .premiumGold
                        )
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
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme
                            .premiumGoldSoft
                            .opacity(0.40),
                        Color.white
                            .opacity(0.26)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                ),
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
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.23),
                    lineWidth: 1
                )
            }
        }
    }

    private func prShortTitle(
        _ kind: StrengthWorkoutPRKind
    ) -> String {
        switch kind {
        case let .repMax(reps):
            return "\(reps)RM"

        case .heaviestWeight:
            return
                ATHLTHLocalization.choose(
                    english:
                        "Heaviest",
                    norwegian:
                        "Tyngst"
                )

        case .estimatedOneRepMax:
            return
                ATHLTHLocalization.choose(
                    english:
                        "Est. 1RM",
                    norwegian:
                        "Est. 1RM"
                )
        }
    }

    private func prSystemImage(
        _ kind: StrengthWorkoutPRKind
    ) -> String {
        switch kind {
        case .repMax:
            return "trophy.fill"
        case .heaviestWeight:
            return "dumbbell.fill"
        case .estimatedOneRepMax:
            return "bolt.fill"
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
            let recordedDuration =
                workout.healthMetrics.duration
                    .flatMap {
                        $0 > 0
                            ? $0
                            : nil
                    }
            let resolvedEndDate =
                workout.endedAt ??
                context.date
            let totalDuration =
                max(
                    recordedDuration ??
                    resolvedEndDate
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
        let workoutPRs =
            strength
                .workoutPersonalRecords(
                    for: workout
                )

        return VStack(
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
                    exercise,
                    records:
                        workoutPRs.filter {
                            $0.exerciseID ==
                                exercise.id
                        }
                )
            }
        }
    }

    private func completionExerciseCard(
        _ exercise:
            StrengthExerciseLog,
        records:
            [StrengthWorkoutPersonalRecord]
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
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    if let skipped = exercise.skippedPlannedSetCount, skipped > 0 {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "\(skipped) planned set(s) skipped",
                                norwegian: "\(skipped) planlagte sett hoppet over"
                            ),
                            systemImage: "forward.end"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                }

                Spacer()

                if !records.isEmpty {
                    Label(
                        records.count == 1
                            ? "PR"
                            : "PR ×(records.count)",
                        systemImage:
                            "medal.fill"
                    )
                    .font(
                        .caption2.weight(
                            .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                    .padding(
                        .horizontal,
                        8
                    )
                    .padding(
                        .vertical,
                        4
                    )
                    .background(
                        ATHLTHTheme
                            .premiumGoldSoft,
                        in: Capsule()
                    )
                }

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

                        if records.contains(
                            where: {
                                $0.setID ==
                                    set.id
                            }
                        ) {
                            Text("PR")
                                .font(
                                    .caption2
                                        .weight(
                                            .bold
                                        )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .premiumGold
                                )
                                .padding(
                                    .horizontal,
                                    7
                                )
                                .padding(
                                    .vertical,
                                    3
                                )
                                .background(
                                    ATHLTHTheme
                                        .premiumGoldSoft,
                                    in: Capsule()
                                )
                        }

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
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let timer = strength.currentTimedSetCountdown
            let totalSets = max(
                workout.exercises.reduce(0) {
                    $0 + $1.sets.filter {
                        $0.hybridPhaseKind == nil
                    }.count + ($1.skippedPlannedSetCount ?? 0)
                }, 1
            )
            let completed = min(max(workout.totalCompletedSets, 0), totalSets)
            let phase = ATHLTHPhoneStrengthPhaseResolver.resolve(
                workoutComplete: workout.exercises.allSatisfy { $0.isCompleted },
                exerciseComplete: strength.currentExerciseAllSetsCompleted,
                isResting: strength.isResting,
                restEndsAt: strength.restEndsAt,
                isTimedSet: strength.currentSet?.resolvedTargetKind == .time,
                timerStarted: timer != nil,
                timerRunning: timer?.isRunning == true,
                timerRemaining: timer.map {
                    TimeInterval($0.secondsRemaining(at: timeline.date))
                },
                now: timeline.date
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Label(
                            max(0, timeline.date.timeIntervalSince(workout.startedAt))
                                .clockDuration,
                            systemImage: "clock"
                        )
                        .font(.system(size: 15, weight: .bold,
                                      design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    }

                    Spacer(minLength: 3)

                    VStack(alignment: .trailing, spacing: 4) {
                        Label(
                            workout.captureDevice.title,
                            systemImage: workout.captureDevice == .appleWatch
                                ? "applewatch" : "iphone"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(ATHLTHLocalization.format(
                            english: "%d/%d sets",
                            norwegian: "%d/%d sett",
                            completed,
                            totalSets
                        ))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .monospacedDigit()
                        let skipped = workout.exercises.reduce(0) {
                            $0 + ($1.skippedPlannedSetCount ?? 0)
                        }
                        if skipped > 0 {
                            Text(ATHLTHLocalization.choose(
                                english: "\(skipped) skipped",
                                norwegian: "\(skipped) hoppet over"
                            ))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                    }
                }

                liveHeartRateAndZoneRow(workout)

                HStack(spacing: 7) {
                    Label(
                        strengthPhaseTitle(phase),
                        systemImage: strengthPhaseSymbol(phase)
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        phase == .resting || phase == .restReady
                            ? ATHLTHTheme.premiumGold
                            : ATHLTHPlanDesign.accentInk
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }

                ProgressView(
                    value: Double(completed),
                    total: Double(totalSets)
                )
                .tint(ATHLTHPlanDesign.accentInk)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english: "Completed sets",
                        norwegian: "Fullførte sett"
                    )
                )
                .accessibilityValue("\(completed) / \(totalSets)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHTheme.card,
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
        }
    }

    private func strengthPhaseTitle(
        _ phase: ATHLTHPhoneStrengthPhase
    ) -> String {
        switch phase {
        case .workingSet:
            return strength.draftWarmUp
                ? ATHLTHLocalization.choose(
                    english: "Warm-up set", norwegian: "Oppvarmingssett"
                  )
                : ATHLTHLocalization.choose(
                    english: "Working set", norwegian: "Arbeidssett"
                  )
        case .timedReady:
            return ATHLTHLocalization.choose(
                english: "Time target ready", norwegian: "Tidsmål klart"
            )
        case .timedRunning:
            return ATHLTHLocalization.choose(
                english: "Set countdown running", norwegian: "Nedtelling pågår"
            )
        case .timedPaused:
            return ATHLTHLocalization.choose(
                english: "Set countdown paused", norwegian: "Nedtelling pauset"
            )
        case .timedFinished:
            return ATHLTHLocalization.choose(
                english: "Time complete · finish set",
                norwegian: "Tiden er ute · fullfør settet"
            )
        case .resting:
            return ATHLTHLocalization.choose(
                english: "Rest between sets", norwegian: "Pause mellom sett"
            )
        case .restReady:
            return ATHLTHLocalization.choose(
                english: "Ready · continue when you choose",
                norwegian: "Klar · fortsett når du ønsker"
            )
        case .exerciseComplete:
            return ATHLTHLocalization.choose(
                english: "Exercise complete", norwegian: "Øvelse fullført"
            )
        case .workoutComplete:
            return ATHLTHLocalization.choose(
                english: "All exercises complete",
                norwegian: "Alle øvelser fullført"
            )
        }
    }

    private func strengthPhaseSymbol(
        _ phase: ATHLTHPhoneStrengthPhase
    ) -> String {
        switch phase {
        case .resting, .restReady:
            return "timer"
        case .timedReady, .timedRunning, .timedPaused, .timedFinished:
            return "stopwatch"
        case .exerciseComplete, .workoutComplete:
            return "checkmark.circle.fill"
        case .workingSet:
            return "dumbbell.fill"
        }
    }

    /// Pulse zone is always measured automatically from Watch heart rate.
    /// A workout target is a separate, optional pre-workout preference.
    private func liveHeartRateAndZoneRow(_ workout: StrengthWorkoutLog) -> some View {
        let pulse = strengthWatchSnapshot?.heartRate
        let maximum = appSession.onboardingProfile?.maximumHeartRateBPM
        let maxBPM = maximum.map(Double.init)
        let observed = ATHLTHHeartRateZones.measuredZone(
            heartRateBPM: pulse, maximumBPM: maxBPM
        )
        let target = strength.currentExercise?.targetHeartRateZone ??
            workout.liveHeartRateTargetZone

        return HStack(spacing: 9) {
            Label(
                (pulse ?? 0) > 0
                    ? "\(Int((pulse ?? 0).rounded())) bpm"
                    : ATHLTHLocalization.choose(
                        english: "Waiting for Apple Watch pulse",
                        norwegian: "Venter på puls fra Apple Watch"
                    ),
                systemImage: "heart.fill"
            )
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: 3) {
                Text(observed.map {
                    ATHLTHLocalization.choose(
                        english: "Zone \($0)", norwegian: "Sone \($0)"
                    )
                } ?? ATHLTHLocalization.choose(
                    english: "Zone unavailable", norwegian: "Sone ikke tilgjengelig"
                ))
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

                if let target {
                    Text(ATHLTHLocalization.choose(
                        english: "Target: zone \(target)",
                        norwegian: "Mål: sone \(target)"
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            ATHLTHPlanDesign.warmSurface,
            in: RoundedRectangle(cornerRadius: 13)
        )
        .accessibilityElement(children: .combine)
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
            .overlay(
                alignment: .topLeading
            ) {
                if let pr =
                        focusedExercisePRHint(
                            exercise
                        ) {
                    HStack(spacing: 5) {
                        Image(
                            systemName:
                                "trophy.fill"
                        )
                        .font(.caption2)

                        Text(pr.label)
                            .font(
                                .caption2
                                    .weight(.bold)
                            )

                        Text(pr.value)
                            .font(
                                .caption2
                                    .monospacedDigit()
                                    .weight(.semibold)
                            )
                    }
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                    .padding(
                        .horizontal,
                        9
                    )
                    .padding(
                        .vertical,
                        6
                    )
                    .background(
                        Color.black
                            .opacity(0.28),
                        in: Capsule()
                    )
                    .background(
                        .ultraThinMaterial,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                ATHLTHTheme
                                    .premiumGold
                                    .opacity(0.34),
                                lineWidth: 0.8
                            )
                    }
                    .padding(12)
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english:
                                "Personal record, \(pr.label), \(pr.value)",
                            norwegian:
                                "Personlig rekord, \(pr.label), \(pr.value)"
                        )
                    )
                }
            }

            if exercise.targetSpeedKilometersPerHour != nil ||
                exercise.targetHeartRateZone != nil {
                HStack(spacing: 8) {
                    if let speed = exercise.targetSpeedKilometersPerHour {
                        Label(
                            String(format: "Målfart %.1f km/t", speed),
                            systemImage: "speedometer"
                        )
                    }
                    if let zone = exercise.targetHeartRateZone {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Target zone \(zone)",
                                norwegian: "Målsone \(zone)"
                            ),
                            systemImage: "heart.text.square"
                        )
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    ATHLTHTheme.premiumGoldSoft,
                    in: RoundedRectangle(cornerRadius: 13)
                )
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

                if isCurrentStrengthTreadmill {
                    focusedHeroMetric(
                        value: String(
                            format: "%.1f",
                            strength.draftTreadmillSpeedKilometersPerHour
                        ),
                        label: "KM/T",
                        icon: "speedometer"
                    )
                    focusedHeroDivider
                    focusedHeroMetric(
                        value: String(
                            format: "%.1f%%",
                            strength.draftTreadmillInclinePercent
                        ),
                        label: ATHLTHLocalization.choose(
                            english: "INCLINE", norwegian: "STIGN."
                        ),
                        icon: "mountain.2"
                    )
                } else {
                focusedHeroMetric(
                    value: currentStrengthLoadKind == .weightKilograms &&
                            !strength.currentSetRecordsWeight ? "—" :
                        currentStrengthLoadKind ==
                            .resistanceLevel
                            ? "\(strength.draftResistanceLevel)"
                            : formatWeight(
                                strength
                                    .draftWeightKilograms
                            ) + " kg",
                    label:
                        currentStrengthLoadKind == .weightKilograms &&
                            !strength.currentSetRecordsWeight
                            ? ATHLTHLocalization.choose(
                                english: "NO WEIGHT", norwegian: "UTEN VEKT"
                            )
                            : currentStrengthLoadKind == .resistanceLevel
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
            }
            .padding(.vertical, 12)
            .background(ATHLTHPlanDesign.surface)
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
                ATHLTHPlanDesign.warmDivider,
                lineWidth: 0.8
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
    private func focusedUpcomingExerciseHero(
        _ next: StrengthExerciseLog,
        completed previous: StrengthExerciseLog
    ) -> some View {
        let urls = focusedExerciseMediaURLs(next)

        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = urls.first {
                    focusedExerciseArtwork(url: url, exercise: next)
                } else {
                    focusedExerciseArtworkFallback(next)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Next exercise",
                        norwegian: "Neste øvelse"
                    ),
                    systemImage: "arrow.right.circle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.86))

                Text(next.exercise.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(
                    ATHLTHLocalization.choose(
                        english: next.sets.first?.plannedReps.map {
                            "\(next.sets.count) sets · \($0) planned reps"
                        } ?? "\(next.sets.count) sets",
                        norwegian: next.sets.first?.plannedReps.map {
                            "\(next.sets.count) sett · \($0) planlagte reps"
                        } ?? "\(next.sets.count) sett"
                    )
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))

                Text(
                    ATHLTHLocalization.choose(
                        english: "Completed: \(previous.exercise.displayName)",
                        norwegian: "Fullført: \(previous.exercise.displayName)"
                    )
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
            }
            .padding(16)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
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

    private func focusedExercisePRHint(
        _ exercise: StrengthExerciseLog
    ) -> (
        label: String,
        value: String
    )? {
        func normalized(
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

        let exerciseKey =
            normalized(
                exercise.exercise.name
            )
        let targetReps =
            strength.currentSet?
                .plannedReps ??
            strength.draftReps

        if targetReps > 0,
           let exact =
                strength
                    .repPersonalRecords
                    .first(
                        where: {
                            normalized(
                                $0.exerciseName
                            ) == exerciseKey &&
                            $0.reps ==
                                targetReps
                        }
                    ) {
            if exact.weightKilograms > 0 {
                return (
                    label:
                        "(targetReps)RM",
                    value:
                        formatWeight(
                            exact
                                .weightKilograms
                        ) + " kg"
                )
            }

            return (
                label:
                    ATHLTHLocalization.choose(
                        english: "Rep PR",
                        norwegian: "Rep-PR"
                    ),
                value:
                    "(exact.reps) reps"
            )
        }

        if let heaviest =
                strength
                    .personalRecords
                    .first(
                        where: {
                            $0.kind ==
                                .heaviestSet &&
                            normalized(
                                $0.title
                            ) == exerciseKey
                        }
                    ) {
            return (
                label:
                    ATHLTHLocalization.choose(
                        english: "PR",
                        norwegian: "PR"
                    ),
                value:
                    heaviest.value
            )
        }

        return nil
    }

    private func focusedExerciseVideoURL(_ exercise: StrengthExerciseLog) -> URL? {
        // Snapshots preserve demonstrations even when a custom exercise changes.
        exercise.exercise.videoURL ??
            focusedExerciseLibraryEntry(exercise)?.exercise.videoURL
    }

    /// The same native front/back atlas used by ATHLTH Insights, scoped to
    /// the selected exercise rather than accumulated training history.
    private func focusedExerciseMuscleDetail(
        _ exercise: StrengthExerciseLog
    ) -> some View {
        let primary = focusedExerciseRegions(
            exercise.exercise.primaryMuscles,
            fallbackName: exercise.exercise.name
        )
        let secondary = focusedExerciseRegions(
            exercise.exercise.secondaryMuscles ?? [],
            fallbackName: nil
        ).subtracting(primary)
        let regions = primary.union(secondary)
        let profile = StrengthMuscleProfile(
            activations: regions.map {
                StrengthMuscleActivation(
                    region: $0,
                    score: primary.contains($0) ? 4.5 : 2.1
                )
            },
            primaryRegions: primary,
            secondaryRegions: secondary
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                Text(ATHLTHLocalization.choose(
                    english: "Muscles used",
                    norwegian: "Muskelgrupper som trenes"
                ))
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(ATHLTHPlanDesign.ink)
            if !regions.isEmpty {
                StrengthMuscleMapView(
                    profile: profile,
                    compact: true,
                    activationTint: ATHLTHTheme.vitality
                )
                .frame(maxWidth: .infinity)
                .frame(height: 142)
            }
            if !exercise.exercise.primaryMuscles.isEmpty {
                let primaryMuscles = exercise.exercise.primaryMuscles
                Text(ATHLTHLocalization.choose(
                    english: "Primary: ", norwegian: "Primær: "
                ) + primaryMuscles.joined(separator: " · "))
                .font(.caption.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            }
            if let secondaryMuscles = exercise.exercise.secondaryMuscles,
               !secondaryMuscles.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Secondary: ", norwegian: "Sekundær: "
                ) + secondaryMuscles.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.warmSurface,
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func focusedExerciseRegions(
        _ labels: [String],
        fallbackName: String?
    ) -> Set<StrengthMuscleRegion> {
        var regions: Set<StrengthMuscleRegion> = []
        for name in labels {
            let lower = name.lowercased()
            for region in StrengthMuscleRegion.allCases {
                let raw = region.rawValue.lowercased()
                if lower == raw || lower == region.title.lowercased() {
                    regions.insert(region)
                }
            }
            if lower.contains("quad") || lower.contains("forside lår") {
                regions.insert(.quads)
            }
            if lower.contains("glute") || lower.contains("setemus") {
                regions.insert(.glutes)
            }
            if lower.contains("hamstring") || lower.contains("bakside lår") {
                regions.insert(.hamstrings)
            }
            if lower.contains("chest") || lower.contains("bryst") {
                regions.insert(.chest)
            }
            if lower.contains("back") || lower.contains("rygg") {
                regions.insert(.upperBack)
            }
            if lower.contains("shoulder") || lower.contains("skulder") {
                regions.insert(.frontDelts)
            }
            if lower.contains("calf") || lower.contains("legg") {
                regions.insert(.calves)
            }
            if lower.contains("tricep") { regions.insert(.triceps) }
            if lower.contains("bicep") { regions.insert(.biceps) }
        }
        if regions.isEmpty, let fallbackName {
            regions.formUnion(
                StrengthMuscleResolver.fallbackRegions(
                    forExerciseName: fallbackName
                )
            )
        }
        return regions
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
        let demoURL = focusedExerciseVideoURL(exercise)

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
                    focusedExerciseMuscleDetail(exercise)
                    if let demoURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Demonstration",
                                    norwegian: "Demonstrasjon"
                                ),
                                systemImage: "play.rectangle"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                            // Play only when instructions are expanded, never automatically
                            // while the athlete is recording or resting.
                            VideoPlayer(player: AVPlayer(url: demoURL))
                                .frame(height: 190)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .id(demoURL)
                        }
                    }

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

                    if demoURL == nil &&
                        summary == nil &&
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

    /// The focused set stays in a single compact surface at the bottom of
    /// the device, independent of scrolling and the instruction gallery.
    /// Larger horizontal buttons replace the unstable vertical chevrons.
    @ViewBuilder
    private func compactLiveStrengthDock(
        exercise: StrengthExerciseLog
    ) -> some View {
        VStack(spacing: 10) {
            if strength.isResting, let end = strength.restEndsAt {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "REST · REMAINING",
                            norwegian: "PAUSE · GJENSTÅR"
                        ))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = end.timeIntervalSince(context.date)
                            Text(remaining > 0
                                 ? max(0, remaining).clockDuration
                                 : "+" + max(0, -remaining).clockDuration)
                                .font(.system(
                                    size: 34, weight: .semibold, design: .rounded
                                ))
                                .monospacedDigit()
                                .foregroundStyle(remaining > 0
                                    ? ATHLTHPlanDesign.ink
                                    : ATHLTHPlanDesign.accentInk)
                                .contentTransition(.numericText())
                                .accessibilityLabel(remaining > 0
                                    ? ATHLTHLocalization.choose(
                                        english: "Time remaining in rest",
                                        norwegian: "Tid igjen av pausen"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Extra rest time",
                                        norwegian: "Ekstra pausetid"
                                    ))
                        }
                    }
                    Spacer()
                    Button {
                        strength.skipRest()
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Continue", norwegian: "Fortsett"
                        ), systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHPlanDesign.accentInk)
                }
            } else {
                HStack(spacing: 8) {
                    Text(ATHLTHLocalization.format(
                        english: "Set %d / %d",
                        norwegian: "Sett %d / %d",
                        strength.currentSet?.setNumber ?? 1,
                        max(exercise.sets.count, 1)
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    Spacer()
                    if StrengthBarbellExercisePolicy.usesBar(exercise),
                       currentStrengthLoadKind == .weightKilograms {
                        Menu {
                            ForEach([0.0, 5.0, 10.0, 15.0, 20.0, 25.0],
                                    id: \.self) { mass in
                                Button(String(format: "%.0f kg", mass)) {
                                    _ = strength.setActiveExerciseBarWeight(
                                        exercise.id, kilograms: mass
                                    )
                                }
                            }
                        } label: {
                            Label(String(format: "%g kg", exercise.barWeightKilograms ?? 20),
                                  systemImage: "scalemass")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Bar weight, included in the total",
                            norwegian: "Stangvekt, inkludert i totalvekten"
                        ))
                    }
                }

                HStack(spacing: 10) {
                    if currentStrengthLoadKind == .resistanceLevel {
                        compactLiveIntegerMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Resistance", norwegian: "Motstand"),
                            value: draftResistanceBinding, step: 1
                        )
                    } else if strength.currentSetRecordsWeight {
                        compactLiveDecimalMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Total kg", norwegian: "Totalvekt"),
                            value: draftWeightBinding, step: 2.5
                        )
                    }
                    if currentStrengthTargetKind == .time {
                        compactLiveIntegerMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Seconds", norwegian: "Sekunder"),
                            value: draftDurationBinding, step: 15
                        )
                    } else {
                        compactLiveIntegerMetric(
                            title: ATHLTHLocalization.choose(
                                english: "Reps", norwegian: "Reps"),
                            value: draftRepsBinding, step: 1
                        )
                    }
                }

                Button {
                    if currentStrengthTargetKind == .time &&
                       strength.currentTimedSetCountdown?.isRunning != true {
                        strength.startOrResumeTimedSet()
                    } else {
                        strength.completeCurrentDraftSet()
                    }
                } label: {
                    Label(
                        currentStrengthTargetKind == .time &&
                        strength.currentTimedSetCountdown?.isRunning != true
                            ? ATHLTHLocalization.choose(
                                english: "Start set", norwegian: "Start sett"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Complete set", norwegian: "Fullfør sett"
                            ),
                        systemImage: currentStrengthTargetKind == .time &&
                            strength.currentTimedSetCountdown?.isRunning != true
                            ? "play.fill" : "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPlanDesign.ink)

                if strength.hasNextExercise {
                    Button {
                        strength.skipRest()
                        strength.moveToNextExercise()
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Next exercise",
                            norwegian: "Neste øvelse"
                        ), systemImage: "arrow.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 27)
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Skips ahead without completing unrecorded sets",
                        norwegian: "Går videre uten å registrere resterende sett"
                    ))
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 13)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ATHLTHPlanDesign.surface)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.11), radius: 17, y: -4)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(ATHLTHPlanDesign.outline.opacity(0.65))
                .frame(height: 1)
        }
    }

    private func compactLiveDecimalMetric(
        title: String, value: Binding<Double>, step: Double
    ) -> some View {
        compactLiveMetric(
            title: title,
            decrement: { value.wrappedValue = max(0, value.wrappedValue - step) },
            increment: { value.wrappedValue = min(999, value.wrappedValue + step) }
        ) {
            TextField(
                "0",
                value: value,
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
        }
    }

    private func compactLiveIntegerMetric(
        title: String, value: Binding<Int>, step: Int
    ) -> some View {
        compactLiveMetric(
            title: title,
            decrement: { value.wrappedValue = max(0, value.wrappedValue - step) },
            increment: { value.wrappedValue = min(7_200, value.wrappedValue + step) }
        ) {
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
        }
    }

    private func compactLiveMetric<Content: View>(
        title: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        @ViewBuilder input: () -> Content
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            HStack(spacing: 3) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                input()
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Enter a number or use the minus and plus buttons",
                        norwegian: "Skriv inn tall eller bruk minus- og plussknappene"
                    ))
                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
            .background(ATHLTHPlanDesign.warmSurface,
                        in: RoundedRectangle(cornerRadius: 15))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func focusedSetEntry(
        exercise: StrengthExerciseLog
    ) -> some View {
        ATHLTHUnifiedCard {
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

                if currentStrengthLoadKind == .weightKilograms && !isCurrentStrengthTreadmill {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Record weight for this set",
                            norwegian: "Registrer vekt på dette settet"
                        ),
                        isOn: Binding(
                            get: { strength.currentSetRecordsWeight },
                            set: { strength.setCurrentSetRecordsWeight($0) }
                        )
                    )
                    .tint(ATHLTHPlanDesign.accent)
                    .font(.subheadline.weight(.medium))
                }

                if isCurrentStrengthTreadmill {
                    HStack(spacing: 10) {
                        focusedNumberField(
                            title: ATHLTHLocalization.choose(
                                english: "Speed", norwegian: "Fart"
                            ),
                            value: treadmillSpeedBinding,
                            suffix: "km/t"
                        )
                        focusedNumberField(
                            title: ATHLTHLocalization.choose(
                                english: "Incline", norwegian: "Stigning"
                            ),
                            value: treadmillInclineBinding,
                            suffix: "%"
                        )
                    }
                    focusedDurationField
                    if strength.draftTreadmillSpeedKilometersPerHour > 0,
                       let pace = ATHLTHRunningPace.paceForManualTreadmillSpeed(
                           kilometersPerHour: strength.draftTreadmillSpeedKilometersPerHour
                       ) {
                        Text(ATHLTHLocalization.choose(
                            english: "Manual speed · estimated pace ",
                            norwegian: "Manuell fart · estimert tempo "
                        ) + pace.clockDuration + " min/km")
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                } else {
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
                    } else if strength.currentSetRecordsWeight {
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

                }

                if let active = strength.currentExercise,
                   StrengthBarbellExercisePolicy.usesBar(active),
                   currentStrengthLoadKind == .weightKilograms,
                   strength.currentSetRecordsWeight {
                    HStack(spacing: 9) {
                        Image(systemName: "scalemass")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Bar weight",
                                norwegian: "Stangvekt"
                            ))
                            .font(.caption.weight(.semibold))
                            Text(ATHLTHLocalization.choose(
                                english: "Included in total weight",
                                norwegian: "Inkludert i totalvekten"
                            ))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button(ATHLTHLocalization.choose(
                                english: "Not set", norwegian: "Ikke valgt"
                            )) {
                                _ = strength.setActiveExerciseBarWeight(
                                    active.id, kilograms: nil
                                )
                            }
                            ForEach([0.0, 5.0, 10.0, 15.0, 20.0, 25.0],
                                    id: \.self) { kg in
                                Button(String(format: "%.0f kg", kg)) {
                                    _ = strength.setActiveExerciseBarWeight(
                                        active.id, kilograms: kg
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(String(
                                    format: "%.0f kg",
                                    active.barWeightKilograms ?? 20
                                ))
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }
                    }
                    .padding(.vertical, 5)
                }

                if currentStrengthTargetKind == .time {
                    timedSetCountdownCard
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

                if exercise.sets.contains(where: { $0.isCompleted }) &&
                   exercise.sets.contains(where: { !$0.isCompleted }) {
                    Button {
                        showingOmitRemainingSetsConfirmation = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Skip remaining planned sets",
                                norwegian: "Hopp over resterende sett"
                            ),
                            systemImage: "forward.end"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHPlanDesign.accentInk)
                    .confirmationDialog(
                        ATHLTHLocalization.choose(
                            english: "End this exercise without the remaining sets?",
                            norwegian: "Avslutte øvelsen uten de resterende settene?"
                        ),
                        isPresented: $showingOmitRemainingSetsConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(ATHLTHLocalization.choose(
                            english: "Skip remaining sets",
                            norwegian: "Hopp over resterende sett"
                        )) {
                            _ = strength.omitRemainingSetsOfCurrentExercise()
                        }
                    } message: {
                        Text(ATHLTHLocalization.choose(
                            english: "Completed sets are kept. The remaining sets are recorded as omitted, not completed.",
                            norwegian: "Fullførte sett beholdes. Resten registreres som hoppet over, ikke fullført."
                        ))
                    }
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
                .tint(ATHLTHPlanDesign.accentInk)
                .clipShape(Capsule())
                .shadow(
                    color: ATHLTHPlanDesign.accentInk.opacity(0.12),
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
            StrengthClearableNumericField(
                value: value,
                allowsDecimal: true
            )
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
            StrengthClearableNumericField(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0) }
                ),
                allowsDecimal: false
            )
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

    private var isCurrentStrengthTreadmill: Bool {
        strength.currentExercise.map {
            StrengthTreadmillWarmUpDefaults.isTreadmill($0.exercise.name)
        } ?? false
    }

    private var treadmillSpeedBinding: Binding<Double> {
        Binding(
            get: { strength.draftTreadmillSpeedKilometersPerHour },
            set: { strength.setDraft(treadmillSpeedKilometersPerHour: $0) }
        )
    }

    private var treadmillInclineBinding: Binding<Double> {
        Binding(
            get: { strength.draftTreadmillInclinePercent },
            set: { strength.setDraft(treadmillInclinePercent: $0) }
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

    /// One shared timer surface in both focused and legacy strength set layouts.
    /// The absolute start date lives in StrengthWorkoutStore, so a locked phone
    /// or a temporarily backgrounded app cannot make the countdown drift.
    private var timedSetCountdownCard: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let countdown = strength.currentTimedSetCountdown
            let target = countdown?.targetSeconds ?? strength.draftDurationSeconds
            let remaining = countdown?.secondsRemaining(at: context.date) ?? target
            let isRunning = countdown?.isRunning == true
            let finished = countdown?.isFinished(at: context.date) == true
            let elapsed = countdown?.elapsedSeconds(at: context.date) ?? 0
            let overtime = countdown?.overtimeSeconds(at: context.date) ?? 0
            // Once the target is reached, show the sum of this exercise's
            // earlier completed timed sets and the current elapsed time.
            let earlierTimedSeconds = strength.currentExercise?.sets
                .filter { $0.isCompleted && $0.resolvedTargetKind == .time }
                .compactMap(\.resolvedCompletedDurationSeconds)
                .reduce(0, +) ?? 0
            let exerciseElapsed = earlierTimedSeconds + elapsed
            let hasStarted = countdown != nil

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Image(systemName: finished ? "stopwatch.fill" : "timer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                        .frame(width: 40, height: 40)
                        .background(
                            ATHLTHTheme.premiumGoldSoft,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: finished ? "TOTAL ELAPSED TIME" : "SET COUNTDOWN",
                                norwegian: finished ? "TOTAL MEDGÅTT TID" : "NEDTELLING FOR SETT"
                            )
                        )
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Text(
                            finished
                                ? ATHLTHLocalization.choose(
                                    english: isRunning ? "Target reached · time continues" : "Target reached · paused",
                                    norwegian: isRunning ? "Målet nådd · tiden fortsetter" : "Målet nådd · på pause"
                                )
                                : isRunning
                                    ? ATHLTHLocalization.choose(
                                        english: "Counting down",
                                        norwegian: "Nedtelling pågår"
                                    )
                                    : hasStarted
                                        ? ATHLTHLocalization.choose(
                                            english: "Paused",
                                            norwegian: "På pause"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Ready when you are",
                                            norwegian: "Klar når du er det"
                                        )
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    }

                    Spacer(minLength: 0)

                    Text(TimeInterval(finished ? exerciseElapsed : remaining).clockDuration)
                        .font(.system(size: 37, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .contentTransition(.numericText(countsDown: true))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }

                if finished {
                    Text(ATHLTHLocalization.choose(
                        english: "+\(TimeInterval(overtime).clockDuration) beyond this set's planned time",
                        norwegian: "+\(TimeInterval(overtime).clockDuration) over planlagt tid for settet"
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                ProgressView(
                    value: Double(min(max(target - remaining, 0), target)),
                    total: Double(max(target, 1))
                )
                .tint(ATHLTHPlanDesign.accent)

                HStack(spacing: 10) {
                    if !finished || hasStarted {
                        Button {
                            if isRunning {
                                strength.pauseTimedSet()
                            } else {
                                strength.startOrResumeTimedSet()
                            }
                        } label: {
                            Label(
                                isRunning
                                    ? ATHLTHLocalization.choose(
                                        english: "Pause",
                                        norwegian: "Pause"
                                    )
                                    : hasStarted
                                        ? ATHLTHLocalization.choose(
                                            english: "Resume",
                                            norwegian: "Fortsett"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Start countdown",
                                            norwegian: "Start nedtelling"
                                        ),
                                systemImage: isRunning ? "pause.fill" : "play.fill"
                            )
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHPlanDesign.accentInk)
                    } else {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Complete the set when ready",
                                norwegian: "Fullfør settet når du er klar"
                            ),
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if hasStarted {
                        Button {
                            strength.resetTimedSet()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHPlanDesign.accentInk)
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english: "Reset countdown",
                                norwegian: "Nullstill nedtelling"
                            )
                        )
                    }
                }

                if !hasStarted {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Start the clock when you begin. You still finish the set manually.",
                            norwegian: "Start klokken når du begynner. Du fullfører fortsatt settet manuelt."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHPlanDesign.warmSurface,
                        ATHLTHTheme.card.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(ATHLTHTheme.premiumGold.opacity(0.28), lineWidth: 0.8)
            }
            .sensoryFeedback(.success, trigger: finished)
        }
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
        ATHLTHUnifiedCard {
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
                            if strength
                                .addExtraSetToCurrentExercise() {
                                showingWorkoutReview =
                                    false
                            }
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "One more set",
                                    norwegian:
                                        "Ta ett ekstra sett"
                                ),
                                systemImage:
                                    "plus.circle.fill"
                            )
                            .font(
                                .subheadline
                                    .weight(.semibold)
                            )
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 44
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(
                            ATHLTHTheme
                                .accentDeep
                        )

                        Button {
                            showingExerciseQueue = true
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Choose another exercise",
                                    norwegian: "Velg en annen øvelse"
                                ),
                                systemImage: "arrow.left.arrow.right"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)

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
                        VStack(spacing: 12) {
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

                            Button {
                                if strength
                                    .addExtraSetToCurrentExercise() {
                                    showingWorkoutReview =
                                        false
                                }
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "One more set",
                                        norwegian:
                                            "Ta ett ekstra sett"
                                    ),
                                    systemImage:
                                        "plus.circle.fill"
                                )
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    minHeight: 44
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(
                                ATHLTHTheme
                                    .accentDeep
                            )

                            Button {
                                showingExerciseLibrary =
                                    true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Add another exercise",
                                        norwegian:
                                            "Legg til en øvelse"
                                    ),
                                    systemImage:
                                        "plus.rectangle.on.rectangle"
                                )
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    minHeight: 44
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(
                                ATHLTHTheme
                                    .vitality
                            )

                            Button {
                                showingAIExercisePlanner =
                                    true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "AI add exercises",
                                        norwegian:
                                            "AI legg til øvelser"
                                    ),
                                    systemImage:
                                        "sparkles"
                                )
                                .font(
                                    .subheadline
                                        .weight(.semibold)
                                )
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    minHeight: 44
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(
                                ATHLTHTheme
                                    .premiumGold
                            )

                            Button {
                                showingWorkoutReview =
                                    true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Review workout",
                                        norwegian:
                                            "Se sammendrag"
                                    ),
                                    systemImage:
                                        "chart.bar.doc.horizontal"
                                )
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    minHeight: 52
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
                                            cornerRadius: 18,
                                            style:
                                                .continuous
                                        )
                                )
                            }
                            .buttonStyle(.plain)
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

    private var activeExistingPlannedExercises:
        [PlannedExercise] {
        guard let workout =
                strength.activeWorkout
        else {
            return []
        }

        let entriesByName =
            Dictionary(
                grouping:
                    exerciseLibrary
                        .allExercises
            ) {
                $0.canonicalName
                    .folding(
                        options: [
                            .caseInsensitive,
                            .diacriticInsensitive
                        ],
                        locale: .current
                    )
                    .lowercased()
            }

        return workout.exercises
            .map {
                exerciseLog in

                let key =
                    exerciseLog
                        .exercise
                        .name
                        .folding(
                            options: [
                                .caseInsensitive,
                                .diacriticInsensitive
                            ],
                            locale: .current
                        )
                        .lowercased()

                let matchedEntry =
                    entriesByName[key]?
                        .first

                let firstSet =
                    exerciseLog
                        .sets
                        .first

                return PlannedExercise(
                    id: UUID(),
                    exerciseID:
                        matchedEntry?.id,
                    embeddedExercise:
                        exerciseLog
                            .exercise,
                    sets:
                        max(
                            exerciseLog
                                .sets
                                .count,
                            1
                        ),
                    reps:
                        firstSet?
                            .plannedReps,
                    targetWeightKilograms:
                        firstSet?
                            .plannedWeightKilograms,
                    targetRPE:
                        firstSet?
                            .plannedRPE,
                    restSeconds:
                        firstSet?
                            .restSeconds,
                    notes: nil,
                    targetRIR:
                        firstSet?
                            .plannedRIR,
                    supersetGroupID:
                        nil,
                    progression:
                        StrengthProgressionRule
                            .none
                )
            }
    }

    private func appendAIExercises(
        _ additions:
            [PlannedExercise]
    ) {
        var didAppend = false

        for planned in additions {
            guard
                let exerciseID =
                    planned.exerciseID,
                let entry =
                    exerciseLibrary
                        .allExercises
                        .first(
                            where: {
                                $0.id ==
                                    exerciseID
                            }
                        )
            else {
                continue
            }

            strength.appendExercise(
                entry.exercise,
                sets:
                    max(
                        planned.sets,
                        1
                    ),
                reps:
                    planned.reps ??
                    8,
                targetKind:
                    planned
                        .resolvedTargetKind,
                targetDurationSeconds:
                    planned
                        .resolvedTargetDurationSeconds,
                loadKind:
                    planned
                        .resolvedLoadKind,
                targetWeightKilograms:
                    planned
                        .targetWeightKilograms,
                targetResistanceLevel:
                    planned
                        .resolvedTargetResistanceLevel,
                restSeconds:
                    planned
                        .restSeconds ??
                    90,
                warmUpSets: 0
            )

            didAppend = true
        }

        if didAppend {
            showingWorkoutReview = false
            loadDefaultsFromCurrentSet()
        }
    }

    @ViewBuilder
    private func workoutHeader(_ workout: StrengthWorkoutLog) -> some View {
        ATHLTHUnifiedCard {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workout.title)
                        .font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(context.date.timeIntervalSince(workout.startedAt).clockDuration)
                            .font(.system(size: 39, weight: .bold, design: .rounded).monospacedDigit())
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
        ATHLTHUnifiedCard {
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

                VStack(spacing: 8) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Add",
                            norwegian: "Legg til"
                        )
                    ) {
                        showingExerciseLibrary = true
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .tint(
                        ATHLTHTheme.accent
                    )

                    Button {
                        showingAIExercisePlanner =
                            true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "AI pick",
                                norwegian: "AI velg"
                            ),
                            systemImage:
                                "sparkles"
                        )
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(
                        ATHLTHTheme
                            .premiumGold
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func simpleTrackingContent(workout: StrengthWorkoutLog) -> some View {
        ATHLTHUnifiedCard {
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
                        HStack(spacing: 8) {
                            Label(exercise.exercise.displayName, systemImage: "dumbbell")
                                .font(.subheadline)
                            if exercise.isWarmUpExercise {
                                Image(systemName: "flame.fill")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.premiumGold)
                                    .accessibilityLabel(
                                        ATHLTHLocalization.choose(
                                            english: "Warm-up",
                                            norwegian: "Oppvarming"
                                        )
                                    )
                            }
                        }
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
        ATHLTHUnifiedCard {
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
                        .font(.system(size: 27, weight: .semibold, design: .rounded))

                    if exercise.isWarmUpExercise {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "WARM-UP",
                                norwegian: "OPPVARMING"
                            ),
                            systemImage: "flame.fill"
                        )
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(ATHLTHTheme.premiumGoldSoft, in: Capsule())
                    }

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
                        _ = strength.setWarmUpExercise(
                            exercise.id,
                            isWarmUp: !exercise.isWarmUpExercise
                        )
                    } label: {
                        Label(
                            exercise.isWarmUpExercise
                                ? ATHLTHLocalization.choose(
                                    english: "Mark as working sets",
                                    norwegian: "Marker som arbeidssett"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Mark as warm-up",
                                    norwegian: "Marker som oppvarming"
                                ),
                            systemImage: exercise.isWarmUpExercise ? "dumbbell.fill" : "flame.fill"
                        )
                    }
                    .disabled(exercise.sets.contains(where: { $0.isCompleted }))

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

        ATHLTHUnifiedCard {
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
        ATHLTHUnifiedCard {
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
        ATHLTHUnifiedCard {
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
        ATHLTHUnifiedCard {
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

            if currentStrengthTargetKind == .time {
                timedSetCountdownCard
                    .padding(.top, 12)
            }

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
        ATHLTHUnifiedCard {
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
        ATHLTHUnifiedCard {
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
        initialWarmUp: Bool = false,
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

        let snapshot = entry.exercise.snapshot
        let isTreadmill =
            StrengthTreadmillWarmUpDefaults.isTreadmill(snapshot.name) ||
            StrengthTreadmillWarmUpDefaults.isTreadmill(snapshot.displayName)
        let bodyweightHold = StrengthTimedBodyweightDefaults.isBodyweightHold(snapshot.name) ||
            StrengthTimedBodyweightDefaults.isBodyweightHold(snapshot.displayName)
        let initialTarget: StrengthExerciseTargetKind =
            isTreadmill || bodyweightHold ? .time : snapshot.defaultStrengthTargetKind
        let initialLoad = snapshot.defaultStrengthLoadKind

        // Each newly added treadmill warm-up has an editable prescription.
        // Start at 1 × 10 minutes, not three five-minute sets.
        _sets = State(
            initialValue: isTreadmill
                ? StrengthTreadmillWarmUpDefaults.sets : 3
        )
        _warmUpSets = State(initialValue:
            initialWarmUp ? (isTreadmill ? 1 : 3) :
                (isTreadmill ? 1 : 0)
        )
        _targetKind = State(initialValue: initialTarget)
        _durationSeconds = State(
            initialValue: isTreadmill
                ? StrengthTreadmillWarmUpDefaults.durationSeconds
                : bodyweightHold
                    ? StrengthTimedBodyweightDefaults.durationSeconds
                    : snapshot.defaultStrengthTargetDurationSeconds
        )
        _loadKind = State(initialValue: initialLoad)
        _useLoadTarget = State(
            initialValue: (isTreadmill || bodyweightHold)
                ? false : initialLoad == .resistanceLevel
        )
        _restSeconds = State(initialValue: isTreadmill ? 0 : 90)
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

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                            .frame(width: 44, height: 44)
                            .background(
                                ATHLTHTheme.premiumGoldSoft,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Warm-up exercise",
                                    norwegian: "Oppvarmingsøvelse"
                                )
                            )
                            .font(.subheadline.weight(.bold))
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "All sets become warm-up and won't count toward volume or PRs.",
                                    norwegian: "Alle sett blir oppvarming og teller ikke mot volum eller PR."
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)
                        Toggle(
                            ATHLTHLocalization.choose(
                                english: "Warm-up exercise",
                                norwegian: "Oppvarmingsøvelse"
                            ),
                            isOn: Binding(
                                get: { warmUpSets == sets },
                                set: { warmUpSets = $0 ? sets : 0 }
                            )
                        )
                        .labelsHidden()
                        .tint(ATHLTHTheme.premiumGold)
                    }
                    .padding(.vertical, 5)
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
                    .onChange(of: sets) { oldValue, newValue in
                        warmUpSets = warmUpSets == oldValue
                            ? newValue
                            : min(warmUpSets, newValue)
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
    @State private var barWeight: Double = 20
    var onBarWeightChange: ((Double) -> Void)? = nil

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
        targetWeightKilograms: Double,
        initialBarWeightKilograms: Double = 20,
        onBarWeightChange: ((Double) -> Void)? = nil
    ) {
        self.onBarWeightChange = onBarWeightChange
        _barWeight = State(initialValue: initialBarWeightKilograms)
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
                        ForEach([0.0, 5.0, 10.0, 15.0, 20.0, 25.0],
                                id: \.self) { kg in
                            Text(String(format: "%.0f kg", kg))
                                .tag(kg)
                        }
                    }
                    .onChange(of: barWeight) { _, selected in
                        onBarWeightChange?(selected)
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



/// Small exercise artwork reuses the exercise database instead of shipping
/// an extra image. A fallback makes offline sessions equally navigable.
private struct StrengthQueueArtwork: View {
    let exercise: StrengthExerciseLog

    var body: some View {
        ZStack {
            ATHLTHPlanDesign.warmSurface

            if let url = exercise.exercise.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "dumbbell.fill")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                    }
                }
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.premiumGold)
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Explicit detection prevents a bar-weight control on dumbbells,
/// resistance machines and bodyweight exercises. Smith machine bars can
/// vary, so their mass is always selected by the athlete.
enum StrengthBarbellExercisePolicy {
    static func usesBar(_ exercise: StrengthExerciseLog) -> Bool {
        usesBarEquipment(
            name: exercise.exercise.name,
            equipment: exercise.exercise.equipment
        )
    }

    static func usesBarEquipment(name: String, equipment: [String]) -> Bool {
        let terms = ([name] + equipment).joined(separator: " ").lowercased()
        if ["dumbbell", "manual", "kettlebell", "hantel", "cable",
            "kabel", "bodyweight"].contains(where: terms.contains) {
            return false
        }
        return ["barbell", "smith", "vektstang", "stang",
                "benkpress", "deadlift", "markløft",
                "skivestang"].contains(where: terms.contains)
    }
}

private struct StrengthActiveExerciseQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var appSession: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    @State private var showingExerciseLibrary = false
    @State private var showingAppendWorkout = false
    @State private var showingCustomExerciseEditor = false
    @State private var addingWarmUp = false
    @State private var pendingExercise: ExerciseLibraryEntry?
    @State private var justCreatedExercise: ExerciseLibraryEntry?
    @State private var pendingRemovalID: UUID?
    @State private var showingRemovalBlocked = false

    private func requestRemoval(_ id: UUID) {
        guard strength.canRemoveActiveExercise(id) else {
            showingRemovalBlocked = true
            return
        }
        pendingRemovalID = id
    }

    var body: some View {
        NavigationStack {
            Group {
                if let workout = strength.activeWorkout {
                    List {
                        Section {
                            ForEach(workout.exercises) { exercise in
                                VStack(alignment: .leading, spacing: 9) {
                                HStack(spacing: 10) {
                                    StrengthQueueArtwork(exercise: exercise)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.exercise.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)

                                        if exercise.isWarmUpExercise {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "WARM-UP",
                                                    norwegian: "OPPVARMING"
                                                ),
                                                systemImage: "flame.fill"
                                            )
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(ATHLTHTheme.premiumGold)
                                        }

                                        let done = exercise.sets.filter(\.isCompleted).count
                                        Text(
                                            ATHLTHLocalization.choose(
                                                english: "\(done)/\(exercise.sets.count) sets",
                                                norwegian: "\(done)/\(exercise.sets.count) sett"
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        if let first = exercise.sets.first {
                                            HStack(spacing: 6) {
                                                if let seconds = first.plannedDurationSeconds,
                                                   seconds > 0 {
                                                    Label(
                                                        TimeInterval(seconds).clockDuration,
                                                        systemImage: "timer"
                                                    )
                                                } else if let reps = first.plannedReps {
                                                    Text("\(reps) reps")
                                                }

                                                if let weight = first.plannedWeightKilograms,
                                                   weight > 0 {
                                                    Text(String(format: "· %.1f kg", weight))
                                                } else if let speed =
                                                    first.completedTreadmillSpeedKilometersPerHour,
                                                    speed > 0 {
                                                    Text(String(format: "· %.1f km/t", speed))
                                                } else if let tempo = first.plannedTempo,
                                                          !tempo.isEmpty {
                                                    Text("· \(tempo)")
                                                }
                                                if let speed = exercise.targetSpeedKilometersPerHour,
                                                   speed > 0 {
                                                    Text(String(format: "· %.1f km/t", speed))
                                                }
                                                if let zone = exercise.targetHeartRateZone {
                                                    Text("· Sone \(zone)")
                                                }
                                            }
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.78)
                                        }
                                    }

                                    Spacer(minLength: 6)

                                    if exercise.id ==
                                        strength.currentExercise?.id {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Now",
                                                norwegian: "Nå"
                                            ),
                                            systemImage: "play.fill"
                                        )
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(ATHLTHTheme.premiumGold)
                                    } else if exercise.isCompleted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(ATHLTHTheme.premiumGold)
                                    } else {
                                        Button(
                                            ATHLTHLocalization.choose(
                                                english: "Train now",
                                                norwegian: "Tren nå"
                                            )
                                        ) {
                                            if strength.selectExerciseForNow(exercise.id) {
                                                dismiss()
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                        .frame(width: 27, height: 42)
                                        .accessibilityLabel(ATHLTHLocalization.choose(
                                            english: "Hold and drag to reorder",
                                            norwegian: "Hold og dra for å flytte øvelsen"
                                        ))
                                }
                                if StrengthBarbellExercisePolicy.usesBar(exercise) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "scalemass")
                                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        Text(ATHLTHLocalization.choose(
                                            english: "Bar weight",
                                            norwegian: "Stangvekt"
                                        ))
                                        .font(.caption.weight(.medium))
                                        Spacer()
                                        Menu {
                                            Button(ATHLTHLocalization.choose(
                                                english: "Not set", norwegian: "Ikke valgt"
                                            )) {
                                                _ = strength.setActiveExerciseBarWeight(
                                                    exercise.id, kilograms: nil
                                                )
                                            }
                                            ForEach([0.0, 5.0, 10.0, 15.0, 20.0, 25.0],
                                                    id: \.self) { kg in
                                                Button(String(format: "%.0f kg", kg)) {
                                                    _ = strength.setActiveExerciseBarWeight(
                                                        exercise.id, kilograms: kg
                                                    )
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(String(
                                                    format: "%.0f kg",
                                                    exercise.barWeightKilograms ?? 20
                                                ))
                                                Image(systemName: "chevron.up.chevron.down")
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        }
                                    }
                                    if exercise.barWeightKilograms != nil {
                                        Text(ATHLTHLocalization.choose(
                                            english: "Bar included in total kg, never added twice.",
                                            norwegian: "Stangen inngår i totalvekten og legges ikke til to ganger."
                                        ))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }

                                DisclosureGroup(
                                    ATHLTHLocalization.choose(
                                        english: "View planned sets",
                                        norwegian: "Vis planlagte sett"
                                    )
                                ) {
                                    VStack(spacing: 0) {
                                        ForEach(exercise.sets) { set in
                                            Button {
                                                if strength.selectSetForNow(
                                                    exerciseID: exercise.id, setID: set.id
                                                ) {
                                                    dismiss()
                                                }
                                            } label: {
                                            HStack(spacing: 9) {
                                                Image(systemName: set.isCompleted
                                                    ? "checkmark.circle.fill"
                                                    : "circle")
                                                    .foregroundStyle(set.isCompleted
                                                        ? ATHLTHPlanDesign.accentInk
                                                        : ATHLTHPlanDesign.secondaryInk)
                                                Text("Sett \(set.setNumber)")
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Text(
                                                    set.resolvedTargetKind == .time
                                                        ? TimeInterval(set.plannedDurationSeconds ?? 0).clockDuration
                                                        : "\(set.plannedReps ?? 0) reps"
                                                )
                                                .monospacedDigit()
                                                if let weight = set.plannedWeightKilograms {
                                                    Text(String(format: "· %.1f kg", weight))
                                                }
                                                if !set.isCompleted {
                                                    Image(systemName: "arrow.right.circle.fill")
                                                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                                }
                                            }
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHPlanDesign.ink)
                                            .padding(.vertical, 10)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(set.isCompleted)
                                            if set.id != exercise.sets.last?.id {
                                                Divider()
                                            }
                                        }
                                        if let skipped = exercise.skippedPlannedSetCount,
                                           skipped > 0 {
                                            Text(ATHLTHLocalization.choose(
                                                english: "\(skipped) planned sets skipped",
                                                norwegian: "\(skipped) planlagte sett hoppet over"
                                            ))
                                            .font(.caption2)
                                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                                .font(.caption.weight(.semibold))
                                .tint(ATHLTHPlanDesign.accentInk)
                                }
                                .padding(.vertical, 9)
                                .listRowBackground(ATHLTHTheme.card)
                                // Drag the exercise itself; no Edit button
                                // or mutation to the saved training plan.
                                .draggable(exercise.id.uuidString)
                                .dropDestination(for: String.self) { ids, _ in
                                    guard let id = ids.first.flatMap(UUID.init(uuidString:))
                                    else { return false }
                                    return strength.moveActiveExercise(
                                        id, before: exercise.id
                                    )
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        requestRemoval(exercise.id)
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Delete",
                                                norwegian: "Slett"
                                            ),
                                            systemImage: "trash"
                                        )
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        _ = strength.setWarmUpExercise(
                                            exercise.id,
                                            isWarmUp: !exercise.isWarmUpExercise
                                        )
                                    } label: {
                                        Label(
                                            exercise.isWarmUpExercise
                                                ? ATHLTHLocalization.choose(
                                                    english: "Make main exercise",
                                                    norwegian: "Flytt til hoveddel"
                                                )
                                                : ATHLTHLocalization.choose(
                                                    english: "Mark as warm-up",
                                                    norwegian: "Marker som oppvarming"
                                                ),
                                            systemImage: "flame"
                                        )
                                    }
                                    .disabled(exercise.sets.contains(where: \.isCompleted))
                                    Button(role: .destructive) {
                                        requestRemoval(exercise.id)
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Delete exercise",
                                                norwegian: "Slett øvelse"
                                            ),
                                            systemImage: "trash"
                                        )
                                    }
                                }
                            }
                            .onMove { from, to in
                                strength.reorderActiveExercises(
                                    fromOffsets: from,
                                    toOffset: to
                                )
                            }
                        } footer: {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Press and drag an exercise to change order, or swipe left to delete an unrecorded exercise. Completed sets are protected.",
                                    norwegian: "Hold og dra en øvelse for å endre rekkefølgen, eller sveip mot venstre for å slette en øvelse uten registrerte sett. Fullførte sett beholdes."
                                )
                            )
                        }
                    }
                } else {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No active workout",
                            norwegian: "Ingen aktiv økt"
                        ),
                        systemImage: "dumbbell"
                    )
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Exercise order",
                    norwegian: "Øvelsesrekkefølge"
                )
            )
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            addingWarmUp = false
                            showingExerciseLibrary = true
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Add exercise", norwegian: "Legg til øvelse"
                            ), systemImage: "dumbbell.fill")
                        }
                        Button {
                            addingWarmUp = true
                            showingExerciseLibrary = true
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Add warm-up", norwegian: "Legg til oppvarming"
                            ), systemImage: "flame")
                        }
                        Button {
                            showingAppendWorkout = true
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Add saved workout",
                                norwegian: "Legg til lagret treningsøkt"
                            ), systemImage: "rectangle.stack.badge.plus")
                        }
                        Button {
                            addingWarmUp = false
                            showingCustomExerciseEditor = true
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Create my exercise", norwegian: "Opprett egen øvelse"
                            ), systemImage: "plus.square.on.square")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Add an exercise, warm-up or custom exercise",
                        norwegian: "Legg til øvelse, oppvarming eller egen øvelse"
                    ))
                }
            }
        }
        // A single exercise should not open a half-screen sheet with
        // hundreds of points of unused empty space.
        .presentationDetents([
            .height(
                min(
                    CGFloat((strength.activeWorkout?.exercises.count ?? 1) * 150 + 205),
                    660
                )
            ),
            .large
        ])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(ATHLTHPlanDesign.canvas)
        .sheet(isPresented: $showingAppendWorkout) {
            ActiveHybridWorkoutPicker { planned, startNow in
                strength.appendWorkoutDuringSession(
                    planned, startNow: startNow
                )
            }
            .environmentObject(appSession)
        }
        .sheet(isPresented: $showingExerciseLibrary) {
            NavigationStack {
                ExerciseLibraryView(
                    selectionTitle: ATHLTHLocalization.choose(
                        english: addingWarmUp ? "Add warm-up" : "Add exercise",
                        norwegian: addingWarmUp ? "Legg til oppvarming" : "Legg til øvelse"
                    )
                ) { entry in
                    showingExerciseLibrary = false
                    pendingExercise = entry
                }
            }
        }
        .sheet(isPresented: $showingCustomExerciseEditor) {
            CustomExerciseEditorView(onSaved: { entry in
                justCreatedExercise = entry
            })
            .environmentObject(exerciseLibrary)
            .environmentObject(appSession)
        }
        .onChange(of: showingCustomExerciseEditor) { _, visible in
            if !visible, let created = justCreatedExercise {
                justCreatedExercise = nil
                pendingExercise = created
            }
        }
        .sheet(item: $pendingExercise) { entry in
            FreestyleExercisePrescriptionView(
                entry: entry,
                initialWarmUp: addingWarmUp
            ) { sets, reps, targetKind, duration, loadKind, weight,
                resistance, rest, warmUpSets in
                strength.appendExercise(
                    entry.exercise,
                    sets: sets,
                    reps: reps,
                    targetKind: targetKind,
                    targetDurationSeconds: duration,
                    loadKind: loadKind,
                    targetWeightKilograms: weight,
                    targetResistanceLevel: resistance,
                    restSeconds: rest,
                    warmUpSets: warmUpSets
                )
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Remove exercise from this workout?",
                norwegian: "Slette øvelsen fra denne økten?"
            ),
            isPresented: Binding(
                get: { pendingRemovalID != nil },
                set: { if !$0 { pendingRemovalID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Delete exercise", norwegian: "Slett øvelse"
            ), role: .destructive) {
                if let id = pendingRemovalID {
                    _ = strength.removeActiveExercise(id)
                }
                pendingRemovalID = nil
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Only this active workout is changed. Your saved training plan is untouched.",
                norwegian: "Bare den aktive økten endres. Treningsplanen din beholdes."
            ))
        }
        .alert(ATHLTHLocalization.choose(
            english: "Recorded sets are protected",
            norwegian: "Registrerte sett er beskyttet"
        ), isPresented: $showingRemovalBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "An exercise with completed sets or a running timed set cannot be deleted. Finish the active timer before removing an unrecorded exercise.",
                norwegian: "Øvelser med fullførte sett eller et pågående tidssett kan ikke slettes. Avslutt tidtakingen før du fjerner en øvelse uten registrerte sett."
            ))
        }
    }
}

private struct StrengthClearableNumericField: View {
    let value: Binding<Double>
    let allowsDecimal: Bool

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .monospacedDigit()
            .multilineTextAlignment(.leading)
            .focused($isFocused)
            .onAppear {
                text = formatted(value.wrappedValue)
            }
            .onChange(of: text) { _, newText in
                // Keep the field empty while the athlete replaces the value.
                // A formatter-backed numeric TextField restores the old
                // digit on every keystroke and prevents clearing "235".
                let entry = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                if entry.isEmpty {
                    value.wrappedValue = 0
                    return
                }

                let normalized = entry.replacingOccurrences(of: ",", with: ".")
                guard let parsed = Double(normalized),
                      parsed.isFinite,
                      parsed >= 0 else {
                    return
                }
                value.wrappedValue = allowsDecimal
                    ? min(parsed, 999.5)
                    : min(parsed.rounded(.towardZero), 999)
            }
            .onChange(of: value.wrappedValue) { oldValue, newValue in
                // Sync +/- buttons and changes to the current set, but do
                // not overwrite partial edits such as an empty field or "5,".
                if !isFocused || parsedValue(text) == oldValue {
                    text = formatted(newValue)
                }
            }
            .onChange(of: isFocused) { _, editing in
                if !editing {
                    text = formatted(value.wrappedValue)
                }
            }
    }

    private func parsedValue(_ input: String) -> Double? {
        Double(input.replacingOccurrences(of: ",", with: "."))
    }

    private func formatted(_ number: Double) -> String {
        if !allowsDecimal || number.rounded() == number {
            return String(Int(number))
        }
        return String(format: "%.1f", number)
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
