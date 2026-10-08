import Foundation
import SwiftUI

struct PlannedWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let planID: UUID
    let workout: PlannedSession
    let isHealthCompleted: Bool

    @State private var showingEditor = false
    @State private var showingStructuredWorkout = false
    @State private var showingHealthLinkPicker = false

    private var currentWorkout: PlannedSession {
        guard let plan = session.trainingPlan(withID: planID) else {
            return workout
        }

        for week in plan.weeks {
            for day in week.days {
                if let updated = day.sessions.first(
                    where: { $0.id == workout.id }
                ) {
                    return updated
                }
            }
        }

        return workout
    }

    private var isManuallyCompleted: Bool {
        session.isPlanSessionManuallyCompleted(
            planID: planID,
            sessionID: currentWorkout.id
        )
    }

    private var storedLinkedHealthID: UUID? {
        session.linkedHealthWorkoutID(
            planID: planID, sessionID: currentWorkout.id
        )
    }

    private var linkedHealthWorkout: WorkoutSummary? {
        guard let linkedID = storedLinkedHealthID else { return nil }
        return health.workouts.first { $0.id == linkedID }
    }

    private var hasRecordedStrengthWorkout: Bool {
        strength.workoutHistory.contains {
            $0.isFinished && $0.plannedSessionID == currentWorkout.id
        }
    }

    private var matchingHealthWorkouts: [WorkoutSummary] {
        health.workouts
            .filter { item in
                switch currentWorkout.kind {
                case .running: return item.activity == .running
                case .walking: return item.activity == .walking ||
                    item.activity == .hiking
                case .strength: return item.activity == .strength
                case .mobility: return item.activity == .yoga ||
                    item.activity == .coreTraining
                case .recovery: return false
                case .custom: return item.activity == .hiit ||
                    item.activity == .rowing ||
                    item.activity == .cycling ||
                    item.activity == .stairClimbing ||
                    item.activity == .other
                }
            }
            .sorted { $0.startDate > $1.startDate }
            .prefix(30)
            .map { $0 }
    }

    private var isCompleted: Bool {
        !session.isPlanSessionSkipped(
            planID: planID, sessionID: currentWorkout.id
        ) && (
            isManuallyCompleted ||
            isHealthCompleted ||
            hasRecordedStrengthWorkout ||
            linkedHealthWorkout != nil
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    overviewCard

                    if currentWorkout.kind == .running ||
                        currentWorkout.kind == .walking {
                        runGuidanceCard
                    }

                    if !currentWorkout.exercises.isEmpty {
                        strengthCard
                    }

                    if !currentWorkout.resolvedRunningWorkouts.isEmpty {
                        runningCard(
                            currentWorkout.resolvedRunningWorkouts
                        )
                    }

                    if currentWorkout.isStructuredWorkout {
                        structuredWorkoutCard
                        structuredWorkoutStartButton
                    }

                    if let notes = cleanNotes {
                        notesCard(notes)
                    }

                    completionCard
                }
                .padding(20)
                .padding(.bottom, 28)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
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
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        showingEditor = true
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                SessionEditorView(
                    planID: planID,
                    workout: currentWorkout
                )
            }
            .sheet(isPresented: $showingHealthLinkPicker) {
                healthLinkPicker
            }
            .fullScreenCover(
                isPresented:
                    $showingStructuredWorkout
            ) {
                StructuredWorkoutSessionView(
                    workout: currentWorkout
                )
                .environmentObject(session)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: currentWorkout.kind.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentWorkout.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    HStack(spacing: 7) {
                        Text(currentWorkout.kind.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)

                        Circle()
                            .fill(ATHLTHTheme.mutedText.opacity(0.55))
                            .frame(width: 3, height: 3)

                        Label(
                            isCompleted ? "Completed" : "Planned",
                            systemImage: isCompleted
                                ? "checkmark.circle.fill"
                                : "calendar"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            isCompleted
                                ? ATHLTHTheme.accent
                                : ATHLTHTheme.mutedText
                        )
                    }
                }

                Spacer()
            }
        }
    }

    private var overviewCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Plan details")

                if let scheduledStart = currentWorkout.scheduledStart {
                    detailRow(
                        icon: "clock",
                        title: "Scheduled",
                        value: scheduledStart.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                }

                if let duration = currentWorkout.durationMinutes {
                    detailRow(
                        icon: "timer",
                        title: "Duration",
                        value: "\(duration) min"
                    )
                }

                if let distance = currentWorkout.targetDistanceKilometers {
                    detailRow(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        title: "Distance",
                        value: String(format: "%.1f km", distance)
                    )
                }

                if let pace = currentWorkout.targetPaceSecondsPerKilometer {
                    detailRow(
                        icon: "speedometer",
                        title: "Target pace",
                        value: paceText(pace)
                    )
                }

                if let routeID = currentWorkout.routeID,
                   let route = session.savedRoutes.first(where: { $0.id == routeID }) {
                    detailRow(
                        icon: "map",
                        title: "Route",
                        value: route.title
                    )
                }

                if let playlist =
                    WorkoutLaunchCoordinator
                        .resolvedSpotifyPlaylist(
                            workout: currentWorkout,
                            session: session
                        ) {
                    detailRow(
                        icon: "music.note.list",
                        title: "Spotify",
                        value: playlist.name
                    )
                } else if currentWorkout.spotifyAutoplayOnStart == false {
                    detailRow(
                        icon: "speaker.slash",
                        title: "Spotify",
                        value: "Off"
                    )
                }

                if currentWorkout.scheduledStart == nil &&
                    currentWorkout.durationMinutes == nil &&
                    currentWorkout.targetDistanceKilometers == nil &&
                    currentWorkout.targetPaceSecondsPerKilometer == nil &&
                    currentWorkout.routeID == nil {
                    Text("No additional targets are set for this workout.")
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
        }
    }

    private var runGuidanceCard:
        some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 14
            ) {
                HStack(spacing: 11) {
                    Image(
                        systemName:
                            "waveform.and.mic"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                    .frame(
                        width: 40,
                        height: 40
                    )
                    .background(
                        ATHLTHTheme
                            .premiumGoldSoft,
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Run guidance",
                                norwegian:
                                    "Løpeveiledning"
                            )
                        )
                        .font(
                            .headline
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "What will help you during this workout",
                                norwegian:
                                    "Hjelpen som følger deg gjennom økten"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    Button(
                        ATHLTHLocalization.choose(
                            english: "Edit",
                            norwegian: "Rediger"
                        )
                    ) {
                        showingEditor = true
                    }
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }

                HStack(spacing: 8) {
                    plannedGuidanceTile(
                        title: "Audio Coach",
                        subtitle:
                            runGuidanceAudioCoachEnabled
                                ? ATHLTHLocalization.choose(
                                    english: "On",
                                    norwegian: "På"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Off",
                                    norwegian: "Av"
                                ),
                        icon:
                            "waveform.and.person.filled",
                        active:
                            runGuidanceAudioCoachEnabled
                    )

                    if currentWorkout.kind ==
                        .running {
                        plannedGuidanceTile(
                            title: "Ghost",
                            subtitle:
                                ghostDetailText,
                            icon:
                                "figure.run.circle.fill",
                            active:
                                currentWorkout
                                    .ghostTargetDurationSeconds != nil
                        )

                        plannedGuidanceTile(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "Route",
                                    norwegian: "Rute"
                                ),
                            subtitle:
                                routeGuardianDetailText,
                            icon:
                                "location.fill",
                            active:
                                (
                                    currentWorkout
                                        .routeAlertConfiguration ??
                                    settings
                                        .routeAlertConfiguration
                                )
                                .enabled &&
                                currentWorkout
                                    .routeID != nil
                        )
                    }
                }

                if let target =
                        currentWorkout
                            .targetAlertConfiguration,
                   target.heartRateEnabled ||
                    target.paceAlertsEnabled {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Live target alerts are configured",
                            norwegian:
                                "Live-mål og varsler er satt opp"
                        ),
                        systemImage:
                            "scope"
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        .orange
                    )
                }
            }
        }
    }

    private var runGuidanceAudioCoachEnabled:
        Bool {
        currentWorkout
            .audioCoachConfiguration?
            .enabled ??
        settings
            .audioCoachEnabledByDefault
    }

    private var ghostDetailText:
        String {
        guard let seconds =
                currentWorkout
                    .ghostTargetDurationSeconds
        else {
            return ATHLTHLocalization.choose(
                english: "Off",
                norwegian: "Av"
            )
        }

        return GhostTargetTimeFormatter
            .string(seconds)
    }

    private var routeGuardianDetailText:
        String {
        guard currentWorkout.routeID != nil
        else {
            return ATHLTHLocalization.choose(
                english: "No route",
                norwegian: "Ingen rute"
            )
        }

        let configuration =
            currentWorkout
                .routeAlertConfiguration ??
            settings
                .routeAlertConfiguration

        return configuration.enabled
            ? ATHLTHLocalization.format(
                english: "%.0f m",
                norwegian: "%.0f m",
                configuration
                    .deviationMeters
            )
            : ATHLTHLocalization.choose(
                english: "Off",
                norwegian: "Av"
            )
    }

    private func plannedGuidanceTile(
        title: String,
        subtitle: String,
        icon: String,
        active: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 14,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                active
                    ? ATHLTHTheme
                        .vitality
                    : ATHLTHTheme
                        .mutedText
            )

            Text(title)
                .font(
                    .system(
                        size: 11,
                        weight: .semibold
                    )
                )
                .lineLimit(1)

            Text(subtitle)
                .font(
                    .system(
                        size: 9.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 72,
            alignment: .leading
        )
        .padding(10)
        .background(
            active
                ? ATHLTHTheme
                    .vitalitySoft
                    .opacity(0.70)
                : Color.primary
                    .opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var strengthCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                sectionTitle("Exercises")

                ForEach(Array(currentWorkout.exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(alignment: .top, spacing: 11) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: Circle()
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(exercise.embeddedExercise.displayName)
                                .font(.subheadline.weight(.semibold))

                            Text(exerciseSummary(exercise))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)

                            if exercise.hasIndividualSetTargets {
                                VStack(spacing: 5) {
                                    ForEach(
                                        Array(
                                            exercise
                                                .resolvedSetTargets
                                                .enumerated()
                                        ),
                                        id: \.element.id
                                    ) { setIndex, target in
                                        HStack(spacing: 7) {
                                            Text(
                                                ATHLTHLocalization.choose(
                                                    english:
                                                        "Set \(setIndex + 1)",
                                                    norwegian:
                                                        "Sett \(setIndex + 1)"
                                                )
                                            )
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(
                                                ATHLTHTheme.primaryText
                                            )
                                            .frame(
                                                width: 42,
                                                alignment: .leading
                                            )

                                            Text(
                                                individualSetSummary(
                                                    target,
                                                    exercise: exercise
                                                )
                                            )
                                            .font(
                                                .caption2
                                                .monospacedDigit()
                                            )
                                            .foregroundStyle(
                                                ATHLTHTheme.mutedText
                                            )
                                            .lineLimit(1)

                                            Spacer()
                                        }
                                        .padding(.horizontal, 9)
                                        .frame(minHeight: 29)
                                        .background(
                                            Color.primary.opacity(0.025),
                                            in: RoundedRectangle(
                                                cornerRadius: 9,
                                                style: .continuous
                                            )
                                        )
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }

                        Spacer()
                    }

                    if index < currentWorkout.exercises.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func runningCard(
        _ runningWorkouts: [RunningWorkoutTemplate]
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(
                    runningWorkouts.count == 1
                        ? "Running workout"
                        : "Running workouts"
                )

                ForEach(
                    Array(runningWorkouts.enumerated()),
                    id: \.element.id
                ) { index, runningWorkout in
                    HStack(spacing: 11) {
                        Image(systemName: runningWorkout.type.systemImage)
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 38, height: 38)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 12)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(runningWorkout.title)
                                .font(.subheadline.weight(.semibold))

                            Text(
                                ATHLTHLocalization.format(
                                    english: "%@ · %d blocks",
                                    norwegian: "%@ · %d blokker",
                                    runningWorkout.type.title,
                                    runningWorkout.blocks.count
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                            if !runningWorkout.summary.isEmpty {
                                Text(runningWorkout.summary)
                                    .font(.caption2)
                                    .foregroundStyle(
                                        ATHLTHTheme.mutedText
                                    )
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }
                        }

                        Spacer()
                    }

                    if index < runningWorkouts.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }


    private var structuredWorkoutCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Workout blocks")

                ForEach(
                    currentWorkout.resolvedWorkoutBlocks
                ) { block in
                    HStack(alignment: .top, spacing: 11) {
                        Text("\(block.sequence)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(
                                ATHLTHTheme.accent
                            )
                            .frame(width: 28, height: 28)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: Circle()
                            )

                        Image(
                            systemName:
                                block.kind.systemImage
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            block.kind == .run
                                ? ATHLTHTheme.vitality
                                : ATHLTHTheme.accentDeep
                        )
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(
                                    .subheadline.weight(
                                        .semibold
                                    )
                                )

                            if let target = block.targetText {
                                Text(target)
                                    .font(.caption)
                                    .foregroundStyle(
                                        ATHLTHTheme.mutedText
                                    )
                            }

                            if let notes = block.notes,
                               !notes.isEmpty {
                                Text(notes)
                                    .font(.caption2)
                                    .foregroundStyle(
                                        ATHLTHTheme.mutedText
                                    )
                            }
                        }

                        Spacer()
                    }

                    if block.id !=
                        currentWorkout
                            .resolvedWorkoutBlocks
                            .last?
                            .id {
                        Divider()
                    }
                }
            }
        }
    }


    private var structuredWorkoutStartButton:
        some View {
        Button {
            WorkoutLaunchCoordinator
                .startLinkedSpotifyIfNeeded(
                    workout: currentWorkout,
                    session: session,
                    settings: settings,
                    spotify: spotify
                )
            showingStructuredWorkout = true
        } label: {
            Label(
                "Start Workout",
                systemImage: "play.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(ATHLTHTheme.accentDeep)
        .disabled(isCompleted)
    }

    private func notesCard(_ notes: String) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("Notes")

                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var healthLinkPicker: some View {
        NavigationStack {
            List {
                if matchingHealthWorkouts.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No matching workouts available",
                            norwegian: "Ingen passende økter tilgjengelig"
                        ),
                        systemImage: "heart.text.square"
                    )
                } else {
                    ForEach(matchingHealthWorkouts) { item in
                        Button {
                            if session.linkHealthWorkout(
                                item,
                                toPlan: planID,
                                sessionID: currentWorkout.id
                            ) {
                                showingHealthLinkPicker = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "heart.circle")
                                    .foregroundStyle(ATHLTHTheme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.activity.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text(item.startDate.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "link")
                                    .foregroundStyle(ATHLTHTheme.accent)
                            }
                        }
                        .disabled(
                            session.linkedHealthWorkoutsByPlanSession.values
                                .contains(item.id) &&
                            session.linkedHealthWorkoutID(
                                planID: planID,
                                sessionID: currentWorkout.id
                            ) != item.id
                        )
                    }
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Link workout",
                    norwegian: "Koble til økt"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel", norwegian: "Avbryt"
                        )
                    ) {
                        showingHealthLinkPicker = false
                    }
                }
            }
        }
    }

    private var completionCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle(
                    ATHLTHLocalization.choose(
                        english: "Completion",
                        norwegian: "Gjennomføring"
                    )
                )

                if isCompleted && !isManuallyCompleted ||
                    storedLinkedHealthID != nil {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Completed with a recorded workout",
                            norwegian: "Fullført med registrert treningsøkt"
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                    if storedLinkedHealthID != nil {
                        Button {
                            session.unlinkHealthWorkout(
                                planID: planID, sessionID: currentWorkout.id
                            )
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Unlink Apple Health workout",
                                    norwegian: "Fjern koblingen til Apple Health"
                                ),
                                systemImage: "link.badge.minus"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    if isManuallyCompleted {
                        Button {
                            session.setPlanSessionManuallyCompleted(
                                planID: planID,
                                sessionID: currentWorkout.id,
                                completed: false
                            )
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Undo manual completion",
                                    norwegian: "Angre manuell fullføring"
                                ),
                                systemImage: "arrow.uturn.backward"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button {
                        session.setPlanSessionManuallyCompleted(
                            planID: planID,
                            sessionID: currentWorkout.id,
                            completed: !isManuallyCompleted
                        )
                    } label: {
                        Label(
                            isManuallyCompleted
                                ? ATHLTHLocalization.choose(
                                    english: "Undo manual completion",
                                    norwegian: "Angre manuell fullføring"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Mark as completed",
                                    norwegian: "Marker som fullført"
                                ),
                            systemImage: isManuallyCompleted
                                ? "arrow.uturn.backward.circle.fill"
                                : "checkmark.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Manual completion updates only this plan, not Apple Health.",
                            norwegian: "Manuell fullføring oppdaterer bare planen, ikke Apple Health."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                if linkedHealthWorkout == nil && !isHealthCompleted {
                    Button {
                        showingHealthLinkPicker = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Link an Apple Health workout",
                                norwegian: "Koble til en Apple Health-økt"
                            ),
                            systemImage: "heart.text.square"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(matchingHealthWorkouts.isEmpty)
                }

                Text(
                    ATHLTHLocalization.choose(
                        english: "Only workouts you explicitly link are credited to this plan. Other Health workouts are never matched by date alone.",
                        norwegian: "Bare økter du selv kobler til, telles i denne planen. Andre Health-økter matches aldri kun på dato."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var cleanNotes: String? {
        guard let notes = currentWorkout.notes?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty
        else {
            return nil
        }

        return notes
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(ATHLTHTheme.mutedText)
    }

    @ViewBuilder
    private func detailRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 11)
                )

            Text(title)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func individualSetSummary(
        _ target: PlannedExerciseSetTarget,
        exercise: PlannedExercise
    ) -> String {
        var parts: [String] = []

        if exercise.resolvedTargetKind == .reps {
            if let reps = target.reps {
                parts.append(
                    ATHLTHLocalization.choose(
                        english: "\(reps) reps",
                        norwegian: "\(reps) reps"
                    )
                )
            }
        } else if let duration =
                    target.durationSeconds {
            let minutes =
                duration / 60
            let seconds =
                duration % 60
            parts.append(
                minutes > 0
                    ? String(
                        format: "%d:%02d",
                        minutes,
                        seconds
                    )
                    : "\(seconds)s"
            )
        }

        if exercise.resolvedLoadKind ==
            .weightKilograms,
           let weight =
                target.weightKilograms {
            parts.append(
                String(
                    format: "%.1f kg",
                    weight
                )
            )
        } else if exercise.resolvedLoadKind ==
                    .resistanceLevel,
                  let level =
                    target.resistanceLevel {
            parts.append(
                ATHLTHLocalization.choose(
                    english:
                        "Resistance \(level)",
                    norwegian:
                        "Motstand \(level)"
                )
            )
        }

        if let rest =
                target.restSeconds {
            parts.append(
                ATHLTHLocalization.choose(
                    english: "\(rest)s rest",
                    norwegian: "\(rest)s hvile"
                )
            )
        }

        if let rpe =
                target.targetRPE {
            parts.append(
                String(
                    format: "RPE %.1f",
                    rpe
                )
            )
        }

        if let rir =
                target.targetRIR {
            parts.append(
                String(
                    format: "RIR %.1f",
                    rir
                )
            )
        }

        if target.isWarmUp == true {
            parts.append(
                ATHLTHLocalization.choose(
                    english: "Warm-up",
                    norwegian: "Oppvarming"
                )
            )
        } else if let setType =
                    target.setType,
                  setType != .work {
            parts.append(
                setType.title
            )
        }

        if let tempo =
                target.tempo?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
           !tempo.isEmpty {
            parts.append(
                "Tempo \(tempo)"
            )
        }

        if let note =
                target.notes?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
           !note.isEmpty {
            parts.append(note)
        }

        return parts.joined(separator: " · ")
    }

    private func exerciseSummary(
        _ exercise: PlannedExercise
    ) -> String {
        var parts: [String] = []

        parts.append(
            exercise.compactTargetSummary
        )

        if let load =
                exercise.compactLoadSummary {
            parts.append(load)
        }

        if !exercise.hasIndividualSetTargets,
           let rest = exercise.restSeconds {
            parts.append(
                ATHLTHLocalization.choose(
                    english: "\(rest)s rest",
                    norwegian: "\(rest)s hvile"
                )
            )
        }

        return parts.joined(separator: " · ")
    }

    private func paceText(_ secondsPerKilometer: Double) -> String {
        let totalSeconds = max(Int(secondsPerKilometer.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}
