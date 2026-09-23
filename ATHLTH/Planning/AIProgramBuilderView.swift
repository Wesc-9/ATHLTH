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
        !selectedGoalIDs.isEmpty &&
        !availableDays.isEmpty &&
        sessionsPerWeek >= 1 &&
        !isGenerating
    }

    var body: some View {
        NavigationStack {
            Form {
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
                            ? "ATHLTH AI uses only the goals and training constraints you select here. You review the program before it replaces anything."
                            : "ATHLTH AI suggests sessions for empty days only. Existing sessions remain untouched."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                goalsSection
                timelineSection
                availabilitySection

                Section("Preferences") {
                    Stepper(
                        "\(sessionsPerWeek) sessions per week",
                        value: $sessionsPerWeek,
                        in: 1...7
                    )

                    Stepper(
                        "About \(sessionDurationMinutes) min per session",
                        value: $sessionDurationMinutes,
                        in: 20...180,
                        step: 5
                    )

                    TextField(
                        "Anything AI should consider? Equipment, experience, preferred split, race details…",
                        text: $userNotes,
                        axis: .vertical
                    )
                    .lineLimit(3...7)
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
                        if selectedGoalIDs.isEmpty {
                            Text("Select at least one goal.")
                        } else if availableDays.isEmpty {
                            Text("Choose at least one available training day.")
                        } else {
                            Text(
                                "AI suggestions are a starting point. Review volume, exercise choice and intensity before using the program."
                            )
                        }
                    }
                }
            }
            .navigationTitle(
                mode == .generate ? "AI Program" : "AI Complete"
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

    private var goalsSection: some View {
        Section("Goals") {
            if goalStore.activeGoals.isEmpty {
                Text("Create a goal in Progress first.")
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
        guard !selectedGoals.isEmpty else {
            errorMessage = AIProgramError.noGoals.localizedDescription
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        let request = AIProgramRequest(
            mode: mode.rawValue,
            startDate: ISO8601DateFormatter().string(from: startDate),
            weekCount: resolvedWeeks,
            sessionsPerWeek: sessionsPerWeek,
            preferredDays: availableDays.sorted(),
            sessionDurationMinutes: sessionDurationMinutes,
            userNotes: userNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            goals: selectedGoals.map(AIProgramGoalInput.init),
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
            session.replaceActivePlan(with: generated)
        case .complete:
            session.fillEmptyDaysFromGeneratedProgram(generated)
        }

        if let planID = session.activePlan?.id {
            goalStore.setLinkedPlan(
                planID,
                goalIDs: selectedGoalIDs
            )
        }

        dismiss()
    }

    @MainActor
    private func loadDefaultsIfNeeded() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true

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
