import SwiftUI

/// Calendar-only sessions are not members of a training plan. Display and
/// edit them without manufacturing a plan ID, changing their UUID, or
/// creating a second copy of the workout.
struct HomeWeeklyStandaloneWorkoutDetailView: View {
    @EnvironmentObject private var session: AppSessionStore
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 30

    let workout: PlannedSession

    @State private var showingEditor = false
    @State private var showingInvitationLobby = false

    private var currentWorkout: PlannedSession {
        session.standalonePlannedSessions.first {
            $0.id == workout.id
        } ?? workout
    }

    private var workoutNotes: String? {
        guard let notes = currentWorkout.notes?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else {
            return nil
        }
        return notes
    }

    // Prefer the actual executable recipe, including interval repetitions,
    // recoveries, pace/zones and exercise targets. Text notes are only a
    // fallback for older calendar sessions without structured blocks.
    private var detailedBlocks: [WorkoutTemplateBlock] {
        let stored = currentWorkout.resolvedWorkoutBlocks
        if !stored.isEmpty { return stored }
        if !currentWorkout.resolvedRunningWorkouts.isEmpty {
            return currentWorkout.resolvedRunningWorkouts.flatMap {
                $0.recipePreviewBlocks
            }
        }
        if !currentWorkout.exercises.isEmpty {
            return ATHLTHUnifiedWorkout.editorBlocks(from: currentWorkout)
        }
        return []
    }

    private var detailCategory: String {
        currentWorkout.workoutCategory ??
            (currentWorkout.kind == .running ? "running" :
             currentWorkout.kind == .walking ? "walking" :
             currentWorkout.kind == .strength ? "strength" : "hybrid")
    }

    private func workoutSteps(from notes: String) -> [String] {
        // Only render an outline when the user has actually separated the
        // notes into stages. Ordinary prose stays intact in a single block.
        let parts = notes.split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (2...8).contains(parts.count) ? parts : []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                sheetHeader
                overviewCard

                // Full read-only programming timeline for authored workouts.
                // The outline also supports the Simple/Advanced detail toggle.
                if !detailedBlocks.isEmpty {
                    ATHLTHWorkoutRecipePreview(
                        title: currentWorkout.title,
                        summary: "",
                        category: detailCategory,
                        symbol: currentWorkout.kind.systemImage,
                        difficulty: nil,
                        durationMinutes: currentWorkout.durationMinutes,
                        blocks: detailedBlocks,
                        embeddedInDetails: true
                    )
                }

                // Preserve free-form instructions for older workouts and
                // additional trainer notes for structured prescriptions.
                if let notes = workoutNotes {
                    notesCard(notes)
                }

                if detailedBlocks.isEmpty && !currentWorkout.exercises.isEmpty {
                    exercisesCard
                }

                if currentWorkout.trainTogetherMode != nil {
                    lobbyButton
                }
            }
            .padding(.horizontal, 19)
            .padding(.top, 17)
            .padding(.bottom, 24)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editActionFooter
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingEditor) {
            SessionEditorView(
                standaloneDate: currentWorkout.scheduledStart ?? Date(),
                initialSourceWorkout: currentWorkout,
                preserveSourceID: true
            )
        }
        .sheet(isPresented: $showingInvitationLobby) {
            PlannedWorkoutLobbyView(workout: currentWorkout)
                .presentationDetents([.medium, .large])
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ATHLTH  /  " + ATHLTHLocalization.choose(
                    english: "TRAINING", norwegian: "TRENING"
                ))
                .font(.caption2.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

                Text(ATHLTHLocalization.choose(
                    english: "Workout details", norwegian: "Øktdetaljer"
                ))
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            }

            Spacer(minLength: 6)

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 48, height: 48)
                .background(
                    ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .accessibilityHidden(true)
        }
        .padding(.top, 1)
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 10) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "SCHEDULED WORKOUT", norwegian: "PLANLAGT ØKT"
                    ),
                    systemImage: "calendar"
                )
                .font(.caption2.weight(.semibold))
                .tracking(1.15)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

                Spacer(minLength: 0)

                Label(
                    currentWorkout.kind.title,
                    systemImage: currentWorkout.kind.systemImage
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(ATHLTHPlanDesign.selectedSurface, in: Capsule())
            }

            Text(currentWorkout.title)
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            if currentWorkout.scheduledStart != nil ||
               currentWorkout.durationMinutes != nil {
                Rectangle()
                    .fill(ATHLTHPlanDesign.warmDivider)
                    .frame(height: 0.7)

                HStack(alignment: .top, spacing: 10) {
                    if let start = currentWorkout.scheduledStart {
                        metricTile(
                            icon: "calendar",
                            title: ATHLTHLocalization.choose(
                                english: "DATE & TIME", norwegian: "DATO OG TID"
                            ),
                            value: start.formatted(
                                .dateTime.weekday(.abbreviated).day()
                                    .month(.abbreviated)
                            ),
                            detail: start.formatted(.dateTime.hour().minute())
                        )
                    }

                    if let minutes = currentWorkout.durationMinutes {
                        metricTile(
                            icon: "timer",
                            title: ATHLTHLocalization.choose(
                                english: "DURATION", norwegian: "VARIGHET"
                            ),
                            value: "\(minutes) min",
                            detail: ATHLTHLocalization.choose(
                                english: "Planned time", norwegian: "Planlagt tid"
                            )
                        )
                    }
                }
            }

            if let distance = currentWorkout.targetDistanceKilometers {
                Label(
                    String(format: "%.1f km", distance),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    ATHLTHPlanDesign.warmSurface.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 13)
                )
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthPlanCard(radius: 24)
    }

    private func metricTile(
        icon: String,
        title: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .lineLimit(2)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ATHLTHPlanDesign.warmSurface.opacity(0.70),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func notesCard(_ notes: String) -> some View {
        let steps = workoutSteps(from: notes)

        return ATHLTHPlanSurface {
            HStack(spacing: 9) {
                Image(systemName: steps.isEmpty ? "note.text" : "list.number")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)

                Text(steps.isEmpty
                     ? ATHLTHLocalization.choose(
                         english: "Workout notes", norwegian: "Notater"
                       )
                     : ATHLTHLocalization.choose(
                         english: "Workout outline", norwegian: "Øktoppsett"
                       ))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
            }

            if steps.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 25, height: 25)
                                .background(
                                    ATHLTHPlanDesign.selectedSurface,
                                    in: Circle()
                                )

                            Text(step)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var exercisesCard: some View {
        ATHLTHPlanSurface {
            Label(
                ATHLTHLocalization.choose(
                    english: "Exercises", norwegian: "Øvelser"
                ),
                systemImage: "dumbbell"
            )
            .font(.headline.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.ink)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(
                    Array(currentWorkout.exercises.enumerated()),
                    id: \.element.id
                ) { index, exercise in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)

                        Text(exercise.embeddedExercise.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var lobbyButton: some View {
        Button {
            showingInvitationLobby = true
        } label: {
            Label(
                ATHLTHLocalization.choose(
                    english: "Open Train Together lobby",
                    norwegian: "Åpne Tren sammen-lobby"
                ),
                systemImage: "person.2"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .frame(maxWidth: .infinity, minHeight: ATHLTHPlanDesign.minTapHeight)
            .background(
                ATHLTHPlanDesign.selectedSurface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var editActionFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ATHLTHPlanDesign.outline)
                .frame(height: 0.7)

            Button {
                showingEditor = true
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Edit workout", norwegian: "Rediger økt"
                    ),
                    systemImage: "square.and.pencil"
                )
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    ATHLTHPlanDesign.ink,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english: "Update the existing scheduled workout",
                    norwegian: "Oppdater den eksisterende planlagte økten"
                )
            )
            .padding(.horizontal, 19)
            .padding(.top, 11)
            .padding(.bottom, 8)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
        }
        .frame(maxWidth: .infinity)
        .background(ATHLTHPlanDesign.canvas)
    }
}
