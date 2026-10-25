import SwiftUI

/// Phase 1 of Train / Plan. This is deliberately a new presentation layer:
/// the existing planner, workout editor and recording engines remain intact.
struct ATHLTHTrainPlanRebuildView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore

    @State private var chosenWeekID: UUID?
    @State private var expandedDayIDs: Set<UUID> = []
    @State private var selectedWorkout: PlannedSession?
    @State private var workoutPendingMove: PlannedSession?
    @State private var workoutPendingSkip: PlannedSession?
    @State private var dayForNewWorkout: TrainingPlanDay?
    @State private var showingPlanLibrary = false
    @State private var showingPlanEditor = false
    @State private var showingWeekCopy = false
    @State private var showingStandaloneEditor = false
    @State private var showingCreatePlan = false

    private var plan: TrainingPlan? { session.activePlan }

    private var selectedWeek: TrainingPlanWeek? {
        guard let plan else { return nil }
        return plan.weeks.first { $0.id == chosenWeekID }
            ?? plan.weeks.first { week in
                guard let start = plan.startDate else { return false }
                let day = Calendar.current.dateComponents(
                    [.day],
                    from: Calendar.current.startOfDay(for: start),
                    to: Calendar.current.startOfDay(for: Date())
                ).day ?? -1
                return day >= (week.weekNumber - 1) * 7 &&
                    day < week.weekNumber * 7
            }
            ?? plan.weeks.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let plan {
                planHeader(plan)
                if let week = selectedWeek {
                    weekSelector(plan, selected: week)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "YOUR WEEK",
                                norwegian: "DIN UKE"
                            ))
                            .font(.caption2.weight(.bold))
                            .tracking(1.7)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            Spacer()
                            Text("\(week.days.reduce(0) { $0 + $1.sessions.count }) økter")
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "Open a free day to plan a workout or mark it as a rest day.",
                            norwegian: "Åpne en ledig dag for å planlegge en økt eller velge hviledag."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        ForEach(week.days.sorted { $0.dayIndex < $1.dayIndex }) { day in
                            dayRow(day, week: week, plan: plan)
                        }
                    }
                }
                standaloneSection
            } else {
                emptyPlanView
                standaloneSection
            }
        }
        .onChange(of: plan?.id) { _, _ in
            chosenWeekID = nil
            expandedDayIDs = []
        }
        .sheet(item: $selectedWorkout) { workout in
            if let plan {
                PlannedWorkoutDetailView(
                    planID: plan.id,
                    workout: workout,
                    isHealthCompleted: false
                )
                .environmentObject(session)
            }
        }
        .sheet(item: $workoutPendingMove) { workout in
            if let plan {
                ATHLTHMovePlannedWorkoutSheet(plan: plan, workout: workout)
                    .environmentObject(session)
            }
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Skip this planned workout?",
                norwegian: "Hoppe over denne planlagte økten?"
            ),
            isPresented: Binding(
                get: { workoutPendingSkip != nil },
                set: { if !$0 { workoutPendingSkip = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Skip workout",
                norwegian: "Hopp over økten"
            )) {
                if let workout = workoutPendingSkip,
                   let planID = plan?.id,
                   canEditOccurrence(workout, planID: planID) {
                    session.setPlanSessionSkipped(
                        planID: planID, sessionID: workout.id, skipped: true
                    )
                }
                workoutPendingSkip = nil
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel",
                norwegian: "Avbryt"
            ), role: .cancel) { workoutPendingSkip = nil }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "This does not remove the workout from your plan or erase any recorded activity.",
                norwegian: "Dette sletter ikke økten fra planen eller registrert treningshistorikk."
            ))
        }
        .sheet(item: $dayForNewWorkout) { day in
            if let plan {
                SessionEditorView(planID: plan.id, dayID: day.id)
            }
        }
        .sheet(isPresented: $showingWeekCopy) {
            if let plan, let selectedWeek {
                ATHLTHPlanWeekCopySheet(
                    plan: plan,
                    sourceWeekID: selectedWeek.id
                )
                .environmentObject(session)
            }
        }
        .sheet(isPresented: $showingPlanEditor) {
            NavigationStack {
                ScrollView {
                    AdvancedPlannerView(showsEmptyState: false)
                        .padding(16)
                }
                .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Edit plan",
                    norwegian: "Rediger plan"
                ))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Done", norwegian: "Ferdig"
                        )) { showingPlanEditor = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingStandaloneEditor) {
            SessionEditorView(standaloneDate: Date())
        }
        .fullScreenCover(isPresented: $showingPlanLibrary) {
            AllTrainingPlansView()
        }
        .sheet(isPresented: $showingCreatePlan) {
            TrainingPlanCreationView()
        }
    }

    private func planHeader(_ plan: TrainingPlan) -> some View {
        Button {
            showingPlanLibrary = true
        } label: {
            HStack(alignment: .center, spacing: 13) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "ACTIVE PLAN",
                        norwegian: "AKTIV PLAN"
                    ))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                    Text(plan.title)
                        .font(.system(size: 24, weight: .medium, design: .serif))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(2)

                    Text("\(plan.weeks.count) uker · \(plan.weeks.reduce(0) { $0 + $1.days.reduce(0) { $0 + $1.sessions.count } }) planlagte økter")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer(minLength: 4)
                VStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 19, weight: .light))
                    Text(ATHLTHLocalization.choose(
                        english: "My plans",
                        norwegian: "Mine planer"
                    ))
                    .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 78, height: 70)
                .background(ATHLTHTheme.champagneSoft, in:
                    RoundedRectangle(cornerRadius: 17))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(ATHLTHTheme.premiumGold.opacity(0.22), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func weekSelector(
        _ plan: TrainingPlan,
        selected: TrainingPlanWeek
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ATHLTHLocalization.choose(
                    english: "WEEK OVERVIEW",
                    norwegian: "UKEOVERSIKT"
                ))
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(ATHLTHTheme.accentDeep)

                Spacer()
                Button {
                    showingWeekCopy = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Copy week", norwegian: "Kopier uke"
                    ), systemImage: "doc.on.doc")
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHTheme.accentDeep)

                Button {
                    showingPlanEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Edit plan", norwegian: "Rediger plan"
                ))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(plan.weeks.sorted { $0.weekNumber < $1.weekNumber }) { week in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                chosenWeekID = week.id
                                expandedDayIDs = []
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(week.weekNumber)")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                Text(ATHLTHLocalization.choose(
                                    english: "Week", norwegian: "Uke"
                                ))
                                .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(week.id == selected.id
                                ? Color.white : ATHLTHTheme.primaryText)
                            .frame(width: 65, height: 57)
                            .background(
                                week.id == selected.id
                                    ? ATHLTHTheme.accentDeep
                                    : Color.white,
                                in: RoundedRectangle(cornerRadius: 15)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(week.id == selected.id ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func dayRow(
        _ day: TrainingPlanDay,
        week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> some View {
        let date = TrainingPlanSchedule.dayDate(
            in: plan, week: week, day: day
        )
        let workouts = date.map {
            TrainingPlanSchedule.sessions(in: plan, on: $0)
        } ?? day.sessions
        let isRestDay = date.map {
            TrainingPlanSchedule.isRestDay(in: plan, on: $0)
        } ?? (day.isRestDay == true)
        let canChangeRest = date.map {
            Calendar.current.startOfDay(for: $0) >=
                Calendar.current.startOfDay(for: Date())
        } ?? false
        let hasStandaloneWorkout = date.map {
            !session.standalonePlannedSessions(on: $0).isEmpty
        } ?? false
        let isExpanded = expandedDayIDs.contains(day.id)
        let isToday = date.map {
            Calendar.current.isDateInToday($0)
        } ?? false

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.17)) {
                    if isExpanded {
                        expandedDayIDs.remove(day.id)
                    } else {
                        expandedDayIDs.insert(day.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(spacing: 1) {
                        Text(date?.formatted(.dateTime.day()) ?? "\(day.dayIndex)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text(date?.formatted(.dateTime.weekday(.abbreviated))
                            .uppercased() ?? "DAG")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(isToday ? Color.white : ATHLTHTheme.accentDeep)
                    .frame(width: 51, height: 55)
                    .background(
                        isToday ? ATHLTHTheme.accentDeep : ATHLTHTheme.champagneSoft,
                        in: RoundedRectangle(cornerRadius: 13)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(workouts.isEmpty
                            ? isRestDay
                                ? ATHLTHLocalization.choose(
                                    english: "Rest day",
                                    norwegian: "Hviledag"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Unplanned day",
                                    norwegian: "Ledig dag"
                                )
                            : workouts.count == 1
                                ? workouts[0].title
                                : "\(workouts.count) treningsøkter")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)
                        Text(workouts.isEmpty
                            ? isRestDay
                                ? ATHLTHLocalization.choose(
                                    english: "Intentional rest · not counted as a workout",
                                    norwegian: "Planlagt hvile · teller ikke som trening"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "No workout scheduled",
                                    norwegian: "Ingen økter planlagt"
                                )
                            : workouts.map(\.kind.title).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 3)
                    if isRestDay {
                        Image(systemName: "leaf")
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .accessibilityHidden(true)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
                .padding(13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                VStack(spacing: 10) {
                    Rectangle()
                        .fill(ATHLTHTheme.border)
                        .frame(height: 0.7)
                    ForEach(workouts) { workout in
                        let skipped = session.isPlanSessionSkipped(
                            planID: plan.id, sessionID: workout.id
                        )
                        let editable = canEditOccurrence(
                            workout, planID: plan.id
                        )
                        HStack(spacing: 6) {
                            Button {
                                selectedWorkout = workout
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: workout.kind.systemImage)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                        .frame(width: 31, height: 31)
                                        .background(
                                            ATHLTHTheme.champagneSoft,
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(workout.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ATHLTHTheme.primaryText)
                                        Text(
                                            skipped
                                                ? ATHLTHLocalization.choose(
                                                    english: "Skipped",
                                                    norwegian: "Hoppet over"
                                                )
                                                : workout.exercises.isEmpty
                                                    ? workout.kind.title
                                                    : "\(workout.exercises.count) øvelser"
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(
                                            skipped
                                                ? ATHLTHTheme.accentDeep
                                                : ATHLTHTheme.mutedText
                                        )
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button {
                                    selectedWorkout = workout
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "View details",
                                            norwegian: "Se detaljer"
                                        ),
                                        systemImage: "doc.text.magnifyingglass"
                                    )
                                }

                                if editable {
                                    if skipped {
                                        Button {
                                            session.setPlanSessionSkipped(
                                                planID: plan.id,
                                                sessionID: workout.id,
                                                skipped: false
                                            )
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Restore",
                                                    norwegian: "Gjenopprett"
                                                ),
                                                systemImage: "arrow.uturn.backward"
                                            )
                                        }
                                    } else {
                                        Button {
                                            workoutPendingMove = workout
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Move",
                                                    norwegian: "Flytt"
                                                ),
                                                systemImage: "calendar.badge.clock"
                                            )
                                        }

                                        Button {
                                            workoutPendingSkip = workout
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Skip",
                                                    norwegian: "Hopp over"
                                                ),
                                                systemImage: "forward.end"
                                            )
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                    .frame(width: 32, height: 38)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Workout actions",
                                norwegian: "Økthandlinger"
                            ))
                        }
                    }
                    if isRestDay {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Rest and recovery are intentional parts of your training plan.",
                                norwegian: "Hvile og restitusjon er en planlagt del av treningen din."
                            ),
                            systemImage: "leaf"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if canChangeRest {
                            Button {
                                _ = session.setPlanDayRestStatus(
                                    planID: plan.id,
                                    dayID: day.id,
                                    isRestDay: false
                                )
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Remove rest day",
                                        norwegian: "Fjern hviledag"
                                    ),
                                    systemImage: "arrow.uturn.backward"
                                )
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                        }
                    } else {
                        if workouts.isEmpty && canChangeRest &&
                            !hasStandaloneWorkout {
                            Button {
                                _ = session.setPlanDayRestStatus(
                                    planID: plan.id,
                                    dayID: day.id,
                                    isRestDay: true
                                )
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Mark as rest day",
                                        norwegian: "Sett som hviledag"
                                    ),
                                    systemImage: "leaf"
                                )
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .buttonStyle(.plain)
                        }

                        if canChangeRest {
                            Button {
                                dayForNewWorkout = day
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Add workout",
                                        norwegian: "Legg til økt"
                                    ),
                                    systemImage: "plus"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.bottom, 13)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isToday ? ATHLTHTheme.premiumGold.opacity(0.58)
                        : ATHLTHTheme.border,
                    lineWidth: isToday ? 1.1 : 0.75
                )
        }
    }

    private func canEditOccurrence(
        _ workout: PlannedSession,
        planID: UUID
    ) -> Bool {
        guard !session.isPlanSessionManuallyCompleted(
            planID: planID, sessionID: workout.id
        ) else { return false }

        // Plan changes must not silently rewrite a finished or partial
        // recording; detailed re-planning belongs in a separate workflow.
        return !strength.workoutHistory.contains {
            $0.plannedSessionID == workout.id && $0.isFinished
        }
    }

    private var standaloneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "ADDITIONAL WORKOUTS",
                    norwegian: "ENKELTØKTER"
                ))
                .font(.caption2.weight(.bold))
                .tracking(1.7)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                Spacer()
                Button {
                    showingStandaloneEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTheme.champagneSoft,
                            in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Add standalone workout",
                    norwegian: "Legg til enkeltøkt"
                ))
            }
            ForEach(
                session.standalonePlannedSessions
                    .filter {
                        guard let date = $0.scheduledStart else { return false }
                        return date >= Calendar.current.startOfDay(for: Date())
                    }
                    .sorted {
                        ($0.scheduledStart ?? .distantFuture) <
                            ($1.scheduledStart ?? .distantFuture)
                    }
                    .prefix(3)
            ) { workout in
                HStack(spacing: 10) {
                    Image(systemName: workout.kind.systemImage)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(workout.scheduledStart?.formatted(
                            .dateTime.day().month(.abbreviated)
                        ) ?? "")
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer()
                    if workout.followUpSourceWorkoutID != nil {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                }
                .padding(12)
                .background(Color.white,
                    in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.top, 2)
    }

    private var emptyPlanView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ATHLTHLocalization.choose(
                english: "YOUR TRAINING PLAN",
                norwegian: "DIN TRENINGSPLAN"
            ))
            .font(.caption2.weight(.bold))
            .tracking(1.6)
            .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(ATHLTHLocalization.choose(
                english: "Build your rhythm.",
                norwegian: "Bygg din egen rytme."
            ))
            .font(.system(size: 27, weight: .medium, design: .serif))
            .foregroundStyle(ATHLTHTheme.primaryText)
            Text(ATHLTHLocalization.choose(
                english: "Create or choose a plan. You can always train without one.",
                norwegian: "Opprett eller velg en plan. Du kan alltid trene uten."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
            HStack(spacing: 10) {
                Button {
                    showingCreatePlan = true
                } label: {
                    Label("Ny plan", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                Button {
                    showingPlanLibrary = true
                } label: {
                    Label("Mine planer", systemImage: "square.stack")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white,
            in: RoundedRectangle(cornerRadius: 23))
    }
}
