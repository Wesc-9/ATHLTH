import SwiftUI

/// The Plan tab is a workspace, not a second workout engine.
/// It operates directly on existing TrainingPlan / PlannedSession records.
struct ATHLTHTrainPlanPremiumView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var goalStore: GoalStore

    // Optional deep link from "I dag" or the rebuilt library.
    var highlightedPlanID: UUID? = nil
    // The owning Train tab supplies its existing iPhone/Watch launch flow.
    // Embedded plan previews without that owner remain read-only for launch.
    var onStartWorkout: ((UUID, PlannedSession) -> Void)? = nil
    @State private var focusedPlanID: UUID?

    @AppStorage("athlth.planWorkspace.advancedMode")
    private var advanced = false
    @State private var selectedWeekIndex: Int?
    @State private var selectedDetailSection: PlanDetailSection = .structure
    @State private var showingEntirePlan = false
    @State private var showingWorkoutLibrary = false
    @State private var showingCopyDay = false
    @State private var copyingSourceDayID: UUID?
    @State private var copyTargetWeekIndex = 0
    @State private var copyTargetDayIDs: Set<UUID> = []
    @State private var copyFeedback: String?
    private enum PlanDetailSection: String, CaseIterable, Identifiable {
        case structure, details, route, coach, history
        var id: Self { self }
        var title: String {
            switch self {
            case .structure: return ATHLTHLocalization.choose(english: "Structure", norwegian: "Øktstruktur")
            case .details: return ATHLTHLocalization.choose(english: "Details", norwegian: "Detaljer")
            case .route: return ATHLTHLocalization.choose(english: "Route", norwegian: "Rute")
            case .coach: return ATHLTHLocalization.choose(english: "Coach notes", norwegian: "Trenertips")
            case .history: return ATHLTHLocalization.choose(english: "History", norwegian: "Historikk")
            }
        }
    }
    @State private var showingCreation = false
    @State private var creationDraftID: UUID?
    @State private var creationResumesDraft = true
    @State private var unfinishedPlanDrafts: [ATHLTHPlanDraftRecord] = []
    @State private var showingDeletePlanDraftConfirmation = false
    @State private var draftPendingDeletionID: UUID?
    @State private var planDraftDeletionError: String?
    private let unfinishedDraftStore = ATHLTHPlanCreationDraftStore()
    @State private var pendingCreatedPlanID: UUID?
    @State private var showingMyPlans = false
    @State private var browsingMyPlans = false
    @State private var showingTemplates = false
    @State private var showingEditor = false
    @State private var showingProgress = false
    @State private var showingGoals = false
    @State private var showingCoach = false
    @State private var showingRecoveryAdvice = false
    @State private var showingAIHelp = false
    private struct WorkoutEditDestination: Identifiable {
        let planID: UUID
        let dayID: UUID
        let version: Int
        let workout: PlannedSession?
        var id: UUID { workout?.id ?? dayID }
    }
    @State private var editingWorkout: WorkoutEditDestination?
    private struct WorkoutDestination: Identifiable {
        let planID: UUID
        let workout: PlannedSession
        var id: UUID { workout.id }
    }
    @State private var openingWorkout: WorkoutDestination?
    @State private var editingTrainingPlaceWorkout: WorkoutDestination?
    @State private var selectedDayID: UUID?
    @State private var selectedWorkoutID: UUID?
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
    @State private var moveWeekDate = Date()
    @State private var moveError: String?
    @State private var editingPlan: TrainingPlan?
    @State private var trainingPlanPendingDeletion: TrainingPlan?

    private let graphite = ATHLTHPlanDesign.ink
    private let secondaryInk = ATHLTHPlanDesign.secondaryInk
    private let warmGold = ATHLTHPlanDesign.accentInk
    private let line = ATHLTHPlanDesign.warmDivider
    private let paper = ATHLTHPlanDesign.warmCanvas
    private let soft = ATHLTHPlanDesign.warmSurface

    private var plan: TrainingPlan? {
        if let id = focusedPlanID ?? highlightedPlanID,
           let selected = session.trainingPlans.first(where: { $0.id == id }) {
            return selected
        }
        return session.activePlan ?? session.trainingPlans.first
    }

    private var selectedWeek: TrainingPlanWeek? {
        guard let plan, !plan.weeks.isEmpty else { return nil }
        let index = min(max(selectedWeekIndex ?? currentWeekIndex(plan), 0),
                        plan.weeks.count - 1)
        return plan.weeks[index]
    }

    var body: some View {
        // Erase the deeply nested planner presentation type before SwiftUI
        // decodes it when switching between Train, Community and Inbox.
        AnyView(editingSheets)
    }

    private func beginMovingWorkout(_ workout: PlannedSession, day: TrainingPlanDay, plan: TrainingPlan) {
        moveError = nil
        moveTargetDate = planDayDate(day.dayIndex, plan: plan)
        moveWeekDate = moveTargetDate
        movingPlanID = plan.id
        movingPlanVersion = plan.version
        movingWorkout = workout
    }

    private func simpleMoveDays(earliest: Date, last: Date) -> some View {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: moveWeekDate)?.start ?? moveWeekDate
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("Choose a new day", "Velg en ny dag"))
                .font(.headline)
            HStack {
                Button {
                    moveWeekDate = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                } label: {
                    Image(systemName: "chevron.left").frame(width: 48, height: 48)
                }
                .disabled((dates.last ?? weekStart) <= earliest || weekStart <= earliest)
                .accessibilityLabel(tr("Previous week", "Forrige uke"))
                Spacer()
                Text(weekStart.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    moveWeekDate = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                } label: {
                    Image(systemName: "chevron.right").frame(width: 48, height: 48)
                }
                .disabled((dates.last ?? weekStart) >= last)
                .accessibilityLabel(tr("Next week", "Neste uke"))
            }
            ForEach(dates, id: \.self) { date in
                let selected = calendar.isDate(date, inSameDayAs: moveTargetDate)
                Button {
                    moveTargetDate = date
                    moveError = nil
                } label: {
                    HStack {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if selected { Image(systemName: "checkmark.circle.fill") }
                    }
                    .foregroundStyle(selected ? Color.white : graphite)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(selected ? graphite : soft, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(date < earliest || date > last)
                .opacity(date < earliest || date > last ? 0.35 : 1)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
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
                                    if advanced {
                                        DatePicker(
                                            tr("New workout date", "Ny treningsdato"),
                                            selection: $moveTargetDate,
                                            in: earliest...last,
                                            displayedComponents: .date
                                        )
                                    } else {
                                        simpleMoveDays(earliest: earliest, last: last)
                                    }
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
                                    if let start = plan.startDate {
                                        let days = Calendar.current.dateComponents(
                                            [.day], from: Calendar.current.startOfDay(for: start),
                                            to: Calendar.current.startOfDay(for: moveTargetDate)
                                        ).day ?? 0
                                        selectedWeekIndex = max(0, days / 7)
                    selectedDayID = nil
                                    }
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
                                let source = plan.weeks.flatMap(\.days).first {
                                    $0.sessions.contains { $0.id == workout.id }
                                }
                                let unchanged = source.map {
                                    calendar.isDate(planDayDate($0.dayIndex, plan: plan), inSameDayAs: target)
                                } ?? true
                                return unchanged || target < max(first, calendar.startOfDay(for: Date()))
                                    || target > last
                            }())
                        }
                    }
                }
                .presentationDetents([.large])
            }
    }

    // A single Plan Studio entry, backed by the existing plan records and editors.
    // Simple and advanced change the amount of visible detail, not the data.
    private var planContent: some View {
        VStack(alignment: .leading, spacing: 19) {
            studioWelcome
            studioEntryPoints

            if browsingMyPlans {
                savedPlansOverview
            } else if let plan {
                studioPlanWorkspace(plan)
            } else {
                studioEmptyState
            }

            ForEach(unfinishedPlanDrafts) { checkpoint in
                continuePlanDraftCard(checkpoint)
            }
        }
        .foregroundStyle(graphite)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            refreshUnfinishedPlanDraft()
            if let checkpoint = unfinishedPlanDrafts.first(where: {
                unfinishedDraftStore.wasEditing(
                    userID: session.profile.userID,
                    draftID: $0.draftID
                ) &&
                Date().timeIntervalSince($0.draft.savedAt) < 24 * 60 * 60
            }) {
                // Reopen only a genuinely interrupted editor, not an
                // unrelated saved draft or a new-plan request.
                Task { @MainActor in
                    await Task.yield()
                    guard !showingCreation else { return }
                    openDraft(checkpoint)
                }
            }
            session.refreshActivePlanForToday()
            if let plan {
                advanced = plan.builderProfile?.mode == .advanced
            }
        }
        .onChange(of: plan?.id) { _, _ in
            selectedWeekIndex = nil
            selectedDayID = nil
            selectedWorkoutID = nil
            selectedDetailSection = .structure
            if let plan {
                advanced = plan.builderProfile?.mode == .advanced
            }
        }
        .onChange(of: selectedWeekIndex) { _, _ in
            selectedDayID = nil
            selectedWorkoutID = nil
            selectedDetailSection = .structure
        }
        .onChange(of: showingCreation) { _, showing in
            if !showing { refreshUnfinishedPlanDraft() }
        }
        .onChange(of: highlightedPlanID) { _, next in
            focusedPlanID = next
            if next != nil { browsingMyPlans = false }
        }
    }


    private var studioWelcome: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("YOUR TRAINING STUDIO", "DITT TRENINGSSTUDIO"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(warmGold)
                    Text(tr("Build your way.", "Trening på din måte."))
                        .font(.system(size: 32, weight: .regular, design: .serif))
                        .foregroundStyle(graphite)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(tr("My plans", "Mine planer")) { browsingMyPlans = true }
                    Button(tr("Plan overview", "Planoversikt")) { browsingMyPlans = false }
                    Button(tr("Saved workouts", "Lagrede økter")) {
                        showingWorkoutLibrary = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(graphite)
                        .frame(width: 44, height: 44)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel(tr("Plan options", "Planvalg"))
            }
            Text(tr(
                "See your plan, open a day or build a program with the depth you need.",
                "Se planen din, åpne en dag eller bygg et program med akkurat den detaljgraden du ønsker."
            ))
            .font(.subheadline)
            .foregroundStyle(secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var studioEntryPoints: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                studioModeChoice(
                    title: tr("Simple", "Enkel"),
                    subtitle: tr("Week by week", "Uke for uke"),
                    symbol: "calendar",
                    selected: !advanced
                ) { advanced = false }
                studioModeChoice(
                    title: tr("Advanced", "Avansert"),
                    subtitle: tr("Every detail", "Dag for dag"),
                    symbol: "slider.horizontal.3",
                    selected: advanced
                ) { advanced = true }
            }
            HStack(spacing: 9) {
                Button {
                    beginNewPlanCreation()
                } label: {
                    Label(
                        tr("Build new plan", "Bygg ny plan"),
                        systemImage: "plus"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(graphite, in: RoundedRectangle(cornerRadius: 15))
                }
                Button {
                    browsingMyPlans.toggle()
                } label: {
                    Label(
                        browsingMyPlans
                            ? tr("Show plan", "Se planen")
                            : tr("My plans", "Mine planer"),
                        systemImage: browsingMyPlans ? "calendar" : "square.stack"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(graphite)
                    .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(line.opacity(0.8), lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func studioModeChoice(
        title: String, subtitle: String, symbol: String,
        selected: Bool, onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                }
            }
            .foregroundStyle(selected ? .white : graphite)
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                selected ? graphite : Color.white,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Color.clear : line, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var studioEmptyState: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image("GoalMountain")
                .resizable()
                .scaledToFill()
                .frame(height: 172)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 19))
                .accessibilityHidden(true)
            Text(tr("Your plan starts here", "Her starter treningsplanen din"))
                .font(.system(size: 25, weight: .regular, design: .serif))
                .foregroundStyle(graphite)
            Text(tr(
                "Start with a simple weekly rhythm or build each training day from warm-up to cooldown. Existing plans and templates can be reused in the builder.",
                "Velg enkel ukeplanlegging eller bygg hver dag fra oppvarming til nedjogg. Lagrede planer og maler kan gjenbrukes i byggeren."
            ))
            .font(.subheadline)
            .foregroundStyle(secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                showingTemplates = true
            } label: {
                Label(
                    tr("Explore plan templates", "Utforsk planmaler"),
                    systemImage: "books.vertical"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(graphite)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .athlthPlanCard(radius: 23)
    }

    private func studioPlanWorkspace(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            studioPlanCover(plan)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("YOUR SCHEDULE", "DIN UKEPLAN"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(warmGold)
                    Text(tr("Open a day to see everything", "Åpne en dag for alle detaljer"))
                        .font(.subheadline)
                        .foregroundStyle(secondaryInk)
                }
                Spacer(minLength: 6)
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(graphite)
                        .frame(width: 44, height: 44)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel(tr("Edit training week", "Rediger treningsuke"))
            }

            if !plan.weeks.isEmpty {
                let index = min(max(selectedWeekIndex ?? currentWeekIndex(plan), 0), plan.weeks.count - 1)
                HStack(spacing: 14) {
                    Button {
                        selectPremiumPlanWeek(max(index - 1, 0))
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(index == 0)
                    Spacer(minLength: 0)
                    VStack(spacing: 3) {
                        Text(tr("Week", "Uke") + " \(index + 1)")
                            .font(.system(size: 22, weight: .regular, design: .serif))
                        Text("\(index + 1) / \(plan.weeks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Button {
                        selectPremiumPlanWeek(min(index + 1, plan.weeks.count - 1))
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(index == plan.weeks.count - 1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(graphite)
                .padding(.horizontal, 4)

                let week = plan.weeks[index]
                VStack(spacing: 9) {
                    ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                        studioDayRow(day, plan: plan)
                        if selectedDayID == day.id {
                            premiumSelectedDayPanel(day, plan: plan)
                                .padding(.bottom, 7)
                        }
                    }
                }
            }

            Button {
                showingEditor = true
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Open the week and day builder", "Åpne uke- og dagbyggeren"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr(
                            "Warm-up, intervals, recovery, sets and session-specific targets",
                            "Oppvarming, intervaller, pauser, sett og øktspesifikke mål"
                        ))
                        .font(.caption)
                        .foregroundStyle(secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(graphite)
                .padding(17)
                .athlthPlanCard(radius: 18)
            }
            .buttonStyle(.plain)

            HStack(spacing: 13) {
                Button {
                    showingWorkoutLibrary = true
                } label: {
                    Label(tr("My workouts", "Mine økter"), systemImage: "bookmark")
                }
                Button {
                    showingEntirePlan.toggle()
                } label: {
                    Label(tr("All weeks", "Alle uker"), systemImage: "calendar")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(graphite)
            .buttonStyle(.plain)
            if showingEntirePlan {
                premiumAllWeeks(plan)
            }
        }
    }

    private func studioPlanCover(_ plan: TrainingPlan) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Image(premiumPlanHeroArt(plan))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: 197)
                    .clipped()
            }
            .frame(height: 197)
            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(planLibraryStatus(plan).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.85))
                Text(plan.title)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Label(
                        "\(plan.weeks.count) " + tr("weeks", "uker"),
                        systemImage: "calendar"
                    )
                    if let start = plan.startDate {
                        Label(
                            start.formatted(.dateTime.day().month(.abbreviated).year()),
                            systemImage: "clock"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(19)
        }
        .frame(height: 197)
        .clipShape(RoundedRectangle(cornerRadius: 23))
    }

    private func studioDayRow(_ day: TrainingPlanDay, plan: TrainingPlan) -> some View {
        let workouts = day.sessions.filter { !$0.isExplicitRestDay }
        let selected = selectedDayID == day.id
        let completed = !workouts.isEmpty &&
            workouts.allSatisfy { isPremiumPlanWorkoutCompleted($0, plan: plan) }
        let date = planDayDate(day.dayIndex, plan: plan)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDayID = selected ? nil : day.id
                selectedWorkoutID = nil
                selectedDetailSection = .structure
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 10, weight: .semibold))
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 26, weight: .regular, design: .serif))
                }
                .foregroundStyle(selected ? .white : graphite)
                .frame(width: 60, height: 67)
                .background(
                    selected ? graphite : soft,
                    in: RoundedRectangle(cornerRadius: 13)
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(workouts.first?.title ?? tr("Rest and recovery", "Hvile og restitusjon"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(workouts.isEmpty
                            ? tr("Rest day", "Hviledag")
                            : workouts.map { item in
                                item.durationMinutes.map { "\($0) min" } ?? item.kind.title
                              }.joined(separator: " · "))
                        if workouts.count > 1 {
                            Text("· \(workouts.count) " + tr("workouts", "økter"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(secondaryInk)
                    .lineLimit(1)
                    if advanced && !workouts.isEmpty {
                        Text(
                            "\(workouts.reduce(0) { $0 + ATHLTHUnifiedWorkout.editorBlocks(from: $1).count }) " +
                            tr("workout blocks", "øktblokker")
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(warmGold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Image(systemName: completed ? "checkmark.circle.fill" :
                    selected ? "chevron.up" : "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(completed ? ATHLTHTheme.vitality : graphite)
            }
            .foregroundStyle(graphite)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(.white, in: RoundedRectangle(cornerRadius: 19))
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(
                        selected ? warmGold.opacity(0.7) : line.opacity(0.65),
                        lineWidth: selected ? 1.2 : 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            date.formatted(.dateTime.weekday(.wide).day().month(.wide))
            + " · " + (workouts.first?.title ?? tr("Rest day", "Hviledag"))
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var programSheets: some View {
        AnyView(planContent)
        .alert(
            tr("Delete this draft?", "Slette dette utkastet?"),
            isPresented: $showingDeletePlanDraftConfirmation
        ) {
            Button(tr("Delete draft", "Slett utkast"), role: .destructive) {
                if unfinishedDraftStore.deleteDraft(
                    userID: session.profile.userID,
                    draftID: draftPendingDeletionID
                ) {
                    refreshUnfinishedPlanDraft()
                    planDraftDeletionError = nil
                } else {
                    planDraftDeletionError = tr(
                        "The draft could not be deleted. Please try again.",
                        "Utkastet kunne ikke slettes. Prøv på nytt."
                    )
                    refreshUnfinishedPlanDraft()
                }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr(
                "This permanently deletes only the unfinished plan on this iPhone. Saved and active training plans will not be changed.",
                "Dette sletter kun det uferdige utkastet på denne iPhonen. Lagrede og aktive treningsplaner blir ikke endret."
            ))
        }
        .sheet(isPresented: $showingCreation, onDismiss: {
            if let planID = pendingCreatedPlanID {
                focusedPlanID = planID
                browsingMyPlans = false
                selectedWeekIndex = 0
                if let created = session.trainingPlan(withID: planID) {
                    advanced = created.builderProfile?.mode == .advanced
                }
                pendingCreatedPlanID = nil
            }
        }) {
            ATHLTHTrainProgramComposerView(
                resumesDraftOnAppear: creationResumesDraft,
                draftID: creationDraftID
            ) { planID in
                pendingCreatedPlanID = planID
            }
        }
        .sheet(isPresented: $showingMyPlans) {
            MyTrainingPlansLibraryView()
        }
        .sheet(isPresented: $showingWorkoutLibrary) {
            NavigationStack {
                ScrollView {
                    ATHLTHTrainLibraryPremiumView(
                        onOpenPlan: { showingWorkoutLibrary = false },
                        startWithWorkouts: true
                    )
                    .padding(16)
                }
                .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Close", "Lukk")) {
                            showingWorkoutLibrary = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCopyDay) {
            if let plan, let copyingSourceDayID {
                planCopyDaySheet(plan: plan, sourceDayID: copyingSourceDayID)
            }
        }
        .alert(tr("Copy workout", "Kopier økt"),
               isPresented: Binding(
                   get: { copyFeedback != nil },
                   set: { if !$0 { copyFeedback = nil } }
               )) {
            Button("OK") { copyFeedback = nil }
        } message: {
            Text(copyFeedback ?? "")
        }
        .sheet(isPresented: $showingTemplates) {
            TrainingPlanLibrarySheet()
        }
        .sheet(isPresented: $showingProgress) {
            if let plan {
                TrainingPlanProgressDetailView(planID: plan.id)
            }
        }
    }

    private var insightsSheets: some View {
        AnyView(programSheets)
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
        AnyView(insightsSheets)
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
        }) { destination in
            let workout = destination.workout
            if let plan = session.trainingPlan(withID: destination.planID),
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
            } else {
                VStack(spacing: 12) {
                    Text(tr("This workout is no longer in the plan.", "Denne økten finnes ikke lenger i planen."))
                        .font(.headline)
                    Button(tr("Close", "Lukk")) { openingWorkout = nil }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
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
        .sheet(item: $editingWorkout) { destination in
            ATHLTHTrainWorkoutBuilderView(
                planID: destination.planID,
                dayID: destination.dayID,
                expectedPlanVersion: destination.version,
                existingWorkout: destination.workout
            )
        }
        .sheet(item: $editingTrainingPlaceWorkout) { destination in
            ATHLTHPlanTrainingPlacePicker(initial: destination.workout.plannedTrainingPlace) { place in
                guard let day = session.trainingPlan(withID: destination.planID)?
                    .weeks.flatMap(\.days)
                    .first(where: { $0.sessions.contains {
                        $0.id == destination.workout.id
                    } }) else { return }
                // A place is selected for the DATE. Keep every unfinished
                // workout on that day aligned without rewriting workout history.
                for workout in day.sessions {
                    guard !session.isPlanSessionSkipped(
                            planID: destination.planID, sessionID: workout.id),
                          !session.isPlanSessionCompleted(
                            planID: destination.planID, sessionID: workout.id,
                            healthWorkouts: health.workouts,
                            strengthHistory: strength.workoutHistory)
                    else { continue }
                    var updated = workout
                    updated.plannedTrainingPlace = place
                    session.updateSession(updated, inPlan: destination.planID)
                }
                editingTrainingPlaceWorkout = nil
            }
        }
        .confirmationDialog(
            trainingPlanPendingDeletion.map {
                tr("Delete \($0.title)?", "Slette \($0.title)?")
            } ?? tr("Delete training plan?", "Slette treningsplan?"),
            isPresented: Binding(
                get: { trainingPlanPendingDeletion != nil },
                set: { if !$0 { trainingPlanPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(tr("Delete training plan", "Slett treningsplan"), role: .destructive) {
                guard let selected = trainingPlanPendingDeletion else { return }
                trainingPlanPendingDeletion = nil
                // Resolve again to avoid deleting a plan removed elsewhere.
                guard session.trainingPlan(withID: selected.id) != nil else { return }
                goalStore.setLinkedPlan(selected.id, goalIDs: [])
                session.deleteTrainingPlan(selected.id)
                focusedPlanID = nil
                selectedWeekIndex = nil
                selectedDayID = nil
                if let currentPlan = plan {
                    advanced = currentPlan.builderProfile?.mode == .advanced
                }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                trainingPlanPendingDeletion = nil
            }
        } message: {
            Text(tr(
                "The training plan and its remaining schedule will be permanently deleted. Recorded workout history is kept.",
                "Treningsplanen og de gjenstående planlagte øktene slettes permanent. Registrerte treningsøkter i historikken beholdes."
            ))
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

    private func beginNewPlanCreation() {
        planDraftDeletionError = nil
        creationDraftID = UUID()
        creationResumesDraft = false
        showingCreation = true
    }

    private func openDraft(_ checkpoint: ATHLTHPlanDraftRecord) {
        creationDraftID = checkpoint.draftID
        creationResumesDraft = true
        showingCreation = true
    }

    private func refreshUnfinishedPlanDraft() {
        unfinishedPlanDrafts = unfinishedDraftStore.records(
            userID: session.profile.userID
        ).filter { $0.draft.stage != "mode" }
    }

    private func draftLocation(_ draft: ATHLTHPlanCreationDraft) -> String {
        switch draft.stage {
        case "week":
            if draft.planningApproach == "guided", let cursor = draft.guidedDayCursor {
                let week = min(cursor / 7 + 1, draft.weekCount)
                let day = cursor % 7 + 1
                return tr("Week \(week) · day \(day)", "Uke \(week) · dag \(day)")
            }
            return tr("Week \((draft.selectedPlanWeekIndex ?? 0) + 1)",
                      "Uke \((draft.selectedPlanWeekIndex ?? 0) + 1)")
        case "profile": return tr("Goals and needs", "Mål og behov")
        case "review": return tr("Review plan", "Oppsummering")
        case "basics": return tr("Plan basics", "Grunninfo")
        default: return tr("Planning in progress", "Påbegynt planlegging")
        }
    }

    private func continuePlanDraftCard(_ checkpoint: ATHLTHPlanDraftRecord) -> some View {
        let draft = checkpoint.draft
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .frame(width: 46, height: 46)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .lineLimit(1)
                    Text(draftLocation(draft) + " · " +
                         draft.savedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 0)
                Menu {
                    Button {
                        openDraft(checkpoint)
                    } label: {
                        Label(tr("Continue planning", "Fortsett planleggingen"),
                              systemImage: "arrow.uturn.forward")
                    }
                    Button {
                        beginNewPlanCreation()
                    } label: {
                        Label(tr("Start a new plan", "Start ny plan"),
                              systemImage: "plus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        draftPendingDeletionID = checkpoint.draftID
                        showingDeletePlanDraftConfirmation = true
                    } label: {
                        Label(tr("Delete draft", "Slett utkast"),
                              systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(tr("Draft options", "Valg for utkast"))
                .accessibilityHint(tr(
                    "Continue, start a new plan or delete this draft",
                    "Fortsett, start en ny plan eller slett utkastet"
                ))
            }

            if let planDraftDeletionError {
                Label(planDraftDeletionError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.isStaticText)
            }

            Button {
                openDraft(checkpoint)
            } label: {
                HStack {
                    Label(tr("Resume my plan", "Fortsett på planen"), systemImage: "arrow.uturn.forward")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 49)
                .background(ATHLTHPlanDesign.ink,
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr(
                "Opens your unfinished plan at the last editing position.",
                "Åpner utkastet der du avsluttet redigeringen."
            ))

            Label(tr("Saved on this iPhone", "Utkast lagret på iPhone"),
                  systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(ATHLTHPlanDesign.Density.comfortable.cardPadding)
        .athlthPlanCard(radius: 22)
    }

    private var workspaceNavigation: some View {
        HStack(spacing: 5) {
            Button {
                browsingMyPlans = false
            } label: {
                Text(tr("Plan overview", "Planoversikt"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(browsingMyPlans ? secondaryInk : Color.white)
                    .background(
                        browsingMyPlans ? Color.clear : graphite,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            Button {
                browsingMyPlans = true
            } label: {
                Text(tr("My plans", "Mine planer"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(browsingMyPlans ? Color.white : secondaryInk)
                    .background(
                        browsingMyPlans ? graphite : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
        }
        .buttonStyle(.plain)
        .padding(5)
        .background(soft, in: RoundedRectangle(cornerRadius: 17))
    }

    private func planLibraryPriority(_ item: TrainingPlan) -> Int {
        if item.id == session.activePlan?.id { return 0 }
        guard let start = item.startDate else { return 2 }
        let today = Calendar.current.startOfDay(for: Date())
        let planStart = Calendar.current.startOfDay(for: start)
        if planStart > today { return 1 }
        let endExclusive = Calendar.current.date(
            byAdding: .day, value: max(item.weeks.count * 7, 0),
            to: planStart
        ) ?? planStart
        return endExclusive <= today ? 3 : 2
    }

    private func planLibraryStatus(_ item: TrainingPlan) -> String {
        switch planLibraryPriority(item) {
        case 0: return tr("Active", "Aktiv")
        case 1: return tr("Upcoming", "Kommende")
        case 3: return tr("Previous", "Tidligere")
        default: return tr("Saved", "Lagret")
        }
    }

    private var savedPlansOverview: some View {
        let plans = session.trainingPlans.sorted { lhs, rhs in
            let firstPriority = planLibraryPriority(lhs)
            let secondPriority = planLibraryPriority(rhs)
            if firstPriority != secondPriority { return firstPriority < secondPriority }
            return (lhs.startDate ?? lhs.createdAt) >
                (rhs.startDate ?? rhs.createdAt)
        }
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(tr("My training plans", "Mine treningsplaner"))
                    .font(.system(size: 23, weight: .regular, design: .serif))
                Spacer()
                Text("\(plans.count) " + tr("plans", "planer"))
                    .font(.caption)
                    .foregroundStyle(secondaryInk)
            }

            if plans.isEmpty {
                Text(tr("No plans yet. Create your first plan to get started.",
                        "Ingen planer ennå. Opprett en plan for å komme i gang."))
                    .font(.subheadline)
                    .foregroundStyle(secondaryInk)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(line: line)
            }
            ForEach(plans) { item in
                let selected = item.id == plan?.id
                let priority = planLibraryPriority(item)
                Button {
                    focusedPlanID = item.id
                    browsingMyPlans = false
                    selectedWeekIndex = nil
                    selectedDayID = nil
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: priority == 0
                              ? "checkmark.circle.fill" : "calendar")
                            .foregroundStyle(warmGold)
                            .frame(width: 27)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                if priority == 0 {
                                    Text(planLibraryStatus(item))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(warmGold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            warmGold.opacity(0.10),
                                            in: Capsule()
                                        )
                                }
                            }
                            HStack(spacing: 5) {
                                Text("\(item.weeks.count) " + tr("weeks", "uker"))
                                Text("·")
                                if let start = item.startDate {
                                    Text(start.formatted(
                                        .dateTime.day().month(.abbreviated).year()
                                    ))
                                } else {
                                    Text(tr("No start date", "Uten startdato"))
                                }
                                if priority != 0 {
                                    Text("·")
                                    Text(planLibraryStatus(item))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(secondaryInk)
                        }
                        Spacer(minLength: 3)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(secondaryInk)
                    }
                    .foregroundStyle(graphite)
                    .padding(15)
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                    .background(
                        selected ? soft : Color.white,
                        in: RoundedRectangle(cornerRadius: 17)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func clickableWeekOverview(_ week: TrainingPlanWeek, plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Choose a day to view or add a workout", "Velg en dag for å se eller legge til en økt"))
                .font(.subheadline).foregroundStyle(secondaryInk)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78))], spacing: 8) {
                ForEach(week.days.sorted { $0.dayIndex < $1.dayIndex }) { day in
                    let selected = selectedDayID == day.id
                    let date = planDayDate(day.dayIndex, plan: plan)
                    Button {
                        selectedDayID = day.id
                    } label: {
                        VStack(spacing: 5) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.subheadline.weight(.semibold))
                            Text(date.formatted(.dateTime.day()))
                                .font(.title3.weight(.semibold))
                            Text(day.sessions.filter { !$0.isExplicitRestDay }.isEmpty
                                 ? tr("Rest", "Fri")
                                 : tr("\(day.sessions.filter { !$0.isExplicitRestDay }.count) workouts",
                                      "\(day.sessions.filter { !$0.isExplicitRestDay }.count) økter"))
                                .font(.caption2)
                        }
                        .foregroundStyle(selected ? Color.white : graphite)
                        .frame(maxWidth: .infinity, minHeight: 90)
                        .background(selected ? graphite : soft, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if selectedDayID != nil {
                Button(tr("Show the whole week", "Vis hele uken")) { selectedDayID = nil }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .foregroundStyle(graphite)
            }
        }
    }

    private var planChooser: some View {
        Menu {
            ForEach(session.trainingPlans) { item in
                Button {
                    focusedPlanID = item.id
                    browsingMyPlans = false
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
                beginNewPlanCreation()
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
                        .font(.caption2.weight(.semibold))
                        .tracking(2.2)
                        .foregroundStyle(warmGold)
                    Text(tr("Training plan", "Treningsplan"))
                        .font(.system(size: 34, weight: .regular, design: .serif))
                }
                Spacer()
                Button {
                    beginNewPlanCreation()
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

            HStack(spacing: 8) {
                Text(advanced
                     ? tr("Detailed plan view", "Detaljert planvisning")
                     : tr("Simple plan overview", "Enkel planoversikt"))
                    .font(.caption)
                    .foregroundStyle(secondaryInk)
                Spacer()
                Menu {
                    Button(tr("Simple view", "Enkel visning")) {
                        advanced = false
                    }
                    Button(tr("Detailed view", "Detaljert visning")) {
                        advanced = true
                    }
                } label: {
                    Label(tr("View options", "Visning"),
                          systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(graphite)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(soft, in: Capsule())
                }
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
                    beginNewPlanCreation()
                }
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 18)
        }
        .surface(line: line)
    }


    // MARK: - Premium plan overview (same visual language as Train / I dag)

    private func premiumPlanDashboard(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 19) {
            if session.activePlan?.id != plan.id {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(tr("Saved or upcoming plan", "Lagret eller kommende plan"))
                    Spacer()
                    if let active = session.activePlan {
                        Button(tr("Active plan", "Aktiv plan")) {
                            focusedPlanID = active.id
                            selectedWeekIndex = nil
                            selectedDayID = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundStyle(secondaryInk)
            }

            premiumPlanHeader(plan)
            premiumPlanActions(plan)
            if showingEntirePlan {
                premiumAllWeeks(plan)
            }
            if let week = selectedWeek {
                premiumPlanWeek(plan, week: week)
            } else {
                Text(tr("This plan has no training weeks yet.",
                        "Denne planen har ingen treningsuker ennå."))
                    .font(.subheadline)
                    .foregroundStyle(secondaryInk)
                Button(tr("Edit plan", "Rediger plan")) { showingEditor = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func premiumPlanHeroArt(_ plan: TrainingPlan) -> String {
        let kinds = plan.weeks.flatMap(\.days)
            .flatMap(\.sessions).filter { !$0.isExplicitRestDay }.map(\.kind)
        let running = kinds.filter { $0 == .running }.count
        let strengthSessions = kinds.filter { $0 == .strength }.count
        if running > 0 && running >= strengthSessions { return "GoalRunning" }
        if strengthSessions > 0 { return "StrengthQuickHero" }
        if kinds.contains(.walking) { return "GoalWalking" }
        return "GoalMountain"
    }

    private func premiumPlanHeader(_ plan: TrainingPlan) -> some View {
        let progress = session.trainingPlanProgress(
            plan, healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let percent = Int((min(max(progress.completionFraction, 0), 1) * 100).rounded())
        let currentWeekNumber = min(
            max((selectedWeekIndex ?? currentWeekIndex(plan)) + 1, 1),
            max(plan.weeks.count, 1)
        )
        let thisWeek = selectedWeek
        let workouts = thisWeek?.days.flatMap(\.sessions)
            .filter { !$0.isExplicitRestDay } ?? []
        let done = workouts.filter { isPremiumPlanWorkoutCompleted($0, plan: plan) }.count
        let remaining = workouts.filter {
            !isPremiumPlanWorkoutCompleted($0, plan: plan) &&
            !session.isPlanSessionSkipped(planID: plan.id, sessionID: $0.id)
        }.count
        let restDays = thisWeek?.days.filter { day in
            day.sessions.isEmpty || day.sessions.allSatisfy(\.isExplicitRestDay)
        }.count ?? 0

        return VStack(spacing: -31) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    Image(premiumPlanHeroArt(plan))
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: 198)
                        .clipped()
                }
                .frame(height: 198)

                LinearGradient(
                    colors: [.black.opacity(0.12), .black.opacity(0.60)],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("TRAINING PLAN", "TRENINGSPLAN"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.5)
                    Text(plan.title)
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tr("\(plan.weeks.count) weeks", "\(plan.weeks.count) uker")
                         + " · " + tr("Week", "Uke") + " \(currentWeekNumber)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer().frame(height: 20)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                Menu {
                    Button {
                        editingPlan = plan
                    } label: {
                        Label(tr("Edit plan details", "Rediger plandetaljer"),
                              systemImage: "slider.horizontal.3")
                    }
                    Button { showingEditor = true } label: {
                        Label(tr("Edit training week", "Rediger treningsuken"),
                              systemImage: "calendar")
                    }
                    Button { browsingMyPlans = true } label: {
                        Label(tr("My plans", "Mine planer"), systemImage: "square.stack")
                    }
                    Button {
                        beginNewPlanCreation()
                    } label: {
                        Label(tr("Create new plan", "Ny treningsplan"),
                              systemImage: "plus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        trainingPlanPendingDeletion = plan
                    } label: {
                        Label(tr("Delete plan", "Slett treningsplan"),
                              systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(graphite)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.94), in: Circle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topTrailing)
                .padding(13)
            }
            .frame(height: 198)
            .clipShape(RoundedRectangle(cornerRadius: 21))
            .accessibilityElement(children: .contain)

            HStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(line.opacity(0.7), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: min(max(progress.completionFraction, 0), 1))
                        .stroke(graphite, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(percent) %")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 65, height: 65)

                premiumPlanMetric("\(workouts.count)",
                    tr("workouts this week", "økter denne uken"))
                premiumPlanMetric("\(done)",
                    tr("completed", "fullført"))
                premiumPlanMetric("\(remaining)",
                    tr("remaining", "gjenstår"))
                premiumPlanMetric("\(restDays)",
                    tr("rest days", "hviledager"))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(line.opacity(0.65), lineWidth: 0.7)
            }
            .shadow(color: graphite.opacity(0.09), radius: 16, y: 8)
            .padding(.horizontal, 10)
        }
    }

    private func premiumPlanMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 20, weight: .medium, design: .serif))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(secondaryInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
    }

    private func premiumPlanActions(_ plan: TrainingPlan) -> some View {
        HStack(spacing: 7) {
            premiumPlanAction(
                tr("Full plan", "Se hele planen"), icon: "list.bullet"
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingEntirePlan.toggle()
                }
            }
            premiumPlanAction(
                tr("Edit plan", "Rediger plan"), icon: "slider.horizontal.3"
            ) { showingEditor = true }
            Menu {
                ForEach(Array(plan.weeks.enumerated()), id: \.offset) { entry in
                    let index = entry.offset
                    Button(tr("Week \(index + 1)", "Uke \(index + 1)")) {
                        selectPremiumPlanWeek(index)
                    }
                }
            } label: {
                premiumPlanActionLabel(tr("Change week", "Bytt uke"),
                                        icon: "chevron.left.chevron.right")
            }
            premiumPlanAction(
                tr("My workouts", "Mine økter"), icon: "square.on.square"
            ) { showingWorkoutLibrary = true }
        }
    }

    private func premiumPlanAction(
        _ label: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { premiumPlanActionLabel(label, icon: icon) }
            .buttonStyle(.plain)
    }

    private func premiumPlanActionLabel(_ label: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(graphite)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(line.opacity(0.65), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13))
    }

    private func selectPremiumPlanWeek(_ index: Int) {
        withAnimation(.easeInOut(duration: 0.21)) {
            selectedWeekIndex = index
            selectedDayID = nil
            selectedWorkoutID = nil
            selectedDetailSection = .structure
        }
    }

    private func premiumAllWeeks(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Entire training plan", "Hele treningsplanen"))
                .font(.system(size: 20, weight: .regular, design: .serif))
            ForEach(Array(plan.weeks.enumerated()), id: \.offset) { entry in
                let index = entry.offset
                let week = entry.element
                DisclosureGroup {
                    VStack(spacing: 4) {
                        ForEach(week.days.sorted(by: {
                            $0.dayIndex < $1.dayIndex
                        })) { day in
                            Button {
                                selectPremiumPlanWeek(index)
                                selectedDayID = day.id
                                showingEntirePlan = false
                            } label: {
                                HStack(spacing: 11) {
                                    Text(copyPlanDate(day.dayIndex, week: index, plan: plan)
                                        .formatted(.dateTime.weekday(.abbreviated).day()))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(secondaryInk)
                                        .frame(width: 50, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 3) {
                                        if day.sessions.isEmpty {
                                            Text(tr("Rest day", "Hviledag"))
                                                .font(.subheadline)
                                        } else {
                                            ForEach(day.sessions) { workout in
                                                Text(workout.title)
                                                    .font(.subheadline.weight(.medium))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(secondaryInk)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(graphite)
                        }
                    }
                    .padding(.top, 7)
                } label: {
                    let workoutCount = week.days.flatMap(\.sessions)
                        .filter { !$0.isExplicitRestDay }.count
                    HStack {
                        Text(tr("Week \(index + 1)", "Uke \(index + 1)"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(workoutCount) " + tr("workouts", "økter"))
                            .font(.caption)
                            .foregroundStyle(secondaryInk)
                            .padding(.trailing, 7)
                    }
                }
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }

    private func isPremiumPlanWorkoutCompleted(
        _ workout: PlannedSession, plan: TrainingPlan
    ) -> Bool {
        session.isPlanSessionCompleted(
            planID: plan.id, sessionID: workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
    }

    private func premiumSelectedDay(in week: TrainingPlanWeek, plan: TrainingPlan)
    -> TrainingPlanDay? {
        if let selectedDayID,
           let found = week.days.first(where: { $0.id == selectedDayID }) {
            return found
        }
        let current = week.days.first {
            Calendar.current.isDate(planDayDate($0.dayIndex, plan: plan),
                                    inSameDayAs: Date())
        }
        return current ?? week.days.first(where: {
            $0.sessions.contains(where: { !$0.isExplicitRestDay })
        }) ?? week.days.sorted(by: { $0.dayIndex < $1.dayIndex }).first
    }

    private func premiumPlanWeek(
        _ plan: TrainingPlan, week: TrainingPlanWeek
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("This week", "Denne uken"))
                    .font(.system(size: 23, weight: .regular, design: .serif))
                Spacer()
                Text(tr("Week", "Uke") + " \((selectedWeekIndex ?? currentWeekIndex(plan)) + 1) " +
                    tr("of", "av") + " \(plan.weeks.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryInk)
                Button {
                    selectPremiumPlanWeek(
                        max((selectedWeekIndex ?? currentWeekIndex(plan)) - 1, 0)
                    )
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 38)
                }
                .disabled((selectedWeekIndex ?? currentWeekIndex(plan)) == 0)
                Button {
                    selectPremiumPlanWeek(
                        min((selectedWeekIndex ?? currentWeekIndex(plan)) + 1,
                            plan.weeks.count - 1)
                    )
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 30, height: 38)
                }
                .disabled((selectedWeekIndex ?? currentWeekIndex(plan)) ==
                          plan.weeks.count - 1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(graphite)

            premiumPlanDayStrip(plan, week: week)
            if let selected = premiumSelectedDay(in: week, plan: plan) {
                premiumSelectedDayPanel(selected, plan: plan)
            }
        }
    }

    private func premiumPlanDayStrip(
        _ plan: TrainingPlan, week: TrainingPlanWeek
    ) -> some View {
        HStack(alignment: .top, spacing: 5) {
            ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                premiumPlanDayTile(day, plan: plan,
                                   selected: premiumSelectedDay(in: week, plan: plan)?.id == day.id)
            }
        }
    }

    private func premiumPlanDayTile(
        _ day: TrainingPlanDay, plan: TrainingPlan, selected: Bool
    ) -> some View {
        let date = planDayDate(day.dayIndex, plan: plan)
        let workouts = day.sessions.filter { !$0.isExplicitRestDay }
        let completed = !workouts.isEmpty &&
            workouts.allSatisfy { isPremiumPlanWorkoutCompleted($0, plan: plan) }
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedDayID = day.id
                selectedWorkoutID = nil
                selectedDetailSection = .structure
            }
        } label: {
            VStack(spacing: 6) {
                Text(weekday(day.dayIndex, plan: plan))
                    .font(.system(size: 10, weight: .semibold))
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Image(systemName: completed ? "checkmark.circle.fill" :
                      workouts.isEmpty ? "circle.fill" :
                      selected ? day.sessions.first?.kind.systemImage ?? "figure.run" :
                      "circle")
                    .font(.system(size: selected ? 17 : 14, weight: .semibold))
                    .foregroundStyle(
                        completed ? Color.green.opacity(0.9) :
                        selected ? Color.white : secondaryInk.opacity(0.72)
                    )
                    .frame(height: 19)

                Text(workouts.first.map {
                    $0.title
                } ?? tr("Rest", "Hvile"))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .frame(height: 26)
                if let minutes = workouts.first?.durationMinutes, minutes > 0 {
                    Text("\(minutes) min")
                        .font(.system(size: 9))
                        .foregroundStyle(selected ? .white.opacity(0.78) :
                            secondaryInk)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
            .foregroundStyle(selected ? .white : graphite)
            .frame(maxWidth: .infinity, minHeight: 115, alignment: .top)
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .background(selected ? graphite : Color.white.opacity(0.90),
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(
            date.formatted(.dateTime.weekday(.wide).day().month(.wide)) +
            " · " + (workouts.first?.title ?? tr("Rest", "Hviledag"))
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }


    // MARK: - Selected training day, workout structure and details

    private func premiumSelectedDayPanel(
        _ day: TrainingPlanDay, plan: TrainingPlan
    ) -> some View {
        let sessions = day.sessions.filter { !$0.isExplicitRestDay }
        return VStack(alignment: .leading, spacing: 14) {
            if sessions.isEmpty {
                premiumRestDayPanel(day, plan: plan)
            } else {
                if sessions.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sessions) { workout in
                                let current = (selectedWorkoutID ?? sessions[0].id) == workout.id
                                Button {
                                    selectedWorkoutID = workout.id
                                    selectedDetailSection = .structure
                                } label: {
                                    Text(workout.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(current ? .white : graphite)
                                        .padding(.horizontal, 13)
                                        .frame(minHeight: 38)
                                        .background(current ? graphite : soft,
                                                    in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                let current = sessions.first(where: {
                    $0.id == (selectedWorkoutID ?? sessions[0].id)
                }) ?? sessions[0]
                premiumWorkoutDetailCard(
                    current, day: day, plan: plan
                )
            }
        }
    }

    private func premiumRestDayPanel(
        _ day: TrainingPlanDay, plan: TrainingPlan
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.recoveryBlue)
                    .frame(width: 47, height: 47)
                    .background(ATHLTHTheme.recoveryBlueSoft,
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(planDayDate(day.dayIndex, plan: plan)
                        .formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryInk)
                    Text(tr("Rest and recovery", "Hvile og restitusjon"))
                        .font(.system(size: 21, weight: .regular, design: .serif))
                }
            }
            Text(tr("No workout is planned for this day.",
                    "Ingen treningsøkt er planlagt denne dagen."))
                .font(.subheadline)
                .foregroundStyle(secondaryInk)

            Button {
                editingWorkout = WorkoutEditDestination(
                    planID: plan.id, dayID: day.id,
                    version: plan.version, workout: nil
                )
            } label: {
                Label(tr("Add workout", "Legg til økt"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .tint(graphite)
        }
        .padding(16)
        .surface(line: line)
    }

    private func premiumWorkoutDetailCard(
        _ workout: PlannedSession,
        day: TrainingPlanDay, plan: TrainingPlan
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 11) {
                Image(premiumWorkoutArt(for: workout))
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 91)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: workout.kind.systemImage)
                        Text(workout.kind.title.uppercased())
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(secondaryInk)
                    Text(workout.title)
                        .font(.system(size: 23, weight: .regular, design: .serif))
                        .foregroundStyle(graphite)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    HStack(spacing: 8) {
                        if let duration = workout.durationMinutes {
                            Label("\(duration) min", systemImage: "clock")
                        }
                        if let distance = workout.targetDistanceKilometers {
                            Text(String(format: "%.1f km", distance))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(secondaryInk)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Menu {
                    Button {
                        editingWorkout = WorkoutEditDestination(
                            planID: plan.id, dayID: day.id,
                            version: plan.version, workout: workout
                        )
                    } label: {
                        Label(tr("Edit workout", "Rediger økt"),
                              systemImage: "square.and.pencil")
                    }
                    Button {
                        beginMovingWorkout(workout, day: day, plan: plan)
                    } label: {
                        Label(tr("Move workout", "Flytt økt"),
                              systemImage: "arrow.left.arrow.right")
                    }
                    Button { preparePlanDayCopy(day, plan: plan) } label: {
                        Label(tr("Copy day", "Kopier dag"),
                              systemImage: "square.on.square")
                    }
                    Button {
                        session.saveSharedWorkout(workout)
                    } label: {
                        Label(tr("Save to My workouts", "Lagre til Mine økter"),
                              systemImage: "bookmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(graphite)
                        .frame(width: 37, height: 37)
                        .background(soft, in: RoundedRectangle(cornerRadius: 11))
                }
            }

            HStack(spacing: 7) {
                if isPremiumPlanWorkoutCompleted(workout, plan: plan) {
                    Label(tr("Completed", "Gjennomført"),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ATHLTHTheme.vitality)
                } else if session.isPlanSessionSkipped(
                    planID: plan.id, sessionID: workout.id
                ) {
                    Label(tr("Skipped", "Hoppet over"),
                          systemImage: "forward.end")
                        .foregroundStyle(secondaryInk)
                } else {
                    Label(tr("Planned", "Planlagt"), systemImage: "calendar")
                        .foregroundStyle(secondaryInk)
                }
                Spacer()
                Text(planDayDate(day.dayIndex, plan: plan)
                    .formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .foregroundStyle(secondaryInk)
            }
            .font(.caption.weight(.medium))

            Divider().overlay(line.opacity(0.75))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(PlanDetailSection.allCases) { section in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedDetailSection = section
                            }
                        } label: {
                            VStack(spacing: 7) {
                                Text(section.title)
                                    .font(.system(size: 11, weight:
                                        selectedDetailSection == section ? .semibold : .medium))
                                    .foregroundStyle(
                                        selectedDetailSection == section
                                            ? graphite : secondaryInk)
                                Rectangle()
                                    .fill(selectedDetailSection == section
                                        ? graphite : .clear)
                                    .frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedDetailSection == section ? .isSelected : []
                        )
                    }
                }
            }

            premiumWorkoutDetailSection(workout, plan: plan)

            HStack(spacing: 9) {
                premiumWorkoutFooterAction(
                    tr("Edit", "Rediger"), icon: "pencil"
                ) {
                    editingWorkout = WorkoutEditDestination(
                        planID: plan.id, dayID: day.id,
                        version: plan.version, workout: workout
                    )
                }
                premiumWorkoutFooterAction(
                    tr("Move", "Flytt"), icon: "arrow.left.arrow.right"
                ) {
                    beginMovingWorkout(workout, day: day, plan: plan)
                }
                premiumWorkoutFooterAction(
                    tr("Copy", "Kopier"), icon: "square.on.square"
                ) {
                    preparePlanDayCopy(day, plan: plan)
                }
                premiumWorkoutFooterAction(
                    tr("Save", "Lagre"), icon: "bookmark"
                ) {
                    session.saveSharedWorkout(workout)
                    copyFeedback = tr("Saved to My workouts", "Lagret i Mine økter")
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(line.opacity(0.72), lineWidth: 0.8)
        }
    }

    private func premiumWorkoutFooterAction(
        _ title: String, icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
            .foregroundStyle(graphite)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(soft, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func premiumWorkoutArt(for workout: PlannedSession) -> String {
        switch workout.kind {
        case .running: return "GoalRunning"
        case .walking: return "GoalWalking"
        case .strength: return "StrengthQuickHero"
        case .mobility, .recovery: return "GoalRecovery"
        case .custom: return "TrainHero"
        }
    }

    @ViewBuilder
    private func premiumWorkoutDetailSection(
        _ workout: PlannedSession, plan: TrainingPlan
    ) -> some View {
        switch selectedDetailSection {
        case .structure:
            premiumWorkoutStructure(workout)
        case .details:
            premiumWorkoutFacts(workout)
        case .route:
            premiumWorkoutRoute(workout)
        case .coach:
            premiumWorkoutCoach(workout)
        case .history:
            premiumWorkoutHistory(workout, plan: plan)
        }
    }

    private func premiumWorkoutStructure(_ workout: PlannedSession) -> some View {
        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        let targetZones = Array(Set(blocks.compactMap(\.targetHeartRateZone))).sorted()
        let phasePlaylists = workout.resolvedRunningWorkouts
            .flatMap(\.blocks)
            .compactMap { block -> (String, SpotifyPlaylistReference)? in
                guard let playlist = block.spotifyPlaylist else { return nil }
                return (block.title, playlist)
            }
        return VStack(alignment: .leading, spacing: 13) {
            if blocks.isEmpty {
                Label(tr("No detailed steps have been registered.",
                         "Økten har ingen detaljerte blokker ennå."),
                      systemImage: "list.bullet")
                    .font(.subheadline)
                    .foregroundStyle(secondaryInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(soft, in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(tr("Workout structure", "Øktstruktur"),
                              systemImage: "list.number")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(graphite)
                        ForEach(Array(blocks.prefix(16).enumerated()),
                                id: \.offset) { index, block in
                            premiumStructureBlock(block, preceding:
                                index == 0 ? nil : blocks[index - 1])
                        }
                        if blocks.count > 16 {
                            Text(tr("\(blocks.count - 16) more steps",
                                    "\(blocks.count - 16) flere steg"))
                                .font(.caption)
                                .foregroundStyle(secondaryInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !targetZones.isEmpty ||
                       blocks.contains(where: { $0.targetPaceSecondsPerKilometer != nil }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(tr("Targets", "Mål"),
                                  systemImage: "chart.bar.fill")
                                .font(.caption.weight(.semibold))
                            if !targetZones.isEmpty {
                                Text(tr("Heart-rate zone", "Pulssone") + " " +
                                     targetZones.map(String.init).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(secondaryInk)
                            }
                            if let pace = blocks.compactMap(
                                \.targetPaceSecondsPerKilometer).first,
                               pace > 0 {
                                Text(String(format: "%d:%02d min/km",
                                            Int(pace) / 60, Int(pace) % 60))
                                    .font(.caption)
                                    .foregroundStyle(secondaryInk)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(soft, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            if !phasePlaylists.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Label(tr("Planned music", "Planlagt musikk"),
                          systemImage: "music.note.list")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(graphite)
                    ForEach(Array(phasePlaylists.enumerated()), id: \.offset) { item in
                        HStack(spacing: 9) {
                            Image(systemName: "music.note")
                                .foregroundStyle(warmGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.element.0)
                                    .font(.caption.weight(.semibold))
                                Text(item.element.1.name)
                                    .font(.caption)
                                    .foregroundStyle(secondaryInk)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Text(tr(
                        "Playlist preferences are saved with their phases; automatic switching is not enabled.",
                        "Spillelistene er lagret per del. Automatisk bytte mellom delene er ikke aktivert."
                    ))
                    .font(.caption2)
                    .foregroundStyle(secondaryInk)
                }
                .padding(12)
                .background(soft, in: RoundedRectangle(cornerRadius: 14))
            }
            if let duration = workout.durationMinutes, duration > 0 {
                Label(tr("Estimated total", "Forventet totaltid") +
                      " · \(duration) min", systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(graphite)
            }
        }
    }

    private func premiumStructureBlock(
        _ block: WorkoutTemplateBlock, preceding: WorkoutTemplateBlock?
    ) -> some View {
        let startsPhase = preceding?.resolvedPhase != block.resolvedPhase
        let startsGroup = block.groupID != nil &&
            block.groupID != preceding?.groupID
        return VStack(alignment: .leading, spacing: 4) {
            if startsPhase {
                Text(block.resolvedPhase.title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(secondaryInk)
                    .padding(.top, 5)
            }
            if startsGroup, let kind = block.groupKind {
                Text(kind.title + " · " + "\(block.groupRounds ?? 1) " +
                     tr("rounds", "runder"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(graphite)
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: block.kind == .rest ? "pause.circle" :
                      block.kind == .exercise ? "dumbbell" :
                      block.kind == .run ? "figure.run" : "circle.fill")
                    .font(.caption)
                    .foregroundStyle(block.kind == .rest
                        ? secondaryInk : ATHLTHTheme.accentDeep)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(graphite)
                        .fixedSize(horizontal: false, vertical: true)
                    if let target = block.targetText {
                        Text(target)
                            .font(.system(size: 11))
                            .foregroundStyle(secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(soft, in: RoundedRectangle(cornerRadius: 11))
    }

    private func premiumWorkoutFacts(_ workout: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            premiumFact(tr("Activity", "Aktivitet"), workout.kind.title,
                        symbol: workout.kind.systemImage)
            if let minutes = workout.durationMinutes {
                premiumFact(tr("Estimated duration", "Estimert varighet"),
                            "\(minutes) min", symbol: "clock")
            }
            if let distance = workout.targetDistanceKilometers {
                premiumFact(tr("Target distance", "Måldistanse"),
                            String(format: "%.1f km", distance),
                            symbol: "figure.run")
            }
            if let scheduled = workout.scheduledStart {
                premiumFact(tr("Planned time", "Planlagt tidspunkt"),
                            scheduled.formatted(.dateTime.hour().minute()),
                            symbol: "calendar")
            }
            if let place = workout.plannedTrainingPlace {
                premiumFact(tr("Training place", "Treningssted"),
                            place.name, symbol: "mappin")
            }
            let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
            premiumFact(tr("Training steps", "Treningsblokker"),
                        "\(blocks.count)", symbol: "list.number")
        }
    }

    private func premiumFact(
        _ title: String, _ value: String, symbol: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(secondaryInk)
                .frame(width: 23)
            Text(title)
                .font(.caption)
                .foregroundStyle(secondaryInk)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(graphite)
                .multilineTextAlignment(.trailing)
        }
        .padding(13)
        .background(soft, in: RoundedRectangle(cornerRadius: 12))
    }

    private func premiumWorkoutRoute(_ workout: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(tr("Route", "Rute"), systemImage: "map")
                .font(.subheadline.weight(.semibold))
            Text(workout.routeID == nil
                ? tr("No route has been added to this workout.",
                     "Ingen rute er knyttet til denne økten.")
                : tr("A route is attached to this workout. Open workout details to view it.",
                     "En rute er knyttet til økten. Åpne øktdetaljene for å se den."))
                .font(.caption)
                .foregroundStyle(secondaryInk)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(soft, in: RoundedRectangle(cornerRadius: 12))
    }

    private func premiumWorkoutCoach(_ workout: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(tr("Coach notes", "Trenernotater"),
                  systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
            Text((workout.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false ? workout.notes : nil) ??
                tr("No notes have been added yet.",
                   "Ingen trenernotater er lagt inn ennå."))
                .font(.subheadline)
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(soft, in: RoundedRectangle(cornerRadius: 12))
    }

    private func premiumWorkoutHistory(
        _ workout: PlannedSession, plan: TrainingPlan
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("Workout history", "Økthistorikk"),
                  systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
            Text(isPremiumPlanWorkoutCompleted(workout, plan: plan)
                ? tr("This planned workout is recorded as completed.",
                     "Denne planlagte økten er registrert som gjennomført.")
                : tr("This session has not been completed yet.",
                     "Denne økten er ennå ikke registrert som fullført."))
                .font(.caption)
                .foregroundStyle(secondaryInk)
            Text(tr("Recorded results can be viewed under Progress.",
                    "Registrerte prestasjoner finner du under Fremgang."))
                .font(.caption)
                .foregroundStyle(secondaryInk)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(soft, in: RoundedRectangle(cornerRadius: 12))
    }


    // MARK: - Copy a complete day without discarding scheduled sessions

    private func preparePlanDayCopy(
        _ day: TrainingPlanDay, plan: TrainingPlan
    ) {
        guard day.sessions.contains(where: { !$0.isExplicitRestDay }) else { return }
        copyingSourceDayID = day.id
        copyTargetDayIDs = []
        copyTargetWeekIndex = selectedWeekIndex ?? currentWeekIndex(plan)
        showingCopyDay = true
    }

    private func planCopyDaySheet(
        plan: TrainingPlan, sourceDayID: UUID
    ) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    Button {
                        copyTargetWeekIndex = max(copyTargetWeekIndex - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(copyTargetWeekIndex == 0)
                    Spacer()
                    Text(tr("Week", "Uke") + " \(copyTargetWeekIndex + 1) " +
                         tr("of", "av") + " \(plan.weeks.count)")
                        .font(.headline)
                    Spacer()
                    Button {
                        copyTargetWeekIndex = min(
                            copyTargetWeekIndex + 1, plan.weeks.count - 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(copyTargetWeekIndex == plan.weeks.count - 1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(graphite)
                .padding(.horizontal, 12)

                if plan.weeks.indices.contains(copyTargetWeekIndex) {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(plan.weeks[copyTargetWeekIndex].days.sorted(
                                by: { $0.dayIndex < $1.dayIndex }
                            )) { day in
                                let date = copyPlanDate(
                                    day.dayIndex, week: copyTargetWeekIndex,
                                    plan: plan)
                                let disabled = day.id == sourceDayID ||
                                    date < Calendar.current.startOfDay(for: Date())
                                let selected = copyTargetDayIDs.contains(day.id)
                                Button {
                                    if selected {
                                        copyTargetDayIDs.remove(day.id)
                                    } else {
                                        copyTargetDayIDs.insert(day.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName:
                                            selected ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(date.formatted(
                                                .dateTime.weekday(.wide).day().month(.wide)))
                                                .font(.subheadline.weight(.semibold))
                                            Text(day.id == sourceDayID
                                                ? tr("Original day", "Originaldag")
                                                : day.sessions.isEmpty
                                                ? tr("No workout scheduled", "Ingen økt planlagt")
                                                : tr("Existing workouts are kept",
                                                     "Eksisterende økter beholdes"))
                                                .font(.caption)
                                                .foregroundStyle(secondaryInk)
                                        }
                                        Spacer()
                                    }
                                    .foregroundStyle(graphite)
                                    .padding(14)
                                    .background(selected ? ATHLTHPlanDesign.selectedSurface :
                                                .white,
                                                in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .disabled(disabled)
                                .opacity(disabled ? 0.42 : 1)
                            }
                        }
                        .padding(.horizontal, 15)
                    }
                }

                Text(tr("Selected dates can span several weeks. Existing workouts are kept.",
                        "Du kan velge dager i flere uker. Eksisterende økter beholdes."))
                    .font(.caption)
                    .foregroundStyle(secondaryInk)
                    .padding(.horizontal, 15)

                Button {
                    applyPlanDayCopy(planID: plan.id, sourceDayID: sourceDayID)
                } label: {
                    Text(tr("Copy to selected days", "Kopier til valgte dager") +
                         " (\(copyTargetDayIDs.count))")
                        .frame(maxWidth: .infinity, minHeight: 51)
                }
                .buttonStyle(.borderedProminent)
                .tint(graphite)
                .disabled(copyTargetDayIDs.isEmpty)
                .padding(.horizontal, 15)
                .padding(.bottom, 12)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Copy day", "Kopier dag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { showingCopyDay = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func copyPlanDate(
        _ dayIndex: Int, week: Int, plan: TrainingPlan
    ) -> Date {
        let start = Calendar.current.startOfDay(for: plan.startDate ?? Date())
        return Calendar.current.date(
            byAdding: .day, value: week * 7 + dayIndex - 1, to: start
        ) ?? start
    }

    private func applyPlanDayCopy(planID: UUID, sourceDayID: UUID) {
        guard let current = session.trainingPlan(withID: planID),
              let source = current.weeks.flatMap(\.days)
                .first(where: { $0.id == sourceDayID })
        else { return }
        let workouts = source.sessions.filter { !$0.isExplicitRestDay }
        guard !workouts.isEmpty else { return }
        var copiedCount = 0
        var errors = 0

        // Resolve the latest version before each copy. The storage API
        // checks future dates and generates independent IDs for every copy.
        for dayID in copyTargetDayIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            for workout in workouts {
                guard let latest = session.trainingPlan(withID: planID) else {
                    errors += 1
                    continue
                }
                if session.copyPlanStudioWorkout(
                    planID: planID,
                    sourceWorkoutID: workout.id,
                    targetDayID: dayID,
                    expectedVersion: latest.version
                ) {
                    copiedCount += 1
                } else {
                    errors += 1
                }
            }
        }
        showingCopyDay = false
        copyTargetDayIDs = []
        copyFeedback = errors == 0
            ? tr("\(copiedCount) workout copies were added.",
                 "\(copiedCount) øktkopier ble lagt til.")
            : tr("\(copiedCount) copied, \(errors) could not be copied.",
                 "\(copiedCount) kopiert, \(errors) kunne ikke kopieres.")
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
                        .font(.caption2.weight(.bold))
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
                    Divider()
                    Button(role: .destructive) {
                        trainingPlanPendingDeletion = plan
                    } label: {
                        Label(tr("Delete training plan", "Slett treningsplan"), systemImage: "trash")
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

            actionButton(
                title: tr("Edit your training week", "Rediger treningsuken"),
                icon: "arrow.right"
            ) {
                showingEditor = true
            }
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
                        .font(.caption2.weight(.bold))
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
                clickableWeekOverview(selectedWeek, plan: plan)

                if advanced {
                    VStack(spacing: 0) {
                        ForEach(selectedWeek.days.filter {
                            selectedDayID == nil || selectedDayID == $0.id
                        }.sorted(by: {
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
        let workouts = week.days.flatMap(\.sessions).filter { !$0.isExplicitRestDay }
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
                !$0.isExplicitRestDay &&
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
        let days = week.days.filter {
            !$0.sessions.isEmpty && (selectedDayID == nil || selectedDayID == $0.id)
        }
            .sorted { $0.dayIndex < $1.dayIndex }
        return VStack(alignment: .leading, spacing: 10) {
            if days.isEmpty {
                Text(selectedDayID == nil
                     ? tr("No workouts this week", "Ingen økter denne uken")
                     : tr("No workout on this day", "Ingen økt denne dagen"))
                    .font(.subheadline)
                    .foregroundStyle(secondaryInk)
                Button {
                    if let dayID = selectedDayID ?? week.days.sorted(by: { $0.dayIndex < $1.dayIndex }).first?.id {
                        editingWorkout = WorkoutEditDestination(planID: plan.id, dayID: dayID, version: plan.version, workout: nil)
                    }
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
                            openingWorkout = WorkoutDestination(planID: plan.id, workout: workout)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: workout.isExplicitRestDay
                                    ? "moon.stars.fill" : workout.kind.systemImage)
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
                                    if let place = workout.plannedTrainingPlace {
                                        Label(place.name, systemImage: place.kind.symbol)
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                            if !completed && !skipped {
                                Divider().overlay(line.opacity(0.55)).padding(.horizontal, 16)
                                Button {
                                    editingWorkout = WorkoutEditDestination(planID: plan.id, dayID: day.id, version: plan.version, workout: workout)
                                } label: {
                                    Label(tr("Change workout", "Endre økt"), systemImage: "slider.horizontal.3")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(graphite)
                                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                        .padding(.horizontal, 18)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(line.opacity(0.55)).padding(.horizontal, 16)
                                Button {
                                    editingTrainingPlaceWorkout = WorkoutDestination(
                                        planID: plan.id, workout: workout)
                                } label: {
                                    Label(workout.plannedTrainingPlace?.name ??
                                          tr("Choose training place", "Velg treningssted"),
                                          systemImage: "mappin.and.ellipse")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(graphite)
                                        .frame(maxWidth: .infinity, minHeight: 48,
                                               alignment: .leading)
                                        .padding(.horizontal, 18)
                                }
                                .buttonStyle(.plain)
                            }
                            if !completed && !skipped &&
                               planDayDate(day.dayIndex, plan: plan) >= Calendar.current.startOfDay(for: Date()) {
                                Divider()
                                    .overlay(line.opacity(0.55))
                                    .padding(.horizontal, 16)
                                Button {
                                    beginMovingWorkout(workout, day: day, plan: plan)
                                } label: {
                                    Label(tr("Move workout", "Flytt økt"), systemImage: "calendar.badge.clock")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(graphite)
                                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                        .padding(.horizontal, 18)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(tr("Choose another day", "Velg en annen dag"))
                            }
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
                                openingWorkout = WorkoutDestination(planID: plan.id, workout: workout)
                            } label: {
                                Label(tr("Workout details", "Øktdetaljer"),
                                      systemImage: "info.circle")
                            }
                            Button {
                                editingWorkout = WorkoutEditDestination(planID: plan.id, dayID: day.id, version: plan.version, workout: workout)
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
                                    beginMovingWorkout(workout, day: day, plan: plan)
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
                            if !completed && !skipped && !workout.isExplicitRestDay {
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
                    if let dayID = selectedDayID ?? week.days.sorted(by: { $0.dayIndex < $1.dayIndex }).first?.id {
                        editingWorkout = WorkoutEditDestination(planID: plan.id, dayID: dayID, version: plan.version, workout: nil)
                    }
                } label: {
                    Label(tr("Add workout", "Legg til økt"),
                          systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .tint(warmGold)
                .accessibilityHint(tr(
                    "Choose the activity and exercises for this day",
                    "Velg treningsform og øvelser for denne dagen"
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
                    Text(weekday(day.dayIndex, plan: plan))
                        .font(.caption2.weight(.semibold))
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
                                openingWorkout = WorkoutDestination(planID: plan.id, workout: workout)
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
                                        .font(.caption2)
                                        .foregroundStyle(secondaryInk)
                                        .padding(8)
                                        .background(soft,
                                            in: RoundedRectangle(cornerRadius: 9))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)

                Button {
                    editingWorkout = WorkoutEditDestination(planID: plan.id, dayID: day.id, version: plan.version, workout: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(graphite)
                        .frame(width: 44, height: 44)
                        .background(soft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    tr("Add workout on \(weekday(day.dayIndex, plan: plan))",
                       "Legg til økt på \(weekday(day.dayIndex, plan: plan))")
                )
            }
            .padding(.vertical, 12)
        }
    }

    private var libraryShortcuts: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(tr("EXPLORE & REUSE", "BRUK OG GJENBRUK"))
                    .font(.caption2.weight(.semibold))
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
                .font(.caption2.weight(.semibold))
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

    private func weekday(_ dayIndex: Int, plan: TrainingPlan) -> String {
        let norwegian = ["Man", "Tir", "Ons", "Tor", "Fre", "Lør", "Søn"]
        let english = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let calendarWeekday = Calendar.current.component(
            .weekday, from: planDayDate(dayIndex, plan: plan)
        )
        let mondayBasedIndex = (calendarWeekday + 5) % 7
        return tr(english[mondayBasedIndex], norwegian[mondayBasedIndex])
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
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.035), radius: 9, y: 4)
    }
}