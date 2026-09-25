import SwiftUI

struct AudioCoachDraft {
    var enabled = false
    var distanceTriggerEnabled = true
    var timeTriggerEnabled = false
    var distanceIntervalKilometers = 1.0
    var timeIntervalMinutes = 10

    var announceDistance = true
    var announceElapsedTime = true
    var announceAveragePace = true
    var announceClockTime = false
    var announceHeartRate = false

    var announceRemainingRouteDistance = true
    var announceEstimatedRemainingRouteTime = true

    var announceCurrentWorkoutStep = true
    var announceRemainingStepTime = true
    var announceRemainingStepDistance = true

    var language: WatchAudioCoachLanguage = .system

    mutating func load(from settings: AppSettingsStore) {
        enabled = settings.audioCoachEnabledByDefault
        distanceTriggerEnabled =
            settings.audioCoachDistanceTriggerEnabled
        timeTriggerEnabled =
            settings.audioCoachTimeTriggerEnabled
        distanceIntervalKilometers =
            settings.audioCoachDistanceIntervalKilometers
        timeIntervalMinutes =
            settings.audioCoachTimeIntervalMinutes
        announceDistance =
            settings.audioCoachAnnounceDistance
        announceElapsedTime =
            settings.audioCoachAnnounceElapsedTime
        announceAveragePace =
            settings.audioCoachAnnounceAveragePace
        announceClockTime =
            settings.audioCoachAnnounceClockTime
        announceHeartRate =
            settings.audioCoachAnnounceHeartRate
        announceRemainingRouteDistance =
            settings.audioCoachAnnounceRemainingRouteDistance
        announceEstimatedRemainingRouteTime =
            settings.audioCoachAnnounceEstimatedRemainingRouteTime
        announceCurrentWorkoutStep =
            settings.audioCoachAnnounceCurrentWorkoutStep
        announceRemainingStepTime =
            settings.audioCoachAnnounceRemainingStepTime
        announceRemainingStepDistance =
            settings.audioCoachAnnounceRemainingStepDistance
        language = settings.audioCoachLanguage
    }

    func configuration(
        routeDistanceMeters: Double? = nil
    ) -> WatchAudioCoachConfiguration {
        WatchAudioCoachConfiguration(
            enabled: enabled,
            language: language,
            distanceIntervalMeters:
                enabled && distanceTriggerEnabled
                    ? distanceIntervalKilometers * 1_000
                    : nil,
            timeIntervalSeconds:
                enabled && timeTriggerEnabled
                    ? Double(timeIntervalMinutes * 60)
                    : nil,
            announceDistance: enabled && announceDistance,
            announceElapsedTime:
                enabled && announceElapsedTime,
            announceAveragePace:
                enabled && announceAveragePace,
            announceClockTime:
                enabled && announceClockTime,
            announceHeartRate:
                enabled && announceHeartRate,
            announceRemainingRouteDistance:
                enabled && announceRemainingRouteDistance,
            announceEstimatedRemainingRouteTime:
                enabled &&
                announceEstimatedRemainingRouteTime,
            routeDistanceMeters: routeDistanceMeters,
            announceCurrentWorkoutStep:
                enabled && announceCurrentWorkoutStep,
            announceRemainingStepTime:
                enabled && announceRemainingStepTime,
            announceRemainingStepDistance:
                enabled && announceRemainingStepDistance
        )
    }
}

enum RunQuickStartMode: String, CaseIterable, Identifiable {
    case free
    case route
    case structured

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Free Run"
        case .route: return "Route"
        case .structured: return "Workout"
        }
    }

    var subtitle: String {
        switch self {
        case .free:
            return "Just start running. No route or target required."
        case .route:
            return "Follow one of your saved ATHLTH routes."
        case .structured:
            return "Choose a workout from the running library."
        }
    }

    var icon: String {
        switch self {
        case .free: return "figure.run"
        case .route:
            return "point.topleft.down.to.point.bottomright.curvepath"
        case .structured: return "list.bullet.rectangle"
        }
    }
}

struct RunQuickStartConfiguration {
    let mode: RunQuickStartMode
    let route: TrainingRoute?
    let workout: RunningWorkoutTemplate?
    let audioCoach: WatchAudioCoachConfiguration
    let friends: [SocialProfileCard]

    var title: String {
        switch mode {
        case .free:
            return "Free Run"
        case .route:
            return route?.title ?? "Route Run"
        case .structured:
            return workout?.title ?? "Running Workout"
        }
    }
}

struct WalkQuickStartConfiguration {
    let audioCoach: WatchAudioCoachConfiguration
    let friends: [SocialProfileCard]
}

struct RunQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var settings: AppSettingsStore

    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (RunQuickStartConfiguration) -> Void

    @State private var mode: RunQuickStartMode = .free
    @State private var selectedRoute: TrainingRoute?
    @State private var selectedWorkout: RunningWorkoutTemplate?
    @State private var selectedFriendIDs: Set<UUID> = []

    @State private var showingRoutes = false
    @State private var showingRunningLibrary = false

    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var didLoadAudioCoachDefaults = false

    private var canStart: Bool {
        guard trainingDeviceProvider == .appleWatch,
              watchConnected
        else {
            return false
        }

        switch mode {
        case .free:
            return true
        case .route:
            return selectedRoute != nil
        case .structured:
            return selectedWorkout != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    introCard
                    modeCard
                    selectionCard
                    ATHLTHPlusFeatureGate(
                        feature: .audioCoach,
                        title: "Audio Coach · ATHLTH+",
                        message:
                            "Choose spoken pace, time, route progress and workout-step updates."
                    ) {
                        AudioCoachSetupCard(
                            draft: $audioCoachDraft,
                            showRouteOptions:
                                mode == .route ||
                                selectedWorkout?.routeID != nil,
                            showStructuredOptions:
                                mode == .structured
                        )
                    }

                    ATHLTHCard {
                        WorkoutFriendPicker(
                            selectedFriendIDs: $selectedFriendIDs
                        )
                    }

                    startButton
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.canvasTop,
                        ATHLTHTheme.canvasBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Start Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRoutes) {
                NavigationStack {
                    SavedRoutesView(
                        selectionTitle: "Choose Route"
                    ) { route in
                        selectedRoute = route
                        showingRoutes = false
                    }
                }
            }
            .sheet(isPresented: $showingRunningLibrary) {
                NavigationStack {
                    RunningWorkoutLibraryView(
                        selectionTitle: "Choose Workout"
                    ) { workout in
                        selectedWorkout = workout
                        showingRunningLibrary = false
                    }
                }
            }
            .task {
                if !didLoadAudioCoachDefaults {
                    audioCoachDraft.load(from: settings)
                    didLoadAudioCoachDefaults = true
                }

                if social.friends.isEmpty {
                    await social.refresh()
                }
            }
        }
    }

    private var introCard: some View {
        ATHLTHCard {
            HStack(spacing: 14) {
                Image(systemName: "figure.run")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 54, height: 54)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("How do you want to run?")
                        .font(.title3.weight(.bold))

                    Text(
                        watchConnected
                            ? "Apple Watch is ready. Choose a free run, route or structured workout."
                            : deviceStatusText
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var modeCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Run type",
                actionTitle: "Choose one"
            )

            VStack(spacing: 8) {
                ForEach(RunQuickStartMode.allCases) { option in
                    Button {
                        mode = option
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(
                                    mode == option
                                        ? Color.white
                                        : ATHLTHTheme.accent
                                )
                                .frame(width: 40, height: 40)
                                .background(
                                    mode == option
                                        ? ATHLTHTheme.accent
                                        : ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(
                                systemName:
                                    mode == option
                                        ? "checkmark.circle.fill"
                                        : "circle"
                            )
                            .foregroundStyle(
                                mode == option
                                    ? ATHLTHTheme.accent
                                    : Color.secondary
                            )
                        }
                        .padding(10)
                        .background(
                            mode == option
                                ? ATHLTHTheme.accentSoft.opacity(0.55)
                                : Color.primary.opacity(0.02),
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var selectionCard: some View {
        switch mode {
        case .free:
            ATHLTHCard {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(ATHLTHTheme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("No destination. No target.")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "ATHLTH records your run, GPS route, time, distance and available heart-rate data."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

        case .route:
            ATHLTHCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            selectedRoute?.title ??
                                "Choose a saved route"
                        )
                        .font(.headline)

                        if let selectedRoute {
                            Text(
                                String(
                                    format: "%.1f km · saved route",
                                    selectedRoute.distanceKilometers
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(
                                session.savedRoutes.isEmpty
                                    ? "You do not have any saved routes yet."
                                    : "\(session.savedRoutes.count) routes available"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        showingRoutes = true
                    } label: {
                        Text(
                            selectedRoute == nil
                                ? "Choose"
                                : "Change"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(ATHLTHTheme.accent)
                }

                if session.savedRoutes.isEmpty {
                    NavigationLink {
                        RunRouteBuilderView()
                    } label: {
                        Label(
                            "Create Route",
                            systemImage: "plus"
                        )
                    }
                    .padding(.top, 10)
                }
            }

        case .structured:
            ATHLTHCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            selectedWorkout?.title ??
                                "Choose a running workout"
                        )
                        .font(.headline)

                        Text(
                            selectedWorkout?.summary ??
                                "\(runningLibrary.allTemplates.count) structured workouts available"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    }

                    Spacer()

                    Button {
                        showingRunningLibrary = true
                    } label: {
                        Text(
                            selectedWorkout == nil
                                ? "Choose"
                                : "Change"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(ATHLTHTheme.accent)
                }

                if let workout = selectedWorkout {
                    Label(
                        "\(workout.blocks.count) blocks" +
                        workout.estimatedDistanceMeters.map {
                            String(
                                format: " · %.1f km",
                                $0 / 1_000
                            )
                        }.orEmpty,
                        systemImage: workout.type.systemImage
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 9)
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            let friends = social.friends.filter {
                selectedFriendIDs.contains($0.userID)
            }

            onStart(
                RunQuickStartConfiguration(
                    mode: mode,
                    route: selectedRoute,
                    workout: selectedWorkout,
                    audioCoach: audioCoachConfiguration,
                    friends: friends
                )
            )
            dismiss()
        } label: {
            Label(
                startButtonTitle,
                systemImage: "play.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(ATHLTHTheme.accent)
        .disabled(!canStart)
    }

    private var startButtonTitle: String {
        if !watchConnected {
            return "Apple Watch Required"
        }

        switch mode {
        case .free: return "Start Free Run"
        case .route: return "Start Route"
        case .structured: return "Start Workout"
        }
    }

    private var deviceStatusText: String {
        switch trainingDeviceProvider {
        case .appleWatch:
            return "Finish Apple Watch setup before starting a live run."
        case .garmin:
            return "Garmin live launch is not available yet."
        case .none:
            return "Choose Apple Watch as your training device for live run capture."
        }
    }

    private var audioCoachConfiguration:
        WatchAudioCoachConfiguration {
        guard session.canAccess(.audioCoach) else {
            return .disabled
        }

        let routeDistanceMeters: Double? = {
            if let route = selectedRoute {
                return route.distanceKilometers * 1_000
            }

            if let workout = selectedWorkout,
               let routeID = workout.routeID,
               let route = session.savedRoutes.first(
                    where: { $0.id == routeID }
               ) {
                return route.distanceKilometers * 1_000
            }

            return nil
        }()

        return audioCoachDraft.configuration(
            routeDistanceMeters: routeDistanceMeters
        )
    }

}

struct WalkQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore

    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (WalkQuickStartConfiguration) -> Void

    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var didLoadAudioCoachDefaults = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ATHLTHCard {
                        HStack(spacing: 14) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 54, height: 54)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 16
                                    )
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Free Walk")
                                    .font(.title3.weight(.bold))

                                Text(
                                    watchConnected
                                        ? "Start immediately and let ATHLTH record time, distance, GPS and available heart-rate data."
                                        : deviceStatusText
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }

                    ATHLTHPlusFeatureGate(
                        feature: .audioCoach,
                        title: "Audio Coach · ATHLTH+",
                        message:
                            "Unlock spoken distance, time, pace and heart-rate updates."
                    ) {
                        AudioCoachSetupCard(
                            draft: $audioCoachDraft,
                            showRouteOptions: false,
                            showStructuredOptions: false
                        )
                    }

                    ATHLTHCard {
                        WorkoutFriendPicker(
                            selectedFriendIDs: $selectedFriendIDs
                        )
                    }

                    Button {
                        let friends = social.friends.filter {
                            selectedFriendIDs.contains($0.userID)
                        }

                        onStart(
                            WalkQuickStartConfiguration(
                                audioCoach:
                                    session.canAccess(.audioCoach)
                                        ? audioCoachDraft.configuration()
                                        : .disabled,
                                friends: friends
                            )
                        )
                        dismiss()
                    } label: {
                        Label(
                            watchConnected
                                ? "Start Walk"
                                : "Apple Watch Required",
                            systemImage: "play.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                    .disabled(
                        trainingDeviceProvider != .appleWatch ||
                        !watchConnected
                    )
                }
                .padding()
            }
            .navigationTitle("Start Walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                if !didLoadAudioCoachDefaults {
                    audioCoachDraft.load(from: settings)
                    didLoadAudioCoachDefaults = true
                }

                if social.friends.isEmpty {
                    await social.refresh()
                }
            }
        }
    }

    private var deviceStatusText: String {
        switch trainingDeviceProvider {
        case .appleWatch:
            return "Finish Apple Watch setup before starting a live walk."
        case .garmin:
            return "Garmin live launch is not available yet."
        case .none:
            return "Choose Apple Watch as your training device for live walk capture."
        }
    }
}

struct StrengthQuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onChoose: (PlannedSession) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Start Strength")
                                .font(.title2.weight(.bold))
                            Text(
                                "Start completely open, or build the session right before you train."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        onChoose(emptySession)
                        dismiss()
                    } label: {
                        choiceCard(
                            title: "Start Empty",
                            subtitle:
                                "Start the workout now. Add exercises, sets, reps and weight while you train.",
                            icon: "play.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StrengthQuickBuilderView { workout in
                            onChoose(workout)
                            dismiss()
                        }
                    } label: {
                        choiceCard(
                            title: "Build Before Start",
                            subtitle:
                                "Choose exercises and targets now, then start the finished setup.",
                            icon: "list.bullet.clipboard.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("Quick Strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var emptySession: PlannedSession {
        PlannedSession(
            id: UUID(),
            title: "Freestyle Strength",
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes:
                "Open strength session · exercises can be added during training",
            runningWorkout: nil
        )
    }

    private func choiceCard(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 15)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct StrengthQuickBuilderView: View {
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore

    let onStart: (PlannedSession) -> Void

    @State private var title = "Strength Workout"
    @State private var exercises: [PlannedExercise] = []
    @State private var showingExerciseLibrary = false
    @State private var exerciseBeingEdited: PlannedExercise?

    var body: some View {
        Form {
            Section("Workout") {
                TextField("Workout name", text: $title)

                Text(
                    "Build only as much as you want. Every exercise can still be changed or added after the workout starts."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Exercises") {
                if exercises.isEmpty {
                    Text(
                        "No exercises yet. Add one below, or go back and choose Start Empty."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ForEach(Array(exercises.enumerated()), id: \.element.id) {
                    index,
                    exercise in

                    Button {
                        exerciseBeingEdited = exercise
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 28, height: 28)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.embeddedExercise.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(exerciseSummary(exercise))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    exercises.remove(atOffsets: offsets)
                }
                .onMove { offsets, destination in
                    exercises.move(
                        fromOffsets: offsets,
                        toOffset: destination
                    )
                }

                Button {
                    showingExerciseLibrary = true
                } label: {
                    Label(
                        "Add Exercise",
                        systemImage: "plus.circle.fill"
                    )
                }
            }

            Section {
                Button {
                    onStart(builtSession)
                } label: {
                    Label(
                        "Continue to Start",
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(
                    title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Build Workout")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExerciseLibrary) {
            NavigationStack {
                ExerciseLibraryView(
                    selectionTitle: "Add to Workout"
                ) { entry in
                    addExercise(entry.exercise)
                    showingExerciseLibrary = false
                }
            }
        }
        .sheet(item: $exerciseBeingEdited) { exercise in
            PlannedExerciseEditorView(
                exercise: exercise
            ) { updated in
                if let index = exercises.firstIndex(
                    where: { $0.id == updated.id }
                ) {
                    exercises[index] = updated
                }
                exerciseBeingEdited = nil
            }
        }
        .task {
            await exerciseLibrary.refresh()
        }
    }

    private var builtSession: PlannedSession {
        PlannedSession(
            id: UUID(),
            title:
                title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            kind: .strength,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: exercises,
            notes: "Built immediately before training",
            runningWorkout: nil
        )
    }

    private func addExercise(
        _ exercise: Exercise
    ) {
        exercises.append(
            PlannedExercise(
                id: UUID(),
                exerciseID: exercise.id,
                embeddedExercise: exercise.snapshot,
                sets: 3,
                reps: 8,
                targetWeightKilograms: nil,
                targetRPE: nil,
                restSeconds: 90,
                notes: nil,
                targetRIR: nil,
                supersetGroupID: nil,
                progression:
                    StrengthProgressionRule.none
            )
        )
    }

    private func exerciseSummary(
        _ exercise: PlannedExercise
    ) -> String {
        var parts = [
            "\(exercise.sets) × \(exercise.reps ?? 0)"
        ]

        if let weight = exercise.targetWeightKilograms {
            parts.append(
                String(format: "%.1f kg", weight)
            )
        }

        if let rpe = exercise.targetRPE {
            parts.append(
                String(format: "RPE %.1f", rpe)
            )
        }

        if let rest = exercise.restSeconds {
            parts.append("\(rest)s rest")
        }

        return parts.joined(separator: " · ")
    }
}

struct AudioCoachSetupCard: View {
    @Binding var enabled: Bool
    @Binding var announceDistance: Bool
    @Binding var announceTime: Bool
    @Binding var distanceIntervalKilometers: Double
    @Binding var timeIntervalMinutes: Int
    @Binding var announceClockTime: Bool

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Audio Coach")
                        .font(.headline)
                    Text(
                        "Spoken updates from Apple Watch while you move."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $enabled)
                    .labelsHidden()
            }

            if enabled {
                VStack(spacing: 12) {
                    Toggle(
                        "Distance updates",
                        isOn: $announceDistance
                    )

                    if announceDistance {
                        HStack {
                            Text("Every")
                            Spacer()
                            Picker(
                                "Distance interval",
                                selection:
                                    $distanceIntervalKilometers
                            ) {
                                Text("0.5 km").tag(0.5)
                                Text("1 km").tag(1.0)
                                Text("2 km").tag(2.0)
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Toggle(
                        "Time updates",
                        isOn: $announceTime
                    )

                    if announceTime {
                        HStack {
                            Text("Every")
                            Spacer()
                            Picker(
                                "Time interval",
                                selection:
                                    $timeIntervalMinutes
                            ) {
                                Text("5 min").tag(5)
                                Text("10 min").tag(10)
                                Text("15 min").tag(15)
                                Text("30 min").tag(30)
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Toggle(
                        "Include current time",
                        isOn: $announceClockTime
                    )

                    Text(
                        "Updates include elapsed time, distance and average pace when available. Structured runs also announce the next block."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }
        }
    }
}

func watchRunningWorkoutTransfer(
    from workout: RunningWorkoutTemplate
) -> WatchRunningWorkoutTransfer {
    var steps: [WatchRunningWorkoutStep] = []

    for block in workout.blocks {
        let repetitions = max(block.repetitions, 1)

        for repetition in 0..<repetitions {
            steps.append(
                watchRunningStep(
                    title: block.title,
                    target: block.work
                )
            )

            if repetition < repetitions - 1,
               let recovery = block.recovery {
                steps.append(
                    watchRunningStep(
                        title: "Recovery",
                        target: recovery
                    )
                )
            }
        }
    }

    return WatchRunningWorkoutTransfer(
        title: workout.title,
        steps: steps
    )
}

private func watchRunningStep(
    title: String,
    target: RunningStepTarget
) -> WatchRunningWorkoutStep {
    let measure: WatchRunningStepMeasure

    switch target.measure {
    case .distance:
        measure = .distance
    case .time:
        measure = .time
    case .open:
        measure = .open
    }

    return WatchRunningWorkoutStep(
        id: UUID(),
        title: title,
        measure: measure,
        distanceMeters: target.distanceMeters,
        durationSeconds: target.durationSeconds,
        intensityText: watchIntensityText(
            target.intensity
        )
    )
}

private func watchIntensityText(
    _ intensity: RunningIntensityTarget
) -> String? {
    switch intensity.kind {
    case .none:
        return nil
    case .easy:
        return "Easy effort"
    case .heartRateZone:
        return intensity.heartRateZone.map {
            "Heart-rate zone \($0)"
        }
    case .rpe:
        return intensity.rpe.map {
            String(format: "RPE %.1f", $0)
        }
    case .pace:
        let low = intensity.paceMinSecondsPerKilometer
        let high = intensity.paceMaxSecondsPerKilometer

        if let low, let high {
            return "\(paceText(low))–\(paceText(high)) /km"
        }

        return (low ?? high).map {
            "\(paceText($0)) /km"
        }
    }
}

private func paceText(
    _ seconds: TimeInterval
) -> String {
    let total = max(Int(seconds.rounded()), 0)
    return String(
        format: "%d:%02d",
        total / 60,
        total % 60
    )
}

private extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }
}
