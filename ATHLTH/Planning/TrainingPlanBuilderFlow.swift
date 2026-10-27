import SwiftUI

/// A location-only change must never count as a completed training day.
/// Both the guided Next button and its action use the same policy.
enum ATHLTHGuidedPlanDayPolicy {
    static func isPlanned(_ edit: ATHLTHPlanWeekDayEdit?) -> Bool {
        guard let edit else { return false }
        return edit.isRestDay == true ||
            edit.detailedWorkout?.isValid == true ||
            (edit.additionalDetailedWorkouts ?? []).contains(where: \.isValid)
    }
}

struct ATHLTHTrainingPlanBuilderFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    let startsAtSourceChoice: Bool
    let initialAdvanced: Bool
    /// Only explicit "Continue draft" actions may resume at a later step.
    let resumesDraftOnAppear: Bool
    /// New plans use their own checkpoint; old and completed plans are safe.
    let draftID: UUID?
    var onCreated: ((UUID) -> Void)? = nil

    @State private var step: BuilderStep
    @State private var mode: TrainingPlanBuilderMode
    @State private var entryChoice: ATHLTHPlanEntryChoiceView.Choice
    @State private var selectedSource: SourceOption = .scratch
    @State private var sourceRoute: [ExistingPlanDestination] = []

    @State private var title = ""

    // A blank title means automatic naming from a REAL linked goal or
    // workout focus, never a generic "My training plan".
    private var defaultPlanTitle: String {
        if let linked = goalStore.activeGoals.first(where: {
            $0.status == .active && selectedGoalIDs.contains($0.id)
        }) {
            return String(linked.title.prefix(40))
        }
        let activities = Set(selectedDays.map { resolvedWorkoutKind(for: $0) })
        if activities.contains(.strength) && activities.contains(.running) {
            return ATHLTHLocalization.choose(
                english: "Strength & running", norwegian: "Styrke og løping")
        }
        if activities.contains(.strength) {
            return ATHLTHLocalization.choose(
                english: "Strength training", norwegian: "Styrketrening")
        }
        if activities.contains(.running) {
            return ATHLTHLocalization.choose(
                english: "Running plan", norwegian: "Løpeplan")
        }
        if activities.contains(.walking) {
            return ATHLTHLocalization.choose(
                english: "Walking plan", norwegian: "Gåprogram")
        }
        return selectedGoalArea.title
    }
    private var resolvedPlanTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultPlanTitle : trimmed
    }
    @State private var weekCount = 4
    @State private var startDate =
        ATHLTHTrainingPlanBuilderFlow.defaultStartDate()

    @State private var focus: TrainingPlanFocus = .running
    @State private var selectedGoalArea: ATHLTHPlanGoalArea = .running
    @State private var selectedGoalChoice = "fitness"
    @State private var secondaryFocus: TrainingPlanFocus?
    @State private var focusWeight = 70
    @State private var goal: TrainingPlanGoalType = .improveFitness
    @State private var goalDetail = ""
    @State private var planSummary = ""
    @State private var isPlanDescriptionExpanded = false

    @State private var injuryFree = true
    @State private var injuriesOrLimitations = ""
    @State private var selectedMuscles: Set<String> = []
    @State private var primaryMuscle: String?

    @State private var sessionsPerWeek = 3
    @State private var selectedDays: Set<Int> = [1, 3, 5]
    @State private var workoutKindOverridesByDay:
        [Int: WorkoutKind] = [:]
    @State private var workoutTitleOverridesByDay: [Int: String] = [:]
    @State private var workoutMinutesByDay: [Int: Int] = [:]
    @State private var editingWeekDay: WeekDayEditorSelection?
    @State private var composingAdvancedDay: WeekDayEditorSelection?
    @State private var structuredWorkoutsByDay:
        [Int: ATHLTHPlanStructuredWorkoutBlueprint] = [:]
    @State private var selectedPlanWeekIndex = 0
    /// Keys use weekIndex * 7 + weekday, so different weeks expand independently.
    @State private var expandedWeekPreviewDays: Set<Int> = []
    @State private var guidedTrainingPlaceExpanded = false
    @State private var weekDayEdits: [Int: ATHLTHPlanWeekDayEdit] = [:]
    @State private var weekPlanningApproach: ATHLTHPlanWeekPlanningApproach?
    @State private var advancedAddDestination: AdvancedAddDestination?

    private struct AdvancedAddDestination: Identifiable {
        let id = UUID()
        let day: Int
        let week: Int
        let phase: WorkoutPhaseKind
        let kind: ATHLTHAdvancedPlanAddContentView.Kind
        var workoutIndex: Int = 0
    }
    @State private var guidedDayCursor = 0
    @State private var firstGuidedWeekDecisionMade = false
    @State private var repeatWeekCount = 1
    @State private var selectingLibraryDay: WeekDayEditorSelection?
    @State private var pendingLibraryDay: WeekDayEditorSelection?
    @State private var pendingStudioDay: WeekDayEditorSelection?
    @State private var pendingTrainingPlaceDay: WeekDayEditorSelection?
    @State private var editingTrainingPlaceDay: WeekDayEditorSelection?
    @State private var reopenDayAfterPlace: WeekDayEditorSelection?
    @State private var quickStudioOption: QuickDayOption?
    @State private var addingExtraWorkout = false
    @State private var editingWorkoutIndex = 0
    @State private var previousGuidedEdits: [Int: ATHLTHPlanWeekDayEdit]?
    @State private var selectingExtraFromLibrary = false

    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    private struct WeekDayEditorSelection: Identifiable, Equatable {
        let id: Int
    }

    private enum QuickDayOption: String, CaseIterable, Identifiable {
        case strength, run, walk, mobility, stretching, meditation, yoga
        var id: String { rawValue }

        var title: String {
            switch self {
            case .strength: return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
            case .run: return ATHLTHLocalization.choose(english: "Run", norwegian: "Løp")
            case .walk: return ATHLTHLocalization.choose(english: "Walk", norwegian: "Gåtur")
            case .mobility: return ATHLTHLocalization.choose(english: "Mobility", norwegian: "Mobilitet")
            case .stretching: return ATHLTHLocalization.choose(english: "Stretching", norwegian: "Uttøying")
            case .meditation: return ATHLTHLocalization.choose(english: "Meditation", norwegian: "Meditasjon")
            case .yoga: return "Yoga"
            }
        }

        var symbol: String {
            switch self {
            case .strength: return "dumbbell.fill"
            case .run: return "figure.run"
            case .walk: return "figure.walk"
            case .mobility: return "figure.cooldown"
            case .stretching: return "figure.flexibility"
            case .meditation: return "sparkles"
            case .yoga: return "figure.yoga"
            }
        }
    }

    @State private var equipment: EquipmentContext = .gym
    @State private var weeklyTimeBudgetMinutes = 240
    @State private var advancedSessionMinutes = 45
    @State private var hasCompetitionDate = false
    @State private var competitionDate =
        Calendar.current.date(
            byAdding: .weekOfYear,
            value: 12,
            to: Date()
        ) ?? Date()
    @State private var visibility: ProfileVisibility = .privateOnly

    @State private var selectedGoalIDs: Set<UUID> = []
    @State private var showingNewGoalFromPlan = false
    @State private var goalIDsBeforeCreation: Set<UUID> = []
    @State private var varyWeekdays = false
    @State private var creationError: String?
    @State private var createdPlanID: UUID?
    @State private var showingCreatedPlan = false
    @State private var showingAIBuilder = false
    @State private var prefersAIPlanBuild = false
    @State private var didApplySuggestedStartDate = false
    @State private var showingPlanDesignLab = false
    @State private var isHydratingPlanDraft = false
    @State private var completedPlanCreation = false

    private let draftStore = ATHLTHPlanCreationDraftStore()

    init(
        startsAtSourceChoice: Bool,
        initialAdvanced: Bool,
        resumesDraftOnAppear: Bool = true,
        draftID: UUID? = nil,
        onCreated: ((UUID) -> Void)? = nil
    ) {
        self.resumesDraftOnAppear = resumesDraftOnAppear
        self.draftID = draftID
        self.onCreated = onCreated
        self.startsAtSourceChoice =
            startsAtSourceChoice
        self.initialAdvanced =
            initialAdvanced
        // The entry screen always offers three clear starting paths.
        // The existing basics/profile/week/review steps remain intact.
        _step = State(initialValue: .mode)
        _entryChoice = State(initialValue: initialAdvanced ? .advanced : .simple)
        _mode = State(
            initialValue:
                initialAdvanced
                    ? .advanced
                    : .basic
        )
    }

    private typealias BuilderStep = ATHLTHPlanJourneyStep

    private enum SourceOption: String, CaseIterable, Identifiable {
        case scratch
        case library
        case saved

        var id: String { rawValue }

        var title: String {
            switch self {
            case .scratch:
                return ATHLTHLocalization.choose(
                    english: "Start from scratch",
                    norwegian: "Start fra scratch"
                )
            case .library:
                return ATHLTHLocalization.choose(
                    english: "From the library",
                    norwegian: "Hent fra bibliotek"
                )
            case .saved:
                return ATHLTHLocalization.choose(
                    english: "Your saved plans",
                    norwegian: "Dine lagrede"
                )
            }
        }

        var subtitle: String {
            switch self {
            case .scratch:
                return ATHLTHLocalization.choose(
                    english: "Build your plan from the ground up.",
                    norwegian: "Bygg treningsplanen helt fra bunnen av."
                )
            case .library:
                return ATHLTHLocalization.choose(
                    english: "Choose a ready-made plan and make it yours.",
                    norwegian: "Velg en mal eller ferdig plan og gjør den til din."
                )
            case .saved:
                return ATHLTHLocalization.choose(
                    english: "Continue with a plan you've saved.",
                    norwegian: "Fortsett med en plan du allerede har lagret."
                )
            }
        }

        var symbol: String {
            switch self {
            case .scratch: return "pencil"
            case .library: return "book.closed"
            case .saved: return "folder"
            }
        }

        var image: String {
            switch self {
            case .scratch: return "GoalStrength"
            case .library: return "GoalMountain"
            case .saved: return "GoalProgress"
            }
        }
    }

    private enum EquipmentContext: String, CaseIterable, Identifiable {
        case gym
        case home
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gym:
                return ATHLTHLocalization.choose(
                    english: "Gym",
                    norwegian: "Treningssenter"
                )
            case .home:
                return ATHLTHLocalization.choose(
                    english: "Home",
                    norwegian: "Hjemme"
                )
            case .both:
                return ATHLTHLocalization.choose(
                    english: "Both",
                    norwegian: "Begge"
                )
            }
        }

        var icon: String {
            switch self {
            case .gym:
                return "dumbbell.fill"
            case .home:
                return "house.fill"
            case .both:
                return "arrow.left.arrow.right"
            }
        }
    }

    private struct MuscleOption: Identifiable {
        let id: String
        let english: String
        let norwegian: String

        var title: String {
            ATHLTHLocalization.choose(
                english: english,
                norwegian: norwegian
            )
        }
    }

    private static let muscleOptions: [MuscleOption] = [
        .init(
            id: "chest",
            english: "Chest",
            norwegian: "Bryst"
        ),
        .init(
            id: "back",
            english: "Back",
            norwegian: "Rygg"
        ),
        .init(
            id: "shoulders",
            english: "Shoulders",
            norwegian: "Skuldre"
        ),
        .init(
            id: "biceps",
            english: "Biceps",
            norwegian: "Biceps"
        ),
        .init(
            id: "triceps",
            english: "Triceps",
            norwegian: "Triceps"
        ),
        .init(
            id: "forearms",
            english: "Forearms",
            norwegian: "Underarmer"
        ),
        .init(
            id: "quads",
            english: "Quadriceps",
            norwegian: "Forside lår"
        ),
        .init(
            id: "hamstrings",
            english: "Hamstrings",
            norwegian: "Bakside lår"
        ),
        .init(
            id: "glutes",
            english: "Glutes",
            norwegian: "Sete"
        ),
        .init(
            id: "calves",
            english: "Calves",
            norwegian: "Legger"
        ),
        .init(
            id: "core",
            english: "Core",
            norwegian: "Kjerne"
        )
    ]

    private static func defaultStartDate() -> Date {
        let calendar = Calendar.current
        let today =
            calendar.startOfDay(for: Date())

        return calendar.nextDate(
            after: today,
            matching:
                DateComponents(weekday: 2),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? today
    }

    var body: some View {
        // Bound metadata decoding for the full plan wizard; an unbounded
        // SwiftUI generic chain exhausted the iPhone main-thread stack.
        AnyView(planPresentations)
    }

    private var planNavigation: some View {
        NavigationStack(path: $sourceRoute) {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        mode == .advanced
                            ? ATHLTHTheme.premiumGold
                                .opacity(0.34)
                            : ATHLTHTheme.accent
                                .opacity(0.28)
                )

                AnyView(content)
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "New training plan",
                    norwegian: "Ny treningsplan"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(step == .source || step == .mode || step == .goal || step == .approach ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                #if DEBUG
                if step != .source && step != .mode && step != .goal && step != .approach {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingPlanDesignLab = true } label: {
                            Image(systemName: "paintpalette")
                        }
                        .accessibilityLabel("Plan Design Lab")
                    }
                }
                #endif
                if step != .source && step != .mode && step != .goal && step != .approach {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(backButtonTitle) {
                            goBack()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !showingCreatedPlan {
                    if step == .mode {
                        AnyView(entryChoiceContinueBar)
                    } else if step == .goal {
                        AnyView(goalContinueBar)
                    } else if step == .basics && mode == .advanced {
                        AnyView(goalContinueBar)
                    } else if step == .basics && mode == .basic {
                        AnyView(simpleContinueBar)
                    } else if step == .approach {
                        AnyView(buildApproachContinueBar)
                    } else if step == .source {
                        AnyView(sourceContinueBar)
                    } else {
                        AnyView(bottomActionBar)
                    }
                }
            }
            .navigationDestination(
                for: ExistingPlanDestination.self
            ) { destination in
                switch destination {
                case .library:
                    TrainingPlanLibraryView {
                        dismiss()
                    }
                case .mine:
                    MyTrainingPlansLibraryView()
                }
            }
            .navigationDestination(
                isPresented: $showingCreatedPlan
            ) {
                createdPlanReviewDestination
            }
        }
    }

    private var planLifecycle: some View {
        AnyView(planNavigation)
        .onAppear {
            draftStore.setEditing(true, userID: session.profile.userID, draftID: draftID)
            guard !didApplySuggestedStartDate
            else {
                return
            }

            didApplySuggestedStartDate = true

            if !resumesDraftOnAppear {
                // A tap on "Create training plan" must never inherit step 2
                // (or a draft checkpoint) from an earlier presentation.
                // Only the explicit "Continue draft" route may restore it.
                step = .mode
                sourceRoute.removeAll()
                selectedSource = .scratch
                isHydratingPlanDraft = false
            }

            if resumesDraftOnAppear,
               let unfinished = draftStore.load(
                   userID: session.profile.userID, draftID: draftID
               ) {
                isHydratingPlanDraft = true
                restorePlanDraft(unfinished)
                // SwiftUI sheets should be presented after the navigation and
                // all of its fields have been restored to the view hierarchy.
                Task { @MainActor in
                    await Task.yield()
                    isHydratingPlanDraft = false
                    if step == .week, let day = unfinished.editorDay {
                        let selection = WeekDayEditorSelection(id: day)
                        switch unfinished.editorKind {
                        case "studio": composingAdvancedDay = selection
                        case "library": selectingLibraryDay = selection
                        case "day": editingWeekDay = selection
                        default: break
                        }
                    }
                    saveResumableDraft()
                }
                return
            }

            let suggested =
                session
                    .suggestedTrainingPlanStartDate
            let defaultDate =
                Self.defaultStartDate()

            startDate = mode == .basic
                ? Calendar.current.startOfDay(for: .now)
                : max(Calendar.current.startOfDay(for: .now),
                      Calendar.current.startOfDay(for: suggested))
        }
        .onDisappear {
            // A normal dismissal exits the editing session, while locking
            // the phone leaves it recoverable after an OS process eviction.
            if scenePhase == .active {
                draftStore.setEditing(false, userID: session.profile.userID, draftID: draftID)
            }
        }
    }

    private var planPrimaryObservers: some View {
        AnyView(planLifecycle)
        .onChange(of: title) { _, _ in saveResumableDraft() }
        .onChange(of: weekCount) { _, _ in saveResumableDraft() }
        .onChange(of: startDate) { _, _ in saveResumableDraft() }
        .onChange(of: mode) { _, _ in saveResumableDraft() }
        .onChange(of: focus) { _, _ in saveResumableDraft() }
        .onChange(of: goal) { _, _ in saveResumableDraft() }
        .onChange(of: selectedGoalArea) { _, _ in saveResumableDraft() }
        .onChange(of: selectedGoalChoice) { _, _ in saveResumableDraft() }
        .onChange(of: selectedGoalIDs) { _, selected in
            if let linked = goalStore.activeGoals.first(where: {
                selected.contains($0.id) && $0.status == .active
            }) {
                applyExistingGoalFocus(linked)
            }
            saveResumableDraft()
        }
        .onChange(of: varyWeekdays) { _, _ in saveResumableDraft() }
        .onChange(of: selectedSource) { _, _ in saveResumableDraft() }
        .onChange(of: workoutKindOverridesByDay) { _, _ in saveResumableDraft() }
        .onChange(of: workoutTitleOverridesByDay) { _, _ in saveResumableDraft() }
        .onChange(of: workoutMinutesByDay) { _, _ in saveResumableDraft() }
        .onChange(of: structuredWorkoutsByDay) { _, _ in saveResumableDraft() }
        .onChange(of: weekDayEdits) { _, _ in saveResumableDraft() }
        .onChange(of: weekPlanningApproach) { _, _ in saveResumableDraft() }
        .onChange(of: guidedDayCursor) { _, _ in
            selectedPlanWeekIndex = guidedCurrentWeek
            guidedTrainingPlaceExpanded = false
            expandedWeekPreviewDays.insert(
                weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)
            )
            saveResumableDraft()
        }
        .onChange(of: firstGuidedWeekDecisionMade) { _, _ in saveResumableDraft() }
    }

    private var planSecondaryObservers: some View {
        AnyView(planPrimaryObservers)
        .onChange(of: weekCount) { _, value in
            selectedPlanWeekIndex = min(selectedPlanWeekIndex, max(0, value - 1))
            weekDayEdits = weekDayEdits.filter { $0.key <= value * 7 }
            guidedDayCursor = min(guidedDayCursor, value * 7)
            repeatWeekCount = min(repeatWeekCount, max(1, value - 1))
        }
        .onChange(of: selectedDays) { _, _ in
            structuredWorkoutsByDay = structuredWorkoutsByDay
                .filter { selectedDays.contains($0.key) }
            workoutKindOverridesByDay = workoutKindOverridesByDay
                .filter { selectedDays.contains($0.key) }
            workoutTitleOverridesByDay = workoutTitleOverridesByDay
                .filter { selectedDays.contains($0.key) }
            workoutMinutesByDay = workoutMinutesByDay
                .filter { selectedDays.contains($0.key) }
            saveResumableDraft()
        }
        .onChange(of: equipment) { _, _ in saveResumableDraft() }
        .onChange(of: weeklyTimeBudgetMinutes) { _, newValue in
            if mode == .advanced {
                let perSession = Double(newValue) / Double(max(1, selectedDays.count))
                advancedSessionMinutes = min(180, max(5, Int((perSession / 5).rounded()) * 5))
            }
            saveResumableDraft()
        }
        .onChange(of: step) { _, _ in saveResumableDraft() }
        .onChange(of: selectedPlanWeekIndex) { _, _ in saveResumableDraft() }
        .onChange(of: simpleMinutes) { _, _ in saveResumableDraft() }
        .onChange(of: simpleActivities) { _, _ in saveResumableDraft() }
        .onChange(of: editingWeekDay) { _, _ in saveResumableDraft() }
        .onChange(of: composingAdvancedDay) { _, _ in saveResumableDraft() }
        .onChange(of: selectingLibraryDay) { _, _ in saveResumableDraft() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveResumableDraft() }
        }
        .onChange(
            of: sessionsPerWeek
        ) { _, newValue in
            let suggested =
                balancedDays(
                    count: newValue
                )
            if selectedDays.count !=
                newValue {
                selectedDays = suggested
            }
        }
    }

    private var planPresentations: some View {
        AnyView(planSecondaryObservers)
        .alert(
            ATHLTHLocalization.choose(
                english: "Could not create plan",
                norwegian: "Kunne ikke opprette planen"
            ),
            isPresented:
                Binding(
                    get: {
                        creationError != nil
                    },
                    set: { shown in
                        if !shown {
                            creationError = nil
                        }
                    }
                )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(creationError ?? "")
        }
        .sheet(isPresented: $showingNewGoalFromPlan, onDismiss: {
            // Link the actual newly created goal, not an illustrated preset.
            if let newGoal = goalStore.activeGoals.first(where: {
                $0.status == .active && !goalIDsBeforeCreation.contains($0.id)
            }) {
                selectedGoalIDs = [newGoal.id]
            }
            goalIDsBeforeCreation.removeAll()
        }) {
            GoalCreationView()
        }
        .sheet(isPresented: $showingPlanDesignLab) {
            ATHLTHPlanDesignLabView()
        }
        .sheet(isPresented: $showingAIBuilder, onDismiss: {
            // Coach-created plans use exactly the same persisted preview
            // and navigation flow as manually created plans.
            if createdPlanID != nil {
                showingCreatedPlan = true
            }
        }) {
            AIProgramBuilderView(
                mode: .generate,
                // Coach selected on the start screen must collect its own
                // intake. Seeded AI for legacy drafts keeps its wizard values.
                seed: entryChoice == .coach ? nil : aiBuilderSeed,
                onProgramCreatedPlanID: { id in
                    createdPlanID = id
                    completedPlanCreation = true
                    draftStore.clear(userID: session.profile.userID, draftID: draftID)
                }
            )
        }
        .sheet(item: $editingWeekDay, onDismiss: {
            if let pendingTrainingPlaceDay {
                self.pendingTrainingPlaceDay = nil
                editingTrainingPlaceDay = pendingTrainingPlaceDay
            } else if let pendingStudioDay {
                self.pendingStudioDay = nil
                composingAdvancedDay = pendingStudioDay
            } else if let pendingLibraryDay {
                self.pendingLibraryDay = nil
                selectingLibraryDay = pendingLibraryDay
            }
        }) { selection in
            planDayActionsSheet(for: selection.id)
        }
        .sheet(item: $editingTrainingPlaceDay, onDismiss: {
            if let reopenDayAfterPlace {
                self.reopenDayAfterPlace = nil
                editingWeekDay = reopenDayAfterPlace
            }
        }) { selection in
            ATHLTHPlanTrainingPlacePicker(
                initial: weekDayEdits[weekDayKey(selection.id)]?.trainingPlace
            ) { place in
                updateWeekDay(selection.id) { edit in
                    edit.trainingPlace = place
                }
                editingTrainingPlaceDay = nil
            }
        }
        .sheet(item: $advancedAddDestination) { destination in
            ATHLTHAdvancedPlanAddContentView(
                initialKind: destination.kind,
                phase: destination.phase,
                onExercise: { blocks in
                    insertGuidedLibraryExercise(
                        blocks, day: destination.day, week: destination.week,
                        workoutIndex: destination.workoutIndex)
                },
                onWorkout: { workout in
                    insertGuidedLibraryWorkout(
                        workout, day: destination.day, week: destination.week)
                }
            )
        }
        .sheet(item: $selectingLibraryDay) { selection in
            ATHLTHPlanWorkoutLibraryPicker { workout in
                assignLibraryWorkout(workout, to: selection.id, asExtra: selectingExtraFromLibrary)
                selectingExtraFromLibrary = false
                selectingLibraryDay = nil
            }
        }
        .sheet(item: $composingAdvancedDay, onDismiss: {
            quickStudioOption = nil
            addingExtraWorkout = false
        }) { selection in
            WorkoutTemplateBuilderView(
                initialTitle: quickStudioOption?.title ??
                    (addingExtraWorkout ? "" : (selectedWorkoutForEditor(day: selection.id)?.title ?? "")),
                initialBlocks: quickStudioOption.map { quickDaySeed($0) } ??
                    (addingExtraWorkout ? [] : (selectedWorkoutForEditor(day: selection.id)?.blocks ?? [])),
                initialRouteID: addingExtraWorkout ? nil : selectedWorkoutForEditor(day: selection.id)?.routeID,
                draftContext: "new-program-week-\(selectedPlanWeekIndex)-day-\(selection.id)-workout-\(addingExtraWorkout ? "new" : String(editingWorkoutIndex))",
                plannedDate: dateForWeekDay(selection.id, weekIndex: selectedPlanWeekIndex),
                planCopyDays: planCopyDayOptions(
                    excluding: selection.id, sourceWeekIndex: selectedPlanWeekIndex
                ),
                initialCopyWeekIndex: selectedPlanWeekIndex,
                onCopyToPlan: { name, blocks, routeID, minutes, keys in
                    copyComposedWorkout(
                        name: name, blocks: blocks, routeID: routeID,
                        duration: minutes, targets: keys,
                        sourceDay: selection.id, sourceWeek: selectedPlanWeekIndex
                    )
                },
                onSaveToPlan: { name, blocks, routeID, minutes, _ in
                    guard let minutes, (1...240).contains(minutes) else { return false }
                    let proposed = ATHLTHPlanStructuredWorkoutBlueprint(
                        title: name,
                        kind: workoutKind(for: blocks),
                        durationMinutes: minutes,
                        routeID: routeID,
                        blocks: blocks
                    )
                    guard proposed.isValid else { return false }
                    updateWeekDay(selection.id) { edit in
                        edit.isRestDay = false
                        if addingExtraWorkout {
                            if edit.detailedWorkout == nil {
                                edit.detailedWorkout = proposed
                                edit.kind = proposed.kind
                                edit.title = proposed.title
                                edit.durationMinutes = proposed.durationMinutes
                            } else {
                                edit.additionalDetailedWorkouts = (edit.additionalDetailedWorkouts ?? []) + [proposed]
                            }
                        } else if editingWorkoutIndex > 0,
                                  var extras = edit.additionalDetailedWorkouts,
                                  extras.indices.contains(editingWorkoutIndex - 1) {
                            extras[editingWorkoutIndex - 1] = proposed
                            edit.additionalDetailedWorkouts = extras
                        } else {
                            edit.detailedWorkout = proposed
                            edit.kind = proposed.kind
                            edit.title = name
                            edit.durationMinutes = proposed.durationMinutes
                        }
                        edit.removeTemplateDetail = false
                    }
                    addingExtraWorkout = false
                    return true
                }
            )
        }
    }

    // Kept separate from the main navigation body to avoid excessive
    // SwiftUI generic type-checking in the plan creation flow.
    @ViewBuilder
    private var createdPlanReviewDestination: some View {
        // Simple skips Advanced's method chooser and lands straight in
        // the actual Plan week view, without an extra success/question card.
        if mode == .basic, let createdPlanID {
            ScrollView {
                ATHLTHTrainPlanPremiumView(highlightedPlanID: createdPlanID)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Your training week", norwegian: "Din treningsuke"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    onCreated?(createdPlanID)
                    dismiss()
                } label: {
                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Done · Open Plan", norwegian: "Ferdig · Åpne Plan"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(ATHLTHTrainDesign.bronze.gradient,
                                in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(ATHLTHTrainDesign.canvas.opacity(0.98))
            }
        } else if let createdPlanID,
                   let savedPlan = session.trainingPlan(withID: createdPlanID) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Your plan has been saved",
                                    norwegian: "Treningsplanen er lagret"
                                ),
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)

                            Text(savedPlan.title)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(ATHLTHPlanDesign.ink)

                            HStack(spacing: 12) {
                                Label("\(savedPlan.weeks.count) " +
                                      ATHLTHLocalization.choose(english: "weeks", norwegian: "uker"),
                                      systemImage: "calendar")
                                Label("\(savedPlan.weeks.first?.days.flatMap(\.sessions).count ?? 0) " +
                                      ATHLTHLocalization.choose(english: "sessions/week", norwegian: "økter/uke"),
                                      systemImage: "figure.run")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)

                            Text(ATHLTHLocalization.choose(
                                english: "You can review your workouts below. The entire plan is available under Train → Plan.",
                                norwegian: "Se gjennom øktene nedenfor. Hele planen finner du under Tren → Plan."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.9),
                                    in: RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                        ATHLTHTrainPlanPremiumView(highlightedPlanID: createdPlanID)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                    }
                    .background(
                        ATHLTHPremiumCanvas(
                            accent: ATHLTHTheme.accent.opacity(0.30)
                        )
                    )
                    .navigationTitle(
                        ATHLTHLocalization.choose(
                            english: "Review your plan",
                            norwegian: "Se over planen din"
                        )
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            onCreated?(createdPlanID)
                            dismiss()
                        } label: {
                            HStack {
                                Text(ATHLTHLocalization.choose(english: "Open in Plan", norwegian: "Åpne i Plan"))
                                    .font(.headline)
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.right")
                            }
                            .foregroundStyle(.white)
                            .padding(18)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(ATHLTHPlanDesign.ink, in: RoundedRectangle(cornerRadius: 18))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                    }
                }
    }

    private enum ExistingPlanDestination: Hashable {
        case library
        case mine
    }

    // Keep each step behind a stable type boundary. The TestFlight 1.8.7
    // crash symbolicates to a giant wizardScroll<ConditionalContent<...>>
    // instantiation; even when a wizard is not visible, SwiftUI can request
    // its generic metadata during unrelated tab layout updates.
    @ViewBuilder
    private var content: some View {
        switch step {
        case .mode:
            AnyView(modeChoice)
        case .goal:
            AnyView(goalChoice)
        case .source:
            AnyView(sourceChoice)
        case .basics:
            if mode == .advanced {
                AnyView(advancedScheduleStep)
            } else {
                AnyView(simpleScheduleStep)
            }
        case .profile:
            AnyView(wizardScroll(AnyView(profileStep))) // legacy only
        case .approach:
            if mode == .advanced {
                AnyView(buildApproachChoice)
            } else {
                AnyView(wizardScroll(AnyView(weekStep)))
            }
        case .week:
            AnyView(wizardScroll(AnyView(
                Group {
                    if mode == .advanced {
                        switch weekPlanningApproach {
                        case .none:
                            AnyView(weekStep)
                        case .some(.quick):
                            AnyView(advancedWeekBuilderStep)
                        case .some(.guided):
                            AnyView(guidedWeekStep)
                        }
                    } else {
                        AnyView(weekStep)
                    }
                }
            )))
        case .review:
            AnyView(wizardScroll(AnyView(reviewStep)))
        }
    }

    // This must NOT be generic. A generic ScrollView over nested wizard
    // steps recreates the deeply mangled runtime metadata from build 94.
    private func wizardScroll(_ page: AnyView) -> some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 16
            ) {
                if step == .week && mode == .advanced {
                    AnyView(sourceChoiceHeader)
                } else {
                    AnyView(progressHeader)
                }
                page
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 118)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private let sourceInk = ATHLTHTrainDesign.ink
    private let sourceMuted = ATHLTHTrainDesign.secondary
    private let sourceGold = ATHLTHTrainDesign.bronze
    private let sourceCanvas = ATHLTHTrainDesign.canvas

    private var stepDisplayTotal: Int {
        ATHLTHPlanJourney.displayedCount(advanced: mode == .advanced)
    }

    private var stepDisplayNumber: Int {
        ATHLTHPlanJourney.position(of: step, advanced: mode == .advanced) ?? 1
    }

    // Single visible entry screen, composed as a native photo-first page.
    // The old mode cards are not rendered or layered underneath.
    private var modeChoice: some View {
        ATHLTHPlanEntryChoiceView(
            choice: Binding(
                get: { entryChoice },
                set: { selected in
                    entryChoice = selected
                    switch selected {
                    case .simple:
                        mode = .basic
                    case .advanced, .coach:
                        mode = .advanced
                    }
                }
            ),
            onOpenLibrary: { sourceRoute.append(.library) },
            onCancel: { dismiss() }
        )
    }

    private var existingPlanLibraryButton: some View {
        ATHLTHPlanExistingChoice(
            title: ATHLTHLocalization.choose(
                english: "Plan library", norwegian: "Planbibliotek"
            ),
            subtitle: ATHLTHLocalization.choose(
                english: "Explore ready plans", norwegian: "Utforsk ferdige planer"
            ),
            symbol: "square.stack.3d.up",
            compact: true
        ) {
            sourceRoute.append(.library)
        }
    }

    private var existingMyPlansButton: some View {
        ATHLTHPlanExistingChoice(
            title: ATHLTHLocalization.choose(
                english: "My plans", norwegian: "Mine planer"
            ),
            subtitle: ATHLTHLocalization.choose(
                english: "View and edit plans", norwegian: "Se og rediger dine planer"
            ),
            symbol: "bookmark",
            compact: true
        ) {
            sourceRoute.append(.mine)
        }
    }

    // User explicitly chooses between Simple, Advanced, or Coach.
    // Manual paths open their actual setup, while Coach opens the
    // existing AIProgramBuilderView via a single sheet, not a nested wizard.
    private var entryChoiceContinueBar: some View {
        Button {
            switch entryChoice {
            case .simple:
                switchSetupMode(to: false)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    step = .basics
                }
            case .advanced:
                switchSetupMode(to: true)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    step = .basics
                }
            case .coach:
                mode = .advanced
                showingAIBuilder = true
            }
        } label: {
            HStack {
                Spacer(minLength: 10)
                Text(ATHLTHLocalization.choose(
                    english: "Select and continue", norwegian: "Velg og fortsett"
                ))
                .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 53)
            .background(
                LinearGradient(
                    colors: [ATHLTHTrainDesign.bronze,
                             Color(red: 0.69, green: 0.50, blue: 0.28)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 19)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background(ATHLTHTrainDesign.canvas.opacity(0.99))
    }

    private func applyExistingGoalFocus(_ linked: ATHLTHGoal) {
        switch linked.category {
        case .strength:
            focus = .strength
            goal = .getStronger
            selectedGoalArea = .strength
            selectedGoalChoice = "power"
            if mode == .basic { simpleActivities = [.strength] }
        case .event:
            focus = .running
            goal = .raceReady
            selectedGoalArea = .specific
            selectedGoalChoice = "event"
            if mode == .basic { simpleActivities = [.running] }
            if let deadline = linked.deadline,
               deadline >= Calendar.current.startOfDay(for: .now) {
                hasCompetitionDate = true
                competitionDate = deadline
            }
        case .endurance:
            focus = .running
            goal = .improveFitness
            selectedGoalArea = .running
            selectedGoalChoice = "fitness"
            if mode == .basic { simpleActivities = [.running] }
        case .recovery:
            focus = .generalFitness
            goal = .improveFitness
            selectedGoalArea = .general
            selectedGoalChoice = "wellness"
            if mode == .basic { simpleActivities = [.walking] }
        case .consistency, .body, .custom:
            focus = .generalFitness
            goal = .improveFitness
            selectedGoalArea = .general
            selectedGoalChoice = "fitness"
        }
        if mode == .basic { setSimpleKinds() }
    }

    private var modeContinueBar: some View {
        Button {
            if mode == .basic {
                updateSimplePlanChoices()
                weekCount = 4
                startDate = Calendar.current.startOfDay(for: .now)
            } else {
                weeklyTimeBudgetMinutes = advancedSessionMinutes * selectedDays.count
            }
            // The preselected running card must already affect the plan even
            // when the user presses Next without tapping a radio row.
            if let selected = ATHLTHPlanGoalOption.options(for: selectedGoalArea)
                .first(where: { $0.id == selectedGoalChoice }) {
                selectGoalOption(selected)
            } else {
                selectGoalArea(selectedGoalArea)
            }
            goForward()
        } label: {
            HStack(spacing: 12) {
                Spacer(minLength: 12)
                Text(ATHLTHLocalization.choose(
                    english: "Select and continue", norwegian: "Velg og fortsett"
                ))
                .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 55)
            .background(
                LinearGradient(
                    colors: [
                        sourceGold.opacity(0.89),
                        Color(red: 0.65, green: 0.48, blue: 0.27)
                    ],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 21, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 21))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(sourceCanvas.opacity(0.98))
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Continue with the selected planning mode.",
            norwegian: "Fortsett med valgt planleggingsmåte."
        ))
    }

    // A dedicated reference-inspired goal screen, kept behind a stable
    // AnyView boundary just like the other stages in this large wizard.
    private var goalChoice: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                referenceGoalProgressHeader
                ATHLTHPlanGoalEntryView(
                    area: selectedGoalArea,
                    selectedChoice: selectedGoalChoice,
                    onChooseArea: { newArea in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.17)) {
                            selectGoalArea(newArea)
                        }
                    },
                    onChooseGoal: { option in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.17)) {
                            selectGoalOption(option)
                        }
                    }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 26)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
    }

    // Goal selection is the first actual plan-building screen; the preceding
    // simple/advanced chooser is an entry route rather than a plan detail.
    // Keep the canonical journey untouched while matching the approved 1/5
    // visual on this step, including the Cancel action and five-step bar.
    private var referenceGoalProgressHeader: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Text(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    ))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(sourceInk)
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(
                        .white.opacity(0.84),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(sourceGold.opacity(0.12), lineWidth: 0.7)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Cancel plan creation",
                    norwegian: "Avbryt planopprettelse"
                ))

                Spacer(minLength: 0)

                Text("ATHLTH / PLAN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.6)
                    .foregroundStyle(sourceInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Text("1 / 5")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(sourceInk)
                    .frame(width: 49, alignment: .trailing)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Step 1 of 5", norwegian: "Steg 1 av 5"
                    ))
            }

            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index == 0 ? sourceGold :
                              Color(red: 0.87, green: 0.85, blue: 0.82))
                        .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.top, 4)
    }

    private func selectGoalArea(_ newArea: ATHLTHPlanGoalArea) {
        selectedGoalArea = newArea
        guard let first = ATHLTHPlanGoalOption.options(for: newArea).first else {
            return
        }
        selectGoalOption(first)
    }

    private func selectGoalOption(_ option: ATHLTHPlanGoalOption) {
        selectedGoalChoice = option.id
        focus = option.focus
        goal = option.goal
        // A visible user-selected objective is not silently replaced by a
        // stale free-text note from another selection.
        if option.id == "distance" {
            goalDetail = ATHLTHLocalization.choose(
                english: "Improve running distance", norwegian: "Løpe lenger"
            )
        } else if goalDetail == "Løpe lenger" ||
                    goalDetail == "Improve running distance" {
            goalDetail = ""
        }

        // Simple plans cycle through chosen activity types. Keep that
        // existing source of truth aligned with the category selected here.
        if mode == .basic {
            switch option.focus {
            case .running, .endurance:
                simpleActivities = [.running]
            case .strength, .hypertrophy:
                simpleActivities = [.strength]
            case .hybrid:
                simpleActivities = [.running, .strength]
            case .generalFitness, .mobilityRehab:
                simpleActivities = [.walking, .running]
            }
            setSimpleKinds()
        }
    }

    private var goalContinueBar: some View {
        Button {
            guard canContinue else { return }
            goForward()
        } label: {
            HStack(spacing: 12) {
                Spacer(minLength: 12)
                Text(ATHLTHLocalization.choose(english: "Next", norwegian: "Neste"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 55)
            .background(
                LinearGradient(
                    colors: [ATHLTHTrainDesign.bronze,
                             Color(red: 0.70, green: 0.52, blue: 0.30)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 22)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .background(ATHLTHTrainDesign.canvas.opacity(0.98))
    }

    // Advanced-only fourth step. Three real destinations share the same plan
    // data. Simple plans are created from their setup and open the week view.
    private var selectedBuildMethod: ATHLTHPlanBuildMethod {
        if prefersAIPlanBuild { return .ai }
        return weekPlanningApproach == .quick ? .weekByWeek : .dayByDay
    }

    private func selectBuildMethod(_ method: ATHLTHPlanBuildMethod) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            switch method {
            case .dayByDay:
                prefersAIPlanBuild = false
                if weekPlanningApproach != .guided {
                    weekPlanningApproach = .guided
                    guidedDayCursor = 0
                    firstGuidedWeekDecisionMade = false
                    repeatWeekCount = max(1, weekCount - 1)
                }
            case .weekByWeek:
                prefersAIPlanBuild = false
                weekPlanningApproach = .quick
            case .ai:
                prefersAIPlanBuild = true
            }
        }
    }

    private var buildApproachChoice: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                sourceChoiceHeader
                ATHLTHPlanBuildMethodEntryView(
                    selected: selectedBuildMethod,
                    onSelect: selectBuildMethod,
                    onOpenLibrary: { sourceRoute.append(.library) },
                    onOpenMyPlans: { sourceRoute.append(.mine) }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
    }

    private var buildApproachContinueBar: some View {
        Button {
            guard mode == .advanced, canContinue else { return }
            switch selectedBuildMethod {
            case .ai:
                showingAIBuilder = true
            case .dayByDay:
                selectBuildMethod(.dayByDay)
                goForward()
            case .weekByWeek:
                selectBuildMethod(.weekByWeek)
                goForward()
            }
        } label: {
            HStack(spacing: 10) {
                Spacer(minLength: 12)
                if selectedBuildMethod == .ai {
                    Image(systemName: "sparkles")
                }
                Text(selectedBuildMethod == .ai
                     ? ATHLTHLocalization.choose(
                        english: "Continue with ATHLTH Coach",
                        norwegian: "Fortsett med ATHLTH Coach")
                     : ATHLTHLocalization.choose(
                        english: "Choose and continue",
                        norwegian: "Velg og fortsett"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 55)
            .background(
                LinearGradient(
                    colors: [ATHLTHTrainDesign.bronze,
                             Color(red: 0.69, green: 0.51, blue: 0.31)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 19)
            )
        }
        .buttonStyle(.plain)
        .disabled(mode != .advanced || !canContinue)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(ATHLTHTrainDesign.canvas.opacity(0.98))
    }

    private var sourceChoice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sourceChoiceHeader
                    .padding(.bottom, 30)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Choose how to start",
                        norwegian: "Velg hvordan du vil starte"
                    )
                )
                .font(.system(size: 33, weight: .regular, design: .serif))
                .foregroundStyle(sourceInk)
                .lineLimit(2)
                .minimumScaleFactor(0.80)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Every great plan starts somewhere. Choose what fits you, and make it yours along the way.",
                        norwegian: "Alle gode planer starter et sted. Velg det som passer deg best, så tilpasser vi resten underveis."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(sourceMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .padding(.horizontal, 10)

                VStack(spacing: 12) {
                    ForEach(SourceOption.allCases) { option in
                        ATHLTHPlanSelectionCard(
                            title: option.title,
                            subtitle: option.subtitle,
                            symbol: option.symbol,
                            selected: selectedSource == option
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selectedSource = option
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(sourceCanvas.ignoresSafeArea())
    }

    private var sourceChoiceHeader: some View {
        VStack(spacing: step == .mode ? 12 : 22) {
            HStack(spacing: 8) {
                Button {
                    if step == .mode { dismiss() } else { goBack() }
                } label: {
                    Text(
                        step == .mode
                        ? ATHLTHLocalization.choose(english: "Close", norwegian: "Lukk")
                        : ATHLTHLocalization.choose(english: "Back", norwegian: "Tilbake")
                    )
                    .font(.subheadline)
                    .foregroundStyle(sourceInk)
                    .padding(.horizontal, 15)
                    .frame(height: 40)
                    .background(
                        Color.white.opacity(0.85),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    step == .mode
                    ? ATHLTHLocalization.choose(english: "Close plan builder", norwegian: "Lukk planbygger")
                    : ATHLTHLocalization.choose(english: "Previous step", norwegian: "Forrige steg")
                )

                Spacer(minLength: 0)

                Text("ATHLTH / PLAN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.8)
                    .foregroundStyle(sourceInk)

                Spacer(minLength: 0)

                Text("\(stepDisplayNumber) / \(stepDisplayTotal)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(sourceInk)
                    .frame(minWidth: 42, alignment: .trailing)
            }

            HStack(spacing: 5) {
                ForEach(1...stepDisplayTotal, id: \.self) { index in
                    Capsule()
                        .fill(
                            index <= stepDisplayNumber
                                ? sourceGold
                                : Color(red: 0.87, green: 0.85, blue: 0.82)
                        )
                        .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // One shared mode state controls both this first screen and the
    // extra settings revealed by later steps of the plan builder.
    private var sourceModePicker: some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                sourceModeOption(
                    .basic,
                    title: ATHLTHLocalization.choose(
                        english: "Beginner",
                        norwegian: "Nybegynner"
                    )
                )

                sourceModeOption(
                    .advanced,
                    title: ATHLTHLocalization.choose(
                        english: "Advanced",
                        norwegian: "Avansert"
                    )
                )
            }
            .padding(3)
            .background(
                Color.white.opacity(0.83),
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(sourceGold.opacity(0.22), lineWidth: 0.8)
            }

            Text(
                ATHLTHLocalization.choose(
                    english: "Choose a simple or more detailed setup.",
                    norwegian: "Velg enkel eller mer detaljert oppstart."
                )
            )
            .font(.caption)
            .foregroundStyle(sourceMuted)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private func sourceModeOption(
        _ option: TrainingPlanBuilderMode,
        title: String
    ) -> some View {
        let isSelected = mode == option

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                mode = option
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(
                    isSelected ? .semibold : .medium
                ))
                .foregroundStyle(sourceInk)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    isSelected
                        ? sourceGold.opacity(0.15)
                        : Color.clear,
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
                        isSelected
                            ? sourceGold.opacity(0.96)
                            : Color.clear,
                        lineWidth: 1.1
                    )
                }
                .contentShape(
                    RoundedRectangle(cornerRadius: 17)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }

    private func sourceSelectionCard(_ option: SourceOption) -> some View {
        let isSelected = selectedSource == option

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSource = option
            }
        } label: {
            VStack(spacing: 0) {
                Image(option.image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 172)
                    .clipped()
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Image(systemName: option.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(sourceInk)
                        .frame(width: 39, height: 39)
                        .background(Color.white.opacity(0.90), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.055), lineWidth: 0.7)
                        }
                        .padding(.top, 12)

                    Text(option.title)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(sourceInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.79)
                        .frame(height: 45, alignment: .center)

                    Text(option.subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(sourceMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.88)
                        .frame(height: 64, alignment: .top)

                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? sourceInk : sourceMuted.opacity(0.3))
                    .frame(height: 29)
                    .padding(.bottom, 9)
                }
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity)
                .background(isSelected ? sourceGold.opacity(0.07) : Color.white)
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(
                        isSelected ? sourceGold : Color.black.opacity(0.09),
                        lineWidth: isSelected ? 1.35 : 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title + ". " + option.subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sourceContinueBar: some View {
        VStack(spacing: 0) {
            Button {
                switch selectedSource {
                case .scratch:
                    goForward()
                case .library:
                    sourceRoute.append(.library)
                case .saved:
                    sourceRoute.append(.mine)
                }
            } label: {
                HStack(spacing: 10) {
                    Spacer(minLength: 22)

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Continue",
                            norwegian: "Fortsett"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 52)
                .background(
                    sourceInk,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(sourceCanvas.opacity(0.98))
    }

    private func sourceCard(
        eyebrow: String,
        title: String,
        subtitle: String,
        footnote: String,
        icon: String,
        prominent: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            HStack {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 22,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : ATHLTHTheme.accentDeep
                    )
                    .frame(width: 54, height: 54)
                    .background(
                        prominent
                            ? Color.white.opacity(0.13)
                            : ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                    )

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : ATHLTHTheme.accentDeep
                    )
            }

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.55)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.62)
                            : ATHLTHTheme.mutedText
                    )

                Text(title)
                    .font(
                        .system(
                            size: 24,
                            weight: .bold,
                            design: .serif
                        )
                    )
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
                    .lineSpacing(2)
            }

            Text(footnote)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    prominent
                        ? Color.white.opacity(0.72)
                        : ATHLTHTheme.accentDeep
                )
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors:
                    prominent
                    ? [
                        ATHLTHTheme.accentDeep,
                        Color(
                            red: 0.15,
                            green: 0.18,
                            blue: 0.24
                        )
                    ]
                    : [
                        Color.white.opacity(0.96),
                        ATHLTHTheme.cardWarm
                            .opacity(0.48)
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
                Color.white.opacity(
                    prominent ? 0.10 : 0.92
                ),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(
                        prominent ? 0.17 : 0.06
                    ),
            radius: 18,
            y: 9
        )
    }

    private func compactSourceRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 44, height: 44)
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
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.88),
                lineWidth: 0.8
            )
        }
    }

    private var progressHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "STEP \(stepDisplayNumber) OF \(stepDisplayTotal)",
                        norwegian:
                            "STEG \(stepDisplayNumber) AV \(stepDisplayTotal)"
                    )
                )
                .font(.system(size: 9, weight: .bold))
                .tracking(1.55)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Spacer()

                Text(stepTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
            }

            HStack(spacing: 6) {
                ForEach(1...stepDisplayTotal, id: \.self) {
                    index in
                    Capsule()
                        .fill(
                            index <= stepDisplayNumber
                                ? ATHLTHTheme.accentDeep
                                : ATHLTHTheme.accent
                                    .opacity(0.10)
                        )
                        .frame(height: 5)
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .mode:
            return ATHLTHLocalization.choose(english: "Planning mode", norwegian: "Detaljnivå")
        case .goal:
            return ATHLTHLocalization.choose(english: "Your main goal", norwegian: "Hovedmålet ditt")
        case .source:
            return ATHLTHLocalization.choose(
                english: "Choose a starting point",
                norwegian: "Velg startmåte"
            )
        case .basics:
            return ATHLTHLocalization.choose(
                english: "Plan basics",
                norwegian: "Grunninfo"
            )
        case .profile:
            return ATHLTHLocalization.choose(english: "Goal & needs", norwegian: "Mål og behov")
        case .approach:
            return ATHLTHLocalization.choose(english: "Build method", norwegian: "Slik bygger du")
        case .week:
            return ATHLTHLocalization.choose(
                english: "Training week",
                norwegian: "Treningsuken"
            )
        case .review:
            return ATHLTHLocalization.choose(
                english: "Review",
                norwegian: "Oppsummering"
            )
        }
    }

    private var modeControl: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            ATHLTHPremiumSegmentedControl(
                titles: [
                    ATHLTHLocalization.choose(
                        english: "Beginner",
                        norwegian: "Nybegynner"
                    ),
                    ATHLTHLocalization.choose(
                        english: "Advanced",
                        norwegian: "Avansert"
                    )
                ],
                selection: modeSelection
            )

            HStack(
                alignment: .top,
                spacing: 8
            ) {
                Image(
                    systemName:
                        mode == .basic
                            ? "sparkles"
                            : "slider.horizontal.3"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    mode == .basic
                        ? ATHLTHTheme.vitality
                        : ATHLTHTheme.premiumGold
                )
                .padding(.top, 1)

                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
            .padding(.horizontal, 4)
        }
    }

    private var modeSelection: Binding<Int> {
        Binding(
            get: {
                mode == .basic ? 0 : 1
            },
            set: { newValue in
                mode =
                    newValue == 0
                        ? .basic
                        : .advanced
            }
        )
    }

    private var modeExplanation: String {
        switch mode {
        case .basic:
            return ATHLTHLocalization.choose(
                english:
                    "Simple language and only the choices you need. ATHLTH fills in the structure for you.",
                norwegian:
                    "Enkelt språk og bare valgene du trenger. ATHLTH hjelper deg med strukturen."
            )
        case .advanced:
            return ATHLTHLocalization.choose(
                english:
                    "More control for athletes and coaches: secondary focus, targets, time budget and competition date.",
                norwegian:
                    "Mer kontroll for utøvere og trenere: sekundærfokus, måltall, tidsbudsjett og konkurransedato."
            )
        }
    }

    // The simple route keeps technical settings out of the primary questions.
    // Advanced keeps the full profile and detailed week wizard.
    @State private var simpleMinutes = 30
    @State private var simpleActivities: Set<WorkoutKind> = [.walking]
    @State private var showingSimpleDays = false
    @State private var showingSimpleDuration = false

    private var orderedSimpleActivities: [WorkoutKind] {
        [.walking, .running, .strength].filter { simpleActivities.contains($0) }
    }

    private var simpleActivitySummary: String {
        orderedSimpleActivities.map { kind in
            switch kind {
            case .walking: return ATHLTHLocalization.choose(english: "walking", norwegian: "gåturer")
            case .running: return ATHLTHLocalization.choose(english: "running", norwegian: "løping")
            default: return ATHLTHLocalization.choose(english: "strength", norwegian: "styrke")
            }
        }.joined(separator: ATHLTHLocalization.choose(english: " and ", norwegian: " og "))
    }

    // Basic plans share the same photographic language as Advanced, but
    // intentionally ask fewer questions. Duration belongs to the individual
    // workout editor, not to this plan-wide setup screen.
    private var simpleScheduleStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                sourceChoiceHeader
                ATHLTHPlanSimpleScheduleEntryView(
                    title: $title,
                    startDate: $startDate,
                    weekCount: $weekCount,
                    linkedGoalIDs: $selectedGoalIDs,
                    selectedDays: selectedDays,
                    goals: goalStore.activeGoals.filter { $0.status == .active },
                    suggestedName: defaultPlanTitle,
                    onToggleDay: { day in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                            toggleDay(day)
                            setSimpleKinds()
                        }
                    },
                    onCreateGoal: openGoalCreationFromPlan,
                    onSelectAdvanced: { switchSetupMode(to: true) }
                )
                if let conflictingPlan {
                    conflictCard(conflictingPlan)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 22)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
    }

        private func openGoalCreationFromPlan() {
        goalIDsBeforeCreation = Set(goalStore.goals.map(\.id))
        showingNewGoalFromPlan = true
    }

    private func switchSetupMode(to advanced: Bool) {
        let nextMode: TrainingPlanBuilderMode = advanced ? .advanced : .basic
        guard mode != nextMode else { return }
        mode = nextMode
        if !advanced {
            startDate = Calendar.current.startOfDay(for: .now)
            weekCount = 4
            setSimpleKinds()
        } else if weekCount == 4 {
            weekCount = 8
        }
        // Preserve explicitly selected goals, plan title and training days.
        sessionsPerWeek = selectedDays.count
    }



        private var simpleContinueBar: some View {
        Button {
            guard canCreatePlan else { return }
            createPlan(seedSuggestedWeek: true)
        } label: {
            HStack(spacing: 12) {
                Spacer(minLength: 12)
                Text(ATHLTHLocalization.choose(english: "Next", norwegian: "Neste"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 55)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTrainDesign.bronze,
                        Color(red: 0.70, green: 0.52, blue: 0.30)
                    ],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 22)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canCreatePlan)
        .opacity(canCreatePlan ? 1 : 0.45)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .background(ATHLTHTrainDesign.canvas.opacity(0.98))
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Create the plan and open it for editing workouts.",
            norwegian: "Opprett planen og åpne den for redigering av økter."
        ))
    }

    private func simpleQuestion<Content: View>(
        _ question: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question)
                .font(.headline)
                .foregroundStyle(ATHLTHPlanDesign.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func simpleChoice(
        _ label: String, symbol: String, selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
                Text(label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.white : ATHLTHPlanDesign.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                selected ? ATHLTHTheme.accentDeep : ATHLTHPlanDesign.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? Color.white.opacity(0.12) : ATHLTHPlanDesign.outline,
                        lineWidth: 0.8
                    )
            }
            .shadow(color: ATHLTHTheme.accentDeep.opacity(selected ? 0.06 : 0.035),
                    radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func simpleCompactChoice(
        _ label: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .foregroundStyle(selected ? Color.white : ATHLTHPlanDesign.ink)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(
                    selected ? ATHLTHTheme.accentDeep : ATHLTHPlanDesign.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            selected ? Color.white.opacity(0.12) : ATHLTHPlanDesign.outline,
                            lineWidth: 0.8
                        )
                }
                .shadow(color: ATHLTHTheme.accentDeep.opacity(selected ? 0.06 : 0.035),
                        radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chooseSimpleActivity(_ kind: WorkoutKind) {
        if simpleActivities.contains(kind) {
            // Keep at least one activity without an extra validation step.
            guard simpleActivities.count > 1 else { return }
            simpleActivities.remove(kind)
        } else {
            simpleActivities.insert(kind)
        }
        updateSimplePlanChoices()
    }

    private func updateSimplePlanChoices() {
        if simpleActivities.count > 1 {
            focus = .hybrid
            // Keep the user's title untouched when changing preferred activities.
        } else if simpleActivities.contains(.running) {
            focus = .running
            // Activity changes should not overwrite a custom plan title.
        } else if simpleActivities.contains(.strength) {
            focus = .strength
            // Plan name stays independent of chosen activity.
        } else {
            focus = .generalFitness
            // No forced plan title: the default appears as placeholder.
        }
        setSimpleKinds()
    }

    private func setSimpleDays(_ count: Int) {
        selectedDays = balancedDays(count: count)
        sessionsPerWeek = count
        setSimpleKinds()
    }

    private func setSimpleKinds() {
        let kinds = orderedSimpleActivities
        guard !kinds.isEmpty else { return }
        workoutKindOverridesByDay = Dictionary(
            uniqueKeysWithValues: selectedDays.sorted().enumerated().map {
                ($0.element, kinds[$0.offset % kinds.count])
            }
        )
        weeklyTimeBudgetMinutes = simpleMinutes * selectedDays.count
    }

    // Basics already appears in the step progress header. Use one quiet
    // editorial heading instead of repeating the step number and details in
    // a large introductory card.
    private var compactBasicsIntro: some View {
        ATHLTHPlanSurface(density: .compact) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .accessibilityHidden(true)

                Text(ATHLTHLocalization.choose(
                    english: "Give the plan a frame",
                    norwegian: "Gi planen en ramme"
                ))
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }


    // Only advanced planning uses the new reference-led schedule screen.
    // Basic's original short step intentionally stays unchanged.
    private var advancedScheduleStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                sourceChoiceHeader
                ATHLTHPlanAdvancedScheduleEntryView(
                    title: $title,
                    startDate: $startDate,
                    weekCount: $weekCount,
                    linkedGoalIDs: $selectedGoalIDs,
                    varyWeekdays: $varyWeekdays,
                    selectedDays: selectedDays,
                    goals: goalStore.activeGoals.filter { $0.status == .active },
                    suggestedName: defaultPlanTitle,
                    onToggleDay: { day in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                            toggleAdvancedTrainingDay(day)
                        }
                    },
                    onCreateGoal: openGoalCreationFromPlan,
                    onSelectSimple: { switchSetupMode(to: false) }
                )
                if let conflictingPlan {
                    conflictCard(conflictingPlan)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 22)
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
    }

        private func selectAdvancedFrequency(_ count: Int) {
        guard (1...7).contains(count) else { return }
        if selectedDays.count != count {
            selectedDays = balancedDays(count: count)
        }
        sessionsPerWeek = count
        weeklyTimeBudgetMinutes = advancedSessionMinutes * count
    }

    private func toggleAdvancedTrainingDay(_ day: Int) {
        guard (1...7).contains(day) else { return }
        if selectedDays.contains(day) {
            guard selectedDays.count > 1 else { return }
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
        sessionsPerWeek = selectedDays.count
        weeklyTimeBudgetMinutes = advancedSessionMinutes * selectedDays.count
    }

    private var basicsStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            compactBasicsIntro

            builderPanel {
                VStack(spacing: 14) {
                    HStack {
                        fieldLabel(
                            ATHLTHLocalization.choose(
                                english: "Plan name",
                                norwegian: "Navn på planen"
                            )
                        )

                        Text("\(title.count)/40")
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    TextField(
                        ATHLTHLocalization.choose(
                            english: "My training plan",
                            norwegian: "Min treningsplan"
                        ),
                        text: $title
                    )
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 13)
                    .frame(height: 48)
                    .background(
                        Color.black.opacity(0.026),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .onChange(of: title) { _, newValue in
                        if newValue.count > 40 {
                            title = String(newValue.prefix(40))
                        }
                    }

                    planDescriptionSection

                    Divider()

                    DatePicker(
                        ATHLTHLocalization.choose(
                            english: "Starts",
                            norwegian: "Starter"
                        ),
                        selection: $startDate,
                        in:
                            Calendar.current
                                .startOfDay(
                                    for: Date()
                                )...,
                        displayedComponents: .date
                    )
                    .font(.subheadline.weight(.semibold))

                    Divider()

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        fieldLabel(
                            ATHLTHLocalization.choose(
                                english: "Duration",
                                norwegian: "Varighet"
                            )
                        )

                        durationOptions
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHPlanDesign.accent)
                        Text(ATHLTHLocalization.choose(
                            english: "Plan window",
                            norwegian: "Planperiode"
                        ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        Spacer(minLength: 4)
                        Text(
                            "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(resolvedEndDate.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    }
                    .padding(.top, 4)
                }
            }

            if let conflict = conflictingPlan {
                conflictCard(conflict)
            }

            if mode == .advanced {
                builderPanel {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Visibility",
                                        norwegian: "Synlighet"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Who can see the plan",
                                        norwegian:
                                            "Hvem kan se planen"
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }

                            Spacer()

                            Picker(
                                "Visibility",
                                selection: $visibility
                            ) {
                                ForEach(
                                    ProfileVisibility
                                        .allCases
                                ) { item in
                                    Text(item.title)
                                        .tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                    }
                }
            }
        }
    }

    private var planDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPlanDescriptionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ATHLTHPlanDesign.accent)
                        .frame(width: 23)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(planSummary.isEmpty
                            ? ATHLTHLocalization.choose(
                                english: "Add plan description",
                                norwegian: "Legg til planbeskrivelse"
                            )
                            : ATHLTHLocalization.choose(
                                english: "Plan description",
                                norwegian: "Planbeskrivelse"
                            )
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                        if !planSummary.isEmpty && !isPlanDescriptionExpanded {
                            Text(planSummary)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .lineLimit(1)
                        } else if planSummary.isEmpty {
                            Text(ATHLTHLocalization.choose(
                                english: "Optional · What is this plan for?",
                                norwegian: "Valgfritt · Hva ønsker du med planen?"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isPlanDescriptionExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(ATHLTHLocalization.choose(
                english: "Expand or collapse the optional description field.",
                norwegian: "Åpne eller lukk feltet for valgfri planbeskrivelse."
            ))

            if isPlanDescriptionExpanded {
                TextField(
                    ATHLTHLocalization.choose(
                        english: "For example: Build strength and consistency over eight weeks",
                        norwegian: "F.eks. bygge styrke og gode treningsvaner"
                    ),
                    text: $planSummary,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .padding(12)
                .background(
                    .white.opacity(0.80),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .onChange(of: planSummary) { _, value in
                    if value.count > 240 {
                        planSummary = String(value.prefix(240))
                    }
                }
                Text("\(planSummary.count)/240")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ATHLTHPlanDesign.selectedSurface.opacity(0.52),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var durationOptions: some View {
        HStack(spacing: 7) {
            ForEach([1, 4, 6, 8], id: \.self) { value in
                Button {
                    weekCount = value
                } label: {
                    VStack(spacing: 2) {
                        Text("\(value)")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                        Text(value == 1
                            ? ATHLTHLocalization.choose(english: "week", norwegian: "uke")
                            : ATHLTHLocalization.choose(english: "weeks", norwegian: "uker")
                        )
                        .font(.system(size: 10))
                    }
                    .foregroundStyle(
                        weekCount == value ? Color.white : ATHLTHPlanDesign.ink
                    )
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        weekCount == value
                            ? ATHLTHTheme.accentDeep
                            : Color.white.opacity(0.84),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(
                                weekCount == value
                                    ? Color.white.opacity(0.13)
                                    : ATHLTHPlanDesign.outline,
                                lineWidth: 0.75
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: value == 1 ? "1 week" : "\(value) weeks",
                    norwegian: value == 1 ? "1 uke" : "\(value) uker"
                ))
                .accessibilityAddTraits(weekCount == value ? [.isSelected] : [])
            }

            Menu {
                // Keep all durations possible, including 2 and 12 weeks;
                // only the quick shortcuts are reduced to one row.
                ForEach(1...52, id: \.self) { value in
                    Button(ATHLTHLocalization.choose(
                        english: value == 1 ? "1 week" : "\(value) weeks",
                        norwegian: value == 1 ? "1 uke" : "\(value) uker"
                    )) {
                        weekCount = value
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    if [1, 4, 6, 8].contains(weekCount) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                    } else {
                        Text("\(weekCount)")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                    }
                    Text([1, 4, 6, 8].contains(weekCount)
                        ? ATHLTHLocalization.choose(english: "Custom", norwegian: "Egen")
                        : ATHLTHLocalization.choose(english: "weeks", norwegian: "uker")
                    )
                    .font(.system(size: 10))
                }
                .foregroundStyle(
                    [1, 4, 6, 8].contains(weekCount)
                        ? ATHLTHPlanDesign.ink
                        : Color.white
                )
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    [1, 4, 6, 8].contains(weekCount)
                        ? Color.white.opacity(0.84)
                        : ATHLTHTheme.accentDeep,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            [1, 4, 6, 8].contains(weekCount)
                                ? ATHLTHPlanDesign.outline
                                : Color.white.opacity(0.13),
                            lineWidth: 0.75
                        )
                }
            }
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Custom duration, \(weekCount) weeks",
                norwegian: "Egendefinert varighet, \(weekCount) uker"
            ))
        }
    }

    private var profileStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            stepIntro(
                eyebrow:
                    ATHLTHLocalization.choose(
                        english: "02 · GOAL & NEEDS",
                        norwegian: "02 · MÅL OG BEHOV"
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "What should this plan do for you?",
                        norwegian: "Hva skal planen gjøre for deg?"
                    ),
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "These answers shape the week. You can change them later.",
                        norwegian:
                            "Svarene former treningsuken. Alt kan endres senere."
                    ),
                icon: "scope"
            )

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Main focus",
                            norwegian: "Hovedfokus"
                        )
                    )

                    focusGrid

                    if mode == .advanced {
                        Divider()

                        advancedFocusControls
                    }
                }
            }

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Main goal",
                            norwegian: "Hva ønsker du å oppnå?"
                        )
                    )

                    goalGrid

                    if mode == .advanced {
                        Divider()

                        TextField(
                            ATHLTHLocalization.choose(
                                english:
                                    "Concrete target, e.g. 5K in 20:00 or squat 150 kg",
                                norwegian:
                                    "Konkret mål, f.eks. 5 km på 20:00 eller 150 kg i knebøy"
                            ),
                            text: $goalDetail,
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            Color.black.opacity(0.026),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )
                    }
                }
            }

            if showMusclePriorities {
                builderPanel {
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        fieldLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Muscles you want to prioritise",
                                norwegian:
                                    "Muskler du vil prioritere"
                            )
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Optional. Choose one or more areas you want the plan to emphasise.",
                                norwegian:
                                    "Valgfritt. Velg ett eller flere områder planen skal prioritere."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                        muscleGrid

                        if selectedMuscles.count > 1 {
                            HStack {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Primary muscle",
                                        norwegian: "Hovedmuskel"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Spacer()

                                Picker(
                                    ATHLTHLocalization.choose(
                                        english: "Primary muscle",
                                        norwegian: "Hovedmuskel"
                                    ),
                                    selection: Binding(
                                        get: {
                                            primaryMuscle ??
                                                selectedMuscles.sorted().first ??
                                                ""
                                        },
                                        set: { primaryMuscle = $0 }
                                    )
                                ) {
                                    ForEach(
                                        Self.muscleOptions.filter {
                                            selectedMuscles.contains($0.id)
                                        }
                                    ) { muscle in
                                        Text(muscle.title).tag(muscle.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }

                        if !selectedMuscles.isEmpty {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Editable exercise suggestions can be included in the proposed strength days. You choose the final programme.",
                                    norwegian: "Redigerbare øvelsesforslag kan legges i styrkeøktene. Du bestemmer det endelige programmet."
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }
                }
            }

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english:
                                "Injuries or limitations",
                            norwegian:
                                "Skader eller begrensninger"
                        )
                    )

                    HStack(spacing: 8) {
                        choicePill(
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "No known issues",
                                    norwegian:
                                        "Ingen kjente"
                                ),
                            icon:
                                "checkmark.circle.fill",
                            selected: injuryFree
                        ) {
                            injuryFree = true
                        }

                        choicePill(
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "I have something to consider",
                                    norwegian:
                                        "Har skade / hensyn"
                                ),
                            icon:
                                "cross.case.fill",
                            selected: !injuryFree
                        ) {
                            injuryFree = false
                        }
                    }

                    if !injuryFree {
                        TextField(
                            ATHLTHLocalization.choose(
                                english:
                                    "Describe what the plan should account for",
                                norwegian:
                                    "Beskriv hva planen skal ta hensyn til"
                            ),
                            text:
                                $injuriesOrLimitations,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            ATHLTHTheme
                                .premiumGoldSoft
                                .opacity(0.50),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "ATHLTH treats this as planning context, not medical advice.",
                                norwegian:
                                    "ATHLTH bruker dette som planleggingsinformasjon, ikke som medisinsk rådgivning."
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }
            }

            if mode == .advanced {
                builderPanel {
                    VStack(spacing: 12) {
                        Toggle(
                            ATHLTHLocalization.choose(
                                english:
                                    "Competition / target date",
                                norwegian:
                                    "Konkurranse / måldato"
                            ),
                            isOn:
                                $hasCompetitionDate
                        )

                        if hasCompetitionDate {
                            DatePicker(
                                ATHLTHLocalization.choose(
                                    english: "Target date",
                                    norwegian: "Måldato"
                                ),
                                selection:
                                    $competitionDate,
                                in: startDate...,
                                displayedComponents:
                                    .date
                            )
                        }
                    }
                }
            }
        }
    }

    private var focusGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(
                TrainingPlanFocus.allCases
            ) { item in
                Button {
                    focus = item

                    if secondaryFocus == item {
                        secondaryFocus = nil
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(
                            systemName:
                                item.systemImage
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28)

                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(
                        focus == item
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 11)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48
                    )
                    .background(
                        focus == item
                            ? ATHLTHTheme.accentDeep
                            : Color.white.opacity(0.72),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var advancedFocusControls: some View {
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
                            english:
                                "Secondary focus",
                            norwegian:
                                "Sekundærfokus"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Optional for hybrid goals",
                            norwegian:
                                "Valgfritt ved kombinerte mål"
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()

                Menu {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "None",
                            norwegian: "Ingen"
                        )
                    ) {
                        secondaryFocus = nil
                    }

                    ForEach(
                        TrainingPlanFocus.allCases
                            .filter {
                                $0 != focus
                            }
                    ) { item in
                        Button(item.title) {
                            secondaryFocus = item
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(
                            secondaryFocus?.title ??
                            ATHLTHLocalization.choose(
                                english: "None",
                                norwegian: "Ingen"
                            )
                        )
                        .lineLimit(1)

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
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Capsule()
                    )
                }
            }

            if let secondaryFocus {
                HStack {
                    Text(focus.title)
                        .font(.caption.weight(.semibold))

                    Spacer()

                    Text(
                        "\(focusWeight) / \(100 - focusWeight)"
                    )
                    .font(
                        .caption.monospacedDigit()
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )

                    Spacer()

                    Text(secondaryFocus.title)
                        .font(.caption.weight(.semibold))
                }

                Slider(
                    value:
                        Binding(
                            get: {
                                Double(focusWeight)
                            },
                            set: {
                                focusWeight =
                                    Int($0)
                            }
                        ),
                    in: 50...90,
                    step: 5
                )
                .tint(ATHLTHTheme.accentDeep)
            }
        }
    }

    private var goalGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(
                TrainingPlanGoalType.allCases
            ) { item in
                Button {
                    goal = item
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(
                                goal == item
                                    ? Color.white
                                    : ATHLTHTheme
                                        .accent
                                        .opacity(0.12)
                            )
                            .frame(width: 23, height: 23)
                            .overlay {
                                if goal == item {
                                    Image(
                                        systemName:
                                            "checkmark"
                                    )
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(
                                        ATHLTHTheme.accentDeep
                                    )
                                }
                            }

                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(
                        goal == item
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .padding(.horizontal, 10)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48
                    )
                    .background(
                        goal == item
                            ? ATHLTHTheme.accentDeep
                            : Color.white.opacity(0.72),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var showMusclePriorities: Bool {
        focus == .hypertrophy ||
        focus == .strength ||
        goal == .buildMuscle ||
        goal == .getStronger
    }

    private var muscleGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 86), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(
                Self.muscleOptions
            ) { muscle in
                let selected =
                    selectedMuscles
                        .contains(muscle.id)

                Button {
                    if selected {
                        selectedMuscles.remove(muscle.id)
                        if primaryMuscle == muscle.id {
                            primaryMuscle = selectedMuscles.sorted().first
                        }
                    } else {
                        selectedMuscles.insert(muscle.id)
                        if primaryMuscle == nil {
                            primaryMuscle = muscle.id
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if selected {
                            Image(
                                systemName: primaryMuscle == muscle.id
                                    ? "star.fill"
                                    : "checkmark"
                            )
                            .font(.system(size: 10, weight: .bold))
                        }
                        Text(muscle.title)
                            .font(.caption.weight(.semibold))
                    }
                        .foregroundStyle(
                            selected
                                ? Color.white
                                : ATHLTHTheme.primaryText
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 39
                        )
                        .background(
                            selected
                                ? ATHLTHTheme.accentDeep
                                : ATHLTHTheme.accentSoft,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if selected && primaryMuscle != muscle.id {
                        Button {
                            primaryMuscle = muscle.id
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Set as primary focus",
                                    norwegian: "Velg som hovedfokus"
                                ),
                                systemImage: "star.fill"
                            )
                        }
                    }
                }
            }
        }
    }

    private func choicePill(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(
                selected
                    ? Color.white
                    : ATHLTHTheme.primaryText
            )
            .padding(.horizontal, 10)
            .frame(
                maxWidth: .infinity,
                minHeight: 44
            )
            .background(
                selected
                    ? ATHLTHTheme.accentDeep
                    : Color.white.opacity(0.72),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }


    // Quick week planning and day-by-day planning share one persisted date model.
    private var guidedCurrentWeek: Int { min(guidedDayCursor / 7, max(0, weekCount - 1)) }

    private var guidedCurrentDate: Date {
        Calendar.current.date(
            byAdding: .day, value: min(guidedDayCursor, weekCount * 7 - 1),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private var guidedCurrentWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: guidedCurrentDate)
        return (weekday + 5) % 7 + 1
    }

    private var guidedChosenDays: Set<Int> {
        Set(weekDayEdits.compactMap { key, edit in
            edit.isRestDay == true || edit.detailedWorkout?.isValid != true
                ? nil : ((key - 1) % 7 + 1)
        })
    }

    private var guidedWeekStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(ATHLTHLocalization.choose(english: "DAY-BY-DAY PLAN", norwegian: "DAG-FOR-DAG-PLAN"))
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                Spacer()
                Button(ATHLTHLocalization.choose(english: "Switch to week view", norwegian: "Bytt til ukeoversikt")) {
                    selectedPlanWeekIndex = guidedCurrentWeek
                    weekPlanningApproach = .quick
                }
                .font(.caption.weight(.semibold))
            }
            if guidedDayCursor >= weekCount * 7 {
                builderPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(ATHLTHLocalization.choose(english: "Your plan is ready", norwegian: "Planen er klar"),
                              systemImage: "checkmark.seal.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "Review the planned workouts before you save the complete period.",
                            norwegian: "Se gjennom øktene før du lagrer hele treningsperioden."
                        ))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            } else if guidedDayCursor == 7 && !firstGuidedWeekDecisionMade {
                guidedFirstWeekDecision
            } else {
                guidedCurrentDayCard
            }
        }
    }

    private var guidedWeekNavigator: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    guidedDayCursor = max(0, guidedDayCursor - 7)
                } label: {
                    Label(ATHLTHLocalization.choose(english: "Previous week", norwegian: "Forrige uke"),
                          systemImage: "chevron.left")
                }
                .disabled(guidedCurrentWeek == 0)
                Spacer()
                Text(ATHLTHLocalization.choose(english: "Week", norwegian: "Uke") +
                     " \(guidedCurrentWeek + 1) / \(weekCount)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button {
                    guidedDayCursor = min(weekCount * 7 - 1, guidedDayCursor + 7)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(guidedCurrentWeek >= weekCount - 1)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Next week", norwegian: "Neste uke"))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.ink)

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    let date = Calendar.current.date(byAdding: .day,
                        value: guidedCurrentWeek * 7 + index, to: startDate) ?? startDate
                    let weekday = (Calendar.current.component(.weekday, from: date) + 5) % 7 + 1
                    let key = weekDayKey(weekday, weekIndex: guidedCurrentWeek)
                    let edit = weekDayEdits[key]
                    Button {
                        guidedDayCursor = guidedCurrentWeek * 7 + index
                    } label: {
                        VStack(spacing: 7) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2.weight(.bold))
                            Image(systemName: edit?.isRestDay == true
                                  ? "moon.stars.fill"
                                  : edit?.detailedWorkout?.isValid == true
                                  ? (edit?.detailedWorkout.map { guidedWorkoutIcon(for: $0) } ?? "figure.run")
                                  : "circle.dotted")
                                .font(.caption)
                        }
                        .foregroundStyle(guidedDayCursor % 7 == index
                                         ? .white : ATHLTHPlanDesign.ink)
                        .frame(maxWidth: .infinity, minHeight: 57)
                        .background(
                            guidedDayCursor % 7 == index
                                ? ATHLTHPlanDesign.ink : ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Day", norwegian: "Dag") + " \(date.formatted(.dateTime.day().month()))")
                }
            }
        }
    }

    private func setGuidedWorkoutStart(index: Int, minute: Int?) {
        let key = weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)
        guard var edit = weekDayEdits[key], let primary = edit.detailedWorkout else { return }
        var workouts = [primary] + (edit.additionalDetailedWorkouts ?? [])
        guard workouts.indices.contains(index) else { return }
        workouts[index].startMinuteOfDay = minute
        edit.detailedWorkout = workouts[0]
        edit.additionalDetailedWorkouts = Array(workouts.dropFirst())
        weekDayEdits[key] = edit
    }

    private func planCopyDayOptions(
        excluding sourceDay: Int, sourceWeekIndex: Int
    ) -> [ATHLTHPlanCopyDay] {
        let sourceKey = weekDayKey(sourceDay, weekIndex: sourceWeekIndex)
        return (0..<weekCount).flatMap { week in
            (1...7).map { weekday in
                let key = weekDayKey(weekday, weekIndex: week)
                let edit = weekDayEdits[key]
                return ATHLTHPlanCopyDay(
                    weekIndex: week,
                    weekday: weekday,
                    date: dateForWeekDay(weekday, weekIndex: week),
                    hasWorkout: edit?.detailedWorkout != nil ||
                        !(edit?.additionalDetailedWorkouts ?? []).isEmpty ||
                        (selectedDays.contains(weekday) && edit?.isRestDay != true),
                    isSource: key == sourceKey
                )
            }
        }
    }

    private func copyComposedWorkout(
        name: String,
        blocks: [WorkoutTemplateBlock],
        routeID: UUID?,
        duration: Int?,
        targets: [Int],
        sourceDay: Int,
        sourceWeek: Int
    ) -> Bool {
        guard !targets.isEmpty,
              let duration, (1...240).contains(duration) else { return false }
        let proposed = ATHLTHPlanStructuredWorkoutBlueprint(
            title: name,
            kind: workoutKind(for: blocks),
            durationMinutes: duration,
            routeID: routeID,
            blocks: blocks
        )
        guard proposed.isValid else { return false }
        let sourceKey = weekDayKey(sourceDay, weekIndex: sourceWeek)
        guard targets.allSatisfy({
            $0 != sourceKey && $0 >= 1 && $0 <= weekCount * 7
        }) else { return false }

        // Do not replace a planned session. Every destination keeps its own
        // workout when it already has one, and copies can span plan weeks.
        for key in targets {
            let weekday = (key - 1) % 7 + 1
            var edit = weekDayEdits[key] ?? ATHLTHPlanWeekDayEdit()
            // Preferred weekdays may already contain a generated session even
            // before a specific day edit exists. Append rather than overwrite it.
            let hasOriginal = selectedDays.contains(weekday) && edit.isRestDay != true
            let hasDetailedWorkout = edit.detailedWorkout != nil
            edit.isRestDay = false
            edit.removeTemplateDetail = false
            if hasDetailedWorkout || hasOriginal {
                edit.additionalDetailedWorkouts =
                    (edit.additionalDetailedWorkouts ?? []) + [proposed]
            } else {
                edit.detailedWorkout = proposed
                edit.kind = proposed.kind
                edit.title = proposed.title
                edit.durationMinutes = proposed.durationMinutes
            }
            weekDayEdits[key] = edit
        }
        saveResumableDraft()
        return true
    }

    private func selectedWorkoutForEditor(day: Int) -> ATHLTHPlanStructuredWorkoutBlueprint? {
        let key = weekDayKey(day, weekIndex: selectedPlanWeekIndex)
        guard let edit = weekDayEdits[key], let primary = edit.detailedWorkout else {
            return effectiveDetailedWorkout(for: day)
        }
        let workouts = [primary] + (edit.additionalDetailedWorkouts ?? [])
        return workouts.indices.contains(editingWorkoutIndex)
            ? workouts[editingWorkoutIndex] : primary
    }

    private func moveGuidedWorkout(from index: Int, by offset: Int) {
        let key = weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)
        guard var edit = weekDayEdits[key], let primary = edit.detailedWorkout else { return }
        var workouts = [primary] + (edit.additionalDetailedWorkouts ?? [])
        let destination = index + offset
        guard workouts.indices.contains(index), workouts.indices.contains(destination) else { return }
        workouts.swapAt(index, destination)
        edit.detailedWorkout = workouts[0]
        edit.additionalDetailedWorkouts = Array(workouts.dropFirst())
        edit.kind = workouts[0].kind
        edit.title = workouts[0].title
        edit.durationMinutes = workouts[0].durationMinutes
        weekDayEdits[key] = edit
    }

    private func moveGuidedWorkout(to destinationDay: Int, index: Int) {
        let sourceKey = weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)
        let destinationKey = weekDayKey(destinationDay, weekIndex: guidedCurrentWeek)
        guard sourceKey != destinationKey,
              var source = weekDayEdits[sourceKey],
              let primary = source.detailedWorkout else { return }
        var sourceWorkouts = [primary] + (source.additionalDetailedWorkouts ?? [])
        guard sourceWorkouts.indices.contains(index) else { return }
        let moving = sourceWorkouts.remove(at: index)
        if let next = sourceWorkouts.first {
            source.detailedWorkout = next
            source.additionalDetailedWorkouts = Array(sourceWorkouts.dropFirst())
            source.kind = next.kind
            source.title = next.title
            source.durationMinutes = next.durationMinutes
        } else {
            // Explicitly mark the emptied date as rest. Otherwise the legacy
            // scheduler would manufacture a default 45-minute workout.
            source.detailedWorkout = nil
            source.additionalDetailedWorkouts = nil
            source.kind = nil
            source.title = nil
            source.durationMinutes = nil
            source.isRestDay = true
            source.removeTemplateDetail = true
        }
        weekDayEdits[sourceKey] = source

        var destination = weekDayEdits[destinationKey] ?? ATHLTHPlanWeekDayEdit()
        destination.isRestDay = false
        destination.removeTemplateDetail = false
        if destination.detailedWorkout == nil {
            destination.detailedWorkout = moving
            destination.kind = moving.kind
            destination.title = moving.title
            destination.durationMinutes = moving.durationMinutes
        } else {
            destination.additionalDetailedWorkouts =
                (destination.additionalDetailedWorkouts ?? []) + [moving]
        }
        weekDayEdits[destinationKey] = destination
    }

    // Move one independent block between existing sessions without dropping either
    // workout. Reject moves that would invalidate the source or destination.
    private func moveGuidedBlock(
        from sourceIndex: Int,
        blockIndex: Int,
        copy: Bool = false,
        to destinationDay: Int,
        workoutIndex: Int
    ) {
        let sourceKey = weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)
        let targetKey = weekDayKey(destinationDay, weekIndex: guidedCurrentWeek)
        guard let sourceEdit = weekDayEdits[sourceKey],
              let sourcePrimary = sourceEdit.detailedWorkout,
              let targetEdit = weekDayEdits[targetKey],
              let targetPrimary = targetEdit.detailedWorkout else { return }

        var sourceWorkouts = [sourcePrimary] + (sourceEdit.additionalDetailedWorkouts ?? [])
        var targetWorkouts = [targetPrimary] + (targetEdit.additionalDetailedWorkouts ?? [])
        guard sourceWorkouts.indices.contains(sourceIndex),
              targetWorkouts.indices.contains(workoutIndex),
              sourceWorkouts[sourceIndex].blocks.indices.contains(blockIndex),
              sourceKey != targetKey || sourceIndex != workoutIndex else { return }

        let selected = sourceWorkouts[sourceIndex].blocks[blockIndex]
        let sourceBlocks = sourceWorkouts[sourceIndex].blocks
        // Move a complete linked group together, retaining its internal order.
        // Unlinked blocks move individually.
        let movingIndices = sourceBlocks.indices.filter { candidate in
            if let group = selected.groupID {
                return sourceBlocks[candidate].groupID == group
            }
            return candidate == blockIndex
        }
        let movingBlocks = movingIndices.map { sourceBlocks[$0] }
        var updatedSource = sourceWorkouts[sourceIndex]
        if !copy {
            updatedSource.blocks = sourceBlocks.enumerated().compactMap {
                movingIndices.contains($0.offset) ? nil : $0.element
            }
        }
        var updatedTarget = targetWorkouts[workoutIndex]
        updatedTarget.blocks.append(contentsOf: movingBlocks)
        // An empty or otherwise invalid source requires explicit session
        // deletion instead; never silently lose a workout or break a superset.
        guard updatedSource.isValid, updatedTarget.isValid else { return }
        previousGuidedEdits = weekDayEdits
        // A move changes the recipe. Recalculate only when the estimator has
        // enough information; never replace a known duration with a guess.
        if let minutes = ATHLTHWorkoutDurationEstimator.minutes(for: updatedSource.blocks) {
            updatedSource.durationMinutes = minutes
        }
        if let minutes = ATHLTHWorkoutDurationEstimator.minutes(for: updatedTarget.blocks) {
            updatedTarget.durationMinutes = minutes
        }
        updatedSource.kind = workoutKind(for: updatedSource.blocks)
        updatedTarget.kind = workoutKind(for: updatedTarget.blocks)
        if updatedSource.kind != .running { updatedSource.routeID = nil }
        if updatedTarget.kind != .running { updatedTarget.routeID = nil }

        if sourceKey == targetKey {
            sourceWorkouts[sourceIndex] = updatedSource
            sourceWorkouts[workoutIndex] = updatedTarget
            var edit = sourceEdit
            edit.detailedWorkout = sourceWorkouts[0]
            edit.additionalDetailedWorkouts = Array(sourceWorkouts.dropFirst())
            edit.kind = sourceWorkouts[0].kind
            edit.title = sourceWorkouts[0].title
            edit.durationMinutes = sourceWorkouts[0].durationMinutes
            weekDayEdits[sourceKey] = edit
        } else {
            sourceWorkouts[sourceIndex] = updatedSource
            targetWorkouts[workoutIndex] = updatedTarget
            var source = sourceEdit
            source.detailedWorkout = sourceWorkouts[0]
            source.additionalDetailedWorkouts = Array(sourceWorkouts.dropFirst())
            source.kind = sourceWorkouts[0].kind
            source.title = sourceWorkouts[0].title
            source.durationMinutes = sourceWorkouts[0].durationMinutes
            var target = targetEdit
            target.detailedWorkout = targetWorkouts[0]
            target.additionalDetailedWorkouts = Array(targetWorkouts.dropFirst())
            target.kind = targetWorkouts[0].kind
            target.title = targetWorkouts[0].title
            target.durationMinutes = targetWorkouts[0].durationMinutes
            weekDayEdits[sourceKey] = source
            weekDayEdits[targetKey] = target
        }
    }

    private func guidedWorkoutIcon(
        for workout: ATHLTHPlanStructuredWorkoutBlueprint
    ) -> String {
        let strengthSteps = workout.blocks.filter { $0.kind == .exercise }.count
        let runSteps = workout.blocks.filter { $0.kind == .run }.count
        // A short running warm-up must not turn a strength workout into
        // an unrelated generic/check icon.
        if strengthSteps > 0 && strengthSteps >= runSteps {
            return WorkoutKind.strength.systemImage
        }
        return workout.kind.systemImage
    }

    /// Guided mode and quick week mode render exactly the same expandable
    /// workout card and phase-detail engine. Only navigation and creation
    /// actions differ: guided mode advances one explicitly planned day at a time.
    // Single authoritative advanced day screen, replacing the legacy
    // week-preview card while preserving the existing dated edit store.
    private var guidedCurrentDayCard: some View {
        ATHLTHAdvancedGuidedDayView(
            date: guidedCurrentDate,
            weekNumber: guidedCurrentWeek + 1,
            totalWeeks: weekCount,
            dayIndex: guidedDayCursor % 7,
            startDate: startDate,
            workouts: previewWorkouts(for: guidedCurrentWeekday),
            isRestDay: weekDayEdits[
                weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)
            ]?.isRestDay == true,
            onSelectDay: { offset in
                guidedDayCursor = min(weekCount * 7 - 1,
                    guidedCurrentWeek * 7 + offset)
            },
            onAddExercise: { phase, workoutIndex in
                advancedAddDestination = AdvancedAddDestination(
                    day: guidedCurrentWeekday, week: guidedCurrentWeek,
                    phase: phase, kind: .exercise, workoutIndex: workoutIndex)
            },
            onAddWorkout: {
                advancedAddDestination = AdvancedAddDestination(
                    day: guidedCurrentWeekday, week: guidedCurrentWeek,
                    phase: .main, kind: .workout)
            },
            onQuick: { quick in
                addAdvancedQuickContent(quick)
            },
            onEditWorkout: { index in
                selectedPlanWeekIndex = guidedCurrentWeek
                editPreviewWorkout(guidedCurrentWeekday, index: index)
            },
            onRestDay: { setRestDay(guidedCurrentWeekday) }
        )
    }

    private func insertGuidedLibraryExercise(
        _ blocks: [WorkoutTemplateBlock], day: Int, week: Int,
        workoutIndex: Int
    ) {
        guard !blocks.isEmpty else { return }
        let key = weekDayKey(day, weekIndex: week)
        var edit = weekDayEdits[key] ?? ATHLTHPlanWeekDayEdit()
        let extras = edit.additionalDetailedWorkouts ?? []
        let editingExtra = workoutIndex > 0 && extras.indices.contains(workoutIndex - 1)
        var workout = (editingExtra ? extras[workoutIndex - 1] : edit.detailedWorkout) ??
            ATHLTHPlanStructuredWorkoutBlueprint(
                title: ATHLTHLocalization.choose(
                    english: "Strength workout", norwegian: "Styrkeøkt"),
                kind: .strength, durationMinutes: 30, routeID: nil, blocks: [])
        for block in blocks {
            var next = WorkoutTemplateBlock(
                sequence: (workout.blocks.map(\.sequence).max() ?? 0) + 1,
                kind: block.kind, title: block.title,
                exerciseSlug: block.exerciseSlug,
                distanceMeters: block.distanceMeters,
                repetitions: block.repetitions,
                durationSeconds: block.durationSeconds,
                targetWeightKilograms: block.targetWeightKilograms,
                loadNote: block.loadNote, notes: block.notes,
                phase: block.phase
            )
            next.setCount = block.setCount
            next.restBetweenSetsSeconds = block.restBetweenSetsSeconds
            next.exerciseID = block.exerciseID
            next.exerciseSnapshot = block.exerciseSnapshot
            workout.blocks.append(next)
        }
        workout.kind = workoutKind(for: workout.blocks)
        if let estimate = ATHLTHWorkoutDurationEstimator.minutes(for: workout.blocks) {
            workout.durationMinutes = estimate
        }
        if editingExtra {
            var copies = extras
            copies[workoutIndex - 1] = workout
            edit.additionalDetailedWorkouts = copies
        } else {
            edit.detailedWorkout = workout
            edit.title = workout.title
            edit.kind = workout.kind
            edit.durationMinutes = workout.durationMinutes
        }
        edit.isRestDay = false
        edit.removeTemplateDetail = false
        weekDayEdits[key] = edit
        selectedDays.insert(day)
        sessionsPerWeek = selectedDays.count
    }

    private func insertGuidedLibraryWorkout(
        _ workout: PlannedSession, day: Int, week: Int
    ) {
        selectedPlanWeekIndex = week
        let existing = weekDayEdits[weekDayKey(day, weekIndex: week)]
        let addAsExtra = existing?.isRestDay != true &&
            existing?.detailedWorkout?.isValid == true
        assignLibraryWorkout(workout, to: day, asExtra: addAsExtra)
        if weekDayEdits[weekDayKey(day, weekIndex: week)]?.isRestDay == false {
            selectedDays.insert(day)
            sessionsPerWeek = selectedDays.count
        } else if weekDayEdits[weekDayKey(day, weekIndex: week)]?.detailedWorkout?.isValid == true {
            selectedDays.insert(day)
            sessionsPerWeek = selectedDays.count
        }
    }

    private func addAdvancedQuickContent(_ choice: String) {
        selectedPlanWeekIndex = guidedCurrentWeek
        let day = guidedCurrentWeekday
        switch choice {
        case "running": chooseQuickWorkout(.run, on: day)
        case "walking": chooseQuickWorkout(.walk, on: day)
        case "yoga": chooseQuickWorkout(.yoga, on: day)
        case "meditation": chooseQuickWorkout(.meditation, on: day)
        case "cycling", "interval", "superset":
            // Opens the real advanced workout composer with all available
            // cycling, interval and superset timeline tools.
            quickStudioOption = nil
            addingExtraWorkout = false
            editingWorkoutIndex = 0
            composingAdvancedDay = WeekDayEditorSelection(id: day)
        case "rest":
            let key = weekDayKey(day, weekIndex: guidedCurrentWeek)
            if var edit = weekDayEdits[key],
               var workout = edit.detailedWorkout, workout.isValid {
                let rest = WorkoutTemplateBlock(
                    sequence: (workout.blocks.map(\.sequence).max() ?? 0) + 1,
                    kind: .rest,
                    title: ATHLTHLocalization.choose(
                        english: "Rest", norwegian: "Pause"),
                    exerciseSlug: nil, distanceMeters: nil,
                    repetitions: nil, durationSeconds: 90,
                    targetWeightKilograms: nil, loadNote: nil,
                    notes: nil, phase: .main
                )
                workout.blocks.append(rest)
                edit.detailedWorkout = workout
                weekDayEdits[key] = edit
            } else {
                setRestDay(day)
            }
        default:
            advancedAddDestination = AdvancedAddDestination(
                day: day, week: guidedCurrentWeek,
                phase: .main, kind: .exercise)
        }
    }

    private var guidedFirstWeekDecision: some View {
        VStack(alignment: .leading, spacing: 15) {
            stepIntro(
                eyebrow: ATHLTHLocalization.choose(english: "WEEK 1 COMPLETE", norwegian: "UKE 1 ER FERDIG"),
                title: ATHLTHLocalization.choose(english: "How will you plan the rest?", norwegian: "Hvordan planlegger vi resten?"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Reuse the workouts you built, or customize every following day.",
                    norwegian: "Gjenbruk øktene du har laget, eller tilpass hver dag i ukene fremover."
                ),
                icon: "checkmark.seal"
            )
            builderPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(firstWeekWorkoutCount) " +
                         ATHLTHLocalization.choose(english: "workouts", norwegian: "økter") +
                         " · \(7 - firstWeekTrainingDayCount) " +
                         ATHLTHLocalization.choose(english: "rest days", norwegian: "hviledager"))
                        .font(.headline)
                    Text(ATHLTHLocalization.choose(
                        english: "Copies are independent. Changing a date later will not change your original week.",
                        norwegian: "Hver uke kan redigeres separat etter kopiering."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            ATHLTHPlanWeekApproachCard(
                icon: "rectangle.on.rectangle",
                title: ATHLTHLocalization.choose(english: "Copy to all remaining weeks", norwegian: "Kopier til alle resterende uker"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Use week one as the starting point throughout the plan.",
                    norwegian: "Bruk uke én som utgangspunkt for hele perioden."
                )
            ) {
                copyFirstGuidedWeek(toCount: weekCount - 1)
            }
            builderPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ATHLTHLocalization.choose(english: "Copy to selected weeks", norwegian: "Kopier til et antall uker"))
                        .font(.subheadline.weight(.semibold))
                    Stepper(
                        "\(repeatWeekCount) " + ATHLTHLocalization.choose(english: "weeks", norwegian: "uker"),
                        value: $repeatWeekCount, in: 1...max(1, weekCount - 1)
                    )
                    Button(ATHLTHLocalization.choose(english: "Copy and continue", norwegian: "Kopier og fortsett")) {
                        copyFirstGuidedWeek(toCount: repeatWeekCount)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            ATHLTHPlanWeekApproachCard(
                icon: "arrow.right",
                title: ATHLTHLocalization.choose(english: "Continue day by day", norwegian: "Fortsett dag for dag"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Start building week two without copying.",
                    norwegian: "Begynn på uke to uten å kopiere noe."
                )
            ) {
                firstGuidedWeekDecisionMade = true
                selectedPlanWeekIndex = 1
            }
            ATHLTHPlanWeekApproachCard(
                icon: "calendar",
                title: ATHLTHLocalization.choose(english: "Plan freely in week view", norwegian: "Planlegg fritt i ukeoversikten"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Keep the first week and switch to the calendar overview.",
                    norwegian: "Behold første uke og fortsett i kalenderen."
                )
            ) {
                firstGuidedWeekDecisionMade = true
                selectedPlanWeekIndex = 1
                weekPlanningApproach = .quick
            }
        }
    }

    private var firstWeekTrainingDayCount: Int {
        (1...7).filter {
            let edit = weekDayEdits[weekDayKey($0, weekIndex: 0)]
            return edit?.isRestDay != true && edit?.detailedWorkout?.isValid == true
        }.count
    }

    private var firstWeekWorkoutCount: Int {
        (1...7).reduce(0) { total, day in
            guard let edit = weekDayEdits[weekDayKey(day, weekIndex: 0)],
                  edit.isRestDay != true,
                  edit.detailedWorkout?.isValid == true else { return total }
            return total + 1 + (edit.additionalDetailedWorkouts?.count ?? 0)
        }
    }

    private func advanceGuidedDay() {
        guard guidedDayCursor < weekCount * 7,
              ATHLTHGuidedPlanDayPolicy.isPlanned(
                weekDayEdits[weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)]
              ) else { return }
        guidedDayCursor += 1
        if guidedDayCursor == 7 {
            // A manually built plan only uses the days actually chosen in week one.
            let days = Set((1...7).filter {
                let edit = weekDayEdits[weekDayKey($0, weekIndex: 0)]
                return edit?.isRestDay != true && edit?.detailedWorkout?.isValid == true
            })
            if !days.isEmpty {
                selectedDays = days
                sessionsPerWeek = days.count
            }
            if weekCount == 1 { firstGuidedWeekDecisionMade = true }
        }
    }

    private func copyFirstGuidedWeek(toCount count: Int) {
        guard count > 0 else { return }
        for week in 1...min(count, weekCount - 1) {
            for day in 1...7 {
                let destination = weekDayKey(day, weekIndex: week)
                guard weekDayEdits[destination] == nil,
                      let source = weekDayEdits[weekDayKey(day, weekIndex: 0)] else { continue }
                weekDayEdits[destination] = source
            }
        }
        firstGuidedWeekDecisionMade = true
        guidedDayCursor = min((count + 1) * 7, weekCount * 7)
        selectedPlanWeekIndex = min(guidedCurrentWeek, weekCount - 1)
    }

    private func quickDaySeed(_ option: QuickDayOption) -> [WorkoutTemplateBlock] {
        if option == .strength { return [] }
        if option == .run || option == .walk {
            var run = WorkoutTemplateBlock(
                sequence: 1, kind: .run, title: option.title,
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil,
                durationSeconds: option == .run ? 1_200 : 1_800,
                targetWeightKilograms: nil, loadNote: nil,
                notes: nil, phase: .main
            )
            run.cardioActivity = option == .run ? .running : .walking
            return [run]
        }
        let wellness: WorkoutWellnessKind = {
            switch option {
            case .meditation: return .meditation
            case .stretching: return .stretching
            case .yoga: return .yoga
            default: return .mobility
            }
        }()
        var block = WorkoutTemplateBlock(
            sequence: 1, kind: .note, title: option.title,
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: wellness == .meditation ? 300 :
                wellness == .yoga ? 900 : 600,
            targetWeightKilograms: nil, loadNote: nil,
            notes: nil, phase: wellness == .meditation ? .recovery : .main
        )
        block.wellnessKind = wellness
        return [block]
    }

    private func chooseQuickWorkout(_ option: QuickDayOption, on day: Int) {
        quickStudioOption = option
        addingExtraWorkout = false
        editingWorkoutIndex = 0
        if editingWeekDay != nil {
            pendingStudioDay = WeekDayEditorSelection(id: day)
            editingWeekDay = nil
        } else {
            selectedPlanWeekIndex = guidedCurrentWeek
            composingAdvancedDay = WeekDayEditorSelection(id: day)
        }
    }

    private func quickDayChoiceGrid(for day: Int) -> some View {
        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(ATHLTHLocalization.choose(
                        english: "Quick choice", norwegian: "Hurtigvalg"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(ATHLTHLocalization.choose(
                        english: "Edit freely afterwards", norwegian: "Rediger etterpå"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 8) {
                    ForEach(QuickDayOption.allCases) { option in
                        Button {
                            chooseQuickWorkout(option, on: day)
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 18, weight: .medium))
                                Text(option.title)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .frame(maxWidth: .infinity, minHeight: 61)
                            .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func setRestDay(_ day: Int) {
        updateWeekDay(day) { edit in
            edit.isRestDay = true
            edit.detailedWorkout = nil
            edit.title = nil
            edit.kind = nil
            edit.durationMinutes = nil
            edit.removeTemplateDetail = true
            edit.additionalDetailedWorkouts = nil
            edit.trainingPlace = nil
        }
    }

    private func workoutKind(for blocks: [WorkoutTemplateBlock]) -> WorkoutKind {
        let runs = blocks.filter { $0.kind == .run }
        let hasStrength = blocks.contains { $0.kind == .exercise }
        let hasRunning = runs.contains { $0.cardioActivity != .walking }
        let hasWalking = runs.contains { $0.cardioActivity == .walking }
        let hasCycling = blocks.contains { $0.activityTag == "cycling" }
        let hasWellness = blocks.contains { $0.wellnessKind != nil }
        if [hasRunning, hasWalking, hasStrength, hasCycling, hasWellness]
            .filter({ $0 }).count > 1 {
            return .custom
        }
        if hasRunning { return .running }
        if hasWalking { return .walking }
        // Cycling has its own category, but WorkoutKind has no cycling case.
        // Never label a cycling-only session as strength.
        if blocks.contains(where: { $0.activityTag == "cycling" }) {
            return .custom
        }
        let wellness = blocks.compactMap(\.wellnessKind)
        if !wellness.isEmpty {
            return wellness.allSatisfy { $0 == .meditation } ? .recovery : .mobility
        }
        return .strength
    }

    private func assignLibraryWorkout(_ workout: PlannedSession, to day: Int, asExtra: Bool) {
        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        let blueprint = ATHLTHPlanStructuredWorkoutBlueprint(
            title: workout.title,
            kind: workoutKind(for: blocks),
            durationMinutes: workout.durationMinutes ?? 45,
            routeID: workout.routeID,
            blocks: blocks
        )
        guard blueprint.isValid else {
            creationError = ATHLTHLocalization.choose(
                english: "This workout has no editable exercise or running steps.",
                norwegian: "Denne økten mangler øvelser eller løpesteg som kan planlegges."
            )
            return
        }
        updateWeekDay(day) { edit in
            edit.isRestDay = false
            if asExtra {
                edit.additionalDetailedWorkouts = (edit.additionalDetailedWorkouts ?? []) + [blueprint]
            } else {
                edit.detailedWorkout = blueprint
                edit.kind = blueprint.kind
                edit.title = blueprint.title
                edit.durationMinutes = blueprint.durationMinutes
            }
            edit.removeTemplateDetail = false
        }
    }

    private func planDayActionsSheet(for day: Int) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    ATHLTHPlanSectionIntro(
                        eyebrow: dateForWeekDay(day, weekIndex: selectedPlanWeekIndex)
                            .formatted(.dateTime.weekday(.wide).day().month(.wide)),
                        title: ATHLTHLocalization.choose(
                            english: "Plan this day", norwegian: "Planlegg denne dagen"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Choose a full workout, build your own or set a rest day.",
                            norwegian: "Velg en komplett økt, bygg en egen eller legg inn hviledag."
                        ),
                        icon: "calendar.day.timeline.left"
                    )
                    if let edit = weekDayEdits[weekDayKey(day)] {
                        Text(edit.isRestDay == true
                             ? ATHLTHLocalization.choose(english: "Rest day", norwegian: "Hviledag")
                             : (edit.detailedWorkout?.title ?? effectiveWorkoutTitle(for: day)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    if weekDayEdits[weekDayKey(day)]?.detailedWorkout == nil {
                        quickDayChoiceGrid(for: day)
                    }
                    ATHLTHPlanWeekApproachCard(
                        icon: "mappin.and.ellipse",
                        title: weekDayEdits[weekDayKey(day)]?.trainingPlace?.name ??
                            ATHLTHLocalization.choose(
                                english: "Training place (optional)",
                                norwegian: "Treningssted (valgfritt)"),
                        subtitle: weekDayEdits[weekDayKey(day)]?.trainingPlace?.address
                            .isEmpty == false
                            ? (weekDayEdits[weekDayKey(day)]?.trainingPlace?.address ?? "")
                            : ATHLTHLocalization.choose(
                                english: "Address, gym, hotel, sports ground or favorites.",
                                norwegian: "Adresse, senter, hotell, idrettsanlegg eller favoritter.")
                    ) {
                        reopenDayAfterPlace = WeekDayEditorSelection(id: day)
                        pendingTrainingPlaceDay = WeekDayEditorSelection(id: day)
                        editingWeekDay = nil
                    }
                    if let dayEdit = weekDayEdits[weekDayKey(day)],
                       dayEdit.isRestDay != true, let primary = dayEdit.detailedWorkout {
                        ATHLTHPlanSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(ATHLTHLocalization.choose(
                                    english: "PLANNED WORKOUT", norwegian: "PLANLAGT ØKT"))
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.2)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                ForEach(Array(([primary] +
                                    (dayEdit.additionalDetailedWorkouts ?? [])).enumerated()),
                                        id: \.offset) { entry in
                                    let index = entry.offset
                                    let workout = entry.element
                                    Button {
                                        editingWorkoutIndex = index
                                        addingExtraWorkout = false
                                        pendingStudioDay = WeekDayEditorSelection(id: day)
                                        editingWeekDay = nil
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(workout.title)
                                                        .font(.headline)
                                                    Text("\(workout.durationMinutes) min · \(workout.blocks.count) " +
                                                         ATHLTHLocalization.choose(
                                                            english: "steps", norwegian: "steg"))
                                                        .font(.caption)
                                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                                }
                                                Spacer()
                                                Image(systemName: "square.and.pencil")
                                            }
                                            ForEach(WorkoutPhaseKind.allCases) { phase in
                                                let count = workout.blocks.filter {
                                                    $0.resolvedPhase == phase
                                                }.count
                                                if count > 0 {
                                                    Label(phase.title + " · \(count)",
                                                          systemImage: phase.symbol)
                                                        .font(.caption)
                                                }
                                            }
                                            Text(ATHLTHLocalization.choose(
                                                english: "Tap to edit exercises, warm-up, intervals, pace and heart-rate zones.",
                                                norwegian: "Trykk for å redigere øvelser, oppvarming, intervaller, tempo og pulssoner."))
                                                .font(.caption2)
                                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                        }
                                        .foregroundStyle(ATHLTHPlanDesign.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    ATHLTHPlanWeekApproachCard(
                        icon: "plus.circle",
                        title: ATHLTHLocalization.choose(english: "Build planned workout", norwegian: "Bygg planlagt økt"),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Create a detailed workout in ATHLTH Studio.",
                            norwegian: "Lag en detaljert treningsøkt i ATHLTH Studio."
                        )
                    ) {
                        addingExtraWorkout = false
                        pendingStudioDay = WeekDayEditorSelection(id: day)
                        editingWeekDay = nil
                    }
                    ATHLTHPlanWeekApproachCard(
                        icon: "books.vertical",
                        title: ATHLTHLocalization.choose(english: "Choose complete workout", norwegian: "Velg komplett treningsøkt"),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Find saved workouts with all exercises and intervals.",
                            norwegian: "Hent lagrede økter med alle øvelser og intervaller."
                        )
                    ) {
                        selectingExtraFromLibrary = false
                        pendingLibraryDay = WeekDayEditorSelection(id: day)
                        editingWeekDay = nil
                    }
                    if weekDayEdits[weekDayKey(day)]?.detailedWorkout != nil {
                        ATHLTHPlanWeekApproachCard(
                            icon: "plus.square.on.square",
                            title: ATHLTHLocalization.choose(english: "Add another workout", norwegian: "Legg til en ekstra økt"),
                            subtitle: ATHLTHLocalization.choose(
                                english: "Create a second workout on this day.",
                                norwegian: "Bygg en ny økt samme dag."
                            )
                        ) {
                            addingExtraWorkout = true
                            pendingStudioDay = WeekDayEditorSelection(id: day)
                            editingWeekDay = nil
                        }
                        ATHLTHPlanWeekApproachCard(
                            icon: "books.vertical",
                            title: ATHLTHLocalization.choose(english: "Add another from library", norwegian: "Legg til en ekstra økt fra bibliotek"),
                            subtitle: ATHLTHLocalization.choose(
                                english: "Choose an existing full workout.",
                                norwegian: "Velg en eksisterende komplett økt."
                            )
                        ) {
                            selectingExtraFromLibrary = true
                            pendingLibraryDay = WeekDayEditorSelection(id: day)
                            editingWeekDay = nil
                        }
                    }
                    ATHLTHPlanWeekApproachCard(
                        icon: "moon.stars",
                        title: ATHLTHLocalization.choose(english: "Rest day", norwegian: "Hviledag"),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Leave this date empty.",
                            norwegian: "La denne dagen være uten treningsøkt."
                        )
                    ) {
                        setRestDay(day)
                        editingWeekDay = nil
                    }
                }
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(english: "Planned day", norwegian: "Planlagt dag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")) {
                        editingWeekDay = nil
                    }
                }
            }
        }
    }

    // Advanced → Week-by-week is a new single surface. The original
    // weekStep is retained exclusively for the Simple/legacy route.
    private var advancedWeekBuilderStep: some View {
        ATHLTHAdvancedWeekBuilderView(
            selectedWeek: $selectedPlanWeekIndex,
            weekCount: $weekCount,
            startDate: startDate,
            days: advancedWeekItems(for: selectedPlanWeekIndex),
            workoutsPerWeek: (0..<weekCount).map {
                advancedWeekItems(for: $0).reduce(0) { $0 + $1.workouts.count }
            },
            weekSymbols: (0..<weekCount).map { index in
                advancedWeekItems(for: index)
                    .sorted(by: { $0.date < $1.date })
                    .map { day in
                        day.isRestDay ? "moon.stars" :
                        day.kind?.systemImage ?? (day.planned ? "plus.circle" : "moon.stars")
                    }
            },
            onEditWorkout: { day, workoutIndex in
                editPreviewWorkout(day, index: workoutIndex)
            },
            onAddExercise: { day, workoutIndex, phase in
                advancedAddDestination = AdvancedAddDestination(
                    day: day, week: selectedPlanWeekIndex, phase: phase,
                    kind: .exercise, workoutIndex: workoutIndex)
            },
            onAddWorkout: { day in
                advancedAddDestination = AdvancedAddDestination(
                    day: day, week: selectedPlanWeekIndex,
                    phase: .main, kind: .workout)
            },
            onMarkRest: { day in
                setRestDay(day)
            },
            onQuick: { day, choice in
                addAdvancedWeekQuickContent(day: day, choice: choice)
            },
            onCopyWeek: { source, destinations, overwrite in
                copyAdvancedWeek(from: source, to: destinations, overwrite: overwrite)
            },
            onMakeRecoveryWeek: { week in
                let current = selectedPlanWeekIndex
                selectedPlanWeekIndex = week
                for day in 1...7 { setRestDay(day) }
                selectedPlanWeekIndex = current
            }
        )
    }

    private func advancedWeekItems(for week: Int) -> [ATHLTHAdvancedWeekBuilderView.Day] {
        (1...7).map { weekday in
            let edit = weekDayEdits[weekDayKey(weekday, weekIndex: week)]
            let primary = edit?.detailedWorkout ??
                (edit?.removeTemplateDetail == true
                    ? nil : structuredWorkoutsByDay[weekday])
            let extras = edit?.additionalDetailedWorkouts ?? []
            let planned = selectedDays.contains(weekday) ||
                edit?.kind != nil || edit?.title != nil ||
                primary != nil || !extras.isEmpty
            let isRest = edit?.isRestDay == true ||
                (!planned && primary == nil && extras.isEmpty)
            return ATHLTHAdvancedWeekBuilderView.Day(
                weekday: weekday,
                date: dateForWeekDay(weekday, weekIndex: week),
                isRestDay: isRest,
                workouts: isRest ? [] : ([primary].compactMap { $0 } + extras),
                suggestedTitle: edit?.title ?? workoutTitleOverridesByDay[weekday],
                planned: planned
            )
        }
    }

    private func copyAdvancedWeek(from source: Int, to destinations: [Int],
                                  overwrite: Bool) {
        guard (0..<weekCount).contains(source) else { return }
        let targets = Set(destinations).filter {
            (0..<weekCount).contains($0) && $0 != source
        }
        for week in targets {
            for weekday in 1...7 {
                let fromKey = weekDayKey(weekday, weekIndex: source)
                let toKey = weekDayKey(weekday, weekIndex: week)
                if !overwrite && weekDayEdits[toKey] != nil {
                    // Protect each individually edited destination day.
                    continue
                }
                if let sourceEdit = weekDayEdits[fromKey] {
                    weekDayEdits[toKey] = sourceEdit
                } else if overwrite {
                    // Remove its override to restore the unchanged base
                    // pattern; do not accidentally fabricate a workout.
                    weekDayEdits.removeValue(forKey: toKey)
                }
            }
        }
        saveResumableDraft()
    }

    private func addAdvancedWeekQuickContent(day: Int, choice: String) {
        switch choice {
        case "running": chooseQuickWorkout(.run, on: day)
        case "walking": chooseQuickWorkout(.walk, on: day)
        case "yoga": chooseQuickWorkout(.yoga, on: day)
        case "meditation": chooseQuickWorkout(.meditation, on: day)
        case "cycling", "interval", "superset":
            // The shared Studio owns the detailed cycling/interval/
            // superset timeline and can append another session.
            quickStudioOption = nil
            editingWorkoutIndex = 0
            addingExtraWorkout = !previewWorkouts(for: day).isEmpty
            composingAdvancedDay = WeekDayEditorSelection(id: day)
        case "rest":
            let key = weekDayKey(day)
            guard var edit = weekDayEdits[key],
                  var workout = edit.detailedWorkout else {
                composingAdvancedDay = WeekDayEditorSelection(id: day)
                return
            }
            workout.blocks.append(WorkoutTemplateBlock(
                sequence: (workout.blocks.map(\.sequence).max() ?? 0) + 1,
                kind: .rest,
                title: ATHLTHLocalization.choose(english: "Rest", norwegian: "Pause"),
                exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
                durationSeconds: 90, targetWeightKilograms: nil,
                loadNote: nil, notes: nil, phase: .main
            ))
            edit.detailedWorkout = workout
            weekDayEdits[key] = edit
        default:
            advancedAddDestination = AdvancedAddDestination(
                day: day, week: selectedPlanWeekIndex,
                phase: .main, kind: .exercise)
        }
    }

    private var weekStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            stepIntro(
                eyebrow:
                    ATHLTHLocalization.choose(
                        english: "03 · TRAINING WEEK",
                        norwegian: "03 · TRENINGSUKEN"
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "Choose when you train",
                        norwegian: "Velg når du vil trene"
                    ),
                subtitle:
                    mode == .basic
                    ? ATHLTHLocalization.choose(
                        english:
                            "Pick the number of sessions. ATHLTH spreads them across the week and keeps the other days as rest.",
                        norwegian:
                            "Velg antall økter. ATHLTH fordeler dem gjennom uken og lar resten være hviledager."
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Choose the exact training days and define the practical limits around the week.",
                        norwegian:
                            "Velg eksakte treningsdager og legg inn rammene rundt treningsuken."
                    ),
                icon:
                    "calendar.day.timeline.left"
            )

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            fieldLabel(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Sessions per week",
                                    norwegian:
                                        "Økter per uke"
                                )
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Rest days stay visible in the plan.",
                                    norwegian:
                                        "Hviledager vises tydelig i planen."
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                sessionsPerWeek =
                                    max(
                                        sessionsPerWeek - 1,
                                        1
                                    )
                            } label: {
                                Image(
                                    systemName:
                                        "minus"
                                )
                                .font(.caption.bold())
                                .frame(
                                    width: 34,
                                    height: 34
                                )
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: Circle()
                                )
                            }
                            .buttonStyle(.plain)

                            Text(
                                "\(sessionsPerWeek)"
                            )
                            .font(
                                .system(
                                    size: 22,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .frame(width: 30)

                            Button {
                                sessionsPerWeek =
                                    min(
                                        sessionsPerWeek + 1,
                                        7
                                    )
                            } label: {
                                Image(
                                    systemName:
                                        "plus"
                                )
                                .font(.caption.bold())
                                .frame(
                                    width: 34,
                                    height: 34
                                )
                                .background(
                                    ATHLTHTheme.accentDeep,
                                    in: Circle()
                                )
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Training days",
                            norwegian: "Treningsdager"
                        )
                    )

                    dayPicker

                    HStack(spacing: 8) {
                        Image(
                            systemName:
                                "moon.stars.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.recoveryBlue
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "\(7 - selectedDays.count) rest day\(7 - selectedDays.count == 1 ? "" : "s") in the week",
                                norwegian:
                                    "\(7 - selectedDays.count) hviledag\(7 - selectedDays.count == 1 ? "" : "er") i uken"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                    }
                }
            }

            builderPanel {
                VStack(
                    alignment: .leading,
                    spacing: 11
                ) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Week setup",
                            norwegian: "Ukeoppsett"
                        )
                    )

                    weeklyPreview

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Tap a workout type to change it. This is only the starting structure and every session remains editable.",
                            norwegian:
                                "Trykk på økttypen for å endre den. Dette er bare startstrukturen, og alle økter kan redigeres senere."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }
            }

            if mode == .advanced {
                builderPanel {
                    VStack(spacing: 13) {
                        Stepper(
                            value:
                                $weeklyTimeBudgetMinutes,
                            in: 60...1_200,
                            step: 30
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Weekly time budget",
                                        norwegian:
                                            "Tidsbudsjett per uke"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Text(
                                    durationText(
                                        weeklyTimeBudgetMinutes
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) {
                dayIndex in
                let selected =
                    selectedDays
                        .contains(dayIndex)

                Button {
                    toggleDay(dayIndex)
                } label: {
                    VStack(spacing: 5) {
                        Text(
                            shortDayName(
                                dayIndex
                            )
                        )
                        .font(.system(size: 9, weight: .bold))

                        Image(
                            systemName:
                                selected
                                    ? "checkmark"
                                    : "moon.fill"
                        )
                        .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(
                        selected
                            ? Color.white
                            : ATHLTHTheme.mutedText
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 50
                    )
                    .background(
                        selected
                            ? ATHLTHTheme.accentDeep
                            : ATHLTHTheme.recoveryBlueSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weekDayKey(_ day: Int, weekIndex: Int? = nil) -> Int {
        (weekIndex ?? selectedPlanWeekIndex) * 7 + day
    }

    private func calendarDate(for week: Int, offset: Int) -> Date {
        Calendar.current.date(
            byAdding: .day, value: week * 7 + offset,
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private func dateForWeekDay(_ day: Int, weekIndex: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let startWeekday = (calendar.component(.weekday, from: start) + 5) % 7 + 1
        let dayOffset = (day - startWeekday + 7) % 7 + weekIndex * 7
        return calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
    }

    private func updateWeekDay(
        _ day: Int, change: (inout ATHLTHPlanWeekDayEdit) -> Void
    ) {
        let key = weekDayKey(day)
        var edit = weekDayEdits[key] ?? ATHLTHPlanWeekDayEdit()
        change(&edit)
        weekDayEdits[key] = edit
    }

    private func effectiveWorkoutKind(for day: Int) -> WorkoutKind {
        weekDayEdits[weekDayKey(day)]?.detailedWorkout?.kind ??
        weekDayEdits[weekDayKey(day)]?.kind ??
        resolvedWorkoutKind(for: day)
    }

    private func effectiveWorkoutTitle(for day: Int) -> String {
        weekDayEdits[weekDayKey(day)]?.detailedWorkout?.title ??
        weekDayEdits[weekDayKey(day)]?.title ??
        resolvedWorkoutTitle(for: day)
    }

    private func effectiveWorkoutMinutes(for day: Int) -> Int {
        weekDayEdits[weekDayKey(day)]?.detailedWorkout?.durationMinutes ??
        weekDayEdits[weekDayKey(day)]?.durationMinutes ??
        resolvedWorkoutMinutes(for: day)
    }

    private func effectiveDetailedWorkout(for day: Int) -> ATHLTHPlanStructuredWorkoutBlueprint? {
        if let edit = weekDayEdits[weekDayKey(day)] {
            if let detailed = edit.detailedWorkout { return detailed }
            if edit.removeTemplateDetail { return nil }
        }
        return structuredWorkoutsByDay[day]
    }

    private var weekSelector: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(ATHLTHLocalization.choose(
                    english: "Week", norwegian: "Uke"
                ) + " \(selectedPlanWeekIndex + 1) / \(weekCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer(minLength: 6)
                Text(calendarDate(for: selectedPlanWeekIndex, offset: 0)
                    .formatted(.dateTime.day().month(.abbreviated)) + " – " +
                     calendarDate(for: selectedPlanWeekIndex, offset: 6)
                    .formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(0..<weekCount, id: \.self) { week in
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    selectedPlanWeekIndex = week
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "WEEK", norwegian: "UKE"
                                    ))
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(0.7)
                                    Text("\(week + 1)")
                                        .font(.system(size: 19, weight: .bold, design: .rounded))
                                    Circle()
                                        .fill(week == selectedPlanWeekIndex
                                            ? Color.white.opacity(0.88)
                                            : ATHLTHTheme.accentDeep.opacity(0.65))
                                        .frame(width: 4, height: 4)
                                        .opacity(weekDayEdits.keys.contains(where: {
                                            ($0 - 1) / 7 == week
                                        }) ? 1 : 0)
                                }
                                .foregroundStyle(week == selectedPlanWeekIndex
                                    ? .white : ATHLTHPlanDesign.ink)
                                .frame(width: 65, height: 64)
                                .background(
                                    week == selectedPlanWeekIndex
                                        ? ATHLTHTheme.accentDeep
                                        : ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 13,
                                                         style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13,
                                                     style: .continuous)
                                        .strokeBorder(
                                            week == selectedPlanWeekIndex
                                                ? Color.clear : ATHLTHPlanDesign.warmDivider,
                                            lineWidth: 0.8
                                        )
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                            .id(week)
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Week", norwegian: "Uke"
                            ) + " \(week + 1)")
                            .accessibilityAddTraits(
                                week == selectedPlanWeekIndex ? .isSelected : []
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: selectedPlanWeekIndex) { _, week in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(week, anchor: .center)
                    }
                }
            }
            Text(ATHLTHLocalization.choose(
                english: "Weeks follow the template until you edit a workout.",
                norwegian: "Ukene følger grunnmønsteret til du endrer en økt."
            ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
    }

    /// A summary represents contiguous phases, preserving the real sequence
    /// (e.g. work → pause → work in intervals rather than collecting all pauses).
    private struct WeekWorkoutPreviewPhase: Identifiable {
        let id: Int
        let phase: WorkoutPhaseKind
        var blocks: [WorkoutTemplateBlock]
    }

    private func previewPhases(
        for blocks: [WorkoutTemplateBlock]
    ) -> [WeekWorkoutPreviewPhase] {
        var sections: [WeekWorkoutPreviewPhase] = []
        for block in blocks {
            if let last = sections.indices.last,
               sections[last].phase == block.resolvedPhase {
                sections[last].blocks.append(block)
            } else {
                sections.append(WeekWorkoutPreviewPhase(
                    id: sections.count, phase: block.resolvedPhase, blocks: [block]
                ))
            }
        }
        return sections
    }

    private func previewWorkouts(for day: Int) -> [ATHLTHPlanStructuredWorkoutBlueprint] {
        let edit = weekDayEdits[weekDayKey(day)]
        guard edit?.isRestDay != true else { return [] }
        let primary = effectiveDetailedWorkout(for: day)
        return (primary.map { [$0] } ?? []) + (edit?.additionalDetailedWorkouts ?? [])
    }

    private func isPreviewRestDay(_ day: Int) -> Bool {
        let edit = weekDayEdits[weekDayKey(day)]
        if edit?.isRestDay == true { return true }
        return !selectedDays.contains(day) &&
            edit?.detailedWorkout == nil &&
            edit?.kind == nil &&
            edit?.title == nil &&
            (edit?.additionalDetailedWorkouts ?? []).isEmpty &&
            structuredWorkoutsByDay[day] == nil
    }

    private func togglePreviewDay(_ day: Int) {
        let key = weekDayKey(day)
        withAnimation(.easeInOut(duration: 0.24)) {
            if expandedWeekPreviewDays.contains(key) {
                expandedWeekPreviewDays.remove(key)
            } else {
                expandedWeekPreviewDays.insert(key)
            }
        }
    }

    private func openPreviewDayActions(_ day: Int) {
        editingWeekDay = WeekDayEditorSelection(id: day)
    }

    private func editPreviewWorkout(_ day: Int, index: Int) {
        editingWorkoutIndex = index
        addingExtraWorkout = false
        quickStudioOption = nil
        composingAdvancedDay = WeekDayEditorSelection(id: day)
    }

    private func addPreviewWorkout(_ day: Int) {
        guard !isPreviewRestDay(day),
              !previewWorkouts(for: day).isEmpty else {
            // A rest day needs an explicit activity choice; preserve the
            // existing plan-day sheet with quick choices and library access.
            openPreviewDayActions(day)
            return
        }
        // The new workout must be appended, never overwrite the first one.
        quickStudioOption = nil
        editingWorkoutIndex = 0
        addingExtraWorkout = true
        composingAdvancedDay = WeekDayEditorSelection(id: day)
    }

    private var weeklyPreviewSummary: some View {
        let days = Array(1...7)
        let activeDays = days.filter { !isPreviewRestDay($0) }
        let workouts = activeDays.reduce(0) { count, day in
            let details = previewWorkouts(for: day)
            // The default weekly program may have an existing workout
            // before the athlete edits its individual blocks.
            return count + max(details.count, 1)
        }
        let minutes = activeDays.reduce(0) { total, day in
            let details = previewWorkouts(for: day)
            return total + (details.isEmpty
                ? effectiveWorkoutMinutes(for: day)
                : details.reduce(0) { $0 + $1.durationMinutes })
        }
        let restDays = days.count - activeDays.count

        return HStack(spacing: 7) {
            weekSummaryMetric("\(workouts) " + ATHLTHLocalization.choose(
                english: "workouts", norwegian: "økter"
            ), symbol: "figure.run")
            weekSummaryMetric("\(minutes) " + ATHLTHLocalization.choose(
                english: "min", norwegian: "min"
            ), symbol: "clock")
            weekSummaryMetric("\(restDays) " + ATHLTHLocalization.choose(
                english: "rest days", norwegian: "hviledager"
            ), symbol: "moon.stars")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekSummaryMetric(_ value: String, symbol: String) -> some View {
        Label(value, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 10))
    }

    private var weeklyPreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Your week, your workouts", norwegian: "Din uke, dine økter"
                ))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !workoutKindOverridesByDay.isEmpty ||
                   !workoutTitleOverridesByDay.isEmpty ||
                   !workoutMinutesByDay.isEmpty {
                    Button(ATHLTHLocalization.choose(
                        english: "Restore suggestions", norwegian: "Nullstill forslag"
                    )) {
                        workoutKindOverridesByDay.removeAll()
                        workoutTitleOverridesByDay.removeAll()
                        workoutMinutesByDay.removeAll()
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.bottom, 3)

            weekSelector
            weeklyPreviewSummary

            ForEach(Array(1...7).sorted {
                dateForWeekDay($0, weekIndex: selectedPlanWeekIndex) <
                dateForWeekDay($1, weekIndex: selectedPlanWeekIndex)
            }, id: \.self) { day in
                weeklyPreviewDayCard(day)
            }
        }
    }

    private func weeklyPreviewDayCard(_ day: Int, guided: Bool = false) -> some View {
        let edit = weekDayEdits[weekDayKey(day)]
        let unplanned = guided &&
            edit?.isRestDay != true &&
            edit?.detailedWorkout?.isValid != true &&
            !(edit?.additionalDetailedWorkouts?.contains(where: \.isValid) ?? false)
        let restDay = guided ? edit?.isRestDay == true : isPreviewRestDay(day)
        let expanded = expandedWeekPreviewDays.contains(weekDayKey(day))
        let workouts = unplanned ? [] : previewWorkouts(for: day)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                togglePreviewDay(day)
            } label: {
                HStack(spacing: 12) {
                    if !unplanned {
                        Image(systemName: restDay
                            ? "moon.stars.fill" : effectiveWorkoutKind(for: day).systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(restDay
                                ? ATHLTHTheme.recoveryBlue : ATHLTHTheme.accentDeep)
                            .frame(width: 48, height: 48)
                            .background(restDay
                                ? ATHLTHTheme.recoveryBlueSoft : ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 14))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(fullDayName(day) + " · " +
                             dateForWeekDay(day, weekIndex: selectedPlanWeekIndex)
                                 .formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(unplanned
                                ? .system(size: 18, weight: .semibold)
                                : .caption.weight(.semibold))
                            .foregroundStyle(unplanned
                                ? ATHLTHPlanDesign.ink : ATHLTHPlanDesign.secondaryInk)
                            .lineLimit(2)

                        if !unplanned {
                            Text(restDay
                                ? ATHLTHLocalization.choose(
                                    english: "Rest day", norwegian: "Hviledag")
                                : effectiveWorkoutTitle(for: day))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .lineLimit(2)
                        }

                        if !unplanned && !restDay {
                            Text(effectiveWorkoutKind(for: day).title + " · " +
                                 "\(effectiveWorkoutMinutes(for: day)) min")
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            if workouts.count > 1 {
                                Text("\(workouts.count) " + ATHLTHLocalization.choose(
                                    english: "workouts", norwegian: "økter"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                            } else if let first = workouts.first {
                                Text("\(first.blocks.count) " + ATHLTHLocalization.choose(
                                    english: "blocks", norwegian: "øktblokker"))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .frame(width: 36, height: 36)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                fullDayName(day) + ", " +
                (unplanned ? ATHLTHLocalization.choose(
                    english: "Not planned yet", norwegian: "Ikke planlagt"
                ) : restDay
                    ? ATHLTHLocalization.choose(english: "Rest day", norwegian: "Hviledag")
                    : effectiveWorkoutTitle(for: day))
            )
            .accessibilityHint(ATHLTHLocalization.choose(
                english: expanded ? "Collapse workout details" : "Expand workout details",
                norwegian: expanded ? "Skjul øktinnhold" : "Vis øktinnhold"
            ))

            if expanded {
                Divider()
                    .overlay(ATHLTHPlanDesign.warmDivider)
                    .padding(.horizontal, 14)
                weeklyPreviewDayDetails(
                    day, restDay: restDay, workouts: workouts,
                    guided: guided, unplanned: unplanned
                )
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthPlanCard(radius: 20)
    }

    private func weeklyPreviewDayDetails(
        _ day: Int, restDay: Bool, workouts: [ATHLTHPlanStructuredWorkoutBlueprint],
        guided: Bool = false, unplanned: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if unplanned {
                Label(ATHLTHLocalization.choose(
                    english: "Choose an activity, build a workout or use a saved one.",
                    norwegian: "Velg en aktivitet, bygg en økt eller hent en lagret økt."
                ), systemImage: "calendar.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else if restDay {
                Label(ATHLTHLocalization.choose(
                    english: "No workout planned for this date.",
                    norwegian: "Ingen treningsøkt er planlagt denne dagen."
                ), systemImage: "moon.stars")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else if workouts.isEmpty {
                Label(ATHLTHLocalization.choose(
                    english: "Add exercises and phases to see the entire workout here.",
                    norwegian: "Legg til øvelser og deler for å se hele økten her."
                ), systemImage: "list.bullet.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                // A template-generated session remains visible alongside any
                // detailed workouts copied into the same date.
                let edit = weekDayEdits[weekDayKey(day)]
                if selectedDays.contains(day), edit?.detailedWorkout == nil {
                    Label(
                        effectiveWorkoutTitle(for: day) + " · " +
                            "\(effectiveWorkoutMinutes(for: day)) min",
                        systemImage: effectiveWorkoutKind(for: day).systemImage
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .padding(.bottom, 4)
                }
                ForEach(Array(workouts.enumerated()), id: \.offset) { entry in
                    weeklyPreviewWorkoutDetail(
                        entry.element, day: day, index: entry.offset,
                        guided: guided, totalCount: workouts.count
                    )
                }
            }
            if guided {
                guidedDayPlanningActions(day, unplanned: unplanned, restDay: restDay,
                                         hasWorkout: !workouts.isEmpty)
            } else {
            HStack(spacing: 9) {
                if !restDay {
                    Button {
                        if workouts.isEmpty {
                            openPreviewDayActions(day)
                        } else {
                            editPreviewWorkout(day, index: 0)
                        }
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Edit workout", norwegian: "Rediger økt"
                        ), systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(ATHLTHPlanDesign.ink)
                }
                Button {
                    addPreviewWorkout(day)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Add workout", norwegian: "Legg til økt"
                    ), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
            }
            }
        }
    }

    private func weeklyPreviewWorkoutDetail(
        _ workout: ATHLTHPlanStructuredWorkoutBlueprint, day: Int, index: Int,
        guided: Bool = false, totalCount: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if index > 0 {
                Divider()
                    .padding(.vertical, 4)
            }
            HStack {
                Text(workout.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                Text("\(workout.durationMinutes) min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            if workout.blocks.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Workout details not yet entered.",
                    norwegian: "Øktinnholdet er ikke lagt inn ennå."
                ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                ForEach(previewPhases(for: workout.blocks)) { phase in
                    weeklyPreviewPhaseDetail(
                        phase, guided: guided, sourceWorkoutIndex: index,
                        originalBlocks: workout.blocks
                    )
                }
            }
            if guided {
                guidedSessionControls(workout: workout, day: day, index: index,
                                      totalCount: totalCount)
            }
            if index > 0 && !guided {
                Button {
                    editPreviewWorkout(day, index: index)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Edit this workout", norwegian: "Rediger denne økten"
                    ), systemImage: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
        }
    }

    /// Guided-only controls live inside the same expandable card the week
    /// overview uses. Quick choices no longer duplicate an entire page.
    private func guidedDayPlanningActions(
        _ day: Int, unplanned: Bool, restDay: Bool, hasWorkout: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if unplanned {
                VStack(alignment: .leading, spacing: 7) {
                    Text(ATHLTHLocalization.choose(
                        english: "Quick choice", norwegian: "Hurtigvalg"
                    ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QuickDayOption.allCases) { option in
                                Button {
                                    selectedPlanWeekIndex = guidedCurrentWeek
                                    chooseQuickWorkout(option, on: day)
                                } label: {
                                    Label(option.title, systemImage: option.symbol)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ATHLTHPlanDesign.ink)
                                        .padding(.horizontal, 11)
                                        .frame(height: 38)
                                        .background(ATHLTHPlanDesign.selectedSurface,
                                                    in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    selectedPlanWeekIndex = guidedCurrentWeek
                    quickStudioOption = nil
                    editingWorkoutIndex = 0
                    addingExtraWorkout = hasWorkout
                    composingAdvancedDay = WeekDayEditorSelection(id: day)
                } label: {
                    Label(hasWorkout
                        ? ATHLTHLocalization.choose(
                            english: "Add workout", norwegian: "Legg til økt")
                        : ATHLTHLocalization.choose(
                            english: "Build workout", norwegian: "Bygg økt"),
                          systemImage: hasWorkout ? "plus.circle" : "plus.square.on.square")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)

                Button {
                    selectedPlanWeekIndex = guidedCurrentWeek
                    selectingExtraFromLibrary = hasWorkout
                    selectingLibraryDay = WeekDayEditorSelection(id: day)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "My workouts", norwegian: "Mine økter"),
                          systemImage: "books.vertical")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHPlanDesign.ink)
            }
            HStack {
                if unplanned {
                    Button {
                        selectedPlanWeekIndex = guidedCurrentWeek
                        setRestDay(day)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Rest day", norwegian: "Hviledag"),
                            systemImage: "moon.stars")
                    }
                } else {
                    Button {
                        selectedPlanWeekIndex = guidedCurrentWeek
                        openPreviewDayActions(day)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "More day options", norwegian: "Flere dagsvalg"),
                            systemImage: "ellipsis.circle")
                    }
                }
                Spacer()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .buttonStyle(.plain)
        }
    }

    /// Optional metadata belongs after the main workout planning controls,
    /// not between the date and the workout. Reuses the existing place picker.
    private func guidedTrainingPlaceDisclosure(for day: Int) -> some View {
        let place = weekDayEdits[weekDayKey(day, weekIndex: guidedCurrentWeek)]?.trainingPlace
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    guidedTrainingPlaceExpanded.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Training place (optional)",
                            norwegian: "Treningssted (valgfritt)"
                        ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        if let place {
                            Text(place.name)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .rotationEffect(.degrees(guidedTrainingPlaceExpanded ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(ATHLTHLocalization.choose(
                english: guidedTrainingPlaceExpanded
                    ? "Collapse training place" : "Expand training place",
                norwegian: guidedTrainingPlaceExpanded
                    ? "Skjul treningssted" : "Vis treningssted"
            ))

            if guidedTrainingPlaceExpanded {
                Divider()
                    .overlay(ATHLTHPlanDesign.warmDivider)
                    .padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 11) {
                    if let place, !place.address.isEmpty {
                        Label(place.address, systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if place == nil {
                        Text(ATHLTHLocalization.choose(
                            english: "Choose a gym, sports venue, address or favorite.",
                            norwegian: "Velg treningssenter, idrettsanlegg, adresse eller favoritt."
                        ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    HStack(spacing: 10) {
                        Button {
                            selectedPlanWeekIndex = guidedCurrentWeek
                            editingTrainingPlaceDay = WeekDayEditorSelection(id: day)
                        } label: {
                            Label(place == nil
                                  ? ATHLTHLocalization.choose(
                                    english: "Select place", norwegian: "Velg treningssted")
                                  : ATHLTHLocalization.choose(
                                    english: "Change place", norwegian: "Endre treningssted"),
                                  systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHTheme.accentDeep)

                        if place != nil {
                            Button {
                                selectedPlanWeekIndex = guidedCurrentWeek
                                updateWeekDay(day) { edit in
                                    edit.trainingPlace = nil
                                }
                            } label: {
                                Text(ATHLTHLocalization.choose(
                                    english: "Remove", norwegian: "Fjern"
                                ))
                                    .frame(minHeight: 42)
                            }
                            .buttonStyle(.bordered)
                            .tint(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .athlthPlanCard(radius: 18)
    }

    private func guidedSessionControls(
        workout: ATHLTHPlanStructuredWorkoutBlueprint,
        day: Int, index: Int, totalCount: Int
    ) -> some View {
        HStack(spacing: 9) {
            Menu {
                Button(ATHLTHLocalization.choose(
                    english: "No fixed start time", norwegian: "Uten fast starttid"
                )) {
                    setGuidedWorkoutStart(index: index, minute: nil)
                }
                ForEach(0..<48, id: \.self) { slot in
                    let minute = slot * 30
                    Button(String(format: "%02d:%02d", minute / 60, minute % 60)) {
                        setGuidedWorkoutStart(index: index, minute: minute)
                    }
                }
            } label: {
                Label(workout.startMinuteOfDay.map {
                    String(format: "%02d:%02d", $0 / 60, $0 % 60)
                } ?? ATHLTHLocalization.choose(
                    english: "Start time", norwegian: "Starttid"
                ), systemImage: "clock")
            }
            .buttonStyle(.bordered)
            .tint(ATHLTHPlanDesign.ink)

            Menu {
                Button {
                    moveGuidedWorkout(from: index, by: -1)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Move up", norwegian: "Flytt opp"),
                        systemImage: "arrow.up")
                }
                .disabled(index == 0)
                Button {
                    moveGuidedWorkout(from: index, by: 1)
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Move down", norwegian: "Flytt ned"),
                        systemImage: "arrow.down")
                }
                .disabled(index >= totalCount - 1)
                Divider()
                ForEach(1...7, id: \.self) { destination in
                    if destination != day {
                        Button {
                            moveGuidedWorkout(to: destination, index: index)
                        } label: {
                            Label(fullDayName(destination), systemImage: "calendar")
                        }
                    }
                }
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Move", norwegian: "Flytt"),
                    systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(.bordered)
            .tint(ATHLTHPlanDesign.ink)

            Spacer(minLength: 0)

            Button {
                selectedPlanWeekIndex = guidedCurrentWeek
                editPreviewWorkout(day, index: index)
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Edit", norwegian: "Rediger"),
                    systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .tint(ATHLTHTheme.accentDeep)
        }
        .font(.caption2.weight(.semibold))
    }

    @ViewBuilder
    private func guidedBlockMoveActions(
        sourceWorkoutIndex: Int, blockIndex: Int
    ) -> some View {
        ForEach(1...7, id: \.self) { targetDay in
            let key = weekDayKey(targetDay, weekIndex: guidedCurrentWeek)
            if let target = weekDayEdits[key],
               let primary = target.detailedWorkout {
                ForEach(Array(([primary] +
                    (target.additionalDetailedWorkouts ?? [])).enumerated()),
                    id: \.offset) { targetIndex, targetWorkout in
                    if targetDay != guidedCurrentWeekday ||
                        targetIndex != sourceWorkoutIndex {
                        Button {
                            moveGuidedBlock(
                                from: sourceWorkoutIndex, blockIndex: blockIndex,
                                to: targetDay, workoutIndex: targetIndex
                            )
                        } label: {
                            Label(targetWorkout.title, systemImage: "arrow.right")
                        }
                        Button {
                            moveGuidedBlock(
                                from: sourceWorkoutIndex, blockIndex: blockIndex,
                                copy: true, to: targetDay, workoutIndex: targetIndex
                            )
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Copy to ", norwegian: "Kopier til "
                            ) + targetWorkout.title, systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    private func weeklyPreviewPhaseDetail(
        _ section: WeekWorkoutPreviewPhase,
        guided: Bool = false,
        sourceWorkoutIndex: Int = 0,
        originalBlocks: [WorkoutTemplateBlock] = []
    ) -> some View {
        let phaseStartIndex = previewPhases(for: originalBlocks)
            .prefix(section.id)
            .reduce(0) { $0 + $1.blocks.count }
        return VStack(alignment: .leading, spacing: 7) {
            Label(section.phase.title, systemImage: section.phase.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { entry in
                let block = entry.element
                let originalIndex = phaseStartIndex + entry.offset
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: block.kind == .rest
                        ? "pause.fill" : block.kind == .exercise
                        ? "dumbbell" : block.kind == .run
                        ? (block.cardioActivity == .walking ? "figure.walk" : "figure.run")
                        : (block.wellnessKind?.symbol ??
                            (block.activityTag == "cycling" ? "bicycle" : "leaf")))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let details = block.targetText {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let kind = block.groupKind,
                           originalIndex == 0 ||
                           (originalBlocks.indices.contains(originalIndex - 1) &&
                            originalBlocks[originalIndex - 1].groupID != block.groupID) {
                            Text(kind.title + " · " + "\(block.groupRounds ?? 1) " +
                                 ATHLTHLocalization.choose(
                                    english: "rounds", norwegian: "runder"
                                 ))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                        if let seconds = block.restBetweenSetsSeconds, seconds > 0 {
                            Label("\(Int(seconds)) " + ATHLTHLocalization.choose(
                                english: "sec rest between sets",
                                norwegian: "sek pause mellom sett"
                            ), systemImage: "pause.circle")
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 9)
                .contextMenu {
                    if guided {
                        guidedBlockMoveActions(sourceWorkoutIndex: sourceWorkoutIndex,
                                               blockIndex: originalIndex)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 13))
    }

    private func resolvedWorkoutTitle(for day: Int) -> String {
        if let chosen = workoutTitleOverridesByDay[day],
           !chosen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return chosen
        }
        return suggestedWorkoutTitle(
            kind: resolvedWorkoutKind(for: day),
            slot: trainingSlot(for: day)
        )
    }

    private func resolvedWorkoutMinutes(for day: Int) -> Int {
        if let chosen = workoutMinutesByDay[day] { return chosen }
        if mode == .basic { return simpleMinutes }
        return max(20, min(180, weeklyTimeBudgetMinutes / max(selectedDays.count, 1)))
    }

    private func subtypeTitles(for kind: WorkoutKind) -> [String] {
        switch kind {
        case .strength:
            return ["Helkropp", "Overkropp", "Underkropp", "Push", "Pull", "Bein", "Kjernestyrke", "Egendefinert"]
        case .running:
            return ["Rolig løp", "Intervaller", "Langtur", "Tempoøkt", "Bakkeintervaller", "Tredemølle", "Egendefinert"]
        case .walking:
            return ["Rolig gåtur", "Rask gange", "Tur i terrenget", "Egendefinert"]
        case .mobility:
            return ["Mobilitet", "Tøying", "Yoga", "Egendefinert"]
        case .recovery:
            return ["Aktiv restitusjon", "Lett bevegelse", "Egendefinert"]
        case .custom:
            return ["Hybridøkt", "Sirkeltrening", "Egendefinert"]
        }
    }

    private func trainingSlot(
        for dayIndex: Int
    ) -> Int {
        selectedDays
            .sorted()
            .firstIndex(
                of: dayIndex
            ) ?? 0
    }

    private func resolvedWorkoutKind(
        for dayIndex: Int
    ) -> WorkoutKind {
        if let override =
            workoutKindOverridesByDay[
                dayIndex
            ] {
            return override
        }

        return suggestedKind(
            slot:
                trainingSlot(
                    for: dayIndex
                )
        )
    }

    private var reviewStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            stepIntro(
                eyebrow:
                    ATHLTHLocalization.choose(
                        english: "04 · REVIEW",
                        norwegian: "04 · OPPSUMMERING"
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "Ready to build",
                        norwegian: "Klar til å bygge"
                    ),
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Review every week and tap a date to customize the workout before saving.",
                        norwegian:
                            "Se gjennom alle ukene og trykk på datoene for å tilpasse øktene før lagring."
                    ),
                icon: "checkmark.seal.fill"
            )

            builderPanel {
                VStack(spacing: 0) {
                    reviewRow(
                        icon: "textformat",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Plan",
                                norwegian: "Plan"
                            ),
                        value:
                            resolvedPlanTitle
                    )

                    reviewDivider

                    reviewRow(
                        icon: "calendar",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Period",
                                norwegian: "Periode"
                            ),
                        value:
                            ATHLTHLocalization.choose(
                                english:
                                    "\(weekCount) weeks · \(startDate.formatted(date: .abbreviated, time: .omitted))",
                                norwegian:
                                    "\(weekCount) uker · \(startDate.formatted(date: .abbreviated, time: .omitted))"
                            )
                    )

                    reviewDivider

                    reviewRow(
                        icon:
                            focus.systemImage,
                        title:
                            ATHLTHLocalization.choose(
                                english: "Focus",
                                norwegian: "Fokus"
                            ),
                        value:
                            focusSummary
                    )

                    reviewDivider

                    reviewRow(
                        icon: "scope",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Goal",
                                norwegian: "Mål"
                            ),
                        value: goal.title
                    )

                    reviewDivider

                    reviewRow(
                        icon:
                            "calendar.day.timeline.left",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Week",
                                norwegian: "Uke"
                            ),
                        value:
                            trainingWeekSummary
                    )

                    reviewDivider

                    reviewRow(
                        icon:
                            injuryFree
                                ? "checkmark.shield.fill"
                                : "cross.case.fill",
                        title:
                            ATHLTHLocalization.choose(
                                english: "Limitations",
                                norwegian: "Hensyn"
                            ),
                        value:
                            injuryFree
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "No known issues",
                                    norwegian:
                                        "Ingen kjente"
                                )
                                : injuriesOrLimitations
                                    .trimmingCharacters(
                                        in:
                                            .whitespacesAndNewlines
                                    )
                                    .isEmpty
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Marked for consideration",
                                        norwegian:
                                            "Markert for hensyn"
                                    )
                                    : injuriesOrLimitations
                    )

                    if !selectedMuscles.isEmpty {
                        reviewDivider

                        reviewRow(
                            icon:
                                "figure.strengthtraining.traditional",
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "Muscle priority",
                                    norwegian:
                                        "Muskelprioritet"
                                ),
                            value:
                                selectedMuscleTitles
                        )
                    }
                }
            }

            builderPanel {
                VStack(alignment: .leading, spacing: 11) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Review every week",
                            norwegian: "Se gjennom og rediger alle ukene"
                        ),
                        systemImage: "calendar.badge.checkmark"
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    weeklyPreview
                }
            }

            if !goalStore.goals.isEmpty {
                builderPanel {
                    VStack(
                        alignment: .leading,
                        spacing: 9
                    ) {
                        fieldLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Connect to goals in Progress",
                                norwegian:
                                    "Koble til mål i Progress"
                            )
                        )

                        ForEach(
                            goalStore.goals.prefix(5)
                        ) { appGoal in
                            Toggle(
                                isOn:
                                    Binding(
                                        get: {
                                            selectedGoalIDs
                                                .contains(
                                                    appGoal.id
                                                )
                                        },
                                        set: {
                                            enabled in
                                            if enabled {
                                                selectedGoalIDs
                                                    .insert(
                                                        appGoal.id
                                                    )
                                            } else {
                                                selectedGoalIDs
                                                    .remove(
                                                        appGoal.id
                                                    )
                                            }
                                        }
                                    )
                            ) {
                                Text(appGoal.title)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }

            if let conflict = conflictingPlan {
                conflictCard(conflict)
            }

            if mode == .advanced && weekPlanningApproach == .guided {
                Button {
                    createPlan(seedSuggestedWeek: false)
                } label: {
                    creationChoiceCard(
                        title: ATHLTHLocalization.choose(
                            english: "Save my detailed plan", norwegian: "Lagre den detaljerte planen"
                        ),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Keep your chosen date-by-date workouts and rest days exactly as planned.",
                            norwegian: "Behold øktene og hviledagene du har valgt, dato for dato."
                        ),
                        icon: "checkmark.seal.fill",
                        prominent: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canCreatePlan || guidedChosenDays.isEmpty)
            } else {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "HOW TO START THE WEEK",
                        norwegian: "HVORDAN VIL DU STARTE?"
                    )
                )
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Button {
                    showingAIBuilder = true
                } label: {
                    creationChoiceCard(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Get an AI proposal",
                                norwegian:
                                    "Få forslag fra AI"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "ATHLTH Coach uses your focus, goal, available days and time. Training limitations are shared with AI only if you opt in.",
                                norwegian:
                                    "ATHLTH Coach bruker fokus, mål, tilgjengelige dager og tid. Treningshensyn deles kun med AI dersom du godkjenner dette."
                            ),
                        icon: "sparkles",
                        prominent: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    !canCreatePlan
                )
                .opacity(
                    canCreatePlan ? 1 : 0.42
                )

                Button {
                    createPlan(
                        seedSuggestedWeek: true
                    )
                } label: {
                    creationChoiceCard(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Use a simple starting structure",
                                norwegian:
                                    "Bruk enkel startstruktur"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Create the chosen training days immediately, without AI, and edit every workout yourself.",
                                norwegian:
                                    "Opprett de valgte treningsdagene med en gang, uten AI, og rediger øktene selv."
                            ),
                        icon:
                            "calendar.day.timeline.left",
                        prominent: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    !canCreatePlan
                )
                .opacity(
                    canCreatePlan ? 1 : 0.42
                )

                Button {
                    createPlan(
                        seedSuggestedWeek: false
                    )
                } label: {
                    creationChoiceCard(
                        title:
                            ATHLTHLocalization.choose(
                                english:
                                    "Start with empty weeks",
                                norwegian:
                                    "Start med tomme uker"
                            ),
                        subtitle:
                            ATHLTHLocalization.choose(
                                english:
                                    "Keep the dates and profile, but add every workout yourself.",
                                norwegian:
                                    "Behold datoer og profil, men legg inn alle økter selv."
                            ),
                        icon:
                            "calendar.badge.plus",
                        prominent: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    !canCreatePlan
                )
                .opacity(
                    canCreatePlan ? 1 : 0.42
                )
            }
            }
        }
    }

    private func reviewRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 11
        ) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 30, height: 30)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var reviewDivider: some View {
        Divider()
            .padding(.leading, 41)
    }

    private func creationChoiceCard(
        title: String,
        subtitle: String,
        icon: String,
        prominent: Bool
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    prominent
                        ? ATHLTHTheme.accentDeep
                        : ATHLTHTheme.premiumGold
                )
                .frame(width: 43, height: 43)
                .background(
                    prominent
                        ? Color.white.opacity(0.92)
                        : ATHLTHTheme.premiumGoldSoft,
                    in: RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(.subheadline.weight(.bold))

                Text(subtitle)
                    .font(.caption)
                    .opacity(0.74)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.caption.bold())
        }
        .foregroundStyle(
            prominent
                ? Color.white
                : ATHLTHTheme.primaryText
        )
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 72
        )
        .background(
            prominent
                ? AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.accentDeep,
                            ATHLTHTheme.accent
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                : AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            ATHLTHPlanDesign.surface,
                            ATHLTHTheme.cardWarm.opacity(0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ),
            in: RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                prominent ? Color.white.opacity(0.14)
                    : ATHLTHPlanDesign.outline,
                lineWidth: 0.8
            )
        }
        .shadow(color: ATHLTHTheme.accentDeep.opacity(prominent ? 0.10 : 0.045),
                radius: 12, y: 5)
    }

    private func stepIntro(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        ATHLTHPlanSectionIntro(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            icon: icon
        )
    }

    private func builderPanel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ATHLTHPlanSurface {
            content()
        }
    }

    private func fieldLabel(
        _ title: String
    ) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
    }

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.35)

            HStack(spacing: 10) {
                if step != .mode {
                    Button {
                        if step == .week && mode == .advanced &&
                           weekPlanningApproach == .guided && guidedDayCursor > 0 {
                            guidedDayCursor -= 1
                        } else {
                            goBack()
                        }
                    } label: {
                        Image(
                            systemName:
                                "chevron.left"
                        )
                        .font(.subheadline.bold())
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }

                if step != .review {
                    Button {
                        if step == .basics && mode == .basic {
                            createPlan(seedSuggestedWeek: true)
                        } else if step == .week && mode == .advanced &&
                                  weekPlanningApproach == .guided &&
                                  guidedDayCursor < weekCount * 7 {
                            advanceGuidedDay()
                        } else {
                            goForward()
                        }
                    } label: {
                        HStack {
                            Text(
                                step == .basics && mode == .basic
                                ? ATHLTHLocalization.choose(english: "Create my plan", norwegian: "Lag planen min")
                                : (step == .week && weekPlanningApproach == .guided
                                    ? (guidedDayCursor >= weekCount * 7
                                        ? ATHLTHLocalization.choose(
                                            english: "Review plan", norwegian: "Se over planen")
                                        : ATHLTHLocalization.choose(
                                            english: "Next day", norwegian: "Neste dag"))
                                    : ATHLTHLocalization.choose(english: "Next", norwegian: "Neste"))
                            )
                            .font(.subheadline.weight(.bold))

                            Spacer()

                            Image(
                                systemName:
                                    "arrow.right"
                            )
                            .font(.subheadline.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(
                            maxWidth: .infinity
                        )
                        .frame(height: 48)
                        .background(
                            step == .week && mode == .advanced &&
                                weekPlanningApproach == .guided
                                ? ATHLTHTrainDesign.bronze
                                : ATHLTHTheme.accentDeep,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)
                    .opacity(
                        canContinue ? 1 : 0.38
                    )
                } else {
                    HStack(spacing: 8) {
                        Image(
                            systemName:
                                "checkmark.circle.fill"
                        )
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Choose how to start the plan above",
                                norwegian:
                                    "Velg hvordan planen skal starte over"
                            )
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                        Spacer()
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(
                .ultraThinMaterial
            )
        }
    }

    private var backButtonTitle: String {
        if step == .source {
            return ATHLTHLocalization.choose(
                english: "Close",
                norwegian: "Lukk"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Back",
            norwegian: "Tilbake"
        )
    }

    private var canContinue: Bool {
        switch step {
        case .mode:
            return true
        case .goal:
            return ATHLTHPlanGoalOption.options(for: selectedGoalArea)
                .contains { $0.id == selectedGoalChoice }
        case .source:
            return true
        case .approach:
            return true
        case .basics:
            return conflictingPlan == nil
        case .profile:
            return
                injuryFree ||
                !injuriesOrLimitations
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
        case .week:
            if mode != .advanced { return !selectedDays.isEmpty }
            guard let weekPlanningApproach else { return false }
            if weekPlanningApproach == .quick { return !selectedDays.isEmpty }
            if guidedDayCursor >= weekCount * 7 {
                return !guidedChosenDays.isEmpty
            }
            if guidedDayCursor == 7 && !firstGuidedWeekDecisionMade { return false }
            return ATHLTHGuidedPlanDayPolicy.isPlanned(
                weekDayEdits[weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)]
            )
        case .review:
            return false
        }
    }

    private var canCreatePlan: Bool {
        !selectedDays.isEmpty &&
        conflictingPlan == nil &&
        (
            mode == .basic || injuryFree ||
            !injuriesOrLimitations
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        )
    }

    private var resolvedEndDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value:
                max(
                    weekCount * 7 - 1,
                    0
                ),
            to:
                Calendar.current
                    .startOfDay(
                        for: startDate
                    )
        ) ?? startDate
    }

    private var conflictingPlan: TrainingPlan? {
        session.trainingPlanConflict(
            startDate: startDate,
            endDate: resolvedEndDate
        )
    }

    private var focusSummary: String {
        guard
            mode == .advanced,
            let secondaryFocus
        else {
            return focus.title
        }

        return
            "\(focusWeight)% \(focus.title) · " +
            "\(100 - focusWeight)% \(secondaryFocus.title)"
    }

    private var orderedPriorityMuscles: [String] {
        let others = selectedMuscles.sorted()
        guard let primaryMuscle,
              selectedMuscles.contains(primaryMuscle)
        else {
            return others
        }
        return [primaryMuscle] + others.filter { $0 != primaryMuscle }
    }

    private var selectedMuscleTitles: String {
        orderedPriorityMuscles.compactMap { id in
            Self.muscleOptions.first { $0.id == id }?.title
        }
        .joined(separator: ", ")
    }

    /// Restore the last editing position without an alert. The checkpoint is
    /// intentionally privacy-safe: health notes and personal goal text are not
    /// silently written to disk and can be reentered when needed.
    private func restorePlanDraft(_ draft: ATHLTHPlanCreationDraft) {
        mode = draft.advanced ? .advanced : .basic
        entryChoice = draft.advanced ? .advanced : .simple
        title = draft.usedDefaultTitle == true ? "" : draft.title
        weekCount = draft.weekCount
        startDate = max(Calendar.current.startOfDay(for: Date()), draft.startDate)
        if let savedArea = draft.entryGoalArea.flatMap(ATHLTHPlanGoalArea.init(rawValue:)) {
            selectedGoalArea = savedArea
        }
        if let savedChoice = draft.entryGoalChoice,
           ATHLTHPlanGoalOption.options(for: selectedGoalArea)
                .contains(where: { $0.id == savedChoice }) {
            selectedGoalChoice = savedChoice
        }
        if let savedFocus = draft.entryPlanFocus.flatMap(TrainingPlanFocus.init(rawValue:)) {
            focus = savedFocus
        }
        if let savedGoal = draft.entryPlanGoal.flatMap(TrainingPlanGoalType.init(rawValue:)) {
            goal = savedGoal
        }
        if selectedGoalChoice == "distance", selectedGoalArea == .running ||
            selectedGoalArea == .specific {
            goalDetail = ATHLTHLocalization.choose(
                english: "Improve running distance", norwegian: "Løpe lenger"
            )
        }
        switch draft.source {
        case "library": selectedSource = .library
        case "saved": selectedSource = .saved
        default: selectedSource = .scratch
        }
        // Activity days are structural plan data and safe to restore for
        // both modes; do not reset a simple plan back to three days.
        if let days = draft.preferredDayIndexes, !days.isEmpty {
            selectedDays = Set(days)
            sessionsPerWeek = days.count
        }
        if draft.advanced {
            if let equipmentValue = draft.equipmentContext,
               let restored = EquipmentContext(rawValue: equipmentValue) {
                equipment = restored
            }
            if let minutes = draft.weeklyTimeBudgetMinutes {
                weeklyTimeBudgetMinutes = minutes
                let perSession = Double(minutes) / Double(max(1, selectedDays.count))
                advancedSessionMinutes = min(180, max(5, Int((perSession / 5).rounded()) * 5))
            }
            workoutKindOverridesByDay = (draft.workoutKindsByDay ?? [:])
                .compactMapValues(WorkoutKind.init(rawValue:))
            workoutTitleOverridesByDay = draft.workoutPresetsByDay ?? [:]
            workoutMinutesByDay = draft.workoutMinutesByDay ?? [:]
            structuredWorkoutsByDay = draft.structuredWorkoutsByDay ?? [:]
            weekDayEdits = draft.weekDayEdits ?? [:]
            weekPlanningApproach = draft.planningApproach.flatMap(
                ATHLTHPlanWeekPlanningApproach.init(rawValue:)
            )
            guidedDayCursor = min(max(0, draft.guidedDayCursor ?? 0), weekCount * 7)
            firstGuidedWeekDecisionMade = draft.firstGuidedWeekDecisionMade ?? false
            selectedPlanWeekIndex = min(max(0, draft.selectedPlanWeekIndex ?? 0), weekCount - 1)
        } else {
            simpleMinutes = draft.simpleMinutes ?? simpleMinutes
            if let kinds = draft.simpleActivityKinds {
                let restored = Set(kinds.compactMap(WorkoutKind.init(rawValue:)))
                if !restored.isEmpty { simpleActivities = restored }
            }
        }
        varyWeekdays = draft.varyWeekdays ?? false
        selectedGoalIDs = Set(draft.linkedGoalIDs ?? []).intersection(
            Set(goalStore.activeGoals.filter { $0.status == .active }.map(\.id))
        )
        step = ATHLTHPlanJourney.restoredStep(draft.stage, advanced: draft.advanced)
    }

    private func saveResumableDraft() {
        guard didApplySuggestedStartDate,
              !completedPlanCreation,
              !isHydratingPlanDraft else {
            return
        }
        let draft = ATHLTHPlanCreationDraft(
            title: resolvedPlanTitle,
            weekCount: weekCount,
            usedDefaultTitle: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            startDate: startDate,
            advanced: mode == .advanced,
            source: selectedSource.rawValue,
            stage: String(describing: step),
            entryGoalArea: selectedGoalArea.rawValue,
            entryGoalChoice: selectedGoalChoice,
            entryPlanFocus: focus.rawValue,
            entryPlanGoal: goal.rawValue,
            preferredDayIndexes: selectedDays.sorted(),
            varyWeekdays: mode == .advanced ? varyWeekdays : false,
            linkedGoalIDs: Array(selectedGoalIDs),
            equipmentContext: mode == .advanced ? equipment.rawValue : nil,
            weeklyTimeBudgetMinutes: mode == .advanced
                ? weeklyTimeBudgetMinutes : nil,
            workoutKindsByDay: mode == .advanced
                ? workoutKindOverridesByDay.mapValues(\.rawValue) : nil,
            workoutPresetsByDay: mode == .advanced
                ? workoutTitleOverridesByDay.filter { day, title in
                    subtypeTitles(for: resolvedWorkoutKind(for: day)).contains(title)
                } : nil,
            workoutMinutesByDay: mode == .advanced
                ? workoutMinutesByDay : nil,
            structuredWorkoutsByDay: mode == .advanced
                ? structuredWorkoutsByDay : nil,
            weekDayEdits: mode == .advanced ? weekDayEdits : nil,
            planningApproach: mode == .advanced ? weekPlanningApproach?.rawValue : nil,
            guidedDayCursor: mode == .advanced ? guidedDayCursor : nil,
            firstGuidedWeekDecisionMade: mode == .advanced ? firstGuidedWeekDecisionMade : nil,
            selectedPlanWeekIndex: mode == .advanced ? selectedPlanWeekIndex : nil,
            editorDay: mode == .advanced
                ? (composingAdvancedDay?.id ?? selectingLibraryDay?.id ?? editingWeekDay?.id)
                : nil,
            editorKind: mode != .advanced ? nil
                : composingAdvancedDay != nil ? "studio"
                : selectingLibraryDay != nil ? "library"
                : editingWeekDay != nil ? "day" : nil,
            simpleMinutes: mode == .basic ? simpleMinutes : nil,
            simpleActivityKinds: mode == .basic
                ? simpleActivities.map(\.rawValue).sorted() : nil
        )
        draftStore.save(draft, userID: session.profile.userID, draftID: draftID)
    }

    private func goForward() {
        guard let next = ATHLTHPlanJourney.next(
            after: step, advanced: mode == .advanced
        ) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            step = next
        }
    }

    private func goBack() {
        if step == .basics {
            withAnimation(.easeInOut(duration: 0.18)) { step = .mode }
            return
        }
        if step == .approach {
            withAnimation(.easeInOut(duration: 0.18)) { step = .mode }
            return
        }
        guard let previous = ATHLTHPlanJourney.previous(
            before: step, advanced: mode == .advanced
        ) else {
            dismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            step = previous
        }
    }

    private func toggleDay(
        _ dayIndex: Int
    ) {
        if selectedDays.contains(dayIndex) {
            guard selectedDays.count > 1
            else {
                return
            }

            selectedDays.remove(dayIndex)
        } else {
            selectedDays.insert(dayIndex)
        }

        sessionsPerWeek =
            selectedDays.count
    }

    private func balancedDays(
        count: Int
    ) -> Set<Int> {
        switch count {
        case 1:
            return [3]
        case 2:
            return [2, 5]
        case 3:
            return [1, 3, 5]
        case 4:
            return [1, 2, 4, 6]
        case 5:
            return [1, 2, 3, 5, 6]
        case 6:
            return [1, 2, 3, 4, 5, 6]
        default:
            return [1, 2, 3, 4, 5, 6, 7]
        }
    }

    private func suggestedKind(
        slot: Int
    ) -> WorkoutKind {
        let pattern =
            focus.suggestedWorkoutPattern

        guard !pattern.isEmpty else {
            return .custom
        }

        return pattern[
            slot % pattern.count
        ]
    }

    private func suggestedWorkoutTitle(
        kind: WorkoutKind,
        slot: Int
    ) -> String {
        switch kind {
        case .strength:
            if focus == .hypertrophy {
                let titles = [
                    ATHLTHLocalization.choose(
                        english: "Upper body",
                        norwegian: "Overkropp"
                    ),
                    ATHLTHLocalization.choose(
                        english: "Lower body",
                        norwegian: "Underkropp"
                    ),
                    ATHLTHLocalization.choose(
                        english: "Full body",
                        norwegian: "Helkropp"
                    )
                ]
                return titles[
                    slot % titles.count
                ]
            }

            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )

        case .running:
            let titles = [
                ATHLTHLocalization.choose(
                    english: "Easy run",
                    norwegian: "Rolig løp"
                ),
                ATHLTHLocalization.choose(
                    english: "Intervals",
                    norwegian: "Intervaller"
                ),
                ATHLTHLocalization.choose(
                    english: "Long run",
                    norwegian: "Langtur"
                )
            ]
            return titles[
                slot % titles.count
            ]

        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walk",
                norwegian: "Gåtur"
            )

        case .mobility:
            return ATHLTHLocalization.choose(
                english: "Mobility",
                norwegian: "Mobilitet"
            )

        case .recovery:
            return ATHLTHLocalization.choose(
                english: "Recovery",
                norwegian: "Restitusjon"
            )

        case .custom:
            return ATHLTHLocalization.choose(
                english: "Workout",
                norwegian: "Økt"
            )
        }
    }

    private func shortDayName(
        _ dayIndex: Int
    ) -> String {
        let norwegian = [
            "M", "T", "O", "T", "F", "L", "S"
        ]
        let english = [
            "M", "T", "W", "T", "F", "S", "S"
        ]
        let index =
            min(
                max(dayIndex - 1, 0),
                6
            )

        return ATHLTHLocalization.choose(
            english: english[index],
            norwegian: norwegian[index]
        )
    }

    private func fullDayName(
        _ dayIndex: Int
    ) -> String {
        let norwegian = [
            "Mandag",
            "Tirsdag",
            "Onsdag",
            "Torsdag",
            "Fredag",
            "Lørdag",
            "Søndag"
        ]
        let english = [
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday",
            "Sunday"
        ]
        let index =
            min(
                max(dayIndex - 1, 0),
                6
            )

        return ATHLTHLocalization.choose(
            english: english[index],
            norwegian: norwegian[index]
        )
    }

    private var trainingWeekSummary:
        String {
        selectedDays
            .sorted()
            .map { dayIndex in
                let kind =
                    resolvedWorkoutKind(
                        for: dayIndex
                    )

                return
                    "\(fullDayName(dayIndex)): \(kind.title)"
            }
            .joined(separator: " · ")
    }

    private func durationText(
        _ minutes: Int
    ) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        if remainder == 0 {
            return ATHLTHLocalization.choose(
                english:
                    "\(hours) h",
                norwegian:
                    "\(hours) t"
            )
        }

        return ATHLTHLocalization.choose(
            english:
                "\(hours) h \(remainder) min",
            norwegian:
                "\(hours) t \(remainder) min"
        )
    }

    private func conflictCard(
        _ conflict: TrainingPlan
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 11
        ) {
            Image(
                systemName:
                    "calendar.badge.exclamationmark"
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(
                ATHLTHTheme.premiumGold
            )
            .frame(width: 38, height: 38)
            .background(
                ATHLTHTheme.premiumGoldSoft,
                in: RoundedRectangle(
                    cornerRadius: 11,
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
                            "Overlaps with \(conflict.title)",
                        norwegian:
                            "Overlapper med \(conflict.title)"
                    )
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Move the start date or change the duration before creating the plan.",
                        norwegian:
                            "Flytt startdatoen eller endre varigheten før planen opprettes."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
        }
        .padding(14)
        .background(
            ATHLTHTheme.premiumGoldSoft
                .opacity(0.54),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var aiBuilderSeed:
        AIProgramBuilderSeed {
        let cleanLimitations =
            injuryFree
                ? ""
                : injuriesOrLimitations
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
        let detail =
            goalDetail
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        var focusNotes: [String] = [
            ATHLTHLocalization.choose(
                english:
                    "Primary goal: \(goal.title).",
                norwegian:
                    "Hovedmål: \(goal.title)."
            )
        ]

        if !detail.isEmpty {
            focusNotes.append(
                ATHLTHLocalization.choose(
                    english:
                        "Concrete target: \(detail).",
                    norwegian:
                        "Konkret mål: \(detail)."
                )
            )
        }

        if !selectedMuscles.isEmpty {
            focusNotes.append(
                ATHLTHLocalization.choose(
                    english:
                        "Prioritise these muscle groups: \(selectedMuscleTitles).",
                    norwegian:
                        "Prioriter disse muskelgruppene: \(selectedMuscleTitles)."
                )
            )
        }

        focusNotes.append(
            ATHLTHLocalization.choose(
                english:
                    "Preferred week: \(trainingWeekSummary).",
                norwegian:
                    "Ønsket treningsuke: \(trainingWeekSummary)."
            )
        )
        let exactSessions = selectedDays.sorted().map { day in
            "\(fullDayName(day)): \(resolvedWorkoutKind(for: day).title) – " +
            "\(resolvedWorkoutTitle(for: day)), \(resolvedWorkoutMinutes(for: day)) min"
        }
        focusNotes.append(
            "Respect the athlete's selected weekly workout structure and subtypes: " +
            exactSessions.joined(separator: "; ") +
            ". Do not ask the athlete to select days or workout count again."
        )

        if mode == .advanced,
           let secondaryFocus {
            focusNotes.append(
                ATHLTHLocalization.choose(
                    english:
                        "Focus split: \(focusWeight)% \(focus.title), \(100 - focusWeight)% \(secondaryFocus.title).",
                    norwegian:
                        "Fokusfordeling: \(focusWeight)% \(focus.title), \(100 - focusWeight)% \(secondaryFocus.title)."
                )
            )
        }

        if hasCompetitionDate &&
            mode == .advanced {
            focusNotes.append(
                ATHLTHLocalization.choose(
                    english:
                        "Target date: \(competitionDate.formatted(date: .abbreviated, time: .omitted)).",
                    norwegian:
                        "Måldato: \(competitionDate.formatted(date: .abbreviated, time: .omitted))."
                )
            )
        }

        let sessionMinutes: Int
        if mode == .advanced {
            sessionMinutes =
                max(
                    weeklyTimeBudgetMinutes /
                    max(selectedDays.count, 1),
                    20
                )
        } else {
            sessionMinutes = 60
        }

        // Location and equipment access are now chosen per day, not guessed
        // from a plan-wide selector. Do not seed gym access as "Yes".
        let seededGymAccess: String? = nil

        return AIProgramBuilderSeed(
            preferredTitle:
                title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            startDate: startDate,
            weekCount: weekCount,
            sessionsPerWeek:
                selectedDays.count,
            sessionDurationMinutes:
                min(sessionMinutes, 180),
            availableDays:
                selectedDays,
            trainingFocus:
                aiTrainingFocus,
            gymAccess:
                seededGymAccess,
            limitations:
                cleanLimitations,
            coachFocusNotes:
                focusNotes.joined(
                    separator: " "
                ),
            selectedGoalIDs: selectedGoalIDs,
            structuredWorkoutsByDay: mode == .advanced
                ? structuredWorkoutsByDay : [:],
            preferredWorkoutsByDay: mode == .advanced
                ? Dictionary(uniqueKeysWithValues: selectedDays.sorted().map { day in
                    (day, ATHLTHPlanDayPreference(
                        title: resolvedWorkoutTitle(for: day),
                        kind: resolvedWorkoutKind(for: day),
                        durationMinutes: resolvedWorkoutMinutes(for: day)
                    ))
                }) : [:],
            builderProfile: currentPlanBuilderProfile,
            planVisibility: visibility,
            planSummary: planSummary
        )
    }

    private var aiTrainingFocus:
        TrainingFocus {
        switch focus {
        case .generalFitness:
            return .generalFitness
        case .strength,
             .hypertrophy:
            return .strength
        case .running,
             .endurance:
            return .running
        case .hybrid:
            return .hybrid
        case .mobilityRehab:
            return .recovery
        }
    }

    /// One authoritative set of plan preferences for both standard saving
    /// and AI-assisted advanced plan creation.
    private var currentPlanBuilderProfile: TrainingPlanBuilderProfile {
        let cleanLimitations =
            injuriesOrLimitations
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        let cleanGoalDetail =
            goalDetail
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        return
            TrainingPlanBuilderProfile(
                mode: mode,
                primaryFocus: focus,
                secondaryFocus: secondaryFocus,
                primaryFocusWeightPercent:
                    secondaryFocus != nil ? focusWeight : nil,
                goal: goal,
                goalDetail:
                    cleanGoalDetail.isEmpty
                        ? nil
                        : cleanGoalDetail,
                competitionDate:
                    hasCompetitionDate ? competitionDate : nil,
                sessionsPerWeek:
                    selectedDays.count,
                preferredDayIndexes:
                    selectedDays.sorted(),
                injuriesOrLimitations:
                    injuryFree ||
                    cleanLimitations.isEmpty
                        ? nil
                        : cleanLimitations,
                priorityMuscles:
                    orderedPriorityMuscles,
                equipmentContext: nil,
                // Basic no longer asks for a duration. Let each activity
                // receive an editable suggestion from the workout builder
                // instead of forcing an unseen 30-minute time budget.
                weeklyTimeBudgetMinutes: nil,
                simpleWorkoutKinds: mode == .basic ? orderedSimpleActivities : nil,
                preferredWorkoutKindsByDay:
                    mode == .advanced ? Dictionary(
                        uniqueKeysWithValues:
                            selectedDays.sorted().map {
                                ($0, resolvedWorkoutKind(for: $0))
                            }
                    ) : nil,
                preferredWorkoutTitlesByDay:
                    mode == .advanced ? Dictionary(
                        uniqueKeysWithValues:
                            selectedDays.sorted().map {
                                ($0, resolvedWorkoutTitle(for: $0))
                            }
                    ) : nil,
                preferredWorkoutMinutesByDay: mode == .advanced && !workoutMinutesByDay.isEmpty
                    ? workoutMinutesByDay : nil
            )

    }

    private func createPlan(
        seedSuggestedWeek: Bool
    ) {
        guard canCreatePlan else {
            return
        }

        if mode == .basic {
            // The activity mix is derived from the goal step. Rebuild day
            // suggestions without replacing the selected goal focus, e.g.
            // Endurance or General Fitness, with an inferred category.
            setSimpleKinds()
        }

        let profile = currentPlanBuilderProfile

        let created =
            session
                .createConfiguredTrainingPlan(
                    title: resolvedPlanTitle,
                    summary: planSummary,
                    weekCount: weekCount,
                    startDate: startDate,
                    endDate: resolvedEndDate,
                    visibility: visibility,
                    builderProfile: profile,
                    seedSuggestedWeek: seedSuggestedWeek,
                    structuredWorkoutsByDay: mode == .advanced
                        ? structuredWorkoutsByDay : [:],
                    weekDayEdits: mode == .advanced ? weekDayEdits : [:]
                )

        guard let created else {
            if let conflict =
                conflictingPlan {
                creationError =
                    ATHLTHLocalization.choose(
                        english:
                            "This period overlaps with \(conflict.title). Adjust the dates and try again.",
                        norwegian:
                            "Perioden overlapper med \(conflict.title). Endre datoene og prøv igjen."
                    )
            } else {
                creationError =
                    ATHLTHLocalization.choose(
                        english:
                            "ATHLTH could not create the plan. Check the details and try again.",
                        norwegian:
                            "ATHLTH kunne ikke opprette planen. Kontroller oppsettet og prøv igjen."
                    )
            }
            return
        }

        if !selectedGoalIDs.isEmpty {
            goalStore.setLinkedPlan(
                created.id,
                goalIDs: selectedGoalIDs
            )
        }

        // Open the real day-by-day planner directly after saving so the
        // user can immediately add exercises, edit days and review the week.
        createdPlanID = created.id
        completedPlanCreation = true
        draftStore.clear(userID: session.profile.userID, draftID: draftID)
        showingCreatedPlan = true
    }
}
