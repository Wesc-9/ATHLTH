import SwiftUI

/// Calendar-only sessions are not members of a training plan. Display and
/// edit them without manufacturing a plan ID, changing their UUID, or
/// creating a second copy of the workout.
struct HomeWeeklyStandaloneWorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 30

    let workout: PlannedSession
    // Hand off to Home's existing recording engines; this detail view never
    // creates its own workout or starts an untracked timer.
    var onStartWorkout: ((PlannedSession, WorkoutCaptureDevice) -> Void)? = nil

    @State private var showingInvitationLobby = false
    @State private var showingWorkoutTextEditor = false
    @State private var draftWorkoutTitle = ""
    @State private var draftWorkoutNotes = ""
    @State private var showingSaveToLibraryOptions = false

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
                workoutTextActions

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
            if currentWorkout.isExplicitRestDay {
                VStack(spacing: 0) {
                    Button(role: .destructive) {
                        session.removeStandalonePlannedSession(currentWorkout.id)
                        dismiss()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Remove rest day",
                                norwegian: "Fjern hviledag"
                            ),
                            systemImage: "trash"
                        )
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 12)
                }
                .background(ATHLTHPlanDesign.canvas)
            } else if onStartWorkout != nil &&
                        (currentWorkout.kind == .running ||
                         currentWorkout.kind == .walking ||
                         currentWorkout.kind == .strength) {
                startActionFooter
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingWorkoutTextEditor) {
            workoutTextEditor
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Save to My Workouts?", norwegian: "Lagre i Mine økter?"
            ),
            isPresented: $showingSaveToLibraryOptions
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Save as new workout", norwegian: "Lagre som ny økt"
            )) {
                _ = session.saveSharedWorkout(currentWorkout)
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {}
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Your calendar copy stays independent of the saved workout.",
                norwegian: "Kalenderkopien beholdes uavhengig av den lagrede økten."
            ))
        }
        .sheet(isPresented: $showingInvitationLobby) {
            PlannedWorkoutLobbyView(
                workout: currentWorkout,
                onStartWorkout: { selected, device in
                    // The real recording engine belongs to Home. Do not
                    // create an independent timer or duplicate workout.
                    showingInvitationLobby = false
                    dismiss()
                    onStartWorkout?(selected, device)
                }
            )
            .presentationDetents([.large])
        }
    }

    private var workoutTextActions: some View {
        HStack(spacing: 10) {
            Button {
                draftWorkoutTitle = currentWorkout.title
                draftWorkoutNotes = currentWorkout.notes ?? ""
                showingWorkoutTextEditor = true
            } label: {
                Label(
                    ATHLTHLocalization.choose(english: "Edit name and description",
                                              norwegian: "Rediger navn og beskrivelse"),
                    systemImage: "square.and.pencil"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                showingSaveToLibraryOptions = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 38, height: 38)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Save workout to my workouts",
                norwegian: "Lagre økten i Mine økter"
            ))
        }
        .padding(.horizontal, 4)
    }

    private var workoutTextEditor: some View {
        NavigationStack {
            Form {
                Section(ATHLTHLocalization.choose(
                    english: "Workout name", norwegian: "Navn på treningsøkt"
                )) {
                    TextField(ATHLTHLocalization.choose(
                        english: "Name", norwegian: "Navn"
                    ), text: $draftWorkoutTitle)
                }
                Section(ATHLTHLocalization.choose(
                    english: "Description", norwegian: "Beskrivelse"
                )) {
                    TextEditor(text: $draftWorkoutNotes)
                        .frame(minHeight: 130)
                }
                Section {
                    Text(ATHLTHLocalization.choose(
                        english: "Changes apply only to this calendar workout. Your saved workouts and training plans remain unchanged.",
                        norwegian: "Endringene gjelder bare denne kalenderøkten. Lagrede økter og treningsplaner endres ikke."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Edit workout", norwegian: "Rediger økt"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) {
                        showingWorkoutTextEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Save", norwegian: "Lagre"
                    )) {
                        var updated = currentWorkout
                        updated.title = draftWorkoutTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let notes = draftWorkoutNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.notes = notes.isEmpty ? nil : notes
                        session.updateStandalonePlannedSession(updated)
                        showingWorkoutTextEditor = false
                    }
                    .disabled(draftWorkoutTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
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
                    english: currentWorkout.isExplicitRestDay ? "Rest day" : "Workout details",
                    norwegian: currentWorkout.isExplicitRestDay ? "Hviledag" : "Øktdetaljer"
                ))
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            }

            Spacer(minLength: 6)


        }
        .padding(.top, 1)
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 10) {
                Label(
                    ATHLTHLocalization.choose(
                        english: currentWorkout.isExplicitRestDay ? "REST DAY" : "SCHEDULED WORKOUT",
                        norwegian: currentWorkout.isExplicitRestDay ? "HVILEDAG" : "PLANLAGT ØKT"
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

    // These labels are inferred only from the user's actual notes. The
    // numeric prescription itself is never synthesized or modified.
    private func noteStepIdentity(
        _ text: String,
        index: Int
    ) -> (title: String, symbol: String) {
        let value = text.lowercased()
        if value.contains("oppvarm") || value.contains("warm-up") ||
           value.contains("warmup") {
            return (
                ATHLTHLocalization.choose(
                    english: "Warm-up", norwegian: "Oppvarming"
                ),
                "figure.walk"
            )
        }
        if value.contains("nedjogg") || value.contains("cooldown") ||
           value.contains("cool-down") {
            return (
                ATHLTHLocalization.choose(
                    english: "Cool-down", norwegian: "Nedjogging"
                ),
                "figure.run"
            )
        }
        if value.contains("pause") || value.contains("recovery") ||
           value.contains("rest") {
            return (
                ATHLTHLocalization.choose(
                    english: "Recovery", norwegian: "Pause"
                ),
                "pause.circle"
            )
        }
        if value.contains("intervall") || value.contains("drag") ||
           value.contains("interval") {
            return (
                ATHLTHLocalization.choose(
                    english: "Work intervals", norwegian: "Arbeidsdrag"
                ),
                "bolt"
            )
        }
        return (
            ATHLTHLocalization.choose(
                english: "Step \(index + 1)", norwegian: "Del \(index + 1)"
            ),
            "circle.grid.2x2"
        )
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
                        let identity = noteStepIdentity(step, index: index)
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: identity.symbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 42, height: 42)
                                .background(
                                    ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 13)
                                )
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(identity.title.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .tracking(1)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                Text(step)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .background(
                            ATHLTHPlanDesign.warmSurface.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
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

    private var startActionFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(ATHLTHPlanDesign.outline)
                .frame(height: 0.7)

            Text(ATHLTHLocalization.choose(
                english: "START WORKOUT", norwegian: "START ØKT"
            ))
            .font(.caption2.weight(.bold))
            .tracking(1.4)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .padding(.top, 6)

            HStack(spacing: 10) {
                launchButton(
                    title: "iPhone",
                    systemImage: "iphone",
                    device: .iPhone,
                    prominent: true,
                    enabled: true
                )

                launchButton(
                    title: "Apple Watch",
                    systemImage: "applewatch",
                    device: .appleWatch,
                    prominent: false,
                    enabled: watchConnection.isVerifiedForLiveLaunch
                )
            }

            if !watchConnection.isVerifiedForLiveLaunch {
                Text(ATHLTHLocalization.choose(
                    english: "Apple Watch is unavailable. You can still start on iPhone.",
                    norwegian: "Apple Watch er ikke tilgjengelig. Du kan fortsatt starte på iPhone."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .padding(.horizontal, 19)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(ATHLTHPlanDesign.canvas)
    }

    private func launchButton(
        title: String,
        systemImage: String,
        device: WorkoutCaptureDevice,
        prominent: Bool,
        enabled: Bool
    ) -> some View {
        Button {
            // A calendar detail can outlive an edit or deletion. Only the
            // persisted standalone workout may be used at launch time.
            guard let persisted = session.standalonePlannedSessions.first(
                where: { $0.id == workout.id }
            ), !persisted.isExplicitRestDay,
               enabled else { return }

            if persisted.trainTogetherMode != nil {
                showingInvitationLobby = true
                return
            }

            dismiss()
            onStartWorkout?(persisted, device)
        } label: {
            Label(
                ATHLTHLocalization.choose(
                    english: "Start on \(title)",
                    norwegian: "Start på \(title)"
                ),
                systemImage: systemImage
            )
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(prominent ? .white : ATHLTHPlanDesign.ink)
            .background(
                prominent ? ATHLTHPlanDesign.ink :
                    ATHLTHPlanDesign.selectedSurface,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.48)
    }
}
