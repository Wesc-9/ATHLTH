import SwiftUI

/// Full-width, landscape-first plan building on iPad.
/// Week navigation, seven real dates and the workout editor stay in view
/// together. The shared AppSessionStore remains the single source of truth.
struct ATHLTHStudioPlanCanvasView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    @State private var selectedPlanID: UUID?
    @State private var selectedWeekID: UUID?
    @State private var selectedDayID: UUID?
    @State private var creatingPlan = false
    @State private var newPlanName = ""
    @State private var newPlanSummary = ""
    @State private var newPlanStart = Date.now
    @State private var newPlanWeeks = 4
    @State private var showingAdvancedBuilder = false
    @State private var showingPlanMetadata = false
    @State private var showingWorkoutFlow = false
    @State private var workoutNavigation: ATHLTHTrainNavigationRequest? = .plan
    @State private var dropMode: DropMode = .move
    @State private var warning: String?

    private enum DropMode: String, CaseIterable, Identifiable {
        case move, copy
        var id: String { rawValue }
    }

    private var plans: [TrainingPlan] { session.trainingPlans }
    private var selectedPlan: TrainingPlan? {
        if let selectedPlanID, let selected = session.trainingPlan(withID: selectedPlanID) {
            return selected
        }
        return session.activePlan ?? session.nextTrainingPlan ?? plans.first
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if creatingPlan || selectedPlan == nil {
                    newPlanWorkspace(width: geometry.size.width)
                } else if let plan = selectedPlan, !plan.weeks.isEmpty {
                    planWorkspace(
                        plan,
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                } else {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No usable training weeks",
                            norwegian: "Ingen tilgjengelige treningsuker"
                        ),
                        systemImage: "calendar.badge.exclamationmark"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
        .onAppear {
            if selectedPlanID == nil {
                selectedPlanID = selectedPlan?.id
            }
            newPlanStart = session.suggestedTrainingPlanStartDate
        }
        .onChange(of: selectedPlanID) { _, _ in
            selectedWeekID = nil
            selectedDayID = nil
        }
        .onChange(of: session.profile.userID) { _, _ in
            selectedPlanID = nil
            selectedWeekID = nil
            selectedDayID = nil
            creatingPlan = false
        }
        .sheet(isPresented: $showingPlanMetadata) {
            if let plan = selectedPlan {
                ATHLTHStudioPlanMetadataView(plan: plan)
            }
        }
        .sheet(isPresented: $showingAdvancedBuilder) {
            ATHLTHTrainingPlanBuilderFlow(
                startsAtSourceChoice: true,
                initialAdvanced: true,
                resumesDraftOnAppear: false,
                draftID: nil,
                onCreated: { planID in
                    selectedPlanID = planID
                    selectedWeekID = nil
                    selectedDayID = nil
                    creatingPlan = false
                    showingAdvancedBuilder = false
                }
            )
        }
        .sheet(isPresented: $showingWorkoutFlow) {
            ATHLTHTrainView(
                navigationRequest: $workoutNavigation,
                isActive: true
            )
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not update training plan",
                norwegian: "Kunne ikke oppdatere treningsplanen"
            ),
            isPresented: Binding(
                get: { warning != nil },
                set: { if !$0 { warning = nil } }
            )
        ) {
            Button("OK", role: .cancel) { warning = nil }
        } message: {
            Text(warning ?? "")
        }
    }

    @ViewBuilder
    private func planWorkspace(
        _ plan: TrainingPlan,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let weekIndex = currentWeekIndex(in: plan)
        let week = plan.weeks[weekIndex]

        if !week.days.isEmpty {
        let day = currentDay(in: week, weekIndex: weekIndex, plan: plan)
        let dayDate = ATHLTHStudioPlanWeekSummary.date(
            for: day, inWeekIndex: weekIndex, planStart: plan.startDate
        )

        VStack(alignment: .leading, spacing: 14) {
            planHeader(plan)
            planMetrics(plan, selectedWeek: week)

            if width >= 875 {
                HStack(alignment: .top, spacing: 13) {
                    weekNavigation(plan, selectedIndex: weekIndex)
                        .frame(width: min(198, width * 0.21))

                    weekCanvas(plan, week: week, weekIndex: weekIndex)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ATHLTHStudioPlanDayEditorView(
                        plan: plan,
                        day: day,
                        date: dayDate,
                        onOpenAdvanced: { workoutID in
                            openFullWorkout(planID: plan.id, workoutID: workoutID)
                        }
                    )
                    .id(day.id)
                    .frame(width: min(344, max(286, width * 0.31)))
                    .frame(maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    VStack(spacing: 13) {
                        compactWeekNavigation(plan, selectedIndex: weekIndex)
                        weekCanvas(plan, week: week, weekIndex: weekIndex)
                            .frame(height: max(400, min(610, height * 0.7)))
                        ATHLTHStudioPlanDayEditorView(
                            plan: plan,
                            day: day,
                            date: dayDate,
                            onOpenAdvanced: { workoutID in
                                openFullWorkout(planID: plan.id, workoutID: workoutID)
                            }
                        )
                        .id(day.id)
                        .frame(minHeight: 450)
                    }
                }
            }
        }
        .padding(.horizontal, width >= 875 ? 17 : 12)
        .padding(.vertical, 13)
        } else {
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english: "This week contains no days",
                    norwegian: "Denne uken mangler dager"
                ),
                systemImage: "calendar.badge.exclamationmark"
            )
        }
    }

    private func planHeader(_ plan: TrainingPlan) -> some View {
        HStack(alignment: .center, spacing: 15) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ATHLTHLocalization.choose(
                    english: "TRAINING PROGRAM", norwegian: "TRENINGSPROGRAM"
                ))
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(ATHLTHStudioStyle.gold)

                HStack(spacing: 8) {
                    Text(plan.title)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                        .lineLimit(1)
                    if session.activePlan?.id == plan.id {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Active plan", norwegian: "Aktiv plan"
                            ))
                    }
                }
                if !plan.summary.isEmpty {
                    Text(plan.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let start = plan.startDate {
                    Text(
                        start.formatted(date: .abbreviated, time: .omitted) +
                        " – " +
                        (session.trainingPlanEndDate(plan) ?? start)
                            .formatted(date: .abbreviated, time: .omitted)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 10)
            if plans.count > 1 {
                Picker(ATHLTHLocalization.choose(
                    english: "Choose plan", norwegian: "Velg plan"
                ), selection: $selectedPlanID) {
                    ForEach(plans) { candidate in
                        Text(candidate.title).tag(Optional(candidate.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            Button {
                showingPlanMetadata = true
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Details", norwegian: "Detaljer"
                ), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            Button {
                newPlanStart = session.suggestedTrainingPlanStartDate
                newPlanName = ""
                newPlanSummary = ""
                newPlanWeeks = 4
                creatingPlan = true
            } label: {
                Label(
                    ATHLTHLocalization.choose(
                        english: "New plan", norwegian: "Ny plan"
                    ),
                    systemImage: "plus"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHStudioStyle.ink)
        }
    }

    private func planMetrics(
        _ plan: TrainingPlan,
        selectedWeek week: TrainingPlanWeek
    ) -> some View {
        let snapshot = ATHLTHStudioPlanWeekSummary.calculate(week)
        let progress = session.trainingPlanProgress(
            plan,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        return HStack(spacing: 11) {
            ATHLTHStudioMetricCard(
                title: ATHLTHLocalization.choose(
                    english: "Current week", norwegian: "Valgt uke"
                ),
                value: "\(week.weekNumber) / \(plan.weeks.count)",
                note: ATHLTHLocalization.choose(
                    english: "Week in program", norwegian: "Uke i programmet"
                )
            )
            ATHLTHStudioMetricCard(
                title: ATHLTHLocalization.choose(
                    english: "Planned sessions", norwegian: "Planlagte økter"
                ),
                value: "\(snapshot.workouts)",
                note: "\(snapshot.running) " +
                    ATHLTHLocalization.choose(english: "runs", norwegian: "løp") +
                    " · \(snapshot.strength) " +
                    ATHLTHLocalization.choose(english: "strength", norwegian: "styrke")
            )
            ATHLTHStudioMetricCard(
                title: ATHLTHLocalization.choose(
                    english: "Planned duration", norwegian: "Planlagt varighet"
                ),
                value: "\(snapshot.knownMinutes) min",
                note: snapshot.missingDurationCount == 0
                    ? ATHLTHLocalization.choose(
                        english: "Duration entered", norwegian: "Varighet oppgitt"
                      )
                    : ATHLTHLocalization.choose(
                        english: "+ sessions without duration", norwegian: "+ økter uten varighet"
                      )
            )
            ATHLTHStudioMetricCard(
                title: ATHLTHLocalization.choose(
                    english: "Completed in plan", norwegian: "Fullført i planen"
                ),
                value: "\(progress.completedSessions) / \(progress.totalSessions)",
                note: ATHLTHLocalization.choose(
                    english: "Based on recorded/matched workouts",
                    norwegian: "Basert på registrerte/koblede økter"
                )
            )
        }
    }

    private func weekNavigation(
        _ plan: TrainingPlan,
        selectedIndex: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "PLAN WEEKS", norwegian: "PLANUKER"
                ))
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                Spacer()
                Text("\(plan.weeks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { index, week in
                        weekNavigationButton(
                            plan: plan, week: week, index: index,
                            isSelected: selectedIndex == index
                        )
                    }
                }
                .padding(.vertical, 3)
            }
            Divider()
            Text(ATHLTHLocalization.choose(
                english: "SAVED WORKOUTS", norwegian: "LAGREDE ØKTER"
            ))
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(ATHLTHStudioStyle.gold)

            if session.savedWorkoutTemplates.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Your library is empty.",
                    norwegian: "Biblioteket ditt er tomt."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(session.savedWorkoutTemplates.prefix(12)) { item in
                            Label(item.title, systemImage: item.kind.systemImage)
                                .font(.caption)
                                .lineLimit(2)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    ATHLTHStudioStyle.canvas,
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                                .draggable("library:\(item.id.uuidString)")
                                .accessibilityHint(ATHLTHLocalization.choose(
                                    english: "Drag to a future day",
                                    norwegian: "Dra til en fremtidig dag"
                                ))
                        }
                    }
                }
                .frame(maxHeight: 185)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.5))
        }
    }

    private func compactWeekNavigation(
        _ plan: TrainingPlan,
        selectedIndex: Int
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { index, week in
                    weekNavigationButton(
                        plan: plan, week: week, index: index,
                        isSelected: selectedIndex == index
                    )
                    .frame(width: 125)
                }
            }
            .padding(3)
        }
        .scrollIndicators(.hidden)
    }

    private func weekNavigationButton(
        plan: TrainingPlan,
        week: TrainingPlanWeek,
        index: Int,
        isSelected: Bool
    ) -> some View {
        let totals = ATHLTHStudioPlanWeekSummary.calculate(week)
        return Button {
            selectedWeekID = week.id
            selectedDayID = nil
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Week \(week.weekNumber)",
                        norwegian: "Uke \(week.weekNumber)"
                    ))
                    .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                    }
                }
                Text("\(totals.workouts) " +
                    ATHLTHLocalization.choose(english: "workouts", norwegian: "økter") +
                    " · \(totals.knownMinutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let firstDay = week.days.first,
                   let date = ATHLTHStudioPlanWeekSummary.date(
                    for: firstDay, inWeekIndex: index,
                    planStart: plan.startDate
                   ) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                isSelected ? ATHLTHStudioStyle.canvas : .white,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(ATHLTHStudioStyle.gold.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func weekCanvas(
        _ plan: TrainingPlan,
        week: TrainingPlanWeek,
        weekIndex: Int
    ) -> some View {
        let snapshot = ATHLTHStudioPlanWeekSummary.calculate(week)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "Week \(week.weekNumber)",
                        norwegian: "Uke \(week.weekNumber)"
                    ))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    Text("\(snapshot.workouts) " +
                        ATHLTHLocalization.choose(english: "workouts", norwegian: "økter") +
                        " · \(snapshot.restDays) " +
                        ATHLTHLocalization.choose(english: "rest days", norwegian: "hviledager"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Picker(ATHLTHLocalization.choose(
                    english: "Drag action", norwegian: "Drahandling"
                ), selection: $dropMode) {
                    Text(ATHLTHLocalization.choose(
                        english: "Move", norwegian: "Flytt"
                    )).tag(DropMode.move)
                    Text(ATHLTHLocalization.choose(
                        english: "Copy", norwegian: "Kopier"
                    )).tag(DropMode.copy)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 145)
            }

            if let block = plan.trainingBlocks?.first(where: {
                $0.contains(week: week.weekNumber)
            }) {
                Label(block.title, systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHStudioStyle.gold)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                        dayRow(
                            day,
                            plan: plan,
                            week: week,
                            weekIndex: weekIndex
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            Text(ATHLTHLocalization.choose(
                english: "Select a day to build it on the right. Drag workouts to another future day.",
                norwegian: "Velg en dag for å bygge den til høyre. Dra økter til en annen fremtidig dag."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.5))
        }
    }

    private func dayRow(
        _ day: TrainingPlanDay,
        plan: TrainingPlan,
        week: TrainingPlanWeek,
        weekIndex: Int
    ) -> some View {
        let selected = currentDay(in: week, weekIndex: weekIndex, plan: plan).id == day.id
        let date = ATHLTHStudioPlanWeekSummary.date(
            for: day, inWeekIndex: weekIndex, planStart: plan.startDate
        )
        return HStack(alignment: .top, spacing: 11) {
            Button {
                selectedWeekID = week.id
                selectedDayID = day.id
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(date?.formatted(.dateTime.weekday(.abbreviated)) ?? "—")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    Text(date?.formatted(.dateTime.day()) ?? "\(day.dayIndex)")
                        .font(.system(size: 25, weight: .medium, design: .rounded))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                    if let date {
                        Text(date.formatted(.dateTime.month(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 59, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                if day.sessions.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "Available — add a workout",
                        norwegian: "Ledig – legg til en økt"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
                    .onTapGesture {
                        selectedWeekID = week.id
                        selectedDayID = day.id
                    }
                } else {
                    ForEach(day.sessions) { workout in
                        HStack(spacing: 8) {
                            Image(systemName: workout.isExplicitRestDay
                                  ? "moon.zzz" : workout.kind.systemImage)
                                .foregroundStyle(ATHLTHStudioStyle.gold)
                                .frame(width: 18)
                            Text(workout.title)
                                .lineLimit(2)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ATHLTHStudioStyle.ink)
                            Spacer(minLength: 0)
                            if let duration = workout.durationMinutes,
                               !workout.isExplicitRestDay {
                                Text("\(duration)m")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(9)
                        .background(.white, in: RoundedRectangle(cornerRadius: 9))
                        .draggable(workout.id.uuidString)
                        .onTapGesture {
                            selectedWeekID = week.id
                            selectedDayID = day.id
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            selected ? ATHLTHStudioStyle.canvas : Color.white,
            in: RoundedRectangle(cornerRadius: 13)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(
                    selected ? ATHLTHStudioStyle.gold.opacity(0.65)
                             : ATHLTHStudioStyle.outline.opacity(0.35)
                )
        }
        .dropDestination(for: String.self) { values, _ in
            handleDrop(values, into: day, plan: plan, weekIndex: weekIndex)
        }
    }

    private func handleDrop(
        _ values: [String],
        into target: TrainingPlanDay,
        plan: TrainingPlan,
        weekIndex: Int
    ) -> Bool {
        guard let raw = values.first,
              !target.sessions.contains(where: \.isExplicitRestDay),
              let date = ATHLTHStudioPlanWeekSummary.date(
                  for: target, inWeekIndex: weekIndex, planStart: plan.startDate
              ),
              Calendar.current.startOfDay(for: date) >=
                  Calendar.current.startOfDay(for: .now),
              session.trainingPlan(withID: plan.id)?.version == plan.version
        else { return false }

        let success: Bool
        if raw.hasPrefix("library:"),
           let libraryID = UUID(uuidString: String(raw.dropFirst("library:".count))) {
            success = session.insertSavedWorkoutIntoPlan(
                templateID: libraryID,
                planID: plan.id,
                dayID: target.id
            )
        } else if let workoutID = UUID(uuidString: raw) {
            if dropMode == .copy {
                success = session.copyPlanStudioWorkout(
                    planID: plan.id,
                    sourceWorkoutID: workoutID,
                    targetDayID: target.id,
                    expectedVersion: plan.version
                )
            } else {
                success = session.movePlanStudioWorkout(
                    planID: plan.id,
                    workoutID: workoutID,
                    targetDate: date,
                    expectedVersion: plan.version,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                )
            }
        } else {
            return false
        }
        if success {
            selectedDayID = target.id
        } else {
            warning = ATHLTHLocalization.choose(
                english: "This workout cannot be moved or copied. Check the date, completion status and latest plan version.",
                norwegian: "Økten kan ikke flyttes eller kopieres. Kontroller dato, fullføringsstatus og siste planversjon."
            )
        }
        return success
    }

    @ViewBuilder
    private func newPlanWorkspace(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "BUILD A TRAINING PLAN", norwegian: "BYGG EN TRENINGSPLAN"
                        ))
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(ATHLTHLocalization.choose(
                            english: "Your entire program, one workspace.",
                            norwegian: "Hele treningsprogrammet på én arbeidsflate."
                        ))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                    }
                    Spacer()
                    if !plans.isEmpty {
                        Button {
                            creatingPlan = false
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Back to plans", norwegian: "Tilbake til planer"
                            ), systemImage: "arrow.left")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if width >= 810 {
                    HStack(alignment: .top, spacing: 22) {
                        createPlanForm
                            .frame(maxWidth: .infinity)
                        creationPreview
                            .frame(width: min(355, width * 0.36))
                    }
                } else {
                    VStack(spacing: 18) {
                        createPlanForm
                        creationPreview
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 1250)
            .frame(maxWidth: .infinity)
        }
    }

    private var createPlanForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(ATHLTHLocalization.choose(
                english: "Plan details", norwegian: "Plandetaljer"
            ), systemImage: "square.and.pencil")
            .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(ATHLTHLocalization.choose(
                    english: "Name your plan", norwegian: "Navn på planen"
                ))
                .font(.caption.weight(.semibold))
                TextField(ATHLTHLocalization.choose(
                    english: "e.g. Four weeks of running",
                    norwegian: "F.eks. Fire uker med løping"
                ), text: $newPlanName)
                .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(ATHLTHLocalization.choose(
                    english: "What is this plan for?", norwegian: "Hva er målet med planen?"
                ))
                .font(.caption.weight(.semibold))
                TextEditor(text: $newPlanSummary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 95)
                    .padding(8)
                    .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            }

            DatePicker(
                ATHLTHLocalization.choose(
                    english: "Start date", norwegian: "Startdato"
                ),
                selection: $newPlanStart,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)

            Stepper(
                value: $newPlanWeeks, in: 1...52, step: 1
            ) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Duration", norwegian: "Varighet"
                    ))
                    Spacer()
                    Text("\(newPlanWeeks) " + ATHLTHLocalization.choose(
                        english: "weeks", norwegian: "uker"
                    ))
                    .fontWeight(.semibold)
                }
            }

            Text(ATHLTHLocalization.choose(
                english: "The plan starts empty. No workouts or training days are invented. You can then populate each date and use your existing exercise library.",
                norwegian: "Planen starter helt tom. Ingen økter eller treningsdager blir lagt inn automatisk. Deretter kan du fylle ut hver dato og bruke ditt eksisterende øvelsesbibliotek."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                createBlankPlan()
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Create empty plan", norwegian: "Opprett tom plan"
                ), systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHStudioStyle.ink)

            Button {
                showingAdvancedBuilder = true
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Use advanced / AI plan builder",
                    norwegian: "Bruk avansert / AI-planlegger"
                ), systemImage: "sparkles")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(23)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var creationPreview: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(ATHLTHLocalization.choose(
                english: "PROGRAM STRUCTURE", norwegian: "PROGRAMSTRUKTUR"
            ))
            .font(.caption.weight(.semibold))
            .tracking(1.5)
            .foregroundStyle(ATHLTHStudioStyle.gold)

            Text("\(newPlanWeeks) " + ATHLTHLocalization.choose(
                english: "weeks", norwegian: "uker"
            ))
            .font(.system(size: 29, weight: .semibold, design: .rounded))
            Text("\(newPlanWeeks * 7) " + ATHLTHLocalization.choose(
                english: "individual dates", norwegian: "egne datoer"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Divider()

            ForEach(0..<min(newPlanWeeks, 4), id: \.self) { weekIndex in
                VStack(alignment: .leading, spacing: 8) {
                    Text(ATHLTHLocalization.choose(
                        english: "Week \(weekIndex + 1)",
                        norwegian: "Uke \(weekIndex + 1)"
                    ))
                    .font(.subheadline.weight(.semibold))

                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            VStack(spacing: 3) {
                                if let date = Calendar.current.date(
                                    byAdding: .day,
                                    value: weekIndex * 7 + dayIndex,
                                    to: Calendar.current.startOfDay(for: newPlanStart)
                                ) {
                                    Text(date.formatted(.dateTime.weekday(.narrow)))
                                    Text(date.formatted(.dateTime.day()))
                                        .fontWeight(.semibold)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(ATHLTHStudioStyle.ink)
                            .frame(maxWidth: .infinity, minHeight: 45)
                            .background(
                                ATHLTHStudioStyle.canvas,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                }
            }

            if newPlanWeeks > 4 {
                Text("+ \(newPlanWeeks - 4) " + ATHLTHLocalization.choose(
                    english: "more weeks", norwegian: "uker til"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(ATHLTHLocalization.choose(
                english: "Add sessions, rest days, notes and structured workouts as you go. Changes are saved to your ATHLTH training plan.",
                norwegian: "Fyll på med økter, hviledager, notater og detaljerte treningsøkter. Endringene lagres i ATHLTH-planen din."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func createBlankPlan() {
        let name = newPlanName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else {
            warning = ATHLTHLocalization.choose(
                english: "Enter a plan name of up to 120 characters.",
                norwegian: "Skriv inn et plannavn på høyst 120 tegn."
            )
            return
        }
        let start = Calendar.current.startOfDay(for: newPlanStart)
        guard let plan = session.createTrainingPlan(
            title: name,
            summary: newPlanSummary,
            weekCount: newPlanWeeks,
            startDate: start,
            visibility: .privateOnly
        ) else {
            let end = Calendar.current.date(
                byAdding: .day,
                value: newPlanWeeks * 7 - 1,
                to: start
            ) ?? start
            let conflict = session.trainingPlanConflict(startDate: start, endDate: end)
            warning = conflict.map {
                ATHLTHLocalization.choose(
                    english: "These dates overlap the saved plan '\($0.title)'. Choose a different start date; nothing was replaced.",
                    norwegian: "Datoene overlapper planen '\($0.title)'. Velg en annen startdato. Ingenting ble overskrevet."
                )
            } ?? ATHLTHLocalization.choose(
                english: "The plan could not be created. Your details are still here.",
                norwegian: "Planen kunne ikke opprettes. Opplysningene dine er beholdt."
            )
            return
        }
        selectedPlanID = plan.id
        selectedWeekID = plan.weeks.first?.id
        selectedDayID = nil
        creatingPlan = false
    }

    private func openFullWorkout(planID: UUID, workoutID: UUID) {
        workoutNavigation = .workout(planID: planID, workoutID: workoutID)
        showingWorkoutFlow = true
    }

    private func currentWeekIndex(in plan: TrainingPlan) -> Int {
        if let selectedWeekID,
           let found = plan.weeks.firstIndex(where: { $0.id == selectedWeekID }) {
            return found
        }
        guard let start = plan.startDate else { return 0 }
        let calendar = Calendar.current
        let offset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: .now)
        ).day ?? 0
        return min(max(0, offset / 7), max(0, plan.weeks.count - 1))
    }

    private func currentDay(
        in week: TrainingPlanWeek,
        weekIndex: Int,
        plan: TrainingPlan
    ) -> TrainingPlanDay {
        if let selectedDayID,
           let selected = week.days.first(where: { $0.id == selectedDayID }) {
            return selected
        }
        if let start = plan.startDate {
            let offset = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: start),
                to: Calendar.current.startOfDay(for: .now)
            ).day ?? -1
            if offset >= 0, offset / 7 == weekIndex,
               let current = week.days.first(where: { $0.dayIndex == offset % 7 + 1 }) {
                return current
            }
        }
        return week.days.min(by: { $0.dayIndex < $1.dayIndex }) ?? week.days[0]
    }
}
