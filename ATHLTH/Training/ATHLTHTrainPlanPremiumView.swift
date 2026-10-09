import SwiftUI

/// The Plan tab is a workspace, not a second workout engine.
/// It operates directly on existing TrainingPlan / PlannedSession records.
struct ATHLTHTrainPlanPremiumView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    // Optional deep link from "I dag" or the rebuilt library.
    var highlightedPlanID: UUID? = nil
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
    @State private var openingWorkout: PlannedSession?
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
        VStack(alignment: .leading, spacing: 18) {
            header
            if let plan {
                overview(plan)
                weekWorkspace(plan)
                libraryShortcuts
            } else {
                firstPlanInvitation
                libraryShortcuts
            }
        }
        .foregroundStyle(graphite)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            session.refreshActivePlanForToday()
        }
        .onChange(of: plan?.id) { _, _ in
            selectedWeekIndex = nil
        }
        .onChange(of: highlightedPlanID) { _, next in
            focusedPlanID = next
        }
        .sheet(isPresented: $showingCreation) {
            ATHLTHTrainProgramComposerView { planID in
                focusedPlanID = planID
                selectedWeekIndex = 0
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
        .sheet(item: $openingWorkout) { workout in
            if let plan,
               let day = plan.weeks.flatMap(\.days).first(where: {
                   $0.sessions.contains(where: { $0.id == workout.id })
               }) {
                ATHLTHTrainWorkoutBuilderView(
                    planID: plan.id,
                    dayID: day.id,
                    existingWorkout: workout
                )
            }
        }
        .sheet(isPresented: $showingAIHelp) {
            CoachPlanAdaptationView()
        }
        .sheet(isPresented: Binding(
            get: { editingDayID != nil },
            set: { visible in
                if !visible { editingDayID = nil }
            }
        )) {
            if let plan, let dayID = editingDayID {
                ATHLTHTrainWorkoutBuilderView(
                    planID: plan.id,
                    dayID: dayID
                )
            }
        }
    }

    private var planChooser: some View {
        Menu {
            ForEach(session.trainingPlans) { item in
                Button {
                    focusedPlanID = item.id
                    selectedWeekIndex = nil
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
                    Text("Basic").tag(false)
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
                    "Start with a name and duration. Add your goals and sessions only when you're ready.",
                    "Start med navn og varighet. Velg deretter egne mål og økter – uten at AI eller ferdige opplegg er påkrevd."
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
                    if !summary.isEmpty {
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
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(graphite)
                        .frame(width: 35, height: 35)
                        .background(soft, in: Circle())
                }
                .accessibilityLabel(tr("Plan options", "Planvalg"))
            }

            HStack(spacing: 0) {
                metric("\(current) / \(weeks)", tr("WEEKS", "UKER"))
                Rectangle().fill(line).frame(width: 1, height: 35)
                metric("\(completed) / \(total)", tr("COMPLETED", "FERDIGE"))
                Rectangle().fill(line).frame(width: 1, height: 35)
                metric("\(Int((progress.completionFraction * 100).rounded())) %",
                       tr("SESSIONS", "ØKTER"))
            }

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
                    Text(tr("Weekly schedule", "Treningsuken"))
                        .font(.system(size: 24, weight: .regular, design: .serif))
                }
                Spacer()
                Button { showingEditor = true } label: {
                    Text(tr("Full editor", "Full editor"))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(graphite)
            }

            if let selectedWeek {
                weekPager(plan, week: selectedWeek)

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
                Text(tr("\(week.days.reduce(0) { $0 + $1.sessions.count }) planned workouts",
                        "\(week.days.reduce(0) { $0 + $1.sessions.count }) planlagte økter"))
                    .font(.caption2)
                    .foregroundStyle(secondaryInk)
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
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let monday = mondayCalendar.dateInterval(
            of: .weekOfYear,
            for: first
        )?.start ?? first
        let weekIndex = min(
            max(selectedWeekIndex ?? currentWeekIndex(plan), 0),
            max(plan.weeks.count - 1, 0)
        )
        return calendar.date(
            byAdding: .day,
            value: weekIndex * 7 + min(max(dayIndex - 1, 0), 6),
            to: monday
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
