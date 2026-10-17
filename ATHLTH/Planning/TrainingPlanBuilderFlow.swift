import SwiftUI

struct ATHLTHTrainingPlanBuilderFlow: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    let startsAtSourceChoice: Bool
    let initialAdvanced: Bool
    var onCreated: ((UUID) -> Void)? = nil

    @State private var step: BuilderStep
    @State private var mode: TrainingPlanBuilderMode
    @State private var selectedSource: SourceOption = .scratch
    @State private var sourceRoute: [ExistingPlanDestination] = []

    @State private var title = ""

    private var defaultPlanTitle: String {
        ATHLTHLocalization.choose(english: "My training plan", norwegian: "Min treningsplan")
    }
    private var resolvedPlanTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultPlanTitle : trimmed
    }
    @State private var weekCount = 8
    @State private var startDate =
        ATHLTHTrainingPlanBuilderFlow.defaultStartDate()

    @State private var focus: TrainingPlanFocus = .generalFitness
    @State private var secondaryFocus: TrainingPlanFocus?
    @State private var focusWeight = 70
    @State private var goal: TrainingPlanGoalType = .improveFitness
    @State private var goalDetail = ""
    @State private var planSummary = ""

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
    @State private var weekDayEdits: [Int: ATHLTHPlanWeekDayEdit] = [:]
    @State private var weekPlanningApproach: ATHLTHPlanWeekPlanningApproach?
    @State private var guidedDayCursor = 0
    @State private var firstGuidedWeekDecisionMade = false
    @State private var repeatWeekCount = 1
    @State private var selectingLibraryDay: WeekDayEditorSelection?

    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    private struct WeekDayEditorSelection: Identifiable {
        let id: Int
    }

    @State private var equipment: EquipmentContext = .gym
    @State private var weeklyTimeBudgetMinutes = 240
    @State private var hasCompetitionDate = false
    @State private var competitionDate =
        Calendar.current.date(
            byAdding: .weekOfYear,
            value: 12,
            to: Date()
        ) ?? Date()
    @State private var visibility: ProfileVisibility = .privateOnly

    @State private var selectedGoalIDs: Set<UUID> = []
    @State private var creationError: String?
    @State private var createdPlanID: UUID?
    @State private var showingCreatedPlan = false
    @State private var showingAIBuilder = false
    @State private var didApplySuggestedStartDate = false
    @State private var showingPlanDesignLab = false
    @State private var resumablePlanDraft: ATHLTHPlanCreationDraft?
    @State private var showingResumePlanDialog = false
    @State private var completedPlanCreation = false

    private let draftStore = ATHLTHPlanCreationDraftStore()

    init(
        startsAtSourceChoice: Bool,
        initialAdvanced: Bool,
        onCreated: ((UUID) -> Void)? = nil
    ) {
        self.onCreated = onCreated
        self.startsAtSourceChoice =
            startsAtSourceChoice
        self.initialAdvanced =
            initialAdvanced
        // The entry screen always offers three clear starting paths.
        // The existing basics/profile/week/review steps remain intact.
        _step = State(initialValue: .mode)
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

                content
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "New training plan",
                    norwegian: "Ny treningsplan"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(step == .source || step == .mode ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                #if DEBUG
                if step != .source && step != .mode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingPlanDesignLab = true } label: {
                            Image(systemName: "paintpalette")
                        }
                        .accessibilityLabel("Plan Design Lab")
                    }
                }
                #endif
                if step != .source && step != .mode {
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
                        modeContinueBar
                    } else if step == .source {
                        sourceContinueBar
                    } else {
                        bottomActionBar
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
                if let createdPlanID,
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
        }
        .onAppear {
            guard !didApplySuggestedStartDate
            else {
                return
            }

            didApplySuggestedStartDate = true

            if let unfinished = draftStore.load(userID: session.profile.userID) {
                resumablePlanDraft = unfinished
                showingResumePlanDialog = true
                return
            }

            let suggested =
                session
                    .suggestedTrainingPlanStartDate
            let defaultDate =
                Self.defaultStartDate()

            startDate =
                max(
                    defaultDate,
                    Calendar.current
                        .startOfDay(
                            for: suggested
                        )
                )
        }
        .onChange(of: title) { _, _ in saveResumableDraft() }
        .onChange(of: weekCount) { _, _ in saveResumableDraft() }
        .onChange(of: startDate) { _, _ in saveResumableDraft() }
        .onChange(of: mode) { _, _ in saveResumableDraft() }
        .onChange(of: selectedSource) { _, _ in saveResumableDraft() }
        .onChange(of: workoutKindOverridesByDay) { _, _ in saveResumableDraft() }
        .onChange(of: workoutTitleOverridesByDay) { _, _ in saveResumableDraft() }
        .onChange(of: workoutMinutesByDay) { _, _ in saveResumableDraft() }
        .onChange(of: structuredWorkoutsByDay) { _, _ in saveResumableDraft() }
        .onChange(of: weekDayEdits) { _, _ in saveResumableDraft() }
        .onChange(of: weekPlanningApproach) { _, _ in saveResumableDraft() }
        .onChange(of: guidedDayCursor) { _, _ in saveResumableDraft() }
        .onChange(of: firstGuidedWeekDecisionMade) { _, _ in saveResumableDraft() }
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
        .onChange(of: weeklyTimeBudgetMinutes) { _, _ in saveResumableDraft() }
        .onChange(of: step) { _, _ in saveResumableDraft() }
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Continue your unfinished plan?",
                norwegian: "Fortsette på treningsplanen?"
            ),
            isPresented: $showingResumePlanDialog,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Continue plan", norwegian: "Fortsett på planen"
            )) {
                if let draft = resumablePlanDraft {
                    mode = draft.advanced ? .advanced : .basic
                    title = draft.usedDefaultTitle == true ? "" : draft.title
                    weekCount = draft.weekCount
                    // A stale date must never point back in time.
                    startDate = max(Calendar.current.startOfDay(for: Date()), draft.startDate)
                    switch draft.source {
                    case "library": selectedSource = .library
                    case "saved": selectedSource = .saved
                    default: selectedSource = .scratch
                    }
                    if draft.advanced {
                        if let days = draft.preferredDayIndexes, !days.isEmpty {
                            selectedDays = Set(days)
                            sessionsPerWeek = days.count
                        }
                        if let savedEquipment = draft.equipmentContext,
                           let restoredEquipment = EquipmentContext(rawValue: savedEquipment) {
                            equipment = restoredEquipment
                        }
                        if let minutes = draft.weeklyTimeBudgetMinutes {
                            weeklyTimeBudgetMinutes = minutes
                        }
                        workoutKindOverridesByDay = (draft.workoutKindsByDay ?? [:])
                            .compactMapValues(WorkoutKind.init(rawValue:))
                        workoutTitleOverridesByDay = draft.workoutPresetsByDay ?? [:]
                        workoutMinutesByDay = draft.workoutMinutesByDay ?? [:]
                        structuredWorkoutsByDay = draft.structuredWorkoutsByDay ?? [:]
                        weekDayEdits = draft.weekDayEdits ?? [:]
                        weekPlanningApproach = draft.planningApproach.flatMap(ATHLTHPlanWeekPlanningApproach.init(rawValue:))
                        guidedDayCursor = min(max(0, draft.guidedDayCursor ?? 0), weekCount * 7)
                        firstGuidedWeekDecisionMade = draft.firstGuidedWeekDecisionMade ?? false
                    }
                    // We intentionally resume the basics step so any goals,
                    // limitations and AI permissions must be reconfirmed.
                    step = .basics
                }
                resumablePlanDraft = nil
                showingResumePlanDialog = false
                saveResumableDraft()
            }
            Button(ATHLTHLocalization.choose(
                english: "Start a new plan", norwegian: "Start ny plan"
            ), role: .destructive) {
                draftStore.clear(userID: session.profile.userID)
                resumablePlanDraft = nil
                showingResumePlanDialog = false
            }
        } message: {
            Text(ATHLTHLocalization.choose(
                english: "This device saved your plan basics and non-sensitive schedule choices. Health notes and personal goals were not saved.",
                norwegian: "Denne enheten lagret grunninfo og treningsdager. Helsedata og personlige mål ble ikke lagret."
            ))
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
                seed: aiBuilderSeed,
                onProgramCreatedPlanID: { id in
                    createdPlanID = id
                    completedPlanCreation = true
                    draftStore.clear(userID: session.profile.userID)
                }
            )
        }
        .sheet(item: $editingWeekDay) { selection in
            planDayActionsSheet(for: selection.id)
        }
        .sheet(item: $selectingLibraryDay) { selection in
            ATHLTHPlanWorkoutLibraryPicker { workout in
                assignLibraryWorkout(workout, to: selection.id)
                selectingLibraryDay = nil
            }
        }
        .sheet(item: $composingAdvancedDay) { selection in
            WorkoutTemplateBuilderView(
                initialTitle: effectiveDetailedWorkout(for: selection.id)?.title ?? "",
                initialBlocks: effectiveDetailedWorkout(for: selection.id)?.blocks ?? [],
                initialRouteID: effectiveDetailedWorkout(for: selection.id)?.routeID,
                draftContext: "new-program-week-\(selectedPlanWeekIndex)-day-\(selection.id)",
                plannedDate: dateForWeekDay(selection.id, weekIndex: selectedPlanWeekIndex),
                onSaveToPlan: { name, blocks, routeID, minutes, _ in
                    let proposed = ATHLTHPlanStructuredWorkoutBlueprint(
                        title: name,
                        kind: workoutKind(for: blocks),
                        durationMinutes: minutes ?? 45,
                        routeID: routeID,
                        blocks: blocks
                    )
                    guard proposed.isValid else { return }
                    updateWeekDay(selection.id) { edit in
                        edit.isRestDay = false
                        edit.detailedWorkout = proposed
                        edit.removeTemplateDetail = false
                        edit.kind = proposed.kind
                        edit.title = name
                        edit.durationMinutes = proposed.durationMinutes
                    }
                }
            )
        }
    }

    private enum ExistingPlanDestination: Hashable {
        case library
        case mine
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .mode:
            modeChoice
        case .source:
            sourceChoice
        case .basics:
            wizardScroll {
                if mode == .basic {
                    simpleBasicsStep
                } else {
                    basicsStep
                }
            }
        case .profile:
            wizardScroll {
                profileStep
            }
        case .week:
            wizardScroll {
                if mode == .advanced {
                    switch weekPlanningApproach {
                    case .none:
                        chooseWeekPlanningApproach
                    case .some(.quick):
                        weekStep
                    case .some(.guided):
                        guidedWeekStep
                    }
                } else {
                    weekStep
                }
            }
        case .review:
            wizardScroll {
                reviewStep
            }
        }
    }

    private func wizardScroll<Content: View>(
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 16
            ) {
                progressHeader
                content()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 118)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private let sourceInk = ATHLTHPlanDesign.ink
    private let sourceMuted = ATHLTHPlanDesign.secondaryInk
    private let sourceGold = ATHLTHPlanDesign.accent
    private let sourceCanvas = ATHLTHPlanDesign.canvas

    private var stepDisplayTotal: Int {
        ATHLTHPlanJourney.sequence(advanced: mode == .advanced).count
    }

    private var stepDisplayNumber: Int {
        ATHLTHPlanJourney.position(of: step, advanced: mode == .advanced) ?? 1
    }

    private var modeChoice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sourceChoiceHeader
                    .padding(.bottom, 4)

                // An illustration adds warmth without displacing the choices
                // below the fold. It stays fully offline as SwiftUI artwork.
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(ATHLTHLocalization.choose(
                                english: "STEP 1 OF \(stepDisplayTotal)",
                                norwegian: "STEG 1 AV \(stepDisplayTotal)"
                            ))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(sourceGold)

                            Text(ATHLTHLocalization.choose(
                                english: "How would you like to plan?",
                                norwegian: "Hvordan vil du planlegge?"
                            ))
                            .font(.system(size: 31, weight: .regular, design: .serif))
                            .foregroundStyle(sourceInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.9)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ATHLTHPlanModeIllustration()
                            .frame(width: 145, height: 170)
                            .accessibilityHidden(true)
                            .padding(.trailing, -7)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "Choose how much control you want. Both options lead to an editable training plan.",
                        norwegian: "Velg hvor mye kontroll du ønsker. Begge alternativene gir deg en treningsplan du kan redigere."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(sourceMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }

                ATHLTHPlanEntryModeCard(
                    title: ATHLTHLocalization.choose(
                        english: "Simple", norwegian: "Enkel"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Get started quickly with just the essentials.",
                        norwegian: "Kom raskt i gang med kun det viktigste."
                    ),
                    symbol: "sparkles",
                    selected: mode == .basic,
                    features: [
                        .init(
                            symbol: "bolt.fill",
                            title: ATHLTHLocalization.choose(
                                english: "Quick start", norwegian: "Rask oppstart"
                            )
                        ),
                        .init(
                            symbol: "list.bullet",
                            title: ATHLTHLocalization.choose(
                                english: "Ready templates", norwegian: "Faste maler"
                            )
                        ),
                        .init(
                            symbol: "pencil",
                            title: ATHLTHLocalization.choose(
                                english: "Easy edits", norwegian: "Enkel å redigere"
                            )
                        )
                    ]
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        mode = .basic
                    }
                }

                ATHLTHPlanEntryModeCard(
                    title: ATHLTHLocalization.choose(
                        english: "Advanced", norwegian: "Avansert"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Choose goals, equipment, training days and detailed program structure.",
                        norwegian: "Velg mål, utstyr, treningsdager og detaljert programstruktur."
                    ),
                    symbol: "slider.horizontal.3",
                    selected: mode == .advanced,
                    features: [
                        .init(
                            symbol: "chart.bar",
                            title: ATHLTHLocalization.choose(
                                english: "Tailored plan", norwegian: "Skreddersydd"
                            )
                        ),
                        .init(
                            symbol: "gearshape",
                            title: ATHLTHLocalization.choose(
                                english: "More settings", norwegian: "Flere valg"
                            )
                        ),
                        .init(
                            symbol: "slider.horizontal.3",
                            title: ATHLTHLocalization.choose(
                                english: "Full control", norwegian: "Full kontroll"
                            )
                        )
                    ]
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        mode = .advanced
                    }
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(sourceGold.opacity(0.26))
                            .frame(height: 0.7)
                        Text(ATHLTHLocalization.choose(
                            english: "ALREADY HAVE A PLAN?",
                            norwegian: "HAR DU EN PLAN FRA FØR?"
                        ))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(sourceMuted)
                        .fixedSize()
                        Rectangle()
                            .fill(sourceGold.opacity(0.26))
                            .frame(height: 0.7)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            existingPlanLibraryButton
                            existingMyPlansButton
                        }
                        VStack(spacing: 10) {
                            existingPlanLibraryButton
                            existingMyPlansButton
                        }
                    }
                }
                .padding(.top, 5)
            }
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 25)
        }
        .scrollIndicators(.hidden)
        .background(sourceCanvas.ignoresSafeArea())
    }

    private var existingPlanLibraryButton: some View {
        ATHLTHPlanExistingChoice(
            title: ATHLTHLocalization.choose(
                english: "Plan library", norwegian: "Planbibliotek"
            ),
            subtitle: ATHLTHLocalization.choose(
                english: "Explore ready plans", norwegian: "Utforsk ferdige planer"
            ),
            symbol: "square.stack.3d.up"
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
            symbol: "bookmark"
        ) {
            sourceRoute.append(.mine)
        }
    }

    private var modeContinueBar: some View {
        Button {
            if mode == .basic {
                // Establish the simple defaults once at actual continuation.
                // Merely selecting a card must not mutate a plan or navigate.
                updateSimplePlanChoices()
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
        VStack(spacing: 22) {
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
            return ATHLTHLocalization.choose(
                english: "Goal & needs",
                norwegian: "Mål og behov"
            )
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

    // The simple route deliberately has no technical settings, date picker,
    // AI prompt or extra confirmation step. Advanced keeps the full wizard.
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

    private var simpleBasicsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(ATHLTHLocalization.choose(
                english: "Let's make a plan for you",
                norwegian: "La oss lage en plan for deg"
            ))
            .font(.system(size: 30, weight: .semibold, design: .serif))
            .foregroundStyle(ATHLTHPlanDesign.ink)

            Text(ATHLTHLocalization.choose(
                english: "Just three choices. You can change your plan later.",
                norwegian: "Bare tre enkle valg. Du kan endre planen senere."
            ))
            .font(.subheadline)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            simpleQuestion(
                ATHLTHLocalization.choose(english: "What would you like to do?", norwegian: "Hva vil du gjøre?")
            ) {
                Text(ATHLTHLocalization.choose(english: "You can choose more than one.", norwegian: "Du kan velge flere."))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                simpleChoice(ATHLTHLocalization.choose(english: "Go for walks", norwegian: "Gå tur"), symbol: "figure.walk", selected: simpleActivities.contains(.walking)) {
                    chooseSimpleActivity(.walking)
                }
                simpleChoice(ATHLTHLocalization.choose(english: "Go running", norwegian: "Løpe"), symbol: "figure.run", selected: simpleActivities.contains(.running)) {
                    chooseSimpleActivity(.running)
                }
                simpleChoice(ATHLTHLocalization.choose(english: "Build strength", norwegian: "Trene styrke"), symbol: "dumbbell", selected: simpleActivities.contains(.strength)) {
                    chooseSimpleActivity(.strength)
                }
            }

            simpleQuestion(
                ATHLTHLocalization.choose(english: "How many days each week?", norwegian: "Hvor mange dager i uken?")
            ) {
                HStack(spacing: 10) {
                    ForEach([1, 2, 3], id: \.self) { count in
                        simpleCompactChoice("\(count)", selected: selectedDays.count == count) {
                            setSimpleDays(count)
                        }
                    }
                }
                simpleChoice(ATHLTHLocalization.choose(english: "Choose yourself", norwegian: "Velg selv"), symbol: "calendar", selected: showingSimpleDays || selectedDays.count > 3) {
                    showingSimpleDays.toggle()
                }
                if showingSimpleDays {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 65))], spacing: 10) {
                        ForEach(1...7, id: \.self) { count in
                            simpleCompactChoice("\(count)", selected: selectedDays.count == count) {
                                setSimpleDays(count)
                            }
                        }
                    }
                }
            }

            simpleQuestion(
                ATHLTHLocalization.choose(english: "How long each time?", norwegian: "Hvor lenge hver gang?")
            ) {
                HStack(spacing: 10) {
                    ForEach([15, 30, 45], id: \.self) { minutes in
                        simpleCompactChoice("\(minutes) min", selected: simpleMinutes == minutes) {
                            simpleMinutes = minutes
                            weeklyTimeBudgetMinutes = minutes * selectedDays.count
                        }
                    }
                }
                simpleChoice(ATHLTHLocalization.choose(english: "Choose yourself", norwegian: "Velg selv"), symbol: "clock", selected: showingSimpleDuration || ![15, 30, 45].contains(simpleMinutes)) {
                    showingSimpleDuration.toggle()
                }
                if showingSimpleDuration {
                    HStack(spacing: 16) {
                        Button {
                            simpleMinutes = max(5, simpleMinutes - 5)
                        } label: {
                            Image(systemName: "minus")
                                .font(.title2.weight(.semibold))
                                .frame(width: 60, height: 60)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(simpleMinutes <= 5)
                        .accessibilityLabel(ATHLTHLocalization.choose(english: "Five minutes less", norwegian: "Fem minutter mindre"))
                        Text("\(simpleMinutes) min")
                            .font(.title2.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(ATHLTHLocalization.choose(english: "\(simpleMinutes) minutes each time", norwegian: "\(simpleMinutes) minutter hver gang"))
                        Button {
                            simpleMinutes = min(180, simpleMinutes + 5)
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .frame(width: 60, height: 60)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(simpleMinutes >= 180)
                        .accessibilityLabel(ATHLTHLocalization.choose(english: "Five minutes more", norwegian: "Fem minutter mer"))
                    }
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(
                    ATHLTHLocalization.choose(english: "Your plan", norwegian: "Planen din"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.headline)
                Text(simpleActivitySummary.capitalized)
                    .font(.subheadline.weight(.semibold))
                Text(ATHLTHLocalization.choose(
                    english: "\(selectedDays.count) times a week · \(simpleMinutes) minutes each time · 8 weeks",
                    norwegian: "\(selectedDays.count) ganger i uken · \(simpleMinutes) minutter hver gang · 8 uker"
                ))
                .font(.subheadline)
                Text(ATHLTHLocalization.choose(
                    english: "We'll spread the workouts across the week. You can change them later.",
                    norwegian: "Vi fordeler øktene utover uken. Du kan endre dem senere."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let conflict = conflictingPlan {
                conflictCard(conflict)
                Text(ATHLTHLocalization.choose(
                    english: "You already have a plan for these dates. Go back and choose Advanced to change the dates.",
                    norwegian: "Du har allerede en plan i denne perioden. Gå tilbake og velg Avansert hvis du vil endre datoene."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .onAppear {
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateSimplePlanChoices()
            }
        }
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
                selected ? ATHLTHTheme.accentDeep : Color.white.opacity(0.85),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
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
                    selected ? ATHLTHTheme.accentDeep : Color.white.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
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
        weekCount = 8
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

    private var basicsStep: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            stepIntro(
                eyebrow:
                    ATHLTHLocalization.choose(
                        english: "01 · PLAN BASICS",
                        norwegian: "01 · GRUNNINFO"
                    ),
                title:
                    ATHLTHLocalization.choose(
                        english: "Give the plan a frame",
                        norwegian: "Gi planen en ramme"
                    ),
                subtitle:
                    ATHLTHLocalization.choose(
                        english:
                            "A clear name, a start date and how long you want the plan to run.",
                        norwegian:
                            "Et tydelig navn, startdato og hvor lenge du vil følge planen."
                    ),
                icon: "calendar"
            )

            builderPanel {
                VStack(spacing: 14) {
                    fieldLabel(
                        ATHLTHLocalization.choose(
                            english: "Plan name",
                            norwegian: "Navn på planen"
                        )
                    )

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
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                    .onChange(of: title) {
                        _, newValue in
                        if newValue.count > 40 {
                            title =
                                String(
                                    newValue
                                        .prefix(40)
                                )
                        }
                    }

                    HStack {
                        Spacer()

                        Text("\(title.count)/40")
                            .font(.caption2)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                    }

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

                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "PLAN WINDOW",
                                    norwegian: "PLANPERIODE"
                                )
                            )
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "\(weekCount) weeks",
                                    norwegian:
                                        "\(weekCount) uker"
                                )
                            )
                            .font(.headline)
                        }

                        Spacer()

                        Text(
                            "\(startDate.formatted(date: .abbreviated, time: .omitted))\n– \(resolvedEndDate.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .multilineTextAlignment(
                            .trailing
                        )
                    }
                    .padding(12)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
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

                        Divider()

                        VStack(
                            alignment: .leading,
                            spacing: 7
                        ) {
                            fieldLabel(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Plan note",
                                    norwegian:
                                        "Kort planbeskrivelse"
                                )
                            )

                            TextField(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Optional context for the season or block",
                                    norwegian:
                                        "Valgfri beskrivelse av perioden"
                                ),
                                text: $planSummary,
                                axis: .vertical
                            )
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                Color.black
                                    .opacity(0.026),
                                in:
                                    RoundedRectangle(
                                        cornerRadius: 13,
                                        style: .continuous
                                    )
                            )
                        }
                    }
                }
            }
        }
    }

    private var durationOptions: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 64), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(
                [1, 2, 4, 6, 8, 12],
                id: \.self
            ) { value in
                Button {
                    weekCount = value
                } label: {
                    VStack(spacing: 2) {
                        Text("\(value)")
                            .font(.headline)
                        Text(
                            value == 1
                                ? ATHLTHLocalization.choose(
                                    english: "week",
                                    norwegian: "uke"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "weeks",
                                    norwegian: "uker"
                                )
                        )
                        .font(.caption2)
                    }
                    .foregroundStyle(
                        weekCount == value
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 52
                    )
                    .background(
                        weekCount == value
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

            Menu {
                ForEach(1...52, id: \.self) {
                    value in
                    Button(
                        ATHLTHLocalization.choose(
                            english:
                                value == 1 ? "1 week" : "\(value) weeks",
                            norwegian:
                                value == 1 ? "1 uke" : "\(value) uker"
                        )
                    ) {
                        weekCount = value
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(
                        systemName:
                            "ellipsis"
                    )
                    .font(.headline)

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Custom",
                            norwegian: "Egendefinert"
                        )
                    )
                    .font(.caption2)
                }
                .foregroundStyle(
                    [1, 2, 4, 6, 8, 12]
                        .contains(weekCount)
                        ? ATHLTHTheme.mutedText
                        : ATHLTHTheme.accentDeep
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 52
                )
                .background(
                    Color.white.opacity(0.72),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
            }
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
    private var chooseWeekPlanningApproach: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepIntro(
                eyebrow: ATHLTHLocalization.choose(english: "03 · YOUR APPROACH", norwegian: "03 · DIN PLANLEGGING"),
                title: ATHLTHLocalization.choose(english: "How do you want to plan?", norwegian: "Hvordan vil du planlegge?"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Both choices produce the same editable training plan.",
                    norwegian: "Begge valgene gir deg samme treningsplan, med mulighet for å endre alt senere."
                ),
                icon: "calendar.badge.plus"
            )
            ATHLTHPlanWeekApproachCard(
                icon: "calendar",
                title: ATHLTHLocalization.choose(english: "Quick week", norwegian: "Rask ukeplan"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Pick your days and start with a week overview. Add detail when you want.",
                    norwegian: "Velg treningsdager og start med ukeoversikten. Legg til detaljer når du vil."
                )
            ) {
                weekPlanningApproach = .quick
            }
            ATHLTHPlanWeekApproachCard(
                icon: "list.number",
                title: ATHLTHLocalization.choose(english: "Day by day", norwegian: "Bygg dag for dag"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Plan each date in order. After week one, copy it or continue.",
                    norwegian: "Planlegg én dag om gangen. Etter første uke kan du kopiere den eller fortsette."
                )
            ) {
                weekPlanningApproach = .guided
                guidedDayCursor = 0
                firstGuidedWeekDecisionMade = false
                repeatWeekCount = max(1, weekCount - 1)
            }
        }
    }

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
            edit.isRestDay || edit.detailedWorkout?.isValid != true
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

    private var guidedCurrentDayCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(ATHLTHLocalization.choose(english: "WEEK", norwegian: "UKE") + " \(guidedCurrentWeek + 1) / \(weekCount)")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(ATHLTHLocalization.choose(english: "DAY", norwegian: "DAG") +
                    " \((guidedDayCursor % 7) + 1) / 7")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(index <= guidedDayCursor % 7
                              ? ATHLTHPlanDesign.ink : ATHLTHPlanDesign.outline)
                        .frame(height: 5)
                }
            }
            stepIntro(
                eyebrow: guidedCurrentDate.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                title: ATHLTHLocalization.choose(english: "Plan this day", norwegian: "Planlegg denne dagen"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Build a full session, choose one from the library, or plan recovery.",
                    norwegian: "Bygg en full økt, velg en fra biblioteket eller legg inn hvile."
                ),
                icon: "calendar.day.timeline.left"
            )
            if let edit = weekDayEdits[weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)] {
                builderPanel {
                    Label(
                        edit.isRestDay
                            ? ATHLTHLocalization.choose(english: "Rest day chosen", norwegian: "Hviledag valgt")
                            : (edit.detailedWorkout?.title ?? ATHLTHLocalization.choose(english: "Workout chosen", norwegian: "Økt valgt")),
                        systemImage: edit.isRestDay ? "moon.stars" : "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    if let workout = edit.detailedWorkout {
                        Text("\(workout.blocks.count) " + ATHLTHLocalization.choose(english: "blocks", norwegian: "blokker") +
                             " · \(workout.durationMinutes) min")
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
            }
            ATHLTHPlanWeekApproachCard(
                icon: "plus.circle",
                title: ATHLTHLocalization.choose(english: "Build planned workout", norwegian: "Bygg planlagt økt"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Exercises, sets, intervals, rest and cool-down.",
                    norwegian: "Øvelser, sett, intervaller, pauser og nedtrapping."
                )
            ) {
                selectedPlanWeekIndex = guidedCurrentWeek
                composingAdvancedDay = WeekDayEditorSelection(id: guidedCurrentWeekday)
            }
            ATHLTHPlanWeekApproachCard(
                icon: "books.vertical",
                title: ATHLTHLocalization.choose(english: "Choose a complete workout", norwegian: "Velg komplett økt fra bibliotek"),
                subtitle: ATHLTHLocalization.choose(
                    english: "Use an existing multi-exercise workout and edit your planned copy.",
                    norwegian: "Hent en lagret økt med alle øvelsene og tilpass kopien i planen."
                )
            ) {
                selectedPlanWeekIndex = guidedCurrentWeek
                selectingLibraryDay = WeekDayEditorSelection(id: guidedCurrentWeekday)
            }
            ATHLTHPlanWeekApproachCard(
                icon: "moon.stars",
                title: ATHLTHLocalization.choose(english: "Rest day", norwegian: "Hviledag"),
                subtitle: ATHLTHLocalization.choose(
                    english: "No workout planned for this date.",
                    norwegian: "Ingen treningsøkt denne dagen."
                )
            ) {
                setRestDay(guidedCurrentWeekday)
            }
            Text(ATHLTHLocalization.choose(
                english: "Select a workout or rest day before continuing. Your choices are saved as a draft.",
                norwegian: "Velg en økt eller hviledag før du fortsetter. Valgene lagres som utkast."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
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
                         " · \(7 - firstWeekWorkoutCount) " +
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
            ) { firstGuidedWeekDecisionMade = true }
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

    private var firstWeekWorkoutCount: Int {
        (1...7).filter {
            let workout = weekDayEdits[weekDayKey($0, weekIndex: 0)]
            return workout?.isRestDay == false && workout?.detailedWorkout?.isValid == true
        }.count
    }

    private func advanceGuidedDay() {
        guard guidedDayCursor < weekCount * 7,
              weekDayEdits[weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)] != nil else { return }
        guidedDayCursor += 1
        if guidedDayCursor == 7 {
            // A manually built plan only uses the days actually chosen in week one.
            let days = Set((1...7).filter {
                let edit = weekDayEdits[weekDayKey($0, weekIndex: 0)]
                return edit?.isRestDay == false && edit?.detailedWorkout?.isValid == true
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

    private func setRestDay(_ day: Int) {
        updateWeekDay(day) { edit in
            edit.isRestDay = true
            edit.detailedWorkout = nil
            edit.title = nil
            edit.kind = nil
            edit.durationMinutes = nil
            edit.removeTemplateDetail = true
        }
    }

    private func workoutKind(for blocks: [WorkoutTemplateBlock]) -> WorkoutKind {
        let runs = blocks.filter { $0.kind == .run }
        let hasStrength = blocks.contains { $0.kind == .exercise }
        let hasRunning = runs.contains { $0.cardioActivity != .walking }
        let hasWalking = runs.contains { $0.cardioActivity == .walking }
        if hasStrength && !runs.isEmpty || (hasRunning && hasWalking) { return .custom }
        if hasRunning { return .running }
        if hasWalking { return .walking }
        return .strength
    }

    private func assignLibraryWorkout(_ workout: PlannedSession, to day: Int) {
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
            edit.detailedWorkout = blueprint
            edit.kind = blueprint.kind
            edit.title = blueprint.title
            edit.durationMinutes = blueprint.durationMinutes
            edit.removeTemplateDetail = false
        }
    }

    private func planDayActionsSheet(for day: Int) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text(dateForWeekDay(day, weekIndex: selectedPlanWeekIndex)
                         .formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Text(ATHLTHLocalization.choose(english: "Plan this day", norwegian: "Planlegg denne dagen"))
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    if let edit = weekDayEdits[weekDayKey(day)] {
                        Text(edit.isRestDay
                             ? ATHLTHLocalization.choose(english: "Rest day", norwegian: "Hviledag")
                             : (edit.detailedWorkout?.title ?? effectiveWorkoutTitle(for: day)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    ATHLTHPlanWeekApproachCard(
                        icon: "plus.circle",
                        title: ATHLTHLocalization.choose(english: "Build planned workout", norwegian: "Bygg planlagt økt"),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Create a detailed workout in ATHLTH Studio.",
                            norwegian: "Lag en detaljert treningsøkt i ATHLTH Studio."
                        )
                    ) {
                        editingWeekDay = nil
                        composingAdvancedDay = WeekDayEditorSelection(id: day)
                    }
                    ATHLTHPlanWeekApproachCard(
                        icon: "books.vertical",
                        title: ATHLTHLocalization.choose(english: "Choose complete workout", norwegian: "Velg komplett treningsøkt"),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Find saved workouts with all exercises and intervals.",
                            norwegian: "Hent lagrede økter med alle øvelser og intervaller."
                        )
                    ) {
                        editingWeekDay = nil
                        selectingLibraryDay = WeekDayEditorSelection(id: day)
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
                        HStack {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Training environment",
                                        norwegian:
                                            "Hvor trener du?"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Used for exercise choices later",
                                        norwegian:
                                            "Brukes til øvelsesvalg senere"
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                            }

                            Spacer()
                        }

                        HStack(spacing: 7) {
                            ForEach(
                                EquipmentContext.allCases
                            ) { item in
                                Button {
                                    equipment = item
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(
                                            systemName:
                                                item.icon
                                        )
                                        .font(.system(size: 14, weight: .semibold))

                                        Text(item.title)
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                    .foregroundStyle(
                                        equipment == item
                                            ? Color.white
                                            : ATHLTHTheme.primaryText
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 54
                                    )
                                    .background(
                                        equipment == item
                                            ? ATHLTHTheme.accentDeep
                                            : ATHLTHTheme.accentSoft,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius: 13,
                                                style: .continuous
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    selectedPlanWeekIndex = max(0, selectedPlanWeekIndex - 1)
                } label: { Image(systemName: "chevron.left") }
                    .disabled(selectedPlanWeekIndex == 0)
                Spacer()
                VStack(spacing: 2) {
                    Text(ATHLTHLocalization.choose(
                        english: "Week", norwegian: "Uke"
                    ) + " \(selectedPlanWeekIndex + 1) " +
                    ATHLTHLocalization.choose(english: "of", norwegian: "av") +
                    " \(weekCount)")
                        .font(.subheadline.weight(.semibold))
                    Text(calendarDate(for: selectedPlanWeekIndex, offset: 0)
                        .formatted(date: .abbreviated, time: .omitted) + " – " +
                        calendarDate(for: selectedPlanWeekIndex, offset: 6)
                        .formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                Spacer()
                Button {
                    selectedPlanWeekIndex = min(weekCount - 1, selectedPlanWeekIndex + 1)
                } label: { Image(systemName: "chevron.right") }
                    .disabled(selectedPlanWeekIndex >= weekCount - 1)
            }
            .buttonStyle(.plain)
            .padding(12)
            .background(ATHLTHTheme.accentSoft.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 14))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(0..<weekCount, id: \.self) { week in
                        Button {
                            selectedPlanWeekIndex = week
                        } label: {
                            HStack(spacing: 5) {
                                Text(ATHLTHLocalization.choose(english: "Week", norwegian: "Uke") +
                                     " \(week + 1)")
                                if weekDayEdits.keys.contains(where: { ($0 - 1) / 7 == week }) {
                                    Circle()
                                        .fill(week == selectedPlanWeekIndex
                                              ? Color.white : ATHLTHTheme.accentDeep)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(week == selectedPlanWeekIndex
                                             ? .white : ATHLTHTheme.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(week == selectedPlanWeekIndex
                                        ? ATHLTHTheme.accentDeep : Color.white,
                                        in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(1...7).sorted {
                        dateForWeekDay($0, weekIndex: selectedPlanWeekIndex) <
                        dateForWeekDay($1, weekIndex: selectedPlanWeekIndex)
                    }, id: \.self) { day in
                        Button {
                            editingWeekDay = WeekDayEditorSelection(id: day)
                        } label: {
                            VStack(spacing: 5) {
                                Text(shortDayName(day))
                                    .font(.caption2.weight(.medium))
                                Text(dateForWeekDay(day, weekIndex: selectedPlanWeekIndex)
                                    .formatted(.dateTime.day()))
                                    .font(.subheadline.weight(.semibold))
                                Circle()
                                    .fill(selectedDays.contains(day)
                                          ? ATHLTHTheme.accentDeep : Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .frame(width: 44, height: 56)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(ATHLTHLocalization.choose(
                english: "Weeks repeat the template until you customize a date.",
                norwegian: "Ukene følger grunnmønsteret til du tilpasser en dato."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
    }

    private var weeklyPreview: some View {
        VStack(spacing: 8) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Your week, your workouts",
                    norwegian: "Din uke, dine økter"
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

            ForEach(Array(1...7).sorted {
                dateForWeekDay($0, weekIndex: selectedPlanWeekIndex) <
                dateForWeekDay($1, weekIndex: selectedPlanWeekIndex)
            }, id: \.self) { day in
                if selectedDays.contains(day) || weekDayEdits[weekDayKey(day)] != nil {
                    Button {
                        editingWeekDay = WeekDayEditorSelection(id: day)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: effectiveWorkoutKind(for: day).systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 44, height: 44)
                                .background(ATHLTHTheme.accentSoft,
                                            in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fullDayName(day) + " · " +
                                     dateForWeekDay(day, weekIndex: selectedPlanWeekIndex)
                                         .formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                Text(effectiveWorkoutTitle(for: day))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(effectiveWorkoutKind(for: day).title + " · " +
                                     "\(effectiveWorkoutMinutes(for: day)) min")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                if mode == .advanced,
                                   let workout = effectiveDetailedWorkout(for: day) {
                                    Label(
                                        "\(workout.blocks.count) " +
                                        ATHLTHLocalization.choose(
                                            english: "detailed blocks", norwegian: "øktblokker"
                                        ),
                                        systemImage: "checkmark.circle.fill"
                                    )
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 36, height: 36)
                                .background(ATHLTHTheme.accentSoft,
                                            in: Circle())
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        fullDayName(day) + ", " + effectiveWorkoutTitle(for: day) +
                        ". " + ATHLTHLocalization.choose(english: "Edit workout", norwegian: "Rediger økten")
                    )
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(ATHLTHTheme.recoveryBlue)
                            .frame(width: 44, height: 44)
                            .background(ATHLTHTheme.recoveryBlueSoft,
                                        in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fullDayName(day) + " · " +
                                 dateForWeekDay(day, weekIndex: selectedPlanWeekIndex)
                                     .formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.semibold))
                            Text(ATHLTHLocalization.choose(english: "Rest day", norwegian: "Hviledag"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(ATHLTHLocalization.choose(english: "Add", norwegian: "Legg til")) {
                            updateWeekDay(day) { edit in
                                edit.kind = resolvedWorkoutKind(for: day)
                                edit.title = resolvedWorkoutTitle(for: day)
                                edit.durationMinutes = resolvedWorkoutMinutes(for: day)
                            }
                            editingWeekDay = WeekDayEditorSelection(id: day)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.46),
                                in: RoundedRectangle(cornerRadius: 18))
                }
            }

            Label(ATHLTHLocalization.choose(
                english: "Tap a workout to choose its type, focus and duration. Your choices are used when creating the plan.",
                norwegian: "Trykk på en økt for å endre type, underkategori og varighet. Valgene brukes når planen opprettes."
            ), systemImage: "hand.tap")
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.top, 6)
        }
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

    private func legacyWeekDayEditSheet(for day: Int) -> some View {
        let kind = effectiveWorkoutKind(for: day)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(fullDayName(day).uppercased() + " · " +
                             dateForWeekDay(day, weekIndex: selectedPlanWeekIndex)
                                .formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        Text(ATHLTHLocalization.choose(
                            english: "Customize workout", norwegian: "Tilpass treningsøkten"
                        ))
                        .font(.title2.weight(.bold))
                    }

                    weekSelector

                    VStack(alignment: .leading, spacing: 13) {
                        Text(ATHLTHLocalization.choose(english: "Activity", norwegian: "Treningsform"))
                            .font(.subheadline.weight(.bold))
                        Picker(ATHLTHLocalization.choose(english: "Activity", norwegian: "Treningsform"),
                               selection: Binding(
                                get: { effectiveWorkoutKind(for: day) },
                                set: { newKind in
                                    updateWeekDay(day) { edit in
                                        edit.kind = newKind
                                        edit.title = nil
                                        edit.detailedWorkout = nil
                                        edit.removeTemplateDetail = true
                                        edit.isCustomTitle = false
                                    }
                                }
                               )) {
                            ForEach(selectableWorkoutKinds, id: \.self) { option in
                                Label(option.title, systemImage: option.systemImage)
                                    .tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(mode == .advanced && effectiveDetailedWorkout(for: day) != nil)
                    }
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(ATHLTHLocalization.choose(
                            english: "What kind of workout?", norwegian: "Hva slags økt?"
                        ))
                        .font(.subheadline.weight(.bold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                            ForEach(subtypeTitles(for: kind), id: \.self) { choice in
                                Button {
                                    updateWeekDay(day) { edit in
                                        edit.title = choice
                                        edit.isCustomTitle = choice == "Egendefinert"
                                        edit.removeTemplateDetail = true
                                        edit.detailedWorkout = nil
                                    }
                                } label: {
                                    Text(choice)
                                        .font(.caption.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(
                                            (effectiveWorkoutTitle(for: day) == choice ||
                                            (choice == "Egendefinert" &&
                                             weekDayEdits[weekDayKey(day)]?.isCustomTitle == true))
                                                ? .white : ATHLTHTheme.primaryText
                                        )
                                        .background(
                                            (effectiveWorkoutTitle(for: day) == choice ||
                                            (choice == "Egendefinert" &&
                                             weekDayEdits[weekDayKey(day)]?.isCustomTitle == true))
                                                ? ATHLTHTheme.accentDeep : ATHLTHTheme.accentSoft,
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if weekDayEdits[weekDayKey(day)]?.isCustomTitle == true {
                            TextField(
                                ATHLTHLocalization.choose(
                                    english: "Custom workout name", norwegian: "Navn på egen økt"
                                ),
                                text: Binding(
                                    get: {
                                        let name = weekDayEdits[weekDayKey(day)]?.title ?? ""
                                        return name == "Egendefinert" ? "" : name
                                    },
                                    set: { newName in
                                        updateWeekDay(day) { edit in
                                            edit.title = newName.isEmpty ? "Egendefinert" : newName
                                        }
                                    }
                                )
                            )
                            .textInputAutocapitalization(.sentences)
                            .padding(12)
                            .background(ATHLTHTheme.accentSoft.opacity(0.7),
                                        in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 9) {
                        Text(ATHLTHLocalization.choose(english: "Duration", norwegian: "Varighet"))
                            .font(.subheadline.weight(.bold))
                        Stepper(
                            "\(effectiveWorkoutMinutes(for: day)) min",
                            value: Binding(
                                get: { effectiveWorkoutMinutes(for: day) },
                                set: { newValue in
                                    updateWeekDay(day) { edit in edit.durationMinutes = newValue }
                                }
                            ),
                            in: 5...180,
                            step: 5
                        )
                    }
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))

                    if mode == .advanced {
                        VStack(alignment: .leading, spacing: 13) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "DETAILED WORKOUT", norwegian: "DETALJERT ØKT"
                                ),
                                systemImage: "square.stack.3d.up"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)

                            Text(ATHLTHLocalization.choose(
                                english: "Build warm-up, running, exercises, sets, supersets, intervals, recovery and cool-down right now, before saving the plan.",
                                norwegian: "Bygg oppvarming, løping, øvelser, sett, supersett, intervaller, pauser og nedtrapping nå – før du lagrer planen."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)

                            if let detail = effectiveDetailedWorkout(for: day) {
                                Label(
                                    "\(detail.blocks.count) " + ATHLTHLocalization.choose(
                                        english: "blocks ready", norwegian: "blokker klare"
                                    ),
                                    systemImage: "checkmark.seal.fill"
                                )
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .font(.subheadline.weight(.semibold))
                            }

                            Button {
                                composingAdvancedDay = WeekDayEditorSelection(id: day)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "dumbbell.fill")
                                    Text(effectiveDetailedWorkout(for: day) == nil
                                        ? ATHLTHLocalization.choose(
                                            english: "Build workout in ATHLTH Studio",
                                            norwegian: "Bygg økten i ATHLTH Studio"
                                          )
                                        : ATHLTHLocalization.choose(
                                            english: "Edit detailed workout",
                                            norwegian: "Rediger detaljert økt"
                                          ))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(15)
                                .background(ATHLTHTheme.accentDeep,
                                            in: RoundedRectangle(cornerRadius: 15))
                            }
                            .buttonStyle(.plain)

                            if effectiveDetailedWorkout(for: day) != nil {
                                Button(role: .destructive) {
                                    updateWeekDay(day) { edit in
                                        edit.detailedWorkout = nil
                                        edit.removeTemplateDetail = true
                                    }
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Remove detailed workout",
                                            norwegian: "Fjern detaljert økt"
                                        ),
                                        systemImage: "trash"
                                    )
                                    .font(.caption.weight(.medium))
                                }
                                Text(ATHLTHLocalization.choose(
                                    english: "To change the workout type, remove the detailed blocks first. This does not delete other days.",
                                    norwegian: "For å endre treningsform må du først fjerne de detaljerte blokkene. Andre dager påvirkes ikke."
                                ))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                        .padding(17)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(18)
            }
            .background(ATHLTHPremiumCanvas(accent: ATHLTHTheme.accent.opacity(0.18)))
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Edit day", norwegian: "Rediger dag"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")) {
                        editingWeekDay = nil
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $composingAdvancedDay) { selection in
                WorkoutTemplateBuilderView(
                    initialTitle: effectiveWorkoutTitle(for: selection.id),
                    initialBlocks: effectiveDetailedWorkout(for: selection.id)?.blocks ?? [],
                    initialRouteID: effectiveDetailedWorkout(for: selection.id)?.routeID,
                    draftContext: "new-program-week-\(selectedPlanWeekIndex)-day-\(selection.id)",
                    plannedDate: dateForWeekDay(selection.id, weekIndex: selectedPlanWeekIndex),
                    onSaveToPlan: { name, blocks, routeID, knownMinutes, _ in
                        guard mode == .advanced else {
                            return
                        }
                        // The detailed recipe belongs to this selected date.
                        // The weekly template remains unchanged for other weeks.
                        let containsRunning = blocks.contains {
                            $0.kind == .run && $0.cardioActivity != .walking
                        }
                        let containsWalking = blocks.contains {
                            $0.kind == .run && $0.cardioActivity == .walking
                        }
                        let containsStrength = blocks.contains { $0.kind == .exercise }
                        let workoutKind: WorkoutKind =
                            (containsStrength && (containsRunning || containsWalking)) ||
                            (containsRunning && containsWalking)
                                ? .custom
                                : containsRunning ? .running
                                : containsWalking ? .walking : .strength
                        let choice = ATHLTHPlanStructuredWorkoutBlueprint(
                            title: name,
                            kind: workoutKind,
                            durationMinutes: knownMinutes ?? effectiveWorkoutMinutes(for: selection.id),
                            routeID: routeID,
                            blocks: blocks
                        )
                        guard choice.isValid else { return }
                        updateWeekDay(selection.id) { edit in
                            edit.detailedWorkout = choice
                            edit.removeTemplateDetail = false
                            edit.kind = workoutKind
                            edit.title = name
                            edit.durationMinutes = choice.durationMinutes
                        }
                    }
                )
            }
        }
    }

    private var selectableWorkoutKinds:
        [WorkoutKind] {
        if mode == .basic {
            return [
                .strength,
                .running,
                .walking,
                .mobility
            ]
        }

        return [
            .strength,
            .running,
            .walking,
            .mobility,
            .recovery,
            .custom
        ]
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
                    Color.white.opacity(0.72)
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
                Color.white.opacity(
                    prominent ? 0.12 : 0.90
                ),
                lineWidth: 0.8
            )
        }
    }

    private func stepIntro(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 14
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 20,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.champagneSoft,
                            ATHLTHTheme.accentSoft
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(eyebrow)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.45)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
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
                        ATHLTHTheme.primaryText
                    )

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.94),
                    ATHLTHTheme.cardWarm
                        .opacity(0.44)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.92),
                lineWidth: 0.8
            )
        }
    }

    private func builderPanel<Content: View>(
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            content()
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    ATHLTHTheme.cardWarm
                        .opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.92),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(0.04),
            radius: 10,
            y: 5
        )
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
                                : (step == .week && weekPlanningApproach == .guided && guidedDayCursor >= weekCount * 7
                                    ? ATHLTHLocalization.choose(english: "Review plan", norwegian: "Se over planen")
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
                            ATHLTHTheme.accentDeep,
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
        case .source:
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
            return weekDayEdits[weekDayKey(guidedCurrentWeekday, weekIndex: guidedCurrentWeek)] != nil
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

    private func saveResumableDraft() {
        guard didApplySuggestedStartDate,
              !completedPlanCreation,
              resumablePlanDraft == nil else {
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
            preferredDayIndexes: mode == .advanced ? selectedDays.sorted() : nil,
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
            firstGuidedWeekDecisionMade: mode == .advanced ? firstGuidedWeekDecisionMade : nil
        )
        draftStore.save(draft, userID: session.profile.userID)
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

        let seededGymAccess: String?
        if mode == .advanced {
            switch equipment {
            case .gym, .both:
                seededGymAccess = "Yes"
            case .home:
                seededGymAccess = "No"
            }
        } else {
            seededGymAccess = nil
        }

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
                equipmentContext: equipment.rawValue,
                weeklyTimeBudgetMinutes:
                    weeklyTimeBudgetMinutes,
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
                preferredWorkoutMinutesByDay:
                    mode == .advanced ? Dictionary(
                        uniqueKeysWithValues:
                            selectedDays.sorted().map {
                                ($0, resolvedWorkoutMinutes(for: $0))
                            }
                    ) : nil
            )

    }

    private func createPlan(
        seedSuggestedWeek: Bool
    ) {
        guard canCreatePlan else {
            return
        }

        if mode == .basic {
            weekCount = 8
            updateSimplePlanChoices()
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
        draftStore.clear(userID: session.profile.userID)
        showingCreatedPlan = true
    }
}
