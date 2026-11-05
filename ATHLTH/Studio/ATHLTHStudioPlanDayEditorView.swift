import SwiftUI

/// A genuine in-place iPad editor for the existing PlannedSession model.
/// The same optimistic-version and completion protections used by Train's
/// Plan Studio are enforced by AppSessionStore on every write.
struct ATHLTHStudioPlanDayEditorView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let plan: TrainingPlan
    let day: TrainingPlanDay
    let date: Date?
    let onOpenAdvanced: (UUID) -> Void
    /// The iPad canvas supplies the shared iPhone workout engine for new sessions.
    var onCreateAdvanced: (() -> Void)? = nil
    var onStartWorkout: ((UUID, UUID) -> Void)? = nil
    var onSendToWatch: ((UUID, UUID) -> Void)? = nil
    var onStartAfter: ((UUID, UUID, TimeInterval) -> Void)? = nil

    @State private var isEditing = false
    @State private var originalWorkout: PlannedSession?
    @State private var expectedVersion = 0
    @State private var title = ""
    @State private var kind: WorkoutKind = .running
    @State private var hasDuration = true
    @State private var duration = 45
    @State private var distanceKilometers = 0.0
    @State private var hasStartTime = false
    @State private var startTime = Date.now
    @State private var notes = ""
    @State private var pendingDelete: PlannedSession?
    @State private var showingDeleteConfirmation = false
    @State private var message: String?

    private var dayIsEditable: Bool {
        guard let date else { return false }
        return Calendar.current.startOfDay(for: date) >=
            Calendar.current.startOfDay(for: .now)
    }

    private var hasRestDay: Bool {
        day.sessions.contains(where: \.isExplicitRestDay)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                if isEditing {
                    editForm
                } else {
                    dayContents
                }
            }
            .padding(19)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.5))
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "The plan was not changed",
                norwegian: "Planen ble ikke endret"
            ),
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Delete planned workout?",
                norwegian: "Slett planlagt økt?"
            ),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                ATHLTHLocalization.choose(
                    english: "Delete workout", norwegian: "Slett økt"
                ),
                role: .destructive
            ) {
                removeConfirmedWorkout()
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Only the planned workout is removed; completed workout results remain.",
                norwegian: "Kun den planlagte økten slettes. Gjennomførte treningsresultater beholdes."
            ))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(ATHLTHLocalization.choose(
                english: "DAY EDITOR", norwegian: "DAGREDAKTØR"
            ))
            .font(.system(size: 10, weight: .semibold))
            .tracking(2.0)
            .foregroundStyle(ATHLTHStudioStyle.gold)

            Text(date?.formatted(.dateTime.weekday(.wide)) ?? day.title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHStudioStyle.ink)

            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "This plan has no scheduled start date.",
                    norwegian: "Denne planen har ingen startdato."
                ))
                .font(.caption).foregroundStyle(.secondary)
            }
            if !dayIsEditable {
                Label(ATHLTHLocalization.choose(
                    english: "Past days are read-only",
                    norwegian: "Tidligere dager kan ikke redigeres"
                ), systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var dayContents: some View {
        VStack(alignment: .leading, spacing: 14) {
            let workouts = day.sessions.filter { !$0.isExplicitRestDay }
            if day.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 25))
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    Text(ATHLTHLocalization.choose(
                        english: "A clear day. Build a workout here.",
                        norwegian: "En ledig dag. Bygg opp en økt her."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 15))
            } else if hasRestDay {
                Label(ATHLTHLocalization.choose(
                    english: "Planned rest day", norwegian: "Planlagt hviledag"
                ), systemImage: "moon.zzz")
                .font(.headline)
                .foregroundStyle(ATHLTHStudioStyle.ink)
                .padding(.vertical, 10)
                if let rest = day.sessions.first(where: \.isExplicitRestDay) {
                    removeAction(for: rest)
                }
            }

            ForEach(workouts) { workout in
                workoutEntry(workout)
            }

            if dayIsEditable && !hasRestDay {
                Button {
                    if let onCreateAdvanced {
                        onCreateAdvanced()
                    } else {
                        beginNewWorkout()
                    }
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Create workout", norwegian: "Opprett økt"
                    ), systemImage: "plus")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHStudioStyle.ink)

                if !session.savedWorkoutTemplates.isEmpty {
                    Menu {
                        ForEach(session.savedWorkoutTemplates.prefix(30)) { template in
                            Button {
                                insertTemplate(template)
                            } label: {
                                Label(template.title, systemImage: template.kind.systemImage)
                            }
                        }
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Insert from my library",
                            norwegian: "Sett inn fra mitt bibliotek"
                        ), systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if day.sessions.isEmpty {
                    Button {
                        addRestDay()
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Mark as rest day",
                            norwegian: "Marker som hviledag"
                        ), systemImage: "moon.zzz")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            if !dayIsEditable {
                Text(ATHLTHLocalization.choose(
                    english: "Historical workouts can be reviewed but not rewritten here.",
                    norwegian: "Historiske økter kan vises, men ikke overskrives her."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func workoutEntry(_ workout: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: workout.kind.systemImage)
                    .foregroundStyle(ATHLTHStudioStyle.gold)
                    .font(.system(size: 19))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                    HStack(spacing: 8) {
                        if let duration = workout.durationMinutes {
                            Text("\(duration) min")
                        }
                        if let distance = workout.targetDistanceKilometers {
                            Text(String(format: "%.1f km", distance))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if workout.isStructuredWorkout || !workout.exercises.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "\(workout.resolvedWorkoutBlocks.count) workout blocks · \(workout.exercises.count) exercises",
                    norwegian: "\(workout.resolvedWorkoutBlocks.count) øktdeler · \(workout.exercises.count) øvelser"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                if let summary = ATHLTHWorkoutContentSummary.text(for: workout) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(
                    Array(workout.resolvedWorkoutBlocks.prefix(4).enumerated()),
                    id: \.offset
                ) { _, block in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(block.title)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }

                ForEach(workout.exercises.prefix(5)) { exercise in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "dumbbell")
                            .font(.caption2)
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(exercise.embeddedExercise.displayName)
                            .font(.caption)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Text("\(exercise.sets) " + ATHLTHLocalization.choose(
                            english: "sets", norwegian: "sett"
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if canLaunch(workout), let onStartWorkout {
                Button {
                    onStartWorkout(plan.id, workout.id)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Start workout", norwegian: "Start økt"
                    ), systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHStudioStyle.ink)
                .contextMenu {
                    Button {
                        onStartWorkout(plan.id, workout.id)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Start on iPhone / choose device",
                            norwegian: "Start på iPhone / velg enhet"
                        ), systemImage: "iphone")
                    }
                    if let onSendToWatch {
                        Button {
                            onSendToWatch(plan.id, workout.id)
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Send to Apple Watch",
                                norwegian: "Send til Apple Watch"
                            ), systemImage: "applewatch")
                        }
                    }
                    if let onStartAfter {
                        Menu {
                            Button(ATHLTHLocalization.choose(
                                english: "In 5 minutes", norwegian: "Om 5 minutter"
                            )) { onStartAfter(plan.id, workout.id, 300) }
                            Button(ATHLTHLocalization.choose(
                                english: "In 15 minutes", norwegian: "Om 15 minutter"
                            )) { onStartAfter(plan.id, workout.id, 900) }
                            Button(ATHLTHLocalization.choose(
                                english: "In 30 minutes", norwegian: "Om 30 minutter"
                            )) { onStartAfter(plan.id, workout.id, 1800) }
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Start later", norwegian: "Start senere"
                            ), systemImage: "clock")
                        }
                    }
                }
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Hold to send to Watch or delay the session",
                    norwegian: "Hold inne for å sende til Watch eller starte senere"
                ))
            }

            HStack(spacing: 8) {
                if isEditable(workout) {
                    Button {
                        beginEdit(workout)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Quick edit", norwegian: "Hurtigredigering"
                        ), systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    onOpenAdvanced(workout.id)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Full editor", norwegian: "Full redigering"
                    ), systemImage: "arrow.up.right")
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHStudioStyle.gold)
            }
            if isEditable(workout) {
                removeAction(for: workout)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 14))
    }

    private func removeAction(for workout: PlannedSession) -> some View {
        Button(role: .destructive) {
            pendingDelete = workout
            showingDeleteConfirmation = true
        } label: {
            Label(ATHLTHLocalization.choose(
                english: "Remove", norwegian: "Fjern"
            ), systemImage: "trash")
            .font(.caption)
        }
        .buttonStyle(.plain)
        .disabled(!isEditable(workout))
    }

    private func canLaunch(_ workout: PlannedSession) -> Bool {
        !workout.isExplicitRestDay &&
        !session.isPlanSessionSkipped(planID: plan.id, sessionID: workout.id) &&
        !session.isPlanSessionCompleted(
            planID: plan.id, sessionID: workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
    }

    private func isEditable(_ workout: PlannedSession) -> Bool {
        dayIsEditable &&
        !session.isPlanSessionSkipped(planID: plan.id, sessionID: workout.id) &&
        !session.isPlanSessionCompleted(
            planID: plan.id, sessionID: workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
    }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(originalWorkout == nil
                     ? ATHLTHLocalization.choose(english: "New workout", norwegian: "Ny økt")
                     : ATHLTHLocalization.choose(english: "Edit workout", norwegian: "Rediger økt"))
                    .font(.headline)
                Spacer()
                Button {
                    isEditing = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Cancel editing", norwegian: "Avbryt redigering"
                ))
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(english: "Workout name", norwegian: "Navn på økt")
                TextField(kind.title, text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Workout name", norwegian: "Navn på økt"
                    ))
                Text(ATHLTHLocalization.choose(
                    english: "Leave empty to use the activity name.",
                    norwegian: "La feltet stå tomt for å bruke aktivitetens navn."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(english: "Activity", norwegian: "Aktivitet")
                Picker(ATHLTHLocalization.choose(
                    english: "Activity", norwegian: "Aktivitet"
                ), selection: $kind) {
                    ForEach(WorkoutKind.allCases) { choice in
                        Label(choice.title, systemImage: choice.systemImage)
                            .tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .disabled(originalWorkout?.isStructuredWorkout == true ||
                          !(originalWorkout?.exercises.isEmpty ?? true))
                Text(ATHLTHLocalization.choose(
                    english: "Structured exercise types are edited with the full workout editor.",
                    norwegian: "Økttyper med øvelser og intervaller endres i full øktredigering."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Toggle(ATHLTHLocalization.choose(
                english: "Planned duration", norwegian: "Planlagt varighet"
            ), isOn: $hasDuration)
            if hasDuration {
                Stepper(value: $duration, in: 5...360, step: 5) {
                    Text("\(duration) min")
                        .font(.subheadline.weight(.medium))
                }
            }

            if kind == .running || kind == .walking {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel(english: "Target distance (km)", norwegian: "Måldistanse (km)")
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Optional distance", norwegian: "Valgfri distanse"
                        ),
                        value: $distanceKilometers,
                        format: .number
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                }
            }

            Toggle(ATHLTHLocalization.choose(
                english: "Set a start time", norwegian: "Velg starttid"
            ), isOn: $hasStartTime)
            if hasStartTime {
                DatePicker(
                    ATHLTHLocalization.choose(
                        english: "Start", norwegian: "Start"
                    ),
                    selection: $startTime,
                    displayedComponents: .hourAndMinute
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(english: "Workout notes", norwegian: "Notater")
                TextEditor(text: $notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 85)
                    .padding(7)
                    .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
            }

            if let originalWorkout, originalWorkout.isStructuredWorkout ||
                    !originalWorkout.exercises.isEmpty {
                Label(ATHLTHLocalization.choose(
                    english: "Existing intervals, exercises and sets are preserved. Edit them in the full workout editor.",
                    norwegian: "Eksisterende intervaller, øvelser og sett beholdes. Rediger dem i full øktredigering."
                ), systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    saveDraft()
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Save workout", norwegian: "Lagre økt"
                    ), systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHStudioStyle.ink)
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    isEditing = false
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    ))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func fieldLabel(english: String, norwegian: String) -> some View {
        Text(ATHLTHLocalization.choose(english: english, norwegian: norwegian))
            .font(.caption.weight(.semibold))
            .foregroundStyle(ATHLTHStudioStyle.ink)
    }

    private func beginNewWorkout() {
        guard dayIsEditable, !hasRestDay else { return }
        originalWorkout = nil
        expectedVersion = plan.version
        title = ""
        kind = .running
        duration = 45
        hasDuration = true
        distanceKilometers = 0
        hasStartTime = false
        startTime = date ?? .now
        notes = ""
        isEditing = true
    }

    private func beginEdit(_ workout: PlannedSession) {
        guard isEditable(workout) else { return }
        originalWorkout = workout
        expectedVersion = plan.version
        title = workout.title
        kind = workout.kind
        hasDuration = workout.durationMinutes != nil
        duration = min(360, max(5, workout.durationMinutes ?? 45))
        distanceKilometers = workout.targetDistanceKilometers ?? 0
        hasStartTime = workout.scheduledStart != nil
        startTime = workout.scheduledStart ?? (date ?? .now)
        notes = workout.notes ?? ""
        isEditing = true
    }

    private func saveDraft() {
        guard dayIsEditable,
              distanceKilometers.isFinite,
              distanceKilometers >= 0,
              distanceKilometers <= 1_000 else {
            message = ATHLTHLocalization.choose(
                english: "Enter a valid distance or leave it at zero.",
                norwegian: "Oppgi en gyldig distanse, eller la den stå på null."
            )
            return
        }

        let proposedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = proposedTitle.isEmpty ? kind.title : proposedTitle
        guard effectiveTitle.count <= 120 else {
            message = ATHLTHLocalization.choose(
                english: "Workout names must be 120 characters or shorter.",
                norwegian: "Øktnavn kan ikke overstige 120 tegn."
            )
            return
        }
        guard !hasRestDay || originalWorkout != nil else {
            message = ATHLTHLocalization.choose(
                english: "Remove the rest day before adding a workout.",
                norwegian: "Fjern hviledagen før du legger til en økt."
            )
            return
        }

        var draft = originalWorkout ?? PlannedSession(
            id: UUID(),
            title: effectiveTitle,
            kind: kind,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        draft.title = effectiveTitle
        draft.kind = kind
        draft.durationMinutes = hasDuration ? duration : nil
        if kind == .running || kind == .walking {
            draft.targetDistanceKilometers = distanceKilometers > 0 ? distanceKilometers : nil
        } else {
            draft.targetDistanceKilometers = nil
        }
        draft.scheduledStart = hasStartTime ? startTime : nil
        draft.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let success = session.savePlanStudioWorkout(
            draft,
            inPlan: plan.id,
            dayID: day.id,
            editingWorkoutID: originalWorkout?.id,
            expectedPlanVersion: expectedVersion,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        if success {
            isEditing = false
            originalWorkout = nil
        } else {
            message = ATHLTHLocalization.choose(
                english: "The plan changed, this day is in the past, or the workout is already completed. Your draft remains open; review the plan before trying again.",
                norwegian: "Planen ble endret, dagen er passert eller økten er allerede fullført. Utkastet er beholdt; kontroller planen før du prøver igjen."
            )
        }
    }

    private func insertTemplate(_ template: PlannedSession) {
        guard dayIsEditable, !hasRestDay,
              session.trainingPlan(withID: plan.id)?.version == plan.version,
              session.insertSavedWorkoutIntoPlan(
                templateID: template.id,
                planID: plan.id,
                dayID: day.id
              ) else {
            message = ATHLTHLocalization.choose(
                english: "Could not add the saved workout. Check plan date and latest changes.",
                norwegian: "Kunne ikke legge til lagret økt. Kontroller dato og siste endringer."
            )
            return
        }
    }

    private func addRestDay() {
        guard dayIsEditable, day.sessions.isEmpty,
              session.trainingPlan(withID: plan.id)?.version == plan.version else {
            return
        }
        var rest = PlannedSession(
            id: UUID(),
            title: ATHLTHLocalization.choose(
                english: "Rest day", norwegian: "Hviledag"
            ),
            kind: .recovery,
            scheduledStart: nil,
            durationMinutes: nil,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil
        )
        rest.workoutCategory = "rest_day"
        if !session.savePlanStudioWorkout(
            rest,
            inPlan: plan.id,
            dayID: day.id,
            editingWorkoutID: nil,
            expectedPlanVersion: plan.version,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        ) {
            message = ATHLTHLocalization.choose(
                english: "The rest day could not be saved. Reload the plan.",
                norwegian: "Kunne ikke lagre hviledagen. Oppdater planen."
            )
        }
    }

    private func removeConfirmedWorkout() {
        guard let workout = pendingDelete else { return }
        pendingDelete = nil
        guard dayIsEditable,
              session.removePlanStudioWorkout(
                planID: plan.id,
                workoutID: workout.id,
                dayID: day.id,
                expectedVersion: plan.version,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
              ) else {
            message = ATHLTHLocalization.choose(
                english: "The workout could not be deleted. It may be completed or changed.",
                norwegian: "Økten kunne ikke slettes. Den kan være fullført eller endret."
            )
            return
        }
        isEditing = false
    }
}
