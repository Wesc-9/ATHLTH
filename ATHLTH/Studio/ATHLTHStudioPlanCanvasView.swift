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
    @SceneStorage("athlth.studio.plan.viewMode") private var viewMode = "overview"
    @State private var copyingWeekID: UUID?
    @State private var pendingWeekCopyTarget: UUID?
    @State private var lastWeekCopy: AppSessionStore.PlanStudioWeekCopyReceipt?
    @State private var copyMessage: String?
    @State private var creatingPlan = false
    @State private var newPlanName = ""
    @State private var newPlanSummary = ""
    @State private var newPlanStart = Date.now
    @State private var newPlanWeeks = 4
    @State private var showingAdvancedBuilder = false
    @State private var showingPlanMetadata = false
    /// The existing plan's workout edits in the right-hand Studio column.
    /// This references the same AppSessionStore session as the iPhone builder.
    @State private var inlineWorkout: InlineWorkoutDestination?
    @State private var inlineNewWorkout: NewWorkoutDestination?
    @State private var newWorkoutTime = Date.now

    private struct NewWorkoutDestination: Identifiable {
        let planID: UUID
        let dayID: UUID
        let expectedVersion: Int
        let date: Date
        var id: String { "\(planID.uuidString)-\(dayID.uuidString)" }
    }

    private struct InlineWorkoutDestination: Identifiable {
        let planID: UUID
        let dayID: UUID
        let expectedPlanVersion: Int
        let workout: PlannedSession
        var id: UUID { workout.id }
    }
    @State private var dropMode: DropMode = .move
    @State private var warning: String?

    private enum DropMode: String, CaseIterable, Identifiable {
        case move, copy
        var id: String { rawValue }
    }

    private enum StudioPlanMode: String, CaseIterable, Identifiable {
        case overview, week, progress
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: return ATHLTHLocalization.choose(
                english: "Whole plan", norwegian: "Hele planen"
            )
            case .week: return ATHLTHLocalization.choose(
                english: "Planning", norwegian: "Planlegging"
            )
            case .progress: return ATHLTHLocalization.choose(
                english: "Progress", norwegian: "Fremdrift"
            )
            }
        }
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
            inlineWorkout = nil
            inlineNewWorkout = nil
            copyingWeekID = nil
            pendingWeekCopyTarget = nil
            lastWeekCopy = nil
            copyMessage = nil
        }
        .onChange(of: selectedWeekID) { _, _ in
            inlineWorkout = nil
            inlineNewWorkout = nil
        }
        .onChange(of: selectedDayID) { _, _ in
            inlineWorkout = nil
            inlineNewWorkout = nil
        }
        .onChange(of: session.profile.userID) { _, _ in
            selectedPlanID = nil
            selectedWeekID = nil
            selectedDayID = nil
            inlineWorkout = nil
            inlineNewWorkout = nil
            copyingWeekID = nil
            pendingWeekCopyTarget = nil
            lastWeekCopy = nil
            copyMessage = nil
            creatingPlan = false
        }
        .sheet(isPresented: $showingPlanMetadata) {
            if let plan = selectedPlan {
                ATHLTHStudioPlanMetadataView(plan: plan)
            }
        }
        .fullScreenCover(isPresented: $showingAdvancedBuilder) {
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
            .environment(\.athlthStudioFullscreenEditing, true)
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Copy entire training week?",
                norwegian: "Kopiere hele treningsuken?"
            ),
            isPresented: Binding(
                get: { pendingWeekCopyTarget != nil },
                set: { if !$0 { pendingWeekCopyTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Copy week", norwegian: "Kopier uke"
            )) {
                copySelectedWeek()
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) {
                pendingWeekCopyTarget = nil
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "All seven days are copied in one step. The destination must be empty and in the future. Your original week is unchanged.",
                norwegian: "Alle syv dager kopieres samlet. Måluken må være tom og ligge i fremtiden. Den opprinnelige uken endres ikke."
            ))
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
            planControlBar(plan)
            if let copyingWeekID {
                weekCopyControls(
                    plan, sourceWeekID: copyingWeekID
                )
            }
            if let copyMessage {
                HStack(spacing: 10) {
                    Label(copyMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                    Spacer(minLength: 0)
                    if let receipt = lastWeekCopy,
                       plan.id == receipt.planID,
                       plan.version == receipt.expectedVersionAfterCopy {
                        Button(ATHLTHLocalization.choose(
                            english: "Undo week copy", norwegian: "Angre ukekopiering"
                        )) {
                            undoWeekCopy()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 7)
            }
            if inlineWorkout == nil && inlineNewWorkout == nil &&
               viewMode == StudioPlanMode.week.rawValue {
                planMetrics(plan, selectedWeek: week)
            }

            if inlineWorkout == nil && inlineNewWorkout == nil,
               viewMode == StudioPlanMode.overview.rawValue ||
               (inlineWorkout == nil && inlineNewWorkout == nil &&
                viewMode == StudioPlanMode.progress.rawValue) {
                ATHLTHStudioPlanOverviewView(
                    plan: plan,
                    display: viewMode == StudioPlanMode.progress.rawValue
                        ? .progress : .overview,
                    selectedWeekID: selectedWeekID,
                    onSelect: { weekID, dayID in
                        selectedWeekID = weekID
                        selectedDayID = dayID
                        viewMode = StudioPlanMode.week.rawValue
                    },
                    onCopyWeek: { weekID in
                        copyingWeekID = weekID
                        copyMessage = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let inlineWorkout, inlineWorkout.planID == plan.id {
                // The existing-plan editor uses exactly the same adjustable
                // workspace as new-plan construction. The week stays visible
                // in the left column and the shared editor remains on the right.
                ATHLTHStudioAdaptiveWorkspace {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(ATHLTHLocalization.choose(
                            english: "YOUR TRAINING WEEK",
                            norwegian: "DIN TRENINGSUKE"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHStudioStyle.gold)

                        Text(plan.title)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundStyle(ATHLTHStudioStyle.ink)

                        compactWeekNavigation(plan, selectedIndex: weekIndex)
                            .allowsHitTesting(false)

                        weekCanvas(plan, week: week, weekIndex: weekIndex)
                            .allowsHitTesting(false)
                            .frame(maxHeight: .infinity)

                        Text(ATHLTHLocalization.choose(
                            english: "Save or close the workout before selecting another day.",
                            norwegian: "Lagre eller lukk økten før du velger en annen dag."
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ATHLTHStudioStyle.canvas)
                } editor: {
                    inlineExistingWorkoutEditor(inlineWorkout)
                } focusRail: {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(ATHLTHLocalization.choose(
                            english: "Week", norwegian: "Uke"
                        ))
                        .font(.caption2)
                        Text("\(week.weekNumber)")
                            .font(.title3.weight(.bold))
                        Divider()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                    }
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    .padding(.top, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .top)
                    .background(ATHLTHStudioStyle.canvas)
                }
                .frame(maxHeight: .infinity)
            } else if let fresh = inlineNewWorkout, fresh.planID == plan.id {
                ATHLTHStudioAdaptiveWorkspace {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(ATHLTHLocalization.choose(
                            english: "YOUR TRAINING WEEK", norwegian: "DIN TRENINGSUKE"
                        ))
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(plan.title)
                            .font(.headline)
                            .foregroundStyle(ATHLTHStudioStyle.ink)
                            .lineLimit(2)
                        compactWeekNavigation(plan, selectedIndex: weekIndex)
                            .allowsHitTesting(false)
                        weekCanvas(plan, week: week, weekIndex: weekIndex)
                            .allowsHitTesting(false)
                            .frame(maxHeight: .infinity)
                        Text(ATHLTHLocalization.choose(
                            english: "Save or close your draft before changing day.",
                            norwegian: "Lagre eller lukk utkastet før du bytter dag."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ATHLTHStudioStyle.canvas)
                } editor: {
                    WorkoutTemplateBuilderView(
                        draftContext: "ipad-plan-day-\(fresh.id)",
                        plannedDate: newWorkoutTime,
                        initialStudioAdvanced: true,
                        onScheduledTimeChanged: { newWorkoutTime = $0 },
                        onAddStandalone: { workout in
                            saveInlineNewWorkout(workout, destination: fresh)
                        },
                        saveButtonTitle: ATHLTHLocalization.choose(
                            english: "Save to training plan", norwegian: "Lagre i treningsplan"
                        ),
                        onCloseInline: { inlineNewWorkout = nil }
                    )
                    .environment(\.athlthStudioFullscreenEditing, true)
                    .id(fresh.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } focusRail: {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(ATHLTHLocalization.choose(
                            english: "New workout", norwegian: "Ny økt"
                        ))
                        .font(.caption)
                    }
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    .padding(.top, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(ATHLTHStudioStyle.canvas)
                }
                .frame(maxHeight: .infinity)
            } else if width >= 875 {
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
                        },
                        onCreateAdvanced: {
                            openNewWorkout(plan: plan, day: day, date: dayDate)
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
                        },
                        onCreateAdvanced: {
                            openNewWorkout(plan: plan, day: day, date: dayDate)
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

    private func planControlBar(_ plan: TrainingPlan) -> some View {
        HStack(spacing: 12) {
            Picker(
                ATHLTHLocalization.choose(
                    english: "Plan view", norwegian: "Planvisning"
                ),
                selection: $viewMode
            ) {
                ForEach(StudioPlanMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 390)
            .disabled(inlineWorkout != nil)

            Spacer(minLength: 2)

            if viewMode == StudioPlanMode.week.rawValue,
               inlineWorkout == nil {
                Button {
                    copyingWeekID = plan.weeks[currentWeekIndex(in: plan)].id
                    copyMessage = nil
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Copy week", norwegian: "Kopier uke"
                        ),
                        systemImage: "square.on.square"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            Label(
                inlineWorkout == nil
                    ? ATHLTHLocalization.choose(
                        english: "Plan saved on this device",
                        norwegian: "Planen lagret på enheten"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Workout draft — not saved to plan yet",
                        norwegian: "Øktutkast – ikke lagret i planen ennå"
                    ),
                systemImage: inlineWorkout == nil
                    ? "checkmark.circle" : "pencil.circle"
            )
            .font(.caption)
            .foregroundStyle(inlineWorkout == nil
                ? ATHLTHStudioStyle.gold : Color.secondary)
            .help(ATHLTHLocalization.choose(
                english: "The stored plan is local. Unsaved workout changes remain drafts. Cloud synchronization requires separate consent.",
                norwegian: "Planen er lagret lokalt. Endringer i en åpen økt er utkast. Skysynkronisering krever separat samtykke."
            ))
            .lineLimit(2)
        }
        .padding(.horizontal, 5)
    }

    private func weekCopyControls(
        _ plan: TrainingPlan,
        sourceWeekID: UUID
    ) -> some View {
        let sourceWeek = plan.weeks.first(where: { $0.id == sourceWeekID })
        let targets = availableWeekCopyTargets(
            in: plan, excluding: sourceWeekID
        )
        return HStack(spacing: 10) {
            Image(systemName: "square.on.square")
                .foregroundStyle(ATHLTHStudioStyle.gold)
            Text(ATHLTHLocalization.format(
                english: "Copy week %d to",
                norwegian: "Kopier uke %d til",
                sourceWeek?.weekNumber ?? 0
            ))
            .font(.caption.weight(.semibold))

            Menu {
                ForEach(targets) { target in
                    Button(ATHLTHLocalization.format(
                        english: "Week %d (empty)",
                        norwegian: "Uke %d (tom)",
                        target.weekNumber
                    )) {
                        pendingWeekCopyTarget = target.id
                    }
                }
            } label: {
                Label(
                    targets.isEmpty
                        ? ATHLTHLocalization.choose(
                            english: "No empty future weeks",
                            norwegian: "Ingen tomme fremtidige uker"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Choose target week",
                            norwegian: "Velg måluke"
                        ),
                    systemImage: "chevron.down"
                )
            }
            .disabled(targets.isEmpty || inlineWorkout != nil)
            .buttonStyle(.bordered)

            Spacer(minLength: 0)
            Button {
                copyingWeekID = nil
                pendingWeekCopyTarget = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Close week copy",
                norwegian: "Lukk ukekopiering"
            ))
        }
        .padding(12)
        .background(
            ATHLTHStudioStyle.paper,
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func availableWeekCopyTargets(
        in plan: TrainingPlan,
        excluding sourceID: UUID
    ) -> [TrainingPlanWeek] {
        let today = Calendar.current.startOfDay(for: Date())
        return plan.weeks.enumerated().compactMap { index, week in
            guard week.id != sourceID,
                  week.days.count == 7,
                  week.days.allSatisfy(\.sessions.isEmpty),
                  week.days.allSatisfy({ day in
                      guard let date = ATHLTHStudioPlanWeekSummary.date(
                          for: day, inWeekIndex: index,
                          planStart: plan.startDate
                      ) else { return false }
                      return date >= today
                  })
            else { return nil }
            return week
        }
    }

    private func copySelectedWeek() {
        defer { pendingWeekCopyTarget = nil }
        guard let sourceID = copyingWeekID,
              let targetID = pendingWeekCopyTarget,
              let plan = selectedPlan,
              let receipt = session.copyPlanStudioWeek(
                  planID: plan.id,
                  sourceWeekID: sourceID,
                  targetWeekID: targetID,
                  expectedVersion: plan.version
              ) else {
            warning = ATHLTHLocalization.choose(
                english: "Could not copy the whole week. Refresh the plan and check that the destination is empty and future-dated.",
                norwegian: "Kunne ikke kopiere hele uken. Oppdater planen og kontroller at måluken er tom og ligger i fremtiden."
            )
            return
        }
        lastWeekCopy = receipt
        copyingWeekID = nil
        copyMessage = ATHLTHLocalization.choose(
            english: "The whole week was copied. You can undo until the next change.",
            norwegian: "Hele uken er kopiert. Du kan angre frem til neste endring."
        )
        selectedWeekID = targetID
    }

    private func undoWeekCopy() {
        guard let receipt = lastWeekCopy,
              session.undoPlanStudioWeekCopy(
                  receipt,
                  healthWorkouts: health.workouts,
                  strengthHistory: strength.workoutHistory
              ) else {
            warning = ATHLTHLocalization.choose(
                english: "Cannot undo: the week has changed or training was completed after copying.",
                norwegian: "Kan ikke angre: Uken er endret eller trening er gjennomført siden kopieringen."
            )
            return
        }
        lastWeekCopy = nil
        copyMessage = ATHLTHLocalization.choose(
            english: "The week copy was undone; the original week is unchanged.",
            norwegian: "Ukekopieringen er angret. Den opprinnelige uken er urørt."
        )
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

    private func openNewWorkout(plan: TrainingPlan, day: TrainingPlanDay, date: Date?) {
        guard let date,
              Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: .now),
              !day.sessions.contains(where: \.isExplicitRestDay),
              session.trainingPlan(withID: plan.id)?.version == plan.version
        else {
            warning = ATHLTHLocalization.choose(
                english: "The day is unavailable or the plan changed. Reload the plan.",
                norwegian: "Dagen er utilgjengelig eller planen er endret. Oppdater planen."
            )
            return
        }
        newWorkoutTime = Calendar.current.date(
            bySettingHour: 18, minute: 0, second: 0, of: date
        ) ?? date
        inlineNewWorkout = NewWorkoutDestination(
            planID: plan.id, dayID: day.id,
            expectedVersion: plan.version, date: date
        )
        viewMode = StudioPlanMode.week.rawValue
    }

    private func saveInlineNewWorkout(
        _ proposed: PlannedSession,
        destination: NewWorkoutDestination
    ) -> Bool {
        guard let current = session.trainingPlan(withID: destination.planID),
              current.version == destination.expectedVersion,
              Calendar.current.startOfDay(for: destination.date) >=
                Calendar.current.startOfDay(for: .now),
              let day = current.weeks.flatMap(\.days).first(where: {
                  $0.id == destination.dayID
              }),
              !day.sessions.contains(where: \.isExplicitRestDay)
        else {
            warning = ATHLTHLocalization.choose(
                english: "The plan changed. Your workout draft is preserved.",
                norwegian: "Planen ble endret. Øktutkastet er bevart."
            )
            return false
        }

        var workout = proposed
        let time = Calendar.current.dateComponents(
            [.hour, .minute, .second], from: newWorkoutTime
        )
        workout.scheduledStart = Calendar.current.date(
            bySettingHour: time.hour ?? 18,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: destination.date
        ) ?? destination.date

        let saved = session.savePlanStudioWorkout(
            workout, inPlan: destination.planID,
            dayID: destination.dayID, editingWorkoutID: nil,
            expectedPlanVersion: destination.expectedVersion,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        if saved {
            inlineNewWorkout = nil
        } else {
            warning = ATHLTHLocalization.choose(
                english: "Could not save the workout. Your draft remains available.",
                norwegian: "Kunne ikke lagre økten. Utkastet er fortsatt tilgjengelig."
            )
        }
        return saved
    }

    private func inlineExistingWorkoutEditor(
        _ destination: InlineWorkoutDestination
    ) -> some View {
        ATHLTHTrainWorkoutBuilderView(
            planID: destination.planID,
            dayID: destination.dayID,
            expectedPlanVersion: destination.expectedPlanVersion,
            existingWorkout: destination.workout,
            onCloseInline: { inlineWorkout = nil }
        )
        .id(destination.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ATHLTHStudioStyle.paper)
    }

    private func openFullWorkout(planID: UUID, workoutID: UUID) {
        guard let plan = session.trainingPlan(withID: planID),
              let day = plan.weeks.flatMap(\.days).first(where: {
                  $0.sessions.contains(where: { $0.id == workoutID })
              }),
              let workout = day.sessions.first(where: { $0.id == workoutID }) else {
            warning = ATHLTHLocalization.choose(
                english: "The workout was not found in the latest plan. Reload the day and try again.",
                norwegian: "Økten finnes ikke i den siste planen. Last inn dagen på nytt og prøv igjen."
            )
            return
        }
        inlineWorkout = InlineWorkoutDestination(
            planID: plan.id,
            dayID: day.id,
            expectedPlanVersion: plan.version,
            workout: workout
        )
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
