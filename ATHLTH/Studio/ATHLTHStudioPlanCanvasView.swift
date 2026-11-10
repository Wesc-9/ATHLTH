import SwiftUI

/// Full-width, landscape-first plan building on iPad.
/// Week navigation, seven real dates and the workout editor stay in view
/// together. The shared AppSessionStore remains the single source of truth.
struct ATHLTHStudioPlanCanvasView: View {
    var onStartWorkout: ((UUID, UUID) -> Void)? = nil
    var onSendToWatch: ((UUID, UUID) -> Void)? = nil
    var onStartAfter: ((UUID, UUID, TimeInterval) -> Void)? = nil
    var requestedPlanID: UUID? = nil
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var favorites: LibraryFavoritesStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @StateObject private var workoutCatalog = WorkoutTemplateCatalogStore()

    @State private var selectedPlanID: UUID?
    @State private var selectedWeekID: UUID?
    @State private var selectedDayID: UUID?
    // One selection per iPad window. Health data and plan content remain in
    // their canonical stores; these tokens only restore the visible editor.
    @SceneStorage("athlth.studio.canvas.planID") private var scenePlanID = ""
    @SceneStorage("athlth.studio.canvas.weekID") private var sceneWeekID = ""
    @SceneStorage("athlth.studio.canvas.dayID") private var sceneDayID = ""
    // Entering the canvas always starts with Planning, not a restored Overview tab.
    @State private var viewMode = "week"
    @State private var favoriteQuery = ""
    @State private var pendingFavorite: FavoriteInsertion?

    private struct FavoriteInsertion {
        let planID: UUID
        let dayID: UUID
        let scheduledDate: Date
        let workout: PlannedSession
        let savedTemplateID: UUID?
    }
    @State private var copyingWeekID: UUID?
    @State private var pendingWeekCopyTarget: UUID?
    @State private var lastWeekCopy: AppSessionStore.PlanStudioWeekCopyReceipt?
    @State private var copyMessage: String?
    @SceneStorage("athlth.studio.canvas.draftOwnerID")
    private var draftOwnerID = ""
    @SceneStorage("athlth.studio.canvas.creatingPlan")
    private var creatingPlan = false
    @SceneStorage("athlth.studio.canvas.newPlanName")
    private var newPlanName = ""
    @SceneStorage("athlth.studio.canvas.newPlanSummary")
    private var newPlanSummary = ""
    @State private var newPlanStart = Date.now
    @SceneStorage("athlth.studio.canvas.newPlanStart")
    private var storedNewPlanStart: Double = 0
    @SceneStorage("athlth.studio.canvas.newPlanWeeks")
    private var newPlanWeeks = 4
    @State private var showingAdvancedBuilder = false
    @State private var showingPlanMetadata = false
    /// The existing plan's workout edits in the right-hand Studio column.
    /// This references the same AppSessionStore session as the iPhone builder.
    @State private var inlineWorkout: InlineWorkoutDestination?
    @State private var inlineNewWorkout: NewWorkoutDestination?
    @State private var newWorkoutTime = Date.now
    @State private var newWorkoutActivity: ATHLTHPlannedWorkoutType?

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
    @State private var actionToUndo: StudioAction?
    @State private var actionToRedo: StudioAction?
    @State private var batchWorkoutIDs = Set<UUID>()
    @State private var batchDestinationDayID: UUID?
    @State private var batchCopy = false

    /// Only the most recent drag-and-drop change can be undone safely.
    /// Its stored plan version prevents reversing another device's edits.
    private enum StudioAction {
        case move(planID: UUID, workoutID: UUID, sourceDate: Date,
                  targetDate: Date, expectedVersion: Int)
        case copy(planID: UUID, sourceWorkoutID: UUID,
                  targetDayID: UUID, copyID: UUID?, expectedVersion: Int)
    }

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
            // Scene storage is tied to an iPad window, not the signed-in
            // account. Never display another account's unsaved plan details.
            let owner = session.profile.userID.uuidString
            if draftOwnerID != owner {
                draftOwnerID = owner
                creatingPlan = false
                newPlanName = ""
                newPlanSummary = ""
                newPlanWeeks = 4
                storedNewPlanStart = 0
            }
            // Each new entrance uses the standard view and column widths.
            viewMode = StudioPlanMode.week.rawValue
            if let requestedPlanID, session.trainingPlan(withID: requestedPlanID) != nil {
                selectedPlanID = requestedPlanID
            }
            if selectedPlanID == nil {
                let restoredPlanID = UUID(uuidString: scenePlanID)
                let plan = restoredPlanID.flatMap {
                    session.trainingPlan(withID: $0)
                } ?? selectedPlan
                selectedPlanID = plan?.id
                if let plan,
                   let savedWeek = UUID(uuidString: sceneWeekID),
                   let week = plan.weeks.first(where: { $0.id == savedWeek }) {
                    selectedWeekID = week.id
                    if let savedDay = UUID(uuidString: sceneDayID),
                       week.days.contains(where: { $0.id == savedDay }) {
                        selectedDayID = savedDay
                    }
                }
            }
            newPlanStart = storedNewPlanStart > 0
                ? Date(timeIntervalSince1970: storedNewPlanStart)
                : session.suggestedTrainingPlanStartDate
        }
        .task {
            async let favs: Void = favorites.refresh()
            async let workouts: Void = workoutCatalog.refresh()
            _ = await (favs, workouts)
        }
        .onChange(of: requestedPlanID) { _, updated in
            if let updated, session.trainingPlan(withID: updated) != nil {
                selectedPlanID = updated
                viewMode = StudioPlanMode.week.rawValue
            }
        }
        .onChange(of: newPlanStart) { _, date in
            storedNewPlanStart = date.timeIntervalSince1970
        }
        .onChange(of: selectedPlanID) { previous, selected in
            scenePlanID = selected?.uuidString ?? ""
            // Restoring the initial scene selection must not erase its week
            // and day. Switching from an existing plan must clear them.
            if previous != nil {
                selectedWeekID = nil
                selectedDayID = nil
                sceneWeekID = ""
                sceneDayID = ""
            }
            inlineWorkout = nil
            inlineNewWorkout = nil
            newWorkoutActivity = nil
            copyingWeekID = nil
            pendingWeekCopyTarget = nil
            lastWeekCopy = nil
            copyMessage = nil
            actionToUndo = nil
            actionToRedo = nil
            batchWorkoutIDs = []
            batchDestinationDayID = nil
        }
        .onChange(of: selectedWeekID) { _, selected in
            sceneWeekID = selected?.uuidString ?? ""
            inlineWorkout = nil
            inlineNewWorkout = nil
            newWorkoutActivity = nil
        }
        .onChange(of: selectedDayID) { _, selected in
            sceneDayID = selected?.uuidString ?? ""
            inlineWorkout = nil
            inlineNewWorkout = nil
            newWorkoutActivity = nil
        }
        .onChange(of: session.profile.userID) { _, _ in
            scenePlanID = ""
            sceneWeekID = ""
            sceneDayID = ""
            draftOwnerID = session.profile.userID.uuidString
            selectedPlanID = nil
            selectedWeekID = nil
            selectedDayID = nil
            inlineWorkout = nil
            inlineNewWorkout = nil
            newWorkoutActivity = nil
            copyingWeekID = nil
            pendingWeekCopyTarget = nil
            lastWeekCopy = nil
            copyMessage = nil
            creatingPlan = false
            newPlanName = ""
            newPlanSummary = ""
            newPlanWeeks = 4
            storedNewPlanStart = 0
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
                english: "This day already has a workout",
                norwegian: "Denne dagen har allerede en økt"
            ),
            isPresented: Binding(
                get: { pendingFavorite != nil },
                set: { if !$0 { pendingFavorite = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Add as an extra workout",
                norwegian: "Legg til som en ekstra økt"
            )) {
                if let favorite = pendingFavorite {
                    insertFavorite(favorite, replacingExisting: false)
                }
                pendingFavorite = nil
            }
            if let favorite = pendingFavorite,
               let plan = session.trainingPlan(withID: favorite.planID),
               let day = plan.weeks.flatMap(\.days).first(where: { $0.id == favorite.dayID }),
               day.sessions.filter({ !$0.isExplicitRestDay }).count == 1 {
                Button(ATHLTHLocalization.choose(
                    english: "Replace existing workout",
                    norwegian: "Erstatt eksisterende økt"
                ), role: .destructive) {
                    insertFavorite(favorite, replacingExisting: true)
                    pendingFavorite = nil
                }
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) { pendingFavorite = nil }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "Keep the current workout and add another, or replace it. Completed workouts cannot be replaced.",
                norwegian: "Behold økten og legg til en ekstra, eller erstatt den. Fullførte økter kan ikke erstattes."
            ))
        }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Apply to \(batchWorkoutIDs.count) planned workouts?",
                norwegian: "Endre \(batchWorkoutIDs.count) planlagte økter?"
            ),
            isPresented: Binding(
                get: { batchDestinationDayID != nil },
                set: { if !$0 { batchDestinationDayID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(
                batchCopy
                    ? ATHLTHLocalization.choose(
                        english: "Copy workouts", norwegian: "Kopier øktene"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Move workouts", norwegian: "Flytt øktene"
                    )
            ) {
                applyBatchTransfer()
            }
            Button(ATHLTHLocalization.choose(
                english: "Cancel", norwegian: "Avbryt"
            ), role: .cancel) { batchDestinationDayID = nil }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "All selected workouts are checked before any plan changes. Completed workouts cannot be moved.",
                norwegian: "Alle valgte økter kontrolleres før planen endres. Fullførte økter kan ikke flyttes."
            ))
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
               viewMode == StudioPlanMode.week.rawValue &&
               plan.weeks.contains(where: { week in
                   week.days.contains(where: { !$0.sessions.isEmpty })
               }) {
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
                    if let newWorkoutActivity {
                        WorkoutTemplateBuilderView(
                            draftContext: "ipad-plan-day-\(session.profile.userID.uuidString)-\(fresh.id)-\(newWorkoutActivity.rawValue)",
                            plannedDate: newWorkoutTime,
                            initialActivity: newWorkoutActivity,
                            initialStudioAdvanced: newWorkoutActivity != .running,
                            onScheduledTimeChanged: { newWorkoutTime = $0 },
                            onAddStandalone: { workout in
                                saveInlineNewWorkout(workout, destination: fresh)
                            },
                            saveButtonTitle: ATHLTHLocalization.choose(
                                english: "Save to training plan", norwegian: "Lagre i treningsplan"
                            ),
                            onCloseInline: { self.newWorkoutActivity = nil }
                        )
                        .environment(\.athlthStudioFullscreenEditing, true)
                        .id("\(fresh.id)-\(newWorkoutActivity.rawValue)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        newWorkoutActivitySelection
                    }
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
                ATHLTHStudioPlanningColumns {
                    weekNavigation(plan, selectedIndex: weekIndex,
                                   selectedDay: day, selectedDate: dayDate)
                } calendar: {
                    weekCanvas(plan, week: week, weekIndex: weekIndex)
                } dayEditor: {
                    ATHLTHStudioPlanDayEditorView(
                        plan: plan,
                        day: day,
                        date: dayDate,
                        onOpenAdvanced: { workoutID in
                            openFullWorkout(planID: plan.id, workoutID: workoutID)
                        },
                        onCreateAdvanced: {
                            openNewWorkout(plan: plan, day: day, date: dayDate)
                        },
                        onStartWorkout: onStartWorkout,
                        onSendToWatch: onSendToWatch,
                        onStartAfter: onStartAfter
                    )
                    .id(day.id)
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
                        },
                        onStartWorkout: onStartWorkout,
                        onSendToWatch: onSendToWatch,
                        onStartAfter: onStartAfter
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

            if batchWorkoutIDs.count >= 2 && inlineWorkout == nil {
                Menu {
                    ForEach(plan.weeks) { week in
                        Menu(ATHLTHLocalization.choose(
                            english: "Move · week \(week.weekNumber)",
                            norwegian: "Flytt · uke \(week.weekNumber)"
                        )) {
                            ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                                Button(ATHLTHLocalization.choose(
                                    english: "Day \(day.dayIndex)",
                                    norwegian: "Dag \(day.dayIndex)"
                                )) {
                                    batchCopy = false
                                    batchDestinationDayID = day.id
                                }
                                .disabled(day.sessions.contains(where: \.isExplicitRestDay))
                            }
                        }
                        Menu(ATHLTHLocalization.choose(
                            english: "Copy · week \(week.weekNumber)",
                            norwegian: "Kopier · uke \(week.weekNumber)"
                        )) {
                            ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                                Button(ATHLTHLocalization.choose(
                                    english: "Day \(day.dayIndex)",
                                    norwegian: "Dag \(day.dayIndex)"
                                )) {
                                    batchCopy = true
                                    batchDestinationDayID = day.id
                                }
                                .disabled(day.sessions.contains(where: \.isExplicitRestDay))
                            }
                        }
                    }
                    Divider()
                    Button(ATHLTHLocalization.choose(
                        english: "Clear selection",
                        norwegian: "Nullstill valg"
                    )) {
                        batchWorkoutIDs = []
                    }
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "\(batchWorkoutIDs.count) selected",
                            norwegian: "\(batchWorkoutIDs.count) valgte"
                        ),
                        systemImage: "checkmark.circle"
                    )
                }
                .tint(ATHLTHStudioStyle.gold)
                .accessibilityIdentifier("athlth-ipad-plan-batch-actions")
            }

            if inlineWorkout == nil && inlineNewWorkout == nil {
                if actionToUndo != nil {
                    Button {
                        undoLastStudioAction()
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Undo", norwegian: "Angre"
                        ), systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("z", modifiers: [.command])
                    .help(ATHLTHLocalization.choose(
                        english: "Undo last drag-and-drop change",
                        norwegian: "Angre siste dra-og-slipp-endring"
                    ))
                }
                if actionToRedo != nil {
                    Button {
                        redoLastStudioAction()
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Redo", norwegian: "Gjør om"
                        ), systemImage: "arrow.uturn.forward")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
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
            .controlSize(.small)
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
        selectedIndex: Int,
        selectedDay: TrainingPlanDay,
        selectedDate: Date?
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
                english: "FAVORITE WORKOUTS", norwegian: "FAVORITTØKTER"
            ))
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(ATHLTHStudioStyle.gold)

            TextField(ATHLTHLocalization.choose(
                english: "Search favorites", norwegian: "Søk i favoritter"
            ), text: $favoriteQuery)
            .font(.caption)
            .padding(9)
            .background(ATHLTHStudioStyle.canvas,
                        in: RoundedRectangle(cornerRadius: 10))

            let saved = session.savedWorkoutTemplates.filter {
                favorites.isFavorite(.workout, itemID: $0.id.uuidString) &&
                $0.title.localizedStandardContains(favoriteQuery)
            }
            let catalog = workoutCatalog.entries.filter {
                favorites.isFavorite(.workout, itemID: $0.id.uuidString) &&
                $0.title.localizedStandardContains(favoriteQuery)
            }
            let running = runningLibrary.allTemplates.filter {
                favorites.isFavorite(.workout, itemID: $0.id.uuidString) &&
                $0.title.localizedStandardContains(favoriteQuery)
            }
            if saved.isEmpty && catalog.isEmpty && running.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Star workouts in the library to use them here.",
                    norwegian: "Merk økter med stjerne i biblioteket for å bruke dem her."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(saved) { item in
                            favoriteWorkoutRow(item.title, symbol: item.kind.systemImage) {
                                selectFavorite(item, savedID: item.id, plan: plan,
                                               day: selectedDay, date: selectedDate)
                            }
                            .draggable("library:\(item.id.uuidString)")
                        }
                        ForEach(catalog) { item in
                            favoriteWorkoutRow(item.title, symbol: item.systemImage) {
                                selectFavorite(item.plannedSession(), savedID: nil,
                                               plan: plan, day: selectedDay, date: selectedDate)
                            }
                            .draggable("catalog:\(item.id.uuidString)")
                        }
                        ForEach(running) { item in
                            favoriteWorkoutRow(item.title, symbol: "figure.run") {
                                selectFavorite(item.plannedSession(), savedID: nil,
                                               plan: plan, day: selectedDay, date: selectedDate)
                            }
                            .draggable("running:\(item.id.uuidString)")
                        }
                    }
                }
                .frame(maxHeight: 245)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.5))
        }
    }


    private func favoriteWorkoutRow(
        _ title: String, symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus.circle")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHStudioStyle.gold)
            }
            .padding(9)
            .background(ATHLTHStudioStyle.canvas,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Add to the selected day; you can also drag it to another day.",
            norwegian: "Legg til på valgt dag, eller dra økten til en annen dag."
        ))
    }

    private func selectFavorite(
        _ workout: PlannedSession, savedID: UUID?,
        plan: TrainingPlan, day: TrainingPlanDay, date: Date?
    ) {
        guard let date,
              Calendar.current.startOfDay(for: date) >=
                Calendar.current.startOfDay(for: .now),
              !day.sessions.contains(where: \.isExplicitRestDay),
              session.trainingPlan(withID: plan.id)?.version == plan.version else {
            warning = ATHLTHLocalization.choose(
                english: "This day is unavailable. Select a future training day.",
                norwegian: "Denne dagen er ikke tilgjengelig. Velg en fremtidig treningsdag."
            )
            return
        }
        let choice = FavoriteInsertion(planID: plan.id, dayID: day.id,
            scheduledDate: date, workout: workout, savedTemplateID: savedID)
        if day.sessions.isEmpty {
            insertFavorite(choice, replacingExisting: false)
        } else {
            pendingFavorite = choice
        }
    }

    private func insertFavorite(_ choice: FavoriteInsertion, replacingExisting: Bool) {
        guard let current = session.trainingPlan(withID: choice.planID),
              let day = current.weeks.flatMap(\.days)
                .first(where: { $0.id == choice.dayID }),
              !day.sessions.contains(where: \.isExplicitRestDay),
              Calendar.current.startOfDay(for: choice.scheduledDate) >=
                Calendar.current.startOfDay(for: .now) else {
            warning = ATHLTHLocalization.choose(
                english: "This plan or day changed. Review it before adding a workout.",
                norwegian: "Planen eller dagen er endret. Kontroller den før du legger til en økt."
            )
            return
        }
        let succeeded: Bool
        if replacingExisting,
           day.sessions.filter({ !$0.isExplicitRestDay }).count == 1,
           let existing = day.sessions.first {
            let replacement = session.studioFavoriteReplacement(
                source: choice.workout, replacing: existing
            )
            succeeded = session.savePlanStudioWorkout(
                replacement, inPlan: current.id, dayID: day.id,
                editingWorkoutID: existing.id, expectedPlanVersion: current.version,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        } else if let savedID = choice.savedTemplateID {
            succeeded = session.insertSavedWorkoutIntoPlan(
                templateID: savedID, planID: current.id, dayID: day.id
            )
        } else {
            succeeded = session.savePlanStudioWorkout(
                choice.workout, inPlan: current.id, dayID: day.id,
                editingWorkoutID: nil, expectedPlanVersion: current.version,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        }
        if succeeded {
            selectedWeekID = current.weeks.first(where: {
                $0.days.contains(where: { $0.id == day.id })
            })?.id
            selectedDayID = day.id
        } else {
            warning = ATHLTHLocalization.choose(
                english: "Could not add or replace this workout. Completed workouts and stale plan versions are protected.",
                norwegian: "Kunne ikke legge til eller erstatte økten. Fullførte økter og utdaterte planversjoner er beskyttet."
            )
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
        .contextMenu {
            Button(ATHLTHLocalization.choose(
                english: "Copy this week", norwegian: "Kopier denne uken"
            ), systemImage: "square.on.square") {
                copyingWeekID = week.id
                copyMessage = nil
            }
        }
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
                            if !workout.isExplicitRestDay {
                                Button {
                                    if batchWorkoutIDs.contains(workout.id) {
                                        batchWorkoutIDs.remove(workout.id)
                                    } else {
                                        batchWorkoutIDs.insert(workout.id)
                                    }
                                } label: {
                                    Image(systemName:
                                        batchWorkoutIDs.contains(workout.id)
                                            ? "checkmark.square.fill" : "square"
                                    )
                                    .font(.system(size: 18))
                                    .foregroundStyle(ATHLTHStudioStyle.gold)
                                    .frame(width: 30, height: 36)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    ATHLTHLocalization.choose(
                                        english: "Select workout for batch actions",
                                        norwegian: "Velg økt for gruppehandling"
                                    )
                                )
                            }
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

        var action: StudioAction?
        let success: Bool
        if raw.hasPrefix("library:"),
           let libraryID = UUID(uuidString: String(
               raw.dropFirst("library:".count)
           )) {
            let oldIDs = Set(target.sessions.map(\.id))
            success = session.insertSavedWorkoutIntoPlan(
                templateID: libraryID,
                planID: plan.id,
                dayID: target.id
            )
            // Library templates also create a new independent planned session.
            // Its source ID is not another plan session, so only move/copy
            // mutations are registered for redo here.
            if success, let newPlan = session.trainingPlan(withID: plan.id),
               let newSession = newPlan.weeks.flatMap(\.days)
                   .first(where: { $0.id == target.id })?
                   .sessions.first(where: { !oldIDs.contains($0.id) }) {
                _ = newSession.id
            }
        } else if raw.hasPrefix("catalog:"),
                  let catalogID = UUID(uuidString: String(raw.dropFirst("catalog:".count))),
                  let item = workoutCatalog.entries.first(where: { $0.id == catalogID }) {
            success = session.savePlanStudioWorkout(
                item.plannedSession(), inPlan: plan.id, dayID: target.id,
                editingWorkoutID: nil, expectedPlanVersion: plan.version,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        } else if raw.hasPrefix("running:"),
                  let templateID = UUID(uuidString: String(raw.dropFirst("running:".count))),
                  let item = runningLibrary.allTemplates.first(where: { $0.id == templateID }) {
            success = session.savePlanStudioWorkout(
                item.plannedSession(), inPlan: plan.id, dayID: target.id,
                editingWorkoutID: nil, expectedPlanVersion: plan.version,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        } else if let workoutID = UUID(uuidString: raw) {
            if dropMode == .copy {
                let oldIDs = Set(target.sessions.map(\.id))
                success = session.copyPlanStudioWorkout(
                    planID: plan.id,
                    sourceWorkoutID: workoutID,
                    targetDayID: target.id,
                    expectedVersion: plan.version
                )
                if success, let updated = session.trainingPlan(withID: plan.id),
                   let updatedDay = updated.weeks.flatMap(\.days)
                       .first(where: { $0.id == target.id }),
                   let copied = updatedDay.sessions.first(where: {
                       !oldIDs.contains($0.id)
                   }) {
                    action = .copy(
                        planID: plan.id,
                        sourceWorkoutID: workoutID,
                        targetDayID: target.id,
                        copyID: copied.id,
                        expectedVersion: updated.version
                    )
                }
            } else {
                let sourceDate = plan.weeks.enumerated().compactMap {
                    offset, week -> Date? in
                    guard let source = week.days.first(where: {
                        $0.sessions.contains(where: { $0.id == workoutID })
                    }) else { return nil }
                    return ATHLTHStudioPlanWeekSummary.date(
                        for: source, inWeekIndex: offset,
                        planStart: plan.startDate
                    )
                }.first
                success = session.movePlanStudioWorkout(
                    planID: plan.id,
                    workoutID: workoutID,
                    targetDate: date,
                    expectedVersion: plan.version,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                )
                if success, let sourceDate,
                   let updated = session.trainingPlan(withID: plan.id) {
                    action = .move(
                        planID: plan.id,
                        workoutID: workoutID,
                        sourceDate: sourceDate,
                        targetDate: date,
                        expectedVersion: updated.version
                    )
                }
            }
        } else {
            return false
        }
        if success {
            selectedDayID = target.id
            actionToUndo = action
            actionToRedo = nil
        } else {
            warning = ATHLTHLocalization.choose(
                english: "This workout cannot be moved or copied. Check the date, completion status and latest plan version.",
                norwegian: "Økten kan ikke flyttes eller kopieres. Kontroller dato, fullføringsstatus og siste planversjon."
            )
        }
        return success
    }

    private func undoLastStudioAction() {
        guard let action = actionToUndo else { return }
        let succeeded: Bool
        switch action {
        case let .move(planID, workoutID, sourceDate, _, expectedVersion):
            succeeded = session.movePlanStudioWorkout(
                planID: planID, workoutID: workoutID,
                targetDate: sourceDate, expectedVersion: expectedVersion,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        case let .copy(planID, _, dayID, copyID, expectedVersion):
            guard let copyID else { return }
            succeeded = session.removePlanStudioWorkout(
                planID: planID, workoutID: copyID,
                dayID: dayID, expectedVersion: expectedVersion,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        }
        actionToUndo = nil
        if succeeded {
            switch action {
            case let .move(planID, workoutID, sourceDate, targetDate, _):
                if let version = session.trainingPlan(withID: planID)?.version {
                    actionToRedo = .move(
                        planID: planID, workoutID: workoutID,
                        sourceDate: sourceDate, targetDate: targetDate,
                        expectedVersion: version
                    )
                }
            case let .copy(planID, sourceID, dayID, _, _):
                if let version = session.trainingPlan(withID: planID)?.version {
                    actionToRedo = .copy(
                        planID: planID, sourceWorkoutID: sourceID,
                        targetDayID: dayID, copyID: nil,
                        expectedVersion: version
                    )
                }
            }
        } else {
            actionToRedo = nil
            warning = ATHLTHLocalization.choose(
                english: "This plan changed or the workout was completed. Undo was not applied.",
                norwegian: "Planen er endret eller økten er fullført. Endringen ble ikke angret."
            )
        }
    }

    private func redoLastStudioAction() {
        guard let action = actionToRedo else { return }
        let succeeded: Bool
        var newCopyID: UUID?
        switch action {
        case let .move(planID, workoutID, _, targetDate, expectedVersion):
            succeeded = session.movePlanStudioWorkout(
                planID: planID, workoutID: workoutID,
                targetDate: targetDate, expectedVersion: expectedVersion,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        case let .copy(planID, sourceID, dayID, _, expectedVersion):
            let existingIDs = Set(
                session.trainingPlan(withID: planID)?
                    .weeks.flatMap(\.days)
                    .first(where: { $0.id == dayID })?
                    .sessions.map(\.id) ?? []
            )
            succeeded = session.copyPlanStudioWorkout(
                planID: planID, sourceWorkoutID: sourceID,
                targetDayID: dayID, expectedVersion: expectedVersion
            )
            if succeeded {
                newCopyID = session.trainingPlan(withID: planID)?
                    .weeks.flatMap(\.days)
                    .first(where: { $0.id == dayID })?
                    .sessions.first(where: { !existingIDs.contains($0.id) })?.id
            }
        }
        actionToRedo = nil
        guard succeeded else {
            actionToUndo = nil
            warning = ATHLTHLocalization.choose(
                english: "The plan changed. Redo was not applied.",
                norwegian: "Planen er endret. Endringen ble ikke utført på nytt."
            )
            return
        }
        switch action {
        case let .move(planID, workoutID, sourceDate, targetDate, _):
            if let version = session.trainingPlan(withID: planID)?.version {
                actionToUndo = .move(
                    planID: planID, workoutID: workoutID,
                    sourceDate: sourceDate, targetDate: targetDate,
                    expectedVersion: version
                )
            }
        case let .copy(planID, sourceID, dayID, _, _):
            if let version = session.trainingPlan(withID: planID)?.version,
               let newCopyID {
                actionToUndo = .copy(
                    planID: planID, sourceWorkoutID: sourceID,
                    targetDayID: dayID, copyID: newCopyID,
                    expectedVersion: version
                )
            }
        }
    }

    private func applyBatchTransfer() {
        guard let dayID = batchDestinationDayID,
              let plan = selectedPlan else {
            batchDestinationDayID = nil
            return
        }
        batchDestinationDayID = nil
        let copied = batchCopy
        let succeeded = session.batchTransferPlanStudioWorkouts(
            planID: plan.id,
            workoutIDs: Array(batchWorkoutIDs),
            targetDayID: dayID,
            copy: copied,
            expectedVersion: plan.version,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        if succeeded {
            batchWorkoutIDs = []
            actionToUndo = nil
            actionToRedo = nil
            selectedDayID = dayID
        } else {
            warning = ATHLTHLocalization.choose(
                english: "No workouts were changed. Verify dates, completion status and the newest plan version.",
                norwegian: "Ingen økter ble endret. Kontroller datoer, fullføringsstatus og siste planversjon."
            )
        }
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
        newPlanName = ""
        newPlanSummary = ""
        newPlanWeeks = 4
        storedNewPlanStart = 0
    }

    private var newWorkoutActivitySelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(ATHLTHLocalization.choose(
                    english: "CREATE A WORKOUT", norwegian: "OPPRETT EN ØKT"
                ))
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(ATHLTHStudioStyle.gold)

                Text(ATHLTHLocalization.choose(
                    english: "Choose your activity",
                    norwegian: "Velg aktivitet"
                ))
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(ATHLTHStudioStyle.ink)

                Text(ATHLTHLocalization.choose(
                    english: "Use the same exercises, intervals and phase editor as on iPhone.",
                    norwegian: "Bruk de samme øvelsene, intervallene og øktdelene som på iPhone."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(ATHLTHPlannedWorkoutType.defaultOrder) { activity in
                        Button {
                            newWorkoutActivity = activity
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: activity.symbol)
                                    .font(.title3)
                                    .foregroundStyle(ATHLTHStudioStyle.gold)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        ATHLTHStudioStyle.canvas,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                Text(activity.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHStudioStyle.ink)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHStudioStyle.gold)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, minHeight: 78)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15))
                            .overlay {
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(ATHLTHStudioStyle.outline.opacity(0.7))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
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
        newWorkoutActivity = nil
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
            newWorkoutActivity = nil
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
