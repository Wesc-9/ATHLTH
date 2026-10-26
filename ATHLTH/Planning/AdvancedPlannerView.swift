import SwiftUI

struct AdvancedPlannerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let planID: UUID?
    let showsEmptyState: Bool

    @State private var selectedWeekID: UUID?
    @State private var selectedDayID: UUID?
    @State private var selectedWorkout: PlannedSession?
    @State private var workoutPendingPremiumEdit: PlannedSession?
    @State private var selectedStandaloneLobbyWorkout: PlannedSession?
    @State private var showingSessionEditor = false
    @State private var showingStandaloneSessionEditor = false
    @State private var showingPlanEditor = false
    @State private var showingPlanProgress = false
    @State private var showingAllPlans = false
    @State private var preparedShare: MessageShareDraft?
    @State private var shareError: String?
    @State private var showingProgramCreation = false
    @State private var studioSection: PlanStudioSection = .program

    private enum PlanStudioSection: Int, CaseIterable {
        case program, week, day
        var title: String {
            switch self {
            case .program: return ATHLTHLocalization.choose(english: "Program", norwegian: "Program")
            case .week: return ATHLTHLocalization.choose(english: "Week", norwegian: "Uke")
            case .day: return ATHLTHLocalization.choose(english: "Day", norwegian: "Dag")
            }
        }
    }
    @State private var weekPendingRemoval: TrainingPlanWeek?
    @State private var pendingWeekCopy: PendingWeekCopy?

    private struct PendingWeekCopy {
        let planID: UUID
        let sourceWeekID: UUID
        let sourceWeekNumber: Int
        let scope: TrainingWeekCopyScope
        let progression: TrainingWeekProgressionMode
        let summary: TrainingWeekCopySummary
    }

    init(
        planID: UUID? = nil,
        showsEmptyState: Bool = true
    ) {
        self.planID = planID
        self.showsEmptyState = showsEmptyState
    }

    private var displayedPlan: TrainingPlan? {
        if let planID {
            return session.trainingPlan(withID: planID)
        }

        return session.activePlan
    }

    var body: some View {
        VStack(spacing: ATHLTHPlanDesign.Density.comfortable.stackSpacing) {
            if let plan = displayedPlan {
                studioNavigator(plan)
                switch studioSection {
                case .program:
                    planOverview(plan)
                    ATHLTHPlanProgramTrendView(plan: plan) { weekID in
                        selectedWeekID = weekID
                        if let week = plan.weeks.first(where: { $0.id == weekID }) {
                            selectedDayID = week.days.first?.id
                        }
                        studioSection = .week
                    }
                    ATHLTHPlanRecordedMetricsView(plan: plan) { weekID in
                        selectedWeekID = weekID
                        if let week = plan.weeks.first(where: { $0.id == weekID }) {
                            selectedDayID = week.days.first?.id
                        }
                        studioSection = .week
                    }
                    ATHLTHPlanWeeklyFollowThroughView(plan: plan) { weekID, dayID in
                        selectedWeekID = weekID
                        if let week = plan.weeks.first(where: { $0.id == weekID }) {
                            if let dayID,
                               week.days.contains(where: { $0.id == dayID }) {
                                selectedDayID = dayID
                                studioSection = .day
                            } else {
                                selectedDayID = week.days.first?.id
                                studioSection = .week
                            }
                        }
                    }
                    recentStrengthEvidence(plan)
                    ATHLTHPlanReviewSuggestionsView(plan: plan) { weekID, dayID in
                        selectedWeekID = weekID
                        if let week = plan.weeks.first(where: { $0.id == weekID }) {
                            if let dayID,
                               week.days.contains(where: { $0.id == dayID }) {
                                selectedDayID = dayID
                                studioSection = .day
                            } else {
                                selectedDayID = week.days.first?.id
                                studioSection = .week
                            }
                        }
                    }
                    planQualityPanel(plan)
                    if let week = selectedWeek(in: plan) {
                        weekSelector(plan)
                        weekBalanceCard(week)
                        weekOverview(plan, week: week)
                    }
                    standaloneScheduleCard
                case .week:
                    if let week = selectedWeek(in: plan) {
                        weekSelector(plan)
                        weekBalanceCard(week)
                        weekOverview(plan, week: week)
                    }
                case .day:
                    if let week = selectedWeek(in: plan) {
                        weekSelector(plan)
                        daySelector(plan, week: week)
                        if let day = selectedDay(in: week) {
                            selectedDayCard(plan: plan, week: week, day: day)
                        }
                    }
                }
            } else {
                if showsEmptyState { emptyPlanState }
                standaloneScheduleCard
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let plan = displayedPlan {
                    Button {
                        do {
                            preparedShare = try ATHLTHShareDraftFactory.plan(
                                plan, library: exerciseLibrary.allExercises,
                                ownerID: session.profile.userID
                            )
                        } catch {
                            shareError = error.localizedDescription
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Share plan", norwegian: "Del plan"
                            ),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                }
            }
        }
        .sheet(item: $preparedShare) { draft in
            ATHLTHDirectShareSheet(draft: draft)
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not share plan", norwegian: "Kunne ikke dele planen"
            ),
            isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .onAppear {
            session.refreshActivePlanForToday()
            syncSelection()
        }
        .onChange(of: displayedPlan?.id) { _, _ in
            syncSelection()
        }
        .onChange(of: displayedPlan?.version) { _, _ in
            reconcileSelection()
        }
        .sheet(isPresented: $showingSessionEditor) {
            if let selectedDayID,
               let plan = displayedPlan {
                SessionEditorView(
                    planID: plan.id,
                    dayID: selectedDayID
                )
            }
        }
        .sheet(
            isPresented:
                $showingStandaloneSessionEditor
        ) {
            SessionEditorView(
                standaloneDate: Date()
            )
        }
        .sheet(isPresented: $showingPlanEditor) {
            if let plan = displayedPlan {
                PlanMetadataEditorView(plan: plan)
            }
        }
        .sheet(isPresented: $showingPlanProgress) {
            if let plan = displayedPlan {
                TrainingPlanProgressDetailView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingAllPlans) {
            AllTrainingPlansView()
        }
        .sheet(isPresented: $showingProgramCreation) {
            TrainingPlanCreationView()
        }
        .sheet(item: $selectedStandaloneLobbyWorkout) { workout in
            NavigationStack {
                PlannedWorkoutLobbyView(workout: workout)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(ATHLTHLocalization.choose(
                                english: "Done", norwegian: "Ferdig"
                            )) {
                                selectedStandaloneLobbyWorkout = nil
                            }
                        }
                    }
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            if let planID = displayedPlan?.id {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("PLANLAGT ØKT")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(2)
                                    .foregroundStyle(Color(red: 0.52, green: 0.39, blue: 0.22))
                                Text(workout.title)
                                    .font(.system(size: 30, weight: .semibold, design: .serif))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(sessionSummary(workout))
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 18)

                            HStack(spacing: 12) {
                                Label(workout.kind.title, systemImage: workout.kind.systemImage)
                                    .font(.caption.weight(.medium))
                                if let start = workout.scheduledStart {
                                    Label(start.formatted(date: .omitted, time: .shortened),
                                          systemImage: "clock")
                                        .font(.caption.weight(.medium))
                                }
                            }
                            .foregroundStyle(Color(red: 0.49, green: 0.36, blue: 0.19))

                            ATHLTHReleasePlanTimeline(workout: workout)

                            Button {
                                workoutPendingPremiumEdit = workout
                                selectedWorkout = nil
                            } label: {
                                Label("Rediger økt", systemImage: "square.and.pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .foregroundStyle(.white)
                                    .background(Color(red: 0.55, green: 0.40, blue: 0.22),
                                                in: RoundedRectangle(cornerRadius: 15))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(20)
                    }
                    .background(Color(red: 0.985, green: 0.979, blue: 0.965).ignoresSafeArea())
                    .navigationTitle("Øktoversikt")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Ferdig") { selectedWorkout = nil }
                        }
                    }
                }
                .environmentObject(session)
            }
        }
        .sheet(item: $workoutPendingPremiumEdit) { workout in
            if let planID = displayedPlan?.id {
                SessionEditorView(planID: planID, workout: workout)
                    .environmentObject(session)
            }
        }
        .confirmationDialog(
            weekPendingRemoval.map {
                "Remove W\($0.weekNumber)?"
            } ?? "Remove week?",
            isPresented: Binding(
                get: { weekPendingRemoval != nil },
                set: { presented in
                    if !presented {
                        weekPendingRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let week = weekPendingRemoval {
                Button(
                    "Remove W\(week.weekNumber)",
                    role: .destructive
                ) {
                    if let plan = displayedPlan {
                        removeWeek(week, from: plan)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                weekPendingRemoval = nil
            }
        } message: {
            if let week = weekPendingRemoval {
                let count = week.days.reduce(0) {
                    $0 + $1.sessions.count
                }

                Text(
                    count == 1
                        ? "This week contains 1 planned workout. Removing the week will also remove that workout."
                        : "This week contains \(count) planned workouts. Removing the week will also remove those workouts."
                )
            }
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Repeat training week?",
                norwegian: "Gjenta treningsuken?"
            ),
            isPresented: Binding(
                get: { pendingWeekCopy != nil },
                set: { showing in
                    if !showing { pendingWeekCopy = nil }
                }
            )
        ) {
            if let request = pendingWeekCopy {
                Button(
                    ATHLTHLocalization.choose(
                        english: "Copy workouts",
                        norwegian: "Kopier økter"
                    )
                ) {
                    _ = session.copyTrainingWeekToEmptyDays(
                        planID: request.planID,
                        sourceWeekID: request.sourceWeekID,
                        scope: request.scope,
                        progression: request.progression
                    )
                    pendingWeekCopy = nil
                }
            }
            Button(
                ATHLTHLocalization.choose(
                    english: "Cancel",
                    norwegian: "Avbryt"
                ),
                role: .cancel
            ) {
                pendingWeekCopy = nil
            }
        } message: {
            if let request = pendingWeekCopy {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Copy \(request.summary.copiedSessions) workouts from week \(request.sourceWeekNumber) to \(request.summary.filledDays) empty future days across \(request.summary.targetWeeks) weeks. \(progressionDescription(request.progression, norwegian: false)) Existing and past workouts are untouched.",
                        norwegian: "Kopier \(request.summary.copiedSessions) økter fra uke \(request.sourceWeekNumber) til \(request.summary.filledDays) tomme fremtidige dager over \(request.summary.targetWeeks) uker. \(progressionDescription(request.progression, norwegian: true)) Eksisterende og tidligere økter endres ikke."
                    )
                )
            }
        }
    }

    private func studioNavigator(_ plan: TrainingPlan) -> some View {
        ATHLTHPlanSurface {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ATHLTH / PLAN STUDIO")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(ATHLTHPlanDesign.accent)
                    Text(plan.title)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ATHLTHLocalization.choose(
                        english: "Move freely between your program, week and day.",
                        norwegian: "Bytt fritt mellom program, uke og dag."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 0)
                Button {
                    showingPlanProgress = true
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Plan insights", norwegian: "Planinnsikt"
                ))
            }
            Picker(
                ATHLTHLocalization.choose(english: "Plan view", norwegian: "Planvisning"),
                selection: $studioSection
            ) {
                ForEach(PlanStudioSection.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Plan view", norwegian: "Planvisning"
            ))
        }
    }

    private var standaloneScheduleCard:
        some View {
        ATHLTHUnifiedCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack(
                    alignment: .top,
                    spacing: 12
                ) {
                    Image(
                        systemName:
                            "calendar.badge.plus"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Extra planned workouts",
                                norwegian:
                                    "Ekstra planlagte økter"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.bold)
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Plan a workout without changing your active training plan.",
                                norwegian:
                                    "Planlegg en økt uten å endre den aktive treningsplanen."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }

                    Spacer()

                    Button {
                        showingStandaloneSessionEditor =
                            true
                    } label: {
                        Image(
                            systemName: "plus"
                        )
                        .font(
                            .system(
                                size: 13,
                                weight: .bold
                            )
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .buttonBorderShape(.circle)
                    .tint(
                        ATHLTHTheme.accent
                    )
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english:
                                "Plan extra workout",
                            norwegian:
                                "Planlegg ekstra økt"
                        )
                    )
                }

                if hasStandaloneDraft {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Saved draft · Tap + to continue",
                            norwegian: "Utkast lagret · Trykk + for å fortsette"
                        ),
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }

                if !upcomingStandaloneSessions
                    .isEmpty {
                    VStack(spacing: 8) {
                        ForEach(
                            upcomingStandaloneSessions
                                .prefix(4)
                        ) { workout in
                            standaloneSessionRow(
                                workout
                            )
                        }
                    }
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "These workouts are kept separate from your training plan and never replace, move or complete plan sessions.",
                        norwegian:
                            "Disse øktene holdes separat og vil aldri erstatte, flytte eller fullføre økter i treningsplanen."
                    )
                )
                .font(.system(size: 9.5))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
        }
    }

    private var hasStandaloneDraft: Bool {
        let key = "athlth.sessionEditor.draft.v1.\(session.profile.userID.uuidString).standalone"
        return UserDefaults.standard.data(forKey: key) != nil
    }

    private var upcomingStandaloneSessions:
        [PlannedSession] {
        let cutoff =
            Calendar.current
                .startOfDay(
                    for: Date()
                )

        return session
            .standalonePlannedSessions
            .filter {
                guard let date =
                        $0.scheduledStart
                else {
                    return false
                }

                return date >= cutoff
            }
            .sorted {
                ($0.scheduledStart ??
                    .distantFuture) <
                ($1.scheduledStart ??
                    .distantFuture)
            }
    }

    private func standaloneSessionRow(
        _ workout: PlannedSession
    ) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName:
                    workout.kind.systemImage
            )
            .font(
                .system(
                    size: 14,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 34,
                height: 34
            )
            .background(
                ATHLTHTheme.accentSoft,
                in: RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(workout.title)
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                if let date =
                        workout.scheduledStart {
                    Text(
                        date.formatted(
                            .dateTime
                                .weekday(
                                    .abbreviated
                                )
                                .day()
                                .month(
                                    .abbreviated
                                )
                                .hour()
                                .minute()
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                if let meeting = workout.meetingPoint {
                    Label(meeting.name, systemImage: "mappin.circle")
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if workout.trainTogetherMode != nil {
                Button {
                    selectedStandaloneLobbyWorkout = workout
                } label: {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTheme.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Open workout lobby",
                    norwegian: "Åpne øktlobby"
                ))
            }

            Menu {
                Button(
                    role: .destructive
                ) {
                    session
                        .removeStandalonePlannedSession(
                            workout.id
                        )
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Delete",
                            norwegian: "Slett"
                        ),
                        systemImage: "trash"
                    )
                }
            } label: {
                Image(
                    systemName: "ellipsis"
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .frame(
                    width: 30,
                    height: 34
                )
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 48)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private func planOverview(_ plan: TrainingPlan) -> some View {
        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 15)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(planTimelineText(plan))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !plan.summary
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty {
                            Text(plan.summary)
                                .font(.subheadline)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText.opacity(0.78)
                                )
                                .padding(.top, 2)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            showingPlanProgress = true
                        } label: {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english: "Plan progress",
                                norwegian: "Planprogresjon"
                            )
                        )

                        if planID == nil {
                            Button {
                                showingAllPlans = true
                            } label: {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("All training plans")
                        }

                        Button {
                            showingPlanEditor = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Edit training plan")
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 125), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    plannerMetric(
                        title: "Sessions",
                        value: "\(allSessions(in: plan).count)",
                        icon: "figure.run"
                    )

                    plannerMetric(
                        title: "Training days",
                        value: "\(trainingDayCount(in: plan))",
                        icon: "calendar"
                    )

                    plannerMetric(
                        title: "Planned time",
                        value: plannedDurationText(plan),
                        icon: "timer"
                    )

                    plannerMetric(
                        title: "Run / walk",
                        value: plannedDistanceText(plan),
                        icon: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }

                Button {
                    showingPlanProgress = true
                } label: {
                    HStack(spacing: 9) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "View training progress",
                                norwegian: "Se treningsutviklingen"
                            ),
                            systemImage: "chart.xyaxis.line"
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .padding(13)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func recentStrengthEvidence(_ plan: TrainingPlan) -> some View {
        let advice = TrainingPlanLoadAdvisor.evaluate(
            plan: plan,
            strengthHistory: strength.workoutHistory,
            limit: 3
        )
        if !advice.isEmpty {
            ATHLTHPlanSurface {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(ATHLTHPlanDesign.accent)
                        .font(.system(size: 18, weight: .medium))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "What your workouts show",
                            norwegian: "Dette viser treningsøktene dine"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "Based only on completed strength workouts connected to this plan.",
                            norwegian: "Kun basert på gjennomførte styrkeøkter knyttet til denne planen."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                ForEach(advice) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.exerciseName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Spacer()
                            Text("\(item.completedWorkSets)/\(item.plannedWorkSets) " +
                                ATHLTHLocalization.choose(
                                    english: "sets", norwegian: "sett"
                                ))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        Text(strengthFeedbackText(item))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.workoutDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    showingPlanProgress = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "See all plan insights",
                            norwegian: "Se all planinnsikt"
                        ),
                        systemImage: "arrow.up.right"
                    )
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func strengthFeedbackText(
        _ advice: TrainingPlanLoadAdvisor.Advice
    ) -> String {
        switch advice.verdict {
        case .reviewTargets:
            return ATHLTHLocalization.choose(
                english: "Some planned work sets were not met. Review the next workout's targets.",
                norwegian: "Noen planlagte arbeidssett ble ikke fullført som planlagt. Vurder målene for neste økt."
            )
        case .targetMet:
            return ATHLTHLocalization.choose(
                english: "The logged work sets reached the planned targets.",
                norwegian: "De loggede arbeidssettene nådde de planlagte målene."
            )
        case .considerIncrease:
            if let weight = advice.suggestedNextWeightKilograms {
                return ATHLTHLocalization.choose(
                    english: "Targets met with documented reserve. Consider \(weight.formatted()) kg next time if it feels appropriate.",
                    norwegian: "Målene ble nådd med dokumentert overskudd. Vurder \(weight.formatted()) kg neste gang hvis det passer."
                )
            }
            return ATHLTHLocalization.choose(
                english: "Targets met with documented reserve. A modest progression may be reasonable.",
                norwegian: "Målene ble nådd med dokumentert overskudd. En forsiktig progresjon kan være aktuell."
            )
        }
    }

    private func weekBalanceCard(_ week: TrainingPlanWeek) -> some View {
        let report = ATHLTHPlanWeekBalanceAdvisor.inspect(week)
        return ATHLTHPlanSurface {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "figure.run.circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "Weekly balance", norwegian: "Ukens balanse"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(ATHLTHLocalization.choose(
                        english: "A review of your schedule, not a recovery or injury-risk score.",
                        norwegian: "En gjennomgang av oppsettet, ikke en restitusjons- eller skaderisikoscore."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 15) {
                balanceStatistic(
                    value: report.runningCount,
                    label: ATHLTHLocalization.choose(english: "Runs", norwegian: "Løp")
                )
                balanceStatistic(
                    value: report.strengthCount,
                    label: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
                )
                balanceStatistic(
                    value: report.scheduledDays,
                    label: ATHLTHLocalization.choose(english: "Days", norwegian: "Dager")
                )
                Spacer(minLength: 0)
            }

            if report.sessionCount > 0 {
                if let minutes = report.completePlannedMinutes {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "\(minutes) planned minutes this week",
                            norwegian: "\(minutes) planlagte minutter denne uken"
                        ),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "Total duration unavailable: \(report.sessionsWithoutDuration) workouts have no time target.",
                        norwegian: "Samlet varighet ukjent: \(report.sessionsWithoutDuration) økter mangler tidsmål."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }

            if report.findings.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "No basic scheduling patterns to review.",
                        norwegian: "Ingen åpenbare mønstre å undersøke i ukeoppsettet."
                    ),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                ForEach(report.findings.prefix(3)) { finding in
                    Button {
                        if let day = week.days.first(where: {
                            $0.dayIndex == finding.dayIndex
                        }) {
                            selectedWeekID = week.id
                            selectedDayID = day.id
                            studioSection = .day
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHPlanDesign.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(finding.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(finding.detail)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Open the related day to review this workout.",
                        norwegian: "Åpne tilhørende dag for å vurdere økten."
                    ))
                }
            }
        }
    }

    private func balanceStatistic(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func planQualityPanel(_ plan: TrainingPlan) -> some View {
        let findings = ATHLTHPlanStructureAdvisor.inspect(plan)
        return ATHLTHPlanSurface {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .font(.system(size: 18, weight: .medium))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "Plan structure check", norwegian: "Sjekk av planstruktur"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(ATHLTHLocalization.choose(
                        english: "Checks scheduling and workout identity, not medical safety.",
                        norwegian: "Kontrollerer planoppsett og øktidentitet, ikke medisinsk sikkerhet."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 0)
            }

            if findings.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "No basic structural issues found.",
                        norwegian: "Ingen enkle strukturavvik funnet."
                    ),
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.vitality)
            } else {
                ForEach(Array(findings.prefix(4))) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.subheadline)
                            .foregroundStyle(
                                item.severity == .attention
                                ? ATHLTHPlanDesign.accent
                                : ATHLTHTheme.accent
                            )
                            .frame(width: 22, alignment: .center)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if findings.count > 4 {
                    Text(ATHLTHLocalization.choose(
                        english: "\(findings.count - 4) additional notes",
                        norwegian: "\(findings.count - 4) flere merknader"
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
        }
    }

    private func weekSelector(_ plan: TrainingPlan) -> some View {
        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weeks")
                            .font(.title3.weight(.bold))
                        Text("Jump between weeks without leaving the planner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            session.addWeekToTrainingPlan(
                                planID: plan.id
                            )
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(plan.weeks.count >= 52)

                        Menu {
                            if let week = selectedWeek(in: plan) {
                                let next = TrainingWeekTemplateEngine.preview(
                                    plan: plan,
                                    sourceWeekID: week.id,
                                    scope: .nextWeek
                                )
                                let future = TrainingWeekTemplateEngine.preview(
                                    plan: plan,
                                    sourceWeekID: week.id,
                                    scope: .allFutureWeeks
                                )

                                if next.hasWork {
                                    Button {
                                        requestWeekCopy(
                                            from: week,
                                            plan: plan,
                                            scope: .nextWeek,
                                            summary: next
                                        )
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Copy to next week",
                                                norwegian: "Kopier til neste uke"
                                            ),
                                            systemImage: "calendar.badge.plus"
                                        )
                                    }
                                }

                                if future.hasWork {
                                    Button {
                                        requestWeekCopy(
                                            from: week,
                                            plan: plan,
                                            scope: .allFutureWeeks,
                                            summary: future
                                        )
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Fill future empty days",
                                                norwegian: "Fyll tomme dager fremover"
                                            ),
                                            systemImage: "calendar"
                                        )
                                    }

                                    Menu {
                                        Button {
                                            requestWeekCopy(
                                                from: week,
                                                plan: plan,
                                                scope: .allFutureWeeks,
                                                summary: future,
                                                progression: .addWeightPerWeek(2.5)
                                            )
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "+2.5 kg per week",
                                                    norwegian: "+2,5 kg per uke"
                                                ),
                                                systemImage: "scalemass"
                                            )
                                        }

                                        Button {
                                            requestWeekCopy(
                                                from: week,
                                                plan: plan,
                                                scope: .allFutureWeeks,
                                                summary: future,
                                                progression: .addRepsPerWeek(1)
                                            )
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "+1 repetition per week",
                                                    norwegian: "+1 repetisjon per uke"
                                                ),
                                                systemImage: "plus"
                                            )
                                        }

                                        if let selectedIndex = plan.weeks.firstIndex(
                                            where: { $0.id == week.id }
                                        ), plan.weeks.count - selectedIndex >= 4 {
                                            Button {
                                                requestWeekCopy(
                                                    from: week,
                                                    plan: plan,
                                                    scope: .allFutureWeeks,
                                                    summary: future,
                                                    progression: .fourWeekStrengthBlock
                                                )
                                            } label: {
                                                Label(
                                                    ATHLTHLocalization.choose(
                                                        english: "4-week block with deload",
                                                        norwegian: "4-ukersblokk med deload"
                                                    ),
                                                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                                                )
                                            }
                                        }
                                    } label: {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Copy with progression",
                                                norwegian: "Kopier med progresjon"
                                            ),
                                            systemImage: "chart.line.uptrend.xyaxis"
                                        )
                                    }
                                }

                                if plan.weeks.count > 1 {
                                    Divider()
                                    Button(role: .destructive) {
                                        requestWeekRemoval(
                                            week,
                                            from: plan
                                        )
                                    } label: {
                                        Label(
                                            "Remove W\(week.weekNumber)",
                                            systemImage: "trash"
                                        )
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(
                                    .system(
                                        size: 15,
                                        weight: .semibold
                                    )
                                )
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                        .disabled(plan.weeks.count <= 1)
                        .accessibilityLabel("Week actions")
                    }
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(plan.weeks) { week in
                            let selected = selectedWeekID == week.id
                            let count = week.days.reduce(0) {
                                $0 + $1.sessions.count
                            }

                            Button {
                                selectedWeekID = week.id
                                selectBestDay(
                                    in: week,
                                    plan: plan
                                )
                            } label: {
                                VStack(spacing: 3) {
                                    Text("W\(week.weekNumber)")
                                        .font(.subheadline.weight(.bold))

                                    Text(
                                        count == 1
                                            ? "1 session"
                                            : "\(count) sessions"
                                    )
                                    .font(
                                        .system(
                                            size: 9,
                                            weight: .semibold
                                        )
                                    )
                                    .opacity(0.78)

                                    if let phase = week.strengthPhase {
                                        Text(
                                            phase == .deload
                                                ? ATHLTHLocalization.choose(
                                                    english: "DELOAD",
                                                    norwegian: "ROLIG UKE"
                                                )
                                                : ATHLTHLocalization.choose(
                                                    english: "BUILD",
                                                    norwegian: "OPPBYGG"
                                                )
                                        )
                                        .font(.system(size: 8, weight: .bold))
                                        .tracking(0.2)
                                    }
                                }
                                .foregroundStyle(
                                    selected
                                        ? Color.white
                                        : ATHLTHTheme.primaryText
                                )
                                .padding(.horizontal, 14)
                                .frame(minHeight: 48)
                                .background(
                                    selected
                                        ? ATHLTHTheme.accent
                                        : Color.primary.opacity(0.035),
                                    in: RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                    .stroke(
                                        selected
                                            ? Color.clear
                                            : Color.black.opacity(0.045),
                                        lineWidth: 1
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)

                if let week = selectedWeek(in: plan) {
                    let workouts = week.days.flatMap(\.sessions)
                    let completed = workouts.filter {
                        session.isPlanSessionCompleted(
                            planID: plan.id,
                            sessionID: $0.id,
                            healthWorkouts: health.workouts,
                            strengthHistory: strength.workoutHistory
                        )
                    }.count

                    VStack(spacing: 7) {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Week \(week.weekNumber) progress",
                                    norwegian: "Fremdrift uke \(week.weekNumber)"
                                )
                            )
                            .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(completed) / \(workouts.count)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                        }
                        ProgressView(
                            value: Double(completed),
                            total: Double(max(workouts.count, 1))
                        )
                        .tint(ATHLTHTheme.accent)
                    }
                    .padding(.top, 5)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func daySelector(
        _ plan: TrainingPlan,
        week: TrainingPlanWeek
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(week.days) { day in
                    let selected = selectedDayID == day.id
                    let date = date(for: day, in: week, plan: plan)
                    let isToday = date.map(Calendar.current.isDateInToday) ?? false

                    Button {
                        selectedDayID = day.id
                    } label: {
                        VStack(spacing: 5) {
                            Text(
                                shortDayLabel(
                                    day,
                                    week: week,
                                    plan: plan
                                )
                            )
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)

                            Text(
                                date?.formatted(
                                    .dateTime.day()
                                ) ?? "\(day.dayIndex)"
                            )
                            .font(.title3.weight(.bold))

                            HStack(spacing: 3) {
                                if isToday {
                                    Circle()
                                        .fill(
                                            selected
                                                ? Color.white
                                                : ATHLTHTheme.accent
                                        )
                                        .frame(width: 5, height: 5)
                                }

                                Text(
                                    day.sessions.isEmpty
                                        ? "Rest"
                                        : "\(day.sessions.count)"
                                )
                                .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .foregroundStyle(
                            selected ? Color.white : ATHLTHTheme.primaryText
                        )
                        .frame(width: 62, height: 78)
                        .background(
                            selected
                                ? ATHLTHTheme.accent
                                : Color.white.opacity(0.72),
                            in: RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                            .stroke(
                                selected
                                    ? Color.clear
                                    : isToday
                                        ? ATHLTHTheme.accent.opacity(0.34)
                                        : Color.black.opacity(0.045),
                                lineWidth: isToday ? 1.3 : 1
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Premium day timeline (release planner presentation)
    private func selectedDayCard(
        plan: TrainingPlan,
        week: TrainingPlanWeek,
        day: TrainingPlanDay
    ) -> some View {
        let ordered = day.sessions.sorted {
            ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture)
        }
        return ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("DAGENS PLAN")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(Color(red: 0.52, green: 0.39, blue: 0.22))
                        Text(displayDayTitle(day, week: week, plan: plan))
                            .font(.system(size: 25, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        Text(daySubtitle(day, week: week, plan: plan))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer()
                    Button {
                        selectedDayID = day.id
                        showingSessionEditor = true
                    } label: {
                        Label("Legg til", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.32, blue: 0.20))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.95, green: 0.92, blue: 0.86),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if ordered.isEmpty {
                    Button {
                        selectedDayID = day.id
                        showingSessionEditor = true
                    } label: {
                        Label("Hviledag · Planlegg en økt", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(Color(red: 0.97, green: 0.96, blue: 0.94),
                                        in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, workout in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(spacing: 5) {
                                    Text(workout.scheduledStart?.formatted(date: .omitted, time: .shortened) ?? "ØKT")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                        .frame(width: 48, alignment: .leading)
                                    Circle()
                                        .strokeBorder(Color(red: 0.60, green: 0.44, blue: 0.25), lineWidth: 2)
                                        .background(Circle().fill(Color.white))
                                        .frame(width: 10, height: 10)
                                    if index < ordered.count - 1 {
                                        Rectangle()
                                            .fill(Color(red: 0.76, green: 0.70, blue: 0.60))
                                            .frame(width: 1, height: 18)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    sessionRow(workout, dayID: day.id)
                                    ATHLTHReleasePlanTimeline(workout: workout)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.bottom, 12)
                        }
                    }
                }
            }
        }
    }

    private func weekOverview(
        _ plan: TrainingPlan,
        week: TrainingPlanWeek
    ) -> some View {
        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ukeoversikt")
                            .font(.system(size: 23, weight: .semibold, design: .serif))
                        Text("Velg en dag for økter, detaljer og redigering.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(
                        ATHLTHLocalization.format(
                                english: "%d total",
                                norwegian: "%d totalt",
                                week.days.reduce(0) { $0 + $1.sessions.count }
                            )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.50, green: 0.36, blue: 0.20))
                }

                VStack(spacing: 0) {
                    ForEach(
                        Array(week.days.enumerated()),
                        id: \.element.id
                    ) { index, day in
                        Button {
                            selectedDayID = day.id
                            studioSection = .day
                        } label: {
                            HStack(spacing: 12) {
                                Text(
                                    shortDayLabel(
                                        day,
                                        week: week,
                                        plan: plan
                                    )
                                )
                                .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    selectedDayID == day.id
                                        ? ATHLTHTheme.accent
                                        : ATHLTHTheme.mutedText
                                )
                                .frame(
                                    width: 34,
                                    alignment: .leading
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        day.sessions.isEmpty
                                            ? "Hviledag"
                                            : day.sessions
                                                .map(\.title)
                                                .joined(
                                                    separator: " · "
                                                )
                                    )
                                    .font(
                                        .subheadline.weight(.semibold)
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )
                                    .lineLimit(1)

                                    if let date = date(
                                        for: day,
                                        in: week,
                                        plan: plan
                                    ) {
                                        Text(
                                            date.formatted(
                                                .dateTime
                                                    .month(.abbreviated)
                                                    .day()
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if !day.sessions.isEmpty {
                                    Text("\(day.sessions.count)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(
                                            ATHLTHTheme.accent
                                        )
                                        .frame(width: 24, height: 24)
                                        .background(
                                            ATHLTHTheme.accentSoft,
                                            in: Circle()
                                        )
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < week.days.count - 1 {
                            Divider().overlay(Color(red: 0.82, green: 0.78, blue: 0.72).opacity(0.5))
                        }
                    }
                }
            }
        }
    }

    private var emptyPlanState: some View {
        ATHLTHUnifiedCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 13) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 15)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Build your training plan")
                            .font(.title3.weight(.bold))

                        Text(
                            "Start simple, or build an advanced multi-week program with exact workouts, routes, exercises and targets."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        showingProgramCreation = true
                    } label: {
                        Label("Create Plan", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)

                    Button {
                        showingAllPlans = true
                    } label: {
                        Label("All Plans", systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func sessionRow(
        _ workout: PlannedSession,
        dayID: UUID
    ) -> some View {
        let planID = displayedPlan?.id
        let completed =
            planID.map {
                session.isPlanSessionCompleted(
                    planID: $0,
                    sessionID: workout.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                )
            } ?? false

        return HStack(spacing: 8) {
            Button {
                selectedWorkout = workout
            } label: {
                HStack(spacing: 11) {
                    Image(
                        systemName: completed
                            ? "checkmark.circle.fill"
                            : workout.kind.systemImage
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        completed
                            ? ATHLTHTheme.vitality
                            : ATHLTHTheme.accent
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        (
                            completed
                                ? ATHLTHTheme.vitalitySoft
                                : ATHLTHTheme.accentSoft
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(workout.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    completed
                                        ? ATHLTHTheme.mutedText
                                        : ATHLTHTheme.primaryText
                                )

                            if completed {
                                Text("Completed")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(ATHLTHTheme.vitality)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        ATHLTHTheme.vitalitySoft,
                                        in: Capsule()
                                    )
                            } else if let start = workout.scheduledStart {
                                Text(
                                    start.formatted(
                                        date: .omitted,
                                        time: .shortened
                                    )
                                )
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accent)
                            }
                        }

                        Text(sessionSummary(workout))
                            .font(.caption)
                            .foregroundStyle(
                                completed
                                    ? ATHLTHTheme.mutedText.opacity(0.72)
                                    : Color.secondary
                            )
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(11)
                .background(
                    completed
                        ? ATHLTHTheme.vitalitySoft.opacity(0.28)
                        : Color.primary.opacity(0.025),
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)

            Menu {
                if let planID,
                   let plan = displayedPlan,
                   session.trainingPlanStatus(plan) == .active {
                    Button {
                        session.setPlanSessionManuallyCompleted(
                            planID: planID,
                            sessionID: workout.id,
                            completed: !completed
                        )
                    } label: {
                        Label(
                            completed
                                ? "Mark as Not Completed"
                                : "Mark as Completed",
                            systemImage: completed
                                ? "arrow.uturn.backward.circle"
                                : "checkmark.circle"
                        )
                    }

                    Divider()
                }

                Button(role: .destructive) {
                    if let planID = displayedPlan?.id {
                        session.removeSession(
                            workout.id,
                            fromDay: dayID,
                            inPlan: planID
                        )
                    }
                } label: {
                    Label("Delete Workout", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private func plannerMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 30, height: 30)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func allSessions(
        in plan: TrainingPlan
    ) -> [PlannedSession] {
        plan.weeks
            .flatMap(\.days)
            .flatMap(\.sessions)
    }

    private func trainingDayCount(
        in plan: TrainingPlan
    ) -> Int {
        plan.weeks
            .flatMap(\.days)
            .filter { !$0.sessions.isEmpty }
            .count
    }

    private func plannedDurationText(
        _ plan: TrainingPlan
    ) -> String {
        let minutes = allSessions(in: plan)
            .compactMap(\.durationMinutes)
            .reduce(0, +)

        guard minutes > 0 else { return "—" }

        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0
            ? "\(hours)h"
            : "\(hours)h \(remaining)m"
    }

    private func plannedDistanceText(
        _ plan: TrainingPlan
    ) -> String {
        let distance = allSessions(in: plan)
            .compactMap(\.targetDistanceKilometers)
            .reduce(0, +)

        guard distance > 0 else { return "—" }

        return String(format: "%.1f km", distance)
    }

    private func planTimelineText(
        _ plan: TrainingPlan
    ) -> String {
        guard let start = plan.startDate else {
            return "\(plan.weeks.count) weeks · \(plan.visibility.title)"
        }

        let end = Calendar.current.date(
            byAdding: .day,
            value: max(plan.weeks.count * 7 - 1, 0),
            to: start
        ) ?? start

        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted)) · \(plan.weeks.count) weeks"
    }

    private func daySubtitle(
        _ day: TrainingPlanDay,
        week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> String {
        if let date = date(for: day, in: week, plan: plan) {
            return date.formatted(
                .dateTime
                    .weekday(.wide)
                    .month(.wide)
                    .day()
            )
        }

        return "Week \(week.weekNumber) · \(day.sessions.count) planned"
    }

    private func displayDayTitle(
        _ day: TrainingPlanDay,
        week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> String {
        guard let date = date(
            for: day,
            in: week,
            plan: plan
        ) else {
            return day.title
        }

        let weekday = Calendar.current.component(
            .weekday,
            from: date
        )

        let titles = [
            "Sunday",
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday"
        ]

        guard (1...7).contains(weekday) else {
            return day.title
        }

        return titles[weekday - 1]
    }

    private func shortDayLabel(
        _ day: TrainingPlanDay,
        week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> String {
        String(
            displayDayTitle(
                day,
                week: week,
                plan: plan
            )
            .prefix(3)
        )
        .uppercased()
    }

    private func date(
        for day: TrainingPlanDay,
        in week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> Date? {
        guard let startDate = plan.startDate else {
            return nil
        }

        let offset =
            max(week.weekNumber - 1, 0) * 7 +
            max(day.dayIndex - 1, 0)

        return Calendar.current.date(
            byAdding: .day,
            value: offset,
            to: Calendar.current.startOfDay(for: startDate)
        )
    }

    private func selectedWeek(
        in plan: TrainingPlan
    ) -> TrainingPlanWeek? {
        if let selectedWeekID,
           let selected = plan.weeks.first(
                where: { $0.id == selectedWeekID }
           ) {
            return selected
        }

        return bestWeek(in: plan) ?? plan.weeks.first
    }

    private func selectedDay(
        in week: TrainingPlanWeek
    ) -> TrainingPlanDay? {
        if let selectedDayID,
           let selected = week.days.first(
                where: { $0.id == selectedDayID }
           ) {
            return selected
        }

        return week.days.first
    }

    private func bestWeek(
        in plan: TrainingPlan
    ) -> TrainingPlanWeek? {
        guard let startDate = plan.startDate else {
            return plan.weeks.first
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents(
            [.day],
            from: start,
            to: today
        ).day ?? 0

        guard days >= 0 else {
            return plan.weeks.first
        }

        let targetNumber = (days / 7) + 1
        return plan.weeks.first {
            $0.weekNumber == targetNumber
        } ?? plan.weeks.last
    }

    private func requestWeekCopy(
        from week: TrainingPlanWeek,
        plan: TrainingPlan,
        scope: TrainingWeekCopyScope,
        summary: TrainingWeekCopySummary,
        progression: TrainingWeekProgressionMode = .unchanged
    ) {
        guard summary.hasWork else { return }
        pendingWeekCopy = PendingWeekCopy(
            planID: plan.id,
            sourceWeekID: week.id,
            sourceWeekNumber: week.weekNumber,
            scope: scope,
            progression: progression,
            summary: summary
        )
    }

    private func progressionDescription(
        _ progression: TrainingWeekProgressionMode,
        norwegian: Bool
    ) -> String {
        switch progression {
        case .unchanged:
            return norwegian
                ? "Målene kopieres uendret."
                : "Targets are copied unchanged."
        case .addWeightPerWeek(let kilograms):
            return norwegian
                ? "Forhåndsutfylte styrkevekter økes med \(kilograms.formatted()) kg per uke. Tomme vektfelt forblir tomme."
                : "Pre-filled strength weights increase by \(kilograms.formatted()) kg per week; empty weights stay empty."
        case .addRepsPerWeek(let repetitions):
            return norwegian
                ? "Repetisjonsmål økes med \(repetitions) per uke. Tidsbaserte mål endres ikke."
                : "Repetition targets increase by \(repetitions) per week; timed targets stay unchanged."
        case .fourWeekStrengthBlock:
            return norwegian
                ? "Fireukersblokk for styrke: +2,5 kg per oppbyggingsuke der vekter allerede er satt. Hver fjerde uke er deload med omtrent 40 % færre arbeidssett og ca. 10 % lavere vekt. Løpeøkter og eksisterende økter endres ikke."
                : "Four-week strength block: +2.5 kg per build week only for pre-filled weights. Every fourth week is a deload with around 40% fewer working sets and roughly 10% lighter load. Running and existing sessions are unchanged."
        }
    }

    private func requestWeekRemoval(
        _ week: TrainingPlanWeek,
        from plan: TrainingPlan
    ) {
        let sessionCount = week.days.reduce(0) {
            $0 + $1.sessions.count
        }

        if sessionCount == 0 {
            removeWeek(week, from: plan)
        } else {
            weekPendingRemoval = week
        }
    }

    private func removeWeek(
        _ week: TrainingPlanWeek,
        from plan: TrainingPlan
    ) {
        guard plan.weeks.count > 1,
              let removedIndex = plan.weeks.firstIndex(
                where: { $0.id == week.id }
              )
        else {
            return
        }

        session.removeWeekFromTrainingPlan(
            planID: plan.id,
            weekID: week.id
        )

        guard let updatedPlan =
                session.trainingPlan(withID: plan.id),
              !updatedPlan.weeks.isEmpty
        else {
            syncSelection()
            return
        }

        let targetIndex = min(
            removedIndex,
            updatedPlan.weeks.count - 1
        )
        let targetWeek = updatedPlan.weeks[targetIndex]

        selectedWeekID = targetWeek.id
        selectBestDay(
            in: targetWeek,
            plan: updatedPlan
        )
        weekPendingRemoval = nil
    }

    private func selectBestDay(
        in week: TrainingPlanWeek,
        plan: TrainingPlan
    ) {
        if let today = week.days.first(
            where: { day in
                guard let date = date(
                    for: day,
                    in: week,
                    plan: plan
                ) else {
                    return false
                }

                return Calendar.current.isDateInToday(date)
            }
        ) {
            selectedDayID = today.id
        } else {
            selectedDayID = week.days.first?.id
        }
    }

    private func syncSelection() {
        guard let plan = displayedPlan,
              let week = bestWeek(in: plan) ?? plan.weeks.first
        else {
            selectedWeekID = nil
            selectedDayID = nil
            return
        }

        selectedWeekID = week.id
        selectBestDay(in: week, plan: plan)
    }

    private func reconcileSelection() {
        guard let plan = displayedPlan else {
            selectedWeekID = nil
            selectedDayID = nil
            return
        }

        guard let week = selectedWeek(in: plan) else {
            syncSelection()
            return
        }

        selectedWeekID = week.id

        if let selectedDayID,
           week.days.contains(where: { $0.id == selectedDayID }) {
            return
        }

        selectBestDay(in: week, plan: plan)
    }

    private func sessionSummary(
        _ workout: PlannedSession
    ) -> String {
        var parts: [String] = []

        let runningWorkouts = workout.resolvedRunningWorkouts

        if !runningWorkouts.isEmpty {
            parts.append(
                runningWorkouts.count == 1
                    ? runningWorkouts[0].type.title
                    : "\(runningWorkouts.count) run workouts"
            )

            if let duration = workout.durationMinutes {
                parts.append("\(duration) min")
            }

            if let distance = workout.targetDistanceKilometers {
                parts.append(
                    String(format: "%.1f km", distance)
                )
            }
        } else {
            if let duration = workout.durationMinutes {
                parts.append("\(duration) min")
            }

            if let distance = workout.targetDistanceKilometers {
                parts.append(
                    String(format: "%.1f km", distance)
                )
            }
        }

        if !workout.exercises.isEmpty {
            parts.append(
                "\(workout.exercises.count) exercises"
            )
        }

        if workout.routeID != nil {
            parts.append("Route")
        }

        return parts.isEmpty
            ? workout.kind.title
            : parts.joined(separator: " · ")
    }
}

struct AllTrainingPlansView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    @State private var showingCreatePlan = false
    @State private var editingPlan: TrainingPlan?
    @State private var planToOpen: TrainingPlan?
    @State private var planPendingDeletion: TrainingPlan?

    private var activePlans: [TrainingPlan] {
        session.trainingPlans.filter {
            session.trainingPlanStatus($0) == .active
        }
    }

    private var upcomingPlans: [TrainingPlan] {
        session.trainingPlans
            .filter {
                session.trainingPlanStatus($0) == .upcoming
            }
            .sorted {
                ($0.startDate ?? .distantFuture) <
                ($1.startDate ?? .distantFuture)
            }
    }

    private var completedPlans: [TrainingPlan] {
        session.trainingPlans
            .filter {
                session.trainingPlanStatus($0) == .completed
            }
            .sorted {
                (session.trainingPlanEndDate($0) ?? .distantPast) >
                (session.trainingPlanEndDate($1) ?? .distantPast)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if session.trainingPlans.isEmpty {
                        ContentUnavailableView {
                            Label(
                                "No training plans yet",
                                systemImage: "calendar.badge.plus"
                            )
                        } description: {
                            Text(
                                "Create your first dated plan. ATHLTH keeps only the plan covering today active."
                            )
                        } actions: {
                            Button("Create Plan") {
                                showingCreatePlan = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accent)
                        }
                        .padding(.top, 36)
                    } else {
                        planSection(
                            "Active",
                            plans: activePlans,
                            status: .active
                        )
                        planSection(
                            "Upcoming",
                            plans: upcomingPlans,
                            status: .upcoming
                        )
                        planSection(
                            "Completed",
                            plans: completedPlans,
                            status: .completed
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.accent.opacity(0.45)
                )
            )
            .navigationTitle("All Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreatePlan = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create training plan")
                }
            }
            .sheet(isPresented: $showingCreatePlan) {
                TrainingPlanCreationView()
            }
            .sheet(item: $editingPlan) { plan in
                PlanMetadataEditorView(plan: plan)
            }
            .sheet(item: $planToOpen) { plan in
                NavigationStack {
                    ScrollView {
                        AdvancedPlannerView(
                            planID: plan.id
                        )
                        .padding()
                    }
                    .background(
                        ATHLTHPremiumCanvas(
                            accent: ATHLTHTheme.accent.opacity(0.45)
                        )
                    )
                    .navigationTitle(plan.title)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .confirmationDialog(
                planPendingDeletion.map {
                    "Delete \($0.title)?"
                } ?? "Delete training plan?",
                isPresented: Binding(
                    get: { planPendingDeletion != nil },
                    set: { presented in
                        if !presented {
                            planPendingDeletion = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let plan = planPendingDeletion {
                    Button("Delete Plan", role: .destructive) {
                        goalStore.setLinkedPlan(
                            plan.id,
                            goalIDs: []
                        )
                        session.deleteTrainingPlan(plan.id)
                        planPendingDeletion = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    planPendingDeletion = nil
                }
            } message: {
                Text(
                    "This removes the plan and its future schedule. Completed workout history is kept."
                )
            }
            .onAppear {
                session.refreshActivePlanForToday()
            }
        }
    }

    @ViewBuilder
    private func planSection(
        _ title: String,
        plans: [TrainingPlan],
        status: TrainingPlanTimingStatus
    ) -> some View {
        if !plans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)

                ForEach(plans) { plan in
                    planCard(plan, status: status)
                }
            }
        }
    }

    private func planCard(
        _ plan: TrainingPlan,
        status: TrainingPlanTimingStatus
    ) -> some View {
        ATHLTHUnifiedCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon(status))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusTint(status))
                    .frame(width: 42, height: 42)
                    .background(
                        statusTint(status).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 13)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(plan.title)
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)

                        Text(statusTitle(status))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(statusTint(status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                statusTint(status).opacity(0.10),
                                in: Capsule()
                            )
                    }

                    Text(planDateText(plan))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(
                        plan.weeks.count == 1
                            ? "1 week"
                            : "\(plan.weeks.count) weeks"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    if !plan.summary
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty {
                        Text(plan.summary)
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText.opacity(0.72)
                            )
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 6)

                Menu {
                    Button {
                        editingPlan = plan
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }

                    Button {
                        _ = session.duplicateTrainingPlan(plan.id)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        planPendingDeletion = plan
                    } label: {
                        Label("Delete Plan", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }

            Button {
                if status == .active {
                    dismiss()
                } else {
                    planToOpen = plan
                }
            } label: {
                Label(
                    status == .active
                        ? "Open Current Plan"
                        : "Open Plan",
                    systemImage: "arrow.right"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ATHLTHTheme.accent)
            .padding(.top, 10)
        }
    }

    private func planDateText(
        _ plan: TrainingPlan
    ) -> String {
        guard let startDate = plan.startDate else {
            return "No dates"
        }

        let start = startDate.formatted(
            date: .abbreviated,
            time: .omitted
        )

        guard let endDate = session.trainingPlanEndDate(plan) else {
            return start
        }

        return "\(start) – " +
            endDate.formatted(
                date: .abbreviated,
                time: .omitted
            )
    }

    private func statusTitle(
        _ status: TrainingPlanTimingStatus
    ) -> String {
        switch status {
        case .active: return "ACTIVE"
        case .upcoming: return "UPCOMING"
        case .completed: return "COMPLETED"
        case .unscheduled: return "UNSCHEDULED"
        }
    }

    private func statusIcon(
        _ status: TrainingPlanTimingStatus
    ) -> String {
        switch status {
        case .active: return "play.circle.fill"
        case .upcoming: return "calendar.badge.clock"
        case .completed: return "checkmark.circle.fill"
        case .unscheduled: return "calendar"
        }
    }

    private func statusTint(
        _ status: TrainingPlanTimingStatus
    ) -> Color {
        switch status {
        case .active: return ATHLTHTheme.vitality
        case .upcoming: return ATHLTHTheme.accent
        case .completed: return ATHLTHTheme.mutedText
        case .unscheduled: return .orange
        }
    }
}


struct TrainingPlanManagerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let onOpenCalendar: () -> Void

    @State private var showingProgramCreation = false
    @State private var showingAllPlans = false
    @State private var programToStart: TrainingPlan?
    @State private var scheduledPlanToOpen: TrainingPlan?
    @State private var aiMode: AIProgramGenerationMode?
    @State private var showingPlanAdaptation = false
    @State private var showingAISubscriptionOffer = false

    init(onOpenCalendar: @escaping () -> Void = {}) {
        self.onOpenCalendar = onOpenCalendar
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR TRAINING PLAN")
                        .font(.caption2.weight(.bold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(
                        session.activePlan == nil
                            ? "Build what comes next."
                            : "Keep building."
                    )
                    .font(
                        .system(
                            size: 30,
                            weight: .bold,
                            design: .serif
                        )
                    )

                    Text(
                        session.activePlan == nil
                            ? "Create it yourself or let ATHLTH Coach shape a draft around your goals and everyday life."
                            : "Your active plan stays in focus. Create another plan or ask Coach to help when life changes."
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                HStack(spacing: 10) {
                    Button {
                        showingProgramCreation = true
                    } label: {
                        Label("Create plan", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .background(
                                Color.white.opacity(0.84),
                                in: RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        openAI(.generate)
                    } label: {
                        Label("ATHLTH Coach", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(.white)
                            .background(
                                ATHLTHTheme.accentDeep,
                                in: RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 18) {
                    Button {
                        showingAllPlans = true
                    } label: {
                        Label(
                            "All plans",
                            systemImage: "square.stack.3d.up"
                        )
                    }

                    if session.activePlan != nil {
                        Button {
                            openPlanAdaptation()
                        } label: {
                            Label(
                                "Adapt plan",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }

                        Button {
                            openAI(.complete)
                        } label: {
                            Label(
                                "Fill empty days",
                                systemImage: "wand.and.stars"
                            )
                        }
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .padding(2)

            if let nextPlan =
                session.nextTrainingPlan {
                upcomingPlanCard(nextPlan)
            }

            if !session.planTemplates.isEmpty {
                ATHLTHUnifiedCard {
                    ATHLTHSectionHeader(
                        title: "Saved Programs",
                        actionTitle: "\(session.planTemplates.count)"
                    )

                    VStack(spacing: 10) {
                        ForEach(session.planTemplates) { template in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(
                                        template.tags.isEmpty
                                            ? "\(template.weeks.count) weeks"
                                            : "\(template.weeks.count) weeks · \(template.tags.joined(separator: ", "))"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }

                                Spacer()

                                Button("Start") {
                                    programToStart = template
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(role: .destructive) {
                                    session.deletePlanTemplate(template.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }

        }
        .sheet(isPresented: $showingAllPlans) {
            AllTrainingPlansView()
        }
        .sheet(isPresented: $showingProgramCreation) {
            TrainingPlanCreationView()
        }
        .sheet(item: $scheduledPlanToOpen) { plan in
            NavigationStack {
                ScrollView {
                    AdvancedPlannerView(
                        planID: plan.id
                    )
                    .padding()
                }
                .background(
                    ATHLTHPremiumCanvas(
                        accent:
                            ATHLTHTheme
                                .accent
                                .opacity(0.35)
                    )
                )
                .navigationTitle(plan.title)
                .navigationBarTitleDisplayMode(
                    .inline
                )
            }
        }
        .sheet(item: $programToStart) { program in
            ProgramStartView(
                program: program,
                onStarted: onOpenCalendar
            )
        }
        .sheet(item: $aiMode) { mode in
            AIProgramBuilderView(mode: mode)
        }
        .sheet(isPresented: $showingPlanAdaptation) {
            CoachPlanAdaptationView()
        }
        .sheet(isPresented: $showingAISubscriptionOffer) {
            SubscriptionOfferView {
                session.applyStoreKitEntitlement(
                    subscriptionStore.activeEntitlement
                )

                if session.canAccess(.aiTrainingPrograms) {
                    showingAISubscriptionOffer = false
                }
            }
            .environmentObject(subscriptionStore)
        }
    }

    private func upcomingPlanCard(
        _ plan: TrainingPlan
    ) -> some View {
        Button {
            scheduledPlanToOpen = plan
        } label: {
            ATHLTHUnifiedCard {
                HStack(spacing: 13) {
                    Image(
                        systemName:
                            "calendar.badge.clock"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accent
                    )
                    .frame(
                        width: 46,
                        height: 46
                    )
                    .background(
                        ATHLTHTheme.accentSoft,
                        in:
                            RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "NEXT PLAN",
                                norwegian:
                                    "NESTE PLAN"
                            )
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .tracking(1.4)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        Text(plan.title)
                            .font(
                                .headline.weight(
                                    .semibold
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .lineLimit(1)

                        if let start =
                            plan.startDate {
                            Text(
                                ATHLTHLocalization.format(
                                    english:
                                        "Starts %@",
                                    norwegian:
                                        "Starter %@",
                                    start.formatted(
                                        date:
                                            .abbreviated,
                                        time:
                                            .omitted
                                    )
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                    }

                    Spacer()

                    VStack(
                        alignment: .trailing,
                        spacing: 4
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Upcoming",
                                norwegian: "Kommende"
                            )
                        )
                        .font(
                            .caption2.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accent
                        )
                        .padding(
                            .horizontal,
                            8
                        )
                        .padding(.vertical, 4)
                        .background(
                            ATHLTHTheme
                                .accentSoft,
                            in: Capsule()
                        )

                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var creationButtons: some View {
        Button {
            showingProgramCreation = true
        } label: {
            Label("Create a plan", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
            openAI(.generate)
        } label: {
            Label("ATHLTH Coach", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(ATHLTHTheme.accent)
    }

    private func openPlanAdaptation() {
        guard session.canAccess(.aiTrainingPrograms) else {
            showingAISubscriptionOffer = true
            return
        }

        showingPlanAdaptation = true
    }

    private func openAI(_ mode: AIProgramGenerationMode) {
        guard session.canAccess(.aiTrainingPrograms) else {
            showingAISubscriptionOffer = true
            return
        }

        aiMode = mode
    }
}

private struct ProgramStartView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let program: TrainingPlan
    let onStarted: () -> Void

    @State private var startDate =
        Calendar.current.startOfDay(for: Date())

    private var endDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(program.weeks.count * 7 - 1, 0),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private var conflictingPlan: TrainingPlan? {
        session.trainingPlanConflict(
            startDate: startDate,
            endDate: endDate
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    Text(program.title)
                        .font(.headline)

                    if !program.summary.isEmpty {
                        Text(program.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent(
                        "Length",
                        value: "\(program.weeks.count) weeks"
                    )
                }

                Section("Add to Calendar") {
                    DatePicker(
                        "Start date",
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    LabeledContent(
                        "Ends",
                        value: endDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )

                    Text(
                        "ATHLTH adds this program to your plan timeline. It becomes active automatically when today falls inside this date range."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let conflict = conflictingPlan {
                    Section("Schedule Conflict") {
                        Label(
                            ATHLTHLocalization.format(
                                english: "Overlaps with %@",
                                norwegian: "Overlapper med %@",
                                conflict.title
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)

                        Text(
                            "Choose a start date after the existing plan ends. Only one training plan can be active on a given date."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Start Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        guard let created =
                                session.usePlanTemplate(
                                    program.id,
                                    startDate: startDate
                                )
                        else {
                            return
                        }

                        dismiss()

                        if session.trainingPlanStatus(created) == .active {
                            onStarted()
                        }
                    }
                    .disabled(conflictingPlan != nil)
                }
            }
            .onAppear {
                startDate = session.suggestedTrainingPlanStartDate
            }
        }
    }
}

private enum ProgramTimelineMode: String, CaseIterable, Identifiable {
    case weeks
    case endDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeks: return "Weeks"
        case .endDate: return "End date"
        }
    }
}

private enum TrainingPlanCreationMode: String, Identifiable {
    case simple
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Quick Start"
        case .advanced: return "Build from Scratch"
        }
    }

    var subtitle: String {
        switch self {
        case .simple:
            return "Create a lightweight starter rhythm."
        case .advanced:
            return "Start with a blank calendar and shape every week yourself."
        }
    }

    var icon: String {
        switch self {
        case .simple: return "wand.and.stars"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

private enum SimpleTrainingPlanFocus: String, CaseIterable, Identifiable {
    case balanced
    case running
    case strength
    case hybrid
    case walking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .running: return "Running"
        case .strength: return "Strength"
        case .hybrid: return "Hybrid"
        case .walking: return "Walking"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced:
            return "A mix of strength, running and walking"
        case .running:
            return "Running first, with mobility between sessions"
        case .strength:
            return "Strength first, with mobility support"
        case .hybrid:
            return "Alternate strength and running"
        case .walking:
            return "Walking volume with supporting strength"
        }
    }

    var icon: String {
        switch self {
        case .balanced: return "circle.grid.cross"
        case .running: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .hybrid: return "arrow.triangle.2.circlepath"
        case .walking: return "figure.walk"
        }
    }

    var pattern: [WorkoutKind] {
        switch self {
        case .balanced:
            return [.strength, .running, .walking]
        case .running:
            return [.running, .running, .mobility]
        case .strength:
            return [.strength, .strength, .mobility]
        case .hybrid:
            return [.strength, .running]
        case .walking:
            return [.walking, .strength]
        }
    }
}

struct SimpleTrainingPlanCreationView: View {
    var body: some View {
        TrainingPlanCreationView(initialMode: .simple)
    }
}

struct AdvancedTrainingPlanCreationView: View {
    var body: some View {
        TrainingPlanCreationView(initialMode: .advanced)
    }
}

struct TrainingPlanCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    @State private var creationMode: TrainingPlanCreationMode?
    private let showsSourceChooser: Bool

    init() {
        showsSourceChooser = true
        _creationMode = State(initialValue: nil)
    }

    fileprivate init(
        initialMode: TrainingPlanCreationMode
    ) {
        showsSourceChooser = false
        _creationMode = State(initialValue: initialMode)
    }

    @State private var title = "My Program"
    @State private var summary = ""
    @State private var simpleFocus: SimpleTrainingPlanFocus = .hybrid
    @State private var simpleSessionsPerWeek = 4
    @State private var simpleWeekCount = 8

    @State private var timelineMode: ProgramTimelineMode = .weeks
    @State private var weekCount = 4
    @State private var customWeeks = 12
    @State private var useCustomWeeks = false
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var endDate = Calendar.current.date(
        byAdding: .day,
        value: 27,
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()
    @State private var visibility: ProfileVisibility = .privateOnly
    @State private var selectedGoalIDs: Set<UUID> = []
    @State private var creationError: String?

    private let quickDurations = [1, 4, 8, 12]

    private var resolvedWeeks: Int {
        switch timelineMode {
        case .weeks:
            return useCustomWeeks ? customWeeks : weekCount
        case .endDate:
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: max(endDate, startDate))
            let days = max(
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: end
                ).day ?? 0,
                0
            )
            return min(
                max(Int(ceil(Double(days + 1) / 7.0)), 1),
                52
            )
        }
    }

    private var resolvedEndDate: Date {
        let calendar = Calendar.current

        switch timelineMode {
        case .weeks:
            return calendar.date(
                byAdding: .day,
                value: max(resolvedWeeks * 7 - 1, 0),
                to: calendar.startOfDay(for: startDate)
            ) ?? startDate
        case .endDate:
            return calendar.startOfDay(for: endDate)
        }
    }

    private var simpleEndDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(simpleWeekCount * 7 - 1, 0),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private var proposedEndDate: Date {
        creationMode == .simple
            ? simpleEndDate
            : resolvedEndDate
    }

    private var conflictingPlan: TrainingPlan? {
        guard creationMode != nil else {
            return nil
        }

        return session.trainingPlanConflict(
            startDate: startDate,
            endDate: proposedEndDate
        )
    }

    var body: some View {
        ATHLTHTrainingPlanBuilderFlow(
            startsAtSourceChoice:
                showsSourceChooser,
            initialAdvanced:
                creationMode == .advanced
        )
    }

    private var navigationTitle: String {
        switch creationMode {
        case .simple:
            return "Quick Start"
        case .advanced:
            return "Build from Scratch"
        case nil:
            return "New Training Plan"
        }
    }

    private var creationModeChoice: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("CREATE A TRAINING PLAN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text("Start your way")
                        .font(
                            .system(
                                size: 34,
                                weight: .semibold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        "There are only two useful starting points: build a blank plan yourself, or choose a complete plan from the Library. Both stay fully editable afterwards."
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineSpacing(2)
                }
                .padding(.bottom, 2)

                Button {
                    beginScratchCreation()
                } label: {
                    creationPathCard(
                        eyebrow: "BLANK PLAN",
                        title: "Build from scratch",
                        subtitle:
                            "Choose the dates and goals, then add every workout exactly where you want it.",
                        badge: "FULL CONTROL",
                        icon: "calendar.badge.plus",
                        accent: ATHLTHTheme.accentDeep,
                        prominent: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TrainingPlanLibraryView {
                        dismiss()
                    }
                } label: {
                    creationPathCard(
                        eyebrow: "TRAINING LIBRARY",
                        title: "Choose a training plan",
                        subtitle:
                            "Browse curated running, strength and hybrid plans, preview every week and make one yours.",
                        badge: "READY TO USE",
                        icon: "square.stack.3d.up.fill",
                        accent: ATHLTHTheme.premiumGold,
                        prominent: false
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text(
                        "Nothing is locked. After creation you can move days, replace workouts, edit exercises, routes, targets and times."
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.38)
            )
        )
    }

    private func creationPathCard(
        eyebrow: String,
        title: String,
        subtitle: String,
        badge: String,
        icon: String,
        accent: Color,
        prominent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(
                        prominent ? Color.white : accent
                    )
                    .frame(width: 56, height: 56)
                    .background(
                        prominent
                            ? Color.white.opacity(0.14)
                            : accent.opacity(0.11),
                        in: RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                        .stroke(
                            prominent
                                ? Color.white.opacity(0.20)
                                : Color.white.opacity(0.92),
                            lineWidth: 0.8
                        )
                    }

                Spacer()

                Text(badge)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.86)
                            : accent
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        prominent
                            ? Color.white.opacity(0.12)
                            : accent.opacity(0.09),
                        in: Capsule()
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.68)
                            : accent.opacity(0.85)
                    )

                Text(title)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.76)
                            : ATHLTHTheme.mutedText
                    )
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
            }

            HStack {
                Text(
                    prominent
                        ? "Empty calendar · your structure"
                        : "Preview first · personalise after"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    prominent
                        ? Color.white.opacity(0.78)
                        : ATHLTHTheme.primaryText.opacity(0.68)
                )

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : accent
                    )
                    .frame(width: 34, height: 34)
                    .background(
                        prominent
                            ? Color.white.opacity(0.14)
                            : accent.opacity(0.09),
                        in: Circle()
                    )
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors:
                    prominent
                        ? [
                            ATHLTHTheme.accentDeep,
                            ATHLTHTheme.accentDeep.opacity(0.88)
                        ]
                        : [
                            Color.white.opacity(0.98),
                            accent.opacity(0.055)
                        ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                prominent
                    ? Color.white.opacity(0.12)
                    : Color.white.opacity(0.96),
                lineWidth: 1
            )
        }
        .shadow(
            color: prominent
                ? ATHLTHTheme.accentDeep.opacity(0.20)
                : Color.black.opacity(0.055),
            radius: prominent ? 20 : 14,
            x: 0,
            y: prominent ? 10 : 7
        )
    }

    private func beginScratchCreation() {
        creationMode = .advanced

        let suggested = session.suggestedTrainingPlanStartDate
        startDate = suggested
        endDate = Calendar.current.date(
            byAdding: .day,
            value: 27,
            to: suggested
        ) ?? suggested
    }

    private var simpleForm: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                builderIntro(
                    eyebrow: "QUICK START",
                    title: "Set the rhythm",
                    subtitle:
                        "ATHLTH creates a lightweight starting schedule. You can still rebuild every workout afterwards.",
                    icon: "wand.and.stars",
                    accent: ATHLTHTheme.vitality
                )

                creationPanel(
                    eyebrow: "01 · BASICS",
                    title: "Plan & focus",
                    subtitle: "Name the plan and choose the training bias.",
                    icon: "scope",
                    accent: ATHLTHTheme.vitality
                ) {
                    VStack(spacing: 12) {
                        premiumTextField(
                            "Plan name",
                            text: $title
                        )

                        DatePicker(
                            "Start date",
                            selection: $startDate,
                            displayedComponents: .date
                        )
                        .font(.subheadline.weight(.semibold))

                        Divider()

                        Picker("Training focus", selection: $simpleFocus) {
                            ForEach(SimpleTrainingPlanFocus.allCases) { focus in
                                Label(
                                    focus.title,
                                    systemImage: focus.icon
                                )
                                .tag(focus)
                            }
                        }

                        HStack(spacing: 9) {
                            Image(systemName: simpleFocus.icon)
                                .foregroundStyle(ATHLTHTheme.vitality)

                            Text(simpleFocus.subtitle)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)

                            Spacer()
                        }
                    }
                }

                creationPanel(
                    eyebrow: "02 · WEEKLY RHYTHM",
                    title: "\(simpleSessionsPerWeek) sessions per week",
                    subtitle:
                        "ATHLTH spreads the sessions across the week. You can move them at any time.",
                    icon: "calendar.day.timeline.left",
                    accent: ATHLTHTheme.accent
                ) {
                    VStack(spacing: 13) {
                        Stepper(
                            "\(simpleSessionsPerWeek) sessions",
                            value: $simpleSessionsPerWeek,
                            in: 2...6
                        )

                        HStack(spacing: 7) {
                            ForEach(
                                Array(simplePreviewKinds.enumerated()),
                                id: \.offset
                            ) { index, kind in
                                VStack(spacing: 6) {
                                    Image(systemName: kind.systemImage)
                                        .font(.system(size: 16, weight: .semibold))

                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            ATHLTHTheme.accentSoft,
                                            Color.white.opacity(0.72)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    in: RoundedRectangle(
                                        cornerRadius: 13,
                                        style: .continuous
                                    )
                                )
                            }
                        }
                    }
                }

                creationPanel(
                    eyebrow: "03 · LENGTH",
                    title: "How long is the plan?",
                    subtitle: "Pick a duration. You can extend or shorten it later.",
                    icon: "calendar.badge.clock",
                    accent: ATHLTHTheme.premiumGold
                ) {
                    durationChipGrid(
                        options: [4, 8, 12, 16, 24],
                        selected: simpleWeekCount
                    ) { weeks in
                        simpleWeekCount = weeks
                    }
                }

                if let conflict = conflictingPlan {
                    planConflictCard(
                        conflict,
                        message:
                            "Choose a start date after the existing plan ends. ATHLTH keeps one active plan on each date."
                    )
                }

                createPlanButton(
                    mode: .simple,
                    title: "Create Quick Plan",
                    subtitle: "\(simpleWeekCount) weeks · \(simpleSessionsPerWeek) sessions / week"
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.vitality.opacity(0.20)
            )
        )
    }

    private var advancedForm: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                creationPanel(
                    eyebrow: "01 · IDENTITY",
                    title: "Name the plan",
                    subtitle: "Keep it clear enough to recognise later in My Plans.",
                    icon: "pencil.line",
                    accent: ATHLTHTheme.accent
                ) {
                    VStack(spacing: 12) {
                        premiumTextField(
                            "Program name",
                            text: $title
                        )

                        premiumTextField(
                            "What are you training for?",
                            text: $summary,
                            axis: .vertical
                        )
                        .lineLimit(2...5)

                        Divider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Visibility")
                                    .font(.subheadline.weight(.semibold))

                                Text("Who can see this plan")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()

                            Picker("Visibility", selection: $visibility) {
                                ForEach(ProfileVisibility.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }

                creationPanel(
                    eyebrow: "02 · TIMELINE",
                    title: "Define the plan window",
                    subtitle: "Choose a start date and either a fixed number of weeks or an end date.",
                    icon: "calendar",
                    accent: ATHLTHTheme.premiumGold
                ) {
                    VStack(spacing: 13) {
                        DatePicker(
                            "Start date",
                            selection: $startDate,
                            displayedComponents: .date
                        )
                        .font(.subheadline.weight(.semibold))

                        Picker("Plan by", selection: $timelineMode) {
                            ForEach(ProgramTimelineMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if timelineMode == .weeks {
                            durationChipGrid(
                                options: quickDurations,
                                selected:
                                    useCustomWeeks
                                        ? nil
                                        : weekCount
                            ) { weeks in
                                weekCount = weeks
                                useCustomWeeks = false
                            }

                            Toggle(
                                "Custom plan length",
                                isOn: $useCustomWeeks
                            )

                            if useCustomWeeks {
                                Stepper(
                                    "\(customWeeks) weeks",
                                    value: $customWeeks,
                                    in: 1...52
                                )
                                .padding(.top, 2)
                            }
                        } else {
                            DatePicker(
                                "End date",
                                selection: $endDate,
                                in: startDate...(
                                    Calendar.current.date(
                                        byAdding: .weekOfYear,
                                        value: 52,
                                        to: startDate
                                    ) ?? startDate
                                ),
                                displayedComponents: .date
                            )
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("PROGRAM WINDOW")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1.4)
                                    .foregroundStyle(ATHLTHTheme.mutedText)

                                Text(
                                    "\(resolvedWeeks) " +
                                    (resolvedWeeks == 1 ? "week" : "weeks")
                                )
                                .font(.title3.weight(.bold))
                            }

                            Spacer()

                            Text(
                                "\(startDate.formatted(date: .abbreviated, time: .omitted))\n– \(resolvedEndDate.formatted(date: .abbreviated, time: .omitted))"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if let conflict = conflictingPlan {
                    planConflictCard(
                        conflict,
                        message:
                            "Adjust the dates before creating this plan. ATHLTH keeps one active plan on each date."
                    )
                }

                if !goalStore.goals.isEmpty {
                    creationPanel(
                        eyebrow: "03 · GOALS",
                        title: "Connect goals",
                        subtitle:
                            "Optional. Linking goals makes progress and coaching context more useful.",
                        icon: "scope",
                        accent: ATHLTHTheme.vitality
                    ) {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(goalStore.goals.enumerated()),
                                id: \.offset
                            ) { index, goal in
                                Toggle(
                                    isOn: Binding(
                                        get: {
                                            selectedGoalIDs.contains(goal.id)
                                        },
                                        set: { enabled in
                                            if enabled {
                                                selectedGoalIDs.insert(goal.id)
                                            } else {
                                                selectedGoalIDs.remove(goal.id)
                                            }
                                        }
                                    )
                                ) {
                                    VStack(
                                        alignment: .leading,
                                        spacing: 3
                                    ) {
                                        Text(goal.title)
                                            .font(.subheadline.weight(.semibold))

                                        Text(goal.category.title)
                                            .font(.caption2)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                }
                                .padding(.vertical, 8)

                                if index < goalStore.goals.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                creationPanel(
                    eyebrow: goalStore.goals.isEmpty
                        ? "03 · WHAT COMES NEXT"
                        : "04 · WHAT COMES NEXT",
                    title: "Built for detailed programming",
                    subtitle:
                        "The new plan starts empty. Add only what belongs in it.",
                    icon: "slider.horizontal.3",
                    accent: ATHLTHTheme.accentDeep
                ) {
                    VStack(spacing: 10) {
                        advancedFeatureRow(
                            "Place any workout on any day",
                            icon: "calendar.badge.plus"
                        )
                        advancedFeatureRow(
                            "Strength exercises, sets, reps, load and progression",
                            icon: "dumbbell.fill"
                        )
                        advancedFeatureRow(
                            "Structured running, distance and routes",
                            icon: "figure.run"
                        )
                        advancedFeatureRow(
                            "Recovery, notes and scheduled time",
                            icon: "clock"
                        )
                    }
                }

                createPlanButton(
                    mode: .advanced,
                    title: "Create Empty Plan",
                    subtitle:
                        "\(resolvedWeeks) " +
                        (resolvedWeeks == 1 ? "week" : "weeks") +
                        " · ready for programming"
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.30)
            )
        )
        .onChange(of: startDate) { _, newStart in
            if endDate < newStart {
                endDate = Calendar.current.date(
                    byAdding: .day,
                    value: 6,
                    to: newStart
                ) ?? newStart
            }
        }
    }

    private func builderIntro(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String,
        accent: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 54, height: 54)
                .background(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.15),
                            accent.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(accent)

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.97),
                    accent.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 25,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 25,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.94), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(0.045),
            radius: 14,
            y: 7
        )
    }

    private func creationPanel<Content: View>(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(
                        accent.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(accent)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.98),
                    accent.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 23,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 23,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.96),
                lineWidth: 0.9
            )
        }
        .shadow(
            color: Color.black.opacity(0.038),
            radius: 12,
            y: 6
        )
    }

    private func premiumTextField(
        _ prompt: String,
        text: Binding<String>,
        axis: Axis = .horizontal
    ) -> some View {
        TextField(
            prompt,
            text: text,
            axis: axis
        )
        .textFieldStyle(.plain)
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.028),
            in: RoundedRectangle(
                cornerRadius: 13,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 13,
                style: .continuous
            )
            .stroke(Color.black.opacity(0.035), lineWidth: 0.8)
        }
    }

    private func durationChipGrid(
        options: [Int],
        selected: Int?,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: 78),
                    spacing: 8
                )
            ],
            spacing: 8
        ) {
            ForEach(options, id: \.self) { weeks in
                let isSelected = selected == weeks

                Button {
                    onSelect(weeks)
                } label: {
                    VStack(spacing: 3) {
                        Text("\(weeks)")
                            .font(.headline)
                        Text(weeks == 1 ? "week" : "weeks")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(
                        isSelected
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .background(
                        LinearGradient(
                            colors:
                                isSelected
                                    ? [
                                        ATHLTHTheme.accent,
                                        ATHLTHTheme.accentDeep
                                    ]
                                    : [
                                        Color.white.opacity(0.88),
                                        Color.black.opacity(0.018)
                                    ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                        .stroke(
                            isSelected
                                ? Color.white.opacity(0.12)
                                : Color.black.opacity(0.035),
                            lineWidth: 0.8
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func planConflictCard(
        _ conflict: TrainingPlan,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 40, height: 40)
                .background(
                    Color.orange.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Overlaps with \(conflict.title)")
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(
            Color.orange.opacity(0.07),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(Color.orange.opacity(0.12), lineWidth: 0.8)
        }
    }

    private func advancedFeatureRow(
        _ title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(
                    ATHLTHTheme.primaryText.opacity(0.84)
                )

            Spacer()
        }
    }

    private func createPlanButton(
        mode: TrainingPlanCreationMode,
        title: String,
        subtitle: String
    ) -> some View {
        let disabled =
            self.title
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty ||
            conflictingPlan != nil

        return Button {
            createPlan(mode: mode)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(
                        Color.white.opacity(0.14),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.accentDeep,
                        ATHLTHTheme.accent
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .shadow(
                color: ATHLTHTheme.accentDeep.opacity(
                    disabled ? 0.04 : 0.20
                ),
                radius: 15,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
    }

    private var simplePreviewKinds: [WorkoutKind] {
        let pattern = simpleFocus.pattern

        guard !pattern.isEmpty else {
            return []
        }

        return (0..<simpleSessionsPerWeek).map {
            pattern[$0 % pattern.count]
        }
    }

    private func createPlan(
        mode: TrainingPlanCreationMode
    ) {
        let createdPlan: TrainingPlan?

        switch mode {
        case .simple:
            let autoSummary =
                "\(simpleFocus.title) · " +
                "\(simpleSessionsPerWeek) sessions per week"

            createdPlan = session.createSimpleTrainingPlan(
                title: title,
                summary: autoSummary,
                weekCount: simpleWeekCount,
                startDate: startDate,
                visibility: .privateOnly,
                sessionsPerWeek: simpleSessionsPerWeek,
                workoutPattern: simpleFocus.pattern
            )

        case .advanced:
            createdPlan = session.createTrainingPlan(
                title: title,
                summary: summary,
                weekCount: resolvedWeeks,
                startDate: startDate,
                endDate: resolvedEndDate,
                visibility: visibility
            )

            if let planID = createdPlan?.id {
                goalStore.setLinkedPlan(
                    planID,
                    goalIDs: selectedGoalIDs
                )
            }
        }

        guard createdPlan != nil else {
            if let conflict = conflictingPlan {
                creationError =
                    "This period overlaps with \(conflict.title). " +
                    "Adjust the dates so only one training plan is active at a time."
            } else {
                creationError =
                    "ATHLTH could not create this plan. Check the dates and try again."
            }
            return
        }

        dismiss()
    }

}

struct PlanMetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

    let plan: TrainingPlan

    @State private var title: String
    @State private var summary: String
    @State private var visibility: ProfileVisibility
    @State private var tags: String
    @State private var startDate: Date
    @State private var weekCount: Int
    @State private var selectedGoalIDs: Set<UUID> = []
    @State private var selectedSpotifyPlaylist: SpotifyPlaylistReference?
    @State private var spotifyAutoplay: Bool
    @State private var showingSpotifyPlaylistPicker = false
    @State private var saveError: String?
    @State private var showingDeleteConfirmation = false

    init(plan: TrainingPlan) {
        self.plan = plan
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _visibility = State(initialValue: plan.visibility)
        _tags = State(initialValue: plan.tags.joined(separator: ", "))
        _startDate = State(
            initialValue:
                plan.startDate ??
                Calendar.current.startOfDay(for: Date())
        )
        _weekCount = State(initialValue: max(plan.weeks.count, 1))
        _selectedSpotifyPlaylist =
            State(initialValue: plan.spotifyPlaylist)
        _spotifyAutoplay =
            State(initialValue: plan.spotifyAutoplayOnWorkoutStart)
    }

    private var resolvedEndDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(weekCount * 7 - 1, 0),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private var conflictingPlan: TrainingPlan? {
        session.trainingPlanConflict(
            startDate: startDate,
            endDate: resolvedEndDate,
            excludingPlanID: plan.id
        )
    }

    private var wouldDiscardScheduledSessions: Bool {
        guard weekCount < plan.weeks.count else { return false }
        return plan.weeks.dropFirst(weekCount).contains { week in
            week.days.contains { !$0.sessions.isEmpty }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Title", text: $title)
                    TextField(
                        "Summary",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    Picker("Visibility", selection: $visibility) {
                        ForEach(ProfileVisibility.allCases) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    }

                    TextField(
                        "Tags, comma separated",
                        text: $tags
                    )
                    .textInputAutocapitalization(.never)
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Timeline",
                        norwegian: "Tidsplan"
                    )
                ) {
                    Stepper(
                        ATHLTHLocalization.format(
                            english: "%d weeks",
                            norwegian: "%d uker",
                            weekCount
                        ),
                        value: $weekCount,
                        in: 1...52
                    )

                    DatePicker(
                        ATHLTHLocalization.choose(
                            english: "Program starts",
                            norwegian: "Planen starter"
                        ),
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    LabeledContent(
                        ATHLTHLocalization.choose(
                            english: "Program ends",
                            norwegian: "Planen avsluttes"
                        ),
                        value: resolvedEndDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )

                    if wouldDiscardScheduledSessions {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "These weeks contain planned workouts. Move or remove them in the planner before shortening this program.",
                                norwegian: "Ukene du vil fjerne inneholder planlagte økter. Flytt eller fjern dem i planleggeren før du forkorter planen."
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                if let conflict = conflictingPlan {
                    Section("Schedule Conflict") {
                        Label(
                            ATHLTHLocalization.format(
                                english: "Overlaps with %@",
                                norwegian: "Overlapper med %@",
                                conflict.title
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)

                        Text(
                            "Move this plan so it does not overlap another scheduled plan."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Goals") {
                    if goalStore.goals.isEmpty {
                        Text("Create a Goal in Progress to connect it to this program.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(goalStore.goals) { goal in
                            Toggle(
                                isOn: Binding(
                                    get: {
                                        selectedGoalIDs.contains(goal.id)
                                    },
                                    set: { enabled in
                                        if enabled {
                                            selectedGoalIDs.insert(goal.id)
                                        } else {
                                            selectedGoalIDs.remove(goal.id)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.title)
                                    Text(goal.category.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Spotify") {
                    if spotify.isConnected {
                        Button {
                            showingSpotifyPlaylistPicker = true
                        } label: {
                            LabeledContent {
                                Text(
                                    selectedSpotifyPlaylist?.name
                                        ?? "None"
                                )
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            } label: {
                                Label(
                                    "Default playlist",
                                    systemImage: "music.note.list"
                                )
                            }
                        }
                        .buttonStyle(.plain)

                        if selectedSpotifyPlaylist != nil {
                            Toggle(
                                "Use as program default",
                                isOn: $spotifyAutoplay
                            )
                        }

                        Text(
                            "This is the default for workouts that do not have their own Spotify choice. A workout-specific playlist or Off setting always takes priority."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if spotify.isConfigured {
                        Button {
                            spotify.connect()
                        } label: {
                            Label(
                                "Connect Spotify",
                                systemImage: "link"
                            )
                        }

                        Text(
                            "Connect Spotify to attach a playlist to this program."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(
                            "Spotify needs a client ID before playlists can be linked."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(
                        "Changing a program creates a new local version. Shared-program sync can use this version number later."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(
                            "Delete Program",
                            systemImage: "trash"
                        )
                        .frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(
                        "Deleting the program removes its remaining plan and schedule. Completed workout history is kept."
                    )
                }
            }
            .navigationTitle("Edit Program")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selectedGoalIDs = Set(
                    goalStore.goals
                        .filter { $0.linkedTrainingPlanID == plan.id }
                        .map(\.id)
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = session.updateTrainingPlan(
                            planID: plan.id,
                            title: title,
                            summary: summary,
                            visibility: visibility,
                            tags: tags
                                .split(separator: ",")
                                .map(String.init),
                            startDate: startDate,
                            weekCount: weekCount
                        )

                        guard saved else {
                            if let conflict = conflictingPlan {
                                saveError = ATHLTHLocalization.format(
                                    english: "This period overlaps with %@. Adjust the dates before saving.",
                                    norwegian: "Perioden overlapper med %@. Endre datoene før du lagrer.",
                                    conflict.title
                                )
                            } else if wouldDiscardScheduledSessions {
                                saveError = ATHLTHLocalization.choose(
                                    english: "Some weeks you are removing still have planned workouts. Move or remove them first.",
                                    norwegian: "Noen av ukene du vil fjerne inneholder planlagte økter. Flytt eller fjern øktene først."
                                )
                            } else {
                                saveError = ATHLTHLocalization.choose(
                                    english: "ATHLTH could not save the plan. Check the dates and try again.",
                                    norwegian: "ATHLTH kunne ikke lagre planen. Kontroller datoene og prøv igjen."
                                )
                            }
                            return
                        }

                        goalStore.setLinkedPlan(
                            plan.id,
                            goalIDs: selectedGoalIDs
                        )

                        _ = session.setTrainingPlanSpotify(
                            planID: plan.id,
                            playlist: selectedSpotifyPlaylist,
                            autoplay: spotifyAutoplay
                        )

                        dismiss()
                    }
                    .disabled(
                        title
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty ||
                        conflictingPlan != nil
                    )
                }
            }
        }
        .sheet(isPresented: $showingSpotifyPlaylistPicker) {
            SpotifyPlaylistPickerView(
                title: "Program Playlist",
                selection: $selectedSpotifyPlaylist
            )
        }
        .confirmationDialog(
            ATHLTHLocalization.format(
                        english: "Delete %@?",
                        norwegian: "Slette %@?",
                        plan.title
                    ),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Program", role: .destructive) {
                goalStore.setLinkedPlan(
                    plan.id,
                    goalIDs: []
                )
                session.deleteTrainingPlan(plan.id)
                dismiss()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the program and its remaining schedule. Completed workout history is kept."
            )
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Unable to save plan",
                norwegian: "Kunne ikke lagre planen"
            ),
            isPresented: Binding(
                get: { saveError != nil },
                set: { shown in
                    if !shown {
                        saveError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }
}

/// Uses exactly the mutual-follow set accepted by Train Together invitations.
/// Search is local to this list; searching never invites a non-mutual account.
private struct SessionTrainingPartnerSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore

    @Binding var selectedPartnerID: UUID?
    @State private var searchText = ""

    private var filteredPartners: [SocialProfileCard] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !query.isEmpty else { return social.trainingPartners }
        return social.trainingPartners.filter {
            $0.resolvedName.localizedStandardContains(query) ||
            ($0.username ?? "").localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedPartnerID = nil
                        dismiss()
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "person.fill")
                                .font(.title3)
                                .foregroundStyle(ATHLTHPlanDesign.accent)
                                .frame(width: 46, height: 46)
                                .background(
                                    ATHLTHPlanDesign.selectedSurface,
                                    in: Circle()
                                )
                            Text(ATHLTHLocalization.choose(
                                english: "Just me",
                                norwegian: "Bare meg"
                            ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            Spacer(minLength: 0)
                            if selectedPartnerID == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ATHLTHPlanDesign.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    if filteredPartners.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ATHLTHLocalization.choose(
                                english: "No matching friends",
                                norwegian: "Ingen venner funnet"
                            ))
                            .font(.headline)
                            Text(ATHLTHLocalization.choose(
                                english: "Only people who follow you back can be invited to a workout.",
                                norwegian: "Kun personer dere følger gjensidig kan inviteres til en økt."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(filteredPartners) { friend in
                            Button {
                                selectedPartnerID = friend.userID
                                dismiss()
                            } label: {
                                HStack(spacing: 13) {
                                    ATHLTHSocialStatusAvatar(
                                        profile: friend,
                                        size: 46
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(friend.resolvedName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(ATHLTHPlanDesign.ink)
                                        if !friend.usernameLabel.isEmpty {
                                            Text(friend.usernameLabel)
                                                .font(.caption)
                                                .foregroundStyle(ATHLTHTheme.mutedText)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if selectedPartnerID == friend.userID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(ATHLTHPlanDesign.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Friends",
                        norwegian: "Venner"
                    ))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Choose a training partner",
                norwegian: "Velg treningspartner"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                prompt: ATHLTHLocalization.choose(
                    english: "Name or @username",
                    norwegian: "Navn eller @brukernavn"
                )
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close",
                        norwegian: "Lukk"
                    )) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            if social.trainingPartners.isEmpty {
                await social.refresh()
            }
        }
    }
}

private enum SessionEditorMode: String, CaseIterable, Identifiable {
    case basic
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "Basic"
        case .advanced: return "Advanced"
        }
    }
}

private enum HeartRateTargetMode: String, CaseIterable, Identifiable {
    case zone
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zone: return "Zone"
        case .custom: return "Custom BPM"
        }
    }
}

private struct SessionEditorStoredDraft: Codable {
    let workout: PlannedSession
    let selectedPartnerID: UUID?
    let physicalMeetup: Bool?
    let scheduledTimeEnabled: Bool
    let editorModeRaw: String
    let targetPaceEnabled: Bool
    let heartRateTargetEnabled: Bool
    let heartRateTargetModeRaw: String
    let heartRateTargetZone: Int
    let customHeartRateMinBPM: Int
    let customHeartRateMaxBPM: Int
    let paceAlertsEnabled: Bool
    let paceAlertToleranceSeconds: Int
    let targetAlertGraceSeconds: Int
    let targetAlertRepeatSeconds: Int
    let targetAlertDelivery: WatchAlertDelivery
    let targetAlertAnnounceBackInTarget: Bool
}

/// One estimate powers both the overview and the editable duration.
enum PlannedSessionDurationEstimator {
    static func strengthMinutes(for exercises: [PlannedExercise]) -> Int? {
        guard !exercises.isEmpty else { return nil }
        let seconds = exercises.reduce(0) { total, exercise in
            let targets = exercise.resolvedSetTargets
            let work = targets.reduce(0) { partial, target in
                switch exercise.resolvedTargetKind {
                case .reps:
                    return partial + max(target.reps ?? exercise.reps ?? 8, 1) * 4
                case .time:
                    return partial + max(
                        target.durationSeconds ??
                            exercise.resolvedTargetDurationSeconds ?? 60,
                        15
                    )
                }
            }
            let rest = targets.dropLast().reduce(0) {
                $0 + max($1.restSeconds ?? exercise.restSeconds ?? 90, 0)
            }
            return total + work + rest
        }
        return max(1, Int(ceil(Double(seconds) / 60)))
    }
}

/// One editor for both outdoor pace and treadmill km/t. The saved
/// RunningStepTarget always stores seconds per km, which the existing Watch
/// transfer and interval estimator already understand.
private struct ATHLTHPlannedRunningPhaseEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let target: RunningStepTarget
    let environment: RunEnvironment
    let onSave: (RunningStepTarget) -> Void

    @State private var selectedZone: Int
    @State private var paceEnabled: Bool
    @State private var paceSecondsPerKm: Double

    init(
        title: String,
        target: RunningStepTarget,
        environment: RunEnvironment,
        fallbackPace: Double,
        onSave: @escaping (RunningStepTarget) -> Void
    ) {
        self.title = title
        self.target = target
        self.environment = environment
        self.onSave = onSave
        _selectedZone = State(initialValue: min(max(target.intensity.heartRateZone ?? 0, 0), 5))
        _paceEnabled = State(initialValue:
            target.intensity.paceMinSecondsPerKilometer != nil)
        _paceSecondsPerKm = State(initialValue: min(max(
            target.intensity.paceMinSecondsPerKilometer ?? fallbackPace, 150
        ), 1200))
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { 3600 / max(paceSecondsPerKm, 1) },
            set: { value in paceSecondsPerKm = 3600 / max(value, 0.5) }
        )
    }

    private var paceText: String {
        let total = Int(paceSecondsPerKm.rounded())
        return String(format: "%d:%02d min/km", total / 60, total % 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(
                        ATHLTHLocalization.choose(english: "Heart-rate zone", norwegian: "Pulssone"),
                        selection: $selectedZone
                    ) {
                        Text(ATHLTHLocalization.choose(
                            english: "No zone target", norwegian: "Ingen sonemål"
                        )).tag(0)
                        ForEach(1...5, id: \.self) { zone in
                            Text(ATHLTHLocalization.choose(
                                english: "Zone", norwegian: "Sone"
                            ) + " \(zone)").tag(zone)
                        }
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "A zone is a target, not a measured heart rate. Use your individual Health Profile zones.",
                        norwegian: "Sonen er et mål, ikke en målt puls. Bruk dine personlige pulssoner fra helseprofilen."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } header: {
                    Text(ATHLTHLocalization.choose(
                        english: "Training zone", norwegian: "Treningssone"
                    ))
                }
                .listRowBackground(ATHLTHPlanDesign.surface)

                Section {
                    Toggle(
                        ATHLTHLocalization.choose(english: "Set target pace", norwegian: "Angi måltempo"),
                        isOn: $paceEnabled
                    )
                    .tint(ATHLTHPlanDesign.accentInk)
                    if paceEnabled {
                        if environment == .treadmill {
                            Stepper(
                                String(format: "%.1f km/t", speedBinding.wrappedValue),
                                value: speedBinding,
                                in: 3...24, step: 0.1
                            )
                            Text(paceText)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        } else {
                            Stepper(paceText, value: $paceSecondsPerKm,
                                    in: 150...1200, step: 5)
                            Text(String(format: "%.1f km/t", 3600 / max(paceSecondsPerKm, 1)))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                } header: {
                    Text(environment == .treadmill
                        ? ATHLTHLocalization.choose(english: "Treadmill speed", norwegian: "Møllehastighet")
                        : ATHLTHLocalization.choose(english: "Outdoor pace", norwegian: "Utendørstempo"))
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: "Each phase may have its own zone and pace. The target is saved with the planned run and sent to Apple Watch.",
                        norwegian: "Hver del kan ha egen sone og eget tempo. Målet lagres med økten og sendes til Apple Watch."
                    ))
                }
                .listRowBackground(ATHLTHPlanDesign.surface)
            }
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Save", norwegian: "Lagre")) {
                        var updated = target
                        var intensity = updated.intensity
                        intensity.paceMinSecondsPerKilometer = paceEnabled ? paceSecondsPerKm : nil
                        intensity.paceMaxSecondsPerKilometer = paceEnabled ? paceSecondsPerKm : nil
                        intensity.heartRateZone = selectedZone > 0 ? selectedZone : nil
                        intensity.kind = paceEnabled
                            ? .pace
                            : (selectedZone > 0 ? .heartRateZone : .easy)
                        updated.intensity = intensity
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SessionRunningPhaseSelection: Identifiable {
    let workoutID: UUID
    let blockID: UUID
    let isRecovery: Bool
    var id: String { workoutID.uuidString + blockID.uuidString + (isRecovery ? "recovery" : "work") }
}

private struct SessionRunningRepetitionSelection: Identifiable {
    let workoutID: UUID
    let blockID: UUID
    let repetition: Int
    var id: String { workoutID.uuidString + blockID.uuidString + "\(repetition)" }
}

struct SessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

    let dayID: UUID?
    let planID: UUID?
    let existingWorkout: PlannedSession?
    let isStandalone: Bool
    /// When set, this editor prepares the same complete PlannedSession model
    /// for Train Together without creating a separate calendar entry.
    let onPreparedWorkout: ((PlannedSession) -> Void)?
    let initialSourceWorkout: PlannedSession?
    let preserveSourceID: Bool

    @State private var hasSelectedWorkoutSource = false
    @State private var prioritizePartnerPlanning = false
    @State private var title = ""
    @State private var kind: WorkoutKind = .strength
    @State private var durationMinutes = 0
    @State private var strengthDurationAdjustmentMinutes = 0
    @State private var pendingInvitationWorkout: PlannedSession?
    @State private var distanceKilometers = 0.0
    @State private var distanceWasAdjustedManually = false
    @State private var durationWasAdjustedManually = false
    @State private var runEnvironment: RunEnvironment = .outdoor
    @State private var notes = ""
    @State private var workoutTemplateID: UUID?
    @State private var workoutBlocks: [WorkoutTemplateBlock] = []
    @State private var workoutCategory: String?
    @State private var showingSavedWorkoutPicker = false
    @State private var showingRecoveryRestPlanner = false
    @State private var selectedPartnerID: UUID?
    @State private var partnerPlanningExpanded = false
    @State private var showingAllTrainingPartners = false
    @State private var allowInviteeExercises = false
    @State private var directPartnerID: UUID?
    @State private var physicalMeetup = true
    @State private var meetingPoint: PlannedWorkoutMeetingPoint?
    @State private var reminderMinutesBefore = 0
    @State private var showingMeetingPointPicker = false
    @State private var draftRestored = false
    @State private var draftFinalized = false
    @State private var isSaving = false
    @State private var invitationError = ""
    @State private var showingInvitationError = false

    @State private var plannedExercises: [PlannedExercise] = []
    @State private var exerciseInsertPhase: WorkoutPhaseKind = .main
    @State private var exerciseBeingEdited: PlannedExercise?
    @State private var showingExerciseLibrary = false

    @State private var selectedRunningWorkouts: [RunningWorkoutTemplate] = []
    @State private var showingRunningLibrary = false
    @State private var replacingRunningWorkoutID: UUID?
    @State private var editingRunningPhase: SessionRunningPhaseSelection?
    @State private var editingRunningRepetition: SessionRunningRepetitionSelection?
    @State private var selectedRouteID: UUID?

    private var selectedRoute: TrainingRoute? {
        guard runEnvironment == .outdoor, let selectedRouteID else { return nil }
        return session.savedRoutes.first { $0.id == selectedRouteID }
    }

    @State private var scheduledTimeEnabled = false
    @State private var scheduledTime = Date()

    @State private var editorMode: SessionEditorMode =
        UserDefaults.standard.bool(forKey: "athlth.planWorkspace.advancedMode")
            ? .advanced : .basic
    @State private var selectedGearIDs: Set<UUID> = []
    @State private var gearSelectionTouched = false
    @State private var audioCoachOverride:
        WatchAudioCoachConfiguration? = nil
    @State private var showingAudioCoachEditor = false
    @State private var routeGuardianDraft =
        RouteGuardianDraft()
    @State private var ghostDraft =
        GhostQuickStartDraft()
    @State private var didLoadRunGuidanceDefaults =
        false
    @State private var autoPausePreference:
        WorkoutAutoPausePreference = .appDefault

    @State private var selectedSpotifyPlaylist:
        SpotifyPlaylistReference? = nil
    @State private var spotifyAutoplayOnStart:
        Bool? = nil
    @State private var showingSpotifyPlaylistPicker = false

    @State private var targetPaceEnabled = false
    @State private var targetPaceMinutes = 5
    @State private var targetPaceSeconds = 0

    @State private var heartRateTargetEnabled = false
    @State private var heartRateTargetMode:
        HeartRateTargetMode = .zone
    @State private var heartRateTargetZone = 2
    @State private var customHeartRateMinBPM = 120
    @State private var customHeartRateMaxBPM = 150
    @State private var paceAlertsEnabled = false
    @State private var paceAlertToleranceSeconds = 15
    @State private var targetAlertGraceSeconds = 30
    @State private var targetAlertRepeatSeconds = 120
    @State private var targetAlertDelivery:
        WatchAlertDelivery = .haptic
    @State private var targetAlertAnnounceBackInTarget = true

    init(dayID: UUID) {
        self.dayID = dayID
        self.planID = nil
        self.existingWorkout = nil
        self.isStandalone = false
        self.onPreparedWorkout = nil
        self.initialSourceWorkout = nil
        self.preserveSourceID = false
    }

    init(
        planID: UUID,
        dayID: UUID
    ) {
        self.dayID = dayID
        self.planID = planID
        self.existingWorkout = nil
        self.isStandalone = false
        self.onPreparedWorkout = nil
        self.initialSourceWorkout = nil
        self.preserveSourceID = false
    }

    init(
        standaloneDate: Date,
        initialSourceWorkout: PlannedSession? = nil,
        preserveSourceID: Bool = false,
        onPreparedWorkout: ((PlannedSession) -> Void)? = nil
    ) {
        self.dayID = nil
        self.planID = nil
        self.existingWorkout = nil
        self.isStandalone = true
        self.onPreparedWorkout = onPreparedWorkout
        self.initialSourceWorkout = initialSourceWorkout
        self.preserveSourceID = preserveSourceID

        let calendar =
            Calendar.current
        let day =
            calendar.startOfDay(
                for: standaloneDate
            )
        let defaultTime =
            calendar.date(
                bySettingHour: 18,
                minute: 0,
                second: 0,
                of: day
            ) ?? day

        _scheduledTimeEnabled =
            State(initialValue: true)
        _scheduledTime =
            State(
                initialValue:
                    defaultTime
            )
    }

    init(
        standaloneDate: Date,
        partnerID: UUID,
        physicalMeetup: Bool,
        initialWorkoutStart: Date? = nil,
        initialMeetingPoint: PlannedWorkoutMeetingPoint? = nil
    ) {
        self.init(standaloneDate: standaloneDate)
        _selectedPartnerID = State(initialValue: partnerID)
        _partnerPlanningExpanded = State(initialValue: true)
        _directPartnerID = State(initialValue: partnerID)
        // Scheduling with a friend always means an in-person meetup.
        _physicalMeetup = State(initialValue: true)
        if let initialWorkoutStart {
            _scheduledTime = State(initialValue: initialWorkoutStart)
        }
        _meetingPoint = State(initialValue: initialMeetingPoint)
    }

    init(
        planID: UUID,
        workout: PlannedSession
    ) {
        self.dayID = nil
        self.planID = planID
        self.existingWorkout = workout
        self.isStandalone = false
        self.onPreparedWorkout = nil
        self.initialSourceWorkout = nil
        self.preserveSourceID = false
        _hasSelectedWorkoutSource = State(initialValue: true)

        _title = State(initialValue: workout.title)
        _kind = State(initialValue: workout.kind)
        _durationMinutes = State(
            initialValue: workout.durationMinutes ?? 45
        )
        let estimated = PlannedSessionDurationEstimator
            .strengthMinutes(for: workout.exercises) ?? 0
        _strengthDurationAdjustmentMinutes = State(
            initialValue: estimated > 0
                ? (workout.durationMinutes ?? estimated) - estimated
                : 0
        )
        _distanceKilometers = State(
            initialValue: workout.targetDistanceKilometers ?? 0.0
        )
        _notes = State(initialValue: workout.notes ?? "")
        _workoutTemplateID = State(
            initialValue: workout.workoutTemplateID
        )
        _workoutBlocks = State(
            initialValue: workout.resolvedWorkoutBlocks
        )
        _workoutCategory = State(
            initialValue: workout.workoutCategory
        )
        _runEnvironment = State(initialValue:
            workout.workoutCategory == "treadmill" ||
            workout.resolvedWorkoutBlocks.contains(where: { $0.kind == .run && $0.isIndoor == true })
                ? .treadmill : .outdoor
        )
        _meetingPoint = State(initialValue: workout.meetingPoint)
        _physicalMeetup = State(initialValue: true)
        _allowInviteeExercises = State(initialValue: workout.allowInviteeExercises == true)
        _reminderMinutesBefore = State(initialValue: workout.reminderMinutesBefore ?? 0)
        _plannedExercises = State(initialValue: workout.exercises)
        _selectedRunningWorkouts = State(
            initialValue: workout.resolvedRunningWorkouts
        )
        _selectedRouteID = State(initialValue: workout.routeID)
        _scheduledTimeEnabled = State(
            initialValue: workout.scheduledStart != nil
        )
        _scheduledTime = State(
            initialValue: workout.scheduledStart ?? Date()
        )
        _selectedGearIDs = State(
            initialValue: Set(workout.gearIDs ?? [])
        )
        _audioCoachOverride = State(
            initialValue: workout.audioCoachConfiguration
        )

        var routeDraft =
            RouteGuardianDraft()
        if let routeConfiguration =
                workout.routeAlertConfiguration {
            routeDraft.load(
                configuration:
                    routeConfiguration
            )
        }
        _routeGuardianDraft =
            State(
                initialValue: routeDraft
            )

        var plannedGhost =
            GhostQuickStartDraft()
        if let targetDuration =
                workout
                    .ghostTargetDurationSeconds,
           targetDuration > 0 {
            plannedGhost.enabled = true
            plannedGhost.targetTimeText =
                GhostTargetTimeFormatter
                    .string(
                        targetDuration
                    )
            plannedGhost.updatesEnabled =
                workout
                    .ghostUpdates?
                    .enabled ??
                true
        }
        _ghostDraft =
            State(
                initialValue:
                    plannedGhost
            )

        _autoPausePreference = State(
            initialValue:
                WorkoutAutoPausePreference(
                    overrideValue:
                        workout.autoPauseEnabled
                )
        )
        _selectedSpotifyPlaylist = State(
            initialValue: workout.spotifyPlaylist
        )
        _spotifyAutoplayOnStart = State(
            initialValue: workout.spotifyAutoplayOnStart
        )

        if let target =
                workout.targetAlertConfiguration {
            _heartRateTargetEnabled = State(
                initialValue: target.heartRateEnabled
            )
            _heartRateTargetZone = State(
                initialValue:
                    min(
                        max(target.heartRateZone ?? 2, 1),
                        5
                    )
            )
            _heartRateTargetMode = State(
                initialValue:
                    target.heartRateZone == nil
                        ? .custom
                        : .zone
            )
            _customHeartRateMinBPM = State(
                initialValue:
                    Int(
                        target.heartRateMinimumBPM?
                            .rounded() ?? 120
                    )
            )
            _customHeartRateMaxBPM = State(
                initialValue:
                    Int(
                        target.heartRateMaximumBPM?
                            .rounded() ?? 150
                    )
            )
            _paceAlertsEnabled = State(
                initialValue:
                    target.paceAlertsEnabled
            )
            _paceAlertToleranceSeconds = State(
                initialValue:
                    Int(
                        target
                            .paceToleranceSecondsPerKilometer
                            .rounded()
                    )
            )
            _targetAlertGraceSeconds = State(
                initialValue:
                    Int(target.graceSeconds.rounded())
            )
            _targetAlertRepeatSeconds = State(
                initialValue:
                    Int(target.repeatSeconds.rounded())
            )
            _targetAlertDelivery = State(
                initialValue: target.delivery
            )
            _targetAlertAnnounceBackInTarget = State(
                initialValue:
                    target.announceBackInTarget
            )
        }

        if let pace = workout.targetPaceSecondsPerKilometer,
           pace > 0 {
            let total = max(Int(pace.rounded()), 0)
            _targetPaceEnabled = State(initialValue: true)
            _targetPaceMinutes = State(
                initialValue: total / 60
            )
            _targetPaceSeconds = State(
                initialValue: total % 60
            )
        }
    }

    private var editorModeIndex:
        Binding<Int> {
        Binding(
            get: {
                editorMode == .advanced
                    ? 1
                    : 0
            },
            set: { index in
                editorMode =
                    index == 1
                        ? .advanced
                        : .basic
                UserDefaults.standard.set(
                    index == 1,
                    forKey: "athlth.planWorkspace.advancedMode"
                )
            }
        )
    }

    private func beginPartnerPlanningFromSource() {
        title = ""
        prioritizePartnerPlanning = true
        partnerPlanningExpanded = true
        hasSelectedWorkoutSource = true
    }

    // Workout-editor sections belong to SessionEditorView, not ProgramStartView.
    private var workoutBasicsSection: some View {
                Section {
                    TextField(
                        automaticWorkoutTitle,
                        text: $title
                    )
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english: "Workout name (optional)",
                            norwegian: "Øktnavn (valgfritt)"
                        )
                    )

                    Picker(ATHLTHLocalization.choose(english: "Type", norwegian: "Type"), selection: $kind) {
                        ForEach(WorkoutKind.allCases) { kind in
                            Label(
                                kind.title,
                                systemImage: kind.systemImage
                            )
                            .tag(kind)
                        }
                    }

                    if isStandalone {
                        DatePicker(
                            ATHLTHLocalization.choose(
                                english: "Date",
                                norwegian: "Dato"
                            ),
                            selection:
                                $scheduledTime,
                            in:
                                Calendar.current
                                    .startOfDay(
                                        for: Date()
                                    )...,
                            displayedComponents:
                                .date
                        )
                    }

                    HStack {
                        Label(ATHLTHLocalization.choose(english: "Time", norwegian: "Tid"), systemImage: "clock")
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Spacer()

                        if scheduledTimeEnabled {
                            DatePicker(
                                "",
                                selection: $scheduledTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()

                            if !isStandalone {
                                Button {
                                    scheduledTimeEnabled = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear workout time")
                            }
                        } else {
                            Button("–") {
                                scheduledTime = Date()
                                scheduledTimeEnabled = true
                            }
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .buttonStyle(.plain)
                            .accessibilityLabel("Set workout time")
                        }
                    }

                    Stepper(
                        ATHLTHLocalization.choose(
                            english: "Duration",
                            norwegian: "Varighet"
                        ) + ": " +
                        (resolvedDurationMinutes == 0 ? "–" : "\(resolvedDurationMinutes) min"),
                        value: plannedDurationBinding,
                        in: 0...300,
                        step: 5
                    )

                    if kind == .walking || kind == .running {
                        Stepper(
                            ATHLTHLocalization.choose(english: "Distance", norwegian: "Distanse") +
                                ": " + String(format: "%.1f km", distanceKilometers),
                            value: Binding(
                                get: { distanceKilometers },
                                set: { newValue in
                                    distanceKilometers = newValue
                                    distanceWasAdjustedManually = true
                                }
                            ),
                            in: 0...100,
                            step: 0.5
                        )
                        Text(ATHLTHLocalization.choose(
                            english: "0 km means no distance target. Adding a structured run can estimate distance automatically.",
                            norwegian: "0 km betyr uten distansemål. Når du legger til en intervalløkt, kan distansen beregnes automatisk."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }

                    if kind == .running {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(ATHLTHLocalization.choose(english: "Running environment", norwegian: "Hvor løper du?"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            Picker(ATHLTHLocalization.choose(english: "Running environment", norwegian: "Løpemiljø"),
                                   selection: $runEnvironment) {
                                Label(ATHLTHLocalization.choose(english: "Outdoor · GPS", norwegian: "Ute · GPS"),
                                      systemImage: "location").tag(RunEnvironment.outdoor)
                                Label(ATHLTHLocalization.choose(english: "Treadmill", norwegian: "Tredemølle"),
                                      systemImage: "figure.run.treadmill").tag(RunEnvironment.treadmill)
                            }
                            .pickerStyle(.segmented)
                            Text(runEnvironment == .treadmill
                                ? ATHLTHLocalization.choose(
                                    english: "Indoor running without GPS. Enter belt speed in km/h or target pace in min/km.",
                                    norwegian: "Innendørs uten GPS. Legg inn møllehastighet i km/t eller tempo i min/km.")
                                : ATHLTHLocalization.choose(
                                    english: "Outdoor running can use GPS, routes and Ghost Race.",
                                    norwegian: "Utendørs løping kan bruke GPS, ruter og Ghost Race."))
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        .padding(.vertical, 6)

                    }

                    if kind == .running {
                        Picker(
                            ATHLTHLocalization.choose(english: "Running shoes", norwegian: "Løpesko"),
                            selection: runningShoeSelection
                        ) {
                            Text("–")
                                .tag(nil as UUID?)

                            ForEach(activeRunningShoes) { shoe in
                                Text(
                                    shoe.id ==
                                        gear.defaultRunningShoe?.id
                                        ? "\(shoe.name) · Default"
                                        : shoe.name
                                )
                                .tag(shoe.id as UUID?)
                            }
                        }
                    }

                    // Avoid repeating an imported run template's summary
                    // immediately before its card. The actual notes stay saved.
                    if selectedRunningWorkouts.count != 1 ||
                       notes.trimmingCharacters(in: .whitespacesAndNewlines) !=
                        selectedRunningWorkouts[0].summary
                            .trimmingCharacters(in: .whitespacesAndNewlines) {
                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Notes", norwegian: "Notater"
                            ),
                            text: $notes,
                            axis: .vertical
                        )
                        .lineLimit(2...6)
                    }
                } header: {
                    HStack(spacing: 12) {
                        Text(ATHLTHLocalization.choose(english: "Workout", norwegian: "Økt"))

                        Spacer()

                        ATHLTHPremiumSegmentedControl(
                            titles:
                                SessionEditorMode
                                    .allCases
                                    .map(\.title),
                            selection:
                                editorModeIndex
                        )
                        .frame(width: 182)
                    }
                    .textCase(nil)
                }
                .listRowBackground(ATHLTHPlanDesign.surface)
                .listRowSeparatorTint(ATHLTHPlanDesign.warmDivider)
    }

    @ViewBuilder
    private var workoutSourcesSection: some View {
        Group {
            if onPreparedWorkout == nil || initialSourceWorkout?.allowInviteeExercises == true {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            ATHLTHLocalization.choose(english: "Add to workout", norwegian: "Legg til"),
                            systemImage: "plus.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                        HStack(spacing: 9) {
                            Button {
                                showingSavedWorkoutPicker = true
                            } label: {
                                compactAddTile(
                                    icon: "rectangle.stack.fill",
                                    title: ATHLTHLocalization.choose(english: "Workout", norwegian: "Treningsøkt"),
                                    subtitle: ATHLTHLocalization.choose(english: "Use saved", norwegian: "Bruk lagret"),
                                    background: ATHLTHPlanDesign.selectedSurface
                                )
                            }
                            .buttonStyle(.plain)

                            if kind == .running && !selectedRunningWorkouts.isEmpty {
                                exercisePlacementMenu
                            } else {
                                Button {
                                    exerciseInsertPhase = .main
                                    showingExerciseLibrary = true
                                } label: {
                                    compactAddTile(
                                        icon: "dumbbell.fill",
                                        title: ATHLTHLocalization.choose(english: "Exercise", norwegian: "Øvelse"),
                                        subtitle: ATHLTHLocalization.choose(english: "From library", norwegian: "Fra biblioteket"),
                                        background: ATHLTHPlanDesign.warmSurface
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(ATHLTHPlanDesign.surface)
                .listRowSeparator(.hidden)
            }
        }
    }

    // Add a supplementary exercise without replacing the selected run
    // or resetting interval prescriptions. Position is carried into the
    // single chronological workout timeline on save.
    private var exercisePlacementMenu: some View {
        Menu {
            ForEach([WorkoutPhaseKind.warmup, .main, .cooldown], id: \.self) { phase in
                Button {
                    exerciseInsertPhase = phase
                    showingExerciseLibrary = true
                } label: {
                    Label(phase.title, systemImage: phase.symbol)
                }
            }
        } label: {
            compactAddTile(
                icon: "dumbbell.fill",
                title: ATHLTHLocalization.choose(
                    english: "Exercise", norwegian: "Øvelse"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Choose placement", norwegian: "Velg plassering"
                ),
                background: ATHLTHPlanDesign.warmSurface
            )
        }
    }

    private func compactAddTile(
        icon: String,
        title: String,
        subtitle: String,
        background: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .frame(width: 29)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 65)
        .background(background, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var sourceChoiceCard: some View {
        WorkoutPlanningSourceCard(
            context: ATHLTHLocalization.choose(
                english: "The same workout builder is used for personal plans and Train Together.",
                norwegian: "Den samme øktmotoren brukes for egen planlegging og Train Together."
            ),
            onCreateNew: {
                hasSelectedWorkoutSource = true
                title = ""
            },
            onUsePlanned: {
                showingSavedWorkoutPicker = true
            },
            onRecoveryRest: onPreparedWorkout == nil
                ? { showingRecoveryRestPlanner = true }
                : nil
        )
    }


    // Keep the potentially large dynamic list outside the parent Form's
    // result builder. This also avoids Swift compiler type-check timeouts
    // when the standalone editor grows new controls.
    // Reuse the common ordered planning recipe without prematurely
    // replacing either live run or strength measurement engine.
    private var workoutPlanningPreviewBlocks: [WorkoutTemplateBlock] {
        if !workoutBlocks.isEmpty { return workoutBlocks }
        guard !plannedExercises.isEmpty,
              !selectedRunningWorkouts.isEmpty else { return [] }
        return ATHLTHUnifiedWorkout.editorBlocks(from: composeSession())
    }

    @ViewBuilder
    private var workoutStructurePreviewSection: some View {
        if !workoutPlanningPreviewBlocks.isEmpty {
            Section(ATHLTHLocalization.choose(
                english: "Workout structure", norwegian: "Øktstruktur"
            )) {
                HStack {
                    Label(
                        "\(workoutPlanningPreviewBlocks.count) blokker",
                        systemImage: "list.number"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.48, green: 0.36, blue: 0.20))
                    Spacer()
                    if let workoutCategory {
                        Text(workoutCategory.capitalized)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
                ForEach(Array(workoutPlanningPreviewBlocks.enumerated()), id: \.element.id) { index, block in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 3) {
                            Image(systemName: block.kind == .rest ? "pause.fill" : block.kind.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(red: 0.49, green: 0.36, blue: 0.19))
                                .frame(width: 28, height: 28)
                                .background(Color(red: 0.94, green: 0.92, blue: 0.88), in: Circle())
                            if index < workoutPlanningPreviewBlocks.count - 1 {
                                Rectangle()
                                    .fill(Color(red: 0.77, green: 0.72, blue: 0.64))
                                    .frame(width: 1, height: 16)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            let description = [
                                block.kind == .rest
                                    ? block.durationSeconds.map { "\(Int($0.rounded())) sek pause" }
                                    : block.targetText,
                                block.notes
                            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            if !description.isEmpty {
                                Text(description)
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(
                        block.kind == .rest
                            ? Color(red: 0.95, green: 0.93, blue: 0.89)
                            : Color(red: 0.975, green: 0.967, blue: 0.949),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
            }
        }
    }

    // Keeping the outer View type small is deliberate: on iOS 27,
    // Swift runtime metadata resolution for the old, deeply nested chain
    // of Form + eleven sheets + lifecycle modifiers exhausted the main
    // thread stack during UISheetPresentationController presentation.
    // AnyView only at stable section boundaries caps generic type depth.
    var body: some View {
        NavigationStack {
            AnyView(editorLifecycle)
        }
    }

    private var editorBaseForm: some View {
        Form {
            if isStandalone && !hasSelectedWorkoutSource {
                Section {
                    sourceChoiceCard
                }
                .listRowBackground(SwiftUI.Color.clear)
                .listRowInsets(EdgeInsets(top: 14, leading: 14,
                                          bottom: 14, trailing: 14))
            } else {
            // Entry from the "Train together" card puts partner selection
            // first while retaining the exact same workout editor.
            if prioritizePartnerPlanning && onPreparedWorkout == nil {
                partnerPlanningSection
            }
            Section {
                workoutBuilderOverview
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            workoutStructurePreviewSection

            workoutBasicsSection

            if kind == .running {
                runningBuilder
                plannedRunGuidanceSection
            }

            workoutSourcesSection


            if onPreparedWorkout == nil && !prioritizePartnerPlanning {
                partnerPlanningSection
            }
            plannedWorkoutLogisticsSection

            if editorMode == .advanced {
                advancedOptions
            }

            if kind == .strength ||
                !plannedExercises.isEmpty {
                strengthBuilder
            }

            if kind == .running && runEnvironment == .outdoor {
                routeBuilder
            }

            if kind == .walking {
                routeBuilder
            }

            if kind == .recovery || kind == .mobility {
                Section(ATHLTHLocalization.choose(english: "Recovery / Mobility", norwegian: "Restitusjon / bevegelighet")) {
                    Text(
                        ATHLTHLocalization.choose(english: "Use duration and notes to describe the session. Structured mobility blocks can be added to the same planner model later.", norwegian: "Bruk varighet og notater for å beskrive økten. Strukturerte bevegelighetsblokker kan legges til senere.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            } // shared workout-source selection
        }
        .scrollContentBackground(.hidden)
        .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
        .tint(ATHLTHPlanDesign.accentInk)
        .listSectionSpacing(14)
        .environment(
            \.defaultMinListRowHeight,
            52
        )
        .navigationTitle(
            isStandalone
                ? ATHLTHLocalization.choose(
                    english:
                        "Plan Extra Workout",
                    norwegian:
                        "Planlegg ekstra økt"
                )
                : existingWorkout == nil
                    ? ATHLTHLocalization.choose(english: "Add workout", norwegian: "Legg til økt")
                    : ATHLTHLocalization.choose(english: "Edit workout", norwegian: "Rediger økt")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(
                    ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )
                ) {
                    finishDraft()
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(
                    isStandalone
                        ? ATHLTHLocalization.choose(
                            english: "Plan",
                            norwegian: "Planlegg"
                        )
                        : existingWorkout == nil
                            ? ATHLTHLocalization.choose(english: "Add", norwegian: "Legg til")
                            : ATHLTHLocalization.choose(english: "Save", norwegian: "Lagre")
                ) {
                    saveSession()
                }
                .disabled(!hasSelectedWorkoutSource || !canAdd || isSaving)
            }
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Invitation not sent",
                norwegian: "Invitasjonen ble ikke sendt"
            ),
            isPresented: $showingInvitationError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(invitationError)
        }
    }

    private var editorPartnerSheets: some View {
        AnyView(editorBaseForm)
            .sheet(isPresented: $showingAllTrainingPartners) {
                SessionTrainingPartnerSelectionSheet(
                    selectedPartnerID: $selectedPartnerID
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingMeetingPointPicker) {
                NavigationStack {
                    TrainTogetherMapPlacePickerView { place in
                        meetingPoint = PlannedWorkoutMeetingPoint(
                            name: place.name,
                            address: place.address,
                            latitude: place.latitude,
                            longitude: place.longitude
                        )
                    }
                }
            }
            .sheet(isPresented: $showingRecoveryRestPlanner) {
                ATHLTHRecoveryRestPlanningSheet(date: scheduledTime) {
                    finishDraft()
                    dismiss()
                }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingSavedWorkoutPicker) {
                PlanWorkoutPickerView { workout in
                    applySavedWorkout(workout)
                    // A template supplies the structure, not the new session name.
                    // The athlete must explicitly name any newly planned session.
                    if existingWorkout == nil {
                        title = ""
                    }
                    hasSelectedWorkoutSource = true
                    showingSavedWorkoutPicker = false
                }
            }
    }

    private var editorLibrarySheets: some View {
        AnyView(editorPartnerSheets)
            .sheet(isPresented: $showingExerciseLibrary) {
                NavigationStack {
                    ExerciseLibraryView(
                        selectionTitle:
                            ATHLTHLocalization.choose(
                                english: "Add to Workout",
                                norwegian: "Legg til i økten"
                            ),
                        selectedExerciseCounts: Dictionary(
                            plannedExercises.compactMap(\.exerciseID).map { ($0, 1) },
                            uniquingKeysWith: +
                        )
                    ) { entry in
                        addExercise(entry.exercise)
                    }
                }
            }
            .sheet(item: $exerciseBeingEdited) { exercise in
                PlannedExerciseEditorView(
                    exercise: exercise,
                    advancedMode:
                        editorMode == .advanced
                ) { updated in
                    if let index = plannedExercises.firstIndex(
                        where: { $0.id == updated.id }
                    ) {
                        plannedExercises[index] = updated
                    }
                    exerciseBeingEdited = nil
                }
            }
            .sheet(isPresented: $showingRunningLibrary,
                   onDismiss: { replacingRunningWorkoutID = nil }) {
                NavigationStack {
                    RunningWorkoutLibraryView(
                        selectionTitle: ATHLTHLocalization.choose(
                            english: "Choose running workout", norwegian: "Velg løpeøkt"
                        )
                    ) { workout in
                        if let replacingRunningWorkoutID,
                           let index = selectedRunningWorkouts.firstIndex(where: {
                               $0.id == replacingRunningWorkoutID
                           }) {
                            selectedRunningWorkouts[index] = workout
                            self.replacingRunningWorkoutID = nil
                            syncRunningMetricsFromSelection()
                        } else {
                            addRunningWorkout(workout)
                        }
                    }
                }
            }
            .sheet(item: $editingRunningPhase) { selection in
                phaseEditor(for: selection)
            }
    }

    private var editorDetailSheets: some View {
        AnyView(editorLibrarySheets)
            .sheet(item: $editingRunningRepetition) { selection in
                repetitionEditor(for: selection)
            }
            .sheet(isPresented: $showingAudioCoachEditor) {
                PlannedAudioCoachEditorView(
                    configuration: $audioCoachOverride,
                    defaultConfiguration:
                        settings.audioCoachConfiguration(
                            enabled:
                                settings.audioCoachEnabledByDefault
                        )
                )
            }
            .sheet(
                isPresented:
                    $showingSpotifyPlaylistPicker
            ) {
                SpotifyPlaylistPickerView(
                    title: "Workout Playlist",
                    selection:
                        spotifyWorkoutPlaylistSelection
                )
            }
    }

    private var editorLifecycle: some View {
        AnyView(editorDetailSheets)
            .onAppear {
                let existingDraft = UserDefaults.standard.data(
                    forKey: draftStorageKey
                ) != nil
                restoreDraftIfNeeded()
                if isStandalone && existingWorkout == nil {
                    if !hasSelectedWorkoutSource {
                        if !existingDraft, let initialSourceWorkout {
                            applySavedWorkout(initialSourceWorkout)
                            if !preserveSourceID { title = "" }
                        }
                        hasSelectedWorkoutSource = existingDraft ||
                            initialSourceWorkout != nil
                    }
                } else {
                    hasSelectedWorkoutSource = true
                }
                if social.trainingPartners.isEmpty {
                    Task { await social.refresh() }
                }
            }
            .onDisappear {
                persistDraft()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistDraft() }
            }
            .onChange(of: selectedRouteID) { oldRouteID, newRouteID in
                syncMetricsFromRouteChange(
                    previousRouteID: oldRouteID,
                    routeID: newRouteID
                )

                ghostDraft.load(
                    route: selectedRoute,
                    settings: settings
                )
            }
            .task {
                await prepareSessionEditor()
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .running {
                    applyDefaultRunningShoeIfNeeded()
                    syncRunningMetricsFromSelection()
                }
            }
            .onChange(of: runEnvironment) { _, value in
                if value == .treadmill {
                    selectedRouteID = nil
                    routeGuardianDraft.enabled = false
                    ghostDraft.enabled = false
                }
                syncRunningMetricsFromSelection()
            }
            .onChange(of: targetPaceEnabled) { _, _ in syncRunningMetricsFromSelection() }
            .onChange(of: targetPaceMinutes) { _, _ in syncRunningMetricsFromSelection() }
            .onChange(of: targetPaceSeconds) { _, _ in syncRunningMetricsFromSelection() }
    }

    private func prepareSessionEditor() async {
            if !didLoadRunGuidanceDefaults {
                if existingWorkout?
                    .routeAlertConfiguration == nil {
                    routeGuardianDraft.load(
                        from: settings
                    )
                }

                if existingWorkout?
                    .ghostTargetDurationSeconds == nil {
                    ghostDraft.load(
                        route: selectedRoute,
                        settings: settings
                    )
                }

                didLoadRunGuidanceDefaults =
                    true
            }

            await gear.refresh()

            if exerciseLibrary
                .allExercises
                .isEmpty {
                await exerciseLibrary
                    .refresh()
            }

            applyDefaultRunningShoeIfNeeded()
    }

    @ViewBuilder
    private var spotifyAdvancedOptions:
        some View {
        Section("Spotify") {
            Toggle(
                "Start Spotify with workout",
                isOn: spotifyWorkoutEnabled
            )
            .disabled(
                !spotify.isConfigured ||
                (
                    !spotify.isConnected &&
                    effectiveSpotifyPlaylist == nil
                )
            )

            if spotify.isConnected {
                Button {
                    showingSpotifyPlaylistPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                "music.note.list"
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accent
                        )
                        .frame(width: 28)

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text("Playlist")
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )

                            Text(
                                spotifyWorkoutPlaylistLabel
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                            .lineLimit(1)
                        }

                        Spacer()

                        Image(
                            systemName:
                                "chevron.right"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(
                            .tertiary
                        )
                    }
                }
                .buttonStyle(.plain)
            } else if spotify.isConfigured {
                Button {
                    spotify.connect()
                } label: {
                    Label(
                        "Connect Spotify",
                        systemImage: "link"
                    )
                }
            } else {
                Text(
                    "Spotify is not configured in this build."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(
                effectiveSpotifyPlaylist == nil
                    ? "No music will be started automatically for this workout."
                    : "The selected playlist starts when this workout begins on iPhone. Spotify never blocks the workout from starting."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .listRowBackground(
            ATHLTHTheme.card
        )
        .listRowSeparatorTint(
            ATHLTHTheme.border
        )

    }

    private var targetRunningSpeedBinding: Binding<Double> {
        Binding(
            get: {
                let seconds = Double(targetPaceMinutes * 60 + targetPaceSeconds)
                return seconds > 0 ? 3_600 / seconds : 12
            },
            set: { speed in
                let rounded = Int((3_600 / max(speed, 0.5)).rounded())
                targetPaceMinutes = rounded / 60
                targetPaceSeconds = rounded % 60
            }
        )
    }

    @ViewBuilder
    private var advancedOptions: some View {
        spotifyAdvancedOptions

        // Pace and treadmill controls live in Basics for both modes.
        if kind == .running || kind == .walking {
            Section(
                ATHLTHLocalization.choose(
                    english: "Workout behavior",
                    norwegian: "Øktoppførsel"
                )
            ) {
                Picker(
                    ATHLTHLocalization.choose(
                        english: "Auto-pause",
                        norwegian: "Auto-pause"
                    ),
                    selection: $autoPausePreference
                ) {
                    ForEach(
                        WorkoutAutoPausePreference.allCases
                    ) { option in
                        Text(option.title).tag(option)
                    }
                }

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Use app default follows Training settings. On or Off overrides it for this workout only.",
                        norwegian:
                            "Bruk standard følger innstillingen under Trening. På eller Av overstyrer den kun for denne økten."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Live Targets & Alerts") {
                Toggle(
                    "Heart-rate target",
                    isOn: $heartRateTargetEnabled
                )

                if heartRateTargetEnabled {
                    Picker(
                        "Heart-rate target",
                        selection: $heartRateTargetMode
                    ) {
                        ForEach(
                            HeartRateTargetMode.allCases
                        ) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if heartRateTargetMode == .zone {
                        Picker(
                            "Zone",
                            selection: $heartRateTargetZone
                        ) {
                            ForEach(1...5, id: \.self) { zone in
                                Text(ATHLTHLocalization.format(
                                    english: "Zone %d",
                                    norwegian: "Sone %d",
                                    zone
                                ))
                                    .tag(zone)
                            }
                        }

                        if let range =
                                heartRateRange(
                                    for: heartRateTargetZone
                                ) {
                            LabeledContent(
                                "Target range",
                                value:
                                    "\(range.lower)–\(range.upper) bpm"
                            )

                            Text(
                                session.onboardingProfile?.maximumHeartRateBPM != nil
                                    ? "ATHLTH uses your saved maximum heart rate from Health Profile as the source of truth for this zone."
                                    : resolvedMaximumHeartRate != nil
                                        ? "ATHLTH estimates maximum heart rate from your age because no known max is saved in Health Profile."
                                        : "Using the saved BPM range for this zone. Add a known max heart rate or date of birth in Health Profile to calculate zones."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(
                                "Add a known maximum heart rate or date of birth in Health Profile to calculate zones, or choose Custom BPM."
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    } else {
                        Stepper(
                            "Minimum: \(customHeartRateMinBPM) bpm",
                            value: $customHeartRateMinBPM,
                            in: 60...230,
                            step: 1
                        )

                        Stepper(
                            "Maximum: \(customHeartRateMaxBPM) bpm",
                            value: $customHeartRateMaxBPM,
                            in: 70...240,
                            step: 1
                        )
                    }
                }

                if kind == .running &&
                    targetPaceEnabled {
                    Toggle(
                        "Alert outside pace target",
                        isOn: $paceAlertsEnabled
                    )

                    if paceAlertsEnabled {
                        Picker(
                            "Pace tolerance",
                            selection:
                                $paceAlertToleranceSeconds
                        ) {
                            Text("± 5 sec /km").tag(5)
                            Text("± 10 sec /km").tag(10)
                            Text("± 15 sec /km").tag(15)
                            Text("± 30 sec /km").tag(30)
                        }
                    }
                }

                if hasLiveTargetAlerts {
                    Picker(
                        "Wait before alert",
                        selection:
                            $targetAlertGraceSeconds
                    ) {
                        Text("Immediately").tag(0)
                        Text("15 sec").tag(15)
                        Text("30 sec").tag(30)
                        Text("1 min").tag(60)
                    }

                    Picker(
                        "Alert style",
                        selection:
                            $targetAlertDelivery
                    ) {
                        ForEach(
                            WatchAlertDelivery.allCases
                        ) { delivery in
                            Text(delivery.title)
                                .tag(delivery)
                        }
                    }

                    Picker(
                        "Repeat while outside target",
                        selection:
                            $targetAlertRepeatSeconds
                    ) {
                        Text("30 sec").tag(30)
                        Text("1 min").tag(60)
                        Text("2 min").tag(120)
                        Text("5 min").tag(300)
                    }

                    Toggle(
                        "Tell me when I'm back in target",
                        isOn:
                            $targetAlertAnnounceBackInTarget
                    )
                }

                Text(
                    "These targets apply only to this workout. Route-deviation alerts use your global Training settings."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        Section("Additional Gear") {
            if additionalGearItems.isEmpty {
                Text(
                    "No additional active gear is available. Add watches, headphones or other gear in My Gear."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(additionalGearItems) { item in
                    Button {
                        toggleGear(item.id)
                    } label: {
                        HStack(spacing: 11) {
                            Image(
                                systemName: item.category.systemImage
                            )
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                Text(item.category.shortTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(
                                systemName:
                                    selectedGearIDs.contains(item.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                            )
                            .foregroundStyle(
                                selectedGearIDs.contains(item.id)
                                    ? ATHLTHTheme.vitality
                                    : ATHLTHTheme.mutedText
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(
                "Selected gear is linked automatically when the workout is completed."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var hasLiveTargetAlerts: Bool {
        heartRateTargetEnabled ||
        (
            kind == .running &&
            targetPaceEnabled &&
            paceAlertsEnabled
        )
    }

    private var resolvedMaximumHeartRate: Double? {
        if let known =
                session
                    .onboardingProfile?
                    .maximumHeartRateBPM,
           known >= 100,
           known <= 240 {
            return Double(known)
        }

        let dateOfBirth =
            session.onboardingProfile?.dateOfBirth ??
            health.personalDetails.dateOfBirth

        guard let dateOfBirth else {
            return nil
        }

        let age = Calendar.current
            .dateComponents(
                [.year],
                from: dateOfBirth,
                to: Date()
            )
            .year ?? 0

        guard age >= 13,
              age <= 100
        else {
            return nil
        }

        return max(
            100,
            208 - (0.7 * Double(age))
        )
    }

    private func estimatedHeartRateRange(
        for zone: Int
    ) -> (lower: Int, upper: Int)? {
        guard let range = ATHLTHHeartRateZones.range(
            for: zone,
            maximumBPM: resolvedMaximumHeartRate
        ) else { return nil }
        return (lower: range.lowerBound, upper: range.upperBound)
    }

    private func heartRateRange(
        for zone: Int
    ) -> (lower: Int, upper: Int)? {
        if let estimated =
                estimatedHeartRateRange(
                    for: zone
                ) {
            return estimated
        }

        guard let existing =
                existingWorkout?
                    .targetAlertConfiguration,
              existing.heartRateEnabled,
              existing.heartRateZone == zone,
              let minimum =
                existing.heartRateMinimumBPM,
              let maximum =
                existing.heartRateMaximumBPM
        else {
            return nil
        }

        return (
            lower: Int(minimum.rounded()),
            upper: Int(maximum.rounded())
        )
    }

    private var workoutTargetAlertConfigurationForSave:
        WatchWorkoutTargetAlertConfiguration? {
        let paceEnabled =
            kind == .running &&
            targetPaceEnabled &&
            paceAlertsEnabled

        let heartRange:
            (
                zone: Int?,
                lower: Double,
                upper: Double
            )? = {
            guard heartRateTargetEnabled else {
                return nil
            }

            switch heartRateTargetMode {
            case .zone:
                guard let range =
                        heartRateRange(
                            for: heartRateTargetZone
                        )
                else {
                    return nil
                }

                return (
                    zone: heartRateTargetZone,
                    lower: Double(range.lower),
                    upper: Double(range.upper)
                )

            case .custom:
                let lower =
                    min(
                        customHeartRateMinBPM,
                        customHeartRateMaxBPM
                    )
                let upper =
                    max(
                        customHeartRateMinBPM,
                        customHeartRateMaxBPM
                    )

                return (
                    zone: nil,
                    lower: Double(lower),
                    upper: Double(upper)
                )
            }
        }()

        guard heartRange != nil ||
                paceEnabled
        else {
            return nil
        }

        return WatchWorkoutTargetAlertConfiguration(
            heartRateEnabled:
                heartRange != nil,
            heartRateZone:
                heartRange?.zone,
            heartRateMinimumBPM:
                heartRange?.lower,
            heartRateMaximumBPM:
                heartRange?.upper,
            paceAlertsEnabled:
                paceEnabled,
            paceToleranceSecondsPerKilometer:
                Double(
                    max(
                        paceAlertToleranceSeconds,
                        0
                    )
                ),
            graceSeconds:
                TimeInterval(
                    max(
                        targetAlertGraceSeconds,
                        0
                    )
                ),
            repeatSeconds:
                TimeInterval(
                    max(
                        targetAlertRepeatSeconds,
                        30
                    )
                ),
            delivery:
                targetAlertDelivery,
            announceBackInTarget:
                targetAlertAnnounceBackInTarget
        )
    }

    private var activeRunningShoes: [ProfileGearItem] {
        gear.items(in: .shoes).filter {
            gear.isActive($0)
        }
    }

    private var runningShoeSelection: Binding<UUID?> {
        Binding(
            get: {
                activeRunningShoes.first {
                    selectedGearIDs.contains($0.id)
                }?.id
            },
            set: { newValue in
                gearSelectionTouched = true

                let shoeIDs = Set(
                    gear.items(in: .shoes).map(\.id)
                )

                selectedGearIDs.subtract(shoeIDs)

                if let newValue {
                    selectedGearIDs.insert(newValue)
                }
            }
        )
    }

    private var additionalGearItems: [ProfileGearItem] {
        gear.items.filter {
            gear.isActive($0) &&
            $0.category != .shoes
        }
        .sorted {
            if $0.category != $1.category {
                return $0.category.rawValue <
                    $1.category.rawValue
            }

            return $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    private var plannedGearIDsForSave: [UUID]? {
        let allowed = selectedGearIDs.filter { id in
            guard let item = gear.items.first(
                where: { $0.id == id }
            ) else {
                return true
            }

            return item.category != .shoes ||
                kind == .running
        }

        if allowed.isEmpty &&
            !gearSelectionTouched &&
            existingWorkout?.gearIDs == nil {
            return nil
        }

        return allowed.sorted {
            $0.uuidString < $1.uuidString
        }
    }

    private var audioCoachStatusText: String {
        if let configuration = audioCoachOverride {
            return configuration.enabled
                ? "Custom · On"
                : "Custom · Off"
        }

        return settings.audioCoachEnabledByDefault
            ? "App default · On"
            : "App default · Off"
    }

    private func toggleGear(_ id: UUID) {
        gearSelectionTouched = true

        if selectedGearIDs.contains(id) {
            selectedGearIDs.remove(id)
        } else {
            selectedGearIDs.insert(id)
        }
    }

    private func applyDefaultRunningShoeIfNeeded() {
        guard kind == .running,
              existingWorkout == nil,
              runningShoeSelection.wrappedValue == nil,
              let defaultShoe = gear.defaultRunningShoe
        else {
            return
        }

        selectedGearIDs.insert(defaultShoe.id)
    }

    private func plannedExerciseDisplayName(_ planned: PlannedExercise) -> String {
        if let id = planned.exerciseID,
           let entry = exerciseLibrary.allExercises.first(where: { $0.id == id }) {
            return exerciseLibrary.localizedExerciseName(entry)
        }
        return planned.embeddedExercise.displayName
    }

    @ViewBuilder
    private func plannedExerciseThumbnail(
        _ planned: PlannedExercise, number: Int
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if let id = planned.exerciseID,
               let entry = exerciseLibrary.allExercises.first(where: { $0.id == id }) {
                ExerciseArtwork(entry: entry, size: 62)
            } else {
                Image(systemName: "dumbbell")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .frame(width: 62, height: 62)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 13)
                    )
            }
            Text(String(number))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .frame(width: 21, height: 21)
                .background(.white, in: Circle())
                .offset(x: -6, y: -6)
        }
    }

    private var strengthBuilder: some View {
        Section(ATHLTHLocalization.choose(english: "Strength exercises", norwegian: "Styrkeøvelser")) {
            if plannedExercises.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Freestyle strength workout")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        "You can add this workout now and choose exercises later, or add exercises below for a structured session."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(plannedExercises.enumerated()), id: \.element.id) { index, planned in
                    Button {
                        exerciseBeingEdited = planned
                    } label: {
                        HStack(spacing: 12) {
                            plannedExerciseThumbnail(planned, number: index + 1)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(plannedExerciseDisplayName(planned))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .lineLimit(2)

                                if kind == .running &&
                                   !selectedRunningWorkouts.isEmpty {
                                    let placement = planned.workoutPhase ??
                                        (planned.isWarmUpExercise ? .warmup : .main)
                                    Label(
                                        placement.title.uppercased(),
                                        systemImage: placement.symbol
                                    )
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                }

                                if planned.isWarmUpExercise {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "WARM-UP",
                                            norwegian: "OPPVARMING"
                                        ),
                                        systemImage: "flame.fill"
                                    )
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(0.5)
                                    .foregroundStyle(ATHLTHTheme.premiumGold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ATHLTHTheme.premiumGoldSoft, in: Capsule())
                                }

                                Text(plannedExerciseSummary(planned))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if planned.hasIndividualSetTargets {
                                    HStack(spacing: 5) {
                                        ForEach(
                                            Array(
                                                planned
                                                    .resolvedSetTargets
                                                    .prefix(3)
                                                    .enumerated()
                                            ),
                                            id: \.element.id
                                        ) { setIndex, target in
                                            Text(
                                                compactPlannedSetLabel(
                                                    target,
                                                    exercise: planned,
                                                    index:
                                                        setIndex + 1
                                                )
                                            )
                                            .font(
                                                .system(
                                                    size: 8.5,
                                                    weight: .bold,
                                                    design: .rounded
                                                )
                                            )
                                            .foregroundStyle(
                                                ATHLTHTheme.accentDeep
                                            )
                                            .padding(.horizontal, 6)
                                            .frame(height: 20)
                                            .background(
                                                ATHLTHTheme.accentSoft,
                                                in: Capsule()
                                            )
                                        }

                                        if planned.sets > 3 {
                                            Text(
                                                "+\(planned.sets - 3)"
                                            )
                                            .font(
                                                .system(
                                                    size: 8.5,
                                                    weight: .bold
                                                )
                                            )
                                            .foregroundStyle(
                                                ATHLTHTheme.mutedText
                                            )
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }

                            Spacer()

                            if planned.supersetGroupID != nil {
                                Image(systemName: "link")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.accent)
                                    .padding(7)
                                    .background(
                                        ATHLTHPlanDesign.selectedSurface,
                                        in: Circle()
                                    )
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk.opacity(0.60))
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(
                        edge: .trailing,
                        allowsFullSwipe: false
                    ) {
                        Button(role: .destructive) {
                            plannedExercises.removeAll {
                                $0.id == planned.id
                            }
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Delete",
                                    norwegian: "Slett"
                                ),
                                systemImage: "trash"
                            )
                        }
                    }
                    .swipeActions(
                        edge: .leading,
                        allowsFullSwipe: false
                    ) {
                        Button {
                            duplicatePlannedExercise(
                                at: index
                            )
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Duplicate",
                                    norwegian: "Dupliser"
                                ),
                                systemImage:
                                    "plus.square.on.square"
                            )
                        }
                        .tint(ATHLTHTheme.accentDeep)
                    }

                    if kind == .running && !selectedRunningWorkouts.isEmpty {
                        HStack(spacing: 8) {
                            Text(ATHLTHLocalization.choose(
                                english: "Position in workout",
                                norwegian: "Plassering i økten"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            Spacer()
                            Menu {
                                ForEach(
                                    [WorkoutPhaseKind.warmup, .main, .cooldown],
                                    id: \.self
                                ) { phase in
                                    Button {
                                        var updated = plannedExercises[index]
                                        updated.workoutPhase = phase
                                        if phase == .warmup {
                                            updated.setEntireExerciseWarmUp(true)
                                        } else if updated.isWarmUpExercise {
                                            updated.setEntireExerciseWarmUp(false)
                                        }
                                        plannedExercises[index] = updated
                                    } label: {
                                        Label(phase.title, systemImage: phase.symbol)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text((planned.workoutPhase ??
                                          (planned.isWarmUpExercise ? .warmup : .main)).title)
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            }
                        }
                    }

                    if index > 0 && editorMode == .advanced {
                        Button {
                            toggleSuperset(at: index)
                        } label: {
                            Label(
                                planned.supersetGroupID == nil
                                    ? ATHLTHLocalization.choose(
                                        english: "Connect to previous as superset",
                                        norwegian: "Koble til forrige som supersett"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Remove superset",
                                        norwegian: "Fjern supersett"
                                    ),
                                systemImage: planned.supersetGroupID == nil
                                    ? "link" : "link.badge.plus"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accent)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(
                            EdgeInsets(top: 1, leading: 86, bottom: 4, trailing: 14)
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .onMove { offsets, destination in
                    plannedExercises.move(
                        fromOffsets: offsets,
                        toOffset: destination
                    )
                }
            }

        }
        .listRowBackground(
            ATHLTHTheme.card
        )
        .listRowSeparatorTint(
            ATHLTHTheme.border
        )
        .environment(\.editMode, .constant(.active))
    }

    /// Keep a chosen friend visible even when the full friend list is long.
    /// All candidates must be mutual follows, as required by invitation RLS.
    private var quickTrainingPartners: [SocialProfileCard] {
        let all = social.trainingPartners
        guard let selectedPartnerID,
              let selected = all.first(where: { $0.userID == selectedPartnerID })
        else {
            return Array(all.prefix(5))
        }
        return [selected] + Array(all.filter {
            $0.userID != selectedPartnerID
        }.prefix(4))
    }

    private var trainingPartnerQuickPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ATHLTHLocalization.choose(
                english: "Training partner",
                norwegian: "Treningspartner"
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.ink)

            HStack(alignment: .top, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 9) {
                        Button {
                            selectedPartnerID = nil
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .frame(width: 46, height: 46)
                                    .background(
                                        ATHLTHPlanDesign.selectedSurface,
                                        in: Circle()
                                    )
                                Text(ATHLTHLocalization.choose(
                                    english: "Just me",
                                    norwegian: "Bare meg"
                                ))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                            }
                            .frame(width: 77)
                            .padding(.vertical, 7)
                            .background(
                                selectedPartnerID == nil
                                    ? ATHLTHPlanDesign.selectedSurface
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 15)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(
                                        selectedPartnerID == nil
                                            ? ATHLTHPlanDesign.accent
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedPartnerID == nil ? [.isSelected] : []
                        )

                        ForEach(quickTrainingPartners) { friend in
                            Button {
                                selectedPartnerID = friend.userID
                            } label: {
                                VStack(spacing: 6) {
                                    ATHLTHSocialStatusAvatar(
                                        profile: friend,
                                        size: 46
                                    )
                                    .frame(width: 54, height: 46)

                                    Text(friend.resolvedName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(ATHLTHPlanDesign.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(width: 77)
                                .padding(.vertical, 7)
                                .background(
                                    selectedPartnerID == friend.userID
                                        ? ATHLTHPlanDesign.selectedSurface
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 15)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(
                                            selectedPartnerID == friend.userID
                                                ? ATHLTHPlanDesign.accent
                                                : Color.clear,
                                            lineWidth: 1.5
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                friend.resolvedName + " " + friend.usernameLabel
                            )
                            .accessibilityAddTraits(
                                selectedPartnerID == friend.userID
                                    ? [.isSelected] : []
                            )
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollClipDisabled()

                Button {
                    showingAllTrainingPartners = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(ATHLTHPlanDesign.accent)
                            .frame(width: 46, height: 46)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: Circle()
                            )
                        Text(ATHLTHLocalization.choose(
                            english: "Others",
                            norwegian: "Andre"
                        ))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    }
                    .frame(width: 66)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "View and search all friends",
                    norwegian: "Vis og søk blant alle venner"
                ))
            }
            .disabled(directPartnerID != nil)

            if social.trainingPartners.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Mutual friends appear here. Tap Others to see the full list.",
                    norwegian: "Venner dere følger gjensidig vises her. Trykk Andre for hele listen."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
    }

    private var partnerPlanningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        partnerPlanningExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accent)
                            .frame(width: 48, height: 48)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 16)
                            )

                        Text(ATHLTHLocalization.choose(
                            english: "Plan with a friend",
                            norwegian: "Planlegg med en venn"
                        ))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                        Spacer(minLength: 0)

                        if !partnerPlanningExpanded,
                           let selectedPartnerID,
                           let friend = social.trainingPartners.first(where: {
                               $0.userID == selectedPartnerID
                           }) {
                            Text(friend.resolvedName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .lineLimit(1)
                        }

                        Image(systemName: partnerPlanningExpanded
                              ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(ATHLTHLocalization.choose(
                    english: "Expand or collapse friend planning",
                    norwegian: "Vis eller skjul planlegging med en venn"
                ))

                if partnerPlanningExpanded {
                    trainingPartnerQuickPicker

                    if selectedPartnerID != nil {
                        Toggle(
                            ATHLTHLocalization.choose(
                                english: "Allow guest to add exercises",
                                norwegian: "La invitert legge til øvelser"
                            ),
                            isOn: $allowInviteeExercises
                        )
                        .tint(ATHLTHPlanDesign.accent)
                    }
                }
            }
            .padding(.vertical, 9)
        } header: {
            Text(ATHLTHLocalization.choose(
                english: "Train together",
                norwegian: "Tren sammen"
            ))
        }
        .listRowBackground(ATHLTHTheme.card)
        .listRowSeparator(.hidden)
    }

    private var plannedWorkoutLogisticsSection: some View {
        Section {
            if selectedPartnerID != nil && physicalMeetup {
                Button {
                    showingMeetingPointPicker = true
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Meeting point",
                                norwegian: "Møtested"
                            ))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(meetingPoint?.name ?? ATHLTHLocalization.choose(
                                english: "Choose a place on the map",
                                norwegian: "Velg sted i kartet"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if let meetingPoint {
                    HStack {
                        Text(meetingPoint.address)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        Spacer()
                        Button(ATHLTHLocalization.choose(
                            english: "Clear", norwegian: "Fjern"
                        )) {
                            self.meetingPoint = nil
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            Picker(
                ATHLTHLocalization.choose(
                    english: "Remind me",
                    norwegian: "Påminn meg"
                ),
                selection: $reminderMinutesBefore
            ) {
                Text(ATHLTHLocalization.choose(
                    english: "Off", norwegian: "Av"
                )).tag(0)
                Text(ATHLTHLocalization.choose(
                    english: "15 minutes before", norwegian: "15 minutter før"
                )).tag(15)
                Text(ATHLTHLocalization.choose(
                    english: "30 minutes before", norwegian: "30 minutter før"
                )).tag(30)
                Text(ATHLTHLocalization.choose(
                    english: "1 hour before", norwegian: "1 time før"
                )).tag(60)
                Text(ATHLTHLocalization.choose(
                    english: "2 hours before", norwegian: "2 timer før"
                )).tag(120)
            }
            .disabled(!scheduledTimeEnabled)
            if !scheduledTimeEnabled {
                Text(ATHLTHLocalization.choose(
                    english: "Choose a workout time to enable a reminder.",
                    norwegian: "Velg tidspunkt for å få påminnelse."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        } header: {
            Text(ATHLTHLocalization.choose(
                english: "Before the workout",
                norwegian: "Før økten"
            ))
        }
        .listRowBackground(ATHLTHTheme.card)
        .listRowSeparatorTint(ATHLTHTheme.border)
    }

    private var workoutBuilderOverview:
        some View {
        VStack(
            alignment: .leading,
            spacing: 13
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "WORKOUT OVERVIEW",
                            norwegian:
                                "ØKTOVERSIKT"
                        )
                    )
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                    Text(
                        title
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                            ? kind.title
                            : title
                    )
                    .font(.headline)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                }

                Spacer()

                Image(
                    systemName:
                        kind.systemImage
                )
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme
                                .champagneSoft,
                            ATHLTHTheme
                                .accentSoft
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(
                        .flexible(),
                        spacing: 7
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 7
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 7
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 7
                    )
                ],
                spacing: 7
            ) {
                workoutOverviewMetric(
                    value:
                        workoutOverviewDuration,
                    label:
                        ATHLTHLocalization.choose(
                            english: "Time",
                            norwegian: "Tid"
                        )
                )

                workoutOverviewMetric(
                    value:
                        workoutOverviewPrimaryCount,
                    label:
                        workoutOverviewPrimaryLabel
                )

                workoutOverviewMetric(
                    value:
                        workoutOverviewSecondaryCount,
                    label:
                        workoutOverviewSecondaryLabel
                )

                workoutOverviewMetric(
                    value:
                        workoutOverviewLoadValue,
                    label:
                        workoutOverviewLoadLabel
                )
            }

            if kind == .strength,
               !workoutOverviewMuscles.isEmpty {
                HStack(spacing: 7) {
                    Image(
                        systemName:
                            "figure.strengthtraining.traditional"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Text(
                        workoutOverviewMuscles
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(2)

                    Spacer()
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color.white.opacity(0.86),
                        ATHLTHTheme.surfaceStone.opacity(0.77),
                        Color.white.opacity(0.76)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        ATHLTHTheme.accent.opacity(0.15),
                        Color.white.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(0.065),
                radius: 14, x: 0, y: 7)
    }

    private func workoutOverviewMetric(
        value: String,
        label: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(value)
                .font(
                    .system(
                        size: 15,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(9)
        .frame(
            maxWidth: .infinity,
            minHeight: 49,
            alignment: .leading
        )
        .background(
            Color.white.opacity(0.57),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.78), lineWidth: 0.7)
        }
    }

    private var workoutOverviewDuration: String {
        if kind == .strength,
           let estimate = PlannedSessionDurationEstimator
               .strengthMinutes(for: plannedExercises) {
            return "~\(estimate)m"
        }
        return resolvedDurationMinutes > 0
            ? "\(resolvedDurationMinutes)m" : "–"
    }

    private var resolvedDurationMinutes: Int {
        if kind == .strength,
           let estimate = PlannedSessionDurationEstimator
               .strengthMinutes(for: plannedExercises) {
            return min(max(estimate + strengthDurationAdjustmentMinutes, 5), 300)
        }
        return durationMinutes
    }

    private var plannedDurationBinding: Binding<Int> {
        Binding(
            get: { resolvedDurationMinutes },
            set: { newValue in
                if kind == .strength,
                   let estimate = PlannedSessionDurationEstimator
                       .strengthMinutes(for: plannedExercises) {
                    strengthDurationAdjustmentMinutes = newValue - estimate
                } else {
                    durationMinutes = newValue
                    durationWasAdjustedManually = true
                }
            }
        )
    }

    private var workoutOverviewPrimaryCount:
        String {
        if kind == .running {
            return
                "\(selectedRunningWorkouts.count)"
        }

        return
            "\(plannedExercises.count)"
    }

    private var workoutOverviewPrimaryLabel:
        String {
        if kind == .running {
            return ATHLTHLocalization.choose(
                english: "Runs",
                norwegian: "Løp"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Exercises",
            norwegian: "Øvelser"
        )
    }

    private var workoutOverviewSecondaryCount:
        String {
        if kind == .strength {
            return
                "\(plannedExercises.reduce(0) { $0 + max($1.sets, 1) })"
        }

        if kind == .running {
            return
                "\(selectedRunningWorkouts.reduce(0) { $0 + $1.blocks.count })"
        }

        return "—"
    }

    private var workoutOverviewSecondaryLabel:
        String {
        if kind == .strength {
            return ATHLTHLocalization.choose(
                english: "Sets",
                norwegian: "Sett"
            )
        }

        if kind == .running {
            return ATHLTHLocalization.choose(
                english: "Blocks",
                norwegian: "Deler"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Structure",
            norwegian: "Struktur"
        )
    }

    private var workoutOverviewLoadValue:
        String {
        if kind == .strength {
            let volume =
                plannedExercises.reduce(0.0) {
                    total,
                    exercise in

                    guard
                        exercise.resolvedTargetKind ==
                            .reps,
                        exercise.resolvedLoadKind ==
                            .weightKilograms
                    else {
                        return total
                    }

                    let exerciseVolume =
                        exercise
                            .resolvedSetTargets
                            .reduce(0.0) {
                                partial,
                                target in

                                guard
                                    let reps =
                                        target.reps,
                                    let load =
                                        target
                                            .weightKilograms
                                else {
                                    return partial
                                }

                                return
                                    partial +
                                    Double(reps) *
                                    load
                            }

                    return
                        total +
                        exerciseVolume
                }

            guard volume > 0 else {
                return "—"
            }

            if volume >= 1_000 {
                return String(
                    format:
                        "%.1ft",
                    volume / 1_000
                )
            }

            return String(
                format:
                    "%.0fkg",
                volume
            )
        }

        if kind == .running ||
            kind == .walking {
            return String(
                format:
                    "%.1fkm",
                distanceKilometers
            )
        }

        return "—"
    }

    private var workoutOverviewLoadLabel:
        String {
        if kind == .strength {
            return ATHLTHLocalization.choose(
                english: "Volume",
                norwegian: "Volum"
            )
        }

        if kind == .running ||
            kind == .walking {
            return ATHLTHLocalization.choose(
                english: "Distance",
                norwegian: "Distanse"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Load",
            norwegian: "Belastning"
        )
    }

    private var workoutOverviewMuscles:
        String {
        let muscles =
            plannedExercises
                .flatMap {
                    $0.embeddedExercise
                        .primaryMuscles
                }
        var seen =
            Set<String>()
        let unique =
            muscles.filter {
                seen.insert($0)
                    .inserted
            }

        return
            unique
                .prefix(4)
                .joined(separator: " · ")
    }

    // Mirrors Quick Run's three-tool layout, but uses this editor's persisted
    // per-session overrides instead of creating an unrelated settings store.
    private var plannedRunGuidanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 11) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 40, height: 40)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Run tools", norwegian: "Løpsverktøy"
                        ))
                        .font(.headline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "Audio Coach, Ghost and route tools for this run",
                            norwegian: "Audio Coach, Ghost og ruteverktøy for denne økten"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    Spacer(minLength: 2)
                }

                HStack(spacing: 8) {
                    Button {
                        var configuration = audioCoachOverride ??
                            settings.audioCoachConfiguration(
                                enabled: settings.audioCoachEnabledByDefault)
                        configuration.enabled.toggle()
                        audioCoachOverride = configuration
                    } label: {
                        plannedGuidanceStatusPill(
                            title: "Audio Coach",
                            icon: "waveform.and.person.filled",
                            active: resolvedAudioCoachEnabled)
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard runEnvironment == .outdoor, selectedRoute != nil else { return }
                        ghostDraft.enabled.toggle()
                    } label: {
                        plannedGuidanceStatusPill(
                            title: "Ghost",
                            icon: "figure.run.circle.fill",
                            active: runEnvironment == .outdoor && ghostDraft.enabled && selectedRoute != nil,
                            unavailable: runEnvironment == .treadmill || selectedRoute == nil)
                    }
                    .buttonStyle(.plain)
                    .disabled(runEnvironment == .treadmill || selectedRoute == nil)

                    Button {
                        guard runEnvironment == .outdoor, selectedRoute != nil else { return }
                        routeGuardianDraft.enabled.toggle()
                    } label: {
                        plannedGuidanceStatusPill(
                            title: ATHLTHLocalization.choose(english: "Route", norwegian: "Rute"),
                            icon: "location.fill",
                            active: runEnvironment == .outdoor &&
                                routeGuardianDraft.enabled && selectedRoute != nil,
                            unavailable: runEnvironment == .treadmill || selectedRoute == nil)
                    }
                    .buttonStyle(.plain)
                    .disabled(runEnvironment == .treadmill || selectedRoute == nil)
                }

                Text(runEnvironment == .treadmill
                    ? ATHLTHLocalization.choose(
                        english: "Indoor run: GPS, route monitoring and route Ghost stay off. Audio Coach and phase targets remain available.",
                        norwegian: "Innendørs: GPS, rutevarsler og rute-Ghost er av. Audio Coach og mål per del fungerer fortsatt.")
                    : selectedRoute == nil
                        ? ATHLTHLocalization.choose(
                            english: "Choose an outdoor route to unlock Ghost and route monitoring.",
                            norwegian: "Velg en utendørs rute for å bruke Ghost og rutevarsler.")
                        : ATHLTHLocalization.choose(
                            english: "Tap a tool to enable or disable it for this workout.",
                            norwegian: "Trykk på et verktøy for å slå det av eller på for denne økten."))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                HStack(spacing: 16) {
                    Button {
                        showingAudioCoachEditor = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Set up Coach", norwegian: "Tilpass Coach"
                        ), systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)

                    Button {
                        editorMode = .advanced
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Live targets", norwegian: "Live-mål"
                        ), systemImage: "scope")
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

                if runEnvironment == .outdoor && selectedRoute != nil {
                    DisclosureGroup(ATHLTHLocalization.choose(
                        english: "Advanced route tools", norwegian: "Avanserte ruteverktøy"
                    )) {
                        NavigationLink {
                            PerWorkoutRouteGuardianView(draft: $routeGuardianDraft)
                        } label: {
                            guidancePlannerRow(
                                title: "Route Guardian",
                                subtitle: ATHLTHLocalization.choose(
                                    english: "Route deviation alerts", norwegian: "Varsler ved avvik fra ruten"),
                                icon: "location.fill", tint: ATHLTHTheme.vitality)
                        }
                        NavigationLink {
                            PerWorkoutGhostView(draft: $ghostDraft, route: selectedRoute)
                        } label: {
                            guidancePlannerRow(
                                title: "Ghost",
                                subtitle: ATHLTHLocalization.choose(
                                    english: "Target time and audio updates", norwegian: "Måltid og lydoppdateringer"),
                                icon: "figure.run.circle.fill", tint: ATHLTHPlanDesign.accentInk)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(ATHLTHPlanDesign.surface)
        .listRowSeparator(.hidden)
    }

    private var resolvedAudioCoachEnabled:
        Bool {
        audioCoachOverride?
            .enabled ??
        settings
            .audioCoachEnabledByDefault
    }

    private var plannedLiveAlertSummary:
        String {
        if hasLiveTargetAlerts {
            return ATHLTHLocalization.choose(
                english:
                    "Heart-rate or pace alerts configured",
                norwegian:
                    "Puls- eller tempovarsler er satt opp"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "Optional heart-rate and pace guidance",
            norwegian:
                "Valgfrie puls- og tempovarsler"
        )
    }

    private func plannedGuidanceStatusPill(
        title: String,
        icon: String,
        active: Bool,
        unavailable: Bool = false
    ) -> some View {
        HStack(spacing: 5) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 9,
                    weight: .semibold
                )
            )

            Text(title)
                .font(
                    .system(
                        size: 9.5,
                        weight: .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.72
                )
        }
        .foregroundStyle(
            unavailable
                ? ATHLTHTheme
                    .mutedText
                    .opacity(0.65)
                : (
                    active
                        ? ATHLTHTheme
                            .vitality
                        : ATHLTHTheme
                            .primaryText
                )
        )
        .frame(
            maxWidth: .infinity
        )
        .frame(height: 32)
        .background(
            active
                ? ATHLTHTheme
                    .vitalitySoft
                : Color.primary
                    .opacity(0.04),
            in: Capsule()
        )
    }

    private func guidancePlannerRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 11) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 15,
                    weight: .semibold
                )
            )
            .foregroundStyle(tint)
            .frame(
                width: 34,
                height: 34
            )
            .background(
                tint.opacity(0.10),
                in: RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(
            .vertical,
            2
        )
    }

    @ViewBuilder
    private func phaseEditor(
        for selection: SessionRunningPhaseSelection
    ) -> some View {
        if let workout = selectedRunningWorkouts.first(where: { $0.id == selection.workoutID }),
           let block = workout.blocks.first(where: { $0.id == selection.blockID }) {
            let target: RunningStepTarget? = selection.isRecovery ? block.recovery : block.work
            if let target {
                ATHLTHPlannedRunningPhaseEditor(
                    title: selection.isRecovery
                        ? ATHLTHLocalization.choose(english: "Active recovery", norwegian: "Aktiv pause")
                        : runningPhaseTitle(block.kind),
                    target: target,
                    environment: runEnvironment,
                    fallbackPace: targetPaceEnabled
                        ? Double(targetPaceMinutes * 60 + targetPaceSeconds) : 360
                ) { updated in
                    updateRunningPhase(selection, target: updated)
                }
            }
        }
    }

    @ViewBuilder
    private func repetitionEditor(
        for selection: SessionRunningRepetitionSelection
    ) -> some View {
        if let workout = selectedRunningWorkouts.first(where: { $0.id == selection.workoutID }),
           let block = workout.blocks.first(where: { $0.id == selection.blockID }) {
            ATHLTHIntervalRepetitionEditorView(
                block: block, repetition: selection.repetition,
                environment: runEnvironment
            ) { override in
                updateRunningRepetition(selection, override: override)
            }
        }
    }

    // The chosen workout is deliberately presented before "Legg til".
    // Phase targets edit the real persisted RunningWorkoutTemplate and flow
    // unchanged into WatchRunningWorkoutTransfer on both devices.
    private var runningBuilder: some View {
        Section {
            VStack(alignment: .leading, spacing: 13) {
                if selectedRunningWorkouts.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.title3)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 44, height: 44)
                            .background(ATHLTHPlanDesign.selectedSurface,
                                        in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ATHLTHLocalization.choose(
                                english: "Open running session",
                                norwegian: "Åpen løpeøkt"
                            ))
                            .font(.subheadline.weight(.semibold))
                            Text(ATHLTHLocalization.choose(
                                english: "Optional: choose an interval workout to set zones and pace for each phase.",
                                norwegian: "Valgfritt: Velg en intervalløkt for å angi sone og tempo for hver del."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    Button {
                        showingRunningLibrary = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Choose running workout", norwegian: "Velg løpeøkt"
                        ), systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                } else {
                    ForEach(Array(selectedRunningWorkouts.enumerated()), id: \.element.id) { index, workout in
                        VStack(alignment: .leading, spacing: 11) {
                            // Place the interval summary at the top of its
                            // own card, above editing controls and phase targets.
                            let recipeDescription = workout.summary
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !recipeDescription.isEmpty {
                                Text(recipeDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: 11) {
                                Image(systemName: workout.type.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    .frame(width: 45, height: 45)
                                    .background(ATHLTHPlanDesign.selectedSurface,
                                                in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(workout.title)
                                        .font(.headline)
                                        .foregroundStyle(ATHLTHPlanDesign.ink)
                                    Text(runningWorkoutMetricSummary(workout))
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                                Spacer(minLength: 2)
                                Button {
                                    replacingRunningWorkoutID = workout.id
                                    showingRunningLibrary = true
                                } label: {
                                    Text(ATHLTHLocalization.choose(english: "Change", norwegian: "Endre"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .background(ATHLTHPlanDesign.warmSurface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                Button(role: .destructive) {
                                    removeRunningWorkout(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(ATHLTHLocalization.choose(
                                    english: "Remove workout", norwegian: "Fjern løpeøkt"
                                ))
                            }

                            Divider().overlay(ATHLTHPlanDesign.warmDivider)

                            HStack(spacing: 8) {
                                Image(systemName: "waveform.path")
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                Text(ATHLTHLocalization.choose(
                                    english: "Running guidance", norwegian: "Løpeveiledning"
                                ))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                Spacer()
                                if let seconds = estimatedRunningTotals(for: [workout]).durationSeconds {
                                    Text("\(Int((seconds / 60).rounded())) min")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }
                            }

                            ForEach(workout.blocks) { block in
                                phaseTargetRow(workout: workout, block: block, isRecovery: false)
                                if block.recovery != nil && block.repetitions > 1 {
                                    phaseTargetRow(workout: workout, block: block, isRecovery: true)
                                }
                                if block.kind == .work && block.repetitions > 1 {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(1...min(max(block.repetitions, 1), 60), id: \.self) { repetition in
                                                Button {
                                                    editingRunningRepetition = SessionRunningRepetitionSelection(
                                                        workoutID: workout.id,
                                                        blockID: block.id,
                                                        repetition: repetition
                                                    )
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text(ATHLTHLocalization.choose(
                                                            english: "Effort", norwegian: "Drag"
                                                        ) + " \(repetition)")
                                                        Image(systemName: "slider.horizontal.3")
                                                    }
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                                    .padding(.horizontal, 10)
                                                    .frame(height: 31)
                                                    .background(ATHLTHPlanDesign.warmSurface, in: Capsule())
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }

                            Text(ATHLTHLocalization.choose(
                                english: "Choose a heart-rate zone and pace per phase. Adjust individual efforts when needed. All targets are saved with the workout.",
                                norwegian: "Velg pulssone og tempo per del. Juster enkelt-drag ved behov. Alle målene lagres med økten."
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        if index < selectedRunningWorkouts.count - 1 {
                            Divider().overlay(ATHLTHPlanDesign.warmDivider)
                                .padding(.vertical, 3)
                        }
                    }
                }
            }
            .padding(.vertical, 5)
        }
        .listRowBackground(ATHLTHPlanDesign.surface)
        .listRowSeparator(.hidden)
    }

    private func runningPhaseTitle(_ kind: RunningBlockKind) -> String {
        switch kind {
        case .warmup: return ATHLTHLocalization.choose(english: "Warm-up", norwegian: "Oppvarming")
        case .work: return ATHLTHLocalization.choose(english: "Effort", norwegian: "Drag")
        case .recovery: return ATHLTHLocalization.choose(english: "Recovery", norwegian: "Pause")
        case .steady: return ATHLTHLocalization.choose(english: "Steady run", norwegian: "Rolig løp")
        case .cooldown: return ATHLTHLocalization.choose(english: "Cool-down", norwegian: "Nedjogg")
        }
    }

    private func phaseTargetRow(
        workout: RunningWorkoutTemplate,
        block: RunningWorkoutBlock,
        isRecovery: Bool
    ) -> some View {
        let target: RunningStepTarget = isRecovery ? (block.recovery ?? .open) : block.work
        let count = isRecovery ? max(0, block.repetitions - 1) : max(1, block.repetitions)
        let name = isRecovery
            ? ATHLTHLocalization.choose(english: "Active recovery", norwegian: "Aktiv pause")
            : runningPhaseTitle(block.kind)
        let zone = target.intensity.heartRateZone
        let pace = target.intensity.paceMinSecondsPerKilometer
        let targetDescription = [
            zone.map { ATHLTHLocalization.choose(english: "Zone", norwegian: "Sone") + " \($0)" },
            pace.map { value in
                runEnvironment == .treadmill
                    ? String(format: "%.1f km/t", 3600 / value)
                    : String(format: "%d:%02d min/km", Int(value) / 60, Int(value) % 60)
            }
        ].compactMap { $0 }.joined(separator: " · ")
        return Button {
            editingRunningPhase = SessionRunningPhaseSelection(
                workoutID: workout.id, blockID: block.id, isRecovery: isRecovery
            )
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(isRecovery ? Color.blue.opacity(0.8) :
                          (block.kind == .work ? Color.orange : ATHLTHTheme.vitality))
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(targetDescription.isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "Set zone and pace", norwegian: "Angi sone og tempo"
                        ) : targetDescription)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 4)
                if let seconds = target.durationSeconds {
                    Text(count > 1
                        ? "\(count) × \(Int((seconds / 60).rounded())) min"
                        : "\(Int((seconds / 60).rounded())) min")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .monospacedDigit()
                } else if let meters = target.distanceMeters {
                    Text(count > 1 ? "\(count) × \(Int(meters)) m" : "\(Int(meters)) m")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(ATHLTHPlanDesign.warmSurface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name + ": " + targetDescription)
    }

    private func updateRunningPhase(
        _ selection: SessionRunningPhaseSelection,
        target: RunningStepTarget
    ) {
        guard let workoutIndex = selectedRunningWorkouts.firstIndex(where: { $0.id == selection.workoutID }),
              let blockIndex = selectedRunningWorkouts[workoutIndex].blocks.firstIndex(where: { $0.id == selection.blockID })
        else { return }
        var selected = selectedRunningWorkouts[workoutIndex]
        if selection.isRecovery {
            selected.blocks[blockIndex].recovery = target
        } else {
            selected.blocks[blockIndex].work = target
        }
        selectedRunningWorkouts[workoutIndex] = selected
        syncRunningMetricsFromSelection()
    }

    private func updateRunningRepetition(
        _ selection: SessionRunningRepetitionSelection,
        override: RunningRepetitionOverride
    ) {
        guard let workoutIndex = selectedRunningWorkouts.firstIndex(where: { $0.id == selection.workoutID }),
              let blockIndex = selectedRunningWorkouts[workoutIndex].blocks.firstIndex(where: { $0.id == selection.blockID })
        else { return }
        var selected = selectedRunningWorkouts[workoutIndex]
        var block = selected.blocks[blockIndex]
        var overrides = block.repetitionOverrides ?? []
        overrides.removeAll { $0.repetition == selection.repetition }
        overrides.append(override)
        block.repetitionOverrides = overrides.sorted { $0.repetition < $1.repetition }
        selected.blocks[blockIndex] = block
        selectedRunningWorkouts[workoutIndex] = selected
        syncRunningMetricsFromSelection()
    }


    private var routeBuilder: some View {
        Section("Route") {
            Picker("Route", selection: $selectedRouteID) {
                Text("No specific route")
                    .tag(nil as UUID?)

                ForEach(session.savedRoutes) { route in
                    Text(
                        "\(route.title) · \(route.distanceKilometers, specifier: "%.1f") km"
                    )
                    .tag(route.id as UUID?)
                }
            }

            if let selectedRoute {
                HStack(spacing: 8) {
                    Label(
                        String(
                            format: "%.1f km",
                            selectedRoute.distanceKilometers
                        ),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )

                    if kind == .walking,
                       let seconds =
                            selectedRoute.expectedTravelTimeSeconds {
                        Label(
                            ATHLTHLocalization.format(
                                    english: "%d min",
                                    norwegian: "%d min",
                                    max(Int((seconds / 60).rounded()), 1)
                                ),
                            systemImage: "timer"
                        )
                    }

                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if session.savedRoutes.isEmpty {
                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label("Create a Route", systemImage: "map.fill")
                }

                Text(
                    "Routes are optional. Create one in ATHLTH and it will appear here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // Show the suggested title as the TextField placeholder until the
    // athlete enters a custom name. Reuse this exact value when saving so
    // calendar, history and invitations never receive a blank title.
    private var automaticWorkoutTitle: String {
        if kind == .running {
            if selectedRunningWorkouts.count == 1 {
                let templateTitle = selectedRunningWorkouts[0].title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !templateTitle.isEmpty {
                    return templateTitle
                }
            }

            if runEnvironment == .treadmill {
                return ATHLTHLocalization.choose(
                    english: "Indoor running – treadmill",
                    norwegian: "Løping innendørs – tredemølle"
                )
            }
        }

        return kind.title
    }

    private var resolvedWorkoutTitle: String {
        let enteredTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return enteredTitle.isEmpty ? automaticWorkoutTitle : enteredTitle
    }

    private var canAdd: Bool {
        !resolvedWorkoutTitle.isEmpty
    }

    private func addExercise(_ exercise: Exercise) {
        guard onPreparedWorkout == nil ||
            initialSourceWorkout?.allowInviteeExercises == true else { return }
        let planned = PlannedExercise(
            id: UUID(),
            exerciseID: exercise.id,
            embeddedExercise: exercise.snapshot,
            sets: 3,
            reps: 8,
            targetWeightKilograms: nil,
            targetRPE: nil,
            restSeconds: 90,
            notes: nil,
            targetRIR: nil,
            supersetGroupID: nil,
            progression: StrengthProgressionRule.none
        )

        var inserted = planned
        inserted.workoutPhase = exerciseInsertPhase
        if exerciseInsertPhase == .warmup {
            inserted.setEntireExerciseWarmUp(true)
        }
        plannedExercises.append(inserted)
    }

    private func duplicatePlannedExercise(
        at index: Int
    ) {
        guard onPreparedWorkout == nil ||
            initialSourceWorkout?.allowInviteeExercises == true else { return }
        guard
            plannedExercises.indices
                .contains(index)
        else {
            return
        }

        let source =
            plannedExercises[index]
        let duplicate =
            PlannedExercise(
                id: UUID(),
                exerciseID:
                    source.exerciseID,
                embeddedExercise:
                    source.embeddedExercise,
                sets: source.sets,
                reps: source.reps,
                targetWeightKilograms:
                    source.targetWeightKilograms,
                targetRPE:
                    source.targetRPE,
                restSeconds:
                    source.restSeconds,
                notes: source.notes,
                targetRIR:
                    source.targetRIR,
                supersetGroupID: nil,
                progression:
                    source.progression,
                targetKind:
                    source.targetKind,
                targetDurationSeconds:
                    source.targetDurationSeconds,
                loadKind:
                    source.loadKind,
                targetResistanceLevel:
                    source.targetResistanceLevel,
                setTargets:
                    source.setTargets?.map {
                        PlannedExerciseSetTarget(
                            reps: $0.reps,
                            durationSeconds:
                                $0.durationSeconds,
                            weightKilograms:
                                $0.weightKilograms,
                            resistanceLevel:
                                $0.resistanceLevel,
                            restSeconds:
                                $0.restSeconds,
                            targetRPE:
                                $0.targetRPE,
                            targetRIR:
                                $0.targetRIR,
                            isWarmUp:
                                $0.isWarmUp,
                            setType:
                                $0.setType,
                            tempo:
                                $0.tempo,
                            notes:
                                $0.notes
                        )
                    }
            )

        var phasedDuplicate = duplicate
        phasedDuplicate.workoutPhase = source.workoutPhase
        plannedExercises.insert(
            phasedDuplicate,
            at:
                min(
                    index + 1,
                    plannedExercises.count
                )
        )
    }

    private func toggleSuperset(at index: Int) {
        guard index > 0,
              plannedExercises.indices.contains(index),
              plannedExercises.indices.contains(index - 1)
        else {
            return
        }

        if plannedExercises[index].supersetGroupID != nil {
            let group = plannedExercises[index].supersetGroupID
            plannedExercises[index].supersetGroupID = nil

            if plannedExercises[index - 1].supersetGroupID == group {
                plannedExercises[index - 1].supersetGroupID = nil
            }
        } else {
            let group =
                plannedExercises[index - 1].supersetGroupID ??
                UUID()

            plannedExercises[index - 1].supersetGroupID = group
            plannedExercises[index].supersetGroupID = group
        }
    }

    private var runningSelectionSummary: String {
        let totals = estimatedRunningTotals()
        var parts: [String] = []
        if let meters = totals.distanceMeters {
            parts.append(String(format: "~%.1f km", meters / 1_000))
        }
        if let seconds = totals.durationSeconds {
            parts.append("\(Int((seconds / 60).rounded())) min")
        }
        return parts.isEmpty ? ATHLTHLocalization.choose(
            english: "Add a pace or time target to estimate totals.",
            norwegian: "Legg til tempo eller tidsmål for å beregne totalen."
        ) : parts.joined(separator: " · ")
    }

    private func runningWorkoutMetricSummary(_ workout: RunningWorkoutTemplate) -> String {
        let totals = estimatedRunningTotals(for: [workout])
        var parts = [workout.type.title, "\(workout.blocks.count) blokker"]
        if let meters = totals.distanceMeters {
            parts.append(String(format: "~%.1f km", meters / 1_000))
        }
        if let seconds = totals.durationSeconds {
            parts.append("\(Int((seconds / 60).rounded())) min")
        }
        return parts.joined(separator: " · ")
    }

    private func addRunningWorkout(
        _ workout: RunningWorkoutTemplate
    ) {
        guard !selectedRunningWorkouts.contains(
            where: { $0.id == workout.id }
        ) else {
            return
        }

        selectedRunningWorkouts.append(workout)
        // The suggested title updates through automaticWorkoutTitle; do
        // not write it into the field or replace a user-entered title.
        syncRunningMetricsFromSelection()
    }

    private func removeRunningWorkout(
        at index: Int
    ) {
        guard selectedRunningWorkouts.indices.contains(index)
        else {
            return
        }

        selectedRunningWorkouts.remove(at: index)
        syncRunningMetricsFromSelection()
    }

    private func syncRunningMetricsFromSelection() {
        guard !selectedRunningWorkouts.isEmpty else { return }

        let totals = estimatedRunningTotals()
        if let selectedRoute, runEnvironment != .treadmill {
            if !distanceWasAdjustedManually { distanceKilometers = selectedRoute.distanceKilometers }
        } else if let meters = totals.distanceMeters, !distanceWasAdjustedManually {
            distanceKilometers = (meters / 100).rounded() / 10
        }
        if let seconds = totals.durationSeconds, !durationWasAdjustedManually {
            durationMinutes = max(1, Int((seconds / 60).rounded()))
        }
    }

    private func estimatedRunningTotals(
        for templates: [RunningWorkoutTemplate]? = nil
    ) -> (distanceMeters: Double?, durationSeconds: Double?) {
        let targetPace = targetPaceEnabled
            ? Double(targetPaceMinutes * 60 + targetPaceSeconds)
            : 360.0
        return ATHLTHRunningPlanningEstimate.totals(
            for: templates ?? selectedRunningWorkouts,
            defaultPaceSecondsPerKilometer: targetPace
        )
    }

    private func syncMetricsFromRouteChange(
        previousRouteID: UUID?,
        routeID: UUID?
    ) {
        guard let routeID else {
            if kind == .running,
               !selectedRunningWorkouts.isEmpty {
                syncRunningMetricsFromSelection()
            }
            return
        }

        guard let route = session.savedRoutes.first(
            where: { $0.id == routeID }
        ) else {
            return
        }

        let previousDistance = max(
            distanceKilometers,
            0.01
        )
        let previousDuration = max(
            durationMinutes,
            1
        )

        distanceKilometers = route.distanceKilometers

        if kind == .walking {
            if let seconds = route.expectedTravelTimeSeconds,
               seconds > 0 {
                durationMinutes = max(
                    5,
                    Int((seconds / 60).rounded())
                )
            }
            return
        }

        guard kind == .running else {
            return
        }

        let distanceValues =
            selectedRunningWorkouts
                .compactMap(\.estimatedDistanceMeters)
        let durationValues =
            selectedRunningWorkouts
                .compactMap(\.estimatedDurationSeconds)

        let hasCompleteDistance =
            !selectedRunningWorkouts.isEmpty &&
            distanceValues.count == selectedRunningWorkouts.count
        let hasCompleteDuration =
            !selectedRunningWorkouts.isEmpty &&
            durationValues.count == selectedRunningWorkouts.count

        if hasCompleteDuration {
            let totalSeconds =
                durationValues.reduce(0, +)

            if hasCompleteDistance {
                let totalMeters =
                    distanceValues.reduce(0, +)

                if totalMeters > 0 {
                    durationMinutes = max(
                        5,
                        Int(
                            (
                                route.distanceKilometers *
                                1_000 *
                                totalSeconds /
                                totalMeters /
                                60
                            )
                            .rounded()
                        )
                    )
                    return
                }
            }

            durationMinutes = max(
                5,
                Int((totalSeconds / 60).rounded())
            )
            return
        }

        // No reliable running duration exists on the saved route itself
        // (Apple Maps stores a walking estimate). Preserve the user's
        // current implied pace when switching to a different run route.
        let impliedMinutesPerKilometer =
            targetPaceEnabled
                ? Double(targetPaceMinutes * 60 + targetPaceSeconds) / 60
                : (durationMinutes > 0 && previousDistance > 0.01
                    ? Double(previousDuration) / previousDistance
                    : 6.0)

        durationMinutes = max(
            5,
            Int(
                (
                    route.distanceKilometers *
                    impliedMinutesPerKilometer
                )
                .rounded()
            )
        )
    }


    private func clonePlannedExercises(
        _ exercises: [PlannedExercise]
    ) -> [PlannedExercise] {
        var supersetIDs:
            [UUID: UUID] = [:]

        return exercises.map { exercise in
            let clonedSupersetID =
                exercise.supersetGroupID.map {
                    originalID in
                    if let existing =
                        supersetIDs[originalID] {
                        return existing
                    }

                    let replacement = UUID()
                    supersetIDs[originalID] =
                        replacement
                    return replacement
                }

            var cloned = PlannedExercise(
                id: UUID(),
                exerciseID:
                    exercise.exerciseID,
                embeddedExercise:
                    exercise.embeddedExercise,
                sets: exercise.sets,
                reps: exercise.reps,
                targetWeightKilograms:
                    exercise.targetWeightKilograms,
                targetRPE:
                    exercise.targetRPE,
                restSeconds:
                    exercise.restSeconds,
                notes: exercise.notes,
                targetRIR:
                    exercise.targetRIR,
                supersetGroupID:
                    clonedSupersetID,
                progression:
                    exercise.progression,
                targetKind:
                    exercise.targetKind,
                targetDurationSeconds:
                    exercise.targetDurationSeconds,
                loadKind:
                    exercise.loadKind,
                targetResistanceLevel:
                    exercise.targetResistanceLevel,
                setTargets:
                    exercise.setTargets?.map {
                        PlannedExerciseSetTarget(
                            reps: $0.reps,
                            durationSeconds:
                                $0.durationSeconds,
                            weightKilograms:
                                $0.weightKilograms,
                            resistanceLevel:
                                $0.resistanceLevel,
                            restSeconds:
                                $0.restSeconds,
                            targetRPE:
                                $0.targetRPE,
                            targetRIR:
                                $0.targetRIR,
                            isWarmUp:
                                $0.isWarmUp,
                            setType:
                                $0.setType,
                            tempo:
                                $0.tempo,
                            notes:
                                $0.notes
                        )
                    }
            )
            cloned.workoutPhase = exercise.workoutPhase
            return cloned
        }
    }

    private func plannedExercisesFromBlocks(
        _ blocks: [WorkoutTemplateBlock]
    ) -> [PlannedExercise] {
        blocks
            .filter {
                $0.kind == .exercise
            }
            .map { block in
                let slug =
                    block.exerciseSlug?
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                let resolvedEntry =
                    exerciseLibrary
                        .allExercises
                        .first { entry in
                            if let slug,
                               let identifier =
                                entry.sourceIdentifier {
                                return identifier
                                    .caseInsensitiveCompare(
                                        slug
                                    ) == .orderedSame
                            }

                            return entry.name
                                .caseInsensitiveCompare(
                                    block.title
                                ) == .orderedSame
                        }

                let snapshot =
                    resolvedEntry?
                        .exercise
                        .snapshot ??
                    ExerciseSnapshot(
                        name: block.title,
                        instructions: [],
                        primaryMuscles: [],
                        equipment: [],
                        imageURL: nil
                    )

                let noteParts =
                    [
                        block.loadNote,
                        block.notes
                    ]
                    .compactMap { value in
                        value?
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                    }
                    .filter {
                        !$0.isEmpty
                    }

                return PlannedExercise(
                    id: UUID(),
                    exerciseID:
                        resolvedEntry?
                            .exercise.id,
                    embeddedExercise:
                        snapshot,
                    sets: 1,
                    reps:
                        block.repetitions,
                    targetWeightKilograms:
                        block.targetWeightKilograms,
                    targetRPE: nil,
                    restSeconds: nil,
                    notes:
                        noteParts.isEmpty
                            ? nil
                            : noteParts.joined(
                                separator: " · "
                            ),
                    targetRIR: nil,
                    supersetGroupID: nil,
                    progression:
                        StrengthProgressionRule.none
                )
            }
    }

    private var inheritedSpotifyPlaylist:
        SpotifyPlaylistReference? {
        guard
            let planID,
            let plan =
                session.trainingPlan(
                    withID: planID
                ),
            plan.spotifyAutoplayOnWorkoutStart
        else {
            return nil
        }

        return plan.spotifyPlaylist
    }

    private var effectiveSpotifyPlaylist:
        SpotifyPlaylistReference? {
        if let explicit =
                spotifyAutoplayOnStart {
            guard explicit else {
                return nil
            }

            return selectedSpotifyPlaylist
        }

        return inheritedSpotifyPlaylist
    }

    private var spotifyWorkoutEnabled:
        Binding<Bool> {
        Binding(
            get: {
                effectiveSpotifyPlaylist != nil
            },
            set: { enabled in
                if enabled {
                    if selectedSpotifyPlaylist != nil {
                        spotifyAutoplayOnStart = true
                    } else if let inherited =
                                inheritedSpotifyPlaylist {
                        selectedSpotifyPlaylist =
                            inherited
                        spotifyAutoplayOnStart =
                            true
                    } else {
                        spotifyAutoplayOnStart =
                            true
                        showingSpotifyPlaylistPicker =
                            true
                    }
                } else {
                    spotifyAutoplayOnStart = false
                }
            }
        )
    }

    private var spotifyWorkoutPlaylistSelection:
        Binding<SpotifyPlaylistReference?> {
        Binding(
            get: {
                selectedSpotifyPlaylist ??
                    (
                        spotifyAutoplayOnStart == nil
                            ? inheritedSpotifyPlaylist
                            : nil
                    )
            },
            set: { playlist in
                selectedSpotifyPlaylist =
                    playlist
                spotifyAutoplayOnStart =
                    playlist == nil
                        ? false
                        : true
            }
        )
    }

    private var spotifyWorkoutPlaylistLabel:
        String {
        if spotifyAutoplayOnStart == false {
            return "Off"
        }

        if let selectedSpotifyPlaylist {
            return selectedSpotifyPlaylist.name
        }

        if spotifyAutoplayOnStart == nil,
           let inheritedSpotifyPlaylist {
            return "Program default · \(inheritedSpotifyPlaylist.name)"
        }

        return "No linked playlist"
    }

    private func applySavedWorkout(
        _ workout: PlannedSession
    ) {
        title = workout.title
        kind = workout.kind
        durationMinutes =
            workout.durationMinutes ?? durationMinutes
        if let estimate = PlannedSessionDurationEstimator
            .strengthMinutes(for: workout.exercises) {
            strengthDurationAdjustmentMinutes =
                (workout.durationMinutes ?? estimate) - estimate
        } else {
            strengthDurationAdjustmentMinutes = 0
        }
        distanceKilometers = workout.targetDistanceKilometers ?? 0
        distanceWasAdjustedManually = workout.targetDistanceKilometers != nil
        durationWasAdjustedManually = workout.durationMinutes != nil
        runEnvironment = workout.workoutCategory == "treadmill" ||
            workout.resolvedWorkoutBlocks.contains(where: { $0.kind == .run && $0.isIndoor == true })
                ? .treadmill : .outdoor
        notes = workout.notes ?? ""

        let copiedExercises =
            clonePlannedExercises(
                workout.exercises
            )
        plannedExercises = preserveSourceID
            ? workout.exercises
            : copiedExercises.isEmpty
                ? plannedExercisesFromBlocks(
                    workout.resolvedWorkoutBlocks
                )
                : copiedExercises

        selectedRunningWorkouts =
            workout.resolvedRunningWorkouts
        selectedRouteID = workout.routeID
        selectedGearIDs = Set(workout.gearIDs ?? [])
        gearSelectionTouched = workout.gearIDs != nil
        audioCoachOverride =
            workout.audioCoachConfiguration

        if let routeConfiguration =
                workout.routeAlertConfiguration {
            routeGuardianDraft.load(
                configuration:
                    routeConfiguration
            )
        } else {
            routeGuardianDraft.load(
                from: settings
            )
        }

        ghostDraft.load(
            targetDuration:
                workout
                    .ghostTargetDurationSeconds,
            updates:
                workout
                    .ghostUpdates,
            route:
                selectedRoute,
            settings:
                settings
        )

        autoPausePreference =
            WorkoutAutoPausePreference(
                overrideValue:
                    workout.autoPauseEnabled
            )
        selectedSpotifyPlaylist =
            workout.spotifyPlaylist
        spotifyAutoplayOnStart =
            workout.spotifyAutoplayOnStart
        workoutTemplateID =
            workout.workoutTemplateID
        workoutBlocks = preserveSourceID
            ? workout.workoutBlocks ?? []
            : workout.resolvedWorkoutBlocks
        workoutCategory = workout.workoutCategory
        meetingPoint = workout.meetingPoint
        physicalMeetup = workout.trainTogetherMode != .sameWorkout
        allowInviteeExercises = workout.allowInviteeExercises == true
        reminderMinutesBefore = workout.reminderMinutesBefore ?? 0

        if let scheduled = workout.scheduledStart {
            scheduledTimeEnabled = true
            scheduledTime = scheduled
        }

        targetPaceEnabled = false
        if let pace =
                workout.targetPaceSecondsPerKilometer,
           pace > 0 {
            let total = max(Int(pace.rounded()), 0)
            targetPaceEnabled = true
            targetPaceMinutes = total / 60
            targetPaceSeconds = total % 60
        }
        if kind == .running { syncRunningMetricsFromSelection() }
    }

    private func composeSession() -> PlannedSession {
        let cleanNotes = notes
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return PlannedSession(
            id: existingWorkout?.id ??
                (preserveSourceID ? initialSourceWorkout?.id ?? UUID() : UUID()),
            title: resolvedWorkoutTitle,
            kind: kind,
            scheduledStart:
                isStandalone
                    ? scheduledTime
                    : scheduledTimeEnabled
                        ? scheduledTime
                        : nil,
            durationMinutes: resolvedDurationMinutes > 0 ? resolvedDurationMinutes : nil,
            targetDistanceKilometers:
                (kind == .walking || kind == .running) && distanceKilometers > 0
                    ? distanceKilometers : nil,
            targetPaceSecondsPerKilometer:
                kind == .running &&
                targetPaceEnabled
                    ? Double(
                        targetPaceMinutes * 60 +
                        targetPaceSeconds
                    )
                    : nil,
            routeID: kind == .running && runEnvironment == .treadmill ? nil : selectedRouteID,
            // Preserve exercises for hybrid/custom structured
            // workouts too (for example HYROX), not only .strength.
            exercises: plannedExercises,
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            runningWorkout: kind == .running
                ? selectedRunningWorkouts.first
                : nil,
            runningWorkouts: kind == .running
                ? selectedRunningWorkouts
                : nil,
            gearIDs: plannedGearIDsForSave,
            audioCoachConfiguration:
                (kind == .running || kind == .walking)
                    ? audioCoachOverride
                    : nil,
            autoPauseEnabled:
                (kind == .running || kind == .walking)
                    ? autoPausePreference.overrideValue
                    : nil,
            spotifyPlaylist:
                selectedSpotifyPlaylist,
            spotifyAutoplayOnStart:
                spotifyAutoplayOnStart,
            targetAlertConfiguration:
                (kind == .running || kind == .walking)
                    ? workoutTargetAlertConfigurationForSave
                    : nil,
            routeAlertConfiguration:
                kind == .running && runEnvironment == .outdoor &&
                selectedRoute != nil
                    ? routeGuardianDraft
                        .configuration
                    : nil,
            ghostTargetDurationSeconds:
                kind == .running && runEnvironment == .outdoor &&
                selectedRoute != nil
                    ? ghostDraft
                        .targetDuration
                    : nil,
            ghostUpdates:
                kind == .running && runEnvironment == .outdoor &&
                selectedRoute != nil &&
                ghostDraft.enabled
                    ? (
                        ghostDraft
                            .updatesEnabled
                            ? settings
                                .ghostRaceAudioConfiguration
                            : .disabled
                    )
                    : nil,
            workoutTemplateID:
                workoutTemplateID,
            workoutBlocks:
                workoutBlocks.isEmpty
                    ? nil
                    : workoutBlocks,
            workoutCategory:
                kind == .running && runEnvironment == .treadmill
                    ? "treadmill"
                    : (workoutCategory == "treadmill" ? nil : workoutCategory),
            meetingPoint: selectedPartnerID != nil ? meetingPoint : nil,
            reminderMinutesBefore: scheduledTimeEnabled && reminderMinutesBefore > 0
                ? reminderMinutesBefore : nil,
            trainTogetherMode: onPreparedWorkout != nil
                ? initialSourceWorkout?.trainTogetherMode
                : selectedPartnerID == nil ? nil : .physical,
            invitedPartnerID: onPreparedWorkout != nil
                ? initialSourceWorkout?.invitedPartnerID : selectedPartnerID,
            allowInviteeExercises: onPreparedWorkout != nil
                ? initialSourceWorkout?.allowInviteeExercises
                : selectedPartnerID == nil ? nil : allowInviteeExercises
        )

    }

    private func saveSession() {
        guard canAdd, !isSaving else { return }
        let workout = pendingInvitationWorkout ?? composeSession()

        // Marketplace proposals only prepare a workout; they must not
        // modify the author's calendar or send another invitation.
        if onPreparedWorkout != nil {
            commitSession(workout)
            return
        }

        guard let partnerID = selectedPartnerID else {
            commitSession(workout)
            return
        }

        // The author's calendar is independent of the recipient's answer
        // and of temporary Messages/network failures. A retry reuses the
        // SAME session ID, rather than creating duplicate calendar entries.
        if pendingInvitationWorkout == nil {
            persistSession(workout)
            pendingInvitationWorkout = workout
        }

        isSaving = true
        Task {
            do {
                let conversationID = try await messaging.openConversation(
                    with: partnerID
                )
                let scheduled = workout.scheduledStart?.formatted(
                    date: .abbreviated, time: .shortened
                ) ?? ATHLTHLocalization.choose(
                    english: "Time to be agreed",
                    norwegian: "Tidspunkt avtales"
                )
                var sharedWorkout = workout
                // Device, personal gear and music never leave the sender.
                sharedWorkout.gearIDs = []
                sharedWorkout.spotifyPlaylist = nil
                sharedWorkout.spotifyAutoplayOnStart = false
                let attachment = try MessageShareDraft(
                    kind: .workout,
                    title: workout.title,
                    subtitle: scheduled,
                    snapshot: sharedWorkout,
                    sourceObjectID: workout.id,
                    sourceOwnerID: session.profile.userID,
                    shareVersion: 2
                )
                let body = ATHLTHLocalization.choose(
                    english: "Let's meet and train! \(workout.title) · \(scheduled). Accept or decline the invitation below.",
                    norwegian: "Vil du trene fysisk sammen? \(workout.title) · \(scheduled). Godta eller avslå invitasjonen nedenfor."
                )
                let sent = await messaging.send(
                    to: partnerID,
                    conversationID: conversationID,
                    body: body,
                    attachment: attachment
                )
                if sent {
                    pendingInvitationWorkout = nil
                    finishDraft()
                    dismiss()
                } else {
                    invitationError = (messaging.errorMessage ??
                        ATHLTHLocalization.choose(
                            english: "Could not send invitation.",
                            norwegian: "Kunne ikke sende invitasjonen."
                        )) + ATHLTHLocalization.choose(
                            english: " Your workout is saved in your calendar. Try Plan again to retry the invitation.",
                            norwegian: " Økten er lagret i kalenderen din. Trykk Planlegg igjen for å prøve invitasjonen på nytt."
                        )
                    showingInvitationError = true
                }
            } catch {
                invitationError = error.localizedDescription +
                    ATHLTHLocalization.choose(
                        english: " The workout is already saved in your calendar.",
                        norwegian: " Økten er allerede lagret i kalenderen din."
                    )
                showingInvitationError = true
            }
            isSaving = false
        }
    }

    private func commitSession(_ workout: PlannedSession) {
        if let onPreparedWorkout {
            onPreparedWorkout(workout)
            finishDraft()
            dismiss()
            return
        }

        persistSession(workout)
        finishDraft()
        dismiss()
    }

    private func persistSession(_ workout: PlannedSession) {
        if isStandalone {
            session.addStandalonePlannedSession(workout)
        } else if existingWorkout != nil, let planID {
            session.updateSession(workout, inPlan: planID)
        } else if let dayID {
            if let planID {
                session.addSession(workout, toDay: dayID, inPlan: planID)
            } else {
                session.addSession(workout, toDay: dayID)
            }
        }
        // AppSessionStore schedules the reminder when saving.
    }

    private var draftStorageKey: String {
        let context: String
        if onPreparedWorkout != nil {
            context = preserveSourceID
                ? "together.proposal.\(initialSourceWorkout?.id.uuidString ?? "new")"
                : "together.marketplace"
        } else if let workout = existingWorkout {
            context = "edit.\(workout.id.uuidString)"
        } else if isStandalone {
            context = directPartnerID.map {
                "standalone.partner.\($0.uuidString)"
            } ?? "standalone"
        } else {
            context = "day.\(planID?.uuidString ?? "active").\(dayID?.uuidString ?? "unknown")"
        }
        return "athlth.sessionEditor.draft.v1.\(session.profile.userID.uuidString).\(context)"
    }

    private func persistDraft() {
        // Do not create an empty draft before the athlete chooses a source.
        guard draftRestored, !draftFinalized,
              hasSelectedWorkoutSource else { return }
        let draft = SessionEditorStoredDraft(
            workout: composeSession(),
            selectedPartnerID: selectedPartnerID,
            physicalMeetup: physicalMeetup,
            scheduledTimeEnabled: scheduledTimeEnabled,
            editorModeRaw: editorMode.rawValue,
            targetPaceEnabled: targetPaceEnabled,
            heartRateTargetEnabled: heartRateTargetEnabled,
            heartRateTargetModeRaw: heartRateTargetMode.rawValue,
            heartRateTargetZone: heartRateTargetZone,
            customHeartRateMinBPM: customHeartRateMinBPM,
            customHeartRateMaxBPM: customHeartRateMaxBPM,
            paceAlertsEnabled: paceAlertsEnabled,
            paceAlertToleranceSeconds: paceAlertToleranceSeconds,
            targetAlertGraceSeconds: targetAlertGraceSeconds,
            targetAlertRepeatSeconds: targetAlertRepeatSeconds,
            targetAlertDelivery: targetAlertDelivery,
            targetAlertAnnounceBackInTarget: targetAlertAnnounceBackInTarget
        )
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: draftStorageKey)
        }
    }

    private func restoreDraftIfNeeded() {
        guard !draftRestored else { return }
        defer { draftRestored = true }
        guard let data = UserDefaults.standard.data(forKey: draftStorageKey),
              let draft = try? JSONDecoder().decode(SessionEditorStoredDraft.self, from: data)
        else { return }

        applySavedWorkout(draft.workout)
        durationMinutes = draft.workout.durationMinutes ?? 0
        meetingPoint = draft.workout.meetingPoint
        reminderMinutesBefore = draft.workout.reminderMinutesBefore ?? 0
        scheduledTimeEnabled = draft.scheduledTimeEnabled
        selectedPartnerID = directPartnerID ?? draft.selectedPartnerID
        // Legacy draft modes are normalized to in-person invitations.
        physicalMeetup = true
        editorMode = SessionEditorMode(rawValue: draft.editorModeRaw) ?? editorMode
        targetPaceEnabled = draft.targetPaceEnabled
        heartRateTargetEnabled = draft.heartRateTargetEnabled
        heartRateTargetMode = HeartRateTargetMode(
            rawValue: draft.heartRateTargetModeRaw
        ) ?? .zone
        heartRateTargetZone = draft.heartRateTargetZone
        customHeartRateMinBPM = draft.customHeartRateMinBPM
        customHeartRateMaxBPM = draft.customHeartRateMaxBPM
        paceAlertsEnabled = draft.paceAlertsEnabled
        paceAlertToleranceSeconds = draft.paceAlertToleranceSeconds
        targetAlertGraceSeconds = draft.targetAlertGraceSeconds
        targetAlertRepeatSeconds = draft.targetAlertRepeatSeconds
        targetAlertDelivery = draft.targetAlertDelivery
        targetAlertAnnounceBackInTarget = draft.targetAlertAnnounceBackInTarget
        didLoadRunGuidanceDefaults = true
    }

    private func finishDraft() {
        draftFinalized = true
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
    }

    private func compactPlannedSetLabel(
        _ target: PlannedExerciseSetTarget,
        exercise: PlannedExercise,
        index: Int
    ) -> String {
        let targetText: String

        switch exercise.resolvedTargetKind {
        case .reps:
            targetText =
                target.reps.map {
                    "\($0)"
                } ?? "—"
        case .time:
            let seconds =
                max(
                    target.durationSeconds ??
                    exercise
                        .resolvedTargetDurationSeconds ??
                    0,
                    0
                )
            if seconds >= 60 {
                targetText =
                    "\(seconds / 60):" +
                    String(
                        format:
                            "%02d",
                        seconds % 60
                    )
            } else {
                targetText =
                    "\(seconds)s"
            }
        }

        let loadText: String
        switch exercise.resolvedLoadKind {
        case .weightKilograms:
            if let weight =
                target.weightKilograms {
                loadText =
                    String(
                        format:
                            "%.0f",
                        weight
                    )
            } else {
                loadText = ""
            }
        case .resistanceLevel:
            if let level =
                target.resistanceLevel {
                loadText =
                    "L\(level)"
            } else {
                loadText = ""
            }
        }

        let warmUp =
            target.isWarmUp == true ||
            target.setType == .warmUp

        if loadText.isEmpty {
            return
                warmUp
                    ? "O\(index) · \(targetText)"
                    : "S\(index) · \(targetText)"
        }

        return
            warmUp
                ? "O\(index) · \(targetText)×\(loadText)"
                : "S\(index) · \(targetText)×\(loadText)"
    }

    private func plannedExerciseSummary(
        _ planned: PlannedExercise
    ) -> String {
        var parts = [
            planned.compactTargetSummary
        ]

        if let load =
                planned.compactLoadSummary {
            parts.append(load)
        }

        if planned.hasIndividualSetTargets {
            parts.append(
                ATHLTHLocalization.choose(
                    english: "Per-set targets",
                    norwegian: "Individuelle sett"
                )
            )
        } else {
            if let rpe = planned.targetRPE {
                parts.append(
                    String(
                        format: "RPE %.1f",
                        rpe
                    )
                )
            }

            if let rir = planned.targetRIR {
                parts.append(
                    String(
                        format: "RIR %.1f",
                        rir
                    )
                )
            }

            if let rest = planned.restSeconds {
                parts.append(
                    ATHLTHLocalization.choose(
                        english: "\(rest)s rest",
                        norwegian: "\(rest)s hvile"
                    )
                )
            }
        }

        if let progression = planned.progression,
           progression.kind != .none {
            parts.append(progression.kind.title)
        }

        return parts.joined(separator: " · ")
    }
}

private struct PlannedAudioCoachEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var configuration:
        WatchAudioCoachConfiguration?

    let defaultConfiguration:
        WatchAudioCoachConfiguration

    @State private var usesCustomSettings: Bool
    @State private var draft:
        WatchAudioCoachConfiguration

    init(
        configuration:
            Binding<WatchAudioCoachConfiguration?>,
        defaultConfiguration:
            WatchAudioCoachConfiguration
    ) {
        _configuration = configuration
        self.defaultConfiguration =
            defaultConfiguration

        let existing =
            configuration.wrappedValue

        _usesCustomSettings = State(
            initialValue: existing != nil
        )
        _draft = State(
            initialValue:
                existing ??
                defaultConfiguration
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Customize for this workout",
                        isOn: $usesCustomSettings
                    )

                    Text(
                        usesCustomSettings
                            ? "These settings apply only to this planned workout."
                            : "ATHLTH will use your Audio Coach defaults from Settings."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if usesCustomSettings {
                    Section("Audio Coach") {
                        Toggle(
                            "Audio Coach",
                            isOn: $draft.enabled
                        )

                        Picker(
                            "Language",
                            selection: $draft.language
                        ) {
                            ForEach(
                                WatchAudioCoachLanguage
                                    .allCases,
                                id: \.self
                            ) { language in
                                Text(language.title)
                                    .tag(language)
                            }
                        }
                    }

                    if draft.enabled {
                        Section("When to speak") {
                            Toggle(
                                "Distance interval",
                                isOn:
                                    distanceTriggerBinding
                            )

                            if draft
                                .distanceIntervalMeters != nil {
                                Stepper(
                                    distanceIntervalLabel,
                                    value:
                                        distanceIntervalBinding,
                                    in: 250...10_000,
                                    step: 250
                                )
                            }

                            Toggle(
                                "Time interval",
                                isOn: timeTriggerBinding
                            )

                            if draft
                                .timeIntervalSeconds != nil {
                                Stepper(
                                    timeIntervalLabel,
                                    value:
                                        timeIntervalBinding,
                                    in: 60...3_600,
                                    step: 60
                                )
                            }
                        }

                        Section("Announcements") {
                            Toggle(
                                "Distance",
                                isOn:
                                    $draft
                                        .announceDistance
                            )
                            Toggle(
                                "Elapsed time",
                                isOn:
                                    $draft
                                        .announceElapsedTime
                            )
                            Toggle(
                                "Average pace",
                                isOn:
                                    $draft
                                        .announceAveragePace
                            )
                            Toggle(
                                "Clock time",
                                isOn:
                                    $draft
                                        .announceClockTime
                            )
                            Toggle(
                                "Heart rate",
                                isOn:
                                    $draft
                                        .announceHeartRate
                            )
                            Toggle(
                                "Remaining route distance",
                                isOn:
                                    $draft
                                        .announceRemainingRouteDistance
                            )
                            Toggle(
                                "Estimated route time left",
                                isOn:
                                    $draft
                                        .announceEstimatedRemainingRouteTime
                            )
                            Toggle(
                                "Current workout step",
                                isOn:
                                    $draft
                                        .announceCurrentWorkoutStep
                            )
                            Toggle(
                                "Remaining step time",
                                isOn:
                                    $draft
                                        .announceRemainingStepTime
                            )
                            Toggle(
                                "Remaining step distance",
                                isOn:
                                    $draft
                                        .announceRemainingStepDistance
                            )
                        }

                        Section("Music & other audio") {
                            Toggle(
                                "Lower music while coach speaks",
                                isOn: Binding(
                                    get: {
                                        draft.shouldDuckOtherAudio
                                    },
                                    set: { enabled in
                                        draft.duckOtherAudio = enabled
                                    }
                                )
                            )

                            Text(
                                draft.shouldDuckOtherAudio
                                    ? "Spotify and other audio are reduced only while the coach is speaking."
                                    : "Coach speech mixes with other audio at its current level."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Audio Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Save") {
                        if usesCustomSettings {
                            var saved = draft
                            saved.routeDistanceMeters = nil
                            configuration = saved
                        } else {
                            configuration = nil
                        }

                        dismiss()
                    }
                }
            }
            .onChange(
                of: usesCustomSettings
            ) { _, enabled in
                if enabled &&
                    configuration == nil {
                    draft = defaultConfiguration
                }
            }
        }
    }

    private var distanceTriggerBinding:
        Binding<Bool> {
        Binding(
            get: {
                draft.distanceIntervalMeters != nil
            },
            set: { enabled in
                draft.distanceIntervalMeters =
                    enabled
                        ? (
                            draft
                                .distanceIntervalMeters ??
                            defaultConfiguration
                                .distanceIntervalMeters ??
                            1_000
                        )
                        : nil
            }
        )
    }

    private var timeTriggerBinding:
        Binding<Bool> {
        Binding(
            get: {
                draft.timeIntervalSeconds != nil
            },
            set: { enabled in
                draft.timeIntervalSeconds =
                    enabled
                        ? (
                            draft
                                .timeIntervalSeconds ??
                            defaultConfiguration
                                .timeIntervalSeconds ??
                            600
                        )
                        : nil
            }
        )
    }

    private var distanceIntervalBinding:
        Binding<Double> {
        Binding(
            get: {
                draft.distanceIntervalMeters ??
                1_000
            },
            set: {
                draft.distanceIntervalMeters = $0
            }
        )
    }

    private var timeIntervalBinding:
        Binding<Double> {
        Binding(
            get: {
                draft.timeIntervalSeconds ??
                600
            },
            set: {
                draft.timeIntervalSeconds = $0
            }
        )
    }

    private var distanceIntervalLabel: String {
        let meters =
            draft.distanceIntervalMeters ??
            1_000

        if meters >= 1_000 {
            return String(
                format:
                    "Every %.2g km",
                meters / 1_000
            )
        }

        return
            "Every \(Int(meters.rounded())) m"
    }

    private var timeIntervalLabel: String {
        let seconds =
            draft.timeIntervalSeconds ??
            600

        return
            "Every \(max(Int((seconds / 60).rounded()), 1)) min"
    }
}

struct PlannedExerciseEditorView: View {
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @Environment(\.dismiss) private var dismiss

    let original: PlannedExercise
    let advancedMode: Bool
    let onSave: (PlannedExercise) -> Void

    @State private var sets: Int
    @State private var targetKind:
        StrengthExerciseTargetKind
    @State private var reps: Int
    @State private var durationSeconds: Int
    @State private var loadKind:
        StrengthExerciseLoadKind
    @State private var weight: Double
    @State private var resistanceLevel: Int
    @State private var useLoadTarget: Bool

    @State private var useRPE: Bool
    @State private var rpe: Double

    @State private var useRIR: Bool
    @State private var rir: Double

    @State private var restSeconds: Int
    @State private var useIndividualSetTargets: Bool
    @State private var individualSetTargets:
        [PlannedExerciseSetTarget]

    @State private var progressionKind:
        StrengthProgressionKind
    @State private var progressionAmount: Double
    @State private var minimumReps: Int
    @State private var maximumReps: Int
    @State private var notes: String
    @State private var usesSpeedTarget: Bool
    @State private var targetSpeedKPH: Double
    @State private var targetHeartRateZone: Int?

    init(
        exercise: PlannedExercise,
        advancedMode: Bool,
        onSave: @escaping (PlannedExercise) -> Void
    ) {
        original = exercise
        self.advancedMode = advancedMode
        self.onSave = onSave

        _sets = State(
            initialValue:
                max(exercise.sets, 1)
        )
        _targetKind = State(
            initialValue:
                exercise.resolvedTargetKind
        )
        _reps = State(
            initialValue:
                exercise.reps ?? 8
        )
        _durationSeconds = State(
            initialValue:
                exercise
                    .resolvedTargetDurationSeconds ??
                exercise
                    .embeddedExercise
                    .defaultStrengthTargetDurationSeconds
        )
        _loadKind = State(
            initialValue:
                exercise.resolvedLoadKind
        )
        _weight = State(
            initialValue:
                exercise.targetWeightKilograms ??
                exercise
                    .resolvedSetTargets
                    .first?
                    .weightKilograms ??
                20
        )
        _resistanceLevel = State(
            initialValue:
                exercise
                    .resolvedTargetResistanceLevel ??
                exercise
                    .resolvedSetTargets
                    .first?
                    .resistanceLevel ??
                5
        )
        _useLoadTarget = State(
            initialValue:
                exercise.targetWeightKilograms != nil ||
                exercise.targetResistanceLevel != nil ||
                exercise.resolvedSetTargets
                    .contains {
                        $0.weightKilograms != nil ||
                        $0.resistanceLevel != nil
                    } ||
                exercise.resolvedLoadKind ==
                    .resistanceLevel
        )

        _useRPE = State(
            initialValue:
                exercise.targetRPE != nil ||
                exercise.resolvedSetTargets
                    .contains {
                        $0.targetRPE != nil
                    }
        )
        _rpe = State(
            initialValue:
                exercise.targetRPE ??
                exercise.resolvedSetTargets
                    .first?
                    .targetRPE ??
                8
        )

        _useRIR = State(
            initialValue:
                exercise.targetRIR != nil ||
                exercise.resolvedSetTargets
                    .contains {
                        $0.targetRIR != nil
                    }
        )
        _rir = State(
            initialValue:
                exercise.targetRIR ??
                exercise.resolvedSetTargets
                    .first?
                    .targetRIR ??
                2
        )

        _restSeconds = State(
            initialValue:
                exercise.restSeconds ??
                exercise.resolvedSetTargets
                    .first?
                    .restSeconds ??
                90
        )

        _useIndividualSetTargets = State(
            initialValue:
                exercise.hasIndividualSetTargets
        )
        _individualSetTargets = State(
            initialValue:
                exercise.resolvedSetTargets
        )

        _progressionKind = State(
            initialValue:
                exercise.progression?.kind ?? .none
        )
        _progressionAmount = State(
            initialValue:
                exercise.progression?.amount ?? 2.5
        )
        _minimumReps = State(
            initialValue:
                exercise.progression?.minimumReps ?? 8
        )
        _maximumReps = State(
            initialValue:
                exercise.progression?.maximumReps ?? 12
        )
        _usesSpeedTarget = State(
            initialValue: exercise.targetSpeedKilometersPerHour != nil
        )
        _targetSpeedKPH = State(
            initialValue: exercise.targetSpeedKilometersPerHour ?? 8.0
        )
        _targetHeartRateZone = State(
            initialValue: exercise.targetHeartRateZone
        )
        _notes = State(
            initialValue:
                exercise.notes ?? ""
        )
    }

    private var catalogEntry: ExerciseLibraryEntry? {
        exerciseLibrary.allExercises.first {
            $0.id == original.exerciseID
        }
    }

    private var exerciseInstructions: [String] {
        if let entry = catalogEntry {
            let localized = exerciseLibrary.localizedExerciseInstructions(entry)
            if !localized.isEmpty { return localized }
        }
        return original.embeddedExercise.instructions ?? []
    }

    private var exerciseVideoURL: URL? {
        original.embeddedExercise.videoURL ?? catalogEntry?.exercise.videoURL
    }

    private var entireWarmUpBinding: Binding<Bool> {
        Binding(
            get: {
                !individualSetTargets.isEmpty &&
                individualSetTargets.allSatisfy {
                    $0.isWarmUp == true || $0.setType == .warmUp
                }
            },
            set: { warmUp in
                let targets = useIndividualSetTargets
                    ? normalizedIndividualTargets()
                    : (0..<max(sets, 1)).map { _ in sharedSetTarget() }

                individualSetTargets = targets.map { target in
                    var updated = target
                    updated.isWarmUp = warmUp
                    updated.setType = warmUp ? .warmUp : .work
                    return updated
                }
                useIndividualSetTargets = true
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        HStack(spacing: 12) {
                            if let entry = catalogEntry {
                                ExerciseArtwork(entry: entry, size: 92)
                            } else {
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(ATHLTHPlanDesign.accent)
                                    .frame(width: 92, height: 92)
                                    .background(
                                        ATHLTHPlanDesign.selectedSurface,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                            }

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(
                                    catalogEntry.map {
                                        exerciseLibrary.localizedExerciseName($0)
                                    } ?? original.embeddedExercise.displayName
                                )
                                 .font(.system(size: 22, weight: .semibold, design: .serif))
                                .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Plan every set exactly how you want it.",
                                        norwegian:
                                            "Planlegg hvert sett akkurat slik du vil."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }

                            Spacer()
                        }

                        Divider()

                        Stepper(
                            ATHLTHLocalization.format(
                                english: "Sets: %d",
                                norwegian: "Sett: %d",
                                sets
                            ),
                            value: $sets,
                            in: 1...20
                        )
                        .onChange(
                            of: sets
                        ) { _, _ in
                            syncSetTargetCount()
                        }

                        ATHLTHPremiumSegmentedControl(
                            titles: [
                                ATHLTHLocalization.choose(
                                    english:
                                        "Same for all",
                                    norwegian:
                                        "Samme for alle"
                                ),
                                ATHLTHLocalization.choose(
                                    english:
                                        "Per set",
                                    norwegian:
                                        "Per sett"
                                )
                            ],
                            selection:
                                setEditingModeIndex
                        )

                        Text(
                            useIndividualSetTargets
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Reps, load, rest and effort can now be different on every set.",
                                    norwegian:
                                        "Reps, belastning, hvile og innsats kan nå være forskjellig på hvert sett."
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "One prescription is used for every set.",
                                    norwegian:
                                        "Samme oppsett brukes på alle settene."
                                )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }
                .listRowBackground(
                    ATHLTHTheme.card
                )

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.premiumGold)
                            .frame(width: 46, height: 46)
                            .background(
                                ATHLTHTheme.premiumGoldSoft,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Warm-up exercise",
                                    norwegian: "Oppvarmingsøvelse"
                                )
                            )
                            .font(.subheadline.weight(.bold))

                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Mark every set as warm-up. These sets won't count toward training load or PRs.",
                                    norwegian: "Marker alle sett som oppvarming. De teller ikke mot treningsbelastning eller PR."
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)
                        Toggle(
                            ATHLTHLocalization.choose(
                                english: "Warm-up exercise",
                                norwegian: "Oppvarmingsøvelse"
                            ),
                            isOn: entireWarmUpBinding
                        )
                        .labelsHidden()
                        .tint(ATHLTHTheme.premiumGold)
                    }
                    .padding(.vertical, 5)
                }
                .listRowBackground(ATHLTHTheme.card)

                if let entry = catalogEntry,
                   let summary = exerciseLibrary.localizedExerciseSummary(entry),
                   !summary.isEmpty {
                    Section(ATHLTHLocalization.choose(
                        english: "About the exercise", norwegian: "Om øvelsen"
                    )) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 5)
                    }
                    .listRowBackground(ATHLTHTheme.card)
                }

                if !original.embeddedExercise.primaryMuscles.isEmpty ||
                   !(original.embeddedExercise.secondaryMuscles ?? []).isEmpty {
                    Section(ATHLTHLocalization.choose(
                        english: "Muscles used", norwegian: "Muskler i bruk"
                    )) {
                        ExerciseMuscleOverview(
                            primaryMuscles: original.embeddedExercise.primaryMuscles,
                            secondaryMuscles: original.embeddedExercise.secondaryMuscles ?? []
                        )
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(ATHLTHTheme.card)
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Target type",
                        norwegian: "Måltype"
                    )
                ) {
                    targetAndLoadTypeControls
                }
                .listRowBackground(
                    ATHLTHTheme.card
                )

                // Cardio/machine exercises can target speed and pulse zone
                // independently of repetitions, weight or time. These are
                // planned goals, not claimed Watch measurements.
                if targetKind == .time {
                    Section(ATHLTHLocalization.choose(
                        english: "Pace & pulse targets",
                        norwegian: "Tempo og pulsmål"
                    )) {
                        Toggle(
                            ATHLTHLocalization.choose(
                                english: "Target speed (km/h)",
                                norwegian: "Målhastighet (km/t)"
                            ),
                            isOn: $usesSpeedTarget
                        )
                        .tint(ATHLTHTheme.premiumGold)

                        if usesSpeedTarget {
                            HStack(spacing: 12) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Speed",
                                    norwegian: "Fart"
                                ))
                                Spacer()
                                Text(String(format: "%.1f km/t", targetSpeedKPH))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                Stepper(
                                    ATHLTHLocalization.choose(
                                        english: "Speed", norwegian: "Fart"
                                    ),
                                    value: $targetSpeedKPH,
                                    in: 0.5...25,
                                    step: 0.5
                                )
                                .labelsHidden()
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "Manual target, not measured speed.",
                                norwegian: "Manuelt mål, ikke målt hastighet."
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }

                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Target heart-rate zone",
                                norwegian: "Målpulssone"
                            ),
                            selection: $targetHeartRateZone
                        ) {
                            Text(ATHLTHLocalization.choose(
                                english: "No target", norwegian: "Ingen mål"
                            )).tag(nil as Int?)
                            ForEach(1...5, id: \.self) { zone in
                                Text("Sone \(zone)").tag(Optional(zone))
                            }
                        }
                        .tint(ATHLTHPlanDesign.accentInk)
                    }
                    .listRowBackground(ATHLTHTheme.card)
                }

                if advancedMode &&
                    targetKind == .reps &&
                    loadKind == .weightKilograms &&
                    useLoadTarget {
                    Section(
                        ATHLTHLocalization.choose(
                            english: "Warm-up",
                            norwegian: "Oppvarming"
                        )
                    ) {
                        HStack(spacing: 11) {
                            Image(
                                systemName:
                                    "flame.fill"
                            )
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(
                                ATHLTHTheme.premiumGold
                            )
                            .frame(width: 36, height: 36)
                            .background(
                                ATHLTHTheme.premiumGoldSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 11,
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
                                            "Warm-up generator",
                                        norwegian:
                                            "Oppvarmingsgenerator"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Build 3 progressive warm-up sets toward your first work set.",
                                        norwegian:
                                            "Lag 3 progressive oppvarmingssett frem mot første arbeidssett."
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }

                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Button {
                                generateWarmUpSets()
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Generate",
                                        norwegian:
                                            "Lag oppvarming"
                                    ),
                                    systemImage:
                                        "wand.and.stars"
                                )
                                .font(.caption.weight(.bold))
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 40
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(
                                ATHLTHTheme.accentDeep,
                                in: RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )

                            if warmUpSetCount > 0 {
                                Button {
                                    removeWarmUpSets()
                                } label: {
                                    Text(
                                        ATHLTHLocalization.choose(
                                            english: "Remove",
                                            norwegian: "Fjern"
                                        )
                                    )
                                    .font(.caption.weight(.bold))
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 40
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 12,
                                        style: .continuous
                                    )
                                )
                            }
                        }
                    }
                    .listRowBackground(
                        ATHLTHTheme.card
                    )
                }

                if useIndividualSetTargets {
                    Section(
                        ATHLTHLocalization.choose(
                            english: "Sets",
                            norwegian: "Sett"
                        )
                    ) {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Individual prescriptions",
                                    norwegian:
                                        "Individuelle verdier"
                                )
                            )
                            .font(.subheadline.weight(.semibold))

                            Spacer()

                            Button {
                                copyFirstSetToAll()
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Copy set 1",
                                        norwegian:
                                            "Kopier sett 1"
                                    ),
                                    systemImage:
                                        "doc.on.doc"
                                )
                                .font(
                                    .caption.weight(.semibold)
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                        }

                        ForEach(
                            individualSetTargets.indices,
                            id: \.self
                        ) { index in
                            plannedSetTargetCard(
                                index: index
                            )
                        }
                    }
                    .listRowBackground(
                        ATHLTHTheme.card
                    )
                } else {
                    Section(
                        ATHLTHLocalization.choose(
                            english: "Prescription",
                            norwegian: "Oppsett"
                        )
                    ) {
                        targetRow

                        Toggle(
                            loadKind == .resistanceLevel
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Resistance target",
                                    norwegian:
                                        "Motstandsmål"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Target weight",
                                    norwegian:
                                        "Målvekt"
                                ),
                            isOn: $useLoadTarget
                        )

                        if useLoadTarget {
                            loadTargetRow
                        }

                        Stepper(
                            ATHLTHLocalization.format(
                                english:
                                    "Rest: %d sec",
                                norwegian:
                                    "Hvile: %d sek",
                                restSeconds
                            ),
                            value: $restSeconds,
                            in: 0...600,
                            step: 15
                        )
                    }
                    .listRowBackground(
                        ATHLTHTheme.card
                    )
                }

                if advancedMode {
                    Section(
                        ATHLTHLocalization.choose(
                            english: "Effort",
                            norwegian: "Anstrengelse"
                        )
                    ) {
                        Toggle(
                            ATHLTHLocalization.choose(
                                english: "Use RPE",
                                norwegian: "Bruk RPE"
                            ),
                            isOn: $useRPE
                        )

                        if useRPE &&
                            !useIndividualSetTargets {
                            HStack {
                                Slider(
                                    value: $rpe,
                                    in: 1...10,
                                    step: 0.5
                                )
                                Text(
                                    "\(rpe, specifier: "%.1f")"
                                )
                                .monospacedDigit()
                            }
                        }

                        Toggle(
                            ATHLTHLocalization.choose(
                                english: "Use RIR",
                                norwegian: "Bruk RIR"
                            ),
                            isOn: $useRIR
                        )

                        if useRIR &&
                            !useIndividualSetTargets {
                            HStack {
                                Slider(
                                    value: $rir,
                                    in: 0...5,
                                    step: 0.5
                                )
                                Text(
                                    "\(rir, specifier: "%.1f")"
                                )
                                .monospacedDigit()
                            }
                        }

                        if useIndividualSetTargets &&
                            (useRPE || useRIR) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Effort is adjusted inside each set above.",
                                    norwegian:
                                        "Innsats justeres på hvert enkelt sett over."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                        }
                    }
                    .listRowBackground(
                        ATHLTHTheme.card
                    )
                }

                if advancedMode &&
                    targetKind == .reps &&
                    loadKind == .weightKilograms {
                    Section(
                        ATHLTHLocalization.choose(
                            english: "Progression",
                            norwegian: "Progresjon"
                        )
                    ) {
                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Rule",
                                norwegian: "Regel"
                            ),
                            selection: $progressionKind
                        ) {
                            ForEach(
                                StrengthProgressionKind
                                    .allCases
                            ) { kind in
                                Text(kind.title)
                                    .tag(kind)
                            }
                        }

                        if progressionKind != .none {
                            HStack {
                                Text(
                                    progressionKind == .addReps
                                        ? ATHLTHLocalization.choose(
                                            english:
                                                "Reps to add",
                                            norwegian:
                                                "Reps å legge til"
                                        )
                                        : progressionKind == .percentage
                                            ? ATHLTHLocalization.choose(
                                                english:
                                                    "Percent",
                                                norwegian:
                                                    "Prosent"
                                            )
                                            : ATHLTHLocalization.choose(
                                                english:
                                                    "Weight to add",
                                                norwegian:
                                                    "Vekt å legge til"
                                            )
                                )

                                Spacer()

                                TextField(
                                    "Amount",
                                    value: $progressionAmount,
                                    format:
                                        .number
                                        .precision(
                                            .fractionLength(
                                                0...2
                                            )
                                        )
                                )
                                .keyboardType(
                                    .decimalPad
                                )
                                .multilineTextAlignment(
                                    .trailing
                                )
                                .frame(width: 90)

                                Text(
                                    progressionKind ==
                                        .percentage
                                        ? "%"
                                        : progressionKind ==
                                            .addReps
                                            ? "reps"
                                            : "kg"
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                            }

                            if progressionKind ==
                                .doubleProgression {
                                Stepper(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Rep range start: \(minimumReps)",
                                        norwegian:
                                            "Reps fra: \(minimumReps)"
                                    ),
                                    value: $minimumReps,
                                    in: 1...50
                                )

                                Stepper(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Rep range end: \(maximumReps)",
                                        norwegian:
                                            "Reps til: \(maximumReps)"
                                    ),
                                    value: $maximumReps,
                                    in:
                                        minimumReps...100
                                )
                            }

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Progression stays separate from completed workout history and can be adjusted later.",
                                    norwegian:
                                        "Progresjonsregelen holdes separat fra økthistorikken og kan endres senere."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }
                    .listRowBackground(
                        ATHLTHTheme.card
                    )
                }

                if !exerciseInstructions.isEmpty || exerciseVideoURL != nil {
                    Section(
                        ATHLTHLocalization.choose(
                            english: "Technique",
                            norwegian: "Teknikk"
                        )
                    ) {
                        if !exerciseInstructions.isEmpty {
                            VStack(
                                alignment: .leading,
                                spacing: 9
                            ) {
                                ForEach(
                                    Array(
                                        exerciseInstructions.prefix(4)
                                            .enumerated()
                                    ),
                                    id: \.offset
                                ) { index, instruction in
                                    HStack(
                                        alignment: .top,
                                        spacing: 9
                                    ) {
                                        Text("\(index + 1)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(
                                                ATHLTHTheme.accentDeep
                                            )
                                            .frame(
                                                width: 22,
                                                height: 22
                                            )
                                            .background(
                                                ATHLTHTheme.accentSoft,
                                                in: Circle()
                                            )

                                        Text(instruction)
                                            .font(.caption)
                                            .foregroundStyle(
                                                ATHLTHTheme.primaryText
                                                    .opacity(0.82)
                                            )
                                    }
                                }
                            }
                        }

                        if let videoURL =
                                exerciseVideoURL {
                            Link(
                                destination: videoURL
                            ) {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Open technique video",
                                        norwegian:
                                            "Åpne teknikkvideo"
                                    ),
                                    systemImage:
                                        "play.rectangle.fill"
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                            }
                        }
                    }
                    .listRowBackground(
                        ATHLTHTheme.card
                    )
                }

                Section(
                    ATHLTHLocalization.choose(
                        english: "Notes",
                        norwegian: "Notater"
                    )
                ) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Technique or progression notes",
                            norwegian:
                                "Teknikk- eller progresjonsnotater"
                        ),
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                }
                .listRowBackground(
                    ATHLTHTheme.card
                )
            }
            .scrollContentBackground(.hidden)
            .background(
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.premiumGold.opacity(0.13)
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Exercise",
                    norwegian: "Øvelse"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Save",
                            norwegian: "Lagre"
                        )
                    ) {
                        saveExercise()
                    }
                }
            }
        }
    }

    private var setEditingModeIndex:
        Binding<Int> {
        Binding(
            get: {
                useIndividualSetTargets
                    ? 1
                    : 0
            },
            set: { newValue in
                let individual =
                    newValue == 1

                if individual &&
                    !useIndividualSetTargets {
                    seedIndividualTargetsFromShared()
                }

                useIndividualSetTargets =
                    individual
            }
        )
    }

    private var targetAndLoadTypeControls:
        some View {
        VStack(spacing: 12) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "What counts as the target?",
                            norwegian:
                                "Hva skal måles?"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(
                        targetKind.title
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                Menu {
                    Button {
                        targetKind = .reps
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Reps",
                                norwegian: "Reps"
                            ),
                            systemImage:
                                targetKind == .reps
                                    ? "checkmark"
                                    : "repeat"
                        )
                    }

                    Button {
                        targetKind = .time
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Time",
                                norwegian: "Tid"
                            ),
                            systemImage:
                                targetKind == .time
                                    ? "checkmark"
                                    : "timer"
                        )
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(targetKind.title)
                        Image(
                            systemName:
                                "chevron.down"
                        )
                        .font(.caption2.bold())
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(
                        .horizontal,
                        10
                    )
                    .frame(height: 34)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Capsule()
                    )
                }
            }

            Divider()

            if useIndividualSetTargets {
                Toggle(
                    loadKind == .resistanceLevel
                        ? ATHLTHLocalization.choose(
                            english:
                                "Plan resistance per set",
                            norwegian:
                                "Planlegg motstand per sett"
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "Plan weight per set",
                            norwegian:
                                "Planlegg vekt per sett"
                        ),
                    isOn: $useLoadTarget
                )

                Divider()
            }

            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Load",
                            norwegian: "Belastning"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(
                        loadKind.title
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                Menu {
                    Button {
                        loadKind =
                            .weightKilograms
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Weight",
                                norwegian: "Vekt"
                            ),
                            systemImage:
                                loadKind ==
                                    .weightKilograms
                                    ? "checkmark"
                                    : "scalemass"
                        )
                    }

                    Button {
                        loadKind =
                            .resistanceLevel
                        useLoadTarget = true
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Resistance",
                                norwegian:
                                    "Motstand"
                            ),
                            systemImage:
                                loadKind ==
                                    .resistanceLevel
                                    ? "checkmark"
                                    : "dial.medium"
                        )
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(loadKind.title)
                        Image(
                            systemName:
                                "chevron.down"
                        )
                        .font(.caption2.bold())
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .padding(
                        .horizontal,
                        10
                    )
                    .frame(height: 34)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Capsule()
                    )
                }
            }
        }
    }

    private func plannedSetTargetCard(
        index: Int
    ) -> some View {
        let binding =
            Binding<PlannedExerciseSetTarget>(
                get: {
                    individualSetTargets[index]
                },
                set: {
                    individualSetTargets[index] =
                        $0
                }
            )

        return VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "SET \(index + 1)",
                        norwegian:
                            "SETT \(index + 1)"
                    )
                )
                .font(.system(size: 9, weight: .bold))
                .tracking(1.25)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Spacer()

                if advancedMode {
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Warm-up",
                            norwegian: "Oppvarming"
                        ),
                        isOn:
                            Binding(
                                get: {
                                    binding.wrappedValue
                                        .isWarmUp ??
                                    false
                                },
                                set: { value in
                                    var target =
                                        binding.wrappedValue
                                    target.isWarmUp =
                                        value

                                    if value {
                                        target.setType =
                                            .warmUp
                                    } else if target.setType ==
                                        .warmUp {
                                        target.setType =
                                            .work
                                    }

                                    binding.wrappedValue =
                                        target
                                }
                            )
                    )
                    .font(.caption2)
                    .labelsHidden()
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english:
                                "Warm-up set",
                            norwegian:
                                "Oppvarmingssett"
                        )
                    )
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(
                        .flexible(),
                        spacing: 8
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 8
                    )
                ],
                spacing: 8
            ) {
                if targetKind == .reps {
                    setMetricStepper(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Reps",
                                norwegian: "Reps"
                            ),
                        value:
                            Binding(
                                get: {
                                    binding
                                        .wrappedValue
                                        .reps ??
                                    reps
                                },
                                set: { value in
                                    var target =
                                        binding
                                            .wrappedValue
                                    target.reps =
                                        value
                                    binding
                                        .wrappedValue =
                                        target
                                }
                            ),
                        range: 1...100,
                        step: 1,
                        suffix: ""
                    )
                } else {
                    setMetricStepper(
                        title:
                            ATHLTHLocalization.choose(
                                english: "Time",
                                norwegian: "Tid"
                            ),
                        value:
                            Binding(
                                get: {
                                    binding
                                        .wrappedValue
                                        .durationSeconds ??
                                    durationSeconds
                                },
                                set: { value in
                                    var target =
                                        binding
                                            .wrappedValue
                                    target.durationSeconds =
                                        value
                                    binding
                                        .wrappedValue =
                                        target
                                }
                            ),
                        range: 15...7_200,
                        step: 15,
                        suffix: "s"
                    )
                }

                if useLoadTarget {
                    if loadKind ==
                        .weightKilograms {
                        setWeightField(
                            target: binding
                        )
                    } else {
                        setMetricStepper(
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Resistance",
                                    norwegian:
                                        "Motstand"
                                ),
                            value:
                                Binding(
                                    get: {
                                        binding
                                            .wrappedValue
                                            .resistanceLevel ??
                                        resistanceLevel
                                    },
                                    set: { value in
                                        var target =
                                            binding
                                                .wrappedValue
                                        target
                                            .resistanceLevel =
                                            value
                                        binding
                                            .wrappedValue =
                                            target
                                    }
                                ),
                            range: 1...10,
                            step: 1,
                            suffix: ""
                        )
                    }
                }

                setMetricStepper(
                    title:
                        ATHLTHLocalization.choose(
                            english: "Rest",
                            norwegian: "Hvile"
                        ),
                    value:
                        Binding(
                            get: {
                                binding
                                    .wrappedValue
                                    .restSeconds ??
                                restSeconds
                            },
                            set: { value in
                                var target =
                                    binding
                                        .wrappedValue
                                target.restSeconds =
                                    value
                                binding
                                    .wrappedValue =
                                    target
                            }
                        ),
                    range: 0...600,
                    step: 15,
                    suffix: "s"
                )

                if useRPE {
                    setEffortStepper(
                        title: "RPE",
                        value:
                            Binding(
                                get: {
                                    binding
                                        .wrappedValue
                                        .targetRPE ??
                                    rpe
                                },
                                set: { value in
                                    var target =
                                        binding
                                            .wrappedValue
                                    target.targetRPE =
                                        value
                                    binding
                                        .wrappedValue =
                                        target
                                }
                            ),
                        range: 1...10
                    )
                }

                if useRIR {
                    setEffortStepper(
                        title: "RIR",
                        value:
                            Binding(
                                get: {
                                    binding
                                        .wrappedValue
                                        .targetRIR ??
                                    rir
                                },
                                set: { value in
                                    var target =
                                        binding
                                            .wrappedValue
                                    target.targetRIR =
                                        value
                                    binding
                                        .wrappedValue =
                                        target
                                }
                            ),
                        range: 0...5
                    )
                }
            }

            if advancedMode {
                advancedSetDetails(
                    target: binding
                )
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.82),
                    ATHLTHTheme.cardWarm
                        .opacity(0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.90),
                lineWidth: 0.8
            )
        }
    }

    private func advancedSetDetails(
        target:
            Binding<PlannedExerciseSetTarget>
    ) -> some View {
        DisclosureGroup {
            VStack(
                alignment: .leading,
                spacing: 11
            ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Set type",
                                norwegian: "Settype"
                            )
                        )
                        .font(.caption.weight(.semibold))

                        Text(
                            (
                                target
                                    .wrappedValue
                                    .setType ??
                                (
                                    target
                                        .wrappedValue
                                        .isWarmUp == true
                                        ? PlannedStrengthSetType
                                            .warmUp
                                        : .work
                                )
                            )
                            .title
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }

                    Spacer()

                    Menu {
                        ForEach(
                            PlannedStrengthSetType
                                .allCases
                        ) { type in
                            Button {
                                var updated =
                                    target
                                        .wrappedValue
                                updated.setType =
                                    type
                                updated.isWarmUp =
                                    type == .warmUp
                                target.wrappedValue =
                                    updated
                            } label: {
                                Label(
                                    type.title,
                                    systemImage:
                                        type.systemImage
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(
                                (
                                    target
                                        .wrappedValue
                                        .setType ??
                                    (
                                        target
                                            .wrappedValue
                                            .isWarmUp ==
                                            true
                                            ? PlannedStrengthSetType
                                                .warmUp
                                            : .work
                                    )
                                )
                                .title
                            )

                            Image(
                                systemName:
                                    "chevron.down"
                            )
                            .font(.caption2.bold())
                        }
                        .font(
                            .caption.weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .padding(
                            .horizontal,
                            10
                        )
                        .frame(height: 34)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: Capsule()
                        )
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "Tempo",
                                norwegian: "Tempo"
                            )
                        )
                        .font(.caption.weight(.semibold))

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Eccentric · pause · concentric · top",
                                norwegian:
                                    "Ned · pause · opp · topp"
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }

                    Spacer()

                    TextField(
                        "3-1-1-0",
                        text:
                            Binding(
                                get: {
                                    target
                                        .wrappedValue
                                        .tempo ??
                                    ""
                                },
                                set: { value in
                                    var updated =
                                        target
                                            .wrappedValue
                                    let trimmed =
                                        value
                                            .trimmingCharacters(
                                                in:
                                                    .whitespacesAndNewlines
                                            )
                                    updated.tempo =
                                        trimmed.isEmpty
                                            ? nil
                                            : trimmed
                                    target
                                        .wrappedValue =
                                        updated
                                }
                            )
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(
                        .trailing
                    )
                    .font(
                        .subheadline
                        .monospacedDigit()
                        .weight(.semibold)
                    )
                    .frame(width: 88)
                    .padding(
                        .horizontal,
                        9
                    )
                    .frame(height: 34)
                    .background(
                        Color.black.opacity(0.025),
                        in: RoundedRectangle(
                            cornerRadius: 9,
                            style: .continuous
                        )
                    )
                }

                Divider()

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Set note",
                            norwegian: "Notat for settet"
                        )
                    )
                    .font(.caption.weight(.semibold))

                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Optional cue for this set",
                            norwegian:
                                "Valgfri beskjed for akkurat dette settet"
                        ),
                        text:
                            Binding(
                                get: {
                                    target
                                        .wrappedValue
                                        .notes ??
                                    ""
                                },
                                set: { value in
                                    var updated =
                                        target
                                            .wrappedValue
                                    let trimmed =
                                        value
                                            .trimmingCharacters(
                                                in:
                                                    .whitespacesAndNewlines
                                            )
                                    updated.notes =
                                        trimmed.isEmpty
                                            ? nil
                                            : trimmed
                                    target
                                        .wrappedValue =
                                        updated
                                }
                            ),
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        Color.black.opacity(0.025),
                        in: RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                }
            }
            .padding(.top, 9)
        } label: {
            HStack(spacing: 8) {
                Image(
                    systemName:
                        "slider.horizontal.3"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.premiumGold
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Advanced set details",
                        norwegian:
                            "Avanserte settdetaljer"
                    )
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Spacer()
            }
        }
        .padding(.top, 2)
    }

    private func setMetricStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        suffix: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.75)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            Stepper(
                value: value,
                in: range,
                step: step
            ) {
                Text(
                    "\(value.wrappedValue)\(suffix)"
                )
                .font(
                    .subheadline
                    .monospacedDigit()
                    .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
            }
        }
        .padding(9)
        .background(
            ATHLTHTheme.accentSoft
                .opacity(0.44),
            in: RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
    }

    private func setEffortStepper(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.75)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            Stepper(
                value: value,
                in: range,
                step: 0.5
            ) {
                Text(
                    value.wrappedValue,
                    format:
                        .number
                        .precision(
                            .fractionLength(1)
                        )
                )
                .font(
                    .subheadline
                    .monospacedDigit()
                    .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
            }
        }
        .padding(9)
        .background(
            ATHLTHTheme.premiumGoldSoft
                .opacity(0.46),
            in: RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
    }

    private func setWeightField(
        target:
            Binding<PlannedExerciseSetTarget>
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text(
                ATHLTHLocalization.choose(
                    english: "WEIGHT",
                    norwegian: "VEKT"
                )
            )
            .font(.system(size: 8, weight: .bold))
            .tracking(0.75)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )

            HStack(spacing: 4) {
                TextField(
                    "0",
                    value:
                        Binding(
                            get: {
                                target
                                    .wrappedValue
                                    .weightKilograms ??
                                weight
                            },
                            set: { value in
                                var updated =
                                    target
                                        .wrappedValue
                                updated
                                    .weightKilograms =
                                    max(value, 0)
                                target
                                    .wrappedValue =
                                    updated
                            }
                        ),
                    format:
                        .number
                        .precision(
                            .fractionLength(
                                0...2
                            )
                        )
                )
                .keyboardType(.decimalPad)
                .font(
                    .subheadline
                    .monospacedDigit()
                    .weight(.bold)
                )

                Text("kg")
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
        }
        .padding(9)
        .background(
            ATHLTHTheme.accentSoft
                .opacity(0.44),
            in: RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
    }

    private var loadTargetRow:
        some View {
        Group {
            if loadKind ==
                .resistanceLevel {
                Stepper(
                    value: $resistanceLevel,
                    in: 1...10
                ) {
                    loadMenu(
                        value:
                            ATHLTHLocalization.choose(
                                english:
                                    "Level \(resistanceLevel)",
                                norwegian:
                                    "Steg \(resistanceLevel)"
                            )
                    )
                }
            } else {
                HStack(spacing: 12) {
                    loadMenu(
                        value:
                            String(
                                format:
                                    "%.1f kg",
                                weight
                            )
                    )

                    Spacer()

                    TextField(
                        "kg",
                        value: $weight,
                        format:
                            .number
                            .precision(
                                .fractionLength(
                                    0...2
                                )
                            )
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(
                        .trailing
                    )
                    .frame(width: 84)

                    Text("kg")
                        .foregroundStyle(
                            .secondary
                        )
                }
            }
        }
    }

    private func loadMenu(
        value: String
    ) -> some View {
        Menu {
            Button {
                loadKind =
                    .weightKilograms
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Weight",
                        norwegian: "Vekt"
                    ),
                    systemImage:
                        loadKind ==
                            .weightKilograms
                            ? "checkmark"
                            : "scalemass"
                )
            }

            Button {
                loadKind =
                    .resistanceLevel
                useLoadTarget = true
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Resistance",
                        norwegian:
                            "Motstand"
                    ),
                    systemImage:
                        loadKind ==
                            .resistanceLevel
                            ? "checkmark"
                            : "dial.medium"
                )
            }
        } label: {
            HStack(spacing: 5) {
                Text(
                    "\(loadKind.title): \(value)"
                )
                .foregroundStyle(.primary)

                Image(
                    systemName:
                        "chevron.down"
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }
        }
    }

    private var targetRow:
        some View {
        Group {
            if targetKind == .reps {
                Stepper(
                    value: $reps,
                    in: 1...100
                ) {
                    targetMenu(
                        value: "\(reps)"
                    )
                }
            } else {
                Stepper(
                    value: $durationSeconds,
                    in: 15...7_200,
                    step: 15
                ) {
                    targetMenu(
                        value:
                            formattedDuration(
                                durationSeconds
                            )
                    )
                }
            }
        }
    }

    private func targetMenu(
        value: String
    ) -> some View {
        Menu {
            Button {
                targetKind = .reps
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Target reps",
                        norwegian:
                            "Målreps"
                    ),
                    systemImage:
                        targetKind == .reps
                            ? "checkmark"
                            : "repeat"
                )
            }

            Button {
                targetKind = .time
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Duration",
                        norwegian:
                            "Varighet"
                    ),
                    systemImage:
                        targetKind == .time
                            ? "checkmark"
                            : "timer"
                )
            }
        } label: {
            HStack(spacing: 5) {
                Text(
                    "\(targetKind.title): \(value)"
                )
                .foregroundStyle(.primary)

                Image(
                    systemName:
                        "chevron.down"
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }
        }
    }

    private var warmUpSetCount: Int {
        individualSetTargets
            .filter {
                $0.isWarmUp == true ||
                $0.setType == .warmUp
            }
            .count
    }

    private func generateWarmUpSets() {
        let currentTargets =
            useIndividualSetTargets
                ? normalizedIndividualTargets()
                : Array(
                    repeating:
                        sharedSetTarget(),
                    count:
                        max(sets, 1)
                )

        let workTargets =
            currentTargets.filter {
                $0.isWarmUp != true &&
                $0.setType != .warmUp
            }
        let firstWork =
            workTargets.first ??
            sharedSetTarget()
        let targetWeight =
            max(
                firstWork.weightKilograms ??
                weight,
                0
            )

        guard targetWeight > 0 else {
            return
        }

        let percentages: [Double] = [
            0.40,
            0.60,
            0.80
        ]
        let warmUpReps = [
            8,
            5,
            3
        ]
        let warmUpRest = [
            45,
            60,
            90
        ]

        let warmUps =
            percentages.enumerated().map {
                index,
                percentage in

                let rawWeight =
                    targetWeight *
                    percentage
                let roundedWeight =
                    max(
                        (
                            rawWeight / 2.5
                        )
                        .rounded() *
                        2.5,
                        0
                    )

                return PlannedExerciseSetTarget(
                    reps:
                        warmUpReps[index],
                    durationSeconds: nil,
                    weightKilograms:
                        roundedWeight,
                    resistanceLevel: nil,
                    restSeconds:
                        warmUpRest[index],
                    targetRPE: nil,
                    targetRIR: nil,
                    isWarmUp: true,
                    setType: .warmUp,
                    tempo:
                        firstWork.tempo,
                    notes:
                        ATHLTHLocalization.choose(
                            english:
                                "Progressive warm-up",
                            norwegian:
                                "Progressiv oppvarming"
                        )
                )
            }

        individualSetTargets =
            warmUps +
            workTargets.map {
                target in
                var updated = target
                if updated.setType == nil {
                    updated.setType = .work
                }
                updated.isWarmUp = false
                return updated
            }
        sets =
            individualSetTargets.count
        useIndividualSetTargets = true
    }

    private func removeWarmUpSets() {
        let workTargets =
            individualSetTargets.filter {
                $0.isWarmUp != true &&
                $0.setType != .warmUp
            }

        guard !workTargets.isEmpty else {
            seedIndividualTargetsFromShared()
            sets =
                individualSetTargets.count
            useIndividualSetTargets = true
            return
        }

        individualSetTargets =
            workTargets
        sets =
            workTargets.count
        useIndividualSetTargets = true
    }

    private func syncSetTargetCount() {
        let safeCount =
            max(sets, 1)

        if individualSetTargets.count >
            safeCount {
            individualSetTargets =
                Array(
                    individualSetTargets
                        .prefix(safeCount)
                )
            return
        }

        let entireWarmUp = !individualSetTargets.isEmpty &&
            individualSetTargets.allSatisfy {
                $0.isWarmUp == true || $0.setType == .warmUp
            }

        while individualSetTargets.count <
            safeCount {
            let source =
                individualSetTargets.last ??
                sharedSetTarget()

            individualSetTargets.append(
                PlannedExerciseSetTarget(
                    reps:
                        source.reps,
                    durationSeconds:
                        source.durationSeconds,
                    weightKilograms:
                        source.weightKilograms,
                    resistanceLevel:
                        source.resistanceLevel,
                    restSeconds:
                        source.restSeconds,
                    targetRPE:
                        source.targetRPE,
                    targetRIR:
                        source.targetRIR,
                    isWarmUp: entireWarmUp,
                    setType: entireWarmUp
                        ? .warmUp
                        : (source.setType == .warmUp ? .work : source.setType),
                    tempo:
                        source.tempo,
                    notes:
                        source.notes
                )
            )
        }
    }

    private func seedIndividualTargetsFromShared() {
        individualSetTargets =
            (0..<max(sets, 1))
                .map { _ in
                    let source =
                        sharedSetTarget()

                    return PlannedExerciseSetTarget(
                        reps: source.reps,
                        durationSeconds:
                            source.durationSeconds,
                        weightKilograms:
                            source.weightKilograms,
                        resistanceLevel:
                            source.resistanceLevel,
                        restSeconds:
                            source.restSeconds,
                        targetRPE:
                            source.targetRPE,
                        targetRIR:
                            source.targetRIR
                    )
                }
    }

    private func sharedSetTarget()
        -> PlannedExerciseSetTarget {
        PlannedExerciseSetTarget(
            reps:
                targetKind == .reps
                    ? reps
                    : nil,
            durationSeconds:
                targetKind == .time
                    ? durationSeconds
                    : nil,
            weightKilograms:
                useLoadTarget &&
                loadKind == .weightKilograms
                    ? weight
                    : nil,
            resistanceLevel:
                useLoadTarget &&
                loadKind == .resistanceLevel
                    ? resistanceLevel
                    : nil,
            restSeconds:
                restSeconds,
            targetRPE:
                useRPE
                    ? rpe
                    : nil,
            targetRIR:
                useRIR
                    ? rir
                    : nil
        )
    }

    private func copyFirstSetToAll() {
        syncSetTargetCount()

        guard
            let first =
                individualSetTargets.first
        else {
            return
        }

        individualSetTargets =
            individualSetTargets.map {
                existing in
                PlannedExerciseSetTarget(
                    id: existing.id,
                    reps: first.reps,
                    durationSeconds:
                        first.durationSeconds,
                    weightKilograms:
                        first.weightKilograms,
                    resistanceLevel:
                        first.resistanceLevel,
                    restSeconds:
                        first.restSeconds,
                    targetRPE:
                        first.targetRPE,
                    targetRIR:
                        first.targetRIR,
                    isWarmUp:
                        existing.isWarmUp,
                    setType:
                        existing.setType,
                    tempo:
                        first.tempo,
                    notes:
                        first.notes
                )
            }
    }

    private func normalizedIndividualTargets()
        -> [PlannedExerciseSetTarget] {
        var targets =
            individualSetTargets

        let safeCount =
            max(sets, 1)

        if targets.count >
            safeCount {
            targets =
                Array(
                    targets
                        .prefix(safeCount)
                )
        }

        while targets.count <
            safeCount {
            targets.append(
                sharedSetTarget()
            )
        }

        return targets.map { target in
            PlannedExerciseSetTarget(
                id: target.id,
                reps:
                    targetKind == .reps
                        ? max(
                            target.reps ??
                                reps,
                            1
                        )
                        : nil,
                durationSeconds:
                    targetKind == .time
                        ? max(
                            target
                                .durationSeconds ??
                                durationSeconds,
                            15
                        )
                        : nil,
                weightKilograms:
                    useLoadTarget &&
                    loadKind ==
                        .weightKilograms
                        ? max(
                            target
                                .weightKilograms ??
                                weight,
                            0
                        )
                        : nil,
                resistanceLevel:
                    useLoadTarget &&
                    loadKind ==
                        .resistanceLevel
                        ? min(
                            max(
                                target
                                    .resistanceLevel ??
                                    resistanceLevel,
                                1
                            ),
                            10
                        )
                        : nil,
                restSeconds:
                    max(
                        target.restSeconds ??
                            restSeconds,
                        0
                    ),
                targetRPE:
                    useRPE
                        ? min(
                            max(
                                target.targetRPE ??
                                    rpe,
                                1
                            ),
                            10
                        )
                        : nil,
                targetRIR:
                    useRIR
                        ? min(
                            max(
                                target.targetRIR ??
                                    rir,
                                0
                            ),
                            5
                        )
                        : nil,
                isWarmUp:
                    target.isWarmUp,
                setType:
                    advancedMode
                        ? (
                            target.setType ??
                            (
                                target.isWarmUp ==
                                    true
                                    ? .warmUp
                                    : .work
                            )
                        )
                        : target.setType,
                tempo:
                    advancedMode
                        ? target.tempo
                        : target.tempo,
                notes:
                    advancedMode
                        ? target.notes
                        : target.notes
            )
        }
    }

    private func saveExercise() {
        var updated =
            original
        let individualTargets =
            useIndividualSetTargets
                ? normalizedIndividualTargets()
                : []

        updated.sets =
            max(sets, 1)
        updated.targetKind =
            targetKind
        updated.loadKind =
            loadKind

        if useIndividualSetTargets,
           let first =
                individualTargets.first {
            updated.setTargets =
                individualTargets
            updated.reps =
                targetKind == .reps
                    ? first.reps
                    : nil
            updated.targetDurationSeconds =
                targetKind == .time
                    ? first.durationSeconds
                    : nil
            updated.targetWeightKilograms =
                useLoadTarget &&
                loadKind ==
                    .weightKilograms
                    ? first.weightKilograms
                    : nil
            updated.targetResistanceLevel =
                useLoadTarget &&
                loadKind ==
                    .resistanceLevel
                    ? first.resistanceLevel
                    : nil
            updated.targetRPE =
                useRPE
                    ? first.targetRPE
                    : nil
            updated.targetRIR =
                useRIR
                    ? first.targetRIR
                    : nil
            updated.restSeconds =
                first.restSeconds
        } else {
            updated.setTargets = nil
            updated.reps =
                targetKind == .reps
                    ? reps
                    : nil
            updated.targetDurationSeconds =
                targetKind == .time
                    ? durationSeconds
                    : nil
            updated.targetWeightKilograms =
                useLoadTarget &&
                loadKind ==
                    .weightKilograms
                    ? weight
                    : nil
            updated.targetResistanceLevel =
                useLoadTarget &&
                loadKind ==
                    .resistanceLevel
                    ? resistanceLevel
                    : nil
            updated.targetRPE =
                useRPE
                    ? rpe
                    : nil
            updated.targetRIR =
                useRIR
                    ? rir
                    : nil
            updated.restSeconds =
                restSeconds
        }

        updated.targetSpeedKilometersPerHour =
            targetKind == .time && usesSpeedTarget
                ? targetSpeedKPH : nil
        updated.targetHeartRateZone =
            targetKind == .time ? targetHeartRateZone : nil

        updated.notes =
            notes
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .nilIfEmpty

        updated.progression =
            targetKind == .reps &&
            loadKind ==
                .weightKilograms
                ? StrengthProgressionRule(
                    kind:
                        progressionKind,
                    amount:
                        max(
                            progressionAmount,
                            0
                        ),
                    minimumReps:
                        progressionKind ==
                            .doubleProgression
                            ? minimumReps
                            : nil,
                    maximumReps:
                        progressionKind ==
                            .doubleProgression
                            ? maximumReps
                            : nil,
                    applyWhenAllSetsCompleted:
                        true
                )
                : StrengthProgressionRule
                    .none

        onSave(updated)
        dismiss()
    }

    private func formattedDuration(
        _ seconds: Int
    ) -> String {
        let safe =
            max(seconds, 0)
        let hours =
            safe / 3_600
        let minutes =
            (safe % 3_600) / 60
        let seconds =
            safe % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format:
                "%02d:%02d",
            minutes,
            seconds
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

    
// Read-only timeline; the existing SessionEditorView remains the single editor.
// Restrained ivory/stone/gold palette avoids category-based pastel cards.
private struct ATHLTHReleasePlanTimeline: View {
    let workout: PlannedSession
    private let bronze = Color(red: 0.49, green: 0.36, blue: 0.19)
    private let paper = Color(red: 0.975, green: 0.967, blue: 0.949)
    private let line = Color(red: 0.77, green: 0.72, blue: 0.64)

    var body: some View {
        let blocks = workout.resolvedWorkoutBlocks.sorted { $0.sequence < $1.sequence }
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 3) {
                            Image(systemName: block.kind == .rest ? "pause.fill" : block.kind.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(bronze)
                                .frame(width: 28, height: 28)
                                .background(Color(red: 0.94, green: 0.92, blue: 0.88), in: Circle())
                            if index < blocks.count - 1 {
                                Rectangle().fill(line).frame(width: 1, height: 16)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(block.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                            let description = [
                                block.kind == .rest
                                    ? block.durationSeconds.map { "\(Int($0.rounded())) sek pause" }
                                    : block.targetText,
                                block.notes
                            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            if !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(block.kind == .rest
                        ? Color(red: 0.952, green: 0.931, blue: 0.894)
                        : Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
                    .padding(.bottom, 5)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paper, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
