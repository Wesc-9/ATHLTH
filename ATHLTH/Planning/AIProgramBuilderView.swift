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
    @State private var coachFocusNotes = ""
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
    @State private var completingPlanID: UUID?
    @State private var completingPlanVersion: Int?

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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    coachHero

                    if showingQuestions {
                        coachQuestions
                    } else {
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
            .onChange(of: coachContext) { _, _ in preview = nil }
            .onChange(of: intakePreferences) { _, value in
                guard didLoadDefaults, session.signedIn else { return }
                AccountLocalStorage.write(
                    value,
                    name: "coach",
                    userID: session.profile.userID
                )
            }
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
                Stepper(
                    "\(sessionsPerWeek) sessions per week",
                    value: $sessionsPerWeek,
                    in: 1...max(availableDays.count, 1)
                )
                .onChange(of: sessionsPerWeek) { _, _ in
                    preview = nil
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
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.84),
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
            .stroke(Color.white.opacity(0.88), lineWidth: 0.8)
        }
        .shadow(
            color: Color.black.opacity(0.045),
            radius: 12,
            y: 5
        )
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
                "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(resolvedEndDate.formatted(date: .abbreviated, time: .omitted))"
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
            coachSectionHeading(eyebrow: "YOUR PLAN", title: "Coach draft")
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
    }

    @MainActor
    private func generatePreview() async {
        guard canGenerate else { return }

        isGenerating = true
        defer { isGenerating = false }

        let requestOwnerID = session.profile.userID
        let request = AIProgramRequest(
            mode: mode.rawValue,
            startDate: ISO8601DateFormatter().string(from: startDate),
            weekCount: resolvedWeeks,
            sessionsPerWeek: sessionsPerWeek,
            preferredDays: availableDays.sorted(),
            sessionDurationMinutes: sessionDurationMinutes,
            userNotes: historyContext + String(coachContext.prefix(1900)) + "\nAdditional preferences: " + String(userNotes.prefix(500)),
            goals: selectedGoals.isEmpty
                ? [AIProgramGoalInput(focus: trainingFocus)]
                : selectedGoals.map(AIProgramGoalInput.init),
            existingDays: existingDays
        )

        do {
            let result = try await service.generate(request)
            guard session.signedIn, session.profile.userID == requestOwnerID else { return }
            preview = result
            errorMessage = nil
        } catch {
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

        dismiss()
    }

    @MainActor
    private func loadDefaultsIfNeeded() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        trainingFocus = session.onboardingProfile?.trainingFocus ?? .generalFitness
        if let saved = AccountLocalStorage.read(CoachIntakePreferences.self, name: "coach", userID: session.profile.userID) {
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
