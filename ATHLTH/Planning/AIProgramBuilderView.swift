import SwiftUI

private enum AIProgramTimelineMode: String, CaseIterable, Identifiable {
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

/// What the athlete already chose for a weekday. AI can fill
/// exercises and running targets, but must not replace these decisions.
struct ATHLTHPlanDayPreference: Hashable {
    let title: String
    let kind: WorkoutKind
    let durationMinutes: Int
}

struct AIProgramBuilderSeed: Hashable {
    var preferredTitle: String
    var startDate: Date
    var weekCount: Int
    var sessionsPerWeek: Int
    var sessionDurationMinutes: Int
    var availableDays: Set<Int>
    var trainingFocus: TrainingFocus
    var gymAccess: String?
    var limitations: String
    var coachFocusNotes: String
    var selectedGoalIDs: Set<UUID>
    /// Advanced, user-authored sessions are authoritative and are applied
    /// to every week after AI generation. Basic always leaves this empty.
    var structuredWorkoutsByDay: [Int: ATHLTHPlanStructuredWorkoutBlueprint] = [:]
    var preferredWorkoutsByDay: [Int: ATHLTHPlanDayPreference] = [:]
    /// Retain the original wizard mode, focus and per-day choices. Without
    /// this metadata, AI-generated advanced plans can reopen as Basic.
    var builderProfile: TrainingPlanBuilderProfile? = nil
    var planVisibility: ProfileVisibility? = nil
    var planSummary: String? = nil

    func applyWizardMetadata(to plan: inout TrainingPlan) {
        guard let builderProfile else { return }
        plan.builderProfile = builderProfile
        if let planVisibility {
            plan.visibility = planVisibility
        }
        // Preserve Coach's specific explanation when it exists. The
        // wizard summary is a fallback, not permission to discard AI insight.
        if plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let planSummary,
           !planSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            plan.summary = planSummary
        }
    }
}

private struct CoachIntakePreferences: Codable, Equatable {
    var experience: String
    var trainingFocus: TrainingFocus
    var gymAccess: String
    var homeEquipment: Set<String>
    var otherEquipment: String
    var limitations: String
    var coachFocusNotes: String?
    var currentSessionsPerWeek: Int
    var useProfileInterests: Bool
    var sessionsPerWeek: Int
    var sessionDurationMinutes: Int
    var availableDays: Set<Int>
}

struct AIProgramBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var health: HealthKitManager

    let mode: AIProgramGenerationMode
    let seed: AIProgramBuilderSeed?
    let onProgramCreated: (() -> Void)?
    let onProgramCreatedPlanID: ((UUID) -> Void)?

    init(
        mode: AIProgramGenerationMode,
        seed: AIProgramBuilderSeed? = nil,
        onProgramCreated: (() -> Void)? = nil,
        onProgramCreatedPlanID: ((UUID) -> Void)? = nil
    ) {
        self.mode = mode
        self.seed = seed
        self.onProgramCreated = onProgramCreated
        self.onProgramCreatedPlanID = onProgramCreatedPlanID
    }

    @State private var selectedGoalIDs: Set<UUID> = []
    @State private var timelineMode: AIProgramTimelineMode = .weeks
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var weekCount = 8
    @State private var endDate = Calendar.current.date(
        byAdding: .weekOfYear,
        value: 8,
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()
    @State private var sessionsPerWeek = 4
    @State private var aiChoosesFrequency = false
    @State private var sessionDurationMinutes = 60
    @State private var availableDays: Set<Int> = Set(1...7)
    @State private var userNotes = ""
    @State private var coachFocusNotes = ""
    @State private var showingQuestions = true
    @State private var experience = ""
    @State private var trainingFocus: TrainingFocus = .generalFitness
    @State private var gymAccess = ""
    @State private var homeEquipment: Set<String> = []
    @State private var otherEquipment = ""
    @State private var limitations = ""
    @State private var shareLimitationsWithAI = false
    @State private var currentSessionsPerWeek = 0
    @State private var useProfileInterests = true
    @State private var standaloneIntake = ATHLTHAIProgramIntake()

    private let equipmentOptions = [
        "Bodyweight / no equipment", "Dumbbells", "Kettlebells",
        "Resistance bands", "Barbell & plates", "Bench", "Squat rack",
        "Pull-up bar", "Treadmill", "Exercise bike"
    ]
    private let muscleGroupOptions = [
        "Full body", "Legs", "Glutes", "Chest", "Back",
        "Shoulders", "Arms", "Core"
    ]
    private let injuryAreaOptions = [
        "Knees", "Feet / ankles", "Hips", "Back", "Shoulders",
        "Elbows", "Wrists / hands", "Neck", "Other"
    ]

    @State private var preview: AIProgramDraft?
    @State private var expandedPreviewWeeks: Set<Int> = []
    @State private var editingDraftWorkout: ATHLTHPlanDraftWorkoutSelection?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var didLoadDefaults = false
    @State private var completingPlanID: UUID?
    @State private var completingPlanVersion: Int?
    private enum CoachJourneyStage {
        case welcome, intake, generating, preview, ready
    }
    @State private var coachJourneyStage: CoachJourneyStage = .welcome
    @State private var coachPreviewWeek = 1
    @State private var coachSavedPlan: TrainingPlan?
    @State private var showingCoachGoalCreator = false
    @State private var coachGoalIDsBeforeCreation: Set<UUID> = []
    private var isStandaloneCoachJourney: Bool {
        mode == .generate && seed == nil
    }

    private let service = AIProgramService()
    private let dayNames = ["M", "T", "W", "T", "F", "S", "S"]

    private var selectedGoals: [ATHLTHGoal] {
        goalStore.goals.filter { selectedGoalIDs.contains($0.id) }
    }

    private var resolvedWeeks: Int {
        switch timelineMode {
        case .weeks:
            return min(max(weekCount, 1), 52)
        case .endDate:
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: max(endDate, startDate))
            let days = max(
                calendar.dateComponents([.day], from: start, to: end).day ?? 0,
                0
            )
            return min(max(Int(ceil(Double(days + 1) / 7.0)), 1), 52)
        }
    }

    private var resolvedEndDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(resolvedWeeks * 7 - 1, 0),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private func draftValidationIssues(_ draft: AIProgramDraft) -> [String] {
        let lockedDays: Set<String>
        if mode == .complete {
            lockedDays = Set(
                existingDays
                    .filter { !$0.existingSessions.isEmpty }
                    .map { "\($0.weekNumber):\($0.dayIndex)" }
            )
        } else {
            lockedDays = []
        }
        let limit = aiChoosesFrequency && mode == .generate
            ? availableDays.count
            : sessionsPerWeek
        return ATHLTHPlanDraftValidator.issues(
            in: draft,
            expectedWeeks: resolvedWeeks,
            allowedDayIndexes: availableDays,
            maximumSessionsPerWeek: limit,
            lockedDayKeys: lockedDays,
            requireFullWeeks: true
        )
    }

    private var canGenerate: Bool {
        if isStandaloneCoachJourney {
            return standaloneIntake.isComplete && !isGenerating
        }
        return (seed != nil || questionsAnswered) &&
            !availableDays.isEmpty &&
            sessionsPerWeek >= 1 &&
            !isGenerating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if isStandaloneCoachJourney {
                        standaloneCoachContent
                    } else {
                        coachHero
                    }

                    if !isStandaloneCoachJourney && seed != nil && mode == .generate {
                        // The upstream wizard already collected duration,
                        // goals, sessions and days. Never ask them twice.
                        seededPlanSummary
                        if preview == nil {
                            seededCoachFineTuning
                        }
                        if let preview {
                            previewSection(preview)
                        } else {
                            generateCard
                        }
                    } else if !isStandaloneCoachJourney && showingQuestions {
                        coachQuestions
                    } else if !isStandaloneCoachJourney {
                        coachSummary
                        goalsSection
                        timelineSection
                            .disabled(mode == .complete)
                        availabilitySection
                        preferencesSection

                        if let preview {
                            previewSection(preview)
                        } else {
                            generateCard
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 36)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.champagne.opacity(0.20)
                )
            )
            .disabled(isGenerating)
            .onChange(of: coachContext) { _, _ in
                if coachJourneyStage != .ready { preview = nil }
            }
            .onChange(of: intakePreferences) { _, value in
                guard didLoadDefaults, session.signedIn else { return }
                AccountLocalStorage.write(
                    value,
                    name: "coach",
                    userID: session.profile.userID
                )
            }
            .navigationTitle("ATHLTH Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                loadDefaultsIfNeeded()
            }
            .alert(
                "AI Program",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { shown in
                        if !shown { errorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .sheet(isPresented: $showingCoachGoalCreator, onDismiss: {
            if let created = goalStore.activeGoals.first(where: {
                !coachGoalIDsBeforeCreation.contains($0.id) && $0.status == .active
            }) {
                selectedGoalIDs.insert(created.id)
            }
            coachGoalIDsBeforeCreation.removeAll()
        }) {
            GoalCreationView()
        }
        .sheet(item: $editingDraftWorkout) { selection in
            if let draft = preview,
               let workout = ATHLTHPlanDraftEditing.workout(in: draft, selection: selection) {
                ATHLTHPlanDraftWorkoutEditor(workout: workout) { modifiedWorkout in
                    guard let changed = ATHLTHPlanDraftEditing.replacing(
                        in: draft, selection: selection, with: modifiedWorkout
                    ), draftValidationIssues(changed).isEmpty else {
                        errorMessage = ATHLTHLocalization.choose(
                            english: "This change is not valid. The draft was not modified.",
                            norwegian: "Endringen er ugyldig. Utkastet ble ikke endret."
                        )
                        return
                    }
                    preview = changed
                }
            }
        }
    }

    // The standalone Coach journey uses real AIProgramService drafts.
    // The legacy completion flow and seeded Wizard Coach stay untouched.
    @ViewBuilder
    private var standaloneCoachContent: some View {
        switch coachJourneyStage {
        case .welcome:
            ATHLTHCoachPlanWelcomeScreen {
                withAnimation(.easeInOut(duration: 0.2)) {
                    coachJourneyStage = .intake
                }
            }
        case .intake:
            coachPlanIntake
        case .generating:
            ATHLTHCoachPlanGeneratingScreen()
        case .preview:
            if let preview {
                ATHLTHCoachPlanDraftScreen(
                    draft: preview,
                    startDate: startDate,
                    selectedWeek: $coachPreviewWeek,
                    onEditWorkout: { week, day, index in
                        editingDraftWorkout = ATHLTHPlanDraftWorkoutSelection(
                            weekNumber: week, dayIndex: day, sessionIndex: index
                        )
                    },
                    onRegenerate: {
                        Task { await generatePreview() }
                    },
                    onApprove: {
                        applyPreview(preview)
                    }
                )
            } else {
                coachPlanIntake
            }
        case .ready:
            if let coachSavedPlan {
                ATHLTHCoachPlanReadyScreen(plan: coachSavedPlan) {
                    dismiss()
                }
            }
        }
    }

    private var coachPlanIntake: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "PLAN FOUNDATION", norwegian: "GRUNNLAG FOR PLANEN"))
                    .font(.caption.bold())
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "Nothing is preselected",
                    norwegian: "Ingenting er forhåndsvalgt"
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }

            Text(ATHLTHLocalization.choose(
                english: "Tell Coach what you actually need.",
                norwegian: "Fortell Coach hva du faktisk trenger."))
                .font(.largeTitle)
                .fontDesign(.serif)

            Text(ATHLTHLocalization.choose(
                english: "Coach waits until the required choices are yours. A linked main goal is optional.",
                norwegian: "Coach venter til de nødvendige valgene er dine. Et koblet hovedmål er valgfritt."))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.secondary)

            coachIntakeCard("figure.mixed.cardio", ATHLTHLocalization.choose(
                english: "What do you want to train?", norwegian: "Hva ønsker du å trene?")) {
                coachChoiceGrid {
                    ForEach(TrainingFocus.profileSelectionCases) { focus in
                        coachToggleOption(
                            focus.title,
                            selected: standaloneIntake.trainingTypes.contains(focus)
                        ) {
                            toggleStandaloneTrainingType(focus)
                        }
                    }
                }

                Divider()

                Text(ATHLTHLocalization.choose(
                    english: "What do you want to achieve?",
                    norwegian: "Hva ønsker du å oppnå?"))
                    .font(.subheadline.bold())

                coachChoiceGrid {
                    ForEach(ATHLTHAIProgramIntake.Outcome.allCases) { outcome in
                        coachToggleOption(
                            outcome.title,
                            selected: standaloneIntake.outcomes.contains(outcome)
                        ) {
                            toggle(outcome, in: &standaloneIntake.outcomes)
                        }
                    }
                }

                if standaloneIntake.trainingTypes.contains(.strength) {
                    Divider()
                    Text(ATHLTHLocalization.choose(
                        english: "Muscle focus",
                        norwegian: "Muskelgrupper"))
                        .font(.subheadline.bold())
                    Text(ATHLTHLocalization.choose(
                        english: "Choose at least one, including full body if you do not want a narrower focus.",
                        norwegian: "Velg minst én. Velg hele kroppen dersom du ikke ønsker et smalere fokus."))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    coachChoiceGrid {
                        ForEach(muscleGroupOptions, id: \.self) { muscle in
                            coachToggleOption(
                                localizedMuscleGroup(muscle),
                                selected: standaloneIntake.muscleGroups.contains(muscle)
                            ) {
                                toggle(muscle, in: &standaloneIntake.muscleGroups)
                            }
                        }
                    }
                }

                if !goalStore.activeGoals.isEmpty {
                    Divider()
                    Text(ATHLTHLocalization.choose(
                        english: "Main goal (optional)",
                        norwegian: "Hovedmål (valgfritt)"))
                        .font(.subheadline.bold())
                    ForEach(goalStore.activeGoals) { goal in
                        Button {
                            if selectedGoalIDs.contains(goal.id) {
                                selectedGoalIDs.removeAll()
                            } else {
                                selectedGoalIDs = [goal.id]
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedGoalIDs.contains(goal.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                                Text(goal.title)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField(ATHLTHLocalization.choose(
                    english: "Other wishes for the plan (optional)",
                    norwegian: "Andre ønsker for planen (valgfritt)"),
                          text: $coachFocusNotes, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
            }

            coachIntakeCard("chart.bar.fill", ATHLTHLocalization.choose(
                english: "Experience", norwegian: "Erfaringsnivå")) {
                coachChoiceGrid {
                    ForEach(ATHLTHAIProgramIntake.Experience.allCases) { level in
                        coachToggleOption(
                            level.title,
                            selected: standaloneIntake.experience == level
                        ) {
                            standaloneIntake.experience = level
                        }
                    }
                }
                Stepper(ATHLTHLocalization.choose(
                    english: "Currently \(currentSessionsPerWeek) sessions per week",
                    norwegian: "Trener nå \(currentSessionsPerWeek) økter per uke"),
                        value: $currentSessionsPerWeek, in: 0...14)
            }

            coachIntakeCard("calendar", ATHLTHLocalization.choose(
                english: "Start, duration and training days",
                norwegian: "Start, varighet og treningsdager")) {
                DatePicker(ATHLTHLocalization.choose(
                    english: "Start date", norwegian: "Startdato"),
                           selection: $startDate,
                           in: Calendar.current.startOfDay(for: .now)...,
                           displayedComponents: .date)
                    .tint(ATHLTHTrainDesign.bronze)

                Text(ATHLTHLocalization.choose(
                    english: "Plan duration", norwegian: "Planens varighet"))
                    .font(.subheadline.bold())
                coachChoiceGrid {
                    ForEach([4, 6, 8, 12, 16, 24], id: \.self) { weeks in
                        coachToggleOption(
                            ATHLTHLocalization.format(
                                english: "%d weeks", norwegian: "%d uker", weeks),
                            selected: standaloneIntake.durationWeeks == weeks
                        ) {
                            standaloneIntake.durationWeeks = weeks
                        }
                    }
                }

                Text(ATHLTHLocalization.choose(
                    english: "Days you can train", norwegian: "Dager du kan trene"))
                    .font(.subheadline.bold())
                HStack(spacing: 5) {
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            toggleStandaloneDay(day)
                        } label: {
                            Text(["Man", "Tir", "Ons", "Tor", "Fre", "Lør", "Søn"][day - 1])
                                .font(.caption.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .foregroundStyle(
                                    standaloneIntake.availableDays.contains(day)
                                        ? .white : ATHLTHTrainDesign.ink
                                )
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    standaloneIntake.availableDays.contains(day)
                                        ? ATHLTHTrainDesign.bronze
                                        : ATHLTHTrainDesign.canvas,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            standaloneIntake.availableDays.contains(day)
                                ? .isSelected : []
                        )
                    }
                }

                Text(ATHLTHLocalization.choose(
                    english: "Sessions per week", norwegian: "Antall økter per uke"))
                    .font(.subheadline.bold())
                coachChoiceGrid {
                    ForEach(1...7, id: \.self) { count in
                        coachToggleOption(
                            "\(count)",
                            selected: standaloneIntake.sessionsPerWeek == count,
                            enabled: standaloneIntake.availableDays.count >= count
                        ) {
                            standaloneIntake.sessionsPerWeek = count
                        }
                    }
                }

                Text(ATHLTHLocalization.choose(
                    english: "Approximate time per session",
                    norwegian: "Omtrentlig tid per økt"))
                    .font(.subheadline.bold())
                coachChoiceGrid {
                    ForEach([20, 30, 45, 60, 75, 90], id: \.self) { minutes in
                        coachToggleOption(
                            "\(minutes) min",
                            selected: standaloneIntake.sessionDurationMinutes == minutes
                        ) {
                            standaloneIntake.sessionDurationMinutes = minutes
                        }
                    }
                }
            }

            coachIntakeCard("location.fill", ATHLTHLocalization.choose(
                english: "Where can you train?", norwegian: "Hvor kan du trene?")) {
                coachChoiceGrid {
                    ForEach(ATHLTHAIProgramIntake.Location.allCases) { location in
                        coachToggleOption(
                            location.title,
                            selected: standaloneIntake.locations.contains(location)
                        ) {
                            toggleStandaloneLocation(location)
                        }
                    }
                }

                if standaloneIntake.locations.contains(.gym) &&
                    standaloneIntake.locations.contains(.outdoors) {
                    Divider()
                    Text(ATHLTHLocalization.choose(
                        english: "Balance gym and outdoor training",
                        norwegian: "Fordel treningen mellom ute og gym"))
                        .font(.subheadline.bold())

                    if standaloneIntake.outdoorSharePercent == nil {
                        Button {
                            standaloneIntake.outdoorSharePercent = 50
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Set distribution",
                                norwegian: "Angi fordeling"),
                                  systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        let outdoorPercent = standaloneIntake.outdoorSharePercent ?? 50
                        HStack {
                            Text(ATHLTHLocalization.choose(
                                english: "Gym \(100 - outdoorPercent)%",
                                norwegian: "Gym \(100 - outdoorPercent)%"))
                            Spacer()
                            Text(ATHLTHLocalization.choose(
                                english: "Outdoors \(outdoorPercent)%",
                                norwegian: "Ute \(outdoorPercent)%"))
                        }
                        .font(.caption.bold())
                        Slider(
                            value: Binding(
                                get: {
                                    Double(standaloneIntake.outdoorSharePercent ?? 50)
                                },
                                set: {
                                    standaloneIntake.outdoorSharePercent = Int($0.rounded())
                                }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        .tint(ATHLTHTrainDesign.bronze)
                        .accessibilityValue("\(outdoorPercent) " +
                            ATHLTHLocalization.choose(
                                english: "percent outdoors",
                                norwegian: "prosent utendørs"))
                    }
                }

                Divider()
                Text(ATHLTHLocalization.choose(
                    english: "Equipment you can use",
                    norwegian: "Utstyr du har tilgang til"))
                    .font(.subheadline.bold())
                Text(ATHLTHLocalization.choose(
                    english: "Choose bodyweight if you do not have equipment.",
                    norwegian: "Velg kroppsvekt dersom du ikke har utstyr."))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                coachChoiceGrid {
                    ForEach(equipmentOptions, id: \.self) { equipment in
                        coachToggleOption(
                            localizedEquipment(equipment),
                            selected: standaloneIntake.equipment.contains(equipment)
                        ) {
                            toggle(equipment, in: &standaloneIntake.equipment)
                        }
                    }
                }
                TextField(ATHLTHLocalization.choose(
                    english: "Other equipment (optional)",
                    norwegian: "Annet utstyr (valgfritt)"),
                          text: $standaloneIntake.otherEquipment, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
            }

            coachIntakeCard("cross.case.fill", ATHLTHLocalization.choose(
                english: "Injuries and limitations",
                norwegian: "Skader og begrensninger")) {
                ForEach(ATHLTHAIProgramIntake.InjuryStatus.allCases) { status in
                    coachToggleOption(
                        status.title,
                        selected: standaloneIntake.injuryStatus == status
                    ) {
                        chooseInjuryStatus(status)
                    }
                }

                if standaloneIntake.injuryStatus == .considerations {
                    Divider()
                    Text(ATHLTHLocalization.choose(
                        english: "Affected areas", norwegian: "Berørte områder"))
                        .font(.subheadline.bold())
                    coachChoiceGrid {
                        ForEach(injuryAreaOptions, id: \.self) { area in
                            coachToggleOption(
                                localizedInjuryArea(area),
                                selected: standaloneIntake.injuryAreas.contains(area)
                            ) {
                                toggle(area, in: &standaloneIntake.injuryAreas)
                            }
                        }
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "How severe is it?", norwegian: "Hvor alvorlig er det?"))
                        .font(.subheadline.bold())
                    coachChoiceGrid {
                        ForEach(ATHLTHAIProgramIntake.InjurySeverity.allCases) { severity in
                            coachToggleOption(
                                severity.title,
                                selected: standaloneIntake.injurySeverity == severity
                            ) {
                                standaloneIntake.injurySeverity = severity
                            }
                        }
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "Required restriction", norwegian: "Påkrevd hensyn"))
                        .font(.subheadline.bold())
                    ForEach(ATHLTHAIProgramIntake.InjuryRestriction.allCases) { restriction in
                        coachToggleOption(
                            restriction.title,
                            selected: standaloneIntake.injuryRestriction == restriction
                        ) {
                            standaloneIntake.injuryRestriction = restriction
                        }
                    }

                    TextField(ATHLTHLocalization.choose(
                        english: "Describe pain, diagnosis or movements to avoid",
                        norwegian: "Beskriv smerte, diagnose eller bevegelser som må unngås"),
                              text: $standaloneIntake.injuryNotes, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)

                    Toggle(isOn: $standaloneIntake.healthSharingAuthorized) {
                        Text(ATHLTHLocalization.choose(
                            english: "I consent to share these health-related details with Coach",
                            norwegian: "Jeg samtykker til å dele disse helseopplysningene med Coach"))
                            .font(.subheadline)
                    }
                    .tint(ATHLTHTrainDesign.bronze)

                    Text(ATHLTHLocalization.choose(
                        english: "Coach can adapt training, but does not diagnose or replace qualified medical advice.",
                        norwegian: "Coach kan tilpasse trening, men stiller ikke diagnose og erstatter ikke kvalifisert helsehjelp."))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
            }

            if !standaloneIntake.validationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        ATHLTHLocalization.format(
                            english: "%d required choices remain",
                            norwegian: "%d nødvendige valg gjenstår",
                            standaloneIntake.validationIssues.count
                        ),
                        systemImage: "info.circle"
                    )
                    .font(.subheadline.bold())

                    ForEach(standaloneIntake.validationIssues, id: \.self) { issue in
                        Text("• \(localizedMissingRequirement(issue))")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ATHLTHTrainDesign.paleGold.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }

            Button {
                applyStandaloneIntakeToRequest()
                Task { await generatePreview() }
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Build my plan with Coach",
                    norwegian: "Lag planen min med Coach"),
                      systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(ATHLTHTrainDesign.bronze.gradient,
                                in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate)
            .opacity(canGenerate ? 1 : 0.5)
        }
    }

    @ViewBuilder
    private func coachChoiceGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            content()
        }
    }

    private func coachToggleOption(
        _ title: String,
        selected: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .foregroundStyle(selected ? .white : ATHLTHTrainDesign.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                selected ? ATHLTHTrainDesign.bronze : ATHLTHTrainDesign.canvas,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleStandaloneTrainingType(_ focus: TrainingFocus) {
        if standaloneIntake.trainingTypes.contains(focus) {
            standaloneIntake.trainingTypes.remove(focus)
        } else {
            if focus == .generalFitness {
                standaloneIntake.trainingTypes.removeAll()
            } else {
                standaloneIntake.trainingTypes.remove(.generalFitness)
            }
            standaloneIntake.trainingTypes.insert(focus)
        }
        if !standaloneIntake.trainingTypes.contains(.strength) {
            standaloneIntake.muscleGroups.removeAll()
        }
    }

    private func toggleStandaloneDay(_ day: Int) {
        if standaloneIntake.availableDays.contains(day) {
            standaloneIntake.availableDays.remove(day)
        } else {
            standaloneIntake.availableDays.insert(day)
        }
        if let count = standaloneIntake.sessionsPerWeek,
           count > standaloneIntake.availableDays.count {
            standaloneIntake.sessionsPerWeek = nil
        }
    }

    private func toggleStandaloneLocation(
        _ location: ATHLTHAIProgramIntake.Location
    ) {
        toggle(location, in: &standaloneIntake.locations)
        if !(standaloneIntake.locations.contains(.gym) &&
             standaloneIntake.locations.contains(.outdoors)) {
            standaloneIntake.outdoorSharePercent = nil
        }
    }

    private func chooseInjuryStatus(
        _ status: ATHLTHAIProgramIntake.InjuryStatus
    ) {
        standaloneIntake.injuryStatus = status
        if status == .none {
            standaloneIntake.injuryAreas.removeAll()
            standaloneIntake.injurySeverity = nil
            standaloneIntake.injuryRestriction = nil
            standaloneIntake.injuryNotes = ""
            standaloneIntake.healthSharingAuthorized = false
        }
    }

    private func toggle<Value: Hashable>(
        _ value: Value,
        in selection: inout Set<Value>
    ) {
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }

    private func applyStandaloneIntakeToRequest() {
        guard standaloneIntake.isComplete,
              let focus = standaloneIntake.resolvedTrainingFocus,
              let durationWeeks = standaloneIntake.durationWeeks,
              let requestedSessions = standaloneIntake.sessionsPerWeek,
              let requestedMinutes = standaloneIntake.sessionDurationMinutes
        else { return }

        trainingFocus = focus
        weekCount = durationWeeks
        timelineMode = .weeks
        sessionsPerWeek = requestedSessions
        aiChoosesFrequency = false
        availableDays = standaloneIntake.availableDays
        sessionDurationMinutes = requestedMinutes
        experience = standaloneIntake.experience?.rawValue ?? ""
        gymAccess = standaloneIntake.locations.map(\.title).sorted().joined(separator: ", ")
        homeEquipment = standaloneIntake.equipment
        otherEquipment = standaloneIntake.otherEquipment
        limitations = standaloneIntake.injuryNotes
        shareLimitationsWithAI =
            standaloneIntake.injuryStatus == .considerations &&
            standaloneIntake.healthSharingAuthorized
    }

    private func localizedMissingRequirement(_ issue: String) -> String {
        switch issue {
        case "trainingTypes":
            return ATHLTHLocalization.choose(english: "Choose what you want to train", norwegian: "Velg hva du ønsker å trene")
        case "outcomes":
            return ATHLTHLocalization.choose(english: "Choose what you want to achieve", norwegian: "Velg hva du ønsker å oppnå")
        case "muscleGroups":
            return ATHLTHLocalization.choose(english: "Choose muscle focus", norwegian: "Velg muskelgrupper")
        case "experience":
            return ATHLTHLocalization.choose(english: "Choose experience level", norwegian: "Velg erfaringsnivå")
        case "durationWeeks":
            return ATHLTHLocalization.choose(english: "Choose plan duration", norwegian: "Velg planens varighet")
        case "sessionsPerWeek":
            return ATHLTHLocalization.choose(english: "Choose sessions per week", norwegian: "Velg antall økter per uke")
        case "availableDays", "availableDayCount":
            return ATHLTHLocalization.choose(english: "Choose enough available training days", norwegian: "Velg nok tilgjengelige treningsdager")
        case "sessionDurationMinutes":
            return ATHLTHLocalization.choose(english: "Choose time per session", norwegian: "Velg tid per økt")
        case "locations":
            return ATHLTHLocalization.choose(english: "Choose training location", norwegian: "Velg treningssted")
        case "locationBalance":
            return ATHLTHLocalization.choose(english: "Set the gym/outdoor balance", norwegian: "Angi fordeling mellom ute og gym")
        case "equipment":
            return ATHLTHLocalization.choose(english: "Choose available equipment or bodyweight", norwegian: "Velg tilgjengelig utstyr eller kroppsvekt")
        case "injuryStatus":
            return ATHLTHLocalization.choose(english: "Confirm injury status", norwegian: "Bekreft skadestatus")
        case "injuryAreas":
            return ATHLTHLocalization.choose(english: "Choose affected areas", norwegian: "Velg berørte områder")
        case "injurySeverity":
            return ATHLTHLocalization.choose(english: "Choose injury severity", norwegian: "Velg hvor alvorlig skaden er")
        case "injuryRestriction":
            return ATHLTHLocalization.choose(english: "Choose the required restriction", norwegian: "Velg nødvendig treningshensyn")
        case "healthSharingAuthorized":
            return ATHLTHLocalization.choose(english: "Confirm sharing of injury details", norwegian: "Bekreft deling av skadeopplysninger")
        default:
            return ATHLTHLocalization.choose(english: "Complete the remaining choice", norwegian: "Fullfør gjenstående valg")
        }
    }

    private func localizedMuscleGroup(_ value: String) -> String {
        switch value {
        case "Full body": return ATHLTHLocalization.choose(english: value, norwegian: "Hele kroppen")
        case "Legs": return ATHLTHLocalization.choose(english: value, norwegian: "Bein")
        case "Glutes": return ATHLTHLocalization.choose(english: value, norwegian: "Sete")
        case "Chest": return ATHLTHLocalization.choose(english: value, norwegian: "Bryst")
        case "Back": return ATHLTHLocalization.choose(english: value, norwegian: "Rygg")
        case "Shoulders": return ATHLTHLocalization.choose(english: value, norwegian: "Skuldre")
        case "Arms": return ATHLTHLocalization.choose(english: value, norwegian: "Armer")
        case "Core": return ATHLTHLocalization.choose(english: value, norwegian: "Kjerne")
        default: return value
        }
    }

    private func localizedEquipment(_ value: String) -> String {
        switch value {
        case "Bodyweight / no equipment":
            return ATHLTHLocalization.choose(english: value, norwegian: "Kroppsvekt / uten utstyr")
        case "Dumbbells": return ATHLTHLocalization.choose(english: value, norwegian: "Manualer")
        case "Kettlebells": return ATHLTHLocalization.choose(english: value, norwegian: "Kettlebells")
        case "Resistance bands": return ATHLTHLocalization.choose(english: value, norwegian: "Strikker")
        case "Barbell & plates": return ATHLTHLocalization.choose(english: value, norwegian: "Vektstang og skiver")
        case "Bench": return ATHLTHLocalization.choose(english: value, norwegian: "Benk")
        case "Squat rack": return ATHLTHLocalization.choose(english: value, norwegian: "Knebøystativ")
        case "Pull-up bar": return ATHLTHLocalization.choose(english: value, norwegian: "Pull-up-stang")
        case "Treadmill": return ATHLTHLocalization.choose(english: value, norwegian: "Tredemølle")
        case "Exercise bike": return ATHLTHLocalization.choose(english: value, norwegian: "Spinningsykkel")
        default: return value
        }
    }

    private func localizedInjuryArea(_ value: String) -> String {
        switch value {
        case "Knees": return ATHLTHLocalization.choose(english: value, norwegian: "Knær")
        case "Feet / ankles": return ATHLTHLocalization.choose(english: value, norwegian: "Føtter / ankler")
        case "Hips": return ATHLTHLocalization.choose(english: value, norwegian: "Hofter")
        case "Back": return ATHLTHLocalization.choose(english: value, norwegian: "Rygg")
        case "Shoulders": return ATHLTHLocalization.choose(english: value, norwegian: "Skuldre")
        case "Elbows": return ATHLTHLocalization.choose(english: value, norwegian: "Albuer")
        case "Wrists / hands": return ATHLTHLocalization.choose(english: value, norwegian: "Håndledd / hender")
        case "Neck": return ATHLTHLocalization.choose(english: value, norwegian: "Nakke")
        case "Other": return ATHLTHLocalization.choose(english: value, norwegian: "Annet")
        default: return value
        }
    }

    private func coachIntakeCard<Content: View>(
        _ icon: String, _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 34, height: 34)
                    .background(ATHLTHTrainDesign.paleGold, in: Circle())
                Text(title).font(.system(size: 17, weight: .medium, design: .serif))
                Spacer()
            }
            content()
        }
        .padding(13)
        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
    }

    private func intakeOption(
        _ value: String, english: String, norwegian: String,
        selection: Binding<String>
    ) -> some View {
        let active = selection.wrappedValue == value
        return Button { selection.wrappedValue = value } label: {
            Text(ATHLTHLocalization.choose(english: english, norwegian: norwegian))
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : ATHLTHTrainDesign.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(active ? ATHLTHTrainDesign.bronze :
                            ATHLTHTrainDesign.canvas, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var seededPlanSummary: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "YOUR CHOSEN PLAN", norwegian: "DIN VALGTE PLAN"
                ))
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(ATHLTHTheme.mutedText)
                Spacer()
                Button(ATHLTHLocalization.choose(
                    english: "Change setup", norwegian: "Endre oppsett"
                )) {
                    dismiss()
                }
                .font(.caption.weight(.semibold))
            }

            Text(seed?.preferredTitle ?? "")
                .font(.title2.weight(.bold))
            HStack(spacing: 8) {
                coachChip("\(resolvedWeeks) " + ATHLTHLocalization.choose(
                    english: "weeks", norwegian: "uker"
                ))
                coachChip("\(sessionsPerWeek) " + ATHLTHLocalization.choose(
                    english: "sessions/week", norwegian: "økter/uke"
                ))
                // Session lengths can differ; the optional time budget is configured below.
            }

            Text(ATHLTHLocalization.choose(
                english: "Coach respects your goal, dates and available days. Set optional experience, equipment and time preferences below. Nothing is saved until you approve.",
                norwegian: "Coach tar hensyn til målet, datoene og dagene dine. Du kan legge til erfaring, utstyr og ønsket tidsramme nedenfor. Ingenting lagres før du godkjenner."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !availableDays.isEmpty {
                Text(availableDays.sorted().map { day in
                    ["Man", "Tir", "Ons", "Tor", "Fre", "Lør", "Søn"][
                        min(max(day - 1, 0), 6)
                    ]
                }.joined(separator: " · "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            if let locked = seed?.structuredWorkoutsByDay, !locked.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Your detailed sessions are protected",
                            norwegian: "Dine detaljerte økter blir bevart"
                        ), systemImage: "lock.shield.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    ForEach(locked.keys.sorted(), id: \.self) { day in
                        if let workout = locked[day] {
                            Text("\(day). \(workout.title) · \(workout.blocks.count) " +
                                 ATHLTHLocalization.choose(
                                    english: "blocks", norwegian: "blokker"
                                 ))
                            .font(.caption)
                        }
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "AI only fills the rest. These sessions are retained exactly when you approve the final plan.",
                        norwegian: "AI fyller bare resten. Disse øktene beholdes når du godkjenner planen."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(ATHLTHTheme.accentSoft.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(18)
        .background(.white.opacity(0.88),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Optional intake, shown only for AI started from the plan wizard.
    /// Unlike the old mandatory wizard profile, these answers are requested
    /// only when the athlete explicitly selects AI. Sensitive limitations
    /// are never submitted without the separate consent in generateCard.
    private var seededCoachFineTuning: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "Fine-tune your AI proposal",
                        norwegian: "Tilpass AI-forslaget"
                    ))
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    Text(ATHLTHLocalization.choose(
                        english: "Optional – your goals and training days are already set.",
                        norwegian: "Valgfritt – mål og treningsdager er allerede valgt."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
            }

            Picker(ATHLTHLocalization.choose(
                english: "Experience", norwegian: "Treningsnivå"
            ), selection: $experience) {
                Text(ATHLTHLocalization.choose(
                    english: "Not specified", norwegian: "Ikke angitt"
                )).tag("")
                Text(ATHLTHLocalization.choose(
                    english: "Beginner", norwegian: "Nybegynner"
                )).tag("Beginner")
                Text(ATHLTHLocalization.choose(
                    english: "Intermediate", norwegian: "Mosjonist"
                )).tag("Intermediate")
                Text(ATHLTHLocalization.choose(
                    english: "Experienced", norwegian: "Erfaren"
                )).tag("Experienced")
            }
            .tint(ATHLTHTrainDesign.bronze)

            Picker(ATHLTHLocalization.choose(
                english: "Where do you train?", norwegian: "Hvor trener du?"
            ), selection: $gymAccess) {
                Text(ATHLTHLocalization.choose(
                    english: "Not specified", norwegian: "Ikke angitt"
                )).tag("")
                Text(ATHLTHLocalization.choose(
                    english: "Gym access", norwegian: "Treningssenter"
                )).tag("Yes")
                Text(ATHLTHLocalization.choose(
                    english: "Home or outdoors", norwegian: "Hjemme eller utendørs"
                )).tag("No")
            }
            .tint(ATHLTHTrainDesign.bronze)

            HStack(spacing: 10) {
                Text(ATHLTHLocalization.choose(
                    english: "Suggested time per session",
                    norwegian: "Ønsket tid per økt"
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainDesign.ink)
                Spacer(minLength: 0)
                Menu {
                    ForEach([20, 30, 40, 45, 60, 75, 90, 120], id: \.self) { minutes in
                        Button("\(minutes) min") {
                            sessionDurationMinutes = minutes
                        }
                    }
                } label: {
                    Text("\(sessionDurationMinutes) min")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                }
            }

            DisclosureGroup(
                ATHLTHLocalization.choose(
                    english: "Equipment and other considerations",
                    norwegian: "Utstyr og andre hensyn"
                )
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(ATHLTHLocalization.choose(
                        english: "Available equipment, e.g. dumbbells",
                        norwegian: "Tilgjengelig utstyr, f.eks. manualer"
                    ), text: $otherEquipment, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)

                    TextField(ATHLTHLocalization.choose(
                        english: "Movements to avoid (optional)",
                        norwegian: "Bevegelser du vil unngå (valgfritt)"
                    ), text: $limitations, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)

                    Text(ATHLTHLocalization.choose(
                        english: "Health-related notes are shared only if you separately consent below.",
                        norwegian: "Helseopplysninger deles bare dersom du samtykker nedenfor."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                .padding(.top, 9)
            }
            .tint(ATHLTHTrainDesign.bronze)
        }
        .padding(16)
        .background(.white.opacity(0.93), in: RoundedRectangle(cornerRadius: 19))
    }

    private var coachHero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.93, blue: 0.84),
                    Color(red: 0.88, green: 0.92, blue: 0.82),
                    Color(red: 0.75, green: 0.84, blue: 0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.34))
                .frame(width: 180, height: 180)
                .offset(x: 190, y: -65)
                .blur(radius: 2)

            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR COACH")
                    .font(.caption2.weight(.bold))
                    .tracking(3)
                    .foregroundStyle(
                        ATHLTHTheme.primaryText.opacity(0.58)
                    )

                Text(
                    showingQuestions
                        ? "Build around\nyour life."
                        : "Your plan,\nmade personal."
                )
                .font(
                    .system(
                        size: 36,
                        weight: .bold,
                        design: .serif
                    )
                )
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineSpacing(-3)

                Text(
                    showingQuestions
                        ? "Tell ATHLTH what matters. We’ll combine it with your goals, schedule and training profile."
                        : "Review the inputs that shape your adaptive training plan before Coach builds it."
                )
                .font(.subheadline)
                .foregroundStyle(
                    ATHLTHTheme.primaryText.opacity(0.70)
                )
                .frame(maxWidth: 310, alignment: .leading)
            }
            .padding(22)
        }
        .frame(height: 250)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 30,
                style: .continuous
            )
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "figure.run")
                .font(.system(size: 88, weight: .ultraLight))
                .foregroundStyle(
                    ATHLTHTheme.primaryText.opacity(0.12)
                )
                .padding(24)
        }
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 18,
            y: 8
        )
    }

    private var coachSummary: some View {
        coachCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.champagneSoft,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your training profile")
                        .font(.headline)

                    HStack(spacing: 7) {
                        coachChip(experience)
                        coachChip(trainingFocus.title)
                        coachChip(
                            gymAccess == "Yes"
                                ? "Gym access"
                                : "Home / outdoors"
                        )
                    }

                    Button("Edit coach answers") {
                        showingQuestions = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(
                eyebrow: "PLAN DETAILS",
                title: "How should training fit?"
            )

            coachCard {
                if mode == .generate {
                    Toggle(isOn: $aiChoosesFrequency) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ATHLTHLocalization.choose(
                                english: "Let AI suggest workout frequency",
                                norwegian: "La AI foreslå antall økter"
                            ))
                            .font(.subheadline.weight(.semibold))
                            Text(ATHLTHLocalization.choose(
                                english: "Coach chooses a reasonable number of workouts based on your current level, goals and available days. Review everything before saving.",
                                norwegian: "Coach foreslår antall økter ut fra nivå, mål og tilgjengelige dager. Du kontrollerer alt før lagring."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    .tint(ATHLTHTheme.accentDeep)
                    .onChange(of: aiChoosesFrequency) { _, _ in preview = nil }
                    Divider()
                }

                if aiChoosesFrequency && mode == .generate {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "At most \(availableDays.count) workouts per week, only on your available days.",
                            norwegian: "Maks \(availableDays.count) økter per uke, kun på valgte dager."
                        ),
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                } else {
                    Stepper(
                        ATHLTHLocalization.choose(
                            english: "\(sessionsPerWeek) workouts per week",
                            norwegian: "\(sessionsPerWeek) økter per uke"
                        ),
                        value: $sessionsPerWeek,
                        in: 1...max(availableDays.count, 1)
                    )
                    .onChange(of: sessionsPerWeek) { _, _ in preview = nil }
                }

                Divider()

                Stepper(
                    "About \(sessionDurationMinutes) min per session",
                    value: $sessionDurationMinutes,
                    in: 20...180,
                    step: 5
                )
                .onChange(of: sessionDurationMinutes) { _, _ in
                    preview = nil
                }

                Divider()

                TextField(
                    "Any other preferences? Preferred split, race details…",
                    text: $userNotes,
                    axis: .vertical
                )
                .lineLimit(3...7)
                .onChange(of: userNotes) { _, _ in
                    preview = nil
                }
            }
        }
    }

    private var generateCard: some View {
        coachCard {
            Button {
                Task { await generatePreview() }
            } label: {
                HStack {
                    Spacer()
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(
                        isGenerating
                            ? "Building your plan…"
                            : mode.actionTitle
                    )
                    .font(.headline)
                    Spacer()
                }
                .frame(height: 54)
                .foregroundStyle(.white)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate)
            if !limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Toggle(isOn: $shareLimitationsWithAI) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "Share training limitations with AI",
                            norwegian: "Del treningshensyn med AI"
                        ))
                        .font(.subheadline.weight(.semibold))
                        Text(ATHLTHLocalization.choose(
                            english: "Optional: these notes may contain sensitive health information. Send them to the AI service only when you enable this choice. Always review suggested workouts.",
                            norwegian: "Valgfritt: Disse notatene kan inneholde sensitive helseopplysninger. De sendes bare til AI-tjenesten når du aktiverer dette valget. Kontroller alltid øktforslagene."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                }
                .tint(ATHLTHTheme.accentDeep)
            }
        }
    }

    private func coachSectionHeading(
        eyebrow: String,
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(2)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Text(title)
                .font(.title3.weight(.bold))
        }
    }

    private func coachChip(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                ATHLTHTheme.accentSoft,
                in: Capsule()
            )
    }

    private func coachCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ATHLTHPlanSurface {
            content()
        }
    }

    private var intakePreferences: CoachIntakePreferences {
        CoachIntakePreferences(
            experience: experience, trainingFocus: trainingFocus, gymAccess: gymAccess,
            homeEquipment: homeEquipment, otherEquipment: otherEquipment,
            limitations: limitations, coachFocusNotes: coachFocusNotes,
            currentSessionsPerWeek: currentSessionsPerWeek,
            useProfileInterests: useProfileInterests, sessionsPerWeek: sessionsPerWeek,
            sessionDurationMinutes: sessionDurationMinutes, availableDays: availableDays
        )
    }

    private var questionsAnswered: Bool {
        !experience.isEmpty && !gymAccess.isEmpty
    }

    private var coachContext: String {
        if isStandaloneCoachJourney {
            let additionalRequest = coachFocusNotes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return standaloneIntake.coachContext +
                "\nAthlete's optional plan request: " +
                (additionalRequest.isEmpty
                    ? "None"
                    : String(additionalRequest.prefix(700)))
        }

        let interests = useProfileInterests
            ? (session.onboardingProfile?.interests.map(\.title).sorted().joined(separator: ", ") ?? "")
            : "Not shared"
        let equipment = homeEquipment.sorted().joined(separator: ", ")
        return """
        Confirmed training profile:
        Experience: \(experience).
        Training focus: \(trainingFocus.title). Match workout types to this focus.
        Current training: \(currentSessionsPerWeek) sessions per week.
        Gym access: \(gymAccess).
        Home equipment: \(equipment.isEmpty ? "Bodyweight only" : equipment).
        Other available equipment: \(String(otherEquipment.prefix(300))).
        Limitations or movements to avoid: \(shareLimitationsWithAI && !limitations.isEmpty ? String(limitations.prefix(500)) : "Not shared").
        Profile interests: \(interests).
        Athlete's own focus request: \(coachFocusNotes.isEmpty ? "No additional focus request" : String(coachFocusNotes.prefix(700))).
        Only prescribe equipment the user can access. With no gym or listed home equipment, use bodyweight or outdoor sessions.
        Scale volume to experience and current training; do not treat an experienced athlete as a beginner or overload a beginner.
        """
    }

    @ViewBuilder
    private var coachQuestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(
                eyebrow: "01 · EXPERIENCE",
                title: "Where are you starting?"
            )

            coachCard {
                Picker("Training experience", selection: $experience) {
                    Text("Choose your level").tag("")
                    Text("Beginner").tag("Beginner")
                    Text("Intermediate").tag("Intermediate")
                    Text("Experienced / train regularly")
                        .tag("Experienced")
                }

                Divider()

                Stepper(
                    "Currently \(currentSessionsPerWeek) sessions per week",
                    value: $currentSessionsPerWeek,
                    in: 0...14
                )
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(
                eyebrow: "02 · DIRECTION",
                title: "What should Coach build toward?"
            )

            coachCard {
                Picker("Training focus", selection: $trainingFocus) {
                    ForEach(TrainingFocus.allCases) { focus in
                        Text(focus.title).tag(focus)
                    }
                }

                Text(trainingFocus.subtitle)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                if !goalStore.activeGoals.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Train toward a goal")
                            .font(.subheadline.weight(.semibold))

                        ForEach(goalStore.activeGoals) { goal in
                            Button {
                                if selectedGoalIDs.contains(goal.id) {
                                    selectedGoalIDs.remove(goal.id)
                                } else {
                                    selectedGoalIDs.insert(goal.id)
                                }
                                preview = nil
                            } label: {
                                HStack(spacing: 10) {
                                    Image(
                                        systemName:
                                            selectedGoalIDs.contains(goal.id)
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                    )
                                    .foregroundStyle(
                                        selectedGoalIDs.contains(goal.id)
                                            ? ATHLTHTheme.accentDeep
                                            : ATHLTHTheme.mutedText
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(goal.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(
                                                ATHLTHTheme.primaryText
                                            )

                                        HStack(spacing: 5) {
                                            Text(goal.category.title)
                                            if let deadline = goal.deadline {
                                                Text("·")
                                                Text(
                                                    deadline.formatted(
                                                        date: .abbreviated,
                                                        time: .omitted
                                                    )
                                                )
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )
                                    }

                                    Spacer()

                                    if goal.isPrimary {
                                        Text("PRIMARY")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(
                                                ATHLTHTheme.accentDeep
                                            )
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Tell Coach what matters most")
                        .font(.subheadline.weight(.semibold))

                    TextField(
                        "Example: Improve my 10K pace without losing strength. Keep Mondays light and prioritize recovery after long runs.",
                        text: $coachFocusNotes,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .onChange(of: coachFocusNotes) { _, _ in
                        preview = nil
                    }

                    Text(
                        "Coach combines this with the goals you select above. You do not need to repeat information already stored in a goal."
                    )
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                if let interests = session.onboardingProfile?.interests,
                   !interests.isEmpty {
                    Divider()

                    Toggle(
                        "Use my profile interests",
                        isOn: $useProfileInterests
                    )

                    if useProfileInterests {
                        Text(
                            interests.map(\.title)
                                .sorted()
                                .joined(separator: " · ")
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(
                eyebrow: "03 · ENVIRONMENT",
                title: "Where can you train?"
            )

            coachCard {
                Picker("Gym access", selection: $gymAccess) {
                    Text("Choose an option").tag("")
                    Text("Yes — I can use a gym").tag("Yes")
                    Text("No — home or outdoors").tag("No")
                }

                Divider()

                Text("Equipment available at home")
                    .font(.subheadline.weight(.semibold))

                ForEach(equipmentOptions, id: \.self) { equipment in
                    Toggle(
                        equipment,
                        isOn: Binding(
                            get: {
                                homeEquipment.contains(equipment)
                            },
                            set: { enabled in
                                if enabled {
                                    homeEquipment.insert(equipment)
                                } else {
                                    homeEquipment.remove(equipment)
                                }
                            }
                        )
                    )
                }

                TextField(
                    "Other equipment (optional)",
                    text: $otherEquipment,
                    axis: .vertical
                )
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(
                eyebrow: "04 · ADAPT",
                title: "Anything Coach should protect?"
            )

            coachCard {
                TextField(
                    "Injuries, limitations or movements to avoid (optional)",
                    text: $limitations,
                    axis: .vertical
                )
                .lineLimit(2...5)

                Text(
                    "Only include details you want ATHLTH Coach to use when planning."
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }

        Button {
            showingQuestions = false
        } label: {
            HStack {
                Text("Continue to plan")
                    .font(.headline)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(
                ATHLTHTheme.accentDeep,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!questionsAnswered)
        .opacity(questionsAnswered ? 1 : 0.45)
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(
                eyebrow: "GOALS",
                title: "What are we training for?"
            )

            coachCard {
                if goalStore.activeGoals.isEmpty {
                    Text(
                        "No active goals yet. Coach will build around your training focus and free-text direction."
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                } else {
                    ForEach(goalStore.activeGoals) { goal in
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
                                    preview = nil
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(goal.title)
                                    .font(.subheadline.weight(.semibold))

                                Text(goal.category.title)
                                    .font(.caption2)
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

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(eyebrow: "TIMELINE", title: "Set the training window")
            coachCard {
            DatePicker(
                "Start date",
                selection: $startDate,
                displayedComponents: .date
            )
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart {
                    endDate = Calendar.current.date(
                        byAdding: .weekOfYear,
                        value: max(weekCount, 1),
                        to: newStart
                    ) ?? newStart
                }
                preview = nil
            }

            Picker("Plan by", selection: $timelineMode) {
                ForEach(AIProgramTimelineMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: timelineMode) { _, _ in
                preview = nil
            }

            if timelineMode == .weeks {
                Stepper(
                    "\(weekCount) \(weekCount == 1 ? "week" : "weeks")",
                    value: $weekCount,
                    in: 1...52
                )
                .onChange(of: weekCount) { _, _ in
                    preview = nil
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
                .onChange(of: endDate) { _, _ in
                    preview = nil
                }
            }

            LabeledContent(
                "Program window",
                value: "\(resolvedWeeks) \(resolvedWeeks == 1 ? "week" : "weeks")"
            )

            Text(
                ATHLTHLocalization.format(
                            english: "%@ – %@",
                            norwegian: "%@ – %@",
                            startDate.formatted(date: .abbreviated, time: .omitted),
                            resolvedEndDate.formatted(date: .abbreviated, time: .omitted)
                        )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            }
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(eyebrow: "SCHEDULE", title: "When can you train?")
            coachCard {
            HStack(spacing: 7) {
                ForEach(1...7, id: \.self) { index in
                    Button {
                        if availableDays.contains(index) {
                            availableDays.remove(index)
                        } else {
                            availableDays.insert(index)
                        }
                        sessionsPerWeek = min(sessionsPerWeek, max(availableDays.count, 1))
                        preview = nil
                    } label: {
                        Text(dayNames[index - 1])
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .foregroundStyle(
                                availableDays.contains(index)
                                    ? .white
                                    : .primary
                            )
                            .background(
                                availableDays.contains(index)
                                    ? ATHLTHTheme.accent
                                    : Color(.tertiarySystemGroupedBackground),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(
                "AI will schedule training only on the days you leave selected and will use recovery/rest days around them."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ draft: AIProgramDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            coachSectionHeading(
                eyebrow: ATHLTHLocalization.choose(english: "YOUR PLAN", norwegian: "DIN PLAN"),
                title: ATHLTHLocalization.choose(english: "Coach draft", norwegian: "Forslag fra coach")
            )
            coachCard {
            Text(draft.title)
                .font(.headline)

            if !draft.summary.isEmpty {
                Text(draft.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent(
                "Length",
                value: "\(draft.weeks.count) weeks"
            )
            LabeledContent(
                "Sessions",
                value: "\(draft.sessionCount)"
            )

            Text(ATHLTHLocalization.choose(
                english: "Inspect every week before accepting. Tap a week for days, sessions and exercise targets.",
                norwegian: "Kontroller alle ukene før du godkjenner. Trykk på en uke for å se dager, økter og øvelsesmål."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            Button {
                if expandedPreviewWeeks.count == draft.weeks.count {
                    expandedPreviewWeeks.removeAll()
                } else {
                    expandedPreviewWeeks = Set(draft.weeks.map(\.weekNumber))
                }
            } label: {
                Label(
                    expandedPreviewWeeks.count == draft.weeks.count
                        ? ATHLTHLocalization.choose(english: "Collapse all weeks", norwegian: "Lukk alle uker")
                        : ATHLTHLocalization.choose(english: "Show all workout details", norwegian: "Vis alle øktdetaljer"),
                    systemImage: "rectangle.expand.vertical"
                )
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)

            ForEach(draft.weeks, id: \.weekNumber) { week in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        if expandedPreviewWeeks.contains(week.weekNumber) {
                            expandedPreviewWeeks.remove(week.weekNumber)
                        } else {
                            expandedPreviewWeeks.insert(week.weekNumber)
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(week.title.isEmpty
                                    ? ATHLTHLocalization.choose(
                                        english: "Week \(week.weekNumber)",
                                        norwegian: "Uke \(week.weekNumber)"
                                    )
                                    : week.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(
                                    "\(week.days.reduce(0) { $0 + $1.sessions.count }) " +
                                    ATHLTHLocalization.choose(english: "workouts", norwegian: "økter")
                                )
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: expandedPreviewWeeks.contains(week.weekNumber)
                                ? "chevron.up" : "chevron.down")
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        .padding(11)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(ATHLTHLocalization.choose(
                        english: "Show or hide this week's planned workouts",
                        norwegian: "Vis eller skjul ukens planlagte økter"
                    ))

                    if expandedPreviewWeeks.contains(week.weekNumber) {
                        ForEach(week.days.filter { !$0.sessions.isEmpty }, id: \.dayIndex) { day in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(day.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                ForEach(day.sessions.indices, id: \.self) { sessionIndex in
                                    let workout = day.sessions[sessionIndex]
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workout.title)
                                            .font(.subheadline.weight(.medium))
                                        if let duration = workout.durationMinutes {
                                            Text("\(duration) min")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let distance = workout.targetDistanceKilometers {
                                            Text("\(distance.formatted()) km")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let locked = seed?.structuredWorkoutsByDay[day.dayIndex] {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Built in ATHLTH Studio – protected",
                                                    norwegian: "Bygget i ATHLTH Studio – beholdes"
                                                ), systemImage: "lock.shield"
                                            )
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(ATHLTHTheme.accentDeep)
                                            ForEach(locked.blocks, id: \.id) { block in
                                                Text("• \(block.title)" +
                                                     (block.targetText.map { " · " + $0 } ?? ""))
                                                .font(.caption2)
                                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                            }
                                        }
                                        ForEach(workout.exercises.indices, id: \.self) { exerciseIndex in
                                            let exercise = workout.exercises[exerciseIndex]
                                            Text(
                                                "• \(exercise.name) · \(exercise.sets) × " +
                                                (exercise.reps.map(String.init) ?? "–")
                                            )
                                            .font(.caption2)
                                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if seed?.structuredWorkoutsByDay[day.dayIndex] == nil {
                                            Button {
                                                editingDraftWorkout = ATHLTHPlanDraftWorkoutSelection(
                                                    weekNumber: week.weekNumber,
                                                    dayIndex: day.dayIndex,
                                                    sessionIndex: sessionIndex
                                                )
                                            } label: {
                                                Label(
                                                    ATHLTHLocalization.choose(english: "Edit workout", norwegian: "Rediger økt"),
                                                    systemImage: "pencil"
                                                )
                                                .font(.caption.weight(.semibold))
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        if seed?.structuredWorkoutsByDay[day.dayIndex] == nil,
                                           mode == .generate,
                                           week.days.contains(where: {
                                               $0.dayIndex != day.dayIndex &&
                                               $0.sessions.isEmpty &&
                                               availableDays.contains($0.dayIndex)
                                           }) {
                                            Menu {
                                                ForEach(
                                                    week.days.filter {
                                                        $0.dayIndex != day.dayIndex &&
                                                        $0.sessions.isEmpty &&
                                                        availableDays.contains($0.dayIndex)
                                                    }, id: \.dayIndex
                                                ) { target in
                                                    Button(target.title) {
                                                        let selection = ATHLTHPlanDraftWorkoutSelection(
                                                            weekNumber: week.weekNumber,
                                                            dayIndex: day.dayIndex,
                                                            sessionIndex: sessionIndex
                                                        )
                                                        guard let moved = ATHLTHPlanDraftEditing.moving(
                                                            in: draft,
                                                            selection: selection,
                                                            toDayIndex: target.dayIndex,
                                                            allowedDayIndexes: availableDays
                                                        ), draftValidationIssues(moved).isEmpty else {
                                                            errorMessage = ATHLTHLocalization.choose(
                                                                english: "Could not move this workout in the draft.",
                                                                norwegian: "Kunne ikke flytte økten i utkastet."
                                                            )
                                                            return
                                                        }
                                                        preview = moved
                                                    }
                                                }
                                            } label: {
                                                Label(
                                                    ATHLTHLocalization.choose(
                                                        english: "Move to another day",
                                                        norwegian: "Flytt til annen dag"
                                                    ),
                                                    systemImage: "calendar.badge.clock"
                                                )
                                                .font(.caption.weight(.semibold))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.vertical, 5)
                        }
                    }
                }
            }

            Text(ATHLTHLocalization.choose(
                english: "No changes are saved until you approve the draft below.",
                norwegian: "Ingen endringer lagres før du godkjenner utkastet nedenfor."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button {
                applyPreview(draft)
            } label: {
                Label(
                    mode == .generate
                        ? ATHLTHLocalization.choose(english: "Use program", norwegian: "Bruk program")
                        : ATHLTHLocalization.choose(english: "Fill empty days", norwegian: "Fyll tomme dager"),
                    systemImage: "checkmark.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHTheme.accent)

            Button {
                preview = nil
                Task { await generatePreview() }
            } label: {
                Label(ATHLTHLocalization.choose(english: "Regenerate", norwegian: "Generer på nytt"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            }
        }
    }

    @MainActor
    private func generatePreview() async {
        guard canGenerate else { return }

        if isStandaloneCoachJourney {
            coachJourneyStage = .generating
        }
        isGenerating = true
        defer { isGenerating = false }

        let requestOwnerID = session.profile.userID
        let request = AIProgramRequest(
            mode: mode.rawValue,
            startDate: ISO8601DateFormatter().string(from: startDate),
            weekCount: resolvedWeeks,
            sessionsPerWeek: aiChoosesFrequency && mode == .generate
                ? availableDays.count : sessionsPerWeek,
            aiChoosesFrequency: aiChoosesFrequency && mode == .generate,
            preferredDays: availableDays.sorted(),
            sessionDurationMinutes: sessionDurationMinutes,
            userNotes: String(coachContext.prefix(2_200)) +
                "\nAdditional preferences: " + String(userNotes.prefix(400)) +
                "\nRecent training context: " + String(historyContext.prefix(400)),
            // A linked ATHLTH goal is optional. Direction and outcomes are
            // carried in the explicit Coach intake when this array is empty.
            goals: selectedGoals.map(AIProgramGoalInput.init),
            existingDays: existingDays
        )

        do {
            let result = try await service.generate(request)
            guard session.signedIn, session.profile.userID == requestOwnerID else { return }
            // AI may propose something on a weekday the user already
            // detailed manually. Overlay the authoritative Studio workout
            // before validation, so we never reject a safe proposal merely
            // because it would otherwise duplicate a protected session.
            let effectiveProposal = result
                .displayingLockedWorkouts(seed?.structuredWorkoutsByDay ?? [:])
                .honoringWeekdayChoices(
                    seed?.preferredWorkoutsByDay ?? [:],
                    protectedDays: Set(seed?.structuredWorkoutsByDay.keys.map { $0 } ?? [])
                )
            let validationIssues = draftValidationIssues(effectiveProposal)
            guard validationIssues.isEmpty else {
                preview = nil
                if isStandaloneCoachJourney { coachJourneyStage = .intake }
                errorMessage = ATHLTHLocalization.choose(
                    english: "AI returned an incomplete or invalid plan. No changes have been saved. Try again.",
                    norwegian: "AI leverte en ufullstendig eller ugyldig plan. Ingenting er lagret. Prøv på nytt."
                )
                return
            }
            expandedPreviewWeeks.removeAll()
            preview = effectiveProposal
            if isStandaloneCoachJourney {
                coachPreviewWeek = 1
                coachJourneyStage = .preview
            }
            errorMessage = nil
        } catch {
            if isStandaloneCoachJourney { coachJourneyStage = .intake }
            errorMessage = error.localizedDescription
        }
    }

    private var historyContext: String {
        guard session.signedIn,
              CoachHistoryPermission.isEnabled(userID: session.profile.userID) else { return "" }
        let cutoff = Date().addingTimeInterval(-28 * 86400)
        let workouts = health.workouts.filter { $0.startDate >= cutoff }
        let local = strength.workoutHistory.filter { $0.isFinished && $0.startedAt >= cutoff }
        let linkedIDs = Set(workouts.map(\.id))
        let additionalStrength = local.filter { log in
            guard let id = log.healthMetrics.healthKitWorkoutUUID else { return true }
            return !linkedIDs.contains(id)
        }
        let minutes = workouts.reduce(0.0) { $0 + $1.duration } / 60
        let kilometers = workouts.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) } / 1000
        return "Consented 28-day training summary (available records only): \(workouts.count) Apple Health workouts, \(Int(minutes)) minutes, \(String(format: "%.1f", kilometers)) km; \(additionalStrength.count) additional ATHLTH strength sessions. Missing records do not imply inactivity. Use this to suggest a gradual plan, not to diagnose readiness.\n"
    }

    private var existingDays: [AIProgramExistingDay] {
        guard mode == .complete,
              let plan = session.activePlan
        else {
            return []
        }

        return plan.weeks.flatMap { week in
            week.days.map { day in
                // The API and AI use calendar weekdays (Mon=1), while
                // stored plans use relative offsets from plan.startDate.
                let weekday = plan.startDate.map {
                    ATHLTHTrainingPlanSchedule.calendarWeekdayIndex(
                        forRelativeDayIndex: day.dayIndex, planStart: $0
                    )
                } ?? day.dayIndex
                return AIProgramExistingDay(
                    weekNumber: week.weekNumber,
                    dayIndex: weekday,
                    dayTitle: day.title,
                    existingSessions: day.sessions.map(\.title)
                )
            }
        }
    }

    @MainActor
    private func applyPreview(_ draft: AIProgramDraft) {
        guard draftValidationIssues(draft).isEmpty else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Review the draft; it contains an invalid workout. Nothing has been saved.",
                norwegian: "Kontroller utkastet. En økt er ugyldig. Ingenting er lagret."
            )
            return
        }
        var generated = draft.makeTrainingPlan(
            ownerID: session.profile.userID,
            startDate: startDate
        )

        if mode == .generate,
           let preferredTitle =
                seed?
                    .preferredTitle
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
           !preferredTitle.isEmpty {
            generated.title = preferredTitle
        }

        if mode == .generate, let seed {
            // Keep all setup details from the first wizard, including
            // Advanced mode, per-day commitments and selected visibility.
            seed.applyWizardMetadata(to: &generated)
            ATHLTHPlanStructuredWorkoutBlueprint.apply(
                seed.builderProfile?.mode == .advanced
                    ? seed.structuredWorkoutsByDay : [:],
                to: &generated.weeks
            )
        }

        switch mode {
        case .generate:
            guard session.addTrainingPlan(generated) else {
                if let endDate = session.trainingPlanEndDate(generated),
                   let conflict = session.trainingPlanConflict(
                       startDate: startDate,
                       endDate: endDate
                   ) {
                    errorMessage =
                        "This program overlaps with \(conflict.title). Adjust the dates so only one plan is active at a time."
                } else {
                    errorMessage =
                        "ATHLTH could not add this program to your plan timeline."
                }
                return
            }

            goalStore.setLinkedPlan(
                generated.id,
                goalIDs: selectedGoalIDs
            )

        case .complete:
            guard session.fillEmptyDaysFromGeneratedProgram(
                generated, expectedPlanID: completingPlanID,
                expectedVersion: completingPlanVersion
            ) else {
                errorMessage = "The plan changed while this draft was being prepared. Close Coach and reopen the plan to generate a fresh draft."
                return
            }

            if let planID = session.activePlan?.id {
                goalStore.setLinkedPlan(
                    planID,
                    goalIDs: selectedGoalIDs
                )
            }
        }

        onProgramCreatedPlanID?(mode == .generate
            ? generated.id : (completingPlanID ?? generated.id))
        onProgramCreated?()
        if isStandaloneCoachJourney && mode == .generate {
            coachSavedPlan = generated
            coachJourneyStage = .ready
        } else {
            dismiss()
        }
    }

    @MainActor
    private func loadDefaultsIfNeeded() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        if !isStandaloneCoachJourney {
            trainingFocus = session.onboardingProfile?.trainingFocus ?? .generalFitness
        }
        if !isStandaloneCoachJourney,
           let saved = AccountLocalStorage.read(
                CoachIntakePreferences.self,
                name: "coach",
                userID: session.profile.userID
           ) {
            experience = saved.experience
            trainingFocus = saved.trainingFocus
            gymAccess = saved.gymAccess
            homeEquipment = saved.homeEquipment
            otherEquipment = saved.otherEquipment
            limitations = saved.limitations
            coachFocusNotes = saved.coachFocusNotes ?? ""
            currentSessionsPerWeek = saved.currentSessionsPerWeek
            useProfileInterests = saved.useProfileInterests
            availableDays = saved.availableDays
            sessionsPerWeek = min(max(saved.sessionsPerWeek, 1), max(availableDays.count, 1))
            sessionDurationMinutes = min(max(saved.sessionDurationMinutes, 20), 180)
        }

        if mode == .generate {
            startDate = session.suggestedTrainingPlanStartDate
            endDate = Calendar.current.date(
                byAdding: .weekOfYear,
                value: max(weekCount, 1),
                to: startDate
            ) ?? startDate
        }

        if mode == .complete,
           let plan = session.activePlan {
            completingPlanID = plan.id
            completingPlanVersion = plan.version
            weekCount = max(plan.weeks.count, 1)
            startDate = plan.startDate
                ?? Calendar.current.startOfDay(for: Date())
            endDate = Calendar.current.date(
                byAdding: .day,
                value: max(weekCount * 7 - 1, 0),
                to: startDate
            ) ?? startDate

            let linked = goalStore.goals.filter {
                $0.linkedTrainingPlanID == plan.id
            }
            if !linked.isEmpty {
                selectedGoalIDs = Set(linked.map(\.id))
            }
        }

        if mode == .generate,
           let seed {
            startDate =
                Calendar.current
                    .startOfDay(
                        for: seed.startDate
                    )
            weekCount =
                min(
                    max(seed.weekCount, 1),
                    52
                )
            endDate =
                Calendar.current.date(
                    byAdding: .day,
                    value:
                        max(
                            weekCount * 7 - 1,
                            0
                        ),
                    to: startDate
                ) ?? startDate
            availableDays =
                seed.availableDays.isEmpty
                    ? Set(1...7)
                    : seed.availableDays
            sessionsPerWeek =
                min(
                    max(
                        seed.sessionsPerWeek,
                        1
                    ),
                    max(
                        availableDays.count,
                        1
                    )
                )
            sessionDurationMinutes =
                min(
                    max(
                        seed.sessionDurationMinutes,
                        20
                    ),
                    180
                )
            trainingFocus =
                seed.trainingFocus
            limitations =
                seed.limitations
            coachFocusNotes =
                seed.coachFocusNotes
            selectedGoalIDs =
                seed.selectedGoalIDs

            if let seededGymAccess =
                    seed.gymAccess,
               !seededGymAccess.isEmpty {
                gymAccess =
                    seededGymAccess
            }

            // All core plan questions were already collected by the wizard.
            // Advanced Coach intake remains available from the standalone
            // Coach entry, never as a second mandatory wizard here.
            showingQuestions = false
        }

    }
}
