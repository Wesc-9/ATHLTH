import SwiftUI

/// The Plan tab is a workspace, not a second workout engine.
/// It operates directly on existing TrainingPlan / PlannedSession records.
struct ATHLTHTrainPlanPremiumView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    // Optional deep link from "I dag" or the rebuilt library.
    var highlightedPlanID: UUID? = nil
    // The owning Train tab supplies its existing iPhone/Watch launch flow.
    // Embedded plan previews without that owner remain read-only for launch.
    var onStartWorkout: ((UUID, PlannedSession) -> Void)? = nil
    @State private var focusedPlanID: UUID?

    @AppStorage("athlth.planWorkspace.advancedMode")
    private var advanced = false
    @State private var selectedWeekIndex: Int?
    @State private var showingCreation = false
    @State private var showingMyPlans = false
    @State private var showingTemplates = false
    @State private var showingAllPlans = false
    @State private var showingEditor = false
    @State private var showingProgress = false
    @State private var showingGoals = false
    @State private var showingCoach = false
    @State private var showingRecoveryAdvice = false
    @State private var showingAIHelp = false
    @State private var editingDayID: UUID?
    @State private var editingExistingWorkout: PlannedSession?
    @State private var openingWorkout: PlannedSession?
    @State private var openingWorkoutPlanID: UUID?
    @State private var queuedLaunchPlanID: UUID?
    @State private var queuedLaunchWorkout: PlannedSession?
    @State private var deletingWorkout: PlannedSession?
    @State private var deletingPlanID: UUID?
    @State private var deletingDayID: UUID?
    @State private var deletingPlanVersion: Int?
    @State private var deleteError: String?
    @State private var movingWorkout: PlannedSession?
    @State private var movingPlanID: UUID?
    @State private var movingPlanVersion: Int?
    @State private var moveTargetDate = Date()
    @State private var moveError: String?
    @State private var editingPlan: TrainingPlan?

    private let graphite = Color(red: 0.18, green: 0.18, blue: 0.17)
    private let secondaryInk = Color(red: 0.48, green: 0.46, blue: 0.43)
    private let warmGold = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let line = Color(red: 0.89, green: 0.87, blue: 0.84)
    private let paper = Color(red: 0.986, green: 0.978, blue: 0.963)
    private let soft = Color(red: 0.964, green: 0.951, blue: 0.929)

    private var plan: TrainingPlan? {
        if let id = focusedPlanID ?? highlightedPlanID,
           let selected = session.trainingPlans.first(where: { $0.id == id }) {
            return selected
        }
        return session.activePlan
    }

    private var selectedWeek: TrainingPlanWeek? {
        guard let plan, !plan.weeks.isEmpty else { return nil }
        let index = min(max(selectedWeekIndex ?? currentWeekIndex(plan), 0),
                        plan.weeks.count - 1)
        return plan.weeks[index]
    }

    var body: some View {
        editingSheets
    }

    // Small view fragments prevent SwiftUI's result-builder type checker
    // from having to solve the entire planner and all of its sheets at once.
    // Isolate the move-workout form from the long Plan workspace modifier
    // chain so SwiftUI can type-check it independently on Swift 6.
    @ViewBuilder
    private func movingWorkoutEditor(_ workout: PlannedSession) -> some View {
            if let selectedMovePlanID = movingPlanID,
               let plan = session.trainingPlan(withID: selectedMovePlanID) {
                NavigationStack {
                    Form {
                        Section {
                            if let startDate = plan.startDate,
                               !plan.weeks.isEmpty {
                                let calendar = Calendar.current
                                let first = calendar.startOfDay(for: startDate)
                                let last = calendar.date(
                                    byAdding: .day,
                                    value: plan.weeks.count * 7 - 1,
                                    to: first
                                ) ?? first
                                let earliest = max(
                                    calendar.startOfDay(for: Date()), first
                                )
                                if earliest <= last {
                                    DatePicker(
                                        tr("New workout date", "Ny treningsdato"),
                                        selection: $moveTargetDate,
                                        in: earliest...last,
                                        displayedComponents: .date
                                    )
                                } else {
                                    Text(tr(
                                        "This plan has no upcoming dates.",
                                        "Denne planen har ingen kommende datoer."
                                    ))
                                    .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(tr(
                                    "The plan has no valid date range.",
                                    "Planen mangler en gyldig datoperiode."
                                ))
                                .foregroundStyle(.secondary)
                            }
                        } footer: {
                            Text(tr(
                                "Choose a date within the plan. Completed and skipped workouts cannot be moved.",
                                "Velg en dato innenfor planen. Gjennomførte og hoppede økter kan ikke flyttes."
                            ))
                        }
                        if let moveError {
                            Text(moveError)
                                .foregroundStyle(.red)
                        }
                    }
                    .navigationTitle(tr("Move workout", "Flytt økt"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(tr("Cancel", "Avbryt")) {
                                movingWorkout = nil
                                movingPlanID = nil
                                movingPlanVersion = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("Save", "Lagre")) {
                                if session.movePlanStudioWorkout(
                                    planID: plan.id,
                                    workoutID: workout.id,
                                    targetDate: moveTargetDate,
                                    expectedVersion: movingPlanVersion ?? -1,
                                    healthWorkouts: health.workouts,
                                    strengthHistory: strength.workoutHistory
                                ) {
                                    movingWorkout = nil
                                    movingPlanID = nil
                                    movingPlanVersion = nil
                                    moveError = nil
                                } else {
                                    moveError = tr(
                                        "Could not move this workout. Check the date or refresh the plan.",
                                        "Kunne ikke flytte økten. Kontroller datoen eller oppdater planen."
                                    )
                                }
                            }
                            .fontWeight(.semibold)
                            .disabled({
                                guard let start = plan.startDate,
                                      !plan.weeks.isEmpty else { return true }
                                let calendar = Calendar.current
                                let first = calendar.startOfDay(for: start)
                                let last = calendar.date(
                                    byAdding: .day,
                                    value: plan.weeks.count * 7 - 1,
                                    to: first
                                ) ?? first
                                let target = calendar.startOfDay(for: moveTargetDate)
                                return target < max(first, calendar.startOfDay(for: Date()))
                                    || target > last
                            }())
                        }
                    }
                }
                .presentationDetents([.medium])
            }
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let plan {
                overview(plan)
                weekWorkspace(plan)
                if advanced { libraryShortcuts }
            } else {
                firstPlanInvitation
                libraryShortcuts
            }
        }
        .foregroundStyle(graphite)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            session.refreshActivePlanForToday()
            if let plan {
                advanced = plan.builderProfile?.mode == .advanced
            }
        }
        .onChange(of: plan?.id) { _, _ in
            selectedWeekIndex = nil
            if let plan {
                advanced = plan.builderProfile?.mode == .advanced
            }
        }
        .onChange(of: highlightedPlanID) { _, next in
            focusedPlanID = next
        }
    }

    private var programSheets: some View {
        planContent
        .sheet(isPresented: $showingCreation) {
            ATHLTHTrainProgramComposerView { planID in
                focusedPlanID = planID
                selectedWeekIndex = 0
                if let created = session.trainingPlan(withID: planID) {
                    advanced = created.builderProfile?.mode == .advanced
                }
            }
        }
        .sheet(isPresented: $showingMyPlans) {
            MyTrainingPlansLibraryView()
        }
        .sheet(isPresented: $showingTemplates) {
            TrainingPlanLibraryView()
        }
        .sheet(isPresented: $showingAllPlans) {
            AllTrainingPlansView()
        }
        .sheet(isPresented: $showingProgress) {
            if let plan {
                TrainingPlanProgressDetailView(planID: plan.id)
            }
        }
    }

    private var insightsSheets: some View {
        programSheets
        .sheet(isPresented: $showingGoals) {
            if let plan {
                ATHLTHTrainGoalHubView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingCoach) {
            if let plan {
                ATHLTHTrainProgressionCoachView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingRecoveryAdvice) {
            if let plan {
                ATHLTHTrainRecoveryAdviceView(planID: plan.id)
            }
        }
    }

    private var editingSheets: some View {
        insightsSheets
        .sheet(isPresented: $showingEditor) {
            if let plan {
                ATHLTHTrainWeekBuilderView(
                    planID: plan.id,
                    initialWeekIndex: selectedWeekIndex ?? currentWeekIndex(plan)
                )
            }
        }
        .sheet(item: $editingPlan) { item in
            PlanMetadataEditorView(plan: item)
        }
        .sheet(item: $openingWorkout, onDismiss: {
            // Start only after dismissing details so iOS does not try to
            // present two workout sheets at the same time.
            if let launchPlanID = queuedLaunchPlanID,
               let launchWorkout = queuedLaunchWorkout {
                queuedLaunchPlanID = nil
                queuedLaunchWorkout = nil
                openingWorkoutPlanID = nil
                // Resolve the current record again after the detail sheet
                // closes. A plan may have changed while the sheet was open.
                if let sourcePlan = session.trainingPlan(withID: launchPlanID),
                   let current = sourcePlan.weeks
                        .flatMap(\.days).flatMap(\.sessions)
                        .first(where: { $0.id == launchWorkout.id }),
                   !session.isPlanSessionSkipped(
                        planID: launchPlanID, sessionID: current.id
                   ),
                   !session.isPlanSessionCompleted(
                        planID: launchPlanID,
                        sessionID: current.id,
                        healthWorkouts: health.workouts,
                        strengthHistory: strength.workoutHistory
                   ) {
                    onStartWorkout?(launchPlanID, current)
                }
            }
        }) { workout in
            if let openingWorkoutPlanID,
               let plan = session.trainingPlan(withID: openingWorkoutPlanID),
               let dayID = workoutDayID(workout, plan: plan) {
                if plan.builderProfile?.mode == .advanced {
                    ATHLTHTrainWorkoutBuilderView(
                        planID: plan.id,
                        dayID: dayID,
                        expectedPlanVersion: plan.version,
                        existingWorkout: workout
                    )
                } else {
                    PlannedWorkoutDetailView(
                        planID: plan.id,
                        workout: workout,
                        isHealthCompleted: session.isPlanSessionCompleted(
                            planID: plan.id,
                            sessionID: workout.id,
                            healthWorkouts: health.workouts,
                            strengthHistory: strength.workoutHistory
                        ),
                        simplePresentation: true,
                        onStartWorkout: launchFromWorkoutDetails
                    )
                }
            }
        }
        .confirmationDialog(
            tr("Remove planned workout?", "Fjerne planlagt økt?"),
            isPresented: Binding(
                get: { deletingWorkout != nil },
                set: { if !$0 { clearPendingDeletion() } }
            ),
            titleVisibility: .visible
        ) {
            Button(tr("Remove workout", "Fjern økten"), role: .destructive) {
                if let workout = deletingWorkout,
                   let planID = deletingPlanID,
                   let dayID = deletingDayID,
                   let version = deletingPlanVersion {
                    let removed = session.removePlanStudioWorkout(
                        planID: planID,
                        workoutID: workout.id,
                        dayID: dayID,
                        expectedVersion: version,
                        healthWorkouts: health.workouts,
                        strengthHistory: strength.workoutHistory
                    )
                    if !removed {
                        deleteError = tr(
                            "The workout could not be removed. The plan may have changed.",
                            "Økten kunne ikke fjernes. Planen kan ha blitt endret."
                        )
                    }
                }
                clearPendingDeletion()
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                clearPendingDeletion()
            }
        } message: {
            Text(tr(
                "Only the planned workout is removed. Recorded training history is not deleted.",
                "Bare den planlagte økten fjernes. Registrert treningshistorikk slettes ikke."
            ))
        }
        .alert(
            tr("Could not remove workout", "Kunne ikke fjerne økten"),
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .sheet(item: $movingWorkout) { workout in
            movingWorkoutEditor(workout)
        }
        .sheet(isPresented: $showingAIHelp) {
            CoachPlanAdaptationView()
        }
        .sheet(isPresented: Binding(
            get: { editingDayID != nil },
            set: { visible in
                if !visible {
                    editingDayID = nil
                    editingExistingWorkout = nil
                }
            }
        )) {
            if let plan, let dayID = editingDayID {
                ATHLTHTrainWorkoutBuilderView(
                    planID: plan.id,
                    dayID: dayID,
                    expectedPlanVersion: plan.version,
                    existingWorkout: editingExistingWorkout
                )
            }
        }
    }

    private var launchFromWorkoutDetails: ((UUID, PlannedSession) -> Void)? {
        guard onStartWorkout != nil else { return nil }
        return { planID, workout in
            queuedLaunchPlanID = planID
            queuedLaunchWorkout = workout
            openingWorkout = nil
        }
    }

    private func clearPendingDeletion() {
        deletingWorkout = nil
        deletingPlanID = nil
        deletingDayID = nil
        deletingPlanVersion = nil
    }

    private func workoutDayID(_ workout: PlannedSession, plan: TrainingPlan) -> UUID? {
        for week in plan.weeks {
            for day in week.days where day.sessions.contains(where: { $0.id == workout.id }) {
                return day.id
            }
        }
        return nil
    }

    private var planChooser: some View {
        Menu {
            ForEach(session.trainingPlans) { item in
                Button {
                    focusedPlanID = item.id
                    selectedWeekIndex = nil
                    advanced = item.builderProfile?.mode == .advanced
                } label: {
                    Label(
                        item.title,
                        systemImage: item.id == plan?.id
                            ? "checkmark.circle.fill" : "calendar"
                    )
                }
            }
            Button {
                showingCreation = true
            } label: {
                Label(tr("New program", "Nytt program"), systemImage: "plus")
            }
        } label: {
            HStack(spacing: 6) {
                Text(tr("Choose program", "Velg program"))
                Image(systemName: "chevron.down")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(graphite)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(soft, in: Capsule())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("YOUR PROGRAM", "DITT PROGRAM"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(warmGold)
                    Text(tr("Training plan", "Treningsplan"))
                        .font(.system(size: 34, weight: .regular, design: .serif))
                }
                Spacer()
                Button {
                    showingCreation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 43, height: 43)
                        .background(graphite, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Create training plan", "Opprett treningsplan"))
            }

            if !session.trainingPlans.isEmpty {
                planChooser
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Image(systemName: advanced ? "slider.horizontal.3" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(warmGold)
                Text(
                    advanced
                        ? tr("Precise control", "Full detaljkontroll")
                        : tr("Easy overview", "Enkel planlegging")
                )
                .font(.caption)
                .foregroundStyle(secondaryInk)
                Spacer()
                Picker("", selection: $advanced) {
                    Text(tr("Simple", "Enkel")).tag(false)
                    Text(tr("Advanced", "Avansert")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 174)
                .accessibilityLabel(tr("Plan detail level", "Detaljnivå"))
            }
        }
    }

    private var firstPlanInvitation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image("GoalStrength")
                .resizable()
                .scaledToFill()
                .saturation(0.5)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 18,
                        topTrailingRadius: 18
                    )
                )
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Your next chapter starts here",
                        "Bygg treningen du ønsker deg"))
                    .font(.system(size: 26, weight: .regular, design: .serif))
                Text(tr(
                    "Choose Simple for three quick questions, or Advanced for full control.",
                    "Velg Enkel for tre raske spørsmål, eller Avansert for full kontroll."
                ))
                .font(.subheadline)
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                actionButton(
                    title: tr("Create a plan", "Opprett treningsplan"),
                    icon: "arrow.right"
                ) {
                    showingCreation = true
                }
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 18)
        }
        .surface(line: line)
    }

    private func overview(_ plan: TrainingPlan) -> some View {
        let progress = session.trainingPlanProgress(
            plan,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let total = max(progress.totalSessions, 0)
        let completed = min(max(progress.completedSessions, 0), total)
        let weeks = max(plan.weeks.count, 1)
        let current = min(currentWeekIndex(plan) + 1, weeks)
        let summary = plan.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("TRAINING PROGRAM", "TRENINGSPROGRAM"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.7)
                        .foregroundStyle(warmGold)
                    Text(plan.title)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .lineLimit(2)
                    if advanced && !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(secondaryInk)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 5)
                Menu {
                    Button {
                        editingPlan = plan
                    } label: {
                        Label(tr("Edit details", "Rediger program"), systemImage: "slider.horizontal.3")
                    }
                    Button {
                        showingAllPlans = true
                    } label: {
                        Label(tr("All plans", "Alle planer"), systemImage: "square.stack")
                    }
                    if advanced {
                    Button {
                        showingGoals = true
                    } label: {
                        Label(tr("Goals and progress", "Mål og fremgang"), systemImage: "target")
                    }
                    Button {
                        showingCoach = true
                    } label: {
                        Label(tr("Progression suggestions", "Progresjonsforslag"), systemImage: "arrow.up.forward")
                    }
                    Button {
                        showingRecoveryAdvice = true
                    } label: {
                        Label(tr("Recovery suggestions", "Restitusjonsforslag"), systemImage: "leaf")
                    }
                    Button {
                        showingProgress = true
                    } label: {
                        Label(tr("Analyze", "Analyser"), systemImage: "chart.xyaxis.line")
                    }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(graphite)
                        .frame(width: 35, height: 35)
                        .background(soft, in: Circle())
                }
                .accessibilityLabel(tr("Plan options", "Planvalg"))
            }

            if !advanced {
                Text(tr(
                    "Your plan is ready. Choose a day below to see your workout.",
                    "Planen din er klar. Velg en dag nedenfor for å se økten din."
                ))
                .font(.subheadline)
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }

            if advanced {
            HStack(spacing: 0) {
                metric("\(current) / \(weeks)", tr("WEEKS", "UKER"))
                Rectangle().fill(line).frame(width: 1, height: 35)
                metric("\(completed) / \(total)", tr("COMPLETED", "FERDIGE"))
                Rectangle().fill(line).frame(width: 1, height: 35)
                metric("\(Int((progress.completionFraction * 100).rounded())) %",
                       tr("SESSIONS", "ØKTER"))
            }

            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(warmGold)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Your progress", "Din fremgang"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr(
                            "\(completed) of \(total) workouts completed",
                            "\(completed) av \(total) økter gjennomført"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .padding(13)
                .background(soft, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)

                GeometryReader { geometry in
                    Capsule()
                        .fill(line.opacity(0.55))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(warmGold)
                                .frame(
                                    width: geometry.size.width *
                                        min(max(progress.completionFraction, 0), 1)
                                )
                        }
                }
                .frame(height: 5)
                .accessibilityLabel(tr("Plan progress", "Fremdrift i planen"))
                .accessibilityValue("\(Int((progress.completionFraction * 100).rounded())) %")
            }

            if advanced {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(tr("Workout completion", "Gjennomførte økter"))
                    Spacer()
                    Text("\(completed) av \(total)")
                }
                .font(.caption)
                .foregroundStyle(secondaryInk)

                GeometryReader { geo in
                    Capsule().fill(line.opacity(0.5))
                        .overlay(alignment: .leading) {
                            Capsule().fill(warmGold)
                                .frame(width: geo.size.width *
                                       min(max(progress.completionFraction, 0), 1))
                        }
                }
                .frame(height: 5)
            }

            HStack(spacing: 9) {
                actionButton(
                    title: tr("Edit workouts", "Bygg og rediger økter"),
                    icon: "arrow.right"
                ) { showingEditor = true }
                Button { showingProgress = true } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 16))
                        .foregroundStyle(graphite)
                        .frame(width: 48, height: 45)
                        .background(soft, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("View progress", "Se fremgang"))
            }
            Button {
                showingGoals = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "target")
                        .foregroundStyle(warmGold)
                    Text(tr("Goals and program progress", "Mål og programfremgang"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(graphite)
                .padding(13)
                .background(soft, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)

            Button {
                showingRecoveryAdvice = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "leaf")
                        .foregroundStyle(warmGold)
                    Text(tr("Recovery suggestions", "Forslag til roligere økter"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(graphite)
                .padding(13)
                .background(soft, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)

            Button {
                showingCoach = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.up.forward")
                        .foregroundStyle(warmGold)
                    Text(tr("Progression suggestions", "Forslag til neste belastning"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(graphite)
                .padding(13)
                .background(soft, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            }
        }
        .padding(17)
        .surface(line: line)
    }

    private func weekWorkspace(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("BUILD YOUR WEEK", "PLANLEGG UKEN"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(warmGold)
                    Text(advanced
                         ? tr("Weekly schedule", "Treningsuken")
                         : tr("Your workouts", "Øktene dine"))
                        .font(.system(size: 24, weight: .regular, design: .serif))
                }
                Spacer()
                if advanced {
                Button { showingEditor = true } label: {
                    Text(tr("Full editor", "Full editor"))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(graphite)
                }

            }

            if let selectedWeek {
                if !advanced && (selectedWeekIndex ?? currentWeekIndex(plan)) != currentWeekIndex(plan) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedWeekIndex = currentWeekIndex(plan)
                        }
                    } label: {
                        Label(tr("Back to current week", "Tilbake til denne uken"),
                              systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(warmGold)
                }
                weekPager(plan, week: selectedWeek)

                if advanced {
                    VStack(spacing: 0) {
                        ForEach(selectedWeek.days.sorted(by: {
                            $0.dayIndex < $1.dayIndex
                        })) { day in
                            dayRow(day, plan: plan)
                            if day.dayIndex != 7 {
                                Rectangle()
                                    .fill(line.opacity(0.65))
                                    .frame(height: 0.7)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.horizontal, 13)
                    .surface(line: line)
                } else {
                    simpleWeekRows(selectedWeek, plan: plan)
                }

                if advanced {
                HStack(spacing: 7) {
                    Button { showingEditor = true } label: {
                        Label(tr("Copy or move week", "Kopier eller flytt uke"),
                              systemImage: "square.on.square")
                    }
                    Spacer()
                    if advanced {
                        Button { showingAIHelp = true } label: {
                            Label(tr("AI suggestions", "AI-forslag"),
                                  systemImage: "sparkles")
                        }
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(graphite)
                .padding(.horizontal, 3)
                .padding(.top, 2)
                }
            } else {
                Text(tr("No weeks have been added yet.", "Det er ikke lagt til noen uker ennå."))
                    .font(.subheadline)
                    .foregroundStyle(secondaryInk)
                actionButton(title: tr("Build first week", "Bygg første uke"),
                             icon: "arrow.right") {
                    showingEditor = true
                }
            }
        }
    }

    private func weekPager(
        _ plan: TrainingPlan,
        week: TrainingPlanWeek
    ) -> some View {
        let index = min(max(selectedWeekIndex ?? currentWeekIndex(plan), 0),
                        max(plan.weeks.count - 1, 0))
        let workouts = week.days.flatMap(\.sessions)
        let completedCount = workouts.filter {
            session.isPlanSessionCompleted(
                planID: plan.id,
                sessionID: $0.id,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        }.count
        let skippedCount = workouts.filter {
            session.isPlanSessionSkipped(planID: plan.id, sessionID: $0.id)
        }.count
        let overdueCount = week.days.reduce(0) { total, day in
            let date = planDayDate(day.dayIndex, plan: plan)
            guard date < Calendar.current.startOfDay(for: Date()) else {
                return total
            }
            return total + day.sessions.filter {
                !session.isPlanSessionSkipped(planID: plan.id, sessionID: $0.id) &&
                !session.isPlanSessionCompleted(
                    planID: plan.id, sessionID: $0.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                )
            }.count
        }
        return HStack(spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedWeekIndex = max(index - 1, 0)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 37)
            }
            .disabled(index == 0)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(tr("Week \(index + 1) of \(plan.weeks.count)",
                        "Uke \(index + 1) av \(plan.weeks.count)"))
                    .font(.subheadline.weight(.semibold))
                Text(advanced
                     ? tr("\(workouts.count) planned workouts",
                          "\(workouts.count) planlagte økter")
                     : tr("\(completedCount) of \(workouts.count) completed",
                          "\(completedCount) av \(workouts.count) gjennomført"))
                    .font(.caption2)
                    .foregroundStyle(secondaryInk)
                if !advanced && (skippedCount > 0 || overdueCount > 0) {
                    Text([
                        skippedCount > 0
                            ? tr("\(skippedCount) skipped", "\(skippedCount) hoppet over")
                            : nil,
                        overdueCount > 0
                            ? tr("\(overdueCount) overdue", "\(overdueCount) ikke gjennomført")
                            : nil
                    ].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryInk)
                }
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedWeekIndex = min(index + 1, plan.weeks.count - 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 37)
            }
            .disabled(index >= plan.weeks.count - 1)
        }
        .font(.subheadline)
        .foregroundStyle(graphite)
        .background(soft, in: RoundedRectangle(cornerRadius: 11))
        .buttonStyle(.plain)
    }

    private func simpleWeekRows(
        _ week: TrainingPlanWeek, plan: TrainingPlan
    ) -> some View {
        let days = week.days.filter { !$0.sessions.isEmpty }
            .sorted { $0.dayIndex < $1.dayIndex }
        return VStack(alignment: .leading, spacing: 10) {
            if days.isEmpty {
                Text(tr("No workouts this week", "Ingen økter denne uken"))
                    .font(.subheadline)
                    .foregroundStyle(secondaryInk)
                Button {
                    showingEditor = true
                } label: {
                    Label(tr("Add workout", "Legg til økt"), systemImage: "plus")
                }
            } else {
                ForEach(days) { day in
                    ForEach(day.sessions) { workout in
                        let completed = session.isPlanSessionCompleted(
                            planID: plan.id,
                            sessionID: workout.id,
                            healthWorkouts: health.workouts,
                            strengthHistory: strength.workoutHistory
                        )
                        let skipped = session.isPlanSessionSkipped(
                            planID: plan.id, sessionID: workout.id
                        )
                        let isToday = Calendar.current.isDate(
                            planDayDate(day.dayIndex, plan: plan),
                            inSameDayAs: Date()
                        )
                        VStack(spacing: 0) {
                        Button {
                            openingWorkoutPlanID = plan.id
                            openingWorkout = workout
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: workout.kind.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(kindTint(workout.kind))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        kindTint(workout.kind).opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 13)
                                    )
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(planDayDate(day.dayIndex, plan: plan)
                                        .formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(isToday ? warmGold : secondaryInk)
                                    Text(simpleWorkoutDescription(workout))
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(graphite)
                                        .multilineTextAlignment(.leading)
                                    if let duration = workout.durationMinutes,
                                       duration > 0 {
                                        Label(
                                            tr("About \(duration) min", "Ca. \(duration) min"),
                                            systemImage: "clock"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(secondaryInk)
                                    }
                                    if isToday && !completed && !skipped {
                                        Label(tr("Today", "I dag"),
                                              systemImage: "calendar")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(warmGold)
                                    }
                                    if skipped {
                                        Label(tr("Skipped", "Hoppet over"),
                                              systemImage: "forward.end")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(secondaryInk)
                                    }
                                    if completed {
                                        Label(tr("Completed", "Gjennomført"),
                                              systemImage: "checkmark.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(kindTint(workout.kind))
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(secondaryInk)
                                    .accessibilityHidden(true)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                            if !completed && !skipped &&
                               (workout.isStructuredWorkout ||
                                workout.kind == .running ||
                                workout.kind == .walking ||
                                workout.kind == .strength),
                               let onStartWorkout {
                                Divider()
                                    .overlay(line.opacity(0.55))
                                    .padding(.horizontal, 16)
                                Button {
                                    guard let current = session.trainingPlan(withID: plan.id)?
                                        .weeks.flatMap(\.days).flatMap(\.sessions)
                                        .first(where: { $0.id == workout.id }),
                                          !session.isPlanSessionSkipped(
                                            planID: plan.id, sessionID: current.id
                                          ),
                                          !session.isPlanSessionCompleted(
                                            planID: plan.id,
                                            sessionID: current.id,
                                            healthWorkouts: health.workouts,
                                            strengthHistory: strength.workoutHistory
                                          )
                                    else { return }
                                    onStartWorkout(plan.id, current)
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                        Text(tr("Start workout", "Start økt"))
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(graphite)
                                    .padding(.horizontal, 18)
                                    .frame(minHeight: 49)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(tr(
                                    "Open the existing workout launcher",
                                    "Åpner den vanlige oppstarten av treningsøkter"
                                ))
                            }
                        }
                        .background(
                            isToday ? soft : Color.white.opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(
                                    isToday ? warmGold.opacity(0.32) : line.opacity(0.70),
                                    lineWidth: 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .contextMenu {
                            if !completed &&
                                !workout.isStructuredWorkout &&
                                (workout.kind == .running ||
                                 workout.kind == .walking ||
                                 workout.kind == .strength) &&
                                !session.isPlanSessionSkipped(
                                    planID: plan.id, sessionID: workout.id
                                ), let onStartWorkout {
                                Button {
                                    // A context menu can remain open while the plan
                                    // changes. Launch only the latest persisted session.
                                    if let latestPlan = session.trainingPlan(withID: plan.id),
                                       let current = latestPlan.weeks
                                           .flatMap(\.days).flatMap(\.sessions)
                                           .first(where: { $0.id == workout.id }),
                                       !current.isStructuredWorkout,
                                       !session.isPlanSessionSkipped(
                                           planID: plan.id, sessionID: current.id
                                       ),
                                       !session.isPlanSessionCompleted(
                                           planID: plan.id,
                                           sessionID: current.id,
                                           healthWorkouts: health.workouts,
                                           strengthHistory: strength.workoutHistory
                                       ) {
                                        onStartWorkout(plan.id, current)
                                    }
                                } label: {
                                    Label(tr("Start workout", "Start økt"),
                                          systemImage: "play.fill")
                                }
                            }
                            Button {
                                openingWorkoutPlanID = plan.id
                                openingWorkout = workout
                            } label: {
                                Label(tr("Workout details", "Øktdetaljer"),
                                      systemImage: "info.circle")
                            }
                            Button {
                                editingExistingWorkout = workout
                                editingDayID = day.id
                            } label: {
                                Label(tr("Change workout", "Endre økten"),
                                      systemImage: "slider.horizontal.3")
                            }
                            if !completed &&
                                !session.isPlanSessionSkipped(
                                    planID: plan.id, sessionID: workout.id
                                ) &&
                                planDayDate(day.dayIndex, plan: plan) >=
                                    Calendar.current.startOfDay(for: Date()) {
                                Button {
                                    moveError = nil
                                    moveTargetDate = max(
                                        Calendar.current.startOfDay(for: Date()),
                                        planDayDate(day.dayIndex, plan: plan)
                                    )
                                    movingPlanID = plan.id
                                    movingPlanVersion = plan.version
                                    movingWorkout = workout
                                } label: {
                                    Label(tr("Move to another day", "Flytt til en annen dag"),
                                          systemImage: "calendar.badge.clock")
                                }
                            }
                            if !completed && !skipped &&
                                planDayDate(day.dayIndex, plan: plan) >=
                                    Calendar.current.startOfDay(for: Date()) {
                                Button(role: .destructive) {
                                    deletingWorkout = workout
                                    deletingPlanID = plan.id
                                    deletingDayID = day.id
                                    deletingPlanVersion = plan.version
                                } label: {
                                    Label(tr("Remove from plan", "Fjern fra planen"),
                                          systemImage: "trash")
                                }
                            }
                            if !completed && !skipped {
                                Button {
                                    session.setPlanSessionManuallyCompleted(
                                        planID: plan.id,
                                        sessionID: workout.id,
                                        completed: true
                                    )
                                } label: {
                                    Label(tr("Mark as completed", "Marker som gjennomført"),
                                          systemImage: "checkmark.circle")
                                }
                            } else if session.isPlanSessionManuallyCompleted(
                                planID: plan.id, sessionID: workout.id
                            ) {
                                Button {
                                    session.setPlanSessionManuallyCompleted(
                                        planID: plan.id,
                                        sessionID: workout.id,
                                        completed: false
                                    )
                                } label: {
                                    Label(tr("Undo completion", "Angre fullføring"),
                                          systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                        .accessibilityLabel(
                            "\(simpleWorkoutDescription(workout)), " +
                            (completed
                                ? tr("completed", "gjennomført")
                                : skipped ? tr("skipped", "hoppet over")
                                : isToday ? tr("today", "i dag")
                                          : tr("planned", "planlagt"))
                        )
                        .accessibilityHint(tr(
                            "Opens workout details",
                            "Åpner detaljer om treningsøkten"
                        ))
                        if let onStartWorkout,
                           !completed,
                           !session.isPlanSessionSkipped(
                               planID: plan.id, sessionID: workout.id
                           ),
                           !workout.isStructuredWorkout,
                           (workout.kind == .running ||
                            workout.kind == .walking ||
                            workout.kind == .strength) {
                            Button {
                                guard let persisted = session.trainingPlan(withID: plan.id)?
                                    .weeks.flatMap(\.days).flatMap(\.sessions)
                                    .first(where: { $0.id == workout.id }),
                                    !persisted.isStructuredWorkout,
                                    !session.isPlanSessionSkipped(
                                        planID: plan.id, sessionID: persisted.id
                                    ),
                                    !session.isPlanSessionCompleted(
                                        planID: plan.id, sessionID: persisted.id,
                                        healthWorkouts: health.workouts,
                                        strengthHistory: strength.workoutHistory
                                    )
                                else { return }
                                onStartWorkout(plan.id, persisted)
                            } label: {
                                Label(tr("Start workout", "Start økt"),
                                      systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(graphite)
                                    .padding(.horizontal, 15)
                                    .frame(height: 38)
                                    .background(soft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityHint(tr(
                                "Choose iPhone or Apple Watch to record this workout.",
                                "Velg iPhone eller Apple Watch for å registrere denne økten."
                            ))
                        }
                    }
                }
                Button {
                    showingEditor = true
                } label: {
                    Label(tr("Add workout to week", "Legg til økt i uken"),
                          systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .tint(warmGold)
                .accessibilityHint(tr(
                    "Open the week editor to plan another workout",
                    "Åpner ukeplanleggeren for å legge til en ny økt"
                ))
            }
        }
    }

    private func simpleWorkoutDescription(_ workout: PlannedSession) -> String {
        let activity: String
        switch workout.kind {
        case .walking: activity = tr("Go for a walk", "Gå en tur")
        case .running: activity = tr("Go running", "Ta en løpetur")
        case .strength: activity = tr("Do strength training", "Tren styrke")
        case .mobility: activity = tr("Do mobility exercises", "Tren bevegelighet")
        case .recovery: activity = tr("Move gently", "Beveg deg rolig")
        case .custom: activity = workout.title
        }
        guard let minutes = workout.durationMinutes, minutes > 0 else {
            return activity
        }
        return tr("\(activity) for \(minutes) minutes",
                  "\(activity) i \(minutes) minutter")
    }

    private func dayRow(_ day: TrainingPlanDay, plan: TrainingPlan) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                VStack(spacing: 2) {
                    Text(weekday(day.dayIndex))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(secondaryInk)
                    Text(
                        planDayDate(day.dayIndex, plan: plan)
                            .formatted(.dateTime.day())
                    )
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(graphite)
                }
                .frame(width: 29)

                VStack(alignment: .leading, spacing: 8) {
                    if day.sessions.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.stars")
                                .foregroundStyle(warmGold)
                            Text(tr("Rest day", "Treningsfri"))
                                .foregroundStyle(secondaryInk)
                        }
                        .font(.subheadline)
                        .frame(minHeight: 32, alignment: .leading)
                    } else {
                        ForEach(day.sessions) { workout in
                            Button {
                                openingWorkoutPlanID = plan.id
                                openingWorkout = workout
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 7) {
                                        Image(systemName: workout.kind.systemImage)
                                            .font(.caption)
                                            .foregroundStyle(kindTint(workout.kind))
                                            .frame(width: 24, height: 24)
                                            .background(
                                                kindTint(workout.kind).opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 7)
                                            )
                                        Text(workout.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(graphite)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(secondaryInk)
                                    }
                                    HStack(spacing: 6) {
                                        Text(workout.kind.title)
                                        if let minutes = workout.durationMinutes {
                                            Text("· \(minutes) min")
                                        }
                                        if !workout.exercises.isEmpty {
                                            Text("· \(workout.exercises.count) " +
                                                tr("exercises", "øvelser"))
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(secondaryInk)
                                    if advanced && !workout.exercises.isEmpty {
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(Array(workout.exercises.prefix(3)), id: \.id) {
                                                exercise in
                                                HStack {
                                                    Text(exercise.embeddedExercise.displayName)
                                                        .lineLimit(1)
                                                    Spacer(minLength: 3)
                                                    Text(exercise.compactTargetSummary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            if workout.exercises.count > 3 {
                                                Text(tr("More exercises in editor",
                                                        "Flere øvelser i editor"))
                                            }
                                        }
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(secondaryInk)
                                        .padding(8)
                                        .background(soft,
                                            in: RoundedRectangle(cornerRadius: 9))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)

                Button {
                    editingDayID = day.id
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(graphite)
                        .frame(width: 30, height: 30)
                        .background(soft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    tr("Add workout on \(weekday(day.dayIndex))",
                       "Legg til økt på \(weekday(day.dayIndex))")
                )
            }
            .padding(.vertical, 12)
        }
    }

    private var libraryShortcuts: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(tr("EXPLORE & REUSE", "BRUK OG GJENBRUK"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(warmGold)
                Spacer()
            }
            libraryRow(
                icon: "square.stack.3d.up",
                title: tr("My plans", "Mine planer"),
                subtitle: tr("Saved, upcoming and previous plans",
                             "Lagrede, kommende og tidligere planer")
            ) {
                showingMyPlans = true
            }
            libraryRow(
                icon: "rectangle.stack",
                title: tr("Training templates", "Treningsmaler"),
                subtitle: tr("Find a plan you can personalize",
                             "Finn en ferdig plan som kan tilpasses")
            ) {
                showingTemplates = true
            }
            if plan != nil {
                libraryRow(
                    icon: "sparkles",
                    title: tr("Adapt your plan", "Tilpass med AI"),
                    subtitle: tr("Suggestions only – you approve changes",
                                 "Kun forslag – du godkjenner endringene")
                ) {
                    showingAIHelp = true
                }
            }
        }
    }

    private func libraryRow(
        icon: String, title: String, subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(warmGold)
                    .frame(width: 33)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(graphite)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(secondaryInk)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(secondaryInk)
            }
            .padding(14)
            .surface(line: line)
        }
        .buttonStyle(.plain)
    }

    private func metric(_ value: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(secondaryInk)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButton(
        title: String, icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Spacer(minLength: 0)
                Text(title).lineLimit(1).minimumScaleFactor(0.86)
                Spacer(minLength: 0)
                Image(systemName: icon)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 45)
            .background(
                graphite,
                in: RoundedRectangle(cornerRadius: 11)
            )
        }
        .buttonStyle(.plain)
    }

    private func currentWeekIndex(_ plan: TrainingPlan) -> Int {
        guard let startDate = plan.startDate, !plan.weeks.isEmpty else {
            return 0
        }
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: first, to: today).day ?? 0
        return min(max(days / 7, 0), plan.weeks.count - 1)
    }

    private func planDayDate(
        _ dayIndex: Int,
        plan: TrainingPlan
    ) -> Date {
        let calendar = Calendar.current
        let fallback = calendar.startOfDay(for: Date())
        let first = calendar.startOfDay(for: plan.startDate ?? fallback)
        let weekIndex = min(
            max(selectedWeekIndex ?? currentWeekIndex(plan), 0),
            max(plan.weeks.count - 1, 0)
        )
        // Planned sessions are persisted relative to the program's actual
        // start date, not the Monday of its calendar week.
        return calendar.date(
            byAdding: .day,
            value: weekIndex * 7 + min(max(dayIndex - 1, 0), 6),
            to: first
        ) ?? first
    }

    private func kindTint(_ kind: WorkoutKind) -> Color {
        switch kind {
        case .strength:
            return Color(red: 0.63, green: 0.45, blue: 0.34)
        case .running:
            return Color(red: 0.39, green: 0.49, blue: 0.62)
        case .walking:
            return Color(red: 0.43, green: 0.53, blue: 0.43)
        case .recovery, .mobility:
            return Color(red: 0.52, green: 0.46, blue: 0.63)
        case .custom:
            return warmGold
        }
    }

    private func weekday(_ dayIndex: Int) -> String {
        let norwegian = ["Man", "Tir", "Ons", "Tor", "Fre", "Lør", "Søn"]
        let english = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let index = min(max(dayIndex - 1, 0), 6)
        return tr(english[index], norwegian[index])
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension View {
    func surface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(line, lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.035), radius: 9, y: 4)
    }
}
