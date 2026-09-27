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

struct AIProgramBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    let mode: AIProgramGenerationMode

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
    @State private var sessionDurationMinutes = 60
    @State private var availableDays: Set<Int> = Set(1...7)
    @State private var userNotes = ""
    @State private var showingQuestions = true
    @State private var experience = ""
    @State private var trainingFocus: TrainingFocus = .generalFitness
    @State private var gymAccess = ""
    @State private var homeEquipment: Set<String> = []
    @State private var otherEquipment = ""
    @State private var limitations = ""
    @State private var currentSessionsPerWeek = 0
    @State private var useProfileInterests = true

    private let equipmentOptions = [
        "Dumbbells", "Kettlebells", "Resistance bands", "Barbell & plates",
        "Bench", "Squat rack", "Pull-up bar", "Treadmill", "Exercise bike"
    ]

    @State private var preview: AIProgramDraft?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var didLoadDefaults = false

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

    private var canGenerate: Bool {
        questionsAnswered &&
        !availableDays.isEmpty &&
        sessionsPerWeek >= 1 &&
        !isGenerating
    }

    var body: some View {
        NavigationStack {
            Form {
                if showingQuestions {
                    coachQuestions
                } else {
                    Section {
                        Label(
                            mode == .generate
                                ? "Build a new program from your goals"
                                : "Fill the gaps in your current program",
                            systemImage: "sparkles"
                        )
                        .font(.headline)

                        Text(
                            mode == .generate
                                ? "ATHLTH Coach uses your confirmed training profile, selected goals and answers. Review the draft before adding it to your calendar."
                                : "ATHLTH Coach suggests sessions for empty days only. Existing sessions remain untouched."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Section("Your training profile") {
                        LabeledContent("Experience", value: experience)
                        LabeledContent("Focus", value: trainingFocus.title)
                        LabeledContent("Gym access", value: gymAccess)
                        Button("Edit coach answers") { showingQuestions = true }
                        Text("Your answers, selected goals and optional interests are sent to ATHLTH Coach. Apple Health records are not included.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    goalsSection
                    timelineSection
                    availabilitySection

                    Section("Preferences") {
                        Stepper(
                            "\(sessionsPerWeek) sessions per week",
                            value: $sessionsPerWeek,
                            in: 1...max(availableDays.count, 1)
                        )
                        .onChange(of: sessionsPerWeek) { _, _ in preview = nil }

                        Stepper(
                            "About \(sessionDurationMinutes) min per session",
                            value: $sessionDurationMinutes,
                            in: 20...180,
                            step: 5
                        )
                        .onChange(of: sessionDurationMinutes) { _, _ in preview = nil }

                        TextField(
                            "Any other preferences? Preferred split, race details…",
                            text: $userNotes,
                            axis: .vertical
                        )
                        .lineLimit(3...7)
                        .onChange(of: userNotes) { _, _ in preview = nil }
                    }

                    if let preview {
                        previewSection(preview)
                    } else {
                        Section {
                            Button {
                                Task { await generatePreview() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isGenerating {
                                        ProgressView()
                                            .padding(.trailing, 6)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(
                                        isGenerating
                                            ? "Building Program…"
                                            : mode.actionTitle
                                    )
                                    Spacer()
                                }
                            }
                            .disabled(!canGenerate)
                        } footer: {
                            if availableDays.isEmpty {
                                Text("Choose at least one available training day.")
                            } else {
                                Text(
                                    "AI suggestions are a starting point. Review volume, exercise choice and intensity before using the program."
                                )
                            }
                        }
                    }
                }
            }
            .disabled(isGenerating)
            .onChange(of: coachContext) { _, _ in preview = nil }
            .navigationTitle(
                showingQuestions ? "Meet your coach" : "ATHLTH Coach"
            )
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
    }

    private var questionsAnswered: Bool {
        !experience.isEmpty && !gymAccess.isEmpty
    }

    private var coachContext: String {
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
        Limitations or movements to avoid: \(limitations.isEmpty ? "None reported" : String(limitations.prefix(500))).
        Profile interests: \(interests).
        Only prescribe equipment the user can access. With no gym or listed home equipment, use bodyweight or outdoor sessions.
        Scale volume to experience and current training; do not treat an experienced athlete as a beginner or overload a beginner.
        """
    }

    @ViewBuilder
    private var coachQuestions: some View {
        Section {
            Label("A plan that fits your life", systemImage: "sparkles")
                .font(.headline)
            Text("Confirm a few details. Your training focus is filled from your profile, and your goals are available on the next screen.")
                .font(.subheadline).foregroundStyle(.secondary)
        }

        Section("1. How experienced are you?") {
            Picker("Training experience", selection: $experience) {
                Text("Choose your level").tag("")
                Text("Beginner").tag("Beginner")
                Text("Intermediate").tag("Intermediate")
                Text("Experienced / train regularly").tag("Experienced")
            }
            Stepper("Currently \(currentSessionsPerWeek) sessions per week", value: $currentSessionsPerWeek, in: 0...14)
        }

        Section("2. What do you want to train?") {
            Picker("Training focus", selection: $trainingFocus) {
                ForEach(TrainingFocus.allCases) { focus in
                    Text(focus.title).tag(focus)
                }
            }
            Text(trainingFocus.subtitle).font(.caption).foregroundStyle(.secondary)
            if let interests = session.onboardingProfile?.interests, !interests.isEmpty {
                Toggle("Use my profile interests", isOn: $useProfileInterests)
                if useProfileInterests {
                    Text(interests.map(\.title).sorted().joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        Section("3. Where can you train?") {
            Picker("Gym access", selection: $gymAccess) {
                Text("Choose an option").tag("")
                Text("Yes — I can use a gym").tag("Yes")
                Text("No — home or outdoors").tag("No")
            }
            Text("Equipment available at home")
                .font(.subheadline.weight(.semibold))
            ForEach(equipmentOptions, id: \.self) { equipment in
                Toggle(equipment, isOn: Binding(
                    get: { homeEquipment.contains(equipment) },
                    set: { enabled in
                        if enabled { homeEquipment.insert(equipment) }
                        else { homeEquipment.remove(equipment) }
                    }
                ))
            }
            TextField("Other equipment (optional)", text: $otherEquipment, axis: .vertical)
            Text("Leave all equipment off for bodyweight training at home.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("4. Anything we should adapt?") {
            TextField("Injuries, limitations or movements to avoid (optional)", text: $limitations, axis: .vertical)
                .lineLimit(2...5)
            Text("Only include details you want the coach to use when planning your workouts.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Button {
                showingQuestions = false
            } label: {
                Label("Continue to goals & schedule", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!questionsAnswered)
        } footer: {
            if !questionsAnswered {
                Text("Choose your experience level and gym access to continue.")
            }
        }
    }

    private var goalsSection: some View {
        Section("Goals") {
            if goalStore.activeGoals.isEmpty {
                Text("No active goals yet. Coach will build a routine around your training focus. You can add a specific goal from your profile later.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(goalStore.activeGoals) { goal in
                    Toggle(
                        isOn: Binding(
                            get: { selectedGoalIDs.contains(goal.id) },
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
                            HStack(spacing: 6) {
                                Text(goal.title)
                                    .font(.subheadline.weight(.semibold))

                                if goal.isPrimary {
                                    Text("PRIMARY")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(ATHLTHTheme.accent)
                                }
                            }

                            HStack(spacing: 6) {
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
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var timelineSection: some View {
        Section("Timeline") {
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
                "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(resolvedEndDate.formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var availabilitySection: some View {
        Section("Available training days") {
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

    @ViewBuilder
    private func previewSection(_ draft: AIProgramDraft) -> some View {
        Section("Preview") {
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

            ForEach(
                Array(draft.weeks.prefix(4)),
                id: \.weekNumber
            ) { week in
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        week.title.isEmpty
                            ? "Week \(week.weekNumber)"
                            : week.title
                    )
                    .font(.subheadline.weight(.semibold))

                    let sessions = week.days.flatMap(\.sessions)
                    Text(
                        sessions.isEmpty
                            ? "Recovery / no sessions"
                            : sessions.map(\.title).joined(separator: " · ")
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                }
                .padding(.vertical, 3)
            }

            if draft.weeks.count > 4 {
                Text("+ \(draft.weeks.count - 4) more weeks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                applyPreview(draft)
            } label: {
                Label(
                    mode == .generate
                        ? "Use Program"
                        : "Fill Empty Days",
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
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @MainActor
    private func generatePreview() async {
        guard canGenerate else { return }

        isGenerating = true
        defer { isGenerating = false }

        let request = AIProgramRequest(
            mode: mode.rawValue,
            startDate: ISO8601DateFormatter().string(from: startDate),
            weekCount: resolvedWeeks,
            sessionsPerWeek: sessionsPerWeek,
            preferredDays: availableDays.sorted(),
            sessionDurationMinutes: sessionDurationMinutes,
            userNotes: coachContext + "\nAdditional preferences: " + String(userNotes.prefix(700)),
            goals: selectedGoals.isEmpty
                ? [AIProgramGoalInput(focus: trainingFocus)]
                : selectedGoals.map(AIProgramGoalInput.init),
            existingDays: existingDays
        )

        do {
            preview = try await service.generate(request)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var existingDays: [AIProgramExistingDay] {
        guard mode == .complete,
              let plan = session.activePlan
        else {
            return []
        }

        return plan.weeks.flatMap { week in
            week.days.map { day in
                AIProgramExistingDay(
                    weekNumber: week.weekNumber,
                    dayIndex: day.dayIndex,
                    dayTitle: day.title,
                    existingSessions: day.sessions.map(\.title)
                )
            }
        }
    }

    @MainActor
    private func applyPreview(_ draft: AIProgramDraft) {
        let generated = draft.makeTrainingPlan(
            ownerID: session.profile.userID,
            startDate: startDate
        )

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
            session.fillEmptyDaysFromGeneratedProgram(generated)

            if let planID = session.activePlan?.id {
                goalStore.setLinkedPlan(
                    planID,
                    goalIDs: selectedGoalIDs
                )
            }
        }

        dismiss()
    }

    @MainActor
    private func loadDefaultsIfNeeded() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        trainingFocus = session.onboardingProfile?.trainingFocus ?? .generalFitness

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

        if selectedGoalIDs.isEmpty,
           let primary = goalStore.primaryGoal {
            selectedGoalIDs = [primary.id]
        }

        if selectedGoalIDs.isEmpty,
           let first = goalStore.activeGoals.first {
            selectedGoalIDs = [first.id]
        }
    }
}
