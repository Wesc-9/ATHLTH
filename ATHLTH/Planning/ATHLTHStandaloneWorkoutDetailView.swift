import SwiftUI

/// Read-only entry point for standalone sessions from Train / Today and Plan.
/// Editing uses the existing shared workout editor; neither plan nor history
/// is changed merely by opening this detail screen.
struct ATHLTHStandaloneWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let workout: PlannedSession

    @State private var showingEditor = false

    private var currentWorkout: PlannedSession {
        session.standalonePlannedSessions.first { $0.id == workout.id }
            ?? workout
    }

    private var isCompleted: Bool {
        strength.workoutHistory.contains {
            $0.plannedSessionID == currentWorkout.id && $0.isFullyCompleted
        }
    }

    private var isPartlyCompleted: Bool {
        !isCompleted && strength.workoutHistory.contains {
            $0.plannedSessionID == currentWorkout.id && $0.isFinished
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    overview

                    if !currentWorkout.resolvedWorkoutBlocks.isEmpty {
                        detailSection(
                            title: ATHLTHLocalization.choose(
                                english: "Workout blocks",
                                norwegian: "Treningsblokker"
                            ),
                            icon: "square.stack.3d.up"
                        ) {
                            ForEach(
                                currentWorkout.resolvedWorkoutBlocks
                                    .sorted { $0.sequence < $1.sequence }
                            ) { block in
                                detailRow(
                                    icon: block.kind.systemImage,
                                    title: block.title,
                                    subtitle: block.targetText ?? block.kind.title
                                )
                            }
                        }
                    }

                    if !currentWorkout.exercises.isEmpty {
                        detailSection(
                            title: ATHLTHLocalization.choose(
                                english: "Strength exercises",
                                norwegian: "Styrkeøvelser"
                            ),
                            icon: "dumbbell"
                        ) {
                            ForEach(currentWorkout.exercises) { exercise in
                                let details = [
                                    exercise.compactTargetSummary,
                                    exercise.compactLoadSummary
                                ].compactMap { $0 }.joined(separator: " · ")
                                detailRow(
                                    icon: "dumbbell",
                                    title: exercise.embeddedExercise.name,
                                    subtitle: details
                                )
                            }
                        }
                    }

                    if !currentWorkout.resolvedRunningWorkouts.isEmpty {
                        detailSection(
                            title: ATHLTHLocalization.choose(
                                english: "Running workouts",
                                norwegian: "Løpeøkter"
                            ),
                            icon: "figure.run"
                        ) {
                            ForEach(currentWorkout.resolvedRunningWorkouts) { run in
                                detailRow(
                                    icon: "figure.run",
                                    title: run.title,
                                    subtitle: run.summary
                                )
                                if !run.blocks.isEmpty {
                                    Text("\(run.blocks.count) " +
                                        ATHLTHLocalization.choose(
                                            english: "planned blocks",
                                            norwegian: "planlagte blokker"
                                        ))
                                        .font(.caption2)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                        .padding(.leading, 43)
                                }
                            }
                        }
                    }

                    if let notes = currentWorkout.notes,
                       !notes.trimmingCharacters(
                           in: .whitespacesAndNewlines
                       ).isEmpty {
                        detailSection(
                            title: ATHLTHLocalization.choose(
                                english: "Notes",
                                norwegian: "Notater"
                            ),
                            icon: "text.alignleft"
                        ) {
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if currentWorkout.followUpSourceWorkoutID != nil {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Scheduled from remaining work in a previous session. Original results are unchanged.",
                                norwegian: "Planlagt fra gjenstående arbeid i en tidligere økt. Opprinnelige resultater er uendret."
                            ),
                            systemImage: "link"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .padding(.horizontal, 5)
                    }
                }
                .padding(16)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Workout details",
                norwegian: "Øktdetaljer"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close",
                        norwegian: "Lukk"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Edit",
                        norwegian: "Rediger"
                    )) { showingEditor = true }
                    .disabled(isCompleted || isPartlyCompleted)
                }
            }
            .sheet(isPresented: $showingEditor) {
                SessionEditorView(workout: currentWorkout)
                    .environmentObject(session)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    ATHLTHLocalization.choose(
                        english: "STANDALONE WORKOUT",
                        norwegian: "ENKELTØKT"
                    ),
                    systemImage: currentWorkout.kind.systemImage
                )
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                Spacer(minLength: 5)
                if isCompleted || isPartlyCompleted {
                    Text(isCompleted
                        ? ATHLTHLocalization.choose(
                            english: "Completed",
                            norwegian: "Fullført"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Partly completed",
                            norwegian: "Delvis gjennomført"
                        ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            Text(currentWorkout.title)
                .font(.system(size: 28, weight: .medium, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if let date = currentWorkout.scheduledStart {
                    Label(
                        date.formatted(
                            date: .abbreviated,
                            time: currentWorkout.scheduledTimeIsExplicit == false
                                ? .omitted : .shortened
                        ),
                        systemImage: "calendar"
                    )
                }
                if let duration = currentWorkout.durationMinutes,
                   duration > 0 {
                    Label("\(duration) min", systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)

            Text(ATHLTHLocalization.choose(
                english: "View the planned details here. Edit the session only when you choose to.",
                norwegian: "Se de planlagte detaljene her. Økten endres bare når du velger å redigere."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(ATHLTHTheme.premiumGold.opacity(0.22), lineWidth: 0.8)
        }
    }

    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)
            content()
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func detailRow(
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 31, height: 32)
                .background(
                    ATHLTHTheme.champagneSoft,
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Spacer(minLength: 0)
        }
    }
}
