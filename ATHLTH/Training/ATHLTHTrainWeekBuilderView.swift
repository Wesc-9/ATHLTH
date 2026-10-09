import SwiftUI

/// Completely rebuilt week/day editor for the Train plan workspace.
/// All writes use existing AppSessionStore persistence APIs.
struct ATHLTHTrainWeekBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @AppStorage("athlth.planWorkspace.advancedMode") private var advanced = false

    let planID: UUID
    @State private var weekIndex: Int
    @State private var selectedDayID: UUID?
    @State private var editorRequest: EditorRequest?
    @State private var removeRequest: RemoveRequest?
    @State private var transferRequest: TransferRequest?
    @State private var showingSavedWorkouts = false

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let muted = Color(red: 0.46, green: 0.44, blue: 0.43)
    private let bronze = Color(red: 0.65, green: 0.53, blue: 0.37)
    private let paper = Color(red: 0.984, green: 0.976, blue: 0.963)
    private let line = Color(red: 0.88, green: 0.86, blue: 0.83)

    init(planID: UUID, initialWeekIndex: Int = 0) {
        self.planID = planID
        _weekIndex = State(initialValue: max(initialWeekIndex, 0))
    }

    private struct EditorRequest: Identifiable {
        let id = UUID()
        let dayID: UUID
        let sessionID: UUID?
    }
    private struct TransferRequest: Identifiable {
        let id = UUID()
        let workoutID: UUID
        let copyInsteadOfMove: Bool
    }

    private struct RemoveRequest: Identifiable {
        let id = UUID()
        let dayID: UUID
        let workoutID: UUID
        let title: String
    }

    private var plan: TrainingPlan? { session.trainingPlan(withID: planID) }

    private var currentWeek: TrainingPlanWeek? {
        guard let plan, !plan.weeks.isEmpty else { return nil }
        return plan.weeks[min(max(weekIndex, 0), plan.weeks.count - 1)]
    }

    private var currentDay: TrainingPlanDay? {
        guard let currentWeek else { return nil }
        return currentWeek.days.first(where: { $0.id == selectedDayID })
            ?? currentWeek.days.sorted(by: { $0.dayIndex < $1.dayIndex }).first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let plan, let week = currentWeek {
                        introduction(plan)
                        weekSelector(plan)
                        daySelector(week)
                        if let day = currentDay {
                            detailForDay(day, plan: plan)
                        }
                    } else {
                        ContentUnavailableView(
                            tr("Program not available", "Fant ikke treningsplanen"),
                            systemImage: "calendar.badge.exclamationmark"
                        )
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(19)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ink)
                }
                ToolbarItem(placement: .principal) {
                    Text("ATHLTH / " + tr("PLAN STUDIO", "PLANSTUDIO"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(ink)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editorRequest) { request in
                ATHLTHTrainWorkoutBuilderView(
                    planID: planID,
                    dayID: request.dayID,
                    existingWorkout: plan?.weeks.flatMap(\.days)
                        .flatMap(\.sessions)
                        .first(where: { $0.id == request.sessionID })
                )
            }
            .sheet(item: $transferRequest) { request in
                ATHLTHTrainSessionTransferView(
                    planID: planID,
                    sessionID: request.workoutID,
                    copyInsteadOfMove: request.copyInsteadOfMove
                )
            }
            .sheet(isPresented: $showingSavedWorkouts) {
                if let dayID = currentDay?.id {
                    ATHLTHTrainSavedWorkoutPickerView(
                        planID: planID,
                        dayID: dayID
                    )
                }
            }
            .alert(item: $removeRequest) { request in
                Alert(
                    title: Text(tr("Remove workout?", "Fjerne treningsøkt?")),
                    message: Text(tr(
                        "Remove \(request.title) from the schedule? Recorded training results are never deleted.",
                        "Fjerne \(request.title) fra planen? Registrert treningshistorikk blir ikke slettet."
                    )),
                    primaryButton: .destructive(Text(tr("Remove", "Fjern"))) {
                        guard !session.isPlanSessionCompleted(
                            planID: planID,
                            sessionID: request.workoutID,
                            healthWorkouts: health.workouts,
                            strengthHistory: strength.workoutHistory
                        ) else { return }
                        session.removeSession(
                            request.workoutID,
                            fromDay: request.dayID,
                            inPlan: planID
                        )
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .preferredColorScheme(.light)
    }

    private func introduction(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("DESIGN YOUR WEEK", "BYGG DIN TRENING"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(bronze)
            Text(plan.title)
                .font(.system(size: 31, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            HStack(spacing: 10) {
                Text(tr("Workouts, rest days and individual targets",
                        "Økter, hviledager og individuelle treningsmål"))
                    .font(.caption)
                    .foregroundStyle(muted)
                Spacer(minLength: 0)
                Picker("", selection: $advanced) {
                    Text("Basic").tag(false)
                    Text(tr("Advanced", "Avansert")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 155)
            }
        }
    }

    private func weekSelector(_ plan: TrainingPlan) -> some View {
        HStack(spacing: 14) {
            Button {
                weekIndex = max(weekIndex - 1, 0)
                selectedDayID = nil
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 43)
            }
            .disabled(weekIndex <= 0)
            Spacer()
            VStack(spacing: 4) {
                Text(tr("WEEK \(weekIndex + 1)", "UKE \(weekIndex + 1)"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(bronze)
                Text("\(weekIndex + 1) / \(plan.weeks.count)")
                    .font(.system(size: 23, weight: .regular, design: .serif))
                    .monospacedDigit()
            }
            Spacer()
            Button {
                weekIndex = min(weekIndex + 1, plan.weeks.count - 1)
                selectedDayID = nil
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 43)
            }
            .disabled(weekIndex >= plan.weeks.count - 1)
        }
        .font(.subheadline)
        .foregroundStyle(ink)
        .padding(9)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15).stroke(line, lineWidth: 0.7)
        }
    }

    private func daySelector(_ week: TrainingPlanWeek) -> some View {
        HStack(spacing: 5) {
            ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                let chosen = currentDay?.id == day.id
                Button {
                    selectedDayID = day.id
                } label: {
                    VStack(spacing: 7) {
                        Text(dayName(day.dayIndex))
                            .font(.system(size: 10, weight: .semibold))
                        Text(dayDate(day.dayIndex).formatted(.dateTime.day()))
                            .font(.system(size: 20, weight: .regular, design: .serif))
                        Capsule()
                            .fill(day.sessions.isEmpty ? Color.clear : bronze)
                            .frame(width: 15, height: 3)
                    }
                    .foregroundStyle(chosen ? .white : ink)
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .background(chosen ? ink : .white,
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    private func detailForDay(_ day: TrainingPlanDay, plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("DAY \(day.dayIndex)", "DAG \(day.dayIndex)"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(bronze)
                    Text(fullDayName(day.dayIndex))
                        .font(.system(size: 25, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                Text("\(day.sessions.count) " + tr("workouts", "økter"))
                    .font(.caption)
                    .foregroundStyle(muted)
            }

            if day.sessions.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 25, weight: .ultraLight))
                        .foregroundStyle(bronze)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr("Rest day", "Treningsfri"))
                            .font(.system(size: 19, weight: .regular, design: .serif))
                        Text(tr("No session scheduled. Add one whenever you want.",
                                "Ingen planlagt økt. Legg til når du ønsker."))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                }
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
            }

            ForEach(day.sessions) { workout in
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: workout.kind.systemImage)
                            .font(.system(size: 19, weight: .light))
                            .foregroundStyle(bronze)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.title)
                                .font(.system(size: 20, weight: .regular, design: .serif))
                            Text(workout.kind.title
                                + " · \(workout.durationMinutes ?? 0) min")
                                .font(.caption)
                                .foregroundStyle(muted)
                        }
                        Spacer()
                        Menu {
                            Button {
                                editorRequest = .init(
                                    dayID: day.id, sessionID: workout.id
                                )
                            } label: {
                                Label(tr("Edit", "Rediger"), systemImage: "pencil")
                            }
                            Button {
                                transferRequest = .init(
                                    workoutID: workout.id,
                                    copyInsteadOfMove: true
                                )
                            } label: {
                                Label(tr("Copy to a day", "Kopier til en dag"),
                                      systemImage: "square.on.square")
                            }
                            Button {
                                transferRequest = .init(
                                    workoutID: workout.id,
                                    copyInsteadOfMove: false
                                )
                            } label: {
                                Label(tr("Move to a day", "Flytt til en dag"),
                                      systemImage: "calendar.badge.clock")
                            }
                            .disabled(isCompleted(workout.id))
                            Button(role: .destructive) {
                                removeRequest = .init(
                                    dayID: day.id,
                                    workoutID: workout.id,
                                    title: workout.title
                                )
                            } label: {
                                Label(tr("Remove", "Fjern"), systemImage: "trash")
                            }
                            .disabled(isCompleted(workout.id))
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(ink)
                                .frame(width: 35, height: 35)
                        }
                    }

                    if workout.kind == .strength && !workout.exercises.isEmpty {
                        ForEach(workout.exercises.prefix(8)) { exercise in
                            HStack {
                                Text(exercise.embeddedExercise.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(exercise.compactTargetSummary)
                                    .font(.caption2)
                                    .foregroundStyle(muted)
                                    .lineLimit(1)
                            }
                        }
                    } else if workout.kind == .running || workout.kind == .walking {
                        HStack(spacing: 12) {
                            if let distance = workout.targetDistanceKilometers {
                                Label("\(distance.formatted()) km", systemImage: "figure.run")
                            }
                            if let pace = workout.targetPaceSecondsPerKilometer {
                                Label("\(Int(pace) / 60):\(String(format: "%02d", Int(pace) % 60))/km",
                                      systemImage: "speedometer")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(muted)
                    }

                    Button {
                        editorRequest = .init(dayID: day.id, sessionID: workout.id)
                    } label: {
                        HStack {
                            Text(tr("Edit complete workout", "Rediger hele økten"))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                        .padding(.top, 7)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(line, lineWidth: 0.7)
                }
            }

            Button {
                editorRequest = .init(dayID: day.id, sessionID: nil)
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text(tr("Add a training session", "Legg til treningsøkt"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(16)
                .background(ink, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)

            Button {
                showingSavedWorkouts = true
            } label: {
                HStack {
                    Image(systemName: "books.vertical")
                        .foregroundStyle(bronze)
                    Text(tr("Use a saved workout", "Bruk en lagret økt"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .padding(15)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(line, lineWidth: 0.7)
                }
            }
            .buttonStyle(.plain)

            if advanced {
                Label(tr(
                    "Planned sessions remain separate from completed results. Changing future workouts will not rewrite your training history.",
                    "Planlagte økter og gjennomført trening lagres separat. Endringer i planen overskriver ikke treningshistorikken."
                ), systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(muted)
            }
        }
    }

    private func isCompleted(_ workoutID: UUID) -> Bool {
        session.isPlanSessionCompleted(
            planID: planID,
            sessionID: workoutID,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
    }

    private func dayDate(_ index: Int) -> Date {
        guard let plan, let start = plan.startDate else { return Date() }
        return Calendar.current.date(
            byAdding: .day,
            value: weekIndex * 7 + index - 1,
            to: Calendar.current.startOfDay(for: start)
        ) ?? start
    }

    private func dayName(_ index: Int) -> String {
        let no = ["Man", "Tir", "Ons", "Tor", "Fre", "Lør", "Søn"]
        let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let position = min(max(index - 1, 0), 6)
        return tr(en[position], no[position])
    }
    private func fullDayName(_ index: Int) -> String {
        let no = ["Mandag", "Tirsdag", "Onsdag", "Torsdag", "Fredag", "Lørdag", "Søndag"]
        let en = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let position = min(max(index - 1, 0), 6)
        return tr(en[position], no[position])
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

/// Workouts have a single data format for Basic and Advanced.
/// Advanced reveals individual set targets without clearing hidden values.
struct ATHLTHTrainWorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @AppStorage("athlth.planWorkspace.advancedMode") private var advanced = false

    let planID: UUID
    let dayID: UUID
    let existingWorkout: PlannedSession?

    @State private var draft: PlannedSession
    @State private var showExerciseSearch = false
    @State private var showRunningTemplates = false
    @State private var showIntervalComposer = false
    @State private var scheduled = false
    @State private var clockTime = Date()
    @State private var errorMessage: String?
    @State private var detailExerciseID: UUID?

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let bronze = Color(red: 0.65, green: 0.53, blue: 0.37)
    private let muted = Color(red: 0.46, green: 0.44, blue: 0.43)
    private let paper = Color(red: 0.984, green: 0.976, blue: 0.963)
    private let line = Color(red: 0.88, green: 0.86, blue: 0.83)

    init(planID: UUID, dayID: UUID, existingWorkout: PlannedSession? = nil) {
        self.planID = planID
        self.dayID = dayID
        self.existingWorkout = existingWorkout
        _draft = State(initialValue: existingWorkout ?? PlannedSession(
            id: UUID(), title: "", kind: .strength,
            scheduledStart: nil, durationMinutes: 50,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: nil
        ))
        _scheduled = State(initialValue: existingWorkout?.scheduledStart != nil)
        _clockTime = State(initialValue: existingWorkout?.scheduledStart ?? Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heading
                        information
                        if draft.kind == .strength || draft.kind == .custom {
                            strengthEditing
                        } else if draft.kind == .running || draft.kind == .walking {
                            runningEditing
                        }
                        notesEditing
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
                footer
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Workout builder", "Øktbygger"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .sheet(isPresented: $showExerciseSearch) {
                ATHLTHTrainExercisePicker { exercise in
                    let newExercise = PlannedExercise(
                        id: UUID(),
                        exerciseID: exercise.exercise.id,
                        embeddedExercise: exercise.exercise.snapshot,
                        sets: 3,
                        reps: 10,
                        targetWeightKilograms: nil,
                        targetRPE: nil,
                        restSeconds: 90,
                        notes: nil
                    )
                    draft.exercises.append(newExercise)
                    detailExerciseID = newExercise.id
                    showExerciseSearch = false
                }
            }
            .sheet(isPresented: $showIntervalComposer) {
                ATHLTHTrainIntervalComposerView(
                    initial: draft.runningWorkout
                ) { template in
                    draft.runningWorkout = template
                    draft.runningWorkouts = [template]
                    if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        draft.title = template.title
                    }
                }
            }
            .sheet(isPresented: $showRunningTemplates) {
                NavigationStack {
                    List(runningLibrary.allTemplates) { template in
                        Button {
                            draft.runningWorkout = template
                            draft.runningWorkouts = [template]
                            draft.title = template.title
                            showRunningTemplates = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.title)
                                Text(template.type.title)
                                    .font(.caption)
                                    .foregroundStyle(muted)
                            }
                        }
                        .foregroundStyle(ink)
                    }
                    .navigationTitle(tr("Running workouts", "Løpeøkter"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(tr("Close", "Lukk")) {
                                showRunningTemplates = false
                            }
                        }
                    }
                }
            }
            .alert(tr("Could not save workout", "Kunne ikke lagre økten"),
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("BUILD YOUR SESSION", "BYGG DIN ØKT"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(bronze)
            Text(existingWorkout == nil
                 ? tr("A workout, your way.", "Din økt. Dine valg.")
                 : tr("Perfect the details.", "Finjuster økten."))
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            HStack {
                Text(tr("Detail level", "Detaljnivå"))
                    .font(.caption)
                    .foregroundStyle(muted)
                Spacer()
                Picker("", selection: $advanced) {
                    Text("Basic").tag(false)
                    Text(tr("Advanced", "Avansert")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 184)
            }
            .padding(12)
            .editorSurface(line: line)
        }
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(tr("About the session", "Om økten"))
            TextField(tr("Workout name", "Navn på økten"), text: $draft.title)
                .padding(13)
                .editorSurface(line: line)
            Picker(tr("Activity", "Treningsform"), selection: $draft.kind) {
                ForEach(WorkoutKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage).tag(kind)
                }
            }
            .tint(ink)
            .padding(13)
            .editorSurface(line: line)
            durationEditing

            if advanced {
                Toggle(tr("Set workout time", "Angi tidspunkt"), isOn: $scheduled)
                    .tint(bronze)
                if scheduled {
                    DatePicker(tr("Start", "Start"), selection: $clockTime,
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .tint(ink)
                }
            }
        }
    }

    private var durationEditing: some View {
        HStack {
            Label(tr("Duration", "Varighet"), systemImage: "clock")
                .font(.subheadline.weight(.medium))
            Spacer()
            Stepper(
                "\(draft.durationMinutes ?? 45) min",
                value: Binding(
                    get: { draft.durationMinutes ?? 45 },
                    set: { draft.durationMinutes = $0 }
                ),
                in: 5...240, step: 5
            )
            .font(.caption)
            .fixedSize()
        }
        .foregroundStyle(ink)
        .padding(13)
        .editorSurface(line: line)
    }

    private var strengthEditing: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle(tr("Exercises", "Øvelser"))
                Spacer()
                Text("\(draft.exercises.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(muted)
            }

            ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                exerciseRow(index: index, exercise: exercise)
            }

            Button {
                showExerciseSearch = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text(tr("Add exercise from library", "Legg til øvelse fra biblioteket"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .padding(15)
                .editorSurface(line: line)
            }
            .buttonStyle(.plain)

            if draft.exercises.isEmpty {
                Text(tr("Begin with your favorite exercises or build your own structure.",
                        "Start med favorittøvelsene dine og bygg opp økten slik du ønsker."))
                    .font(.caption)
                    .foregroundStyle(muted)
            }
        }
    }

    private func exerciseRow(index: Int, exercise: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(index + 1). \(exercise.embeddedExercise.displayName)")
                        .font(.subheadline.weight(.semibold))
                    Text(exercise.compactTargetSummary)
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer(minLength: 8)
                Menu {
                    Button {
                        detailExerciseID = detailExerciseID == exercise.id
                            ? nil : exercise.id
                    } label: {
                        Label(tr("Edit targets", "Rediger sett"),
                              systemImage: "slider.horizontal.3")
                    }
                    Button {
                        let removed = draft.exercises.remove(at: index)
                        if detailExerciseID == removed.id {
                            detailExerciseID = nil
                        }
                    } label: {
                        Label(tr("Remove exercise", "Fjern øvelse"),
                              systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(ink)
                        .frame(width: 35, height: 30)
                }
            }

            if detailExerciseID == exercise.id {
                targetsEditor(index: index, exercise: exercise)
            } else {
                Button {
                    detailExerciseID = exercise.id
                } label: {
                    HStack {
                        Text(tr("Edit sets and load", "Rediger sett og belastning"))
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .editorSurface(line: line)
    }

    private func targetsEditor(index: Int, exercise: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("Sets", "Sett"))
                    .font(.caption)
                    .foregroundStyle(muted)
                Spacer()
                Stepper(
                    "\(draft.exercises[index].sets)",
                    value: Binding(
                        get: { draft.exercises[index].sets },
                        set: { number in
                            draft.exercises[index].sets = number
                            if draft.exercises[index].setTargets != nil {
                                draft.exercises[index].setTargets =
                                    Array(draft.exercises[index].resolvedSetTargets
                                        .prefix(number))
                            }
                        }
                    ), in: 1...20
                )
                .font(.caption)
                .fixedSize()
            }

            if exercise.hasIndividualSetTargets && !advanced {
                Label(tr(
                    "Individual targets are preserved. Switch to Advanced to change them.",
                    "Ulike settmål er bevart. Bytt til Avansert for å redigere hvert sett."
                ), systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(muted)
            } else if advanced {
                ForEach(0..<max(exercise.sets, 1), id: \.self) { setIndex in
                    individualSetEditor(exerciseIndex: index, setIndex: setIndex)
                }
            } else {
                HStack {
                    Stepper(
                        "\(exercise.reps ?? 10) " + tr("reps", "reps"),
                        value: Binding(
                            get: { draft.exercises[index].reps ?? 10 },
                            set: { draft.exercises[index].reps = $0 }
                        ), in: 1...100
                    )
                    .font(.caption)
                    Spacer()
                    Stepper(
                        "\((exercise.targetWeightKilograms ?? 0).formatted()) kg",
                        value: Binding(
                            get: { draft.exercises[index].targetWeightKilograms ?? 0 },
                            set: { draft.exercises[index].targetWeightKilograms = $0 }
                        ), in: 0...500, step: 1
                    )
                    .font(.caption)
                }
            }
        }
    }

    private func individualSetEditor(
        exerciseIndex: Int, setIndex: Int
    ) -> some View {
        let targets = draft.exercises[exerciseIndex].resolvedSetTargets
        guard targets.indices.contains(setIndex) else {
            return AnyView(EmptyView())
        }
        let target = targets[setIndex]
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("SET \(setIndex + 1)", "SETT \(setIndex + 1)"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(bronze)
                HStack {
                    Stepper(
                        "\(target.reps ?? 10) reps",
                        value: setIntBinding(exerciseIndex, setIndex, \.reps, fallback: 10),
                        in: 1...100
                    )
                    .font(.caption)
                    Spacer()
                    Stepper(
                        "\((target.weightKilograms ?? 0).formatted()) kg",
                        value: setDoubleBinding(exerciseIndex, setIndex,
                                                \.weightKilograms, fallback: 0),
                        in: 0...500, step: 0.5
                    )
                    .font(.caption)
                }
                HStack {
                    Stepper(
                        "RIR \((target.targetRIR ?? 2).formatted())",
                        value: setDoubleBinding(exerciseIndex, setIndex,
                                                \.targetRIR, fallback: 2),
                        in: 0...8, step: 0.5
                    )
                    .font(.caption)
                    Spacer()
                    Stepper(
                        "\(target.restSeconds ?? 90)s " + tr("rest", "pause"),
                        value: setIntBinding(exerciseIndex, setIndex,
                                             \.restSeconds, fallback: 90),
                        in: 0...600, step: 15
                    )
                    .font(.caption)
                }
                Toggle(
                    tr("Warm-up set", "Oppvarmingssett"),
                    isOn: Binding(
                        get: {
                            draft.exercises[exerciseIndex].resolvedSetTargets[setIndex]
                                .isWarmUp ?? false
                        },
                        set: { newValue in
                            mutateSet(exerciseIndex, setIndex) {
                                $0.isWarmUp = newValue
                                $0.setType = newValue ? .warmUp : .work
                            }
                        }
                    )
                )
                .tint(bronze)
                .font(.caption)
            }
            .padding(12)
            .background(paper, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    private func mutateSet(
        _ exerciseIndex: Int,
        _ setIndex: Int,
        _ change: (inout PlannedExerciseSetTarget) -> Void
    ) {
        guard draft.exercises.indices.contains(exerciseIndex) else { return }
        var exercise = draft.exercises[exerciseIndex]
        var targets = exercise.resolvedSetTargets
        guard targets.indices.contains(setIndex) else { return }
        change(&targets[setIndex])
        exercise.setTargets = targets
        if let first = targets.first {
            exercise.reps = first.reps
            exercise.targetWeightKilograms = first.weightKilograms
            exercise.restSeconds = first.restSeconds
            exercise.targetRIR = first.targetRIR
        }
        draft.exercises[exerciseIndex] = exercise
    }

    private func setIntBinding(
        _ exercise: Int, _ set: Int,
        _ key: WritableKeyPath<PlannedExerciseSetTarget, Int?>,
        fallback: Int
    ) -> Binding<Int> {
        Binding(
            get: { draft.exercises[exercise].resolvedSetTargets[set][keyPath: key] ?? fallback },
            set: { value in
                mutateSet(exercise, set) { $0[keyPath: key] = value }
            }
        )
    }

    private func setDoubleBinding(
        _ exercise: Int, _ set: Int,
        _ key: WritableKeyPath<PlannedExerciseSetTarget, Double?>,
        fallback: Double
    ) -> Binding<Double> {
        Binding(
            get: { draft.exercises[exercise].resolvedSetTargets[set][keyPath: key] ?? fallback },
            set: { value in
                mutateSet(exercise, set) { $0[keyPath: key] = value }
            }
        )
    }

    private var runningEditing: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(tr("Running targets", "Løpemål"))
            HStack {
                Label(tr("Distance", "Distanse"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Spacer()
                Stepper(
                    "\((draft.targetDistanceKilometers ?? 5).formatted()) km",
                    value: Binding(
                        get: { draft.targetDistanceKilometers ?? 5 },
                        set: { draft.targetDistanceKilometers = $0 }
                    ),
                    in: 0...200,
                    step: 0.5
                )
                .fixedSize()
            }
            .font(.subheadline)
            .padding(13)
            .editorSurface(line: line)

            if draft.kind == .running {
                Button { showIntervalComposer = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "repeat")
                            .foregroundStyle(bronze)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Build your intervals", "Bygg løpeintervaller"))
                                .font(.subheadline.weight(.semibold))
                            Text(tr("Warm-up, intervals, pace and recovery",
                                    "Oppvarming, drag, fart og pauser"))
                                .font(.caption)
                                .foregroundStyle(muted)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(ink)
                    .padding(14)
                    .editorSurface(line: line)
                }
                .buttonStyle(.plain)

                if let structured = draft.runningWorkout,
                   !structured.blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("CURRENT STRUCTURE", "VALGT ØKTSTRUKTUR"))
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.25)
                            .foregroundStyle(bronze)
                        ForEach(structured.blocks) { block in
                            HStack(alignment: .firstTextBaseline) {
                                Text(block.title)
                                    .font(.caption.weight(.medium))
                                Spacer(minLength: 5)
                                Text("\(block.repetitions) × "
                                      + (block.work.measure == .distance
                                        ? "\(Int(block.work.distanceMeters ?? 0)) m"
                                        : "\(Int((block.work.durationSeconds ?? 0)/60)) min"))
                                    .font(.caption)
                                    .foregroundStyle(muted)
                            }
                        }
                    }
                    .padding(13)
                    .editorSurface(line: line)
                }

                Button { showRunningTemplates = true } label: {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(bronze)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Choose a saved running workout",
                                    "Velg lagret løpeøkt"))
                                .font(.subheadline.weight(.semibold))
                            if let selected = draft.runningWorkout {
                                Text(selected.title)
                                    .font(.caption)
                                    .foregroundStyle(muted)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(ink)
                    .padding(14)
                    .editorSurface(line: line)
                }
                .buttonStyle(.plain)
            }

            if advanced {
                HStack {
                    Text(tr("Target pace", "Måltempo"))
                        .font(.subheadline)
                    Spacer()
                    Stepper(
                        paceLabel(draft.targetPaceSecondsPerKilometer ?? 330),
                        value: Binding(
                            get: { Int(draft.targetPaceSecondsPerKilometer ?? 330) },
                            set: { draft.targetPaceSecondsPerKilometer = Double($0) }
                        ),
                        in: 180...1200,
                        step: 5
                    )
                    .fixedSize()
                }
                .padding(13)
                .editorSurface(line: line)
            }
        }
    }

    private func paceLabel(_ value: Double) -> String {
        let s = Int(value)
        return "\(s / 60):\(String(format: "%02d", s % 60))/km"
    }

    private var notesEditing: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle(tr("Session notes", "Øktnotater"))
            TextField(
                tr("What matters most in this workout?",
                   "Hva er viktig under denne økten?"),
                text: Binding(
                    get: { draft.notes ?? "" },
                    set: { draft.notes = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(2...4)
            .padding(13)
            .editorSurface(line: line)
        }
    }

    private var footer: some View {
        Button(action: save) {
            HStack {
                Spacer()
                Text(tr("Save workout", "Lagre treningsøkt"))
                Spacer()
                Image(systemName: "checkmark")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(height: 49)
            .padding(.horizontal, 16)
            .background(ink, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.white)
        .overlay(alignment: .top) {
            Rectangle().fill(line).frame(height: 0.7)
        }
    }

    private func save() {
        guard let plan = session.trainingPlan(withID: planID),
              let location = plan.weeks.enumerated()
                .compactMap({ weekOffset, week -> (Int, Int)? in
                    guard let index = week.days.firstIndex(where: { $0.id == dayID }) else {
                        return nil
                    }
                    return (weekOffset, index)
                }).first,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            errorMessage = tr("Workout could not be found.",
                            "Kunne ikke finne treningsdagen.")
            return
        }

        let (weekIndex, dayIndex) = location
        var updated = draft
        let day = plan.weeks[weekIndex].days[dayIndex]
        if scheduled, let start = plan.startDate {
            let calendar = Calendar.current
            let intended = calendar.date(
                byAdding: .day,
                value: weekIndex * 7 + day.dayIndex - 1,
                to: calendar.startOfDay(for: start)
            ) ?? start
            let components = calendar.dateComponents([.hour, .minute], from: clockTime)
            updated.scheduledStart = calendar.date(
                bySettingHour: components.hour ?? 18,
                minute: components.minute ?? 0,
                second: 0,
                of: intended
            )
        } else if !scheduled {
            updated.scheduledStart = nil
        }

        if existingWorkout != nil {
            session.updateSession(updated, inPlan: planID)
        } else {
            session.addSession(updated, toDay: dayID, inPlan: planID)
        }
        dismiss()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .regular, design: .serif))
            .foregroundStyle(ink)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

/// Contextual access to the existing exercise data, not a legacy library UI.
private struct ATHLTHTrainExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ExerciseLibraryStore

    let onSelect: (ExerciseLibraryEntry) -> Void
    @State private var search = ""

    private var results: [ExerciseLibraryEntry] {
        Array(library.search(query: search).prefix(75))
    }

    var body: some View {
        NavigationStack {
            List(results) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "dumbbell")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                            Text(item.bodyPart ?? item.category ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                    }
                    .foregroundStyle(.primary)
                }
            }
            .searchable(
                text: $search,
                prompt: ATHLTHLocalization.choose(
                    english: "Search exercises or muscle groups",
                    norwegian: "Søk etter øvelse eller muskelgruppe"
                )
            )
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Add exercise", norwegian: "Legg til øvelse"
            ))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")) {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

private extension View {
    func editorSurface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(line, lineWidth: 0.7)
            }
    }
}
