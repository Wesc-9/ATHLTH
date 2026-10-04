import Foundation
import SwiftUI

struct PlannedWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

    let planID: UUID
    let workout: PlannedSession
    let isHealthCompleted: Bool

    @State private var showingEditor = false
    @State private var showingStructuredWorkout = false

    private var currentWorkout: PlannedSession {
        guard let plan = session.activePlan,
              plan.id == planID
        else {
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

    private var isCompleted: Bool {
        isHealthCompleted || isManuallyCompleted
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
                            currentWorkout
                                .audioCoachConfiguration?
                                .enabled ??
                            settings
                                .audioCoachEnabledByDefault
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
                            currentWorkout
                                .audioCoachConfiguration?
                                .enabled ??
                            settings
                                .audioCoachEnabledByDefault
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

                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.embeddedExercise.name)
                                .font(.subheadline.weight(.semibold))

                            Text(exerciseSummary(exercise))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
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

    private var completionCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Completion")

                if isHealthCompleted {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.accent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Completed")
                                .font(.headline)

                            Text("Matched automatically from Apple Health.")
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.accent)
                    }
                } else {
                    Button {
                        session.setPlanSessionManuallyCompleted(
                            planID: planID,
                            sessionID: currentWorkout.id,
                            completed: !isManuallyCompleted
                        )
                    } label: {
                        HStack(spacing: 10) {
                            Image(
                                systemName: isManuallyCompleted
                                    ? "arrow.uturn.backward.circle.fill"
                                    : "checkmark.circle.fill"
                            )
                            .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    isManuallyCompleted
                                        ? "Mark as Not Completed"
                                        : "Mark as Completed"
                                )
                                .font(.headline)

                                Text(
                                    isManuallyCompleted
                                        ? "Remove the manual completion."
                                        : "Set this planned workout as performed."
                                )
                                .font(.caption)
                                .opacity(0.78)
                            }

                            Spacer()
                        }
                        .foregroundStyle(
                            isManuallyCompleted
                                ? ATHLTHTheme.accentDeep
                                : Color.white
                        )
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(
                            isManuallyCompleted
                                ? ATHLTHTheme.accentSoft
                                : ATHLTHTheme.accent,
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                    }
                    .buttonStyle(.plain)

                    Text(
                        "Manual completion updates your ATHLTH plan only. It does not create an Apple Health workout."
                    )
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }
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

        if let rest = exercise.restSeconds {
            parts.append("\(rest)s rest")
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
